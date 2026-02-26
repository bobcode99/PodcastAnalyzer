## ADDED Requirements

### Requirement: @Observable singletons SHALL NOT be wrapped in @State
Views that reference `@Observable` singletons SHALL use computed properties (`private var foo: Foo { .shared }`) instead of `@State private var foo = Foo.shared`, unless `$binding` syntax is required.

Affected: MacContentView (audioManager, importManager, notificationManager).

#### Scenario: Singleton property changes
- **WHEN** an `@Observable` singleton property changes (e.g., `audioManager.isPlaying`)
- **THEN** the View re-renders correctly via observation tracking through the computed property

#### Scenario: No $binding usage
- **WHEN** the singleton is only read (no `$foo` binding syntax used)
- **THEN** the singleton is accessed via computed property, not `@State`

### Requirement: Sheet bindings SHALL use @Bindable not manual Binding
Sheet presentations bound to `@Observable` singleton properties SHALL use `@Bindable` with `$property` syntax instead of manual `Binding(get:set:)` wrappers.

Affected: ContentView import sheet binding.

#### Scenario: Import sheet toggle
- **WHEN** `importManager.showImportSheet` is toggled
- **THEN** the sheet presents/dismisses correctly using `@Bindable` + `$importManager.showImportSheet`

### Requirement: Async initialization SHALL use .task not .onAppear + Task
Views that perform async initialization SHALL consolidate synchronous setup and async work into a single `.task` modifier instead of splitting across `.onAppear` (sync) and `.task` (async).

Affected: EpisodeListView.

#### Scenario: EpisodeListView appears
- **WHEN** EpisodeListView appears for the first time
- **THEN** ViewModel creation, modelContext setup, and async refresh all run sequentially within a single `.task` block, preventing race conditions where `.task` runs before `.onAppear`

### Requirement: Default switch cases SHALL NOT use EmptyView
`switch` statements in View body that use `EmptyView()` as a default/fallback case SHALL replace it with a meaningful fallback view (e.g., a `Text` describing the unexpected state) to surface bugs during development.

Affected: EpisodeListView, EpisodeDetailView, SettingsView, EpisodeAIAnalysisView (~6 instances).

#### Scenario: Unexpected tab index
- **WHEN** a tab selection or enum case reaches the default branch
- **THEN** a visible fallback view is shown instead of `EmptyView()`, making the bug visible during development

### Requirement: List views SHALL support pull-to-refresh
All scrollable list views displaying episode data SHALL have `.refreshable()` modifiers that trigger appropriate data reload.

Affected: SavedEpisodesView, DownloadedPodcastsGridView, LatestEpisodesView (these are missing `.refreshable`; HomeView, LibraryView, EpisodeListView already have it).

#### Scenario: User pulls to refresh on Saved Episodes
- **WHEN** the user pulls down on the SavedEpisodesView list
- **THEN** saved episodes are reloaded from SwiftData and the list updates

#### Scenario: User pulls to refresh on Latest Episodes
- **WHEN** the user pulls down on the LatestEpisodesView list
- **THEN** latest episodes are recalculated from subscribed podcasts and the list updates
