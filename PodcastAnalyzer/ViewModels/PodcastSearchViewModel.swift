//
//  PodcastSearchViewModel.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/23.
//


import Combine  // For the service publishers
import SwiftUI

@MainActor
class PodcastSearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var podcasts: [Podcast] = []
    @Published var isLoading = false

    @Published var selectedPodcastId: Int? = nil
    @Published var episodesForSelectedPodcast: [Episode]? = nil
    @Published var isLoadingEpisodes = false

    private let service = ApplePodcastService()
    private var cancellables = Set<AnyCancellable>()

    func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            podcasts = []
            return
        }

        isLoading = true
        podcasts = []

        service.searchPodcasts(term: searchText, limit: 20)
            .sink { completion in
                self.isLoading = false
                if case .failure(let error) = completion {
                    print("Search error: \(error)")
                }
            } receiveValue: { results in
                self.podcasts = results
            }
            .store(in: &cancellables)
    }

    func loadEpisodes(from feedUrl: String) {
        isLoadingEpisodes = true
        episodesForSelectedPodcast = nil

        service.fetchEpisodesFromRSS(feedUrl: feedUrl, limit: 20)
            .sink { completion in
                self.isLoadingEpisodes = false
                if case .failure(let error) = completion {
                    print("RSS error: \(error)")
                }
            } receiveValue: { episodes in
                self.episodesForSelectedPodcast = episodes
            }
            .store(in: &cancellables)
    }
}