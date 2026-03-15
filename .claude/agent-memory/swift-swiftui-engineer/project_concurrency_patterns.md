---
name: Swift Concurrency Patterns in PodcastAnalyzer
description: Observed async/await and Task patterns, redundancies, and fixes applied in the codebase
type: project
---

## Redundant `await MainActor.run {}` in `@MainActor` classes

`BackgroundSyncManager`, `DownloadManager`, and `EnhancedAudioManager` are all `@MainActor @Observable`. Tasks spawned from their methods inherit that isolation, so `await MainActor.run {}` inside those Tasks is a no-op and should be removed.

**Why:** Tasks created inside `@MainActor` context inherit `@MainActor` isolation. All state mutations (e.g., `notificationPermissionStatus = .authorized`) are already on the main actor.

**How to apply:** Whenever reviewing code in these singletons, flag any `await MainActor.run { }` inside `Task { }` blocks — it's always redundant.

## `AsyncStream.makeStream(of:)` replaces old closure-based pattern

`TranscriptService` (actor) previously used `AsyncStream { continuation in Task { ... } }`. Modern pattern:

```swift
let (stream, continuation) = AsyncStream.makeStream(of: Double.self)
let setupTask = Task { await self.setupAndInstallAssetsInternal(continuation: continuation) }
continuation.onTermination = { _ in setupTask.cancel() }
return stream
```

Same applies to `AsyncThrowingStream.makeStream(of:)` for `audioToSRTWithProgress` and `audioToSRTChunkedWithProgress`.

**Why:** `makeStream` is cleaner, easier to pair with `onTermination`, and avoids the nested Task-inside-closure smell.

## Foreground sync timer: fire immediately on start

`BackgroundSyncManager.startForegroundSync()` previously slept _first_, meaning the first foreground sync after app launch was delayed 4 hours. Fixed: call `syncNow()` before entering the sleep loop.

## Task lifecycle: store all Tasks for cancellation

Properties added:
- `BackgroundSyncManager`: `foregroundSyncTask` was already stored (good)
- `LibraryViewModel`: `initTask: Task<Void, Never>?` — previously bare `Task { await loadAll() }` in init; now stored and cancelled in `cleanup()`
- `EnhancedAudioManager`: `captionLoadTask: Task<Void, Never>?` — cancels previous load before starting new one; checked `Task.isCancelled` before writing state; cancelled in `cleanup()`
- `TranscriptManager`: added `cancelAll()` to cancel all `processingTasks` and clear all state dictionaries

## Weak-self pattern inside `@MainActor` class Task

After `guard let self else { return }` rebinds `self` as non-optional, using `guard let self = self` _again_ in the same scope is a compile error (Swift 6: can't re-bind a non-Optional). Use `guard !Task.isCancelled else { return }` instead.

## Duplicate download guard in DownloadManager

`downloadEpisode(episode:podcastTitle:language:)` now has a synchronous early-exit before the async `Task {}` block that checks for `.downloading`, `.finishing`, and `.downloaded` states. This prevents multiple concurrent downloads for the same episode.
