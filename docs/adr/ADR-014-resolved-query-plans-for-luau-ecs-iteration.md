# ADR-014: Resolved Query Plans for Luau ECS Iteration

**Date:** 2026-07-03

## Context

Luau systems commonly run tight ECS loops through `Query:iter(world)`. The public API is ergonomic, but the bridge was repeatedly resolving component ids and entity rows while iterating. That work is redundant because a query's component set is stable for the iterator.

Scrapbot needs to improve script hot-loop performance without exposing raw native pointers to Luau, bypassing scheduler access validation, or making stored script proxies unsafe after structural mutation.

## Decision

Scrapbot will prepare Luau query iterators into resolved runtime plans. A prepared plan resolves component ids to component table indices once, chooses the smallest table as the query driver once, and returns component row indices alongside each yielded entity.

Component proxies still expose the same Luau field API. Internally, resolved proxies carry entity identity plus table/row coordinates. Runtime field access validates that the cached row still belongs to the requested entity and falls back through the sparse entity-to-row map if a row moved.

Reusable typed query objects will also own a hidden persistent plan. `Query:iter(world)` and `Query:view(world)` reuse that plan when it was prepared for the same active world and the same world query-plan generation. The world increments that generation when a new component table appears, so an empty plan can recover if a system creates the queried component type later. Component table indices are append-only, so ordinary component membership churn does not invalidate the table-index part of a plan.

The bridge will not add a global field-index cache for component proxy fields yet. A query-local field-index cache was tested and regressed the `spawn_swarm` workload because the cache overhead exceeded the small column-name scan it replaced.

## Consequences

`Query:iter(world)` keeps the existing Luau ergonomics while doing less repeated host lookup work in hot systems.

The C ABI between Luau and Zig now has prepared-query and resolved-field callbacks, increasing bridge complexity. The old string-based query and field callbacks remain available for low-level compatibility paths.

Persistent query object plans remove repeated component id-to-table resolution from recurring script systems. The plan cache is scoped by active world pointer and query-plan generation, not by global component id alone.

Resolved rows are not raw pointers and are validated before use, so structural mutation should not silently redirect a proxy to the wrong entity. Buffer-backed query views now cover explicit `f32` and `vec3` bulk field access, and generation-aware handles now prevent stale generated proxies from aliasing compacted entities. Deferred command buffers, stable slot handles, chunked/archetype storage, broader field view support, and hybrid native hot systems remain future work.
