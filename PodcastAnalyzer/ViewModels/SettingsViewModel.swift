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
    @Published var podcastInfoModelList: [PodcastInfoModel] = []
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
        guard !podcastInfoModelList.contains(where: { $0.podcastInfo.rssUrl == trimmedLink }) else {
            errorMessage = "This feed is already added"
            successMessage = ""
            return
        }
        
        // Start validation
        isValidating = true
        errorMessage = ""
        successMessage = "Validating RSS feed..."

        // Use Task.detached to avoid blocking main thread
        Task.detached { [weak self] in
            guard let self else { return }

            do {
                await self.logger.info("Validating RSS feed: \(trimmedLink)")

                // Fetch happens on background thread
                let podcastInfo = try await self.service.fetchPodcast(from: trimmedLink)
                await self.logger.info("✅ RSS feed is valid: \(podcastInfo.title)")
                await self.logger.debug("image url: \(podcastInfo.imageURL)")

                // Switch to main actor for UI updates and database operations
                await MainActor.run {
                    // Create new podcast feed
                    let podcastInfoModel = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date.now)

                    // Save to database
                    modelContext.insert(podcastInfoModel)
                    try? modelContext.save()

                    self.podcastInfoModelList.append(podcastInfoModel)
                    self.rssUrlInput = ""
                    self.errorMessage = ""
                    self.successMessage = "✅ Feed added successfully!"
                    self.logger.info("Feed saved to database: \(podcastInfo.title)")

                    // Hide success message after 2 seconds
                    self.successMessageTask?.cancel()
                    self.successMessageTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if !Task.isCancelled {
                            self.successMessage = ""
                        }
                    }

                    self.isValidating = false
                }
            } catch let error as PodcastServiceError {
                await MainActor.run {
                    self.logger.error("RSS validation failed: \(error.localizedDescription)")
                    self.errorMessage = "❌ Invalid RSS feed: \(error.localizedDescription)"
                    self.successMessage = ""
                    self.isValidating = false
                }
            } catch {
                await MainActor.run {
                    self.logger.error("Unexpected error: \(error.localizedDescription)")
                    self.errorMessage = "❌ Error: \(error.localizedDescription)"
                    self.successMessage = ""
                    self.isValidating = false
                }
            }
        }
    }
    
    func removePodcastFeed(_ podcastInfoModel: PodcastInfoModel, modelContext: ModelContext) {
        do {
            modelContext.delete(podcastInfoModel)
            try modelContext.save()
            podcastInfoModelList.removeAll { $0.id == podcastInfoModel.id }
            errorMessage = ""
            self.logger.info("Feed deleted: \(podcastInfoModel.podcastInfo.title)")
        } catch {
            errorMessage = "Failed to delete feed: \(error.localizedDescription)"
            self.logger.error("Failed to delete feed: \(error.localizedDescription)")
        }
    }
    
    func loadFeeds(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<PodcastInfoModel>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        
        do {
            podcastInfoModelList = try modelContext.fetch(descriptor)
            errorMessage = ""
            self.logger.info("Loaded \(self.podcastInfoModelList.count) feeds")
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
