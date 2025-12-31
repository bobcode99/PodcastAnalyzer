//
//  MacContentView.swift
//  PodcastAnalyzer
//
//  macOS-specific content view with sidebar navigation (like Apple Podcasts/Spotify)
//

#if os(macOS)
import Combine
import SwiftData
import SwiftUI

// MARK: - Sidebar Navigation Item

enum MacSidebarItem: String, CaseIterable, Identifiable {
  case home = "Home"
  case library = "Library"
  case search = "Search"

  var id: String { rawValue }

  var iconName: String {
    switch self {
    case .home: return "house"
    case .library: return "books.vertical"
    case .search: return "magnifyingglass"
    }
  }
}

// MARK: - Library Sub-items

enum LibrarySubItem: String, CaseIterable, Identifiable {
  case podcasts = "Your Podcasts"
  case saved = "Saved"
  case downloaded = "Downloaded"
  case latest = "Latest Episodes"

  var id: String { rawValue }

  var iconName: String {
    switch self {
    case .podcasts: return "square.stack"
    case .saved: return "star.fill"
    case .downloaded: return "arrow.down.circle.fill"
    case .latest: return "clock.fill"
    }
  }

  var iconColor: Color {
    switch self {
    case .podcasts: return .blue
    case .saved: return .yellow
    case .downloaded: return .green
    case .latest: return .blue
    }
  }
}

// MARK: - macOS Content View

struct MacContentView: View {
  @State private var audioManager = EnhancedAudioManager.shared
  @ObservedObject private var importManager = PodcastImportManager.shared
  @ObservedObject private var notificationManager = NotificationNavigationManager.shared
  @Environment(\.modelContext) private var modelContext

  @State private var selectedSidebarItem: MacSidebarItem? = .home
  @State private var selectedLibrarySubItem: LibrarySubItem?
  @State private var searchText: String = ""
  @State private var columnVisibility: NavigationSplitViewVisibility = .all

  // For notification navigation
  @State private var notificationEpisode: PodcastEpisodeInfo?
  @State private var notificationPodcastTitle: String = ""
  @State private var notificationImageURL: String?
  @State private var notificationLanguage: String = "en"
  @State private var showNotificationEpisode: Bool = false

  private var showMiniPlayer: Bool {
    audioManager.currentEpisode != nil
  }

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      // Sidebar
      sidebarContent
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    } detail: {
      // Main content area
      VStack(spacing: 0) {
        mainContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        // Mini player at bottom
        if showMiniPlayer {
          MacMiniPlayerBar()
        }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 900, minHeight: 600)
    .onAppear {
      audioManager.restoreLastEpisode()
    }
    .sheet(isPresented: $importManager.showImportSheet) {
      PodcastImportSheet()
        .frame(minWidth: 400, minHeight: 300)
    }
    .onChange(of: notificationManager.shouldNavigate) { _, shouldNavigate in
      if shouldNavigate, let target = notificationManager.navigationTarget {
        handleNotificationNavigation(target: target)
      }
    }
  }

  // MARK: - Sidebar Content

  @ViewBuilder
  private var sidebarContent: some View {
    List(selection: $selectedSidebarItem) {
      Section("Browse") {
        ForEach([MacSidebarItem.home], id: \.id) { item in
          Label(item.rawValue, systemImage: item.iconName)
            .tag(item)
        }
      }

      Section("Library") {
        ForEach(LibrarySubItem.allCases) { subItem in
          Label {
            Text(subItem.rawValue)
          } icon: {
            Image(systemName: subItem.iconName)
              .foregroundColor(subItem.iconColor)
          }
          .tag(MacSidebarItem.library)
          .onTapGesture {
            selectedSidebarItem = .library
            selectedLibrarySubItem = subItem
          }
        }
      }

      Section {
        Label("Search", systemImage: "magnifyingglass")
          .tag(MacSidebarItem.search)
      }
    }
    .listStyle(.sidebar)
    .navigationTitle("Podcasts")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: {}) {
          Image(systemName: "gearshape")
        }
        .help("Settings")
        .keyboardShortcut(",", modifiers: .command)
      }
    }
  }

  // MARK: - Main Content

  @ViewBuilder
  private var mainContent: some View {
    switch selectedSidebarItem {
    case .home:
      MacHomeContentView()

    case .library:
      if let subItem = selectedLibrarySubItem {
        switch subItem {
        case .podcasts:
          MacLibraryPodcastsView()
        case .saved:
          MacLibrarySavedView()
        case .downloaded:
          MacLibraryDownloadedView()
        case .latest:
          MacLibraryLatestView()
        }
      } else {
        MacLibraryPodcastsView()
      }

    case .search:
      MacSearchView()

    case .none:
      MacHomeContentView()
    }
  }

  // MARK: - Notification Navigation

  private func handleNotificationNavigation(target: NotificationNavigationTarget) {
    if let result = notificationManager.findEpisode(
      podcastTitle: target.podcastTitle,
      episodeTitle: target.episodeTitle
    ) {
      notificationEpisode = result.episode
      notificationPodcastTitle = target.podcastTitle
      notificationImageURL = result.imageURL
      notificationLanguage = result.language
      showNotificationEpisode = true
    }
    notificationManager.clearNavigation()
  }
}

// MARK: - Placeholder Views (to be implemented)

struct MacHomeContentView: View {
  @StateObject private var viewModel = HomeViewModel()
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        // Up Next Section
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text("Up Next")
              .font(.title2)
              .fontWeight(.bold)
            Spacer()
            if !viewModel.upNextEpisodes.isEmpty {
              Button("See All") {}
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
          }

          if viewModel.upNextEpisodes.isEmpty {
            ContentUnavailableView(
              "No Unplayed Episodes",
              systemImage: "play.circle",
              description: Text("Subscribe to podcasts to see new episodes here")
            )
            .frame(height: 200)
          } else {
            LazyVGrid(columns: [
              GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)
            ], spacing: 16) {
              ForEach(viewModel.upNextEpisodes.prefix(8)) { episode in
                MacUpNextCard(episode: episode)
              }
            }
          }
        }
        .padding(.horizontal, 24)

        // Popular Shows Section
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text("Popular Shows")
              .font(.title2)
              .fontWeight(.bold)

            Spacer()

            // Region picker
            Picker("Region", selection: $viewModel.selectedRegion) {
              ForEach(Constants.podcastRegions, id: \.code) { region in
                Text(region.name).tag(region.code)
              }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
          }

          if viewModel.topPodcasts.isEmpty && !viewModel.isLoadingTopPodcasts {
            ContentUnavailableView(
              "Unable to Load",
              systemImage: "chart.line.uptrend.xyaxis",
              description: Text("Check your internet connection")
            )
            .frame(height: 200)
          } else {
            LazyVGrid(columns: [
              GridItem(.flexible(), spacing: 12),
              GridItem(.flexible(), spacing: 12)
            ], spacing: 8) {
              ForEach(Array(viewModel.topPodcasts.enumerated()), id: \.element.id) { index, podcast in
                MacTopPodcastRow(podcast: podcast, rank: index + 1)
              }
            }
          }
        }
        .padding(.horizontal, 24)
      }
      .padding(.vertical, 24)
    }
    .navigationTitle("Home")
    .onAppear {
      viewModel.setModelContext(modelContext)
    }
  }
}

struct MacUpNextCard: View {
  let episode: LibraryEpisode

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      CachedArtworkImage(urlString: episode.imageURL, size: 160, cornerRadius: 12)

      Text(episode.podcastTitle)
        .font(.caption)
        .foregroundColor(.secondary)
        .lineLimit(1)

      Text(episode.episodeInfo.title)
        .font(.subheadline)
        .fontWeight(.medium)
        .lineLimit(2)

      if let duration = episode.episodeInfo.formattedDuration {
        Text(duration)
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
    .frame(width: 180)
    .contentShape(Rectangle())
  }
}

struct MacTopPodcastRow: View {
  let podcast: AppleRSSPodcast
  let rank: Int

  var body: some View {
    HStack(spacing: 12) {
      Text("\(rank)")
        .font(.headline)
        .foregroundColor(.secondary)
        .frame(width: 24)

      CachedArtworkImage(urlString: podcast.artworkUrl100, size: 50, cornerRadius: 8)

      VStack(alignment: .leading, spacing: 2) {
        Text(podcast.name)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(1)

        Text(podcast.artistName)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
      }

      Spacer()
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
  }
}

struct MacLibraryPodcastsView: View {
  @StateObject private var viewModel = LibraryViewModel(modelContext: nil)
  @Environment(\.modelContext) private var modelContext

  private let columns = [
    GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 16)
  ]

  var body: some View {
    ScrollView {
      if viewModel.podcastsSortedByRecentUpdate.isEmpty {
        ContentUnavailableView(
          "No Subscriptions",
          systemImage: "square.stack.3d.up",
          description: Text("Search and subscribe to podcasts to build your library")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        LazyVGrid(columns: columns, spacing: 20) {
          ForEach(viewModel.podcastsSortedByRecentUpdate) { podcast in
            MacPodcastGridCell(podcast: podcast)
          }
        }
        .padding(24)
      }
    }
    .navigationTitle("Your Podcasts")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: {
          Task { await viewModel.refreshAllPodcasts() }
        }) {
          Image(systemName: "arrow.clockwise")
        }
        .disabled(viewModel.isLoading)
      }
    }
    .onAppear {
      viewModel.setModelContext(modelContext)
    }
  }
}

struct MacPodcastGridCell: View {
  let podcast: PodcastInfoModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      CachedArtworkImage(urlString: podcast.podcastInfo.imageURL, size: 150, cornerRadius: 10)

      Text(podcast.podcastInfo.title)
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(2)
    }
    .frame(width: 150)
  }
}

struct MacLibrarySavedView: View {
  var body: some View {
    ContentUnavailableView(
      "No Saved Episodes",
      systemImage: "star",
      description: Text("Star episodes to save them here for later")
    )
    .navigationTitle("Saved")
  }
}

struct MacLibraryDownloadedView: View {
  var body: some View {
    ContentUnavailableView(
      "No Downloads",
      systemImage: "arrow.down.circle",
      description: Text("Downloaded episodes will appear here for offline listening")
    )
    .navigationTitle("Downloaded")
  }
}

struct MacLibraryLatestView: View {
  var body: some View {
    ContentUnavailableView(
      "No Episodes",
      systemImage: "clock",
      description: Text("Subscribe to podcasts to see latest episodes")
    )
    .navigationTitle("Latest Episodes")
  }
}

struct MacSearchView: View {
  @State private var searchText = ""

  var body: some View {
    VStack {
      if searchText.isEmpty {
        ContentUnavailableView(
          "Search Podcasts",
          systemImage: "magnifyingglass",
          description: Text("Find new podcasts to subscribe")
        )
      } else {
        Text("Search results for: \(searchText)")
      }
    }
    .navigationTitle("Search")
    .searchable(text: $searchText, prompt: "Podcasts")
  }
}

#endif
