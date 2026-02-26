## ADDED Requirements

### Requirement: Mini player bar uses Liquid Glass surface on macOS 26+
On macOS 26 and later, the floating mini player bar container SHALL apply `.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))` instead of the `.ultraThinMaterial` background, giving the bar a native Liquid Glass appearance.

#### Scenario: Glass effect applied on macOS 26
- **WHEN** the app runs on macOS 26 or later and a podcast episode is playing
- **THEN** the mini player bar renders with a Liquid Glass surface that blurs and tints the content behind it

#### Scenario: Material fallback on macOS 14 and 15
- **WHEN** the app runs on macOS 14 or macOS 15
- **THEN** the mini player bar renders with `.ultraThinMaterial` background and rounded corners, visually equivalent to the pre-change behaviour

---

### Requirement: Mini player bar is interactive glass
The Liquid Glass effect on the mini player bar SHALL include `.interactive()` so the surface responds to pointer hover and click, consistent with other macOS floating toolbars.

#### Scenario: Glass surface responds to pointer hover
- **WHEN** the user moves the pointer over the mini player bar on macOS 26+
- **THEN** the glass surface shows a visible interactive highlight reaction

---

### Requirement: Expanded player controls use GlassEffectContainer
The playback control buttons (play/pause, skip back, skip forward) in the expanded player sheet SHALL be wrapped in a `GlassEffectContainer` and each button SHALL use `.buttonStyle(.glass)`, allowing the adjacent glass surfaces to merge visually.

#### Scenario: Control buttons render as merged glass group
- **WHEN** the expanded player sheet is open on macOS 26+
- **THEN** the three playback controls appear as a single cohesive Liquid Glass cluster, with effects merging between adjacent buttons

#### Scenario: Control buttons fall back on macOS 14 and 15
- **WHEN** the expanded player sheet is open on macOS 14 or 15
- **THEN** buttons render with their standard SwiftUI style (no glass), maintaining full functionality

---

### Requirement: Liquid Glass is scoped to floating player surfaces only
The sidebar, content area, and all non-floating views SHALL NOT apply `glassEffect()`. Glass treatment is restricted to the mini player bar and expanded player sheet.

#### Scenario: Sidebar has no glass treatment
- **WHEN** the app is running on macOS 26+
- **THEN** the sidebar list uses the standard system sidebar background, not a glass surface

---

### Requirement: Availability gate uses #available(macOS 26, *)
Every `glassEffect()` call site SHALL be wrapped in `if #available(macOS 26, *) { ... } else { ... }`. There SHALL be no unconditional `glassEffect()` calls in the macOS target.

#### Scenario: Build succeeds targeting macOS 14 deployment target
- **WHEN** the project is built with a macOS 14 minimum deployment target
- **THEN** the build succeeds with zero compiler errors related to glass APIs
