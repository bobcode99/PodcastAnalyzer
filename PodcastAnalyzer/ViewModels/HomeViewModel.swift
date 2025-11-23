// ViewModels/HomeViewModel.swift
import Foundation
import SwiftUI
import Combine
import SwiftData
import os.log

@MainActor
class HomeViewModel: ObservableObject {
    @Published var podcasts: [PodcastInfo] = []
    @Published var podcastFeeds: [PodcastInfoModel] = []
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
        isLoading = true
        error = nil
        podcasts = []  // Clear previous podcasts to avoid duplicates
        
        logger.info("Starting to load podcasts from \(self.podcastFeeds.count) feeds")
        
        Task {
            for feed in podcastFeeds {
                do {
                    self.logger.info("Fetching podcast from URL: \(feed.rssUrl)")
                    let podcastInfo = try await service.fetchPodcast(from: feed.rssUrl)
                    
                    self.logger.info("✅ Successfully fetched: \(podcastInfo.title)")
                    self.logger.debug("Episodes count: \(podcastInfo.episodes.count)")
                    self.logger.debug("image url: \(podcastInfo.imageURL)")
                    
                    // Update feed with fetched data
                    feed.title = podcastInfo.title
                    feed.lastUpdated = Date()
                    
                    // Add to podcasts list (no duplicates because ID is rssUrl)
                    self.podcasts.append(podcastInfo)
                    
                    // Save to SwiftData
                    if let context = self.modelContext {
                        try context.save()
                        self.logger.debug("Feed saved to database")
                    }
                    
                } catch let error as PodcastServiceError {
                    self.logger.error("PodcastServiceError for \(feed.rssUrl): \(error.localizedDescription)")
                    self.error = "Failed to fetch \(feed.title ?? "podcast"): \(error.localizedDescription)"
                } catch {
                    self.logger.error("Unknown error for \(feed.rssUrl): \(error.localizedDescription)")
                    self.error = "An unexpected error occurred: \(error.localizedDescription)"
                }
            }
            
            self.isLoading = false
            self.logger.info("Finished loading all podcasts")
        }
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
            podcastFeeds = try context.fetch(descriptor)
            logger.info("Loaded \(self.podcastFeeds.count) podcast feeds from database")
        } catch {
            self.error = "Failed to load feeds: \(error.localizedDescription)"
            logger.error("Failed to load feeds: \(error.localizedDescription)")
        }
    }
}
