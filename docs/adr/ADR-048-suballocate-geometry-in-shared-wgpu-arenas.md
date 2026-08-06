# ADR-048: Suballocate geometry in shared WGPU arenas

**Date:** 2026-07-31

## Context

WGPU previously created canonical vertex, canonical index, and meshlet-expanded index buffers for
every cached Geometry version. A render pass therefore had to rebind geometry buffers for every
retained geometry/material/LOD batch.

Generated imported LODs made that cost visible. GPU culling could select one level and leave the
other indirect commands empty, but the CPU still encoded one draw call for each retained alternate.
That command topology is unsuitable as the base for page-resident virtual geometry.

## Decision

WGPU owns one shared vertex arena and one shared index arena. Canonical and meshlet-expanded indices
share the index arena. A Geometry cache entry owns aligned arena ranges plus counts and the exact
resource handle/version; it does not own buffers.

Both arenas use an aligned first-fit free-range allocator. They:

- grow geometrically from a bounded initial allocation;
- preserve existing bytes with a GPU buffer copy when growth replaces the backing buffer;
- reuse a range when a changed Geometry version still fits;
- release replaced ranges only after all replacement uploads succeed;
- retire submitted ranges until asynchronous visibility completion proves their last referencing
  frame has finished on the GPU;
- coalesce released ranges and reclaim stale handles at geometry-topology invalidation boundaries.

Unchanged Geometry versions return from the cache without allocation, scanning, or upload. Stable
frames do not compact arenas. Fragmentation is accepted until a future explicit maintenance or
residency boundary can relocate data safely.

Logical residency ends when a cache entry or virtual page is evicted. Physical allocator ownership
continues while the range is retired. The visibility copy is encoded after all geometry passes, so
its mapped frame proves that every earlier arena read has finished. Eligible retired ranges can
then return to the free list. CPU frame age alone is not a GPU-lifetime guarantee.

Indirect templates store arena-global `first_index` and `base_vertex` values. On adapters with
indirect-first-instance, visibility offsets are global too. Adjacent commands with the same material
and submission policy can therefore share vertex/index bindings and one fixed multi-draw call.
Adapters without the capability use the same arenas but keep the existing per-batch bind group and
single indirect call fallback.

The structured renderer snapshot publishes logical retained batches separately from encoded draw
submissions. It also publishes vertex/index capacity and residency plus cumulative arena upload,
upload-byte, and growth counters. Bounded profiles record frame-local deltas for mutation work.

## Consequences

Geometry, imported LODs, procedural resources, meshlet commands, depth, shadow, world, and embedded
viewport drawing share one backend-owned allocation model. No public Geometry, ECS, Luau, native,
or project-file contract changes.

Compatible retained LOD commands collapse into fewer CPU-visible submissions without changing GPU
selection or indirect command counts. A backing-buffer growth copies retained data at an explicit
invalidation boundary; ordinary frames continue to bind the current arena buffers.

The allocator does not yet provide sparse pages, hierarchical cluster selection, streaming, an
eviction budget, or defragmentation. Those are follow-up virtual-geometry policies layered over this
arena ownership rather than reasons to introduce an importer-specific buffer path.
