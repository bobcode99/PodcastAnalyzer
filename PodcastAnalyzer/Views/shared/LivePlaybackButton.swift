//
//  LivePlaybackButton.swift
//  PodcastAnalyzer
//
//  Unified play button component that directly observes EnhancedAudioManager
//  for live playback state - no polling needed.
//

import SwiftUI

/// Unified play button that shows live playback state by directly observing the audio manager.
/// Falls back to SwiftData values when the episode is not currently playing.
@MainActor
struct LivePlaybackButton: View {
  // MARK: - Episode Identity
  
  /// Episode title for matching with audio manager
  let episodeTitle: String
  /// Podcast title for matching with audio manager
  let podcastTitle: String
  
  // MARK: - Episode Metadata (fallback when not playing)
  
  /// Duration in seconds from episode metadata
  let duration: TimeInterval?
  /// Formatted duration string (e.g., "45m") - used when no progress
  let formattedDuration: String?
  /// Last saved playback position from SwiftData
  var lastPlaybackPosition: TimeInterval = 0
  /// Saved progress (0.0 to 1.0) from SwiftData
  var playbackProgress: Double = 0
  /// Whether the episode has been completed
  var isCompleted: Bool = false
  
  // MARK: - Actions
  
  /// Action to perform when play/pause button is tapped
  let onPlay: () -> Void
  
  // MARK: - Style
  
  /// Visual style variant
  var style: ButtonStyle = .compact
  
  /// Whether the button should be disabled (e.g., no audio URL)
  var isDisabled: Bool = false
  
  enum ButtonStyle {
    case compact      // For list rows (smaller, capsule shape)
    case standard     // For detail views (larger, bordered prominent)
    case iconOnly     // Icon + duration only, capsule with semantic color
  }
  
  // MARK: - Live State from AudioManager
  
  @State private var audioManager = EnhancedAudioManager.shared
  
  /// Unique key for this episode (matches episodeKey format)
  private var episodeKey: String {
    "\(podcastTitle)\u{1F}\(episodeTitle)"
  }
  
  /// Whether this episode is currently loaded in the audio manager
  private var isCurrentEpisode: Bool {
    audioManager.currentEpisode?.id == episodeKey
  }
  
  /// Whether this episode is currently playing
  private var isPlayingThisEpisode: Bool {
    isCurrentEpisode && audioManager.isPlaying
  }
  
  /// Live progress - from audio manager if playing, otherwise from SwiftData
  private var liveProgress: Double {
    if isCurrentEpisode, audioManager.duration > 0 {
      return audioManager.currentTime / audioManager.duration
    }
    return playbackProgress
  }
  
  /// Live position - from audio manager if playing, otherwise from SwiftData
  private var livePosition: TimeInterval {
    if isCurrentEpisode {
      return audioManager.currentTime
    }
    return lastPlaybackPosition
  }
  
  /// Live duration - from audio manager if playing, otherwise from metadata
  private var liveDuration: TimeInterval? {
    if isCurrentEpisode, audioManager.duration > 0 {
      return audioManager.duration
    }
    return duration
  }
  
  /// Computed duration text for display
  private var durationText: String? {
    let isInProgress = liveProgress > 0 && liveProgress < 1
    
    // If we have duration, use it for precise calculation
    if let totalSeconds = liveDuration, totalSeconds > 0 {
      let secondsToFormat = isInProgress ? (totalSeconds - livePosition) : totalSeconds
      let timeString = formatTimeUnits(Int(secondsToFormat))
      return isInProgress ? "\(timeString) left" : timeString
    }
    
    // Fallback to formatted duration from episode metadata (for unplayed episodes)
    return formattedDuration
  }
  
  // MARK: - Body
  
  var body: some View {
    switch style {
    case .compact:
      compactButton
    case .standard:
      standardButton
    case .iconOnly:
      iconOnlyButton
    }
  }
  
  // MARK: - Compact Style (for list rows)
  
  private var compactButton: some View {
    Button(action: onPlay) {
      HStack(spacing: 4) {
        // Icon
        playIcon(size: 9)
        
        // Progress bar (only show when partially played)
        if liveProgress > 0 && liveProgress < 1 {
          ProgressView(value: liveProgress)
            .progressViewStyle(.linear)
            .tint(.white)
            .frame(width: 24)
        }
        
        // Duration text
        if let duration = durationText {
          Text(duration)
            .font(.system(size: 10))
            .fontWeight(.medium)
        }
      }
      .foregroundStyle(.white)
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
    Button(action: onPlay) {
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
  
  // MARK: - Icon Only Style (capsule with icon, progress bar, and duration)
  
  private var iconOnlyButton: some View {
    Button(action: onPlay) {
      HStack(spacing: 6) {
        playIcon(size: 14)
        
        // Progress bar (only show when partially played)
        if liveProgress > 0 && liveProgress < 1 {
          ProgressView(value: liveProgress)
            .progressViewStyle(.linear)
            .tint(.white)
            .frame(width: 32)
        }
        
        if let duration = durationText {
          Text(duration)
            .font(.caption)
            .fontWeight(.medium)
        }
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(Color.blue)
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
  }
  
  // MARK: - Helpers
  
  @ViewBuilder
  private func playIcon(size: CGFloat) -> some View {
    if isPlayingThisEpisode {
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
    if isPlayingThisEpisode {
      return "Pause"
    } else if isCompleted {
      return "Replay"
    } else {
      return "Play"
    }
  }
  
  /// Format seconds into human-readable time units
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
}

// MARK: - Convenience Initializer for LibraryEpisode

extension LivePlaybackButton {
  /// Convenience initializer for LibraryEpisode (used in UpNext, Library views)
  init(
    episode: LibraryEpisode,
    isDisabled: Bool = false,
    style: ButtonStyle = .compact,
    action: @escaping () -> Void
  ) {
    self.episodeTitle = episode.episodeInfo.title
    self.podcastTitle = episode.podcastTitle
    self.duration = episode.episodeInfo.duration.map { TimeInterval($0) }
    self.formattedDuration = episode.episodeInfo.formattedDuration
    self.lastPlaybackPosition = episode.lastPlaybackPosition
    self.playbackProgress = episode.progress
    self.isCompleted = episode.isCompleted
    self.isDisabled = isDisabled || episode.episodeInfo.audioURL == nil
    self.style = style
    self.onPlay = action
  }
}
