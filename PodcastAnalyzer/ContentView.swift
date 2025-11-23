//
//  ContentView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/12.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            Tab(Constants.homeString, systemImage: Constants.homeIconName) {
                HomeView()
            }
               Tab(Constants.settingsString, systemImage: Constants.settingsIconName) {
                SettingsView()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
