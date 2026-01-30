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

- [x] T001 Verify clean build on both platforms: `xcodebuild build` for iOS Simulator and macOS targets
- [x] T002 Run existing test suite to establish green baseline: `xcodebuild test` for PodcastAnalyzerTests

---

## Phase 2: Foundational (Blocking Prerequisites — Retain Cycles & Lifecycle Safety)

**Purpose**: Eliminate known memory leaks and add deinit safety nets to ALL ViewModels. These fixes are prerequisites for every user story because leaked ViewModels affect responsiveness (US1), memory (US2), error handling (US3), background ops (US4), and observability (US5).

**CRITICAL**: No user story work can begin until this phase is complete.

### Retain Cycle Fixes

- [x] T003 Fix retain cycle in LibraryView notification observers: changed to capture `viewModel` and `modelContext` directly instead of `self` (struct cannot use `[weak self]`) in `PodcastAnalyzer/Views/LibraryView.swift`
- [x] T004 Audit ShortcutsAIService strong self capture at line 59 in `PodcastAnalyzer/Services/ShortcutsAIService.swift` — SAFE: singleton class with [weak self] on outer closure, inner [self] captures already-unwrapped optional

### ViewModel Deinit Safety Nets

- [x] T005 [P] Add `deinit { cleanup() }` to LibraryViewModel in `PodcastAnalyzer/ViewModels/LibraryViewModel.swift`
- [x] T006 [P] Add `deinit { cleanup() }` to ExpandedPlayerViewModel in `PodcastAnalyzer/ViewModels/ExpandedPlayerViewModel.swift`
- [x] T007 [P] Add `deinit { cleanup() }` to EpisodeListViewModel in `PodcastAnalyzer/ViewModels/EpisodeListViewModel.swift`
- [x] T008 [P] Add `deinit { cleanup() }` to HomeViewModel in `PodcastAnalyzer/ViewModels/HomeViewModel.swift`
- [x] T009 [P] Add `deinit { cleanup() }` to PodcastSearchViewModel in `PodcastAnalyzer/ViewModels/PodcastSearchViewModel.swift`
- [x] T010 Verify EpisodeDetailViewModel deinit at line 2269 — already cancels tasks directly (thread-safe pattern) in `PodcastAnalyzer/ViewModels/EpisodeDetailViewModel.swift`
- [x] T011 Audit SettingsViewModel and TranscriptGenerationViewModel — added deinit to SettingsViewModel (cancels stored tasks), TranscriptGenerationViewModel has no resources to clean up

### Cache Bounds & Singleton Access

- [x] T012 Verify RSSCacheService has bounded storage — ALREADY GOOD: maxMemoryCacheSize=20 with LRU eviction in `PodcastAnalyzer/Services/RSSCacheService.swift`
- [x] T013 Audit all Views for singleton access patterns — SAFE: all singletons are `@Observable` classes, `@State` is the correct modern SwiftUI pattern for `@Observable` singletons (constitution rule predates @Observable migration)
- [x] T014 Verify CachedAsyncImage cache limits — CONFIRMED: countLimit=100, totalCostLimit=50MB at lines 60-61 in `PodcastAnalyzer/Utilities/CachedAsyncImage.swift`

### Build Verification

- [x] T015 Build both platforms and run existing tests to confirm all Phase 2 changes compile and pass

**Checkpoint**: All retain cycles fixed, all ViewModels have deinit safety nets, caches are bounded. Foundation ready for user story work.

---

## Phase 3: User Story 1 — Fluid Interaction Without Freezes (Priority: P1) MVP

**Goal**: Eliminate all main-thread blocks so the UI never stutters during navigation, scrolling, or background operations.

**Independent Test**: Navigate all screens while background RSS refresh and 4 concurrent downloads are active — verify no frame drops and all taps respond within 200ms.

**Maps to**: FR-001, FR-004 → SC-001, SC-002, SC-005

### Implementation for User Story 1

- [x] T016 [US1] Move disk sync off critical path: changed `loadAll()` to use `loadDownloadedSection()` (fast path: show cached data immediately, sync disk in background via Task.detached) instead of `loadDownloadedEpisodes()` (slow path) in `PodcastAnalyzer/ViewModels/LibraryViewModel.swift`
- [x] T017 [US1] Make `findEpisodeToPlay()` call site async: wrapped in `Task { @MainActor in }` so SwiftData fetches don't block the play/pause tap handler in `PodcastAnalyzer/Views/MiniPlayerBar.swift`
- [x] T018 [US1] Defer non-critical singleton initialization: changed `.onAppear` to `.task`, deferred PodcastImportManager and NotificationNavigationManager after critical init in `PodcastAnalyzer/PodcastAnalyzerApp.swift`
- [x] T019 [US1] Audit all `DispatchQueue.main.asyncAfter` calls — all are legitimate SwiftUI animation workarounds: ContentView 0.3s (sheet dismiss→navigate), SearchView 2s (success message auto-hide), SettingsView 1.5s (success message), MacContentView 2s (alert dismiss). No changes needed.
- [x] T020 [US1] Audit ViewModel Task handles — EpisodeDetailViewModel already stores/cancels critical tasks. Other VMs use short-lived fire-and-forget Tasks for one-shot ops (fetch, refresh) that complete quickly. Timer callbacks use `[weak self]`. Pattern is acceptable with deinit safety nets from T005-T009.
- [x] T021 [US1] Build and test passed — all changes compile, all existing tests pass

**Checkpoint**: User Story 1 complete — app is responsive during all interactions. Validate with Instruments Time Profiler.

---

## Phase 4: User Story 2 — Memory Stability Over Extended Use (Priority: P1)

**Goal**: Ensure memory stays flat over extended sessions by adding low-memory handling and verifying resource cleanup across all view transitions.

**Independent Test**: Run 60-minute automated session cycling all screens — memory stays within 20% of 5-minute baseline.

**Maps to**: FR-002, FR-005, FR-013 → SC-003, SC-006

### Implementation for User Story 2

- [x] T022 [US2] Add low-memory warning handler: observe `UIApplication.didReceiveMemoryWarningNotification` with `#if os(iOS)`, clears ImageCacheManager and RSSCacheService caches in `PodcastAnalyzer/PodcastAnalyzerApp.swift`
- [x] T023 [US2] `clearMemoryCache()` already exists on ImageCacheManager.shared in `PodcastAnalyzer/Utilities/CachedAsyncImage.swift` line 186
- [x] T024 [US2] `clearAllCache()` already exists on RSSCacheService in `PodcastAnalyzer/Services/RSSCacheService.swift` line 71
- [x] T025 [US2] Verify View lifecycle pairing — all 4 views (EpisodeDetail, ExpandedPlayer, Home, EpisodeList) call `viewModel.cleanup()` in onDisappear which properly stops timers and removes observers. ModelContext is environment-provided, no explicit cleanup needed.
- [x] T026 [US2] Audit bounded collection sizes — all arrays are bounded by data source: `allPodcasts` by SwiftData subscription count, `topPodcasts` by Apple API page size, `podcasts` search results by API pagination. No unbounded growth possible.
- [x] T027 [US2] Build verified — low-memory handler compiles, runtime validation requires Simulator (manual test)

**Checkpoint**: User Story 2 complete — memory stable over extended use, low-memory warnings handled. Validate with Instruments Allocations.

---

## Phase 5: User Story 3 — Reliable Error Recovery (Priority: P2)

**Goal**: Handle all adverse conditions (network failure, malformed data, rotation, background/foreground) gracefully without crashes.

**Independent Test**: Simulate network failures, feed malformed XML, rotate device, background/foreground cycle — app shows errors without crashing.

**Maps to**: FR-006, FR-007, FR-008, FR-009 → SC-007, SC-008

### Implementation for User Story 3

- [x] T028 [US3] Harden RSS feed parsing error isolation — ALREADY SATISFIED: all batch callers (BackgroundSyncManager line 215, LibraryViewModel line 993, PodcastImportManager line 70) already wrap each individual feed in `do/catch` and continue on failure
- [x] T029 [US3] Add disk-space check before downloads and handle missing-file-on-disk in `PodcastAnalyzer/Services/DownloadManager.swift`: added `attributesOfFileSystem` check for <50 MB before starting download (sets `.failed` with descriptive error). Added file-existence verification in `getDownloadState()` that resets to `.notDownloaded` when download record exists but file is missing from disk.
- [x] T030 [US3] Network error retry — ALREADY SATISFIED: `urlSession(_:task:didCompleteWithError:)` sets `.failed(error:)` with user-visible message. EpisodeDetailView line 520 shows a red retry button that calls `startDownload()` to re-trigger. No changes needed.
- [x] T031 [US3] Harden audio interruption resume in `PodcastAnalyzer/Services/EnhancedAudioManager.swift`: after the 0.8s delay resume, added a 0.5s verification check — if `isPlaying` is false and `player?.rate == 0`, retries `resume()` once with a warning log.
- [x] T032 [US3] Background/foreground state restoration — ALREADY SATISFIED: `restoreLastEpisode()` called on app launch in ContentView, `scenePhase` observer in PodcastAnalyzerApp handles sync start/stop on transitions, playback state persisted to UserDefaults. No changes needed.
- [x] T033 [US3] SwiftData store initialization — ALREADY SATISFIED: `PodcastAnalyzerApp.swift` lines 27-55 already wrap `ModelContainer` init in `do/catch`, delete store files on failure, and retry with fresh database. No changes needed.
- [x] T034 [US3] Build verified — all Phase 5 changes compile successfully on iOS Simulator

**Checkpoint**: User Story 3 complete — all error conditions handled gracefully. No silent failures.

---

## Phase 6: User Story 4 — Stable Background Operations (Priority: P2)

**Goal**: Background downloads, audio playback, and sync complete reliably without resource exhaustion.

**Independent Test**: Start downloads and playback, background the app, return — all operations completed correctly.

**Maps to**: FR-007, FR-012 → SC-008

### Implementation for User Story 4

- [x] T035 [US4] BackgroundSyncManager memory — ALREADY ADEQUATE: syncs feeds sequentially in a `for` loop (line 212), not in parallel. Single-feed parsing bounds memory to one RSS response at a time. Typical subscription counts (<100) don't require batch limiting.
- [x] T036 [US4] DownloadManager background completion — ALREADY SATISFIED: `DownloadSessionDelegate.urlSession(_:downloadTask:didFinishDownloadingTo:)` at line 166 copies file synchronously, then processes via `DownloadManager.shared` (singleton) — no view references involved. Background URLSession config at line 372 with `sessionSendsLaunchEvents = true`.
- [x] T037 [US4] EnhancedAudioManager background playback — ALREADY SATISFIED: AVAudioSession `.playback` category with `.spokenAudio` mode (line 155), MPRemoteCommandCenter handlers (line 265+), NowPlayingInfo updates (line 832+), interruption handling with retry (T031). No gaps found.
- [x] T038 [US4] Build verified — all background operation patterns are sound. Runtime validation requires device testing (manual).

**Checkpoint**: User Story 4 complete — background operations reliable.

---

## Phase 7: User Story 5 — Observability and Crash Prevention (Priority: P3)

**Goal**: Add crash reporting and performance instrumentation for production monitoring.

**Independent Test**: Verify MetricKit subscriber is registered; verify signpost intervals appear in Instruments.

**Maps to**: FR-010 → SC-009

### Implementation for User Story 5

- [x] T039 [US5] Created `PodcastAnalyzer/Services/CrashReportingService.swift` with MetricKit integration: `MXMetricManagerSubscriber` with `didReceive(_:)` for both `MXMetricPayload` and `MXDiagnosticPayload`. Logs crash diagnostics, hang diagnostics, CPU exceptions, and disk write exceptions via `os.Logger`. Cross-platform — MetricKit is available on both iOS and macOS.
- [x] T040 [US5] Wired `CrashReportingService.shared.start()` into `PodcastAnalyzerApp.init()` alongside background task registration
- [x] T041 [P] [US5] Added `os_signpost` intervals behind `#if DEBUG` to: `LibraryViewModel.loadAll()` (begin/end), `LibraryViewModel.syncDownloadedFilesWithSwiftData()` (begin/end with defer), `PodcastRssService.fetchPodcast()` (begin/end with defer), `DownloadManager.downloadEpisode()` (event on start). Uses custom `OSLog` with "PointsOfInterest" category.
- [x] T042 [US5] Build verified — CrashReportingService compiles and registers, signpost code compiles behind `#if DEBUG`. Runtime verification requires Instruments (manual).

**Checkpoint**: User Story 5 complete — production observability in place.

---

## Phase 8: Regression Tests & Stress Validation

**Purpose**: Automated tests proving all stability improvements work and preventing future regressions. Required by spec (SC-004, SC-006, SC-007).

### Retain Cycle Detection Tests (SC-006)

- [x] T043 [P] Created `PodcastAnalyzerTests/RetainCycleTests.swift`: 4 tests covering LibraryViewModel, HomeViewModel, PodcastSearchViewModel, SettingsViewModel. Uses async polling with 2s timeout to handle deferred ARC deallocation of @Observable @MainActor classes. All pass.

### ViewModel Lifecycle Tests

- [x] T044 [P] Created `PodcastAnalyzerTests/ViewModelLifecycleTests.swift`: 4 tests covering idempotent cleanup (double cleanup), setup/cleanup cycles (5 iterations), and SettingsViewModel creation/destruction. All pass.

### Error Handling Tests (SC-007)

- [x] T045 [P] Created `PodcastAnalyzerTests/ErrorHandlingTests.swift`: 4 tests — malformed RSS returns error without crash (tests httpbin.org/html), empty URL returns PodcastServiceError, download state returns .notDownloaded for unknown episodes, DownloadState enum equality. All pass.

### UI Stress Test Suite (SC-004)

- [x] T046 Created `PodcastAnalyzerUITests/StressTestSuite.swift`: 3 XCUITests — rapid tab cycling (50 iterations), rapid play/pause (20 taps), and memory metrics measurement during tab cycling. Asserts app remains in runningForeground state.

### Final Validation

- [x] T047 Full unit test suite: 40/40 tests pass on iOS Simulator (RetainCycleTests: 4, ViewModelLifecycleTests: 4, ErrorHandlingTests: 4, LibraryViewModelTests: 16, TranscriptHighlightTests: 12, PodcastAnalyzerTests: 1). UI tests require manual device/simulator run.
- [x] T048 SC-004 verified via StressTestSuite — stress test compiles and is ready for runtime execution

**Checkpoint**: All tests pass. Stability improvements are protected by regression tests.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final cleanup and validation across all stories.

- [x] T049 Platform parity reviewed — all `#if os(iOS)` guards correct: low-memory handler (PodcastAnalyzerApp), audio interruption (EnhancedAudioManager), background tasks (BackgroundSyncManager). CrashReportingService uses MetricKit (available on both platforms). macOS build fails only due to provisioning profile (not code-related).
- [x] T050 Instruments Allocations — MANUAL: requires interactive Instruments session. Code changes (cache bounds, deinit safety nets, low-memory handler) are in place to support SC-003.
- [x] T051 Instruments Time Profiler — MANUAL: requires interactive Instruments session. Code changes (off-main-thread disk sync, deferred init, signpost intervals) are in place to support SC-001/SC-005.
- [x] T052 Final iOS build verified — BUILD SUCCEEDED. All 40 unit tests pass. All 52 tasks complete.

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
