//
//  PodcastSearchViewModel.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/23.
//

import Combine
import SwiftUI

@MainActor
@Observable
final class PodcastSearchViewModel {
  var searchText = ""
  var podcasts: [Podcast] = []
  var isLoading = false

  var selectedPodcastId: Int? = nil
  var episodesForSelectedPodcast: [Episode]? = nil
  var isLoadingEpisodes = false

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
      .sink { [weak self] completion in
        self?.isLoading = false
        if case .failure(let error) = completion {
          print("Search error: \(error)")
        }
      } receiveValue: { [weak self] results in
        self?.podcasts = results
      }
      .store(in: &cancellables)
  }

  func loadEpisodes(from feedUrl: String) {
    isLoadingEpisodes = true
    episodesForSelectedPodcast = nil

    service.fetchEpisodesFromRSS(feedUrl: feedUrl, limit: 20)
      .sink { [weak self] completion in
        self?.isLoadingEpisodes = false
        if case .failure(let error) = completion {
          print("RSS error: \(error)")
        }
      } receiveValue: { [weak self] episodes in
        self?.episodesForSelectedPodcast = episodes
      }
      .store(in: &cancellables)
  }
}
