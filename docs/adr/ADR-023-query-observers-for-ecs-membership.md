# ADR-023: Query Observers for ECS Membership

**Date:** 2026-07-06

## Context

Scrapbot's renderer and editor UI now share the authoritative scene world, but some engine subsystems still need to react to ECS structure changing without rebuilding dense derived state every frame. Structural event journals expose entity/component additions and removals, but consumers that care about a full component set need a retained membership layer that can report when an entity starts or stops matching a query.

The runtime must preserve generation-aware handles and dense-index compaction safety. A removed entity can move another live entity to a different dense index, so observers cannot rely only on cached handles when reconciling membership after removals.

## Decision

The runtime provides `QueryObserver`, a reusable observer for a fixed component-id set. A query observer owns a retained membership snapshot and reports three views after `refresh(world)`: current members, entities that appeared since the previous refresh, and entities that disappeared since the previous refresh.

Observers consume the world's structural event journal incrementally when component additions/removals can be reconciled by handle. When the journal has been cleared or an entity removal may have compacted dense indices, the observer performs a full query diff against entity ids, repairs live handles, and emits only the resulting membership deltas.

`reset(world)` seeds the retained membership snapshot without emitting appeared or disappeared deltas, letting a subsystem start observing an already-running world. Engine-transient frame entities remain outside structural events, so observers are intended for persistent scene/runtime structure rather than per-frame overlay churn.

## Consequences

- Engine systems can keep retained side data in sync with ECS query membership instead of rescanning whole worlds every frame.
- Consumers can observe component-set appearance/disappearance without per-entity callbacks or a second ECS model.
- Entity removals are safe across dense compaction because observers reconcile by stable entity id when needed.
- Query observers still depend on structural events, so consumers that clear journals must coordinate with observers or expect the next refresh to perform a full diff.
- Field-level change tracking remains outside this decision; observers report structural membership changes only.
