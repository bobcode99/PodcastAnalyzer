//
//  CachedAsyncImage.swift
//  PodcastAnalyzer
//
//  A cached version of AsyncImage that stores images in memory and disk
//

import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Platform Image Type Alias

#if os(iOS)
typealias CachedPlatformImage = UIImage
#else
typealias CachedPlatformImage = NSImage
#endif

// MARK: - Download Coordinator (Actor for thread-safe async coordination)

/// Actor that coordinates in-flight downloads to prevent duplicate requests
private actor DownloadCoordinator {
  private var inFlightDownloads: [String: Task<CachedPlatformImage?, Never>] = [:]

  func getExistingTask(for key: String) -> Task<CachedPlatformImage?, Never>? {
    inFlightDownloads[key]
  }

  func registerTask(_ task: Task<CachedPlatformImage?, Never>, for key: String) {
    inFlightDownloads[key] = task
  }

  func removeTask(for key: String) {
    inFlightDownloads.removeValue(forKey: key)
  }
}

// MARK: - Image Cache Manager

final class ImageCacheManager: @unchecked Sendable {
  static let shared = ImageCacheManager()

  private let memoryCache = NSCache<NSString, CachedPlatformImage>()
  private let fileManager = FileManager.default
  private let cacheDirectory: URL

  // Actor for coordinating downloads (replaces NSLock for async contexts)
  private let downloadCoordinator = DownloadCoordinator()

  // Serial queue for synchronous memory cache access (safer than NSLock)
  private let memoryCacheQueue = DispatchQueue(label: "com.podcastanalyzer.imagecache.memory")

  private init() {
    // Set up memory cache limits
    memoryCache.countLimit = 100  // Max 100 images
    memoryCache.totalCostLimit = 50 * 1024 * 1024  // 50 MB

    // Set up disk cache directory
    let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    cacheDirectory = cachesDir.appendingPathComponent("ImageCache", isDirectory: true)

    // Create cache directory if needed
    try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
  }

  // MARK: - Cache Key Generation

  private func cacheKey(for url: URL) -> String {
    // Use a stable hash - SHA256-like approach using Data
    let urlString = url.absoluteString
    var hash: UInt64 = 5381
    for char in urlString.utf8 {
      hash = ((hash << 5) &+ hash) &+ UInt64(char)
    }
    return String(format: "%016llx", hash)
  }

  // MARK: - Synchronous Memory Cache (for immediate UI response)

  /// Synchronous cache lookup - safe to call from any context
  func getCachedSync(for url: URL) -> CachedPlatformImage? {
    let key = cacheKey(for: url) as NSString
    // NSCache is thread-safe, but we use queue for consistency
    return memoryCacheQueue.sync {
      memoryCache.object(forKey: key)
    }
  }

  private func cacheInMemory(_ image: CachedPlatformImage, for url: URL) {
    let key = cacheKey(for: url) as NSString
    let cost = Int(image.size.width * image.size.height * 4)  // Approximate byte size
    memoryCacheQueue.sync {
      memoryCache.setObject(image, forKey: key, cost: cost)
    }
  }

  // MARK: - Disk Cache

  private func diskCachePath(for url: URL) -> URL {
    let key = cacheKey(for: url)
    return cacheDirectory.appendingPathComponent(key)
  }

  private func getDiskCached(for url: URL) -> CachedPlatformImage? {
    let path = diskCachePath(for: url)
    guard let data = try? Data(contentsOf: path),
          let image = CachedPlatformImage(data: data) else {
      return nil
    }
    // Also cache in memory for faster access next time
    cacheInMemory(image, for: url)
    return image
  }

  private func cacheToDisk(_ image: CachedPlatformImage, for url: URL) {
    let path = diskCachePath(for: url)
    #if os(iOS)
    if let data = image.jpegData(compressionQuality: 0.8) {
      try? data.write(to: path)
    }
    #else
    if let tiffData = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
      try? data.write(to: path)
    }
    #endif
  }

  // MARK: - Download and Cache (with deduplication via actor)

  func downloadAndCache(from url: URL) async -> CachedPlatformImage? {
    let key = cacheKey(for: url)

    // Check memory cache first (synchronous)
    if let cached = getCachedSync(for: url) {
      return cached
    }

    // Check disk cache (synchronous but I/O bound)
    if let diskCached = getDiskCached(for: url) {
      return diskCached
    }

    // Check if already downloading (actor-isolated, safe across await)
    if let existingTask = await downloadCoordinator.getExistingTask(for: key) {
      return await existingTask.value
    }

    // Create download task
    let task = Task<CachedPlatformImage?, Never> { [weak self] in
      guard let self else { return nil }

      do {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = CachedPlatformImage(data: data) else { return nil }

        // Cache in memory and disk
        self.cacheInMemory(image, for: url)
        self.cacheToDisk(image, for: url)

        return image
      } catch {
        return nil
      }
    }

    // Register task with coordinator
    await downloadCoordinator.registerTask(task, for: key)

    let result = await task.value

    // Remove from coordinator
    await downloadCoordinator.removeTask(for: key)

    return result
  }

  // MARK: - Cache Cleanup

  func clearMemoryCache() {
    memoryCacheQueue.sync {
      memoryCache.removeAllObjects()
    }
  }

  func clearDiskCache() {
    try? fileManager.removeItem(at: cacheDirectory)
    try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
  }

  func clearAllCache() {
    clearMemoryCache()
    clearDiskCache()
  }
}

// MARK: - Cached Async Image View

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
  let url: URL?
  let scale: CGFloat
  @ViewBuilder let content: (Image) -> Content
  @ViewBuilder let placeholder: () -> Placeholder

  @State private var image: CachedPlatformImage?
  @State private var loadTask: Task<Void, Never>?

  init(
    url: URL?,
    scale: CGFloat = 1,
    @ViewBuilder content: @escaping (Image) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.url = url
    self.scale = scale
    self.content = content
    self.placeholder = placeholder
  }

  var body: some View {
    Group {
      if let image = image {
        #if os(iOS)
        content(Image(uiImage: image))
        #else
        content(Image(nsImage: image))
        #endif
      } else {
        placeholder()
      }
    }
    .onAppear {
      loadImageIfNeeded()
    }
    .onChange(of: url) { _, newURL in
      // URL changed, reset and reload
      image = nil
      loadTask?.cancel()
      loadImageIfNeeded()
    }
    .onDisappear {
      // Cancel any pending load when view disappears
      loadTask?.cancel()
      loadTask = nil
    }
  }

  private func loadImageIfNeeded() {
    guard let url = url else { return }

    // IMPORTANT: Check memory cache synchronously first!
    // This prevents creating Tasks for already-cached images
    if let cached = ImageCacheManager.shared.getCachedSync(for: url) {
      self.image = cached
      return
    }

    // Only create async task if not in memory cache
    loadTask?.cancel()
    loadTask = Task {
      if let cachedImage = await ImageCacheManager.shared.downloadAndCache(from: url) {
        if !Task.isCancelled {
          await MainActor.run {
            self.image = cachedImage
          }
        }
      }
    }
  }
}

// MARK: - Convenience Initializers

extension CachedAsyncImage where Placeholder == ProgressView<EmptyView, EmptyView> {
  init(
    url: URL?,
    scale: CGFloat = 1,
    @ViewBuilder content: @escaping (Image) -> Content
  ) {
    self.init(url: url, scale: scale, content: content, placeholder: { ProgressView() })
  }
}

extension CachedAsyncImage where Content == Image, Placeholder == ProgressView<EmptyView, EmptyView> {
  init(url: URL?, scale: CGFloat = 1) {
    self.init(url: url, scale: scale, content: { $0 }, placeholder: { ProgressView() })
  }
}

// MARK: - Cached Artwork Image (Specialized for Podcasts)

struct CachedArtworkImage: View {
  let urlString: String?
  let size: CGFloat
  let cornerRadius: CGFloat

  init(urlString: String?, size: CGFloat = 60, cornerRadius: CGFloat = 8) {
    self.urlString = urlString
    self.size = size
    self.cornerRadius = cornerRadius
  }

  private var url: URL? {
    guard let urlString = urlString else { return nil }
    return URL(string: urlString)
  }

  var body: some View {
    CachedAsyncImage(url: url) { image in
      image
        .resizable()
        .aspectRatio(contentMode: .fill)
    } placeholder: {
      Color.gray.opacity(0.2)
        .overlay(
          ProgressView()
            .scaleEffect(0.5)
        )
    }
    .frame(width: size, height: size)
    .cornerRadius(cornerRadius)
    .clipped()
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: 20) {
    CachedArtworkImage(
      urlString: "https://example.com/image.jpg",
      size: 100,
      cornerRadius: 12
    )

    CachedAsyncImage(url: URL(string: "https://example.com/test.jpg")) { image in
      image
        .resizable()
        .scaledToFit()
    } placeholder: {
      Color.gray
    }
    .frame(width: 200, height: 200)
  }
}
