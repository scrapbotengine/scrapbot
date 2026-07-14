# FDR-007: ECS UI

**Status:** Active
**Last reviewed:** 2026-07-14

## Overview

ECS UI lets projects describe screen-space interfaces with ordinary entities and engine-provided components. The engine synchronizes those components into retained hierarchy and paint state so UI follows entity appearance, disappearance, and world replacement without requiring projects to manage renderer objects.

## Behavior

- Every UI entity describes a rectangular box with an explicit size, optional position, per-edge margin and padding, background color, SDF border color and width, corner radius, and hidden state.
- A hidden box removes its complete descendant subtree from retained layout, painting, and pointer interaction without despawning any entities.
- UI entities form a parent-by-name hierarchy validated when the scene loads.
- Horizontal and vertical stack components arrange child boxes in scene order with a configurable gap; boxes without a stack component overlay their children. Fill stacks treat child sizes as proportions, fill the cross-axis, and can expose draggable separators with minimum pane sizes.
- Table containers arrange children in row-major order across 1–64 equal-width columns, with independent column and row gaps. A partial final row remains left aligned.
- Panel decoration adds an optional title band with its own text and background styling and reserves that band above nested content. Panels can compose with overlay, stack, or table layout.
- Scroll-area containers accept an explicitly oversized child pane, clip descendants to their padded content rectangle, and smoothly approach wheel-driven vertical offsets.
- Nested scroll clips intersect, the topmost hovered scroll area receives wheel input, and overflowing areas render a proportional scrollbar.
- Every element receives retained hover and active state from topmost pointer hit testing. Active state is captured on primary-button press and held until release.
- Text and button controls provide labels with RGBA color and pixel size. Buttons consume generic element state with optional hover and active background and text colors.
- Single-line input controls store authored text in their ECS component while the retained UI state owns focus, cursor, selection, horizontal reveal, and blink state. Clicking selects all text.
- Focused inputs accept typed text, Left/Right/Home/End cursor movement, Shift-extended selection, Backspace/Delete, and Select All. Tab and Shift+Tab traverse inputs in paint order; Enter commits and leaves the field, while Escape restores the value present when focus began.
- Backgrounds and inset borders use GPU-evaluated signed-distance rounded rectangles, including square corners at a zero radius.
- The engine reconciles alive UI entities after frame systems and removes retained nodes when their entities disappear.
- WGPU paints UI after world geometry, including in headless framegrabs.
- UI rendering does not require a world camera or renderable geometry.
- The built-in Inter font is embedded and redistributed under the SIL Open Font License 1.1.
- Text uses a precomputed MTSDF atlas and derivative-based GPU antialiasing, so one atlas remains sharp across UI text sizes.

## Design Decisions

### 1. Keep UI authoring in the ECS

**Decision:** Represent public UI state as engine-provided components on ordinary entities.
**Why:** UI lifecycle then follows the same scene loading, world replacement, entity generation, and future command-buffer behavior as gameplay state.
**Tradeoff:** Hierarchical layout needs a synchronization layer because ECS component storage is not itself an ordered tree.

### 2. Maintain retained derived state

**Decision:** An engine-owned reconciliation step tracks eligible entities, resolves their hierarchy, computes layout, and emits a bounded paint list.
**Why:** Renderers need ordered, resolved rectangles and glyphs rather than repeated ECS queries or project-owned GPU handles.
**Tradeoff:** The implementation has fixed node/paint limits and recomputes layout each frame. The same reconciler maintains distinct project and transient editor UI coordinate and interaction domains.

### 3. Use explicit pixels with opt-in proportional fill

**Decision:** Use top-left pixel coordinates and explicit sizes with overlay, horizontal-stack, and vertical-stack flow. A stack can opt into fill layout, where authored child sizes seed proportional weights and each child fills the cross-axis. Fill stacks may make their gaps draggable and enforce a shared minimum pane size.
**Why:** Fixed boxes remain deterministic, while an explicit fill policy supports responsive application and editor layouts without introducing a complete constraint language.
**Tradeoff:** There is no percentage syntax, alignment, automatic content measurement, per-child grow policy, or horizontal scrolling yet. Split weights are retained runtime state rather than scene data.

### 4. Compose controls from a shared box model

**Decision:** Keep geometry and visual box styling in one layout component, then add independent stack, table, panel, text, button, and input components to an entity.
**Why:** A shared box model makes margins, padding, backgrounds, and rounded corners consistent while ECS composition keeps layout and content roles explicit. See ADR-014.
**Tradeoff:** Invalid combinations require scene validation. Buttons expose visual press feedback, but activation commands still await the UI event system.

### 5. Keep pointer state generic and derived

**Decision:** Hit-test all retained element boxes and store hover and active state on the retained nodes; controls decide whether and how to consume those states.
**Why:** Pointer interaction is a property of an element's screen area, not of a button. This lets future controls reuse one topmost-hit and press-capture model. See ADR-014.
**Tradeoff:** Interaction state is currently renderer-owned derived state and is not yet queryable or mutable through the public ECS APIs.

### 6. Embed one screen-oriented scalable font

**Decision:** Precompute an MTSDF atlas for Inter with `msdf-atlas-gen` and reconstruct glyph coverage in the UI shader.
**Why:** Scrapbot needs dependable text in packaged games and agent framegrabs without system-font discovery or platform font APIs.
**Tradeoff:** The first text path is ASCII-only and does not provide shaping, fallback, localization, kerning, or user-supplied fonts. Regenerating the built-in font requires the external atlas compiler.

### 7. Keep smooth scrolling derived and clip paint on the GPU

**Decision:** Author scroll speed and smoothness in an ECS component, but retain current and target offsets on the reconciled node. Intersect descendant clips during layout and enforce them per fragment in the WGPU UI shader.
**Why:** Authored components stay declarative, smoothing survives normal frame reconciliation, pointer and paint clipping share one rectangle, and nested areas preserve the ordered paint stream. See ADR-020.
**Tradeoff:** Scroll position is not yet queryable or controllable through public ECS APIs, and per-fragment discard adds modest shader work.

### 8. Keep panels decorative and tables structural

**Decision:** Let `ui_panel` reserve and paint a title band without becoming a flow container, while `ui_table` owns row-major child placement with equal-width columns.
**Why:** Panels should compose around any nested layout, while tables need a generic 1–N column primitive rather than inspector-specific field rendering.
**Tradeoff:** Column proportions, spanning, headers, and automatic row measurement are deferred; authored child height determines each row's height.

### 9. Retain editing state while keeping values in the ECS

**Decision:** Store an input's current text and styling in its public ECS component, but retain transient focus, cursor, selection, original value, horizontal offset, and caret blink state in the UI reconciler.
**Why:** Systems and tools can observe the value through the ordinary world while frame-local interaction survives reconciliation without polluting scene data.
**Tradeoff:** This first control is single-line and ASCII-only. It does not yet provide clipboard operations, IME composition, Unicode shaping, multiline editing, validation events, or a public commit/change event API.

## Related

- **ADRs:** ADR-003, ADR-013, ADR-014, ADR-020
- **FDRs:** FDR-002, FDR-003, FDR-005, FDR-008

## Open Questions

- What Luau mutation API best preserves ECS scheduling and deferred structural changes?
- What command-event API should report release-inside button activation?
- When should text gain shaping, font fallback, and glyph-atlas streaming?
