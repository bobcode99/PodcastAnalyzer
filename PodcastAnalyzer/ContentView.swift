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
  @ObservedObject private var importManager = PodcastImportManager.shared

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
    .sheet(isPresented: $importManager.showImportSheet) {
      PodcastImportSheet()
    }
  }
}

// MARK: - Podcast Import Sheet

struct PodcastImportSheet: View {
  @ObservedObject private var importManager = PodcastImportManager.shared
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        if importManager.isImporting {
          // Progress view
          VStack(spacing: 16) {
            ProgressView(value: importManager.importProgress)
              .progressViewStyle(.linear)
              .padding(.horizontal)

            Text(importManager.importStatus)
              .font(.subheadline)
              .foregroundColor(.secondary)

            ProgressView()
              .scaleEffect(1.5)
              .padding(.top, 20)
          }
          .padding()
        } else if let results = importManager.importResults {
          // Results view
          VStack(spacing: 20) {
            Image(systemName: results.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
              .font(.system(size: 60))
              .foregroundColor(results.failed == 0 ? .green : .orange)

            Text("Import Complete")
              .font(.title2)
              .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(.green)
                Text("\(results.successful) podcasts imported")
              }

              if results.skipped > 0 {
                HStack {
                  Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(.blue)
                  Text("\(results.skipped) already subscribed")
                }
              }

              if results.failed > 0 {
                HStack {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                  Text("\(results.failed) failed")
                }
              }
            }
            .font(.subheadline)

            if !results.failedPodcasts.isEmpty {
              VStack(alignment: .leading, spacing: 4) {
                Text("Failed URLs:")
                  .font(.caption)
                  .foregroundColor(.secondary)

                ForEach(results.failedPodcasts.prefix(3), id: \.self) { url in
                  Text(url)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(1)
                }

                if results.failedPodcasts.count > 3 {
                  Text("... and \(results.failedPodcasts.count - 3) more")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
              }
              .padding()
              .background(Color.gray.opacity(0.1))
              .cornerRadius(8)
            }

            Button("Done") {
              importManager.dismissImportSheet()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 16)
          }
          .padding()
        } else {
          // Initial/waiting state
          VStack(spacing: 16) {
            ProgressView()
              .scaleEffect(1.5)
            Text("Preparing import...")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
        }

        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle("Import Podcasts")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if !importManager.isImporting {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
              importManager.dismissImportSheet()
            }
          }
        }
      }
      .interactiveDismissDisabled(importManager.isImporting)
    }
  }
}

#Preview {
  ContentView()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
