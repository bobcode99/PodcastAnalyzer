## ADDED Requirements

### Requirement: Sidebar displays labelled section headers
The sidebar SHALL render section group headers ("Browse", "Library", "Search") using `.font(.caption)` and `.foregroundStyle(.secondary)`, matching the macOS HIG sidebar label convention.

#### Scenario: Section headers are visible in sidebar
- **WHEN** the app launches on macOS
- **THEN** the sidebar shows "Browse", "Library", and "Search" as small, secondary-colored group headers above their respective items

---

### Requirement: Sidebar column width scales for wider displays
The `NavigationSplitView` sidebar column SHALL use `navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)` to accommodate wider macOS displays while keeping a usable minimum on 13" screens.

#### Scenario: Sidebar respects minimum width on small display
- **WHEN** the app window is at its minimum width on a 13" display
- **THEN** the sidebar column is at least 200 pt wide and content is not clipped

#### Scenario: Sidebar expands on wide display
- **WHEN** the app window is widened on a large external display
- **THEN** the sidebar column grows up to 300 pt and stops there regardless of window size

---

### Requirement: Sidebar selection is keyboard navigable
The sidebar list SHALL support arrow-key navigation so users can move between items without a mouse, consistent with standard macOS list behaviour.

#### Scenario: Arrow key moves selection in sidebar
- **WHEN** the sidebar has focus and the user presses the down arrow key
- **THEN** the selection moves to the next sidebar item and the detail view updates accordingly

---

### Requirement: Sidebar uses balanced split view style
The `NavigationSplitView` SHALL use `.navigationSplitViewStyle(.balanced)` so the detail column resizes proportionally when the window is resized.

#### Scenario: Detail column resizes with window
- **WHEN** the user resizes the main window
- **THEN** both sidebar and detail columns resize proportionally, maintaining readable content in both panels
