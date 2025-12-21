//
//  ContentView.swift
//  PodcastAnalyzer
//
//

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @State private var audioManager = EnhancedAudioManager.shared

    private var showMiniPlayer: Bool {
        audioManager.currentEpisode != nil
    }

    var body: some View {
        TabView() {
            
            Tab(Constants.homeString, systemImage: Constants.homeIconName) {
                HomeView()
            }

            Tab(Constants.settingsString, systemImage: Constants.settingsIconName) {
                SettingsView()
            }

            Tab(role: .search) {
                SearchView()
            }
        }
        .tabViewBottomAccessory {
            if showMiniPlayer {
                MiniPlayerBar()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
