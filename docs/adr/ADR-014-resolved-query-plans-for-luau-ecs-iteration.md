# ADR-014: Resolved Query Plans for Luau ECS Iteration

**Date:** 2026-07-03

## Context

Luau systems commonly run tight ECS loops through `Query:iter(world)`. The public API is ergonomic, but the bridge was repeatedly resolving component ids and entity rows while iterating. That work is redundant because a query's component set is stable for the iterator.

Machina needs to improve script hot-loop performance without exposing raw native pointers to Luau, bypassing scheduler access validation, or making stored script proxies unsafe after structural mutation.

## Decision

Machina will prepare Luau query iterators into resolved runtime plans. A prepared plan resolves component ids to component table indices once, chooses the smallest table as the query driver once, and returns component row indices alongside each yielded entity.

Component proxies still expose the same Luau field API. Internally, resolved proxies carry entity identity plus table/row coordinates. Runtime field access validates that the cached row still belongs to the requested entity and falls back through the sparse entity-to-row map if a row moved.

The bridge will not add a global field-index cache for component proxy fields yet. A query-local field-index cache was tested and regressed the `spawn_swarm` workload because the cache overhead exceeded the small column-name scan it replaced.

## Consequences

`Query:iter(world)` keeps the existing Luau ergonomics while doing less repeated host lookup work in hot systems.

The C ABI between Luau and Zig now has prepared-query and resolved-field callbacks, increasing bridge complexity. The old string-based query and field callbacks remain available for low-level compatibility paths.

Resolved rows are not raw pointers and are validated before use, so structural mutation should not silently redirect a proxy to the wrong entity. Deferred command buffers, generation-safe entity handles, chunked/archetype storage, and bulk field access remain future work.
