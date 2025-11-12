// ViewModels/HomeViewModel.swift
import Foundation
import SwiftUI
import Combine
import SwiftData

@MainActor
class HomeViewModel: ObservableObject {
    @Published var podcasts: [String] = []
    @Published var podcastFeeds: [PodcastFeed] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let service = PodcastRssService()
    private var modelContext: ModelContext?
    
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
        // Call your service here
        // Example: service.fetchPodcasts(from: podcastFeeds)
        isLoading = false
    }
    
    // MARK: - SwiftData Operations
    
    private func loadPodcastFeeds() {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PodcastFeed>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        
        do {
            podcastFeeds = try context.fetch(descriptor)
        } catch {
            self.error = "Failed to load feeds: \(error.localizedDescription)"
        }
    }
}
