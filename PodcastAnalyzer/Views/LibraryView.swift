//
//  LibraryView.swift
//  PodcastAnalyzer
//
//  Redesigned Library tab - 2x2 grid of podcasts sorted by recent update,
//  with navigation to Saved/Downloaded sub-pages
//

import SwiftData
import SwiftUI
import ZMarkupParser

#if os(iOS)
import UIKit
#endif

// MARK: - Library View

struct LibraryView: View {
  @State private var viewModel = LibraryViewModel(modelContext: nil)
  @Environment(\.modelContext) private var modelContext
  
  // Use @Query for instant persistence and automatic updates
  @Query(
    filter: #Predicate<PodcastInfoModel> { $0.isSubscribed },
    sort: \.lastUpdated,
    order: .reverse
  ) private var subscribedPodcasts: [PodcastInfoModel]

  // Filtered podcasts for display, sorted by latest episode date
  private var displayPodcasts: [PodcastInfoModel] {
    subscribedPodcasts.sorted { p1, p2 in
      let date1 = p1.podcastInfo.episodes.first?.pubDate ?? .distantPast
      let date2 = p2.podcastInfo.episodes.first?.pubDate ?? .distantPast
      return date1 > date2
    }
  }

  // Grid layout: 2 columns
  private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12)
  ]

  // Context menu state
  @State private var podcastToUnsubscribe: PodcastInfoModel?
  @State private var showUnsubscribeConfirmation = false

  var body: some View {
    NavigationStack {
      ZStack {
        ScrollView {
          VStack(spacing: 24) {
            // Quick access cards
            quickAccessSection
              .padding(.horizontal, 16)

            // Subscribed Podcasts Grid
            podcastsGridSection
              .padding(.horizontal, 16)
          }
          .padding(.top, 8)
          .padding(.bottom, 40)
        }

        // Only show full-screen loading on first load when no cached data exists
        if viewModel.isLoadingPodcasts && subscribedPodcasts.isEmpty
            && viewModel.savedEpisodes.isEmpty && viewModel.downloadedEpisodes.isEmpty {
          ProgressView("Loading Library...")
            .scaleEffect(1.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.platformBackground)
        }
      }
      .navigationTitle(Constants.libraryString)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button(action: {
            Task {
              await viewModel.refreshAllPodcasts()
            }
          }) {
            Image(systemName: "arrow.clockwise")
          }
          .disabled(viewModel.isLoading)
        }
      }
      .platformToolbarTitleDisplayMode()
      .refreshable {
        await viewModel.refreshAllPodcasts()
      }
    }
    .onAppear {
      // This is the key: set the context once
      viewModel.setModelContext(modelContext)
      viewModel.setPodcasts(subscribedPodcasts)
    }
    .onChange(of: subscribedPodcasts) { _, newPodcasts in
        viewModel.setPodcasts(newPodcasts)
    }
    .onDisappear {
      viewModel.cleanup()
    }
    .confirmationDialog(
      "Unsubscribe from Podcast",
      isPresented: $showUnsubscribeConfirmation,
      titleVisibility: .visible
    ) {
      Button("Unsubscribe", role: .destructive) {
        if let podcast = podcastToUnsubscribe {
          unsubscribePodcast(podcast)
        }
        podcastToUnsubscribe = nil
      }
      Button("Cancel", role: .cancel) {
        podcastToUnsubscribe = nil
      }
    } message: {
      if let podcast = podcastToUnsubscribe {
        Text("Are you sure you want to unsubscribe from \"\(podcast.podcastInfo.title)\"? Downloaded episodes will remain available.")
      }
    }
  }

  // MARK: - Quick Access Section

  @ViewBuilder
  private var quickAccessSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Row of quick access cards
      HStack(spacing: 12) {
        // Saved (Starred) card
        NavigationLink(destination: SavedEpisodesView(viewModel: viewModel)) {
          QuickAccessCard(
            icon: "star.fill",
            iconColor: .yellow,
            title: "Saved",
            count: viewModel.savedEpisodes.count,
            isLoading: viewModel.isLoadingSaved
          )
        }
        .buttonStyle(.plain)

        // Downloaded card
        NavigationLink(destination: DownloadedEpisodesView(viewModel: viewModel)) {
          QuickAccessCard(
            icon: "arrow.down.circle.fill",
            iconColor: .green,
            title: "Downloaded",
            count: viewModel.downloadedEpisodes.count,
            isLoading: viewModel.isLoadingDownloaded
          )
        }
        .buttonStyle(.plain)
      }

      // Latest episodes row
      NavigationLink(destination: LatestEpisodesView(viewModel: viewModel)) {
        HStack {
          HStack(spacing: 8) {
            Image(systemName: "clock.fill")
              .font(.system(size: 16))
              .foregroundColor(.blue)
            Text("Latest Episodes")
              .font(.subheadline)
              .fontWeight(.medium)
              .foregroundColor(.primary)
          }

          Spacer()

          HStack(spacing: 4) {
            if viewModel.isLoadingLatest {
              ProgressView()
                .scaleEffect(0.6)
            } else {
              Text("\(viewModel.latestEpisodes.count)")
                .font(.caption)
                .foregroundColor(.secondary)
              Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.platformSystemGray6)
        .cornerRadius(12)
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Podcasts Grid Section

  @ViewBuilder
  private var podcastsGridSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Your Podcasts")
          .font(.headline)

        Spacer()

        if viewModel.isLoadingPodcasts {
          ProgressView()
            .scaleEffect(0.7)
        } else {
          Text("\(displayPodcasts.count)")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
      }

      if displayPodcasts.isEmpty {
        emptyPodcastsView
      } else {
        LazyVGrid(columns: columns, spacing: 16) {
          ForEach(displayPodcasts) { podcast in
            NavigationLink(destination: EpisodeListView(podcastModel: podcast)) {
              PodcastGridCell(podcast: podcast)
            }
            .buttonStyle(.plain)
            .contextMenu {
              // View episodes
              NavigationLink(destination: EpisodeListView(podcastModel: podcast)) {
                Label("View Episodes", systemImage: "list.bullet")
              }

              Divider()

              // Refresh podcast
              Button {
                Task {
                  await refreshPodcast(podcast)
                }
              } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
              }

              // Copy RSS URL
              Button {
                PlatformClipboard.string = podcast.podcastInfo.rssUrl
              } label: {
                Label("Copy RSS URL", systemImage: "doc.on.doc")
              }

              Divider()

              // Unsubscribe
              Button(role: .destructive) {
                podcastToUnsubscribe = podcast
                showUnsubscribeConfirmation = true
              } label: {
                Label("Unsubscribe", systemImage: "minus.circle")
              }
            }
          }
        }
      }
    }
  }

  // MARK: - Podcast Actions

  private func refreshPodcast(_ podcast: PodcastInfoModel) async {
    let rssService = PodcastRssService()
    do {
      let updatedPodcast = try await rssService.fetchPodcast(from: podcast.podcastInfo.rssUrl)
      podcast.podcastInfo = updatedPodcast
      podcast.lastUpdated = Date()
      try modelContext.save()
    } catch {
      // Silently fail refresh
    }
  }

  private func unsubscribePodcast(_ podcast: PodcastInfoModel) {
    podcast.isSubscribed = false
    do {
      try modelContext.save()
      // Reload the view model
      viewModel.setModelContext(modelContext)
    } catch {
      // Silently fail
    }
  }

  @ViewBuilder
  private var emptyPodcastsView: some View {
    VStack(spacing: 12) {
      Image(systemName: "square.stack.3d.up")
        .font(.system(size: 40))
        .foregroundColor(.secondary)
      Text("No Subscriptions")
        .font(.headline)
      Text("Search and subscribe to podcasts to build your library")
        .font(.caption)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }
}

// MARK: - Quick Access Card

struct QuickAccessCard: View {
  let icon: String
  let iconColor: Color
  let title: String
  let count: Int
  var isLoading: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: icon)
          .font(.system(size: 20))
          .foregroundColor(iconColor)

        Spacer()

        if isLoading {
          ProgressView()
            .scaleEffect(0.6)
        } else {
          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }

      Spacer()

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.primary)

        Text("\(count) episodes")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 90)
    .background(Color.platformSystemGray6)
    .cornerRadius(12)
  }
}

// MARK: - Podcast Grid Cell

struct PodcastGridCell: View {
  let podcast: PodcastInfoModel

  private var latestEpisodeDate: String? {
    guard let date = podcast.podcastInfo.episodes.first?.pubDate else { return nil }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Artwork - using CachedAsyncImage for better performance
      GeometryReader { geo in
        CachedAsyncImage(url: URL(string: podcast.podcastInfo.imageURL)) { image in
          image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
          Color.gray.opacity(0.2)
            .overlay(ProgressView().scaleEffect(0.5))
        }
        .frame(width: geo.size.width, height: geo.size.width)
        .cornerRadius(10)
        .clipped()
      }
      .aspectRatio(1, contentMode: .fit)

      // Podcast title
      Text(podcast.podcastInfo.title)
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(2)
        .foregroundColor(.primary)

      // Latest episode date
      if let dateStr = latestEpisodeDate {
        Text(dateStr)
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
  }
}

// MARK: - Saved Episodes View (Sub-page)

struct SavedEpisodesView: View {
  @Bindable var viewModel: LibraryViewModel
  @Environment(\.modelContext) private var modelContext
  @State private var settingsViewModel = SettingsViewModel()
  @State private var episodeToDelete: LibraryEpisode?
  @State private var showDeleteConfirmation = false

  var body: some View {
    Group {
      if viewModel.savedEpisodes.isEmpty {
        emptyStateView
      } else {
        List(viewModel.filteredSavedEpisodes) { episode in
          EpisodeRowView(
            libraryEpisode: episode,
            episodeModel: fetchEpisodeModel(for: episode),
            showArtwork: settingsViewModel.showEpisodeArtwork,
            onToggleStar: { toggleStar(episode) },
            onDownload: { downloadEpisode(episode) },
            onDeleteRequested: {
              episodeToDelete = episode
              showDeleteConfirmation = true
            },
            onTogglePlayed: { togglePlayed(episode) }
          )
          .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
        .listStyle(.plain)
        .refreshable {
          viewModel.setModelContext(modelContext)
        }
      }
    }
    .navigationTitle("Saved")
    .searchable(text: $viewModel.savedSearchText, prompt: "Search saved episodes")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear {
      viewModel.setModelContext(modelContext)
    }
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
      Text("Are you sure you want to delete this downloaded episode?")
    }
  }

  private var emptyStateView: some View {
    VStack(spacing: 16) {
      Image(systemName: "star")
        .font(.system(size: 50))
        .foregroundColor(.secondary)
      Text("No Saved Episodes")
        .font(.headline)
      Text("Star episodes to save them here for later")
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Helper Methods

  private func fetchEpisodeModel(for episode: LibraryEpisode) -> EpisodeDownloadModel? {
    let episodeId = episode.id
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == episodeId }
    )
    return try? modelContext.fetch(descriptor).first
  }

  private func toggleStar(_ episode: LibraryEpisode) {
    if let model = fetchEpisodeModel(for: episode) {
      model.isStarred.toggle()
      try? modelContext.save()
      viewModel.setModelContext(modelContext)
    }
  }

  private func togglePlayed(_ episode: LibraryEpisode) {
    if let model = fetchEpisodeModel(for: episode) {
      model.isCompleted.toggle()
      if !model.isCompleted {
        model.lastPlaybackPosition = 0
      }
      try? modelContext.save()
      viewModel.setModelContext(modelContext)
    }
  }

  private func downloadEpisode(_ episode: LibraryEpisode) {
    DownloadManager.shared.downloadEpisode(
      episode: episode.episodeInfo,
      podcastTitle: episode.podcastTitle,
      language: episode.language
    )
  }

  private func deleteDownload(_ episode: LibraryEpisode) {
    DownloadManager.shared.deleteDownload(
      episodeTitle: episode.episodeInfo.title,
      podcastTitle: episode.podcastTitle
    )
    viewModel.setModelContext(modelContext)
  }
}

// MARK: - Downloaded Episodes View (Sub-page)

struct DownloadedEpisodesView: View {
  @Bindable var viewModel: LibraryViewModel
  @Environment(\.modelContext) private var modelContext
  @State private var settingsViewModel = SettingsViewModel()
  @State private var episodeToDelete: LibraryEpisode?
  @State private var showDeleteConfirmation = false

  var body: some View {
    Group {
      if viewModel.downloadedEpisodes.isEmpty {
        emptyStateView
      } else {
        List(viewModel.filteredDownloadedEpisodes) { episode in
          EpisodeRowView(
            libraryEpisode: episode,
            episodeModel: fetchEpisodeModel(for: episode),
            showArtwork: settingsViewModel.showEpisodeArtwork,
            onToggleStar: { toggleStar(episode) },
            onDownload: { downloadEpisode(episode) },
            onDeleteRequested: {
              episodeToDelete = episode
              showDeleteConfirmation = true
            },
            onTogglePlayed: { togglePlayed(episode) }
          )
          .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
        .listStyle(.plain)
        .refreshable {
          viewModel.setModelContext(modelContext)
        }
      }
    }
    .navigationTitle("Downloaded")
    .searchable(text: $viewModel.downloadedSearchText, prompt: "Search downloaded episodes")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear {
      viewModel.setModelContext(modelContext)
    }
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
      Text("Are you sure you want to delete this downloaded episode?")
    }
  }

  private var emptyStateView: some View {
    VStack(spacing: 16) {
      Image(systemName: "arrow.down.circle")
        .font(.system(size: 50))
        .foregroundColor(.secondary)
      Text("No Downloads")
        .font(.headline)
      Text("Downloaded episodes will appear here for offline listening")
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Helper Methods

  private func fetchEpisodeModel(for episode: LibraryEpisode) -> EpisodeDownloadModel? {
    let episodeId = episode.id
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == episodeId }
    )
    return try? modelContext.fetch(descriptor).first
  }

  private func toggleStar(_ episode: LibraryEpisode) {
    if let model = fetchEpisodeModel(for: episode) {
      model.isStarred.toggle()
      try? modelContext.save()
      viewModel.setModelContext(modelContext)
    }
  }

  private func togglePlayed(_ episode: LibraryEpisode) {
    if let model = fetchEpisodeModel(for: episode) {
      model.isCompleted.toggle()
      if !model.isCompleted {
        model.lastPlaybackPosition = 0
      }
      try? modelContext.save()
      viewModel.setModelContext(modelContext)
    }
  }

  private func downloadEpisode(_ episode: LibraryEpisode) {
    DownloadManager.shared.downloadEpisode(
      episode: episode.episodeInfo,
      podcastTitle: episode.podcastTitle,
      language: episode.language
    )
  }

  private func deleteDownload(_ episode: LibraryEpisode) {
    DownloadManager.shared.deleteDownload(
      episodeTitle: episode.episodeInfo.title,
      podcastTitle: episode.podcastTitle
    )
    viewModel.setModelContext(modelContext)
  }
}

// MARK: - Latest Episodes View (Sub-page)

struct LatestEpisodesView: View {
  @Bindable var viewModel: LibraryViewModel
  @Environment(\.modelContext) private var modelContext
  @State private var settingsViewModel = SettingsViewModel()
  @State private var episodeToDelete: LibraryEpisode?
  @State private var showDeleteConfirmation = false

  var body: some View {
    Group {
      if viewModel.latestEpisodes.isEmpty {
        emptyStateView
      } else {
        List(viewModel.filteredLatestEpisodes) { episode in
          EpisodeRowView(
            libraryEpisode: episode,
            episodeModel: fetchEpisodeModel(for: episode),
            showArtwork: settingsViewModel.showEpisodeArtwork,
            onToggleStar: { toggleStar(episode) },
            onDownload: { downloadEpisode(episode) },
            onDeleteRequested: {
              episodeToDelete = episode
              showDeleteConfirmation = true
            },
            onTogglePlayed: { togglePlayed(episode) }
          )
          .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
        .listStyle(.plain)
        .refreshable {
          viewModel.setModelContext(modelContext)
        }
      }
    }
    .navigationTitle("Latest Episodes")
    .searchable(text: $viewModel.latestSearchText, prompt: "Search latest episodes")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear {
      viewModel.setModelContext(modelContext)
    }
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
      Text("Are you sure you want to delete this downloaded episode?")
    }
  }

  private var emptyStateView: some View {
    VStack(spacing: 16) {
      Image(systemName: "clock")
        .font(.system(size: 50))
        .foregroundColor(.secondary)
      Text("No Episodes")
        .font(.headline)
      Text("Subscribe to podcasts to see latest episodes")
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Helper Methods

  private func fetchEpisodeModel(for episode: LibraryEpisode) -> EpisodeDownloadModel? {
    let episodeId = episode.id
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == episodeId }
    )
    return try? modelContext.fetch(descriptor).first
  }

  private func toggleStar(_ episode: LibraryEpisode) {
    if let model = fetchEpisodeModel(for: episode) {
      model.isStarred.toggle()
      try? modelContext.save()
      viewModel.setModelContext(modelContext)
    } else if let audioURL = episode.episodeInfo.audioURL {
      // Create model if it doesn't exist
      let model = EpisodeDownloadModel(
        episodeTitle: episode.episodeInfo.title,
        podcastTitle: episode.podcastTitle,
        audioURL: audioURL,
        imageURL: episode.imageURL ?? "",
        pubDate: episode.episodeInfo.pubDate
      )
      model.isStarred = true
      modelContext.insert(model)
      try? modelContext.save()
      viewModel.setModelContext(modelContext)
    }
  }

  private func togglePlayed(_ episode: LibraryEpisode) {
    if let model = fetchEpisodeModel(for: episode) {
      model.isCompleted.toggle()
      if !model.isCompleted {
        model.lastPlaybackPosition = 0
      }
      try? modelContext.save()
      viewModel.setModelContext(modelContext)
    } else if let audioURL = episode.episodeInfo.audioURL {
      // Create model if it doesn't exist
      let model = EpisodeDownloadModel(
        episodeTitle: episode.episodeInfo.title,
        podcastTitle: episode.podcastTitle,
        audioURL: audioURL,
        imageURL: episode.imageURL ?? "",
        pubDate: episode.episodeInfo.pubDate
      )
      model.isCompleted = true
      modelContext.insert(model)
      try? modelContext.save()
      viewModel.setModelContext(modelContext)
    }
  }

  private func downloadEpisode(_ episode: LibraryEpisode) {
    DownloadManager.shared.downloadEpisode(
      episode: episode.episodeInfo,
      podcastTitle: episode.podcastTitle,
      language: episode.language
    )
  }

  private func deleteDownload(_ episode: LibraryEpisode) {
    DownloadManager.shared.deleteDownload(
      episodeTitle: episode.episodeInfo.title,
      podcastTitle: episode.podcastTitle
    )
    viewModel.setModelContext(modelContext)
  }
}

// MARK: - Library Episode Context Menu

struct LibraryEpisodeContextMenu: View {
  let episode: LibraryEpisode
  let modelContext: ModelContext
  let onRefresh: () -> Void

  private let downloadManager = DownloadManager.shared
  private let audioManager = EnhancedAudioManager.shared

  private var statusChecker: EpisodeStatusChecker {
    EpisodeStatusChecker(episode: episode)
  }

  private var downloadState: DownloadState { statusChecker.downloadState }

  private var isDownloaded: Bool { statusChecker.isDownloaded }
  private var playbackURL: String { statusChecker.playbackURL }

  var body: some View {
    // Go to Show
    goToShowButton

    Divider()

    // Play episode
    Button {
      playEpisode()
    } label: {
      Label("Play Episode", systemImage: "play.fill")
    }
    .disabled(episode.episodeInfo.audioURL == nil)

    // Play Next
    Button {
      addToPlayNext()
    } label: {
      Label("Play Next", systemImage: "text.insert")
    }
    .disabled(episode.episodeInfo.audioURL == nil)

    Divider()

    // Star/Unstar
    Button {
      toggleStar()
    } label: {
      Label(
        episode.isStarred ? "Remove from Saved" : "Save Episode",
        systemImage: episode.isStarred ? "star.slash" : "star"
      )
    }

    // Mark as Played/Unplayed
    Button {
      togglePlayed()
    } label: {
      Label(
        episode.isCompleted ? "Mark as Unplayed" : "Mark as Played",
        systemImage: episode.isCompleted ? "arrow.counterclockwise" : "checkmark.circle"
      )
    }

    Divider()

    // Download/Delete download
    if isDownloaded {
      Button(role: .destructive) {
        deleteDownload()
      } label: {
        Label("Delete Download", systemImage: "trash")
      }
    } else if case .downloading = downloadState {
      Button {
        cancelDownload()
      } label: {
        Label("Cancel Download", systemImage: "xmark.circle")
      }
    } else if episode.episodeInfo.audioURL != nil {
      Button {
        startDownload()
      } label: {
        Label("Download", systemImage: "arrow.down.circle")
      }
    }

    Divider()

    // Share
    Button {
      shareEpisode()
    } label: {
      Label("Share", systemImage: "square.and.arrow.up")
    }
  }

  @ViewBuilder
  private var goToShowButton: some View {
    let title = episode.podcastTitle
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.title == title }
    )
    if let podcastModel = try? modelContext.fetch(descriptor).first {
      NavigationLink(destination: EpisodeListView(podcastModel: podcastModel)) {
        Label("Go to Show", systemImage: "square.stack")
      }
    } else {
      Button {
        // Can't navigate without podcast model
      } label: {
        Label("Go to Show", systemImage: "square.stack")
      }
      .disabled(true)
    }
  }

  private func playEpisode() {
    guard episode.episodeInfo.audioURL != nil else { return }

    let playbackEpisode = PlaybackEpisode(
      id: statusChecker.episodeKey,
      title: episode.episodeInfo.title,
      podcastTitle: episode.podcastTitle,
      audioURL: playbackURL,
      imageURL: episode.imageURL,
      episodeDescription: episode.episodeInfo.podcastEpisodeDescription,
      pubDate: episode.episodeInfo.pubDate,
      duration: episode.episodeInfo.duration,
      guid: episode.episodeInfo.guid
    )

    audioManager.play(
      episode: playbackEpisode,
      audioURL: playbackURL,
      startTime: episode.lastPlaybackPosition,
      imageURL: episode.imageURL ?? "",
      useDefaultSpeed: episode.lastPlaybackPosition == 0
    )
  }

  private func addToPlayNext() {
    guard episode.episodeInfo.audioURL != nil else { return }

    let playbackEpisode = PlaybackEpisode(
      id: statusChecker.episodeKey,
      title: episode.episodeInfo.title,
      podcastTitle: episode.podcastTitle,
      audioURL: playbackURL,
      imageURL: episode.imageURL,
      episodeDescription: episode.episodeInfo.podcastEpisodeDescription,
      pubDate: episode.episodeInfo.pubDate,
      duration: episode.episodeInfo.duration,
      guid: episode.episodeInfo.guid
    )

    audioManager.playNext(playbackEpisode)
  }

  private func toggleStar() {
    let episodeKey = statusChecker.episodeKey
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == episodeKey }
    )

    if let model = try? modelContext.fetch(descriptor).first {
      model.isStarred.toggle()
      try? modelContext.save()
    } else if let audioURL = episode.episodeInfo.audioURL {
      let model = EpisodeDownloadModel(
        episodeTitle: episode.episodeInfo.title,
        podcastTitle: episode.podcastTitle,
        audioURL: audioURL,
        imageURL: episode.imageURL ?? "",
        pubDate: episode.episodeInfo.pubDate
      )
      model.isStarred = true
      modelContext.insert(model)
      try? modelContext.save()
    }
    onRefresh()
  }

  private func togglePlayed() {
    let episodeKey = statusChecker.episodeKey
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == episodeKey }
    )

    if let model = try? modelContext.fetch(descriptor).first {
      model.isCompleted.toggle()
      if !model.isCompleted {
        model.lastPlaybackPosition = 0
      }
      try? modelContext.save()
    } else if let audioURL = episode.episodeInfo.audioURL {
      let model = EpisodeDownloadModel(
        episodeTitle: episode.episodeInfo.title,
        podcastTitle: episode.podcastTitle,
        audioURL: audioURL,
        imageURL: episode.imageURL ?? "",
        pubDate: episode.episodeInfo.pubDate
      )
      model.isCompleted = true
      modelContext.insert(model)
      try? modelContext.save()
    }
    onRefresh()
  }

  private func startDownload() {
    downloadManager.downloadEpisode(
      episode: episode.episodeInfo,
      podcastTitle: episode.podcastTitle,
      language: episode.language
    )
  }

  private func cancelDownload() {
    downloadManager.cancelDownload(
      episodeTitle: episode.episodeInfo.title,
      podcastTitle: episode.podcastTitle
    )
  }

  private func deleteDownload() {
    downloadManager.deleteDownload(
      episodeTitle: episode.episodeInfo.title,
      podcastTitle: episode.podcastTitle
    )
    onRefresh()
  }

  private func shareEpisode() {
    if let audioURL = episode.episodeInfo.audioURL, let url = URL(string: audioURL) {
      PlatformShareSheet.share(url: url)
    }
  }
}

#Preview {
  LibraryView()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
