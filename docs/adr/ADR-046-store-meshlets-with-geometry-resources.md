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

On adapters that expose `indirect-first-instance`, WGPU expands the local triangle streams into one
meshlet-ordered index buffer per Geometry version. It retains meshlet metadata, visibility slices,
and indexed-indirect templates beside the existing whole-primitive draw database.
WGPU also requests native multi-draw-count when available, which guarantees fixed multi-draw is
not emulated internally; adapters without it retain correct fixed multi-draw semantics.

The compute pass first rejects the complete instance and selects its LOD. It then tests that
Geometry's meshlets:

- camera visibility uses the meshlet sphere, normal cone for single-sided materials, and Hi-Z;
- shadow visibility uses each cascade's frustum and the meshlet sphere;
- one atomic instance count and compact visible-instance slice are retained per meshlet.

World, depth, and shadow passes bind the meshlet-ordered index buffer and issue one native fixed
multi-draw per retained geometry/material/LOD batch. Fixed multi-draw is intentional: meshlet
topology and command count are already known at the resource-version boundary, while compute
writes zero or nonzero instance counts into those retained commands. A GPU-authored command-count
buffer would add state and synchronization without compacting any information the renderer needs.

Adapters without `indirect-first-instance`, `--cpu-culling`, empty meshlet layouts, or layouts that
would exceed the bounded visibility allocation retain the existing whole-primitive indexed-
indirect path with the same visual result.

Meshlet construction is allowed only at explicit geometry creation or replacement boundaries.
Stable frames never rebuild, scan, hash, or upload unchanged meshlet data.

## Consequences

Procedural geometry, imported-model primitives, transient Luau/native geometry, and every generated
LOD level now share one cluster format and lifecycle. Future GPU culling can consume resource-owned
bounds without inventing an importer-only model representation or a second renderer.

Geometry registration does additional CPU work and retains extra cluster arrays. Scrapbot also
gains a pinned C++ source dependency and must build/link meshoptimizer on every supported host.

Capable native adapters now reject invisible clusters before rasterization and submit the retained
cluster commands with one multi-draw call per batch. This reduces triangle work for large,
partially visible primitives without exposing cluster identity outside the backend.

Each meshlet reserves an aligned visible-instance slice sized to its batch membership. The backend
caps the total at 1,048,576 entries and falls back rather than allocating unbounded storage.
Meshlet metadata, templates, bind groups, and expanded index buffers rebuild only after Geometry
version/topology, batch-capacity, or dependent GPU-buffer changes. Stable frames only reset/copy
the retained indirect templates and run current-frame compute and render commands.
