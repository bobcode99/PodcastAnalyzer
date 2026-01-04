//
//  EpisodeStatusUtils.swift
//  PodcastAnalyzer
//
//  Centralized utilities for checking episode status (downloaded, transcript, AI analysis, etc.)
//

import Foundation
import SwiftData

// MARK: - Episode Key Utilities

enum EpisodeKeyUtils {
  /// Unit Separator (U+001F) used as delimiter between podcast title and episode title
  static let delimiter = "\u{1F}"

  /// Create an episode key from podcast and episode titles
  static func makeKey(podcastTitle: String, episodeTitle: String) -> String {
    "\(podcastTitle)\(delimiter)\(episodeTitle)"
  }

  /// Parse an episode key into podcast and episode titles
  /// Supports both new format (Unit Separator) and old format (|) for backward compatibility
  static func parseKey(_ episodeKey: String) -> (podcastTitle: String, episodeTitle: String)? {
    // Try new format first (Unit Separator)
    if let delimiterIndex = episodeKey.range(of: delimiter) {
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
}

// MARK: - Episode Status Checker

/// Utility struct for checking various episode statuses
struct EpisodeStatusChecker {
  let episodeTitle: String
  let podcastTitle: String
  let audioURL: String?

  private let downloadManager = DownloadManager.shared

  init(episodeTitle: String, podcastTitle: String, audioURL: String? = nil) {
    self.episodeTitle = episodeTitle
    self.podcastTitle = podcastTitle
    self.audioURL = audioURL
  }

  /// Initialize from a LibraryEpisode
  init(episode: LibraryEpisode) {
    self.episodeTitle = episode.episodeInfo.title
    self.podcastTitle = episode.podcastTitle
    self.audioURL = episode.episodeInfo.audioURL
  }

  /// Initialize from a PodcastEpisodeInfo
  init(episode: PodcastEpisodeInfo, podcastTitle: String) {
    self.episodeTitle = episode.title
    self.podcastTitle = podcastTitle
    self.audioURL = episode.audioURL
  }

  // MARK: - Download Status

  /// Get the current download state for this episode
  var downloadState: DownloadState {
    downloadManager.getDownloadState(
      episodeTitle: episodeTitle,
      podcastTitle: podcastTitle
    )
  }

  /// Check if episode is fully downloaded
  var isDownloaded: Bool {
    if case .downloaded = downloadState { return true }
    return false
  }

  /// Check if episode is currently downloading
  var isDownloading: Bool {
    if case .downloading = downloadState { return true }
    return false
  }

  /// Get download progress (0.0 to 1.0) if downloading
  var downloadProgress: Double? {
    if case .downloading(let progress) = downloadState {
      return progress
    }
    return nil
  }

  /// Get the local file path if downloaded
  var localAudioPath: String? {
    if case .downloaded(let path) = downloadState {
      return path
    }
    return nil
  }

  /// Get the playback URL (local file if downloaded, otherwise remote URL)
  var playbackURL: String {
    if let path = localAudioPath {
      return "file://" + path
    }
    return audioURL ?? ""
  }

  // MARK: - Transcript Status

  /// Check if a transcript (SRT file) exists for this episode
  var hasTranscript: Bool {
    let fm = FileManager.default
    let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let captionsDir = docsDir.appendingPathComponent("Captions", isDirectory: true)

    let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
    let baseFileName = "\(podcastTitle)_\(episodeTitle)"
      .components(separatedBy: invalidCharacters)
      .joined(separator: "_")
      .trimmingCharacters(in: .whitespaces)

    let srtPath = captionsDir.appendingPathComponent("\(baseFileName).srt")
    return fm.fileExists(atPath: srtPath.path)
  }

  // MARK: - AI Analysis Status

  /// Check if AI analysis exists for this episode (requires ModelContext)
  func hasAIAnalysis(in modelContext: ModelContext) -> Bool {
    guard let audioURL = audioURL else { return false }

    let descriptor = FetchDescriptor<EpisodeAIAnalysis>(
      predicate: #Predicate { $0.episodeAudioURL == audioURL }
    )

    guard let model = try? modelContext.fetch(descriptor).first else {
      return false
    }

    return model.hasFullAnalysis
      || model.hasSummary
      || model.hasEntities
      || model.hasHighlights
      || (model.qaHistoryJSON != nil && !model.qaHistoryJSON!.isEmpty)
  }

  // MARK: - Episode Key

  /// Get the unique key for this episode
  var episodeKey: String {
    EpisodeKeyUtils.makeKey(podcastTitle: podcastTitle, episodeTitle: episodeTitle)
  }
}

