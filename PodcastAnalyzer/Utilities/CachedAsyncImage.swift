//
//  CachedAsyncImage.swift
//  PodcastAnalyzer
//
//  Thin wrappers around Nuke's LazyImage for cached image loading.
//

import SwiftUI
import NukeUI
import Nuke

// MARK: - Pipeline Configuration

/// Call once at app launch to configure Nuke's image pipeline with a persistent data cache.
func configureImagePipeline() {
  let dataCache = try? DataCache(name: "com.podcast.analyzer.images")
  var config = ImagePipeline.Configuration()
  if let dataCache {
    dataCache.sizeLimit = 200 * 1024 * 1024
  }
  if let dataCache {
    config.dataCache = dataCache
  }
  let imageCache = ImageCache()
  #if os(macOS)
  // The default shared cache can grow very large on desktop-class RAM.
  imageCache.costLimit = 80 * 1024 * 1024
  imageCache.countLimit = 200
  #else
  imageCache.costLimit = 120 * 1024 * 1024
  imageCache.countLimit = 300
  #endif
  config.imageCache = imageCache
  ImagePipeline.shared = ImagePipeline(configuration: config)
}

// MARK: - Cached Async Image View

/// Drop-in replacement for the previous custom CachedAsyncImage, backed by Nuke.
nonisolated struct CachedAsyncImage<Content: View, Placeholder: View>: View {
  let url: URL?
  let scale: CGFloat
  @ViewBuilder let content: (Image) -> Content
  @ViewBuilder let placeholder: () -> Placeholder

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
    LazyImage(url: url) { state in
      if let image = state.image {
        content(image)
      } else {
        placeholder()
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

nonisolated struct CachedArtworkImage: View {
  let urlString: String?
  let size: CGFloat
  let cornerRadius: CGFloat

  init(urlString: String?, size: CGFloat = 60, cornerRadius: CGFloat = 8) {
    self.urlString = urlString
    self.size = size
    self.cornerRadius = cornerRadius
  }

  private var url: URL? {
    guard let urlString else { return nil }
    return URL(string: urlString)
  }

  private var request: ImageRequest? {
    guard let url else { return nil }
    var request = ImageRequest(url: url)
    request.processors = [
      ImageProcessors.Resize(
        size: CGSize(width: size, height: size),
        unit: .points,
        contentMode: .aspectFill,
        crop: true,
        upscale: false
      )
    ]
    return request
  }

  var body: some View {
    LazyImage(request: request) { state in
      if let image = state.image {
        image.resizable().aspectRatio(contentMode: .fill)
      } else {
        Color.gray.opacity(0.2)
          .overlay(ProgressView().scaleEffect(0.5))
      }
    }
    .frame(width: size, height: size)
    .clipShape(.rect(cornerRadius: cornerRadius))
    .clipped()
  }
}

// MARK: - Cache Utilities

/// Convenience for clearing and inspecting Nuke's image caches.
nonisolated enum ImageCacheUtility {
  static func clearAllCache() {
    ImagePipeline.shared.cache.removeAll()
  }

  static func clearMemoryCache() {
    ImagePipeline.shared.cache.removeAll()
  }

  /// Returns the total size of the data cache in bytes, or 0 if unavailable.
  static func dataCacheTotalSize() -> Int64 {
    if let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
      return Int64(dataCache.totalSize)
    }
    return 0
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
