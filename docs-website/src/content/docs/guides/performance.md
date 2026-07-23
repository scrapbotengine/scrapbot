---
title: Performance
description: Profile Scrapbot projects, write scalable ECS systems, and run CPU and memory growth checks.
---

Scrapbot's performance contract is data-oriented and incremental: systems iterate matching entities once, structural changes feed dirty queues, render and UI membership use compact active sets, and stable frame topology reuses scheduler, command, render-list, and GPU-buffer storage.

## Measure a project

Use a bounded null-backend run for repeatable CPU and allocator evidence:

```sh
bin/scrapbot run examples/ecs-showcase \
  --backend null \
  --headless \
  --no-hot-reload \
  --frames 10000 \
  --runtime-stats \
  --json
```

The versioned JSON result reports early and late nanoseconds per frame, CPU growth ratio, allocator checkpoints, and ECS slot counts. Compare results on the same machine and build configuration. Use `mise test-soak` for the repository's 10,000-frame growth gate.

Repository builds make optimization intent explicit: `mise build-dev` emits `bin/scrapbot-dev` with `-o:minimal`, while `mise build` emits the ordinary performance binary with `-o:speed`. `mise benchmark-profiles` runs the same bounded null-backend project through both binaries and reports median late-update time over three trials. It is a same-machine investigation tool, not a cross-machine CI budget. Pass an optional project, frame count, and trial count after `--`, for example `mise benchmark-profiles -- examples/ecs-showcase 4000 5`.

Use `examples/ecs-stress --editor` to watch the retained native-query path drive roughly 3,000 glowing renderables while editing the emitter live. `mise benchmark-native-queries` copies that example to a temporary project, sets the requested spawn rate, and reports late frame time, packed entities, chunk count, average chunk occupancy, scalar tail lanes, compiled-plan builds, and retained-plan hits. Optional arguments set frame count and spawn rate, for example `mise benchmark-native-queries -- 4000 1000`.

Use `examples/clustered-lights --editor` to inspect the GPU clustered-lighting path under a deliberately excessive but spatially distributed load: 320 animated point lights, a moving camera, shared emissive markers, and a dark receiving environment. The Performance panel exposes the retained cluster count, growable per-cluster capacity, and active point-light count alongside draw and GPU timing diagnostics.

Open the editor to compare individual engine, project-Odin, and Luau systems. The Systems panel publishes a rolling 50-frame average every five frames. Engine phases and project systems measure their CPU callback boundaries. Renderer work is split across `scrapbot.render.cull`, `.shadow`, `.world`, `.post`, `.ui`, `.finish`, `.submit`, and `.present`; these are CPU encoding and API timings. FIFO/vsync waiting belongs to the core window loop and is excluded from engine-system and active-frame timings. Native project systems with non-conflicting access may execute in parallel, so their individual callback durations are attribution rather than strictly additive wall time. Structured WGPU `render_stats` separately expose asynchronous GPU execution samples.

The collapsible Performance panel gives a compact frame-health view beside the Systems panel. It publishes every five frames and shows observed FPS from wall-clock presentation intervals and `FRAME` from active CPU work, each over a rolling 50-frame window. Surface acquisition, vsync waiting, and other between-frame idle time affect FPS but not `FRAME`. The panel also shows the latest valid asynchronous GPU frame duration, scene-plus-runtime entity count, retained GPU draw-batch count, and the number of instances rejected by Hi-Z occlusion. GPU frame time remains `--` until timestamp-query results are available. A draw batch is Scrapbot's GPU-driven geometry/material grouping unit, not a count of every graphics API draw command across every pass.

## Iterate queries once

Luau query systems and `query:each` use Scrapbot's linear cursor internally. Native systems should use the same iteration shape:

```odin
query := scrapbot.query(components[:])
cursor: scrapbot.Query_Cursor
for {
	entity, ok := scrapbot.next(ctx, query, &cursor)
	if !ok {
		break
	}
	// Read and write declared components.
}
```

The cursor chooses the smallest requested project-component storage as its candidate set, or world entity slots when no project component can narrow the query. It advances through that set once and remains stable because spawn, despawn, and component membership commands are deferred until the scheduled stage finishes. Candidate order is an internal detail. `scrapbot.count` and `scrapbot.entity_at` remain available for explicit tooling and random access, but a count-plus-index loop repeatedly rescans candidates and should not be used for per-frame simulation.

Dense native arithmetic systems can go one step further with `Query_Chunk`. Bind Transform or schema-backed Number/Vec2/Vec3/Vec4 arrays once, fetch up to 64 matching entities per host call, process complete groups with Odin `#simd` values, handle the scalar tail, and commit only an explicit lane mask. The host retains a compiled plan for each chunk shape, so ordinary calls use a stable candidate-storage slot and direct typed field indices instead of repeating component and field-name resolution per entity. The buffers remain extension-owned copies, so the ABI does not leak ECS pointers or storage layout. This is most valuable when the same simple operation applies to many entities; cursor iteration remains clearer for branchy logic, sparse matches, and systems dominated by spawn/despawn commands.

Scrapbot's portable SIMD layer currently uses four `f32` lanes for matrix multiplication, frustum-plane work, sphere tests, and the native showcase's transform/lifetime/velocity kernels. Prefer private or wrapper-level lane types over putting `#simd` fields in persistent components or the C ABI: vector width and CPU features are implementation details, while project data must remain stable and serializable.

## Understand retained work

- Native deferred-command buffers persist across frames, start small, and grow geometrically when a system emits more commands. A compact ordered header stream addresses separate payload-kind arrays; queued spawns and component additions retain only components actually present, while schema-backed components retain only their supplied Number/Vec2/Vec3/Vec4 fields. Buffers impose no fixed per-frame command-count ceiling and retain each array's high-water capacity; fixed ABI limits apply only to caller-owned staging payloads.
- System dependency plans rebuild only when registered system topology changes.
- Runtime entity slots use a free-index stack and generation increments, while scene ordering uses a monotonic cursor, so spawn does not scan historical world capacity and stale handles remain invalid.
- Project-component membership is indexed in both directions. Queries can start from sparse storage, and despawn releases only the custom storages owned by that entity.
- Renderable membership follows structural and value dirty queues. The retained render list updates only changed entities and slots; an unchanged frame does not scan the active renderable set. Cameras and compact light sets remain cheap frame values because camera motion and lighting directly affect camera-dependent render state.
- WGPU addresses persistent instance records by stable ECS render slot, coalesces nearby changed slots into bounded uploads, and retains compact render/culling uniforms until their values change. Instance-to-LOD batch mappings and indirect templates are likewise retained instead of being reconstructed on stable frames. Transform-only changes upload 64-byte position/rotation/scale/local-bounds records; a dirty-only compute pass expands them into model matrices, normal matrices, and world bounds while static material, shadow, batch, and LOD fields remain resident. Spawn and despawn within an existing geometry/material/LOD batch adjust retained membership without rebuilding the draw database; new batch keys or required capacity can still grow it. The backend computes camera and four-cascade shadow visibility on the GPU and obtains per-batch instance counts through indexed indirect arguments. Its deterministic cluster-centric compute pass assigns the retained point-light list into 3,456 view-frustum clusters without CPU cluster construction; light and cluster-index buffers grow geometrically. It retains a 131,072-slot instance limit; its draw database grows instead of imposing a fixed batch count.
- Scenes with at least 256 occupied instance slots build a max-depth Hi-Z pyramid after the depth prepass only on stable-instance frames. The following frame consumes it only while the camera matrix and persistent instance records remain unchanged. Camera movement or transform, membership, geometry, material, or LOD changes temporarily fall back to frustum culling rather than building or consuming depth that cannot be reused safely. Queries use a coarse mip covering the complete projected bound; objects crossing the camera plane or occupying a large near-field angle bypass occlusion and remain conservatively visible.
- Authored geometry LOD resources resolve all alternate batches when topology changes. Each GPU instance carries compact batch indices and descending screen-radius thresholds; the visibility shader selects one before compaction. The CPU reference path selects the same level for regression comparison.
- UI structural synchronization is dirty-entity driven. Stable project and editor roots skip layout independently when their topology, layout values, and viewport are unchanged. Their resolved nodes and visual inputs are also independently signatured, so unchanged domains retain paint commands and skip traversal and glyph emission while interaction remains live.
- WGPU geometry and materials are cached by resource handle and version. Project UI, editor chrome, and editor-world overlays use independent monotonic output revisions, CPU vertex arrays, and GPU buffers. Typed ECS mutation, scrolling, interaction, or tooling motion invalidates only the affected stream. Unchanged frames avoid hierarchy and paint traversal, a full paint-array hash, vertex generation, and UI uploads; they only encode retained-buffer draws.
- WGPU builds the five-level bloom pyramid with five dispatches in one compute pass before one fullscreen composite, avoiding a chain of short intermediate render passes.
- The editor entity browser materializes authored entities plus an explicitly selected runtime entity rather than every short-lived runtime spawn. Selection and explicit structural invalidation rebuild it; periodic running-value refresh does not. The inspector follows the selected entity's component revision or selected resource version, so unrelated runtime churn does not rebuild stable component panels. Profiler revisions update only profiler rows and direct manipulation stays frame-responsive.

## Choose the right diagnostic

- Use the null backend for simulation, scheduler, query, lifecycle, and memory comparisons. Runtime-stat JSON includes `native_queries` counters for plan reuse, chunks, packed entities, and scalar tail lanes.
- Use `--scheduler-trace` to inspect worker count, parallel stages, and maximum native width.
- Use the Performance panel for frame-rate and active-CPU health, the Systems panel for CPU phase attribution, and `tests/fixtures/ui/ui-performance.json` for editor interaction costs.
- Use bounded headless WGPU plus a framegrab when renderer correctness or submission cost matters.
- Inspect structured `render_stats` for GPU-driven mode, draw/slot/visibility capacity, database rebuilds, occupied slot span, cumulative instance upload calls/bytes, frustum candidates, occlusion rejects, per-LOD visible counts, and UI vertex rebuild/upload counts and bytes. `instance_transform_uploads` and `instance_transform_upload_bytes` isolate the dense Transform-update stream from total instance traffic; ordinary Transform-only frames use one upload regardless of persistent-slot fragmentation. `instance_expand_dispatches` and `instance_expanded_slots` report the corresponding GPU expansion work. `ui_project_vertex_rebuilds`, `ui_editor_vertex_rebuilds`, and `ui_overlay_vertex_rebuilds` identify which retained domain invalidated.
- When `gpu_timestamps_supported` and `gpu_timestamps_valid` are true, `gpu_frame_ms` plus cull, shadow, depth, world, Hi-Z, bloom, composite, and UI milliseconds come from WebGPU timestamp queries. Four-frame readback rings publish completed samples without synchronously waiting on the GPU. Use external GPU tooling for shader costs, bandwidth, occupancy, and deeper captures.

Avoid absolute cross-machine budgets in tests. Scrapbot's regression suite instead checks bounded work, topology reuse, linear cursor behavior, stable storage, zero post-teardown allocator bytes, and same-machine before/after measurements.
