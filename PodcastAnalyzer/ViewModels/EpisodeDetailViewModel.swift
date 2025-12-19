//
//  EpisodeDetailViewModel.swift
//  PodcastAnalyzer
//
//  Enhanced with download management and playback state
//

import SwiftUI
import ZMarkupParser
import SwiftData
import Combine
import os.log

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "EpisodeDetailViewModel")

@Observable
final class EpisodeDetailViewModel {
    
    var descriptionView: AnyView = AnyView(
        Text("Loading...").foregroundColor(.secondary)
    )
    
    let episode: PodcastEpisodeInfo
    let podcastTitle: String
    private let fallbackImageURL: String?
    
    // Reference singletons
    let audioManager = EnhancedAudioManager.shared
    private let downloadManager = DownloadManager.shared
    
    // Download state
    var downloadState: DownloadState = .notDownloaded

    // Transcript state
    var transcriptState: TranscriptState = .idle
    var transcriptText: String = ""
    var isModelReady: Bool = false
    private let fileStorage = FileStorageManager.shared

    // Playback state from SwiftData
    private var episodeModel: EpisodeDownloadModel?
    private var modelContext: ModelContext?

    // Cancellables for observation
    private var cancellables = Set<AnyCancellable>()
    
    init(episode: PodcastEpisodeInfo, podcastTitle: String, fallbackImageURL: String?) {
        self.episode = episode
        self.podcastTitle = podcastTitle
        self.fallbackImageURL = fallbackImageURL
        parseDescription()
        
        // Initialize download state
        updateDownloadState()
        
        // Observe download state changes
        observeDownloadState()
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadEpisodeModel()
    }
    
    // MARK: - Episode Properties
    
    var title: String { episode.title }
    
    var pubDateString: String? {
        episode.pubDate?.formatted(date: .long, time: .omitted)
    }
    
    var imageURLString: String {
        episode.imageURL ?? fallbackImageURL ?? ""
    }
    
    var audioURL: String? { episode.audioURL }
    var isPlayDisabled: Bool {
        guard episode.audioURL != nil else { return true }
        // Can play if downloaded or has URL
        return !hasLocalAudio && episode.audioURL == nil
    }
    
    var playbackURL: String {
        // Prefer local file if available
        if let localPath = localAudioPath {
            return "file://" + localPath
        }
        return episode.audioURL ?? ""
    }
    
    var hasLocalAudio: Bool {
        if case .downloaded = downloadState {
            return true
        }
        return false
    }
    
    var localAudioPath: String? {
        if case .downloaded(let path) = downloadState {
            return path
        }
        return nil
    }
    
    // MARK: - Playback State
    
    var isPlayingThisEpisode: Bool {
        guard let currentEpisode = audioManager.currentEpisode else { return false }
        return currentEpisode.title == episode.title && currentEpisode.podcastTitle == podcastTitle
    }
    
    var currentTime: TimeInterval {
        isPlayingThisEpisode ? audioManager.currentTime : (episodeModel?.lastPlaybackPosition ?? 0)
    }
    
    var duration: TimeInterval {
        isPlayingThisEpisode ? audioManager.duration : 0
    }
    
    var playbackRate: Float {
        audioManager.playbackRate
    }
    
    var currentCaption: String {
        isPlayingThisEpisode ? audioManager.currentCaption : ""
    }

    var isStarred: Bool {
        episodeModel?.isStarred ?? false
    }

    var savedDuration: TimeInterval {
        episodeModel?.duration ?? 0
    }

    var playbackProgress: Double {
        episodeModel?.progress ?? 0
    }

    var remainingTimeString: String? {
        episodeModel?.remainingTimeString
    }
    
    // MARK: - Actions
    
    func playAction() {
        guard let audioURLString = episode.audioURL else { return }

        // Prefer local file if available
        let playbackURL: String
        if let localPath = localAudioPath {
            playbackURL = "file://" + localPath
        } else {
            playbackURL = audioURLString
        }

        let playbackEpisode = PlaybackEpisode(
            id: "\(podcastTitle)|\(episode.title)",
            title: episode.title,
            podcastTitle: podcastTitle,
            audioURL: playbackURL,
            imageURL: imageURLString
        )

        // Resume from saved position if available
        let startTime = episodeModel?.lastPlaybackPosition ?? 0

        // Use default speed from settings only for fresh plays (not resuming)
        let useDefaultSpeed = startTime == 0

        audioManager.play(
            episode: playbackEpisode,
            audioURL: playbackURL,
            startTime: startTime,
            imageURL: imageURLString,
            useDefaultSpeed: useDefaultSpeed
        )

        // Update last played date
        updateLastPlayed()
    }
    
    func seek(to time: TimeInterval) {
        audioManager.seek(to: time)
        savePlaybackPosition(time)
    }
    
    func skipForward() {
        audioManager.skipForward()
    }
    
    func skipBackward() {
        audioManager.skipBackward()
    }
    
    func setPlaybackSpeed(_ rate: Float) {
        audioManager.setPlaybackRate(rate)
    }
    
    // MARK: - Download Management
    
    func startDownload() {
        downloadManager.downloadEpisode(episode: episode, podcastTitle: podcastTitle)
    }
    
    func cancelDownload() {
        downloadManager.cancelDownload(episodeTitle: episode.title, podcastTitle: podcastTitle)
    }
    
    func deleteDownload() {
        downloadManager.deleteDownload(episodeTitle: episode.title, podcastTitle: podcastTitle)
    }
    
    private func updateDownloadState() {
        downloadState = downloadManager.getDownloadState(
            episodeTitle: episode.title,
            podcastTitle: podcastTitle
        )
    }
    
    private func observeDownloadState() {
        // Poll for download state changes
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateDownloadState()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - SwiftData Persistence
    
    private func loadEpisodeModel() {
        guard let context = modelContext else { return }
        
        let id = "\(podcastTitle)|\(episode.title)"
        let descriptor = FetchDescriptor<EpisodeDownloadModel>(
            predicate: #Predicate { $0.id == id }
        )
        
        do {
            let results = try context.fetch(descriptor)
            if let model = results.first {
                episodeModel = model
            } else {
                // Create new model
                createEpisodeModel(context: context)
            }
        } catch {
            logger.error("Failed to load episode model: \(error.localizedDescription)")
        }
    }

    private func createEpisodeModel(context: ModelContext) {
        guard let audioURL = episode.audioURL else { return }

        let model = EpisodeDownloadModel(
            episodeTitle: episode.title,
            podcastTitle: podcastTitle,
            audioURL: audioURL,
            imageURL: imageURLString,
            pubDate: episode.pubDate
        )
        context.insert(model)

        do {
            try context.save()
            episodeModel = model
        } catch {
            logger.error("Failed to create episode model: \(error.localizedDescription)")
        }
    }
    
    private func savePlaybackPosition(_ position: TimeInterval) {
        guard let model = episodeModel else { return }
        model.lastPlaybackPosition = position

        // Also save duration if we have it
        if audioManager.duration > 0 {
            model.duration = audioManager.duration
        }

        // Mark as completed if near the end (within 30 seconds)
        if model.duration > 0 && position >= model.duration - 30 {
            model.isCompleted = true
        }

        do {
            try modelContext?.save()
        } catch {
            logger.error("Failed to save playback position: \(error.localizedDescription)")
        }
    }

    private func updateLastPlayed() {
        guard let model = episodeModel else { return }
        model.lastPlayedDate = Date()
        model.playCount += 1

        // Save image URL and pub date if not already saved
        if model.imageURL == nil {
            model.imageURL = imageURLString
        }
        if model.pubDate == nil {
            model.pubDate = episode.pubDate
        }

        do {
            try modelContext?.save()
        } catch {
            logger.error("Failed to update last played: \(error.localizedDescription)")
        }
    }

    // MARK: - Description Parsing

    private func parseDescription() {
        let html = episode.podcastEpisodeDescription ?? ""

        guard !html.isEmpty else {
            descriptionView = AnyView(
                Text("No description available.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
            return
        }

        let rootStyle = MarkupStyle(
            font: MarkupStyleFont(size: 16),
            foregroundColor: MarkupStyleColor(color: UIColor.label)
        )

        let parser = ZHTMLParserBuilder.initWithDefault()
            .set(rootStyle: rootStyle)
            .build()

        Task {
            let attributedString = parser.render(html)

            await MainActor.run {
                self.descriptionView = AnyView(
                    HTMLTextView(attributedString: attributedString)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                )
            }
        }
    }

    // MARK: - Action Methods

    func shareEpisode() {
        // TODO: Implement share functionality
        logger.debug("Share episode: \(self.episode.title)")
    }

    func translateDescription() {
        // TODO: Implement translation
        logger.debug("Translate description requested")
    }

    func toggleStar() {
        guard let model = episodeModel else { return }
        model.isStarred.toggle()

        do {
            try modelContext?.save()
        } catch {
            logger.error("Failed to save star state: \(error.localizedDescription)")
        }
    }

    func addToList() {
        // TODO: Implement add to list functionality
        logger.debug("Add to list: \(self.episode.title)")
    }

    func downloadAudio() {
        startDownload()
    }

    func reportIssue() {
        // TODO: Implement issue reporting
        logger.debug("Report issue for: \(self.episode.title)")
    }

    // MARK: - Transcript Methods

    func checkTranscriptStatus() {
        Task {
            // Check if model is ready
            let transcriptService = TranscriptService()
            isModelReady = await transcriptService.isModelReady()

            // Check if transcript already exists
            let exists = await fileStorage.captionFileExists(
                for: episode.title,
                podcastTitle: podcastTitle
            )

            if exists {
                await loadExistingTranscript()
            }
        }
    }

    func generateTranscript() {
        guard let audioPath = localAudioPath else {
            transcriptState = .error("No local audio file available. Please download the episode first.")
            return
        }

        Task {
            do {
                let audioURL = URL(fileURLWithPath: audioPath)
                let transcriptService = TranscriptService()

                let modelReady = await transcriptService.isModelReady()

                if !modelReady {
                    await MainActor.run {
                        transcriptState = .downloadingModel(progress: 0)
                    }

                    for await progress in await transcriptService.setupAndInstallAssets() {
                        await MainActor.run {
                            transcriptState = .downloadingModel(progress: progress)
                        }
                    }
                } else {
                    for await _ in await transcriptService.setupAndInstallAssets() {
                        // Silently consume progress
                    }
                }

                guard await transcriptService.isInitialized() else {
                    throw NSError(
                        domain: "TranscriptService", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to initialize transcription service"]
                    )
                }

                await MainActor.run {
                    transcriptState = .transcribing(progress: 0)
                }

                let srtContent = try await transcriptService.audioToSRT(inputFile: audioURL)

                _ = try await fileStorage.saveCaptionFile(
                    content: srtContent,
                    episodeTitle: episode.title,
                    podcastTitle: podcastTitle
                )

                await MainActor.run {
                    transcriptText = srtContent
                    transcriptState = .completed
                }

            } catch {
                await MainActor.run {
                    transcriptState = .error(error.localizedDescription)
                }
            }
        }
    }

    func copyTranscriptToClipboard() {
        UIPasteboard.general.string = transcriptText
    }

    private func loadExistingTranscript() async {
        do {
            let content = try await fileStorage.loadCaptionFile(
                for: episode.title,
                podcastTitle: podcastTitle
            )

            await MainActor.run {
                transcriptText = content
                transcriptState = .completed
            }
        } catch {
            logger.error("Failed to load transcript: \(error.localizedDescription)")
        }
    }

    var hasTranscript: Bool {
        !transcriptText.isEmpty
    }

    /// Parses SRT content and returns clean text without timestamps
    var cleanTranscriptText: String {
        guard !transcriptText.isEmpty else { return "" }

        var cleanLines: [String] = []
        let entries = transcriptText.components(separatedBy: "\n\n")

        for entry in entries {
            let lines = entry.components(separatedBy: "\n")
            // Skip index and timestamp lines, get text
            if lines.count >= 3 {
                let textLines = Array(lines[2...])
                cleanLines.append(contentsOf: textLines)
            }
        }

        return cleanLines.joined(separator: " ")
    }
}
