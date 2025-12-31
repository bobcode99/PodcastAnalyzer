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

// MARK: - Library View

struct LibraryView: View {
  @StateObject private var viewModel: LibraryViewModel
  @Environment(\.modelContext) private var modelContext

  // Grid layout: 2 columns
  private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12)
  ]

  // Context menu state
  @State private var podcastToUnsubscribe: PodcastInfoModel?
  @State private var showUnsubscribeConfirmation = false

  init() {
    _viewModel = StateObject(wrappedValue: LibraryViewModel(modelContext: nil))
  }

  var body: some View {
    NavigationStack {
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
      .overlay {
        if viewModel.isLoading {
          ProgressView()
            .scaleEffect(1.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground).opacity(0.5))
        }
      }
    }
    .onAppear {
      viewModel.setModelContext(modelContext)
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
            count: viewModel.savedEpisodes.count
          )
        }
        .buttonStyle(.plain)

        // Downloaded card
        NavigationLink(destination: DownloadedEpisodesView(viewModel: viewModel)) {
          QuickAccessCard(
            icon: "arrow.down.circle.fill",
            iconColor: .green,
            title: "Downloaded",
            count: viewModel.downloadedEpisodes.count
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
        .background(Color(.systemGray6))
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

        Text("\(viewModel.podcastsSortedByRecentUpdate.count)")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      if viewModel.podcastsSortedByRecentUpdate.isEmpty {
        emptyPodcastsView
      } else {
        LazyVGrid(columns: columns, spacing: 16) {
          ForEach(viewModel.podcastsSortedByRecentUpdate) { podcast in
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
                UIPasteboard.general.string = podcast.podcastInfo.rssUrl
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

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: icon)
          .font(.system(size: 20))
          .foregroundColor(iconColor)

        Spacer()

        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundColor(.secondary)
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
    .background(Color(.systemGray6))
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
  @ObservedObject var viewModel: LibraryViewModel

  var body: some View {
    Group {
      if viewModel.savedEpisodes.isEmpty {
        emptyStateView
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
    .navigationTitle("Saved")
    .navigationBarTitleDisplayMode(.inline)
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
}

// MARK: - Downloaded Episodes View (Sub-page)

struct DownloadedEpisodesView: View {
  @ObservedObject var viewModel: LibraryViewModel

  var body: some View {
    Group {
      if viewModel.downloadedEpisodes.isEmpty {
        emptyStateView
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
    .navigationTitle("Downloaded")
    .navigationBarTitleDisplayMode(.inline)
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
}

// MARK: - Latest Episodes View (Sub-page)

struct LatestEpisodesView: View {
  @ObservedObject var viewModel: LibraryViewModel

  var body: some View {
    Group {
      if viewModel.latestEpisodes.isEmpty {
        emptyStateView
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
    .navigationTitle("Latest Episodes")
    .navigationBarTitleDisplayMode(.inline)
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
}

// MARK: - Library Episode Row View

struct LibraryEpisodeRowView: View {
  let episode: LibraryEpisode
  @Environment(\.modelContext) private var modelContext
  @State private var hasAIAnalysis: Bool = false

  private var plainDescription: String? {
    guard let desc = episode.episodeInfo.podcastEpisodeDescription else { return nil }
    let stripped = desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return stripped.isEmpty ? nil : stripped
  }

  private func checkAIAnalysis() {
    guard let audioURL = episode.episodeInfo.audioURL else { return }
    let descriptor = FetchDescriptor<EpisodeAIAnalysis>(
      predicate: #Predicate { $0.episodeAudioURL == audioURL }
    )
    if let model = try? modelContext.fetch(descriptor).first {
      hasAIAnalysis =
        model.hasFullAnalysis || model.hasSummary || model.hasEntities
        || model.hasHighlights
        || (model.qaHistoryJSON != nil && !model.qaHistoryJSON!.isEmpty)
    }
  }

  var body: some View {
    HStack(spacing: 12) {
      // Episode artwork - using CachedAsyncImage for better performance
      CachedArtworkImage(urlString: episode.imageURL, size: 60, cornerRadius: 8)

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

        // Date, duration, and status indicators
        HStack(spacing: 6) {
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

          if hasAIAnalysis {
            Image(systemName: "sparkles")
              .font(.system(size: 10))
              .foregroundColor(.orange)
          }

          if episode.isCompleted {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 10))
              .foregroundColor(.green)
          }
        }
      }
    }
    .padding(.vertical, 4)
    .onAppear { checkAIAnalysis() }
  }
}

#Preview {
  LibraryView()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
