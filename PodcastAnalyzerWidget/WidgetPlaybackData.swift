//
//  WidgetPlaybackData.swift
//  PodcastAnalyzerWidget
//
//  Shared data model for passing playback state between main app and widget
//  Uses App Group UserDefaults for cross-process communication
//

import Foundation

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
  /// Returns nil when audioURL is missing so the widget doesn't fire
  /// a navigation URL from placeholder or incomplete data.
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

  /// Read artwork image data from the shared container (called from widget)
  static func readArtworkData() -> Data? {
    guard let fileURL = artworkFileURL else { return nil }
    return try? Data(contentsOf: fileURL)
  }
}
