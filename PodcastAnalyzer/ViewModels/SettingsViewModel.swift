import Foundation
import SwiftUI
import Combine
import SwiftData

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var rssLink: String = ""
    @Published var showSuccessMessage: Bool = false
    @Published var errorMessage: String?
    @Published var podcastFeeds: [PodcastFeed] = []
    
    private var successMessageTask: Task<Void, Never>?
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
    
    // MARK: - Public Methods
    
    func addRssLink() {
        guard let context = modelContext else {
            errorMessage = "Database connection error"
            return
        }
        
        let trimmedLink = rssLink.trimmingCharacters(in: .whitespaces)
        
        // Validate URL format
        guard isValidURL(trimmedLink) else {
            errorMessage = "Please enter a valid URL"
            return
        }
        
        // Check for duplicates
        guard !podcastFeeds.contains(where: { $0.rssUrl == trimmedLink }) else {
            errorMessage = "This feed is already added"
            return
        }
        
        // Create new podcast feed
        let newFeed = PodcastFeed(rssUrl: trimmedLink)
        
        do {
            context.insert(newFeed)
            try context.save()
            
            podcastFeeds.append(newFeed)
            rssLink = ""
            errorMessage = nil
            showSuccessMessage = true
            
            // Hide success message after 2 seconds
            successMessageTask?.cancel()
            successMessageTask = Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if !Task.isCancelled {
                    self.showSuccessMessage = false
                }
            }
        } catch {
            errorMessage = "Failed to save feed: \(error.localizedDescription)"
        }
    }
    
    func removePodcastFeed(_ feed: PodcastFeed) {
        guard let context = modelContext else {
            errorMessage = "Database connection error"
            return
        }
        
        do {
            context.delete(feed)
            try context.save()
            podcastFeeds.removeAll { $0.id == feed.id }
        } catch {
            errorMessage = "Failed to delete feed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private Methods
    
    private func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme != nil && url.host != nil
    }
    
    private func loadPodcastFeeds() {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PodcastFeed>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        
        do {
            podcastFeeds = try context.fetch(descriptor)
        } catch {
            errorMessage = "Failed to load feeds: \(error.localizedDescription)"
        }
    }
}
