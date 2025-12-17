//
//  A tiny, async/await wrapper around FeedKit.
//  Import this file anywhere – no other code needed.
//

import FeedKit
import Foundation
internal import XMLKit


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
                podcastEpisodeDescription: item.description,
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
