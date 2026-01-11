//
//  NotificationNavigationManager.swift
//  PodcastAnalyzer
//
//  Handles notification tap navigation to EpisodeDetailView
//

import Foundation
import Observation
import SwiftData
import SwiftUI
import UserNotifications
import os.log

// MARK: - Notification Navigation Target

struct NotificationNavigationTarget: Equatable {
  let podcastTitle: String
  let episodeTitle: String
  let audioURL: String
  let imageURL: String
  let language: String
}

// MARK: - Notification Navigation Manager
@Observable
@MainActor
class NotificationNavigationManager {
    static let shared = NotificationNavigationManager()
    
    var shouldNavigate = false
    var navigationTarget: NotificationNavigationTarget?

    @ObservationIgnored
    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func setModelContainer(_ container: ModelContainer) {
        self.modelContext = container.mainContext
    }

    func clearNavigation() {
        shouldNavigate = false
        navigationTarget = nil
    }
    
    // Improved lookup logic
    func findEpisode(podcastTitle: String, episodeTitle: String) -> (episode: PodcastEpisodeInfo, imageURL: String?, language: String)? {
        guard let context = modelContext else { return nil }
        
        let descriptor = FetchDescriptor<PodcastInfoModel>(
            predicate: #Predicate { $0.podcastInfo.title == podcastTitle }
        )
        
        guard let podcast = try? context.fetch(descriptor).first,
              let episode = podcast.podcastInfo.episodes.first(where: { $0.title == episodeTitle }) else {
            return nil
        }
        
        return (episode, podcast.podcastInfo.imageURL, "en")
    }
}