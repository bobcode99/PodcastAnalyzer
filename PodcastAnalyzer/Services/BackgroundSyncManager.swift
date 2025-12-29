//
//  BackgroundSyncManager.swift
//  PodcastAnalyzer
//
//  Manages background sync for podcast episodes with notifications
//

import BackgroundTasks
import Combine
import Foundation
import SwiftData
import UserNotifications
import os.log

@MainActor
class BackgroundSyncManager: ObservableObject {
  static let shared = BackgroundSyncManager()

  // Background task identifier
  static let backgroundTaskIdentifier = "com.podcast.analyzer.refresh"

  // Settings
  @Published var isBackgroundSyncEnabled: Bool {
    didSet {
      UserDefaults.standard.set(isBackgroundSyncEnabled, forKey: Keys.backgroundSyncEnabled)
      if isBackgroundSyncEnabled {
        scheduleBackgroundRefresh()
      } else {
        cancelBackgroundRefresh()
      }
    }
  }

  @Published var isNotificationsEnabled: Bool {
    didSet {
      UserDefaults.standard.set(isNotificationsEnabled, forKey: Keys.notificationsEnabled)
      if isNotificationsEnabled {
        requestNotificationPermission()
      }
    }
  }

  @Published var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined
  @Published var lastSyncDate: Date?
  @Published var isSyncing: Bool = false

  private let rssService = PodcastRssService()
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "BackgroundSync")
  private var modelContainer: ModelContainer?

  private enum Keys {
    static let backgroundSyncEnabled = "backgroundSyncEnabled"
    static let notificationsEnabled = "notificationsEnabled"
    static let lastSyncDate = "lastSyncDate"
  }

  private init() {
    self.isBackgroundSyncEnabled = UserDefaults.standard.bool(forKey: Keys.backgroundSyncEnabled)
    self.isNotificationsEnabled = UserDefaults.standard.bool(forKey: Keys.notificationsEnabled)
    if let date = UserDefaults.standard.object(forKey: Keys.lastSyncDate) as? Date {
      self.lastSyncDate = date
    }

    Task {
      await checkNotificationPermission()
    }
  }

  // MARK: - Setup

  func setModelContainer(_ container: ModelContainer) {
    self.modelContainer = container
  }

  // MARK: - Background Task Registration

  /// Call this in app's init to register background task
  static func registerBackgroundTask() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: backgroundTaskIdentifier,
      using: nil
    ) { task in
      Task { @MainActor in
        await BackgroundSyncManager.shared.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
      }
    }
  }

  func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
    // Schedule for 5 minutes from now (iOS may delay based on system conditions)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)

    do {
      try BGTaskScheduler.shared.submit(request)
      logger.info("Background refresh scheduled for 5 minutes from now")
    } catch {
      logger.error("Failed to schedule background refresh: \(error.localizedDescription)")
    }
  }

  func cancelBackgroundRefresh() {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
    logger.info("Background refresh cancelled")
  }

  private func handleBackgroundRefresh(task: BGAppRefreshTask) async {
    // Schedule next refresh
    scheduleBackgroundRefresh()

    // Set expiration handler
    task.expirationHandler = { [weak self] in
      self?.logger.warning("Background refresh expired")
      task.setTaskCompleted(success: false)
    }

    // Perform sync
    let success = await performSync()
    task.setTaskCompleted(success: success)
  }

  // MARK: - Manual Sync (for foreground use)

  func syncNow() async {
    guard !isSyncing else { return }
    _ = await performSync()
  }

  // MARK: - Core Sync Logic

  private func performSync() async -> Bool {
    guard let container = modelContainer else {
      logger.warning("ModelContainer not set, cannot sync")
      return false
    }

    isSyncing = true
    defer { isSyncing = false }

    logger.info("Starting podcast sync...")

    let context = ModelContext(container)
    let descriptor = FetchDescriptor<PodcastInfoModel>()

    do {
      let podcasts = try context.fetch(descriptor)
      logger.info("Found \(podcasts.count) podcasts to sync")

      var totalNewEpisodes = 0
      var newEpisodeDetails: [(podcastTitle: String, episodeTitle: String)] = []

      // Sync each podcast
      for podcast in podcasts {
        let existingEpisodeTitles = Set(podcast.podcastInfo.episodes.map { $0.title })

        do {
          let updatedPodcast = try await rssService.fetchPodcast(from: podcast.podcastInfo.rssUrl)

          // Find new episodes
          let newEpisodes = updatedPodcast.episodes.filter { !existingEpisodeTitles.contains($0.title) }

          if !newEpisodes.isEmpty {
            totalNewEpisodes += newEpisodes.count
            for episode in newEpisodes.prefix(3) {  // Limit to first 3 for notification
              newEpisodeDetails.append((podcastTitle: updatedPodcast.title, episodeTitle: episode.title))
            }

            // Update the podcast with new episodes
            podcast.podcastInfo = updatedPodcast
            podcast.lastUpdated = Date()

            logger.info("Found \(newEpisodes.count) new episodes for \(updatedPodcast.title)")
          }
        } catch {
          logger.error("Failed to sync \(podcast.podcastInfo.title): \(error.localizedDescription)")
        }
      }

      // Save changes
      try context.save()

      // Update last sync date
      lastSyncDate = Date()
      UserDefaults.standard.set(lastSyncDate, forKey: Keys.lastSyncDate)

      // Send notification if there are new episodes
      if totalNewEpisodes > 0 && isNotificationsEnabled {
        await sendNewEpisodesNotification(
          totalCount: totalNewEpisodes,
          details: newEpisodeDetails
        )
      }

      logger.info("Sync completed. Found \(totalNewEpisodes) new episodes total.")
      return true

    } catch {
      logger.error("Sync failed: \(error.localizedDescription)")
      return false
    }
  }

  // MARK: - Notifications

  func requestNotificationPermission() {
    Task {
      do {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(
          options: [.alert, .sound, .badge]
        )
        await MainActor.run {
          if granted {
            notificationPermissionStatus = .authorized
            logger.info("Notification permission granted")
          } else {
            notificationPermissionStatus = .denied
            isNotificationsEnabled = false
            logger.info("Notification permission denied")
          }
        }
      } catch {
        logger.error("Failed to request notification permission: \(error.localizedDescription)")
      }
    }
  }

  func checkNotificationPermission() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    notificationPermissionStatus = settings.authorizationStatus
  }

  private func sendNewEpisodesNotification(
    totalCount: Int,
    details: [(podcastTitle: String, episodeTitle: String)]
  ) async {
    let content = UNMutableNotificationContent()

    if totalCount == 1, let first = details.first {
      content.title = "New Episode"
      content.body = "\(first.podcastTitle): \(first.episodeTitle)"
    } else if details.count <= 3 {
      content.title = "\(totalCount) New Episodes"
      content.body = details.map { $0.podcastTitle }.joined(separator: ", ")
    } else {
      content.title = "\(totalCount) New Episodes"
      let podcastNames = Set(details.map { $0.podcastTitle })
      content.body = "From \(podcastNames.count) podcasts"
    }

    content.sound = .default
    content.badge = NSNumber(value: totalCount)

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil  // Deliver immediately
    )

    do {
      try await UNUserNotificationCenter.current().add(request)
      logger.info("Notification sent for \(totalCount) new episodes")
    } catch {
      logger.error("Failed to send notification: \(error.localizedDescription)")
    }
  }

  // MARK: - Foreground Timer (Optional: for when app is active)

  private var foregroundTimer: Timer?

  func startForegroundSync() {
    guard isBackgroundSyncEnabled else { return }

    stopForegroundSync()
    foregroundTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
      Task { @MainActor in
        await self?.syncNow()
      }
    }
    logger.info("Foreground sync timer started (5 min interval)")
  }

  func stopForegroundSync() {
    foregroundTimer?.invalidate()
    foregroundTimer = nil
  }
}
