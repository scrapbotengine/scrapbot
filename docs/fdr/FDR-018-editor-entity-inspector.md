# FDR-018: Editor Entity Inspector

**Status:** Active
**Last reviewed:** 2026-07-04

## Overview

The editor entity inspector lets a developer inspect and lightly manipulate live scene entities while a project is running headfully. It exists as the first game-facing editor workflow built on Machina's engine-hosted UI, shared ECS runtime, and live project update loop.

## Behavior

- The editor shell is hidden by default and can be shown with `machina run --editor` or toggled in a headful run with Ctrl+Tab.
- When the editor shell is visible, the game renders into the full remaining viewport between the editor top bar, bottom bar, left sidebar, and right sidebar.
- The editor shell includes playback controls for pause/resume and single-frame stepping.
- Playback controls are generated as retained `machina.ui.button` + `machina.ui.command` entities and routed through shared retained UI command hit testing.
- Pausing stops scheduled update systems while keeping startup, diagnostics, rendering, and editor interaction available.
- Clicking a visible renderable mesh selects that entity.
- The bottom bar shows live world counts and viewport size.
- The right sidebar is reserved for selected-entity component inspection and component field editing.
- The selected entity inspector shows the selected entity name/id and renders one full-width component box per attached component. Boxes use consistent sidebar padding and display current field values read through ECS component reflection.
- Component boxes are arranged as a retained vertical group with one-pixel separators between boxes.
- Component titles are fitted to the card width and should not overdraw adjacent content.
- Component fields render as table-like rows with property labels on the left and values on the right.
- Component field rows are reusable inspector editing controls: the base row handles label layout, value input placement, focus state, clipping, and selection highlighting, while type-specific behavior decides how a selected value is parsed and committed.
- Each editable value renders as a darker rounded text input box. `vec3` fields render one input box per lane.
- Clicking a value input focuses it for editing and gives it a focus-ring border plus a visible caret.
- Numeric value inputs select their full value when focused so typing can immediately replace the existing number. Select-all-on-focus is treated as an input-control option rather than a global editor rule.
- Focused inputs accept typed text through the platform text-input path.
- Focused inputs support left/right caret movement, Home, End, Backspace, Delete, Ctrl+A select all, and Shift+movement text selection.
- Typing, Backspace, and Delete replace or remove the selected range when text is selected.
- Field changes are staged in the input buffer and apply only when the user presses Enter or the input loses focus.
- Ctrl+Z undoes inspector field edits, and Ctrl+Shift+Z or Ctrl+Y redoes them.
- Inspector edits mutate the live ECS world. They do not yet persist back to TOML scene files.
- String fields can be edited through the same text input control, subject to the current fixed input-buffer length.
- The inspector does not show a full entity list by default.
- A selected renderable gets a world-space translate gizmo with X, Y, and Z handles.
- Dragging a gizmo axis mutates the selected entity's transform position.
- Selection uses generation-aware entity handles so stale selections are rejected instead of silently aliasing another entity.
- Editor chrome consumes pointer input before it can select scene entities or trigger in-game UI buttons. Mesh picking and gizmo interaction only use pointer coordinates inside the game viewport.

## Design Decisions

### 1. Keep the first inspector selection-first

**Decision:** The first inspector shows the selected entity plus aggregate counts, not a full live entity table.
**Why:** Projects may have many entities. Selection-first inspection gives immediate utility without making every editor frame enumerate and render a large list.
**Tradeoff:** Browsing, search, filters, hierarchy views, and virtualized entity lists still need later design.

### 2. Use renderable picking as the first selection mechanism

**Decision:** Clicking a mesh selects the nearest renderable entity hit by a CPU-side picking ray.
**Why:** Mesh clicking is the most direct first editor interaction and works without requiring a hierarchy panel.
**Tradeoff:** The current picker uses renderable bounds rather than triangle-accurate mesh acceleration, so dense or oddly shaped meshes can select coarsely until a real picking acceleration structure exists.

### 3. Gate gameplay updates through editor playback state

**Decision:** Pause and step are owned by the live project session and gate scheduled update systems.
**Why:** Playback controls must affect the authoritative game world, not only renderer presentation. Keeping the state in the live project avoids a renderer-only pause path.
**Tradeoff:** This is not yet a full timeline/debugger model. Fixed update, rewind, breakpoints, deterministic stepping controls, and simulation speed need later decisions.

### 4. Build the gizmo with engine render data

**Decision:** The translate gizmo is generated by the engine into the render world as non-scene renderables.
**Why:** The gizmo should be visible and batched by the same renderer path without mutating project scene files or becoming a selectable game entity.
**Tradeoff:** Gizmo rendering is currently simple world-space box geometry. Local-space handles, rotation/scale modes, snapping, hover styling, occlusion behavior, and undo integration are not covered yet.

### 5. Inspect and edit real ECS component storage

**Decision:** Inspector component cards read selected entity components and fields from the shared ECS world, and focused primitive fields write back through the same runtime component field APIs.
**Why:** Editor inspection and editing should reflect the actual runtime state used by scripts, native systems, rendering, and tests. This follows ADR-013 and ADR-016.
**Tradeoff:** The first editing path is deliberately text-input based and commits on Enter or blur. Drag sliders, rich typed widgets, validation diagnostics, scene persistence, reload transaction integration, and command grouping still need later design.

### 5a. Keep component boxes bounded

**Decision:** Inspector component boxes fill the right sidebar width, stack in a retained vertical group, use one-pixel separators, and render fields as left-label/right-value rows. Component titles and field rows use consistent internal padding and are clipped to the available width for the built-in bitmap font. Overflowing component stacks live inside the inspector scroll view.
**Why:** Component ids can be long qualified strings, especially engine-owned `machina.*` ids, and editor chrome must remain legible without text escaping rounded cards.
**Tradeoff:** Truncated ids and values need future hover, copy, tooltip, horizontal scrolling, or expandable-detail affordances before the inspector is comfortable for deeper editing.

### 5b. Reserve the right sidebar for selected-entity components

**Decision:** The right sidebar is exclusively for selected-entity component inspection/editing. Systems and runtime status live in other chrome regions.
**Why:** Mixing performance, selection, and editing in one sidebar made the first overlay hard to scan and left no stable surface for component editing. A dedicated component column gives future editors a clear home for per-component controls.
**Tradeoff:** Entity browsing/search and asset/project inspectors need their own future regions or modes.

### 5c. Start inspector undo at the field-command level

**Decision:** Inspector field edits are stored as bounded in-memory commands containing the selected entity handle, component id, field name, old value, and new value.
**Why:** This gives the editor immediate undo/redo behavior without inventing scene-file persistence or a global editor transaction model too early.
**Tradeoff:** The history is runtime-only, per editor session, and field-granular. It does not yet group drags, survive reload, serialize to project files, or coordinate with future multi-entity edits.

### 6. Route editor controls through retained UI commands

**Decision:** Pause/play, step, splitter hit targets, and the systems scroll view are generated as retained UI data and routed through the shared composed pointer route. Editor commands apply directly to editor state instead of emitting project-world UI command events.
**Why:** Editor chrome should exercise the same UI ownership path as game UI without leaking editor service commands into project scripts.
**Tradeoff:** This proves first command and scroll ownership, but persistent focus, cross-frame pointer capture, bubbling, keyboard activation, disabled controls, and typed editor command payloads still need a richer UI event model.

## Related

- **ADRs:** ADR-007, ADR-013, ADR-016
- **FDRs:** FDR-005, FDR-008, FDR-009

## Open Questions

- What virtualized/searchable entity browser should complement click selection?
- Should picking move from bounding volumes to per-mesh acceleration, ID-buffer selection, or a hybrid?
- How should editor mutations persist back into text scene files while preserving live reload's last-known-good behavior?
- How should undo/redo become a project-wide transaction model that can group drags, text edits, component add/remove, and multi-entity changes?
- What transform gizmo modes, snapping rules, and coordinate spaces are required before this feels like a real editor?
- How should pause/step interact with future fixed-update scheduling and parallel systems?
