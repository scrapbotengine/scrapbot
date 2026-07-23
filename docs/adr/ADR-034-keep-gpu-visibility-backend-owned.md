# ADR-034: Keep GPU visibility backend-owned

**Date:** 2026-07-19

## Context

The first WGPU renderer rebuilt per-instance matrix and material arrays on the CPU every frame, capped a frame at 64 instances, and submitted direct indexed draws. ECS render membership was already change-driven and resource ownership was already backend-neutral, but the frame packet forced stable scene data back through a small transient uniform allocation.

GPU-driven rendering needs persistent instance identity, scalable visibility, and indirect draw counts without moving GPU buffers into ECS or making project data aware of a specific backend.

## Decision

Keep ECS responsible for stable render-instance slots, structural dirty tracking, and backend-neutral render data. Let each capable backend own its persistent GPU instance table, visibility buffers, batch metadata, compute pipelines, and indirect arguments.

Keep gameplay simulation CPU-authoritative. Odin and Luau systems continue to read and write ordinary ECS component state with the same ordering and deferred-mutation promises. GPU compute is appropriate for renderer-owned derived work such as visibility, compaction, LOD selection, and future graphics effects; moving gameplay components into GPU-only state would create a second authority and weaken the scripting contract.

ECS retains the backend-neutral render list across frames. Separate structural/static and Transform-only mutation queues update or remove only the affected entity and stable render slot; unchanged frames do not scan the active renderable set. Transform writeback paths enqueue their exact entity without requesting resource or batch reconciliation. Structural membership and resource changes supersede redundant same-frame Transform work.

The WGPU backend retains geometry/material batches and instance-to-LOD batch mappings until a new batch key, world replacement, geometry/material change, or geometry-LOD topology change requires revision. Spawning or despawning another instance of an existing batch updates its retained membership count and GPU slot without rebuilding the draw database. Transform-only updates reuse the previous batch mapping and pack one dense 64-byte position/rotation/scale/local-bounds record per dirty slot; the unused position lane carries the exact persistent destination slot. One upload feeds a renderer-owned compute pass that expands only those updates into model matrices, normal matrices, and conservative world bounds in the persistent 240-byte instance table before visibility culling. Static material, shadow, batch, LOD, and active fields remain resident in a cache-separated source array and are uploaded only when their source changes. The batch table and its visibility/indirect buffers grow geometrically instead of imposing a fixed batch ceiling. Static record writes coalesce nearby dirty slots into bounded uploads, compact render and culling uniforms remain retained until their values change, camera and shadow visibility compute into separate compacted per-batch slices, and one indexed indirect draw is issued per retained batch. Indirect `firstInstance` remains zero; aligned visibility-buffer slices provide batch-local instance indexing without requiring the optional WebGPU `indirect-first-instance` feature.

Run a depth prepass and build a max-depth Hi-Z pyramid when the scene is large enough to amortize it. Do not build a pyramid on a frame whose instance records changed, because it cannot be reused safely on the following continuously moving frame. The compute visibility pass consumes the previous completed pyramid only while the camera matrix and persistent instance records remain unchanged; a camera, transform, render-membership, geometry, material, or LOD change disables occlusion for that frame so stale depth cannot reject visible objects. Bounding spheres remain conservative: the query mip covers the complete projected footprint, a sphere crossing the camera plane is always visible, and large near-field bounds bypass Hi-Z because center-radius projection is not conservative at large angular sizes.

Treat LOD as geometry-resource data, not an entity or backend-specific component. A UUID-backed `scrapbot.geometry_lod` project resource owns an icosphere level chain and descending screen-radius thresholds. ECS entities still reference one stable geometry handle. The persistent GPU instance record carries the resolved alternate batch indices and thresholds, and the visibility shader selects the draw batch from projected screen radius before compaction. The CPU reference path implements the same selection rule.

Use optional WebGPU timestamp queries and asynchronous multi-frame readback rings for per-pass GPU execution time and visibility/LOD counters. Never block the render loop waiting for diagnostic data. A frame without completed readback retains the most recent valid sample.

Keep a CPU implementation of the same bounding-sphere/frustum test as a deterministic correctness oracle. CPU editor picking remains independent because it needs exact triangle hits and entity identity rather than render visibility.

## Consequences

Renderable count and draw-batch count are no longer constrained by the old uniform arrays, steady-state instance data remains resident on the GPU, and transform expansion, frustum, occlusion, LOD, and count work scale on the GPU while ECS and resource boundaries stay portable. The CPU work of an unchanged frame is independent of total renderable count; changed work scales with dirty entities and compact coalesced GPU ranges. The deterministic CPU-culling path still expands complete records as a correctness oracle. Authored LOD changes preserve the base runtime handle and advance a geometry-topology revision so retained batches rebuild without scanning unrelated ECS membership.

The implementation still submits one CPU-known draw per geometry/material/LOD batch because portable WebGPU does not provide core multi-draw-count submission. It retains an explicit backend limit of 131,072 instance slots. New batch keys, geometry-LOD topology changes, and draw-database growth rebuild batch visibility slices; ordinary membership churn within retained batches does not. Hi-Z currently requires a stable camera for one frame and project-authored geometry LODs currently generate icosphere levels. Imported meshes, offline simplification, bindless materials, meshlets, skinning, and a GPU-authored draw-count submission path remain future work.
