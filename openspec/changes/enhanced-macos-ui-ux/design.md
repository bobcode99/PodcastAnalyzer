## Context

The macOS views (`MacContentView`, `MacMiniPlayerBar`, `MacSettingsView`) already use modern SwiftUI idioms — `NavigationSplitView`, `List(selection:)`, `.foregroundStyle()`, `.clipShape(.rect(cornerRadius:))` — so there is no deprecated-API cleanup debt.

The remaining gaps are:
1. The mini player bar uses `.ultraThinMaterial` (good fallback), but macOS 26 supports `glassEffect()` for a native Liquid Glass surface
2. The expanded player sheet uses plain colors and no material depth
3. `MacSettingsView` is a raw `TabView` rendered inside a `WindowGroup`; macOS expects a dedicated `Settings` scene with correct window chrome and sizing
4. The sidebar list items have adequate spacing but lack the subtle selection treatment and grouped section styling expected by macOS HIG

## Goals / Non-Goals

**Goals:**
- Adopt Liquid Glass on the mini player bar and expanded player sheet (macOS 26+), with `.ultraThinMaterial` fallback
- Migrate settings from `WindowGroup` + custom toolbar to the native `Settings` scene with `Form`-inside-`Tab`, `LabeledContent` rows, and `scenePadding()`
- Polish the sidebar: tighten section header styling, ensure keyboard-navigable selection, and set correct column widths for wider displays
- Use `GlassEffectContainer` for grouped controls in the expanded player sheet

**Non-Goals:**
- Redesigning any iOS views — all changes are `#if os(macOS)` scoped
- Adding new playback features or settings fields
- Adopting Liquid Glass on iOS (separate change when iOS 26 SDK ships)
- Changing navigation routing logic or the `MacSidebarItem` / `LibrarySubItem` enums

## Decisions

### D1 — Liquid Glass scoping: mini player + expanded player only

**Decision:** Apply `glassEffect()` to the mini player bar container and the expanded player sheet's control cluster. Do not apply it to the sidebar or content area.

**Rationale:** Apple's HIG places Liquid Glass on floating surfaces and transient UI (toolbars, sheets, overlays), not on full-content areas. The mini player bar floats over content — ideal fit. The sidebar is a structural panel, not a floating surface.

**Alternative considered:** Glass the sidebar panel. Rejected — macOS sidebar materials use `sidebar` list style and system-supplied background, not custom glass layers. Overriding breaks the expected column separator.

---

### D2 — GlassEffectContainer for expanded player controls

**Decision:** Wrap the play/skip button group in a `GlassEffectContainer` with each button using `.buttonStyle(.glass)`.

**Rationale:** Multiple adjacent glass views in a container share blending and morphing budget. Wrapping them avoids independent compositing layers and enables the "merge at proximity" visual behavior described in the Liquid Glass reference.

**Alternative considered:** Individual `.glassEffect()` on each button. Works but loses the merged glass treatment and costs more compositing.

---

### D3 — Availability gate: macOS 26 / fallback to `.ultraThinMaterial`

**Decision:** Wrap all `glassEffect()` calls in `if #available(macOS 26, *)` with an `else` branch using the existing `.ultraThinMaterial` background (already in place for the mini player).

**Rationale:** The app targets macOS 14+. Without a fallback, the mini player loses its blur background on macOS 14/15. The material fallback preserves the existing visual quality.

**Pattern:**
```swift
if #available(macOS 26, *) {
    content
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
} else {
    content
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
}
```

---

### D4 — Settings: `Settings` scene, not `WindowGroup`

**Decision:** Add a `Settings { MacSettingsView() }` scene to `PodcastAnalyzerApp.swift` (macOS only). Remove the current workaround of opening the settings window manually.

**Rationale:** The `Settings` scene provides the correct macOS Preferences window chrome (traffic-light controls, `Cmd+,` binding, toolbar-less title bar). A `WindowGroup` requires manual `OpenWindowAction` wiring and produces wrong window chrome.

**Impact:** `MacSettingsView` needs `scenePadding()` and a `frame(maxWidth: 560, minHeight: 300)` constraint added. Each tab's root should be a `Form` (already is in most tabs).

**Alternative considered:** Keep `WindowGroup` and use `windowStyle(.hiddenTitleBar)`. Rejected — still does not get correct system Preferences appearance or `Cmd+,` binding for free.

---

### D5 — Sidebar polish: section headers + column width

**Decision:** Use `Section` with explicit `header:` labels styled `.font(.caption).foregroundStyle(.secondary)` for "Browse", "Library", and "Search" groups. Set `navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)` to accommodate wider displays.

**Rationale:** Current sidebar uses plain section headers that inherit default list style. macOS HIG specifies smaller, uppercased section labels with more visual separation.

**Alternative considered:** `List` without sections, relying on dividers. Rejected — sections give keyboard focus grouping and match the expected Finder/Mail/Notes sidebar aesthetic.

---

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| `glassEffect()` macOS 26 API may shift before GM | Gate strictly with `#available`; `.ultraThinMaterial` fallback is production-quality |
| `Settings` scene migration may conflict with existing `openSettings()` call sites | Search for `openSettings` and `openWindow("settings")` usages before migrating; remove them |
| `GlassEffectContainer` spacing tuning is subjective | Start with `spacing: 20`; validate in macOS 26 Simulator before committing |
| Sidebar width increase (220→240 ideal) may push content too narrow on 13" MacBook Air | Test at 1280×800; keep `min: 200` as hard floor |

## Migration Plan

1. Add `Settings` scene to `PodcastAnalyzerApp.swift` behind `#if os(macOS)`
2. Add `scenePadding()` + `frame` constraint to `MacSettingsView`
3. Remove any manual settings window open calls
4. Wrap mini player bar container in `#available(macOS 26, *)` glass block; keep `.ultraThinMaterial` in `else`
5. Wrap expanded player control `HStack` in `GlassEffectContainer`; switch buttons to `.buttonStyle(.glass)`
6. Update sidebar `Section` headers; adjust column width ideal
7. Build on macOS 26 Simulator and validate glass rendering
8. Build on macOS 14 Simulator and validate material fallback

No data migration needed — changes are purely visual.

## Open Questions

- **Q1:** Should the mini player's progress bar also get a glass treatment (e.g., tinted fill), or keep the current `Color.accentColor` fill? Lean towards keeping accentColor — glass fill on a thin bar is visually noisy.
- **Q2:** Are there any `openWindow(id: "settings")` call sites outside `MacSettingsView`? (Check `MacContentView` toolbar button.) If so, replace with `SettingsLink` after migration.
