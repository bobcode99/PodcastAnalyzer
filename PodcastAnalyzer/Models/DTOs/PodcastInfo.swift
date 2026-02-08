//
//  PodcastInfo.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//

import Foundation

public struct PodcastInfo: Sendable, Identifiable {
  public let id: String  // This will be the rssUrl
  public let title: String
  public let podcastInfoDescription: String?
  public let episodes: [PodcastEpisodeInfo]
  public let rssUrl: String
  public let imageURL: String
  public let language: String

  nonisolated init(
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

// Explicit Codable conformance to avoid MainActor isolation issues with SwiftData
extension PodcastInfo: Codable {
  private enum CodingKeys: String, CodingKey {
    case id, title, podcastInfoDescription, episodes, rssUrl, imageURL, language
  }

  public nonisolated init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.title = try container.decode(String.self, forKey: .title)
    self.podcastInfoDescription = try container.decodeIfPresent(String.self, forKey: .podcastInfoDescription)
    self.episodes = try container.decode([PodcastEpisodeInfo].self, forKey: .episodes)
    self.rssUrl = try container.decode(String.self, forKey: .rssUrl)
    self.imageURL = try container.decode(String.self, forKey: .imageURL)
    self.language = try container.decode(String.self, forKey: .language)
  }

  public nonisolated func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encodeIfPresent(podcastInfoDescription, forKey: .podcastInfoDescription)
    try container.encode(episodes, forKey: .episodes)
    try container.encode(rssUrl, forKey: .rssUrl)
    try container.encode(imageURL, forKey: .imageURL)
    try container.encode(language, forKey: .language)
  }
}
