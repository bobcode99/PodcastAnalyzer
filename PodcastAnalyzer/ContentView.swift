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
        ZStack(alignment: .bottom) {
            // Main tab view
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
            // Add padding to prevent mini player from covering tab bar
            .safeAreaInset(edge: .bottom) {
                if miniPlayerViewModel.isVisible {
                    Color.clear.frame(height: 70) // Reserve space for mini player
                }
            }
            
            // Mini player overlay (appears when playing)
            MiniPlayerBar()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
