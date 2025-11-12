import Foundation
import SwiftUI
import Combine
import SwiftData

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var rssUrlInput: String = ""
    @Published var successMessage: String = ""
    @Published var errorMessage: String = ""
    @Published var podcastFeeds: [PodcastFeed] = []
    
    private var successMessageTask: Task<Void, Never>?
    
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
        
        // Create new podcast feed
        let newFeed = PodcastFeed(rssUrl: trimmedLink)
        
        do {
            modelContext.insert(newFeed)
            try modelContext.save()
            
            podcastFeeds.append(newFeed)
            rssUrlInput = ""
            errorMessage = ""
            successMessage = "✅ Feed added successfully!"
            
            // Hide success message after 2 seconds
            successMessageTask?.cancel()
            successMessageTask = Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !Task.isCancelled {
                    self.successMessage = ""
                }
            }
        } catch {
            errorMessage = "Failed to save feed: \(error.localizedDescription)"
            successMessage = ""
        }
    }
    
    func removePodcastFeed(_ feed: PodcastFeed, modelContext: ModelContext) {
        do {
            modelContext.delete(feed)
            try modelContext.save()
            podcastFeeds.removeAll { $0.id == feed.id }
            errorMessage = ""
        } catch {
            errorMessage = "Failed to delete feed: \(error.localizedDescription)"
        }
    }
    
    func loadFeeds(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<PodcastFeed>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        
        do {
            podcastFeeds = try modelContext.fetch(descriptor)
            errorMessage = ""
        } catch {
            errorMessage = "Failed to load feeds: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private Methods
    
    private func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme != nil && url.host != nil
    }
}
