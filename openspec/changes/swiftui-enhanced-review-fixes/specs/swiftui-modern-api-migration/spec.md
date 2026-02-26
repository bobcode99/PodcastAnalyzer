## ADDED Requirements

### Requirement: All ScrollViews SHALL use .scrollIndicators(.hidden) instead of showsIndicators parameter
`ScrollView(.horizontal, showsIndicators: false)` occurrences SHALL be replaced with `ScrollView(.horizontal) { }.scrollIndicators(.hidden)` in `ExpandedPlayerView`, `HomeView`, `EpisodeListView`, and `EpisodeAIAnalysisView`.

#### Scenario: Horizontal scroll views hide indicators via modifier
- **WHEN** a horizontal `ScrollView` is rendered in any of the affected views
- **THEN** scroll indicators are hidden via the `.scrollIndicators(.hidden)` modifier, not the deprecated initializer parameter

### Requirement: withAnimation SHALL use explicit animation value
`withAnimation { }` in `EpisodeListView` (description expand toggle) SHALL be replaced with `withAnimation(.easeInOut(duration: 0.2)) { }` to avoid the deprecated parameterless overload.

#### Scenario: Description expand animates with explicit curve
- **WHEN** the user taps the expand/collapse button for the podcast description
- **THEN** the animation uses an explicit `.easeInOut(duration: 0.2)` curve

### Requirement: Icon-only buttons SHALL have accessibility labels
All icon-only `Button` and `Menu` views SHALL have an `.accessibilityLabel` modifier. This applies to:
- MiniPlayerBar play/pause button
- EpisodeDetailView toolbar translate button and ellipsis menu
- EpisodeDetailView transcript header auto-scroll, settings, and options buttons
- EpisodeRowView ellipsis menu

#### Scenario: VoiceOver announces play/pause button
- **WHEN** VoiceOver focus lands on the MiniPlayerBar play/pause button
- **THEN** VoiceOver announces "Pause" or "Play" based on current state

#### Scenario: VoiceOver announces translate button
- **WHEN** VoiceOver focus lands on the translate toolbar button in EpisodeDetailView
- **THEN** VoiceOver announces "Translate"

#### Scenario: VoiceOver announces episode row menu
- **WHEN** VoiceOver focus lands on the ellipsis menu in EpisodeRowView
- **THEN** VoiceOver announces "More options"
