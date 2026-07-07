# FDR-018: Editor Entity Inspector

**Status:** Active
**Last reviewed:** 2026-07-07

## Overview

The editor entity inspector lets a developer inspect and lightly manipulate live scene entities while a project is running headfully. It exists as the first game-facing editor workflow built on Scrapbot's engine-hosted UI, shared ECS runtime, and live project update loop.

## Behavior

- The editor shell is hidden by default and can be shown with `scrapbot run --editor` or toggled in a headful run with Ctrl+Tab.
- When the editor shell is visible, the game renders into the full remaining viewport between the editor top bar, bottom bar, left sidebar, and right sidebar.
- The editor shell includes playback controls for pause/resume and single-frame stepping.
- Playback controls are generated as retained `scrapbot.ui.button` + `scrapbot.ui.command` entities and routed through shared retained UI command hit testing.
- Pausing stops scheduled update systems while keeping startup, diagnostics, rendering, and editor interaction available.
- Clicking a visible renderable mesh selects that entity.
- The left sidebar shows a live list of entities currently in the world below the systems list.
- Entity-list rows show the entity name, a component count, and highlight the selected entity.
- Spawned runtime entities use muted row text in the entity list so they are visually distinct from authored scene entities.
- Clicking an entity-list row selects that generation-aware entity handle and updates the right-sidebar component inspector.
- The bottom bar shows live world counts and viewport size.
- The right sidebar is reserved for selected-entity component inspection and component field editing.
- The selected entity inspector shows the selected entity name/id and renders one full-width component box per attached component. Boxes use consistent 4px-grid sidebar padding and display current field values read through ECS component reflection.
- Component boxes are arranged as a retained vertical group with one-pixel separators between boxes.
- Component titles are fitted to the card width and should not overdraw adjacent content.
- Component fields render as table-like rows with property labels on the left and values on the right.
- Component field rows are reusable inspector editing controls: the base row is a retained table that handles configurable label/value sizing, value input placement, focus state, and clipping, while type-specific behavior decides how a selected value is parsed and committed.
- Each editable value renders as a darker rounded text input box with 2 logical pixels of text padding and rounded corners. `vec3` fields render one input box per lane.
- `vec3` fields render one input box per lane, each preceded by a colored lane label: red `X`, green `Y`, and blue `Z`.
- Color-like `vec3` fields additionally render a color swatch next to the lane input boxes.
- Boolean fields render as click-to-toggle controls.
- Known enum-like string fields render as selectors. First-pass selectors cover built-in primitive names, renderer tone mapping and antialiasing modes, canvas scale modes, and retained UI alignment fields.
- Clicking a value input focuses it for editing and gives it a focus-ring border plus a visible caret.
- Numeric value inputs select their full value when focused so typing can immediately replace the existing number. Select-all-on-focus is treated as an input-control option rather than a global editor rule.
- Focused inputs accept typed text through the platform text-input path.
- Focused inputs support left/right caret movement, Home, End, Backspace, Delete, Ctrl+A select all, and Shift+movement text selection.
- Typing, Backspace, and Delete replace or remove the selected range when text is selected.
- Field changes are staged in the input buffer and apply only when the user presses Enter or the input loses focus.
- Ctrl+Z undoes inspector field edits, and Ctrl+Shift+Z or Ctrl+Y redoes them.
- Inspector edits mutate the live ECS world. In the Odin implementation, first-pass scene persistence rewrites existing authored field lines for authored entities in the default scene TOML.
- String fields can be edited through the same text input control, subject to the current fixed input-buffer length.
- Clicking the selected-entity header copies the full entity id to the editor clipboard, even when the visible header area is width-constrained.
- A selected renderable gets a world-space translate gizmo with visible X, Y, and Z handles in Odin software and WebGPU editor render paths.
- Dragging a gizmo axis mutates the selected entity's transform position. Holding Shift during an Odin translate-gizmo drag snaps the moved axis to 0.25 world-unit increments. In the Odin implementation, each completed translate-gizmo drag contributes one grouped undo/redo command and one pending scene edit for `scrapbot.transform.position`.
- The Odin SDL run-loop path shares one live-project frame tick for software and WebGPU presentation, passes active-axis drag state into rendering so the constrained axis is highlighted, and deterministic smoke coverage routes SDL pointer input through entity selection and translate-gizmo dragging.
- Selection uses generation-aware entity handles so stale selections are rejected instead of silently aliasing another entity.
- Editor chrome consumes pointer input before it can select scene entities or trigger in-game UI buttons. Mesh picking and gizmo interaction only use pointer coordinates inside the game viewport.

## Design Decisions

### 1. Keep browsing lightweight

**Decision:** The editor exposes a compact live entity list in the left sidebar and keeps component details in the right sidebar for the selected entity.
**Why:** Developers need a basic way to inspect non-renderable or hard-to-click entities without turning the first inspector into a full hierarchy editor.
**Tradeoff:** The list is intentionally shallow. Search, filters, hierarchy grouping, and richer virtualization still need later design.

### 1a. Show entity provenance without adding new scene data

**Decision:** The entity list visualizes runtime-spawned entities with muted text while leaving authored scene entities at the normal row color.
**Why:** Future scene persistence and entity editing need an early, visible distinction between state that lives in scene TOML and state created while the project runs.
**Tradeoff:** The first visualization is deliberately subtle. It does not yet expose filters, badges, persistence actions, or component-level dirty state.

### 2. Use renderable picking as the first selection mechanism

**Decision:** Clicking a mesh selects the nearest renderable entity hit by a CPU-side picking ray, while clicking a row in the entity list selects that entity directly.
**Why:** Mesh clicking is the most direct first editor interaction for visible objects, and the entity list covers resources, non-renderables, and occluded objects.
**Tradeoff:** The current picker uses renderable bounds rather than triangle-accurate mesh acceleration, and the entity list does not yet provide hierarchy or search.

### 3. Gate gameplay updates through editor playback state

**Decision:** Pause and step are owned by the live project session and gate scheduled update systems.
**Why:** Playback controls must affect the authoritative game world, not only renderer presentation. Keeping the state in the live project avoids a renderer-only pause path.
**Tradeoff:** This is not yet a full timeline/debugger model. Fixed update, rewind, breakpoints, deterministic stepping controls, and simulation speed need later decisions.

### 4. Build the gizmo with engine render data

**Decision:** The translate gizmo is generated by the engine as transient non-scene renderables.
**Why:** The gizmo should be visible and batched by the same renderer path without mutating project scene files or becoming a selectable game entity.
**Tradeoff:** Gizmo rendering is currently simple screen-space strokes projected from world-space axes. Local-space handles, rotation/scale modes, richer snapping controls, occlusion behavior, and a broader editor transaction model are not covered yet.

### 5. Inspect and edit real ECS component storage

**Decision:** Inspector component cards read selected entity components and fields from the shared ECS world, and focused primitive fields write back through the same runtime component field APIs.
**Why:** Editor inspection and editing should reflect the actual runtime state used by scripts, native systems, rendering, and tests. This follows ADR-016 and ADR-022.
**Tradeoff:** The first editing path is deliberately text-input based and commits on Enter or blur. Drag sliders, rich typed widgets, validation diagnostics, scene persistence, reload transaction integration, and command grouping still need later design.

### 5a. Keep component boxes bounded

**Decision:** Inspector component boxes fill the right sidebar width, stack in a retained vertical group, use one-pixel separators, and render fields as left-label/right-value rows. Field rows are retained `scrapbot.ui.table` entities with two columns and `first_column_ratio = 0.5`, so the table controls the current 50/50 title/editor split after padding and gap. Component titles and field rows use consistent logical 4px-grid spacing, while typed input controls use tighter 2 logical pixels of text padding and 2 logical pixel row gaps for readability. Overflowing component stacks live inside the inspector scroll view.
**Why:** Component ids can be long qualified strings, especially engine-owned `scrapbot.*` ids, and editor chrome must remain legible without text escaping rounded cards.
**Tradeoff:** Truncated ids and values still need future hover, tooltip, horizontal scrolling, or expandable-detail affordances before the inspector is comfortable for deeper editing. The first selected-header copy path gives agents and users a deterministic way to recover the full selected entity id.

### 5b. Reserve the right sidebar for selected-entity components

**Decision:** The right sidebar is exclusively for selected-entity component inspection/editing. Systems and runtime status live in other chrome regions.
**Why:** Mixing performance, selection, and editing in one sidebar made the first overlay hard to scan and left no stable surface for component editing. A dedicated component column gives future editors a clear home for per-component controls.
**Tradeoff:** Entity browsing/search and asset/project inspectors need their own future regions or modes.

### 5c. Start inspector undo at the field-command level

**Decision:** Inspector field edits are stored as bounded in-memory commands containing the selected entity handle, component id, field name, old value, and new value.
**Why:** This gives the editor immediate undo/redo behavior without inventing a global editor transaction model too early.
**Tradeoff:** The history is runtime-only, per editor session, and field-granular. It does not yet group drags, survive reload, coordinate with future multi-entity edits, or persist component/entity structural edits.

### 5d. Build typed controls as variations on a reusable row

**Decision:** The inspector has one reusable field-row layout and adds typed control variants for value kinds. Numeric and general string values use text inputs, `vec3` values use lane inputs preceded by colored `X`/`Y`/`Z` labels, color-like `vec3` values add a swatch, booleans use toggles, and known enum-like strings can use selectors.
**Why:** This follows the editor-library direction: one base editing component shape with type-specific gadgets, instead of one-off layout code per component field. It also keeps live ECS mutation and undo/redo on the same field-command path.
**Tradeoff:** The first selectors are hard-coded to known engine string fields. Rich enum metadata, dropdowns, sliders, drag editing, validation messages, and full scene persistence still need later design.

### 5e. Persist authored field edits with narrow TOML rewrites

**Decision:** The Odin editor records the latest successful inspector field edit as a pending scene edit. `scrapbot test` replay and live project frames consume that edit by finding the selected authored entity, matching the component table in the default scene file, and replacing the existing authored field line with the new typed TOML value.
**Why:** This gives immediate text-file feedback for the most common inspector workflow while preserving the text-first project model.
**Tradeoff:** The first pass is intentionally narrow. It only updates existing field lines on authored entities in the default scene, and it does not create missing fields, persist spawned entities, persist component add/remove/despawn operations, preserve inline comments on edited lines, or perform a full TOML round-trip.

### 6. Route editor controls through retained UI commands

**Decision:** Pause/play, step, splitter hit targets, and the systems scroll view are generated as retained UI data and routed through the shared composed pointer route. Editor commands apply directly to editor state instead of emitting project-world UI command events.
**Why:** Editor chrome should exercise the same UI ownership path as game UI without leaking editor service commands into project scripts.
**Tradeoff:** This proves first command and scroll ownership, but persistent focus, cross-frame pointer capture, bubbling, keyboard activation, disabled controls, and typed editor command payloads still need a richer UI event model.

## Related

- **ADRs:** ADR-007, ADR-016, ADR-022
- **FDRs:** FDR-005, FDR-008, FDR-009

## Open Questions

- What searchable or hierarchical entity browser should grow out of the compact entity list?
- Should picking move from bounding volumes to per-mesh acceleration, ID-buffer selection, or a hybrid?
- How should full editor transactions persist back into text scene files while preserving live reload's last-known-good behavior?
- How should undo/redo become a project-wide transaction model that can group text edits, component add/remove, and multi-entity changes beyond the first translate-gizmo drag grouping?
- What transform gizmo modes, snapping rules, and coordinate spaces are required before this feels like a real editor?
- How should pause/step interact with future fixed-update scheduling and parallel systems?
