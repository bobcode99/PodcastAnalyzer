//
//  CachedAsyncImage.swift
//  PodcastAnalyzer
//
//  A cached version of AsyncImage that stores images in memory and disk
//

import SwiftUI

// MARK: - Image Cache Manager

actor ImageCacheManager {
  static let shared = ImageCacheManager()

  private let memoryCache = NSCache<NSString, UIImage>()
  private let fileManager = FileManager.default
  private let cacheDirectory: URL

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
    // Use URL hash as key to handle special characters
    let hash = url.absoluteString.hashValue
    return String(format: "%llx", hash)
  }

  // MARK: - Memory Cache

  func getCached(for url: URL) -> UIImage? {
    let key = cacheKey(for: url) as NSString
    return memoryCache.object(forKey: key)
  }

  func cacheInMemory(_ image: UIImage, for url: URL) {
    let key = cacheKey(for: url) as NSString
    let cost = Int(image.size.width * image.size.height * 4)  // Approximate byte size
    memoryCache.setObject(image, forKey: key, cost: cost)
  }

  // MARK: - Disk Cache

  private func diskCachePath(for url: URL) -> URL {
    let key = cacheKey(for: url)
    return cacheDirectory.appendingPathComponent(key)
  }

  func getDiskCached(for url: URL) -> UIImage? {
    let path = diskCachePath(for: url)
    guard let data = try? Data(contentsOf: path),
          let image = UIImage(data: data) else {
      return nil
    }
    // Also cache in memory for faster access next time
    cacheInMemory(image, for: url)
    return image
  }

  func cacheToDisk(_ image: UIImage, for url: URL) {
    let path = diskCachePath(for: url)
    if let data = image.jpegData(compressionQuality: 0.8) {
      try? data.write(to: path)
    }
  }

  // MARK: - Download and Cache

  func downloadAndCache(from url: URL) async -> UIImage? {
    // Check memory cache first
    if let cached = getCached(for: url) {
      return cached
    }

    // Check disk cache
    if let diskCached = getDiskCached(for: url) {
      return diskCached
    }

    // Download
    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      guard let image = UIImage(data: data) else { return nil }

      // Cache in memory and disk
      cacheInMemory(image, for: url)
      cacheToDisk(image, for: url)

      return image
    } catch {
      return nil
    }
  }

  // MARK: - Cache Cleanup

  func clearMemoryCache() {
    memoryCache.removeAllObjects()
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

  @State private var image: UIImage?
  @State private var isLoading = false

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
        content(Image(uiImage: image))
      } else {
        placeholder()
          .task(id: url) {
            await loadImage()
          }
      }
    }
  }

  private func loadImage() async {
    guard let url = url, !isLoading else { return }

    isLoading = true
    defer { isLoading = false }

    if let cachedImage = await ImageCacheManager.shared.downloadAndCache(from: url) {
      await MainActor.run {
        self.image = cachedImage
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
