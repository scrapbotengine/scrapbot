# FDR-005: Engine UI Primitives

**Status:** Active
**Last reviewed:** 2026-07-04

## Overview

Engine UI primitives provide the controls and layout capabilities needed for runtime overlays, debug tools, and the future editor. They exist so Machina can build tooling with its own scene model, renderer, and input systems instead of depending on a separate editor application stack.

## Behavior

- The engine can render text-authored UI overlays in offscreen renders and interactive windows.
- Scene entities can define a UI canvas, screen-space colored rectangles, rounded borders, fixed-pixel text labels, button markers, button command ids, scroll views, vertical stacks, direction-aware stacks, layout child metadata, spacers, text blocks, toggles, progress bars, and separators.
- `machina.ui.canvas` stores `design_size` and `scale_mode`. `scale_mode = "none"` preserves raw screen pixels. `scale_mode = "fit"` scales and centers scene-authored UI into the current scene UI target while preserving aspect ratio. `scale_mode = "fill"` scales enough to cover that target. The target is the full window in normal runs and the editor game viewport while the editor shell is visible.
- UI rectangles use screen-space positions and sizes with a top-left origin, plus an optional `corner_radius` field in pixels. Missing `corner_radius` values default to `0.0` for compatibility with older scene data.
- UI rectangle corners render through the UI shader using rounded-rectangle SDF coverage with alpha blending. Text glyph quads use the same UI pipeline with `corner_radius = 0.0`.
- `machina.ui.border` adds a data-authored border to a rect with `color` and `thickness`. Borders render through the same rounded-rectangle SDF path by drawing an outer rounded rect and an inset fill rect.
- UI text labels use screen-space positions with a top-left origin.
- The first UI demo uses a subdued dark Tailwind-derived palette: near-black workspaces, slate panels, muted cyan structure accents, restrained semantic control colors, and high-contrast but not pure-white text.
- Button markers derive hover, held, and pressed interaction state in headful runs and use that state for button visuals.
- UI interaction consumes transient `machina.input.*` ECS resources instead of reading raw platform events directly.
- Releasing the primary pointer over a command button emits a transient ECS command event that Luau systems can consume during the same frame.
- Headful runs can toggle the engine-owned editor/debug overlay with Ctrl+Tab.
- Headful runs hide the engine-owned editor/debug overlay by default; `machina run --editor` starts with it visible.
- The first engine-owned editor/debug shell displays current FPS beside the rendered scene.
- In editor mode, 3D scene content and scene-authored game UI render into a dedicated 16:9 game viewport. Editor chrome renders outside that viewport, currently in a right sidebar.
- The engine-owned editor/debug shell also hosts the first editor playback controls and selected-entity inspector; detailed behavior is tracked in FDR-018.
- When live system profiling data is available, the editor/debug overlay lists active systems with their full system id and rolling average runtime over the current profiling window.
- The editor/debug overlay also lists engine-internal render systems profiled through the render ECS schedule.
- The visible performance table updates at a throttled human-readable cadence while profiling continues to sample scheduled systems every frame.
- The system performance view uses compact fixed-width rows and a scene-shaped clipped smooth-scroll viewport so long system lists remain legible and every system can be reached without inline pagination text.
- While the editor/debug overlay is visible, mouse wheel input scrolls the visible system viewport when the system list overflows. Scroll state uses a target pixel offset plus an animated visible pixel offset, and wheel distance is intentionally independent from row height so content can settle between rows.
- The UI gallery example demonstrates the retained primitive set with panels, text, buttons, command events, scroll views, vertical stacks, horizontal stacks, spacers, centered text blocks, toggles, progress bars, separators, and script-mutated UI state.
- `machina.ui.scroll_view` defines a screen-space viewport with `position`, `size`, and `content_offset` fields. Descendants are offset by `content_offset` and clipped to the viewport.
- In live headful runs, scene-authored scroll views under the pointer update their `content_offset` from mouse wheel input before project update systems run.
- `machina.ui.vbox` defines a vertical stack origin and spacing. Direct children are ordered by `machina.ui.layout.item.order` and stacked by their current primitive height.
- `machina.ui.stack` defines a direction-aware stack origin, spacing, direction, and padding. Supported directions are `vertical`, `column`, `horizontal`, and `row`.
- `machina.ui.layout.item` attaches an entity to a parent entity id and gives it integer order, minimum size, grow ratio, cross-axis alignment metadata, and symmetric x/y/z margin. Parent ids are stable scene entity ids, not dense runtime handles. Grow ratios are stored and validated but do not redistribute extra space yet.
- `machina.ui.spacer` participates in layout without rendering.
- `machina.ui.text_block` gives a text entity a content box and horizontal/vertical `start`, `center`, or `end` alignment.
- `machina.ui.toggle` stores checked state and influences button/rect visuals. It does not yet toggle itself automatically; scripts or editor systems own state mutation.
- `machina.ui.progress_bar` stores value, max, and fill color. It renders as a fill inside the entity's rect.
- `machina.ui.separator` renders a thin semantic divider through the same UI vertex path as rectangles.
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

**Decision:** Platform input is translated into transient `machina.input.pointer`, `machina.input.keyboard`, and `machina.input.frame` ECS resources. UI button visuals are derived by render-phase ECS systems, and command events are emitted into the live project world before update systems run.
**Why:** This keeps UI behavior aligned with the engine-wide ECS model, follows ADR-020, and avoids a separate immediate-mode renderer input channel.
**Tradeoff:** Command routing is string-id based for now; richer action payloads, focus, text input, and editor service dispatch still need later design.

### 6a. Resolve retained layout for scene UI input

**Decision:** Project UI input routing resolves `scroll_view`, `vbox`, `stack`, and `layout.item` before hit-testing command buttons or scrolling viewports.
**Why:** Scene-authored controls can be local to layout containers, so raw component positions are not authoritative screen positions. Rendering, command events, and scroll interaction must agree on the retained layout model.
**Tradeoff:** Layout resolution currently exists in both render and live-project input paths. A shared UI layout module should replace that duplication when the layout model grows further.

### 7. Route button presses through command events

**Decision:** Button entities can author a command id, and a successful release emits a one-frame command event containing the command id and source entity id.
**Why:** This gives scripts and future editor systems a simple ECS-native way to react to UI without embedding callbacks in scene data.
**Tradeoff:** The current event shape is intentionally small and does not yet model bubbling, capture, disabled state, modifiers, or typed payloads.

### 8. Profile systems at the scheduler boundary

**Decision:** The first editor performance table uses timings captured around scheduled system dispatch and renders them through the engine-owned overlay.
**Why:** Measuring at the scheduler boundary keeps the data tied to declared ECS systems and works for human and agent debugging without script instrumentation. It follows ADR-006, ADR-007, and ADR-008.
**Tradeoff:** The table reports CPU wall time for project and engine-internal render systems. It does not yet include GPU time, parallel worker timing, flame charts, sorting, or drill-down timing history.

### 9. Expose the first layout containers as ECS data

**Decision:** Machina exposes `machina.ui.scroll_view`, `machina.ui.vbox`, and `machina.ui.layout.item` as retained ECS components. The editor performance table uses the same public primitives that project scenes can author.
**Why:** Smooth canvas scrolling requires target/display state, fractional content offsets that can settle between rows, frame-time animation, clipping, and explicit child ordering. Keeping that shape in ECS avoids a renderer-private layout path and gives examples, tools, and future editor surfaces the same data model.
**Tradeoff:** The first layout model is deliberately small. It has vertical stacking and clipping, but not hbox, flex/grid sizing, padding, focus, scroll bars, virtualization, keyboard navigation, or style inheritance.

### 9a. Add a Machina-native control library shape

**Decision:** Machina expands the retained UI model with `machina.ui.stack`, `machina.ui.spacer`, `machina.ui.text_block`, `machina.ui.toggle`, `machina.ui.progress_bar`, and `machina.ui.separator` instead of adopting Godot's exact control names.
**Why:** Godot's UI model is useful inspiration: content controls, layout containers, child sizing metadata, and themeable semantic controls. Machina still needs component names and behavior that fit ECS authoring, text scenes, and future agent workflows.
**Tradeoff:** This is not a full widget toolkit yet. `grow` ratios are stored but not space-distributing; toggles do not self-mutate; text input, focus, keyboard navigation, scroll bars, style inheritance, and reusable composite widgets remain future work.

### 9b. Make canvas scale, margin, and border first-class retained data

**Decision:** Machina adds opt-in canvas fit/fill scaling, layout item margins, and rounded rect borders as ECS component fields instead of treating the UI gallery as a window-size-specific hand layout.
**Why:** The default game window is larger than the original UI examples. Retained UI needs explicit primitives for viewport adaptation and spacing so examples, editor chrome, and future tools can remain legible without per-window coordinate hacks.
**Tradeoff:** This is still a compact layout system. Margins are symmetric vec3 values, borders are uniform, and canvas scaling is per scene UI surface rather than a full responsive constraint layout.

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
- What exact ECS shape should grid/flex sizing, scroll bars, asymmetric margins/padding, and grow-ratio space distribution use?
- How should UI containers express focus, keyboard navigation, virtualization, and style inheritance?
- What text editing capability is needed before the editor becomes practical?
- How should the editor expose system-list sorting and drill-down timing history?
- What should the first user-facing UI primitive library look like beyond raw retained ECS components?
