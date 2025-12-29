//
//  LibraryViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for Library tab - manages subscribed podcasts, saved, downloaded, and latest episodes
//

import Combine
import Foundation
import SwiftData
import SwiftUI
import os.log

// MARK: - Library Episode Model

struct LibraryEpisode: Identifiable {
  let id: String
  let podcastTitle: String
  let imageURL: String?
  let language: String
  let episodeInfo: PodcastEpisodeInfo
  let isStarred: Bool
  let isDownloaded: Bool
  let isCompleted: Bool
  let lastPlaybackPosition: TimeInterval

  var hasProgress: Bool {
    lastPlaybackPosition > 0 && !isCompleted
  }
}

// MARK: - Library ViewModel

@MainActor
class LibraryViewModel: ObservableObject {
  @Published var podcastInfoModelList: [PodcastInfoModel] = []
  @Published var savedEpisodes: [LibraryEpisode] = []
  @Published var downloadedEpisodes: [LibraryEpisode] = []
  @Published var latestEpisodes: [LibraryEpisode] = []
  @Published var isLoading = false
  @Published var error: String?

  private let service = PodcastRssService()
  private let downloadManager = DownloadManager.shared
  private var modelContext: ModelContext?
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "LibraryViewModel")

  // Use Unit Separator (U+001F) as delimiter
  private static let episodeKeyDelimiter = "\u{1F}"

  init(modelContext: ModelContext?) {
    self.modelContext = modelContext
    if modelContext != nil {
      loadAll()
    }
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    loadAll()
  }

  // MARK: - Load All Data

  private func loadAll() {
    loadPodcastFeeds()
    loadSavedEpisodes()
    loadDownloadedEpisodes()
    loadLatestEpisodes()
  }

  // MARK: - Load Podcasts

  private func loadPodcastFeeds() {
    guard let context = modelContext else {
      logger.warning("ModelContext is nil, cannot load feeds")
      return
    }

    let descriptor = FetchDescriptor<PodcastInfoModel>(
      sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
    )

    do {
      podcastInfoModelList = try context.fetch(descriptor)
      logger.info("Loaded \(self.podcastInfoModelList.count) podcast feeds from database")
    } catch {
      self.error = "Failed to load feeds: \(error.localizedDescription)"
      logger.error("Failed to load feeds: \(error.localizedDescription)")
    }
  }

  // MARK: - Load Saved Episodes

  private func loadSavedEpisodes() {
    guard let context = modelContext else { return }

    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.isStarred == true },
      sortBy: [SortDescriptor(\.downloadedDate, order: .reverse)]
    )

    do {
      let models = try context.fetch(descriptor)
      savedEpisodes = models.compactMap { model in
        findEpisodeInfo(for: model)
      }
      logger.info("Loaded \(self.savedEpisodes.count) saved episodes")
    } catch {
      logger.error("Failed to load saved episodes: \(error.localizedDescription)")
    }
  }

  // MARK: - Load Downloaded Episodes

  private func loadDownloadedEpisodes() {
    var allDownloaded: [LibraryEpisode] = []

    // Check each episode from subscribed podcasts for download status
    for podcast in podcastInfoModelList {
      let podcastInfo = podcast.podcastInfo

      for episode in podcastInfo.episodes {
        let downloadState = downloadManager.getDownloadState(
          episodeTitle: episode.title,
          podcastTitle: podcastInfo.title
        )

        // Only include downloaded episodes
        if case .downloaded = downloadState {
          let episodeKey = "\(podcastInfo.title)\(Self.episodeKeyDelimiter)\(episode.title)"
          let model = getEpisodeModel(for: episodeKey)

          allDownloaded.append(LibraryEpisode(
            id: episodeKey,
            podcastTitle: podcastInfo.title,
            imageURL: episode.imageURL ?? podcastInfo.imageURL,
            language: podcastInfo.language,
            episodeInfo: episode,
            isStarred: model?.isStarred ?? false,
            isDownloaded: true,
            isCompleted: model?.isCompleted ?? false,
            lastPlaybackPosition: model?.lastPlaybackPosition ?? 0
          ))
        }
      }
    }

    // Sort by publication date (newest first)
    downloadedEpisodes = allDownloaded
      .sorted { ($0.episodeInfo.pubDate ?? .distantPast) > ($1.episodeInfo.pubDate ?? .distantPast) }

    logger.info("Loaded \(self.downloadedEpisodes.count) downloaded episodes")
  }

  // MARK: - Load Latest Episodes

  private func loadLatestEpisodes() {
    var allEpisodes: [LibraryEpisode] = []

    for podcast in podcastInfoModelList {
      let podcastInfo = podcast.podcastInfo
      // Get latest 5 episodes from each podcast
      let latestFromPodcast = podcastInfo.episodes.prefix(5).map { episode in
        let episodeKey = "\(podcastInfo.title)\(Self.episodeKeyDelimiter)\(episode.title)"
        let model = getEpisodeModel(for: episodeKey)

        return LibraryEpisode(
          id: episodeKey,
          podcastTitle: podcastInfo.title,
          imageURL: episode.imageURL ?? podcastInfo.imageURL,
          language: podcastInfo.language,
          episodeInfo: episode,
          isStarred: model?.isStarred ?? false,
          isDownloaded: model?.localAudioPath != nil,
          isCompleted: model?.isCompleted ?? false,
          lastPlaybackPosition: model?.lastPlaybackPosition ?? 0
        )
      }
      allEpisodes.append(contentsOf: latestFromPodcast)
    }

    // Sort by date and take latest 50
    latestEpisodes = allEpisodes
      .sorted { ($0.episodeInfo.pubDate ?? .distantPast) > ($1.episodeInfo.pubDate ?? .distantPast) }
      .prefix(50)
      .map { $0 }

    logger.info("Loaded \(self.latestEpisodes.count) latest episodes")
  }

  // MARK: - Helper Methods

  private func findEpisodeInfo(for model: EpisodeDownloadModel) -> LibraryEpisode? {
    // Parse the episode key to get podcast title and episode title
    let parts = model.id.components(separatedBy: Self.episodeKeyDelimiter)
    guard parts.count == 2 else { return nil }

    let podcastTitle = parts[0]
    let episodeTitle = parts[1]

    // Find the podcast
    guard let podcast = podcastInfoModelList.first(where: { $0.podcastInfo.title == podcastTitle }) else {
      return nil
    }

    // Find the episode
    guard let episode = podcast.podcastInfo.episodes.first(where: { $0.title == episodeTitle }) else {
      return nil
    }

    return LibraryEpisode(
      id: model.id,
      podcastTitle: podcastTitle,
      imageURL: episode.imageURL ?? podcast.podcastInfo.imageURL,
      language: podcast.podcastInfo.language,
      episodeInfo: episode,
      isStarred: model.isStarred,
      isDownloaded: model.localAudioPath != nil,
      isCompleted: model.isCompleted,
      lastPlaybackPosition: model.lastPlaybackPosition
    )
  }

  private func getEpisodeModel(for key: String) -> EpisodeDownloadModel? {
    guard let context = modelContext else { return nil }

    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == key }
    )

    return try? context.fetch(descriptor).first
  }

  // MARK: - Refresh All Podcasts

  func refreshAllPodcasts() async {
    guard let context = modelContext else {
      logger.warning("ModelContext is nil, cannot refresh")
      return
    }

    isLoading = true
    error = nil

    let podcastCount = self.podcastInfoModelList.count
    logger.info("Starting parallel refresh of \(podcastCount) podcast feeds")

    // Extract RSS URLs and model IDs before entering TaskGroup
    let modelData: [(id: UUID, rssUrl: String)] = self.podcastInfoModelList.map { ($0.id, $0.podcastInfo.rssUrl) }

    // Use TaskGroup to fetch all podcasts in parallel
    let results = await withTaskGroup(of: (UUID, PodcastInfo?).self) { group -> [(UUID, PodcastInfo?)] in
      for (id, rssUrl) in modelData {
        group.addTask {
          do {
            let updatedPodcast = try await self.service.fetchPodcast(from: rssUrl)
            return (id, updatedPodcast)
          } catch {
            return (id, nil)
          }
        }
      }

      var collected: [(UUID, PodcastInfo?)] = []
      for await result in group {
        collected.append(result)
      }
      return collected
    }

    // Update models
    var successCount = 0
    for (id, updatedPodcast) in results {
      if let podcast = updatedPodcast,
         let model = self.podcastInfoModelList.first(where: { $0.id == id }) {
        model.podcastInfo = podcast
        successCount += 1
        logger.info("Updated \(podcast.title) with \(podcast.episodes.count) episodes")
      }
    }
    logger.info("Successfully refreshed \(successCount)/\(podcastCount) podcasts")

    // Save changes
    do {
      try context.save()
      logger.info("Saved all podcast updates")
    } catch {
      logger.error("Failed to save updates: \(error.localizedDescription)")
    }

    // Reload all data
    loadAll()

    isLoading = false
    logger.info("Finished refreshing all podcasts")
  }
}
