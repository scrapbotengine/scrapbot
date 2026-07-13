# ADR-016: Track entity origin in the runtime world

**Date:** 2026-07-13

## Context

The editor inspects one live ECS world containing both entities declared by scene TOML and entities spawned while the project runs. Inferring origin from entity order, names, or current components would become unreliable as spawning, despawning, hot reload, and future scene editing evolve.

## Decision

Every world entity carries immutable origin metadata for its lifetime. Building a world from scene TOML marks those entities as scene-authored; all deferred runtime spawn paths mark new entities as runtime-spawned. Origin describes how an entity entered the current world, not whether its components have changed since then.

## Consequences

The editor and future persistence tools can distinguish authored and ephemeral entities without heuristics. Runtime entities remain fully inspectable. World entity data grows slightly, and any future operation that promotes a runtime entity into scene data must create an explicit authoring workflow rather than mutating origin casually.
