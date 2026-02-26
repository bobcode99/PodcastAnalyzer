## Why

Time Profiler, code review, and static analysis across the codebase reveal three categories of issues impacting reliability, performance, and maintainability:

1. **Crash risk from `MainActor.assumeIsolated` in deinit** — 9 ViewModels/Services call `MainActor.assumeIsolated` inside `deinit`, which runs on arbitrary threads. These are intermittent crash vectors (`EXC_BREAKPOINT` / `dispatch_assert_queue_fail`).
2. **SwiftUI rendering inefficiency** — Eager `NavigationLink` destination creation (10+ heavy views instantiated per scroll), 100ms polling loops, O(n²) inline filtering in view body, and `.onChange` allocating arrays every render cause visible jank and battery drain.
3. **Swift 6 concurrency anti-patterns** — `@unchecked Sendable` on `ImageCacheManager`, `await Task.detached(...).value` (defeats detachment purpose), redundant `await MainActor.run` from already-`@MainActor` contexts, and missing `nonisolated` markers on pure utility types.

## What Changes

### Concurrency Safety
- Replace all 9 `MainActor.assumeIsolated` in `deinit` with direct `Task.cancel()` calls (which are thread-safe)
- Replace `MainActor.assumeIsolated` in AVPlayer's `addPeriodicTimeObserver` callback with `Task { @MainActor in }`
- Migrate `ImageCacheManager` from `@unchecked Sendable` to proper actor-based or Mutex-based isolation
- Remove redundant `await MainActor.run { }` from already-`@MainActor` Task closures (~6 instances in DownloadManager, PlaybackStateCoordinator)
- Replace `await Task.detached(...).value` anti-pattern with regular `Task` or synchronous calls (~6 instances in DataManagementView, ShortcutsAIService)
- Add `nonisolated` to pure utility structs (VTTParser, etc.)

### SwiftUI Rendering Performance
- Replace eager `NavigationLink(destination:)` with `.navigationDestination(item:)` in HomeView (Up Next, For You, Popular Shows)
- Replace `.onChange(of: episodes.map(\.id))` in HomeView with gated comparison to avoid per-render array allocation
- Move inline O(n×m) `filterLibraryEpisodes()` / `filterLibraryPodcasts()` from SearchView body into ViewModel
- Replace 100ms polling loop in EpisodeDetailView transcript highlighting with `@Observable` observation or reduced polling rate
- Use existing `cachedPlainDescription` in EpisodeRowView body instead of recomputing regex-based HTML stripping every render

### SwiftUI Patterns & UX
- Replace `@State private var audioManager = EnhancedAudioManager.shared` with computed property in MacContentView
- Replace manual `Binding(get:set:)` wrapper with `@Bindable` in ContentView sheet binding
- Consolidate `.onAppear` + `.task` race condition in EpisodeListView into single `.task`
- Replace `EmptyView()` default cases with meaningful fallback UI (~6 instances)
- Add `.refreshable()` to SavedEpisodesView, DownloadedPodcastsGridView, LatestEpisodesView

## Capabilities

### New Capabilities
- `concurrency-safety`: Fix Swift 6 concurrency anti-patterns — `assumeIsolated` crash vectors, `@unchecked Sendable`, redundant MainActor.run, Task.detached misuse, missing nonisolated markers
- `swiftui-rendering-perf`: Fix SwiftUI rendering hotspots — eager NavigationLink, polling loops, inline body computation, onChange allocation, missing cache usage
- `swiftui-patterns`: Fix SwiftUI state management and UX patterns — @State singletons, Binding workarounds, .onAppear+.task races, EmptyView fallbacks, missing .refreshable

### Modified Capabilities
<!-- No existing specs to modify -->

## Impact

**Files affected (~20):**
- ViewModels: HomeViewModel, LibraryViewModel, EpisodeListViewModel, EpisodeDetailViewModel, ExpandedPlayerViewModel, SettingsViewModel, PodcastSearchViewModel
- Services: EnhancedAudioManager, DownloadManager, BackgroundSyncManager, TranscriptManager, PlaybackStateCoordinator, PersistentLogService
- Views: HomeView, SearchView, EpisodeDetailView, EpisodeRowView, LibraryView, ContentView, MacContentView
- Utilities: CachedAsyncImage, VTTParser

**Risk:** Low-medium. Most changes are mechanical (removing `assumeIsolated`, adding `nonisolated`, swapping navigation patterns). The `ImageCacheManager` migration requires careful testing of image loading behavior.

**Dependencies:** None. All changes are internal refactors with no API or schema changes.
