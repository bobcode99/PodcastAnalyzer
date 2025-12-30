//
//  EnhancedAudioManager.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//

//
//  EnhancedAudioManager.swift
//  PodcastAnalyzer
//
//  Manages audio playback with background support, Now Playing info, and transcript tracking
//

import AVFoundation
import Combine
import Foundation
import MediaPlayer
import os.log

// MARK: - Playback State Notification
extension Notification.Name {
  static let playbackPositionDidUpdate = Notification.Name("playbackPositionDidUpdate")
}

struct PlaybackPositionUpdate {
  let episodeTitle: String
  let podcastTitle: String
  let position: TimeInterval
  let duration: TimeInterval
  let audioURL: String  // Added: needed to create new models
}

@Observable
class EnhancedAudioManager: NSObject {
  static let shared = EnhancedAudioManager()

  var player: AVPlayer?
  var isPlaying: Bool = false
  var currentEpisode: PlaybackEpisode?
  var currentTime: TimeInterval = 0
  var duration: TimeInterval = 0
  var playbackRate: Float = 1.0

  var currentCaption: String = ""
  var captionSegments: [CaptionSegment] = []

  // Queue management
  var queue: [PlaybackEpisode] = []
  var hasRestoredLastEpisode: Bool = false

  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "AudioManager")

  // Use Unit Separator (U+001F) as delimiter - same as EpisodeDownloadModel
  private static let episodeKeyDelimiter = "\u{1F}"

  private enum Keys {
    static let lastEpisodeTitle = "lastEpisodeTitle"
    static let lastPodcastTitle = "lastPodcastTitle"
    static let lastPlaybackTime = "lastPlaybackTime"
    static let lastAudioURL = "lastAudioURL"
    static let playbackRate = "playbackRate"
    static let lastImageURL = "lastImageURL"
    static let defaultPlaybackSpeed = "defaultPlaybackSpeed"
  }

  override private init() {
    super.init()
    setupAudioSession()
    setupRemoteControls()
    // Critical for remote commands!
    UIApplication.shared.beginReceivingRemoteControlEvents()
    loadPlaybackRate()
  }

  private func setupAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio, options: [])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      logger.info("Audio session configured for background playback")
    } catch {
      logger.error("Audio session failed: \(error.localizedDescription)")
    }
  }

  private func setupRemoteControls() {
    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] _ in
      self?.resume()
      return .success
    }

    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.pause()
      return .success
    }

    // Skip 15 seconds – fixed with NSNumber
    commandCenter.skipForwardCommand.isEnabled = true
    commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 15)]
    commandCenter.skipForwardCommand.addTarget { [weak self] _ in
      self?.skipForward(seconds: 15)
      return .success
    }

    commandCenter.skipBackwardCommand.isEnabled = true
    commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
    commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
      self?.skipBackward(seconds: 15)
      return .success
    }

    commandCenter.changePlaybackPositionCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      self?.seek(to: event.positionTime)
      return .success
    }
  }

  // MARK: - Play
  func play(
    episode: PlaybackEpisode, audioURL: String, startTime: TimeInterval = 0,
    imageURL: String? = nil, useDefaultSpeed: Bool = false
  ) {
    guard let url = URL(string: audioURL) else { return }

    if currentEpisode?.id == episode.id, player != nil {
      if isPlaying { pause() } else { resume() }
      return
    }

    cleanup()

    // IMPORTANT: Reset duration and currentTime for new episode
    // This prevents showing old duration in Now Playing
    duration = 0
    currentTime = 0

    // Apply default speed from settings for new episodes
    if useDefaultSpeed {
      let defaultSpeed = UserDefaults.standard.float(forKey: Keys.defaultPlaybackSpeed)
      if defaultSpeed > 0 {
        playbackRate = defaultSpeed
        UserDefaults.standard.set(defaultSpeed, forKey: Keys.playbackRate)
      }
    }

    let playerItem = AVPlayerItem(url: url)
    player = AVPlayer(playerItem: playerItem)
    currentEpisode = episode

    // Update Now Playing info (duration will be 0 initially, updated when available)
    updateNowPlayingInfo(imageURL: imageURL ?? episode.imageURL)

    if startTime > 0 {
      player?.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
    }

    setupTimeObserver()
    setupPlayerObservers(playerItem: playerItem)

    player?.play()
    player?.rate = playbackRate
    isPlaying = true

    savePlaybackState(imageURL: imageURL ?? episode.imageURL)
    loadCaptions(episode: episode)
  }

  // MARK: - Controls – always update Now Playing
  func pause() {
    player?.pause()
    isPlaying = false
    updateNowPlayingPlaybackRate()
    savePlaybackState()
    postPlaybackPositionUpdate()
  }

  func resume() {
    // If we have a restored episode but no player, start playback
    if player == nil, let episode = currentEpisode {
      play(
        episode: episode,
        audioURL: episode.audioURL,
        startTime: currentTime,
        imageURL: episode.imageURL,
        useDefaultSpeed: false
      )
      return
    }

    player?.play()
    player?.rate = playbackRate
    isPlaying = true
    updateNowPlayingPlaybackRate()
    savePlaybackState()
  }

  func stop() {
    cleanup()
    currentEpisode = nil
    currentTime = 0
    duration = 0
    isPlaying = false
    currentCaption = ""
    captionSegments = []
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    logger.info("Playback stopped")
  }

  func seek(to time: TimeInterval) {
    let cmTime = CMTime(seconds: time, preferredTimescale: 600)
    player?.seek(to: cmTime) { [weak self] _ in
      self?.updateNowPlayingCurrentTime()
      self?.savePlaybackState()
      self?.postPlaybackPositionUpdate()
    }
  }

  func skipForward(seconds: TimeInterval = 15) {
    let newTime = min(currentTime + seconds, duration)
    seek(to: newTime)
  }

  func skipBackward(seconds: TimeInterval = 15) {
    let newTime = max(currentTime - seconds, 0)
    seek(to: newTime)
  }

  func setPlaybackRate(_ rate: Float) {
    playbackRate = rate
    player?.rate = isPlaying ? rate : 0
    UserDefaults.standard.set(rate, forKey: Keys.playbackRate)
    updateNowPlayingPlaybackRate()
    logger.info("Playback rate set to \(rate)x")
  }

  // MARK: - Queue Management

  /// Add an episode to the end of the queue
  func addToQueue(_ episode: PlaybackEpisode) {
    // Don't add if already in queue or is current episode
    guard !queue.contains(where: { $0.id == episode.id }),
      currentEpisode?.id != episode.id
    else {
      logger.info("Episode already in queue or currently playing")
      return
    }
    queue.append(episode)
    logger.info("Added to queue: \(episode.title)")
  }

  /// Add an episode to play next (first position in queue)
  func playNext(_ episode: PlaybackEpisode) {
    // Remove if already in queue
    queue.removeAll { $0.id == episode.id }
    // Don't add if currently playing
    guard currentEpisode?.id != episode.id else {
      logger.info("Episode is currently playing")
      return
    }
    queue.insert(episode, at: 0)
    logger.info("Play next: \(episode.title)")
  }

  /// Remove an episode from the queue
  func removeFromQueue(_ episode: PlaybackEpisode) {
    queue.removeAll { $0.id == episode.id }
    logger.info("Removed from queue: \(episode.title)")
  }

  /// Remove episode at specific index
  func removeFromQueue(at index: Int) {
    guard index >= 0 && index < queue.count else { return }
    let episode = queue.remove(at: index)
    logger.info("Removed from queue at index \(index): \(episode.title)")
  }

  /// Move episode in queue
  func moveInQueue(from source: IndexSet, to destination: Int) {
    // Manual implementation of move since Array.move(fromOffsets:toOffset:) requires SwiftUI import
    var items = queue
    let sourceIndices = Array(source).sorted(by: >)

    // Remove items from source positions (in reverse to preserve indices)
    var movedItems: [PlaybackEpisode] = []
    for index in sourceIndices {
      movedItems.insert(items.remove(at: index), at: 0)
    }

    // Calculate adjusted destination
    let adjustedDestination = destination - source.filter { $0 < destination }.count

    // Insert at destination
    for (offset, item) in movedItems.enumerated() {
      items.insert(item, at: adjustedDestination + offset)
    }

    queue = items
  }

  /// Clear the entire queue
  func clearQueue() {
    queue.removeAll()
    logger.info("Queue cleared")
  }

  /// Play the next episode in queue
  func playNextInQueue() {
    guard !queue.isEmpty else {
      logger.info("Queue is empty")
      return
    }

    let nextEpisode = queue.removeFirst()
    play(
      episode: nextEpisode,
      audioURL: nextEpisode.audioURL,
      startTime: 0,
      imageURL: nextEpisode.imageURL,
      useDefaultSpeed: false
    )
    logger.info("Playing next in queue: \(nextEpisode.title)")
  }

  /// Skip to a specific episode in the queue
  func skipToQueueItem(at index: Int) {
    guard index >= 0 && index < queue.count else { return }

    // Remove all items before the selected one
    let episodesToRemove = Array(queue.prefix(index))
    queue.removeFirst(index)

    // Play the selected episode
    playNextInQueue()

    logger.info("Skipped \(episodesToRemove.count) episodes in queue")
  }

  /// Restore the last played episode on app launch (without playing)
  func restoreLastEpisode() {
    guard !hasRestoredLastEpisode else { return }
    hasRestoredLastEpisode = true

    guard let state = loadLastPlaybackState() else {
      logger.info("No previous playback state to restore")
      return
    }

    // Just set the current episode info without playing
    currentEpisode = state.episode
    currentTime = state.time
    duration = 0  // Will be updated when user plays

    logger.info("Restored last episode: \(state.episode.title) at \(state.time)s")
  }

  // MARK: - Caption Management

  private func loadCaptions(episode: PlaybackEpisode) {
    Task {
      let fileStorage = FileStorageManager.shared

      if await fileStorage.captionFileExists(for: episode.title, podcastTitle: episode.podcastTitle)
      {
        do {
          let srtContent = try await fileStorage.loadCaptionFile(
            for: episode.title,
            podcastTitle: episode.podcastTitle
          )
          let segments = parseSRT(srtContent)

          await MainActor.run {
            self.captionSegments = segments
            logger.info("Loaded \(segments.count) caption segments")
          }
        } catch {
          logger.error("Failed to load captions: \(error.localizedDescription)")
        }
      }
    }
  }

  private func parseSRT(_ srtContent: String) -> [CaptionSegment] {
    var segments: [CaptionSegment] = []

    // Normalize line endings
    let normalizedText = srtContent.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    // Use regex to split SRT into entries (handles single or double newline separators)
    // Pattern matches: index number at start of line, followed by timestamp line
    let entryPattern =
      #"(?:^|\n)(\d+)\n(\d{2}:\d{2}:\d{2}[,\.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]\d{3})\n"#

    guard let regex = try? NSRegularExpression(pattern: entryPattern, options: []) else {
      logger.error("Failed to create SRT regex pattern")
      return segments
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

      guard let startTime = parseTimeString(startTimeStr),
        let endTime = parseTimeString(endTimeStr)
      else { continue }

      // Find text: starts after this match, ends at next match or end of string
      let textStart = match.range.location + match.range.length
      let textEnd: Int
      if index + 1 < matches.count {
        textEnd = matches[index + 1].range.location
      } else {
        textEnd = nsText.length
      }

      guard textStart < textEnd else { continue }

      let textRange = NSRange(location: textStart, length: textEnd - textStart)
      let text = nsText.substring(with: textRange)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\n", with: " ")

      guard !text.isEmpty else { continue }

      segments.append(
        CaptionSegment(
          startTime: startTime,
          endTime: endTime,
          text: text
        ))
    }

    return segments
  }

  private func parseTimeString(_ timeString: String) -> TimeInterval? {
    // Format: 00:00:10,500
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

  private func updateCurrentCaption() {
    guard !captionSegments.isEmpty else {
      currentCaption = ""
      return
    }

    // Find the caption segment for current time
    if let segment = captionSegments.first(where: { segment in
      currentTime >= segment.startTime && currentTime <= segment.endTime
    }) {
      currentCaption = segment.text
    } else {
      currentCaption = ""
    }
  }

  // MARK: - Now Playing Info

  private func updateNowPlayingInfo(imageURL: String? = nil) {
    guard let episode = currentEpisode else { return }

    var nowPlayingInfo = [String: Any]()
    nowPlayingInfo[MPMediaItemPropertyTitle] = episode.title
    nowPlayingInfo[MPMediaItemPropertyArtist] = episode.podcastTitle
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

    // Load artwork asynchronously using URLSession (not Data(contentsOf:))
    if let imageURLString = imageURL ?? episode.imageURL,
      let url = URL(string: imageURLString)
    {
      Task.detached { [weak self] in
        do {
          let (data, _) = try await URLSession.shared.data(from: url)
          if let image = UIImage(data: data) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run {
              var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
              info[MPMediaItemPropertyArtwork] = artwork
              MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
          }
        } catch {
          self?.logger.error("Failed to load artwork: \(error.localizedDescription)")
        }
      }
    }
  }

  private func updateNowPlayingCurrentTime() {
    var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  private func updateNowPlayingDuration() {
    guard duration > 0 else { return }
    var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    logger.info("Updated Now Playing duration: \(Int(self.duration))s")
  }

  private func updateNowPlayingPlaybackRate() {
    var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  // MARK: - State Persistence

  /// Posts a notification with current playback position for SwiftData persistence
  private func postPlaybackPositionUpdate() {
    guard let episode = currentEpisode, duration > 0 else { return }

    let update = PlaybackPositionUpdate(
      episodeTitle: episode.title,
      podcastTitle: episode.podcastTitle,
      position: currentTime,
      duration: duration,
      audioURL: episode.audioURL
    )

    NotificationCenter.default.post(
      name: .playbackPositionDidUpdate,
      object: nil,
      userInfo: ["update": update]
    )
  }

  private func savePlaybackState(imageURL: String? = nil) {
    guard let episode = currentEpisode else { return }

    UserDefaults.standard.set(episode.title, forKey: Keys.lastEpisodeTitle)
    UserDefaults.standard.set(episode.podcastTitle, forKey: Keys.lastPodcastTitle)
    UserDefaults.standard.set(currentTime, forKey: Keys.lastPlaybackTime)
    UserDefaults.standard.set(episode.audioURL, forKey: Keys.lastAudioURL)
    if let imageURL = imageURL {
      UserDefaults.standard.set(imageURL, forKey: Keys.lastImageURL)
    }

    logger.debug("Saved playback state: \(episode.title) at \(self.currentTime)s")
  }

  func loadLastPlaybackState() -> (episode: PlaybackEpisode, time: TimeInterval, imageURL: String?)?
  {
    guard let title = UserDefaults.standard.string(forKey: Keys.lastEpisodeTitle),
      let podcastTitle = UserDefaults.standard.string(forKey: Keys.lastPodcastTitle),
      let audioURL = UserDefaults.standard.string(forKey: Keys.lastAudioURL)
    else {
      return nil
    }

    let time = UserDefaults.standard.double(forKey: Keys.lastPlaybackTime)
    let imageURL = UserDefaults.standard.string(forKey: Keys.lastImageURL)

    let episode = PlaybackEpisode(
      id: "\(podcastTitle)\(Self.episodeKeyDelimiter)\(title)",
      title: title,
      podcastTitle: podcastTitle,
      audioURL: audioURL,
      imageURL: imageURL
    )

    return (episode, time, imageURL)
  }

  private func loadPlaybackRate() {
    let savedRate = UserDefaults.standard.float(forKey: Keys.playbackRate)
    playbackRate = savedRate > 0 ? savedRate : 1.0
  }

  func clearPlaybackState() {
    UserDefaults.standard.removeObject(forKey: Keys.lastEpisodeTitle)
    UserDefaults.standard.removeObject(forKey: Keys.lastPodcastTitle)
    UserDefaults.standard.removeObject(forKey: Keys.lastPlaybackTime)
    UserDefaults.standard.removeObject(forKey: Keys.lastAudioURL)
    UserDefaults.standard.removeObject(forKey: Keys.lastImageURL)
  }

  // MARK: - Time Observer

  private func setupTimeObserver() {
    let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
    timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      [weak self] time in
      guard let self = self else { return }

      self.currentTime = time.seconds

      // Track if duration was previously unknown
      let previousDuration = self.duration

      if let newDuration = self.player?.currentItem?.duration.seconds,
        newDuration.isFinite
      {
        self.duration = newDuration

        // Update Now Playing duration when it first becomes available
        // (transition from 0 or invalid to valid duration)
        if previousDuration <= 0 && newDuration > 0 {
          self.updateNowPlayingDuration()
        }
      }

      // Update current caption
      self.updateCurrentCaption()

      // Update Now Playing time every second
      if Int(self.currentTime * 10) % 10 == 0 {
        self.updateNowPlayingCurrentTime()
      }

      // Auto-save every 5 seconds and post notification for SwiftData persistence
      if Int(self.currentTime) % 5 == 0 {
        self.savePlaybackState()
        self.postPlaybackPositionUpdate()
      }
    }
  }

  // MARK: - Player Observers

  private func setupPlayerObservers(playerItem: AVPlayerItem) {
    // Observe playback end
    NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
      .sink { [weak self] _ in
        self?.handlePlaybackEnded()
      }
      .store(in: &cancellables)

    // Observe playback stall
    NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled, object: playerItem)
      .sink { [weak self] _ in
        self?.logger.warning("Playback stalled")
      }
      .store(in: &cancellables)
  }

  private func handlePlaybackEnded() {
    logger.info("Playback ended")
    isPlaying = false
    currentTime = 0

    // Check if there's a next episode in queue
    if !queue.isEmpty {
      logger.info("Playing next episode from queue")
      playNextInQueue()
    } else {
      clearPlaybackState()
    }
  }

  // MARK: - Cleanup

  private func cleanup() {
    if let observer = timeObserver {
      player?.removeTimeObserver(observer)
      timeObserver = nil
    }

    player?.pause()
    player = nil
    cancellables.removeAll()
  }

  deinit {
    cleanup()
  }
}

// MARK: - Supporting Models

struct PlaybackEpisode: Identifiable, Codable {
  let id: String
  let title: String
  let podcastTitle: String
  let audioURL: String
  var imageURL: String?
  var episodeDescription: String?
  var pubDate: Date?
  var duration: Int?
  var guid: String?
}

struct CaptionSegment: Identifiable {
  let id = UUID()
  let startTime: TimeInterval
  let endTime: TimeInterval
  let text: String
}
