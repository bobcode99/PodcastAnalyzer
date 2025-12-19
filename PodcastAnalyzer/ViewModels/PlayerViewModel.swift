//
//  PlayerViewModel.swift
//  PodcastAnalyzer
//
//  DEPRECATED: This ViewModel has been replaced by ExpandedPlayerViewModel
//  This file is kept for reference but should not be used in new code
//

import Foundation
import SwiftUI
import Combine
import os.log

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "PlayerViewModel")

// MARK: - PlayerViewModel (Manual Observable Implementation)

@available(*, deprecated, message: "Use ExpandedPlayerViewModel instead")
class PlayerViewModel: ObservableObject {
    
    // MARK: - Published Properties (like @Published in ObservableObject)
    
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 1 // Prevent divide by zero
    @Published var playbackSpeed: Float = 1.0
    @Published var currentCaption: String = ""
    
    // MARK: - Computed Properties
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var currentTimeString: String {
        formatTime(currentTime)
    }
    
    var remainingTimeString: String {
        let remaining = duration - currentTime
        return "-" + formatTime(remaining)
    }
    
    // MARK: - Episode Info
    
    let episode: PodcastEpisodeInfo
    let episodeTitle: String
    let podcastTitle: String
    let audioURL: String
    let imageURL: URL?
    
    // MARK: - Dependencies
    
    private let audioManager = EnhancedAudioManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?
    
    // MARK: - Initialization
    
    init(episode: PodcastEpisodeInfo, podcastTitle: String, audioURL: String, imageURL: String?) {
        self.episode = episode
        self.episodeTitle = episode.title
        self.podcastTitle = podcastTitle
        self.audioURL = audioURL
        self.imageURL = imageURL != nil ? URL(string: imageURL!) : nil
        
        setupObservers()
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Update UI every 0.1 seconds while playing
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updatePlaybackState()
        }
    }
    
    private func updatePlaybackState() {
        // Sync with audio manager
        if audioManager.currentEpisode?.title == episodeTitle {
            isPlaying = audioManager.isPlaying
            currentTime = audioManager.currentTime
            duration = audioManager.duration
            playbackSpeed = audioManager.playbackRate
            currentCaption = audioManager.currentCaption
        }
    }
    
    // MARK: - Playback Control
    
    func startPlayback() {
        let playbackEpisode = PlaybackEpisode(
            id: "\(podcastTitle)|\(episodeTitle)",
            title: episodeTitle,
            podcastTitle: podcastTitle,
            audioURL: audioURL,
            imageURL: imageURL?.absoluteString
        )
        
        audioManager.play(
            episode: playbackEpisode,
            audioURL: audioURL,
            startTime: 0,
            imageURL: imageURL?.absoluteString
        )
    }
    
    func togglePlayPause() {
        if isPlaying {
            pausePlayback()
        } else {
            resumePlayback()
        }
    }
    
    func pausePlayback() {
        audioManager.pause()
    }
    
    func resumePlayback() {
        audioManager.resume()
    }
    
    func skipForward() {
        audioManager.skipForward(seconds: 15)
    }
    
    func skipBackward() {
        audioManager.skipBackward(seconds: 15)
    }
    
    func seekToProgress(_ progress: Double) {
        let newTime = progress * duration
        audioManager.seek(to: newTime)
    }
    
    func setPlaybackSpeed(_ speed: Float) {
        audioManager.setPlaybackRate(speed)
    }
    
    // MARK: - Additional Actions

    func shareEpisode() {
        // TODO: Implement sharing
        logger.debug("Share episode: \(self.episodeTitle)")
    }

    func addToPlaylist() {
        // TODO: Implement playlist
        logger.debug("Add to playlist: \(self.episodeTitle)")
    }

    func showEpisodeNotes() {
        // TODO: Implement episode notes
        logger.debug("Show episode notes requested")
    }

    func showSleepTimer() {
        // TODO: Implement sleep timer
        logger.debug("Show sleep timer requested")
    }

    func showAirPlay() {
        // TODO: Implement AirPlay picker
        logger.debug("Show AirPlay requested")
    }

    func showQueue() {
        // TODO: Implement queue
        logger.debug("Show queue requested")
    }
    
    // MARK: - Helpers
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }
        
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        updateTimer?.invalidate()
        cancellables.removeAll()
    }
}