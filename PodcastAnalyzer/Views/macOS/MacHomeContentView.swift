//
//  MacHomeContentView.swift
//  PodcastAnalyzer
//
//  macOS Home tab content — Up Next and Popular Shows
//

#if os(macOS)
import SwiftData
import SwiftUI

struct MacHomeContentView: View {
  @State private var viewModel = HomeViewModel()
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        // Up Next Section
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text("Up Next")
              .font(.title2)
              .fontWeight(.bold)
            Spacer()
          }

          if viewModel.upNextEpisodes.isEmpty {
            ContentUnavailableView(
              "No Unplayed Episodes",
              systemImage: "play.circle",
              description: Text("Subscribe to podcasts to see new episodes here")
            )
            .frame(height: 200)
          } else {
            LazyVGrid(columns: [
              GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)
            ], spacing: 16) {
              ForEach(viewModel.upNextEpisodes.prefix(8)) { episode in
                NavigationLink(value: EpisodeDetailRoute(
                  episode: episode.episodeInfo,
                  podcastTitle: episode.podcastTitle,
                  fallbackImageURL: episode.imageURL,
                  podcastLanguage: episode.language
                )) {
                  MacUpNextCard(episode: episode)
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
        .padding(.horizontal, 24)

        // Popular Shows Section
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text("Popular Shows")
              .font(.title2)
              .fontWeight(.bold)

            Spacer()

            // Region picker
            Picker("Region", selection: $viewModel.selectedRegion) {
              ForEach(Constants.podcastRegions, id: \.code) { region in
                Text(region.name).tag(region.code)
              }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
          }

          if viewModel.topPodcasts.isEmpty && !viewModel.isLoadingTopPodcasts {
            ContentUnavailableView(
              "Unable to Load",
              systemImage: "chart.line.uptrend.xyaxis",
              description: Text("Check your internet connection")
            )
            .frame(height: 200)
          } else {
            LazyVGrid(columns: [
              GridItem(.flexible(), spacing: 12),
              GridItem(.flexible(), spacing: 12)
            ], spacing: 8) {
              ForEach(Array(viewModel.topPodcasts.enumerated()), id: \.element.id) { index, podcast in
                NavigationLink(
                  value: PodcastBrowseRoute(
                    podcastName: podcast.name,
                    artworkURL: podcast.safeArtworkUrl,
                    artistName: podcast.artistName,
                    collectionId: podcast.id,
                    applePodcastURL: podcast.url
                  )
                ) {
                  MacTopPodcastRow(podcast: podcast, rank: index + 1)
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
        .padding(.horizontal, 24)
      }
      .padding(.vertical, 24)
    }
    .navigationTitle("Home")
    .onAppear {
      viewModel.setModelContext(modelContext)
    }
  }
}

// MARK: - Up Next Card

struct MacUpNextCard: View {
  let episode: LibraryEpisode

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      CachedArtworkImage(urlString: episode.imageURL, size: 160, cornerRadius: 12)

      Text(episode.podcastTitle)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      Text(episode.episodeInfo.title)
        .font(.subheadline)
        .fontWeight(.medium)
        .lineLimit(2)

      if let duration = episode.episodeInfo.formattedDuration {
        Text(duration)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 180)
    .contentShape(Rectangle())
  }
}

// MARK: - Top Podcast Row

struct MacTopPodcastRow: View {
  let podcast: AppleRSSPodcast
  let rank: Int

  var body: some View {
    HStack(spacing: 12) {
      Text("\(rank)")
        .font(.headline)
        .foregroundStyle(.secondary)
        .frame(width: 24)

      CachedArtworkImage(urlString: podcast.artworkUrl100, size: 50, cornerRadius: 8)

      VStack(alignment: .leading, spacing: 2) {
        Text(podcast.name)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(1)

        Text(podcast.artistName)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
  }
}

#endif
