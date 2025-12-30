import Foundation
import SwiftData

@Model
class PodcastInfoModel {
  @Attribute(.unique)
  var id: UUID

  var podcastInfo: PodcastInfo

  var dateAdded: Date
  var lastUpdated: Date

  /// Whether the user has subscribed to this podcast.
  /// false = browsed/cached podcast, true = subscribed podcast
  var isSubscribed: Bool

  init(podcastInfo: PodcastInfo, lastUpdated: Date, isSubscribed: Bool = true) {
    self.id = UUID()
    self.podcastInfo = podcastInfo
    self.dateAdded = Date()
    self.lastUpdated = lastUpdated
    self.isSubscribed = isSubscribed
  }
}
