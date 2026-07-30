# ADR-046: Store meshlets with geometry resources

**Date:** 2026-07-30

## Context

Scrapbot's GPU-driven renderer culls and submits complete geometry/material/LOD batches. Large
primitives therefore remain one visibility unit even when most of their triangles are outside the
view or hidden.

Mesh shaders are not part of Scrapbot's current WebGPU baseline. The pinned wgpu-native API does
offer optional native indirect-first-instance and multi-draw-count features, but requiring them
would remove the existing portable path. Building clusters during ordinary frames would also
violate the engine's change-driven derived-state rule.

## Decision

Every runtime Geometry owns a deterministic meshlet representation beside its canonical vertices
and triangle indices. Registration builds the representation once with the pinned upstream
meshoptimizer library. Replacement, clone, destruction, hot reload, and LOD generation treat all
meshlet arrays as part of the same versioned Geometry content.

Use at most 64 vertices and 124 triangles per meshlet. Retain:

- meshlet-local vertex indirection and 8-bit triangle streams;
- offsets and counts into those streams;
- a conservative local bounding sphere;
- a normal-cone axis and cutoff.

The source vertices and full index buffer remain canonical. ECS components continue to reference
one generational Geometry handle, LOD selection continues to resolve Geometry handles, and no
meshlet identity enters scene files, Luau payloads, or the native extension ABI.

Keep the current whole-primitive indexed-indirect renderer as the active baseline until the GPU
path can consume meshlet bounds and submit the resulting commands end to end. A capable WGPU path
may use feature-gated indirect-first-instance and native multi-draw-count submission. Unsupported
adapters must retain the existing geometry-batch path with the same visual result.

Meshlet construction is allowed only at explicit geometry creation or replacement boundaries.
Stable frames never rebuild, scan, hash, or upload unchanged meshlet data.

## Consequences

Procedural geometry, imported-model primitives, transient Luau/native geometry, and every generated
LOD level now share one cluster format and lifecycle. Future GPU culling can consume resource-owned
bounds without inventing an importer-only model representation or a second renderer.

Geometry registration does additional CPU work and retains extra cluster arrays. Scrapbot also
gains a pinned C++ source dependency and must build/link meshoptimizer on every supported host.

This decision does not by itself claim meshlet GPU culling or reduced raster work. Until the
feature-gated submission path lands, rendering still uses the canonical whole-primitive index
buffer and one indexed-indirect call per retained batch.
