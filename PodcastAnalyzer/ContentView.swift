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

  // Tab selection + per-tab NavigationPath for programmatic pushes
  @State private var selectedTab = 0
  @State private var homePath = NavigationPath()
  @State private var libraryPath = NavigationPath()
  @State private var settingsPath = NavigationPath()
  @State private var searchPath = NavigationPath()

  // Navigation state for expanded player navigation (set by MiniPlayerBar on dismiss)
  @State private var expandedPlayerNavigation: ExpandedPlayerNavigation = .none

  var body: some View {
    TabView(selection: $selectedTab) {
      Tab(Constants.homeString, systemImage: Constants.homeIconName, value: 0) {
        NavigationStack(path: $homePath) {
          HomeView()
            .navigationDestinations()
        }
      }

      Tab(Constants.libraryString, systemImage: Constants.libraryIconName, value: 1) {
        NavigationStack(path: $libraryPath) {
          LibraryView()
            .navigationDestinations()
        }
      }

      Tab(Constants.settingsString, systemImage: Constants.settingsIconName, value: 2) {
        NavigationStack(path: $settingsPath) {
          SettingsView()
            .navigationDestinations()
        }
      }

      Tab(value: 3) {
        NavigationStack(path: $searchPath) {
          PodcastSearchView()
            .navigationDestinations()
        }
      } label: {
        Label("Search", systemImage: "magnifyingglass")
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

  /// Returns a binding to the currently selected tab's NavigationPath.
  private var currentPath: Binding<NavigationPath> {
    switch selectedTab {
    case 0: return $homePath
    case 1: return $libraryPath
    case 2: return $settingsPath
    default: return $searchPath
    }
  }

  private func handleNotificationNavigation(target: NotificationNavigationTarget) {
    let route: EpisodeDetailRoute
    if let result = notificationManager.findEpisode(
      podcastTitle: target.podcastTitle,
      episodeTitle: target.episodeTitle
    ) {
      route = EpisodeDetailRoute(
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
      route = EpisodeDetailRoute(
        episode: episode,
        podcastTitle: target.podcastTitle,
        fallbackImageURL: target.imageURL.isEmpty ? nil : target.imageURL,
        podcastLanguage: target.language
      )
    }

    // Push to the current tab's navigation stack
    selectedTab = 0
    homePath.append(route)
    notificationManager.clearNavigation()
  }

  private func handleExpandedPlayerNavigation(_ navigation: ExpandedPlayerNavigation) {
    switch navigation {
    case .none:
      break
    case let .episodeDetail(episode, podcastTitle, imageURL):
      currentPath.wrappedValue.append(
        EpisodeDetailRoute(
          episode: episode,
          podcastTitle: podcastTitle,
          fallbackImageURL: imageURL,
          podcastLanguage: nil
        )
      )
      expandedPlayerNavigation = .none
    case let .podcastEpisodeList(podcastModel):
      currentPath.wrappedValue.append(
        PodcastBrowseRoute(podcastModel: podcastModel)
      )
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

// MARK: - Navigation Destinations

extension View {
  /// Registers type-based navigationDestination handlers for the shared route types.
  /// Called on each tab's root view inside its NavigationStack.
  ///
  /// Both NavigationLink(value:) pushes and programmatic NavigationPath.append()
  /// pushes resolve through these same `for:` handlers — no `isPresented:` needed.
  func navigationDestinations() -> some View {
    self
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
