//
//  ListeningStatsViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for listening statistics - aggregates SwiftData playback history
//

import Foundation
import Observation
import SwiftData
import OSLog

// MARK: - Time Period

enum TimePeriod: String, CaseIterable, Identifiable {
  case oneMonth = "1M"
  case threeMonths = "3M"
  case oneYear = "1Y"
  case allTime = "All"

  var id: String { rawValue }

  var displayName: String { rawValue }

  var cutoffDate: Date? {
    let calendar = Calendar.current
    switch self {
    case .oneMonth:
      return calendar.date(byAdding: .month, value: -1, to: Date())
    case .threeMonths:
      return calendar.date(byAdding: .month, value: -3, to: Date())
    case .oneYear:
      return calendar.date(byAdding: .year, value: -1, to: Date())
    case .allTime:
      return nil
    }
  }
}

// MARK: - Podcast Listening Stat

struct PodcastListeningStat: Identifiable {
  let id = UUID()
  let podcastTitle: String
  let totalListeningTime: TimeInterval
  let playCount: Int
  let imageURL: String?

  var totalHours: Double {
    totalListeningTime / 3600.0
  }
}

// MARK: - ViewModel

@MainActor
@Observable
final class ListeningStatsViewModel {
  var selectedTimePeriod: TimePeriod = .allTime
  var totalHoursListened: Double = 0
  var totalEpisodesPlayed: Int = 0
  var topPodcasts: [PodcastListeningStat] = []
  var isLoading = false

  @ObservationIgnored
  private var modelContext: ModelContext?

  @ObservationIgnored
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "ListeningStatsViewModel")

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    loadStats()
  }

  func loadStats() {
    guard let context = modelContext else { return }
    isLoading = true

    let cutoff = selectedTimePeriod.cutoffDate

    // Fetch all EpisodeDownloadModel sorted by lastPlayedDate descending
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      sortBy: [SortDescriptor(\.lastPlayedDate, order: .reverse)]
    )

    do {
      let allModels = try context.fetch(descriptor)

      // Filter: has been played + within time period
      let filtered = allModels.filter { model in
        let hasBeenPlayed = model.playCount > 0 || model.lastPlayedDate != nil
        guard hasBeenPlayed else { return false }

        if let cutoff {
          return (model.lastPlayedDate ?? .distantPast) >= cutoff
        }
        return true
      }

      // Total episodes played
      totalEpisodesPlayed = filtered.count

      // Total hours listened: sum of min(lastPlaybackPosition, duration) * max(playCount, 1)
      var totalSeconds: TimeInterval = 0
      var podcastGroups: [String: (time: TimeInterval, count: Int, imageURL: String?)] = [:]

      for model in filtered {
        let effectiveDuration: TimeInterval
        if model.duration > 0 {
          effectiveDuration = min(model.lastPlaybackPosition, model.duration)
        } else {
          effectiveDuration = model.lastPlaybackPosition
        }
        let listeningTime = effectiveDuration * Double(max(model.playCount, 1))
        totalSeconds += listeningTime

        // Group by podcast title
        let title = model.podcastTitle
        let existing = podcastGroups[title] ?? (time: 0, count: 0, imageURL: model.imageURL)
        podcastGroups[title] = (
          time: existing.time + listeningTime,
          count: existing.count + max(model.playCount, 1),
          imageURL: existing.imageURL ?? model.imageURL
        )
      }

      totalHoursListened = totalSeconds / 3600.0

      // Top 3 podcasts sorted by listening time
      topPodcasts = podcastGroups
        .map { PodcastListeningStat(podcastTitle: $0.key, totalListeningTime: $0.value.time, playCount: $0.value.count, imageURL: $0.value.imageURL) }
        .sorted { $0.totalListeningTime > $1.totalListeningTime }
        .prefix(3)
        .map { $0 }

      logger.info("Stats loaded: \(self.totalEpisodesPlayed) episodes, \(String(format: "%.1f", self.totalHoursListened))h, \(self.topPodcasts.count) top podcasts")
    } catch {
      logger.error("Failed to load listening stats: \(error.localizedDescription)")
    }

    isLoading = false
  }
}
