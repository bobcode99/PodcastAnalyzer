## Why

A comprehensive four-skill SwiftUI audit (expert review, modern API, performance, UI patterns) revealed critical performance bottlenecks, state management anti-patterns, and deprecated API usage across the codebase. Several hot-path views execute SwiftData queries, regex operations, and O(n) computations inside `body` — some firing 10x/second due to playback timers. Fixing these now prevents compounding performance debt as the app grows.

## What Changes

**Performance (Critical/High)**
- Cache `filteredEpisodes` as stored property in `EpisodeListViewModel` instead of recomputing filter+sort on every body access
- Cache SwiftData query results in `EpisodeDetailHeaderView.podcastDestination` and `LibraryView.goToShowButton` via `@State` + `.onAppear` instead of fetching inside `@ViewBuilder` body
- Guard 100ms transcript playback timer — only assign `currentPlaybackTime` when the active sentence actually changes (eliminates O(n) sentence scan 10x/sec)
- Cache `plainDescription` HTML strip in `EpisodeRowView` with `@State` + `.onAppear` instead of regex in body
- Remove 5-second SwiftData polling timer in `EpisodeListViewModel` — rely on existing download notification observer
- Batch `fetchEpisodeModel(for:)` into single query in `onAppear` instead of N+1 per-row SwiftData fetches (HomeView, LibraryView)
- Remove no-op `.onChange(of: audioManager.currentTime)` in deprecated `ReactiveEpisodePlayButton` that forces re-render on every AVPlayer tick
- Remove `image = nil` in `CachedAsyncImage.onDisappear` to fix placeholder flash during scrolling
- Cache `RelativeDateTimeFormatter` as static in `PodcastGridCell` instead of instantiating per render
- Cache `EpisodeStatusChecker` — compute once instead of 4+ instantiations per `EpisodeRowView` render

**State Management**
- Replace `@Bindable` with computed property on `DownloadManager.shared` in `EpisodeListView` (no `$` binding used)
- Replace `@State` with `@Bindable` on `AISettingsManager.shared` in `AISettingsView` (needs `$` bindings)
- Replace fresh `SettingsViewModel()` instances with `@AppStorage("showEpisodeArtwork")` in `LibraryView` and `EpisodeListView`
- Add `private` to `@Environment(\.modelContext)` in `SettingsView`
- Change `var downloadManager` to `let downloadManager` in `EpisodeRowView`

**Modern API Migration**
- Replace `showsIndicators: false` with `.scrollIndicators(.hidden)` across 5 occurrences
- Replace `withAnimation { }` with `withAnimation(.default) { }` in `EpisodeListView`
- Add accessibility labels to all icon-only buttons (MiniPlayerBar, EpisodeDetailView toolbar, EpisodeRowView menu)

**View Composition Cleanup**
- Remove dead `showMiniPlayer` computed property in `ContentView` (always returns `true`)
- Replace hardcoded `"1.0.0"` version string in `SettingsView` with `Bundle.main` lookup
- Replace force-unwrap `URL(string:)!` with optional binding in `HomeView`
- Add `refreshRecommendations()` method to `HomeViewModel` — view should call method, not mutate internals

## Capabilities

### New Capabilities
- `swiftui-performance-fixes`: Performance optimizations covering cached computations, eliminated polling, batched SwiftData queries, and guarded timer updates
- `swiftui-state-management-fixes`: Corrected property wrapper usage (@Bindable, @State, @AppStorage) and access modifiers
- `swiftui-modern-api-migration`: Deprecated API replacements and accessibility improvements
- `swiftui-view-composition-cleanup`: Dead code removal, safety fixes, and view composition improvements

### Modified Capabilities

## Impact

- **Files affected (~15):** `EpisodeListView.swift`, `EpisodeListViewModel.swift`, `EpisodeDetailView.swift`, `EpisodeDetailHeaderView.swift`, `EpisodeRowView.swift`, `LibraryView.swift`, `HomeView.swift`, `HomeViewModel.swift`, `ContentView.swift`, `SettingsView.swift`, `AISettingsView.swift`, `ExpandedPlayerView.swift`, `EpisodeAIAnalysisView.swift`, `CachedAsyncImage.swift`, `EpisodePlayButtonWithProgress.swift`, `MiniPlayerBar.swift`
- **No API changes**: All fixes are internal — no public interface or data model changes
- **No dependency changes**: Pure SwiftUI/SwiftData refactoring
- **Risk**: Low-medium — changes are isolated per-file with clear before/after; build verification after each batch
