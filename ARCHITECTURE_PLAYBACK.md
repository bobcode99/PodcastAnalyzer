# Playback State & Download Architecture

## Overview

The app uses **TWO separate data models** to keep RSS feed data separate from user-specific state:

```
┌─────────────────────────────────────────────────────────────┐
│                     RSS FEED DATA (Read-Only)                │
├─────────────────────────────────────────────────────────────┤
│ PodcastInfo (struct)           PodcastEpisodeInfo (struct)   │
│ - title                        - title                       │
│ - description                  - description                 │
│ - episodes[]                   - pubDate                     │
│ - rssUrl                       - audioURL                    │
│ - imageURL                     - imageURL                    │
│                                                               │
│ Stored in: PodcastInfoModel (SwiftData)                      │
│ Purpose: RSS subscription data, refreshed when feed updates  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│              USER STATE DATA (Per-Episode Tracking)          │
├─────────────────────────────────────────────────────────────┤
│ EpisodeDownloadModel (SwiftData @Model)                      │
│ - id: "podcastTitle|episodeTitle"  ← UNIQUE KEY              │
│ - episodeTitle                                               │
│ - podcastTitle                                               │
│ - audioURL                                                   │
│                                                               │
│ PLAYBACK STATE:                                              │
│ - lastPlaybackPosition: TimeInterval  ← RESUME TIMESTAMP     │
│ - isCompleted: Bool                                          │
│ - lastPlayedDate: Date?                                      │
│                                                               │
│ DOWNLOAD STATE:                                              │
│ - localAudioPath: String?  ← WHERE DOWNLOADED FILE IS        │
│ - downloadedDate: Date?                                      │
│ - fileSize: Int64                                            │
│ - captionPath: String?                                       │
│                                                               │
│ Purpose: Track what user has played/downloaded PER EPISODE   │
└─────────────────────────────────────────────────────────────┘
```

## How Playback Position Saving Works (Fixed)

### Step 1: User Plays Episode
```swift
EpisodeDetailView
    ↓
EpisodeDetailViewModel.playAction()
    ↓
EnhancedAudioManager.play(episode, audioURL, startTime, imageURL)
```

### Step 2: Automatic Position Broadcasting
```swift
EnhancedAudioManager (every 5 seconds during playback)
    ↓
postPlaybackPositionUpdate()
    ↓
NotificationCenter.post(.playbackPositionDidUpdate)
    ↓
PlaybackPositionUpdate {
    episodeTitle: "EP123"
    podcastTitle: "My Podcast"
    position: 245.0 seconds
    duration: 1800.0 seconds
    audioURL: "https://..."
}
```

### Step 3: PlaybackStateCoordinator Saves to Database
```swift
PlaybackStateCoordinator.savePlaybackPosition()
    ↓
Search for existing EpisodeDownloadModel by id
    ↓
IF FOUND:
    ✅ Update lastPlaybackPosition
    ✅ Update lastPlayedDate
    ✅ Mark isCompleted if near end
ELSE:
    ✅ CREATE NEW EpisodeDownloadModel  ← FIXED!
    ✅ Set initial values
    ↓
context.save() → SwiftData database
```

### Step 4: Resume Next Time
```swift
User opens episode again
    ↓
EpisodeDetailViewModel.loadEpisodeModel()
    ↓
Fetch EpisodeDownloadModel from SwiftData
    ↓
IF FOUND:
    startTime = model.lastPlaybackPosition  ← RESUME HERE!
ELSE:
    startTime = 0  ← START FROM BEGINNING
    ↓
audioManager.play(episode, audioURL, startTime, imageURL)
```

## How Download State Works

### Download Process:
```
User taps "Download"
    ↓
DownloadManager.downloadEpisode()
    ↓
URLSession downloads to temp file
    ↓
FileStorageManager.saveAudioFile()
    ↓
File moved to: ~/Library/Audio/PodcastTitle_EpisodeTitle.mp3
    ↓
DownloadManager updates: downloadStates[key] = .downloaded(path)
    ↓
UI shows "Downloaded" badge
```

### Checking Download Status:
```
DownloadManager.getDownloadState(episodeTitle, podcastTitle)
    ↓
Check in-memory downloadStates dictionary
    ↓
IF NOT FOUND:
    ✅ Check disk: Does file exist in ~/Library/Audio/?
    ✅ If YES: Restore state to .downloaded(path)
    ✅ If NO: Return .notDownloaded
```

### Playing Downloaded Episodes:
```
User taps "Play" on downloaded episode
    ↓
EpisodeDetailViewModel.playAction()
    ↓
Check: hasLocalAudio?
    ↓
IF YES:
    playbackURL = "file:///path/to/downloaded/file.mp3"
ELSE:
    playbackURL = "https://stream/url"
    ↓
audioManager.play(episode, playbackURL, ...)
```

## Storage Locations

### SwiftData Database:
- **Location**: App's documents directory (managed by SwiftData)
- **Contains**:
  - `PodcastInfoModel` - Subscribed podcasts
  - `EpisodeDownloadModel` - Per-episode state

### File System:
- **Audio Files**: `~/Library/Audio/PodcastTitle_EpisodeTitle.{mp3|m4a|aac}`
- **Captions**: `~/Documents/Captions/PodcastTitle_EpisodeTitle.srt`
- **UserDefaults**: Last played episode (for mini player persistence)

## Key Improvements Made

### Before (BROKEN):
- ❌ PlaybackStateCoordinator only updated existing models
- ❌ If you played a new episode, position was NEVER saved
- ❌ Download state lost on app restart

### After (FIXED):
- ✅ PlaybackStateCoordinator auto-creates models for new episodes
- ✅ Every episode automatically tracked in SwiftData
- ✅ Download state restored from disk on app restart
- ✅ Multi-format support (mp3, m4a, aac, wav, flac)

## Debugging

To verify playback saving is working, check logs for:
```
✅ Saved playback: EP123 at 245s / 1800s
Creating new episode model for: EP123
Updating existing episode model: EP123
```

To verify download restoration:
```
Created audio directory: /path/to/Library/Audio
Saved audio file: PodcastTitle_EpisodeTitle.mp3 with extension: mp3
```

## Summary

**The Answer to Your Question:**
- Episodes are **NOT cached** - they're stored in SwiftData (persistent database)
- `EpisodeDownloadModel` is the database table that stores per-episode state
- It's separate from the RSS feed data to avoid mixing feed data with user data
- Each episode gets its own row in the database when first played
- Position is auto-saved every 5 seconds, on pause, and on seek
