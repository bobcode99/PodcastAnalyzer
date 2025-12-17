//
//  ContentView.swift
//  PodcastAnalyzer
//
//  Main app view with mini player overlay
//

import SwiftUI
import SwiftData

struct ContentView: View {
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
            
            // Mini player overlay (appears when playing)
            MiniPlayerBar()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
