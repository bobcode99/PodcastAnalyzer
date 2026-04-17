## ADDED Requirements

### Requirement: Settings uses the native macOS Settings scene
The app SHALL declare a `Settings { MacSettingsView() }` scene in `PodcastAnalyzerApp.swift`, compiled under `#if os(macOS)`. The existing settings entry point (toolbar gear button or menu item) SHALL use `SettingsLink` or the system `Cmd+,` binding rather than a manual `openWindow` call.

#### Scenario: Cmd+, opens settings window
- **WHEN** the user presses Cmd+, on macOS
- **THEN** the Settings window opens with the correct macOS Preferences chrome (traffic-light controls, no extra toolbar)

#### Scenario: Settings window has correct chrome
- **WHEN** the Settings window is open
- **THEN** it displays standard macOS window controls (close, minimise, zoom), a title bar showing the selected tab name, and no custom toolbar

---

### Requirement: Settings window has correct frame constraints
`MacSettingsView` SHALL apply `scenePadding()` and `.frame(maxWidth: 560, minHeight: 300)` so the window sizes correctly across all tab contents without growing unbounded.

#### Scenario: Settings window does not grow beyond max width
- **WHEN** the Settings window is open on a large display
- **THEN** the window width does not exceed 560 pt

#### Scenario: Settings window has minimum usable height
- **WHEN** the Settings window is open on any display
- **THEN** the window height is at least 300 pt and all tab content is scrollable or fits within the frame

---

### Requirement: Each settings tab root is a Form
Every tab in `MacSettingsView` SHALL use `Form { ... }` as its root container so controls are automatically aligned, labelled, and accessible per macOS HIG.

#### Scenario: Settings controls are aligned in a Form
- **WHEN** any settings tab is selected
- **THEN** labels and controls are aligned in two columns (label left, control right) using standard Form layout, without manual alignment hacks

---

### Requirement: Settings rows use LabeledContent for key-value display
Informational rows that display a label and a value (e.g., storage size, app version) SHALL use `LabeledContent("Label") { Text(value) }` instead of a manual `HStack` with `Spacer`.

#### Scenario: Storage row renders with correct alignment
- **WHEN** the Storage settings tab is selected
- **THEN** cache size and download size labels are left-aligned and their values are right-aligned, using native Form label styling

---

### Requirement: No duplicate settings window from WindowGroup
After migration to the `Settings` scene, there SHALL be no secondary `WindowGroup` or `openWindow` call that creates an additional settings window. All settings entry points SHALL route through the single `Settings` scene.

#### Scenario: Only one settings window can be open at a time
- **WHEN** the user triggers settings multiple times (Cmd+, or toolbar button)
- **THEN** only one Settings window exists; a second invocation brings the existing window to front rather than opening a new one
