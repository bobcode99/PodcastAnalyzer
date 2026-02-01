//
//  EpisodeDetailViewModel.swift
//  PodcastAnalyzer
//
//  Enhanced with download management and playback state
//

import Observation
import SwiftData
import SwiftUI
import ZMarkupParser
import os.log

#if canImport(Translation)
@preconcurrency import Translation
#endif

#if os(iOS)
import UIKit
#else
import AppKit
#endif

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "EpisodeDetailViewModel")

/// Represents word-level timing information for accurate highlighting
struct WordTiming: Equatable, Sendable {
  let word: String
  let startTime: TimeInterval
  let endTime: TimeInterval
}

/// Represents a single transcript segment with timing information
struct TranscriptSegment: Identifiable, Equatable {
  let id: Int
  let startTime: TimeInterval
  let endTime: TimeInterval
  let text: String
  var translatedText: String?
  /// Word-level timing for accurate highlighting (from Speech framework)
  var wordTimings: [WordTiming]?

  /// Formatted start time string (MM:SS or HH:MM:SS)
  var formattedStartTime: String {
    let totalSeconds = Int(startTime)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }

  /// Returns display text based on subtitle display mode
  func displayText(mode: SubtitleDisplayMode) -> (primary: String, secondary: String?) {
    switch mode {
    case .originalOnly:
      return (text, nil)
    case .translatedOnly:
      return (translatedText ?? text, nil)
    case .dualOriginalFirst:
      return (text, translatedText)
    case .dualTranslatedFirst:
      return (translatedText ?? text, translatedText != nil ? text : nil)
    }
  }

  /// Whether this segment has a translation
  var hasTranslation: Bool {
    translatedText != nil
  }
}

@Observable
final class EpisodeDetailViewModel {

  var descriptionView: AnyView = AnyView(
    Text("Loading...").foregroundStyle(.secondary)
  )

  @ObservationIgnored
  let episode: PodcastEpisodeInfo

  @ObservationIgnored
  let podcastTitle: String

  @ObservationIgnored
  private let fallbackImageURL: String?

  // Reference singletons
  @ObservationIgnored
  let audioManager = EnhancedAudioManager.shared

  @ObservationIgnored
  private let downloadManager = DownloadManager.shared

  // Download state
  var downloadState: DownloadState = .notDownloaded

  // Transcript state
  var transcriptState: TranscriptState = .idle
  var transcriptText: String = ""
  var isModelReady: Bool = false

  @ObservationIgnored
  private let fileStorage = FileStorageManager.shared

  // Parsed transcript segments for live captions
  var transcriptSegments: [TranscriptSegment] = []
  var transcriptSearchQuery: String = ""

  // RSS transcript state (from podcast:transcript tag)
  var rssTranscriptState: TranscriptDownloadState = .notAvailable

  // Translation state
  var translationStatus: TranslationStatus = .idle
  var translatedDescription: String?
  var translatedEpisodeTitle: String?
  var translatedPodcastTitle: String?  // Translated podcast show name
  var transcriptTranslationTrigger: Bool = false  // Toggle to trigger .translationTask
  var descriptionTranslationTrigger: Bool = false  // Toggle to trigger description translation
  var episodeTitleTranslationTrigger: Bool = false  // Toggle to trigger title translation
  var podcastTitleTranslationTrigger: Bool = false  // Toggle to trigger podcast title translation

  // Translation language selection
  var selectedTranslationLanguage: TranslationTargetLanguage?  // Language selected for translation
  var availableTranslationLanguages: Set<String> = []  // Cached language codes

  @ObservationIgnored
  private let translationService = TranslationService.shared

  @ObservationIgnored
  private let transcriptDownloadService = TranscriptDownloadService.shared

  @ObservationIgnored
  private let subtitleSettings = SubtitleSettingsManager.shared

  // Playback state from SwiftData
  @ObservationIgnored
  private var episodeModel: EpisodeDownloadModel?

  @ObservationIgnored
  private var modelContext: ModelContext?

  // Timer tasks - replaced Combine timers with Task-based timers for Swift 6
  @ObservationIgnored
  private var downloadTimerTask: Task<Void, Never>?

  @ObservationIgnored
  private var playbackTimerTask: Task<Void, Never>?

  // Flag to track transcript manager observation
  @ObservationIgnored
  private var isObservingTranscriptManager = false

  // Podcast language for transcription
  var podcastLanguage: String = "en"

  init(
    episode: PodcastEpisodeInfo, podcastTitle: String, fallbackImageURL: String?,
    podcastLanguage: String = "en"
  ) {
    self.episode = episode
    self.podcastTitle = podcastTitle
    self.fallbackImageURL = fallbackImageURL
    self.podcastLanguage = podcastLanguage
    parseDescription()

    // Initialize download state
    updateDownloadState()

    // Observe download state changes
    observeDownloadState()

    // Check for active transcript job and start observing
    checkAndObserveTranscriptJob()
  }

  /// Episode key using centralized utility
  private var episodeKey: String {
    EpisodeKeyUtils.makeKey(podcastTitle: podcastTitle, episodeTitle: episode.title)
  }

  /// Checks if there's an active transcript job and starts observing
  private func checkAndObserveTranscriptJob() {
    if TranscriptManager.shared.activeJobs[episodeKey] != nil {
      observeTranscriptManager()
    }
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    loadEpisodeModel()
    observePlaybackState()
    loadAIAnalysisFromSwiftData()
  }

  // MARK: - Episode Properties

  var title: String { episode.title }

  var pubDateString: String? {
    episode.pubDate?.formatted(date: .long, time: .omitted)
  }

  var imageURLString: String {
    episode.imageURL ?? fallbackImageURL ?? ""
  }

  var audioURL: String? { episode.audioURL }
  var isPlayDisabled: Bool {
    guard episode.audioURL != nil else { return true }
    // Can play if downloaded or has URL
    return !hasLocalAudio && episode.audioURL == nil
  }

  var playbackURL: String {
    // Prefer local file if available
    if let localPath = localAudioPath {
      return "file://" + localPath
    }
    return episode.audioURL ?? ""
  }

  var hasLocalAudio: Bool {
    if case .downloaded = downloadState {
      return true
    }
    return false
  }

  var localAudioPath: String? {
    if case .downloaded(let path) = downloadState {
      return path
    }
    return nil
  }

  // MARK: - Playback State

  /// Check if this episode is the current one loaded in audio manager (regardless of play state)
  var isCurrentEpisode: Bool {
    guard let currentEpisode = audioManager.currentEpisode else { return false }
    return currentEpisode.title == episode.title && currentEpisode.podcastTitle == podcastTitle
  }

  /// Check if this episode is currently playing
  var isPlayingThisEpisode: Bool {
    isCurrentEpisode && audioManager.isPlaying
  }

  var currentTime: TimeInterval {
    isPlayingThisEpisode ? audioManager.currentTime : (episodeModel?.lastPlaybackPosition ?? 0)
  }

  var duration: TimeInterval {
    isPlayingThisEpisode ? audioManager.duration : 0
  }

  var playbackRate: Float {
    audioManager.playbackRate
  }

  var currentCaption: String {
    isPlayingThisEpisode ? audioManager.currentCaption : ""
  }

  var isStarred: Bool {
    episodeModel?.isStarred ?? false
  }

  var isCompleted: Bool {
    episodeModel?.isCompleted ?? false
  }

  var savedDuration: TimeInterval {
    episodeModel?.duration ?? 0
  }

  var lastPlaybackPosition: TimeInterval {
    episodeModel?.lastPlaybackPosition ?? 0
  }

  var formattedDuration: String? {
    episode.formattedDuration
  }

  var playbackProgress: Double {
    episodeModel?.progress ?? 0
  }

  var remainingTimeString: String? {
    episodeModel?.remainingTimeString
  }

  // MARK: - Actions

  func playAction() {
    guard let audioURLString = episode.audioURL else { return }

    // Prefer local file if available
    let playbackURL: String
    if let localPath = localAudioPath {
      playbackURL = "file://" + localPath
    } else {
      playbackURL = audioURLString
    }

    let playbackEpisode = PlaybackEpisode(
      id: episodeKey,
      title: episode.title,
      podcastTitle: podcastTitle,
      audioURL: playbackURL,
      imageURL: imageURLString,
      episodeDescription: episode.podcastEpisodeDescription,
      pubDate: episode.pubDate,
      duration: episode.duration,
      guid: episode.guid
    )

    // Resume from saved position, but reset to 0 if episode was marked as completed
    // This allows users to replay completed episodes from the beginning
    var startTime: TimeInterval = 0
    if let model = episodeModel {
      if model.isCompleted {
        // Reset position for completed episodes (user wants to replay)
        model.lastPlaybackPosition = 0
        model.isCompleted = false
        try? modelContext?.save()
        startTime = 0

        // Force new player if this is the same episode (AVPlayer may be at end-of-media)
        if audioManager.currentEpisode?.id == episodeKey {
          audioManager.stop()
        }
      } else {
        startTime = model.lastPlaybackPosition
      }
    }

    // Use default speed from settings only for fresh plays (not resuming)
    let useDefaultSpeed = startTime == 0

    audioManager.play(
      episode: playbackEpisode,
      audioURL: playbackURL,
      startTime: startTime,
      imageURL: imageURLString,
      useDefaultSpeed: useDefaultSpeed
    )

    // Update last played date
    updateLastPlayed()
  }

  func seek(to time: TimeInterval) {
    audioManager.seek(to: time)
    savePlaybackPosition(time)
  }

  func skipForward() {
    audioManager.skipForward()
  }

  func skipBackward() {
    audioManager.skipBackward()
  }

  func setPlaybackSpeed(_ rate: Float) {
    audioManager.setPlaybackRate(rate)
  }

  // MARK: - Download Management

  func startDownload() {
    downloadManager.downloadEpisode(
      episode: episode, podcastTitle: podcastTitle, language: podcastLanguage)
  }

  func cancelDownload() {
    downloadManager.cancelDownload(episodeTitle: episode.title, podcastTitle: podcastTitle)
  }

  func deleteDownload() {
    downloadManager.deleteDownload(episodeTitle: episode.title, podcastTitle: podcastTitle)
  }

  private func updateDownloadState() {
    downloadState = downloadManager.getDownloadState(
      episodeTitle: episode.title,
      podcastTitle: podcastTitle
    )
  }

  private func observeDownloadState() {
    // Cancel any existing download timer first
    downloadTimerTask?.cancel()

    // Poll for download state changes using Task-based timer
    downloadTimerTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { break }
        self?.updateDownloadState()
      }
    }
  }

  private func observePlaybackState() {
    // Cancel any existing playback timer first
    playbackTimerTask?.cancel()

    // Poll for playback state changes using Task-based timer
    playbackTimerTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { break }
        self?.refreshEpisodeModel()
      }
    }
  }

  private func refreshEpisodeModel() {
    guard let context = modelContext else { return }

    let id = episodeKey
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == id }
    )

    do {
      let results = try context.fetch(descriptor)
      if let model = results.first {
        episodeModel = model
      }
    } catch {
      // Silent fail - model will be refreshed on next timer tick
    }
  }

  // MARK: - SwiftData Persistence

  private func loadEpisodeModel() {
    guard let context = modelContext else { return }

    let id = episodeKey
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == id }
    )

    do {
      let results = try context.fetch(descriptor)
      if let model = results.first {
        episodeModel = model
      } else {
        // Create new model
        createEpisodeModel(context: context)
      }
    } catch {
      logger.error("Failed to load episode model: \(error.localizedDescription)")
    }
  }

  private func createEpisodeModel(context: ModelContext) {
    guard let audioURL = episode.audioURL else { return }

    let model = EpisodeDownloadModel(
      episodeTitle: episode.title,
      podcastTitle: podcastTitle,
      audioURL: audioURL,
      imageURL: imageURLString,
      pubDate: episode.pubDate
    )
    context.insert(model)

    do {
      try context.save()
      episodeModel = model
    } catch {
      logger.error("Failed to create episode model: \(error.localizedDescription)")
    }
  }

  private func savePlaybackPosition(_ position: TimeInterval) {
    guard let model = episodeModel else { return }
    model.lastPlaybackPosition = position

    // Also save duration if we have it
    if audioManager.duration > 0 {
      model.duration = audioManager.duration
    }

    // Mark as completed if near the end (within 30 seconds)
    if model.duration > 0 && position >= model.duration - 30 {
      model.isCompleted = true
    }

    do {
      try modelContext?.save()
    } catch {
      logger.error("Failed to save playback position: \(error.localizedDescription)")
    }
  }

  private func updateLastPlayed() {
    guard let model = episodeModel else { return }
    model.lastPlayedDate = Date()
    model.playCount += 1

    // Save image URL and pub date if not already saved
    if model.imageURL == nil {
      model.imageURL = imageURLString
    }
    if model.pubDate == nil {
      model.pubDate = episode.pubDate
    }

    do {
      try modelContext?.save()
    } catch {
      logger.error("Failed to update last played: \(error.localizedDescription)")
    }
  }

  // MARK: - Description Parsing

  private func parseDescription() {
    let html = episode.podcastEpisodeDescription ?? ""

    guard !html.isEmpty else {
      descriptionView = AnyView(
        Text("No description available.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      )
      return
    }

    #if os(iOS)
    let labelColor = UIColor.label
    #else
    let labelColor = NSColor.labelColor
    #endif

    let rootStyle = MarkupStyle(
      font: MarkupStyleFont(size: 16),
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
            .padding(.vertical, 4)
        )
      }
    }
  }

  // MARK: - Action Methods

  @ObservationIgnored
  private let applePodcastService = ApplePodcastService()

  @ObservationIgnored
  private var shareTask: Task<Void, Never>?

  func shareEpisode() {
    logger.debug("Share episode: \(self.episode.title)")

    // Cancel previous share task
    shareTask?.cancel()

    // Try to find Apple Podcast URL first with timeout
    shareTask = Task {
      do {
        let appleUrl = try await withTimeout(seconds: 5) {
          try await self.applePodcastService.getAppleEpisodeLink(
            episodeTitle: self.episode.title,
            episodeGuid: self.episode.guid
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
    guard let urlString = urlString, let url = URL(string: urlString) else {
      logger.warning("No URL available for sharing")
      return
    }

    PlatformShareSheet.share(url: url)
  }

  func translateDescription() {
    logger.debug("Translate description requested")
    // Toggle to trigger the .translationTask modifiers for description, title, and podcast name
    descriptionTranslationTrigger.toggle()
    episodeTitleTranslationTrigger.toggle()
    podcastTitleTranslationTrigger.toggle()
  }

  // MARK: - Transcript Translation

  /// Translate to a specific language (called from language picker)
  func translateTo(_ language: TranslationTargetLanguage) {
    // Store the selected language for the translation triggers to use
    selectedTranslationLanguage = language
    let targetLang = language.languageIdentifier

    logger.debug("Translate requested to: \(language.displayName) (\(targetLang))")

    // Always trigger title/description translation (works without transcript)
    translationStatus = .preparingSession
    descriptionTranslationTrigger.toggle()
    episodeTitleTranslationTrigger.toggle()
    podcastTitleTranslationTrigger.toggle()

    // Skip transcript translation if no segments available
    guard !transcriptSegments.isEmpty else {
      logger.info("No transcript segments - translating title/description only")
      return
    }

    Task {
      // Try to load existing transcript translation first
      if let translated = await translationService.loadExistingTranslation(
        segments: transcriptSegments,
        episodeTitle: episode.title,
        podcastTitle: podcastTitle,
        targetLanguage: targetLang
      ) {
        await MainActor.run {
          self.transcriptSegments = translated
          self.translationStatus = .completed
          logger.info("Loaded cached translation for \(self.episode.title) in \(language.displayName)")
        }
        return
      }

      // No cached translation, trigger the transcript translation task
      await MainActor.run {
        self.transcriptTranslationTrigger.toggle()
      }
    }
  }

  /// Check which translation languages are available (cached)
  func checkAvailableTranslations() {
    Task {
      let available = await fileStorage.listAvailableTranslations(
        for: episode.title,
        podcastTitle: podcastTitle
      )

      await MainActor.run {
        self.availableTranslationLanguages = available
        logger.info("Found \(available.count) cached translations: \(available)")
      }
    }
  }

  /// Trigger transcript translation using Apple's Translation framework
  func translateTranscript() {
    guard !transcriptSegments.isEmpty else {
      logger.warning("No transcript segments to translate")
      return
    }

    // Use selected language or fall back to settings default
    let targetLang = (selectedTranslationLanguage ?? subtitleSettings.targetLanguage).languageIdentifier

    Task {
      // Try to load existing translation first
      if let translated = await translationService.loadExistingTranslation(
        segments: transcriptSegments,
        episodeTitle: episode.title,
        podcastTitle: podcastTitle,
        targetLanguage: targetLang
      ) {
        await MainActor.run {
          self.transcriptSegments = translated
          self.translationStatus = .completed
          logger.info("Loaded cached translation for \(self.episode.title)")
        }
        return
      }

      // No cached translation, trigger the translation task
      await MainActor.run {
        self.translationStatus = .preparingSession
        self.transcriptTranslationTrigger.toggle()
      }
    }
  }

  /// Called by .translationTask when translation session is ready
  @available(iOS 17.4, macOS 14.4, *)
  func performTranscriptTranslation(using session: TranslationSession) async {
    #if canImport(Translation)
    let segments = await MainActor.run { self.transcriptSegments }
    let total = segments.count

    guard total > 0 else {
      await MainActor.run {
        self.translationStatus = .failed("No segments to translate")
      }
      return
    }

    await MainActor.run {
      self.translationStatus = .translating(progress: 0, completed: 0, total: total)
    }

    var translatedSegments = segments

    // Translate one by one to avoid Sendable issues with batch
    for (index, segment) in segments.enumerated() {
      do {
        let response = try await session.translate(segment.text)
        translatedSegments[index].translatedText = response.targetText

        let progress = Double(index + 1) / Double(total)
        await MainActor.run {
          self.translationStatus = .translating(progress: progress, completed: index + 1, total: total)
        }
      } catch {
        logger.error("Translation failed for segment \(index): \(error.localizedDescription)")
        await MainActor.run {
          self.translationStatus = .failed(error.localizedDescription)
        }
        return
      }
    }

    // Save translated segments using selected language or settings default
    let targetLang = await MainActor.run {
      (self.selectedTranslationLanguage ?? self.subtitleSettings.targetLanguage).languageIdentifier
    }

    do {
      try await translationService.saveTranslatedSRT(
        segments: translatedSegments,
        episodeTitle: episode.title,
        podcastTitle: podcastTitle,
        targetLanguage: targetLang
      )
    } catch {
      logger.error("Failed to save translation: \(error.localizedDescription)")
    }

    await MainActor.run {
      self.transcriptSegments = translatedSegments
      self.translationStatus = .completed
      // Update available translations
      self.availableTranslationLanguages.insert(targetLang)
    }

    logger.info("Completed translation for \(self.episode.title)")
    #endif
  }

  /// Called by .translationTask for description translation
  @available(iOS 17.4, macOS 14.4, *)
  func performDescriptionTranslation(using session: TranslationSession) async {
    #if canImport(Translation)
    guard let description = episode.podcastEpisodeDescription, !description.isEmpty else {
      return
    }

    // Strip HTML for translation
    let plainText = stripHTMLForTranslation(description)

    do {
      let response = try await session.translate(plainText)
      await MainActor.run {
        self.translatedDescription = response.targetText
      }
      logger.info("Translated description for \(self.episode.title)")
    } catch {
      logger.error("Description translation failed: \(error.localizedDescription)")
    }
    #endif
  }

  /// Called by .translationTask for title translation
  @available(iOS 17.4, macOS 14.4, *)
  func performTitleTranslation(using session: TranslationSession) async {
    #if canImport(Translation)
    let title = episode.title
    guard !title.isEmpty else { return }

    do {
      let response = try await session.translate(title)
      await MainActor.run {
        self.translatedEpisodeTitle = response.targetText
      }
      logger.info("Translated title for \(self.episode.title)")
    } catch {
      logger.error("Title translation failed: \(error.localizedDescription)")
    }
    #endif
  }

  /// Called by .translationTask for podcast name translation
  @available(iOS 17.4, macOS 14.4, *)
  func performPodcastTitleTranslation(using session: TranslationSession) async {
    #if canImport(Translation)
    let title = podcastTitle
    guard !title.isEmpty else { return }

    do {
      let response = try await session.translate(title)
      await MainActor.run {
        self.translatedPodcastTitle = response.targetText
      }
      logger.info("Translated podcast title: \(title)")
    } catch {
      logger.error("Podcast title translation failed: \(error.localizedDescription)")
    }
    #endif
  }

  /// Strip HTML tags for translation
  private func stripHTMLForTranslation(_ html: String) -> String {
    var result = html
    // Remove HTML tags
    result = result.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    // Decode HTML entities
    result = decodeHTMLEntities(result)
    // Collapse whitespace
    result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Load existing translations for current segments
  func loadExistingTranslations() {
    let settings = SubtitleSettingsManager.shared
    let targetLang = settings.targetLanguage.languageIdentifier

    Task {
      if let translated = await translationService.loadExistingTranslation(
        segments: transcriptSegments,
        episodeTitle: episode.title,
        podcastTitle: podcastTitle,
        targetLanguage: targetLang
      ) {
        await MainActor.run {
          self.transcriptSegments = translated
          logger.info("Loaded existing translations for \(self.episode.title)")
        }
      }
    }
  }

  /// Check if translation exists for current language
  var hasExistingTranslation: Bool {
    transcriptSegments.contains { $0.translatedText != nil }
  }

  func toggleStar() {
    // Create model if it doesn't exist
    if episodeModel == nil, let context = modelContext {
      createEpisodeModel(context: context)
    }

    guard let model = episodeModel else {
      logger.warning("Cannot toggle star: no episode model available")
      return
    }
    model.isStarred.toggle()

    do {
      try modelContext?.save()
    } catch {
      logger.error("Failed to save star state: \(error.localizedDescription)")
    }
  }

  func togglePlayed() {
    // Create model if it doesn't exist
    if episodeModel == nil, let context = modelContext {
      createEpisodeModel(context: context)
    }

    guard let model = episodeModel else {
      logger.warning("Cannot toggle played: no episode model available")
      return
    }
    model.isCompleted.toggle()
    if !model.isCompleted {
      model.lastPlaybackPosition = 0
    }

    do {
      try modelContext?.save()
    } catch {
      logger.error("Failed to save played state: \(error.localizedDescription)")
    }
  }

  func addToPlayNext() {
    guard let audioURLString = episode.audioURL else {
      logger.warning("Cannot add to play next: no audio URL")
      return
    }

    let playbackEpisode = PlaybackEpisode(
      id: episodeKey,
      title: episode.title,
      podcastTitle: podcastTitle,
      audioURL: audioURLString,
      imageURL: imageURLString,
      episodeDescription: episode.podcastEpisodeDescription,
      pubDate: episode.pubDate,
      duration: episode.duration,
      guid: episode.guid
    )

    audioManager.playNext(playbackEpisode)
    logger.info("Added to play next: \(self.episode.title)")
  }

  func reportIssue() {
    // TODO: Implement issue reporting
    logger.debug("Report issue for: \(self.episode.title)")
  }

  // MARK: - RSS Transcript Methods

  /// Check if RSS transcript is available from the feed
  func checkRSSTranscriptAvailability() {
    Task {
      let state = await transcriptDownloadService.getDownloadState(
        episodeTitle: episode.title,
        podcastTitle: podcastTitle,
        transcriptURL: episode.transcriptURL,
        transcriptType: episode.transcriptType
      )

      await MainActor.run {
        rssTranscriptState = state

        // If already downloaded, load the transcript
        if case .downloaded = state {
          Task {
            await loadExistingTranscript()
          }
        }
      }
    }
  }

  /// Download RSS transcript from the feed URL
  func downloadRSSTranscript() {
    guard case .available(let urlString, let type) = rssTranscriptState,
          let url = URL(string: urlString) else {
      logger.warning("Cannot download RSS transcript: not available")
      return
    }

    Task {
      await MainActor.run {
        rssTranscriptState = .downloading(progress: 0.5)
      }

      do {
        let savedURL = try await transcriptDownloadService.downloadTranscript(
          from: url,
          type: type,
          episodeTitle: episode.title,
          podcastTitle: podcastTitle
        )

        await MainActor.run {
          rssTranscriptState = .downloaded(localPath: savedURL.path)
          logger.info("RSS transcript downloaded successfully")
        }

        // Load the transcript
        await loadExistingTranscript()

      } catch {
        await MainActor.run {
          rssTranscriptState = .failed(error: error.localizedDescription)
          logger.error("RSS transcript download failed: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Check if RSS transcript is available and not yet downloaded
  var hasRSSTranscriptAvailable: Bool {
    if case .available = rssTranscriptState { return true }
    return false
  }

  /// Check if RSS transcript is being downloaded
  var isDownloadingRSSTranscript: Bool {
    if case .downloading = rssTranscriptState { return true }
    return false
  }

  /// Check if RSS transcript has been downloaded
  var hasDownloadedRSSTranscript: Bool {
    if case .downloaded = rssTranscriptState { return true }
    return false
  }

  // MARK: - Transcript Methods

  /// Gets the podcast language from SwiftData, falling back to "en" if not found
  private func getPodcastLanguage() -> String {
    guard let context = modelContext else { return "en" }

    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.title == podcastTitle }
    )

    do {
      let results = try context.fetch(descriptor)
      if let podcastModel = results.first {
        return podcastModel.podcastInfo.language
      }
    } catch {
      logger.error("Failed to fetch podcast language: \(error.localizedDescription)")
    }

    return "en"  // Default fallback
  }

  func checkTranscriptStatus() {
    Task {
      // Get podcast language and create transcript service
      let language = getPodcastLanguage()
      let transcriptService = TranscriptService(language: language)
      isModelReady = await transcriptService.isModelReady()

      // Check if transcript already exists (either from RSS or generated)
      let exists = await fileStorage.captionFileExists(
        for: episode.title,
        podcastTitle: podcastTitle
      )

      if exists {
        await loadExistingTranscript()
      } else {
        // Check for RSS transcript availability
        checkRSSTranscriptAvailability()
      }
    }
  }

  func generateTranscript() {
    guard let audioPath = localAudioPath else {
      transcriptState = .error(
        "No local audio file available. Please download the episode first.")
      return
    }

    // Use TranscriptManager for background processing
    let language = getPodcastLanguage()
    TranscriptManager.shared.queueTranscript(
      episodeTitle: episode.title,
      podcastTitle: podcastTitle,
      audioPath: audioPath,
      language: language
    )

    // Start observing TranscriptManager state
    observeTranscriptManager()
  }

  /// Observes TranscriptManager for job status updates
  private func observeTranscriptManager() {
    guard !isObservingTranscriptManager else { return }
    isObservingTranscriptManager = true
    startTranscriptObservation()
  }

  private func startTranscriptObservation() {
    // Don't start if we've stopped observing
    guard isObservingTranscriptManager else { return }

    withObservationTracking {
      // Access the property to register observation
      _ = TranscriptManager.shared.activeJobs
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self, self.isObservingTranscriptManager else { return }
        self.handleTranscriptJobUpdate()
        self.startTranscriptObservation()
      }
    }
  }

  private func handleTranscriptJobUpdate() {
    // Use Unit Separator (U+001F) as delimiter - same as TranscriptManager
    let delimiter = "\u{1F}"
    let jobId = "\(podcastTitle)\(delimiter)\(episode.title)"

    if let job = TranscriptManager.shared.activeJobs[jobId] {
      // Update local state based on job status
      switch job.status {
      case .queued:
        transcriptState = .transcribing(progress: 0)
      case .downloadingModel(let progress):
        transcriptState = .downloadingModel(progress: progress)
      case .transcribing(let progress):
        transcriptState = .transcribing(progress: progress)
      case .completed:
        // Load the transcript from disk
        Task {
          await loadExistingTranscript()
        }
      case .failed(let error):
        transcriptState = .error(error)
      }
    }
  }

  func copyTranscriptToClipboard() {
    PlatformClipboard.string = transcriptText
  }

  /// Cached word timings data from JSON file (for accurate word-level highlighting)
  private var wordTimingsData: TranscriptService.TranscriptData?

  private func loadExistingTranscript() async {
    do {
      let content = try await fileStorage.loadCaptionFile(
        for: episode.title,
        podcastTitle: podcastTitle
      )

      // Also get the file date
      let fileDate = await fileStorage.getCaptionFileDate(
        for: episode.title,
        podcastTitle: podcastTitle
      )

      // Try to load word timings JSON (optional - may not exist for RSS transcripts)
      var timingsData: TranscriptService.TranscriptData?
      if let wordTimingsJSON = try await fileStorage.loadWordTimingFile(
        for: episode.title,
        podcastTitle: podcastTitle
      ) {
        if let jsonData = wordTimingsJSON.data(using: .utf8) {
          timingsData = try? JSONDecoder().decode(TranscriptService.TranscriptData.self, from: jsonData)
        }
      }

      await MainActor.run {
        transcriptText = content
        cachedTranscriptDate = fileDate
        wordTimingsData = timingsData
        transcriptState = .completed
        parseTranscriptSegments()
      }
    } catch {
      logger.error("Failed to load transcript: \(error.localizedDescription)")
    }
  }

  var hasTranscript: Bool {
    !transcriptText.isEmpty
  }

  /// Get the transcript generation date from the SRT file's modification date
  var transcriptGeneratedAt: Date? {
    get async {
      return await fileStorage.getCaptionFileDate(
        for: episode.title,
        podcastTitle: podcastTitle
      )
    }
  }

  /// Cached transcript generation date (for synchronous access in View)
  var cachedTranscriptDate: Date?

  /// Load transcript generation date
  func loadTranscriptDate() {
    Task {
      let date = await transcriptGeneratedAt
      await MainActor.run {
        cachedTranscriptDate = date
      }
    }
  }

  var hasAIAnalysis: Bool {
    cloudAnalysisCache.fullAnalysis != nil || !cloudAnalysisCache.questionAnswers.isEmpty
  }

  /// Parses SRT content and returns clean text formatted in paragraphs
  /// Groups segments into sentences, then combines 4 sentences per paragraph
  var cleanTranscriptText: String {
    guard !transcriptSegments.isEmpty else { return "" }

    // Group segments into sentences using TranscriptGrouping
    let sentences = TranscriptGrouping.groupIntoSentences(transcriptSegments)

    // Combine 4 sentences per paragraph
    let sentencesPerParagraph = 4
    var paragraphs: [String] = []

    for startIndex in stride(from: 0, to: sentences.count, by: sentencesPerParagraph) {
      let endIndex = min(startIndex + sentencesPerParagraph, sentences.count)
      let chunk = sentences[startIndex..<endIndex]
      let paragraphText = chunk.map { $0.text }.joined(separator: " ")
      paragraphs.append(paragraphText)
    }

    return paragraphs.joined(separator: "\n\n")
  }

  // MARK: - Live Captions Methods

  /// Finds word timings for a segment from the loaded word timings data
  /// - Parameters:
  ///   - segmentId: The segment ID (1-based)
  ///   - startTime: Segment start time
  ///   - endTime: Segment end time
  /// - Returns: Array of WordTiming if found, nil otherwise
  private func findWordTimingsForSegment(segmentId: Int, startTime: TimeInterval, endTime: TimeInterval) -> [WordTiming]? {
    guard let data = wordTimingsData else { return nil }

    // Try to find segment by ID first
    if let segment = data.segments.first(where: { $0.id == segmentId }) {
      return segment.wordTimings.map { timing in
        WordTiming(word: timing.word, startTime: timing.startTime, endTime: timing.endTime)
      }
    }

    // Fallback: find segment by time overlap
    for segment in data.segments {
      // Check if times roughly match (within 0.5s tolerance)
      if abs(segment.startTime - startTime) < 0.5 && abs(segment.endTime - endTime) < 0.5 {
        return segment.wordTimings.map { timing in
          WordTiming(word: timing.word, startTime: timing.startTime, endTime: timing.endTime)
        }
      }
    }

    return nil
  }

  /// Parses SRT content into transcript segments
  func parseTranscriptSegments() {
    guard !transcriptText.isEmpty else {
      transcriptSegments = []
      return
    }

    var segments: [TranscriptSegment] = []

    // Normalize line endings
    let normalizedText = transcriptText.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    // Use regex to split SRT into entries
    // Pattern matches: index number at start of line, followed by timestamp line
    let entryPattern =
      #"(?:^|\n)(\d+)\n(\d{2}:\d{2}:\d{2}[,\.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]\d{3})\n"#

    guard let regex = try? NSRegularExpression(pattern: entryPattern, options: []) else {
      logger.error("Failed to create SRT regex pattern")
      return
    }

    let nsText = normalizedText as NSString
    let matches = regex.matches(
      in: normalizedText, options: [], range: NSRange(location: 0, length: nsText.length))

    logger.info(
      "Raw SRT text length: \(self.transcriptText.count), Found \(matches.count) potential entries via regex"
    )

    for (index, match) in matches.enumerated() {
      // Extract captured groups
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
      else {
        logger.warning(
          "Entry \(index + 1): failed to parse times '\(startTimeStr)' -> '\(endTimeStr)'")
        continue
      }

      // Find text: starts after this match, ends at next match or end of string
      let textStart = match.range.location + match.range.length
      let textEnd: Int
      if index + 1 < matches.count {
        // Find the start of the next entry's index number
        let nextMatch = matches[index + 1]
        textEnd = nextMatch.range.location
      } else {
        textEnd = nsText.length
      }

      guard textStart < textEnd else { continue }

      let textRange = NSRange(location: textStart, length: textEnd - textStart)
      var text = nsText.substring(with: textRange)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\n", with: " ")

      // Remove any trailing index number that belongs to the next entry
      if let lastNewlineIndex = text.lastIndex(of: "\n") {
        let afterNewline = String(text[text.index(after: lastNewlineIndex)...])
        if afterNewline.trimmingCharacters(in: .whitespaces).allSatisfy({ $0.isNumber }) {
          text = String(text[..<lastNewlineIndex])
        }
      }

      text = text.trimmingCharacters(in: .whitespacesAndNewlines)

      // Decode HTML entities (e.g., &nbsp; -> space)
      text = decodeHTMLEntities(text)

      guard !text.isEmpty else {
        logger.warning("Entry \(index + 1): empty text")
        continue
      }

      // Look up word timings for this segment if available
      let wordTimings: [WordTiming]? = findWordTimingsForSegment(
        segmentId: index + 1,  // Word timings use 1-based IDs
        startTime: startTime,
        endTime: endTime
      )

      segments.append(
        TranscriptSegment(
          id: index,
          startTime: startTime,
          endTime: endTime,
          text: text,
          wordTimings: wordTimings
        ))
    }

    // Apply sentence grouping if enabled
    if subtitleSettings.groupSegmentsIntoSentences {
      let grouped = groupSegmentsIntoSentences(segments)
      transcriptSegments = grouped
      logger.info(
        "Grouped \(segments.count) segments into \(grouped.count) sentences"
      )
    } else {
      transcriptSegments = segments
      logger.info(
        "Successfully parsed \(segments.count) transcript segments from \(matches.count) regex matches"
      )
    }

    // Debug: log first few segments if we have any
    if !segments.isEmpty {
      logger.info("First segment: \(segments[0].text.prefix(50))...")
      if segments.count > 1 {
        logger.info("Second segment: \(segments[1].text.prefix(50))...")
      }
    }
  }

  // MARK: - Sentence Grouping

  /// Groups transcript segments into complete sentences by merging segments that don't end with sentence-ending punctuation
  private func groupSegmentsIntoSentences(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
    let sentenceEndings = CharacterSet(charactersIn: ".!?。！？")
    var grouped: [TranscriptSegment] = []
    var currentGroup: [TranscriptSegment] = []

    for segment in segments {
      currentGroup.append(segment)

      // Check if this segment ends with sentence-ending punctuation
      let trimmedText = segment.text.trimmingCharacters(in: .whitespaces)
      if let lastChar = trimmedText.unicodeScalars.last,
         sentenceEndings.contains(lastChar) {
        // End of sentence - merge the group
        if let merged = mergeSegments(currentGroup) {
          grouped.append(merged)
        }
        currentGroup = []
      }
    }

    // Handle any remaining segments that didn't end with punctuation
    if !currentGroup.isEmpty, let merged = mergeSegments(currentGroup) {
      grouped.append(merged)
    }

    return grouped
  }

  /// Merges multiple transcript segments into a single segment
  private func mergeSegments(_ segments: [TranscriptSegment]) -> TranscriptSegment? {
    guard let first = segments.first, let last = segments.last else { return nil }

    // Combine text with spaces
    let combinedText = segments.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")

    // Combine translated text if all segments have translations
    let translatedText: String?
    if segments.allSatisfy({ $0.translatedText != nil }) {
      translatedText = segments.compactMap { $0.translatedText?.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    } else {
      translatedText = nil
    }

    // Combine word timings from all segments (if any have them)
    let combinedWordTimings: [WordTiming]?
    let allTimings = segments.compactMap { $0.wordTimings }.flatMap { $0 }
    combinedWordTimings = allTimings.isEmpty ? nil : allTimings

    return TranscriptSegment(
      id: first.id,
      startTime: first.startTime,
      endTime: last.endTime,
      text: combinedText,
      translatedText: translatedText,
      wordTimings: combinedWordTimings
    )
  }

  /// Parses SRT time format (HH:MM:SS,mmm) to TimeInterval
  private func parseSRTTime(_ timeString: String) -> TimeInterval? {
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

  /// Decode common HTML entities in text
  private func decodeHTMLEntities(_ text: String) -> String {
    var result = text

    // Common HTML entities
    let entities: [(String, String)] = [
      ("&nbsp;", " "),
      ("&amp;", "&"),
      ("&lt;", "<"),
      ("&gt;", ">"),
      ("&quot;", "\""),
      ("&apos;", "'"),
      ("&#39;", "'"),
      ("&rsquo;", "'"),
      ("&lsquo;", "'"),
      ("&rdquo;", "\""),
      ("&ldquo;", "\""),
      ("&ndash;", "–"),
      ("&mdash;", "—"),
      ("&hellip;", "…"),
      ("&#160;", " "),  // Numeric form of &nbsp;
    ]

    for (entity, replacement) in entities {
      result = result.replacingOccurrences(of: entity, with: replacement)
    }

    // Handle numeric HTML entities (&#NNN;)
    if let regex = try? NSRegularExpression(pattern: "&#(\\d+);", options: []) {
      let nsString = result as NSString
      let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))

      // Process matches in reverse to avoid index shifting
      for match in matches.reversed() {
        if match.numberOfRanges >= 2 {
          let codeRange = match.range(at: 1)
          if let code = Int(nsString.substring(with: codeRange)),
             let scalar = Unicode.Scalar(code) {
            let replacement = String(Character(scalar))
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
          }
        }
      }
    }

    return result
  }

  /// Returns filtered segments based on search query (searches both original and translated text)
  var filteredTranscriptSegments: [TranscriptSegment] {
    guard !transcriptSearchQuery.isEmpty else {
      return transcriptSegments
    }

    let query = transcriptSearchQuery.lowercased()
    return transcriptSegments.filter { segment in
      // Search in original text
      if segment.text.lowercased().contains(query) {
        return true
      }
      // Also search in translated text if available
      if let translatedText = segment.translatedText,
         translatedText.lowercased().contains(query) {
        return true
      }
      return false
    }
  }

  /// Returns the currently playing segment based on playback time
  var currentSegmentId: Int? {
    guard isPlayingThisEpisode else { return nil }
    let time = audioManager.currentTime

    return transcriptSegments.first { segment in
      time >= segment.startTime && time <= segment.endTime
    }?.id
  }

  /// Returns true if transcript is currently being processed (downloading model or transcribing)
  var isTranscriptProcessing: Bool {
    switch transcriptState {
    case .downloadingModel, .transcribing:
      return true
    default:
      return false
    }
  }

  /// Seeks to the start of a transcript segment and starts playback if needed
  func seekToSegment(_ segment: TranscriptSegment) {
    // If not playing this episode, start playback first
    if !isPlayingThisEpisode {
      playAction()
      // Give player time to initialize, then seek
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(0.3))
        self?.audioManager.seek(to: segment.startTime)
      }
    } else {
      audioManager.seek(to: segment.startTime)
    }
  }

  // MARK: - On-Device AI (Quick Tags from Metadata)

  // On-device AI availability
  var onDeviceAIAvailability: FoundationModelsAvailability = .unavailable(reason: "Checking...")

  // Quick tags state and cache
  var quickTagsState: AnalysisState = .idle
  var quickTagsCache: CachedQuickTags = CachedQuickTags()

  /// Check if on-device Foundation Models are available
  func checkOnDeviceAIAvailability() {
    if #available(iOS 26.0, macOS 26.0, *) {
      Task {
        let service = AppleFoundationModelsService()
        let availability = await service.checkAvailability()

        await MainActor.run {
          onDeviceAIAvailability = availability
        }
      }
    } else {
      onDeviceAIAvailability = .unavailable(reason: "Requires iOS 26 or later")
    }
  }

  /// Generate quick tags from episode metadata (on-device, fast)
  func generateQuickTags() {
    guard #available(iOS 26.0, macOS 26.0, *) else {
      quickTagsState = .error("Requires iOS 26 or later")
      return
    }

    guard onDeviceAIAvailability.isAvailable else {
      quickTagsState = .error(onDeviceAIAvailability.message ?? "On-device AI unavailable")
      return
    }

    Task {
      do {
        await MainActor.run {
          quickTagsState = .analyzing(progress: 0, message: "Generating tags...")
        }

        let service = AppleFoundationModelsService()
        let tags = try await service.generateQuickTags(
          title: episode.title,
          description: episode.podcastEpisodeDescription ?? "",
          podcastTitle: podcastTitle,
          duration: episode.duration.map { TimeInterval($0) },
          releaseDate: episode.pubDate,
          progressCallback: { [weak self] message, progress in
            Task { @MainActor in
              self?.quickTagsState = .analyzing(progress: progress, message: message)
            }
          }
        )

        await MainActor.run {
          quickTagsCache.tags = tags
          quickTagsCache.generatedAt = Date()
          quickTagsState = .completed

          // Save to SwiftData
          saveQuickTagsToSwiftData(tags: tags)

          logger.info("Quick tags generated successfully")
        }
      } catch {
        await MainActor.run {
          quickTagsState = .error("Failed: \(error.localizedDescription)")
          logger.error("Quick tags generation failed: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Generate brief summary from metadata (on-device, fast)
  func generateBriefSummary() {
    guard #available(iOS 26.0, macOS 26.0, *) else {
      quickTagsState = .error("Requires iOS 26 or later")
      return
    }

    guard onDeviceAIAvailability.isAvailable else {
      quickTagsState = .error(onDeviceAIAvailability.message ?? "On-device AI unavailable")
      return
    }

    Task {
      do {
        await MainActor.run {
          quickTagsState = .analyzing(progress: 0, message: "Creating summary...")
        }

        let service = AppleFoundationModelsService()
        let summary = try await service.generateBriefSummary(
          title: episode.title,
          description: episode.podcastEpisodeDescription ?? "",
          progressCallback: { [weak self] message, progress in
            Task { @MainActor in
              self?.quickTagsState = .analyzing(progress: progress, message: message)
            }
          }
        )

        await MainActor.run {
          quickTagsCache.briefSummary = summary
          quickTagsCache.generatedAt = Date()
          quickTagsState = .completed
          logger.info("Brief summary generated successfully")
        }
      } catch {
        await MainActor.run {
          quickTagsState = .error("Failed: \(error.localizedDescription)")
          logger.error("Brief summary generation failed: \(error.localizedDescription)")
        }
      }
    }
  }

  // MARK: - Cloud AI (Transcript Analysis with BYOK)

  // Cloud analysis state and cache
  var cloudAnalysisState: AnalysisState = .idle
  var cloudQuestionState: AnalysisState = .idle
  var cloudAnalysisCache: CachedCloudAnalysis = CachedCloudAnalysis()

  // Streaming response text (updated in real-time)
  var streamingText: String = ""
  var isStreaming: Bool = false
  var currentStreamingType: CloudAnalysisType?

  /// Generate cloud-based transcript analysis with streaming
  func generateCloudAnalysis(type: CloudAnalysisType) {
    let settings = AISettingsManager.shared

    guard settings.hasConfiguredProvider else {
      cloudAnalysisState = .error("No API key configured. Go to Settings > AI Settings.")
      return
    }

    guard hasTranscript else {
      cloudAnalysisState = .error("No transcript available. Generate transcript first.")
      return
    }

    Task {
      do {
        await MainActor.run {
          cloudAnalysisState = .analyzing(progress: 0, message: "Preparing...")
          streamingText = ""
          isStreaming = true
          currentStreamingType = type
        }

        let service = CloudAIService.shared
        let plainText = SRTParser.extractPlainText(from: transcriptText)

        let result = try await service.analyzeTranscriptStreaming(
          plainText,
          episodeTitle: episode.title,
          podcastTitle: podcastTitle,
          analysisType: type,
          podcastLanguage: podcastLanguage,
          onChunk: { [weak self] text in
            self?.streamingText = text
          },
          progressCallback: { [weak self] message, progress in
            Task { @MainActor in
              self?.cloudAnalysisState = .analyzing(progress: progress, message: message)
            }
          }
        )

        await MainActor.run {
          isStreaming = false
          currentStreamingType = nil
          streamingText = ""

          // Store in cache
          switch type {
          case .summary:
            cloudAnalysisCache.summary = result
          case .entities:
            cloudAnalysisCache.entities = result
          case .highlights:
            cloudAnalysisCache.highlights = result
          case .fullAnalysis:
            cloudAnalysisCache.fullAnalysis = result
          }
          cloudAnalysisState = .completed

          // Save to SwiftData
          saveCloudAnalysisToSwiftData(result: result, type: type)

          logger.info("Cloud analysis (\(type.rawValue)) completed successfully")
        }
      } catch {
        await MainActor.run {
          isStreaming = false
          currentStreamingType = nil
          streamingText = ""
          cloudAnalysisState = .error(error.localizedDescription)
          logger.error("Cloud analysis failed: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Ask a question about the episode using cloud AI
  func askCloudQuestion(_ question: String) {
    let settings = AISettingsManager.shared

    guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    guard settings.hasConfiguredProvider else {
      cloudQuestionState = .error("No API key configured. Go to Settings > AI Settings.")
      return
    }

    guard hasTranscript else {
      cloudQuestionState = .error("No transcript available. Generate transcript first.")
      return
    }

    Task {
      do {
        await MainActor.run {
          cloudQuestionState = .analyzing(progress: 0, message: "Processing question...")
        }

        let service = CloudAIService.shared
        let plainText = SRTParser.extractPlainText(from: transcriptText)

        let result = try await service.askQuestion(
          question,
          transcript: plainText,
          episodeTitle: episode.title,
          podcastLanguage: podcastLanguage,
          progressCallback: { [weak self] message, progress in
            Task { @MainActor in
              self?.cloudQuestionState = .analyzing(progress: progress, message: message)
            }
          }
        )

        await MainActor.run {
          cloudAnalysisCache.questionAnswers.append(result)
          cloudQuestionState = .completed

          // Save Q&A to SwiftData
          saveQAToSwiftData(result)

          logger.info("Cloud Q&A completed successfully - Provider: \(result.provider.displayName), Model: \(result.model)")
        }
      } catch {
        await MainActor.run {
          cloudQuestionState = .error(error.localizedDescription)
          logger.error("Cloud Q&A failed: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Clear a specific cloud analysis result
  func clearCloudAnalysis(type: CloudAnalysisType) {
    switch type {
    case .summary:
      cloudAnalysisCache.summary = nil
    case .entities:
      cloudAnalysisCache.entities = nil
    case .highlights:
      cloudAnalysisCache.highlights = nil
    case .fullAnalysis:
      cloudAnalysisCache.fullAnalysis = nil
    }
    cloudAnalysisState = .idle
  }

  /// Clear all AI results
  func clearAllAIResults() {
    quickTagsCache.clear()
    quickTagsState = .idle
    cloudAnalysisCache.clearAll()
    cloudAnalysisState = .idle
    cloudQuestionState = .idle
  }

  // MARK: - Legacy AI Properties (for backward compatibility)

  var aiAvailability: FoundationModelsAvailability {
    onDeviceAIAvailability
  }

  func checkAIAvailability() {
    checkOnDeviceAIAvailability()
  }

  // MARK: - SwiftData AI Analysis Persistence

  /// Cached SwiftData model for AI analysis
  private var aiAnalysisModel: EpisodeAIAnalysis?

  /// Load AI analysis from SwiftData on initialization
  func loadAIAnalysisFromSwiftData() {
    guard let context = modelContext else { return }

    // Load cloud analysis
    let audioURL = episode.audioURL ?? ""
    let cloudDescriptor = FetchDescriptor<EpisodeAIAnalysis>(
      predicate: #Predicate { $0.episodeAudioURL == audioURL }
    )

    do {
      let results = try context.fetch(cloudDescriptor)
      if let model = results.first {
        aiAnalysisModel = model
        restoreCloudAnalysisFromModel(model)
      }
    } catch {
      logger.error("Failed to load AI analysis: \(error.localizedDescription)")
    }

    // Load quick tags
    let tagsDescriptor = FetchDescriptor<EpisodeQuickTagsModel>(
      predicate: #Predicate { $0.episodeAudioURL == audioURL }
    )

    do {
      let results = try context.fetch(tagsDescriptor)
      if let model = results.first {
        restoreQuickTagsFromModel(model)
      }
    } catch {
      logger.error("Failed to load quick tags: \(error.localizedDescription)")
    }
  }

  /// Restore cloud analysis cache from SwiftData model
  private func restoreCloudAnalysisFromModel(_ model: EpisodeAIAnalysis) {
    // Restore summary
    if let summaryText = model.summaryText {
      let parsed = ParsedSummaryResponse(
        summary: summaryText,
        mainTopics: model.summaryMainTopics ?? [],
        keyTakeaways: model.summaryKeyTakeaways ?? [],
        targetAudience: model.summaryTargetAudience ?? "",
        engagementLevel: model.summaryEngagementLevel ?? ""
      )
      cloudAnalysisCache.summary = CloudAnalysisResult(
        type: .summary,
        content: summaryText,
        parsedSummary: parsed,
        parsedEntities: nil,
        parsedHighlights: nil,
        parsedFullAnalysis: nil,
        provider: CloudAIProvider(rawValue: model.summaryProvider ?? "") ?? .openai,
        model: model.summaryModel ?? "",
        timestamp: model.summaryGeneratedAt ?? model.createdAt
      )
    }

    // Restore entities
    if model.hasEntities {
      let parsed = ParsedEntitiesResponse(
        people: model.entitiesPeople ?? [],
        organizations: model.entitiesOrganizations ?? [],
        products: model.entitiesProducts ?? [],
        locations: model.entitiesLocations ?? [],
        resources: model.entitiesResources ?? []
      )
      let content = formatEntitiesAsText(parsed)
      cloudAnalysisCache.entities = CloudAnalysisResult(
        type: .entities,
        content: content,
        parsedSummary: nil,
        parsedEntities: parsed,
        parsedHighlights: nil,
        parsedFullAnalysis: nil,
        provider: CloudAIProvider(rawValue: model.entitiesProvider ?? "") ?? .openai,
        model: model.entitiesModel ?? "",
        timestamp: model.entitiesGeneratedAt ?? model.createdAt
      )
    }

    // Restore highlights
    if model.hasHighlights {
      let parsed = ParsedHighlightsResponse(
        highlights: model.highlightsList ?? [],
        bestQuote: model.highlightsBestQuote ?? "",
        actionItems: model.highlightsActionItems ?? [],
        controversialPoints: model.highlightsControversialPoints,
        entertainingMoments: model.highlightsEntertainingMoments
      )
      let content = formatHighlightsAsText(parsed)
      cloudAnalysisCache.highlights = CloudAnalysisResult(
        type: .highlights,
        content: content,
        parsedSummary: nil,
        parsedEntities: nil,
        parsedHighlights: parsed,
        parsedFullAnalysis: nil,
        provider: CloudAIProvider(rawValue: model.highlightsProvider ?? "") ?? .openai,
        model: model.highlightsModel ?? "",
        timestamp: model.highlightsGeneratedAt ?? model.createdAt
      )
    }

    // Restore full analysis
    if let fullText = model.fullAnalysisText {
      // Try to parse as JSON for structured display
      let parsedFull = parseFullAnalysisJSON(fullText)
      cloudAnalysisCache.fullAnalysis = CloudAnalysisResult(
        type: .fullAnalysis,
        content: fullText,
        parsedSummary: nil,
        parsedEntities: nil,
        parsedHighlights: nil,
        parsedFullAnalysis: parsedFull,
        provider: CloudAIProvider(rawValue: model.fullAnalysisProvider ?? "") ?? .openai,
        model: model.fullAnalysisModel ?? "",
        timestamp: model.fullAnalysisGeneratedAt ?? model.createdAt
      )
    }

    // Restore Q&A history
    cloudAnalysisCache.questionAnswers = model.qaHistory
  }

  /// Restore quick tags cache from SwiftData model
  private func restoreQuickTagsFromModel(_ model: EpisodeQuickTagsModel) {
    let tags = EpisodeQuickTags(
      tags: model.tags,
      primaryCategory: model.primaryCategory,
      secondaryCategory: model.secondaryCategory,
      contentType: model.contentType,
      difficulty: model.difficulty
    )
    quickTagsCache.tags = tags
    quickTagsCache.briefSummary = model.briefSummary
    quickTagsCache.generatedAt = model.generatedAt
  }

  /// Save quick tags to SwiftData
  private func saveQuickTagsToSwiftData(tags: EpisodeQuickTags) {
    guard let context = modelContext else { return }
    guard let audioURL = episode.audioURL else { return }

    // Find existing or create new
    let descriptor = FetchDescriptor<EpisodeQuickTagsModel>(
      predicate: #Predicate { $0.episodeAudioURL == audioURL }
    )

    do {
      let results = try context.fetch(descriptor)
      if let existing = results.first {
        // Update existing
        existing.tags = tags.tags
        existing.primaryCategory = tags.primaryCategory
        existing.secondaryCategory = tags.secondaryCategory
        existing.contentType = tags.contentType
        existing.difficulty = tags.difficulty
        existing.briefSummary = quickTagsCache.briefSummary
        existing.generatedAt = Date()
      } else {
        // Create new
        let model = EpisodeQuickTagsModel(
          episodeAudioURL: audioURL,
          episodeTitle: episode.title,
          tags: tags.tags,
          primaryCategory: tags.primaryCategory,
          secondaryCategory: tags.secondaryCategory,
          contentType: tags.contentType,
          difficulty: tags.difficulty,
          briefSummary: quickTagsCache.briefSummary
        )
        context.insert(model)
      }

      try context.save()
      logger.info("Quick tags saved to SwiftData")
    } catch {
      logger.error("Failed to save quick tags: \(error.localizedDescription)")
    }
  }

  /// Save cloud analysis to SwiftData
  private func saveCloudAnalysisToSwiftData(result: CloudAnalysisResult, type: CloudAnalysisType) {
    guard let context = modelContext else { return }
    guard let audioURL = episode.audioURL else { return }

    // Find existing or create new
    let descriptor = FetchDescriptor<EpisodeAIAnalysis>(
      predicate: #Predicate { $0.episodeAudioURL == audioURL }
    )

    do {
      let results = try context.fetch(descriptor)
      let model: EpisodeAIAnalysis

      if let existing = results.first {
        model = existing
      } else {
        model = EpisodeAIAnalysis(
          episodeAudioURL: audioURL,
          episodeTitle: episode.title,
          podcastTitle: podcastTitle
        )
        context.insert(model)
      }

      // Update based on analysis type
      switch type {
      case .summary:
        if let parsed = result.parsedSummary {
          model.summaryText = parsed.summary
          model.summaryMainTopics = parsed.mainTopics
          model.summaryKeyTakeaways = parsed.keyTakeaways
          model.summaryTargetAudience = parsed.targetAudience
          model.summaryEngagementLevel = parsed.engagementLevel
        } else {
          model.summaryText = result.content
        }
        model.summaryProvider = result.provider.rawValue
        model.summaryModel = result.model
        model.summaryGeneratedAt = result.timestamp

      case .entities:
        if let parsed = result.parsedEntities {
          model.entitiesPeople = parsed.people
          model.entitiesOrganizations = parsed.organizations
          model.entitiesProducts = parsed.products
          model.entitiesLocations = parsed.locations
          model.entitiesResources = parsed.resources
        }
        model.entitiesProvider = result.provider.rawValue
        model.entitiesModel = result.model
        model.entitiesGeneratedAt = result.timestamp

      case .highlights:
        if let parsed = result.parsedHighlights {
          model.highlightsList = parsed.highlights
          model.highlightsBestQuote = parsed.bestQuote
          model.highlightsActionItems = parsed.actionItems
          model.highlightsControversialPoints = parsed.controversialPoints
          model.highlightsEntertainingMoments = parsed.entertainingMoments
        }
        model.highlightsProvider = result.provider.rawValue
        model.highlightsModel = result.model
        model.highlightsGeneratedAt = result.timestamp

      case .fullAnalysis:
        model.fullAnalysisText = result.content
        model.fullAnalysisProvider = result.provider.rawValue
        model.fullAnalysisModel = result.model
        model.fullAnalysisGeneratedAt = result.timestamp
      }

      model.updatedAt = Date()
      aiAnalysisModel = model

      try context.save()
      logger.info("Cloud analysis (\(type.rawValue)) saved to SwiftData")
    } catch {
      logger.error("Failed to save cloud analysis: \(error.localizedDescription)")
    }
  }

  /// Save Q&A to SwiftData
  private func saveQAToSwiftData(_ result: CloudQAResult) {
    guard let context = modelContext else { return }
    guard let audioURL = episode.audioURL else { return }

    // Find existing or create new
    let descriptor = FetchDescriptor<EpisodeAIAnalysis>(
      predicate: #Predicate { $0.episodeAudioURL == audioURL }
    )

    do {
      let results = try context.fetch(descriptor)
      let model: EpisodeAIAnalysis

      if let existing = results.first {
        model = existing
      } else {
        model = EpisodeAIAnalysis(
          episodeAudioURL: audioURL,
          episodeTitle: episode.title,
          podcastTitle: podcastTitle
        )
        context.insert(model)
      }

      model.addQA(result)
      aiAnalysisModel = model

      try context.save()
      logger.info("Q&A saved to SwiftData - Provider: \(result.provider.displayName), Model: \(result.model)")
    } catch {
      logger.error("Failed to save Q&A: \(error.localizedDescription)")
    }
  }

  // MARK: - Format Helpers

  private func formatEntitiesAsText(_ entities: ParsedEntitiesResponse) -> String {
    var parts: [String] = []
    if !entities.people.isEmpty { parts.append("People: \(entities.people.joined(separator: ", "))") }
    if !entities.organizations.isEmpty { parts.append("Organizations: \(entities.organizations.joined(separator: ", "))") }
    if !entities.products.isEmpty { parts.append("Products: \(entities.products.joined(separator: ", "))") }
    if !entities.locations.isEmpty { parts.append("Locations: \(entities.locations.joined(separator: ", "))") }
    if !entities.resources.isEmpty { parts.append("Resources: \(entities.resources.joined(separator: ", "))") }
    return parts.joined(separator: "\n\n")
  }

  private func formatHighlightsAsText(_ highlights: ParsedHighlightsResponse) -> String {
    var parts: [String] = []
    if !highlights.highlights.isEmpty { parts.append("Highlights:\n• " + highlights.highlights.joined(separator: "\n• ")) }
    if !highlights.bestQuote.isEmpty { parts.append("Best Quote: \"\(highlights.bestQuote)\"") }
    if !highlights.actionItems.isEmpty { parts.append("Action Items:\n• " + highlights.actionItems.joined(separator: "\n• ")) }
    if let controversial = highlights.controversialPoints, !controversial.isEmpty {
      parts.append("Controversial Points:\n• " + controversial.joined(separator: "\n• "))
    }
    if let entertaining = highlights.entertainingMoments, !entertaining.isEmpty {
      parts.append("Entertaining Moments:\n• " + entertaining.joined(separator: "\n• "))
    }
    return parts.joined(separator: "\n\n")
  }

  /// Parse full analysis JSON from stored content
  private func parseFullAnalysisJSON(_ content: String) -> ParsedFullAnalysisResponse? {
    var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)

    // Remove markdown code block if present
    if jsonString.hasPrefix("```json") {
      jsonString = String(jsonString.dropFirst(7))
    } else if jsonString.hasPrefix("```") {
      jsonString = String(jsonString.dropFirst(3))
    }
    if jsonString.hasSuffix("```") {
      jsonString = String(jsonString.dropLast(3))
    }
    jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let data = jsonString.data(using: .utf8) else { return nil }

    do {
      return try JSONDecoder().decode(ParsedFullAnalysisResponse.self, from: data)
    } catch {
      logger.debug("Failed to parse full analysis JSON: \(error.localizedDescription)")
      return nil
    }
  }

  // MARK: - Cleanup

  /// Cancel all active subscriptions to prevent memory leaks
  func cleanup() {
    // Stop transcript observation
    isObservingTranscriptManager = false

    // Cancel share task
    shareTask?.cancel()
    shareTask = nil

    // Explicitly cancel timer tasks (critical for preventing memory leaks)
    downloadTimerTask?.cancel()
    downloadTimerTask = nil

    playbackTimerTask?.cancel()
    playbackTimerTask = nil
  }

  deinit {
    // Ensure cleanup even if cleanup() wasn't called (defensive programming)
    downloadTimerTask?.cancel()
    playbackTimerTask?.cancel()
    shareTask?.cancel()
  }
}
