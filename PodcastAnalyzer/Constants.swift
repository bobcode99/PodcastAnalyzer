import Foundation

struct Constants {
  static let apiBaseURL = "https://api.podcastanalyzer.com"
  static let defaultTimeoutInterval: TimeInterval = 30.0
  static let maxConcurrentDownloads = 4
  static let supportedAudioFormats = ["mp3", "aac", "wav", "flac"]
  static let userAgent = "PodcastAnalyzer/1.0 (iOS)"

  static let homeString = "Home"
  static let settingsString = "Settings"
  static let searchString = "Search"

  static let homeIconName = "house.fill"
  static let settingsIconName = "gearshape.fill"
  static let searchIconName = "magnifyingglass.circle.fill"
}
