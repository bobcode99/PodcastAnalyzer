//
//  EpisodeDetailViewModel.swift
//  PodcastAnalyzer
//
//  Enhanced with download management and playback state
//

import Combine
import SwiftData
import SwiftUI
import ZMarkupParser
import os.log

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "EpisodeDetailViewModel")

/// Represents a single transcript segment with timing information
struct TranscriptSegment: Identifiable, Equatable {
  let id: Int
  let startTime: TimeInterval
  let endTime: TimeInterval
  let text: String

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
}

@Observable
final class EpisodeDetailViewModel {

  var descriptionView: AnyView = AnyView(
    Text("Loading...").foregroundColor(.secondary)
  )

  let episode: PodcastEpisodeInfo
  let podcastTitle: String
  private let fallbackImageURL: String?

  // Reference singletons
  let audioManager = EnhancedAudioManager.shared
  private let downloadManager = DownloadManager.shared

  // Download state
  var downloadState: DownloadState = .notDownloaded

  // Transcript state
  var transcriptState: TranscriptState = .idle
  var transcriptText: String = ""
  var isModelReady: Bool = false
  private let fileStorage = FileStorageManager.shared

  // Parsed transcript segments for live captions
  var transcriptSegments: [TranscriptSegment] = []
  var transcriptSearchQuery: String = ""

  // Playback state from SwiftData
  private var episodeModel: EpisodeDownloadModel?
  private var modelContext: ModelContext?

  // Cancellables for observation
  private var cancellables = Set<AnyCancellable>()

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

  /// Checks if there's an active transcript job and starts observing
  private func checkAndObserveTranscriptJob() {
    // Use Unit Separator (U+001F) as delimiter - same as TranscriptManager
    let delimiter = "\u{1F}"
    let jobId = "\(podcastTitle)\(delimiter)\(episode.title)"
    if TranscriptManager.shared.activeJobs[jobId] != nil {
      observeTranscriptManager()
    }
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    loadEpisodeModel()
    observePlaybackState()
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

  var isPlayingThisEpisode: Bool {
    guard let currentEpisode = audioManager.currentEpisode else { return false }
    return currentEpisode.title == episode.title && currentEpisode.podcastTitle == podcastTitle
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

  var savedDuration: TimeInterval {
    episodeModel?.duration ?? 0
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
      id: "\(podcastTitle)|\(episode.title)",
      title: episode.title,
      podcastTitle: podcastTitle,
      audioURL: playbackURL,
      imageURL: imageURLString
    )

    // Resume from saved position if available
    let startTime = episodeModel?.lastPlaybackPosition ?? 0

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
    // Poll for download state changes
    Timer.publish(every: 0.5, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        self?.updateDownloadState()
      }
      .store(in: &cancellables)
  }

  private func observePlaybackState() {
    // Poll for playback state changes (duration, progress, completion)
    Timer.publish(every: 2.0, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in
        self?.refreshEpisodeModel()
      }
      .store(in: &cancellables)
  }

  private func refreshEpisodeModel() {
    guard let context = modelContext else { return }

    let id = "\(podcastTitle)|\(episode.title)"
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

    let id = "\(podcastTitle)|\(episode.title)"
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
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      )
      return
    }

    let rootStyle = MarkupStyle(
      font: MarkupStyleFont(size: 16),
      foregroundColor: MarkupStyleColor(color: UIColor.label)
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

  func shareEpisode() {
    // TODO: Implement share functionality
    logger.debug("Share episode: \(self.episode.title)")
  }

  func translateDescription() {
    // TODO: Implement translation
    logger.debug("Translate description requested")
  }

  func toggleStar() {
    guard let model = episodeModel else { return }
    model.isStarred.toggle()

    do {
      try modelContext?.save()
    } catch {
      logger.error("Failed to save star state: \(error.localizedDescription)")
    }
  }

  func addToList() {
    // TODO: Implement add to list functionality
    logger.debug("Add to list: \(self.episode.title)")
  }

  func downloadAudio() {
    startDownload()
  }

  func reportIssue() {
    // TODO: Implement issue reporting
    logger.debug("Report issue for: \(self.episode.title)")
  }

  // MARK: - Transcript Methods

  /// Gets the podcast language from SwiftData, falling back to "en" if not found
  private func getPodcastLanguage() -> String {
    guard let context = modelContext else { return "en" }

    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.podcastInfo.title == podcastTitle }
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

      // Check if transcript already exists
      let exists = await fileStorage.captionFileExists(
        for: episode.title,
        podcastTitle: podcastTitle
      )

      if exists {
        await loadExistingTranscript()
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
    TranscriptManager.shared.$activeJobs
      .receive(on: DispatchQueue.main)
      .sink { [weak self] jobs in
        guard let self = self else { return }
        // Use Unit Separator (U+001F) as delimiter - same as TranscriptManager
        let delimiter = "\u{1F}"
        let jobId = "\(self.podcastTitle)\(delimiter)\(self.episode.title)"

        if let job = jobs[jobId] {
          // Update local state based on job status
          switch job.status {
          case .queued:
            self.transcriptState = .transcribing(progress: 0)
          case .downloadingModel(let progress):
            self.transcriptState = .downloadingModel(progress: progress)
          case .transcribing(let progress):
            self.transcriptState = .transcribing(progress: progress)
          case .completed:
            // Load the transcript from disk
            Task {
              await self.loadExistingTranscript()
            }
          case .failed(let error):
            self.transcriptState = .error(error)
          }
        }
      }
      .store(in: &cancellables)
  }

  func copyTranscriptToClipboard() {
    UIPasteboard.general.string = transcriptText
  }

  private func loadExistingTranscript() async {
    do {
      let content = try await fileStorage.loadCaptionFile(
        for: episode.title,
        podcastTitle: podcastTitle
      )

      await MainActor.run {
        transcriptText = content
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

  /// Parses SRT content and returns clean text without timestamps
  /// Each subtitle entry is separated by a newline for readability
  var cleanTranscriptText: String {
    guard !transcriptText.isEmpty else { return "" }

    var cleanLines: [String] = []
    let entries = transcriptText.components(separatedBy: "\n\n")

    for entry in entries {
      let lines = entry.components(separatedBy: "\n")
      // Skip index and timestamp lines, get text
      if lines.count >= 3 {
        let textLines = Array(lines[2...])
        let combinedText = textLines.joined(separator: " ").trimmingCharacters(
          in: .whitespaces)
        if !combinedText.isEmpty {
          cleanLines.append(combinedText)
        }
      }
    }

    // Join with newlines to preserve paragraph breaks
    return cleanLines.joined(separator: "\n\n")
  }

  // MARK: - Live Captions Methods

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

      guard !text.isEmpty else {
        logger.warning("Entry \(index + 1): empty text")
        continue
      }

      segments.append(
        TranscriptSegment(
          id: index,
          startTime: startTime,
          endTime: endTime,
          text: text
        ))
    }

    transcriptSegments = segments
    logger.info(
      "Successfully parsed \(segments.count) transcript segments from \(matches.count) regex matches"
    )

    // Debug: log first few segments if we have any
    if !segments.isEmpty {
      logger.info("First segment: \(segments[0].text.prefix(50))...")
      if segments.count > 1 {
        logger.info("Second segment: \(segments[1].text.prefix(50))...")
      }
    }
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

  /// Returns filtered segments based on search query
  var filteredTranscriptSegments: [TranscriptSegment] {
    guard !transcriptSearchQuery.isEmpty else {
      return transcriptSegments
    }

    let query = transcriptSearchQuery.lowercased()
    return transcriptSegments.filter { segment in
      segment.text.lowercased().contains(query)
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

  /// Seeks to the start of a transcript segment and starts playback if needed
  func seekToSegment(_ segment: TranscriptSegment) {
    // If not playing this episode, start playback first
    if !isPlayingThisEpisode {
      playAction()
      // Give player time to initialize, then seek
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        self?.audioManager.seek(to: segment.startTime)
      }
    } else {
      audioManager.seek(to: segment.startTime)
    }
  }
}
