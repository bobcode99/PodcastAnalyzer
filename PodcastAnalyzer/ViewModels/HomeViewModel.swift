import Combine
// ViewModels/HomeViewModel.swift
import Foundation
import SwiftData
import SwiftUI
import os.log

@MainActor
class HomeViewModel: ObservableObject {
  @Published var podcastInfoModelList: [PodcastInfoModel] = []
  @Published var isLoading = false
  @Published var error: String?

  private let service = PodcastRssService()
  private var modelContext: ModelContext?
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "HomeViewModel")

  init(modelContext: ModelContext?) {
    self.modelContext = modelContext
    if modelContext != nil {
      loadPodcastFeeds()
    }
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    loadPodcastFeeds()
  }

  func loadPodcasts() {
    loadPodcastFeeds()
  }

  /// Refresh all podcasts by fetching latest data from RSS feeds using parallel TaskGroup
  func refreshAllPodcasts() async {
    guard let context = modelContext else {
      logger.warning("ModelContext is nil, cannot refresh")
      return
    }

    isLoading = true
    error = nil

    let podcastCount = self.podcastInfoModelList.count
    logger.info("Starting parallel refresh of \(podcastCount) podcast feeds")

    // Extract RSS URLs and model IDs before entering TaskGroup to avoid Sendable issues
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

    // Update models on main actor
    var successCount = 0
    for (id, updatedPodcast) in results {
      if let podcast = updatedPodcast,
         let model = self.podcastInfoModelList.first(where: { $0.id == id }) {
        model.podcastInfo = podcast
        successCount += 1
        logger.info("Updated \(podcast.title) with \(podcast.episodes.count) episodes")
      }
    }
    logger.info("Successfully refreshed \(successCount)/\(podcastCount) podcasts in parallel")

    // Save changes
    do {
      try context.save()
      logger.info("Saved all podcast updates")
    } catch {
      logger.error("Failed to save updates: \(error.localizedDescription)")
    }

    isLoading = false
    logger.info("Finished refreshing all podcasts")
  }

  // MARK: - SwiftData Operations

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
}
