# ADR-013: Shared ECS for Engine-Internal Worlds

**Date:** 2026-07-02

**Status:** Superseded by [ADR-022](ADR-022-single-world-render-data-flow.md).

## Context

Scrapbot's game state, scenes, scripts, tests, and future editor already use one entity-component-system runtime. Rendering originally read scene components directly and kept renderer-specific object arrays as the effective draw model. That would create a second, informal ECS if internal engine paths grew separate storage, scheduling, and query rules.

The renderer still needs backend-owned resources such as `wgpu` buffers, bind groups, textures, and pipelines. Those handles should not become user-authored scene data or script-visible component fields, but the data flow that decides what gets rendered should still use the engine ECS model.

## Decision

Scrapbot uses the same `runtime.World`, `runtime.ComponentRegistry`, and `runtime.SystemSchedule` implementation for engine-internal worlds as it uses for game worlds.

The renderer owns a render world and a render-phase schedule. Each frame, render systems extract renderable scene data from the game world into the render world, prepare renderer resources, queue draw-command entities, and draw by querying that render world.

Engine-internal render components and systems use reserved `scrapbot.*` type ids. Backend handles remain renderer-owned side resources until Scrapbot has explicit native/internal component storage with lifecycle rules for non-serializable values.

Render systems are profiled at the render scheduler boundary and exposed to the same editor performance overlay stream as project systems. The overlay currently displays render timings from the last completed frame alongside current project system timings.

## Consequences

- Engine subsystems can have separate worlds without creating separate ECS implementations.
- Render extraction, preparation, queueing, and drawing can use the same system access declarations and scheduling rules as game logic.
- Runtime tooling can inspect engine-internal system costs without a separate profiling model.
- Scene-authored data remains text-based and serializable, while backend handles stay outside project files and scripting APIs.
- The renderer now has a clear path toward native/internal components for GPU resources instead of ad hoc object lists.
- The current implementation still has a GPU-resource sidecar, so not every renderer-owned value is an ECS component yet.
