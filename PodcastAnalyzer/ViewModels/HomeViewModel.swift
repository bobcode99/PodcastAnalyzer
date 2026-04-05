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
import OSLog

@MainActor
@Observable
final class HomeViewModel {
  // Static cache shared across all instances to prevent duplicate API calls
  private static var cachedTopPodcasts: [AppleRSSPodcast] = []
  private static var cachedRegion: String = ""
  // Replace boolean flag with Task to allow joining
  private static var loadingTask: Task<[AppleRSSPodcast], Error>?
  private static var loadingRegion: String?

  // Up Next episodes (unplayed from subscribed podcasts)
  var upNextEpisodes: [LibraryEpisode] = []
  // Scored version — used by HomeView cards to show reason badges
  var scoredUpNextEpisodes: [ScoredEpisode] = []

  // Top podcasts from Apple RSS - observable instance properties that sync with static cache
  var topPodcasts: [AppleRSSPodcast] = []
  var isLoadingTopPodcasts = false

  // Region selection - synced with Settings
  var selectedRegion: String = "us" {
    didSet {
      if oldValue != selectedRegion {
        // Save to UserDefaults for consistency
        UserDefaults.standard.set(selectedRegion, forKey: "selectedPodcastRegion")
        Task { await loadTopPodcasts(forceRefresh: true) }
      }
    }
  }

  // For You recommendations (on-device AI)
  var recommendations: EpisodeRecommendations?
  var isLoadingRecommendations = false
  var recommendedEpisodes: [LibraryEpisode] = []

  @ObservationIgnored
  private var recommendationsTask: Task<Void, Never>?

  @ObservationIgnored
  private var loadTask: Task<Void, Never>?

  @ObservationIgnored
  private var subscribeTask: Task<Void, Never>?

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
    if let region = Constants.podcastRegions.first(where: { $0.code == selectedRegion }) {
      return "\(region.flag) \(region.name)"
    }
    return selectedRegion.uppercased()
  }

  var selectedRegionFlag: String {
    Constants.podcastRegions.first { $0.code == selectedRegion }?.flag ?? "🌍"
  }

  init() {
    // Restore saved region preference
    if let saved = UserDefaults.standard.string(forKey: "selectedPodcastRegion") {
      selectedRegion = saved
    }

    // Restore from static cache if available for current region
    if !Self.cachedTopPodcasts.isEmpty && Self.cachedRegion == selectedRegion {
      topPodcasts = Self.cachedTopPodcasts
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
      isAlreadyLoaded = true  // Set immediately to prevent race condition
      loadTask = Task {
        await loadAll()
      }
    }
  }

  // MARK: - Load All Data

  private func loadAll(forceRefresh: Bool = false) async {
    // Load feeds first, then episodes (episodes depend on feeds)
    await loadPodcastFeeds()
    // Load up next and top podcasts can run in parallel via async let
    async let upNextTask: () = loadUpNextEpisodes()
    async let topPodcastsTask: () = loadTopPodcasts(forceRefresh: forceRefresh)
    _ = await (upNextTask, topPodcastsTask)

    // Load recommendations after feeds are loaded
    if #available(iOS 26.0, macOS 26.0, *) {
      loadRecommendations()
    }
  }

  func refresh() async {
    await loadAll(forceRefresh: true)
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

    // Batch fetch all EpisodeDownloadModels once (instead of N+1 individual queries)
    let allDescriptor = FetchDescriptor<EpisodeDownloadModel>()
    let allModels = (try? context.fetch(allDescriptor)) ?? []
    var modelsByKey: [String: EpisodeDownloadModel] = [:]
    for model in allModels {
      modelsByKey[model.id] = model
    }

    // Compute per-podcast aggregates from the already-fetched allModels.
    // These are the engagement signals used by UpNextSuggestionEngine.
    var podcastPlayCounts: [String: Int] = [:]
    var podcastRecentPlayDates: [String: Date] = [:]
    for model in allModels {
      podcastPlayCounts[model.podcastTitle, default: 0] += model.playCount
      if let d = model.lastPlayedDate {
        if let existing = podcastRecentPlayDates[model.podcastTitle] {
          if d > existing { podcastRecentPlayDates[model.podcastTitle] = d }
        } else {
          podcastRecentPlayDates[model.podcastTitle] = d
        }
      }
    }

    // Build EpisodeInput candidates (unplayed, up to 10 per podcast)
    var inputs: [EpisodeInput] = []

    for podcastModel in podcastInfoModelList {
      let podcastTitle = podcastModel.podcastInfo.title

      for episode in podcastModel.podcastInfo.episodes.prefix(10) {
        let key = Self.makeEpisodeKey(podcastTitle: podcastTitle, episodeTitle: episode.title)
        let model = modelsByKey[key]

        // Skip completed episodes
        guard model?.isCompleted != true else { continue }

        let libraryEpisode = LibraryEpisode(
          id: key,
          podcastTitle: podcastTitle,
          imageURL: episode.imageURL ?? podcastModel.podcastInfo.imageURL,
          language: podcastModel.podcastInfo.language,
          episodeInfo: episode,
          isStarred: model?.isStarred ?? false,
          isDownloaded: Self.hasLocalAudioFile(model?.localAudioPath),
          isCompleted: model?.isCompleted ?? false,
          lastPlaybackPosition: model?.lastPlaybackPosition ?? 0,
          savedDuration: model?.duration ?? 0
        )

        inputs.append(EpisodeInput(
          episode: libraryEpisode,
          downloadModel: model,
          podcastTotalPlayCount: podcastPlayCounts[podcastTitle] ?? 0,
          podcastMostRecentPlayDate: podcastRecentPlayDates[podcastTitle]
        ))
      }
    }

    // Score and rank via UpNextSuggestionEngine
    let scored = UpNextSuggestionEngine().score(inputs: inputs, limit: 25)
    scoredUpNextEpisodes = scored
    var result = scored.map(\.episode).prefix(20).map { $0 }

    // Ensure the currently playing episode is at the top of Up Next
    if let currentEpisode = EnhancedAudioManager.shared.currentEpisode {
      let currentKey = Self.makeEpisodeKey(podcastTitle: currentEpisode.podcastTitle, episodeTitle: currentEpisode.title)
      let currentModel = modelsByKey[currentKey]

      // Don't add if already completed
      if currentModel?.isCompleted != true {
        if let existingIndex = result.firstIndex(where: { $0.id == currentKey }) {
          // Already in list — move to top
          let episode = result.remove(at: existingIndex)
          result.insert(episode, at: 0)
        } else {
          // Not in list (non-subscribed podcast or beyond prefix limit) — create and insert at top
          let episodeInfo = PodcastEpisodeInfo(
            title: currentEpisode.title,
            podcastEpisodeDescription: currentEpisode.episodeDescription,
            pubDate: currentEpisode.pubDate,
            audioURL: currentEpisode.audioURL,
            imageURL: currentEpisode.imageURL,
            duration: currentEpisode.duration,
            guid: currentEpisode.guid
          )
          let libraryEpisode = LibraryEpisode(
            id: currentKey,
            podcastTitle: currentEpisode.podcastTitle,
            imageURL: currentEpisode.imageURL,
            language: "",
            episodeInfo: episodeInfo,
            isStarred: currentModel?.isStarred ?? false,
            isDownloaded: Self.hasLocalAudioFile(currentModel?.localAudioPath),
            isCompleted: false,
            lastPlaybackPosition: currentModel?.lastPlaybackPosition ?? 0,
            savedDuration: currentModel?.duration ?? 0
          )
          result.insert(libraryEpisode, at: 0)
        }
      }
    }

    upNextEpisodes = result
    // Keep scoredUpNextEpisodes in sync so HomeView cards can read reasons.
    // Re-map from the reordered result so the pinned current episode stays first.
    let scoredById = Dictionary(uniqueKeysWithValues: scored.map { ($0.id, $0) })
    scoredUpNextEpisodes = result.map { episode in
      scoredById[episode.id] ?? ScoredEpisode(
        episode: episode,
        downloadModel: modelsByKey[episode.id],
        score: 0,
        reason: .none,
        progressRatio: 0
      )
    }
    logger.info("Loaded \(self.upNextEpisodes.count) up next episodes")

    // Populate auto-play candidates from up next episodes
    let autoPlayEpisodes = upNextEpisodes.compactMap { episode -> PlaybackEpisode? in
      guard let audioURL = episode.episodeInfo.audioURL else { return nil }
      return PlaybackEpisode(
        id: episode.id,
        title: episode.episodeInfo.title,
        podcastTitle: episode.podcastTitle,
        audioURL: audioURL,
        imageURL: episode.imageURL,
        episodeDescription: episode.episodeInfo.podcastEpisodeDescription,
        pubDate: episode.episodeInfo.pubDate,
        duration: episode.episodeInfo.duration,
        guid: episode.episodeInfo.guid
      )
    }
    EnhancedAudioManager.shared.addToAutoPlayCandidates(autoPlayEpisodes)
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
      episodeDescription: episode.episodeInfo.podcastEpisodeDescription,
      pubDate: episode.episodeInfo.pubDate,
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

  private func loadTopPodcasts(forceRefresh: Bool = false) async {
    let regionToLoad = selectedRegion

    // Use cached data if available for this region (unless force refresh)
    if !forceRefresh && !Self.cachedTopPodcasts.isEmpty && Self.cachedRegion == regionToLoad {
      // Sync instance property from cache (for UI updates)
      if topPodcasts.isEmpty {
        topPodcasts = Self.cachedTopPodcasts
      }
      logger.debug("Using cached top podcasts for \(regionToLoad)")
      return
    }

    // Join existing task if it matches our region (prevents duplicate requests)
    if let task = Self.loadingTask, Self.loadingRegion == regionToLoad {
      isLoadingTopPodcasts = true
      do {
        let podcasts = try await task.value
        if selectedRegion == regionToLoad {
          topPodcasts = podcasts
        }
      } catch {
        logger.error("Joined task failed: \(error.localizedDescription)")
      }
      isLoadingTopPodcasts = false
      return
    }

    // Start new task
    logger.info("Starting new top podcasts load for \(regionToLoad)")
    isLoadingTopPodcasts = true
    Self.loadingRegion = regionToLoad

    // Clean up old data if force refreshing or changing region
    if forceRefresh || Self.cachedRegion != regionToLoad {
      topPodcasts = []
      Self.cachedTopPodcasts = []
      Self.cachedRegion = ""
    }

    // Create shared task with retry logic for transient API failures
    let task = Task { () -> [AppleRSSPodcast] in
      var lastError: Error?
      for attempt in 1...3 {
        do {
          return try await applePodcastService.fetchTopPodcasts(region: regionToLoad, limit: 25)
        } catch {
          lastError = error
          // Only retry on server errors (5xx) or network errors
          let nsError = error as NSError
          let isServerError = nsError.domain == NSURLErrorDomain ||
                              (error as? URLError)?.code == .badServerResponse
          if isServerError && attempt < 3 {
            logger.warning("Retry \(attempt)/3 for region \(regionToLoad) after error: \(error.localizedDescription)")
            try? await Task.sleep(for: .milliseconds(500 * attempt))  // Exponential backoff
            continue
          }
          throw error
        }
      }
      throw lastError ?? URLError(.unknown)
    }
    Self.loadingTask = task

    do {
      let podcasts = try await task.value
      // Update both static cache and observable instance property
      Self.cachedTopPodcasts = podcasts
      Self.cachedRegion = regionToLoad

      // Update instance property only if region hasn't changed
      if selectedRegion == regionToLoad {
        topPodcasts = podcasts
      }
      logger.info("Loaded \(podcasts.count) top podcasts for \(regionToLoad)")
    } catch {
      logger.error("Failed to load top podcasts: \(error.localizedDescription)")
    }

    // Cleanup static state if it's still ours
    if Self.loadingRegion == regionToLoad {
      Self.loadingRegion = nil
      Self.loadingTask = nil
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

    subscribeTask?.cancel()
    subscribeTask = Task {
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
          predicate: #Predicate { $0.title == title }
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

  // MARK: - For You Recommendations

  @available(iOS 26.0, macOS 26.0, *)
  func loadRecommendations() {
    guard !isLoadingRecommendations else { return }

    // Check if For You is enabled
    guard UserDefaults.standard.object(forKey: "showForYouRecommendations") == nil ||
          UserDefaults.standard.bool(forKey: "showForYouRecommendations") else {
      recommendations = nil
      recommendedEpisodes = []
      return
    }

    guard let context = modelContext else { return }

    recommendationsTask?.cancel()
    isLoadingRecommendations = true

    recommendationsTask = Task { [weak self] in
      guard let self else { return }

      let service = AppleFoundationModelsService()
      let availability = await service.checkAvailability()
      guard availability.isAvailable else {
        isLoadingRecommendations = false
        return
      }

      // Query SwiftData for listening history
      let descriptor = FetchDescriptor<EpisodeDownloadModel>(
        sortBy: [SortDescriptor(\.lastPlayedDate, order: .reverse)]
      )

      guard let allModels = try? context.fetch(descriptor) else {
        isLoadingRecommendations = false
        return
      }

      let playedModels = allModels.filter { $0.playCount > 0 || $0.lastPlayedDate != nil }
      let listeningHistory: [(title: String, podcastTitle: String, completed: Bool)] = playedModels.prefix(10).map {
        (title: $0.episodeTitle, podcastTitle: $0.podcastTitle, completed: $0.isCompleted)
      }

      guard !listeningHistory.isEmpty else {
        isLoadingRecommendations = false
        return
      }

      // Build available episodes from subscribed podcasts (unplayed)
      var availableEpisodes: [(title: String, podcastTitle: String, description: String)] = []
      for podcastModel in podcastInfoModelList {
        for episode in podcastModel.podcastInfo.episodes.prefix(5) {
          let key = Self.makeEpisodeKey(podcastTitle: podcastModel.podcastInfo.title, episodeTitle: episode.title)
          let epDescriptor = FetchDescriptor<EpisodeDownloadModel>(
            predicate: #Predicate { $0.id == key }
          )
          let model = try? context.fetch(epDescriptor).first
          if model?.isCompleted != true {
            availableEpisodes.append((
              title: episode.title,
              podcastTitle: podcastModel.podcastInfo.title,
              description: episode.podcastEpisodeDescription ?? ""
            ))
          }
        }
      }

      let candidateEpisodes = Array(availableEpisodes.prefix(15))
      guard !candidateEpisodes.isEmpty else {
        isLoadingRecommendations = false
        return
      }

      if Task.isCancelled { isLoadingRecommendations = false; return }

      do {
        let result = try await service.generateEpisodeRecommendations(
          listeningHistory: listeningHistory,
          availableEpisodes: candidateEpisodes
        )
        if !Task.isCancelled {
          recommendations = result
          resolveRecommendedEpisodes()
        }
      } catch {
        logger.error("Failed to generate recommendations: \(error.localizedDescription)")
      }
      isLoadingRecommendations = false
    }
  }

  /// Match recommended titles against subscribed podcast episodes and build LibraryEpisode array
  private func resolveRecommendedEpisodes() {
    guard let recommendations, let context = modelContext else {
      recommendedEpisodes = []
      return
    }

    var resolved: [LibraryEpisode] = []
    for title in recommendations.recommendedTitles {
      // Search through subscribed podcasts for the episode
      for podcastModel in podcastInfoModelList {
        if let episode = podcastModel.podcastInfo.episodes.first(where: { $0.title == title }) {
          let key = Self.makeEpisodeKey(podcastTitle: podcastModel.podcastInfo.title, episodeTitle: episode.title)
          let descriptor = FetchDescriptor<EpisodeDownloadModel>(
            predicate: #Predicate { $0.id == key }
          )
          let model = try? context.fetch(descriptor).first

          resolved.append(LibraryEpisode(
            id: key,
            podcastTitle: podcastModel.podcastInfo.title,
            imageURL: episode.imageURL ?? podcastModel.podcastInfo.imageURL,
            language: podcastModel.podcastInfo.language,
            episodeInfo: episode,
            isStarred: model?.isStarred ?? false,
            isDownloaded: model?.localAudioPath != nil,
            isCompleted: model?.isCompleted ?? false,
            lastPlaybackPosition: model?.lastPlaybackPosition ?? 0,
            savedDuration: model?.duration ?? 0
          ))
          break
        }
      }
    }
    recommendedEpisodes = resolved
  }

  deinit {
    MainActor.assumeIsolated {
      cleanup()
    }
  }

  func cleanup() {
    regionObserverTask?.cancel()
    regionObserverTask = nil
    recommendationsTask?.cancel()
    recommendationsTask = nil
    loadTask?.cancel()
    loadTask = nil
    subscribeTask?.cancel()
    subscribeTask = nil
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
