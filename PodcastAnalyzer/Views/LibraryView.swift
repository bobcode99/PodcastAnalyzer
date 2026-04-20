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

  @State private var sortedPodcasts: [PodcastGridItem] = []

  private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12)
  ]

  @State private var errorMessage: String?

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
    .navigationDestination(for: LibrarySubpageRoute.self) { route in
      switch route {
      case .saved:
        SavedEpisodesView(viewModel: viewModel, showEpisodeArtwork: showEpisodeArtwork)
      case .downloaded:
        DownloadedPodcastsGridView(viewModel: viewModel)
      case .latest:
        LatestEpisodesView(viewModel: viewModel, showEpisodeArtwork: showEpisodeArtwork)
      case .downloadingEpisodes:
        ActiveDownloadsView(viewModel: viewModel)
      }
    }
    .refreshable {
      await viewModel.refreshAllPodcasts()
    }
    .onAppear {
      viewModel.setModelContext(modelContext)
      viewModel.setPodcasts(subscribedPodcasts)
      updateSortedPodcasts()
    }
    .task {
      // Only run the initial load if it hasn't already been kicked off by setModelContext.
      // Without this guard, every tab re-appearance triggers a full refresh.
      guard !viewModel.isLoaded else { return }
      await viewModel.refreshSavedEpisodes()
      await viewModel.refreshDownloadedEpisodes()
    }
    .task {
      // Modernized notification observers using async sequences
      for await _ in NotificationCenter.default.notifications(named: .podcastSyncCompleted) {
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

    // Note: Do NOT call viewModel.cleanup() here — LibraryView is a tab root,
    // and pushing a NavigationLink fires onDisappear.  Cleaning up would cancel
    // the download-completion observer while the user is in a sub-page.
    .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "")
    }
  }

  // MARK: - Quick Access Section

  @ViewBuilder
  private var quickAccessSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        NavigationLink(value: LibrarySubpageRoute.saved) {
          QuickAccessCard(
            icon: "star.fill",
            iconColor: .yellow,
            title: "Saved",
            count: viewModel.savedEpisodes.count,
            isLoading: false
          )
        }
        .buttonStyle(.plain)

        NavigationLink(value: LibrarySubpageRoute.downloaded) {
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

      NavigationLink(value: LibrarySubpageRoute.latest) {
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
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
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
          ForEach(sortedPodcasts) { item in
            if let model = subscribedPodcasts.first(where: { $0.id == item.id }) {
              NavigationLink(value: PodcastBrowseRoute(podcastModel: model)) {
                PodcastGridCell(item: item)
              }
              .buttonStyle(.plain)
              .contentShape(Rectangle())
              .podcastContextMenu(
                podcast: model,
                modelContext: modelContext,
                onError: { errorMessage = $0 },
                onUnsubscribed: {
                  viewModel.setModelContext(modelContext)
                }
              )
            }
          }
        }
      }
    }
  }

  // MARK: - Helper Methods

  private func updateSortedPodcasts() {
    sortedPodcasts = subscribedPodcasts
      .map { PodcastGridItem(from: $0) }
      .sorted {
        switch ($0.latestEpisodeDate, $1.latestEpisodeDate) {
        case let (lhs?, rhs?): return lhs > rhs
        case (_?, nil):        return true   // dated before undated
        case (nil, _?):        return false
        case (nil, nil):       return false
        }
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
