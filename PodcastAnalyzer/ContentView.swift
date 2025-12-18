//
//  ContentView.swift
//  PodcastAnalyzer
//
//  Main app view with mini player overlay
//

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @StateObject private var miniPlayerViewModel = MiniPlayerViewModel()

    var body: some View {
        TabView {
            Tab(Constants.homeString, systemImage: Constants.homeIconName) {
                HomeView()
            }

            Tab(Constants.settingsString, systemImage: Constants.settingsIconName) {
                SettingsView()
            }

            Tab(Constants.searchString, systemImage: Constants.searchIconName) {
                SearchView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Mini player appears above tab bar, respecting safe area
            if miniPlayerViewModel.isVisible {
                MiniPlayerBar()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
