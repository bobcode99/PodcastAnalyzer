## 1. Scroll Tracking Infrastructure

- [ ] 1.1 Add `@State private var isHeaderVisible: Bool = true` and `@State private var lastScrollOffset: CGFloat = 0` to `EpisodeDetailView`
- [ ] 1.2 Create `View` extension `.trackScrollForHeaderCollapse(isHeaderVisible:lastOffset:)` that attaches `onScrollGeometryChange(for: CGFloat.self)` with 5pt dead zone direction detection and at-top auto-expand
- [ ] 1.3 Reset `lastScrollOffset` in `.onChange(of: selectedTab)` to prevent stale delta on tab switch

## 2. Header Collapse Animation

- [ ] 2.1 Wrap `EpisodeDetailHeaderView` in a container with `frame(height: isHeaderVisible ? nil : 0).clipped().opacity(isHeaderVisible ? 1 : 0)` and `.animation(.easeInOut(duration: 0.25), value: isHeaderVisible)`
- [ ] 2.2 Wrap the `Divider()` below the header in the same visibility logic so it collapses with the header

## 3. Apply Scroll Tracking to Each Tab

- [ ] 3.1 Apply `.trackScrollForHeaderCollapse` to the `ScrollView` in `summaryTab`
- [ ] 3.2 Apply `.trackScrollForHeaderCollapse` to the `ScrollView` in `transcriptContent` (alongside existing `onScrollPhaseChange`)
- [ ] 3.3 Pass `isHeaderVisible` binding to `EpisodeAIAnalysisView` and apply `.trackScrollForHeaderCollapse` to its internal `ScrollView`

## 4. Programmatic Scroll Filtering

- [ ] 4.1 Add `@State private var isUserScrolling: Bool = false` and track via `onScrollPhaseChange` (`.interacting`/`.decelerating` = true, `.idle` = false)
- [ ] 4.2 Guard the direction detection in the scroll tracking modifier to only update `isHeaderVisible` when user is actively scrolling

## 5. Build & Verify

- [ ] 5.1 Build for iOS Simulator and verify zero errors
- [ ] 5.2 Verify header collapses on scroll down and expands on scroll up across all 3 tabs
