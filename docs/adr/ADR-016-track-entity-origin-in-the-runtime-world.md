# ADR-016: Track entity origin in the runtime world

**Date:** 2026-07-13

## Context

The editor inspects one live ECS world containing both entities declared by scene TOML and entities spawned while the project runs. Inferring origin from entity order, names, or current components would become unreliable as spawning, despawning, hot reload, and future scene editing evolve.

## Decision

Every world entity carries explicit origin metadata. Building a world from scene TOML and applying authored snapshots marks those entities as scene origin; deferred project spawn paths mark new entities as runtime origin; engine tooling uses editor origin. Origin describes the entity's current lifecycle class, not whether its component values have changed. It remains stable during ordinary simulation. The explicit stopped-mode Keep workflow may promote a runtime entity to scene origin, and duplicating an authored entity creates a new scene-origin entity.

## Consequences

The editor and persistence tools can distinguish authored, runtime, and tooling entities without heuristics. Runtime entities remain fully inspectable. World entity data grows slightly, and origin-changing operations must remain explicit authoring workflows rather than casual component mutation.
