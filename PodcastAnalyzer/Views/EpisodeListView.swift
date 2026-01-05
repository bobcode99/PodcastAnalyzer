//
//  EpisodeListView.swift
//  PodcastAnalyzer
//
//  Unified view for browsing podcast episodes - works for both subscribed and unsubscribed podcasts.
//

import SwiftData
import SwiftUI

#if os(iOS)
  import UIKit
#endif

// MARK: - Episode Filter Enum

enum EpisodeFilter: String, CaseIterable {
  case all = "All"
  case unplayed = "Unplayed"
  case played = "Played"
  case starred = "Starred"
  case downloaded = "Downloaded"

  var icon: String {
    switch self {
    case .all: return "list.bullet"
    case .unplayed: return "circle"
    case .played: return "checkmark.circle"
    case .starred: return "star.fill"
    case .downloaded: return "arrow.down.circle.fill"
    }
  }
}

// MARK: - Podcast Source (subscribed vs browse)

enum PodcastSource {
  case model(PodcastInfoModel)
  case browse(
    collectionId: String, podcastName: String, artistName: String, artworkURL: String,
    applePodcastURL: String?)
}

// MARK: - Episode List View

struct EpisodeListView: View {
  private let source: PodcastSource

  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Bindable private var downloadManager = DownloadManager.shared
  @State private var viewModel: EpisodeListViewModel?
  @State private var settingsViewModel = SettingsViewModel()
  @State private var episodeToDelete: PodcastEpisodeInfo?
  @State private var showDeleteConfirmation = false
  @State private var showUnsubscribeConfirmation = false
  @State private var applePodcastURL: URL?

  // Browse mode state
  @State private var isLoadingRSS = false
  @State private var loadError: String?
  @State private var podcastModel: PodcastInfoModel?

  private let applePodcastService = ApplePodcastService()

  // MARK: - Initializers

  /// Initialize with a podcast model (subscribed or browsed)
  init(podcastModel: PodcastInfoModel) {
    self.source = .model(podcastModel)
  }

  /// Initialize for browsing an unsubscribed podcast (will be persisted with isSubscribed=false)
  init(
    podcastName: String,
    podcastArtwork: String,
    artistName: String,
    collectionId: String,
    applePodcastUrl: String?
  ) {
    self.source = .browse(
      collectionId: collectionId,
      podcastName: podcastName,
      artistName: artistName,
      artworkURL: podcastArtwork,
      applePodcastURL: applePodcastUrl
    )
  }

  private var navigationTitle: String {
    switch source {
    case .model(let model):
      return model.podcastInfo.title
    case .browse(_, let name, _, _, _):
      return name
    }
  }

  private var artistName: String {
    switch source {
    case .model:
      return ""
    case .browse(_, _, let artist, _, _):
      return artist
    }
  }

  private var isSubscribed: Bool {
    podcastModel?.isSubscribed ?? false
  }

  private var toolbarPlacement: ToolbarItemPlacement {
    #if os(iOS)
      return .topBarTrailing
    #else
      return .primaryAction
    #endif
  }

  var body: some View {
    Group {
      switch source {
      case .model(let model):
        modelContent(podcastModel: model)
      case .browse:
        browseContent
      }
    }
    .navigationTitle(navigationTitle)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .onDisappear {
      // Clean up all resources when view disappears (works for both modes)
      viewModel?.cleanup()
    }
  }

  // MARK: - Model Content (for existing PodcastInfoModel)

  @ViewBuilder
  private func modelContent(podcastModel: PodcastInfoModel) -> some View {
    Group {
      if let vm = viewModel {
        episodeListContent(viewModel: vm)
      } else {
        ProgressView("Loading...")
      }
    }
    .onAppear {
      self.podcastModel = podcastModel
      if viewModel == nil {
        let vm = EpisodeListViewModel(podcastModel: podcastModel)
        vm.setModelContext(modelContext)
        viewModel = vm
      }
      viewModel?.startRefreshTimer()
    }
    .task {
      await lookupApplePodcastURL(title: podcastModel.podcastInfo.title)
    }
  }

  // MARK: - Browse Content

  @ViewBuilder
  private var browseContent: some View {
    Group {
      if isLoadingRSS {
        loadingView
      } else if let error = loadError {
        errorView(error)
      } else if let vm = viewModel {
        episodeListContent(viewModel: vm)
      } else {
        loadingView
      }
    }
    .task {
      await loadBrowsePodcast()
    }
  }

  private var loadingView: some View {
    VStack(spacing: 20) {
      if case .browse(_, let name, _, let artwork, _) = source {
        AsyncImage(url: URL(string: artwork.replacingOccurrences(of: "100x100", with: "300x300"))) {
          phase in
          if let image = phase.image {
            image.resizable().scaledToFit()
          } else {
            Color.gray
          }
        }
        .frame(width: 150, height: 150)
        .cornerRadius(12)

        Text(name)
          .font(.headline)
      }

      ProgressView("Loading episodes...")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func errorView(_ error: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 50))
        .foregroundColor(.orange)

      Text("Unable to load podcast")
        .font(.headline)

      Text(error)
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)

      Button("Try Again") {
        Task { await loadBrowsePodcast() }
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func loadBrowsePodcast() async {
    guard case .browse(let collectionId, let podcastName, _, _, let appleURL) = source else {
      return
    }

    isLoadingRSS = true
    loadError = nil

    // Set Apple URL if provided
    if let urlStr = appleURL, let url = URL(string: urlStr) {
      applePodcastURL = url
    }

    // Check if this podcast already exists in SwiftData (subscribed or browsed before)
    let existingModel = findExistingPodcast(podcastName: podcastName)
    if let existing = existingModel {
      // Use existing model
      self.podcastModel = existing
      let vm = EpisodeListViewModel(podcastModel: existing)
      vm.setModelContext(modelContext)
      self.viewModel = vm
      vm.startRefreshTimer()

      if applePodcastURL == nil {
        await lookupApplePodcastURL(title: existing.podcastInfo.title)
      }

      isLoadingRSS = false
      return
    }

    // Look up RSS URL from Apple
    do {
      guard let podcast = try await applePodcastService.lookupPodcast(collectionId: collectionId),
        let feedUrl = podcast.feedUrl
      else {
        throw URLError(.badServerResponse)
      }

      // Fetch RSS with caching
      let info = try await RSSCacheService.shared.fetchPodcast(from: feedUrl)

      // Persist to SwiftData with isSubscribed = false (browsed podcast)
      let model = PodcastInfoModel(podcastInfo: info, lastUpdated: Date(), isSubscribed: false)
      modelContext.insert(model)
      try modelContext.save()

      self.podcastModel = model
      let vm = EpisodeListViewModel(podcastModel: model)
      vm.setModelContext(modelContext)
      self.viewModel = vm
      vm.startRefreshTimer()

      // Lookup Apple URL if not provided
      if applePodcastURL == nil {
        await lookupApplePodcastURL(title: info.title)
      }

      isLoadingRSS = false
    } catch {
      loadError = error.localizedDescription
      isLoadingRSS = false
    }
  }

  private func findExistingPodcast(podcastName: String) -> PodcastInfoModel? {
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.podcastInfo.title == podcastName }
    )
    return try? modelContext.fetch(descriptor).first
  }

  private func subscribe() {
    guard let model = podcastModel else { return }

    // Just flip the isSubscribed flag
    model.isSubscribed = true

    do {
      try modelContext.save()
    } catch {
      loadError = "Failed to subscribe: \(error.localizedDescription)"
    }
  }

  private func unsubscribe() {
    guard let model = podcastModel else { return }

    // Flip the isSubscribed flag to false
    model.isSubscribed = false

    do {
      try modelContext.save()
      // Navigate back after unsubscribing
      dismiss()
    } catch {
      loadError = "Failed to unsubscribe: \(error.localizedDescription)"
    }
  }

  // MARK: - Episode List Content

  @ViewBuilder
  private func episodeListContent(viewModel: EpisodeListViewModel) -> some View {
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
            showArtwork: settingsViewModel.showEpisodeArtwork,
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
    .toolbar {
      ToolbarItem(placement: toolbarPlacement) {
        Menu {
          if let url = applePodcastURL {
            Link(destination: url) {
              Label("View on Apple Podcasts", systemImage: "link")
            }

            Divider()
          }

          if isSubscribed {
            Button(role: .destructive) {
              showUnsubscribeConfirmation = true
            } label: {
              Label("Unsubscribe", systemImage: "minus.circle")
            }
          } else {
            Button(action: subscribe) {
              Label("Subscribe", systemImage: "plus.circle")
            }
          }

          Divider()

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
    .confirmationDialog(
      "Unsubscribe from Podcast",
      isPresented: $showUnsubscribeConfirmation,
      titleVisibility: .visible
    ) {
      Button("Unsubscribe", role: .destructive) {
        unsubscribe()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Are you sure you want to unsubscribe from this podcast? Downloaded episodes will remain available."
      )
    }
  }

  // MARK: - Apple Podcast Lookup

  private func lookupApplePodcastURL(title: String) async {
    do {
      let podcasts = try await applePodcastService.searchPodcasts(term: title, limit: 5)
      // Find matching podcast by name
      if let match = podcasts.first(where: {
        $0.collectionName.lowercased() == title.lowercased()
      }) ?? podcasts.first {
        // Construct Apple Podcasts URL
        let urlString = "https://podcasts.apple.com/podcast/id\(match.collectionId)"
        applePodcastURL = URL(string: urlString)
      }
    } catch {
      // Silently fail - Apple URL is optional
    }
  }

  // MARK: - Header Section

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

          if !artistName.isEmpty {
            Text(artistName)
              .font(.subheadline)
              .foregroundColor(.secondary)
          }

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

          // Subscribe button
          Button(action: subscribe) {
            HStack {
              Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle.fill")
              Text(isSubscribed ? "Subscribed" : "Subscribe")
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSubscribed ? Color.green : Color.blue)
            .cornerRadius(16)
          }
          .buttonStyle(.plain)
          .disabled(isSubscribed)
          .padding(.top, 4)

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
              .buttonStyle(.plain)
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
          .buttonStyle(.plain)
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
  var downloadManager: DownloadManager
  let episodeModel: EpisodeDownloadModel?
  var showArtwork: Bool = true
  let onToggleStar: () -> Void
  let onDownload: () -> Void
  let onDeleteRequested: () -> Void
  let onTogglePlayed: () -> Void

  @Environment(\.modelContext) private var modelContext
  private var audioManager: EnhancedAudioManager {
    EnhancedAudioManager.shared
  }
  private let applePodcastService = ApplePodcastService()
  @State private var shareTask: Task<Void, Never>?
  @State private var hasAIAnalysis: Bool = false

  // Transcript state - only updated on appear and when actively transcribing this episode
  @State private var hasCaptions: Bool = false
  @State private var isTranscribing: Bool = false
  @State private var transcriptProgress: Double? = nil
  @State private var isDownloadingModel: Bool = false

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

  private func updateTranscriptStatus() {
    // Check if transcript file exists
    let fileExists = statusChecker.hasTranscript

    // Check for active job only for this specific episode
    let transcriptManager = TranscriptManager.shared
    if let job = transcriptManager.activeJobs[jobId] {
      switch job.status {
      case .completed:
        hasCaptions = true
        isTranscribing = false
        transcriptProgress = nil
        isDownloadingModel = false
      case .queued:
        hasCaptions = fileExists
        isTranscribing = true
        transcriptProgress = 0.0
        isDownloadingModel = false
      case .downloadingModel(let progress):
        hasCaptions = fileExists
        isTranscribing = true
        transcriptProgress = progress
        isDownloadingModel = true
      case .transcribing(let progress):
        hasCaptions = fileExists
        isTranscribing = true
        transcriptProgress = progress
        isDownloadingModel = false
      case .failed:
        hasCaptions = fileExists
        isTranscribing = false
        transcriptProgress = nil
        isDownloadingModel = false
      }
    } else {
      hasCaptions = fileExists
      isTranscribing = false
      transcriptProgress = nil
      isDownloadingModel = false
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
        if showArtwork {
          episodeThumbnail
        }
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
    .onAppear {
      checkAIAnalysis()
      updateTranscriptStatus()
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

      // Title
      Text(episode.title)
        .font(.subheadline)
        .fontWeight(.semibold)
        .lineLimit(3)
        .foregroundColor(.primary)

      // Description
      if let description = plainDescription {
        Text(description)
          .font(.caption)
          .foregroundColor(.secondary)
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
      // Play button with progress (using reusable component)
      EpisodePlayButton(
        isPlaying: audioManager.isPlaying,
        isPlayingThisEpisode: isPlayingThisEpisode,
        isCompleted: isCompleted,
        playbackProgress: playbackProgress,
        duration: episodeModel?.duration,
        lastPlaybackPosition: episodeModel?.lastPlaybackPosition ?? 0,
        formattedDuration: episode.formattedDuration,
        isDisabled: episode.audioURL == nil,
        style: .compact,
        action: playAction
      )

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
    .buttonStyle(.plain)
  }
}
