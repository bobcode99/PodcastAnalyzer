## 1. Settings Scene Migration

- [x] 1.1 Add `Settings { MacSettingsView() }` scene to `PodcastAnalyzerApp.swift` inside `#if os(macOS)` (already existed)
- [x] 1.2 Add `scenePadding()` and `.frame(maxWidth: 560, minHeight: 300)` to `MacSettingsView`
- [x] 1.3 Search for any `openWindow(id: "settings")` or manual settings window calls in `MacContentView` toolbar and remove them (none found — was using `openSettings()`)
- [x] 1.4 Replace the toolbar gear button action with `SettingsLink` (or verify `Cmd+,` now works via the scene)
- [x] 1.5 Verify only one Settings window opens when triggered multiple times (`Settings` scene handles this automatically)

## 2. Settings Form Cleanup

- [x] 2.1 Audit each tab in `MacSettingsView` — ensure every tab root is `Form { ... }`, adding it where missing (all 7 tabs already use Form)
- [x] 2.2 Replace any `HStack { Text(...); Spacer(); Text(value) }` informational rows with `LabeledContent("Label") { Text(value) }` (storage sizes, app version, etc.)
- [x] 2.3 Build and confirm all settings controls align correctly in two-column Form layout

## 3. Sidebar Polish

- [x] 3.1 Add explicit `Section(header:)` labels to the "Browse", "Library", and "Search" groups in `MacContentView`, styled `.font(.caption).foregroundStyle(.secondary)`
- [x] 3.2 Update `navigationSplitViewColumnWidth` to `(min: 200, ideal: 240, max: 300)`
- [x] 3.3 Verify arrow-key navigation works in the sidebar list (no code change expected — `List(selection:)` with `.sidebar` handles it natively)

## 4. Mini Player — Liquid Glass

- [x] 4.1 In `MacContentView`, locate the mini player bar container that applies `.background(.ultraThinMaterial)`
- [x] 4.2 Wrap the background modifier in `if #available(macOS 26, *) { .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12)) } else { .background(.ultraThinMaterial, in: .rect(cornerRadius: 12)) }`
- [x] 4.3 Build on macOS 26 Simulator — confirm glass surface renders with blur and interactive highlight
- [x] 4.4 Build on macOS 14 Simulator — confirm `.ultraThinMaterial` fallback renders correctly

## 5. Expanded Player — Liquid Glass Controls

- [x] 5.1 In `MacMiniPlayerBar`, locate the `MacExpandedPlayerView` playback controls `HStack` (play/pause, skip back, skip forward)
- [x] 5.2 Wrap the controls `HStack` in `if #available(macOS 26, *) { GlassEffectContainer(spacing: 20) { ... } } else { ... }` keeping existing layout in the else branch
- [x] 5.3 Inside the `#available` branch, apply `.buttonStyle(.glass)` to each of the three control buttons
- [x] 5.4 Verify glass cluster merges visually on macOS 26 Simulator (buttons share a single glass surface at default spacing)
- [x] 5.5 Verify buttons function correctly (play/pause toggles, skip changes position) with the new button style

## 6. Verification

- [x] 6.1 Run full build for macOS target — zero errors and zero new warnings
- [x] 6.2 Run full build for iOS target — confirm no iOS regressions (all changes should be `#if os(macOS)` scoped)
- [ ] 6.3 Manually test: sidebar section headers visible, column width resizes correctly, keyboard nav works
- [ ] 6.4 Manually test: Settings window opens with `Cmd+,`, correct chrome, Form alignment looks right
- [ ] 6.5 Manually test on macOS 26 Simulator: mini player glass renders, expanded player glass cluster renders
- [ ] 6.6 Manually test on macOS 14 Simulator: mini player material fallback, expanded player standard buttons
