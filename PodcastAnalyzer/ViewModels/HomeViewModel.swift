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

  /// Refresh all podcasts by fetching latest data from RSS feeds
  func refreshAllPodcasts() async {
    guard let context = modelContext else {
      logger.warning("ModelContext is nil, cannot refresh")
      return
    }

    isLoading = true
    error = nil

    logger.info("Starting to refresh \(self.podcastInfoModelList.count) podcast feeds")

    for model in self.podcastInfoModelList {
      let rssUrl = model.podcastInfo.rssUrl
      logger.info("Fetching latest episodes from: \(rssUrl)")

      do {
        let updatedPodcast = try await service.fetchPodcast(from: rssUrl)

        logger.info("Language: \(updatedPodcast.language)")
        // Update the model with new data
        model.podcastInfo = updatedPodcast
        logger.info(
          "Updated \(updatedPodcast.title) with \(updatedPodcast.episodes.count) episodes"
        )
      } catch {
        logger.error("Failed to refresh \(rssUrl): \(error.localizedDescription)")
      }
    }

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
