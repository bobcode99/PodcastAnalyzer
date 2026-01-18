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
import Foundation
import MediaPlayer
import os.log

#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Playback State Notification
extension Notification.Name {
  static let playbackPositionDidUpdate = Notification.Name("playbackPositionDidUpdate")
}

struct PlaybackPositionUpdate: Sendable {
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
  private let maxQueueSize = 50

  // Auto-play candidates (unplayed episodes that can be randomly selected)
  var autoPlayCandidates: [PlaybackEpisode] = []

  // Audio interruption handling - track if we should resume after interruption ends
  private var wasPlayingBeforeInterruption: Bool = false

  private var timeObserver: Any?
  // Task-based observers for Swift 6 concurrency
  private var interruptionTask: Task<Void, Never>?
  private var playerEndedTask: Task<Void, Never>?
  private var playerStalledTask: Task<Void, Never>?
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "AudioManager")

  // Use Unit Separator (U+001F) as delimiter - same as EpisodeDownloadModel
  private static let episodeKeyDelimiter = "\u{1F}"

  private enum Keys {
    static let lastEpisodeTitle = "lastEpisodeTitle"
    static let lastPodcastTitle = "lastPodcastTitle"
    static let lastPlaybackTime = "lastPlaybackTime"
    static let lastDuration = "lastDuration"
    static let lastAudioURL = "lastAudioURL"
    static let playbackRate = "playbackRate"
    static let lastImageURL = "lastImageURL"
    static let defaultPlaybackSpeed = "defaultPlaybackSpeed"
    static let autoPlayNextEpisode = "autoPlayNextEpisode"
  }

  override private init() {
    super.init()
    setupAudioSession()
    setupRemoteControls()
    setupInterruptionObserver()
    #if os(iOS)
    // Critical for remote commands on iOS!
    UIApplication.shared.beginReceivingRemoteControlEvents()
    #endif
    loadPlaybackRate()
  }

  private func setupAudioSession() {
    #if os(iOS)
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio, options: [])
      // Don't activate session here - only activate when actually playing
      logger.info("Audio session configured (will activate when playing)")
    } catch {
      logger.error("Audio session setup failed: \(error.localizedDescription)")
    }
    #else
    // macOS doesn't require AVAudioSession configuration
    logger.info("Audio manager initialized for macOS")
    #endif
  }

  private func activateAudioSession() {
    #if os(iOS)
    do {
      try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
      logger.info("Audio session activated")
    } catch {
      logger.error("Failed to activate audio session: \(error.localizedDescription)")
    }
    #endif
  }

  private func deactivateAudioSession() {
    #if os(iOS)
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      logger.info("Audio session deactivated - other apps can now play")
    } catch {
      logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
    }
    #endif
  }

  private func setupInterruptionObserver() {
    #if os(iOS)
    // Use Task-based async sequence for Swift 6 concurrency
    interruptionTask = Task { @MainActor [weak self] in
      for await notification in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
        self?.handleAudioInterruption(notification)
      }
    }
    logger.info("Audio interruption observer configured")
    #endif
  }

private func handleAudioInterruption(_ notification: Notification) {
    #if os(iOS)
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else { return }

    logger.info("Handling audio interruption: type=\(type.rawValue, privacy: .public)")


    switch type {
    case .began:
        // 1. Mark our state BEFORE we call pause()
        wasPlayingBeforeInterruption = isPlaying
        
        if isPlaying {
            // We use a local pause here to stop the player
            // but we don't necessarily want to treat this as a "user-stop"
            player?.pause()
            isPlaying = false
            updateNowPlayingPlaybackRate()
            logger.info("Interruption began: Audio paused")
        }

    case .ended:
        // 2. Determine if we SHOULD resume
        // We check the system hint AND our manual flag
        var shouldResume = false
        if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                shouldResume = true
            }
        }
        
        // If system says yes OR our manual state says we were playing
        let finalDecisionToResume = shouldResume || wasPlayingBeforeInterruption
        
        if finalDecisionToResume {
            // 3. Mandatory Session Reactivation
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                
                // 4. Delayed Resume
                // Audio hardware needs a moment to switch back from the other app
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self = self else { return }
                    self.resume()
                    self.wasPlayingBeforeInterruption = false
                    self.logger.info("Interruption ended: Audio resumed")
                }
            } catch {
                logger.error("Failed to reactivate session after interruption: \(error.localizedDescription)")
            }
        } else {
            wasPlayingBeforeInterruption = false
        }

    @unknown default:
        break
    }
    #endif
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

    // Activate audio session now that we're about to play
    activateAudioSession()

    // Use cached duration from episode metadata if available
    // This provides immediate feedback instead of showing 0:00
    if let episodeDuration = episode.duration, episodeDuration > 0 {
      duration = TimeInterval(episodeDuration)
    } else {
      duration = 0
    }
    currentTime = startTime > 0 ? startTime : 0

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

    // Update Now Playing info with cached duration (will be refined when AVPlayer reports actual duration)
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

    // Ensure audio session is active when resuming
    activateAudioSession()

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

    // Deactivate audio session so other apps can play
    deactivateAudioSession()

    logger.info("Playback stopped and audio session deactivated")
  }

  func seek(to time: TimeInterval) {
    let cmTime = CMTime(seconds: time, preferredTimescale: 600)
    player?.seek(to: cmTime) { [weak self] _ in
      // Dispatch to main actor since completion handler runs on arbitrary queue
      Task { @MainActor in
        self?.updateNowPlayingCurrentTime()
        self?.savePlaybackState()
        self?.postPlaybackPositionUpdate()
      }
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
    // Enforce queue size limit
    guard queue.count < maxQueueSize else {
      logger.info("Queue is full (max \(self.maxQueueSize) episodes)")
      return
    }
    queue.append(episode)
    logger.info("Added to queue: \(episode.title) (\(self.queue.count)/\(self.maxQueueSize))")
  }

  /// Add an episode to play next (first position in queue)
  func playNext(_ episode: PlaybackEpisode) {
    // Check if already in queue (will be moved, not added)
    let wasInQueue = queue.contains(where: { $0.id == episode.id })
    // Remove if already in queue
    queue.removeAll { $0.id == episode.id }
    // Don't add if currently playing
    guard currentEpisode?.id != episode.id else {
      logger.info("Episode is currently playing")
      return
    }
    // Enforce queue size limit (only if adding new, not moving existing)
    if !wasInQueue && queue.count >= maxQueueSize {
      logger.info("Queue is full (max \(self.maxQueueSize) episodes)")
      return
    }
    queue.insert(episode, at: 0)
    logger.info("Play next: \(episode.title) (\(self.queue.count)/\(self.maxQueueSize))")
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

  /// Update the list of auto-play candidates (unplayed episodes)
  func updateAutoPlayCandidates(_ episodes: [PlaybackEpisode]) {
    autoPlayCandidates = episodes
    logger.info("Updated auto-play candidates: \(episodes.count) episodes")
  }

  /// Add episodes to auto-play candidates (avoids duplicates)
  func addToAutoPlayCandidates(_ episodes: [PlaybackEpisode]) {
    let existingIds = Set(autoPlayCandidates.map { $0.id })
    let newEpisodes = episodes.filter { !existingIds.contains($0.id) }
    autoPlayCandidates.append(contentsOf: newEpisodes)
    logger.info("Added \(newEpisodes.count) to auto-play candidates (total: \(self.autoPlayCandidates.count))")
  }

  /// Remove an episode from auto-play candidates (e.g., after fully played)
  func removeFromAutoPlayCandidates(_ episodeId: String) {
    autoPlayCandidates.removeAll { $0.id == episodeId }
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
    duration = state.duration  // Restore saved duration for correct progress display

    logger.info("Restored last episode: \(state.episode.title) at \(state.time)s / \(state.duration)s")
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
          #if os(iOS)
          if let image = UIImage(data: data) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run {
              var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
              info[MPMediaItemPropertyArtwork] = artwork
              MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
          }
          #else
          if let image = NSImage(data: data) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { size in
              let newImage = NSImage(size: size)
              newImage.lockFocus()
              image.draw(in: NSRect(origin: .zero, size: size))
              newImage.unlockFocus()
              return newImage
            }
            await MainActor.run {
              var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
              info[MPMediaItemPropertyArtwork] = artwork
              MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
          }
          #endif
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
    UserDefaults.standard.set(duration, forKey: Keys.lastDuration)
    UserDefaults.standard.set(episode.audioURL, forKey: Keys.lastAudioURL)
    if let imageURL = imageURL {
      UserDefaults.standard.set(imageURL, forKey: Keys.lastImageURL)
    }

    logger.debug("Saved playback state: \(episode.title) at \(self.currentTime)s / \(self.duration)s")
  }

  func loadLastPlaybackState() -> (episode: PlaybackEpisode, time: TimeInterval, duration: TimeInterval, imageURL: String?)?
  {
    guard let title = UserDefaults.standard.string(forKey: Keys.lastEpisodeTitle),
      let podcastTitle = UserDefaults.standard.string(forKey: Keys.lastPodcastTitle),
      let audioURL = UserDefaults.standard.string(forKey: Keys.lastAudioURL)
    else {
      return nil
    }

    let time = UserDefaults.standard.double(forKey: Keys.lastPlaybackTime)
    let savedDuration = UserDefaults.standard.double(forKey: Keys.lastDuration)
    let imageURL = UserDefaults.standard.string(forKey: Keys.lastImageURL)

    let episode = PlaybackEpisode(
      id: "\(podcastTitle)\(Self.episodeKeyDelimiter)\(title)",
      title: title,
      podcastTitle: podcastTitle,
      audioURL: audioURL,
      imageURL: imageURL
    )

    return (episode, time, savedDuration, imageURL)
  }

  private func loadPlaybackRate() {
    let savedRate = UserDefaults.standard.float(forKey: Keys.playbackRate)
    playbackRate = savedRate > 0 ? savedRate : 1.0
  }

  func clearPlaybackState() {
    UserDefaults.standard.removeObject(forKey: Keys.lastEpisodeTitle)
    UserDefaults.standard.removeObject(forKey: Keys.lastPodcastTitle)
    UserDefaults.standard.removeObject(forKey: Keys.lastPlaybackTime)
    UserDefaults.standard.removeObject(forKey: Keys.lastDuration)
    UserDefaults.standard.removeObject(forKey: Keys.lastAudioURL)
    UserDefaults.standard.removeObject(forKey: Keys.lastImageURL)
  }

  // MARK: - Time Observer

  private func setupTimeObserver() {
    let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
    timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      [weak self] time in
      // Since we're on .main queue, we can safely assume MainActor isolation
      MainActor.assumeIsolated {
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
  }

  // MARK: - Player Observers

  private func setupPlayerObservers(playerItem: AVPlayerItem) {
    // Cancel any existing player observer tasks
    playerEndedTask?.cancel()
    playerStalledTask?.cancel()

    // Observe playback end using Task-based async sequence
    playerEndedTask = Task { @MainActor [weak self] in
      for await _ in NotificationCenter.default.notifications(named: .AVPlayerItemDidPlayToEndTime, object: playerItem) {
        self?.handlePlaybackEnded()
      }
    }

    // Observe playback stall using Task-based async sequence
    playerStalledTask = Task { [weak self] in
      for await _ in NotificationCenter.default.notifications(named: .AVPlayerItemPlaybackStalled, object: playerItem) {
        self?.logger.warning("Playback stalled")
      }
    }
  }

  private func handlePlaybackEnded() {
    logger.info("Playback ended")
    isPlaying = false
    currentTime = 0

    // Remove current episode from auto-play candidates (it's been fully played)
    if let currentId = currentEpisode?.id {
      removeFromAutoPlayCandidates(currentId)
    }

    // Check if there's a next episode in queue
    if !queue.isEmpty {
      logger.info("Playing next episode from queue")
      playNextInQueue()
    } else {
      // Check auto-play setting and try to play random unplayed episode
      let autoPlayEnabled = UserDefaults.standard.bool(forKey: Keys.autoPlayNextEpisode)
      if autoPlayEnabled, !autoPlayCandidates.isEmpty {
        // Pick a random episode from candidates
        let randomIndex = Int.random(in: 0..<autoPlayCandidates.count)
        let nextEpisode = autoPlayCandidates[randomIndex]
        logger.info("Auto-playing random episode: \(nextEpisode.title)")
        play(
          episode: nextEpisode,
          audioURL: nextEpisode.audioURL,
          startTime: 0,
          imageURL: nextEpisode.imageURL,
          useDefaultSpeed: false
        )
      } else {
        clearPlaybackState()
      }
    }
  }

  // MARK: - Cleanup

  private func cleanup() {
    if let observer = timeObserver {
      player?.removeTimeObserver(observer)
      timeObserver = nil
    }

    // Cancel Task-based observers
    playerEndedTask?.cancel()
    playerEndedTask = nil
    playerStalledTask?.cancel()
    playerStalledTask = nil

    player?.pause()
    player = nil
  }

  // Note: This is a singleton designed to live for the app's lifetime.
  // No deinit needed - the singleton is never deallocated.
}

// MARK: - Supporting Models

struct PlaybackEpisode: Identifiable, Codable, Sendable {
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

struct CaptionSegment: Identifiable, Sendable {
  let id = UUID()
  let startTime: TimeInterval
  let endTime: TimeInterval
  let text: String
}
