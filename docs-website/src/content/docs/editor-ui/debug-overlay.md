---
title: Editor UI Overlay
description: Use Machina's ECS-hosted debug overlay for FPS and system performance inspection.
---

Machina's first editor UI is an engine-owned editor shell rendered with Machina UI primitives.

It is hidden by default.

Show it at startup:

```sh
machina run examples/spawn_swarm --editor
```

Toggle it during a headful run:

```txt
Ctrl+Tab
```

## What It Shows

The current shell uses:

- A top bar with FPS and playback controls.
- A left sidebar with active project system count, rolling average runtime over the profiling window, project Luau/native systems, engine-internal render systems, one retained system table, and a visible scrollbar when the system list overflows.
- A right sidebar reserved for selected-entity component inspection/editing.
- A bottom bar with compact runtime status.
- A game viewport that fills all remaining space between those editor regions.
- Draggable separators between the sidebars and the game viewport. They render as thin dividers, but use public `machina.ui.hit_area` command buttons for wider hover/click targets, highlight when hovered or dragged, and switch to the platform east-west resize cursor.

System timings are captured at scheduler dispatch boundaries. Render system timings are captured from the render ECS schedule and displayed alongside project systems.

The visible table updates at a throttled cadence for readability while the underlying profiler keeps sampling every frame.

When editor chrome is visible, scene content and scene-authored UI render into the game viewport. The editor viewport is not forced to 16:9.

The shell body is generated as a retained `machina.ui.hgroup`: left sidebar, left splitter, growable game viewport, right splitter, and right sidebar. Splitter drag state is engine-owned, but layout resolution still flows through the shared retained UI path.

The system inspector and selected-entity inspector both use retained sidebar content with consistent internal padding. The system list is one table panel with aligned text rows, not separate row panels. Component boxes fill the right sidebar width and keep labels and values aligned instead of drawing loose overlay text.

Editor chrome pointer ownership is resolved through the same retained UI routing used by project UI. Playback buttons, splitter hit areas, and the systems scroll view are generated as ordinary `machina.ui.*` entities, then routed through the shared pointer route instead of private editor hit-test ladders.

## UI Is ECS Data

The editor shell is generated into the render ECS world, but the same retained UI primitives are available to projects:

- `machina.ui.canvas`
- `machina.ui.rect`
- `machina.ui.border`
- `machina.ui.text`
- `machina.ui.button`
- `machina.ui.hit_area`
- `machina.ui.command`
- `machina.ui.scroll_view`
- `machina.ui.vbox`
- `machina.ui.hgroup`
- `machina.ui.stack`
- `machina.ui.layout.item`
- `machina.ui.spacer`
- `machina.ui.text_block`
- `machina.ui.toggle`
- `machina.ui.progress_bar`
- `machina.ui.separator`

Text uses an embedded Spleen-derived bitmap font.

Editor controls are built from the same retained primitives as project UI. For example, playback button labels are text children of their button rects instead of separate absolute overlays.

## Scene-Authored UI Example

```toml
[[entities]]
id = "debug-panel"
name = "Debug Panel"

[entities.components."machina.ui.canvas"]
design_size = [640.0, 480.0, 0.0]
scale_mode = "fit"

[entities.components."machina.ui.rect"]
position = [12.0, 12.0, 0.0]
size = [320.0, 120.0, 0.0]
color = [0.059, 0.09, 0.165]
corner_radius = 6.0

[entities.components."machina.ui.border"]
color = [0.148, 0.2, 0.282]
thickness = 1.0

[[entities]]
id = "debug-label"
name = "Debug Label"

[entities.components."machina.ui.text"]
position = [28.0, 24.0, 0.0]
size = 1.5
color = [0.93, 0.969, 1.0]
value = "MACHINA UI"
```

## Command Buttons

Buttons are ECS-shaped too:

```toml
[entities.components."machina.ui.button"]

[entities.components."machina.ui.command"]
command = "open.debug.panel"
```

When a command button is pressed, Machina emits transient `machina.ui.command_event` data into the live project world before update systems run. Editor chrome can consume editor-owned commands directly, but it still uses retained `machina.ui.button` + `machina.ui.command` routing for hit ownership.

Do not author `machina.ui.command_event` in scene files. It is runtime-only transient data.

## Design Constraints

Editor/debug UI should stay legible. The built-in bitmap text should not be used below `1.0` scale for editor surfaces, and primary readouts should be larger.
