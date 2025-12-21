//
//  PlaybackStateCoordinator.swift
//  PodcastAnalyzer
//
//  Coordinates playback position updates between EnhancedAudioManager and SwiftData
//

import Combine
import Foundation
import SwiftData
import os.log

@MainActor
class PlaybackStateCoordinator: ObservableObject {
  static var shared: PlaybackStateCoordinator?

  private var modelContext: ModelContext?
  private var cancellables = Set<AnyCancellable>()
  private let logger = Logger(
    subsystem: "com.podcast.analyzer", category: "PlaybackStateCoordinator")

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
    setupNotificationObserver()
    Self.shared = self  // Keep singleton reference
  }

  private func setupNotificationObserver() {
    NotificationCenter.default.publisher(for: .playbackPositionDidUpdate)
      .compactMap { $0.userInfo?["update"] as? PlaybackPositionUpdate }
      .sink { [weak self] update in
        self?.savePlaybackPosition(update: update)
      }
      .store(in: &cancellables)

    logger.info("Playback state coordinator initialized")
  }

  private func savePlaybackPosition(update: PlaybackPositionUpdate) {
    guard let context = modelContext else { return }

    let id = "\(update.podcastTitle)|\(update.episodeTitle)"
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == id }
    )

    do {
      let results = try context.fetch(descriptor)

      let model: EpisodeDownloadModel
      if let existingModel = results.first {
        // Update existing model
        model = existingModel
        logger.debug("Updating existing episode model: \(update.episodeTitle)")
      } else {
        // Create new model automatically
        logger.info("Creating new episode model for: \(update.episodeTitle)")
        model = EpisodeDownloadModel(
          episodeTitle: update.episodeTitle,
          podcastTitle: update.podcastTitle,
          audioURL: update.audioURL
        )
        context.insert(model)
      }

      // Update playback state
      model.lastPlaybackPosition = update.position
      model.lastPlayedDate = Date()

      // IMPORTANT: Always update duration from the player (this is the actual duration)
      if update.duration > 0 {
        model.duration = update.duration
      }

      // Reset completed status when replaying (position is before 90% of duration)
      // This allows users to re-listen and get fresh progress tracking
      if model.isCompleted && update.duration > 0 {
        let progressRatio = update.position / update.duration
        if progressRatio < 0.9 {
          model.isCompleted = false
          logger.info(
            "Reset completed status for: \(update.episodeTitle) (replay detected at \(Int(progressRatio * 100))%)"
          )
        }
      }

      // Mark as completed if within 30 seconds of end
      if update.duration > 0 && (update.duration - update.position) < 30 {
        model.isCompleted = true
      }

      try context.save()
      logger.info(
        "✅ Saved playback: \(update.episodeTitle) at \(Int(update.position))s / \(Int(update.duration))s"
      )

    } catch {
      logger.error("Failed to save playback position: \(error.localizedDescription)")
    }
  }
}
