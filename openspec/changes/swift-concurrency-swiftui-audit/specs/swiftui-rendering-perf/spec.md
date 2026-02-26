## ADDED Requirements

### Requirement: NavigationLink SHALL defer destination creation in HomeView
HomeView's Up Next, For You, and Popular Shows sections SHALL use `.navigationDestination(item:)` or `.navigationDestination(for:)` instead of `NavigationLink(destination:)` to defer creation of `EpisodeDetailView` and `EpisodeListView` until the user taps.

#### Scenario: Scrolling Up Next without tapping
- **WHEN** the user scrolls the Up Next horizontal list containing 10 episode cards
- **THEN** zero `EpisodeDetailView` instances are created (destinations are deferred)

#### Scenario: Tapping an Up Next card
- **WHEN** the user taps an episode card in Up Next
- **THEN** a single `EpisodeDetailView` is created and navigated to

### Requirement: HomeView onChange SHALL NOT allocate arrays per render
The `.onChange(of: episodes.map(\.id))` pattern in HomeView SHALL be replaced with a gated comparison that avoids creating a new `[ID]` array on every SwiftUI render cycle.

#### Scenario: View re-renders without episode change
- **WHEN** HomeView body is re-evaluated but the episode list has not changed
- **THEN** no array allocation occurs and `batchFetchEpisodeModels()` is not called

#### Scenario: Episode list changes
- **WHEN** a new episode is added or removed from the list
- **THEN** `batchFetchEpisodeModels()` is called exactly once

### Requirement: SearchView filtering SHALL run in ViewModel not View body
`filterLibraryPodcasts()` and `filterLibraryEpisodes()` in SearchView SHALL be moved to stored properties in a ViewModel, updated only when `searchText` changes, instead of being computed inline in the View body.

#### Scenario: Search text changes
- **WHEN** the user types a character in the library search field
- **THEN** filtering runs once in the ViewModel and the View reads the cached result

#### Scenario: View re-renders without search text change
- **WHEN** SearchView body re-evaluates due to unrelated state change
- **THEN** no filtering computation occurs (cached results are used)

### Requirement: Transcript highlighting SHALL NOT poll at 100ms
The transcript highlighting timer in EpisodeDetailView SHALL poll at no more than 250ms (4Hz) instead of 100ms (10Hz). Updates SHALL be gated on actual time change exceeding 0.5s delta.

#### Scenario: Playback active with transcript visible
- **WHEN** audio is playing and the transcript tab is visible
- **THEN** the polling loop runs at 250ms intervals (not 100ms) and only updates UI when time delta >= 0.5s

#### Scenario: Transcript tab not visible
- **WHEN** the user switches away from the transcript tab
- **THEN** the polling timer is inactive (no CPU wake-ups)

### Requirement: EpisodeRowView SHALL use cached plain description
`EpisodeRowView` SHALL use the existing `cachedPlainDescription` @State property in its body instead of recomputing `plainDescription` (7 string operations + regex) on every render.

#### Scenario: Episode row renders in list
- **WHEN** an EpisodeRowView appears in a scrolling list
- **THEN** the description text is read from `cachedPlainDescription` (set once in `.onAppear`) without recomputing regex-based HTML stripping
