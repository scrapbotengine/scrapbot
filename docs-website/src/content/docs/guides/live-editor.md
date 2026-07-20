---
title: Live Editor
description: Inspect, navigate, select, and transform entities while a Scrapbot project is running.
---

Scrapbot's editor is part of the running project rather than a separate executable. It inspects the same live ECS world, systems, and renderer launched by `scrapbot run`.

## Open the editor

Start a visible WGPU run and press `Cmd+E` on macOS or `Ctrl+E` elsewhere to toggle the editor:

```sh
bin/scrapbot run examples/ecs-showcase
```

Pass `--editor` to start with the editor already open:

```sh
bin/scrapbot run examples/ecs-showcase --editor
```

Opening the editor preserves the current playback state. Closing it always starts or resumes normal playback, including when the project was paused or stopped. The project world and project-authored UI fill all currently available center space without enforcing a fixed aspect ratio. Drag either vertical separator beside the viewport to resize the scene or inspector sidebar; the center viewport automatically fills the remainder and the panes keep their proportions as the window changes. Each complete sidebar also has a contrasting 10-pixel frame around its smooth scroll viewport, with a small gutter between separate tool sections, so the dock hierarchy stays legible and every section remains reachable in a short window. Systems, Scene, Inspector, and component sections share the same titled card, colors, disclosure arrow, and collapse behavior; click any title band to fold that section. Wheel input over a nested Systems, scene-browser, or inspector pane scrolls that pane; wheel input over sidebar padding or non-scrollable chrome scrolls the complete sidebar. During a native window resize, the simulation, surface, camera aspect, viewport, and editor layout continue updating throughout the drag.

The top bar contains the Scrapbot title and project simulation controls. The bottom bar reports simulation and persistence status. Running and paused playback display `PLAY MODE / <STATE> / CHANGES ARE TEMPORARY`; amber top and status bars plus an amber viewport frame keep that warning visible across the workspace. Pausing preserves the play-mode treatment because edits remain disposable. Stop returns the editor to neutral authoring chrome.

| Control | Behavior |
| --- | --- |
| Play | Run project systems with normal frame deltas. |
| Pause | Toggle between running and paused playback. While paused, rendering, editor UI, scene-camera navigation, picking, and gizmos remain responsive. |
| Stop | Restore the in-memory authoring state captured when playback began, discard playback mutations and runtime spawns, retain loaded Luau and Odin systems, and remain stopped. |
| Step | While pausing normal playback, run one fixed 1/60-second project update. |
| Undo / Redo | While stopped, traverse complete authoring transactions. The controls dim when no matching history step is available. |
| Save | While stopped, write dirty scene authoring and inline project-resource changes to their source files. |
| Revert | While stopped and dirty, discard unsaved authoring and reload project resources and scene entities from disk without reloading Luau, Odin, or systems. Revert clears authoring history. |

The transport also has command shortcuts while the editor is open:

| Shortcut | Behavior |
| --- | --- |
| `Cmd/Ctrl+E` | Toggle editor visibility. Opening preserves playback state; closing starts or resumes playback. |
| `Cmd/Ctrl+R` | Play when stopped, resume when paused, and stop when running. |
| `Cmd/Ctrl+T` | Pause when running; advance one fixed step when paused or stopped. |

Opening the shell never changes transport state. Leaving it always enters running playback, so a paused project resumes and a stopped authoring world captures its in-memory playback baseline before project systems advance. Use the explicit Play, Pause, Stop, and Step controls or their shortcuts while editing.

Transport shortcuts are ignored while the scene camera captures the pointer or a project-owned input has focus. Command-modified E and R do not change the transform-gizmo mode.

Pause preserves the current runtime world so Play can resume it. Play and Step capture the current stopped authoring state in memory before simulation advances. Stop returns to that captured state without reloading code or the scene file: unsaved authored entities, dirty state, selection, and undo history survive, while playback mutations and runtime-spawned entities disappear. Stopped is authoring mode. The bottom bar retains `/ UNSAVED` beside the current playback state until Save—or `Ctrl/Cmd+S`—writes those changes explicitly, Undo/Redo returns to the clean history position, or Revert discards them.

Project resources participate in the same authoring state. The left sidebar's Resources panel is a selectable ECS list with Create, Duplicate, and Delete controls. Selecting a material opens an inline resource inspector where Name and Path rename or move it, material channels use the ordinary numeric controls, and the References panel reports consumers. Referenced resources cannot be deleted; Find Usage selects their first live consumer. Resource lifecycle operations are stopped-mode structural transactions, so Undo/Redo and Play/Stop preserve them in memory. Revert discards them.

Save addresses entities and resources by stable UUID, prepares every dirty scene and resource output in memory, validates the generated TOML and scene resource references, and then commits file creation, replacement, moves, and deletion together as one recoverable project transaction. A failure before commit restores every previous file and removes incomplete new destinations; an interrupted committed Save finishes cleanup when the project next loads. Resource names and paths can change without changing scene identity.

Save matches authored entities by stable UUID, not by name. Completed authoring transactions identify candidate entities, then Save compares each unique candidate with the parsed authored baseline through constant-time UUID indexes. Value-only edits patch semantic differences and preserve comments and surrounding formatting even when the same Save contains structural changes. Structural saves rewrite only their own dirty entity blocks, omit deleted UUIDs, and append created or explicitly kept runtime UUIDs in action order. Scrapbot validates the complete generated scene before atomically replacing the source file. A successful Save marks the current history position as clean, so undoing away from it reports unsaved changes and redoing back clears them. Unpromoted runtime and editor-owned entities are never written. Changes made while running or paused remain disposable runtime state.

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

While the editor is open, project and runtime camera entities appear in the scene view as blue, world-scaled wireframe camera bodies. The body naturally becomes smaller on screen as the scene viewpoint moves away. Selecting a camera highlights its visualizer in amber and reveals a bounded projection-frustum preview derived from its FOV, near clip plane, current viewport aspect, and resolved world transform. The preview stops after five world units (or at a shorter far clip plane), so an ordinary long far plane cannot flood the scene view. Click any visible body or selected frustum stroke to select its owning camera entity; camera visualizers take priority over ordinary triangle picking. These visualizers are editor-only: the separate fly camera is never shown as project content, and closing the editor removes them.

## Browse and inspect entities

The top-left systems panel is a selectable list of every system participating in the frame. Engine-owned rows cover the editor camera, transform gizmo, ECS UI, picking, render preparation, and granular render phases; registered project-Odin and Luau systems follow them. Selecting a system has no action yet, but the selection is retained for future debugger details. Its right-aligned timing column shows rolling average callback time per frame in milliseconds with three decimal places, published every five successful frames from the latest 50 successful frames. A colored dot identifies provenance: mint for Engine, blue for Project Odin, and amber for Luau. The matching thin bar has no background track; it is anchored to the panel's right edge and grows leftward across the complete row on an absolute scale where 10 ms fills the available width. Drag the horizontal separator below the panel to trade height between the profiler and the complete Scene pane. Engine systems use `scrapbot.*` names, project-Odin systems use their registered names, and Luau systems use the optional `name` from their system options with an ordinal fallback when unnamed. Render rows report CPU callback and API time, not asynchronous GPU execution time.

Project-system values measure callback execution and exclude scheduler setup and deferred-command application. Engine rows measure their named CPU frame phases. `scrapbot.render.cull`, `.shadow`, `.world`, `.post`, `.ui`, `.finish`, `.submit`, and `.present` expose where CPU-side renderer time is spent; none measures asynchronous GPU execution. Values above 10 ms clamp to a full-width bar.

The Scene panel contains a flush, selectable, scrollable hierarchy plus a compact stopped-mode authoring toolbar. It is an ordinary public tree-enabled `ui_list`: pooled direct rows carry semantic parent, sibling order, and collapse state on `ui_layout`, while the shared UI system owns flattening, indentation, collapsed-branch filtering, and subtree placement. Transform parent UUIDs form the scene meaning of that tree; SDF chevrons expand and collapse branches. Drop on the middle of another row to make it the new parent, on a row's top or bottom edge to adopt that row's parent and insert before or after it, or in empty Scene-list space to make the entity a root. The reusable list/tree gesture paints a lander line for insertion and tints a row for reparenting. Parent and order changes happen atomically, preserve the current world pose, and reject cycles; a transformless source receives an identity Transform, while a transformless parent contributes an identity spatial basis. While stopped, scene entities may use only scene parents and one completed drag is one undoable, saveable structural transaction. Save emits TOML entity blocks in the authored order without moving live ECS storage handles. During playback, hierarchy and order edits are disposable. An authored parent with children must currently be emptied before it can be deleted.

`+` creates a scene entity with a Transform, `DUP` duplicates the selected scene or runtime entity into a new authored UUID, `DEL` removes the selected authored entity, and `KEEP` explicitly promotes a selected runtime entity into scene data. The hierarchy includes runtime-spawned objects that do not come from the scene TOML. Scene-authored names use normal white text and runtime-spawned names use muted gray. Transient editor-origin entities—including the shell itself and scene camera—stay hidden from the browser and inspector.

The shell is itself built from transient ECS entities using the same responsive layout, horizontal and vertical stack, draggable separator, scroll-area, selectable-list, progress, panel, table, text, button, input, and checkbox components available to project UI. Editor origin keeps those tool entities out of project data while letting the editor exercise the ordinary UI system. Sidebar and inspector sizing uses the public per-axis fill, minimum-size, and fit-to-content policies rather than editor-specific post-layout repair code. See [ECS UI](/guides/ecs-ui/) for the project-facing component model.

Click an entry to select it, or click rendered geometry in the viewport. Viewport picking tests the rendered triangles and selects the nearest hit; clicking empty viewport space clears the selection. The browser scrolls to reveal a viewport-picked entity and automatically clears selection if that entity despawns.

The inspector reports the selected entity's editable name, identity, provenance, attached components, field names, and current values. Each component receives a titled panel, with its fields arranged as label/value rows in an edge-to-edge two-column property table. The initial split gives labels one third and values two thirds of the width; drag the column boundary to resize it. Spacing belongs to the individual cells, so controls stay comfortably inset without shrinking the table itself. Click a panel title or its SDF disclosure arrow to collapse or expand that component. Components registered as advanced remain visible and inspectable but start collapsed; expanding one remains a retained editor choice while inspecting that component. Click the trailing cross to remove an authorable component.

An authored Material panel shows its resource name and UUID, editable base color and HDR emissive channels, and a stopped-mode selector populated from known material resources. Material numbers use the same typing, stepping, and whole-control scrubbing as every numeric input. While running or paused they preview immediately as disposable runtime changes; Stop restores the captured authoring resource values. While stopped they become undoable authoring transactions. Resource-reference switching remains stopped-mode authoring. Resource data stays registry-owned outside ECS; the selector and controls themselves use the public ECS UI system.

Every truthfully registered Bool, String, Number, Vec2, Vec3, Vec4, and Color field is editable through the same reusable checkbox and input controls available to project UI. Vector rows provide one input per axis, while scalar and string rows use one full-width input. UUID references and text alignment are validated text for now. Color fields are semantically distinct, default to bounded RGBA channel controls, and are ready for a future reusable color picker. Engine-derived state and opaque render handles remain read-only until they gain an honest public editing contract. A complete stopped-mode reflected edit becomes one authoring transaction, so Undo, Redo, Save, and Revert work without field-specific editor history code.

Click **Add Component** to open a floating, independently scrollable component picker. It is populated from the live component registry rather than a hardcoded editor list: single-token project components appear under **Project**, while dotted engine and library names are nested by namespace token. The menu lists only components not already attached to the selected entity. Remove an authorable component with the cross in its panel title. While stopped, scene-entity membership changes are undoable authoring transactions. While running or paused, changes apply immediately to scene and runtime entities for inspection and experimentation, remain outside Undo and Save, and disappear on Stop. Engine-defined components such as Transform, Camera, lights, render data, and UI remain mutable because the entity owns their membership. Engine-managed derived state such as Render Instance and editor gizmo ownership remains visible in the inspector but intentionally has no removal action. Click outside the menu, press Escape, or choose a component to close it.

Click a value to focus it and select its complete contents. Typed text replaces the selection. Left/Right/Home/End move the cursor, Shift extends the selection, and Backspace/Delete edit it. Numeric typing and keyboard stepping remain staged without changing the component until Enter commits and leaves the field. Escape, clicking elsewhere, or using Tab/Shift+Tab restores the value captured when focus began; Tab still moves through fields in visual order, including independent X/Y/Z/W controls. Pointer scrubbing remains a live preview and commits once on release.

Numeric typing and keyboard stepping remain local to the focused control until Enter commits the valid value; invalid numbers receive a red border and never reach the active world. Use Up/Down for the field's normal step, Shift+Up/Down for a 10× step, or Ctrl/Cmd+Up/Down for a 0.1× step. Built-in editor numbers and custom fields whose registry metadata sets `draggable` can be scrubbed horizontally anywhere across the control without requiring an axis badge; scrubbing previews live and commits once on release. Use the top-bar controls or `Ctrl/Cmd+Z` and `Ctrl/Cmd+Shift+Z` to undo and redo. Complete typing, stepping, scrubbing, boolean changes, transform-gizmo drags, renames, entity operations, promotions, and component membership changes each occupy one bounded history entry; dependent boolean fields changed by one control remain atomic. While stopped, authored changes can be persisted with Save; edits to unpromoted runtime entities and all edits made while running or paused are session-only and do not enter authoring history.

Entity membership, resource-browser values, and the selected entity's running component values refresh every 200 ms, while selection and stopped-authoring changes refresh immediately. A periodic refresh leaves the actively edited text alone. The scene browser and inspector scroll independently with pixel-continuous targets, frame-time smoothing without line snapping, clipped partial content, and proportional scrollbars. Fractional trackpad deltas remain fractional.

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

Use the `WORLD` and `LOCAL` controls in the viewport's upper-left corner to choose the gizmo orientation. World keeps the rails, walls, and rings aligned to the scene axes. Local rotates them with the selected entity's resolved world orientation: movement follows its rotated axes, rotation composes around those axes, and scale continues to edit the corresponding local X, Y, or Z scale. The selected space is stored on the transient gizmo component. A drag freezes its basis when it begins, so the handle stays stable even while the transform changes. For a parented entity, the gizmo edits its world pose and derives the new local Transform automatically.

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
