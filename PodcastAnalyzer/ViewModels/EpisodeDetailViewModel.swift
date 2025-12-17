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
        
        audioManager.play(
            episode: playbackEpisode,
            audioURL: playbackURL,
            startTime: startTime,
            imageURL: imageURLString
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
            print("Failed to load episode model: \(error)")
        }
    }
    
    private func createEpisodeModel(context: ModelContext) {
        guard let audioURL = episode.audioURL else { return }
        
        let model = EpisodeDownloadModel(
            episodeTitle: episode.title,
            podcastTitle: podcastTitle,
            audioURL: audioURL
        )
        context.insert(model)
        
        do {
            try context.save()
            episodeModel = model
        } catch {
            print("Failed to create episode model: \(error)")
        }
    }
    
    private func savePlaybackPosition(_ position: TimeInterval) {
        guard let model = episodeModel else { return }
        model.lastPlaybackPosition = position
        
        do {
            try modelContext?.save()
        } catch {
            print("Failed to save playback position: \(error)")
        }
    }
    
    private func updateLastPlayed() {
        guard let model = episodeModel else { return }
        model.lastPlayedDate = Date()
        
        do {
            try modelContext?.save()
        } catch {
            print("Failed to update last played: \(error)")
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
}
