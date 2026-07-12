# FDR-007: ECS UI

**Status:** Active
**Last reviewed:** 2026-07-12

## Overview

ECS UI lets projects describe screen-space interfaces with ordinary entities and engine-provided components. The engine synchronizes those components into retained hierarchy and paint state so UI follows entity appearance, disappearance, and world replacement without requiring projects to manage renderer objects.

## Behavior

- Scene entities can carry UI layout and bitmap-text components.
- UI entities form a parent-by-name hierarchy validated when the scene loads.
- Layout supports overlay, row, and column parents with pixel position, size, padding, and gap values.
- Panels support RGBA backgrounds, and text supports RGBA color and pixel size.
- The engine reconciles alive UI entities after frame systems and removes retained nodes when their entities disappear.
- WGPU paints UI after world geometry, including in headless framegrabs.
- UI rendering does not require a world camera or renderable geometry.
- The built-in monogram font is embedded and redistributed under CC0.

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

**Decision:** Use top-left pixel coordinates and explicit sizes with overlay, row, and column flow.
**Why:** This is deterministic, easy to validate in framegrabs, and sufficient to prove hierarchy and text before responsive sizing becomes necessary.
**Tradeoff:** There is no canvas scaling, percentage sizing, clipping, scrolling, alignment, or content measurement yet.

### 4. Embed one permissive pixel font

**Decision:** Bake the CC0 monogram font into an ASCII atlas at runtime and sample it with nearest filtering.
**Why:** Scrapbot needs dependable text in packaged games and agent framegrabs without system-font discovery or platform font APIs.
**Tradeoff:** The first text path is ASCII-only and does not provide shaping, fallback, localization, or user-supplied fonts.

## Related

- **ADRs:** ADR-003
- **FDRs:** FDR-002, FDR-003, FDR-005

## Open Questions

- What Luau mutation API best preserves ECS scheduling and deferred structural changes?
- Should responsive sizing stay component-based or use a separate style resource?
- When should bitmap text gain shaping, font fallback, and glyph-atlas streaming?
