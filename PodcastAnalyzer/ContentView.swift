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
  // importManager needs @State because $binding syntax is required for sheet
  @State private var importManager = PodcastImportManager.shared
  private var notificationManager: NotificationNavigationManager { .shared }
  @Environment(\.modelContext) private var modelContext

  @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

  // Navigation state for notification-triggered navigation
  @State private var notificationEpisodeRoute: EpisodeDetailRoute?

  // Navigation state for expanded player navigation
  @State private var expandedPlayerNavigation: ExpandedPlayerNavigation = .none
  @State private var expandedPlayerEpisodeRoute: EpisodeDetailRoute?
  @State private var expandedPlayerPodcastRoute: PodcastBrowseRoute?

  var body: some View {
    TabView {
      Tab(Constants.homeString, systemImage: Constants.homeIconName) {
        NavigationStack {
          HomeView()
            .playerNavigationDestinations(
              notificationEpisodeRoute: $notificationEpisodeRoute,
              expandedPlayerEpisodeRoute: $expandedPlayerEpisodeRoute,
              expandedPlayerPodcastRoute: $expandedPlayerPodcastRoute
            )
        }
      }

      Tab(Constants.libraryString, systemImage: Constants.libraryIconName) {
        NavigationStack {
          LibraryView()
            .playerNavigationDestinations(
              notificationEpisodeRoute: $notificationEpisodeRoute,
              expandedPlayerEpisodeRoute: $expandedPlayerEpisodeRoute,
              expandedPlayerPodcastRoute: $expandedPlayerPodcastRoute
            )
        }
      }

      Tab(Constants.settingsString, systemImage: Constants.settingsIconName) {
        NavigationStack {
          SettingsView()
            .playerNavigationDestinations(
              notificationEpisodeRoute: $notificationEpisodeRoute,
              expandedPlayerEpisodeRoute: $expandedPlayerEpisodeRoute,
              expandedPlayerPodcastRoute: $expandedPlayerPodcastRoute
            )
        }
      }

      Tab(role: .search) {
        NavigationStack {
          PodcastSearchView()
            .playerNavigationDestinations(
              notificationEpisodeRoute: $notificationEpisodeRoute,
              expandedPlayerEpisodeRoute: $expandedPlayerEpisodeRoute,
              expandedPlayerPodcastRoute: $expandedPlayerPodcastRoute
            )
        }
      }
    }
    .tabViewBottomAccessory {
      MiniPlayerBar(pendingNavigation: $expandedPlayerNavigation)
    }
    .onChange(of: expandedPlayerNavigation) { _, newValue in
      handleExpandedPlayerNavigation(newValue)
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .onAppear {
      // Restore last played episode on app launch
      audioManager.restoreLastEpisode()
    }
        .sheet(isPresented: $importManager.showImportSheet) {
            PodcastImportSheet()
        }
        .fullScreenCover(isPresented: Binding(
          get: { !hasCompletedOnboarding },
          set: { if !$0 { hasCompletedOnboarding = true } }
        )) {
          OnboardingView()
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
      notificationEpisodeRoute = EpisodeDetailRoute(
        episode: result.episode,
        podcastTitle: target.podcastTitle,
        fallbackImageURL: result.imageURL,
        podcastLanguage: result.language
      )
    } else {
      let episode = PodcastEpisodeInfo(
        title: target.episodeTitle,
        podcastEpisodeDescription: nil,
        pubDate: nil,
        audioURL: target.audioURL.isEmpty ? nil : target.audioURL,
        imageURL: target.imageURL.isEmpty ? nil : target.imageURL,
        duration: nil,
        guid: nil
      )
      notificationEpisodeRoute = EpisodeDetailRoute(
        episode: episode,
        podcastTitle: target.podcastTitle,
        fallbackImageURL: target.imageURL.isEmpty ? nil : target.imageURL,
        podcastLanguage: target.language
      )
    }

    // Clear the navigation state
    notificationManager.clearNavigation()
  }

  private func handleExpandedPlayerNavigation(_ navigation: ExpandedPlayerNavigation) {
    switch navigation {
    case .none:
      break
    case let .episodeDetail(episode, podcastTitle, imageURL):
      expandedPlayerPodcastRoute = nil
      expandedPlayerEpisodeRoute = EpisodeDetailRoute(
        episode: episode,
        podcastTitle: podcastTitle,
        fallbackImageURL: imageURL,
        podcastLanguage: nil
      )
      expandedPlayerNavigation = .none
    case let .podcastEpisodeList(podcastModel):
      expandedPlayerEpisodeRoute = nil
      expandedPlayerPodcastRoute = PodcastBrowseRoute(podcastModel: podcastModel)
      expandedPlayerNavigation = .none
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
              .foregroundStyle(.secondary)

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
              .foregroundStyle(results.failed == 0 ? .green : .orange)

            Text("Import Complete")
              .font(.title2)
              .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(.green)
                Text("\(results.successful) podcasts imported")
              }

              if results.skipped > 0 {
                HStack {
                  Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.blue)
                  Text("\(results.skipped) already subscribed")
                }
              }

              if results.failed > 0 {
                HStack {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                  Text("\(results.failed) failed")
                }
              }
            }
            .font(.subheadline)

            if !results.failedPodcasts.isEmpty {
              VStack(alignment: .leading, spacing: 4) {
                Text("Failed URLs:")
                  .font(.caption)
                  .foregroundStyle(.secondary)

                ForEach(results.failedPodcasts.prefix(3), id: \.self) { url in
                  Text(url)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                }

                if results.failedPodcasts.count > 3 {
                  Text("... and \(results.failedPodcasts.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
              }
              .padding()
              .background(Color.gray.opacity(0.1))
              .clipShape(.rect(cornerRadius: 8))
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
              .foregroundStyle(.secondary)
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
    notificationEpisodeRoute: Binding<EpisodeDetailRoute?>,
    expandedPlayerEpisodeRoute: Binding<EpisodeDetailRoute?>,
    expandedPlayerPodcastRoute: Binding<PodcastBrowseRoute?>
  ) -> some View {
    self
      .navigationDestination(item: notificationEpisodeRoute) { route in
        EpisodeDetailView(
          episode: route.episode,
          podcastTitle: route.podcastTitle,
          fallbackImageURL: route.fallbackImageURL,
          podcastLanguage: route.podcastLanguage ?? "en"
        )
      }
      .navigationDestination(item: expandedPlayerEpisodeRoute) { route in
        EpisodeDetailView(
          episode: route.episode,
          podcastTitle: route.podcastTitle,
          fallbackImageURL: route.fallbackImageURL,
          podcastLanguage: route.podcastLanguage ?? "en"
        )
      }
      .navigationDestination(item: expandedPlayerPodcastRoute) { route in
        if let model = route.podcastModel {
          EpisodeListView(podcastModel: model)
        } else {
          EpisodeListView(
            podcastName: route.podcastName,
            podcastArtwork: route.artworkURL,
            artistName: route.artistName,
            collectionId: route.collectionId ?? "",
            applePodcastUrl: route.applePodcastURL
          )
        }
      }
      .navigationDestination(for: EpisodeDetailRoute.self) { route in
        EpisodeDetailView(
          episode: route.episode,
          podcastTitle: route.podcastTitle,
          fallbackImageURL: route.fallbackImageURL,
          podcastLanguage: route.podcastLanguage ?? "en"
        )
      }
      .navigationDestination(for: PodcastBrowseRoute.self) { route in
        if let model = route.podcastModel {
          EpisodeListView(podcastModel: model)
        } else {
          EpisodeListView(
            podcastName: route.podcastName,
            podcastArtwork: route.artworkURL,
            artistName: route.artistName,
            collectionId: route.collectionId ?? "",
            applePodcastUrl: route.applePodcastURL
          )
        }
      }
  }
}

#Preview {
  ContentView()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
