---
title: Live Editor
description: Inspect, navigate, select, and transform entities while a Scrapbot project is running.
---

Scrapbot's editor is part of the running project rather than a separate executable. It inspects the same live ECS world, systems, and renderer launched by `scrapbot run`.

## Open the editor

Start a visible WGPU run and press `Ctrl+Esc` to toggle the editor:

```sh
bin/scrapbot run examples/ecs-showcase --backend wgpu --window
```

Pass `--editor` to start with the editor already open:

```sh
bin/scrapbot run examples/ecs-showcase --backend wgpu --window --editor
```

The project keeps running when the editor opens or closes. Its world and project-authored UI fill all currently available center space without enforcing a fixed aspect ratio. Drag either vertical separator beside the viewport to resize the scene or inspector sidebar; the center viewport automatically fills the remainder and the panes keep their proportions as the window changes. During a native window resize, the simulation, surface, camera aspect, viewport, and editor layout continue updating throughout the drag.

## Navigate the scene view

The editor creates an editor-owned scene-camera entity whose initial view matches the project camera. Moving it does not change the project's camera.

| Input | Action |
| --- | --- |
| Hold right mouse button | Capture scene-camera input |
| Mouse | Look around while captured |
| `W` / `S` | Move forward / backward |
| `A` / `D` | Move left / right |
| `Space` | Move up |
| `Ctrl` | Move down |
| Release right mouse button | Return to normal pointer interaction |

Closing and reopening the editor preserves the scene-camera viewpoint for the current run.

## Browse and inspect entities

The scene sidebar lists scene-authored and runtime-spawned entities, including objects that do not come from the scene TOML. Scene-authored names use normal white text and runtime-spawned names use muted gray. Transient editor-origin entities—including the shell itself and scene camera—stay hidden from the browser and inspector.

The shell is itself built from transient ECS entities using the same layout, horizontal and vertical stack, draggable separator, scroll-area, panel, table, text, and button components available to project UI. Editor origin keeps those tool entities out of project data while letting the editor exercise the ordinary UI system.

Click an entry to select it, or click rendered geometry in the viewport. Viewport picking tests the rendered triangles and selects the nearest hit; clicking empty viewport space clears the selection. The browser scrolls to reveal a viewport-picked entity and automatically clears selection if that entity despawns.

The inspector reports the selected entity's name, identity, provenance, attached components, field names, and current values. Each component receives a titled panel, with its fields arranged as label/value rows in a two-column property table. Transform, camera, ambient/directional/point-light, and custom Vec3 values are editable; other values use the same selectable control in read-only mode. Vec3 rows provide separate X, Y, and Z inputs, while scalar rows use one full-width value input.

Click a value to focus it and select its complete contents. Typed text replaces the selection. Left/Right/Home/End move the cursor, Shift extends the selection, and Backspace/Delete edit it. Use Tab or Shift+Tab to traverse fields in visual order; Vec3 traversal proceeds through the red X, green Y, and blue Z controls independently. Enter commits and leaves the field, while Escape restores that axis or scalar value from when focus began.

Numeric controls update the running world as soon as their text becomes valid. Invalid numbers receive a red border and remain local to the control. Use Up/Down for the field's normal step, Shift+Up/Down for a 10× step, or Ctrl/Cmd+Up/Down for a 0.1× step. Drag an X/Y/Z label horizontally to scrub that axis. `Ctrl/Cmd+Z` undoes the last completed inspector gesture and `Ctrl/Cmd+Shift+Z` redoes it. A complete typing, stepping, or scrubbing gesture occupies one bounded runtime history entry.

Inspector edits are not persisted to the scene file yet. Closing the process discards both edits and undo history.

Entity membership and formatted values refresh every 200 ms, while selection changes refresh immediately. A periodic refresh leaves the actively edited text alone. The scene browser and inspector scroll independently with pixel-continuous targets, frame-time smoothing without line snapping, clipped partial content, and proportional scrollbars. Fractional trackpad deltas remain fractional.

## Transform an entity

Selecting an entity with a Transform adds a screen-legible transform gizmo. Choose a mode with the standard shortcuts:

| Shortcut | Mode | Handles |
| --- | --- | --- |
| `W` | Move | World-axis rails, plane walls, and a free-move center |
| `E` | Rotate | Axis rings |
| `R` | Scale | Axis rails, plane walls, and a uniform-scale center |

The axis colors remain consistent in every mode:

- Red moves along X.
- Green moves along Y.
- Blue moves along Z.

Hover an axis to affect one component, or hover an XY, XZ, or YZ wall to affect that pair. In move mode, the center handle translates freely in the camera plane. In scale mode, it changes all three scale components uniformly. Gizmo ownership and mode are represented by a transient editor component on the selected entity; the component is removed when selection changes or the editor closes. W/E/R mode shortcuts are ignored while the right mouse button is capturing fly-camera input.

Transform edits currently affect only the running world. Scene persistence, undo, snapping, local/world orientation switching, and multi-selection are not implemented yet.

## Capture the editor

For deterministic documentation or renderer checks, combine the editor with a headless framegrab:

```sh
bin/scrapbot run examples/ecs-showcase \
  --backend wgpu \
  --editor \
  --headless \
  --frames 20 \
  --framegrab /tmp/scrapbot-editor.png
```

Headless framegrabs do not provide pointer interaction. See [Rendering And Testing](/guides/rendering-testing/) for 1:1 region exports and visual verification guidance.
