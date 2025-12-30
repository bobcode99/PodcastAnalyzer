//
//  EpisodeListView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/23.
//

import Combine
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
  private func episodeListContent(viewModel: EpisodeListViewModel)
    -> some View
  {
    List {
      // MARK: - Header Section
      Section {
        headerSection(viewModel: viewModel)
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)

        // MARK: - Filter and Sort Bar
        filterSortBar(viewModel: viewModel)
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
      }

      // MARK: - Episodes List
      Section {
        ForEach(viewModel.filteredEpisodes) { episode in
          EpisodeRowView(
            episode: episode,
            podcastTitle: viewModel.podcastInfo.title,
            fallbackImageURL: viewModel.podcastInfo.imageURL,
            podcastLanguage: viewModel.podcastInfo.language,
            downloadManager: downloadManager,
            episodeModel: viewModel.episodeModels[
              viewModel.makeEpisodeKey(episode)
            ],
            onToggleStar: {
              viewModel.toggleStar(for: episode)
            },
            onDownload: { viewModel.downloadEpisode(episode) },
            onDeleteRequested: {
              episodeToDelete = episode
              showDeleteConfirmation = true
            },
            onTogglePlayed: {
              viewModel.togglePlayed(for: episode)
            }
          )
          .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
      } header: {
        Text("Episodes (\(viewModel.filteredEpisodeCount))")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.secondary)
      }
    }
    .listStyle(.plain)
    .navigationTitle(viewModel.podcastInfo.title)
    .iosNavigationBarTitleDisplayModeInline()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Toggle(isOn: $downloadManager.autoTranscriptEnabled) {
            Label(
              "Auto-Generate Transcripts",
              systemImage: "text.bubble"
            )
          }

          Divider()

          Button(action: {
            Task { await viewModel.refreshPodcast() }
          }) {
            Label(
              "Refresh Episodes",
              systemImage: "arrow.clockwise"
            )
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
    .refreshable {
      await viewModel.refreshPodcast()
    }
    .searchable(
      text: Binding(
        get: { viewModel.searchText },
        set: { viewModel.searchText = $0 }
      ),
      prompt: "Search episodes"
    )
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
            Text(
              languageDisplayName(
                for: viewModel.podcastInfo.language
              )
            )
            .font(.caption2)
          }
          .foregroundColor(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.gray.opacity(0.15))
          .cornerRadius(4)

          if viewModel.podcastInfo.podcastInfoDescription != nil {
            VStack(alignment: .leading, spacing: 2) {
              viewModel.descriptionView
                .lineLimit(
                  viewModel.isDescriptionExpanded ? nil : 3
                )

              Button(action: {
                withAnimation {
                  viewModel.isDescriptionExpanded.toggle()
                }
              }) {
                Text(
                  viewModel.isDescriptionExpanded
                    ? "Show less" : "More"
                )
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
              Image(
                systemName: viewModel.sortOldestFirst
                  ? "arrow.up" : "arrow.down"
              )
              .font(.system(size: 12))
              Text(
                viewModel.sortOldestFirst ? "Oldest" : "Newest"
              )
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

  @Environment(\.modelContext) private var modelContext
  private var audioManager: EnhancedAudioManager {
    EnhancedAudioManager.shared
  }
  private let applePodcastService = ApplePodcastService()
  @State private var shareCancellable: AnyCancellable?
  @State private var hasAIAnalysis: Bool = false

  // Use Unit Separator (U+001F) as delimiter
  private static let episodeKeyDelimiter = "\u{1F}"

  private var downloadState: DownloadState {
    downloadManager.getDownloadState(
      episodeTitle: episode.title,
      podcastTitle: podcastTitle
    )
  }

  private var isDownloaded: Bool {
    if case .downloaded = downloadState { return true }
    return false
  }

  private var hasCaptions: Bool {
    // First check if there's an active job that's completed
    if let status = transcriptJobStatus, case .completed = status {
      return true
    }

    let fm = FileManager.default
    let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let captionsDir = docsDir.appendingPathComponent(
      "Captions",
      isDirectory: true
    )

    let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
    let baseFileName = "\(podcastTitle)_\(episode.title)"
      .components(separatedBy: invalidCharacters)
      .joined(separator: "_")
      .trimmingCharacters(in: .whitespaces)

    let srtPath = captionsDir.appendingPathComponent("\(baseFileName).srt")
    return fm.fileExists(atPath: srtPath.path)
  }

  private var jobId: String {
    "\(podcastTitle)\(Self.episodeKeyDelimiter)\(episode.title)"
  }

  private var transcriptJobStatus: TranscriptJobStatus? {
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
      return progress  // Show actual model download progress (matches EpisodeDetailView)
    case .transcribing(let progress):
      return progress  // Show actual transcription progress (matches EpisodeDetailView)
    default:
      return nil
    }
  }

  private var isDownloadingModel: Bool {
    guard let status = transcriptJobStatus else { return false }
    if case .downloadingModel = status { return true }
    return false
  }

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

  private var playbackURL: String {
    if case .downloaded(let path) = downloadState {
      return "file://" + path
    }
    return episode.audioURL ?? ""
  }

  private var durationText: String? {
    if let model = episodeModel,
      model.duration > 0 && model.progress > 0 && model.progress < 1
    {
      let remaining = model.duration - model.lastPlaybackPosition
      return formatDuration(Int(remaining)) + " left"
    }
    return episode.formattedDuration
  }

  private var episodeImageURL: String {
    episode.imageURL ?? fallbackImageURL ?? ""
  }

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

  private func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
  }

  private func checkAIAnalysis() {
    guard let audioURL = episode.audioURL else { return }
    let descriptor = FetchDescriptor<EpisodeAIAnalysis>(
      predicate: #Predicate { $0.episodeAudioURL == audioURL }
    )
    if let model = try? modelContext.fetch(descriptor).first {
      // Check if ANY AI analysis is available
      hasAIAnalysis =
        model.hasFullAnalysis || model.hasSummary || model.hasEntities
        || model.hasHighlights
        || (model.qaHistoryJSON != nil && !model.qaHistoryJSON!.isEmpty)
    }
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
        episodeThumbnail
        episodeInfo
      }
      .padding(.vertical, 8)
    }
    .contextMenu { contextMenuContent }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      trailingSwipeActions
    }
    .swipeActions(edge: .leading, allowsFullSwipe: true) {
      leadingSwipeActions
    }
    .onAppear { checkAIAnalysis() }
  }

  @ViewBuilder
  private var episodeThumbnail: some View {
    ZStack(alignment: .bottomTrailing) {
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
        .frame(width: 90, height: 90)
        .cornerRadius(8)
        .clipped()
      } else {
        Color.gray
          .frame(width: 90, height: 90)
          .cornerRadius(8)
      }

      // Playing indicator overlay
      if isPlayingThisEpisode {
        Image(
          systemName: audioManager.isPlaying
            ? "waveform" : "pause.fill"
        )
        .font(.system(size: 12, weight: .bold))
        .foregroundColor(.white)
        .padding(4)
        .background(Color.blue)
        .cornerRadius(4)
        .padding(4)
      }
    }
  }

  @ViewBuilder
  private var episodeInfo: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Date row
      if let date = episode.pubDate {
        Text(date.formatted(date: .abbreviated, time: .omitted))
          .font(.caption)
          .foregroundColor(.secondary)
      }

      // Title - more lines
      Text(episode.title)
        .font(.subheadline)
        .fontWeight(.semibold)
        .lineLimit(3)
        .foregroundColor(.primary)

      // Description - more lines
      if let description = plainDescription {
        Text(description)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(3)
      }

      Spacer(minLength: 4)

      // Bottom status bar with all indicators
      bottomStatusBar
    }
  }

  @ViewBuilder
  private var bottomStatusBar: some View {
    HStack(spacing: 6) {
      // Play button with progress
      Button(action: playAction) {
        HStack(spacing: 4) {
          if isPlayingThisEpisode && audioManager.isPlaying {
            Image(systemName: "pause.fill").font(.system(size: 9))
          } else if isCompleted {
            Image(systemName: "arrow.counterclockwise").font(
              .system(size: 9, weight: .bold)
            )
          } else {
            Image(systemName: "play.fill").font(.system(size: 9))
          }

          // Progress bar
          if playbackProgress > 0 && playbackProgress < 1 {
            GeometryReader { geo in
              ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.4)).frame(
                  height: 2
                )
                Capsule().fill(Color.white).frame(
                  width: geo.size.width * playbackProgress,
                  height: 2
                )
              }
            }
            .frame(width: 24, height: 2)
          }

          if let duration = durationText {
            Text(duration).font(.system(size: 10)).fontWeight(
              .medium
            )
          }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.blue)
        .clipShape(Capsule())
      }
      .buttonStyle(.borderless)
      .disabled(episode.audioURL == nil)

      // Download progress
      if case .downloading(let progress) = downloadState {
        HStack(spacing: 2) {
          ProgressView().scaleEffect(0.4)
          Text("\(Int(progress * 100))%").font(.system(size: 9))
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
      } else if case .finishing = downloadState {
        HStack(spacing: 2) {
          ProgressView().scaleEffect(0.4)
          Text("Saving").font(.system(size: 9))
        }
        .foregroundColor(.blue)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.15))
        .clipShape(Capsule())
      }

      // Status indicators
      HStack(spacing: 4) {
        if isStarred {
          Image(systemName: "star.fill")
            .font(.system(size: 10))
            .foregroundColor(.yellow)
        }

        if isDownloaded {
          Image(systemName: "arrow.down.circle.fill")
            .font(.system(size: 10))
            .foregroundColor(.green)
        }

        if hasCaptions {
          Image(systemName: "captions.bubble.fill")
            .font(.system(size: 10))
            .foregroundColor(.purple)
        } else if isTranscribing {
          HStack(spacing: 2) {
            ProgressView().scaleEffect(0.35)
            if isDownloadingModel {
              // Show "Model" label during model download phase (matches EpisodeDetailView)
              Text("Model")
                .font(.system(size: 8))
                .foregroundColor(.purple)
            }
            if let progress = transcriptProgress {
              Text("\(Int(progress * 100))%")
                .font(.system(size: 8))
                .foregroundColor(.purple)
            }
          }
        }

        if hasAIAnalysis {
          Image(systemName: "sparkles")
            .font(.system(size: 10))
            .foregroundColor(.orange)
        }

        if isCompleted {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 10))
            .foregroundColor(.green)
        }
      }

      Spacer()

      // Ellipsis menu button
      Menu {
        contextMenuContent
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.secondary)
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
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
          id:
            "\(podcastTitle)\(Self.episodeKeyDelimiter)\(episode.title)",
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
      id: "\(podcastTitle)\(Self.episodeKeyDelimiter)\(episode.title)",
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
    // Try to find Apple Podcast URL first
    shareCancellable = applePodcastService.getAppleEpisodeLink(
      episodeTitle: episode.title,
      episodeGuid: episode.guid
    )
    .timeout(.seconds(5), scheduler: DispatchQueue.main)
    .sink(
      receiveCompletion: { completion in
        if case .failure = completion {
          // On error, fall back to audio URL
          shareWithURL(episode.audioURL)
        }
      },
      receiveValue: { appleUrl in
        // Use Apple URL if found, otherwise fall back to audio URL
        shareWithURL(appleUrl ?? episode.audioURL)
      }
    )
  }

  private func shareWithURL(_ urlString: String?) {
    guard let urlString = urlString, let url = URL(string: urlString) else {
      return
    }

    let activityVC = UIActivityViewController(
      activityItems: [url],
      applicationActivities: nil
    )
    if let windowScene = UIApplication.shared.connectedScenes.first
      as? UIWindowScene,
      let rootVC = windowScene.windows.first?.rootViewController
    {
      rootVC.present(activityVC, animated: true)
    }
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
