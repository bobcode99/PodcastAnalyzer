//
//  ContentView.swift
//  PodcastAnalyzer
//
//  Main app view with mini player overlay
//

import SwiftUI
import SwiftData
import Combine

// Mini player height constant
let miniPlayerHeight: CGFloat = 64

struct ContentView: View {
    @State private var audioManager = EnhancedAudioManager.shared
    @State private var selectedTab = 0

    private var showMiniPlayer: Bool {
        audioManager.currentEpisode != nil
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    miniPlayerSpacer
                }
                .tabItem {
                    Label(Constants.homeString, systemImage: Constants.homeIconName)
                }
                .tag(0)

            SettingsView()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    miniPlayerSpacer
                }
                .tabItem {
                    Label(Constants.settingsString, systemImage: Constants.settingsIconName)
                }
                .tag(1)

            SearchView()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    miniPlayerSpacer
                }
                .tabItem {
                    Label(Constants.searchString, systemImage: Constants.searchIconName)
                }
                .tag(2)
        }
        .overlay(alignment: .bottom) {
            if showMiniPlayer {
                MiniPlayerBar()
                    .frame(height: miniPlayerHeight)
                    .padding(.bottom, 50) // Tab bar height offset
            }
        }
    }

    @ViewBuilder
    private var miniPlayerSpacer: some View {
        if showMiniPlayer {
            Color.clear.frame(height: miniPlayerHeight)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
