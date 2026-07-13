# FDR-007: ECS UI

**Status:** Active
**Last reviewed:** 2026-07-13

## Overview

ECS UI lets projects describe screen-space interfaces with ordinary entities and engine-provided components. The engine synchronizes those components into retained hierarchy and paint state so UI follows entity appearance, disappearance, and world replacement without requiring projects to manage renderer objects.

## Behavior

- Every UI entity describes a rectangular box with an explicit size, optional position, per-edge margin and padding, background color, and corner radius.
- UI entities form a parent-by-name hierarchy validated when the scene loads.
- Horizontal and vertical stack components arrange child boxes in scene order with a configurable gap; boxes without a stack component overlay their children.
- Every element receives retained hover and active state from topmost pointer hit testing. Active state is captured on primary-button press and held until release.
- Text and button controls provide labels with RGBA color and pixel size. Buttons consume generic element state with optional hover and active background and text colors.
- Backgrounds use GPU-evaluated signed-distance rounded rectangles, including square corners at a zero radius.
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
**Tradeoff:** The first implementation has fixed node/paint limits and recomputes layout each frame.

### 3. Start with fixed screen-space pixels

**Decision:** Use top-left pixel coordinates and explicit sizes with overlay, horizontal-stack, and vertical-stack flow.
**Why:** This is deterministic, easy to validate in framegrabs, and sufficient to prove hierarchy and text before responsive sizing becomes necessary.
**Tradeoff:** There is no canvas scaling, percentage sizing, clipping, scrolling, alignment, or content measurement yet.

### 4. Compose controls from a shared box model

**Decision:** Keep geometry and visual box styling in one layout component, then add independent stack, text, and button components to an entity.
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

## Related

- **ADRs:** ADR-003, ADR-013, ADR-014
- **FDRs:** FDR-002, FDR-003, FDR-005, FDR-008

## Open Questions

- What Luau mutation API best preserves ECS scheduling and deferred structural changes?
- What command-event API should report release-inside button activation?
- Should responsive sizing stay component-based or use a separate style resource?
- When should text gain shaping, font fallback, and glyph-atlas streaming?
