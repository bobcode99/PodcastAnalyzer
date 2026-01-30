//
//  ContentView.swift
//  PodcastAnalyzer
//
//

import SwiftData
import SwiftUI

struct ContentView: View {
  var body: some View {
    #if os(iOS)
    iOSContentView()
    #else
    MacContentView()
    #endif
  }
}

// MARK: - iOS Content View

#if os(iOS)
struct iOSContentView: View {
  // Access singletons directly without @State to avoid unnecessary observation overhead
  private var audioManager: EnhancedAudioManager { .shared }
  private var importManager: PodcastImportManager { .shared }
  private var notificationManager: NotificationNavigationManager { .shared }
  @Environment(\.modelContext) private var modelContext

  // Navigation state for notification-triggered navigation
  @State private var notificationEpisode: PodcastEpisodeInfo?
  @State private var notificationPodcastTitle: String = ""
  @State private var notificationImageURL: String?
  @State private var notificationLanguage: String = "en"
  @State private var showNotificationEpisode: Bool = false

  // Navigation state for expanded player navigation
  @State private var expandedPlayerNavigation: ExpandedPlayerNavigation = .none
  @State private var expandedPlayerEpisode: PodcastEpisodeInfo?
  @State private var expandedPlayerPodcastTitle: String = ""
  @State private var expandedPlayerImageURL: String?
  @State private var showExpandedPlayerEpisode: Bool = false
  @State private var expandedPlayerPodcastModel: PodcastInfoModel?
  @State private var showExpandedPlayerPodcast: Bool = false

    private var showMiniPlayer: Bool {
        // Change this to true so it always shows even if empty
        return true
    }

  var body: some View {
    TabView {
      Tab(Constants.homeString, systemImage: Constants.homeIconName) {
        NavigationStack {
          HomeView()
            .playerNavigationDestinations(
              showNotificationEpisode: $showNotificationEpisode,
              notificationEpisode: notificationEpisode,
              notificationPodcastTitle: notificationPodcastTitle,
              notificationImageURL: notificationImageURL,
              notificationLanguage: notificationLanguage,
              showEpisodeDetail: $showExpandedPlayerEpisode,
              episodeDetail: expandedPlayerEpisode,
              episodePodcastTitle: expandedPlayerPodcastTitle,
              episodeImageURL: expandedPlayerImageURL,
              showPodcastList: $showExpandedPlayerPodcast,
              podcastModel: expandedPlayerPodcastModel
            )
        }
      }

      Tab(Constants.libraryString, systemImage: Constants.libraryIconName) {
        NavigationStack {
          LibraryView()
            .playerNavigationDestinations(
              showNotificationEpisode: $showNotificationEpisode,
              notificationEpisode: notificationEpisode,
              notificationPodcastTitle: notificationPodcastTitle,
              notificationImageURL: notificationImageURL,
              notificationLanguage: notificationLanguage,
              showEpisodeDetail: $showExpandedPlayerEpisode,
              episodeDetail: expandedPlayerEpisode,
              episodePodcastTitle: expandedPlayerPodcastTitle,
              episodeImageURL: expandedPlayerImageURL,
              showPodcastList: $showExpandedPlayerPodcast,
              podcastModel: expandedPlayerPodcastModel
            )
        }
      }

      Tab(Constants.settingsString, systemImage: Constants.settingsIconName) {
        NavigationStack {
          SettingsView()
            .playerNavigationDestinations(
              showNotificationEpisode: $showNotificationEpisode,
              notificationEpisode: notificationEpisode,
              notificationPodcastTitle: notificationPodcastTitle,
              notificationImageURL: notificationImageURL,
              notificationLanguage: notificationLanguage,
              showEpisodeDetail: $showExpandedPlayerEpisode,
              episodeDetail: expandedPlayerEpisode,
              episodePodcastTitle: expandedPlayerPodcastTitle,
              episodeImageURL: expandedPlayerImageURL,
              showPodcastList: $showExpandedPlayerPodcast,
              podcastModel: expandedPlayerPodcastModel
            )
        }
      }

      Tab(role: .search) {
        NavigationStack {
          PodcastSearchView()
            .playerNavigationDestinations(
              showNotificationEpisode: $showNotificationEpisode,
              notificationEpisode: notificationEpisode,
              notificationPodcastTitle: notificationPodcastTitle,
              notificationImageURL: notificationImageURL,
              notificationLanguage: notificationLanguage,
              showEpisodeDetail: $showExpandedPlayerEpisode,
              episodeDetail: expandedPlayerEpisode,
              episodePodcastTitle: expandedPlayerPodcastTitle,
              episodeImageURL: expandedPlayerImageURL,
              showPodcastList: $showExpandedPlayerPodcast,
              podcastModel: expandedPlayerPodcastModel
            )
        }
      }
    }
    .tabViewBottomAccessory {
      if showMiniPlayer {
        MiniPlayerBar(pendingNavigation: $expandedPlayerNavigation)
      }
    }
    .onChange(of: expandedPlayerNavigation) { _, newValue in
      handleExpandedPlayerNavigation(newValue)
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .onAppear {
      // Restore last played episode on app launch
      audioManager.restoreLastEpisode()
    }
// Using @Bindable locally for the sheet binding
        .sheet(isPresented: Binding(get: { importManager.showImportSheet }, set: { importManager.showImportSheet = $0 })) {
            PodcastImportSheet()
        }
        .onChange(of: notificationManager.shouldNavigate) { _, shouldNavigate in
            if shouldNavigate, let target = notificationManager.navigationTarget {
                handleNotificationNavigation(target: target)
            }
        }
  }

  private func handleNotificationNavigation(target: NotificationNavigationTarget) {
    // Try to find the episode from the database
    if let result = notificationManager.findEpisode(
      podcastTitle: target.podcastTitle,
      episodeTitle: target.episodeTitle
    ) {
      notificationEpisode = result.episode
      notificationPodcastTitle = target.podcastTitle
      notificationImageURL = result.imageURL
      notificationLanguage = result.language
      showNotificationEpisode = true
    } else {
      // Fallback: create a minimal episode info from notification data
      notificationEpisode = PodcastEpisodeInfo(
        title: target.episodeTitle,
        podcastEpisodeDescription: nil,
        pubDate: nil,
        audioURL: target.audioURL.isEmpty ? nil : target.audioURL,
        imageURL: target.imageURL.isEmpty ? nil : target.imageURL,
        duration: nil,
        guid: nil
      )
      notificationPodcastTitle = target.podcastTitle
      notificationImageURL = target.imageURL.isEmpty ? nil : target.imageURL
      notificationLanguage = target.language
      showNotificationEpisode = true
    }

    // Clear the navigation state
    notificationManager.clearNavigation()
  }

  private func handleExpandedPlayerNavigation(_ navigation: ExpandedPlayerNavigation) {
    switch navigation {
    case .none:
      break
    case let .episodeDetail(episode, podcastTitle, imageURL):
      // Small delay to allow sheet dismissal animation to complete
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        expandedPlayerEpisode = episode
        expandedPlayerPodcastTitle = podcastTitle
        expandedPlayerImageURL = imageURL
        showExpandedPlayerEpisode = true
        expandedPlayerNavigation = .none
      }
    case let .podcastEpisodeList(podcastModel):
      // Small delay to allow sheet dismissal animation to complete
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        expandedPlayerPodcastModel = podcastModel
        showExpandedPlayerPodcast = true
        expandedPlayerNavigation = .none
      }
    }
  }
}
#endif

// MARK: - Podcast Import Sheet

struct PodcastImportSheet: View {
  @Bindable private var importManager = PodcastImportManager.shared
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
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
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

// MARK: - Player Navigation Destinations

extension View {
  /// Attaches navigationDestination modifiers for expanded player / notification navigation.
  /// Must be called on a view that is inside a NavigationStack.
  func playerNavigationDestinations(
    showNotificationEpisode: Binding<Bool>,
    notificationEpisode: PodcastEpisodeInfo?,
    notificationPodcastTitle: String,
    notificationImageURL: String?,
    notificationLanguage: String,
    showEpisodeDetail: Binding<Bool>,
    episodeDetail: PodcastEpisodeInfo?,
    episodePodcastTitle: String,
    episodeImageURL: String?,
    showPodcastList: Binding<Bool>,
    podcastModel: PodcastInfoModel?
  ) -> some View {
    self
      .navigationDestination(isPresented: showNotificationEpisode) {
        if let episode = notificationEpisode {
          EpisodeDetailView(
            episode: episode,
            podcastTitle: notificationPodcastTitle,
            fallbackImageURL: notificationImageURL,
            podcastLanguage: notificationLanguage
          )
        }
      }
      .navigationDestination(isPresented: showEpisodeDetail) {
        if let episode = episodeDetail {
          EpisodeDetailView(
            episode: episode,
            podcastTitle: episodePodcastTitle,
            fallbackImageURL: episodeImageURL
          )
        }
      }
      .navigationDestination(isPresented: showPodcastList) {
        if let podcastModel = podcastModel {
          EpisodeListView(podcastModel: podcastModel)
        }
      }
  }
}

#Preview {
  ContentView()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
