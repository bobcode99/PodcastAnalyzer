//
//  PodcastEpisodeInfo.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//

import FeedKit
import Foundation

public struct PodcastEpisodeInfo: Sendable, Identifiable {
  public let title: String
  public let podcastEpisodeDescription: String?
  public let pubDate: Date?
  public let audioURL: String?
  public let imageURL: String?
  public let duration: Int?  // Duration in seconds from itunes:duration
  public let guid: String?  // Episode GUID from RSS feed

  /// Unique identifier for this episode (uses audioURL or title+pubDate combo)
  public var id: String {
    if let audioURL = audioURL {
      return audioURL
    }
    // Fallback: combine title with pubDate for uniqueness
    let dateString = pubDate?.timeIntervalSince1970.description ?? "unknown"
    return "\(title)_\(dateString)"
  }

  /// Formatted duration string (e.g., "1h 5m", "48m", "3m 20s")
  public var formattedDuration: String? {
    guard let duration = duration, duration > 0 else { return nil }

    let hours = duration / 3600
    let minutes = (duration % 3600) / 60
    let seconds = duration % 60

    if hours > 0 {
      return "\(hours)h \(minutes)m"
    } else if minutes > 0 {
      if seconds > 0 && minutes < 10 {
        return "\(minutes)m \(seconds)s"
      }
      return "\(minutes)m"
    } else {
      return "\(seconds)s"
    }
  }
}

// Explicit Codable conformance to avoid MainActor isolation issues with SwiftData
extension PodcastEpisodeInfo: Codable {
  private enum CodingKeys: String, CodingKey {
    case title, podcastEpisodeDescription, pubDate, audioURL, imageURL, duration, guid
  }

  public nonisolated init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.title = try container.decode(String.self, forKey: .title)
    self.podcastEpisodeDescription = try container.decodeIfPresent(String.self, forKey: .podcastEpisodeDescription)
    self.pubDate = try container.decodeIfPresent(Date.self, forKey: .pubDate)
    self.audioURL = try container.decodeIfPresent(String.self, forKey: .audioURL)
    self.imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
    self.duration = try container.decodeIfPresent(Int.self, forKey: .duration)
    self.guid = try container.decodeIfPresent(String.self, forKey: .guid)
  }

  public nonisolated func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(title, forKey: .title)
    try container.encodeIfPresent(podcastEpisodeDescription, forKey: .podcastEpisodeDescription)
    try container.encodeIfPresent(pubDate, forKey: .pubDate)
    try container.encodeIfPresent(audioURL, forKey: .audioURL)
    try container.encodeIfPresent(imageURL, forKey: .imageURL)
    try container.encodeIfPresent(duration, forKey: .duration)
    try container.encodeIfPresent(guid, forKey: .guid)
  }
}
