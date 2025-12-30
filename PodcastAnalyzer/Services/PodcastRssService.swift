//
//  A tiny, async/await wrapper around FeedKit.
//  Import this file anywhere – no other code needed.
//

import FeedKit
import Foundation
internal import XMLKit
import os.log

public actor PodcastRssService {
    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "PodcastRssService")

  /// Parses duration from iTunes duration field (FeedKit returns TimeInterval)
  private func parseDuration(_ duration: TimeInterval) -> Int {
    // FeedKit returns duration as TimeInterval (Double) in seconds
    return Int(duration)
  }

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

      // Parse duration - can be in seconds (Int) or time format (HH:MM:SS or MM:SS)
      var durationSeconds: Int? = nil
      if let duration = item.iTunes?.duration {
        durationSeconds = parseDuration(duration)
      }


      return PodcastEpisodeInfo(
        title: title,
        podcastEpisodeDescription: item.description,
        pubDate: item.pubDate,
        audioURL: item.enclosure?.attributes?.url,
        imageURL: item.iTunes?.image?.attributes?.href,
        duration: durationSeconds,
        guid: item.guid?.text
      )
    }

    return await PodcastInfo(
      title: rssFeed.channel?.title ?? "Untitled Podcast",
      description: rssFeed.channel?.description,
      episodes: episodes,
      rssUrl: urlString,
      imageURL: rssFeed.channel?.iTunes?.image?.attributes?.href ?? "",
      language: rssFeed.channel?.language ?? "en-us"
    )
  }
}
