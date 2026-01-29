# Tasks: App Stability & Responsiveness Hardening

**Input**: Design documents from `/specs/001-app-stability/`
**Prerequisites**: plan.md (required), spec.md (required for user stories)

**Tests**: Included — the spec explicitly requires automated leak detection, error handling tests, and stress tests (SC-004, SC-006, SC-007).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing. Because this is a hardening feature (not greenfield), "foundational" work is retain-cycle and lifecycle fixes that unblock all user stories.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: No new project structure needed — this feature modifies existing files. Setup ensures build health before changes begin.

- [ ] T001 Verify clean build on both platforms: `xcodebuild build` for iOS Simulator and macOS targets
- [ ] T002 Run existing test suite to establish green baseline: `xcodebuild test` for PodcastAnalyzerTests

---

## Phase 2: Foundational (Blocking Prerequisites — Retain Cycles & Lifecycle Safety)

**Purpose**: Eliminate known memory leaks and add deinit safety nets to ALL ViewModels. These fixes are prerequisites for every user story because leaked ViewModels affect responsiveness (US1), memory (US2), error handling (US3), background ops (US4), and observability (US5).

**CRITICAL**: No user story work can begin until this phase is complete.

### Retain Cycle Fixes

- [ ] T003 Fix retain cycle in LibraryView notification observers: change `[self]` to `[weak self]` with `guard let self else { return }` at lines 202 and 217 in `PodcastAnalyzer/Views/LibraryView.swift`
- [ ] T004 Audit ShortcutsAIService strong self capture at line 59 in `PodcastAnalyzer/Services/ShortcutsAIService.swift` — verify actor singleton pattern makes this safe, or change to `[weak self]`

### ViewModel Deinit Safety Nets

- [ ] T005 [P] Add `deinit { cleanup() }` to LibraryViewModel in `PodcastAnalyzer/ViewModels/LibraryViewModel.swift`
- [ ] T006 [P] Add `deinit { cleanup() }` to ExpandedPlayerViewModel in `PodcastAnalyzer/ViewModels/ExpandedPlayerViewModel.swift`
- [ ] T007 [P] Add `deinit { cleanup() }` to EpisodeListViewModel in `PodcastAnalyzer/ViewModels/EpisodeListViewModel.swift`
- [ ] T008 [P] Add `deinit { cleanup() }` to HomeViewModel in `PodcastAnalyzer/ViewModels/HomeViewModel.swift`
- [ ] T009 [P] Add `deinit { cleanup() }` to PodcastSearchViewModel in `PodcastAnalyzer/ViewModels/PodcastSearchViewModel.swift`
- [ ] T010 Verify EpisodeDetailViewModel deinit at line 2269 calls `cleanup()` in `PodcastAnalyzer/ViewModels/EpisodeDetailViewModel.swift`
- [ ] T011 Audit SettingsViewModel and TranscriptGenerationViewModel for timer/observer lifecycle — add `deinit` if they hold resources in `PodcastAnalyzer/ViewModels/SettingsViewModel.swift` and `PodcastAnalyzer/ViewModels/TranscriptGenerationViewModel.swift`

### Cache Bounds & Singleton Access

- [ ] T012 Verify RSSCacheService has bounded storage (countLimit or eviction policy). If unbounded, add `countLimit` of 50 feeds in `PodcastAnalyzer/Services/RSSCacheService.swift`
- [ ] T013 Audit all Views for singleton access patterns — grep for `@State.*shared` or `@StateObject.*shared` and fix to computed property pattern (`var x: T { .shared }`) across `PodcastAnalyzer/Views/`
- [ ] T014 Verify CachedAsyncImage cache limits are set (countLimit: 100, totalCostLimit: 50 MB) in `PodcastAnalyzer/Utilities/CachedAsyncImage.swift` — already expected to be good, just confirm

### Build Verification

- [ ] T015 Build both platforms and run existing tests to confirm all Phase 2 changes compile and pass

**Checkpoint**: All retain cycles fixed, all ViewModels have deinit safety nets, caches are bounded. Foundation ready for user story work.

---

## Phase 3: User Story 1 — Fluid Interaction Without Freezes (Priority: P1) MVP

**Goal**: Eliminate all main-thread blocks so the UI never stutters during navigation, scrolling, or background operations.

**Independent Test**: Navigate all screens while background RSS refresh and 4 concurrent downloads are active — verify no frame drops and all taps respond within 200ms.

**Maps to**: FR-001, FR-004 → SC-001, SC-002, SC-005

### Implementation for User Story 1

- [ ] T016 [US1] Move `syncDownloadedFilesWithSwiftData()` off the main thread in `PodcastAnalyzer/ViewModels/LibraryViewModel.swift` lines 597-704: split into (a) quick SwiftData fetch on MainActor, (b) disk I/O in `Task.detached(priority: .background)`, (c) UI update via `@MainActor` callback. Use a separate background `ModelContext` from the same `ModelContainer` for the disk scan.
- [ ] T017 [US1] Make `findEpisodeToPlay()` async in `PodcastAnalyzer/Views/MiniPlayerBar.swift` lines 173-228: wrap call site in `Task { @MainActor in ... }` so SwiftData fetches don't block the UI
- [ ] T018 [US1] Defer non-critical singleton initialization in `PodcastAnalyzer/PodcastAnalyzerApp.swift` lines 66-87: keep PlaybackStateCoordinator and BackgroundSyncManager synchronous, move PodcastImportManager and NotificationNavigationManager setup to `Task.detached` after first frame. Use `.task` modifier instead of `.onAppear` for async setup.
- [ ] T019 [US1] Audit all `DispatchQueue.main.asyncAfter` calls for unnecessary delays — review `PodcastAnalyzer/ContentView.swift` (lines 191, 200), `PodcastAnalyzer/Views/SearchView.swift` (line 311), `PodcastAnalyzer/Views/SettingsView.swift` (line 551), `PodcastAnalyzer/Views/macOS/MacContentView.swift` (line 945). Reduce delays where possible; document why remaining delays are necessary.
- [ ] T020 [US1] Ensure all ViewModel `Task` handles are stored as properties and cancelled in `cleanup()`/`deinit` — audit all ViewModels in `PodcastAnalyzer/ViewModels/` for fire-and-forget `Task { }` blocks that should be cancellable
- [ ] T021 [US1] Build both platforms and verify Library tab loads instantly with 50+ podcasts (disk sync runs in background without stutter)

**Checkpoint**: User Story 1 complete — app is responsive during all interactions. Validate with Instruments Time Profiler.

---

## Phase 4: User Story 2 — Memory Stability Over Extended Use (Priority: P1)

**Goal**: Ensure memory stays flat over extended sessions by adding low-memory handling and verifying resource cleanup across all view transitions.

**Independent Test**: Run 60-minute automated session cycling all screens — memory stays within 20% of 5-minute baseline.

**Maps to**: FR-002, FR-005, FR-013 → SC-003, SC-006

### Implementation for User Story 2

- [ ] T022 [US2] Add low-memory warning handler in `PodcastAnalyzer/PodcastAnalyzerApp.swift`: observe `UIApplication.didReceiveMemoryWarningNotification` (iOS) to clear CachedAsyncImage's NSCache and RSSCacheService cache. Use `#if os(iOS)` guard. On macOS, add `DispatchSource.makeMemoryPressureSource` handler or skip if not available.
- [ ] T023 [US2] Expose a `clearCache()` method on CachedAsyncImage's image cache manager in `PodcastAnalyzer/Utilities/CachedAsyncImage.swift` — the low-memory handler needs to call it. Verify `removeAllObjects()` is sufficient.
- [ ] T024 [US2] Add `clearCache()` method to RSSCacheService in `PodcastAnalyzer/Services/RSSCacheService.swift` if not already present — the low-memory handler needs to call it
- [ ] T025 [US2] Verify all Views with `onAppear` have matching `onDisappear` cleanup — audit `PodcastAnalyzer/Views/EpisodeDetailView.swift`, `PodcastAnalyzer/Views/ExpandedPlayerView.swift`, `PodcastAnalyzer/Views/HomeView.swift`, `PodcastAnalyzer/Views/EpisodeListView.swift` for observers/timers created in onAppear but not cleaned up in onDisappear
- [ ] T026 [US2] Enforce bounded collection sizes in ViewModels: audit `PodcastAnalyzer/ViewModels/LibraryViewModel.swift` (podcast lists), `PodcastAnalyzer/ViewModels/HomeViewModel.swift` (autoplay candidates), `PodcastAnalyzer/ViewModels/PodcastSearchViewModel.swift` (search results) — add `.prefix(N)` caps where arrays can grow unbounded
- [ ] T027 [US2] Build and verify: simulate memory warning in iOS Simulator (Debug → Simulate Memory Warning) → confirm caches clear and app continues operating

**Checkpoint**: User Story 2 complete — memory stable over extended use, low-memory warnings handled. Validate with Instruments Allocations.

---

## Phase 5: User Story 3 — Reliable Error Recovery (Priority: P2)

**Goal**: Handle all adverse conditions (network failure, malformed data, rotation, background/foreground) gracefully without crashes.

**Independent Test**: Simulate network failures, feed malformed XML, rotate device, background/foreground cycle — app shows errors without crashing.

**Maps to**: FR-006, FR-007, FR-008, FR-009 → SC-007, SC-008

### Implementation for User Story 3

- [ ] T028 [US3] Harden RSS feed parsing error isolation in `PodcastAnalyzer/Services/PodcastRssService.swift`: wrap each individual feed parse in its own `do/catch`. On failure, log the error and mark only that feed as errored — do not propagate to cancel sibling feeds.
- [ ] T029 [US3] Add disk-space check before downloads in `PodcastAnalyzer/Services/DownloadManager.swift`: before starting a download, check `FileManager.default.attributesOfFileSystem` for available space. If <50 MB, set download state to `.failed` with a descriptive error. Add handling for missing-file-on-disk edge case (download record exists but audio file is gone) — reset to `.notDownloaded`.
- [ ] T030 [US3] Add network error retry capability in `PodcastAnalyzer/Services/DownloadManager.swift`: when a download fails due to network error, set state to `.failed` with a user-visible message and provide a retry mechanism (re-trigger download on user action) instead of silently stalling.
- [ ] T031 [US3] Harden audio interruption resume in `PodcastAnalyzer/Services/EnhancedAudioManager.swift` line 246: after the 0.8s delay resume call, check player status. If not playing, retry once after 0.5s. Log outcome.
- [ ] T032 [US3] Verify background/foreground state restoration in `PodcastAnalyzer/PodcastAnalyzerApp.swift` and `PodcastAnalyzer/ContentView.swift`: confirm `@SceneStorage` or `@State` preserves tab selection, confirm `EnhancedAudioManager` restores playback position from UserDefaults on foreground. If missing, add `scenePhase` observer to save state on `.background` transition.
- [ ] T033 [US3] Audit SwiftData store initialization in `PodcastAnalyzer/PodcastAnalyzerApp.swift` for corrupted store handling: wrap `ModelContainer` initialization in `do/catch` — on failure, delete the store file and recreate, logging a warning.
- [ ] T034 [US3] Build and test: verify malformed RSS feed doesn't crash the sync, download with low disk shows error, background/foreground preserves state

**Checkpoint**: User Story 3 complete — all error conditions handled gracefully. No silent failures.

---

## Phase 6: User Story 4 — Stable Background Operations (Priority: P2)

**Goal**: Background downloads, audio playback, and sync complete reliably without resource exhaustion.

**Independent Test**: Start downloads and playback, background the app, return — all operations completed correctly.

**Maps to**: FR-007, FR-012 → SC-008

### Implementation for User Story 4

- [ ] T035 [US4] Audit BackgroundSyncManager memory usage during sync in `PodcastAnalyzer/Services/BackgroundSyncManager.swift`: verify sync operations respect memory budgets (<300 MB peak). Add bounded batch sizes for feed refresh (e.g., sync 10 feeds per batch, not all at once).
- [ ] T036 [US4] Verify DownloadManager background URLSession delegate handles completion even if originating view is gone — audit `PodcastAnalyzer/Services/DownloadManager.swift` for `urlSession(_:downloadTask:didFinishDownloadingTo:)` to confirm it saves files and updates state independent of any view reference
- [ ] T037 [US4] Verify `EnhancedAudioManager` continues playback during backgrounding with lock screen controls functional — audit `PodcastAnalyzer/Services/EnhancedAudioManager.swift` for AVAudioSession category setup, MPRemoteCommandCenter handlers, and NowPlayingInfo updates. Fix any gaps.
- [ ] T038 [US4] Build and test: start download + playback → background app → wait 2 min → foreground → verify download completed and audio still playing

**Checkpoint**: User Story 4 complete — background operations reliable.

---

## Phase 7: User Story 5 — Observability and Crash Prevention (Priority: P3)

**Goal**: Add crash reporting and performance instrumentation for production monitoring.

**Independent Test**: Verify MetricKit subscriber is registered; verify signpost intervals appear in Instruments.

**Maps to**: FR-010 → SC-009

### Implementation for User Story 5

- [ ] T039 [US5] Create CrashReportingService with MetricKit integration in NEW file `PodcastAnalyzer/Services/CrashReportingService.swift`: implement `MXMetricManagerSubscriber` with `didReceive(_:)` for both `MXMetricPayload` and `MXDiagnosticPayload`. Log diagnostics via `os.Logger`. Use `#if os(iOS)` for iOS-specific MetricKit features. On macOS, register subscriber for basic metric payloads only.
- [ ] T040 [US5] Wire CrashReportingService startup into app launch: call `CrashReportingService.shared.start()` from `PodcastAnalyzer/PodcastAnalyzerApp.swift` during `onAppear`/`.task` setup
- [ ] T041 [P] [US5] Add `os_signpost` intervals to critical operations behind `#if DEBUG` in: `PodcastAnalyzer/ViewModels/LibraryViewModel.swift` (around `loadAll()` and `syncDownloadedFilesWithSwiftData()`), `PodcastAnalyzer/Services/PodcastRssService.swift` (around feed fetch/parse), `PodcastAnalyzer/Services/DownloadManager.swift` (around download start/complete)
- [ ] T042 [US5] Build and verify: CrashReportingService initializes without error, signpost intervals appear in Instruments Time Profiler

**Checkpoint**: User Story 5 complete — production observability in place.

---

## Phase 8: Regression Tests & Stress Validation

**Purpose**: Automated tests proving all stability improvements work and preventing future regressions. Required by spec (SC-004, SC-006, SC-007).

### Retain Cycle Detection Tests (SC-006)

- [ ] T043 [P] Create `PodcastAnalyzerTests/RetainCycleTests.swift`: write one test per ViewModel that creates the VM, calls `cleanup()`, sets reference to nil, and asserts `weak` reference is nil. Cover: LibraryViewModel, EpisodeDetailViewModel, ExpandedPlayerViewModel, EpisodeListViewModel, HomeViewModel, PodcastSearchViewModel. Use in-memory `ModelContainer` for SwiftData VMs.

### ViewModel Lifecycle Tests

- [ ] T044 [P] Create `PodcastAnalyzerTests/ViewModelLifecycleTests.swift`: test that after `cleanup()` — timers stop firing, notification observers are removed, Task handles are cancelled. Test LibraryViewModel (timer + observers), ExpandedPlayerViewModel (timer), EpisodeListViewModel (timer).

### Error Handling Tests (SC-007)

- [ ] T045 [P] Create `PodcastAnalyzerTests/ErrorHandlingTests.swift`: test malformed RSS XML returns error without crash (PodcastRssService), test missing audio file on disk resets download state (DownloadManager), test low disk space prevents download with error state (DownloadManager).

### UI Stress Test Suite (SC-004)

- [ ] T046 Create `PodcastAnalyzerUITests/StressTestSuite.swift`: XCUITest that launches app, rapidly cycles through all tabs (100 iterations), opens/closes episode detail views (50 iterations), triggers play/pause (20 iterations), scrolls library to bottom and back (10 iterations). Assert app never crashes (implicit). Add `measure` block to capture memory metrics.

### Final Validation

- [ ] T047 Run full test suite on both platforms: `xcodebuild test` for iOS Simulator and macOS — all tests must pass
- [ ] T048 Run stress test and verify SC-004: zero crashes over the full test duration

**Checkpoint**: All tests pass. Stability improvements are protected by regression tests.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final cleanup and validation across all stories.

- [ ] T049 Review all changes for platform parity — verify `#if os(iOS)` / `#if os(macOS)` guards are correct and macOS builds successfully
- [ ] T050 Run Instruments Allocations on a 10-minute session to spot-check SC-003 (memory stability)
- [ ] T051 Run Instruments Time Profiler to spot-check SC-001 (200ms response) and SC-005 (no >16ms blocks)
- [ ] T052 Final build verification on both iOS and macOS with all changes integrated

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 — biggest responsiveness wins
- **US2 (Phase 4)**: Depends on Phase 2 — can run in parallel with US1 (different files)
- **US3 (Phase 5)**: Depends on Phase 2 — can run in parallel with US1/US2 (different files)
- **US4 (Phase 6)**: Depends on Phase 2 — can run in parallel with others
- **US5 (Phase 7)**: Depends on Phase 2 — new file, no conflicts with US1-US4
- **Tests (Phase 8)**: Depends on US1-US5 completion (tests validate the fixes)
- **Polish (Phase 9)**: Depends on Phase 8

### User Story Dependencies

- **US1 (P1)**: Independent after Phase 2. Touches: LibraryViewModel, MiniPlayerBar, PodcastAnalyzerApp, ContentView
- **US2 (P1)**: Independent after Phase 2. Touches: PodcastAnalyzerApp (low-memory handler), CachedAsyncImage, RSSCacheService, View cleanup audit
- **US3 (P2)**: Independent after Phase 2. Touches: PodcastRssService, DownloadManager, EnhancedAudioManager, PodcastAnalyzerApp (store corruption)
- **US4 (P2)**: Independent after Phase 2. Touches: BackgroundSyncManager, DownloadManager (audit only), EnhancedAudioManager (audit only)
- **US5 (P3)**: Fully independent — new file CrashReportingService.swift + signpost additions

**Note on shared files**: US1, US2, and US3 all touch `PodcastAnalyzerApp.swift` but in different sections (launch init, low-memory handler, store corruption handler). These can be sequenced or merged carefully.

### Parallel Opportunities

```
After Phase 2 completes:
├── US1 (T016-T021) ──── different ViewModel + View files
├── US2 (T022-T027) ──── cache + memory files
├── US3 (T028-T034) ──── service error handling files
├── US4 (T035-T038) ──── background operation audits
└── US5 (T039-T042) ──── new CrashReportingService file

Within Phase 2:
├── T005, T006, T007, T008, T009 ── all [P] (different ViewModel files)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (build verification)
2. Complete Phase 2: Foundational (retain cycles + deinit)
3. Complete Phase 3: User Story 1 (off-main-thread work)
4. **STOP and VALIDATE**: App is responsive — no freezes, <200ms interactions
5. This alone delivers the highest-impact improvement

### Incremental Delivery

1. Setup + Foundational → Retain cycles fixed, ViewModels safe (immediate memory win)
2. Add US1 → Responsiveness fixed (biggest user-visible improvement)
3. Add US2 → Memory stability over time (extended session safety)
4. Add US3 → Error resilience (graceful degradation)
5. Add US4 → Background reliability (core podcast app function)
6. Add US5 → Observability (long-term monitoring)
7. Tests → Regression protection (sustain all improvements)
8. Polish → Final validation

### Build After Every Task

Every task that modifies code must be followed by a build verification. Do not batch multiple file changes without building — catch errors immediately.

---

## Notes

- [P] tasks = different files, no dependencies — safe to parallelize
- [Story] label maps task to specific user story for traceability
- Each user story is independently testable after Phase 2 foundation
- Total: 52 tasks across 9 phases
- This is a hardening feature — no new UI, no new models, no new screens
- All changes respect existing MVVM + singleton/actor architecture
- Zero new third-party dependencies — only Apple frameworks (MetricKit, os_signpost)
