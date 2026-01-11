//
//  EpisodePlayButton.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/1/4.
//

import Foundation
import SwiftData
import SwiftUI

/// Reusable play button with progress indicator
/// Shows play/pause/replay icon, progress bar when partially played, and duration text
struct EpisodePlayButton: View {
  /// Whether the audio manager is currently playing
  let isPlaying: Bool
  /// Whether this specific episode is the current one in the audio manager
  let isPlayingThisEpisode: Bool
  /// Whether the episode has been completed
  let isCompleted: Bool
  /// Playback progress (0.0 to 1.0)
  let playbackProgress: Double
  /// Total duration in seconds (optional)
  let duration: TimeInterval?
  /// Last playback position in seconds
  let lastPlaybackPosition: TimeInterval
  /// Formatted duration string (e.g., "45m") - used when no progress
  let formattedDuration: String?
  /// Whether the button should be disabled (e.g., no audio URL)
  let isDisabled: Bool
  /// Style variant for different contexts
  let style: PlayButtonStyle
  /// Action to perform when tapped
  let action: () -> Void

  enum PlayButtonStyle {
    case compact      // For list rows (smaller, capsule shape)
    case standard     // For detail views (larger, bordered prominent)
  }

  init(
    isPlaying: Bool,
    isPlayingThisEpisode: Bool,
    isCompleted: Bool = false,
    playbackProgress: Double = 0,
    duration: TimeInterval? = nil,
    lastPlaybackPosition: TimeInterval = 0,
    formattedDuration: String? = nil,
    isDisabled: Bool = false,
    style: PlayButtonStyle = .compact,
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
    self.style = style
    self.action = action
  }

  /// Convenience initializer from EpisodeDownloadModel data
  init(
    audioManager: EnhancedAudioManager,
    episodeTitle: String,
    podcastTitle: String,
    episodeModel: EpisodeDownloadModel?,
    formattedDuration: String?,
    isDisabled: Bool = false,
    style: PlayButtonStyle = .compact,
    action: @escaping () -> Void
  ) {
    let isPlayingThis = audioManager.currentEpisode?.title == episodeTitle
      && audioManager.currentEpisode?.podcastTitle == podcastTitle

    self.isPlaying = audioManager.isPlaying
    self.isPlayingThisEpisode = isPlayingThis
    self.isCompleted = episodeModel?.isCompleted ?? false
    self.playbackProgress = episodeModel?.progress ?? 0
    self.duration = episodeModel?.duration
    self.lastPlaybackPosition = episodeModel?.lastPlaybackPosition ?? 0
    self.formattedDuration = formattedDuration
    self.isDisabled = isDisabled
    self.style = style
    self.action = action
  }

  private var durationText: String? {
      // Determine which value to format: remaining time or total duration
      let isInProgress = playbackProgress > 0 && playbackProgress < 1

      // If we have duration from the model, use it for precise calculation
      if let totalSeconds = duration, totalSeconds > 0 {
          let secondsToFormat = isInProgress ? (totalSeconds - lastPlaybackPosition) : totalSeconds
          let timeString = formatTimeUnits(Int(secondsToFormat))
          return isInProgress ? "\(timeString) left" : timeString
      }

      // Fallback to formatted duration from episode metadata (for unplayed episodes)
      return formattedDuration
  }

  private func formatTimeUnits(_ totalSeconds: Int) -> String {
      let seconds = max(0, totalSeconds)
      let h = seconds / 3600
      let m = (seconds % 3600) / 60
      let s = seconds % 60

      if h > 0 {
          // "1h 5m"
          return "\(h)h \(m)m"
      } else if m > 0 {
          // "50m"
          return "\(m)m"
      } else {
          // "0:44"
          return String(format: "0:%02d", s)
      }
  }

  var body: some View {
    switch style {
    case .compact:
      compactButton
    case .standard:
      standardButton
    }
  }

  // MARK: - Compact Style (for list rows)

  private var compactButton: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        // Icon
        playIcon(size: 9)

        // Progress bar (only show when partially played)
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

  // MARK: - Standard Style (for detail views)

  private var standardButton: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        playIcon(size: 12)
        Text(buttonLabel)
          .font(.caption)
          .fontWeight(.medium)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
    }
    .buttonStyle(.borderedProminent)
    .disabled(isDisabled)
  }

  // MARK: - Helpers

  @ViewBuilder
  private func playIcon(size: CGFloat) -> some View {
    if isPlayingThisEpisode && isPlaying {
      Image(systemName: "pause.fill")
        .font(.system(size: size))
    } else if isCompleted {
      Image(systemName: "arrow.counterclockwise")
        .font(.system(size: size, weight: .bold))
    } else {
      Image(systemName: "play.fill")
        .font(.system(size: size))
    }
  }

  private var buttonLabel: String {
    if isPlayingThisEpisode && isPlaying {
      return "Pause"
    } else if isCompleted {
      return "Replay"
    } else {
      return "Play"
    }
  }
}
