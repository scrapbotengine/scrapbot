# FDR-017: Shadow Components

**Status:** Active
**Last reviewed:** 2026-07-02

## Overview

Shadow components let scene authors opt renderable entities into casting and receiving shadows using ECS component data. They make early lighting behavior explicit, text-authored, and compatible with the renderer's scene-world batching path.

## Behavior

- Scene entities can add `scrapbot.shadow.caster` to make a renderable participate in the shadow map.
- Scene entities can add `scrapbot.shadow.receiver` to make a renderable sample the shadow map during lighting.
- The components are marker components with no fields.
- Shadow casting and receiving are independent; an entity may cast, receive, both, or neither.
- The current renderer supports shadows from the first directional light.
- Shadow receivers keep ambient lighting and darken only the direct-light contribution where occluded.
- The spawn swarm example uses a static receiver floor and animated caster objects.
- Legacy cube renderables can use the shadow marker components after being normalized to box geometry.

## Design Decisions

### 1. Use ECS marker components

**Decision:** Shadow behavior is expressed with `scrapbot.shadow.caster` and `scrapbot.shadow.receiver` marker components.
**Why:** This mirrors familiar `castShadow`/`receiveShadow` authoring while staying aligned with Scrapbot's component-first scene model. It follows ADR-008 and ADR-022.
**Tradeoff:** Component presence is all-or-nothing for now; per-object shadow bias, opacity, and quality controls remain future work.

### 2. Start with directional-light shadow mapping

**Decision:** The first implementation renders a depth shadow map from the active directional light.
**Why:** Directional lights are the only scene-authored light type today, and a single depth map gives immediate visual feedback without introducing a full light/shadow asset model.
**Tradeoff:** Point-light, spot-light, cascaded, contact, and soft-shadow behavior are not covered yet.

### 3. Keep shadows inside render batching

**Decision:** Shadow markers participate in render batch keys resolved from scene-world renderable data.
**Why:** Caster and receiver behavior affects render passes, so the renderer must not merge entities whose shadow state requires different treatment. This follows FDR-016.
**Tradeoff:** Some entities with identical geometry and per-instance material color may split into separate batches when their shadow flags differ.

## Related

- **ADRs:** ADR-004, ADR-008, ADR-022
- **FDRs:** FDR-002, FDR-007, FDR-008, FDR-014, FDR-015, FDR-016

## Open Questions

- Should shadow quality, map size, bias, and strength become project settings or per-light/per-receiver data?
- When should the renderer add cascaded directional shadows for larger scenes?
