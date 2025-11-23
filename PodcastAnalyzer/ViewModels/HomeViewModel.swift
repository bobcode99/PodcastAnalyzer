// ViewModels/HomeViewModel.swift
import Foundation
import SwiftUI
import Combine
import SwiftData
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
        isLoading = true
        error = nil
        
        logger.info("Starting to load podcasts from \(self.podcastInfoModelList.count) feeds")
        
        Task {
            for podcastInfoModel in podcastInfoModelList {
                    self.logger.info("Fetching podcast from URL: \(podcastInfoModel.podcastInfo.rssUrl)")
                                        
                    // Update feed with fetched data
                
//                podcastInfoModel.podcastInfo.episodes.forEach { episode in
//                 
//                    self.logger.info("All:  \(episode.title)")
//                }
               
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
            podcastInfoModelList = try context.fetch(descriptor)
            logger.info("Loaded \(self.podcastInfoModelList.count) podcast feeds from database")
        } catch {
            self.error = "Failed to load feeds: \(error.localizedDescription)"
            logger.error("Failed to load feeds: \(error.localizedDescription)")
        }
    }
}
