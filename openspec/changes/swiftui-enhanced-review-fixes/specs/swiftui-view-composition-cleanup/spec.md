## ADDED Requirements

### Requirement: ContentView SHALL remove dead showMiniPlayer code
The `showMiniPlayer` computed property (always returns `true`) and its `if` conditional SHALL be removed. `MiniPlayerBar` SHALL be rendered directly in `.tabViewBottomAccessory`.

#### Scenario: MiniPlayerBar rendered unconditionally
- **WHEN** `iOSContentView` body is evaluated
- **THEN** `MiniPlayerBar` is rendered directly without a conditional wrapper

### Requirement: SettingsView SHALL read version from Bundle
The hardcoded `"1.0.0"` version string in `SettingsView` SHALL be replaced with `Bundle.main.infoDictionary?["CFBundleShortVersionString"]` for automatic version tracking.

#### Scenario: Version displays correctly
- **WHEN** the Settings screen renders the version row
- **THEN** the displayed version matches the app's `CFBundleShortVersionString` from Info.plist

### Requirement: HomeView SHALL NOT force-unwrap URL strings
`URL(string: podcast.url)!` in `HomeView` SHALL be replaced with optional binding (`if let url = URL(string: podcast.url)`) to prevent crashes on malformed external data.

#### Scenario: Malformed URL does not crash
- **WHEN** `podcast.url` contains an invalid URL string
- **THEN** the Link/Share button is not rendered (graceful degradation), and no crash occurs

### Requirement: HomeView SHALL call ViewModel method for recommendation refresh
The refresh button in `HomeView.forYouSection` SHALL call a single `viewModel.refreshRecommendations()` method instead of directly mutating `viewModel.recommendations` and `viewModel.recommendedEpisodes` from the view.

#### Scenario: Refresh button calls single method
- **WHEN** the user taps the refresh button in the For You section
- **THEN** `viewModel.refreshRecommendations()` is called, which internally clears state and reloads
