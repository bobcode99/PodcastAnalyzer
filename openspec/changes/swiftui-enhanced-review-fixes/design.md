## Context

The PodcastAnalyzer app uses SwiftUI with `@Observable` ViewModels, SwiftData for persistence, and singleton services (`EnhancedAudioManager`, `DownloadManager`, `FileStorageManager`). A four-skill audit identified performance bottlenecks concentrated in three hot paths:

1. **Episode list scrolling** — `EpisodeRowView` recomputes HTML-stripping regex + instantiates `EpisodeStatusChecker` 4+ times per body evaluation. `EpisodeListViewModel.filteredEpisodes` is a computed property running filter+sort on every access (called twice per render).
2. **Transcript playback** — A 100ms timer fires unconditionally while the Transcript tab is visible, driving O(n) sentence scans and a SwiftData fetch in `EpisodeDetailHeaderView` (10x/sec).
3. **Library browsing** — N+1 SwiftData `fetchEpisodeModel(for:)` calls per list row, formatter instantiation per grid cell, and full re-sort on every SwiftData write.

The state management and modern API issues are lower-risk but improve correctness and maintainability.

## Goals / Non-Goals

**Goals:**
- Eliminate all SwiftData queries from `@ViewBuilder` body evaluations
- Remove or guard all polling timers to only fire when necessary
- Cache expensive computed properties as stored state with targeted invalidation
- Correct property wrapper misuse (`@Bindable`, `@State`, `@AppStorage`)
- Replace deprecated APIs and add accessibility labels to icon-only buttons
- All fixes MUST build successfully and preserve existing behavior

**Non-Goals:**
- Architectural refactoring (no MVVM changes, no new patterns)
- UI/UX changes (no visual changes except fixing placeholder flash)
- Liquid Glass adoption (separate change)
- Extracting large view bodies into subviews (medium-priority, deferred)
- Merging duplicate `UpNextCard`/`ForYouCard` (medium-priority, deferred)

## Decisions

### 1. Cache strategy for `filteredEpisodes`

**Decision:** Convert from computed property to stored `private(set) var` with explicit recomputation in `didSet` of `selectedFilter`, `sortOldestFirst`, `searchText`, and `episodeModels`.

**Rationale:** `filteredEpisodes` is accessed twice per render (`ForEach` + `filteredEpisodeCount`). Making it stored eliminates redundant O(n log n) work. Using `didSet` on the trigger properties ensures it stays in sync without manual call sites.

**Alternative considered:** Keeping computed but caching with a dirty flag. Rejected — more complex and `@Observable` doesn't support custom `willSet`/`didSet` on tracked properties cleanly.

### 2. SwiftData query caching in `EpisodeDetailHeaderView`

**Decision:** Add `@State private var cachedPodcastModel: PodcastInfoModel?`, fetch once in `.task { }`, and use the cached value in `podcastDestination`.

**Rationale:** The current approach executes a SwiftData fetch inside a `@ViewBuilder` computed property that runs 10x/second due to the playback timer. `.task` runs once on appear and cancels on disappear.

### 3. Transcript playback timer guard

**Decision:** Keep the 100ms timer but add a threshold guard: only assign `currentPlaybackTime` when the computed `currentSentenceId` would change (i.e., time crosses a sentence boundary).

**Rationale:** Removing the timer entirely and using `@Observable` observation on `audioManager.currentTime` would fire on every AVPlayer periodic callback (~10Hz), giving no improvement. The timer is fine — the issue is the unconditional `@State` assignment triggering body re-evaluation. Guarding with `abs(newTime - currentPlaybackTime) > 0.5` or checking if the sentence actually changed reduces body evaluations from 10/sec to ~1 every few seconds.

**Alternative considered:** Using `onChange(of: audioManager.currentTime)`. Rejected — this fires at AVPlayer's rate (potentially faster than 10Hz) and can't be throttled.

### 4. Batch SwiftData fetches for list rows

**Decision:** Fetch all `EpisodeDownloadModel` records in a single batch `onAppear` query keyed into a `[String: EpisodeDownloadModel]` dictionary, then pass per-row via dictionary lookup.

**Rationale:** Mirrors the pattern already used in `EpisodeListViewModel.episodeModels`. Eliminates N+1 queries (20 episodes = 20 fetches → 1 fetch).

### 5. `EpisodeRowView` caching approach

**Decision:** Cache `plainDescription` via `@State` + `.onAppear`. For `EpisodeStatusChecker`, compute the four needed values once at the top of `body` as local `let` bindings.

**Rationale:** `@State` caching for `plainDescription` avoids regex in body. Local `let` for status checker values avoids object allocation without adding `@State` complexity for what is a simple struct computation.

## Risks / Trade-offs

- **[Stale cached data]** → Mitigated by using `.task`/`.onAppear` for initial fetch and `onChange` for invalidation triggers. SwiftData model objects are reference types — cached `PodcastInfoModel` stays live.
- **[Transcript highlight delay]** → Increasing timer guard threshold from 100ms to 500ms may cause visible lag in sentence highlighting. Mitigated by testing with real podcast content and adjusting threshold.
- **[Breaking observation chains]** → Converting computed properties to stored requires ensuring all mutation paths call recomputation. Mitigated by using `didSet` on trigger properties.
- **[Deprecated view deletion]** → Not deleting deprecated `EpisodePlayButton`/`ReactiveEpisodePlayButton` yet — only removing the harmful `.onChange` side effects. Full cleanup deferred.
