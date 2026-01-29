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

  // Cached sorted podcasts to avoid re-sorting on every render
  @State private var sortedPodcasts: [PodcastInfoModel] = []

  // Grid layout: 2 columns
  private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12)
  ]

  // Context menu state
  @State private var podcastToUnsubscribe: PodcastInfoModel?
  @State private var showUnsubscribeConfirmation = false

  // Notification observers
  @State private var syncObserver: NSObjectProtocol?
  @State private var downloadObserver: NSObjectProtocol?

  var body: some View {
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

      // Initial loading state only when truly empty
      if viewModel.isLoading && subscribedPodcasts.isEmpty
          && viewModel.savedEpisodes.isEmpty && viewModel.downloadedEpisodes.isEmpty {
        ProgressView("Loading Library...")
          .scaleEffect(1.5)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color.platformBackground)
      }
    }
    .navigationTitle(Constants.libraryString)
    .platformToolbarTitleDisplayMode()
    .refreshable {
      await viewModel.refreshAllPodcasts()
    }
    .onAppear {
      // Set the context and initial podcasts
      viewModel.setModelContext(modelContext)
      viewModel.setPodcasts(subscribedPodcasts)
      updateSortedPodcasts()
      setupNotificationObservers()
      // Refresh saved/downloaded counts in case they changed while view was off-screen
      Task {
        await viewModel.refreshSavedEpisodes()
        await viewModel.refreshDownloadedEpisodes()
      }
    }
    .onChange(of: subscribedPodcasts) { _, newPodcasts in
      viewModel.setPodcasts(newPodcasts)
      // Update sorted cache with animation
      withAnimation(.easeInOut(duration: 0.3)) {
        updateSortedPodcasts()
      }
    }
    .onDisappear {
      viewModel.cleanup()
      removeNotificationObservers()
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
            isLoading: false
          )
        }
        .buttonStyle(.plain)

        // Downloaded card - include actively downloading episodes in the count
        NavigationLink(destination: DownloadedEpisodesView(viewModel: viewModel)) {
          QuickAccessCard(
            icon: "arrow.down.circle.fill",
            iconColor: .green,
            title: "Downloaded",
            count: viewModel.downloadedEpisodes.count + viewModel.downloadingEpisodes.count,
            isLoading: false
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
             Text("\(viewModel.latestEpisodes.count)")
               .font(.caption)
               .foregroundColor(.secondary)
             Image(systemName: "chevron.right")
               .font(.caption)
               .foregroundColor(.secondary)
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

  // MARK: - Helper Methods

  private func updateSortedPodcasts() {
    sortedPodcasts = subscribedPodcasts.sorted { p1, p2 in
      let date1 = p1.podcastInfo.episodes.first?.pubDate ?? .distantPast
      let date2 = p2.podcastInfo.episodes.first?.pubDate ?? .distantPast
      return date1 > date2
    }
  }

  private func setupNotificationObservers() {
    // Listen for sync completion to refresh data
    syncObserver = NotificationCenter.default.addObserver(
      forName: .podcastSyncCompleted,
      object: nil,
      queue: .main
    ) { [self] _ in
      Task { @MainActor in
        // Refresh the view model data
        viewModel.setModelContext(modelContext)
        withAnimation(.easeInOut(duration: 0.3)) {
          updateSortedPodcasts()
        }
      }
    }

    // Listen for download completion to update counts
    downloadObserver = NotificationCenter.default.addObserver(
      forName: .episodeDownloadCompleted,
      object: nil,
      queue: .main
    ) { [self] _ in
      Task { @MainActor in
        viewModel.setModelContext(modelContext)
      }
    }
  }

  private func removeNotificationObservers() {
    if let observer = syncObserver {
      NotificationCenter.default.removeObserver(observer)
      syncObserver = nil
    }
    if let observer = downloadObserver {
      NotificationCenter.default.removeObserver(observer)
      downloadObserver = nil
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

          Text("\(sortedPodcasts.count)")
            .font(.subheadline)
            .foregroundColor(.secondary)
      }

      if sortedPodcasts.isEmpty {
        emptyPodcastsView
      } else {
        LazyVGrid(columns: columns, spacing: 16) {
          ForEach(sortedPodcasts) { podcast in
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
      // Fixed aspect ratio instead of GeometryReader to prevent excessive re-evaluation
      CachedAsyncImage(url: URL(string: podcast.podcastInfo.imageURL)) { image in
        image.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        Color.gray.opacity(0.2)
          .overlay(ProgressView().scaleEffect(0.5))
      }
      .aspectRatio(1, contentMode: .fit)
      .cornerRadius(10)
      .clipped()

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
      Task {
        await viewModel.refreshSavedEpisodes()
      }
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
      // Refresh only saved section
      Task { await viewModel.refreshSavedEpisodes() }
    }
  }

  private func togglePlayed(_ episode: LibraryEpisode) {
    if let model = fetchEpisodeModel(for: episode) {
      model.isCompleted.toggle()
      if !model.isCompleted {
        model.lastPlaybackPosition = 0
      }
      try? modelContext.save()
      // Refresh to update UI state
      Task { await viewModel.refreshSavedEpisodes() }
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
    
    // Update model immediately
    if let model = fetchEpisodeModel(for: episode) {
        model.localAudioPath = nil
        try? modelContext.save()
    }
    
    // Refresh list
    Task { await viewModel.refreshSavedEpisodes() }
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
      if viewModel.downloadedEpisodes.isEmpty && viewModel.downloadingEpisodes.isEmpty {
        emptyStateView
      } else {
        List {
          // Downloading Section
          if !viewModel.downloadingEpisodes.isEmpty {
            Section {
              ForEach(viewModel.downloadingEpisodes) { downloading in
                DownloadingEpisodeRow(episode: downloading)
                  .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
              }
            } header: {
              Text("Downloading")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .textCase(nil)
            }
          }

          // Downloaded Section
          if !viewModel.filteredDownloadedEpisodes.isEmpty {
            Section {
              ForEach(viewModel.filteredDownloadedEpisodes) { episode in
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
            } header: {
              if !viewModel.downloadingEpisodes.isEmpty {
                Text("Downloaded")
                  .font(.subheadline)
                  .fontWeight(.semibold)
                  .foregroundColor(.primary)
                  .textCase(nil)
              }
            }
          }
        }
        .listStyle(.plain)
        .refreshable {
          await viewModel.refreshDownloadedEpisodes()
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
      Task {
        await viewModel.refreshDownloadedEpisodes()
      }
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
      Task { await viewModel.refreshDownloadedEpisodes() }
    }
  }

  private func togglePlayed(_ episode: LibraryEpisode) {
    if let model = fetchEpisodeModel(for: episode) {
      model.isCompleted.toggle()
      if !model.isCompleted {
        model.lastPlaybackPosition = 0
      }
      try? modelContext.save()
      Task { await viewModel.refreshDownloadedEpisodes() }
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
    
    // Update model immediately
    if let model = fetchEpisodeModel(for: episode) {
        model.localAudioPath = nil
        try? modelContext.save()
    }
    
    // Refresh list
    Task { await viewModel.refreshDownloadedEpisodes() }
  }
}

// MARK: - Downloading Episode Row

struct DownloadingEpisodeRow: View {
  let episode: DownloadingEpisode

  private var statusText: String {
    switch episode.state {
    case .downloading(let progress):
      return "\(Int(progress * 100))%"
    case .finishing:
      return "Finishing..."
    default:
      return ""
    }
  }

  var body: some View {
    HStack(spacing: 12) {
      // Artwork - use CachedAsyncImage for better memory management
      CachedAsyncImage(url: URL(string: episode.imageURL ?? "")) { image in
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
      } placeholder: {
        Rectangle()
          .fill(Color.gray.opacity(0.2))
          .overlay(
            Image(systemName: "music.note")
              .foregroundColor(.gray)
          )
      }
      .frame(width: 56, height: 56)
      .cornerRadius(8)

      // Title and progress
      VStack(alignment: .leading, spacing: 4) {
        Text(episode.episodeTitle)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(2)

        Text(episode.podcastTitle)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)

        // Progress bar
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule()
              .fill(Color.blue.opacity(0.2))
              .frame(height: 4)
            Capsule()
              .fill(Color.blue)
              .frame(width: geo.size.width * episode.progress, height: 4)
          }
        }
        .frame(height: 4)
      }

      Spacer()

      // Status
      Text(statusText)
        .font(.caption)
        .foregroundColor(.blue)
        .fontWeight(.medium)
    }
    .padding(.vertical, 4)
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
