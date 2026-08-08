# ADR-046: Store meshlets with geometry resources

**Date:** 2026-07-30
**Updated:** 2026-08-08

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

On adapters that expose `indirect-first-instance`, WGPU expands the local triangle streams into a
meshlet-ordered index range in the shared geometry index arena. It retains meshlet metadata,
visibility slices, and indexed-indirect templates beside the existing whole-primitive draw database.
WGPU also requests native multi-draw-count when available, which guarantees fixed multi-draw is
not emulated internally. Adapters without it retain fixed multi-draw only for forced diagnostic
views; ordinary selected meshlets use portable compaction.

WGPU chooses submission independently for every retained geometry/material/LOD batch. A batch with
at least two instances uses meshlets; a single-instance batch retains one whole-primitive indirect
command. The threshold is part of retained batch layout and changes only when membership crosses
it, so an ordinary frame does not rescan or rewrite the draw database.

Native multi-draw adapters retain one indexed-indirect command per meshlet. Other
indirect-first-instance adapters use the same parallel compact backend as portable virtual
Geometry: one candidate pass followed by meshlet-major camera and shadow passes. Compatible
same-material batches share four triangle-count lanes and at most four non-indexed indirect draws.
The vertex shaders pull conventional meshlet indices and attributes from the shared arenas.

The conservative threshold prevents cluster command setup and driver finalization from costing
more than the raster work it can avoid on low-instance architectural meshes. Meshlet identity,
visibility, and occlusion-query debug views deliberately force eligible batches through meshlet
submission so their evidence remains complete and truthful.

For a meshlet-selected batch, the compute pass first rejects the complete instance and selects its
LOD. It then tests that Geometry's meshlets:

- camera visibility uses the meshlet sphere, normal cone for single-sided materials, and Hi-Z;
- shadow visibility uses each cascade's frustum and the meshlet sphere;
- native multi-draw writes one atomic instance count and visible-instance slice per meshlet;
- portable compaction appends `{instance slot, meshlet index}` records to shared material lanes.

World, depth, and shadow passes may therefore mix whole-primitive draws, native fixed multi-draw,
and portable compact spans. Native command topology remains known at the resource-version
boundary. Portable topology is bounded by the four retained lane ceilings rather than the number
of meshlets, avoiding emulated empty draws and serial instance-major walks on dense resources.

Mixed culling stays within WebGPU's portable eight-storage-buffer stage limit. Classic, native,
candidate, camera-meshlet, and shadow-meshlet dispatches share the retained batch table and
counters. Each stage binds only its required visibility and indirect buffers and rejects batches
owned by another submission policy.

Adapters without `indirect-first-instance`, `--cpu-culling`, empty meshlet layouts, or layouts that
would exceed the bounded visibility allocation retain indexed-indirect submission. Complete
resources use their canonical whole-primitive payload. Streamed resources use their pinned coarse
indexed proxy, preserving coverage while intentionally reducing detail.

Meshlet construction is allowed only at explicit geometry creation or replacement boundaries.
Stable frames never rebuild, scan, hash, or upload unchanged meshlet data.

## Consequences

Procedural geometry, imported-model primitives, transient Luau/native geometry, and every generated
LOD level now share one cluster format and lifecycle. Future GPU culling can consume resource-owned
bounds without inventing an importer-only model representation or a second renderer.

Geometry registration does additional CPU work and retains extra cluster arrays. Scrapbot also
gains a pinned C++ source dependency and must build/link meshoptimizer on every supported host.

Capable adapters now reject invisible clusters before rasterization when batch reuse can amortize
the work. Native multi-draw keeps exact per-meshlet commands. Portable adapters transpose the
work into parallel meshlet-major culling and a bounded number of lane draws. Low-instance batches
avoid either command multiplier, while meshlet-oriented debug views can still inspect every
eligible cluster. No cluster identity escapes the backend.

Each meshlet reserves an aligned visible-instance slice sized to its batch membership. The backend
caps the total at 1,048,576 entries and falls back rather than allocating unbounded storage.
Meshlet metadata, templates, bind groups, selection policy, and expanded index buffers rebuild only
after Geometry version/topology, batch-capacity, policy-threshold, or dependent GPU-buffer changes.
Stable frames only reset/copy the active retained indirect templates and run current-frame compute
and render commands. See ADR-048 for shared arena ownership and compatible submission spans.
