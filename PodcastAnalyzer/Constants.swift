import Foundation

// MARK: - Notification Names

extension Notification.Name {
  static let podcastRegionChanged = Notification.Name("podcastRegionChanged")
  static let episodeDownloadCompleted = Notification.Name("episodeDownloadCompleted")
}

struct Constants {

  static let homeString = "Home"
  static let libraryString = "Library"
  static let settingsString = "Settings"
  static let searchString = "Search"

  static let homeIconName = "house.fill"
  static let libraryIconName = "books.vertical.fill"
  static let settingsIconName = "gearshape.fill"
  static let searchIconName = "magnifyingglass.circle.fill"

  // Apple RSS Marketing API for top podcasts
  static let appleRSSBaseURL = "https://rss.marketingtools.apple.com/api/v2"

  // Available regions for top podcasts
  static let podcastRegions: [(code: String, name: String)] = [
    ("us", "United States"),
    ("tw", "Taiwan"),
    ("jp", "Japan"),
    ("gb", "United Kingdom"),
    ("au", "Australia"),
    ("ca", "Canada"),
    ("de", "Germany"),
    ("fr", "France"),
    ("kr", "South Korea"),
    ("hk", "Hong Kong")
  ]
}
