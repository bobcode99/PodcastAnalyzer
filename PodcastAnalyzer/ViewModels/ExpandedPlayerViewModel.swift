//
//  ExpandedPlayerViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for expanded player view - supports Apple Podcasts style UI
//

import Combine
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

  private let audioManager = EnhancedAudioManager.shared
  private var updateTimer: Timer?
  private let applePodcastService = ApplePodcastService()
  private var shareCancellable: AnyCancellable?

  init() {
    // Update state immediately before setting up timer
    updateState()
    setupUpdateTimer()
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
      currentEpisode = episode
      isPlaying = audioManager.isPlaying
      episodeTitle = episode.title
      podcastTitle = episode.podcastTitle

      if let imageURLString = episode.imageURL {
        imageURL = URL(string: imageURLString)
      }

      currentTime = audioManager.currentTime
      duration = audioManager.duration
      playbackSpeed = audioManager.playbackRate

      if duration > 0 {
        progress = currentTime / duration
      }

      // Update queue
      queue = audioManager.queue
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
    // TODO: Persist to SwiftData via EpisodeDownloadModel
  }

  func togglePlayed() {
    isCompleted.toggle()
    // TODO: Persist to SwiftData via EpisodeDownloadModel
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
