## 1. Performance — Hot Path Fixes (Critical/High)

- [x] 1.1 Cache `filteredEpisodes` as stored property in `EpisodeListViewModel` with `didSet` recomputation on `selectedFilter`, `sortOldestFirst`, `searchText`, `episodeModels`
- [x] 1.2 Cache SwiftData query in `EpisodeDetailHeaderView.podcastDestination` — add `@State cachedPodcastModel`, fetch in `.task`, read from cache
- [x] 1.3 Cache SwiftData query in `LibraryView.LibraryEpisodeContextMenu.goToShowButton` — add `@State`, fetch in `.onAppear`
- [x] 1.4 Guard transcript playback timer in `EpisodeDetailView` — skip `currentPlaybackTime` assignment when time diff < 0.5s and sentence unchanged; skip when paused
- [x] 1.5 Cache `plainDescription` in `EpisodeRowView` — add `@State cachedPlainDescription`, compute in `.onAppear`
- [x] 1.6 Compute `EpisodeStatusChecker` once per body in `EpisodeRowView` — replace computed `var statusChecker` with local `let` in body or single computed access
- [x] 1.7 Remove 5-second polling timer in `EpisodeListViewModel` — delete `startRefreshTimer()`/`stopRefreshTimer()`, rely on existing notification observer
- [x] 1.8 Remove no-op `.onChange(of: audioManager.currentTime/isPlaying)` handlers in `ReactiveEpisodePlayButton`
- [x] 1.9 Remove `image = nil` from `CachedAsyncImage.onDisappear`
- [x] 1.10 Cache `RelativeDateTimeFormatter` as `static let` in `PodcastGridCell`

## 2. Performance — Batch SwiftData Queries (Medium)

- [x] 2.1 Batch `fetchEpisodeModel(for:)` in `HomeView.UpNextListView` — single query in `.onAppear`, pass dictionary to rows
- [x] 2.2 Batch `fetchEpisodeModel(for:)` in `LibraryView.SavedEpisodesView` — same pattern
- [x] 2.3 Batch `fetchEpisodeModel(for:)` in `LibraryView.DownloadedEpisodesView` — same pattern
- [x] 2.4 Batch `fetchEpisodeModel(for:)` in `LibraryView.LatestEpisodesView` — same pattern

## 3. State Management Fixes

- [x] 3.1 Replace `@Bindable private var downloadManager` with computed property in `EpisodeListView`
- [x] 3.2 Replace `@State private var settings` with `@Bindable` in `AISettingsView`
- [x] 3.3 Replace `@State private var settingsViewModel = SettingsViewModel()` with `@AppStorage("showEpisodeArtwork")` in `LibraryView`
- [x] 3.4 Replace `@State private var settingsViewModel = SettingsViewModel()` with `@AppStorage("showEpisodeArtwork")` in `EpisodeListView`
- [x] 3.5 Add `private` to `@Environment(\.modelContext)` in `SettingsView`
- [x] 3.6 Change `var downloadManager` to `let downloadManager` in `EpisodeRowView`

## 4. Modern API Migration

- [x] 4.1 Replace `showsIndicators: false` with `.scrollIndicators(.hidden)` in `ExpandedPlayerView`
- [x] 4.2 Replace `showsIndicators: false` with `.scrollIndicators(.hidden)` in `HomeView` (2 occurrences)
- [x] 4.3 Replace `showsIndicators: false` with `.scrollIndicators(.hidden)` in `EpisodeListView`
- [x] 4.4 Replace `showsIndicators: false` with `.scrollIndicators(.hidden)` in `EpisodeAIAnalysisView`
- [x] 4.5 Replace `withAnimation { }` with `withAnimation(.easeInOut(duration: 0.2)) { }` in `EpisodeListView`

## 5. Accessibility Labels

- [x] 5.1 Add `.accessibilityLabel` to play/pause button in `MiniPlayerBar`
- [x] 5.2 Add `.accessibilityLabel` to translate button and ellipsis menu in `EpisodeDetailView` toolbar
- [x] 5.3 Add `.accessibilityLabel` to auto-scroll, settings, and options buttons in `EpisodeDetailView` transcript header
- [x] 5.4 Add `.accessibilityLabel` to ellipsis menu in `EpisodeRowView`

## 6. View Composition Cleanup

- [x] 6.1 Remove dead `showMiniPlayer` computed property and `if` conditional in `ContentView`
- [x] 6.2 Replace hardcoded `"1.0.0"` with `Bundle.main` version lookup in `SettingsView`
- [x] 6.3 Replace force-unwrap `URL(string:)!` with optional binding in `HomeView` (3 occurrences)
- [x] 6.4 Add `refreshRecommendations()` method to `HomeViewModel` and call from view instead of direct mutation

## 7. Build Verification

- [x] 7.1 Build for iOS Simulator after each task group and verify zero errors
- [x] 7.2 Final full build verification after all changes
