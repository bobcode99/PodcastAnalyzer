# PodcastAnalyzer Constitution

## Core Principles

### I. Memory Discipline (NON-NEGOTIABLE)
- Target memory budget: **under 150 MB** during normal use, **under 300 MB** peak
- Every `@State` image or cached resource **must** be cleared in `onDisappear`
- Never use `GeometryReader` inside `LazyVGrid`/`LazyVStack` — use fixed aspect ratios
- All unbounded arrays (`autoPlayCandidates`, episode lists) **must** have a size cap
- Never hold full episode descriptions in memory for list views — defer to detail views
- `NSCache` instances must set `countLimit` and `totalCostLimit`
- Singletons accessed from Views must use computed properties (`var x: T { .shared }`), not `@State`
- Use `CachedAsyncImage` everywhere — never raw `AsyncImage`

### II. CPU & Responsiveness
- Target CPU: **under 10%** idle, **under 40%** during interaction
- Timer-based polling is a last resort — prefer `Combine`/`AsyncSequence`/`NotificationCenter`
- Polling intervals: minimum 0.5s for UI updates, 1.0s+ for background work
- Never run SwiftData fetches or disk I/O on the main thread — use `Task.detached(priority: .background)` for heavy work
- All `onAppear` data loads must be non-blocking — show cached/stale data immediately, refresh in background
- View body evaluation must complete in under 16ms (one frame at 60fps)

### III. Data Integrity & Safety
- **Never** use `Dictionary(uniqueKeysWithValues:)` — always use `Dictionary(_:uniquingKeysWith:)` to handle duplicates gracefully
- All SwiftData fetch results must be deduplicated before display (use `Set<String>` seen-ID pattern)
- Duplicate model entries must be detected and cleaned up during sync operations
- Episode keys use Unit Separator (`\u{1F}`) delimiter — never pipe (`|`) for new data
- `@Attribute(.unique)` does not guarantee fetch-time uniqueness — always code defensively

### IV. Observer & Resource Lifecycle
- Every observer/timer created in `init` or `onAppear` **must** have a matching cleanup in `onDisappear` or `deinit`
- After cleanup, re-entering a view (`onAppear`) **must** re-establish all observers and timers
- Pattern: `ensureObserversAndTimerRunning()` — idempotent setup, safe to call multiple times
- `Task` instances stored as properties must be cancelled on cleanup
- Background `URLSession` delegates must handle completion even if the originating view is gone

### V. Testing Standards
- **Framework**: XCTest for all unit and integration tests
- Every crash fix **must** include a regression test proving the fix
- Tests that create `LibraryViewModel` (or any ViewModel with timers/observers) **must** call `cleanup()` in `tearDown`
- Async tests use polling (`waitUntil`) instead of fixed `Task.sleep` — timeout of 3s default, 5s for disk-bound operations
- Tests involving downloaded files **must** create real temp files (sync functions verify disk existence)
- Dictionary safety tests must verify `uniquingKeysWith` handles duplicates without crashing
- Test data must use the production key format (Unit Separator delimiter)
- In-memory `ModelContainer` (`isStoredInMemoryOnly: true`) for all SwiftData tests

### VI. UI/UX Consistency
- Quick access cards (Saved, Downloaded) must show live counts that update automatically
- Downloaded count includes actively downloading episodes (`downloaded + downloading`)
- Pull-to-refresh must trigger a full data sync, not just re-set the model context
- Navigation push (NavigationLink) must not trigger parent view's `onDisappear` cleanup — only tab switches do
- Lists must show data immediately from cache, then refresh in background without blocking scroll
- Search filtering is case-insensitive, matches both episode title and podcast title
- Empty states must only show when both static data and active operations are empty

## Performance Standards

| Metric | Target | Hard Limit |
|--------|--------|------------|
| Memory (idle) | < 80 MB | < 150 MB |
| Memory (peak) | < 150 MB | < 300 MB |
| CPU (idle) | < 5% | < 10% |
| CPU (interaction) | < 30% | < 50% |
| View body eval | < 8ms | < 16ms |
| List scroll FPS | 60 fps | > 45 fps |
| Data load to display | < 200ms | < 500ms |
| Image cache memory | < 50 MB | < 100 MB |

## Architecture Constraints

- **MVVM**: Views → ViewModels → Services → Models. No direct service calls from Views
- **Singletons**: Audio, download, file storage are singletons — never create second instances
- **Actors**: RSS, file storage, transcription use Swift Actors for thread safety
- **SwiftData**: Episodes are nested arrays in `PodcastInfoModel`, not separate entities
- **No backward compatibility**: Break old formats freely, no migration shims
- **Local-first**: SwiftData provides offline-first persistence, no remote sync
- **Platform**: iOS 26.0+ and macOS 26.0+ — use `#if os()` for platform-specific code

## Development Workflow

1. **Read before edit**: Never propose changes to code you haven't read
2. **Build after every change**: `xcodebuild build` must pass before moving on
3. **Test after crash fixes**: Every fix for a runtime crash must include a unit test
4. **Profile before optimizing**: Use Xcode Instruments (Allocations, Time Profiler) to identify hotspots — don't guess
5. **Minimize changes**: Only change what's needed. Don't refactor surrounding code, add docstrings to untouched code, or over-engineer

## Governance

- This constitution supersedes default coding habits when they conflict
- Memory and CPU limits are hard requirements — violations are treated as bugs
- All PRs must verify no `Dictionary(uniqueKeysWithValues:)` usage on data that could contain duplicates
- Observer lifecycle violations (setup without cleanup, or cleanup without re-setup) are treated as memory leaks

**Version**: 1.0.0 | **Ratified**: 2026-01-30 | **Last Amended**: 2026-01-30
