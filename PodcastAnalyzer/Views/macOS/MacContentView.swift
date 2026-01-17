//
//  MacContentView.swift
//  PodcastAnalyzer
//
//  macOS-specific content view with sidebar navigation (like Apple Podcasts/Spotify)
//

#if os(macOS)
import SwiftData
import SwiftUI

// MARK: - Sidebar Navigation Item

enum MacSidebarItem: String, CaseIterable, Identifiable, Hashable {
  case home = "Home"
  case library = "Library"
  case search = "Search"
  // Library sub-items with unique identifiers
  case libraryPodcasts = "Library.Podcasts"
  case librarySaved = "Library.Saved"
  case libraryDownloaded = "Library.Downloaded"
  case libraryLatest = "Library.Latest"

  var id: String { rawValue }

  var iconName: String {
    switch self {
    case .home: return "house"
    case .library: return "books.vertical"
    case .search: return "magnifyingglass"
    case .libraryPodcasts: return "square.stack"
    case .librarySaved: return "star.fill"
    case .libraryDownloaded: return "arrow.down.circle.fill"
    case .libraryLatest: return "clock.fill"
    }
  }

  // Convert to LibrarySubItem if applicable
  var librarySubItem: LibrarySubItem? {
    switch self {
    case .libraryPodcasts: return .podcasts
    case .librarySaved: return .saved
    case .libraryDownloaded: return .downloaded
    case .libraryLatest: return .latest
    default: return nil
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
  // Use @State for @Observable to ensure SwiftUI properly tracks changes
  @State private var audioManager = EnhancedAudioManager.shared
  @State private var importManager = PodcastImportManager.shared
  @State private var notificationManager = NotificationNavigationManager.shared
  @Environment(\.modelContext) private var modelContext
  @Environment(\.openSettings) private var openSettings

  @State private var selectedSidebarItem: MacSidebarItem? = .home
  @State private var selectedLibrarySubItem: LibrarySubItem? = .podcasts
  @State private var searchText: String = ""
  @State private var columnVisibility: NavigationSplitViewVisibility = .all

  // For notification navigation
  @State private var notificationEpisode: PodcastEpisodeInfo?
  @State private var notificationPodcastTitle: String = ""
  @State private var notificationImageURL: String?
  @State private var notificationLanguage: String = "en"
  @State private var showNotificationEpisode: Bool = false

  // Track if there's a current episode for mini player
  private var hasCurrentEpisode: Bool {
    audioManager.currentEpisode != nil
  }

  // Mini player height constant for consistent spacing
  private let miniPlayerHeight: CGFloat = 72

  var body: some View {
    // Create bindable references for @Observable singletons
    @Bindable var importManager = importManager

    // Use ZStack to ensure mini player is ALWAYS at the absolute bottom of the window
    ZStack(alignment: .bottom) {
      NavigationSplitView(columnVisibility: $columnVisibility) {
        // Sidebar
        sidebarContent
          .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
      } detail: {
        // Main content area
        mainContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .navigationSplitViewStyle(.balanced)
        // Removed .padding(.bottom) - let miniplayer overlay naturally

      // Mini player at absolute bottom, now fixed-width and centered for floating feel
        if hasCurrentEpisode {
          MacMiniPlayerBar()
            .frame(width: 800) // Fixed width - adjust this value (e.g., 600-1000) to fit your app's typical window
            .padding(.bottom, 20) // Lift from bottom edge
            .background(.ultraThinMaterial) // Blurry glass effect
            .cornerRadius(12) // Rounded corners
            .shadow(radius: 8) // Hover/lift shadow
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    .animation(.easeInOut(duration: 0.25), value: hasCurrentEpisode)
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
        Label("Home", systemImage: "house")
          .tag(MacSidebarItem.home)
      }

      Section("Library") {
        Label {
          Text("Your Podcasts")
        } icon: {
          Image(systemName: "square.stack")
            .foregroundColor(.blue)
        }
        .tag(MacSidebarItem.libraryPodcasts)
        
        Label {
          Text("Saved")
        } icon: {
          Image(systemName: "star.fill")
            .foregroundColor(.yellow)
        }
        .tag(MacSidebarItem.librarySaved)
        
        Label {
          Text("Downloaded")
        } icon: {
          Image(systemName: "arrow.down.circle.fill")
            .foregroundColor(.green)
        }
        .tag(MacSidebarItem.libraryDownloaded)
        
        Label {
          Text("Latest Episodes")
        } icon: {
          Image(systemName: "clock.fill")
            .foregroundColor(.blue)
        }
        .tag(MacSidebarItem.libraryLatest)
      }

      Section {
        Label("Search", systemImage: "magnifyingglass")
          .tag(MacSidebarItem.search)
      }
    }
    .listStyle(.sidebar)
    .navigationTitle("Podcasts")
    .onChange(of: selectedSidebarItem) { _, newValue in
      // Update selectedLibrarySubItem when a library sub-item is selected
      if let subItem = newValue?.librarySubItem {
        selectedLibrarySubItem = subItem
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: {
          openSettings()
        }) {
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
    NavigationStack {
      switch selectedSidebarItem {
      case .home:
        MacHomeContentView()

      case .libraryPodcasts:
        MacLibraryPodcastsView()
      case .librarySaved:
        MacLibrarySavedView()
      case .libraryDownloaded:
        MacLibraryDownloadedView()
      case .libraryLatest:
        MacLibraryLatestView()
      case .library:
        // Fallback to podcasts if somehow .library is selected
        MacLibraryPodcastsView()

      case .search:
        MacSearchView()

      case .none:
        MacHomeContentView()
      }
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
  @State private var viewModel = HomeViewModel()
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
                NavigationLink(
                  destination: EpisodeDetailView(
                    episode: episode.episodeInfo,
                    podcastTitle: episode.podcastTitle,
                    fallbackImageURL: episode.imageURL,
                    podcastLanguage: episode.language
                  )
                ) {
                  MacUpNextCard(episode: episode)
                }
                .buttonStyle(.plain)
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
                NavigationLink(
                  destination: EpisodeListView(
                    podcastName: podcast.name,
                    podcastArtwork: podcast.safeArtworkUrl,
                    artistName: podcast.artistName,
                    collectionId: podcast.id,
                    applePodcastUrl: podcast.url
                  )
                ) {
                  MacTopPodcastRow(podcast: podcast, rank: index + 1)
                }
                .buttonStyle(.plain)
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
  @State private var viewModel = LibraryViewModel(modelContext: nil)
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
            NavigationLink(
              destination: EpisodeListView(podcastModel: podcast)
            ) {
              MacPodcastGridCell(podcast: podcast)
            }
            .buttonStyle(.plain)
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
  @State private var viewModel = LibraryViewModel(modelContext: nil)
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    Group {
      if viewModel.savedEpisodes.isEmpty {
        ContentUnavailableView(
          "No Saved Episodes",
          systemImage: "star",
          description: Text("Star episodes to save them here for later")
        )
      } else {
        List(viewModel.savedEpisodes) { episode in
          NavigationLink(
            destination: EpisodeDetailView(
              episode: episode.episodeInfo,
              podcastTitle: episode.podcastTitle,
              fallbackImageURL: episode.imageURL,
              podcastLanguage: episode.language
            )
          ) {
            MacLibraryEpisodeRow(
              episode: episode.episodeInfo,
              podcastTitle: episode.podcastTitle,
              podcastImageURL: episode.imageURL ?? "",
              podcastLanguage: episode.language
            )
          }
          .contextMenu {
            LibraryEpisodeContextMenu(
              episode: episode,
              modelContext: modelContext,
              onRefresh: { viewModel.setModelContext(modelContext) }
            )
          }
        }
        .listStyle(.plain)
      }
    }
    .navigationTitle("Saved")
    .onAppear {
      viewModel.setModelContext(modelContext)
    }
  }
}

struct MacLibraryDownloadedView: View {
  @State private var viewModel = LibraryViewModel(modelContext: nil)
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    Group {
      if viewModel.downloadedEpisodes.isEmpty {
        ContentUnavailableView(
          "No Downloads",
          systemImage: "arrow.down.circle",
          description: Text("Downloaded episodes will appear here for offline listening")
        )
      } else {
        List(viewModel.downloadedEpisodes) { episode in
          NavigationLink(
            destination: EpisodeDetailView(
              episode: episode.episodeInfo,
              podcastTitle: episode.podcastTitle,
              fallbackImageURL: episode.imageURL,
              podcastLanguage: episode.language
            )
          ) {
            MacLibraryEpisodeRow(
              episode: episode.episodeInfo,
              podcastTitle: episode.podcastTitle,
              podcastImageURL: episode.imageURL ?? "",
              podcastLanguage: episode.language
            )
          }
          .contextMenu {
            LibraryEpisodeContextMenu(
              episode: episode,
              modelContext: modelContext,
              onRefresh: { viewModel.setModelContext(modelContext) }
            )
          }
        }
        .listStyle(.plain)
      }
    }
    .navigationTitle("Downloaded")
    .onAppear {
      viewModel.setModelContext(modelContext)
    }
  }
}

struct MacLibraryLatestView: View {
  @State private var viewModel = LibraryViewModel(modelContext: nil)
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    Group {
      if viewModel.latestEpisodes.isEmpty {
        ContentUnavailableView(
          "No Episodes",
          systemImage: "clock",
          description: Text("Subscribe to podcasts to see latest episodes")
        )
      } else {
        List(viewModel.latestEpisodes) { episode in
          NavigationLink(
            destination: EpisodeDetailView(
              episode: episode.episodeInfo,
              podcastTitle: episode.podcastTitle,
              fallbackImageURL: episode.imageURL,
              podcastLanguage: episode.language
            )
          ) {
            MacLibraryEpisodeRow(
              episode: episode.episodeInfo,
              podcastTitle: episode.podcastTitle,
              podcastImageURL: episode.imageURL ?? "",
              podcastLanguage: episode.language
            )
          }
          .contextMenu {
            LibraryEpisodeContextMenu(
              episode: episode,
              modelContext: modelContext,
              onRefresh: { viewModel.setModelContext(modelContext) }
            )
          }
        }
        .listStyle(.plain)
      }
    }
    .navigationTitle("Latest Episodes")
    .onAppear {
      viewModel.setModelContext(modelContext)
    }
  }
}

struct MacSearchView: View {
  @State private var viewModel = PodcastSearchViewModel()
  @Environment(\.modelContext) private var modelContext
  @Query(filter: #Predicate<PodcastInfoModel> { $0.isSubscribed == true })
  private var subscribedPodcasts: [PodcastInfoModel]

  @State private var selectedTab: SearchTab = .applePodcasts
  @State private var searchText = ""

  var body: some View {
    VStack(spacing: 0) {
      // Tab selector
      tabSelector
        .padding(.horizontal, 16)
        .padding(.top, 8)

      // Search results
      if searchText.isEmpty {
        emptySearchView
      } else {
        switch selectedTab {
        case .applePodcasts:
          applePodcastsResultsView
        case .library:
          libraryResultsView
        }
      }
    }
    .navigationTitle("Search")
    .searchable(text: $searchText, prompt: "Podcasts & Episodes")
    .onSubmit(of: .search) {
      if selectedTab == .applePodcasts {
        viewModel.searchText = searchText
        viewModel.performSearch()
      }
    }
    .onChange(of: searchText) { _, newValue in
      viewModel.searchText = newValue
      if selectedTab == .applePodcasts && !newValue.isEmpty {
        viewModel.performSearch()
      }
    }
    .onChange(of: selectedTab) { _, newTab in
      if newTab == .applePodcasts && !searchText.isEmpty {
        viewModel.searchText = searchText
        viewModel.performSearch()
      }
    }
  }

  // MARK: - Tab Selector

  private var tabSelector: some View {
    HStack(spacing: 0) {
      ForEach(SearchTab.allCases, id: \.self) { tab in
        Button(action: {
          withAnimation(.easeInOut(duration: 0.2)) {
            selectedTab = tab
          }
        }) {
          Text(tab.rawValue)
            .font(.subheadline)
            .fontWeight(selectedTab == tab ? .semibold : .regular)
            .foregroundColor(selectedTab == tab ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
              RoundedRectangle(cornerRadius: 8)
                .fill(selectedTab == tab ? Color.gray.opacity(0.2) : Color.clear)
            )
        }
        .buttonStyle(.plain)
      }
    }
    .padding(4)
    .background(Color.gray.opacity(0.1))
    .cornerRadius(10)
  }

  // MARK: - Empty Search View

  private var emptySearchView: some View {
    VStack(spacing: 16) {
      Spacer()
      Image(systemName: "magnifyingglass")
        .font(.system(size: 50))
        .foregroundColor(.secondary)
      Text("Search for podcasts")
        .font(.title3)
        .foregroundColor(.secondary)
      Text(selectedTab == .applePodcasts
           ? "Find new podcasts to subscribe"
           : "Search your subscribed podcasts and episodes")
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
      Spacer()
    }
  }

  // MARK: - Apple Podcasts Results

  private var applePodcastsResultsView: some View {
    Group {
      if viewModel.isLoading {
        VStack {
          Spacer()
          ProgressView("Searching...")
          Spacer()
        }
      } else if viewModel.podcasts.isEmpty {
        VStack {
          Spacer()
          Text("No results found")
            .foregroundColor(.secondary)
          Spacer()
        }
      } else {
        List {
          ForEach(viewModel.podcasts, id: \.collectionId) { podcast in
            NavigationLink(destination: EpisodeListView(
              podcastName: podcast.collectionName,
              podcastArtwork: podcast.artworkUrl100 ?? "",
              artistName: podcast.artistName,
              collectionId: String(podcast.collectionId),
              applePodcastUrl: nil
            )) {
              MacApplePodcastRow(
                podcast: podcast,
                isSubscribed: isSubscribed(podcast),
                onSubscribe: { subscribeToPodcast(podcast) }
              )
            }
            .buttonStyle(.plain)
          }
        }
        .listStyle(.plain)
      }
    }
  }

  // MARK: - Library Results

  private var libraryResultsView: some View {
    let filteredPodcasts = filterLibraryPodcasts()
    let filteredEpisodes = filterLibraryEpisodes()

    return Group {
      if filteredPodcasts.isEmpty && filteredEpisodes.isEmpty {
        VStack {
          Spacer()
          Text("No results in your library")
            .foregroundColor(.secondary)
          Spacer()
        }
      } else {
        List {
          // Podcasts section
          if !filteredPodcasts.isEmpty {
            Section {
              ForEach(filteredPodcasts) { podcastModel in
                NavigationLink {
                  EpisodeListView(podcastModel: podcastModel)
                } label: {
                  MacLibraryPodcastRow(podcastModel: podcastModel)
                }
              }
            }
          }

          // Episodes section
          if !filteredEpisodes.isEmpty {
            Section {
              ForEach(filteredEpisodes, id: \.uniqueId) { item in
                NavigationLink {
                  EpisodeDetailView(
                    episode: item.episode,
                    podcastTitle: item.podcastTitle,
                    fallbackImageURL: item.podcastImageURL,
                    podcastLanguage: item.podcastLanguage
                  )
                } label: {
                  MacLibraryEpisodeRow(
                    episode: item.episode,
                    podcastTitle: item.podcastTitle,
                    podcastImageURL: item.podcastImageURL,
                    podcastLanguage: item.podcastLanguage
                  )
                }
              }
            }
          }
        }
        .listStyle(.plain)
      }
    }
  }

  // MARK: - Helper Methods

  private func isSubscribed(_ podcast: Podcast) -> Bool {
    subscribedPodcasts.contains { $0.podcastInfo.title == podcast.collectionName }
  }

  private func subscribeToPodcast(_ podcast: Podcast) {
    guard let feedUrl = podcast.feedUrl else { return }

    Task {
      do {
        let rssService = PodcastRssService()
        let podcastInfo = try await rssService.fetchPodcast(from: feedUrl)
        let podcastInfoModel = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date.now)

        await MainActor.run {
          modelContext.insert(podcastInfoModel)
          try? modelContext.save()
        }
      } catch {
        print("Failed to subscribe: \(error)")
      }
    }
  }

  private func filterLibraryPodcasts() -> [PodcastInfoModel] {
    let query = searchText.lowercased()
    return subscribedPodcasts.filter { podcast in
      podcast.podcastInfo.title.lowercased().contains(query)
    }
  }

  private func filterLibraryEpisodes() -> [(uniqueId: String, episode: PodcastEpisodeInfo, podcastTitle: String, podcastImageURL: String, podcastLanguage: String)] {
    let query = searchText.lowercased()
    var results: [(uniqueId: String, episode: PodcastEpisodeInfo, podcastTitle: String, podcastImageURL: String, podcastLanguage: String)] = []

    for podcast in subscribedPodcasts {
      let matchingEpisodes = podcast.podcastInfo.episodes.filter { episode in
        episode.title.lowercased().contains(query) ||
        (episode.podcastEpisodeDescription?.lowercased().contains(query) ?? false)
      }

      for episode in matchingEpisodes {
        // Create unique ID using podcast title + episode title
        let uniqueId = "\(podcast.podcastInfo.title)\u{1F}\(episode.title)"
        results.append((
          uniqueId: uniqueId,
          episode: episode,
          podcastTitle: podcast.podcastInfo.title,
          podcastImageURL: podcast.podcastInfo.imageURL,
          podcastLanguage: podcast.podcastInfo.language
        ))
      }
    }

    return results
  }
}

// MARK: - Mac Apple Podcast Row

struct MacApplePodcastRow: View {
  let podcast: Podcast
  let isSubscribed: Bool
  let onSubscribe: () -> Void

  @State private var isSubscribing = false

  var body: some View {
    HStack(spacing: 12) {
      CachedArtworkImage(urlString: podcast.artworkUrl100, size: 56, cornerRadius: 8)

      VStack(alignment: .leading, spacing: 2) {
        Text(podcast.collectionName)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(1)
          .foregroundColor(.primary)

        Text("Show · \(podcast.artistName)")
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
      }

      Spacer()

      if isSubscribed {
        Image(systemName: "checkmark")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.green)
      } else if isSubscribing {
        ProgressView()
          .scaleEffect(0.8)
      } else {
        Button(action: {
          isSubscribing = true
          onSubscribe()
          DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isSubscribing = false
          }
        }) {
          Image(systemName: "plus")
            .font(.title3)
            .foregroundColor(.blue)
        }
        .buttonStyle(.plain)
      }

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }
}

// MARK: - Mac Library Podcast Row

struct MacLibraryPodcastRow: View {
  let podcastModel: PodcastInfoModel

  var body: some View {
    HStack(spacing: 12) {
      CachedArtworkImage(urlString: podcastModel.podcastInfo.imageURL, size: 56, cornerRadius: 8)

      VStack(alignment: .leading, spacing: 2) {
        Text(podcastModel.podcastInfo.title)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(1)

        Text("Show · \(podcastModel.podcastInfo.episodes.count) episodes")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      Image(systemName: "checkmark")
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundColor(.primary)
    }
    .padding(.vertical, 4)
  }
}

// MARK: - Mac Library Episode Row

struct MacLibraryEpisodeRow: View {
  let episode: PodcastEpisodeInfo
  let podcastTitle: String
  let podcastImageURL: String
  let podcastLanguage: String

  private var audioManager: EnhancedAudioManager { EnhancedAudioManager.shared }

  var body: some View {
    HStack(spacing: 12) {
      CachedArtworkImage(urlString: episode.imageURL ?? podcastImageURL, size: 56, cornerRadius: 8)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 4) {
          if let date = episode.pubDate {
            Text(date.formatted(date: .abbreviated, time: .omitted))
          }
          if let duration = episode.formattedDuration {
            Text("·")
            Text(duration)
          }
        }
        .font(.caption2)
        .foregroundColor(.secondary)

        Text(episode.title)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(1)
      }

      Spacer()

      if episode.audioURL != nil {
        Button(action: {
          playEpisode()
        }) {
          Image(systemName: "play.fill")
            .font(.title3)
            .foregroundColor(.white)
            .frame(width: 32, height: 32)
            .background(Color.purple)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 4)
  }

  private func playEpisode() {
    guard let audioURL = episode.audioURL else { return }

    let playbackEpisode = PlaybackEpisode(
      id: "\(podcastTitle)\u{1F}\(episode.title)",
      title: episode.title,
      podcastTitle: podcastTitle,
      audioURL: audioURL,
      imageURL: episode.imageURL ?? podcastImageURL,
      episodeDescription: episode.podcastEpisodeDescription,
      pubDate: episode.pubDate,
      duration: episode.duration,
      guid: episode.guid
    )

    audioManager.play(
      episode: playbackEpisode,
      audioURL: audioURL,
      startTime: 0,
      imageURL: episode.imageURL ?? podcastImageURL,
      useDefaultSpeed: true
    )
  }
}

#endif
