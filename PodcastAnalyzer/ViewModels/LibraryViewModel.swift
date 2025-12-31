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

  /// Podcasts sorted by most recent episode date (for Library grid)
  var podcastsSortedByRecentUpdate: [PodcastInfoModel] {
    podcastInfoModelList.sorted { p1, p2 in
      let date1 = p1.podcastInfo.episodes.first?.pubDate ?? .distantPast
      let date2 = p2.podcastInfo.episodes.first?.pubDate ?? .distantPast
      return date1 > date2
    }
  }

  private let service = PodcastRssService()
  private let downloadManager = DownloadManager.shared
  private var modelContext: ModelContext?
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "LibraryViewModel")

  // All podcasts (subscribed + browsed) for episode lookups
  private var allPodcasts: [PodcastInfoModel] = []

  // Flag to prevent redundant loads
  private var isAlreadyLoaded = false

  // Use Unit Separator (U+001F) as delimiter
  private static let episodeKeyDelimiter = "\u{1F}"

  init(modelContext: ModelContext?) {
    self.modelContext = modelContext
    if modelContext != nil {
      Task {
        await loadAll()
      }
    }
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    // Only load if we haven't or if we need a fresh start
    if !isAlreadyLoaded {
      Task {
        await loadAll()
        isAlreadyLoaded = true
      }
    }
  }

  // MARK: - Load All Data

  private func loadAll() async {
    isLoading = true

    // First, load all podcasts (needed by other loaders)
    await loadAllPodcasts()

    // Then run the rest in parallel
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await self.loadPodcastFeeds() }
      group.addTask { await self.loadSavedEpisodes() }
      group.addTask { await self.loadDownloadedEpisodes() }
      group.addTask { await self.loadLatestEpisodes() }
    }

    isLoading = false
  }

  // MARK: - Load All Podcasts (for episode lookups)

  private func loadAllPodcasts() async {
    guard let context = modelContext else { return }

    // Load ALL podcasts (subscribed + browsed) for episode lookups
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
    )

    do {
      let podcasts = try context.fetch(descriptor)
      await MainActor.run {
        self.allPodcasts = podcasts
        logger.info("Loaded \(self.allPodcasts.count) total podcasts for episode lookups")
      }
    } catch {
      logger.error("Failed to load all podcasts: \(error.localizedDescription)")
    }
  }

  // MARK: - Load Podcasts

  private func loadPodcastFeeds() async {
    guard let context = modelContext else {
      logger.warning("ModelContext is nil, cannot load feeds")
      return
    }

    // Only load subscribed podcasts (not browsed/cached ones)
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.isSubscribed == true },
      sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
    )

    do {
      let podcasts = try context.fetch(descriptor)
      await MainActor.run {
        self.podcastInfoModelList = podcasts
        logger.info("Loaded \(self.podcastInfoModelList.count) subscribed podcast feeds from database")
      }
    } catch {
      await MainActor.run {
        self.error = "Failed to load feeds: \(error.localizedDescription)"
        logger.error("Failed to load feeds: \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Load Saved Episodes

  private func loadSavedEpisodes() async {
    guard let context = modelContext else { return }

    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.isStarred == true },
      sortBy: [SortDescriptor(\.downloadedDate, order: .reverse)]
    )

    do {
      let models = try context.fetch(descriptor)
      // Map models to LibraryEpisodes - need to access allPodcasts on MainActor
      let results = await MainActor.run {
        models.compactMap { model in
          self.findEpisodeInfo(for: model)
        }
      }
      await MainActor.run {
        self.savedEpisodes = results
        logger.info("Loaded \(self.savedEpisodes.count) saved episodes")
      }
    } catch {
      logger.error("Failed to load saved episodes: \(error.localizedDescription)")
    }
  }

  // MARK: - Load Downloaded Episodes

  private func loadDownloadedEpisodes() async {
    guard let context = modelContext else { return }

    // OPTIMIZATION: Instead of looping ALL episodes,
    // query the EpisodeDownloadModel directly!
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.localAudioPath != nil },
      sortBy: [SortDescriptor(\.downloadedDate, order: .reverse)]
    )

    do {
      let downloadedModels = try context.fetch(descriptor)
      // Map models to LibraryEpisodes - need to access allPodcasts on MainActor
      let results = await MainActor.run {
        downloadedModels.compactMap { model in
          self.findEpisodeInfo(for: model)
        }
      }

      await MainActor.run {
        self.downloadedEpisodes = results
        logger.info("Loaded \(self.downloadedEpisodes.count) downloaded episodes")
      }
    } catch {
      logger.error("Download fetch failed: \(error)")
    }
  }

  // MARK: - Load Latest Episodes

  private func loadLatestEpisodes() async {
    // Wait for podcastInfoModelList to be loaded
    let pods = await MainActor.run { self.podcastInfoModelList }
    var allEpisodes: [LibraryEpisode] = []

    for podcast in pods {
      let podcastInfo = podcast.podcastInfo
      // Get latest 5 episodes from each podcast
      for episode in podcastInfo.episodes.prefix(5) {
        let episodeKey = "\(podcastInfo.title)\(Self.episodeKeyDelimiter)\(episode.title)"
        // Note: getEpisodeModel still hits DB, but we batch this better now
        let model = await MainActor.run {
          self.getEpisodeModel(for: episodeKey)
        }

        allEpisodes.append(LibraryEpisode(
          id: episodeKey,
          podcastTitle: podcastInfo.title,
          imageURL: episode.imageURL ?? podcastInfo.imageURL,
          language: podcastInfo.language,
          episodeInfo: episode,
          isStarred: model?.isStarred ?? false,
          isDownloaded: model?.localAudioPath != nil,
          isCompleted: model?.isCompleted ?? false,
          lastPlaybackPosition: model?.lastPlaybackPosition ?? 0
        ))
      }
    }

    // Sort by date and take latest 50
    let sorted = allEpisodes
      .sorted { ($0.episodeInfo.pubDate ?? .distantPast) > ($1.episodeInfo.pubDate ?? .distantPast) }
      .prefix(50)

    await MainActor.run {
      self.latestEpisodes = Array(sorted)
      logger.info("Loaded \(self.latestEpisodes.count) latest episodes")
    }
  }

  // MARK: - Helper Methods

  private func findEpisodeInfo(for model: EpisodeDownloadModel) -> LibraryEpisode? {
    // Parse the episode key to get podcast title and episode title
    let parts = model.id.components(separatedBy: Self.episodeKeyDelimiter)
    guard parts.count == 2 else { return nil }

    let podcastTitle = parts[0]
    let episodeTitle = parts[1]

    // Find the podcast from ALL podcasts (subscribed + browsed)
    // Access allPodcasts on MainActor since it's a @MainActor class
    let podcasts = allPodcasts
    guard let podcast = podcasts.first(where: { $0.podcastInfo.title == podcastTitle }) else {
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
    await loadAll()

    isLoading = false
    logger.info("Finished refreshing all podcasts")
  }
}
