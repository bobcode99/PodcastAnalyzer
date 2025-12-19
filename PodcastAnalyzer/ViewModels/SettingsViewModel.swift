import Foundation
import SwiftUI
import Combine
import SwiftData
import os.log

// MARK: - Transcript Model Status
enum TranscriptModelStatus: Equatable {
    case checking
    case notDownloaded
    case downloading(progress: Double)
    case ready
    case error(String)
    case simulatorNotSupported

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var rssUrlInput: String = ""
    @Published var successMessage: String = ""
    @Published var errorMessage: String = ""
    @Published var podcastInfoModelList: [PodcastInfoModel] = []
    @Published var isValidating: Bool = false
    @Published var defaultPlaybackSpeed: Float = 1.0

    // Transcript model status
    @Published var transcriptModelStatus: TranscriptModelStatus = .checking

    private var successMessageTask: Task<Void, Never>?
    private var transcriptDownloadTask: Task<Void, Never>?
    private let service = PodcastRssService()
    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "SettingsViewModel")

    private enum Keys {
        static let defaultPlaybackSpeed = "defaultPlaybackSpeed"
    }

    init() {
        loadDefaultPlaybackSpeed()
    }

    // MARK: - Public Methods

    func addRssLink(modelContext: ModelContext, onSuccess: (() -> Void)? = nil) {
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
        successMessage = ""

        // Fetch and validate RSS feed
        Task { [weak self] in
            guard let self else { return }

            do {
                logger.info("Validating RSS feed: \(trimmedLink)")

                // Fetch happens on background thread
                let podcastInfo = try await service.fetchPodcast(from: trimmedLink)
                logger.info("RSS feed is valid: \(podcastInfo.title)")
                logger.debug("image url: \(podcastInfo.imageURL)")

                // Create new podcast feed
                let podcastInfoModel = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date.now)

                // Save to database
                modelContext.insert(podcastInfoModel)
                try? modelContext.save()

                podcastInfoModelList.append(podcastInfoModel)
                rssUrlInput = ""
                errorMessage = ""
                successMessage = "Feed added successfully!"
                logger.info("Feed saved to database: \(podcastInfo.title)")

                isValidating = false

                // Call success callback
                onSuccess?()

                // Hide success message after 2 seconds
                successMessageTask?.cancel()
                successMessageTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if !Task.isCancelled {
                        self.successMessage = ""
                    }
                }
            } catch let error as PodcastServiceError {
                logger.error("RSS validation failed: \(error.localizedDescription)")
                errorMessage = "Invalid RSS feed: \(error.localizedDescription)"
                successMessage = ""
                isValidating = false
            } catch {
                logger.error("Unexpected error: \(error.localizedDescription)")
                errorMessage = "Error: \(error.localizedDescription)"
                successMessage = ""
                isValidating = false
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

    func clearMessages() {
        successMessage = ""
        errorMessage = ""
        rssUrlInput = ""
    }

    // MARK: - Playback Speed Settings

    func setDefaultPlaybackSpeed(_ speed: Float) {
        defaultPlaybackSpeed = speed
        UserDefaults.standard.set(speed, forKey: Keys.defaultPlaybackSpeed)
        logger.info("Default playback speed set to \(speed)x")
    }

    private func loadDefaultPlaybackSpeed() {
        let savedSpeed = UserDefaults.standard.float(forKey: Keys.defaultPlaybackSpeed)
        defaultPlaybackSpeed = savedSpeed > 0 ? savedSpeed : 1.0
    }

    // MARK: - Transcript Model Management

    func checkTranscriptModelStatus() {
        // Check if running on simulator
        #if targetEnvironment(simulator)
        transcriptModelStatus = .simulatorNotSupported
        logger.info("Transcript model download not supported on simulator")
        return
        #else
        transcriptModelStatus = .checking

        Task {
            let transcriptService = TranscriptService()
            let isReady = await transcriptService.isModelReady()

            await MainActor.run {
                if isReady {
                    transcriptModelStatus = .ready
                    logger.info("Transcript model is ready")
                } else {
                    transcriptModelStatus = .notDownloaded
                    logger.info("Transcript model not downloaded")
                }
            }
        }
        #endif
    }

    func downloadTranscriptModel() {
        guard !transcriptModelStatus.isDownloading else { return }

        transcriptDownloadTask?.cancel()
        transcriptModelStatus = .downloading(progress: 0)

        transcriptDownloadTask = Task { [weak self] in
            guard let self else { return }

            let transcriptService = TranscriptService()

            for await progress in await transcriptService.setupAndInstallAssets() {
                if Task.isCancelled { break }
                transcriptModelStatus = .downloading(progress: progress)
            }

            if !Task.isCancelled {
                // Verify installation
                let isReady = await transcriptService.isModelReady()

                if isReady {
                    transcriptModelStatus = .ready
                    logger.info("Transcript model downloaded successfully")
                } else {
                    transcriptModelStatus = .error("Download completed but model not ready")
                    logger.error("Transcript model download failed verification")
                }
            }
        }
    }

    func cancelTranscriptDownload() {
        transcriptDownloadTask?.cancel()
        transcriptDownloadTask = nil
        transcriptModelStatus = .notDownloaded
        logger.info("Transcript model download cancelled")
    }

    // MARK: - Private Methods

    private func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme != nil && url.host != nil
    }
}
