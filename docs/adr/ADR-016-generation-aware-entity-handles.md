# ADR-016: Generation-Aware Entity Handles

**Date:** 2026-07-03

## Context

Scrapbot stores entities densely. Removing an entity can move the last entity into the removed index so entity iteration and component table storage stay compact. With index-only handles, a stale handle could accidentally refer to the moved entity after removal.

This is especially risky for Luau entity proxies. Scripts can keep a proxy in a local or upvalue, despawn the entity, and then call methods on the stale proxy later in the same invocation or a future invocation.

## Decision

Entity handles now carry an entity index plus a generation. Created entities receive nonzero generations. Runtime accessors validate nonzero generations against the entity record at the target index.

The default generation value remains `0` as a compatibility path for internal index-only call sites that intentionally perform broad world scans. Handles returned by `World.createEntity`, `World.findEntityById`, queries, script `world.spawn`, and script query proxies carry real generations.

The Luau C bridge passes generations alongside entity indices for query results, entity proxies, component proxies, mutation callbacks, and buffer-backed query views. Resolved row access validates both the row/entity relationship and the generation when present.

This does not make handles stable across entity compaction. If an entity is moved from one dense index to another, an older handle to the moved entity becomes invalid. The immediate goal is safety: stale handles must fail instead of aliasing a different live entity.

## Consequences

Stale generated handles now fail with `InvalidEntity` instead of silently reading or mutating the wrong entity.

Script proxies are safer after despawn and dense compaction, including in component proxy reads/writes and query view bulk writes.

The C ABI is wider because entity generation travels with entity index. Hot paths pay a small validation cost, but the safety property is worth it until Scrapbot has a fuller entity id/slot lifecycle model.

Future work can replace dense index handles with stable slot handles and a free list if we decide that handles should remain valid for moved entities rather than simply rejecting stale ones.
