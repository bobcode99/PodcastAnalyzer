//
//  EpisodePlayButtonWithProgress.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/1/4.
//

import Combine
import Foundation
import SwiftData
import SwiftUI

/// A more detailed play button that shows progress information inline
struct EpisodePlayButtonWithProgress: View {
  let isPlaying: Bool
  let isPlayingThisEpisode: Bool
  let isCompleted: Bool
  let playbackProgress: Double
  let duration: TimeInterval?
  let lastPlaybackPosition: TimeInterval
  let formattedDuration: String?
  let isDisabled: Bool
  let action: () -> Void

  init(
    isPlaying: Bool,
    isPlayingThisEpisode: Bool,
    isCompleted: Bool = false,
    playbackProgress: Double = 0,
    duration: TimeInterval? = nil,
    lastPlaybackPosition: TimeInterval = 0,
    formattedDuration: String? = nil,
    isDisabled: Bool = false,
    action: @escaping () -> Void
  ) {
    self.isPlaying = isPlaying
    self.isPlayingThisEpisode = isPlayingThisEpisode
    self.isCompleted = isCompleted
    self.playbackProgress = playbackProgress
    self.duration = duration
    self.lastPlaybackPosition = lastPlaybackPosition
    self.formattedDuration = formattedDuration
    self.isDisabled = isDisabled
    self.action = action
  }

  private var durationText: String? {
    if let dur = duration, dur > 0, playbackProgress > 0, playbackProgress < 1 {
      let remaining = dur - lastPlaybackPosition
      return formatDuration(Int(remaining)) + " left"
    }
    return formattedDuration
  }

  private func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        // Play/Pause/Replay icon
        if isPlayingThisEpisode && isPlaying {
          Image(systemName: "pause.fill")
            .font(.system(size: 9))
        } else if isCompleted {
          Image(systemName: "arrow.counterclockwise")
            .font(.system(size: 9, weight: .bold))
        } else {
          Image(systemName: "play.fill")
            .font(.system(size: 9))
        }

        // Progress bar (only when partially played)
        if playbackProgress > 0 && playbackProgress < 1 {
          GeometryReader { geo in
            ZStack(alignment: .leading) {
              Capsule()
                .fill(Color.white.opacity(0.4))
                .frame(height: 2)
              Capsule()
                .fill(Color.white)
                .frame(width: geo.size.width * playbackProgress, height: 2)
            }
          }
          .frame(width: 24, height: 2)
        }

        // Duration text
        if let duration = durationText {
          Text(duration)
            .font(.system(size: 10))
            .fontWeight(.medium)
        }
      }
      .foregroundColor(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(Color.blue)
      .clipShape(Capsule())
    }
    .buttonStyle(.borderless)
    .disabled(isDisabled)
  }
}

// MARK: - Reactive Play Button for LibraryEpisode

/// A reactive version that observes EnhancedAudioManager for live playback updates
struct ReactiveEpisodePlayButton: View {
  let episode: LibraryEpisode
  let action: () -> Void

  // Observe audioManager to trigger re-renders on playback state changes
  private var audioManager: EnhancedAudioManager { EnhancedAudioManager.shared }

  // Timer for periodic updates during playback
  private static let playbackTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
  @State private var refreshTrigger = false

  init(episode: LibraryEpisode, action: @escaping () -> Void) {
    self.episode = episode
    self.action = action
  }

  private var isPlayingThisEpisode: Bool {
    audioManager.currentEpisode?.title == episode.episodeInfo.title
      && audioManager.currentEpisode?.podcastTitle == episode.podcastTitle
  }

  private var livePlaybackProgress: Double {
    // Use live data if this episode is currently playing
    if isPlayingThisEpisode && audioManager.duration > 0 {
      return audioManager.currentTime / audioManager.duration
    }
    // Fall back to saved progress
    return episode.progress
  }

  private var livePlaybackPosition: TimeInterval {
    if isPlayingThisEpisode {
      return audioManager.currentTime
    }
    return episode.lastPlaybackPosition
  }

  var body: some View {
    EpisodePlayButtonWithProgress(
      isPlaying: audioManager.isPlaying,
      isPlayingThisEpisode: isPlayingThisEpisode,
      isCompleted: episode.isCompleted,
      playbackProgress: livePlaybackProgress,
      duration: episode.episodeInfo.duration.map { TimeInterval($0) },
      lastPlaybackPosition: livePlaybackPosition,
      formattedDuration: episode.episodeInfo.formattedDuration,
      isDisabled: episode.episodeInfo.audioURL == nil,
      action: action
    )
    .onReceive(Self.playbackTimer) { _ in
      // Force refresh during playback
      if isPlayingThisEpisode {
        refreshTrigger.toggle()
      }
    }
    // Access audioManager properties to trigger observation
    .onChange(of: audioManager.isPlaying) { _, _ in }
    .onChange(of: audioManager.currentTime) { _, _ in }
  }
}