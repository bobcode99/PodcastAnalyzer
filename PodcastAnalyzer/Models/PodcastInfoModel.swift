import Foundation
import SwiftData

@Model
class PodcastInfoModel {
  var id: UUID = UUID()

  var podcastInfo: PodcastInfo = PodcastInfo()

  var dateAdded: Date = Date()
  var lastUpdated: Date = Date()

  /// Whether the user has subscribed to this podcast.
  /// false = browsed/cached podcast, true = subscribed podcast
  var isSubscribed: Bool = false

  // MARK: - Queryable Properties (Swift 6 Predicate Compatibility)
  // These top-level properties enable #Predicate to work without nested keypaths
  // which don't conform to Sendable in Swift 6 strict concurrency mode

  /// Podcast title for predicate queries (mirrors podcastInfo.title)
  var title: String = ""

  /// RSS URL for predicate queries (mirrors podcastInfo.rssUrl)
  var rssUrl: String = ""

  /// Stores either an ETag token or a Last-Modified date string from the last
  /// successful RSS fetch (AntennaPod dual-field trick). nil = never fetched.
  var httpCacheHeader: String?

  /// Predicted date of the next new episode based on release cadence analysis.
  /// nil = not yet analysed or cadence is irregular.
  var predictedNextReleaseDate: Date?

  /// Human-readable cadence detected by ReleaseScheduleGuesser (e.g. "weekly").
  var detectedCadence: String?

  init(podcastInfo: PodcastInfo, lastUpdated: Date, isSubscribed: Bool = true) {
    self.id = UUID()
    self.podcastInfo = podcastInfo
    self.dateAdded = Date()
    self.lastUpdated = lastUpdated
    self.isSubscribed = isSubscribed
    // Initialize queryable properties
    self.title = podcastInfo.title
    self.rssUrl = podcastInfo.rssUrl
  }
}
