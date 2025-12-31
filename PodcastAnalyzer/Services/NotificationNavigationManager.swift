//
//  NotificationNavigationManager.swift
//  PodcastAnalyzer
//
//  Handles notification tap navigation to EpisodeDetailView
//

import Combine
import Foundation
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

@MainActor
class NotificationNavigationManager: NSObject, ObservableObject {
  static let shared = NotificationNavigationManager()

  @Published var navigationTarget: NotificationNavigationTarget?
  @Published var shouldNavigate: Bool = false

  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "NotificationNavigation")
  private var modelContainer: ModelContainer?

  private override init() {
    super.init()
    UNUserNotificationCenter.current().delegate = self
  }

  func setModelContainer(_ container: ModelContainer) {
    self.modelContainer = container
  }

  func clearNavigation() {
    navigationTarget = nil
    shouldNavigate = false
  }

  /// Find the episode info from the database given the notification data
  func findEpisode(podcastTitle: String, episodeTitle: String) -> (episode: PodcastEpisodeInfo, imageURL: String?, language: String)? {
    guard let container = modelContainer else { return nil }

    let context = ModelContext(container)
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.podcastInfo.title == podcastTitle }
    )

    guard let podcast = try? context.fetch(descriptor).first else { return nil }

    if let episode = podcast.podcastInfo.episodes.first(where: { $0.title == episodeTitle }) {
      return (episode, episode.imageURL ?? podcast.podcastInfo.imageURL, podcast.podcastInfo.language)
    }

    return nil
  }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationNavigationManager: UNUserNotificationCenterDelegate {

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo

    Task { @MainActor in
      handleNotificationTap(userInfo: userInfo)
    }

    completionHandler()
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Show notification even when app is in foreground
    #if os(iOS)
    completionHandler([.banner, .sound, .badge])
    #else
    // macOS uses .list and .banner (or .alert for older macOS)
    completionHandler([.banner, .sound])
    #endif
  }

  @MainActor
  private func handleNotificationTap(userInfo: [AnyHashable: Any]) {
    guard let type = userInfo["type"] as? String else {
      logger.warning("Notification tap without type")
      return
    }

    if type == "newEpisode" {
      guard let podcastTitle = userInfo["podcastTitle"] as? String,
            let episodeTitle = userInfo["episodeTitle"] as? String,
            let audioURL = userInfo["audioURL"] as? String,
            let imageURL = userInfo["imageURL"] as? String,
            let language = userInfo["language"] as? String
      else {
        logger.warning("Notification tap missing required fields")
        return
      }

      logger.info("Navigating to episode: \(episodeTitle) from \(podcastTitle)")

      navigationTarget = NotificationNavigationTarget(
        podcastTitle: podcastTitle,
        episodeTitle: episodeTitle,
        audioURL: audioURL,
        imageURL: imageURL,
        language: language
      )
      shouldNavigate = true
    } else if type == "multipleEpisodes" {
      // For multiple episodes, navigate to Library/Latest
      logger.info("Multiple episodes notification tapped, navigating to Latest")
      // Could implement navigation to Library tab here if needed
    }
  }
}
