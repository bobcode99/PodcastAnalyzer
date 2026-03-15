//
//  DownloadedViews.swift
//  PodcastAnalyzer
//
//  Downloaded podcasts grid, cells, episode list, and downloading row for Library.
//

import SwiftData
import SwiftUI

// MARK: - Downloaded Podcasts Grid View (Sub-page)

struct DownloadedPodcastsGridView: View {
  @Bindable var viewModel: LibraryViewModel
  @Environment(\.modelContext) private var modelContext

  private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12)
  ]

  var body: some View {
    Group {
      if viewModel.podcastsWithDownloads.isEmpty {
        VStack(spacing: 16) {
          Image(systemName: "arrow.down.circle")
            .font(.system(size: 50))
            .foregroundStyle(.secondary)
          Text("No Downloads")
            .font(.headline)
          Text("Downloaded episodes will appear here")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVGrid(columns: columns, spacing: 16) {
            ForEach(viewModel.podcastsWithDownloads, id: \.podcast.id) { item in
              NavigationLink(destination: EpisodeListView(
                podcastModel: item.podcast,
                initialFilter: .downloaded
              )) {
                DownloadedPodcastCell(
                  podcast: item.podcast,
                  downloadCount: item.downloadCount
                )
              }
              .buttonStyle(.plain)
              .contentShape(Rectangle())
            }
          }
          .padding(.horizontal)
        }
      }
    }
    .navigationTitle("Downloaded")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .refreshable {
      await viewModel.refreshDownloadedEpisodes()
    }
    .onAppear {
      viewModel.setModelContext(modelContext)
    }
    .task {
      await viewModel.refreshDownloadedEpisodes()
    }
  }
}

// MARK: - Downloaded Podcast Cell

struct DownloadedPodcastCell: View {
  let podcast: PodcastInfoModel
  let downloadCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      CachedAsyncImage(url: URL(string: podcast.podcastInfo.imageURL)) { image in
        image.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        Color.gray.opacity(0.2)
          .overlay(ProgressView().scaleEffect(0.5))
      }
      .aspectRatio(1, contentMode: .fit)
      .clipShape(.rect(cornerRadius: 10))
      .clipped()

      Text(podcast.podcastInfo.title)
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(2)
        .foregroundStyle(.primary)

      Text("\(downloadCount) downloaded")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Downloaded Episodes View (Sub-page)

struct DownloadedEpisodesView: View {
  @Bindable var viewModel: LibraryViewModel
  let showEpisodeArtwork: Bool
  @Environment(\.modelContext) private var modelContext
  @State private var episodeToDelete: LibraryEpisode?
  @State private var showDeleteConfirmation = false
  @State private var episodeModels: [String: EpisodeDownloadModel] = [:]
  @State private var refreshTask: Task<Void, Never>?

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
                .foregroundStyle(.primary)
                .textCase(nil)
            }
          }

          // Downloaded Section
          if !viewModel.filteredDownloadedEpisodes.isEmpty {
            Section {
              ForEach(viewModel.filteredDownloadedEpisodes) { episode in
                EpisodeRowView(
                  libraryEpisode: episode,
                  episodeModel: episodeModels[episode.id],
                  showArtwork: showEpisodeArtwork,
                  onToggleStar: {
                    LibraryEpisodeActions.toggleStar(episode, episodeModels: &episodeModels, context: modelContext)
                    refreshTask?.cancel()
                    refreshTask = Task { await viewModel.refreshDownloadedEpisodes() }
                  },
                  onDownload: { LibraryEpisodeActions.downloadEpisode(episode) },
                  onDeleteRequested: {
                    episodeToDelete = episode
                    showDeleteConfirmation = true
                  },
                  onTogglePlayed: {
                    LibraryEpisodeActions.togglePlayed(episode, episodeModels: &episodeModels, context: modelContext)
                    refreshTask?.cancel()
                    refreshTask = Task { await viewModel.refreshDownloadedEpisodes() }
                  }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
              }
            } header: {
              if !viewModel.downloadingEpisodes.isEmpty {
                Text("Downloaded")
                  .font(.subheadline)
                  .fontWeight(.semibold)
                  .foregroundStyle(.primary)
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
      episodeModels = LibraryEpisodeActions.batchFetchEpisodeModels(from: modelContext)
    }
    .task {
      await viewModel.refreshDownloadedEpisodes()
    }
    .onDisappear {
      refreshTask?.cancel()
    }
    .confirmationDialog(
      "Delete Download",
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let episode = episodeToDelete {
          LibraryEpisodeActions.deleteDownload(episode, episodeModels: episodeModels, context: modelContext)
          refreshTask?.cancel()
          refreshTask = Task { await viewModel.refreshDownloadedEpisodes() }
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
        .foregroundStyle(.secondary)
      Text("No Downloads")
        .font(.headline)
      Text("Downloaded episodes will appear here for offline listening")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
      CachedAsyncImage(url: URL(string: episode.imageURL ?? "")) { image in
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
      } placeholder: {
        Rectangle()
          .fill(Color.gray.opacity(0.2))
          .overlay(
            Image(systemName: "music.note")
              .foregroundStyle(.gray)
          )
      }
      .frame(width: 56, height: 56)
      .clipShape(.rect(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 4) {
        Text(episode.episodeTitle)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(2)

        Text(episode.podcastTitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        ProgressView(value: episode.progress)
          .progressViewStyle(.linear)
          .tint(.blue)
          .frame(height: 4)
      }

      Spacer()

      Text(statusText)
        .font(.caption)
        .foregroundStyle(.blue)
        .fontWeight(.medium)
    }
    .padding(.vertical, 4)
  }
}
