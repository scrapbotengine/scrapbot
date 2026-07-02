# FDR-016: Render Batching

**Status:** Active
**Last reviewed:** 2026-07-02

## Overview

Render batching lets Machina draw many scene-authored entities that share the same geometry and material as a single instanced render batch. It keeps the ECS authoring model simple while giving renderer internals a scalable path for scenes with repeated objects.

## Behavior

- Projects author normal renderable ECS entities with transform, geometry, and material component data.
- The renderer automatically groups renderable entities that use the same built-in geometry primitive settings and material base color.
- Each render batch preserves per-entity transform and material color through instance data.
- Shadow caster/receiver state participates in render batch compatibility.
- The render schedule queues one internal draw command per batch, not one command per renderable entity.
- Legacy cube renderables participate in batching after being normalized to box geometry and material data.
- The batching demo example contains many independent animated scene entities that collapse into a small number of render batches.
- Offscreen render verification covers the batching demo as part of the standard test suite.

## Design Decisions

### 1. Batch below the scene authoring surface

**Decision:** Scene authors continue to create independent ECS entities; batching is an automatic renderer behavior.
**Why:** Authoring, scripting, live reload, and editor tooling should reason about real entities, not renderer optimization groups. This follows ADR-008 and ADR-013.
**Tradeoff:** The renderer must rebuild or validate batch plans when renderable scene data changes.

### 2. Batch by geometry and material keys first

**Decision:** The first batching key is built-in primitive parameters, base-color material data, and shadow caster/receiver state.
**Why:** These are the render states Machina currently supports, and they map cleanly to shared vertex/index buffers plus per-instance transforms, colors, and shadow behavior. This follows FDR-015 and FDR-017.
**Tradeoff:** Future material properties, mesh assets, textures, and pipeline state will need to become part of the key before they can batch safely.

### 3. Keep batching inside the render ECS schedule

**Decision:** Batches are planned during render preparation and queued as internal render-world draw command entities.
**Why:** Renderer data flow should keep using Machina's shared ECS scheduler instead of reintroducing an ad hoc object list. This follows ADR-013.
**Tradeoff:** GPU buffers remain renderer-owned side resources until Machina has explicit native/internal component storage for non-serializable values.

## Related

- **ADRs:** ADR-004, ADR-008, ADR-013
- **FDRs:** FDR-007, FDR-008, FDR-009, FDR-015, FDR-017

## Open Questions

- How should mesh asset identifiers, material assets, textures, and shader variants extend the batching key?
- Should render diagnostics expose batch counts and instance counts for profiling and editor inspection?
