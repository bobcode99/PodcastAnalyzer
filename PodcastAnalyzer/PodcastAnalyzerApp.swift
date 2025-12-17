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
            fatalError("Could not create ModelContainer: \(error)")
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
