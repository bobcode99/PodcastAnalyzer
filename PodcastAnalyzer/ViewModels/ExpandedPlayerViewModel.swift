//
//  ExpandedPlayerViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for expanded player view
//

import Combine
import SwiftUI

class ExpandedPlayerViewModel: ObservableObject {
  @Published var isPlaying: Bool = false
  @Published var episodeTitle: String = ""
  @Published var podcastTitle: String = ""
  @Published var imageURL: URL?
  @Published var progress: Double = 0
  @Published var currentTime: TimeInterval = 0
  @Published var duration: TimeInterval = 1
  @Published var playbackSpeed: Float = 1.0
  @Published var currentEpisode: PlaybackEpisode?

  private let audioManager = EnhancedAudioManager.shared
  private var updateTimer: Timer?

  init() {
    setupUpdateTimer()
  }

  private func setupUpdateTimer() {
    updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      self?.updateState()
    }
  }

  private func updateState() {
    if let episode = audioManager.currentEpisode {
      currentEpisode = episode
      isPlaying = audioManager.isPlaying
      episodeTitle = episode.title
      podcastTitle = episode.podcastTitle

      if let imageURLString = episode.imageURL {
        imageURL = URL(string: imageURLString)
      }

      currentTime = audioManager.currentTime
      duration = audioManager.duration
      playbackSpeed = audioManager.playbackRate

      if duration > 0 {
        progress = currentTime / duration
      }
    }
  }

  // MARK: - Computed Properties

  var currentTimeString: String {
    formatTime(currentTime)
  }

  var remainingTimeString: String {
    let remaining = duration - currentTime
    return "-" + formatTime(remaining)
  }

  // MARK: - Actions

  func togglePlayPause() {
    if isPlaying {
      audioManager.pause()
    } else {
      audioManager.resume()
    }
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

  deinit {
    updateTimer?.invalidate()
  }
}
