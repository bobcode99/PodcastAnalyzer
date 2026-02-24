## ADDED Requirements

### Requirement: EpisodeListView SHALL use computed property for DownloadManager singleton
`EpisodeListView` SHALL access `DownloadManager.shared` via a computed property (`private var downloadManager: DownloadManager { .shared }`) instead of `@Bindable`, since no `$` binding syntax is used.

#### Scenario: Download state observed without @Bindable
- **WHEN** `DownloadManager.downloadStates` changes
- **THEN** `EpisodeListView` body re-evaluates through `@Observable` observation without `@Bindable` wrapper

### Requirement: AISettingsView SHALL use @Bindable for AISettingsManager singleton
`AISettingsView` SHALL declare `AISettingsManager.shared` with `@Bindable` instead of `@State`, since `$settings.property` binding syntax is used for Toggle/Picker bindings.

#### Scenario: Toggle binding works with @Bindable
- **WHEN** the user toggles a setting that uses `$settings.someProperty`
- **THEN** the `AISettingsManager.shared` singleton is mutated correctly through the binding

### Requirement: LibraryView and EpisodeListView SHALL use @AppStorage for showEpisodeArtwork
`LibraryView` and `EpisodeListView` SHALL use `@AppStorage("showEpisodeArtwork")` instead of creating a fresh `SettingsViewModel()` instance. This ensures live updates when the setting changes in `SettingsView`.

#### Scenario: Setting change reflects immediately in Library
- **WHEN** the user toggles "Show Episode Artwork" in Settings
- **THEN** `LibraryView` reflects the change immediately without requiring view recreation

### Requirement: SettingsView SHALL mark @Environment as private
`@Environment(\.modelContext)` in `SettingsView` SHALL be declared `private`.

#### Scenario: Compilation succeeds with private modifier
- **WHEN** the project builds
- **THEN** `SettingsView.modelContext` is `private` and no external access exists

### Requirement: EpisodeRowView SHALL declare downloadManager as let
`EpisodeRowView.downloadManager` SHALL be declared as `let` since it is injected at initialization and never reassigned.

#### Scenario: Immutable dependency
- **WHEN** `EpisodeRowView` is initialized with a `DownloadManager` reference
- **THEN** the reference is immutable (`let`) for the lifetime of the view
