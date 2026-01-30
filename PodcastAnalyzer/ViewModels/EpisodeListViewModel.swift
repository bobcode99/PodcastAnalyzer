//
//  EpisodeListViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for EpisodeListView - handles filtering, sorting, and episode operations
//

import SwiftData
import SwiftUI
import ZMarkupParser

#if os(iOS)
import UIKit
#else
import AppKit
#endif

import os.log

private let viewModelLogger = Logger(subsystem: "com.podcast.analyzer", category: "ViewModelLifecycle")

@MainActor
@Observable
final class EpisodeListViewModel {
  var episodeModels: [String: EpisodeDownloadModel] = [:]

  #if DEBUG
  private let instanceId = UUID()
  #endif
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
  private var downloadCompletionObserver: NSObjectProtocol?

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
    #if DEBUG
    viewModelLogger.info("📦 EpisodeListViewModel INIT: \(self.instanceId) for \(podcastModel.podcastInfo.title)")
    #endif
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    loadEpisodeModels()
    setupDownloadCompletionObserver()
  }

  private func setupDownloadCompletionObserver() {
    // Remove existing observer if any
    if let observer = downloadCompletionObserver {
      NotificationCenter.default.removeObserver(observer)
    }

    // Capture podcast title before closure to avoid main actor isolation issues
    let myPodcastTitle = podcastModel.podcastInfo.title

    // Listen for download completion to update SwiftData
    downloadCompletionObserver = NotificationCenter.default.addObserver(
      forName: .episodeDownloadCompleted,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self = self,
            let userInfo = notification.userInfo,
            let episodeTitle = userInfo["episodeTitle"] as? String,
            let podcastTitle = userInfo["podcastTitle"] as? String,
            let localPath = userInfo["localPath"] as? String else { return }

      // Only handle if this is for our podcast
      guard podcastTitle == myPodcastTitle else { return }

      // Dispatch to MainActor for the update
      Task { @MainActor in
        self.updateEpisodeDownloadModel(
          episodeTitle: episodeTitle,
          podcastTitle: podcastTitle,
          localPath: localPath
        )
      }
    }
  }

  private func updateEpisodeDownloadModel(episodeTitle: String, podcastTitle: String, localPath: String) {
    guard let context = modelContext else { return }

    let episodeKey = "\(podcastTitle)\(Self.episodeKeyDelimiter)\(episodeTitle)"

    // Check if model already exists
    if let existingModel = episodeModels[episodeKey] {
      existingModel.localAudioPath = localPath
      existingModel.downloadedDate = Date()
      // Get file size
      if let attrs = try? FileManager.default.attributesOfItem(atPath: localPath),
         let size = attrs[.size] as? Int64 {
        existingModel.fileSize = size
      }
      try? context.save()
    } else {
      // Find the episode to get its audio URL
      guard let episode = podcastModel.podcastInfo.episodes.first(where: { $0.title == episodeTitle }),
            let audioURL = episode.audioURL else { return }

      // Create new model
      let model = EpisodeDownloadModel(
        episodeTitle: episodeTitle,
        podcastTitle: podcastTitle,
        audioURL: audioURL,
        localAudioPath: localPath,
        downloadedDate: Date(),
        imageURL: episode.imageURL ?? podcastModel.podcastInfo.imageURL,
        pubDate: episode.pubDate
      )
      // Get file size
      if let attrs = try? FileManager.default.attributesOfItem(atPath: localPath),
         let size = attrs[.size] as? Int64 {
        model.fileSize = size
      }
      context.insert(model)
      try? context.save()
      episodeModels[episodeKey] = model
    }
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
    // Stop any existing timer first to prevent duplicates
    stopRefreshTimer()

    // Refresh every 5 seconds instead of 2 to reduce CPU usage
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
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

  // MARK: - Cleanup

  deinit {
    MainActor.assumeIsolated {
      cleanup()
    }
  }

  /// Clean up all resources to prevent memory leaks
  func cleanup() {
    #if DEBUG
    viewModelLogger.info("🗑️ EpisodeListViewModel CLEANUP: \(self.instanceId)")
    #endif
    stopRefreshTimer()
    if let observer = downloadCompletionObserver {
      NotificationCenter.default.removeObserver(observer)
      downloadCompletionObserver = nil
    }
  }
}
