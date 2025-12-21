import Foundation
import SwiftData

@Model
class PodcastInfoModel {
  @Attribute(.unique)
  var id: UUID

  var podcastInfo: PodcastInfo

  var dateAdded: Date
  var lastUpdated: Date

  init(podcastInfo: PodcastInfo, lastUpdated: Date) {
    self.id = UUID()
    self.podcastInfo = podcastInfo
    self.dateAdded = Date()
    self.lastUpdated = lastUpdated
  }
}
