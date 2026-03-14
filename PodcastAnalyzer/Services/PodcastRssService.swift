//
//  PodcastRssService.swift
//  PodcastAnalyzer
//
//  Async/await wrapper around FeedKit with podcast namespace support.
//

import FeedKit
import Foundation
import OSLog
internal import XMLKit


public actor PodcastRssService {
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "PodcastRssService")

  #if DEBUG
  private static let signpostLog = OSLog(subsystem: "com.podcast.analyzer", category: "PointsOfInterest")
  #endif

  // MARK: - Supported Transcript Types

  /// Supported transcript MIME types in order of preference
  /// Reference: https://github.com/Podcastindex-org/podcast-namespace/blob/main/docs/tags/transcript.md
  private enum TranscriptType: String, CaseIterable {
    case vtt = "text/vtt"
    case srt = "application/x-subrip"
    case srtAlt = "application/srt"

    /// Check if a MIME type matches this transcript type
    func matches(_ mimeType: String) -> Bool {
      let normalized = mimeType.lowercased().trimmingCharacters(in: .whitespaces)
      return normalized == rawValue || normalized.contains(rawValue.split(separator: "/").last ?? "")
    }

    /// Priority for selection (lower is better)
    var priority: Int {
      switch self {
      case .vtt: return 0      // Prefer VTT (most widely supported)
      case .srt: return 1      // SRT is also good
      case .srtAlt: return 1   // Same as SRT
      }
    }
  }

  /// Selected transcript info
  private struct SelectedTranscript {
    let url: String
    let type: String
    let language: String?
  }

  // MARK: - Public Methods

  /// Parses duration from iTunes duration field (FeedKit returns TimeInterval)
  private func parseDuration(_ duration: TimeInterval) -> Int {
    Int(duration)
  }

  /// Parses the given RSS URL and returns a clean model.
  /// - Parameter urlString: any RSS/Atom/JSON feed URL
  /// - Returns: `PodcastInfo` (only RSS data is kept)
  public func fetchPodcast(from urlString: String) async throws -> PodcastInfo {
    #if DEBUG
    let signpostID = OSSignpostID(log: Self.signpostLog)
    os_signpost(.begin, log: Self.signpostLog, name: "RSSService.fetchPodcast", signpostID: signpostID)
    defer { os_signpost(.end, log: Self.signpostLog, name: "RSSService.fetchPodcast", signpostID: signpostID) }
    #endif

    guard let url = URL(string: urlString) else {
      throw PodcastServiceError.invalidURL
    }

    // Fetch and parse with FeedKit (auto-detects format)
    let (data, _) = try await URLSession.shared.data(from: url)
    let feed = try Feed(data: data)

    guard case .rss(let rssFeed) = feed else {
      throw PodcastServiceError.notRSS
    }

    guard let channel = rssFeed.channel else {
      throw PodcastServiceError.notRSS
    }

    // Create episodes with transcript info from FeedKit's podcast namespace
    let items = channel.items ?? []
    let episodes = items.compactMap { item -> PodcastEpisodeInfo? in
      guard let title = item.title else { return nil }

      // Parse duration
      var durationSeconds: Int? = nil
      if let duration = item.iTunes?.duration {
        durationSeconds = parseDuration(duration)
      }

      // Get best transcript from podcast namespace (FeedKit parses this automatically)
      // item.podcast?.transcripts is [PodcastTranscript]? from FeedKit
      let transcript = selectBestTranscript(from: item.podcast?.transcripts)

      return PodcastEpisodeInfo(
        title: title,
        podcastEpisodeDescription: item.description,
        pubDate: item.pubDate,
        audioURL: item.enclosure?.attributes?.url,
        imageURL: item.iTunes?.image?.attributes?.href,
        duration: durationSeconds,
        guid: item.guid?.text,
        transcriptURL: transcript?.url,
        transcriptType: transcript?.type
      )
    }

    let transcriptCount = episodes.filter { $0.transcriptURL != nil }.count
    logger.info("Parsed \(episodes.count) episodes, \(transcriptCount) with transcripts")

    return PodcastInfo(
      title: channel.title ?? "Untitled Podcast",
      description: channel.description,
      episodes: episodes,
      rssUrl: urlString,
      imageURL: channel.iTunes?.image?.attributes?.href ?? "",
      language: channel.language ?? "en-us"
    )
  }

  // MARK: - Private Helpers

  /// Select the best transcript from available options
  /// Prefers VTT and SRT formats as they have timing information
  /// Reference: https://github.com/Podcastindex-org/podcast-namespace/blob/main/docs/examples/transcripts/transcripts.md
  private func selectBestTranscript(from transcripts: [PodcastTranscript]?) -> SelectedTranscript? {
    guard let transcripts = transcripts, !transcripts.isEmpty else {
      return nil
    }

    // Find supported transcripts with their priority
    var supportedTranscripts: [(transcript: SelectedTranscript, priority: Int)] = []

    for transcript in transcripts {
      guard let type = transcript.attributes?.type,
            let url = transcript.attributes?.url,
            !url.isEmpty else {
        continue
      }

      // Check if this is a supported type
      for transcriptType in TranscriptType.allCases {
        if transcriptType.matches(type) {
          let selected = SelectedTranscript(
            url: url,
            type: type,
            language: transcript.attributes?.language
          )
          supportedTranscripts.append((selected, transcriptType.priority))
          break
        }
      }
    }

    // Sort by priority (lower is better) and return the best one
    let best = supportedTranscripts.min(by: { $0.priority < $1.priority })?.transcript

    if let best = best {
      logger.debug("Selected transcript: type=\(best.type), url=\(best.url)")
    }

    return best
  }
}
