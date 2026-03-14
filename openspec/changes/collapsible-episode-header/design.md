## Context

`EpisodeDetailView` uses a fixed `VStack` layout: `EpisodeDetailHeaderView` (~140pt) → tab selector → tab content. Each tab owns its own `ScrollView`. The header is always visible, consuming valuable vertical space when reading transcripts or AI analysis. iOS deployment target is 26.0+, so `onScrollGeometryChange` is available.

The key constraint: each tab has its own independent `ScrollView`, so scroll tracking must work with whichever tab is active. The transcript tab already uses `onScrollPhaseChange` for auto-scroll disable.

## Goals / Non-Goals

**Goals:**
- Hide `EpisodeDetailHeaderView` when scrolling down in any tab
- Reveal header when scrolling up or reaching top
- Smooth animated transition (no jarring jumps)
- Keep tab selector always pinned/visible
- Work with all 3 tabs (summary, transcript, AI analysis)

**Non-Goals:**
- Collapsing the tab selector (stays fixed)
- Parallax or partial-collapse effects (binary show/hide)
- Changing header content or layout
- macOS-specific behavior (iOS only for now)

## Decisions

### 1. Use `onScrollGeometryChange` to track scroll offset

**Choice**: Track `contentOffset.y` via `onScrollGeometryChange(for: CGFloat.self)` on each tab's ScrollView.

**Rationale**: iOS 26+ guarantees availability. This is the modern, declarative approach. It fires on every scroll frame with zero layout overhead (no GeometryReader). Already proven in the codebase — `onScrollPhaseChange` is used in the transcript tab.

**Alternative considered**: `GeometryReader` with preference keys — heavier, causes extra layout passes, and is the legacy approach.

### 2. Track scroll direction via offset delta, not absolute position

**Choice**: Compare current offset to previous offset. If delta > threshold (5pt), set `scrollDirection = .down` (collapse). If delta < -threshold, set `scrollDirection = .up` (expand). Always expand when offset ≤ 0 (at top).

**Rationale**: Absolute offset thresholds feel wrong on long content. Direction-based tracking matches user intent (Safari, Slack, Twitter all use this pattern). The 5pt threshold prevents jitter from small momentum bounces.

### 3. Animate with `clipped()` + height transition, not offset

**Choice**: Wrap header in a container with `frame(height: isHeaderVisible ? nil : 0).clipped()` and `opacity` transition.

**Rationale**: Using `.offset(y:)` to slide the header leaves a gap or requires compensating the content frame. Setting height to 0 + clipped naturally collapses the space. Combined with `.animation(.easeInOut(duration: 0.25))`, this gives a smooth collapse/expand. The `opacity` transition (1 → 0 on collapse) prevents content from being visible during the clip animation.

**Alternative considered**: `.transition(.move)` with `if` conditional — causes view identity changes, breaks `@State` in header, and re-runs `.task`.

### 4. State lives in `EpisodeDetailView`, passed as binding or read by header

**Choice**: Add `@State private var isHeaderVisible: Bool = true` in `EpisodeDetailView`. Each tab's ScrollView attaches `onScrollGeometryChange` that updates `lastScrollOffset` and computes visibility.

**Rationale**: The parent view owns layout decisions. The header doesn't need to know about scrolling — it just renders. This keeps `EpisodeDetailHeaderView` unchanged.

### 5. Share scroll tracking via a helper modifier

**Choice**: Create a `View` extension `.trackScrollForHeaderCollapse(isHeaderVisible:lastOffset:)` that attaches `onScrollGeometryChange` with the direction logic. Apply it to each tab's ScrollView.

**Rationale**: Avoids duplicating the offset-tracking logic across 3 tabs. The transcript tab already has `onScrollPhaseChange` — the new modifier adds alongside it cleanly.

## Risks / Trade-offs

- **[Momentum bounce false triggers]** → 5pt dead zone threshold prevents small bounces from toggling. At-top check always reveals.
- **[Tab switch jank]** → Reset `lastScrollOffset` on tab change to prevent stale delta causing false collapse.
- **[Transcript auto-scroll conflict]** → Auto-scroll (programmatic) fires `onScrollGeometryChange` too. Filter: only update direction when `ScrollPhase == .interacting` or `.decelerating`, not `.idle`.
- **[EpisodeAIAnalysisView scroll ownership]** → AI tab creates its own ScrollView when `embedsOwnScroll: true`. The modifier must be applied inside `EpisodeAIAnalysisView` or the ScrollView must be lifted out. Decision: pass `isHeaderVisible` binding into `EpisodeAIAnalysisView` and apply modifier internally.
