# ADR-015: Buffer-Backed Luau Query Views

**Date:** 2026-07-03

## Context

Resolved query plans made `Query:iter(world)` cheaper, but high-cardinality Luau systems still paid a host call for every component field read and write. The `spawn_swarm` example made this visible: hundreds of animated entities spent most update time crossing the Luau/native bridge even though the data being touched was simple `f32` and `vec3` columns.

Scrapbot needs a scalable Luau hot-loop path that still uses the shared ECS runtime, scheduler access validation, and safe resolved-row checks. We do not want script systems to receive native pointers or own component storage directly.

## Decision

Scrapbot will expose explicit buffer-backed query views through typed query objects:

- `Query:view(world)` captures the current matched entity set and resolved component rows for the active system invocation.
- `view:count()` returns the captured entity count.
- `view:read_f32(component, field)` and `view:read_vec3(component, field)` bulk-copy ECS field values into Luau buffers.
- `view:write_f32(component, field, buffer)` and `view:write_vec3(component, field, buffer)` validate and bulk-copy buffer values back into ECS storage.

The view stores entity ids plus component-major resolved row arrays. ECS field data remains owned by `runtime.World`; the view is a frame-local transfer surface, not a second world or script-owned component store.

Bulk reads require declared read access. Bulk writes require declared write access and reject non-finite numeric values before mutating the world. Resolved row writes still validate that the row belongs to the target entity.

`Query:iter(world)` remains the preferred ergonomic API for ordinary systems. `Query:view(world)` is the explicit hot-loop API for large component sets where buffer offset code is justified.

## Consequences

Luau systems can amortize bridge overhead by moving contiguous `f32` and `vec3` data in bulk. In the `spawn_swarm` benchmark, the update path dropped from the earlier resolved-row baseline of roughly `0.67 ms/frame` to roughly `0.16 ms/frame` for 793 animated renderables on the current development machine, including generation-aware entity validation.

The script API now has two runtime access styles: component proxies for readability and query views for scale. Query views are less ergonomic because scripts must use byte offsets and Luau `buffer` operations, but the explicit API makes that tradeoff visible.

The first view surface is intentionally narrow. It supports `f32` and `vec3`, which are the current hot-path fields. Integer, boolean, string, or future native component storage views should be added only when a real workload needs them.

The C ABI and Luau declaration file grow with view callbacks and buffer-typed APIs. Future work should reduce remaining per-call allocations in the bridge where measurable, and should eventually align this view path with deferred structural mutation and hybrid Luau/Zig systems.
