# FDR-007: ECS UI

**Status:** Active
**Last reviewed:** 2026-07-20

## Overview

ECS UI lets projects describe screen-space interfaces with ordinary entities and engine-provided components. The engine synchronizes those components into retained hierarchy and paint state so UI follows entity appearance, disappearance, and world replacement without requiring projects to manage renderer objects.

## Behavior

- Every UI entity describes a rectangular box with an explicit size, optional minimum size, per-axis fill and fit-to-content policies, optional position, per-edge margin and padding, background color, SDF border color and width, corner radius, and hidden state.
- A hidden box removes its complete descendant subtree from retained layout, painting, and pointer interaction without despawning any entities.
- UI entities form a parent-by-UUID hierarchy validated when the scene loads. Entity names remain editable labels.
- Horizontal and vertical stack components arrange child boxes in scene order with a configurable gap; boxes without a stack component overlay their children. Fill stacks treat child sizes as proportions, fill the cross-axis, and can expose draggable separators with minimum pane sizes. Hovering or dragging a separator selects the matching horizontal- or vertical-resize system cursor.
- Table containers arrange children in row-major order across 1–64 equal-width columns, with independent column and row gaps. A partial final row remains left aligned.
- Selectable-list containers arrange direct children vertically as full-width rows, store the selected child by stable UUID, and provide shared selected, hover, and active backgrounds. Lists compose with panels and scroll areas; clicking nested row content selects its direct row ancestor.
- Tree-enabled lists flatten direct rows from semantic parent/order metadata on their public layout components, indent row contents while preserving full-width interaction chrome, omit collapsed or hidden branches, and apply cycle-safe subtree reparent/reorder drops.
- Progress components render an optional track and a clamped fill with configurable inset, color, corner radius, maximum, and left-to-right or right-to-left direction. They compose with any ordinary layout box.
- Viewport components embed a renderer-backed Model, Material, or Texture resource, or the retained active World, inside an ordinary UI box. They participate in normal clipping, scrolling, and paint order; pointer dragging orbits interactive 3D targets and the wheel changes distance. Optional camera and root UUIDs select a World viewpoint and subtree. WGPU assigns visible viewports independently sized pooled targets; static resources are revision-cached rather than redrawn on stable frames.
- Panel decoration adds an optional title band with its own text and background styling and reserves that band above nested content. Titled panels can opt into pointer-driven collapse/expansion; collapsed state lives in the ECS component, contracts the panel to its title band, removes ordinary descendants from layout and interaction, and is indicated by an antialiased SDF disclosure chevron with overridable size, spacing, and radius. Direct child buttons can opt into trailing title-band placement. These are ordinary reusable buttons with text or SDF close, plus, right-chevron, or down-chevron icons, ordinary hover/active styling, and independent activation; multiple actions lay out from right to left and never toggle collapse. Panels can compose with overlay, stack, or table layout.
- Scroll-area containers accept an explicitly oversized child pane, clip descendants to their padded content rectangle, and smoothly approach wheel-driven vertical offsets. Scrollbar width, placement, minimum thumb size, colors, and radius are public component styles.
- Nested scroll clips intersect, the topmost hovered scroll area receives wheel input, and overflowing areas render a proportional scrollbar.
- Every laid-out element receives a public `ui_state` component. Topmost pointer hit testing updates hover and active state, focus follows reusable inputs, and primary presses increment an activation revision. Lists, panels, inputs, and checkboxes increment a change revision when user interaction changes their ECS value. Inputs additionally expose validation, submit, and cancel edges with monotonic revisions. Draggable lists expose their direct-child source and target UUIDs plus a monotonic drop revision.
- Text controls provide labels with RGBA color, pixel size, and left, center, or right alignment within the padded content box. Buttons consume generic element state with optional hover and active background and text colors, independently align their vertically centered label left, center, or right, and may render a close, plus, right-chevron, or down-chevron SDF icon instead of text.
- Each interaction pass emits an engine-internal bounded, ordered stream of generic activation, change, and direct-child drop events addressed by entity UUID. Editor orchestration consumes that stream, while project systems observe the public `ui_state` revisions; layout and control mechanics do not dispatch editor commands.
- Single-line input controls store authored text in their ECS component while the retained UI state owns focus, cursor, selection, horizontal reveal, and blink state. Clicking selects all text.
- Checkbox controls store their boolean state and complete box, border, radius, checkmark, hover, and active styling in an ECS component, consume generic hover/active state, toggle on primary press, and render their box and checkmark analytically with SDFs. Read-only checkboxes retain their visual state without accepting pointer changes.
- Focused inputs accept typed text, Left/Right/Home/End cursor movement, Shift-extended selection, Backspace/Delete, and Select All. Text inputs preserve their ordinary submit-on-focus-transfer behavior. Numeric typing and keyboard stepping are staged in the control without mutating the committed `number`; Enter validates, commits, submits, and leaves the field, while Escape, focus loss, and Tab traversal restore the value present when focus began. Tab and Shift+Tab still move through inputs in paint order. Numeric inputs provide bounds, stepping, and validation; `draggable = true` opts a writable numeric input into live horizontal pointer scrubbing across its complete control surface and the matching resize cursor, with one submission on release. Optional styled prefix badges remain presentation and do not gate interaction. Prefix spacing/radius, selection radius, focus/invalid borders, and caret geometry/colors are public styles.
- Backgrounds and inset borders use GPU-evaluated signed-distance rounded rectangles, including square corners at a zero radius.
- Structural dirty notifications add, update, or remove only affected retained nodes when UI components or entities appear and disappear. Updating values on already-attached UI components does not dirty retained membership; reparenting, hiding, attachment, and removal do. Structural synchronization also validates runtime-authored parent chains and rebuilds compact parent/first-child/next-sibling links, so responsive layout and painting traverse the retained hierarchy linearly instead of rediscovering every node's children through whole-tree scans. Project and editor domains carry independent monotonic layout and paint revisions. Typed ECS setters, retained scrolling, and interaction changes increment only the affected domain, so an unchanged frame skips hierarchy, layout, and paint traversal without hashing every node and component. The setters are shared by project Luau and programmatic engine/editor composition, while scene parsing produces the same public component structs.
- Generated Luau queries expose the complete value and styling payload of every public UI component. `add_component` updates or attaches those same components to live entities, while `remove_component` removes them through the structural dirty path.
- Luau UI additions, removals, and runtime spawns are deferred with other structural ECS commands. Partial UI payloads merge with current values, runtime spawn returns the entity's stable UUID for parent references, and removed/despawned UI component slots are reclaimed.
- Native extensions expose the same complete public UI values, styles, state revisions, deferred mutation, removal, and runtime spawning through fixed-layout typed payloads. Bounded inline text and font buffers keep allocator-owned Odin strings from crossing the extension ABI; UI state remains renderer-owned and read-only.
- WGPU paints retained UI after world geometry, including in headless framegrabs. Project UI, editor chrome, and dynamic editor-world camera/gizmo primitives use independent revision-driven command, CPU-vertex, and GPU-buffer streams. Project UI keeps one uniform canvas-to-window scale when embedded in the free-aspect editor viewport; it is translated and clipped to the available rectangle without independently stretching either axis. Pointer input and semantic diagnostics use the inverse of that exact transform. Changing one stream does not hash, regenerate, or upload the others.
- Bounded runs can replay versioned semantic UI diagnostic scripts against the same reconciled tree used for live interaction. Actions target laid-out entities by stable UUID, name, or visible text; clicks and offset or target-anchored drags include real press/move/release phases, clipped targets are revealed through ancestor scroll areas, expectations fail the run, and capture actions select a tight 1:1 framegrab region without hard-coded coordinates. Optional JSON tree dumps expose raw and visible screen rectangles, clipping, hierarchy, control kinds, text, paint order, and interaction state even when a run fails.
- UI rendering does not require a world camera or renderable geometry.
- The built-in Inter font is embedded and redistributed under the SIL Open Font License 1.1.
- Text uses a precomputed MTSDF atlas and derivative-based GPU antialiasing, so one atlas remains sharp across UI text sizes.
- Projects may declare up to 15 named TTF/OTF resources. Text, buttons, inputs, and panel titles choose a font by resource name; Scrapbot auto-generates stale atlas artifacts and falls back to embedded Inter when a runtime resource is unavailable.

## Design Decisions

### 1. Keep UI authoring in the ECS

**Decision:** Represent public UI state as engine-provided components on ordinary entities.
**Why:** UI lifecycle then follows the same scene loading, world replacement, entity generation, and future command-buffer behavior as gameplay state.
**Tradeoff:** Hierarchical layout needs a synchronization layer because ECS component storage is not itself an ordered tree.

### 2. Maintain retained derived state

**Decision:** An engine-owned synchronization step consumes structural dirty entities, updates retained membership in place, and rebuilds compact parent/first-child/next-sibling links. Independent project/editor layout revisions invalidate only the affected root domain. Responsive layout and paint then traverse those links directly and emit a bounded paint list.
**Why:** Renderers need ordered, resolved rectangles and glyphs rather than repeated ECS queries or project-owned GPU handles.
**Tradeoff:** The implementation has fixed node/paint limits. Stable project and editor domains use monotonic paint revisions plus compact focus/font state; unchanged domains retain their paint-command ranges and skip both traversal and glyph emission. WGPU consumes monotonic output revisions for independent project, editor, and world-overlay buffers, so unchanged frames perform no paint-array hash, vertex rebuild, or upload. Every visual, structural, layout, scrolling, or interaction mutation must increment the correct retained-domain revision through the typed ownership path so both cache layers remain correct. The same reconciler maintains distinct project and transient editor UI coordinate and interaction domains. See ADR-024.

### 3. Use explicit pixels with opt-in proportional fill

**Decision:** Use top-left pixel coordinates and explicit sizes with overlay, horizontal-stack, and vertical-stack flow. A stack can opt into fill layout, where authored child sizes seed proportional weights and each child fills the cross-axis. A child can set `fixed_in_fill` to keep its authored main-axis extent while siblings divide the remainder. Fill stacks may make their gaps draggable and enforce a shared minimum pane size. Individual boxes can independently fill either available axis, fit either axis to visible children, and clamp the result to an authored minimum size.
**Why:** Fixed boxes remain deterministic, while an explicit fill policy supports responsive application and editor layouts without introducing a complete constraint language.
**Tradeoff:** There is no percentage syntax, general box alignment, weighted per-child grow policy outside fill stacks, or horizontal scrolling yet. Split weights and resolved fit-to-content sizes are retained runtime state rather than scene data.

### 4. Compose controls from a shared box model

**Decision:** Keep geometry and visual box styling in one layout component, then add independent stack, table, list, progress, viewport, panel, text, button, input, and checkbox components to an entity. Express title-band actions by composing ordinary icon-button child entities instead of adding a singular control API to panels.
**Why:** A shared box model makes margins, padding, backgrounds, and rounded corners consistent while ECS composition keeps layout and content roles explicit. See ADR-014.
**Tradeoff:** Invalid combinations require scene validation. Generic activation/change revisions and the ordered event stream expose interaction edges, while higher-level command routing remains the responsibility of project or editor systems.

### 5. Keep pointer state generic and derived

**Decision:** Hit-test all retained element boxes and publish hover, active, focus, activation, and change state through the renderer-owned, read-only `ui_state` ECS component. Emit matching engine-internal generic activation/change events after control mechanics run so editor orchestration can assign meaning without entering the mechanics path.
**Why:** Pointer interaction is a property of an element's screen area, not of a button. Projects and the editor can consume the same stable revision counters without renderer code assigning meaning to a click. See ADR-014 and ADR-025.
**Tradeoff:** Transient booleans describe the most recent UI pass and are observed by project systems on the following frame. Revision counters must be retained by consumers that need to detect every edge.

### 6. Embed a fallback and compile project fonts automatically

**Decision:** Embed a precomputed MTSDF atlas for Inter, auto-compile declared project TTF/OTF files into cached MTSDF artifacts, and select their fixed texture-array layer per glyph command.
**Why:** Projects can own their visual identity while packaged games and agent framegrabs remain deterministic and independent of system font discovery or platform font APIs. Inter keeps engine/editor text and failed resource lookups legible.
**Tradeoff:** Project asset compilation requires `msdf-atlas-gen` when a cache is absent or stale. The current path is ASCII-only and does not provide shaping, localization, kerning, variable axes, arbitrary fallback chains, or dynamic atlas growth.

### 7. Keep smooth scrolling derived and clip paint on the GPU

**Decision:** Author scroll speed and smoothness in an ECS component, but retain current and target offsets on the reconciled node. Intersect descendant clips during layout and enforce them per fragment in the WGPU UI shader.
**Why:** Authored components stay declarative, smoothing survives normal frame reconciliation, pointer and paint clipping share one rectangle, and nested areas preserve the ordered paint stream. See ADR-020.
**Tradeoff:** Scroll position is not yet queryable or controllable through public ECS APIs, and per-fragment discard adds modest shader work.

### 8. Keep panels decorative and tables structural

**Decision:** Let `ui_panel` reserve and paint a title band without becoming a flow container, optionally use that band to toggle ECS-owned collapsed state, and place any direct child `ui_button` marked as a panel action in the trailing title band. Let `ui_table` own row-major child placement. Tables default to equal columns, can derive reusable column proportions from the first row's authored widths, and can expose pointer-draggable separators that resize adjacent columns for the retained UI session.
**Why:** Panels should compose around any nested layout, while tables need a generic 1–N column primitive rather than inspector-specific field rendering.
**Tradeoff:** A collapsed panel contracts its vertical extent but retains its authored expanded size. Panel action placement is intentionally limited to direct child buttons. Resized table proportions are transient reconciler state rather than serialized scene edits. Spanning, headers, and automatic row measurement are deferred; authored child height determines each row's height.

### 9. Retain editing state while keeping values in the ECS

**Decision:** Store an input's current text and styling in its public ECS component, but retain transient focus, cursor, selection, original value, horizontal offset, and caret blink state in the UI reconciler.
**Why:** Systems and tools can observe the value through the ordinary world while frame-local interaction survives reconciliation without polluting scene data.
**Tradeoff:** This first control is single-line and ASCII-only. It does not yet provide clipboard operations, IME composition, Unicode shaping, or multiline editing.

Numeric mode enables parsing, validation, bounds, and keyboard stepping. Pointer scrubbing is a separate explicit capability: `draggable = true` enables whole-surface horizontal scrubbing only when the input is numeric and writable. A click without crossing the drag threshold still focuses and selects the input for text editing.

### 10. Make list selection ECS-owned

**Decision:** Let `ui_list` vertically lay out its direct children, fill their width, and store the selected child UUID in the component. Let it optionally recognize direct-child drag/drop gestures and classify a row's top edge, middle, and bottom edge as `before`, `into`, and `after`. Publish source/target UUIDs, placement, and a drop revision through `ui_state`; paint a styled clipped lander line for insertion placements and a target-row background for `into`. Derive hover and active state through the existing pointer chain, and compose scrolling through `ui_scroll_area` instead of embedding a second scrolling model.
**Why:** Project UI and editor tooling need the same reusable navigation primitive, while stable UUID selection survives retained reconciliation and nested labels or row content remain clickable.
**Tradeoff:** Lists currently support one selected direct child, vertical layout, and pointer selection only. Keyboard navigation, activation events, multi-selection, virtualization, disabled rows, and programmatic scroll-to-selection remain future work.

Tree mode is an opt-in extension of the same list rather than a second widget. Direct rows carry semantic parent, sibling order, and collapse state on `ui_layout`; the shared reconciler flattens and indents them, hides collapsed branches, rejects cycles, and mutates parent/order metadata for subtree-safe `before`, `into`, and `after` drops. Ordinary non-tree direct children remain available for toolbars. Row chrome, labels, and disclosure buttons remain normal composable UI entities.

### 11. Drive diagnostics through semantic retained state

**Decision:** Let bounded renderer runs inspect and drive the reconciled ECS UI tree by entity identity and visible control data, while preserving ordinary input, layout, scrolling, state, and paint paths.
**Why:** Automated agents and tests need to reproduce interaction bugs without OS automation, coordinate guessing, or editor-only fixtures, and need structured geometry alongside pixels when a visual assertion fails.
**Tradeoff:** Text-only targets can be ambiguous and therefore support an occurrence selector; scripts that depend on internal editor names remain diagnostic contracts rather than public project APIs.

## Related

- **ADRs:** ADR-003, ADR-013, ADR-014, ADR-020, ADR-023, ADR-024, ADR-025, ADR-037
- **FDRs:** FDR-002, FDR-003, FDR-005, FDR-008

## Open Questions

- Should release-inside activation become a separate state edge from primary press?
- When should text gain shaping, Unicode fallback chains, and glyph-atlas streaming?
