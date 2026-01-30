//
//  ExpandedPlayerViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for expanded player view - supports Apple Podcasts style UI
//

import Observation
import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
@Observable
final class ExpandedPlayerViewModel {
  var isPlaying: Bool = false
  var episodeTitle: String = ""
  var podcastTitle: String = ""
  var imageURL: URL?
  var progress: Double = 0
  var currentTime: TimeInterval = 0
  var duration: TimeInterval = 1
  var playbackSpeed: Float = 1.0
  var currentEpisode: PlaybackEpisode?
  var episodeDate: Date?
  var isStarred: Bool = false
  var isCompleted: Bool = false
  var queue: [PlaybackEpisode] = []
  var episodeDescription: String?
  var downloadState: DownloadState = .notDownloaded
  var podcastModel: PodcastInfoModel?

  // Sleep timer properties
  var sleepTimerOption: SleepTimerOption = .off
  var sleepTimerRemaining: TimeInterval = 0

  // Transcript properties
  var hasTranscript: Bool = false
  var transcriptSegments: [TranscriptSegment] = []
  var transcriptSearchQuery: String = ""
  var displayMode: SubtitleDisplayMode = .originalOnly

  @ObservationIgnored
  private let audioManager = EnhancedAudioManager.shared

  @ObservationIgnored
  private let downloadManager = DownloadManager.shared

  @ObservationIgnored
  private let fileStorage = FileStorageManager.shared

  @ObservationIgnored
  private let subtitleSettings = SubtitleSettingsManager.shared

  @ObservationIgnored
  private var updateTimer: Timer?

  @ObservationIgnored
  private let applePodcastService = ApplePodcastService()

  @ObservationIgnored
  private var shareTask: Task<Void, Never>?

  @ObservationIgnored
  private var modelContext: ModelContext?

  @ObservationIgnored
  private var lastLoadedEpisodeId: String?

  // Use Unit Separator (U+001F) as delimiter - same as DownloadManager
  private static let episodeKeyDelimiter = "\u{1F}"

  init() {
    // Update state immediately before setting up timer
    updateState()
    setupUpdateTimer()
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    loadEpisodeState()
    loadPodcastModel()
  }

  private func setupUpdateTimer() {
    updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        self.updateState()
      }
    }
  }

  private func updateState() {
    if let episode = audioManager.currentEpisode {
      let previousEpisodeId = currentEpisode?.id

      // Only write properties when values actually changed to avoid unnecessary SwiftUI re-renders
      if currentEpisode?.id != episode.id { currentEpisode = episode }
      if isPlaying != audioManager.isPlaying { isPlaying = audioManager.isPlaying }
      if episodeTitle != episode.title { episodeTitle = episode.title }
      if podcastTitle != episode.podcastTitle { podcastTitle = episode.podcastTitle }

      if let imageURLString = episode.imageURL {
        let newURL = URL(string: imageURLString)
        if imageURL != newURL { imageURL = newURL }
      }

      if episodeDate != episode.pubDate { episodeDate = episode.pubDate }

      let newCurrentTime = audioManager.currentTime
      let newDuration = audioManager.duration
      if currentTime != newCurrentTime { currentTime = newCurrentTime }
      if duration != newDuration { duration = newDuration }
      if playbackSpeed != audioManager.playbackRate { playbackSpeed = audioManager.playbackRate }

      if newDuration > 0 {
        let newProgress = newCurrentTime / newDuration
        if progress != newProgress { progress = newProgress }
      }

      // Update queue
      let newQueue = audioManager.queue
      if queue != newQueue { queue = newQueue }

      // Update download state
      let newDownloadState = downloadManager.getDownloadState(
        episodeTitle: episode.title,
        podcastTitle: episode.podcastTitle
      )
      if downloadState != newDownloadState { downloadState = newDownloadState }

      // Sync display mode from settings
      if displayMode != subtitleSettings.displayMode { displayMode = subtitleSettings.displayMode }

      // Sync sleep timer state
      if sleepTimerOption != audioManager.sleepTimerOption { sleepTimerOption = audioManager.sleepTimerOption }
      if sleepTimerRemaining != audioManager.sleepTimerRemaining { sleepTimerRemaining = audioManager.sleepTimerRemaining }

      // Reload episode state when episode changes
      if previousEpisodeId != episode.id {
        loadEpisodeState()
        loadPodcastModel()
        loadTranscript()
      }
    }
  }

  // MARK: - SwiftData Loading

  private func loadEpisodeState() {
    guard let context = modelContext, let episode = currentEpisode else { return }

    let episodeKey = "\(episode.podcastTitle)\(Self.episodeKeyDelimiter)\(episode.title)"

    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == episodeKey }
    )

    do {
      if let model = try context.fetch(descriptor).first {
        isStarred = model.isStarred
        isCompleted = model.isCompleted
      } else {
        isStarred = false
        isCompleted = false
      }
    } catch {
      print("Failed to load episode state: \(error)")
    }
  }

  private func loadPodcastModel() {
    guard let context = modelContext else { return }

    let podcastName = podcastTitle
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.title == podcastName }
    )

    do {
      podcastModel = try context.fetch(descriptor).first
    } catch {
      print("Failed to load podcast model: \(error)")
    }
  }

  private func getOrCreateEpisodeModel() -> EpisodeDownloadModel? {
    guard let context = modelContext, let episode = currentEpisode else { return nil }

    let episodeKey = "\(episode.podcastTitle)\(Self.episodeKeyDelimiter)\(episode.title)"

    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == episodeKey }
    )

    do {
      if let existing = try context.fetch(descriptor).first {
        return existing
      } else {
        // Create new model
        let model = EpisodeDownloadModel(
          episodeTitle: episode.title,
          podcastTitle: episode.podcastTitle,
          audioURL: episode.audioURL,
          imageURL: episode.imageURL,
          pubDate: episode.pubDate
        )
        context.insert(model)
        try context.save()
        return model
      }
    } catch {
      print("Failed to get/create episode model: \(error)")
      return nil
    }
  }

  // MARK: - Computed Properties

  /// Whether duration is still loading (not yet available from player)
  var isDurationLoading: Bool {
    duration <= 0
  }

  var currentTimeString: String {
    formatTime(currentTime)
  }

  var remainingTimeString: String {
    guard duration > 0 else { return "--:--" }
    let remaining = duration - currentTime
    return "-" + formatTime(remaining)
  }

  var durationString: String {
    guard duration > 0 else { return "--:--" }
    return formatTime(duration)
  }

  // MARK: - Playback Actions

  func togglePlayPause() {
    if isPlaying {
      audioManager.pause()
    } else {
      audioManager.resume()
    }
  }

  func skipForward() {
    audioManager.skipForward(seconds: 30)
  }

  func skipBackward() {
    audioManager.skipBackward(seconds: 15)
  }

  func seekToProgress(_ progress: Double) {
    let newTime = progress * duration
    audioManager.seek(to: newTime)
  }

  func setPlaybackSpeed(_ speed: Float) {
    audioManager.setPlaybackRate(speed)
  }

  // MARK: - Episode Actions

  func toggleStar() {
    isStarred.toggle()

    // Persist to SwiftData
    guard let model = getOrCreateEpisodeModel() else { return }
    model.isStarred = isStarred
    try? modelContext?.save()
  }

  func togglePlayed() {
    isCompleted.toggle()

    // Persist to SwiftData
    guard let model = getOrCreateEpisodeModel() else { return }
    model.isCompleted = isCompleted
    if !isCompleted {
      model.lastPlaybackPosition = 0
    }
    try? modelContext?.save()
  }

  // MARK: - Sleep Timer

  func setSleepTimer(_ option: SleepTimerOption) {
    audioManager.setSleepTimer(option)
  }

  var isSleepTimerActive: Bool {
    audioManager.isSleepTimerActive
  }

  var sleepTimerRemainingFormatted: String {
    audioManager.sleepTimerRemainingFormatted
  }

  func shareEpisode() {
    guard let episode = currentEpisode else { return }

    // Cancel previous share task
    shareTask?.cancel()

    // Try to find Apple Podcast URL first with timeout
    shareTask = Task {
      do {
        let appleUrl = try await withTimeout(seconds: 5) {
          try await self.applePodcastService.getAppleEpisodeLink(
            episodeTitle: episode.title,
            episodeGuid: episode.guid
          )
        }
        if !Task.isCancelled {
          shareWithURL(appleUrl ?? episode.audioURL)
        }
      } catch {
        if !Task.isCancelled {
          // On error, fall back to audio URL
          shareWithURL(episode.audioURL)
        }
      }
    }
  }

  private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask {
        try await operation()
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw CancellationError()
      }
      let result = try await group.next()!
      group.cancelAll()
      return result
    }
  }

  private func shareWithURL(_ urlString: String?) {
    guard let urlString = urlString, let url = URL(string: urlString) else { return }
    PlatformShareSheet.share(url: url)
  }

  func playNextCurrentEpisode() {
    guard let episode = currentEpisode else { return }
    audioManager.playNext(episode)
  }

  // MARK: - Download Actions

  var hasLocalAudio: Bool {
    if case .downloaded = downloadState { return true }
    return false
  }

  var audioURL: String? {
    currentEpisode?.audioURL
  }

  func startDownload() {
    guard let episode = currentEpisode else { return }
    // Create a PodcastEpisodeInfo to pass to download manager
    let episodeInfo = PodcastEpisodeInfo(
      title: episode.title,
      podcastEpisodeDescription: episode.episodeDescription,
      pubDate: episode.pubDate,
      audioURL: episode.audioURL,
      imageURL: episode.imageURL,
      duration: episode.duration,
      guid: episode.guid
    )
    downloadManager.downloadEpisode(
      episode: episodeInfo,
      podcastTitle: episode.podcastTitle,
      language: "en"  // Default language
    )
  }

  func cancelDownload() {
    guard let episode = currentEpisode else { return }
    downloadManager.cancelDownload(
      episodeTitle: episode.title,
      podcastTitle: episode.podcastTitle
    )
  }

  func deleteDownload() {
    guard let episode = currentEpisode else { return }
    downloadManager.deleteDownload(
      episodeTitle: episode.title,
      podcastTitle: episode.podcastTitle
    )
  }

  func reportConcern() {
    // Open a report URL or show an alert
    // For now, this can be a placeholder that opens Apple's podcast report page
    guard let url = URL(string: "https://www.apple.com/feedback/podcasts.html") else { return }
    #if os(iOS)
    UIApplication.shared.open(url)
    #else
    NSWorkspace.shared.open(url)
    #endif
  }

  // MARK: - Queue Actions

  func skipToQueueItem(at index: Int) {
    audioManager.skipToQueueItem(at: index)
  }

  func removeFromQueue(at index: Int) {
    audioManager.removeFromQueue(at: index)
  }

  func moveInQueue(from source: IndexSet, to destination: Int) {
    audioManager.moveInQueue(from: source, to: destination)
  }

  // MARK: - Transcript

  /// Current segment based on playback time
  var currentSegmentId: Int? {
    let time = currentTime
    return transcriptSegments.first { segment in
      time >= segment.startTime && time <= segment.endTime
    }?.id
  }

  /// Current segment text for display
  var currentSegmentText: String? {
    guard let id = currentSegmentId else { return nil }
    return transcriptSegments.first { $0.id == id }?.text
  }

  /// Filtered segments based on search query
  var filteredTranscriptSegments: [TranscriptSegment] {
    guard !transcriptSearchQuery.isEmpty else {
      return transcriptSegments
    }
    let query = transcriptSearchQuery.lowercased()
    return transcriptSegments.filter { segment in
      segment.text.lowercased().contains(query)
    }
  }

  private func loadTranscript() {
    guard let episode = currentEpisode else {
      hasTranscript = false
      transcriptSegments = []
      return
    }

    // Avoid reloading if already loaded for this episode
    let episodeId = episode.id
    if lastLoadedEpisodeId == episodeId && !transcriptSegments.isEmpty {
      return
    }

    Task {
      let exists = await fileStorage.captionFileExists(
        for: episode.title,
        podcastTitle: episode.podcastTitle
      )

      if exists {
        do {
          let content = try await fileStorage.loadCaptionFile(
            for: episode.title,
            podcastTitle: episode.podcastTitle
          )
          let segments = parseTranscriptSegments(from: content)

          await MainActor.run {
            self.hasTranscript = true
            self.transcriptSegments = segments
            self.lastLoadedEpisodeId = episodeId
          }
        } catch {
          await MainActor.run {
            self.hasTranscript = false
            self.transcriptSegments = []
          }
        }
      } else {
        await MainActor.run {
          self.hasTranscript = false
          self.transcriptSegments = []
        }
      }
    }
  }

  /// Parses SRT content into transcript segments
  private func parseTranscriptSegments(from srtContent: String) -> [TranscriptSegment] {
    var segments: [TranscriptSegment] = []

    let normalizedText = srtContent.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let entryPattern =
      #"(?:^|\n)(\d+)\n(\d{2}:\d{2}:\d{2}[,\.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]\d{3})\n"#

    guard let regex = try? NSRegularExpression(pattern: entryPattern, options: []) else {
      return []
    }

    let nsText = normalizedText as NSString
    let matches = regex.matches(
      in: normalizedText, options: [], range: NSRange(location: 0, length: nsText.length))

    for (index, match) in matches.enumerated() {
      guard match.numberOfRanges >= 4 else { continue }

      let startTimeRange = match.range(at: 2)
      let endTimeRange = match.range(at: 3)

      guard startTimeRange.location != NSNotFound,
        endTimeRange.location != NSNotFound
      else { continue }

      let startTimeStr = nsText.substring(with: startTimeRange)
      let endTimeStr = nsText.substring(with: endTimeRange)

      guard let startTime = parseSRTTime(startTimeStr),
        let endTime = parseSRTTime(endTimeStr)
      else { continue }

      let textStart = match.range.location + match.range.length
      let textEnd: Int
      if index + 1 < matches.count {
        textEnd = matches[index + 1].range.location
      } else {
        textEnd = nsText.length
      }

      guard textStart < textEnd else { continue }

      let textRange = NSRange(location: textStart, length: textEnd - textStart)
      var text = nsText.substring(with: textRange)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\n", with: " ")

      text = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }

      segments.append(
        TranscriptSegment(
          id: index,
          startTime: startTime,
          endTime: endTime,
          text: text
        ))
    }

    return segments
  }

  private func parseSRTTime(_ timeString: String) -> TimeInterval? {
    let components = timeString.replacingOccurrences(of: ",", with: ".").components(
      separatedBy: ":")
    guard components.count == 3 else { return nil }

    guard let hours = Double(components[0]),
      let minutes = Double(components[1]),
      let seconds = Double(components[2])
    else {
      return nil
    }

    return hours * 3600 + minutes * 60 + seconds
  }

  /// Seek to a specific transcript segment
  func seekToSegment(_ segment: TranscriptSegment) {
    audioManager.seek(to: segment.startTime)
    if !isPlaying {
      audioManager.resume()
    }
  }

  // MARK: - Helpers

  private func formatTime(_ time: TimeInterval) -> String {
    guard time.isFinite && time >= 0 else { return "0:00" }

    let hours = Int(time) / 3600
    let minutes = Int(time) / 60 % 60
    let seconds = Int(time) % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }

  deinit {
    MainActor.assumeIsolated {
      cleanup()
    }
  }

  /// Clean up resources. Call this from onDisappear.
  func cleanup() {
    updateTimer?.invalidate()
    updateTimer = nil
  }
}
