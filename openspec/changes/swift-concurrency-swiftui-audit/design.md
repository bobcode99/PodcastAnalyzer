## Context

PodcastAnalyzer is a Swift 6 iOS/macOS app with:
- `SWIFT_STRICT_CONCURRENCY = complete`
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (all types default to `@MainActor`)
- `SWIFT_VERSION = 6.0`

The codebase has grown organically, accumulating concurrency workarounds (`assumeIsolated`, `@unchecked Sendable`) and SwiftUI patterns that predate current best practices. A Time Profiler session revealed 75s+ of avoidable CPU time from rendering inefficiencies, and code review found 9 intermittent crash vectors from `MainActor.assumeIsolated` in `deinit`.

**~20 files** across ViewModels, Services, Views, and Utilities are affected. All changes are internal refactors — no API, schema, or dependency changes.

## Goals / Non-Goals

**Goals:**
- Eliminate all `MainActor.assumeIsolated` crash vectors in deinit (9 files)
- Remove `@unchecked Sendable` from `ImageCacheManager` with a compiler-verified alternative
- Fix the top 5 SwiftUI rendering hotspots (eager NavigationLink, polling, inline body computation)
- Correct SwiftUI state management anti-patterns (@State singletons, Binding workarounds, .onAppear+.task races)
- All changes must compile cleanly under Swift 6 strict concurrency

**Non-Goals:**
- Localization / accessibility audit (separate change)
- Architectural refactoring (MVVM structure stays as-is)
- Adding new features or changing user-visible behavior
- Migrating to Swift 6.2 features (`@concurrent`, `nonisolated(nonsending)`)
- iOS deployment target changes

## Decisions

### D1: Replace `assumeIsolated` in deinit with direct Task.cancel()

**Choice:** Call `task?.cancel()` directly in deinit without any isolation wrapper.

**Rationale:** `Task.cancel()` is documented as thread-safe — it sets a cancellation flag atomically. No MainActor isolation is needed. This is simpler and safer than `assumeIsolated`, which crashes if deinit runs on a background thread (which it intermittently does).

**Alternative considered:** `isolated deinit` (Swift 6.2+, iOS 18.4+). Rejected because the app supports iOS 17+.

**Affected files (9):** BackgroundSyncManager, TranscriptManager, PlaybackStateCoordinator, SettingsViewModel, PodcastSearchViewModel, EpisodeListViewModel, ExpandedPlayerViewModel, LibraryViewModel, HomeViewModel.

### D2: Replace `@unchecked Sendable` on ImageCacheManager with actor

**Choice:** Convert `ImageCacheManager` from `final class: @unchecked Sendable` to a proper `actor`.

**Rationale:** The class already uses a `DownloadCoordinator` actor internally and a `DispatchQueue` for synchronization. Converting to an actor replaces manual locking with compiler-verified isolation. `NSCache` is internally thread-safe, so it can be a `let` property on the actor safely.

**Alternative considered:** `Mutex<NSCache>` (iOS 18+). Rejected — deployment target is iOS 17+. Also considered `@MainActor` isolation, but image caching should not block the main thread.

### D3: Replace eager NavigationLink with .navigationDestination(item:)

**Choice:** Use `@State private var selectedEpisode: PodcastEpisodeInfo?` + `.navigationDestination(item:)` instead of `NavigationLink(destination:)`.

**Rationale:** `NavigationLink(destination:)` creates the destination view tree for every item in the list, even when not tapped. In HomeView, this means 10+ `EpisodeDetailView` instances (each with transcript setup, 10+ @State vars, parser initialization) created per scroll. `.navigationDestination(item:)` defers creation until tap.

**Alternative considered:** `NavigationLink(value:)` + `navigationDestination(for:)`. Equally valid, but `item:` binding is simpler for optional state.

### D4: Replace 100ms polling with observation + reduced frequency

**Choice:** Increase the polling interval from 100ms to 250ms and gate updates on actual time change (>0.5s delta).

**Rationale:** The current 100ms poll (10 wake-ups/sec) with linear search through sentences is excessive. The existing code already gates on 0.5s time delta, so polling at 250ms is sufficient. Full observation replacement (removing the timer entirely) would require deeper refactoring of how `EnhancedAudioManager.currentTime` is published, which is out of scope.

**Alternative considered:** Replace polling entirely with `@Observable` observation on `audioManager.currentTime`. Rejected for this change — `currentTime` updates at 4Hz from AVPlayer's periodic observer, which would trigger SwiftUI body evaluation at the same rate. The polling approach with explicit gating gives more control.

### D5: Move SearchView filtering to ViewModel

**Choice:** Move `filterLibraryPodcasts()` and `filterLibraryEpisodes()` from computed properties in the View body to stored properties in a ViewModel, updated via `onChange(of: searchText)`.

**Rationale:** Currently O(n×m) filtering runs on every SwiftUI body evaluation. Moving to the ViewModel means filtering only runs when the search text actually changes.

### D6: Fix @State singleton pattern

**Choice:** Replace `@State private var singleton = Foo.shared` with computed property `private var singleton: Foo { .shared }`.

**Rationale:** `@State` copies the reference and creates a separate observation scope. For `@Observable` singletons, SwiftUI already observes through the singleton's properties directly — no `@State` wrapper needed. The exception is when `$binding` syntax is required (check for `$varName` usage first).

## Risks / Trade-offs

**[Risk: ImageCacheManager actor migration breaks image loading]**
→ Mitigation: All callers already `await` the download coordinator. Converting to actor adds `await` to cache reads, which is a minor performance cost. Test image loading in lists after migration.

**[Risk: NavigationLink migration changes navigation behavior]**
→ Mitigation: `.navigationDestination(item:)` has identical navigation UX. Test that deep links and back navigation still work correctly in HomeView.

**[Risk: Removing assumeIsolated may leave tasks uncancelled]**
→ Mitigation: `Task.cancel()` is thread-safe and already works from deinit. The only difference is removing the crash-prone isolation assumption. Verify with Instruments that no task leaks occur.

**[Risk: SearchView filtering move changes timing of results]**
→ Mitigation: Results update on `onChange(of: searchText)` which fires synchronously with the text change. No user-visible delay difference.
