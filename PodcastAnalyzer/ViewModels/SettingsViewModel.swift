import Foundation
import SwiftUI
import Combine
import SwiftData
import os.log

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var rssUrlInput: String = ""
    @Published var successMessage: String = ""
    @Published var errorMessage: String = ""
    @Published var podcastFeeds: [PodcastFeed] = []
    @Published var isValidating: Bool = false
    
    private var successMessageTask: Task<Void, Never>?
    private let service = PodcastRssService()
    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "SettingsViewModel")
    
    // MARK: - Public Methods
    
    func addRssLink(modelContext: ModelContext) {
        let trimmedLink = rssUrlInput.trimmingCharacters(in: .whitespaces)
        
        // Validate URL format
        guard isValidURL(trimmedLink) else {
            errorMessage = "Please enter a valid URL"
            successMessage = ""
            return
        }
        
        // Check for duplicates
        guard !podcastFeeds.contains(where: { $0.rssUrl == trimmedLink }) else {
            errorMessage = "This feed is already added"
            successMessage = ""
            return
        }
        
        // Start validation
        isValidating = true
        errorMessage = ""
        successMessage = "Validating RSS feed..."
        
        Task {
            do {
                self.logger.info("Validating RSS feed: \(trimmedLink)")
                
                // Try to fetch the podcast to validate the RSS feed
                let podcastInfo = try await service.fetchPodcast(from: trimmedLink)
                
                self.logger.info("✅ RSS feed is valid: \(podcastInfo.title)")
                
                // Create new podcast feed
                let newFeed = PodcastFeed(rssUrl: trimmedLink)
                newFeed.title = podcastInfo.title
                newFeed.subtitle = podcastInfo.description
                
                // Save to database
                modelContext.insert(newFeed)
                try modelContext.save()
                
                self.podcastFeeds.append(newFeed)
                self.rssUrlInput = ""
                self.errorMessage = ""
                self.successMessage = "✅ Feed added successfully!"
                self.logger.info("Feed saved to database: \(podcastInfo.title)")
                
                // Hide success message after 2 seconds
                self.successMessageTask?.cancel()
                self.successMessageTask = Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if !Task.isCancelled {
                        self.successMessage = ""
                    }
                }
            } catch let error as PodcastServiceError {
                self.logger.error("RSS validation failed: \(error.localizedDescription)")
                self.errorMessage = "❌ Invalid RSS feed: \(error.localizedDescription)"
                self.successMessage = ""
            } catch {
                self.logger.error("Unexpected error: \(error.localizedDescription)")
                self.errorMessage = "❌ Error: \(error.localizedDescription)"
                self.successMessage = ""
            }
            
            self.isValidating = false
        }
    }
    
    func removePodcastFeed(_ feed: PodcastFeed, modelContext: ModelContext) {
        do {
            modelContext.delete(feed)
            try modelContext.save()
            podcastFeeds.removeAll { $0.id == feed.id }
            errorMessage = ""
            self.logger.info("Feed deleted: \(feed.title ?? feed.rssUrl)")
        } catch {
            errorMessage = "Failed to delete feed: \(error.localizedDescription)"
            self.logger.error("Failed to delete feed: \(error.localizedDescription)")
        }
    }
    
    func loadFeeds(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<PodcastFeed>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        
        do {
            podcastFeeds = try modelContext.fetch(descriptor)
            errorMessage = ""
            self.logger.info("Loaded \(self.podcastFeeds.count) feeds")
        } catch {
            errorMessage = "Failed to load feeds: \(error.localizedDescription)"
            self.logger.error("Failed to load feeds: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    
    private func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme != nil && url.host != nil
    }
}
