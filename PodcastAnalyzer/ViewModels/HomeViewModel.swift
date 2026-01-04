//
//  HomeViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for Home tab - manages Up Next episodes and Popular Shows from Apple
//

import Foundation
import Observation
import SwiftData
import SwiftUI
import os.log

@MainActor
@Observable
final class HomeViewModel {
  // Up Next episodes (unplayed from subscribed podcasts)
  var upNextEpisodes: [LibraryEpisode] = []

  // Top podcasts from Apple RSS
  var topPodcasts: [AppleRSSPodcast] = []
  var isLoadingTopPodcasts = false

  // Region selection - synced with Settings
  var selectedRegion: String = "us" {
    didSet {
      if oldValue != selectedRegion {
        // Save to UserDefaults for consistency
        UserDefaults.standard.set(selectedRegion, forKey: "selectedPodcastRegion")
        Task { await loadTopPodcasts() }
      }
    }
  }

  // Podcast preview/subscription
  var selectedPodcast: AppleRSSPodcast?
  var isSubscribing = false
  var subscriptionError: String?
  var subscriptionSuccess = false

  @ObservationIgnored
  private var podcastInfoModelList: [PodcastInfoModel] = []

  @ObservationIgnored
  private let applePodcastService = ApplePodcastService()

  @ObservationIgnored
  private let rssService = PodcastRssService()

  @ObservationIgnored
  private var modelContext: ModelContext?

  @ObservationIgnored
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "HomeViewModel")

  // Flag to prevent redundant loads
  @ObservationIgnored
  private var isAlreadyLoaded = false

  // Task for region change observation
  @ObservationIgnored
  private var regionObserverTask: Task<Void, Never>?

  // Use Unit Separator (U+001F) as delimiter
  private static let episodeKeyDelimiter = "\u{1F}"

  var selectedRegionName: String {
    Constants.podcastRegions.first { $0.code == selectedRegion }?.name ?? selectedRegion.uppercased()
  }

  init() {
    // Restore saved region preference
    if let saved = UserDefaults.standard.string(forKey: "selectedPodcastRegion") {
      selectedRegion = saved
    }

    // Listen for region changes from Settings using async sequence
    regionObserverTask = Task {
      for await notification in NotificationCenter.default.notifications(named: .podcastRegionChanged) {
        if let newRegion = notification.object as? String {
          selectedRegion = newRegion
        }
      }
    }
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    // Only load if we haven't or if we need a fresh start
    if !isAlreadyLoaded {
      Task {
        await loadAll()
        isAlreadyLoaded = true
      }
    }
  }

  // MARK: - Load All Data

  private func loadAll() async {
    // Load feeds first, then episodes (episodes depend on feeds)
    await loadPodcastFeeds()
    // Load up next and top podcasts can run in parallel via async let
    async let upNextTask: () = loadUpNextEpisodes()
    async let topPodcastsTask: () = loadTopPodcasts()
    _ = await (upNextTask, topPodcastsTask)
  }

  func refresh() async {
    await loadAll()
  }

  // MARK: - Load Podcasts

  private func loadPodcastFeeds() async {
    guard let context = modelContext else { return }

    // Only load subscribed podcasts (not browsed/cached ones)
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.isSubscribed == true },
      sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
    )

    do {
      podcastInfoModelList = try context.fetch(descriptor)
      logger.info("Loaded \(self.podcastInfoModelList.count) subscribed podcasts")
    } catch {
      logger.error("Failed to load podcasts: \(error.localizedDescription)")
    }
  }

  // MARK: - Up Next Episodes

  private func loadUpNextEpisodes() async {
    guard let context = modelContext else { return }

    // Get up to 20 most recent unplayed episodes from subscribed podcasts
    var allEpisodes: [LibraryEpisode] = []

    for podcastModel in podcastInfoModelList {
      let podcastTitle = podcastModel.podcastInfo.title

      // Get recent episodes (limit 10 per podcast for performance)
      for episode in podcastModel.podcastInfo.episodes.prefix(10) {
        let key = Self.makeEpisodeKey(podcastTitle: podcastTitle, episodeTitle: episode.title)

        // Check if episode is completed
        let descriptor = FetchDescriptor<EpisodeDownloadModel>(
          predicate: #Predicate { $0.id == key }
        )

        let model = try? context.fetch(descriptor).first

        // Only include unplayed episodes
        if model?.isCompleted != true {
          allEpisodes.append(LibraryEpisode(
            id: key,
            podcastTitle: podcastTitle,
            imageURL: episode.imageURL ?? podcastModel.podcastInfo.imageURL,
            language: podcastModel.podcastInfo.language,
            episodeInfo: episode,
            isStarred: model?.isStarred ?? false,
            isDownloaded: model?.localAudioPath != nil,
            isCompleted: model?.isCompleted ?? false,
            lastPlaybackPosition: model?.lastPlaybackPosition ?? 0
          ))
        }
      }
    }

    // Sort by date (newest first) and limit
    allEpisodes.sort { ($0.episodeInfo.pubDate ?? .distantPast) > ($1.episodeInfo.pubDate ?? .distantPast) }
    upNextEpisodes = Array(allEpisodes.prefix(20))
    logger.info("Loaded \(self.upNextEpisodes.count) up next episodes")
  }

  private static func makeEpisodeKey(podcastTitle: String, episodeTitle: String) -> String {
    "\(podcastTitle)\(episodeKeyDelimiter)\(episodeTitle)"
  }

  // MARK: - Episode Actions

  /// Play an episode - delegate to audio manager
  func playEpisode(_ episode: LibraryEpisode) {
    let audioURL = episode.episodeInfo.audioURL ?? ""
    let playbackEpisode = PlaybackEpisode(
      id: episode.id,
      title: episode.episodeInfo.title,
      podcastTitle: episode.podcastTitle,
      audioURL: audioURL,
      imageURL: episode.imageURL,
      duration: episode.episodeInfo.duration,
      guid: episode.episodeInfo.guid
    )
    EnhancedAudioManager.shared.play(
      episode: playbackEpisode,
      audioURL: audioURL,
      imageURL: episode.imageURL
    )
  }

  /// Mark episode as played and remove from Up Next
  func markAsPlayed(_ episode: LibraryEpisode) {
    guard let context = modelContext else { return }

    let key = Self.makeEpisodeKey(podcastTitle: episode.podcastTitle, episodeTitle: episode.episodeInfo.title)
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == key }
    )

    if let model = try? context.fetch(descriptor).first {
      model.isCompleted = true
    } else {
      // Create new model if doesn't exist
      let model = EpisodeDownloadModel(
        episodeTitle: episode.episodeInfo.title,
        podcastTitle: episode.podcastTitle,
        audioURL: episode.episodeInfo.audioURL ?? "",
        isCompleted: true,
        imageURL: episode.imageURL,
        pubDate: episode.episodeInfo.pubDate
      )
      context.insert(model)
      try? context.save()
    }
    // Reload to reflect changes (episode will disappear from Up Next when marked as played)
    Task {
      await loadUpNextEpisodes()
    }
  }

  // MARK: - Load Top Podcasts

  private func loadTopPodcasts() async {
    isLoadingTopPodcasts = true

    do {
      let podcasts = try await applePodcastService.fetchTopPodcasts(region: selectedRegion, limit: 25)
      topPodcasts = podcasts
      logger.info("Loaded \(podcasts.count) top podcasts for \(self.selectedRegion)")
    } catch {
      logger.error("Failed to load top podcasts: \(error.localizedDescription)")
    }

    isLoadingTopPodcasts = false
  }

  // MARK: - Podcast Preview

  func showPodcastPreview(_ podcast: AppleRSSPodcast) {
    selectedPodcast = podcast
    subscriptionError = nil
    subscriptionSuccess = false
  }

  /// Check if a podcast is already subscribed by name
  func isAlreadySubscribed(_ podcast: AppleRSSPodcast) -> Bool {
    podcastInfoModelList.contains { $0.podcastInfo.title == podcast.name }
  }

  // MARK: - Subscribe to Podcast

  func subscribeToPodcast(_ podcast: AppleRSSPodcast) {
    guard let context = modelContext else {
      subscriptionError = "Unable to save"
      return
    }

    isSubscribing = true
    subscriptionError = nil
    subscriptionSuccess = false

    Task {
      do {
        // Look up the podcast to get the RSS feed URL
        guard let result = try await applePodcastService.lookupPodcast(collectionId: podcast.id),
              let feedUrl = result.feedUrl else {
          subscriptionError = "Could not find RSS feed"
          isSubscribing = false
          return
        }

        // Fetch podcast info from RSS
        let podcastInfo = try await rssService.fetchPodcast(from: feedUrl)

        // Check if already subscribed
        let title = podcastInfo.title
        let existingDescriptor = FetchDescriptor<PodcastInfoModel>(
          predicate: #Predicate { $0.podcastInfo.title == title }
        )

        if (try? context.fetch(existingDescriptor).first) != nil {
          logger.info("Already subscribed to \(podcastInfo.title)")
          subscriptionSuccess = true
          isSubscribing = false
          return
        }

        // Create new subscription (explicitly set isSubscribed to true)
        let model = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date(), isSubscribed: true)
        context.insert(model)

        try context.save()
        podcastInfoModelList.insert(model, at: 0)
        await loadUpNextEpisodes()
        subscriptionSuccess = true
        logger.info("Successfully subscribed to \(podcastInfo.title)")

      } catch {
        subscriptionError = error.localizedDescription
        logger.error("Failed to subscribe: \(error.localizedDescription)")
      }

      isSubscribing = false
    }
  }

  func cleanup() {
    regionObserverTask?.cancel()
    regionObserverTask = nil
  }

  // MARK: - Find Podcast Model

  func findPodcastModel(for podcastTitle: String) -> PodcastInfoModel? {
    podcastInfoModelList.first { $0.podcastInfo.title == podcastTitle }
  }

  // MARK: - Star/Unstar Episode

  func toggleStar(for episode: LibraryEpisode) {
    guard let context = modelContext else { return }

    let key = Self.makeEpisodeKey(podcastTitle: episode.podcastTitle, episodeTitle: episode.episodeInfo.title)
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == key }
    )

    if let model = try? context.fetch(descriptor).first {
      model.isStarred.toggle()
      try? context.save()
    } else {
      // Create new model if doesn't exist
      let model = EpisodeDownloadModel(
        episodeTitle: episode.episodeInfo.title,
        podcastTitle: episode.podcastTitle,
        audioURL: episode.episodeInfo.audioURL ?? "",
        isStarred: true,
        imageURL: episode.imageURL,
        pubDate: episode.episodeInfo.pubDate
      )
      context.insert(model)
      try? context.save()
    }
  }

  // MARK: - Mark Played/Unplayed Episode

  func togglePlayed(for episode: LibraryEpisode) {
    guard let context = modelContext else { return }

    let key = Self.makeEpisodeKey(podcastTitle: episode.podcastTitle, episodeTitle: episode.episodeInfo.title)
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == key }
    )

    if let model = try? context.fetch(descriptor).first {
      model.isCompleted.toggle()
      try? context.save()
    } else {
      // Create new model if doesn't exist
      let model = EpisodeDownloadModel(
        episodeTitle: episode.episodeInfo.title,
        podcastTitle: episode.podcastTitle,
        audioURL: episode.episodeInfo.audioURL ?? "",
        isCompleted: true,
        imageURL: episode.imageURL,
        pubDate: episode.episodeInfo.pubDate
      )
      context.insert(model)
      try? context.save()
    }

    // Reload to reflect changes
    Task {
      await loadUpNextEpisodes()
    }
  }
}
