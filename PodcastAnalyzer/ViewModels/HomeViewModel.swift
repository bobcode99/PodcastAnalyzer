//
//  HomeViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for Home tab - manages Up Next episodes and Popular Shows from Apple
//

import Combine
import Foundation
import SwiftData
import SwiftUI
import os.log

@MainActor
class HomeViewModel: ObservableObject {
  // Up Next episodes (unplayed from subscribed podcasts)
  @Published var upNextEpisodes: [LibraryEpisode] = []

  // Top podcasts from Apple RSS
  @Published var topPodcasts: [AppleRSSPodcast] = []
  @Published var isLoadingTopPodcasts = false

  // Region selection
  @Published var selectedRegion: String = "us" {
    didSet {
      if oldValue != selectedRegion {
        UserDefaults.standard.set(selectedRegion, forKey: "selectedPodcastRegion")
        loadTopPodcasts()
      }
    }
  }

  // Podcast preview/subscription
  @Published var selectedPodcast: AppleRSSPodcast?
  @Published var isSubscribing = false
  @Published var subscriptionError: String?
  @Published var subscriptionSuccess = false

  private var podcastInfoModelList: [PodcastInfoModel] = []
  private let applePodcastService = ApplePodcastService()
  private let rssService = PodcastRssService()
  private var modelContext: ModelContext?
  private var cancellables = Set<AnyCancellable>()
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "HomeViewModel")

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
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    loadAll()
  }

  // MARK: - Load All Data

  private func loadAll() {
    loadPodcastFeeds()
    loadUpNextEpisodes()
    loadTopPodcasts()
  }

  func refresh() async {
    loadPodcastFeeds()
    loadUpNextEpisodes()
    loadTopPodcasts()
  }

  // MARK: - Load Podcasts

  private func loadPodcastFeeds() {
    guard let context = modelContext else {
      logger.warning("ModelContext is nil, cannot load feeds")
      return
    }

    // Only load subscribed podcasts (not browsed/cached ones)
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.isSubscribed == true },
      sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
    )

    do {
      podcastInfoModelList = try context.fetch(descriptor)
      logger.info("Loaded \(self.podcastInfoModelList.count) subscribed podcast feeds")
    } catch {
      logger.error("Failed to load feeds: \(error.localizedDescription)")
    }
  }

  // MARK: - Load Up Next Episodes

  private func loadUpNextEpisodes() {
    var allEpisodes: [LibraryEpisode] = []

    for podcast in podcastInfoModelList {
      let podcastInfo = podcast.podcastInfo

      for episode in podcastInfo.episodes {
        let episodeKey = "\(podcastInfo.title)\(Self.episodeKeyDelimiter)\(episode.title)"
        let model = getEpisodeModel(for: episodeKey)

        // Only include unplayed episodes
        let isCompleted = model?.isCompleted ?? false
        if !isCompleted {
          allEpisodes.append(LibraryEpisode(
            id: episodeKey,
            podcastTitle: podcastInfo.title,
            imageURL: episode.imageURL ?? podcastInfo.imageURL,
            language: podcastInfo.language,
            episodeInfo: episode,
            isStarred: model?.isStarred ?? false,
            isDownloaded: model?.localAudioPath != nil,
            isCompleted: false,
            lastPlaybackPosition: model?.lastPlaybackPosition ?? 0
          ))
        }
      }
    }

    // Sort by date (newest first) and take top 50
    upNextEpisodes = allEpisodes
      .sorted { ($0.episodeInfo.pubDate ?? .distantPast) > ($1.episodeInfo.pubDate ?? .distantPast) }
      .prefix(50)
      .map { $0 }

    logger.info("Loaded \(self.upNextEpisodes.count) up next episodes")
  }

  private func getEpisodeModel(for key: String) -> EpisodeDownloadModel? {
    guard let context = modelContext else { return nil }

    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == key }
    )

    return try? context.fetch(descriptor).first
  }

  // MARK: - Load Top Podcasts

  private func loadTopPodcasts() {
    isLoadingTopPodcasts = true

    applePodcastService.fetchTopPodcasts(region: selectedRegion, limit: 25)
      .sink(
        receiveCompletion: { [weak self] completion in
          self?.isLoadingTopPodcasts = false
          if case .failure(let error) = completion {
            self?.logger.error("Failed to load top podcasts: \(error.localizedDescription)")
          }
        },
        receiveValue: { [weak self] podcasts in
          self?.topPodcasts = podcasts
          self?.logger.info("Loaded \(podcasts.count) top podcasts for \(self?.selectedRegion ?? "unknown")")
        }
      )
      .store(in: &cancellables)
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

    // Look up the podcast to get the RSS feed URL
    applePodcastService.lookupPodcast(collectionId: podcast.id)
      .flatMap { [weak self] result -> AnyPublisher<PodcastInfo, Error> in
        guard let feedUrl = result?.feedUrl else {
          return Fail(error: URLError(.badServerResponse)).eraseToAnyPublisher()
        }

        return Future { promise in
          Task {
            do {
              let podcastInfo = try await self?.rssService.fetchPodcast(from: feedUrl)
              if let info = podcastInfo {
                promise(.success(info))
              } else {
                promise(.failure(URLError(.cannotParseResponse)))
              }
            } catch {
              promise(.failure(error))
            }
          }
        }
        .eraseToAnyPublisher()
      }
      .receive(on: DispatchQueue.main)
      .sink(
        receiveCompletion: { [weak self] completion in
          self?.isSubscribing = false
          if case .failure(let error) = completion {
            self?.subscriptionError = error.localizedDescription
            self?.logger.error("Failed to subscribe: \(error.localizedDescription)")
          }
        },
        receiveValue: { [weak self] podcastInfo in
          guard let self = self else { return }

          // Check if already subscribed
          let title = podcastInfo.title
          let existingDescriptor = FetchDescriptor<PodcastInfoModel>(
            predicate: #Predicate { $0.podcastInfo.title == title }
          )

          if (try? context.fetch(existingDescriptor).first) != nil {
            self.logger.info("Already subscribed to \(podcastInfo.title)")
            self.subscriptionSuccess = true
            return
          }

          // Create new subscription (explicitly set isSubscribed to true)
          let model = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date(), isSubscribed: true)
          context.insert(model)

          do {
            try context.save()
            self.podcastInfoModelList.insert(model, at: 0)
            self.loadUpNextEpisodes()
            self.subscriptionSuccess = true
            self.logger.info("Successfully subscribed to \(podcastInfo.title)")
          } catch {
            self.subscriptionError = error.localizedDescription
            self.logger.error("Failed to save subscription: \(error.localizedDescription)")
          }
        }
      )
      .store(in: &cancellables)
  }
}
