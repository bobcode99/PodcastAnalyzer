//
//  ContentView.swift
//  PodcastAnalyzer
//
//

import Combine
import SwiftData
import SwiftUI

struct ContentView: View {
  @State private var audioManager = EnhancedAudioManager.shared

  private var showMiniPlayer: Bool {
    audioManager.currentEpisode != nil
  }

  var body: some View {
    TabView {
      Tab(Constants.homeString, systemImage: Constants.homeIconName) {
        HomeView()
      }

      Tab(Constants.libraryString, systemImage: Constants.libraryIconName) {
        LibraryView()
      }

      Tab(Constants.settingsString, systemImage: Constants.settingsIconName) {
        SettingsView()
      }

      Tab(role: .search) {
        PodcastSearchView()
      }
    }
    .tabViewBottomAccessory {
      if showMiniPlayer {
        MiniPlayerBar()
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .onAppear {
      // Restore last played episode on app launch
      audioManager.restoreLastEpisode()
    }
  }
}

#Preview {
  ContentView()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
