//
//  Formatters.swift
//  PodcastAnalyzer
//
//  Shared formatting utilities for playback speed and time display.
//

import Foundation

nonisolated enum Formatters {
  /// Format a playback speed value for display (e.g., 1.0 → "1x", 1.5 → "1.5x", 2.0 → "2x")
  static func formatSpeed(_ speed: Float) -> String {
    if speed == 1.0 {
      return "1x"
    } else if speed.truncatingRemainder(dividingBy: 1) == 0 {
      return "\(Int(speed))x"
    } else {
      return String(format: "%.2gx", speed)
    }
  }

  /// Format a time interval for playback display (e.g., 90 → "1:30", 3661 → "1:01:01")
  static func formatPlaybackTime(_ time: TimeInterval) -> String {
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
}
