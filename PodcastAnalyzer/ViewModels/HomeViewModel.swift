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

    // Use TaskGroup to fetch all podcasts in parallel
    await withTaskGroup(of: (PodcastInfoModel, PodcastInfo?).self) { group in
      for model in self.podcastInfoModelList {
        group.addTask {
          let rssUrl = model.podcastInfo.rssUrl
          do {
            let updatedPodcast = try await self.service.fetchPodcast(from: rssUrl)
            return (model, updatedPodcast)
          } catch {
            self.logger.error("Failed to refresh \(rssUrl): \(error.localizedDescription)")
            return (model, nil)
          }
        }
      }

      // Collect results and update models
      var successCount = 0
      for await (model, updatedPodcast) in group {
        if let podcast = updatedPodcast {
          model.podcastInfo = podcast
          successCount += 1
          logger.info("Updated \(podcast.title) with \(podcast.episodes.count) episodes")
        }
      }
      logger.info("Successfully refreshed \(successCount)/\(podcastCount) podcasts in parallel")
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
