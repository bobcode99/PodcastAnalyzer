//
//  DownloadState.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//

//
//  DownloadManager.swift
//  PodcastAnalyzer
//
//  Manages episode downloads with progress tracking
//

import Foundation
import Observation
import os.log

enum DownloadState: Codable, Equatable, Sendable {
  case notDownloaded
  case downloading(progress: Double)
  case finishing  // Download complete, processing file
  case downloaded(localPath: String)
  case failed(error: String)
}

// MARK: - Download Session Delegate

/// Handles URLSession delegate callbacks on background threads
/// Communicates with DownloadManager via async/await
private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, Sendable {

  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "DownloadDelegate")

  // Thread-safe storage for tracking downloads (accessed from URLSession background queue)
  private let downloadTracker = DownloadTracker()

  // Actor for thread-safe download tracking
  private actor DownloadTracker {
    var activeDownloads: [String: URLSessionDownloadTask] = [:]
    var originalURLs: [String: URL] = [:]
    var episodeLanguages: [String: String] = [:]

    func setDownload(_ task: URLSessionDownloadTask, for key: String, originalURL: URL, language: String) {
      activeDownloads[key] = task
      originalURLs[key] = originalURL
      episodeLanguages[key] = language
    }

    func getDownloadKey(for task: URLSessionTask) -> String? {
      activeDownloads.first(where: { $0.value === task })?.key
    }

    func getOriginalURL(for key: String) -> URL? {
      originalURLs[key]
    }

    func getLanguage(for key: String) -> String {
      episodeLanguages[key] ?? "en"
    }

    func removeDownload(for key: String) {
      activeDownloads.removeValue(forKey: key)
      originalURLs.removeValue(forKey: key)
      episodeLanguages.removeValue(forKey: key)
    }

    func cancelDownload(for key: String) -> URLSessionDownloadTask? {
      guard let task = activeDownloads[key] else { return nil }
      activeDownloads.removeValue(forKey: key)
      originalURLs.removeValue(forKey: key)
      episodeLanguages.removeValue(forKey: key)
      return task
    }
  }

  // Use Unit Separator (U+001F) as delimiter
  private static let episodeKeyDelimiter = "\u{1F}"

  func makeKey(episode: String, podcast: String) -> String {
    "\(podcast)\(Self.episodeKeyDelimiter)\(episode)"
  }

  private func parseEpisodeKey(_ episodeKey: String) -> (podcastTitle: String, episodeTitle: String)? {
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

  // MARK: - Public Methods (called from DownloadManager)

  func startDownload(url: URL, episodeTitle: String, podcastTitle: String, language: String, session: URLSession) async -> URLSessionDownloadTask {
    let episodeKey = makeKey(episode: episodeTitle, podcast: podcastTitle)

    // Cancel existing download if any
    if let existingTask = await downloadTracker.cancelDownload(for: episodeKey) {
      existingTask.cancel()
    }

    let task = session.downloadTask(with: url)
    await downloadTracker.setDownload(task, for: episodeKey, originalURL: url, language: language)
    return task
  }

  func cancelDownload(episodeTitle: String, podcastTitle: String) async {
    let episodeKey = makeKey(episode: episodeTitle, podcast: podcastTitle)
    if let task = await downloadTracker.cancelDownload(for: episodeKey) {
      task.cancel()
    }
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    // CRITICAL: URLSession deletes the temp file as soon as this method returns!
    // We MUST copy the file SYNCHRONOUSLY here, before any async work.

    // Get file extension from URL
    let originalURL = downloadTask.originalRequest?.url
    var fileExtension = originalURL?.pathExtension.lowercased() ?? "mp3"
    let validExtensions = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"]
    if fileExtension.isEmpty || !validExtensions.contains(fileExtension) {
      fileExtension = "mp3"
    }

    // Create our own temp file and copy SYNCHRONOUSLY
    let tempDirectory = FileManager.default.temporaryDirectory
    let ourTempFile = tempDirectory.appendingPathComponent(UUID().uuidString + ".\(fileExtension)")

    do {
      try FileManager.default.copyItem(at: location, to: ourTempFile)
      logger.info("Copied download to temp location: \(ourTempFile.lastPathComponent)")
    } catch {
      logger.error("Failed to copy temp file: \(error.localizedDescription)")
      // Update state asynchronously
      Task {
        if let episodeKey = await downloadTracker.getDownloadKey(for: downloadTask) {
          await downloadTracker.removeDownload(for: episodeKey)
          await MainActor.run {
            DownloadManager.shared.downloadStates[episodeKey] = .failed(error: "Failed to save download: \(error.localizedDescription)")
          }
        }
      }
      return
    }

    // Now do the rest asynchronously - the file is safely copied
    Task {
      guard let episodeKey = await downloadTracker.getDownloadKey(for: downloadTask) else {
        logger.warning("Download finished but no matching episode key found")
        try? FileManager.default.removeItem(at: ourTempFile)
        return
      }

      guard let (podcastTitle, episodeTitle) = parseEpisodeKey(episodeKey) else {
        logger.error("Invalid episode key format: \(episodeKey)")
        try? FileManager.default.removeItem(at: ourTempFile)
        return
      }

      logger.info("Download finished for: \(episodeTitle), processing file...")

      do {
        logger.info("Processing downloaded file for: \(episodeTitle)")

        // Set finishing state on main thread
        await MainActor.run {
          DownloadManager.shared.downloadStates[episodeKey] = .finishing
        }

        // Move to final destination
        let fileStorage = FileStorageManager.shared
        let destinationURL = try await fileStorage.saveAudioFile(
          from: ourTempFile,
          episodeTitle: episodeTitle,
          podcastTitle: podcastTitle
        )

        // Clean up temp file
        try? FileManager.default.removeItem(at: ourTempFile)

        // Get language for auto-transcript
        let language = await downloadTracker.getLanguage(for: episodeKey)

        // Remove from tracker
        await downloadTracker.removeDownload(for: episodeKey)

        // Update state on MainActor
        await MainActor.run {
          let manager = DownloadManager.shared
          manager.downloadStates[episodeKey] = .downloaded(localPath: destinationURL.path)

          // Post notification
          NotificationCenter.default.post(
            name: .episodeDownloadCompleted,
            object: nil,
            userInfo: [
              "episodeTitle": episodeTitle,
              "podcastTitle": podcastTitle,
              "localPath": destinationURL.path
            ]
          )

          // Trigger auto-transcript if enabled
          if manager.autoTranscriptEnabled {
            TranscriptManager.shared.queueTranscript(
              episodeTitle: episodeTitle,
              podcastTitle: podcastTitle,
              audioPath: destinationURL.path,
              language: language
            )
          }
        }

        logger.info("Download completed successfully: \(episodeTitle)")

      } catch {
        try? FileManager.default.removeItem(at: ourTempFile)
        await downloadTracker.removeDownload(for: episodeKey)

        await MainActor.run {
          DownloadManager.shared.downloadStates[episodeKey] = .failed(error: error.localizedDescription)
        }
        logger.error("Download save failed: \(error.localizedDescription)")
      }
    }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }

    let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

    Task {
      guard let episodeKey = await downloadTracker.getDownloadKey(for: downloadTask) else { return }

      await MainActor.run {
        let manager = DownloadManager.shared
        // Don't overwrite .finishing or .downloaded states with progress updates
        if case .downloading = manager.downloadStates[episodeKey] {
          manager.downloadStates[episodeKey] = .downloading(progress: progress)
        } else if manager.downloadStates[episodeKey] == nil {
          manager.downloadStates[episodeKey] = .downloading(progress: progress)
        }
      }
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error = error else { return }

    // Ignore cancellation errors
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
      logger.info("Download was cancelled")
      return
    }

    Task {
      guard let episodeKey = await downloadTracker.getDownloadKey(for: task) else { return }
      await downloadTracker.removeDownload(for: episodeKey)

      await MainActor.run {
        DownloadManager.shared.downloadStates[episodeKey] = .failed(error: error.localizedDescription)
      }
      logger.error("Download failed: \(error.localizedDescription)")
    }
  }
}

// MARK: - Download Manager

@MainActor
@Observable
final class DownloadManager {
  static let shared = DownloadManager()

  var downloadStates: [String: DownloadState] = [:]

  // Auto-transcript setting
  var autoTranscriptEnabled: Bool {
    didSet {
      UserDefaults.standard.set(autoTranscriptEnabled, forKey: "autoTranscriptEnabled")
    }
  }

  @ObservationIgnored
  private let sessionDelegate = DownloadSessionDelegate()

  @ObservationIgnored
  private lazy var urlSession: URLSession = {
    let config = URLSessionConfiguration.background(
      withIdentifier: "com.podcast.analyzer.downloads")
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    return URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
  }()

  @ObservationIgnored
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "DownloadManager")

  @ObservationIgnored
  private let fileStorage = FileStorageManager.shared

  private init() {
    self.autoTranscriptEnabled = UserDefaults.standard.bool(forKey: "autoTranscriptEnabled")
  }

  // MARK: - State Restoration

  /// Synchronously checks if audio file exists on disk
  private func checkAudioFileExistsSynchronously(episodeTitle: String, podcastTitle: String) -> String? {
    let fm = FileManager.default

    #if os(macOS)
    let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let audioDir = appSupport.appendingPathComponent("PodcastAnalyzer/Audio", isDirectory: true)
    #else
    let libraryDir = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    let audioDir = libraryDir.appendingPathComponent("Audio", isDirectory: true)
    #endif

    let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
    let baseFileName = "\(podcastTitle)_\(episodeTitle)"
      .components(separatedBy: invalidCharacters)
      .joined(separator: "_")
      .trimmingCharacters(in: .whitespaces)

    let possibleExtensions = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"]

    for ext in possibleExtensions {
      let path = audioDir.appendingPathComponent("\(baseFileName).\(ext)")
      if fm.fileExists(atPath: path.path) {
        return path.path
      }
    }
    return nil
  }

  // MARK: - Download Control

  func downloadEpisode(episode: PodcastEpisodeInfo, podcastTitle: String, language: String = "en") {
    let episodeKey = sessionDelegate.makeKey(episode: episode.title, podcast: podcastTitle)

    guard let audioURLString = episode.audioURL,
          let url = URL(string: audioURLString)
    else {
      logger.error("Invalid audio URL for episode: \(episode.title)")
      downloadStates[episodeKey] = .failed(error: "Invalid URL")
      return
    }

    // Check if already downloaded
    Task {
      let exists = await fileStorage.audioFileExists(
        for: episode.title, podcastTitle: podcastTitle)
      if exists {
        let path = await fileStorage.audioFilePath(
          for: episode.title, podcastTitle: podcastTitle)
        downloadStates[episodeKey] = .downloaded(localPath: path.path)
        return
      }

      // Start download
      downloadStates[episodeKey] = .downloading(progress: 0)
      let task = await sessionDelegate.startDownload(
        url: url,
        episodeTitle: episode.title,
        podcastTitle: podcastTitle,
        language: language,
        session: urlSession
      )
      task.resume()
      logger.info("Started download: \(episode.title)")
    }
  }

  func cancelDownload(episodeTitle: String, podcastTitle: String) {
    let episodeKey = sessionDelegate.makeKey(episode: episodeTitle, podcast: podcastTitle)

    Task {
      await sessionDelegate.cancelDownload(episodeTitle: episodeTitle, podcastTitle: podcastTitle)
      downloadStates[episodeKey] = .notDownloaded
      logger.info("Cancelled download: \(episodeTitle)")
    }
  }

  func deleteDownload(episodeTitle: String, podcastTitle: String) {
    let episodeKey = sessionDelegate.makeKey(episode: episodeTitle, podcast: podcastTitle)

    Task {
      do {
        try await fileStorage.deleteAudioFile(for: episodeTitle, podcastTitle: podcastTitle)

        // Also delete captions if they exist
        if await fileStorage.captionFileExists(for: episodeTitle, podcastTitle: podcastTitle) {
          try await fileStorage.deleteCaptionFile(for: episodeTitle, podcastTitle: podcastTitle)
        }

        downloadStates[episodeKey] = .notDownloaded
        logger.info("Deleted download: \(episodeTitle)")
      } catch {
        logger.error("Failed to delete download: \(error.localizedDescription)")
      }
    }
  }

  func getDownloadState(episodeTitle: String, podcastTitle: String) -> DownloadState {
    let episodeKey = sessionDelegate.makeKey(episode: episodeTitle, podcast: podcastTitle)

    // If we don't have a state, check disk to restore it
    if downloadStates[episodeKey] == nil {
      if let path = checkAudioFileExistsSynchronously(
        episodeTitle: episodeTitle, podcastTitle: podcastTitle)
      {
        // Schedule the state update for next run loop to avoid "publishing during view update"
        DispatchQueue.main.async { [weak self] in
          self?.downloadStates[episodeKey] = .downloaded(localPath: path)
        }
        return .downloaded(localPath: path)
      }
    }

    return downloadStates[episodeKey] ?? .notDownloaded
  }

  func getLocalPath(episodeTitle: String, podcastTitle: String) -> String? {
    let state = getDownloadState(episodeTitle: episodeTitle, podcastTitle: podcastTitle)
    if case .downloaded(let path) = state {
      return path
    }
    return nil
  }
}
