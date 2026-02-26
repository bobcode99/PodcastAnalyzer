## ADDED Requirements

### Requirement: Deinit SHALL NOT use MainActor.assumeIsolated
All `deinit` methods SHALL cancel stored tasks by calling `task?.cancel()` directly, without wrapping in `MainActor.assumeIsolated`. `Task.cancel()` is thread-safe and does not require isolation.

Affected files: BackgroundSyncManager, TranscriptManager, PlaybackStateCoordinator, SettingsViewModel, PodcastSearchViewModel, EpisodeListViewModel, ExpandedPlayerViewModel, LibraryViewModel, HomeViewModel.

#### Scenario: ViewModel deallocated on background thread
- **WHEN** a @MainActor ViewModel is deallocated and `deinit` runs on an arbitrary background thread
- **THEN** all stored tasks are cancelled without crash (no `EXC_BREAKPOINT` / `dispatch_assert_queue_fail`)

#### Scenario: Tasks are fully cancelled in deinit
- **WHEN** a ViewModel with active tasks is deallocated
- **THEN** every stored `Task` property has `.cancel()` called and the app does not leak running tasks

### Requirement: AVPlayer time observer SHALL use proper MainActor dispatch
The `addPeriodicTimeObserver` callback in `EnhancedAudioManager.setupTimeObserver()` SHALL use `Task { @MainActor in }` instead of `MainActor.assumeIsolated` to dispatch to the main actor.

#### Scenario: Time observer fires on main dispatch queue
- **WHEN** AVPlayer's periodic time observer fires its callback on `DispatchQueue.main`
- **THEN** the callback dispatches to `@MainActor` via `Task { @MainActor in }` and updates `currentTime`, `duration`, and caption state without crash

### Requirement: ImageCacheManager SHALL use compiler-verified isolation
`ImageCacheManager` SHALL be converted from `final class: @unchecked Sendable` to an `actor`, removing manual `DispatchQueue`-based synchronization in favor of actor isolation.

#### Scenario: Concurrent image cache access
- **WHEN** multiple views request cached images simultaneously
- **THEN** the actor serializes access automatically without data races, and images load correctly

#### Scenario: Memory cache eviction
- **WHEN** `NSCache` evicts entries under memory pressure
- **THEN** the actor's state remains consistent (NSCache is internally thread-safe as a let property)

### Requirement: Redundant MainActor.run SHALL be removed from @MainActor contexts
Code running inside a `Task { }` that inherits `@MainActor` isolation SHALL NOT wrap property access in `await MainActor.run { }`. Direct property access SHALL be used instead.

Affected instances: DownloadManager (~6), PlaybackStateCoordinator (1), EpisodeListViewModel (1).

#### Scenario: Task inheriting @MainActor accesses @MainActor property
- **WHEN** a `Task { }` is created inside a `@MainActor` class method
- **THEN** properties of other `@MainActor` types are accessed directly without `await MainActor.run`

### Requirement: Task.detached SHALL only be used for justified isolation escape
`await Task.detached(...).value` (immediate await of detached task) SHALL be replaced with either a regular `Task` or synchronous execution. `Task.detached` SHALL only be used when genuinely escaping `@MainActor` for long-running blocking I/O.

Affected instances: DataManagementView (~6 cache size calculations), ShortcutsAIService (1).

#### Scenario: Short file enumeration in DataManagementView
- **WHEN** the user opens Data Management settings and cache sizes are calculated
- **THEN** brief file enumeration runs without unnecessary thread switching via `Task.detached`

### Requirement: Pure utility types SHALL be marked nonisolated
Structs and enums that contain only pure functions (no mutable state, no side effects) SHALL be marked `nonisolated` to opt out of the module-level `@MainActor` default.

#### Scenario: VTTParser called from actor context
- **WHEN** `VTTParser.parseSegments()` is called from a non-MainActor context (e.g., FileStorageManager actor)
- **THEN** the call compiles without requiring MainActor hop because the struct is `nonisolated`
