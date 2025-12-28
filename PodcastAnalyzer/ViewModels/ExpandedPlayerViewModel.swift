//
//  ExpandedPlayerViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for expanded player view - supports Apple Podcasts style UI
//

import Combine
import SwiftData
import SwiftUI

@MainActor
class ExpandedPlayerViewModel: ObservableObject {
  @Published var isPlaying: Bool = false
  @Published var episodeTitle: String = ""
  @Published var podcastTitle: String = ""
  @Published var imageURL: URL?
  @Published var progress: Double = 0
  @Published var currentTime: TimeInterval = 0
  @Published var duration: TimeInterval = 1
  @Published var playbackSpeed: Float = 1.0
  @Published var currentEpisode: PlaybackEpisode?
  @Published var episodeDate: Date?
  @Published var isStarred: Bool = false
  @Published var isCompleted: Bool = false
  @Published var queue: [PlaybackEpisode] = []
  @Published var episodeDescription: String?
  @Published var downloadState: DownloadState = .notDownloaded
  @Published var podcastModel: PodcastInfoModel?

  private let audioManager = EnhancedAudioManager.shared
  private let downloadManager = DownloadManager.shared
  private var updateTimer: Timer?
  private let applePodcastService = ApplePodcastService()
  private var shareCancellable: AnyCancellable?
  private var modelContext: ModelContext?

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
    updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        self.updateState()
      }
    }
  }

  private func updateState() {
    if let episode = audioManager.currentEpisode {
      let previousEpisodeId = currentEpisode?.id
      currentEpisode = episode
      isPlaying = audioManager.isPlaying
      episodeTitle = episode.title
      podcastTitle = episode.podcastTitle

      if let imageURLString = episode.imageURL {
        imageURL = URL(string: imageURLString)
      }

      // Update episode date from current episode
      episodeDate = episode.pubDate

      currentTime = audioManager.currentTime
      duration = audioManager.duration
      playbackSpeed = audioManager.playbackRate

      if duration > 0 {
        progress = currentTime / duration
      }

      // Update queue
      queue = audioManager.queue

      // Update download state
      downloadState = downloadManager.getDownloadState(
        episodeTitle: episode.title,
        podcastTitle: episode.podcastTitle
      )

      // Reload episode state when episode changes
      if previousEpisodeId != episode.id {
        loadEpisodeState()
        loadPodcastModel()
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
      predicate: #Predicate { $0.podcastInfo.title == podcastName }
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

  var currentTimeString: String {
    formatTime(currentTime)
  }

  var remainingTimeString: String {
    let remaining = duration - currentTime
    return "-" + formatTime(remaining)
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

  func shareEpisode() {
    guard let episode = currentEpisode else { return }

    // Try to find Apple Podcast URL first
    shareCancellable = applePodcastService.findAppleEpisodeUrl(
      episodeTitle: episode.title,
      podcastCollectionId: 0  // Search by title only
    )
    .timeout(.seconds(5), scheduler: DispatchQueue.main)
    .sink(
      receiveCompletion: { [weak self] completion in
        if case .failure = completion {
          // On error, fall back to audio URL
          self?.shareWithURL(episode.audioURL)
        }
      },
      receiveValue: { [weak self] appleUrl in
        // Use Apple URL if found, otherwise fall back to audio URL
        self?.shareWithURL(appleUrl ?? episode.audioURL)
      }
    )
  }

  private func shareWithURL(_ urlString: String?) {
    guard let urlString = urlString, let url = URL(string: urlString) else { return }

    let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let rootVC = windowScene.windows.first?.rootViewController
    {
      rootVC.present(activityVC, animated: true)
    }
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
      duration: episode.duration
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
    UIApplication.shared.open(url)
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
    updateTimer?.invalidate()
  }
}
