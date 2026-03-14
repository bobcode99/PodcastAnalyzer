## Why

The transcript display system needs refinement to improve user experience. Currently, the ExpandedPlayerView includes a transcript preview section that clutters the UI, auto-generate transcript options are scattered in ellipsis menus making them hard to discover, and while the segment-level highlighting exists, it needs comprehensive tests to ensure reliability.

## What Changes

- **Remove transcriptPreviewSection from ExpandedPlayerView** - Clean up the player view by removing the transcript preview; users can access transcripts in EpisodeDetailView
- **Add "Auto-generate Transcripts" toggle to Settings** - Move the auto-generate transcript preference to the Settings > Transcript section for better discoverability
- **Remove auto-generate transcript options from ellipsis menus** - Clean up episode menus by removing redundant transcript generation options
- **Add unit tests for transcript grouping and highlighting logic** - Test TranscriptGrouping, SentenceHighlightState, and segment-level highlighting within sentences

## Capabilities

### New Capabilities
- `auto-transcript-setting`: User preference for automatically generating transcripts when episodes are downloaded/played

### Modified Capabilities
_(None - existing transcript-display behavior is preserved, just moving where settings are controlled)_

## Impact

**Files affected:**
- `Views/ExpandedPlayerView.swift` - Remove transcriptPreviewSection and related code
- `Views/SettingsView.swift` - Add auto-generate transcript toggle
- `ViewModels/SettingsViewModel.swift` - Add auto-generate transcript setting persistence
- `Models/SubtitleSettingsModel.swift` or new settings model - Store auto-generate preference
- `Views/EpisodeMenuActions.swift` - Remove transcript generation options
- `Views/Components/TranscriptViews.swift` - No changes, but needs test coverage

**Tests to add:**
- `TranscriptGroupingTests.swift` - Test sentence grouping from segments
- `SentenceHighlightStateTests.swift` - Test highlight state computation
- `TranscriptSegmentTests.swift` - Test time-based segment lookups
