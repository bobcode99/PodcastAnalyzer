//
//  EpisodeRowView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/1/9.
//


import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct EpisodeRowView: View {
  let episode: PodcastEpisodeInfo
  let podcastTitle: String
  let fallbackImageURL: String?
  let podcastLanguage: String
  var downloadManager: DownloadManager
  let episodeModel: EpisodeDownloadModel?
  var showArtwork: Bool = true
  let onToggleStar: () -> Void
  let onDownload: () -> Void
  let onDeleteRequested: () -> Void
  let onTogglePlayed: () -> Void

  /// Primary initializer for PodcastEpisodeInfo (used in EpisodeListView)
  init(
    episode: PodcastEpisodeInfo,
    podcastTitle: String,
    fallbackImageURL: String?,
    podcastLanguage: String,
    downloadManager: DownloadManager = DownloadManager.shared,
    episodeModel: EpisodeDownloadModel? = nil,
    showArtwork: Bool = true,
    onToggleStar: @escaping () -> Void,
    onDownload: @escaping () -> Void,
    onDeleteRequested: @escaping () -> Void,
    onTogglePlayed: @escaping () -> Void
  ) {
    self.episode = episode
    self.podcastTitle = podcastTitle
    self.fallbackImageURL = fallbackImageURL
    self.podcastLanguage = podcastLanguage
    self.downloadManager = downloadManager
    self.episodeModel = episodeModel
    self.showArtwork = showArtwork
    self.onToggleStar = onToggleStar
    self.onDownload = onDownload
    self.onDeleteRequested = onDeleteRequested
    self.onTogglePlayed = onTogglePlayed
  }

  /// Convenience initializer for LibraryEpisode (used in Library views)
  init(
    libraryEpisode: LibraryEpisode,
    downloadManager: DownloadManager = DownloadManager.shared,
    episodeModel: EpisodeDownloadModel? = nil,
    showArtwork: Bool = true,
    onToggleStar: @escaping () -> Void,
    onDownload: @escaping () -> Void,
    onDeleteRequested: @escaping () -> Void,
    onTogglePlayed: @escaping () -> Void
  ) {
    self.episode = libraryEpisode.episodeInfo
    self.podcastTitle = libraryEpisode.podcastTitle
    self.fallbackImageURL = libraryEpisode.imageURL
    self.podcastLanguage = libraryEpisode.language
    self.downloadManager = downloadManager
    self.episodeModel = episodeModel
    self.showArtwork = showArtwork
    self.onToggleStar = onToggleStar
    self.onDownload = onDownload
    self.onDeleteRequested = onDeleteRequested
    self.onTogglePlayed = onTogglePlayed
  }

  @Environment(\.modelContext) private var modelContext
  private var audioManager: EnhancedAudioManager {
    EnhancedAudioManager.shared
  }
  private let applePodcastService = ApplePodcastService()
  @State private var shareTask: Task<Void, Never>?
  @State private var hasAIAnalysis: Bool = false

  // Transcript state - computed from TranscriptManager (reactive) + filesystem check
  @State private var hasCaptionsOnDisk: Bool = false

  private var activeTranscriptJob: TranscriptJob? {
    TranscriptManager.shared.activeJobs[jobId]
  }

  private var hasCaptions: Bool {
    if case .completed = activeTranscriptJob?.status { return true }
    return hasCaptionsOnDisk
  }

  private var isTranscribing: Bool {
    guard let job = activeTranscriptJob else { return false }
    switch job.status {
    case .queued, .downloadingModel, .transcribing: return true
    case .completed, .failed: return false
    }
  }

  private var transcriptProgress: Double? {
    guard let job = activeTranscriptJob else { return nil }
    switch job.status {
    case .queued: return 0.0
    case .downloadingModel(let p), .transcribing(let p): return p
    default: return nil
    }
  }

  private var isDownloadingModel: Bool {
    if case .downloadingModel = activeTranscriptJob?.status { return true }
    return false
  }

  // Status checker using centralized utility
  private var statusChecker: EpisodeStatusChecker {
    EpisodeStatusChecker(episode: episode, podcastTitle: podcastTitle)
  }

  private var downloadState: DownloadState { statusChecker.downloadState }
  private var isDownloaded: Bool { statusChecker.isDownloaded }
  private var playbackURL: String { statusChecker.playbackURL }
  private var jobId: String { statusChecker.episodeKey }

  private var isStarred: Bool { episodeModel?.isStarred ?? false }
  private var isCompleted: Bool { episodeModel?.isCompleted ?? false }
  private var playbackProgress: Double { episodeModel?.progress ?? 0 }

  private var isPlayingThisEpisode: Bool {
    guard let currentEpisode = audioManager.currentEpisode else {
      return false
    }
    return currentEpisode.title == episode.title
      && currentEpisode.podcastTitle == podcastTitle
  }

  private var episodeImageURL: String {
    episode.imageURL ?? fallbackImageURL ?? ""
  }

  // Cache the plain description to avoid regex on every render
  private var plainDescription: String? {
    guard let desc = episode.podcastEpisodeDescription else { return nil }
    let stripped = desc.replacingOccurrences(
      of: "<[^>]+>",
      with: "",
      options: .regularExpression
    )
    .replacingOccurrences(of: "&nbsp;", with: " ")
    .replacingOccurrences(of: "&amp;", with: "&")
    .replacingOccurrences(of: "&lt;", with: "<")
    .replacingOccurrences(of: "&gt;", with: ">")
    .replacingOccurrences(of: "&#39;", with: "'")
    .replacingOccurrences(of: "&quot;", with: "\"")
    .trimmingCharacters(in: .whitespacesAndNewlines)
    return stripped.isEmpty ? nil : stripped
  }

  private func checkAIAnalysis() {
    hasAIAnalysis = statusChecker.hasAIAnalysis(in: modelContext)
  }

  var body: some View {
    NavigationLink(
      destination: EpisodeDetailView(
        episode: episode,
        podcastTitle: podcastTitle,
        fallbackImageURL: fallbackImageURL,
        podcastLanguage: podcastLanguage
      )
    ) {
      HStack(alignment: .center, spacing: 12) {
        if showArtwork {
          episodeThumbnail
        }
        episodeInfo
      }
      .padding(.vertical, 8)
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      trailingSwipeActions
    }
    .swipeActions(edge: .leading, allowsFullSwipe: true) {
      leadingSwipeActions
    }
    .contextMenu {
      contextMenuContent
    }
    .onAppear {
      checkAIAnalysis()
      hasCaptionsOnDisk = statusChecker.hasTranscript
    }
    .onChange(of: activeTranscriptJob?.status) { _, newStatus in
      // Refresh filesystem check when job completes (file was just written)
      if case .completed = newStatus {
        hasCaptionsOnDisk = true
      }
    }
  }

  @ViewBuilder
  private var episodeThumbnail: some View {
    ZStack(alignment: .bottomTrailing) {
      // Using CachedAsyncImage for better performance
      CachedArtworkImage(urlString: episodeImageURL, size: 90, cornerRadius: 8)

      // Playing indicator overlay
      if isPlayingThisEpisode {
        Image(
          systemName: audioManager.isPlaying
            ? "waveform" : "pause.fill"
        )
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(.white)
        .padding(4)
        .glassEffect(.regular.tint(.blue), in: .rect(cornerRadius: 4))
        .padding(4)
      }
    }
  }

  /// Format episode date - relative for today, otherwise abbreviated
  private func formatEpisodeDate(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) {
      let formatter = RelativeDateTimeFormatter()
      formatter.unitsStyle = .abbreviated
      return formatter.localizedString(for: date, relativeTo: Date())
    } else {
      return date.formatted(date: .abbreviated, time: .omitted)
    }
  }

  @ViewBuilder
  private var episodeInfo: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Date row
      if let date = episode.pubDate {
        Text(formatEpisodeDate(date))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      // Title
      Text(episode.title)
        .font(.subheadline)
        .fontWeight(.semibold)
        .lineLimit(3)
        .foregroundStyle(.primary)

      // Description
      if let description = plainDescription {
        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }

      Spacer(minLength: 4)

      // Bottom status bar
      bottomStatusBar
    }
  }

  @ViewBuilder
  private var bottomStatusBar: some View {
    HStack(spacing: 6) {
      // Play button with progress - uses live audio manager state
      LivePlaybackButton(
        episodeTitle: episode.title,
        podcastTitle: podcastTitle,
        duration: episodeModel?.duration,
        formattedDuration: episode.formattedDuration,
        lastPlaybackPosition: episodeModel?.lastPlaybackPosition ?? 0,
        playbackProgress: playbackProgress,
        isCompleted: isCompleted,
        onPlay: playAction,
        style: .compact,
        isDisabled: episode.audioURL == nil
      )

      // Download progress
      if case .downloading(let progress) = downloadState {
        HStack(spacing: 2) {
          ProgressView().scaleEffect(0.4)
          Text("\(Int(progress * 100))%").font(.system(size: 9))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassEffect(.regular.tint(.orange), in: .capsule)
      } else if case .finishing = downloadState {
        HStack(spacing: 2) {
          ProgressView().scaleEffect(0.4)
          Text("Saving").font(.system(size: 9))
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassEffect(.regular.tint(.blue), in: .capsule)
      }

      // Status indicators
      HStack(spacing: 4) {
        if isStarred {
          Image(systemName: "star.fill")
            .font(.system(size: 10))
            .foregroundStyle(.yellow)
        }

        if isDownloaded {
          Image(systemName: "arrow.down.circle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.green)
        }

        if hasCaptions {
          Image(systemName: "captions.bubble.fill")
            .font(.system(size: 10))
            .foregroundStyle(.purple)
        } else if isTranscribing {
          HStack(spacing: 2) {
            ProgressView().scaleEffect(0.35)
            if isDownloadingModel {
              Text("Model")
                .font(.system(size: 8))
                .foregroundStyle(.purple)
            }
            if let progress = transcriptProgress {
              Text("\(Int(progress * 100))%")
                .font(.system(size: 8))
                .foregroundStyle(.purple)
            }
          }
        }

        if hasAIAnalysis {
          Image(systemName: "sparkles")
            .font(.system(size: 10))
            .foregroundStyle(.orange)
        }

        if isCompleted {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.green)
        }
      }

      Spacer()

      // Ellipsis menu button
      Menu {
        contextMenuContent
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .compositingGroup()
      .buttonStyle(.plain)
    }
  }

  @ViewBuilder
  private var contextMenuContent: some View {
    EpisodeMenuActions(
      isStarred: isStarred,
      isCompleted: isCompleted,
      hasLocalAudio: isDownloaded,
      downloadState: downloadState,
      audioURL: episode.audioURL,
      onToggleStar: onToggleStar,
      onTogglePlayed: onTogglePlayed,
      onDownload: onDownload,
      onCancelDownload: {
        downloadManager.cancelDownload(
          episodeTitle: episode.title,
          podcastTitle: podcastTitle
        )
      },
      onDeleteDownload: onDeleteRequested,
      onShare: {
        shareEpisode()
      },
      onPlayNext: {
        guard let audioURL = episode.audioURL else { return }
        let playbackEpisode = PlaybackEpisode(
          id: statusChecker.episodeKey,
          title: episode.title,
          podcastTitle: podcastTitle,
          audioURL: audioURL,
          imageURL: episode.imageURL ?? fallbackImageURL,
          episodeDescription: episode.podcastEpisodeDescription,
          pubDate: episode.pubDate,
          duration: episode.duration,
          guid: episode.guid
        )
        audioManager.playNext(playbackEpisode)
      }
    )
  }

  @ViewBuilder
  private var trailingSwipeActions: some View {
    Button(action: onToggleStar) {
      Label(
        isStarred ? "Unstar" : "Star",
        systemImage: isStarred ? "star.slash" : "star.fill"
      )
    }
    .tint(.yellow)

    if isDownloaded {
      Button(role: .destructive, action: onDeleteRequested) {
        Label("Delete", systemImage: "trash")
      }
    } else if case .downloading = downloadState {
      Button(action: {
        downloadManager.cancelDownload(
          episodeTitle: episode.title,
          podcastTitle: podcastTitle
        )
      }) {
        Label("Cancel", systemImage: "xmark.circle")
      }
      .tint(.orange)
    } else if case .finishing = downloadState {
      Button(action: {}) {
        Label("Saving", systemImage: "arrow.down.circle.dotted")
      }
      .tint(.gray)
      .disabled(true)
    } else if episode.audioURL != nil {
      Button(action: onDownload) {
        Label("Download", systemImage: "arrow.down.circle")
      }
      .tint(.blue)
    }
  }

  @ViewBuilder
  private var leadingSwipeActions: some View {
    Button(action: onTogglePlayed) {
      Label(
        isCompleted ? "Unplayed" : "Played",
        systemImage: isCompleted
          ? "arrow.counterclockwise" : "checkmark.circle"
      )
    }
    .tint(.green)
  }

  private func playAction() {
    guard episode.audioURL != nil else { return }

    let imageURL = episode.imageURL ?? fallbackImageURL ?? ""

    let playbackEpisode = PlaybackEpisode(
      id: statusChecker.episodeKey,
      title: episode.title,
      podcastTitle: podcastTitle,
      audioURL: playbackURL,
      imageURL: imageURL,
      episodeDescription: episode.podcastEpisodeDescription,
      pubDate: episode.pubDate,
      duration: episode.duration,
      guid: episode.guid
    )

    let startTime = episodeModel?.lastPlaybackPosition ?? 0
    let useDefaultSpeed = startTime == 0

    audioManager.play(
      episode: playbackEpisode,
      audioURL: playbackURL,
      startTime: startTime,
      imageURL: imageURL,
      useDefaultSpeed: useDefaultSpeed
    )
  }

  private func shareEpisode() {
    shareTask?.cancel()
    shareTask = Task {
      do {
        // Use timeout with task group
        let appleUrl = try await withThrowingTaskGroup(of: String?.self) { group in
          group.addTask {
            try await applePodcastService.getAppleEpisodeLink(
              episodeTitle: episode.title,
              episodeGuid: episode.guid
            )
          }
          group.addTask {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            throw CancellationError()
          }
          let result = try await group.next()!
          group.cancelAll()
          return result
        }
        if !Task.isCancelled {
          shareWithURL(appleUrl ?? episode.audioURL)
        }
      } catch {
        if !Task.isCancelled {
          shareWithURL(episode.audioURL)
        }
      }
    }
  }

  private func shareWithURL(_ urlString: String?) {
    guard let urlString = urlString, let url = URL(string: urlString) else {
      return
    }
    PlatformShareSheet.share(url: url)
  }
}
