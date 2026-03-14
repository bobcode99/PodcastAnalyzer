## Why

The Home tab's "Top Episodes" section has layout issues (oversized artwork, rank numbers, and misaligned ellipsis), CJK transcripts insert unwanted spaces when merging segments into sentences, and there's no way to reduce token consumption for CJK transcript text sent to AI. Additionally, the current transcript display shows raw segments — users need a merged sentence view with per-segment time-based highlighting for a reading-friendly experience.

## What Changes

- **Top Episodes layout polish**: Reduce artwork from 80pt to 56pt, rank number from `.title2` to `.headline`, tighten spacing, and position ellipsis inline instead of far-right overlay
- **CJK sentence spacing fix**: Remove space insertion between segments in `TranscriptSentence.text` when content is CJK (Chinese/Japanese/Korean)
- **CJK token reducer (Swift port)**: Port the core algorithm from [cjk-token-reducer](https://github.com/jserv/cjk-token-reducer) — language detection (Unicode range scoring), segment preservation (code blocks, URLs, English terms), and Google Translate API integration — to a Swift service for reducing AI token usage on CJK transcripts by 35-50%
- **Sentence-merged highlight transcript mode**: New display mode that merges SRT segments into natural sentences and highlights each segment's text portion in real-time as playback progresses through the sentence. Toggleable in Settings alongside existing display modes.

## Capabilities

### New Capabilities
- `cjk-token-reducer`: Swift port of CJK-to-English translation for token optimization — language detection, segment preservation, Google Translate API, caching
- `sentence-highlight-transcript`: Merged sentence display with per-segment time-based highlighting — segments joined into sentences, each segment's text highlighted according to its time range during playback

### Modified Capabilities
- (none — existing specs unchanged; these are additive changes + bug fixes)

## Impact

- **Files modified**:
  - `Views/HomeView.swift` — Top Episodes row layout adjustments (artwork size, spacing, ellipsis position)
  - `Views/Components/TranscriptViews.swift` — CJK spacing fix in `TranscriptSentence.text`, new sentence-highlight rendering mode
  - `Models/SubtitleSettingsModel.swift` — New display mode enum case for sentence-highlight
  - `Views/SettingsView.swift` — Toggle for sentence-highlight mode
- **Files created**:
  - `Services/CJKTokenReducer.swift` — Language detection, preservation, translation, caching
  - `Tests/CJKTokenReducerTests.swift` — Unit tests for detection, preservation, translation
- **Dependencies**: Google Translate free API (no key required, `translate.googleapis.com`), no new package dependencies
- **Risk**: Google Translate free API has rate limits; circuit breaker + caching mitigate this
