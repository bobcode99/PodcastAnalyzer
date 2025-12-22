# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PodcastAnalyzer is an iOS/macOS podcast player app built with SwiftUI and SwiftData. The app supports RSS feed subscriptions, episode downloads, audio playback with background support, and has infrastructure for future transcription features.

## Build & Test Commands

### Building the Project

```bash
# Build for iOS simulator
xcodebuild -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer -destination 'platform=iOS Simulator,name=iPhone 17' build

# Build for macOS
xcodebuild -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer -destination 'platform=macOS' build

# Clean build folder
xcodebuild -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer clean
```

### Running Tests

```bash
# Run all unit tests
xcodebuild test -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer -destination 'platform=iOS Simulator,name=iPhone 17'

# Run only unit tests (not UI tests)
xcodebuild test -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PodcastAnalyzerTests

# Run only UI tests
xcodebuild test -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PodcastAnalyzerUITests

# Run a single test
xcodebuild test -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PodcastAnalyzerTests/PodcastAnalyzerTests/testExample
```

### Package Dependencies

The project uses Swift Package Manager with these dependencies:

- **FeedKit** (10.1.3): RSS/Atom feed parsing
- **ZMarkupParser** (1.12.0): HTML description rendering
- **ZNSTextAttachment** (1.1.9): Text attachment support

Dependencies are resolved automatically by Xcode. To update packages:

```bash
xcodebuild -resolvePackageDependencies -project PodcastAnalyzer.xcodeproj
```

## Architecture Overview

### MVVM + SwiftUI Architecture

The app follows Model-View-ViewModel (MVVM) pattern with SwiftUI's reactive bindings:

**Data Flow:**

```
User Interaction → View → ViewModel → Service → Model/Persistence
                    ↑         ↓
                    └─ @Published / @Observable
```

### Core Components

#### 1. Entry Point & Navigation

- **PodcastAnalyzerApp.swift**: App entry point, initializes SwiftData ModelContainer
- **ContentView.swift**: Root TabView with 3 tabs (Home, Settings, Search) + MiniPlayerBar overlay
- Navigation uses SwiftUI's NavigationStack with programmatic state management

#### 2. Views & ViewModels

Each major view has a corresponding ViewModel:

| View                                 | ViewModel              | Purpose                                 |
| ------------------------------------ | ---------------------- | --------------------------------------- |
| HomeView                             | HomeViewModel          | Display subscribed podcasts list        |
| SettingsView                         | SettingsViewModel      | Manage RSS feed subscriptions           |
| EpisodeListView (EpoisodeView.swift) | -                      | Shows episodes for a podcast            |
| EpisodeDetailView                    | EpisodeDetailViewModel | Episode details, download, playback     |
| PlayerView                           | PlayerViewModel        | Full-screen immersive player            |
| MiniPlayerBar                        | MiniPlayerViewModel    | Bottom overlay showing current playback |

**ViewModel Patterns:**

- Use `@Published` properties for reactive UI updates
- EpisodeDetailViewModel uses `@Observable` (newer approach)
- ViewModels coordinate between Views and Services (never direct service calls from Views)

#### 3. Services Layer (Singletons & Actors)

**EnhancedAudioManager.shared** (Singleton, @Observable)

- Central audio playback engine using AVPlayer
- Manages playback state, speed control, seek operations
- Handles background playback and lock screen controls via MediaPlayer framework
- Loads and parses SRT caption files for display
- Persists playback state to UserDefaults

**PodcastRssService** (Actor)

- Fetches and parses RSS feeds using FeedKit
- Async/await API: `fetchPodcast(from: String) async throws -> PodcastInfo`
- Thread-safe feed parsing

**DownloadManager.shared** (Singleton, URLSessionDownloadDelegate)

- Manages episode audio downloads with URLSession background configuration
- Tracks download progress and state per episode
- Supports cancel/delete operations
- Uses FileStorageManager for file I/O

**FileStorageManager.shared** (Actor)

- Organizes files by type:
  - Audio: `~/Library/Audio/` (not user-visible)
  - Captions: `~/Documents/Captions/` (accessible in Files app)
- Thread-safe file operations (save/load/delete)
- Returns human-readable file sizes

**TranscriptService** (Actor, iOS 17+)

- Scaffolding for speech-to-text transcription using Apple Speech framework
- Not fully integrated yet

#### 4. Models & Persistence

**SwiftData Models (Persisted):**

- `PodcastInfoModel`: Podcast metadata with UUID, episodes list, RSS URL
- `EpisodeDownloadModel`: Tracks playback position, completion state, download date

**Runtime Structs:**

- `PodcastInfo`: Core podcast data structure
- `PodcastEpisodeInfo`: Episode metadata
- `PlaybackEpisode`: Lightweight episode representation during playback
- `DownloadState` (enum): notDownloaded, downloading(progress), downloaded(path), failed(error)

### Key Architectural Decisions

1. **Singleton Services**: Audio, download, and file storage are singletons to maintain global state across the app

2. **Actor-Based Concurrency**: PodcastRssService, FileStorageManager, and TranscriptService use Swift Actors for thread-safe async operations

3. **Polling vs Combine**: MiniPlayerBar and PlayerView use Timer-based polling of EnhancedAudioManager state (simpler than Combine publishers)

4. **Local-First**: SwiftData provides offline-first persistence with no remote sync

5. **Background Downloads**: URLSession background configuration allows downloads to continue when app is suspended

6. **No backward compatibility** - Break old formats freely

## Common Development Patterns

### Adding a New View with ViewModel

1. Create view in `Views/` directory:

```swift
struct MyNewView: View {
    @StateObject private var viewModel = MyNewViewModel()

    var body: some View {
        // UI code
    }
}
```

2. Create ViewModel in `ViewModels/` directory:

```swift
class MyNewViewModel: ObservableObject {
    @Published var data: [Item] = []

    func loadData() {
        // Business logic
    }
}
```

### Accessing SwiftData

Inject ModelContext in views that need database access:

```swift
@Environment(\.modelContext) private var modelContext

// Query data
let podcasts = try? modelContext.fetch(FetchDescriptor<PodcastInfoModel>())

// Insert
modelContext.insert(newPodcast)

// Delete
modelContext.delete(podcast)
```

### Playing Audio

Always use EnhancedAudioManager.shared:

```swift
EnhancedAudioManager.shared.play(
    episode: playbackEpisode,
    audioURL: audioURL,
    startTime: lastPosition,
    imageURL: imageURL
)
```

### Managing Downloads

Use DownloadManager.shared with state observation:

```swift
@Published var downloadState: DownloadState = .notDownloaded

DownloadManager.shared.downloadEpisode(
    episodeID: episode.audioURL,
    audioURL: episode.audioURL,
    episodeTitle: episode.title
)

// Observe state changes
if case .downloading(let progress) = downloadState {
    // Update UI with progress
}
```

### File Storage

Use FileStorageManager actor for file I/O:

```swift
// Save audio file
try await FileStorageManager.shared.saveAudioFile(data: audioData, filename: "episode.mp3")

// Get file path
let path = await FileStorageManager.shared.getAudioFilePath(filename: "episode.mp3")

// Delete file
try await FileStorageManager.shared.deleteAudioFile(filename: "episode.mp3")
```

## Critical Implementation Notes

### 1. Audio Playback State Management

- EnhancedAudioManager is the single source of truth for playback state
- PlayerViewModel and MiniPlayerViewModel both poll EnhancedAudioManager
- DO NOT create multiple AVPlayer instances - always use the shared manager
- Playback state persists to UserDefaults (last episode, position, speed)

### 2. Download State Synchronization

- DownloadManager tracks state per episode via audioURL as key
- State transitions: notDownloaded → downloading(%) → downloaded(path) OR failed(error)
- Always check download state before attempting to play locally
- EpisodeDetailViewModel computes `hasLocalAudio` to determine play source

### 3. SwiftData Schema

- Schema includes only PodcastInfoModel (episodes are nested arrays, not separate entities)
- EpisodeDownloadModel tracks playback state separately
- Migration strategy: Not implemented yet - schema changes will reset data

### 4. Background Playback Requirements

- Info.plist must include "Privacy - Microphone Usage Description" (for future transcription)
- AVAudioSession configured for playback category in EnhancedAudioManager
- MediaPlayer framework updates lock screen "Now Playing" info
- URLSession background configuration enables download persistence

### 5. File Naming Conventions

- Audio files sanitized: replace spaces/special chars with underscores
- Filename format: `{podcast_title}_{episode_title}.mp3`
- Caption files: `{episode_id}.srt`

## Constants & Configuration

See `PodcastAnalyzer/Constants.swift`:

- `apiBaseURL`: Placeholder for future API integration
- `maxConcurrentDownloads`: 4 simultaneous downloads
- `supportedAudioFormats`: ["mp3", "aac", "wav", "flac"]
- Tab names and icon SF Symbol names

## Known Limitations & Future Work

**Not Implemented:**

- Search functionality (SearchView is placeholder with magnifying glass icon)
- Actual transcription generation (TranscriptService exists but not wired up)
- Podcast discovery API
- Playback history analytics
- Cross-device sync
- Sleep timer
- Playlist management
- AirPlay device selection

**Partially Implemented:**

- Captions: SRT parsing and display works, but generation via TranscriptService is incomplete
- Error handling: Some services throw errors, but UI error display is inconsistent

## Debugging Tips

### Audio Playback Issues

- Check AVPlayer status in EnhancedAudioManager
- Verify audio URL is accessible (stream vs local file)
- Check AVAudioSession configuration
- Review Console logs for AVFoundation errors

### Download Issues

- Check DownloadManager state dictionary
- Verify URLSession delegate callbacks are firing
- Inspect FileStorageManager paths (Library/Audio/)
- Check network permissions and reachability

### SwiftData Issues

- Verify ModelContainer initialization in PodcastAnalyzerApp
- Check ModelContext injection in views
- Review FetchDescriptor queries
- Look for SwiftData errors in Console

### UI Not Updating

- Ensure ViewModels use @Published or @Observable
- Verify Views observe ViewModels with @StateObject/@ObservedObject
- Check Timer-based polling intervals (PlayerView: 0.1s, MiniPlayerBar: 0.5s)
- Confirm main thread for UI updates after async operations
