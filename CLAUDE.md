# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PodcastAnalyzer is an iOS/macOS podcast player app built with SwiftUI and SwiftData. The app supports RSS feed subscriptions, episode downloads, audio playback with background support, and has infrastructure for future transcription features.

## Build & Test Commands

```bash
# Build for iOS simulator
xcodebuild -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer -destination 'platform=iOS Simulator,name=iPhone 17' build

# Build for macOS
xcodebuild -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer -destination 'platform=macOS' build

# Clean build folder
xcodebuild -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer clean

# Run all tests
xcodebuild test -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer -destination 'platform=iOS Simulator,name=iPhone 17'

# Run only unit tests
xcodebuild test -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PodcastAnalyzerTests

# Run a single test
xcodebuild test -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PodcastAnalyzerTests/PodcastAnalyzerTests/testExample

# Resolve package dependencies
xcodebuild -resolvePackageDependencies -project PodcastAnalyzer.xcodeproj
```

## CI

GitHub Actions workflow (`.github/workflows/ios.yml`) runs build and tests on PRs to main branch using macOS runner with iOS Simulator.

## Architecture Overview

### MVVM + SwiftUI Architecture

The app follows Model-View-ViewModel (MVVM) pattern with SwiftUI's reactive bindings:

```
User Interaction → View → ViewModel → Service → Model/Persistence
                    ↑         ↓
                    └─ @Published / @Observable
```

- Views in `Views/` with corresponding ViewModels in `ViewModels/`
- ViewModels use `@Published` properties (or `@Observable` macro for newer ones like EpisodeDetailViewModel)
- ViewModels coordinate between Views and Services (never direct service calls from Views)

### Entry Point & Navigation

- **PodcastAnalyzerApp.swift**: App entry point, initializes SwiftData ModelContainer
- **ContentView.swift**: Root TabView with 3 tabs (Home, Settings, Search) + MiniPlayerBar overlay
- Navigation uses SwiftUI's NavigationStack with programmatic state management

### Services Layer (Singletons & Actors)

| Service | Type | Purpose |
|---------|------|---------|
| `EnhancedAudioManager.shared` | Singleton, @Observable | Central audio playback engine (AVPlayer), background playback, lock screen controls, SRT captions |
| `PodcastRssService` | Actor | RSS feed fetching/parsing via FeedKit |
| `DownloadManager.shared` | Singleton, URLSessionDownloadDelegate | Episode downloads with background URLSession |
| `FileStorageManager.shared` | Actor | File I/O for audio (`~/Library/Audio/`) and captions (`~/Documents/Captions/`) |
| `TranscriptService` | Actor, iOS 17+ | Speech-to-text scaffolding (not fully integrated) |

### Models & Persistence

**SwiftData Models:**
- `PodcastInfoModel`: Podcast metadata with UUID, episodes list (nested arrays), RSS URL
- `EpisodeDownloadModel`: Tracks playback position, completion state, download date

**Runtime Structs:**
- `PodcastInfo`, `PodcastEpisodeInfo`: Core data structures
- `PlaybackEpisode`: Lightweight episode representation during playback
- `DownloadState` (enum): notDownloaded, downloading(progress), downloaded(path), failed(error)

### Key Architectural Decisions

1. **Singleton Services**: Audio, download, and file storage are singletons to maintain global state
2. **Actor-Based Concurrency**: PodcastRssService, FileStorageManager, TranscriptService use Swift Actors for thread safety
3. **Polling vs Combine**: MiniPlayerBar (0.5s) and PlayerView (0.1s) use Timer-based polling of EnhancedAudioManager
4. **Local-First**: SwiftData provides offline-first persistence with no remote sync
5. **Background Downloads**: URLSession background configuration for download persistence
6. **No backward compatibility**: Break old formats freely

## Critical Implementation Notes

### Audio Playback
- EnhancedAudioManager is the single source of truth for playback state
- DO NOT create multiple AVPlayer instances - always use the shared manager
- Playback state persists to UserDefaults (last episode, position, speed)

### Download State
- DownloadManager tracks state per episode via audioURL as key
- State transitions: notDownloaded → downloading(%) → downloaded(path) OR failed(error)
- Always check download state before attempting to play locally

### SwiftData Schema
- Episodes are nested arrays in PodcastInfoModel, not separate entities
- Migration strategy: Not implemented - schema changes will reset data

### Background Playback Requirements
- AVAudioSession configured for playback category in EnhancedAudioManager
- MediaPlayer framework updates lock screen "Now Playing" info

### File Naming
- Audio files: `{podcast_title}_{episode_title}.mp3` (sanitized: spaces/special chars → underscores)
- Caption files: `{episode_id}.srt`

## Package Dependencies

- **FeedKit** (10.1.3): RSS/Atom feed parsing
- **ZMarkupParser** (1.12.0): HTML description rendering
- **ZNSTextAttachment** (1.1.9): Text attachment support

## Constants

See `PodcastAnalyzer/Constants.swift` for `maxConcurrentDownloads` (4), `supportedAudioFormats`, tab names, and SF Symbol names.
