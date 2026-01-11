//
//  MiniPlayerViewModel.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//

import SwiftUI

@MainActor
@Observable
final class MiniPlayerViewModel {
  var isVisible: Bool = false
  var isPlaying: Bool = false
  var episodeTitle: String = ""
  var podcastTitle: String = ""
  var imageURL: URL?
  var progress: Double = 0
  var currentEpisode: PlaybackEpisode?

  private let audioManager = EnhancedAudioManager.shared
  private var updateTimer: Timer?

  init() {
    setupUpdateTimer()
  }

  private func setupUpdateTimer() {
    updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor [weak self] in
        self?.updateState()
      }
    }
  }

  private func updateState() {
    if let episode = audioManager.currentEpisode {
      isVisible = true
      currentEpisode = episode
      isPlaying = audioManager.isPlaying
      episodeTitle = episode.title
      podcastTitle = episode.podcastTitle

      if let imageURLString = episode.imageURL {
        imageURL = URL(string: imageURLString)
      }

      let duration = audioManager.duration
      if duration > 0 {
        progress = audioManager.currentTime / duration
      }
    } else {
      isVisible = false
    }
  }

  func togglePlayPause() {
    if isPlaying {
      audioManager.pause()
    } else {
      audioManager.resume()
    }
  }

  /// Clean up resources. Call this from onDisappear.
  func cleanup() {
    updateTimer?.invalidate()
    updateTimer = nil
  }
}
