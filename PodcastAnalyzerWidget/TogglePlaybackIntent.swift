//
//  TogglePlaybackIntent.swift
//  PodcastAnalyzerWidget
//
//  AppIntent for toggling playback from widget button
//

import AppIntents
import Foundation

struct TogglePlaybackIntent: AppIntent {
  static let title: LocalizedStringResource = "Toggle Playback"
  static let description: IntentDescription = "Play or pause the current episode"
  static let openAppWhenRun: Bool = true

  func perform() async throws -> some IntentResult {
    guard let defaults = WidgetDataManager.sharedDefaults else {
      return .result()
    }
    // Set a flag that the main app will pick up when it becomes active
    defaults.set(true, forKey: "widgetTogglePlayback")
    return .result()
  }
}
