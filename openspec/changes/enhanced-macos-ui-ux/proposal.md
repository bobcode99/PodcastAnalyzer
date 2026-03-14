## Why

The macOS app shares most of its UI logic with iOS but doesn't take advantage of macOS-native patterns — the sidebar navigation is functional but visually flat, the mini player lacks depth, and the Settings window uses a plain `TabView` without proper macOS chrome. With macOS 26 / iOS 26 introducing Liquid Glass and modern SwiftUI APIs maturing, now is the right time to bring the macOS experience up to a native, polished standard.

## What Changes

- **Sidebar** — Adopt `List` selection with proper `sidebarAdaptableTabView` or `NavigationSplitView` styling; add section headers, hover highlights, and keyboard navigation support
- **MiniPlayer bar** — Apply Liquid Glass surface effect to the floating player bar; improve progress scrubber interaction (expand on hover)
- **MacExpandedPlayer sheet** — Use `GlassEffectContainer` for controls; replace custom blurs with `.glassEffect()` materials
- **Settings window** — Migrate to the `Settings` scene with proper `Form`-inside-`Tab` layout, correct window sizing, and `scenePadding()`; use `LabeledContent` for aligned rows
- **Typography & spacing** — Replace deprecated `.foregroundColor()` with `.foregroundStyle()`; replace `.cornerRadius()` with `.clipShape(.rect(cornerRadius:))`; tighten row padding to match macOS HIG
- **Toolbar** — Add standard macOS toolbar items (search field, settings link via `SettingsLink`) using `.toolbar` API rather than custom overlays
- **Liquid Glass adoption** — Gate with `#available(macOS 26, *)` and provide `.ultraThinMaterial` fallback for earlier OS versions

## Capabilities

### New Capabilities
- `macos-sidebar-navigation`: Polished `NavigationSplitView` sidebar with section headers, selection state, keyboard nav, and proper column widths
- `macos-player-glass`: Liquid Glass surface for the floating mini player bar and expanded player sheet
- `macos-settings-window`: Properly structured macOS Settings scene with `Form`-based tabs, correct window frame, and `LabeledContent` rows

### Modified Capabilities
<!-- No existing specs to delta against — all capabilities are new -->

## Impact

- **Files**: `MacContentView.swift`, `MacMiniPlayerBar.swift`, `MacSettingsView.swift`
- **Availability gate**: `#available(macOS 26, *)` required for Liquid Glass; `.ultraThinMaterial` fallback for macOS 14/15
- **Dependencies**: No new packages — Liquid Glass is a native SwiftUI API in macOS 26 SDK
- **iOS**: No impact — changes are `#if os(macOS)` scoped
