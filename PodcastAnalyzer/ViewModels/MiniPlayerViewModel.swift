//
//  MiniPlayerViewModel.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//

import Combine
import SwiftUI

class MiniPlayerViewModel: ObservableObject {
  @Published var isVisible: Bool = false
  @Published var isPlaying: Bool = false
  @Published var episodeTitle: String = ""
  @Published var podcastTitle: String = ""
  @Published var imageURL: URL?
  @Published var progress: Double = 0
  @Published var currentEpisode: PlaybackEpisode?

  private let audioManager = EnhancedAudioManager.shared
  private var updateTimer: Timer?

  init() {
    setupUpdateTimer()
  }

  private func setupUpdateTimer() {
    updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      self?.updateState()
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

  deinit {
    updateTimer?.invalidate()
  }
}
