## ADDED Requirements

### Requirement: EpisodeListViewModel SHALL cache filteredEpisodes as a stored property
The `filteredEpisodes` property in `EpisodeListViewModel` SHALL be a stored `private(set) var` array that is recomputed only when `selectedFilter`, `sortOldestFirst`, `searchText`, or `episodeModels` change. `filteredEpisodeCount` SHALL read from the stored array's `.count`.

#### Scenario: Filter change triggers recomputation
- **WHEN** the user changes `selectedFilter` from `.all` to `.unplayed`
- **THEN** `filteredEpisodes` is recomputed once and the stored array is updated

#### Scenario: Body evaluation does not recompute
- **WHEN** SwiftUI evaluates `EpisodeListView.body` due to an unrelated state change
- **THEN** `filteredEpisodes` returns the cached stored array without recomputation

### Requirement: EpisodeDetailHeaderView SHALL cache SwiftData query results
The `podcastDestination` view in `EpisodeDetailHeaderView` SHALL NOT execute SwiftData fetch operations during body evaluation. The `PodcastInfoModel` lookup SHALL be performed once in a `.task` modifier and cached in `@State`.

#### Scenario: Initial load fetches once
- **WHEN** `EpisodeDetailHeaderView` appears
- **THEN** a single SwiftData query fetches the `PodcastInfoModel` and stores it in `@State`

#### Scenario: Playback timer does not trigger fetch
- **WHEN** the 100ms playback timer fires and causes body re-evaluation
- **THEN** `podcastDestination` reads from the cached `@State` value without executing a SwiftData query

### Requirement: LibraryView goToShowButton SHALL cache SwiftData query results
The `goToShowButton` in `LibraryEpisodeContextMenu` SHALL NOT execute SwiftData fetch operations inside `@ViewBuilder` body. The query SHALL be performed in `.onAppear` and cached in `@State`.

#### Scenario: Context menu renders without fetch
- **WHEN** the context menu body is evaluated
- **THEN** the `PodcastInfoModel` is read from cached `@State`, not from a live SwiftData query

### Requirement: Transcript playback timer SHALL guard state assignment
The 100ms playback timer in `EpisodeDetailView.transcriptContent` SHALL only assign `currentPlaybackTime` when the time difference exceeds a threshold (0.5 seconds) or when the active sentence would change. The timer SHALL NOT fire when playback is paused or the current episode is not playing.

#### Scenario: Paused playback stops timer updates
- **WHEN** the audio is paused and the Transcript tab is visible
- **THEN** the timer loop continues but no `@State` assignment occurs

#### Scenario: Small time change within same sentence is skipped
- **WHEN** `audioManager.currentTime` changes by less than 0.5 seconds and the active sentence has not changed
- **THEN** `currentPlaybackTime` is NOT reassigned and no body re-evaluation occurs

### Requirement: EpisodeRowView SHALL cache plainDescription
The HTML-stripped `plainDescription` in `EpisodeRowView` SHALL be computed once in `.onAppear` and stored in `@State`. It SHALL NOT be recomputed on every body evaluation.

#### Scenario: Scroll does not recompute HTML strip
- **WHEN** a download progress tick causes `EpisodeRowView` body re-evaluation
- **THEN** `plainDescription` is read from `@State` cache without regex execution

### Requirement: EpisodeListViewModel SHALL NOT use polling timer for SwiftData refresh
The `startRefreshTimer()` / `stopRefreshTimer()` 5-second polling loop SHALL be removed. SwiftData model updates SHALL be handled by the existing `.episodeDownloadCompleted` notification observer.

#### Scenario: Download completion updates episode models
- **WHEN** a download completes and `.episodeDownloadCompleted` notification fires
- **THEN** `episodeModels` dictionary is updated via the existing notification observer

#### Scenario: No periodic background fetches
- **WHEN** `EpisodeListView` is visible for 30 seconds with no downloads
- **THEN** zero SwiftData fetch operations occur (beyond the initial `.onAppear` load)

### Requirement: List views SHALL batch SwiftData queries for episode models
`UpNextListView`, `SavedEpisodesView`, `DownloadedEpisodesView`, and `LatestEpisodesView` SHALL fetch all `EpisodeDownloadModel` records in a single batch query in `.onAppear` keyed into a dictionary, then pass per-row via dictionary lookup.

#### Scenario: 20-episode list uses 1 fetch
- **WHEN** `UpNextListView` appears with 20 episodes
- **THEN** exactly 1 SwiftData fetch retrieves all episode models, not 20 individual fetches

### Requirement: ReactiveEpisodePlayButton SHALL NOT force re-render on every AVPlayer tick
The no-op `.onChange(of: audioManager.currentTime) { _, _ in }` and `.onChange(of: audioManager.isPlaying) { _, _ in }` handlers in `ReactiveEpisodePlayButton` SHALL be removed.

#### Scenario: Non-playing episode row does not re-render on time tick
- **WHEN** AVPlayer fires a periodic time observer callback
- **THEN** `ReactiveEpisodePlayButton` instances for non-playing episodes do NOT re-evaluate their body

### Requirement: CachedAsyncImage SHALL NOT clear image on disappear
`CachedAsyncImage.onDisappear` SHALL cancel in-flight load tasks but SHALL NOT set `image = nil`. Memory management SHALL be delegated to `NSCache` eviction.

#### Scenario: Scroll off and back shows cached image
- **WHEN** a `CachedAsyncImage` scrolls off-screen and then back on-screen
- **THEN** the previously loaded image is displayed immediately without placeholder flash

### Requirement: PodcastGridCell SHALL use a static RelativeDateTimeFormatter
`PodcastGridCell.latestEpisodeDate` SHALL use a `static let` cached `RelativeDateTimeFormatter` instead of instantiating a new one on every body evaluation.

#### Scenario: Grid renders 12 cells
- **WHEN** the Library grid renders 12 `PodcastGridCell` views
- **THEN** exactly 1 `RelativeDateTimeFormatter` instance is used across all cells

### Requirement: EpisodeRowView SHALL compute EpisodeStatusChecker once per body
The `statusChecker` in `EpisodeRowView` SHALL be computed once as a local `let` at the top of `body` (or its equivalent), not as a computed property that reinstantiates on every access.

#### Scenario: Four status properties use one checker
- **WHEN** `EpisodeRowView.body` accesses `downloadState`, `isDownloaded`, `playbackURL`, and `jobId`
- **THEN** exactly 1 `EpisodeStatusChecker` instance is created for that body evaluation
