## PodcastAnalyzer

PodcastAnalyzer is an iOS app for organizing, analyzing, and listening to podcast episodes. It focuses on smarter episode discovery, AI‑assisted insights, and a polished SwiftUI listening experience.

### Features

- **Episode library**: Browse and manage your saved podcast episodes.
- **Search**: Quickly find episodes by title or metadata.
- **AI analysis**: View AI‑generated insights and transcript‑driven features for each episode.
- **SwiftUI UI**: Modern, responsive interface built with SwiftUI and Combine.

### Requirements

- **Xcode**: 15 or later (project currently runs on newer Xcode 26.x CI images).
- **iOS**: Target iOS version is configured in the Xcode project (open the project to see the exact minimum).

### Getting started

1. Clone the repository:

```bash
git clone https://github.com/bobcode99/PodcastAnalyzer.git
cd PodcastAnalyzer/PodcastAnalyzer
```

2. Open the Xcode project:

```bash
open PodcastAnalyzer.xcodeproj
```

3. Select the `PodcastAnalyzer` scheme and choose an iOS Simulator (or device).

4. Build and run the app from Xcode (`⌘R`).

### Running tests

- **From Xcode**:  
  - Select the `PodcastAnalyzer` scheme.  
  - Press `⌘U` to run the unit tests.

- **From the command line** (unit tests only, matching CI):

```bash
xcodebuild \
  test \
  -scheme PodcastAnalyzer \
  -project PodcastAnalyzer.xcodeproj \
  -destination "platform=iOS Simulator,name=iPhone 16" \
  -only-testing:PodcastAnalyzerTests
```

GitHub Actions is configured to run only the `PodcastAnalyzerTests` unit tests by default.

### Folder structure (high level)

- `PodcastAnalyzer/PodcastAnalyzer/Views` – SwiftUI views for core screens (episode list, search, AI analysis, data management, etc.).
- `PodcastAnalyzer/PodcastAnalyzer/Utilities` – Shared utility types and helpers (formatters, episode actions, etc.).
- `PodcastAnalyzer/PodcastAnalyzerTests` – Unit tests for parsing, formatting, state, and other core logic.

### Contributing

Improvements and bug fixes are welcome. Feel free to open an issue or pull request with a clear description and, if possible, tests that cover your changes.

# Podcast analyzer


Useful links:
https://castos.com/tools/find-podcast-rss-feed/
