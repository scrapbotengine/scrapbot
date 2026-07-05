---
title: Editor UI Overlay
description: Use Scrapbot's ECS-hosted debug overlay for FPS and system performance inspection.
---

Scrapbot's first editor UI is an engine-owned editor shell rendered with Scrapbot UI primitives.

It is hidden by default.

Show it at startup:

```sh
scrapbot run examples/spawn_swarm --editor
```

Toggle it during a headful run:

```txt
Ctrl+Tab
```

## What It Shows

The current shell uses:

- A top bar with FPS and playback controls.
- A left sidebar with active project system count, rolling average runtime over the profiling window, project Luau/native systems, engine-internal render systems, a live entity list, one retained system table, and visible scrollbars when lists overflow.
- A right sidebar reserved for selected-entity component inspection/editing.
- A bottom bar with compact runtime status.
- A game viewport that fills all remaining space between those editor regions.
- Draggable separators between the sidebars and the game viewport. They render as thin dividers, but use public `scrapbot.ui.hit_area` command buttons for wider hover/click targets, highlight when hovered or dragged, and switch to the platform east-west resize cursor.

System timings are captured at scheduler dispatch boundaries. Render system timings are captured from the render ECS schedule and displayed alongside project systems.

The visible table updates at a throttled cadence for readability while the underlying profiler keeps sampling every frame.

When editor chrome is visible, scene content and scene-authored UI render into the game viewport. The editor viewport is not forced to 16:9.

The shell body is generated as a retained `scrapbot.ui.hgroup`: left sidebar, left splitter, growable game viewport, right splitter, and right sidebar. Splitter drag state is engine-owned, but layout resolution still flows through the shared retained UI path.

The system inspector and selected-entity inspector both use retained sidebar content with consistent internal padding. The system list is one table panel with aligned text rows, not separate row panels. Component boxes fill the right sidebar width and keep labels and values aligned instead of drawing loose overlay text.

The left entity list shows all live entities in the current world. Scene-authored entities use the normal row text color. Runtime-spawned entities use muted row text so they are visually distinct before scene-saving and entity-editing workflows start relying on that distinction.

## Selected-Entity Inspector

Click a visible mesh in the game viewport to select its entity.

The right sidebar shows the selected entity name/id and one component box per attached component. Component fields use a reusable inspector row shape: label on the left, value input boxes on the right, and clipping inside the panel. Focus is shown on the input box itself, not as a full-row highlight.

Click a value input to focus it for editing. Focused inputs render a focus-ring border and caret.

Numeric inputs select their full value on focus, so typing immediately replaces the existing number. Other inputs can choose different focus behavior.

Typed inspector controls build on the same base row:

- `vec3` values render one input box per lane, each preceded by a colored lane label: red `X`, green `Y`, and blue `Z`.
- Color-like `vec3` values also add a live color swatch.
- Boolean values render as click-to-toggle controls.
- Known enum-like strings can render as selectors. `scrapbot.geometry.primitive.primitive` currently cycles through built-in primitive names.

The current editing slice supports primitive runtime text edits:

- Typed text inserts into the focused input.
- Left and Right move the caret; Shift+Left and Shift+Right extend the text selection.
- Home and End jump to the start or end of the input; Shift+Home and Shift+End extend the text selection.
- Ctrl+A selects all input text.
- Backspace and Delete remove text around the caret or remove the selected text.
- Enter commits the edited text into the live ECS field.
- Moving focus away also commits the edited text.
- Ctrl+Z undoes inspector field edits.
- Ctrl+Shift+Z or Ctrl+Y redoes inspector field edits.

Inspector edits mutate the live ECS world. They do not yet persist back to TOML scene files.

Editor chrome pointer ownership is resolved through the same retained UI routing used by project UI. Playback buttons, splitter hit areas, and the systems scroll view are generated as ordinary `scrapbot.ui.*` entities, then routed through the shared pointer route instead of private editor hit-test ladders.

## UI Is ECS Data

The editor shell is generated into the render ECS world, but the same retained UI primitives are available to projects:

- `scrapbot.ui.canvas`
- `scrapbot.ui.rect`
- `scrapbot.ui.border`
- `scrapbot.ui.text`
- `scrapbot.ui.button`
- `scrapbot.ui.hit_area`
- `scrapbot.ui.command`
- `scrapbot.ui.scroll_view`
- `scrapbot.ui.vgroup`
- `scrapbot.ui.hgroup`
- `scrapbot.ui.stack`
- `scrapbot.ui.layout.item`
- `scrapbot.ui.spacer`
- `scrapbot.ui.text_block`
- `scrapbot.ui.toggle`
- `scrapbot.ui.progress_bar`
- `scrapbot.ui.separator`

Text uses an embedded Spleen-derived bitmap font.

Editor controls are built from the same retained primitives as project UI. For example, playback button labels are text children of their button rects instead of separate absolute overlays.

## Scene-Authored UI Example

```toml
[[entities]]
id = "debug-panel"
name = "Debug Panel"

[entities.components."scrapbot.ui.canvas"]
design_size = [640.0, 480.0, 0.0]
scale_mode = "fit"

[entities.components."scrapbot.ui.rect"]
position = [12.0, 12.0, 0.0]
size = [320.0, 120.0, 0.0]
color = [0.059, 0.09, 0.165]
corner_radius = 6.0

[entities.components."scrapbot.ui.border"]
color = [0.148, 0.2, 0.282]
thickness = 1.0

[[entities]]
id = "debug-label"
name = "Debug Label"

[entities.components."scrapbot.ui.text"]
position = [28.0, 24.0, 0.0]
size = 1.5
color = [0.93, 0.969, 1.0]
value = "SCRAPBOT UI"
```

## Command Buttons

Buttons are ECS-shaped too:

```toml
[entities.components."scrapbot.ui.button"]

[entities.components."scrapbot.ui.command"]
command = "open.debug.panel"
```

When a command button is pressed, Scrapbot emits transient `scrapbot.ui.command_event` data into the live project world before update systems run. Editor chrome can consume editor-owned commands directly, but it still uses retained `scrapbot.ui.button` + `scrapbot.ui.command` routing for hit ownership.

Do not author `scrapbot.ui.command_event` in scene files. It is runtime-only transient data.

## Design Constraints

Editor/debug UI should stay legible. The built-in bitmap text should not be used below `1.0` scale for editor surfaces, and primary readouts should be larger.
