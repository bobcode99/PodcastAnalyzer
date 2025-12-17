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
}