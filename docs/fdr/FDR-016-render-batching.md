# FDR-016: Render Batching

**Status:** Active
**Last reviewed:** 2026-07-02

## Overview

Render batching lets Scrapbot draw many scene-authored entities that share compatible geometry and pipeline-affecting render state as a single instanced render batch. It keeps the ECS authoring model simple while giving renderer internals a scalable path for scenes with repeated objects.

## Behavior

- Projects author normal renderable ECS entities with transform, geometry, and material component data.
- The renderer automatically groups renderable entities that use the same built-in geometry primitive settings and compatible pipeline-affecting state.
- Each render batch preserves per-entity transform and base color through instance data.
- Current base-color-only material data does not split batches.
- Shadow caster/receiver state participates in render batch compatibility.
- The render schedule prepares one instanced draw per batch, not one draw per renderable entity.
- Legacy cube renderables participate in batching after being normalized to box geometry and material data.
- The spawn swarm example contains hundreds of script-spawned renderables while still collapsing into a few render batches.
- The batching animation fixture covers animated scene entities that collapse into a small number of render batches.
- Offscreen render verification covers the spawn swarm example as part of the standard test suite.
- Headless benchmark output reports renderable and render-batch counts so batching regressions are visible without opening a window.

## Design Decisions

### 1. Batch below the scene authoring surface

**Decision:** Scene authors continue to create independent ECS entities; batching is an automatic renderer behavior.
**Why:** Authoring, scripting, live reload, and editor tooling should reason about real entities, not renderer optimization groups. This follows ADR-008 and ADR-022.
**Tradeoff:** The renderer must rebuild or validate batch plans when renderable scene data changes.

### 2. Keep per-instance material data out of the key

**Decision:** The current batching key is built-in primitive parameters plus shadow caster/receiver state. Base color is per-instance data and does not split batches.
**Why:** Base color is already carried through the instance buffer, so splitting otherwise-compatible renderables by color creates unnecessary batches without changing visual output. This follows FDR-015 and FDR-017.
**Tradeoff:** Future material properties, mesh assets, textures, and shader variants that affect buffers, bindings, or pipelines will need to become part of the key before they can batch safely.

### 3. Draw from prepared batch plans

**Decision:** Batches are planned during render preparation from a frame renderable snapshot and drawn directly from that plan plus renderer-owned GPU resources.
**Why:** Render submission should not create ECS draw-command entities in a cloned render world when the batch plan already contains the ordered draw set. This follows ADR-022.
**Tradeoff:** GPU buffers remain renderer-owned side resources until Scrapbot has explicit native/internal component storage for non-serializable values.

### 4. Plan batches from a one-pass renderable snapshot

**Decision:** Render preparation snapshots the frame's renderable data once and builds batch membership from that snapshot.
**Why:** Large ECS-authored scenes should scale with the number of renderables, not with repeated world scans per renderable or per instance. This keeps automatic batching practical for script-spawned scenes.
**Tradeoff:** The renderer owns a short-lived per-frame copy of renderable data during preparation.

## Related

- **ADRs:** ADR-004, ADR-008, ADR-022
- **FDRs:** FDR-007, FDR-008, FDR-009, FDR-015, FDR-017

## Open Questions

- How should mesh asset identifiers, material assets, textures, and shader variants extend the batching key?
- Should render diagnostics expose per-batch instance counts, geometry keys, and pipeline keys for editor inspection?
