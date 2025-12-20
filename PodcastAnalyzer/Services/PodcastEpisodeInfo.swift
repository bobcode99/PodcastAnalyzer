//
//  PodcastEpisodeInfo.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//


import FeedKit
import Foundation
internal import XMLKit

public struct PodcastEpisodeInfo: Sendable, Codable {
    public let title: String
    public let podcastEpisodeDescription: String?
    public let pubDate: Date?
    public let audioURL: String?
    public let imageURL: String?
    public let duration: Int? // Duration in seconds from itunes:duration

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