# FDR-005: Engine UI Primitives

**Status:** Active
**Last reviewed:** 2026-07-05

## Overview

Engine UI primitives provide the controls and layout capabilities needed for runtime overlays, debug tools, and the future editor. They exist so Machina can build tooling with its own scene model, renderer, and input systems instead of depending on a separate editor application stack.

## Behavior

- The engine can render text-authored UI overlays in offscreen renders and interactive windows.
- Scene entities can define a UI canvas, screen-space colored rectangles, rounded borders, fixed-pixel text labels, button markers, non-rendering hit areas, button command ids, scroll views, vertical stacks, horizontal groups, direction-aware stacks, layout child metadata, spacers, text blocks, toggles, progress bars, and separators.
- `machina.ui.canvas` stores `design_size` and `scale_mode`. `scale_mode = "none"` preserves raw screen pixels. `scale_mode = "fit"` scales and centers scene-authored UI into the current scene UI target while preserving aspect ratio. `scale_mode = "fill"` scales enough to cover that target. The target is the full window in normal runs and the editor game viewport while the editor shell is visible.
- UI rectangles use screen-space positions and sizes with a top-left origin, plus an optional `corner_radius` field in pixels. Missing `corner_radius` values default to `0.0` for compatibility with older scene data.
- UI rectangle corners render through the UI shader using rounded-rectangle SDF coverage with alpha blending. Text glyph quads use the same UI pipeline with `corner_radius = 0.0`.
- `machina.ui.border` adds a data-authored border to a rect with `color` and `thickness`. Borders render through the same rounded-rectangle SDF path by drawing an outer rounded rect and an inset fill rect.
- UI text labels use screen-space positions with a top-left origin.
- The first UI demo uses a subdued dark Tailwind-derived palette: near-black workspaces, slate panels, muted cyan structure accents, restrained semantic control colors, and high-contrast but not pure-white text.
- Button markers derive hover, held, and pressed interaction state in headful runs and use that state for button visuals.
- UI interaction consumes transient `machina.input.*` ECS resources instead of reading raw platform events directly.
- Releasing the primary pointer over a command button emits a transient ECS command event that Luau systems can consume during the same frame.
- Command button hit routing is centralized in the retained UI layout module. Scene-authored command events and engine-owned editor command controls resolve the same rect or hit-area layout and clipping rules before dispatch.
- Headful runs can toggle the engine-owned editor/debug overlay with Ctrl+Tab.
- Headful runs hide the engine-owned editor/debug overlay by default; `machina run --editor` starts with it visible.
- The engine-owned editor/debug shell displays current FPS in a top bar and keeps its chrome spacing on a 4px grid.
- In editor mode, 3D scene content and scene-authored game UI render into the full remaining viewport between the top bar, bottom bar, left sidebar, and right sidebar. The editor viewport is not forced to 16:9.
- The left sidebar hosts the system performance inspector and, below it, a live entity list for the current ECS world. The right sidebar is reserved for selected-entity component inspection and eventual component editing. The sidebars are separated from the game viewport by draggable splitters. Splitters render as thin dividers, use public non-rendering hit-area command buttons for wider hover/click targets, change color when hovered or dragged, and use the platform east-west resize cursor in headful runs.
- The engine-owned editor/debug shell also hosts the first editor playback controls and selected-entity inspector; detailed behavior is tracked in FDR-018.
- When live system profiling data is available, the editor/debug overlay lists active systems with their full system id and rolling average runtime over the current profiling window.
- The editor/debug overlay also lists engine-internal render systems profiled through the render ECS schedule.
- The visible performance table updates at a throttled human-readable cadence while profiling continues to sample scheduled systems every frame.
- The system performance view uses one retained table panel with aligned text rows, consistent 4px-grid sidebar padding, and a scene-shaped clipped smooth-scroll viewport so long system lists remain legible and every system can be reached without inline pagination text.
- The system performance view shows a generated scrollbar when its clipped system list overflows.
- While the editor/debug overlay is visible, mouse wheel input scrolls the visible systems, entity-list, or inspector viewport only when the pointer is over that viewport or its scrollbar and the target list overflows. Wheel input over the game viewport remains available to scene-authored scroll views. Scroll state uses a target pixel offset plus an animated visible pixel offset, and wheel distance is intentionally independent from row height so content can settle between rows.
- The UI gallery example demonstrates the retained primitive set with panels, text, buttons, command events, scroll views, vertical stacks, horizontal groups, tables, horizontal stacks, spacers, centered text blocks, toggles, progress bars, separators, and script-mutated UI state.
- `machina.ui.scroll_view` defines a screen-space viewport with `position`, `size`, and `content_offset` fields. Descendants are offset by `content_offset` and clipped to the viewport.
- In live headful runs, scene-authored scroll views under the pointer update their `content_offset` from mouse wheel input before project update systems run.
- `machina.ui.vbox` defines a vertical stack origin and spacing. Direct children are ordered by `machina.ui.layout.item.order` and stacked by their current primitive height.
- `machina.ui.hgroup` defines a horizontal group with `position`, `size`, `spacing`, and `padding`. Direct children are ordered by `machina.ui.layout.item.order`, start from natural or preferred widths, shrink toward minimum widths when space is tight, and receive proportional extra width from positive `grow` values while respecting maximum widths.
- `machina.ui.table` defines a row-major layout grid with `position`, `size`, `columns`, `row_height`, `column_gap`, `row_gap`, `padding`, and `first_column_ratio`. Direct children are ordered by `machina.ui.layout.item.order`; `order % columns` selects the column and `order / columns` selects the row. For two-column tables, `first_column_ratio = 0.5` creates an even title/editor split.
- `machina.ui.stack` defines a direction-aware stack origin, spacing, direction, and padding. Supported directions are `vertical`, `column`, `horizontal`, and `row`.
- `machina.ui.layout.item` attaches an entity to a parent entity id and gives it integer order, minimum, preferred, and maximum size hints, grow and shrink ratios, cross-axis alignment metadata, and symmetric x/y/z margin. Parent ids are stable scene entity ids, not dense runtime handles. Hgroups use these hints for main-axis negotiation; older stack/vbox paths use the resulting item size.
- `machina.ui.layout.item` can also parent a child to a non-container UI rect, text, or separator. In that case the child inherits the parent's resolved position and continues through the parent's layout chain. This is the preferred pattern for button labels and small composite controls.
- `machina.ui.spacer` participates in layout without rendering.
- `machina.ui.text_block` gives a text entity a content box and horizontal/vertical `start`, `center`, or `end` alignment.
- `machina.ui.hit_area` defines a non-rendering interaction rectangle with `position` and `size`. Command routing and button interaction state prefer it over the visual rect when present.
- `machina.ui.toggle` stores checked state and influences button/rect visuals. It does not yet toggle itself automatically; scripts or editor systems own state mutation.
- `machina.ui.progress_bar` stores value, max, and fill color. It renders as a fill inside the entity's rect.
- `machina.ui.separator` renders a thin semantic divider through the same UI vertex path as rectangles.
- Retained UI layout and hit testing are resolved through a shared engine module used by both rendering and scene UI input. Render positions, hover/press state, command dispatch, scrolling, clipping, and scene canvas viewport scaling should not maintain separate semantics.
- Mouse-wheel scroll routing is component-based: code asks the shared retained UI router for the `machina.ui.scroll_view` under the pointer, receives the bounded next offset, and then applies or mirrors that result. Scene-authored scroll views apply it directly; editor lists generate small scroll-view routing worlds and mirror the routed offset into animated editor state.
- UI can be used for runtime diagnostics before a full editor exists.
- UI definitions that are part of projects or tools follow the text-first project model.
- The UI overlay renders after 3D scene content.

## Design Decisions

### 1. Use engine-hosted UI for tooling

**Decision:** Editor and runtime tools are built with Machina UI primitives.
**Why:** This keeps tooling portable and integrated with the engine. It follows ADR-007.
**Tradeoff:** Early editor work depends on maturing an engine UI system first.

### 2. Support debug overlays before full editor panels

**Decision:** The first UI milestone should support runtime diagnostics and inspection overlays.
**Why:** Overlays exercise rendering, input, layout, and engine state presentation with a smaller surface than a full editor.
**Tradeoff:** Overlay-first design must still leave room for complex editor workflows.

### 3. Keep initial editor UI engine-owned

**Decision:** The first editor/debug shell is generated by the engine at runtime instead of being authored in the project scene, and it is opt-in at launch through `machina run --editor`.
**Why:** Editor chrome should be available over any project without mutating project files, while still using the same ECS UI primitives and renderer path as scene-authored UI. The game viewport must remain an explicit region so editor panels do not obscure the running scene. It follows ADR-007 and ADR-013.
**Tradeoff:** Runtime tooling UI needs a separate authoring path before it can become a full editable editor layout.

### 4. Keep the first slice retained and ECS-authored

**Decision:** The first UI primitives are retained scene data rather than an immediate-mode scripting API.
**Why:** Retained ECS data keeps the first slice text-first, reloadable through scene files, render-testable, and aligned with ADR-008 and ADR-013.
**Tradeoff:** Authoring dynamic UI from scripts still needs a higher-level API in a later slice.

### 4a. Render rounded rectangles with SDF coverage

**Decision:** `machina.ui.rect.corner_radius` is a real ECS field and rounded corners are rendered in `ui.wgsl` through a rounded-rectangle SDF.
**Why:** Rounded panels and buttons should be data-authored, work for scene UI and engine-generated editor UI, and avoid baking corner geometry into every rect.
**Tradeoff:** The current radius is uniform per rect. Per-corner radii, borders, shadows, and style inheritance remain future work.

### 5. Use a built-in pixel text path before font assets

**Decision:** Early text labels render with Spleen 16x32-derived bitmap glyphs embedded as engine source data, generated from the checked-in BDF source under `third_party/spleen/`.
**Why:** UI without text is not useful, and a built-in text path avoids making asset import, font atlases, shaping, and localization prerequisites for the first UI milestone.
**Tradeoff:** The current text path is suitable for diagnostics and examples, not polished editor typography.

### 6. Keep input interaction in the ECS path

**Decision:** Platform input is translated into transient `machina.input.pointer`, `machina.input.keyboard`, and `machina.input.frame` ECS resources. UI button visuals are derived by render-phase ECS systems, pointer ownership can be resolved through `ui_layout.routePointer`, and command events are emitted into the live project world before update systems run.
**Why:** This keeps UI behavior aligned with the engine-wide ECS model, follows ADR-020, and avoids a separate immediate-mode renderer input channel.
**Tradeoff:** Command routing is string-id based for now; richer action payloads, persistent focus, text input, keyboard navigation, bubbling, modal layers, and editor service dispatch still need later design.

### 6a. Resolve retained layout for scene UI input

**Decision:** Project UI input routing resolves `scroll_view`, `vbox`, `stack`, and `layout.item` before hit-testing command buttons or scrolling viewports.
**Why:** Scene-authored controls can be local to layout containers, so raw component positions are not authoritative screen positions. Rendering, command events, and scroll interaction must agree on the retained layout model.
**Tradeoff:** `src/ui_layout.zig` is now the shared resolver for rendering and scene UI input, but the retained layout model is still intentionally compact and does not yet provide full constraint solving, focus, scroll bars, or style inheritance.

### 6b. Share UI hit testing between rendering and input routing

**Decision:** Button hover/held/pressed visuals, scene command dispatch, editor command controls, scene scroll routing, and editor chrome pointer ownership use shared `src/ui_layout.zig` hit-test helpers.
**Why:** A control should not look hovered through one coordinate path and dispatch through another. Keeping rect resolution, clipping, and hit tests together gives future focus/capture work one place to extend.
**Tradeoff:** Hit routing still selects the last matching entity in the current ECS iteration order. Z-order, disabled state, focus ownership, pointer capture, bubbling, and modal layers remain future design work.

### 6c. Add a composed pointer route foundation

**Decision:** `ui_layout.routePointer` composes retained command and scroll routing into one result that reports the command hit, scroll route, and current capture intent.
**Why:** Editor chrome and game UI both need one answer to "who owns this pointer frame?" as soon as controls can overlap or compete for wheel, press, drag, and release behavior. A public composed route keeps focus/capture work in one ECS-shaped API instead of growing independent editor, renderer, and scene hit-test ladders.
**Tradeoff:** The first route only distinguishes command and scroll capture. It does not yet persist capture across frames, model keyboard focus, disabled controls, hover enter/leave events, bubbling/capture phases, or text input ownership.

### 7. Route button presses through command events

**Decision:** Button entities can author a command id, and a successful release emits a one-frame command event containing the command id and source entity id. A button can optionally provide `machina.ui.hit_area` when its interaction target should differ from its visual rectangle.
**Why:** This gives scripts and future editor systems a simple ECS-native way to react to UI without embedding callbacks in scene data.
**Tradeoff:** The current event shape is intentionally small and does not yet model bubbling, capture, disabled state, modifiers, typed payloads, or persistent focus. Engine-owned editor commands may consume routed hits directly instead of emitting project-world `machina.ui.command_event` data.

### 8. Profile systems at the scheduler boundary

**Decision:** The first editor performance table uses timings captured around scheduled system dispatch and renders them through the engine-owned overlay.
**Why:** Measuring at the scheduler boundary keeps the data tied to declared ECS systems and works for human and agent debugging without script instrumentation. It follows ADR-006, ADR-007, and ADR-008.
**Tradeoff:** The table reports CPU wall time for project and engine-internal render systems. It does not yet include GPU time, parallel worker timing, flame charts, sorting, or drill-down timing history.

### 8a. Render system rows inside one retained table

**Decision:** The editor system inspector uses a scroll view containing one retained table panel. The table owns the system-id text and right-aligned rolling average duration text; system rows do not get individual panels or row divider entities.
**Why:** The system list is one table of profiling data, not a stack of separate cards. This keeps it readable in a fixed sidebar without phase prefixes, last-sample churn, or uneven overlay text.
**Tradeoff:** The compact row does not yet support sorting, filtering, grouped phases, hover detail, or expandable timing history. Reusable editor helpers currently emit retained ECS primitives, but they are not a full public widget library yet.

### 9. Expose the first layout containers as ECS data

**Decision:** Machina exposes `machina.ui.scroll_view`, `machina.ui.vbox`, `machina.ui.hgroup`, and `machina.ui.layout.item` as retained ECS components. The editor performance table and editor shell body use the same public primitives that project scenes can author.
**Why:** Smooth canvas scrolling requires target/display state, fractional content offsets that can settle between rows, frame-time animation, clipping, and explicit child ordering. Keeping that shape in ECS avoids a renderer-private layout path and gives examples, tools, and future editor surfaces the same data model.
**Tradeoff:** The first layout model is deliberately small. It has vertical stacking, horizontal groups, padding, and clipping, but not full flex/grid sizing, focus, scroll bars, virtualization, keyboard navigation, or style inheritance.

### 9a. Add a Machina-native control library shape

**Decision:** Machina expands the retained UI model with `machina.ui.stack`, `machina.ui.spacer`, `machina.ui.text_block`, `machina.ui.toggle`, `machina.ui.progress_bar`, and `machina.ui.separator` instead of adopting Godot's exact control names.
**Why:** Godot's UI model is useful inspiration: content controls, layout containers, child sizing metadata, and themeable semantic controls. Machina still needs component names and behavior that fit ECS authoring, text scenes, and future agent workflows.
**Tradeoff:** This is not a full widget toolkit yet. `grow` ratios are stored but not space-distributing; toggles do not self-mutate; text input, focus, keyboard navigation, scroll bars, style inheritance, and reusable composite widgets remain future work.

### 9b. Make canvas scale, margin, and border first-class retained data

**Decision:** Machina adds opt-in canvas fit/fill scaling, layout item margins, and rounded rect borders as ECS component fields instead of treating the UI gallery as a window-size-specific hand layout.
**Why:** The default game window is larger than the original UI examples. Retained UI needs explicit primitives for viewport adaptation and spacing so examples, editor chrome, and future tools can remain legible without per-window coordinate hacks.
**Tradeoff:** This is still a compact layout system. Margins are symmetric vec3 values, borders are uniform, and canvas scaling is per scene UI surface rather than a full responsive constraint layout.

### 9c. Allow composite controls to parent through visual primitives

**Decision:** A `machina.ui.layout.item` child may target a non-container UI rect, text, or separator parent and inherit that parent's resolved position before continuing up the parent's own layout chain.
**Why:** Button labels and similar composite controls should move with their visual parent without duplicating absolute coordinates or requiring every clickable primitive to also be a container.
**Tradeoff:** This is parent-position inheritance, not a full scene graph. It does not yet inherit style, visibility, disabled state, opacity, transform scale/rotation, or input capture.

### 9d. Split the editor shell into explicit chrome regions

**Decision:** The engine-owned editor shell uses a top bar, bottom bar, left sidebar, right sidebar, and a game viewport that fills the remaining rectangle without enforcing a fixed aspect ratio.
**Why:** The editor needs stable regions for tools as it grows. Systems belong in a dedicated inspector, component editing needs an exclusive selected-entity surface, and the game should use all area not occupied by editor chrome.
**Tradeoff:** This is still a fixed chrome layout rather than dockable panels, tabs, splitters, collapsible sidebars, or persisted editor workspace state.

### 9e. Use retained hgroups for editor splitters

**Decision:** The editor shell body is generated as a retained `machina.ui.hgroup` with left sidebar, left splitter, growable game viewport, right splitter, and right sidebar children. Dragging a splitter mutates engine-owned editor width state, and the generated hgroup resolves the resulting layout. Splitters keep a wider interaction target than their visible divider width, highlight on hover/drag, and request the platform east-west resize cursor in headful windows.
**Why:** Resizable editor regions should exercise and harden the same ECS UI layout path that projects can use. This avoids a private renderer-only layout model for one of the editor's most important surfaces.
**Tradeoff:** Splitter persistence, collapsed panels, minimum-size negotiation across nested groups, cursor styling, keyboard resizing, and user-configured workspace layouts remain future work.

### 10. Treat examples as the primitive gallery

**Decision:** The UI gallery example is the proving ground for retained UI primitives until Machina has a richer widget/layout library.
**Why:** Examples give humans and agents a concrete target for visual checks and show how text-authored UI pieces compose today.
**Tradeoff:** The gallery is not a substitute for real layout, styling, focus, text input, or reusable widget APIs.

## Related

- **ADRs:** ADR-001, ADR-004, ADR-007, ADR-008, ADR-013, ADR-020
- **FDRs:** FDR-001, FDR-002, FDR-003, FDR-007, FDR-008, FDR-009, FDR-018

## Open Questions

- What script-facing API should generate or mutate UI state for runtime tools?
- How should command ids be namespaced and routed into editor tools or engine services?
- When should focus and text input become active behavior?
- What should full keyboard state and text input look like beyond the current modifier/action edge fields?
- What exact ECS shape should grid/flex sizing, scroll bars, asymmetric margins/padding, and grow-ratio space distribution beyond `machina.ui.hgroup` use?
- How should UI containers express focus, keyboard navigation, virtualization, and style inheritance?
- What text editing capability is needed before the editor becomes practical?
- How should the editor expose system-list sorting and drill-down timing history?
- What should the first user-facing UI primitive library look like beyond raw retained ECS components?
