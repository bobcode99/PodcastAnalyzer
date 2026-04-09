//
//  TogglePlaybackIntent.swift
//  PodcastAnalyzerWidget
//
//  AppIntent for toggling playback from widget button.
//  Conforms to AudioPlaybackIntent so iOS can run it without bringing the app
//  to the foreground. Posts a Darwin notification so the main app process can
//  react immediately when it is alive in the background (audio playing).
//

import AppIntents
import CoreFoundation
import Foundation
import WidgetKit

// MARK: - Resume Playback Intent (opens app — used for play button when app is terminated)

/// Opens the main app and signals it to start playback from saved state.
/// Must use openAppWhenRun = true so iOS launches the app when it is fully terminated.
/// perform() runs in the widget extension process *before* the app opens, so the flag
/// is guaranteed to be in shared UserDefaults by the time handleWidgetToggleOnActive() fires.
struct ResumePlaybackIntent: AppIntent {
  static let title: LocalizedStringResource = "Resume Playback"
  static let description: IntentDescription = "Opens the app and resumes podcast playback"
  static let openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult {
    guard let defaults = WidgetDataManager.sharedDefaults else { return .result() }
    defaults.set(true, forKey: "widgetTogglePlayback")
    defaults.synchronize()
    return .result()
  }
}

// MARK: - Toggle Playback Intent (background only — used for pause button when app is alive)

struct TogglePlaybackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Toggle Playback"
  static let description: IntentDescription = "Play or pause the current episode"
  // Do not open the app – handle in background via Darwin notification
  static let openAppWhenRun: Bool = false

  func perform() async throws -> some IntentResult {
    guard let defaults = WidgetDataManager.sharedDefaults else {
      return .result()
    }
    // Set a flag the main app reads when it becomes active (covers cold-launch case)
    defaults.set(true, forKey: "widgetTogglePlayback")
    defaults.synchronize()
    // Post a Darwin notification so the main app can toggle immediately
    // if it is alive in the background playing audio.
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName("com.jn.PodcastAnalyzer.togglePlayback" as CFString),
      nil, nil, true
    )

    // Optimistically flip isPlaying in shared UserDefaults so the widget
    // re-renders immediately with the correct icon — before the main app
    // has had a chance to write the authoritative state back.
    if let current = WidgetDataManager.readPlaybackData() {
      let optimistic = WidgetPlaybackData(
        episodeTitle: current.episodeTitle,
        podcastTitle: current.podcastTitle,
        imageURL: current.imageURL,
        audioURL: current.audioURL,
        currentTime: current.currentTime,
        duration: current.duration,
        isPlaying: !current.isPlaying,
        lastUpdated: current.lastUpdated
      )
      WidgetDataManager.writePlaybackData(optimistic)
    }

    // Force an immediate re-render with the optimistic state.
    WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
    return .result()
  }
}
