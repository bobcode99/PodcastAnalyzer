# PodcastAnalyzer - State Machine Architecture

This document provides a comprehensive overview of the state machines and workflows in the PodcastAnalyzer application.

## Table of Contents
1. [Overall System Architecture](#overall-system-architecture)
2. [Download State Machine](#download-state-machine)
3. [Transcript Generation State Machine](#transcript-generation-state-machine)
4. [AI Analysis State Machine](#ai-analysis-state-machine)
5. [Playback State Machine](#playback-state-machine)
6. [Complete Workflow Integration](#complete-workflow-integration)

---

## Overall System Architecture

```mermaid
graph TB
    subgraph "User Flow"
        A[Subscribe to RSS Feed] --> B[Browse Episodes]
        B --> C{User Action}
    end

    subgraph "Download Flow"
        C -->|Download| D[Download Manager]
        D --> E[Download State Machine]
    end

    subgraph "Transcript Flow"
        E -->|On Complete| F[Transcript Manager]
        F --> G[Transcript State Machine]
    end

    subgraph "AI Analysis Flow"
        G -->|On Complete| H[Cloud AI Service]
        H --> I[AI Analysis State Machine]
    end

    subgraph "Playback Flow"
        C -->|Play| J[Audio Manager]
        E -->|Local File| J
        J --> K[Playback State Machine]
        G -->|Captions Ready| J
    end

    style D fill:#e1f5ff
    style F fill:#fff4e1
    style H fill:#ffe1f0
    style J fill:#e1ffe1
```

---

## Download State Machine

The `DownloadState` enum manages episode audio file downloads with progress tracking.

### States
```swift
enum DownloadState {
    case notDownloaded
    case downloading(progress: Double)  // 0.0 to 1.0
    case finishing                      // Processing downloaded file
    case downloaded(localPath: String)
    case failed(error: String)
}
```

### State Transitions
```mermaid
stateDiagram-v2
    [*] --> notDownloaded

    notDownloaded --> downloading: User initiates download

    downloading --> downloading: Progress updates (0% → 100%)
    downloading --> finishing: Download complete (URLSession callback)
    downloading --> failed: Network error / Cancellation
    downloading --> notDownloaded: User cancels

    finishing --> downloaded: File saved successfully
    finishing --> failed: File save error

    downloaded --> notDownloaded: User deletes download

    failed --> notDownloaded: User retries
    failed --> downloading: Automatic retry (optional)

    note right of finishing
        Critical state: URLSession temp file
        must be copied immediately before
        delegate method returns
    end note

    note right of downloaded
        File stored in:
        iOS: ~/Library/Audio/
        macOS: ~/ApplicationSupport/PodcastAnalyzer/Audio/
    end note
```

### Key Implementation Details
- **Manager**: `DownloadManager.shared` (Singleton, @Observable)
- **Concurrency**: Background URLSession with up to 4 parallel downloads
- **Storage**: `FileStorageManager` actor handles file I/O
- **Auto-Transcript**: On download completion, optionally queues transcript generation
- **State Persistence**: Checks disk on app launch to restore `downloaded` state

### Code Location
- `PodcastAnalyzer/Services/DownloadManager.swift`
- `PodcastAnalyzer/Models/DownloadState.swift` (lines 19-25)

---

## Transcript Generation State Machine

The `TranscriptJobStatus` enum manages speech-to-text transcription using Apple's Speech framework.

### States
```swift
enum TranscriptJobStatus {
    case queued
    case downloadingModel(progress: Double)  // 0.0 to 1.0
    case transcribing(progress: Double)      // 0.0 to 1.0
    case completed
    case failed(error: String)
}
```

### State Transitions
```mermaid
stateDiagram-v2
    [*] --> queued

    queued --> downloadingModel: Job starts processing

    downloadingModel --> downloadingModel: Model download progress
    downloadingModel --> transcribing: Model ready
    downloadingModel --> failed: Model download failed

    transcribing --> transcribing: Transcription progress updates
    transcribing --> completed: SRT file generated
    transcribing --> failed: Transcription error

    completed --> [*]: Job cleaned up after 3s
    failed --> [*]: Job remains for error visibility

    note right of downloadingModel
        Downloads Apple Speech framework
        language models (~100MB per language)
        Only happens once per language
    end note

    note right of transcribing
        CPU-intensive work runs on
        background thread using Task.detached
        to avoid blocking UI
    end note

    note right of completed
        Saves SRT caption file to:
        ~/Documents/Captions/
        (user-accessible in Files app)
    end note
```

### Parallel Processing
```mermaid
graph LR
    A[TranscriptManager] -->|Max 2-4 concurrent| B[Job 1: transcribing]
    A -->|Max 2-4 concurrent| C[Job 2: downloadingModel]
    A -->|Max 2-4 concurrent| D[Job 3: queued]
    A -->|Max 2-4 concurrent| E[Job 4: transcribing]

    F[CPU Cores] -->|Background Thread| B
    F -->|Background Thread| C
    F -->|Background Thread| E

    style A fill:#fff4e1
    style B fill:#ffe1e1
    style C fill:#e1f5ff
    style E fill:#ffe1e1
```

### Key Implementation Details
- **Manager**: `TranscriptManager.shared` (iOS 17+, @Observable)
- **Service**: `TranscriptService` actor for Speech framework operations
- **Concurrency**: 2-4 parallel jobs based on device CPU cores
- **Output**: SRT subtitle format with ~5 second segments
- **Language Support**: Auto-detects from podcast metadata (supports 30+ languages)
- **Auto-Queue**: Triggered automatically if "Auto-Transcript" is enabled

### Code Location
- `PodcastAnalyzer/Services/TranscriptManager.swift`
- `PodcastAnalyzer/Services/TranscriptService.swift`

---

## AI Analysis State Machine

The `AnalysisState` enum manages cloud-based AI analysis of transcripts using user-provided API keys (BYOK - Bring Your Own Key).

### States
```swift
enum AnalysisState {
    case idle
    case analyzing(progress: Double, message: String)
    case completed
    case error(String)
}
```

### State Transitions
```mermaid
stateDiagram-v2
    [*] --> idle

    idle --> analyzing: User requests analysis

    analyzing --> analyzing: Streaming response updates
    analyzing --> completed: Analysis successful
    analyzing --> error: API error / Network failure

    completed --> idle: User requests new analysis
    error --> idle: User retries
    error --> analyzing: Automatic retry (optional)

    note right of analyzing
        Supports streaming responses:
        - OpenAI (GPT-4)
        - Claude (Anthropic)
        - Gemini (Google)
        - Grok (xAI)
        - Groq
        - Apple Intelligence (via Shortcuts)
    end note

    note right of completed
        Results persisted to SwiftData:
        - Summary (topics, takeaways)
        - Entities (people, orgs, products)
        - Highlights (quotes, moments)
        - Full Analysis (comprehensive)
        - Q&A History
    end note
```

### Analysis Types & Workflow
```mermaid
graph TB
    A[Transcript Available] --> B{Analysis Type}

    B -->|Summary| C[Extract: Topics, Takeaways, Audience]
    B -->|Entities| D[Extract: People, Orgs, Products, Locations]
    B -->|Highlights| E[Extract: Key Moments, Quotes, Actions]
    B -->|Full Analysis| F[Comprehensive Overview + All Above]
    B -->|Q&A| G[Question Answering]

    C --> H[Streaming Response]
    D --> H
    E --> H
    F --> H
    G --> H

    H --> I[Parse JSON Response]
    I --> J[Save to SwiftData]
    J --> K[Display in UI]

    style C fill:#e1f5ff
    style D fill:#ffe1f0
    style E fill:#fff4e1
    style F fill:#e1ffe1
    style G fill:#f0e1ff
```

### Key Implementation Details
- **Service**: `CloudAIService.shared` (@MainActor)
- **Settings**: `AISettingsManager` manages API keys and provider selection
- **Providers**:
  - OpenAI (GPT-4o, GPT-4o-mini)
  - Claude (Haiku 4.5, Sonnet 4.5, Opus 4.5)
  - Gemini (2.5 Flash, 2.0 Pro)
  - Grok (2, 3)
  - Groq (Llama, Mixtral)
  - Apple Intelligence (via Shortcuts app)
- **Response Format**: JSON with structured fields (parsed using Codable)
- **Streaming**: Real-time token-by-token display for better UX
- **Persistence**: `EpisodeAIAnalysis` SwiftData model

### Code Location
- `PodcastAnalyzer/Services/CloudAIService.swift`
- `PodcastAnalyzer/Models/AIAnalysisModel.swift`
- `PodcastAnalyzer/Models/EpisodeAnalysisModels.swift`

---

## Playback State Machine

The playback engine manages audio playback with background support, queue management, and caption display.

### Playback States
```mermaid
stateDiagram-v2
    [*] --> stopped

    stopped --> playing: User plays episode

    playing --> paused: User pauses / Interruption begins
    playing --> seeking: User seeks to position
    playing --> ended: Playback reaches end

    paused --> playing: User resumes / Interruption ends
    paused --> seeking: User seeks while paused
    paused --> stopped: User stops playback

    seeking --> playing: Seek complete (was playing)
    seeking --> paused: Seek complete (was paused)

    ended --> playing: Next episode in queue
    ended --> playing: Auto-play random unplayed episode
    ended --> stopped: No more episodes

    note right of playing
        Updates every 0.1s:
        - Current time
        - Caption text
        - Now Playing info

        Auto-saves every 5s:
        - Position to UserDefaults
        - Position to SwiftData
    end note

    note right of paused
        Handles interruptions:
        - Phone calls
        - Other app audio
        - Siri activation

        Resumes automatically when
        interruption ends
    end note
```

### Queue Management
```mermaid
graph TB
    A[Current Episode] --> B{Playback Ends}

    B -->|Queue Not Empty| C[Play Next in Queue]
    B -->|Queue Empty + Auto-Play ON| D{Unplayed Episodes Available?}
    B -->|Queue Empty + Auto-Play OFF| E[Stop Playback]

    D -->|Yes| F[Play Random Unplayed Episode]
    D -->|No| E

    C --> G[Remove from Queue]
    F --> H[Remove from Auto-Play Candidates]

    G --> A
    H --> A

    I[User Action: Add to Queue] --> J[Append to Queue End]
    K[User Action: Play Next] --> L[Insert at Queue Front]

    J --> M[Queue: max 50 episodes]
    L --> M

    style A fill:#e1ffe1
    style C fill:#e1f5ff
    style F fill:#fff4e1
```

### Audio Session & Background Playback
```mermaid
sequenceDiagram
    participant App
    participant AVPlayer
    participant AVAudioSession
    participant MediaPlayer
    participant iOS

    App->>AVPlayer: Load audio URL
    App->>AVAudioSession: Configure for .playback
    AVAudioSession->>iOS: Request audio session
    iOS-->>AVAudioSession: Session activated

    App->>AVPlayer: play()
    AVPlayer->>App: Time updates (every 0.1s)
    App->>MediaPlayer: Update Now Playing info
    MediaPlayer->>iOS: Update Lock Screen

    iOS->>App: Audio interruption (phone call)
    App->>AVPlayer: pause()
    App->>App: Store wasPlayingBeforeInterruption = true

    iOS->>App: Interruption ended
    App->>AVAudioSession: Reactivate session
    AVAudioSession-->>App: Session ready
    App->>AVPlayer: play() after 0.8s delay

    iOS->>App: Remote control (AirPods button)
    App->>AVPlayer: Execute command (play/pause/skip)
```

### Caption Display
```mermaid
stateDiagram-v2
    [*] --> noCaptions

    noCaptions --> captionsLoading: SRT file exists
    captionsLoading --> captionsReady: Parse complete
    captionsLoading --> noCaptions: Parse failed

    captionsReady --> displayingCaption: Current time matches segment
    displayingCaption --> captionsReady: Time moves to next/no segment

    note right of captionsReady
        SRT segments parsed:
        - Start time
        - End time
        - Text content

        Updated every 0.1s based on
        current playback time
    end note
```

### Key Implementation Details
- **Manager**: `EnhancedAudioManager.shared` (Singleton, @Observable)
- **Player**: AVPlayer with AVAudioSession for background playback
- **Remote Controls**: MediaPlayer framework for lock screen/AirPods/CarPlay
- **Queue**:
  - Max 50 episodes
  - Supports reordering
  - "Play Next" vs "Add to Queue"
- **Auto-Play**: Random selection from unplayed episodes when queue is empty
- **Speed Control**: 0.5x to 2.0x playback rate
- **Captions**: SRT file parsing and time-synchronized display
- **State Persistence**:
  - UserDefaults: Last episode, position, speed
  - SwiftData: Per-episode playback progress

### Code Location
- `PodcastAnalyzer/Services/EnhancedAudioManager.swift`

---

## Complete Workflow Integration

### End-to-End User Journey
```mermaid
sequenceDiagram
    autonumber
    participant User
    participant UI
    participant DownloadMgr as Download Manager
    participant TranscriptMgr as Transcript Manager
    participant AIMgr as AI Service
    participant AudioMgr as Audio Manager
    participant Storage

    User->>UI: Subscribe to RSS feed
    UI->>Storage: Save PodcastInfoModel

    User->>UI: Browse episodes
    UI->>User: Display episode list

    User->>UI: Download episode
    UI->>DownloadMgr: downloadEpisode()
    DownloadMgr->>DownloadMgr: State: notDownloaded → downloading
    DownloadMgr->>UI: Progress updates (10%, 20%, ...)
    DownloadMgr->>DownloadMgr: State: downloading → finishing
    DownloadMgr->>Storage: Save audio file
    DownloadMgr->>DownloadMgr: State: finishing → downloaded

    alt Auto-Transcript Enabled
        DownloadMgr->>TranscriptMgr: queueTranscript()
        TranscriptMgr->>TranscriptMgr: State: queued → downloadingModel
        TranscriptMgr->>TranscriptMgr: Download Speech model if needed
        TranscriptMgr->>TranscriptMgr: State: downloadingModel → transcribing
        TranscriptMgr->>UI: Progress updates (0%, 25%, 50%, ...)
        TranscriptMgr->>Storage: Save SRT caption file
        TranscriptMgr->>TranscriptMgr: State: transcribing → completed
    end

    User->>UI: Request AI Analysis
    UI->>AIMgr: analyzeTranscriptStreaming()
    AIMgr->>AIMgr: State: idle → analyzing
    AIMgr->>AIMgr: Load transcript from SRT file
    AIMgr->>AIMgr: Send to Cloud AI (streaming)
    AIMgr->>UI: Stream response chunks
    AIMgr->>Storage: Save EpisodeAIAnalysis
    AIMgr->>AIMgr: State: analyzing → completed

    User->>UI: Play episode
    UI->>AudioMgr: play()
    AudioMgr->>AudioMgr: State: stopped → playing
    AudioMgr->>AudioMgr: Load captions if available

    loop Every 0.1s
        AudioMgr->>AudioMgr: Update currentTime
        AudioMgr->>AudioMgr: Update currentCaption
        AudioMgr->>UI: Publish state changes
    end

    loop Every 5s
        AudioMgr->>Storage: Save playback position
    end

    User->>UI: Pause playback
    UI->>AudioMgr: pause()
    AudioMgr->>AudioMgr: State: playing → paused

    Note over User,Storage: User can resume playback later,<br/>position is restored from storage
```

### State Dependencies & Triggers
```mermaid
graph TB
    subgraph "Download Phase"
        A[notDownloaded] -->|User Action| B[downloading]
        B -->|Complete| C[downloaded]
    end

    subgraph "Transcript Phase"
        C -->|Auto-Trigger| D[queued]
        D -->|Processing| E[transcribing]
        E -->|Complete| F[SRT File Saved]
    end

    subgraph "AI Analysis Phase"
        F -->|User Action| G[analyzing]
        G -->|Complete| H[Analysis Saved]
    end

    subgraph "Playback Phase"
        C -->|User Action| I[stopped]
        I -->|Play| J[playing]
        F -->|Captions| J
        H -->|Context| J
    end

    style C fill:#90EE90
    style F fill:#FFD700
    style H fill:#FF69B4
    style J fill:#87CEEB

    C -.->|Optional: Stream| I

    classDef complete fill:#90EE90,stroke:#333,stroke-width:2px
    classDef processing fill:#FFB347,stroke:#333,stroke-width:2px
    classDef ready fill:#87CEEB,stroke:#333,stroke-width:2px
```

### Concurrent State Machines
Multiple episodes can be in different states simultaneously:

| Episode | Download | Transcript | AI Analysis | Playback |
|---------|----------|------------|-------------|----------|
| Episode 1 | downloaded | completed | completed | **playing** |
| Episode 2 | downloaded | transcribing (75%) | idle | stopped |
| Episode 3 | downloading (50%) | queued | idle | stopped |
| Episode 4 | notDownloaded | - | - | stopped |

**Key Points:**
- Download Manager: Max 4 concurrent downloads
- Transcript Manager: Max 2-4 concurrent transcription jobs
- Audio Manager: Only 1 episode can be playing at a time
- AI Service: Processes one analysis request at a time (per episode)

---

## Implementation Patterns

### Singleton Services
All major services use the singleton pattern for global state management:
```swift
DownloadManager.shared
TranscriptManager.shared
EnhancedAudioManager.shared
CloudAIService.shared
FileStorageManager.shared
```

### Concurrency Models
- **Actors**: `TranscriptService`, `FileStorageManager` (thread-safe async operations)
- **@Observable**: `DownloadManager`, `TranscriptManager`, `EnhancedAudioManager` (SwiftUI reactive updates)
- **@MainActor**: `CloudAIService` (UI-bound operations)

### State Persistence
- **UserDefaults**: Lightweight state (playback position, settings)
- **SwiftData**: Relational data (episodes, analysis results, download records)
- **FileManager**: Binary data (audio files, caption files)

### Error Handling Strategy
All state machines include explicit error states and recovery paths:
- **Download**: Retry on network failure, cancel on user request
- **Transcript**: Fail gracefully, show error in UI
- **AI Analysis**: Parse API errors, suggest remediation
- **Playback**: Handle interruptions, resume when possible

---

## Architecture Highlights

### ✅ Strengths
- **Clear State Separation**: Each domain has its own state machine
- **Observable Pattern**: SwiftUI-friendly reactive updates
- **Async/Await**: Modern Swift concurrency throughout
- **Background Processing**: Downloads and transcriptions continue when app is suspended
- **Graceful Degradation**: Each feature works independently (can play without transcript, transcript without AI)
- **Parallel Processing**: Efficient use of device resources

### 🔄 State Synchronization
- Download completion triggers transcript queue (if enabled)
- Transcript completion enables AI analysis
- All states update UI reactively via @Observable
- SwiftData provides persistence layer for cross-session state recovery

### 🎯 User Experience Flow
1. **Immediate Feedback**: All operations show progress (0-100%)
2. **Background Work**: CPU-intensive tasks run on background threads
3. **State Restoration**: App remembers playback position and download state
4. **Queue Management**: Smart auto-play keeps users engaged
5. **Offline-First**: Core playback works without network

---

## File References

### Core Services
- `PodcastAnalyzer/Services/DownloadManager.swift` - Download state machine
- `PodcastAnalyzer/Services/TranscriptManager.swift` - Transcript job management
- `PodcastAnalyzer/Services/TranscriptService.swift` - Speech framework integration
- `PodcastAnalyzer/Services/CloudAIService.swift` - AI analysis orchestration
- `PodcastAnalyzer/Services/EnhancedAudioManager.swift` - Playback engine
- `PodcastAnalyzer/Services/FileStorageManager.swift` - File I/O operations

### Models
- `PodcastAnalyzer/Models/DownloadState.swift` - Download state enum
- `PodcastAnalyzer/Models/AIAnalysisModel.swift` - AI analysis persistence
- `PodcastAnalyzer/Models/EpisodeAnalysisModels.swift` - Analysis types and cache

### ViewModels
- `PodcastAnalyzer/ViewModels/EpisodeDetailViewModel.swift` - Episode detail coordination
- `PodcastAnalyzer/ViewModels/PlayerViewModel.swift` - Playback UI state

---

*Generated: 2026-01-18*
*PodcastAnalyzer - iOS/macOS Podcast Player & Analyzer*
