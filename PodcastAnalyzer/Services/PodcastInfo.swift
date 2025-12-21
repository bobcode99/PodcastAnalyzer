//
//  PodcastInfo.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//

import FeedKit
import Foundation
internal import XMLKit

public struct PodcastInfo: Sendable, Identifiable, Codable {
  public let id: String  // This will be the rssUrl
  public let title: String
  public let podcastInfoDescription: String?
  public let episodes: [PodcastEpisodeInfo]
  public let rssUrl: String
  public let imageURL: String
  public let language: String

  init(
    title: String, description: String?, episodes: [PodcastEpisodeInfo], rssUrl: String,
    imageURL: String, language: String
  ) {
    self.id = rssUrl  // Use RSS URL as unique ID
    self.title = title
    self.podcastInfoDescription = description
    self.episodes = episodes
    self.rssUrl = rssUrl
    self.imageURL = imageURL
    self.language = language
  }
}
