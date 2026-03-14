//
//  LibraryView.swift
//  PodcastAnalyzer
//
//  Library tab - 2x2 grid of podcasts sorted by recent update,
//  with navigation to Saved/Downloaded sub-pages.
//

import SwiftData
import SwiftUI

struct LibraryView: View {
  @State private var viewModel = LibraryViewModel(modelContext: nil)
  @AppStorage("showEpisodeArtwork") private var showEpisodeArtwork = true
  @Environment(\.modelContext) private var modelContext

  @Query(
    filter: #Predicate<PodcastInfoModel> { $0.isSubscribed },
    sort: \.lastUpdated,
    order: .reverse
  ) private var subscribedPodcasts: [PodcastInfoModel]

  @State private var sortedPodcasts: [PodcastInfoModel] = []

  private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12)
  ]

  @State private var podcastToUnsubscribe: PodcastInfoModel?
  @State private var showUnsubscribeConfirmation = false

  var body: some View {
    ZStack {
      ScrollView {
        VStack(spacing: 24) {
          quickAccessSection
            .padding(.horizontal, 16)

          podcastsGridSection
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 40)
      }

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
      viewModel.setModelContext(modelContext)
      viewModel.setPodcasts(subscribedPodcasts)
      updateSortedPodcasts()
    }
    .task {
      await viewModel.refreshSavedEpisodes()
      await viewModel.refreshDownloadedEpisodes()
    }
    .task {
      // Modernized notification observers using async sequences
      for await _ in NotificationCenter.default.notifications(named: .podcastSyncCompleted).map({ $0 }) {
        viewModel.refreshData()
      }
    }
    .task {
      for await _ in NotificationCenter.default.notifications(named: .episodeDownloadCompleted).map({ $0 }) {
        viewModel.refreshData()
      }
    }
    .onChange(of: subscribedPodcasts) { _, newPodcasts in
      if newPodcasts.map(\.id) != sortedPodcasts.map(\.id) {
        viewModel.setPodcasts(newPodcasts)
        withAnimation(.easeInOut(duration: 0.3)) {
          updateSortedPodcasts()
        }
      }
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
      HStack(spacing: 12) {
        NavigationLink(destination: SavedEpisodesView(viewModel: viewModel, showEpisodeArtwork: showEpisodeArtwork)) {
          QuickAccessCard(
            icon: "star.fill",
            iconColor: .yellow,
            title: "Saved",
            count: viewModel.savedEpisodes.count,
            isLoading: false
          )
        }
        .buttonStyle(.plain)

        NavigationLink(destination: DownloadedPodcastsGridView(viewModel: viewModel)) {
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

      NavigationLink(destination: LatestEpisodesView(viewModel: viewModel, showEpisodeArtwork: showEpisodeArtwork)) {
        HStack {
          HStack(spacing: 8) {
            Image(systemName: "clock.fill")
              .font(.system(size: 16))
              .foregroundStyle(.blue)
            Text("Latest Episodes")
              .font(.subheadline)
              .fontWeight(.medium)
              .foregroundStyle(.primary)
          }

          Spacer()

          HStack(spacing: 4) {
             Text("\(viewModel.latestEpisodes.count)")
               .font(.caption)
               .foregroundStyle(.secondary)
             Image(systemName: "chevron.right")
               .font(.caption)
               .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
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

          Text("\(sortedPodcasts.count)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
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
            .contentShape(Rectangle())
            .contextMenu {
              NavigationLink(destination: EpisodeListView(podcastModel: podcast)) {
                Label("View Episodes", systemImage: "list.bullet")
              }

              Divider()

              Button {
                Task {
                  await refreshPodcast(podcast)
                }
              } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
              }

              Button {
                PlatformClipboard.string = podcast.podcastInfo.rssUrl
              } label: {
                Label("Copy RSS URL", systemImage: "doc.on.doc")
              }

              Divider()

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

  // MARK: - Helper Methods

  private func updateSortedPodcasts() {
    sortedPodcasts = subscribedPodcasts.sorted { p1, p2 in
      let date1 = p1.podcastInfo.episodes.first?.pubDate ?? .distantPast
      let date2 = p2.podcastInfo.episodes.first?.pubDate ?? .distantPast
      return date1 > date2
    }
  }

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
        .foregroundStyle(.secondary)
      Text("No Subscriptions")
        .font(.headline)
      Text("Search and subscribe to podcasts to build your library")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }
}

#Preview {
  LibraryView()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
