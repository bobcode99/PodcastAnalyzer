//
//  SearchView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/23.
//

import Combine  // For the service publishers
import SwiftUI

struct PodcastSearchView: View {
    @StateObject private var viewModel = PodcastSearchViewModel()

    var body: some View {
        NavigationStack {  // Like a main layout with navigation
            VStack {
                // Search bar
                TextField("Search podcasts...", text: $viewModel.searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                    .onSubmit {
                        viewModel.performSearch()
                    }

                if viewModel.isLoading {
                    ProgressView("Searching podcasts...")
                        .padding()
                } else if viewModel.podcasts.isEmpty && !viewModel.searchText.isEmpty {
                    Text("No podcasts found")
                        .foregroundColor(.secondary)
                        .padding()
                }

                // List of podcasts (like a table in Thymeleaf or JSP)
                List(viewModel.podcasts) { podcast in
                    PodcastRowView(podcast: podcast, viewModel: viewModel)
                }
            }
            .navigationTitle("Podcast Search")
        }
    }
}

// One row in the list – like a row DTO rendered in HTML
struct PodcastRowView: View {
    let podcast: Podcast
    @ObservedObject var viewModel: PodcastSearchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Artwork image (like <img> tag)
                if let urlString = podcast.artworkUrl100,
                    let url = URL(string: urlString)
                {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                    .frame(width: 80, height: 80)
                    .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 80)
                        .cornerRadius(8)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(podcast.collectionName)
                        .font(.headline)
                    Text(podcast.artistName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let rating = podcast.contentAdvisoryRating {
                        Text("Rating: \(rating)")
                            .font(.caption)
                            .foregroundColor(rating == "Explicit" ? .red : .green)
                    }

                    if let genres = podcast.genres {
                        Text("Genres: \(genres.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // RSS URL (shortened)
            if let feed = podcast.feedUrl {
                Text("RSS: \(String(feed.prefix(50)))...")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }

            // Episodes section – expands when tapped
            if viewModel.selectedPodcastId == podcast.collectionId {
                if viewModel.isLoadingEpisodes {
                    ProgressView("Loading episodes...")
                        .padding(.top, 8)
                } else if let episodes = viewModel.episodesForSelectedPodcast,
                    !episodes.isEmpty
                {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Episodes")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        ForEach(episodes.prefix(5)) { episode in  // Show only first 5
                            VStack(alignment: .leading, spacing: 4) {
                                Text(episode.trackName)
                                    .font(.caption)
                                    .lineLimit(2)

                                if let duration = episode.trackTimeMillis {
                                    let minutes = duration / 1000 / 60
                                    Text(
                                        "\(minutes) min • \(episode.releaseDate ?? "Unknown date")"
                                    )
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                }
                            }
                            .padding(.leading, 8)
                        }
                    }
                    .padding(.top, 8)
                } else {
                    Text("No episodes loaded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())  // Makes whole row tappable
        .onTapGesture {
            if viewModel.selectedPodcastId == podcast.collectionId {
                viewModel.selectedPodcastId = nil  // Collapse
            } else {
                viewModel.selectedPodcastId = podcast.collectionId
                if let feedUrl = podcast.feedUrl {
                    viewModel.loadEpisodes(from: feedUrl)
                }
            }
        }
    }
}


// Preview – like running the app in Xcode preview
#Preview {
    PodcastSearchView()
}
