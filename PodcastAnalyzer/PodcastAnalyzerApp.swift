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

  var body: some Scene {
    WindowGroup {
      ContentView()
        .onAppear {
          // Initialize playback state coordinator on first appear
          Task { @MainActor in
            if PlaybackStateCoordinator.shared == nil {
              _ = PlaybackStateCoordinator(modelContext: sharedModelContainer.mainContext)
            }
          }
        }
        .onOpenURL { url in
          // Handle URL callbacks from Shortcuts
          handleIncomingURL(url)
        }
    }
    .modelContainer(sharedModelContainer)
  }

  private func handleIncomingURL(_ url: URL) {
    logger.info("Received URL: \(url.absoluteString)")

    // Route to ShortcutsAIService for handling
    Task { @MainActor in
      ShortcutsAIService.shared.handleURL(url)
    }
  }
}
