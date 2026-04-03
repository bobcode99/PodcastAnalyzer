//
//  WidgetPlaybackData.swift
//  PodcastAnalyzer
//
//  Shared data model for passing playback state between main app and widget
//  Uses App Group UserDefaults for cross-process communication
//

import Foundation
import Nuke

#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Widget Playback Data

/// Data structure representing current playback state for the widget
nonisolated struct WidgetPlaybackData: Codable, Sendable {
  let episodeTitle: String
  let podcastTitle: String
  let imageURL: String?
  let audioURL: String?
  let currentTime: TimeInterval
  let duration: TimeInterval
  let isPlaying: Bool
  let lastUpdated: Date

  /// Progress as a value from 0.0 to 1.0
  var progress: Double {
    guard duration > 0 else { return 0 }
    return min(currentTime / duration, 1.0)
  }

  /// Deep link URL to open the expanded player in the app
  var deepLinkURL: URL? {
    URL(string: "podcastanalyzer://expandplayer")
  }

  /// Deep link URL to navigate directly to the episode detail screen.
  /// Returns nil when audioURL is missing (e.g. placeholder data) so the
  /// widget falls back to .widgetURL on the parent view.
  var episodeDetailURL: URL? {
    guard let audioURL, !audioURL.isEmpty else { return nil }
    var components = URLComponents()
    components.scheme = "podcastanalyzer"
    components.host = "episodedetail"
    components.queryItems = [
      URLQueryItem(name: "title", value: episodeTitle),
      URLQueryItem(name: "podcast", value: podcastTitle),
      URLQueryItem(name: "audio", value: audioURL),
      URLQueryItem(name: "image", value: imageURL),
    ]
    return components.url
  }

  /// Formatted current time string
  var formattedCurrentTime: String {
    formatTime(currentTime)
  }

  /// Formatted duration string
  var formattedDuration: String {
    formatTime(duration)
  }

  /// Formatted remaining time string
  var formattedRemainingTime: String {
    let remaining = max(0, duration - currentTime)
    return "-" + formatTime(remaining)
  }

  private func formatTime(_ time: TimeInterval) -> String {
    let totalSeconds = Int(time)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }
}

// MARK: - Widget Data Manager

/// Manages reading/writing widget data via App Group UserDefaults
nonisolated enum WidgetDataManager {
  /// App Group identifier - must match the App Group configured in Xcode
  static let appGroupIdentifier = "group.com.jn.PodcastAnalyzer"

  /// Key for storing playback data in UserDefaults
  private static let playbackDataKey = "widgetPlaybackData"

  /// Shared UserDefaults for App Group
  static var sharedDefaults: UserDefaults? {
    UserDefaults(suiteName: appGroupIdentifier)
  }

  /// Write playback data to shared UserDefaults (called from main app)
  static func writePlaybackData(_ data: WidgetPlaybackData) {
    guard let defaults = sharedDefaults else { return }

    do {
      let encoded = try JSONEncoder().encode(data)
      defaults.set(encoded, forKey: playbackDataKey)
      // Force flush to disk so the widget extension (separate process) reads fresh data
      defaults.synchronize()
    } catch {
      // Silently fail - widget will show placeholder
    }
  }

  /// Read playback data from shared UserDefaults (called from widget)
  static func readPlaybackData() -> WidgetPlaybackData? {
    guard let defaults = sharedDefaults,
          let data = defaults.data(forKey: playbackDataKey) else {
      return nil
    }

    do {
      return try JSONDecoder().decode(WidgetPlaybackData.self, from: data)
    } catch {
      return nil
    }
  }

  /// Clear playback data (called when playback stops)
  static func clearPlaybackData() {
    sharedDefaults?.removeObject(forKey: playbackDataKey)
  }

  /// Check if playback data is stale (more than 24 hours old)
  static func isDataStale(_ data: WidgetPlaybackData) -> Bool {
    Date().timeIntervalSince(data.lastUpdated) > 86400
  }

  // MARK: - Artwork Image File (shared container)

  /// URL for the shared App Group container directory
  private static var sharedContainerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
  }

  /// File URL for the cached widget artwork image
  static var artworkFileURL: URL? {
    sharedContainerURL?.appending(path: "widget_artwork.jpg")
  }

  /// Write artwork image data to the shared container (called from main app)
  static func writeArtworkData(_ data: Data) {
    guard let fileURL = artworkFileURL else { return }
    try? data.write(to: fileURL, options: .atomic)
  }

  /// Read artwork image data from the shared container (called from widget)
  static func readArtworkData() -> Data? {
    guard let fileURL = artworkFileURL else { return nil }
    return try? Data(contentsOf: fileURL)
  }

  /// Clear the cached artwork file
  static func clearArtwork() {
    guard let fileURL = artworkFileURL else { return }
    try? FileManager.default.removeItem(at: fileURL)
  }

  /// Download and cache artwork image from URL using Nuke.
  /// Skips download if the same URL was already cached.
  /// Called from @MainActor context (EnhancedAudioManager).
  @MainActor private static var lastCachedArtworkURL: String?

  @MainActor static func cacheArtworkIfNeeded(from imageURLString: String?) {
    guard let imageURLString, imageURLString != lastCachedArtworkURL,
          let imageURL = URL(string: imageURLString) else {
      return
    }
    lastCachedArtworkURL = imageURLString
    Task.detached(priority: .utility) {
      do {
        let image = try await ImagePipeline.shared.image(for: imageURL)
        #if os(iOS)
        if let jpegData = image.jpegData(compressionQuality: 0.8) {
          writeArtworkData(jpegData)
        }
        #else
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
          writeArtworkData(jpegData)
        }
        #endif
      } catch {
        // Image download failed — widget will show placeholder
      }
    }
  }
}
