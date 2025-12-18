//
//  PodcastAnalyzerApp.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/12.
//

import SwiftUI
import SwiftData

@main
struct PodcastAnalyzerApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PodcastInfoModel.self,
            EpisodeDownloadModel.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Migration failed - delete old store and create fresh one
            print("Migration failed, attempting to recreate database: \(error)")

            // Get the default store URL
            let url = URL.applicationSupportDirectory.appending(path: "default.store")

            // Delete old store files
            let fileManager = FileManager.default
            let storeFiles = [
                url,
                url.appendingPathExtension("shm"),
                url.appendingPathExtension("wal")
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
        }
        .modelContainer(sharedModelContainer)
    }
}
