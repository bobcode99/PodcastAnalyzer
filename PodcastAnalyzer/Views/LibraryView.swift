//
//  LibraryView.swift
//  PodcastAnalyzer
//
//  Library tab - shows subscribed podcasts, saved, downloaded, and latest episodes
//

import SwiftData
import SwiftUI
import ZMarkupParser

// MARK: - Library Filter Enum

enum LibraryFilter: String, CaseIterable {
  case podcasts = "Podcasts"
  case saved = "Saved"
  case downloaded = "Downloaded"
  case latest = "Latest"

  var icon: String {
    switch self {
    case .podcasts: return "square.stack.fill"
    case .saved: return "star.fill"
    case .downloaded: return "arrow.down.circle.fill"
    case .latest: return "clock.fill"
    }
  }
}

// MARK: - Library View

struct LibraryView: View {
  @StateObject private var viewModel: LibraryViewModel
  @Environment(\.modelContext) private var modelContext
  @State private var selectedFilter: LibraryFilter = .podcasts

  init() {
    _viewModel = StateObject(wrappedValue: LibraryViewModel(modelContext: nil))
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Filter chips
        filterBar
          .padding(.horizontal, 16)
          .padding(.vertical, 8)

        // Content based on filter
        Group {
          if viewModel.isLoading {
            ProgressView()
              .scaleEffect(1.5)
              .frame(maxHeight: .infinity)
          } else if let error = viewModel.error {
            errorView(error)
          } else {
            contentForFilter
          }
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
      .toolbarTitleDisplayMode(.inlineLarge)
      .refreshable {
        await viewModel.refreshAllPodcasts()
      }
    }
    .onAppear {
      viewModel.setModelContext(modelContext)
    }
  }

  // MARK: - Filter Bar

  @ViewBuilder
  private var filterBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(LibraryFilter.allCases, id: \.self) { filter in
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
      }
    }
  }

  // MARK: - Content Views

  @ViewBuilder
  private var contentForFilter: some View {
    switch selectedFilter {
    case .podcasts:
      podcastsListView
    case .saved:
      savedEpisodesView
    case .downloaded:
      downloadedEpisodesView
    case .latest:
      latestEpisodesView
    }
  }

  @ViewBuilder
  private var podcastsListView: some View {
    if viewModel.podcastInfoModelList.isEmpty {
      emptyPodcastsView
    } else {
      List(viewModel.podcastInfoModelList) { model in
        NavigationLink(destination: EpisodeListView(podcastModel: model)) {
          LibraryPodcastRowView(podcast: model.podcastInfo)
        }
      }
      .listStyle(.plain)
    }
  }

  @ViewBuilder
  private var savedEpisodesView: some View {
    if viewModel.savedEpisodes.isEmpty {
      emptyStateView(
        icon: "star",
        title: "No Saved Episodes",
        message: "Star episodes to save them here"
      )
    } else {
      List(viewModel.savedEpisodes) { episode in
        NavigationLink(
          destination: EpisodeDetailView(
            episode: episode.episodeInfo,
            podcastTitle: episode.podcastTitle,
            fallbackImageURL: episode.imageURL,
            podcastLanguage: episode.language
          )
        ) {
          LibraryEpisodeRowView(episode: episode)
        }
      }
      .listStyle(.plain)
    }
  }

  @ViewBuilder
  private var downloadedEpisodesView: some View {
    if viewModel.downloadedEpisodes.isEmpty {
      emptyStateView(
        icon: "arrow.down.circle",
        title: "No Downloads",
        message: "Downloaded episodes will appear here"
      )
    } else {
      List(viewModel.downloadedEpisodes) { episode in
        NavigationLink(
          destination: EpisodeDetailView(
            episode: episode.episodeInfo,
            podcastTitle: episode.podcastTitle,
            fallbackImageURL: episode.imageURL,
            podcastLanguage: episode.language
          )
        ) {
          LibraryEpisodeRowView(episode: episode)
        }
      }
      .listStyle(.plain)
    }
  }

  @ViewBuilder
  private var latestEpisodesView: some View {
    if viewModel.latestEpisodes.isEmpty {
      emptyStateView(
        icon: "clock",
        title: "No Episodes",
        message: "Subscribe to podcasts to see latest episodes"
      )
    } else {
      List(viewModel.latestEpisodes) { episode in
        NavigationLink(
          destination: EpisodeDetailView(
            episode: episode.episodeInfo,
            podcastTitle: episode.podcastTitle,
            fallbackImageURL: episode.imageURL,
            podcastLanguage: episode.language
          )
        ) {
          LibraryEpisodeRowView(episode: episode)
        }
      }
      .listStyle(.plain)
    }
  }

  @ViewBuilder
  private var emptyPodcastsView: some View {
    VStack(spacing: 12) {
      Image(systemName: "square.stack.3d.up")
        .font(.system(size: 50))
        .foregroundColor(.gray)
      Text("No Subscriptions")
        .font(.headline)
      Text("Search and subscribe to podcasts to build your library")
        .font(.caption)
        .foregroundColor(.gray)
        .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxHeight: .infinity)
  }

  @ViewBuilder
  private func emptyStateView(icon: String, title: String, message: String) -> some View {
    VStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 50))
        .foregroundColor(.gray)
      Text(title)
        .font(.headline)
      Text(message)
        .font(.caption)
        .foregroundColor(.gray)
        .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxHeight: .infinity)
  }

  @ViewBuilder
  private func errorView(_ error: String) -> some View {
    VStack {
      Image(systemName: "exclamationmark.circle")
        .font(.largeTitle)
        .foregroundColor(.red)
      Text("Error")
        .font(.headline)
      Text(error)
        .font(.caption)
        .foregroundColor(.gray)
    }
    .frame(maxHeight: .infinity)
  }
}

// MARK: - Library Podcast Row View

struct LibraryPodcastRowView: View {
  let podcast: PodcastInfo
  @State private var descriptionView: AnyView?

  var body: some View {
    HStack(spacing: 12) {
      // Podcast artwork
      if let url = URL(string: podcast.imageURL) {
        AsyncImage(url: url) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          } else if phase.error != nil {
            Color.gray
          } else {
            ProgressView()
          }
        }
        .frame(width: 60, height: 60)
        .cornerRadius(8)
        .clipped()
      } else {
        Color.gray
          .frame(width: 60, height: 60)
          .cornerRadius(8)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(podcast.title)
          .font(.headline)
          .lineLimit(1)

        if let view = descriptionView {
          view
            .lineLimit(2)
        } else if let description = podcast.podcastInfoDescription {
          Text(description.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
            .font(.caption)
            .foregroundColor(.gray)
            .lineLimit(2)
        }

        Text("\(podcast.episodes.count) episodes")
          .font(.caption2)
          .foregroundColor(.blue)
      }
    }
    .padding(.vertical, 4)
    .onAppear {
      parseDescription()
    }
  }

  private func parseDescription() {
    guard let html = podcast.podcastInfoDescription, !html.isEmpty else { return }

    let rootStyle = MarkupStyle(
      font: MarkupStyleFont(size: 12),
      foregroundColor: MarkupStyleColor(color: UIColor.secondaryLabel)
    )

    let parser = ZHTMLParserBuilder.initWithDefault()
      .set(rootStyle: rootStyle)
      .build()

    Task {
      let attributedString = parser.render(html)

      await MainActor.run {
        descriptionView = AnyView(
          HTMLTextView(attributedString: attributedString)
        )
      }
    }
  }
}

// MARK: - Library Episode Row View

struct LibraryEpisodeRowView: View {
  let episode: LibraryEpisode

  private var plainDescription: String? {
    guard let desc = episode.episodeInfo.podcastEpisodeDescription else { return nil }
    let stripped = desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return stripped.isEmpty ? nil : stripped
  }

  var body: some View {
    HStack(spacing: 12) {
      // Episode artwork
      if let url = URL(string: episode.imageURL ?? "") {
        AsyncImage(url: url) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          } else {
            Color.gray
          }
        }
        .frame(width: 60, height: 60)
        .cornerRadius(8)
        .clipped()
      } else {
        Color.gray
          .frame(width: 60, height: 60)
          .cornerRadius(8)
      }

      VStack(alignment: .leading, spacing: 4) {
        // Podcast title
        Text(episode.podcastTitle)
          .font(.caption)
          .foregroundColor(.secondary)

        // Episode title
        Text(episode.episodeInfo.title)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(2)

        // Date and duration
        HStack(spacing: 8) {
          if let date = episode.episodeInfo.pubDate {
            Text(date.formatted(date: .abbreviated, time: .omitted))
              .font(.caption2)
              .foregroundColor(.secondary)
          }

          if let duration = episode.episodeInfo.formattedDuration {
            Text(duration)
              .font(.caption2)
              .foregroundColor(.secondary)
          }

          // Status indicators
          if episode.isDownloaded {
            Image(systemName: "arrow.down.circle.fill")
              .font(.system(size: 10))
              .foregroundColor(.green)
          }

          if episode.isStarred {
            Image(systemName: "star.fill")
              .font(.system(size: 10))
              .foregroundColor(.yellow)
          }
        }
      }
    }
    .padding(.vertical, 4)
  }
}

#Preview {
  LibraryView()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
