import Foundation
import SwiftData

@Model
class PodcastInfoModel {
    var id: String
    var rssUrl: String
    var title: String?
    var imageUrl: String?
    var podcastDescription: String?
    var dateAdded: Date
    var lastUpdated: Date?
    
    init(rssUrl: String, title: String? = nil, imageUrl: String? = nil, podcastDescription: String? = nil) {
        self.id = UUID().uuidString
        self.rssUrl = rssUrl
        self.title = title
        self.imageUrl = imageUrl
        self.podcastDescription = podcastDescription
        self.dateAdded = Date()
        self.lastUpdated = nil
    }
}
