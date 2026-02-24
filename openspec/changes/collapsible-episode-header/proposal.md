## Why

The `EpisodeDetailHeaderView` (artwork, title, play/download buttons) permanently occupies ~140pt of vertical space, leaving limited room for transcript and AI analysis content — the primary use case once a user starts reading. Hiding the header on scroll down and revealing it on scroll up (like Safari's address bar) maximizes content area while keeping metadata one gesture away.

## What Changes

- Track scroll direction in `EpisodeDetailView` using `onScrollGeometryChange` (iOS 18+) or `GeometryReader` offset tracking
- Animate `EpisodeDetailHeaderView` collapse/expand with height + opacity transition on scroll direction change
- Keep tab selector always visible (pinned) — only the header collapses
- Automatically expand header when user scrolls back to the top
- Preserve existing header functionality (NavigationLink, play button, download button) — no behavior changes

## Capabilities

### New Capabilities
- `collapsible-scroll-header`: Scroll-direction-aware header collapse/expand behavior in EpisodeDetailView, using SwiftUI scroll phase and geometry tracking

### Modified Capabilities
<!-- None — this is additive behavior on an existing view, no existing spec requirements change -->

## Impact

- **Files**: `EpisodeDetailView.swift`, `EpisodeDetailHeaderView.swift`
- **APIs**: Uses `onScrollGeometryChange` (iOS 18+) or `ScrollView` offset tracking
- **Dependencies**: None — pure SwiftUI
- **Risk**: Low — additive animation on existing layout, no data flow changes
