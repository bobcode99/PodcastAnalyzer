//
//  PlaybackStateCoordinator.swift
//  PodcastAnalyzer
//
//  Coordinates playback position updates between EnhancedAudioManager and SwiftData
//

import Foundation
import SwiftData
import Combine
import os.log

@MainActor
class PlaybackStateCoordinator: ObservableObject {
    static var shared: PlaybackStateCoordinator?

    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "PlaybackStateCoordinator")

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

            if let model = results.first {
                // Update existing model
                model.lastPlaybackPosition = update.position
                model.lastPlayedDate = Date()

                // Mark as completed if within 30 seconds of end
                if update.duration > 0 && (update.duration - update.position) < 30 {
                    model.isCompleted = true
                }
            } else {
                // Create new model - we need the audioURL but don't have it in the update
                // For now, skip creation if model doesn't exist
                logger.debug("No existing episode model found for: \(update.episodeTitle)")
                return
            }

            try context.save()
            logger.debug("Saved playback position: \(update.episodeTitle) at \(update.position)s")

        } catch {
            logger.error("Failed to save playback position: \(error.localizedDescription)")
        }
    }
}
