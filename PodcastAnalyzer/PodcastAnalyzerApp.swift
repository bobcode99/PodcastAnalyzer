//
//  PodcastAnalyzerApp.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/12.
//

import SwiftData
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "App")

@main
struct PodcastAnalyzerApp: App {
  @Environment(\.scenePhase) private var scenePhase

  let sharedModelContainer: ModelContainer = {
    let schema = Schema([
      PodcastInfoModel.self,
      EpisodeDownloadModel.self,
      EpisodeAIAnalysis.self,
      EpisodeQuickTagsModel.self,
    ])
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

    do {
      return try ModelContainer(for: schema, configurations: [modelConfiguration])
    } catch {
      // Migration failed - delete old store and create fresh one
      logger.error(
        "Migration failed, attempting to recreate database: \(error.localizedDescription)")

      // Get the default store URL
      let url = URL.applicationSupportDirectory.appending(path: "default.store")

      // Delete old store files
      let fileManager = FileManager.default
      let storeFiles = [
        url,
        url.appendingPathExtension("shm"),
        url.appendingPathExtension("wal"),
      ]

      for file in storeFiles {
        try? fileManager.removeItem(at: file)
      }

      // Try again with fresh database
      do {
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
      } catch {
        fatalError("Could not create ModelContainer after reset: \(error)")
      }
    }
  }()

  init() {
    // Register background task for episode sync
    BackgroundSyncManager.registerBackgroundTask()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .onAppear {
          // Initialize playback state coordinator on first appear
          Task { @MainActor in
            if PlaybackStateCoordinator.shared == nil {
              _ = PlaybackStateCoordinator(modelContext: sharedModelContainer.mainContext)
            }

            // Set up background sync manager
            BackgroundSyncManager.shared.setModelContainer(sharedModelContainer)

            // Start foreground sync if enabled
            if BackgroundSyncManager.shared.isBackgroundSyncEnabled {
              BackgroundSyncManager.shared.startForegroundSync()
              BackgroundSyncManager.shared.scheduleBackgroundRefresh()
            }
          }
        }
        .onOpenURL { url in
          // Handle URL callbacks from Shortcuts
          handleIncomingURL(url)
        }
    }
    .modelContainer(sharedModelContainer)
    .onChange(of: scenePhase) { _, newPhase in
      switch newPhase {
      case .active:
        // App became active - start foreground sync
        if BackgroundSyncManager.shared.isBackgroundSyncEnabled {
          BackgroundSyncManager.shared.startForegroundSync()
        }
      case .background:
        // App going to background - stop foreground timer, schedule background task
        BackgroundSyncManager.shared.stopForegroundSync()
        if BackgroundSyncManager.shared.isBackgroundSyncEnabled {
          BackgroundSyncManager.shared.scheduleBackgroundRefresh()
        }
      case .inactive:
        break
      @unknown default:
        break
      }
    }
  }

  private func handleIncomingURL(_ url: URL) {
    logger.info("Received URL: \(url.absoluteString)")

    // Route to ShortcutsAIService for handling
    Task { @MainActor in
      ShortcutsAIService.shared.handleURL(url)
    }
  }
}
