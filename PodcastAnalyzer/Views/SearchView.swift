//
//  SearchView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/23.
//

import Combine
import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#endif

// MARK: - Search Tab Enum

enum SearchTab: String, CaseIterable {
    case applePodcasts = "Apple Podcasts"
    case library = "Library"
}

// MARK: - Main Search View

struct PodcastSearchView: View {
    @StateObject private var viewModel = PodcastSearchViewModel()
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<PodcastInfoModel> { $0.isSubscribed == true })
    private var subscribedPodcasts: [PodcastInfoModel]

    @State private var selectedTab: SearchTab = .applePodcasts
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                tabSelector
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Search results
                if searchText.isEmpty {
                    emptySearchView
                } else {
                    switch selectedTab {
                    case .applePodcasts:
                        applePodcastsResultsView
                    case .library:
                        libraryResultsView
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Podcasts & Episodes")
            .onSubmit(of: .search) {
                if selectedTab == .applePodcasts {
                    viewModel.searchText = searchText
                    viewModel.performSearch()
                }
            }
            .onChange(of: searchText) { _, newValue in
                viewModel.searchText = newValue
                if selectedTab == .applePodcasts && !newValue.isEmpty {
                    viewModel.performSearch()
                }
            }
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .applePodcasts && !searchText.isEmpty {
                    viewModel.searchText = searchText
                    viewModel.performSearch()
                }
            }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(SearchTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }) {
                    Text(tab.rawValue)
                        .font(.subheadline)
                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                        .foregroundColor(selectedTab == tab ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.platformSystemGray5 : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.platformSystemGray6)
        .cornerRadius(10)
    }

    // MARK: - Empty Search View

    private var emptySearchView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("Search for podcasts")
                .font(.title3)
                .foregroundColor(.secondary)
            Text(selectedTab == .applePodcasts
                 ? "Find new podcasts to subscribe"
                 : "Search your subscribed podcasts and episodes")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Apple Podcasts Results

    private var applePodcastsResultsView: some View {
        Group {
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                }
            } else if viewModel.podcasts.isEmpty {
                VStack {
                    Spacer()
                    Text("No results found")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(viewModel.podcasts, id: \.collectionId) { podcast in
                        NavigationLink(destination: EpisodeListView(
                            podcastName: podcast.collectionName,
                            podcastArtwork: podcast.artworkUrl100 ?? "",
                            artistName: podcast.artistName,
                            collectionId: String(podcast.collectionId),
                            applePodcastUrl: nil
                        )) {
                            ApplePodcastRow(
                                podcast: podcast,
                                isSubscribed: isSubscribed(podcast),
                                onSubscribe: { subscribeToPodcast(podcast) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Library Results

    private var libraryResultsView: some View {
        let filteredPodcasts = filterLibraryPodcasts()
        let filteredEpisodes = filterLibraryEpisodes()

        return Group {
            if filteredPodcasts.isEmpty && filteredEpisodes.isEmpty {
                VStack {
                    Spacer()
                    Text("No results in your library")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    // Podcasts section
                    if !filteredPodcasts.isEmpty {
                        Section {
                            ForEach(filteredPodcasts) { podcastModel in
                                LibraryPodcastRow(podcastModel: podcastModel)
                            }
                        }
                    }

                    // Episodes section
                    if !filteredEpisodes.isEmpty {
                        Section {
                            ForEach(filteredEpisodes, id: \.episode.id) { item in
                                LibraryEpisodeRow(
                                    episode: item.episode,
                                    podcastTitle: item.podcastTitle,
                                    podcastImageURL: item.podcastImageURL,
                                    podcastLanguage: item.podcastLanguage
                                )
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Helper Methods

    private func isSubscribed(_ podcast: Podcast) -> Bool {
        subscribedPodcasts.contains { $0.podcastInfo.title == podcast.collectionName }
    }

    private func subscribeToPodcast(_ podcast: Podcast) {
        guard let feedUrl = podcast.feedUrl else { return }

        Task {
            do {
                let rssService = PodcastRssService()
                let podcastInfo = try await rssService.fetchPodcast(from: feedUrl)
                let podcastInfoModel = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date.now)

                await MainActor.run {
                    modelContext.insert(podcastInfoModel)
                    try? modelContext.save()
                }
            } catch {
                print("Failed to subscribe: \(error)")
            }
        }
    }

    private func filterLibraryPodcasts() -> [PodcastInfoModel] {
        let query = searchText.lowercased()
        return subscribedPodcasts.filter { podcast in
            podcast.podcastInfo.title.lowercased().contains(query)
        }
    }

    private func filterLibraryEpisodes() -> [(episode: PodcastEpisodeInfo, podcastTitle: String, podcastImageURL: String, podcastLanguage: String)] {
        let query = searchText.lowercased()
        var results: [(episode: PodcastEpisodeInfo, podcastTitle: String, podcastImageURL: String, podcastLanguage: String)] = []

        for podcast in subscribedPodcasts {
            let matchingEpisodes = podcast.podcastInfo.episodes.filter { episode in
                episode.title.lowercased().contains(query) ||
                (episode.podcastEpisodeDescription?.lowercased().contains(query) ?? false)
            }

            for episode in matchingEpisodes {
                results.append((
                    episode: episode,
                    podcastTitle: podcast.podcastInfo.title,
                    podcastImageURL: podcast.podcastInfo.imageURL,
                    podcastLanguage: podcast.podcastInfo.language
                ))
            }
        }

        return results
    }
}

// MARK: - Apple Podcast Row

struct ApplePodcastRow: View {
    let podcast: Podcast
    let isSubscribed: Bool
    let onSubscribe: () -> Void

    @State private var isSubscribing = false

    var body: some View {
        HStack(spacing: 12) {
            // Artwork - using CachedAsyncImage for better performance
            CachedArtworkImage(urlString: podcast.artworkUrl100, size: 56, cornerRadius: 8)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(podcast.collectionName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Text("Show · \(podcast.artistName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Subscribe button or checkmark
            if isSubscribed {
                Image(systemName: "checkmark")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            } else if isSubscribing {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button(action: {
                    isSubscribing = true
                    onSubscribe()
                    // Reset after a delay (subscription will update via @Query)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isSubscribing = false
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Library Podcast Row

struct LibraryPodcastRow: View {
    let podcastModel: PodcastInfoModel

    var body: some View {
        NavigationLink {
            EpisodeListView(podcastModel: podcastModel)
        } label: {
            HStack(spacing: 12) {
                // Artwork - using CachedAsyncImage for better performance
                CachedArtworkImage(urlString: podcastModel.podcastInfo.imageURL, size: 56, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(podcastModel.podcastInfo.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text("Show · \(podcastModel.podcastInfo.episodes.count) episodes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "checkmark")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Library Episode Row

struct LibraryEpisodeRow: View {
    let episode: PodcastEpisodeInfo
    let podcastTitle: String
    let podcastImageURL: String
    let podcastLanguage: String

    private var audioManager: EnhancedAudioManager { EnhancedAudioManager.shared }

    var body: some View {
        NavigationLink {
            EpisodeDetailView(
                episode: episode,
                podcastTitle: podcastTitle,
                fallbackImageURL: podcastImageURL,
                podcastLanguage: podcastLanguage
            )
        } label: {
            HStack(spacing: 12) {
                // Artwork - using CachedAsyncImage for better performance
                CachedArtworkImage(urlString: episode.imageURL ?? podcastImageURL, size: 56, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 4) {
                    // Date and duration
                    HStack(spacing: 4) {
                        if let date = episode.pubDate {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                        }
                        if let duration = episode.formattedDuration {
                            Text("·")
                            Text(duration)
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)

                    // Title
                    Text(episode.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                Spacer()

                // Play button
                if episode.audioURL != nil {
                    Button(action: {
                        playEpisode()
                    }) {
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.purple)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func playEpisode() {
        guard let audioURL = episode.audioURL else { return }

        let playbackEpisode = PlaybackEpisode(
            id: "\(podcastTitle)\u{1F}\(episode.title)",
            title: episode.title,
            podcastTitle: podcastTitle,
            audioURL: audioURL,
            imageURL: episode.imageURL ?? podcastImageURL,
            episodeDescription: episode.podcastEpisodeDescription,
            pubDate: episode.pubDate,
            duration: episode.duration,
            guid: episode.guid
        )

        audioManager.play(
            episode: playbackEpisode,
            audioURL: audioURL,
            startTime: 0,
            imageURL: episode.imageURL ?? podcastImageURL,
            useDefaultSpeed: true
        )
    }
}

// MARK: - Preview

#Preview {
    PodcastSearchView()
}
