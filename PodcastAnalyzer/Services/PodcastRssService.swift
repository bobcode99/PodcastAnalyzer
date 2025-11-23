//
//  A tiny, async/await wrapper around FeedKit.
//  Import this file anywhere – no other code needed.
//

import FeedKit
import Foundation
internal import XMLKit

public struct PodcastEpisodeInfo: Sendable, Codable {
    public let title: String
    public let description: String?
    public let pubDate: Date?
    public let audioURL: String?
    public let imageURL: String?
}

public struct PodcastInfo: Sendable, Identifiable {
    public let id: String  // This will be the rssUrl
    public let title: String
    public let description: String?
    public let episodes: [PodcastEpisodeInfo]
    public let rssUrl: String
    public let imageURL: String
    
    init(title: String, description: String?, episodes: [PodcastEpisodeInfo], rssUrl: String, imageURL: String) {
        self.id = rssUrl  // Use RSS URL as unique ID
        self.title = title
        self.description = description
        self.episodes = episodes
        self.rssUrl = rssUrl
        self.imageURL = imageURL
    }
}

// MARK: - The service

public enum PodcastServiceError: Error, LocalizedError {
    case invalidURL
    case notRSS
    case parsingFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "The URL is malformed."
        case .notRSS: return "The feed is not an RSS feed."
        case .parsingFailed(let e): return "Parsing failed: \(e.localizedDescription)"
        }
    }
}

public actor PodcastRssService {

    /// Parses the given RSS URL and returns a clean model.
    /// - Parameter urlString: any RSS/Atom/JSON feed URL
    /// - Returns: `PodcastInfo` (only RSS data is kept)
    public func fetchPodcast(from urlString: String) async throws -> PodcastInfo {
        guard let url = URL(string: urlString) else {
            throw PodcastServiceError.invalidURL
        }

        // FeedKit auto-detects the format
        let feed = try await Feed(url: url)

        guard case .rss(let rssFeed) = feed else {
            throw PodcastServiceError.notRSS
        }

        let episodes = (rssFeed.channel?.items ?? []).compactMap { item -> PodcastEpisodeInfo? in
            guard let title = item.title else { return nil }
            return PodcastEpisodeInfo(
                title: title,
                description: item.description,
                pubDate: item.pubDate,
                audioURL: item.enclosure?.attributes?.url,
                imageURL: item.iTunes?.image?.attributes?.href
            )
        }

        return await PodcastInfo(
            title: rssFeed.channel?.title ?? "Untitled Podcast",
            description: rssFeed.channel?.description,
            episodes: episodes,
            rssUrl: urlString,
            imageURL: rssFeed.channel?.iTunes?.image?.attributes?.href ?? ""
        )
    }
}
