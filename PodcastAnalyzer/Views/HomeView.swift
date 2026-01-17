//
//  HomeView.swift
//  PodcastAnalyzer
//
//  Home tab - shows Up Next (unplayed episodes) and Popular Shows from Apple Podcasts
//

import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct HomeView: View {
  @State private var viewModel = HomeViewModel()
  @Environment(\.modelContext) private var modelContext
  @State private var showRegionPicker = false

  // Context menu state for popular shows
  @State private var podcastToSubscribe: AppleRSSPodcast?
  @State private var showSubscribeSheet = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          // Up Next Section
          upNextSection

          // Popular Shows Section
          popularShowsSection
        }
        .padding(.vertical)
      }
      .navigationTitle(Constants.homeString)
      .platformToolbarTitleDisplayMode()
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button(action: { showRegionPicker = true }) {
            HStack(spacing: 4) {
              Text(viewModel.selectedRegionFlag)
                .font(.title3)
              Image(systemName: "chevron.down")
                .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
          }
        }
      }
      .sheet(isPresented: $showRegionPicker) {
        RegionPickerSheet(
          selectedRegion: $viewModel.selectedRegion,
          isPresented: $showRegionPicker
        )
        .presentationDetents([.medium])
      }
      .refreshable {
        await viewModel.refresh()
      }
    }
    .onAppear {
      // This is the key: set the context once
      viewModel.setModelContext(modelContext)
    }
  }

  // MARK: - Up Next Section

  @ViewBuilder
  private var upNextSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Up Next")
          .font(.title2)
          .fontWeight(.bold)

        Spacer()

        if !viewModel.upNextEpisodes.isEmpty {
          NavigationLink(destination: UpNextListView(episodes: viewModel.upNextEpisodes)) {
            Text("See All")
              .font(.subheadline)
              .foregroundColor(.blue)
          }
        }
      }
      .padding(.horizontal)

      if viewModel.upNextEpisodes.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "play.circle")
            .font(.system(size: 40))
            .foregroundColor(.gray)
          Text("No unplayed episodes")
            .font(.subheadline)
            .foregroundColor(.secondary)
          Text("Subscribe to podcasts to see new episodes here")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 12) {
            ForEach(viewModel.upNextEpisodes.prefix(10)) { episode in
              NavigationLink(
                destination: EpisodeDetailView(
                  episode: episode.episodeInfo,
                  podcastTitle: episode.podcastTitle,
                  fallbackImageURL: episode.imageURL,
                  podcastLanguage: episode.language
                )
              ) {
                UpNextCard(episode: episode)
              }
              .buttonStyle(.plain)
              .contextMenu {
                UpNextContextMenu(
                  episode: episode,
                  viewModel: viewModel
                )
              }
            }
          }
          .padding(.horizontal)
        }
      }
    }
  }

  // MARK: - Popular Shows Section

  @ViewBuilder
  private var popularShowsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Popular Shows")
          .font(.title2)
          .fontWeight(.bold)

        Spacer()

        if viewModel.isLoadingTopPodcasts {
          ProgressView()
            .scaleEffect(0.8)
        }
      }
      .padding(.horizontal)

      if viewModel.topPodcasts.isEmpty && !viewModel.isLoadingTopPodcasts {
        VStack(spacing: 8) {
          Image(systemName: "chart.line.uptrend.xyaxis")
            .font(.system(size: 40))
            .foregroundColor(.gray)
          Text("Unable to load popular shows")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
      } else {
        LazyVStack(spacing: 0) {
          ForEach(Array(viewModel.topPodcasts.enumerated()), id: \.element.id) { index, podcast in
            TopPodcastRow(podcast: podcast, rank: index + 1, viewModel: viewModel)
          }
        }
        .padding(.horizontal)
      }
    }
  }
}

// MARK: - Up Next Card

struct UpNextCard: View {
  let episode: LibraryEpisode
  @Environment(\.modelContext) private var modelContext
  @State private var statusObserver: EpisodeStatusObserver?

  private var audioManager: EnhancedAudioManager { EnhancedAudioManager.shared }

  private func playEpisode() {
    guard episode.episodeInfo.audioURL != nil else { return }
    guard let observer = statusObserver else { return }

    let playbackEpisode = PlaybackEpisode(
      id: EpisodeKeyUtils.makeKey(podcastTitle: episode.podcastTitle, episodeTitle: episode.episodeInfo.title),
      title: episode.episodeInfo.title,
      podcastTitle: episode.podcastTitle,
      audioURL: observer.playbackURL,
      imageURL: episode.imageURL,
      episodeDescription: episode.episodeInfo.podcastEpisodeDescription,
      pubDate: episode.episodeInfo.pubDate,
      duration: episode.episodeInfo.duration,
      guid: episode.episodeInfo.guid
    )

    audioManager.play(
      episode: playbackEpisode,
      audioURL: observer.playbackURL,
      startTime: episode.lastPlaybackPosition,
      imageURL: episode.imageURL ?? "",
      useDefaultSpeed: episode.lastPlaybackPosition == 0
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Episode artwork - using CachedAsyncImage for better performance
      ZStack(alignment: .bottomTrailing) {
        CachedArtworkImage(urlString: episode.imageURL, size: 140, cornerRadius: 12)

        // Status icons overlay (reactive)
        if let observer = statusObserver {
          EpisodeStatusIconsCompact(
            isStarred: episode.isStarred,
            isDownloaded: observer.isDownloaded,
            hasTranscript: observer.hasTranscript,
            hasAIAnalysis: observer.hasAIAnalysis,
            isDownloading: observer.isDownloading,
            downloadProgress: observer.downloadProgress,
            isTranscribing: observer.isTranscribing
          )
        }
      }

      // Podcast title
      Text(episode.podcastTitle)
        .font(.caption)
        .foregroundColor(.secondary)
        .lineLimit(1)

      // Episode title
      Text(episode.episodeInfo.title)
        .font(.subheadline)
        .fontWeight(.medium)
        .lineLimit(2)
        .multilineTextAlignment(.leading)

      // Play button with progress (reactive for live updates)
      ReactiveEpisodePlayButton(
        episode: episode,
        action: playEpisode
      )
    }
    .frame(width: 140)
    .onAppear {
      if statusObserver == nil {
        statusObserver = EpisodeStatusObserver(episode: episode)
      }
      statusObserver?.setModelContext(modelContext)
    }
    .onDisappear {
      statusObserver?.cleanup()
    }
  }
}

// MARK: - Up Next Context Menu

struct UpNextContextMenu: View {
  let episode: LibraryEpisode
  var viewModel: HomeViewModel

  private var downloadManager: DownloadManager { DownloadManager.shared }
  private var audioManager: EnhancedAudioManager { EnhancedAudioManager.shared }

  private var statusChecker: EpisodeStatusChecker {
    EpisodeStatusChecker(episode: episode)
  }

  private var downloadState: DownloadState { statusChecker.downloadState }
  private var isDownloaded: Bool { statusChecker.isDownloaded }

  var body: some View {
    // Go to Show
    if let podcastModel = viewModel.findPodcastModel(for: episode.podcastTitle) {
      NavigationLink(destination: EpisodeListView(podcastModel: podcastModel)) {
        Label("Go to Show", systemImage: "square.stack")
      }

      Divider()
    }

    // Star/Unstar
    Button {
      viewModel.toggleStar(for: episode)
    } label: {
      Label(
        episode.isStarred ? "Unstar" : "Star",
        systemImage: episode.isStarred ? "star.fill" : "star"
      )
    }

    // Mark as Played/Unplayed
    Button {
      viewModel.togglePlayed(for: episode)
    } label: {
      Label(
        episode.isCompleted ? "Mark as Unplayed" : "Mark as Played",
        systemImage: episode.isCompleted ? "arrow.counterclockwise" : "checkmark.circle"
      )
    }

    Divider()

    // Play Next
    if let audioURL = episode.episodeInfo.audioURL {
      Button {
        let playbackEpisode = PlaybackEpisode(
          id: episode.id,
          title: episode.episodeInfo.title,
          podcastTitle: episode.podcastTitle,
          audioURL: audioURL,
          imageURL: episode.imageURL,
          episodeDescription: episode.episodeInfo.podcastEpisodeDescription,
          pubDate: episode.episodeInfo.pubDate,
          duration: episode.episodeInfo.duration,
          guid: episode.episodeInfo.guid
        )
        audioManager.playNext(playbackEpisode)
      } label: {
        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
      }

      Divider()
    }

    // Download actions
    switch downloadState {
    case .notDownloaded:
      Button {
        downloadManager.downloadEpisode(
          episode: episode.episodeInfo,
          podcastTitle: episode.podcastTitle,
          language: episode.language
        )
      } label: {
        Label("Download", systemImage: "arrow.down.circle")
      }

    case .downloading:
      Button {
        downloadManager.cancelDownload(
          episodeTitle: episode.episodeInfo.title,
          podcastTitle: episode.podcastTitle
        )
      } label: {
        Label("Cancel Download", systemImage: "xmark.circle")
      }

    case .finishing:
      Label("Saving...", systemImage: "arrow.down.circle.dotted")

    case .downloaded:
      Button(role: .destructive) {
        downloadManager.deleteDownload(
          episodeTitle: episode.episodeInfo.title,
          podcastTitle: episode.podcastTitle
        )
      } label: {
        Label("Delete Download", systemImage: "trash")
      }

    case .failed:
      Button {
        downloadManager.downloadEpisode(
          episode: episode.episodeInfo,
          podcastTitle: episode.podcastTitle,
          language: episode.language
        )
      } label: {
        Label("Retry Download", systemImage: "arrow.clockwise")
      }
    }

    Divider()

    // Share
    if let audioURL = episode.episodeInfo.audioURL, let url = URL(string: audioURL) {
      Button {
        PlatformShareSheet.share(url: url)
      } label: {
        Label("Share Episode", systemImage: "square.and.arrow.up")
      }
    }
  }
}

// MARK: - Top Podcast Row

struct TopPodcastRow: View {
  let podcast: AppleRSSPodcast
  let rank: Int
  var viewModel: HomeViewModel

  var body: some View {
    NavigationLink(destination: EpisodeListView(
      podcastName: podcast.name,
      podcastArtwork: podcast.artworkUrl100,
      artistName: podcast.artistName,
      collectionId: podcast.id,
      applePodcastUrl: podcast.url
    )) {
      HStack(spacing: 12) {
        // Rank
        Text("\(rank)")
          .font(.headline)
          .foregroundColor(.secondary)
          .frame(width: 24)

        // Artwork - using CachedAsyncImage for better performance
        CachedArtworkImage(urlString: podcast.artworkUrl100, size: 56, cornerRadius: 8)

        // Info
        VStack(alignment: .leading, spacing: 2) {
          Text(podcast.name)
            .font(.subheadline)
            .fontWeight(.medium)
            .lineLimit(1)
            .foregroundColor(.primary)

          Text(podcast.artistName)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)

          if let genres = podcast.genres, let first = genres.first {
            Text(first.name)
              .font(.caption2)
              .foregroundColor(.blue)
          }
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(.vertical, 8)
    }
    .buttonStyle(.plain)
    .contextMenu {
      // View episodes
      NavigationLink(destination: EpisodeListView(
        podcastName: podcast.name,
        podcastArtwork: podcast.artworkUrl100,
        artistName: podcast.artistName,
        collectionId: podcast.id,
        applePodcastUrl: podcast.url
      )) {
        Label("View Episodes", systemImage: "list.bullet")
      }

      Divider()

      // Subscribe
      if viewModel.isAlreadySubscribed(podcast) {
        Label("Already Subscribed", systemImage: "checkmark.circle.fill")
          .foregroundColor(.green)
      } else {
        Button {
          viewModel.subscribeToPodcast(podcast)
        } label: {
          Label("Subscribe", systemImage: "plus.circle")
        }
      }

      // View on Apple Podcasts
      Link(destination: URL(string: podcast.url)!) {
        Label("View on Apple Podcasts", systemImage: "link")
      }

      Divider()

      // Copy name
      Button {
        PlatformClipboard.string = podcast.name
      } label: {
        Label("Copy Name", systemImage: "doc.on.doc")
      }

      // Share
      Button {
        PlatformShareSheet.share(url: URL(string: podcast.url)!)
      } label: {
        Label("Share", systemImage: "square.and.arrow.up")
      }
    }

    Divider()
  }
}

// MARK: - Region Picker Sheet

struct RegionPickerSheet: View {
  @Binding var selectedRegion: String
  @Binding var isPresented: Bool

  var body: some View {
    NavigationStack {
      List {
        ForEach(Constants.podcastRegions, id: \.code) { region in
          Button(action: {
            selectedRegion = region.code
            isPresented = false
          }) {
            HStack {
              Text(region.flag)
                .font(.title2)
              Text(region.name)
                .foregroundColor(.primary)

              Spacer()

              if selectedRegion == region.code {
                Image(systemName: "checkmark")
                  .foregroundColor(.blue)
              }
            }
          }
        }
      }
      .navigationTitle("Select Region")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            isPresented = false
          }
        }
      }
    }
  }
}

// MARK: - Podcast Preview Sheet

struct PodcastPreviewSheet: View {
  let podcast: AppleRSSPodcast
  var viewModel: HomeViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          // Artwork
          CachedAsyncImage(url: URL(string: podcast.artworkUrl100.replacingOccurrences(of: "100x100", with: "600x600"))) { image in
              image.resizable().scaledToFit()
          } placeholder: {
              Color.gray
          }
          .frame(width: 200, height: 200)
          .cornerRadius(16)
          .shadow(radius: 8)

          // Title and Artist
          VStack(spacing: 4) {
            Text(podcast.name)
              .font(.title2)
              .fontWeight(.bold)
              .multilineTextAlignment(.center)

            Text(podcast.artistName)
              .font(.subheadline)
              .foregroundColor(.secondary)
          }

          // Genres
          if let genres = podcast.genres {
            HStack {
              ForEach(genres, id: \.genreId) { genre in
                Text(genre.name)
                  .font(.caption)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 4)
                  .background(Color.blue.opacity(0.15))
                  .foregroundColor(.blue)
                  .cornerRadius(12)
              }
            }
          }

          // Subscribe Button
          if viewModel.isAlreadySubscribed(podcast) {
            HStack {
              Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
              Text("Already Subscribed")
                .font(.headline)
                .foregroundColor(.green)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green.opacity(0.15))
            .cornerRadius(12)
            .padding(.horizontal)
          } else if viewModel.isSubscribing {
            ProgressView("Subscribing...")
          } else if viewModel.subscriptionError != nil {
            VStack(spacing: 8) {
              Text("Failed to subscribe")
                .foregroundColor(.red)
              Button("Try Again") {
                viewModel.subscribeToPodcast(podcast)
              }
            }
          } else {
            Button(action: {
              viewModel.subscribeToPodcast(podcast)
            }) {
              Label("Subscribe", systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)
          }

          // View on Apple Podcasts
          Link(destination: URL(string: podcast.url)!) {
            Label("View on Apple Podcasts", systemImage: "link")
              .font(.subheadline)
          }
          .padding(.top, 8)
        }
        .padding()
      }
      .navigationTitle("Podcast")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
            dismiss()
          }
        }
      }
      .onChange(of: viewModel.subscriptionSuccess) { _, success in
        if success {
          dismiss()
        }
      }
    }
  }
}

// MARK: - Up Next List View

struct UpNextListView: View {
  let episodes: [LibraryEpisode]
  @Environment(\.modelContext) private var modelContext
  @State private var viewModel = HomeViewModel()
  @State private var episodeToDelete: LibraryEpisode?
  @State private var showDeleteConfirmation = false

  var body: some View {
    List(episodes) { episode in
      EpisodeRowView(
        libraryEpisode: episode,
        episodeModel: fetchEpisodeModel(for: episode),
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
    .navigationTitle("Up Next")
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
  }

  private func togglePlayed(_ episode: LibraryEpisode) {
    if let model = fetchEpisodeModel(for: episode) {
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
  }
}

#Preview {
  HomeView()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
