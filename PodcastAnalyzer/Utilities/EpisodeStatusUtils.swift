//
//  EpisodeStatusUtils.swift
//  PodcastAnalyzer
//
//  Centralized utilities for checking episode status (downloaded, transcript, AI analysis, etc.)
//

import Combine
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

// MARK: - Episode Status View Helper

/// A helper class that can be observed for status updates
@MainActor
class EpisodeStatusObserver: ObservableObject {
  @Published var isDownloaded: Bool = false
  @Published var isDownloading: Bool = false
  @Published var downloadProgress: Double = 0
  @Published var hasTranscript: Bool = false
  @Published var hasAIAnalysis: Bool = false

  private var checker: EpisodeStatusChecker
  private var modelContext: ModelContext?

  init(episodeTitle: String, podcastTitle: String, audioURL: String? = nil) {
    self.checker = EpisodeStatusChecker(
      episodeTitle: episodeTitle,
      podcastTitle: podcastTitle,
      audioURL: audioURL
    )
    updateStatus()
  }

  init(episode: LibraryEpisode) {
    self.checker = EpisodeStatusChecker(episode: episode)
    updateStatus()
  }

  init(episode: PodcastEpisodeInfo, podcastTitle: String) {
    self.checker = EpisodeStatusChecker(episode: episode, podcastTitle: podcastTitle)
    updateStatus()
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    checkAIAnalysis()
  }

  func updateStatus() {
    isDownloaded = checker.isDownloaded
    isDownloading = checker.isDownloading
    downloadProgress = checker.downloadProgress ?? 0
    hasTranscript = checker.hasTranscript
  }

  func checkAIAnalysis() {
    guard let context = modelContext else { return }
    hasAIAnalysis = checker.hasAIAnalysis(in: context)
  }

  var playbackURL: String {
    checker.playbackURL
  }

  var downloadState: DownloadState {
    checker.downloadState
  }
}

// MARK: - Status Icons View

import SwiftUI

/// Reusable view for displaying episode status icons
struct EpisodeStatusIcons: View {
  let isStarred: Bool
  let isDownloaded: Bool
  let hasTranscript: Bool
  let hasAIAnalysis: Bool
  let isCompleted: Bool
  let showCompleted: Bool

  init(
    isStarred: Bool = false,
    isDownloaded: Bool = false,
    hasTranscript: Bool = false,
    hasAIAnalysis: Bool = false,
    isCompleted: Bool = false,
    showCompleted: Bool = true
  ) {
    self.isStarred = isStarred
    self.isDownloaded = isDownloaded
    self.hasTranscript = hasTranscript
    self.hasAIAnalysis = hasAIAnalysis
    self.isCompleted = isCompleted
    self.showCompleted = showCompleted
  }

  var body: some View {
    HStack(spacing: 4) {
      if isStarred {
        statusIcon("star.fill", color: .yellow)
      }

      if isDownloaded {
        statusIcon("arrow.down.circle.fill", color: .green)
      }

      if hasTranscript {
        statusIcon("captions.bubble.fill", color: .purple)
      }

      if hasAIAnalysis {
        statusIcon("sparkles", color: .orange)
      }

      if showCompleted && isCompleted {
        statusIcon("checkmark.circle.fill", color: .green)
      }
    }
  }

  private func statusIcon(_ name: String, color: Color) -> some View {
    Image(systemName: name)
      .font(.system(size: 10))
      .foregroundColor(color)
  }
}

/// Compact status icons for overlays on artwork
struct EpisodeStatusIconsCompact: View {
  let isStarred: Bool
  let isDownloaded: Bool
  let hasTranscript: Bool
  let hasAIAnalysis: Bool

  init(
    isStarred: Bool = false,
    isDownloaded: Bool = false,
    hasTranscript: Bool = false,
    hasAIAnalysis: Bool = false
  ) {
    self.isStarred = isStarred
    self.isDownloaded = isDownloaded
    self.hasTranscript = hasTranscript
    self.hasAIAnalysis = hasAIAnalysis
  }

  private var hasAnyStatus: Bool {
    isStarred || isDownloaded || hasTranscript || hasAIAnalysis
  }

  var body: some View {
    if hasAnyStatus {
      HStack(spacing: 3) {
        if isStarred {
          statusIcon("star.fill", color: .yellow)
        }
        if isDownloaded {
          statusIcon("arrow.down.circle.fill", color: .green)
        }
        if hasTranscript {
          statusIcon("captions.bubble.fill", color: .purple)
        }
        if hasAIAnalysis {
          statusIcon("sparkles", color: .orange)
        }
      }
      .padding(4)
      .background(.ultraThinMaterial)
      .cornerRadius(6)
      .padding(4)
    }
  }

  private func statusIcon(_ name: String, color: Color) -> some View {
    Image(systemName: name)
      .font(.system(size: 9, weight: .bold))
      .foregroundColor(color)
  }
}
