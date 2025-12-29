//
//  HomeView.swift
//  PodcastAnalyzer
//
//  Home tab - shows Up Next (unplayed episodes) and Popular Shows from Apple Podcasts
//

import Combine
import SwiftData
import SwiftUI

struct HomeView: View {
  @StateObject private var viewModel = HomeViewModel()
  @Environment(\.modelContext) private var modelContext
  @State private var showRegionPicker = false

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
      .toolbarTitleDisplayMode(.inlineLarge)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button(action: { showRegionPicker = true }) {
            HStack(spacing: 4) {
              Text(viewModel.selectedRegionName)
                .font(.caption)
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

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Episode artwork
      if let url = URL(string: episode.imageURL ?? "") {
        AsyncImage(url: url) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          } else {
            Color.gray
          }
        }
        .frame(width: 140, height: 140)
        .cornerRadius(12)
        .clipped()
      } else {
        Color.gray
          .frame(width: 140, height: 140)
          .cornerRadius(12)
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

      // Duration
      if let duration = episode.episodeInfo.formattedDuration {
        Text(duration)
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
    .frame(width: 140)
  }
}

// MARK: - Top Podcast Row

struct TopPodcastRow: View {
  let podcast: AppleRSSPodcast
  let rank: Int
  @ObservedObject var viewModel: HomeViewModel

  var body: some View {
    Button(action: {
      viewModel.showPodcastPreview(podcast)
    }) {
      HStack(spacing: 12) {
        // Rank
        Text("\(rank)")
          .font(.headline)
          .foregroundColor(.secondary)
          .frame(width: 24)

        // Artwork
        AsyncImage(url: URL(string: podcast.artworkUrl100)) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          } else {
            Color.gray
          }
        }
        .frame(width: 56, height: 56)
        .cornerRadius(8)
        .clipped()

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
    .sheet(isPresented: Binding(
      get: { viewModel.selectedPodcast?.id == podcast.id },
      set: { if !$0 { viewModel.selectedPodcast = nil } }
    )) {
      if let podcast = viewModel.selectedPodcast {
        PodcastPreviewSheet(podcast: podcast, viewModel: viewModel)
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
      .navigationBarTitleDisplayMode(.inline)
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
  @ObservedObject var viewModel: HomeViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          // Artwork
          AsyncImage(url: URL(string: podcast.artworkUrl100.replacingOccurrences(of: "100x100", with: "600x600"))) { phase in
            if let image = phase.image {
              image.resizable().scaledToFit()
            } else {
              Color.gray
            }
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
      .navigationBarTitleDisplayMode(.inline)
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

  var body: some View {
    List(episodes) { episode in
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
    .navigationTitle("Up Next")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  HomeView()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
