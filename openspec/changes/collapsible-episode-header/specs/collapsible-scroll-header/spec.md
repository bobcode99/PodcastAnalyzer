## ADDED Requirements

### Requirement: EpisodeDetailHeaderView SHALL collapse when user scrolls down
The `EpisodeDetailHeaderView` SHALL animate to zero height with opacity fade when the user scrolls downward past a 5pt threshold in any tab's ScrollView. The tab selector SHALL remain visible at all times.

#### Scenario: User scrolls down in transcript tab
- **WHEN** the user scrolls down more than 5pt in the transcript tab
- **THEN** the `EpisodeDetailHeaderView` animates to collapsed state (height 0, opacity 0) over 0.25s
- **AND** the tab selector remains pinned and visible
- **AND** the tab content expands to fill the freed space

#### Scenario: User scrolls down in summary tab
- **WHEN** the user scrolls down more than 5pt in the summary tab
- **THEN** the header collapses with the same animation behavior

#### Scenario: User scrolls down in AI analysis tab
- **WHEN** the user scrolls down more than 5pt in the AI analysis tab
- **THEN** the header collapses with the same animation behavior

### Requirement: EpisodeDetailHeaderView SHALL expand when user scrolls up
The `EpisodeDetailHeaderView` SHALL animate back to full height with opacity when the user scrolls upward past a 5pt threshold. The header SHALL always be visible when content is scrolled to the top (offset ≤ 0).

#### Scenario: User scrolls up after header is collapsed
- **WHEN** the header is collapsed and the user scrolls up more than 5pt
- **THEN** the header animates to expanded state (full height, opacity 1) over 0.25s

#### Scenario: Content is at the top
- **WHEN** the scroll content offset is at or above the top (≤ 0)
- **THEN** the header SHALL be visible regardless of previous scroll direction

### Requirement: Header state SHALL reset on tab switch
When the user switches tabs, the scroll tracking state SHALL reset to prevent stale offset deltas from causing incorrect header visibility changes.

#### Scenario: Switch from transcript (collapsed) to summary
- **WHEN** the header is collapsed in the transcript tab and the user taps the summary tab
- **THEN** the `lastScrollOffset` resets
- **AND** the header remains in its current visibility state until the user scrolls in the new tab

### Requirement: Scroll tracking SHALL ignore programmatic scrolls
The header collapse/expand logic SHALL only respond to user-initiated scroll interactions (`.interacting` or `.decelerating` phases), not programmatic scrolls (e.g., auto-scroll in transcript tab).

#### Scenario: Auto-scroll moves transcript during playback
- **WHEN** the transcript auto-scrolls to follow playback (programmatic scroll)
- **THEN** the header visibility does NOT change

### Requirement: Small scroll movements SHALL NOT toggle header
A dead zone of 5pt SHALL be applied to scroll direction detection to prevent jitter from small momentum bounces or imprecise touches.

#### Scenario: User makes a tiny scroll gesture
- **WHEN** the user scrolls less than 5pt in either direction
- **THEN** the header visibility does NOT change

### Requirement: Header collapse SHALL use clipped height animation
The collapse animation SHALL use `frame(height:)` set to 0 combined with `clipped()` and opacity transition. The header view identity SHALL be preserved (no conditional `if` removal) to maintain `@State` and `.task` lifecycle.

#### Scenario: Header collapses
- **WHEN** the header transitions from visible to collapsed
- **THEN** the header frame height animates to 0 and opacity animates to 0
- **AND** the header view remains in the hierarchy (not removed)
- **AND** no `.task` or `.onAppear` re-fires from the transition
