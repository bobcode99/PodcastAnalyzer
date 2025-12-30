//
//  PodcastImportManager.swift
//  PodcastAnalyzer
//
//  Handles importing podcasts from Shortcuts (Apple Podcasts export)
//

import Combine
import Foundation
import SwiftData
import os.log

@MainActor
class PodcastImportManager: ObservableObject {
    static let shared = PodcastImportManager()

    @Published var isImporting = false
    @Published var importProgress: Double = 0
    @Published var importStatus: String = ""
    @Published var importResults: ImportResults?
    @Published var showImportSheet = false

    private let rssService = PodcastRssService()
    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "PodcastImport")
    private var modelContainer: ModelContainer?
    private var cancellables = Set<AnyCancellable>()

    struct ImportResults {
        let total: Int
        let successful: Int
        let failed: Int
        let skipped: Int
        let failedPodcasts: [String]
    }

    private init() {
        setupNotificationObserver()
    }

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.publisher(for: .importPodcastsRequested)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let rssURLs = notification.userInfo?["rssURLs"] as? [String] else { return }
                Task { @MainActor in
                    await self?.importPodcasts(from: rssURLs)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Import Podcasts

    func importPodcasts(from rssURLs: [String]) async {
        guard let container = modelContainer else {
            logger.error("ModelContainer not set, cannot import podcasts")
            return
        }

        isImporting = true
        showImportSheet = true
        importProgress = 0
        importStatus = "Starting import..."
        importResults = nil

        let context = ModelContext(container)
        var successful = 0
        var failed = 0
        var skipped = 0
        var failedPodcasts: [String] = []

        for (index, rssURL) in rssURLs.enumerated() {
            importProgress = Double(index) / Double(rssURLs.count)
            importStatus = "Importing podcast \(index + 1) of \(rssURLs.count)..."

            do {
                // Check if podcast already exists
                let existingPodcast = try findExistingPodcast(rssURL: rssURL, context: context)

                if let existing = existingPodcast {
                    if existing.isSubscribed {
                        // Already subscribed, skip
                        logger.info("Skipping already subscribed podcast: \(existing.podcastInfo.title)")
                        skipped += 1
                        continue
                    } else {
                        // Exists but not subscribed, just flip the flag
                        existing.isSubscribed = true
                        try context.save()
                        logger.info("Subscribed to existing podcast: \(existing.podcastInfo.title)")
                        successful += 1
                        continue
                    }
                }

                // Fetch podcast info from RSS
                let podcastInfo = try await rssService.fetchPodcast(from: rssURL)

                // Check if podcast with same title exists
                if let existingByTitle = try findPodcastByTitle(title: podcastInfo.title, context: context) {
                    if existingByTitle.isSubscribed {
                        logger.info("Skipping duplicate podcast: \(podcastInfo.title)")
                        skipped += 1
                        continue
                    } else {
                        existingByTitle.isSubscribed = true
                        try context.save()
                        successful += 1
                        continue
                    }
                }

                // Create new subscription
                let model = PodcastInfoModel(
                    podcastInfo: podcastInfo,
                    lastUpdated: Date(),
                    isSubscribed: true
                )
                context.insert(model)
                try context.save()

                logger.info("Successfully imported: \(podcastInfo.title)")
                successful += 1

            } catch {
                logger.error("Failed to import podcast from \(rssURL): \(error.localizedDescription)")
                failed += 1
                failedPodcasts.append(rssURL)
            }
        }

        importProgress = 1.0
        importStatus = "Import complete!"
        importResults = ImportResults(
            total: rssURLs.count,
            successful: successful,
            failed: failed,
            skipped: skipped,
            failedPodcasts: failedPodcasts
        )

        isImporting = false

        logger.info("Import completed: \(successful) successful, \(failed) failed, \(skipped) skipped")
    }

    // MARK: - Helper Methods

    private func findExistingPodcast(rssURL: String, context: ModelContext) throws -> PodcastInfoModel? {
        let descriptor = FetchDescriptor<PodcastInfoModel>(
            predicate: #Predicate { $0.podcastInfo.rssUrl == rssURL }
        )
        return try context.fetch(descriptor).first
    }

    private func findPodcastByTitle(title: String, context: ModelContext) throws -> PodcastInfoModel? {
        let descriptor = FetchDescriptor<PodcastInfoModel>(
            predicate: #Predicate { $0.podcastInfo.title == title }
        )
        return try context.fetch(descriptor).first
    }

    func dismissImportSheet() {
        showImportSheet = false
        importResults = nil
    }
}
