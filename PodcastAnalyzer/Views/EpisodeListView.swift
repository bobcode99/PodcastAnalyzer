//
//  EpoisodeView.swift
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

struct EpisodeListView: View {
  let podcastModel: PodcastInfoModel
  @Environment(\.modelContext) private var modelContext
  @ObservedObject private var downloadManager = DownloadManager.shared
  private var audioManager: EnhancedAudioManager { EnhancedAudioManager.shared }
  @State private var episodeModels: [String: EpisodeDownloadModel] = [:]
  @State private var episodeToDelete: PodcastEpisodeInfo?
  @State private var showDeleteConfirmation = false
  @State private var isRefreshing = false
  @State private var isDescriptionExpanded = false
  @State private var refreshTimer: Timer?

  // Filter and sort state
  @State private var selectedFilter: EpisodeFilter = .all
  @State private var sortOldestFirst: Bool = false

  // Search state
  @State private var searchText: String = ""

  private let rssService = PodcastRssService()

  // MARK: - Filtered and Sorted Episodes

  private var filteredEpisodes: [PodcastEpisodeInfo] {
    var episodes = podcastModel.podcastInfo.episodes

    // Apply search filter first
    if !searchText.isEmpty {
      let query = searchText.lowercased()
      episodes = episodes.filter { episode in
        episode.title.lowercased().contains(query)
          || (episode.podcastEpisodeDescription?.lowercased().contains(query) ?? false)
      }
    }

    // Apply category filter
    switch selectedFilter {
    case .all:
      break  // No filtering
    case .unplayed:
      episodes = episodes.filter { episode in
        let key = makeEpisodeKey(episode)
        guard let model = episodeModels[key] else { return true }  // Not played = unplayed
        return !model.isCompleted && model.progress < 0.1
      }
    case .played:
      episodes = episodes.filter { episode in
        let key = makeEpisodeKey(episode)
        guard let model = episodeModels[key] else { return false }
        // Only show fully completed episodes
        return model.isCompleted
      }
    case .downloaded:
      episodes = episodes.filter { episode in
        let state = downloadManager.getDownloadState(
          episodeTitle: episode.title,
          podcastTitle: podcastModel.podcastInfo.title
        )
        if case .downloaded = state { return true }
        return false
      }
    }

    // Apply sort
    if sortOldestFirst {
      episodes = episodes.sorted { (e1, e2) in
        guard let d1 = e1.pubDate, let d2 = e2.pubDate else { return false }
        return d1 < d2
      }
    }
    // Default is newest first (as returned by RSS)

    return episodes
  }

  private var filteredEpisodeCount: Int {
    filteredEpisodes.count
  }

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
        // MARK: - Header Section
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .top) {
            // Podcast Image
            if let url = URL(string: podcastModel.podcastInfo.imageURL) {
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

            // Title and Summary with expandable description
            VStack(alignment: .leading, spacing: 4) {
              Text(podcastModel.podcastInfo.title)
                .font(.headline)

              if let summary = podcastModel.podcastInfo.podcastInfoDescription {
                VStack(alignment: .leading, spacing: 2) {
                  Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(isDescriptionExpanded ? nil : 3)

                  Button(action: {
                    withAnimation {
                      isDescriptionExpanded.toggle()
                    }
                  }) {
                    Text(isDescriptionExpanded ? "Show less" : "More")
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

        // MARK: - Filter and Sort Bar
        VStack(spacing: 12) {
          // Filter chips
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(EpisodeFilter.allCases, id: \.self) { filter in
                FilterChip(
                  title: filter.rawValue,
                  icon: filter.icon,
                  isSelected: selectedFilter == filter
                ) {
                  withAnimation(.easeInOut(duration: 0.2)) {
                    selectedFilter = filter
                  }
                }
              }

              Divider()
                .frame(height: 24)

              // Sort toggle
              Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                  sortOldestFirst.toggle()
                }
              }) {
                HStack(spacing: 4) {
                  Image(systemName: sortOldestFirst ? "arrow.up" : "arrow.down")
                    .font(.system(size: 12))
                  Text(sortOldestFirst ? "Oldest" : "Newest")
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

        // MARK: - Episodes List
        Section {
          ForEach(filteredEpisodes) { episode in
            EpisodeRowView(
              episode: episode,
              podcastTitle: podcastModel.podcastInfo.title,
              fallbackImageURL: podcastModel.podcastInfo.imageURL,
              podcastLanguage: podcastModel.podcastInfo.language,
              downloadManager: downloadManager,
              episodeModel: episodeModels[makeEpisodeKey(episode)],
              onToggleStar: { toggleStar(for: episode) },
              onDownload: { downloadEpisode(episode) },
              onDeleteRequested: {
                episodeToDelete = episode
                showDeleteConfirmation = true
              },
              onTogglePlayed: { togglePlayed(for: episode) }
            )
            .padding(.horizontal, 16)

            Divider()
              .padding(.leading, 108)
          }
        } header: {
          Text("Episodes (\(filteredEpisodeCount))")
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
    .navigationTitle(podcastModel.podcastInfo.title)
    .iosNavigationBarTitleDisplayModeInline()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          // Auto-transcript toggle
          Toggle(isOn: $downloadManager.autoTranscriptEnabled) {
            Label("Auto-Generate Transcripts", systemImage: "text.bubble")
          }

          Divider()

          // Refresh podcast
          Button(action: {
            Task { await refreshPodcast() }
          }) {
            Label("Refresh Episodes", systemImage: "arrow.clockwise")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
    .onAppear {
      loadEpisodeModels()
      // Start periodic refresh for playback state updates
      startRefreshTimer()
    }
    .onDisappear {
      stopRefreshTimer()
    }
    .refreshable {
      await refreshPodcast()
    }
    .searchable(text: $searchText, prompt: "Search episodes")
    .confirmationDialog(
      "Delete Download",
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let episode = episodeToDelete {
          deleteDownload(episode)
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

  // MARK: - Helper Methods

  private func makeEpisodeKey(_ episode: PodcastEpisodeInfo) -> String {
    // Use Unit Separator (U+001F) as delimiter - same as DownloadManager
    let delimiter = "\u{1F}"
    return "\(podcastModel.podcastInfo.title)\(delimiter)\(episode.title)"
  }

  private func startRefreshTimer() {
    // Refresh every 2 seconds to update playback progress
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
      loadEpisodeModels()
    }
  }

  private func stopRefreshTimer() {
    refreshTimer?.invalidate()
    refreshTimer = nil
  }

  private func loadEpisodeModels() {
    let podcastTitle = podcastModel.podcastInfo.title
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.podcastTitle == podcastTitle }
    )

    do {
      let results = try modelContext.fetch(descriptor)
      var models: [String: EpisodeDownloadModel] = [:]
      for model in results {
        models[model.id] = model
      }
      episodeModels = models
    } catch {
      print("Failed to load episode models: \(error)")
    }
  }

  private func refreshPodcast() async {
    isRefreshing = true
    defer { isRefreshing = false }

    do {
      let updatedPodcast = try await rssService.fetchPodcast(
        from: podcastModel.podcastInfo.rssUrl)
      await MainActor.run {
        podcastModel.podcastInfo = updatedPodcast
        try? modelContext.save()
      }
    } catch {
      print("Failed to refresh podcast: \(error)")
    }
  }

  private func toggleStar(for episode: PodcastEpisodeInfo) {
    let key = makeEpisodeKey(episode)
    if let model = episodeModels[key] {
      model.isStarred.toggle()
      try? modelContext.save()
    } else {
      guard let audioURL = episode.audioURL else { return }
      let model = EpisodeDownloadModel(
        episodeTitle: episode.title,
        podcastTitle: podcastModel.podcastInfo.title,
        audioURL: audioURL,
        imageURL: episode.imageURL ?? podcastModel.podcastInfo.imageURL,
        pubDate: episode.pubDate
      )
      model.isStarred = true
      modelContext.insert(model)
      try? modelContext.save()
      episodeModels[key] = model
    }
  }

  private func downloadEpisode(_ episode: PodcastEpisodeInfo) {
    downloadManager.downloadEpisode(
      episode: episode,
      podcastTitle: podcastModel.podcastInfo.title,
      language: podcastModel.podcastInfo.language
    )
  }

  private func deleteDownload(_ episode: PodcastEpisodeInfo) {
    downloadManager.deleteDownload(
      episodeTitle: episode.title, podcastTitle: podcastModel.podcastInfo.title)
  }

  private func togglePlayed(for episode: PodcastEpisodeInfo) {
    let key = makeEpisodeKey(episode)
    if let model = episodeModels[key] {
      model.isCompleted.toggle()
      // Reset playback position if marking as unplayed
      if !model.isCompleted {
        model.lastPlaybackPosition = 0
      }
      try? modelContext.save()
    } else {
      // Create a new model and mark as played
      guard let audioURL = episode.audioURL else { return }
      let model = EpisodeDownloadModel(
        episodeTitle: episode.title,
        podcastTitle: podcastModel.podcastInfo.title,
        audioURL: audioURL,
        imageURL: episode.imageURL ?? podcastModel.podcastInfo.imageURL,
        pubDate: episode.pubDate
      )
      model.isCompleted = true
      modelContext.insert(model)
      try? modelContext.save()
      episodeModels[key] = model
    }
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

  private var downloadState: DownloadState {
    downloadManager.getDownloadState(episodeTitle: episode.title, podcastTitle: podcastTitle)
  }

  private var isDownloaded: Bool {
    if case .downloaded = downloadState {
      return true
    }
    return false
  }

  /// Check if caption file exists
  private var hasCaptions: Bool {
    let fm = FileManager.default
    let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let captionsDir = docsDir.appendingPathComponent("Captions", isDirectory: true)

    // Check for .srt file with sanitized filename
    let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
    let baseFileName = "\(podcastTitle)_\(episode.title)"
      .components(separatedBy: invalidCharacters)
      .joined(separator: "_")
      .trimmingCharacters(in: .whitespaces)

    let srtPath = captionsDir.appendingPathComponent("\(baseFileName).srt")
    return fm.fileExists(atPath: srtPath.path)
  }

  /// Get transcript job status if active
  private var transcriptJobStatus: TranscriptJobStatus? {
    // Use Unit Separator (U+001F) as delimiter - same as TranscriptManager
    let delimiter = "\u{1F}"
    let jobId = "\(podcastTitle)\(delimiter)\(episode.title)"
    return transcriptManager.activeJobs[jobId]?.status
  }

  /// Check if transcript is being generated
  private var isTranscribing: Bool {
    if let status = transcriptJobStatus {
      switch status {
      case .queued, .downloadingModel, .transcribing:
        return true
      default:
        return false
      }
    }
    return false
  }

  /// Get transcript progress (0.0 to 1.0)
  private var transcriptProgress: Double? {
    guard let status = transcriptJobStatus else { return nil }
    switch status {
    case .queued:
      return 0.0
    case .downloadingModel(let progress):
      return progress * 0.1  // Model download is 10% of total
    case .transcribing(let progress):
      return 0.1 + (progress * 0.9)  // Transcription is 90% of total
    default:
      return nil
    }
  }

  private var isStarred: Bool {
    episodeModel?.isStarred ?? false
  }

  private var isCompleted: Bool {
    episodeModel?.isCompleted ?? false
  }

  private var playbackProgress: Double {
    episodeModel?.progress ?? 0
  }

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

  /// Duration text - show remaining time if partially played, otherwise full duration
  private var durationText: String? {
    if let model = episodeModel, model.duration > 0 && model.progress > 0 && model.progress < 1 {
      // Show remaining time
      let remaining = model.duration - model.lastPlaybackPosition
      return formatDuration(Int(remaining))
    }
    // Show full duration from episode
    return episode.formattedDuration
  }

  private var episodeImageURL: String {
    episode.imageURL ?? fallbackImageURL ?? ""
  }

  /// Get plain text description (strip HTML tags)
  private var plainDescription: String? {
    guard let desc = episode.podcastEpisodeDescription else { return nil }
    // Simple HTML tag removal
    let stripped = desc.replacingOccurrences(
      of: "<[^>]+>", with: "", options: .regularExpression
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

    if hours > 0 {
      return "\(hours)h \(minutes)m"
    } else {
      return "\(minutes)m"
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
      HStack(alignment: .top, spacing: 12) {
        // Episode thumbnail
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

        // Episode info
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

            // Caption/Transcript indicator
            if hasCaptions {
              Image(systemName: "captions.bubble.fill")
                .font(.system(size: 8))
                .foregroundColor(.purple)
            } else if isTranscribing {
              // Show transcript generation progress
              HStack(spacing: 2) {
                ProgressView()
                  .scaleEffect(0.4)
                if let progress = transcriptProgress {
                  Text("\(Int(progress * 100))%")
                    .font(.system(size: 7))
                    .foregroundColor(.purple)
                }
              }
            }
          }

          // Title
          Text(episode.title)
            .font(.subheadline)
            .fontWeight(.medium)
            .lineLimit(2)
            .foregroundColor(.primary)

          // Description
          if let description = plainDescription {
            Text(description)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(2)
          }

          // Play button with duration badge
          HStack(spacing: 8) {
            // Duration badge with play button
            Button(action: playAction) {
              HStack(spacing: 4) {
                // Play/Pause/Completed (Replay) icon
                if isPlayingThisEpisode && audioManager.isPlaying {
                  Image(systemName: "pause.fill")
                    .font(.system(size: 10))
                } else if isCompleted {
                  // Show replay icon for completed episodes
                  Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .bold))
                } else {
                  Image(systemName: "play.fill")
                    .font(.system(size: 10))
                }

                // Progress bar (if partially played)
                if playbackProgress > 0 && playbackProgress < 1 {
                  GeometryReader { geo in
                    ZStack(alignment: .leading) {
                      Capsule()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 3)
                      Capsule()
                        .fill(Color.blue)
                        .frame(
                          width: geo.size.width * playbackProgress,
                          height: 3)
                    }
                  }
                  .frame(width: 30, height: 3)
                }

                // Duration text
                if let duration = durationText {
                  Text(duration)
                    .font(.caption2)
                    .fontWeight(.medium)
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

            // Download progress indicator
            if case .downloading(let progress) = downloadState {
              HStack(spacing: 4) {
                ProgressView()
                  .scaleEffect(0.5)
                Text("\(Int(progress * 100))%")
                  .font(.caption2)
              }
              .foregroundColor(.orange)
            } else if case .finishing = downloadState {
              HStack(spacing: 4) {
                ProgressView()
                  .scaleEffect(0.5)
                Text("Saving...")
                  .font(.caption2)
              }
              .foregroundColor(.blue)
            }

            Spacer()
          }
        }
      }
      .padding(.vertical, 6)
    }
    .contextMenu {
      Button(action: onToggleStar) {
        Label(
          isStarred ? "Unstar" : "Star",
          systemImage: isStarred ? "star.fill" : "star"
        )
      }

      Button(action: onTogglePlayed) {
        Label(
          isCompleted ? "Mark as Unplayed" : "Mark as Played",
          systemImage: isCompleted ? "arrow.counterclockwise" : "checkmark.circle"
        )
      }

      Divider()

      if isDownloaded {
        Button(role: .destructive, action: onDeleteRequested) {
          Label("Delete Download", systemImage: "trash")
        }
      } else if case .downloading = downloadState {
        Button(action: {
          downloadManager.cancelDownload(
            episodeTitle: episode.title, podcastTitle: podcastTitle)
        }) {
          Label("Cancel Download", systemImage: "xmark.circle")
        }
      } else if case .finishing = downloadState {
        // Show saving status - no action available
        Label("Saving...", systemImage: "arrow.down.circle.dotted")
      } else {
        Button(action: onDownload) {
          Label("Download", systemImage: "arrow.down.circle")
        }
        .disabled(episode.audioURL == nil)
      }

      if let audioURL = episode.audioURL, let url = URL(string: audioURL) {
        Divider()
        Button(action: {
          let activityVC = UIActivityViewController(
            activityItems: [url], applicationActivities: nil)
          if let windowScene = UIApplication.shared.connectedScenes.first
            as? UIWindowScene,
            let rootVC = windowScene.windows.first?.rootViewController
          {
            rootVC.present(activityVC, animated: true)
          }
        }) {
          Label("Share Episode", systemImage: "square.and.arrow.up")
        }
      }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      // Star action (always available)
      Button(action: onToggleStar) {
        Label(
          isStarred ? "Unstar" : "Star",
          systemImage: isStarred ? "star.slash" : "star.fill")
      }
      .tint(.yellow)

      // Download/Delete/Cancel action
      if isDownloaded {
        Button(role: .destructive, action: onDeleteRequested) {
          Label("Delete", systemImage: "trash")
        }
      } else if case .downloading = downloadState {
        Button(action: {
          downloadManager.cancelDownload(
            episodeTitle: episode.title, podcastTitle: podcastTitle)
        }) {
          Label("Cancel", systemImage: "xmark.circle")
        }
        .tint(.orange)
      } else if case .finishing = downloadState {
        // No swipe action while saving - show disabled state
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
    .swipeActions(edge: .leading, allowsFullSwipe: true) {
      // Mark as played/unplayed action
      Button(action: onTogglePlayed) {
        Label(
          isCompleted ? "Unplayed" : "Played",
          systemImage: isCompleted ? "arrow.counterclockwise" : "checkmark.circle")
      }
      .tint(.green)
    }
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

//#Preview {
//    EpisodeListView(podcastModel: new PodcastInfoModel)
//}
