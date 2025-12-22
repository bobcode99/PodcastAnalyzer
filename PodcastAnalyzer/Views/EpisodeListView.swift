//
//  EpisodeListView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/23.
//

import SwiftData
import SwiftUI

// MARK: - Episode Filter Enum

enum EpisodeFilter: String, CaseIterable {
  case all = "All"
  case unplayed = "Unplayed"
  case played = "Played"
  case downloaded = "Downloaded"

  var icon: String {
    switch self {
    case .all: return "list.bullet"
    case .unplayed: return "circle"
    case .played: return "checkmark.circle"
    case .downloaded: return "arrow.down.circle.fill"
    }
  }
}

// MARK: - Episode List View

struct EpisodeListView: View {
  let podcastModel: PodcastInfoModel
  @Environment(\.modelContext) private var modelContext
  @ObservedObject private var downloadManager = DownloadManager.shared
  @State private var viewModel: EpisodeListViewModel?
  @State private var episodeToDelete: PodcastEpisodeInfo?
  @State private var showDeleteConfirmation = false

  var body: some View {
    Group {
      if let vm = viewModel {
        episodeListContent(viewModel: vm)
      } else {
        ProgressView("Loading...")
      }
    }
    .onAppear {
      if viewModel == nil {
        let vm = EpisodeListViewModel(podcastModel: podcastModel)
        vm.setModelContext(modelContext)
        viewModel = vm
      }
      viewModel?.startRefreshTimer()
    }
    .onDisappear {
      viewModel?.stopRefreshTimer()
    }
  }

  @ViewBuilder
  private func episodeListContent(viewModel: EpisodeListViewModel) -> some View {
    ScrollView {
      LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
        // MARK: - Header Section
        headerSection(viewModel: viewModel)

        // MARK: - Filter and Sort Bar
        filterSortBar(viewModel: viewModel)

        // MARK: - Episodes List
        Section {
          ForEach(viewModel.filteredEpisodes) { episode in
            EpisodeRowView(
              episode: episode,
              podcastTitle: viewModel.podcastInfo.title,
              fallbackImageURL: viewModel.podcastInfo.imageURL,
              podcastLanguage: viewModel.podcastInfo.language,
              downloadManager: downloadManager,
              episodeModel: viewModel.episodeModels[viewModel.makeEpisodeKey(episode)],
              onToggleStar: { viewModel.toggleStar(for: episode) },
              onDownload: { viewModel.downloadEpisode(episode) },
              onDeleteRequested: {
                episodeToDelete = episode
                showDeleteConfirmation = true
              },
              onTogglePlayed: { viewModel.togglePlayed(for: episode) }
            )
            .padding(.horizontal, 16)

            Divider()
              .padding(.leading, 108)
          }
        } header: {
          Text("Episodes (\(viewModel.filteredEpisodeCount))")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(uiColor: .systemBackground))
        }
      }
    }
    .navigationTitle(viewModel.podcastInfo.title)
    .iosNavigationBarTitleDisplayModeInline()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Toggle(isOn: $downloadManager.autoTranscriptEnabled) {
            Label("Auto-Generate Transcripts", systemImage: "text.bubble")
          }

          Divider()

          Button(action: {
            Task { await viewModel.refreshPodcast() }
          }) {
            Label("Refresh Episodes", systemImage: "arrow.clockwise")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
    .refreshable {
      await viewModel.refreshPodcast()
    }
    .searchable(text: Binding(
      get: { viewModel.searchText },
      set: { viewModel.searchText = $0 }
    ), prompt: "Search episodes")
    .confirmationDialog(
      "Delete Download",
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let episode = episodeToDelete {
          viewModel.deleteDownload(episode)
        }
        episodeToDelete = nil
      }
      Button("Cancel", role: .cancel) {
        episodeToDelete = nil
      }
    } message: {
      Text(
        "Are you sure you want to delete this downloaded episode? You can download it again later."
      )
    }
  }

  @ViewBuilder
  private func headerSection(viewModel: EpisodeListViewModel) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        if let url = URL(string: viewModel.podcastInfo.imageURL) {
          AsyncImage(url: url) { phase in
            if let image = phase.image {
              image.resizable().scaledToFit()
            } else if phase.error != nil {
              Color.gray
            } else {
              ProgressView()
            }
          }
          .frame(width: 100, height: 100)
          .cornerRadius(8)
        } else {
          Color.gray.frame(width: 100, height: 100).cornerRadius(8)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text(viewModel.podcastInfo.title)
            .font(.headline)

          // Language badge
          HStack(spacing: 4) {
            Image(systemName: "globe")
              .font(.system(size: 10))
            Text(languageDisplayName(for: viewModel.podcastInfo.language))
              .font(.caption2)
          }
          .foregroundColor(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.gray.opacity(0.15))
          .cornerRadius(4)

          if let summary = viewModel.podcastInfo.podcastInfoDescription {
            VStack(alignment: .leading, spacing: 2) {
              Text(summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(viewModel.isDescriptionExpanded ? nil : 3)

              Button(action: {
                withAnimation {
                  viewModel.isDescriptionExpanded.toggle()
                }
              }) {
                Text(viewModel.isDescriptionExpanded ? "Show less" : "More")
                  .font(.caption)
                  .fontWeight(.medium)
                  .foregroundColor(.blue)
              }
            }
          }
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 10)
  }

  /// Convert language code to display name
  private func languageDisplayName(for code: String) -> String {
    let locale = Locale(identifier: code)
    if let name = locale.localizedString(forLanguageCode: code) {
      return name.capitalized
    }
    return code.uppercased()
  }

  @ViewBuilder
  private func filterSortBar(viewModel: EpisodeListViewModel) -> some View {
    VStack(spacing: 12) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(EpisodeFilter.allCases, id: \.self) { filter in
            FilterChip(
              title: filter.rawValue,
              icon: filter.icon,
              isSelected: viewModel.selectedFilter == filter
            ) {
              withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedFilter = filter
              }
            }
          }

          Divider()
            .frame(height: 24)

          Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
              viewModel.sortOldestFirst.toggle()
            }
          }) {
            HStack(spacing: 4) {
              Image(systemName: viewModel.sortOldestFirst ? "arrow.up" : "arrow.down")
                .font(.system(size: 12))
              Text(viewModel.sortOldestFirst ? "Oldest" : "Newest")
                .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.15))
            .foregroundColor(.primary)
            .cornerRadius(16)
          }
        }
        .padding(.horizontal, 4)
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
  }
}

// MARK: - Episode Row View

struct EpisodeRowView: View {
  let episode: PodcastEpisodeInfo
  let podcastTitle: String
  let fallbackImageURL: String?
  let podcastLanguage: String
  @ObservedObject var downloadManager: DownloadManager
  @ObservedObject var transcriptManager = TranscriptManager.shared
  let episodeModel: EpisodeDownloadModel?
  let onToggleStar: () -> Void
  let onDownload: () -> Void
  let onDeleteRequested: () -> Void
  let onTogglePlayed: () -> Void

  private var audioManager: EnhancedAudioManager { EnhancedAudioManager.shared }

  // Use Unit Separator (U+001F) as delimiter
  private static let episodeKeyDelimiter = "\u{1F}"

  private var downloadState: DownloadState {
    downloadManager.getDownloadState(episodeTitle: episode.title, podcastTitle: podcastTitle)
  }

  private var isDownloaded: Bool {
    if case .downloaded = downloadState { return true }
    return false
  }

  private var hasCaptions: Bool {
    let fm = FileManager.default
    let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let captionsDir = docsDir.appendingPathComponent("Captions", isDirectory: true)

    let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
    let baseFileName = "\(podcastTitle)_\(episode.title)"
      .components(separatedBy: invalidCharacters)
      .joined(separator: "_")
      .trimmingCharacters(in: .whitespaces)

    let srtPath = captionsDir.appendingPathComponent("\(baseFileName).srt")
    return fm.fileExists(atPath: srtPath.path)
  }

  private var transcriptJobStatus: TranscriptJobStatus? {
    let jobId = "\(podcastTitle)\(Self.episodeKeyDelimiter)\(episode.title)"
    return transcriptManager.activeJobs[jobId]?.status
  }

  private var isTranscribing: Bool {
    guard let status = transcriptJobStatus else { return false }
    switch status {
    case .queued, .downloadingModel, .transcribing:
      return true
    default:
      return false
    }
  }

  private var transcriptProgress: Double? {
    guard let status = transcriptJobStatus else { return nil }
    switch status {
    case .queued:
      return 0.0
    case .downloadingModel(let progress):
      return progress * 0.1
    case .transcribing(let progress):
      return 0.1 + (progress * 0.9)
    default:
      return nil
    }
  }

  private var isStarred: Bool { episodeModel?.isStarred ?? false }
  private var isCompleted: Bool { episodeModel?.isCompleted ?? false }
  private var playbackProgress: Double { episodeModel?.progress ?? 0 }

  private var isPlayingThisEpisode: Bool {
    guard let currentEpisode = audioManager.currentEpisode else { return false }
    return currentEpisode.title == episode.title && currentEpisode.podcastTitle == podcastTitle
  }

  private var playbackURL: String {
    if case .downloaded(let path) = downloadState {
      return "file://" + path
    }
    return episode.audioURL ?? ""
  }

  private var durationText: String? {
    if let model = episodeModel, model.duration > 0 && model.progress > 0 && model.progress < 1 {
      let remaining = model.duration - model.lastPlaybackPosition
      return formatDuration(Int(remaining))
    }
    return episode.formattedDuration
  }

  private var episodeImageURL: String {
    episode.imageURL ?? fallbackImageURL ?? ""
  }

  private var plainDescription: String? {
    guard let desc = episode.podcastEpisodeDescription else { return nil }
    let stripped = desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return stripped.isEmpty ? nil : stripped
  }

  private func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
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
      HStack(alignment: .top, spacing: 12) {
        episodeThumbnail
        episodeInfo
      }
      .padding(.vertical, 6)
    }
    .contextMenu { contextMenuContent }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingSwipeActions }
    .swipeActions(edge: .leading, allowsFullSwipe: true) { leadingSwipeActions }
  }

  @ViewBuilder
  private var episodeThumbnail: some View {
    if let url = URL(string: episodeImageURL) {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image.resizable().scaledToFill()
        case .failure:
          Color.gray
        case .empty:
          Color.gray.opacity(0.3)
        @unknown default:
          Color.gray
        }
      }
      .frame(width: 80, height: 80)
      .cornerRadius(8)
      .clipped()
    } else {
      Color.gray
        .frame(width: 80, height: 80)
        .cornerRadius(8)
    }
  }

  @ViewBuilder
  private var episodeInfo: some View {
    VStack(alignment: .leading, spacing: 4) {
      // Date and indicators row
      HStack(spacing: 4) {
        if let date = episode.pubDate {
          Text(date.formatted(date: .abbreviated, time: .omitted))
            .font(.caption2)
            .foregroundColor(.secondary)
        }

        if isStarred {
          Image(systemName: "star.fill")
            .font(.system(size: 8))
            .foregroundColor(.yellow)
        }

        if isDownloaded {
          Image(systemName: "arrow.down.circle.fill")
            .font(.system(size: 8))
            .foregroundColor(.green)
        }

        if hasCaptions {
          Image(systemName: "captions.bubble.fill")
            .font(.system(size: 8))
            .foregroundColor(.purple)
        } else if isTranscribing {
          HStack(spacing: 2) {
            ProgressView().scaleEffect(0.4)
            if let progress = transcriptProgress {
              Text("\(Int(progress * 100))%")
                .font(.system(size: 7))
                .foregroundColor(.purple)
            }
          }
        }
      }

      Text(episode.title)
        .font(.subheadline)
        .fontWeight(.medium)
        .lineLimit(2)
        .foregroundColor(.primary)

      if let description = plainDescription {
        Text(description)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(2)
      }

      playbackControls
    }
  }

  @ViewBuilder
  private var playbackControls: some View {
    HStack(spacing: 8) {
      Button(action: playAction) {
        HStack(spacing: 4) {
          if isPlayingThisEpisode && audioManager.isPlaying {
            Image(systemName: "pause.fill").font(.system(size: 10))
          } else if isCompleted {
            Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .bold))
          } else {
            Image(systemName: "play.fill").font(.system(size: 10))
          }

          if playbackProgress > 0 && playbackProgress < 1 {
            GeometryReader { geo in
              ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.3)).frame(height: 3)
                Capsule().fill(Color.blue).frame(width: geo.size.width * playbackProgress, height: 3)
              }
            }
            .frame(width: 30, height: 3)
          }

          if let duration = durationText {
            Text(duration).font(.caption2).fontWeight(.medium)
          }
        }
        .foregroundColor(.blue)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.15))
        .clipShape(Capsule())
      }
      .buttonStyle(.borderless)
      .disabled(episode.audioURL == nil)

      if case .downloading(let progress) = downloadState {
        HStack(spacing: 4) {
          ProgressView().scaleEffect(0.5)
          Text("\(Int(progress * 100))%").font(.caption2)
        }
        .foregroundColor(.orange)
      } else if case .finishing = downloadState {
        HStack(spacing: 4) {
          ProgressView().scaleEffect(0.5)
          Text("Saving...").font(.caption2)
        }
        .foregroundColor(.blue)
      }

      Spacer()
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
        downloadManager.cancelDownload(episodeTitle: episode.title, podcastTitle: podcastTitle)
      },
      onDeleteDownload: onDeleteRequested,
      onShare: {
        guard let audioURL = episode.audioURL, let url = URL(string: audioURL) else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let rootVC = windowScene.windows.first?.rootViewController
        {
          rootVC.present(activityVC, animated: true)
        }
      },
      onPlayNext: {
        guard let audioURL = episode.audioURL else { return }
        let playbackEpisode = PlaybackEpisode(
          id: "\(podcastTitle)|\(episode.title)",
          title: episode.title,
          podcastTitle: podcastTitle,
          audioURL: audioURL,
          imageURL: episode.imageURL ?? fallbackImageURL
        )
        audioManager.playNext(playbackEpisode)
      }
    )
  }

  @ViewBuilder
  private var trailingSwipeActions: some View {
    Button(action: onToggleStar) {
      Label(isStarred ? "Unstar" : "Star", systemImage: isStarred ? "star.slash" : "star.fill")
    }
    .tint(.yellow)

    if isDownloaded {
      Button(role: .destructive, action: onDeleteRequested) {
        Label("Delete", systemImage: "trash")
      }
    } else if case .downloading = downloadState {
      Button(action: {
        downloadManager.cancelDownload(episodeTitle: episode.title, podcastTitle: podcastTitle)
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
        systemImage: isCompleted ? "arrow.counterclockwise" : "checkmark.circle"
      )
    }
    .tint(.green)
  }

  private func playAction() {
    guard episode.audioURL != nil else { return }

    let imageURL = episode.imageURL ?? fallbackImageURL ?? ""

    let playbackEpisode = PlaybackEpisode(
      id: "\(podcastTitle)|\(episode.title)",
      title: episode.title,
      podcastTitle: podcastTitle,
      audioURL: playbackURL,
      imageURL: imageURL
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
}

// MARK: - Filter Chip Component

struct FilterChip: View {
  let title: String
  let icon: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Image(systemName: icon)
          .font(.system(size: 12))
        Text(title)
          .font(.caption)
          .fontWeight(isSelected ? .semibold : .regular)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(isSelected ? Color.blue : Color.gray.opacity(0.15))
      .foregroundColor(isSelected ? .white : .primary)
      .cornerRadius(16)
    }
  }
}
