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

Opening or closing the editor does not change the project's current playback state. Its world and project-authored UI fill all currently available center space without enforcing a fixed aspect ratio. Drag either vertical separator beside the viewport to resize the scene or inspector sidebar; the center viewport automatically fills the remainder and the panes keep their proportions as the window changes. Each complete sidebar also has a contrasting 10-pixel frame around its smooth scroll viewport, with a small gutter between separate tool sections, so the dock hierarchy stays legible and every section remains reachable in a short window. Systems, Scene, Inspector, and component sections share the same titled card, colors, disclosure arrow, and collapse behavior; click any title band to fold that section. Wheel input over a nested Systems, scene-browser, or inspector pane scrolls that pane; wheel input over sidebar padding or non-scrollable chrome scrolls the complete sidebar. During a native window resize, the simulation, surface, camera aspect, viewport, and editor layout continue updating throughout the drag.

The top bar contains the Scrapbot title and the project simulation controls. The bottom bar reports only the current simulation state.

| Control | Behavior |
| --- | --- |
| Play | Run project systems with normal frame deltas. |
| Pause | Freeze project systems and world time at their current state. Rendering, editor UI, scene-camera navigation, picking, and gizmos remain responsive. |
| Stop | Restore the in-memory authoring state captured when playback began, discard playback mutations and runtime spawns, retain loaded Luau and Odin systems, and remain stopped. |
| Step | While pausing normal playback, run one fixed 1/60-second project update. |
| Save | While stopped, write dirty value and structural scene-authoring changes back to the scene TOML. |

Pause preserves the current runtime world so Play can resume it. Play and Step capture the current stopped authoring state in memory before simulation advances. Stop returns to that captured state without reloading code or the scene file: unsaved authored entities, dirty state, selection, and undo history survive, while playback mutations and runtime-spawned entities disappear. Stopped is authoring mode, and the bottom bar reports `STOPPED / UNSAVED` until Save—or `Ctrl/Cmd+S`—writes those changes explicitly.

Save matches authored entities by stable UUID, not by name. Completed authoring transactions identify candidate entities, then Save compares them with the parsed authored baseline. Value-only edits patch semantic differences. Structural saves rewrite only dirty entity blocks, omit deleted UUIDs, and append created or explicitly kept runtime UUIDs in action order; every clean entity block remains byte-for-byte intact before the file is atomically replaced. Unpromoted runtime and editor-owned entities are never written. Changes made while running or paused remain disposable runtime state.

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

The top-left systems panel is a selectable list of every system participating in the frame. Engine-owned rows cover the editor camera, transform gizmo, ECS UI, picking, render preparation, and render submission; registered project-Odin and Luau systems follow them. Selecting a system has no action yet, but the selection is retained for future debugger details. Its right-aligned timing column shows rolling average callback time per frame in milliseconds with three decimal places, published every five successful frames from the latest 50 successful frames. A colored dot identifies provenance: mint for Engine, blue for Project Odin, and amber for Luau. The matching thin bar has no background track; it is anchored to the panel's right edge and grows leftward across the complete row on an absolute scale where 10 ms fills the available width. Drag the horizontal separator below the panel to trade height between the profiler and the complete Scene pane. Engine systems use `scrapbot.*` names, project-Odin systems use their registered names, and Luau systems use the optional `name` from their system options with an ordinal fallback when unnamed. Render submission reports CPU callback time through queue submission, not asynchronous GPU execution time.

Project-system values measure callback execution and exclude scheduler setup and deferred-command application. Engine rows measure their named CPU frame phases; `scrapbot.render` ends at queue submission and therefore does not include asynchronous GPU execution. Values above 10 ms clamp to a full-width bar.

The Scene panel contains a flush, selectable, scrollable entity list plus a compact stopped-mode authoring toolbar. `+` creates a scene entity with a Transform, `DUP` duplicates the selected scene or runtime entity into a new authored UUID, `DEL` removes the selected authored entity, and `KEEP` explicitly promotes a selected runtime entity into scene data. It includes runtime-spawned objects that do not come from the scene TOML. Scene-authored names use normal white text and runtime-spawned names use muted gray. Transient editor-origin entities—including the shell itself and scene camera—stay hidden from the browser and inspector.

The shell is itself built from transient ECS entities using the same responsive layout, horizontal and vertical stack, draggable separator, scroll-area, selectable-list, progress, panel, table, text, button, input, and checkbox components available to project UI. Editor origin keeps those tool entities out of project data while letting the editor exercise the ordinary UI system. Sidebar and inspector sizing uses the public per-axis fill, minimum-size, and fit-to-content policies rather than editor-specific post-layout repair code. See [ECS UI](/guides/ecs-ui/) for the project-facing component model.

Click an entry to select it, or click rendered geometry in the viewport. Viewport picking tests the rendered triangles and selects the nearest hit; clicking empty viewport space clears the selection. The browser scrolls to reveal a viewport-picked entity and automatically clears selection if that entity despawns.

The inspector reports the selected entity's editable name, identity, provenance, attached components, field names, and current values. Each component receives a titled panel, with its fields arranged as label/value rows in an edge-to-edge two-column property table. The initial split gives labels one third and values two thirds of the width; drag the column boundary to resize it. Spacing belongs to the individual cells, so controls stay comfortably inset without shrinking the table itself. Click a panel title or its SDF disclosure arrow to collapse or expand that component. Transform, camera, ambient/directional/point-light, and custom Vec3 values are editable; other values use the same selectable control in read-only mode. Vec3 rows provide separate X, Y, and Z inputs, while scalar rows use one full-width value input.

While stopped, click **Add Component** to open a floating, independently scrollable component picker. It is populated from the live component registry rather than a hardcoded editor list: single-token project components appear under **Project**, while dotted engine and library names are nested by namespace token. Atlas-safe `[ ]` and `[x]` labels distinguish available and attached components; choosing one toggles its membership as an undoable authoring transaction. Click outside the menu, press Escape, or choose a component to close it.

Click a value to focus it and select its complete contents. Typed text replaces the selection. Left/Right/Home/End move the cursor, Shift extends the selection, and Backspace/Delete edit it. Use Tab or Shift+Tab to traverse fields in visual order; Vec3 traversal proceeds through the red X, green Y, and blue Z controls independently. Enter commits and leaves the field, while Escape restores that axis or scalar value from when focus began.

Numeric controls update the active world as soon as their text becomes valid. Invalid numbers receive a red border and remain local to the control. Use Up/Down for the field's normal step, Shift+Up/Down for a 10× step, or Ctrl/Cmd+Up/Down for a 0.1× step. Drag an X/Y/Z label horizontally to scrub that axis. `Ctrl/Cmd+Z` undoes the last completed authoring transaction and `Ctrl/Cmd+Shift+Z` redoes it. Complete typing, stepping, scrubbing, boolean changes, transform-gizmo drags, renames, entity operations, promotions, and component membership changes each occupy one bounded history entry. While stopped, authored changes can be persisted with Save; edits to unpromoted runtime entities and all edits made while running or paused are session-only.

Entity membership and formatted values refresh every 200 ms, while selection changes refresh immediately. A periodic refresh leaves the actively edited text alone. The scene browser and inspector scroll independently with pixel-continuous targets, frame-time smoothing without line snapping, clipped partial content, and proportional scrollbars. Fractional trackpad deltas remain fractional.

## Transform an entity

Selecting an entity with a Transform adds a screen-legible transform gizmo. Choose a mode with the standard shortcuts:

| Shortcut | Mode | Handles |
| --- | --- | --- |
| `W` | Move | Axis rails, plane walls, and a free-move center |
| `E` | Rotate | Axis rings |
| `R` | Scale | Axis rails, plane walls, and a uniform-scale center |

The axis colors remain consistent in every mode:

- Red moves along X.
- Green moves along Y.
- Blue moves along Z.

Hover an axis to affect one component, or hover an XY, XZ, or YZ wall to affect that pair. In move mode, the center handle translates freely in the camera plane. In scale mode, it changes all three scale components uniformly. Gizmo ownership and mode are represented by a transient editor component on the selected entity; the component is removed when selection changes or the editor closes. W/E/R mode shortcuts are ignored while the right mouse button is capturing fly-camera input.

Use the `WORLD` and `LOCAL` controls in the viewport's upper-left corner to choose the gizmo orientation. World keeps the rails, walls, and rings aligned to the scene axes. Local rotates them with the selected entity: movement follows its rotated axes, rotation composes around those axes, and scale continues to edit the corresponding local X, Y, or Z scale. The selected space is stored on the transient gizmo component. A drag freezes its basis when it begins, so the handle stays stable even while the transform changes.

While stopped, transform edits to scene-authored entities participate in explicit Save. During running or paused playback they affect only runtime state. A complete gizmo drag is one undoable transaction, including multi-axis handles. Snapping and multi-selection are not implemented yet.

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

Headless runs normally have no platform pointer. Add a semantic `--ui-script` and `--ui-dump` to reproduce editor clicks, scrolling, typing, hover, focus, and assertions without OS automation; a `capture` action can crop the final 1:1 PNG to its resolved target. See [Rendering And Testing](/guides/rendering-testing/#semantic-ui-diagnostics).
