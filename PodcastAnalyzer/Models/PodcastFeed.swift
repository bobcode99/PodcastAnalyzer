import Foundation
import SwiftData

@Model
final class PodcastFeed {
    var id: String
    var rssUrl: String
    var title: String?
    var subtitle: String?
    var imageUrl: String?
    var dateAdded: Date
    var lastUpdated: Date?
    
    init(rssUrl: String, title: String? = nil) {
        self.id = UUID().uuidString
        self.rssUrl = rssUrl
        self.title = title
        self.subtitle = nil
        self.imageUrl = nil
        self.dateAdded = Date()
        self.lastUpdated = nil
    }
}
