//
//  EpisodeListViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for EpisodeListView - handles filtering, sorting, and episode operations
//

import Combine
import SwiftData
import SwiftUI
import ZMarkupParser

#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
@Observable
final class EpisodeListViewModel {
  // MARK: - Published State
  var episodeModels: [String: EpisodeDownloadModel] = [:]
  var selectedFilter: EpisodeFilter = .all
  var sortOldestFirst: Bool = false
  var searchText: String = ""
  var isRefreshing: Bool = false
  var isDescriptionExpanded: Bool = false

  // HTML-rendered description view
  var descriptionView: AnyView = AnyView(EmptyView())

  // MARK: - Dependencies
  private let podcastModel: PodcastInfoModel
  private let downloadManager = DownloadManager.shared
  private let rssService = PodcastRssService()
  private var modelContext: ModelContext?
  private var refreshTimer: Timer?

  // Use Unit Separator (U+001F) as delimiter - same as DownloadManager
  private static let episodeKeyDelimiter = "\u{1F}"

  // MARK: - Computed Properties

  var podcastInfo: PodcastInfo {
    podcastModel.podcastInfo
  }

  var filteredEpisodes: [PodcastEpisodeInfo] {
    var episodes = podcastModel.podcastInfo.episodes

    // Apply search filter first
    if !searchText.isEmpty {
      let query = searchText.lowercased()
      episodes = episodes.filter { episode in
        episode.title.lowercased().contains(query)
          || (episode.podcastEpisodeDescription?.lowercased().contains(query) ?? false)
      }
    }

    // Apply category filter
    switch selectedFilter {
    case .all:
      break
    case .unplayed:
      episodes = episodes.filter { episode in
        let key = makeEpisodeKey(episode)
        guard let model = episodeModels[key] else { return true }
        return !model.isCompleted && model.progress < 0.1
      }
    case .played:
      episodes = episodes.filter { episode in
        let key = makeEpisodeKey(episode)
        guard let model = episodeModels[key] else { return false }
        return model.isCompleted
      }
    case .starred:
      episodes = episodes.filter { episode in
        let key = makeEpisodeKey(episode)
        guard let model = episodeModels[key] else { return false }
        return model.isStarred
      }
    case .downloaded:
      episodes = episodes.filter { episode in
        let state = downloadManager.getDownloadState(
          episodeTitle: episode.title,
          podcastTitle: podcastModel.podcastInfo.title
        )
        if case .downloaded = state { return true }
        return false
      }
    }

    // Apply sort
    if sortOldestFirst {
      episodes = episodes.sorted { (e1, e2) in
        guard let d1 = e1.pubDate, let d2 = e2.pubDate else { return false }
        return d1 < d2
      }
    }

    return episodes
  }

  var filteredEpisodeCount: Int {
    filteredEpisodes.count
  }

  // MARK: - Initialization

  init(podcastModel: PodcastInfoModel) {
    self.podcastModel = podcastModel
    parseDescription()
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    loadEpisodeModels()
  }

  // MARK: - HTML Description Parsing

  private func parseDescription() {
    let html = podcastModel.podcastInfo.podcastInfoDescription ?? ""

    guard !html.isEmpty else {
      descriptionView = AnyView(
        Text("No description available.")
          .foregroundColor(.secondary)
          .font(.caption)
      )
      return
    }

    #if os(iOS)
    let labelColor = UIColor.secondaryLabel
    #else
    let labelColor = NSColor.secondaryLabelColor
    #endif

    let rootStyle = MarkupStyle(
      font: MarkupStyleFont(size: 13),  // Smaller font for list view
      foregroundColor: MarkupStyleColor(color: labelColor)
    )

    let parser = ZHTMLParserBuilder.initWithDefault()
      .set(rootStyle: rootStyle)
      .build()

    Task {
      let attributedString = parser.render(html)

      await MainActor.run {
        self.descriptionView = AnyView(
          HTMLTextView(attributedString: attributedString)
            .frame(maxWidth: .infinity, alignment: .leading)
        )
      }
    }
  }

  // MARK: - Timer Management

  func startRefreshTimer() {
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        self.loadEpisodeModels()
      }
    }
  }

  func stopRefreshTimer() {
    refreshTimer?.invalidate()
    refreshTimer = nil
  }

  // MARK: - Episode Key Helper

  func makeEpisodeKey(_ episode: PodcastEpisodeInfo) -> String {
    return "\(podcastModel.podcastInfo.title)\(Self.episodeKeyDelimiter)\(episode.title)"
  }

  // MARK: - Data Loading

  func loadEpisodeModels() {
    guard let context = modelContext else { return }

    let podcastTitle = podcastModel.podcastInfo.title
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.podcastTitle == podcastTitle }
    )

    do {
      let results = try context.fetch(descriptor)
      var models: [String: EpisodeDownloadModel] = [:]
      for model in results {
        models[model.id] = model
      }
      episodeModels = models
    } catch {
      print("Failed to load episode models: \(error)")
    }
  }

  // MARK: - Podcast Operations

  func refreshPodcast() async {
    isRefreshing = true
    defer { isRefreshing = false }

    do {
      let updatedPodcast = try await rssService.fetchPodcast(
        from: podcastModel.podcastInfo.rssUrl)
      podcastModel.podcastInfo = updatedPodcast
      try? modelContext?.save()
    } catch {
      print("Failed to refresh podcast: \(error)")
    }
  }

  // MARK: - Episode Actions

  func toggleStar(for episode: PodcastEpisodeInfo) {
    guard let context = modelContext else { return }

    let key = makeEpisodeKey(episode)
    if let model = episodeModels[key] {
      model.isStarred.toggle()
      try? context.save()
    } else {
      guard let audioURL = episode.audioURL else { return }
      let model = EpisodeDownloadModel(
        episodeTitle: episode.title,
        podcastTitle: podcastModel.podcastInfo.title,
        audioURL: audioURL,
        imageURL: episode.imageURL ?? podcastModel.podcastInfo.imageURL,
        pubDate: episode.pubDate
      )
      model.isStarred = true
      context.insert(model)
      try? context.save()
      episodeModels[key] = model
    }
  }

  func downloadEpisode(_ episode: PodcastEpisodeInfo) {
    downloadManager.downloadEpisode(
      episode: episode,
      podcastTitle: podcastModel.podcastInfo.title,
      language: podcastModel.podcastInfo.language
    )
  }

  func deleteDownload(_ episode: PodcastEpisodeInfo) {
    downloadManager.deleteDownload(
      episodeTitle: episode.title,
      podcastTitle: podcastModel.podcastInfo.title
    )
  }

  func togglePlayed(for episode: PodcastEpisodeInfo) {
    guard let context = modelContext else { return }

    let key = makeEpisodeKey(episode)
    if let model = episodeModels[key] {
      model.isCompleted.toggle()
      if !model.isCompleted {
        model.lastPlaybackPosition = 0
      }
      try? context.save()
    } else {
      guard let audioURL = episode.audioURL else { return }
      let model = EpisodeDownloadModel(
        episodeTitle: episode.title,
        podcastTitle: podcastModel.podcastInfo.title,
        audioURL: audioURL,
        imageURL: episode.imageURL ?? podcastModel.podcastInfo.imageURL,
        pubDate: episode.pubDate
      )
      model.isCompleted = true
      context.insert(model)
      try? context.save()
      episodeModels[key] = model
    }
  }
}
