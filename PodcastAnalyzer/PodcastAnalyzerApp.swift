//
//  PodcastAnalyzerApp.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/12.
//

import SwiftData
import SwiftUI
import OSLog

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

    // Register MetricKit crash reporting subscriber
    CrashReportingService.shared.start()

    // Export previous session's os.log entries to Documents/Logs
    PersistentLogService.shared.exportLogsInBackground()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .task {
          // Critical: initialize playback state and sync manager first
          if PlaybackStateCoordinator.shared == nil {
            _ = PlaybackStateCoordinator(modelContext: sharedModelContainer.mainContext)
          }
          BackgroundSyncManager.shared.setModelContainer(sharedModelContainer)

          // Start foreground sync if enabled
          if BackgroundSyncManager.shared.isBackgroundSyncEnabled {
            BackgroundSyncManager.shared.startForegroundSync()
            BackgroundSyncManager.shared.scheduleBackgroundRefresh()
          }

          // Deferred: non-critical managers initialized after first frame
          PodcastImportManager.shared.setModelContainer(sharedModelContainer)
          NotificationNavigationManager.shared.setModelContainer(sharedModelContainer)

          // Register low-memory warning handler to clear caches
          #if os(iOS)
          NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
          ) { _ in
            Task { @MainActor in
              ImageCacheManager.shared.clearMemoryCache()
              await RSSCacheService.shared.clearAllCache()
              logger.warning("Low memory warning: cleared image and RSS caches")
            }
          }
          #endif
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

    // macOS Settings window (Cmd+,)
    #if os(macOS)
    Settings {
      MacSettingsView()
    }
    .modelContainer(sharedModelContainer)
    #endif
  }

  private func handleIncomingURL(_ url: URL) {
    logger.info("Received URL: \(url.absoluteString)")

    // Handle widget deep links
    if url.scheme == "podcastanalyzer" {
      Task { @MainActor in
        switch url.host {
        case "episode":
          // Widget tap with audio URL: podcastanalyzer://episode?audio=<encoded_url>
          if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
             let audioParam = components.queryItems?.first(where: { $0.name == "audio" })?.value {
            NotificationNavigationManager.shared.navigateToEpisode(audioURL: audioParam)
          }
        case "nowplaying":
          // Navigate to currently playing episode
          NotificationNavigationManager.shared.navigateToNowPlaying()
        case "library":
          // Just open the app to library (no specific navigation needed)
          break
        default:
          // Fall back to Shortcuts handling
          ShortcutsAIService.shared.handleURL(url)
        }
      }
    } else {
      // Route to ShortcutsAIService for handling
      Task { @MainActor in
        ShortcutsAIService.shared.handleURL(url)
      }
    }
  }
}
