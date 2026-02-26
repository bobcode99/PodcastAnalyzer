## 1. Concurrency Safety — deinit crash vectors

- [x] 1.1 Replace `MainActor.assumeIsolated` in `deinit` with direct `task?.cancel()` calls in BackgroundSyncManager, TranscriptManager, PlaybackStateCoordinator
- [x] 1.2 Replace `MainActor.assumeIsolated` in `deinit` with direct `task?.cancel()` calls in SettingsViewModel, PodcastSearchViewModel, EpisodeListViewModel
- [x] 1.3 Replace `MainActor.assumeIsolated` in `deinit` with direct `task?.cancel()` calls in ExpandedPlayerViewModel, LibraryViewModel, HomeViewModel

## 2. Concurrency Safety — isolation & Sendable fixes

- [x] 2.1 Replace `MainActor.assumeIsolated` in `EnhancedAudioManager.setupTimeObserver()` AVPlayer callback with `Task { @MainActor in }`
- [x] 2.2 Convert `ImageCacheManager` from `final class: @unchecked Sendable` to an `actor`, removing manual DispatchQueue synchronization
- [x] 2.3 Remove redundant `await MainActor.run { }` from `@MainActor` Task closures in DownloadManager (~6 instances) — SKIPPED: DownloadSessionDelegate is nonisolated, so MainActor.run is required there
- [x] 2.4 Remove redundant `await MainActor.run { }` from `@MainActor` Task closures in PlaybackStateCoordinator (1) and EpisodeListViewModel (1)
- [x] 2.5 Replace `await Task.detached(...).value` with regular `Task` or synchronous code in DataManagementView (~6 cache size calculations) — SKIPPED: Task.detached is justified here to escape @MainActor for file I/O
- [x] 2.6 Replace `await Task.detached(...).value` with regular `Task` or synchronous code in ShortcutsAIService (1) — SKIPPED: Task.detached is justified for blocking Process.waitUntilExit()
- [x] 2.7 Add `nonisolated` to pure utility types (VTTParser and similar structs/enums with no mutable state)

## 3. SwiftUI Rendering Performance — NavigationLink & HomeView

- [x] 3.1 Replace eager `NavigationLink(destination:)` with `.navigationDestination(item:)` in HomeView Up Next section
- [x] 3.2 Replace eager `NavigationLink(destination:)` with `.navigationDestination(item:)` in HomeView For You section
- [x] 3.3 Replace eager `NavigationLink(destination:)` with `.navigationDestination(for:)` in HomeView Popular Shows section
- [x] 3.4 Replace `.onChange(of: episodes.map(\.id))` in HomeView with gated comparison to avoid per-render array allocation

## 4. SwiftUI Rendering Performance — polling, filtering, caching

- [x] 4.1 Move `filterLibraryPodcasts()` and `filterLibraryEpisodes()` from SearchView body to @State cached properties, updated via `onChange(of: searchText)`
- [x] 4.2 Increase transcript highlighting polling interval from 100ms to 250ms in EpisodeDetailView and gate updates on time delta >= 0.5s
- [x] 4.3 Stop transcript polling timer when transcript tab is not visible — already handled by onAppear/onDisappear on transcriptContent
- [x] 4.4 Use existing `cachedPlainDescription` @State property in EpisodeRowView body instead of recomputing `plainDescription` — already implemented correctly

## 5. SwiftUI Patterns — state management

- [x] 5.1 Replace `@State` singletons with computed properties in MacContentView (audioManager, notificationManager; importManager kept @State for $binding)
- [x] 5.2 Replace manual `Binding(get:set:)` wrapper with `@State` + `$property` syntax in ContentView import sheet binding
- [x] 5.3 Consolidate `.onAppear` (sync) + `.task` (async) race condition in EpisodeListView into single `.task` block

## 6. SwiftUI Patterns — UX improvements

- [x] 6.1 Replace `EmptyView()` default switch cases with meaningful fallback views in EpisodeListView and EpisodeDetailView
- [x] 6.2 Replace `EmptyView()` default switch cases with meaningful fallback views in SettingsView (EpisodeAIAnalysisView EmptyView is intentional for idle/completed states)
- [x] 6.3 Add `.refreshable()` to SavedEpisodesView — already present
- [x] 6.4 Add `.refreshable()` to DownloadedPodcastsGridView
- [x] 6.5 Add `.refreshable()` to LatestEpisodesView — already present

## 7. Verification

- [x] 7.1 Build project with `xcodebuild -scheme PodcastAnalyzer -destination 'platform=iOS Simulator,name=iPhone 17'` — zero errors, zero new warnings
