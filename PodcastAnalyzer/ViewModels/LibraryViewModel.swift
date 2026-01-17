//
//  LibraryViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for Library tab - manages subscribed podcasts, saved, downloaded, and latest episodes
//

import Foundation
import SwiftData
import SwiftUI
import os.log

// MARK: - Library Episode Model

struct LibraryEpisode: Identifiable {
  let id: String
  let podcastTitle: String
  let imageURL: String?
  let language: String
  let episodeInfo: PodcastEpisodeInfo
  let isStarred: Bool
  let isDownloaded: Bool
  let isCompleted: Bool
  let lastPlaybackPosition: TimeInterval

  var hasProgress: Bool {
    lastPlaybackPosition > 0 && !isCompleted
  }

  /// Progress percentage (0.0 to 1.0)
  var progress: Double {
    guard let duration = episodeInfo.duration, duration > 0 else { return 0 }
    return min(lastPlaybackPosition / Double(duration), 1.0)
  }
}

// MARK: - Library ViewModel

@MainActor
@Observable
final class LibraryViewModel {
  var podcastInfoModelList: [PodcastInfoModel] = []
  var savedEpisodes: [LibraryEpisode] = []
  var downloadedEpisodes: [LibraryEpisode] = []
  var latestEpisodes: [LibraryEpisode] = []
  var isLoading = false
  var error: String?

  // Private DTO for background processing
  private struct EpisodeDownloadData: Sendable {
    let id: String
    let isStarred: Bool
    let localAudioPath: String?
    let isCompleted: Bool
    let lastPlaybackPosition: TimeInterval
  }

  // Separate loading states for progressive UI updates
  var isLoadingPodcasts = false
  var isLoadingSaved = false
  var isLoadingDownloaded = false
  var isLoadingLatest = false

  // Search state for subpages
  var savedSearchText: String = ""
  var downloadedSearchText: String = ""
  var latestSearchText: String = ""

  // Filtered arrays based on search text
  var filteredSavedEpisodes: [LibraryEpisode] {
    guard !savedSearchText.isEmpty else { return savedEpisodes }
    let query = savedSearchText.lowercased()
    return savedEpisodes.filter {
      $0.episodeInfo.title.lowercased().contains(query) ||
      $0.podcastTitle.lowercased().contains(query)
    }
  }

  var filteredDownloadedEpisodes: [LibraryEpisode] {
    guard !downloadedSearchText.isEmpty else { return downloadedEpisodes }
    let query = downloadedSearchText.lowercased()
    return downloadedEpisodes.filter {
      $0.episodeInfo.title.lowercased().contains(query) ||
      $0.podcastTitle.lowercased().contains(query)
    }
  }

  var filteredLatestEpisodes: [LibraryEpisode] {
    guard !latestSearchText.isEmpty else { return latestEpisodes }
    let query = latestSearchText.lowercased()
    return latestEpisodes.filter {
      $0.episodeInfo.title.lowercased().contains(query) ||
      $0.podcastTitle.lowercased().contains(query)
    }
  }

  // Removed podcastsSortedByRecentUpdate as it is now handled by @Query in the View

  private let service = PodcastRssService()
  private let downloadManager = DownloadManager.shared
  private var modelContext: ModelContext?
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "LibraryViewModel")
  private var downloadCompletionObserver: NSObjectProtocol?

  // All podcasts (subscribed + browsed) for episode lookups
  private var allPodcasts: [PodcastInfoModel] = []

  // Flag to prevent redundant loads
  private var isAlreadyLoaded = false

  // Use Unit Separator (U+001F) as delimiter
  private static let episodeKeyDelimiter = "\u{1F}"

  // Cache for O(1) lookups
  private var podcastTitleMap: [String: PodcastInfoModel] = [:]

  init(modelContext: ModelContext?) {
    self.modelContext = modelContext
    if modelContext != nil {
      Task {
        await loadAll()
      }
    }
    setupDownloadCompletionObserver()
  }

  /// Clean up resources. Call this from onDisappear.
  func cleanup() {
    if let observer = downloadCompletionObserver {
      NotificationCenter.default.removeObserver(observer)
      downloadCompletionObserver = nil
    }
  }

  private func setupDownloadCompletionObserver() {
    // Listen for download completion to update SwiftData and reload
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

      Task { @MainActor in
        self.handleDownloadCompletion(
          episodeTitle: episodeTitle,
          podcastTitle: podcastTitle,
          localPath: localPath
        )
      }
    }
  }

  private func handleDownloadCompletion(episodeTitle: String, podcastTitle: String, localPath: String) {
    guard let context = modelContext else { return }

    let episodeKey = "\(podcastTitle)\(Self.episodeKeyDelimiter)\(episodeTitle)"

    // Check if model already exists
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == episodeKey }
    )

    do {
      if let existingModel = try context.fetch(descriptor).first {
        existingModel.localAudioPath = localPath
        existingModel.downloadedDate = Date()
        if let attrs = try? FileManager.default.attributesOfItem(atPath: localPath),
           let size = attrs[.size] as? Int64 {
          existingModel.fileSize = size
        }
        try context.save()
      } else {
        // Find the episode from allPodcasts using O(1) lookup
        guard let podcast = podcastTitleMap[podcastTitle],
              let episode = podcast.podcastInfo.episodes.first(where: { $0.title == episodeTitle }),
              let audioURL = episode.audioURL else { return }

        let model = EpisodeDownloadModel(
          episodeTitle: episodeTitle,
          podcastTitle: podcastTitle,
          audioURL: audioURL,
          localAudioPath: localPath,
          downloadedDate: Date(),
          imageURL: episode.imageURL ?? podcast.podcastInfo.imageURL,
          pubDate: episode.pubDate
        )
        if let attrs = try? FileManager.default.attributesOfItem(atPath: localPath),
           let size = attrs[.size] as? Int64 {
          model.fileSize = size
        }
        context.insert(model)
        try context.save()
      }

      // Reload downloaded episodes to update the UI
      Task {
        await loadDownloadedEpisodes()
      }
    } catch {
      logger.error("Failed to update download model: \(error.localizedDescription)")
    }
  }

  func setModelContext(_ context: ModelContext) {
    // Prevent redundant reloading if context hasn't changed and data is loaded
    if self.modelContext == context && isAlreadyLoaded {
      return
    }
    
    self.modelContext = context
    // Start ALL loading in parallel - don't block UI at all
    // Each section loads independently and updates its own state
    isLoadingPodcasts = true
    isLoadingSaved = true
    isLoadingDownloaded = true
    isLoadingLatest = true

    // Launch loading tasks
    // Chain podcasts -> latest to ensure dependencies are met without polling
    Task { 
      await loadPodcastsSection()
      await loadLatestSection()
    }
    
    // Independent sections
    Task { await loadSavedSection() }
    Task { await loadDownloadedSection() }

    isAlreadyLoaded = true
  }

  /// Receive updated podcast list from View's @Query
  func setPodcasts(_ podcasts: [PodcastInfoModel]) {
    self.podcastInfoModelList = podcasts
    // Update dependent sections
    Task { await loadLatestSection() }
  }

  // MARK: - Independent Section Loaders

  /// Load podcasts section independently
  private func loadPodcastsSection() async {
    // We no longer load feeds manually here, they are injected via setPodcasts
    // Just load the full lookup map
    await loadAllPodcasts()
    isLoadingPodcasts = false
  }

  /// Load saved episodes section independently
  private func loadSavedSection() async {
    // Load immediately - EpisodeDownloadModel has all the data we need
    await loadSavedEpisodes()
    isLoadingSaved = false
  }

  /// Load downloaded episodes section independently
  private func loadDownloadedSection() async {
    // Load downloaded episodes immediately from SwiftData (fast)
    await loadDownloadedEpisodesQuick()
    isLoadingDownloaded = false

    // Then sync with disk in background (slow, but doesn't block UI)
    Task.detached(priority: .background) { [weak self] in
      guard let self else { return }
      await self.syncDownloadedFilesWithSwiftData()
      // Reload to pick up any newly synced episodes
      await self.loadDownloadedEpisodesQuick()
    }
  }

  /// Load latest episodes section independently
  private func loadLatestSection() async {
    // This section depends heavily on podcastInfoModelList
    // We now await this AFTER loadPodcastsSection completes, so no need to poll
    await loadLatestEpisodes()
    isLoadingLatest = false
  }

  /// Legacy loadAll for refresh operations that need to wait for completion
  private func loadAll() async {
    isLoading = true
    isLoadingPodcasts = true
    isLoadingSaved = true
    isLoadingDownloaded = true
    isLoadingLatest = true

    // First, load all podcasts (needed by other loaders)
    await loadAllPodcasts()

    // No need to load feeds here, they come from @Query
    isLoadingPodcasts = false

    // Then load the rest using async let for parallelism while staying on MainActor
    async let savedTask: () = loadSavedEpisodesWithState()
    async let downloadedTask: () = loadDownloadedEpisodesWithState()
    async let latestTask: () = loadLatestEpisodesWithState()
    _ = await (savedTask, downloadedTask, latestTask)

    isLoading = false
  }

  // MARK: - Load All Podcasts (for episode lookups)

  private func loadAllPodcasts() async {
    guard let context = modelContext else { return }

    // Load ALL podcasts (subscribed + browsed) for episode lookups
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
    )

    do {
      let podcasts = try context.fetch(descriptor)
      // Since we're @MainActor, update directly
      self.allPodcasts = podcasts
      
      // Update lookup map
      self.podcastTitleMap = Dictionary(uniqueKeysWithValues: 
        podcasts.compactMap { ($0.podcastInfo.title, $0) }
      )
      
      logger.info("Loaded \(self.allPodcasts.count) total podcasts for episode lookups")
    } catch {
      logger.error("Failed to load all podcasts: \(error.localizedDescription)")
    }
  }

  // MARK: - Load Podcasts
  
  // Removed loadPodcastFeeds as it's replaced by @Query injection via setPodcasts
  
  // MARK: - Load Saved Episodes

  private func loadSavedEpisodes() async {
    guard let context = modelContext else { return }

    // Fetch ALL and filter in memory to avoid predicate issues with Unicode
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      sortBy: [SortDescriptor(\.downloadedDate, order: .reverse)]
    )

    do {
      let allModels = try context.fetch(descriptor)
      // Filter for starred episodes in memory
      let starredModels = allModels.filter { $0.isStarred }
      // Map to LibraryEpisode - always succeeds due to fallback
      let results = starredModels.map { model in
        self.createLibraryEpisode(from: model)
      }
      self.savedEpisodes = results
      logger.info("Loaded \(self.savedEpisodes.count) saved episodes")
    } catch {
      logger.error("Failed to load saved episodes: \(error.localizedDescription)")
    }
  }

  // MARK: - Load Downloaded Episodes

  /// Quick load from SwiftData without disk sync (for responsive UI)
  private func loadDownloadedEpisodesQuick() async {
    guard let context = modelContext else { return }

    // Fetch ALL EpisodeDownloadModel and filter in memory
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      sortBy: [SortDescriptor(\.downloadedDate, order: .reverse)]
    )

    do {
      let allModels = try context.fetch(descriptor)

      // Filter for downloaded episodes in memory (localAudioPath is not nil and not empty)
      let downloadedModels = allModels.filter { model in
        guard let path = model.localAudioPath else { return false }
        return !path.isEmpty
      }

      // Map to LibraryEpisode
      let results = downloadedModels.map { model in
        self.createLibraryEpisode(from: model)
      }
      self.downloadedEpisodes = results
      logger.info("Quick loaded \(self.downloadedEpisodes.count) downloaded episodes")
    } catch {
      logger.error("Download fetch failed: \(error)")
    }
  }

  /// Full load with disk sync (for refresh operations)
  private func loadDownloadedEpisodes() async {
    guard let context = modelContext else { return }

    // First, sync SwiftData with actual files on disk
    // This handles cases where downloads completed while no observer was listening
    await syncDownloadedFilesWithSwiftData()

    // Fetch ALL EpisodeDownloadModel and filter in memory
    // This avoids potential SwiftData predicate issues with Unicode strings
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      sortBy: [SortDescriptor(\.downloadedDate, order: .reverse)]
    )

    do {
      let allModels = try context.fetch(descriptor)
      logger.info("Fetched \(allModels.count) total EpisodeDownloadModel entries")

      // Filter for downloaded episodes in memory (localAudioPath is not nil and not empty)
      let downloadedModels = allModels.filter { model in
        guard let path = model.localAudioPath else { return false }
        return !path.isEmpty
      }
      logger.info("Found \(downloadedModels.count) models with localAudioPath")

      // Map to LibraryEpisode - always succeeds due to fallback
      let results = downloadedModels.map { model in
        self.createLibraryEpisode(from: model)
      }
      self.downloadedEpisodes = results
      logger.info("Loaded \(self.downloadedEpisodes.count) downloaded episodes")
    } catch {
      logger.error("Download fetch failed: \(error)")
    }
  }

  /// Syncs SwiftData with actual downloaded files on disk
  /// This handles cases where downloads completed but the notification was missed
  private func syncDownloadedFilesWithSwiftData() async {
    guard let context = modelContext else { return }

    // 1. Gather data on MainActor
    let descriptor = FetchDescriptor<EpisodeDownloadModel>()
    let existingModelsDict: [String: EpisodeDownloadModel]
    do {
      let allModels = try context.fetch(descriptor)
      existingModelsDict = Dictionary(uniqueKeysWithValues: allModels.map { ($0.id, $0) })
    } catch {
      logger.error("Failed to fetch existing models for sync: \(error)")
      return
    }

    // Prepare episode data for background processing (Sendable)
    struct EpisodeCheckItem: Sendable {
      let episodeTitle: String
      let podcastTitle: String
      let audioURL: String?
      let imageURL: String
      let pubDate: Date?
      let episodeKey: String
    }

    let delimiter = Self.episodeKeyDelimiter
    var itemsToCheck: [EpisodeCheckItem] = []
    for podcast in allPodcasts {
      let podcastInfo = podcast.podcastInfo
      for episode in podcastInfo.episodes {
        let episodeKey = "\(podcastInfo.title)\(delimiter)\(episode.title)"
        itemsToCheck.append(EpisodeCheckItem(
          episodeTitle: episode.title,
          podcastTitle: podcastInfo.title,
          audioURL: episode.audioURL,
          imageURL: episode.imageURL ?? podcastInfo.imageURL,
          pubDate: episode.pubDate,
          episodeKey: episodeKey
        ))
      }
    }

    // 2. Perform file system checks in background (this is the slow part)
    struct SyncResult: Sendable {
      let episodeKey: String
      let localPath: String
      let episodeTitle: String
      let podcastTitle: String
      let audioURL: String
      let imageURL: String
      let pubDate: Date?
      let needsUpdate: Bool
      let needsInsert: Bool
    }

    let existingKeys = Set(existingModelsDict.keys)
    let existingPaths: [String: String?] = Dictionary(uniqueKeysWithValues: 
      existingModelsDict.map { ($0.key, $0.value.localAudioPath) }
    )

    let syncResults = await Task.detached(priority: .background) { () -> [SyncResult] in
      var results: [SyncResult] = []
      let fm = FileManager.default
      
      // Get audio directory path (same logic as DownloadManager.checkAudioFileExistsSynchronously)
      #if os(macOS)
      let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      let audioDir = appSupport.appendingPathComponent("PodcastAnalyzer/Audio", isDirectory: true)
      #else
      let libraryDir = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
      let audioDir = libraryDir.appendingPathComponent("Audio", isDirectory: true)
      #endif
      
      let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
      let possibleExtensions = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"]
      
      for item in itemsToCheck {
        // Direct file system check (same logic as DownloadManager)
        let baseFileName = "\(item.podcastTitle)_\(item.episodeTitle)"
          .components(separatedBy: invalidCharacters)
          .joined(separator: "_")
          .trimmingCharacters(in: .whitespaces)
        
        var localPath: String? = nil
        for ext in possibleExtensions {
          let path = audioDir.appendingPathComponent("\(baseFileName).\(ext)")
          if fm.fileExists(atPath: path.path) {
            localPath = path.path
            break
          }
        }
        
        guard let foundPath = localPath else { continue }
        
        let existsInDB = existingKeys.contains(item.episodeKey)
        let currentPath = existingPaths[item.episodeKey] ?? nil
        
        if existsInDB {
          // Check if path needs update
          if currentPath != foundPath {
            results.append(SyncResult(
              episodeKey: item.episodeKey,
              localPath: foundPath,
              episodeTitle: item.episodeTitle,
              podcastTitle: item.podcastTitle,
              audioURL: item.audioURL ?? "",
              imageURL: item.imageURL,
              pubDate: item.pubDate,
              needsUpdate: true,
              needsInsert: false
            ))
          }
        } else if item.audioURL != nil {
          // Needs insert
          results.append(SyncResult(
            episodeKey: item.episodeKey,
            localPath: foundPath,
            episodeTitle: item.episodeTitle,
            podcastTitle: item.podcastTitle,
            audioURL: item.audioURL!,
            imageURL: item.imageURL,
            pubDate: item.pubDate,
            needsUpdate: false,
            needsInsert: true
          ))
        }
      }
      return results
    }.value

    // 3. Apply results on MainActor
    var syncedCount = 0
    for result in syncResults {
      if result.needsUpdate {
        if let existingModel = existingModelsDict[result.episodeKey] {
          existingModel.localAudioPath = result.localPath
          existingModel.downloadedDate = existingModel.downloadedDate ?? Date()
          syncedCount += 1
        }
      } else if result.needsInsert {
        let model = EpisodeDownloadModel(
          episodeTitle: result.episodeTitle,
          podcastTitle: result.podcastTitle,
          audioURL: result.audioURL,
          localAudioPath: result.localPath,
          downloadedDate: Date(),
          imageURL: result.imageURL,
          pubDate: result.pubDate
        )
        context.insert(model)
        syncedCount += 1
      }
    }

    if syncedCount > 0 {
      try? context.save()
      logger.info("Synced \(syncedCount) downloaded episodes from disk to SwiftData")
    }
  }

  // MARK: - Load Latest Episodes

  private func loadLatestEpisodes() async {
    guard let context = modelContext else { return }

    // 1. Gather all necessary data on MainActor (where ModelContext lives)
    let descriptor = FetchDescriptor<EpisodeDownloadModel>()
    let episodeDataDict: [String: EpisodeDownloadData]
    do {
      let allModels = try context.fetch(descriptor)
      // Map to Sendable DTOs
      let keyValues = allModels.map { model in
        (model.id, EpisodeDownloadData(
          id: model.id,
          isStarred: model.isStarred,
          localAudioPath: model.localAudioPath,
          isCompleted: model.isCompleted,
          lastPlaybackPosition: model.lastPlaybackPosition
        ))
      }
      episodeDataDict = Dictionary(uniqueKeysWithValues: keyValues)
    } catch {
      logger.error("Failed to fetch episode models: \(error)")
      return
    }

    // Capture the podcast info structs (already Sendable)
    let podcasts = self.podcastInfoModelList.map { $0.podcastInfo }

    // 2. Perform heavy processing in background
    let delimiter = Self.episodeKeyDelimiter
    
    let sortedEpisodes = await Task.detached(priority: .userInitiated) { () -> [LibraryEpisode] in
      var allEpisodes: [LibraryEpisode] = []

      for podcastInfo in podcasts {
        // Get latest 5 episodes from each podcast
        for episode in podcastInfo.episodes.prefix(5) {
          let episodeKey = "\(podcastInfo.title)\(delimiter)\(episode.title)"
          let data = episodeDataDict[episodeKey]

          allEpisodes.append(LibraryEpisode(
            id: episodeKey,
            podcastTitle: podcastInfo.title,
            imageURL: episode.imageURL ?? podcastInfo.imageURL,
            language: podcastInfo.language,
            episodeInfo: episode,
            isStarred: data?.isStarred ?? false,
            isDownloaded: data?.localAudioPath != nil,
            isCompleted: data?.isCompleted ?? false,
            lastPlaybackPosition: data?.lastPlaybackPosition ?? 0
          ))
        }
      }

      // Sort by date and take latest 50
      return allEpisodes
        .sorted { ($0.episodeInfo.pubDate ?? .distantPast) > ($1.episodeInfo.pubDate ?? .distantPast) }
        .prefix(50)
        .map { $0 } // Convert SubSequence back to Array
    }.value

    // 3. Update UI on MainActor
    self.latestEpisodes = sortedEpisodes
    logger.info("Loaded \(self.latestEpisodes.count) latest episodes (background processed)")

    // Update auto-play candidates
    updateAutoPlayCandidates()
  }

  /// Update the audio manager's auto-play candidates with unplayed episodes
  private func updateAutoPlayCandidates() {
    let unplayedEpisodes = latestEpisodes.filter { !$0.isCompleted }
    let playbackEpisodes = unplayedEpisodes.compactMap { episode -> PlaybackEpisode? in
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
    EnhancedAudioManager.shared.updateAutoPlayCandidates(playbackEpisodes)
    logger.info("Updated auto-play candidates with \(playbackEpisodes.count) unplayed episodes")
  }

  // MARK: - Loading with State Wrappers

  /// Load saved episodes with loading state indicator
  private func loadSavedEpisodesWithState() async {
    isLoadingSaved = true
    await loadSavedEpisodes()
    isLoadingSaved = false
  }

  /// Load downloaded episodes with loading state indicator
  private func loadDownloadedEpisodesWithState() async {
    isLoadingDownloaded = true
    await loadDownloadedEpisodes()
    isLoadingDownloaded = false
  }

  /// Load latest episodes with loading state indicator
  private func loadLatestEpisodesWithState() async {
    isLoadingLatest = true
    await loadLatestEpisodes()
    isLoadingLatest = false
  }

  // MARK: - Helper Methods

  /// Create a LibraryEpisode from EpisodeDownloadModel - always succeeds using stored data
  private func createLibraryEpisode(from model: EpisodeDownloadModel) -> LibraryEpisode {
    // Try to find full episode info from podcasts first
    if let (podcastTitle, episodeTitle) = parseEpisodeKey(model.id) {
      // Verify parsed titles match stored titles (catches mis-parsing due to | in episode titles)
      if podcastTitle == model.podcastTitle && episodeTitle == model.episodeTitle {
        // Try to find full podcast info for richer data using O(1) lookup
        if let podcast = podcastTitleMap[podcastTitle],
           let episode = podcast.podcastInfo.episodes.first(where: { $0.title == episodeTitle }) {
          return LibraryEpisode(
            id: model.id,
            podcastTitle: podcastTitle,
            imageURL: episode.imageURL ?? podcast.podcastInfo.imageURL,
            language: podcast.podcastInfo.language,
            episodeInfo: episode,
            isStarred: model.isStarred,
            isDownloaded: model.localAudioPath != nil,
            isCompleted: model.isCompleted,
            lastPlaybackPosition: model.lastPlaybackPosition
          )
        }
      }
    }

    // Fallback: use the stored data from EpisodeDownloadModel directly
    // This handles episodes with special characters, unsubscribed podcasts, etc.
    let durationSeconds: Int? = model.duration > 0 ? Int(model.duration) : nil
    let episodeInfo = PodcastEpisodeInfo(
      title: model.episodeTitle,
      podcastEpisodeDescription: nil,
      pubDate: model.pubDate,
      audioURL: model.audioURL,
      imageURL: model.imageURL,
      duration: durationSeconds,
      guid: nil
    )

    return LibraryEpisode(
      id: model.id,
      podcastTitle: model.podcastTitle,
      imageURL: model.imageURL,
      language: "en",
      episodeInfo: episodeInfo,
      isStarred: model.isStarred,
      isDownloaded: model.localAudioPath != nil,
      isCompleted: model.isCompleted,
      lastPlaybackPosition: model.lastPlaybackPosition
    )
  }

  /// Parse episode key, supporting both new format (Unit Separator) and old format (|) for backward compatibility
  private func parseEpisodeKey(_ episodeKey: String) -> (podcastTitle: String, episodeTitle: String)? {
    // Try new format first (Unit Separator)
    if let delimiterIndex = episodeKey.range(of: Self.episodeKeyDelimiter) {
      let podcastTitle = String(episodeKey[..<delimiterIndex.lowerBound])
      let episodeTitle = String(episodeKey[delimiterIndex.upperBound...])
      return (podcastTitle, episodeTitle)
    }

    // Fall back to old format (|) for backward compatibility
    if let lastPipeIndex = episodeKey.lastIndex(of: "|") {
      let podcastTitle = String(episodeKey[..<lastPipeIndex])
      let episodeTitle = String(episodeKey[episodeKey.index(after: lastPipeIndex)...])
      return (podcastTitle, episodeTitle)
    }

    return nil
  }

  private func findEpisodeInfo(for model: EpisodeDownloadModel) -> LibraryEpisode? {
    // Parse the episode key to get podcast title and episode title
    guard let (podcastTitle, episodeTitle) = parseEpisodeKey(model.id) else {
      logger.warning("Failed to parse episode key: \(model.id)")
      // Fallback: use the stored data from EpisodeDownloadModel
      return createFallbackLibraryEpisode(from: model)
    }

    // Find the podcast using O(1) lookup
    if let podcast = podcastTitleMap[podcastTitle],
       let episode = podcast.podcastInfo.episodes.first(where: { $0.title == episodeTitle }) {
      // Found the full episode info
      return LibraryEpisode(
        id: model.id,
        podcastTitle: podcastTitle,
        imageURL: episode.imageURL ?? podcast.podcastInfo.imageURL,
        language: podcast.podcastInfo.language,
        episodeInfo: episode,
        isStarred: model.isStarred,
        isDownloaded: model.localAudioPath != nil,
        isCompleted: model.isCompleted,
        lastPlaybackPosition: model.lastPlaybackPosition
      )
    }

    // Fallback: use the stored data from EpisodeDownloadModel
    // This handles cases where the podcast was unsubscribed or episode removed from RSS
    return createFallbackLibraryEpisode(from: model)
  }

  /// Create a LibraryEpisode from EpisodeDownloadModel's stored data when the podcast isn't in the database
  private func createFallbackLibraryEpisode(from model: EpisodeDownloadModel) -> LibraryEpisode {
    // Create a minimal PodcastEpisodeInfo from the stored data
    let durationSeconds: Int? = model.duration > 0 ? Int(model.duration) : nil
    let episodeInfo = PodcastEpisodeInfo(
      title: model.episodeTitle,
      podcastEpisodeDescription: nil,
      pubDate: model.pubDate,
      audioURL: model.audioURL,
      imageURL: model.imageURL,
      duration: durationSeconds,
      guid: nil
    )

    return LibraryEpisode(
      id: model.id,
      podcastTitle: model.podcastTitle,
      imageURL: model.imageURL,
      language: "en",  // Default language when unknown
      episodeInfo: episodeInfo,
      isStarred: model.isStarred,
      isDownloaded: model.localAudioPath != nil,
      isCompleted: model.isCompleted,
      lastPlaybackPosition: model.lastPlaybackPosition
    )
  }

  private func getEpisodeModel(for key: String) -> EpisodeDownloadModel? {
    guard let context = modelContext else { return nil }

    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == key }
    )

    return try? context.fetch(descriptor).first
  }

  // MARK: - Refresh All Podcasts

  func refreshAllPodcasts() async {
    guard let context = modelContext else {
      logger.warning("ModelContext is nil, cannot refresh")
      return
    }

    isLoading = true
    error = nil

    let podcastCount = self.podcastInfoModelList.count
    logger.info("Starting parallel refresh of \(podcastCount) podcast feeds")

    // Extract RSS URLs and model IDs before entering TaskGroup
    let modelData: [(id: UUID, rssUrl: String)] = self.podcastInfoModelList.map { ($0.id, $0.podcastInfo.rssUrl) }

    // Use TaskGroup to fetch all podcasts in parallel
    let results = await withTaskGroup(of: (UUID, PodcastInfo?).self) { group -> [(UUID, PodcastInfo?)] in
      for (id, rssUrl) in modelData {
        group.addTask {
          do {
            let updatedPodcast = try await self.service.fetchPodcast(from: rssUrl)
            return (id, updatedPodcast)
          } catch {
            return (id, nil)
          }
        }
      }

      var collected: [(UUID, PodcastInfo?)] = []
      for await result in group {
        collected.append(result)
      }
      return collected
    }

    // Update models
    var successCount = 0
    for (id, updatedPodcast) in results {
      if let podcast = updatedPodcast,
         let model = self.podcastInfoModelList.first(where: { $0.id == id }) {
        model.podcastInfo = podcast
        successCount += 1
        logger.info("Updated \(podcast.title) with \(podcast.episodes.count) episodes")
      }
    }
    logger.info("Successfully refreshed \(successCount)/\(podcastCount) podcasts")

    // Save changes
    do {
      try context.save()
      logger.info("Saved all podcast updates")
    } catch {
      logger.error("Failed to save updates: \(error.localizedDescription)")
    }

    // Reload all data
    await loadAll()

    isLoading = false
    logger.info("Finished refreshing all podcasts")
  }
}
