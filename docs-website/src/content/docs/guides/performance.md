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

Large imported models retain position-only CPU query proxies instead of full render vertices and
source indices. Their immutable products remain the fallback source. Backend cache creation may
temporarily reconstruct exact leaf geometry, but stable cache hits do not retain or rebuild that
CPU view. Use the allocator checkpoints from identical bounded runs to measure the retained-memory
effect independently from GPU page residency.

Repository builds make optimization intent explicit: `mise build-dev` emits `bin/scrapbot-dev` with `-o:minimal`, while `mise build` emits the ordinary performance binary with `-o:speed`. `mise benchmark-profiles` runs the same bounded null-backend project through both binaries and reports median late-update time over three trials. It is a same-machine investigation tool, not a cross-machine CI budget. Pass an optional project, frame count, and trial count after `--`, for example `mise benchmark-profiles -- examples/ecs-showcase 4000 5`.

Use `examples/ecs-stress --editor` to watch the retained native-query path drive roughly 3,000 glowing renderables while editing the emitter live. `mise benchmark-native-queries` copies that example to a temporary project, sets the requested spawn rate, and reports late frame time, packed entities, chunk count, average chunk occupancy, scalar tail lanes, compiled-plan builds, and retained-plan hits. Optional arguments set frame count and spawn rate, for example `mise benchmark-native-queries -- 4000 1000`.

Use `examples/clustered-lights --editor` to inspect the GPU clustered-lighting path under a deliberately excessive but spatially distributed load: 320 animated point lights, a moving camera, shared emissive markers, and a dark receiving environment. The Performance panel exposes the retained cluster count, growable per-cluster capacity, and active point-light count alongside draw and GPU timing diagnostics.

Use `mise archive-profile` for a bounded 1600×900 capture of the generated Impossible Archive.
The task creates the showcase GLB, warms the renderer, records 240 measured frames, and prints the
profile directory. Its dense imported reliefs and 64 MiB virtual-geometry budget are useful for
examining hierarchy traversal, visible clusters, culling, and portable compact-submission cost in
one reproducible workload. The checked-in 64 MiB budget keeps the showcase preset resident; lower
it deliberately when profiling page requests, uploads, deferred groups, prefetches, and evictions.

Open the editor to compare individual engine, project-Odin, and Luau systems. The Systems panel publishes a rolling 50-frame average every five frames. Engine phases and project systems measure their CPU callback boundaries. Renderer work is split across `scrapbot.render.cull`, `.shadow`, `.world`, `.post`, `.ui`, `.finish`, `.submit`, and `.present`; these are CPU encoding and API timings. FIFO/vsync waiting belongs to the core window loop and is excluded from engine-system and active-frame timings. Native project systems with non-conflicting access may execute in parallel, so their individual callback durations are attribution rather than strictly additive wall time. Structured WGPU `render_stats` separately expose asynchronous GPU execution samples.

The collapsible Performance panel gives a compact frame-health view beside the Systems panel. It publishes every five frames and shows observed FPS from wall-clock presentation intervals and `CPU FRAME` from active CPU work, each over a rolling 50-frame window.

`CPU FRAME` begins after presentation-surface acquisition. It includes scheduled systems, retained render preparation, GPU command encoding and finalization, queue submission, and the CPU-side present call. Surface acquisition, vsync waiting, profiler drains, and other between-frame idle time affect FPS but not `CPU FRAME`.

The panel also shows the latest valid asynchronous GPU frame and scene durations, effective render scale, scene-plus-runtime entity count, retained and camera-visible GPU batch counts, visible meshlet draws, Hi-Z state, frustum rejects, whole-object occlusion rejects, and meshlet occlusion rejects. `GPU FRAME` spans the earliest through latest executed timed pass boundaries, including native-resolution UI when present. `GPU SCENE` shares that beginning and ends after final composition, before UI. Both remain `--` until timestamp-query results are available.

Structured renderer snapshots split retained batch and instance counts into `conventional_*` and
`virtual_*` fields. Use those counts to verify automatic policy before attributing a pass cost to
virtual geometry; two instances of one Geometry may intentionally use different paths.

**Retained Batches** is stable draw-database topology: one entry for each geometry/material/LOD combination the loaded scene may render. Culling never removes these records merely because the camera turns.

Structured `render_stats.draw_submissions` is the number of compatible indirect command spans
encoded for one pass. It can be lower than Retained Batches because shared geometry arenas let
adjacent same-material LOD or meshlet commands retain separate visibility while sharing bindings
and one fixed multi-draw call.

**Visible Batches** counts camera batches with at least one object that survived object-level frustum and Hi-Z culling and selected that LOD. **Visible Meshlet Draws** counts meshlet indirect commands that received at least one surviving instance after meshlet frustum, cone, and Hi-Z tests. The latter is zero on the whole-primitive CPU-reference path.

The panel's three values describe camera visibility, not shadow-cascade visibility. Retained batches can therefore remain high while visible batches and meshlet draws approach zero. Empty indirect commands produce no triangles. Compatible commands still occupy retained topology but share bounded submission spans.

The Hi-Z state explains why an occlusion count may be zero:

- **Unavailable** means the active backend or submission path cannot perform GPU Hi-Z queries.
- **Below N** means the scene has fewer occupied instance slots than the normal adaptive threshold.
- **Scene changed** means persistent instance data changed this frame.
- **Camera changed** means the view-projection matrix no longer matches the retained depth.
- **Warming up** means a valid pyramid exists but no safe previous-frame query is available yet.
- **Active** means the current GPU cull consumed a reusable pyramid.

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

Dense native arithmetic systems can use `Query_Chunk`:

- Bind Transform or schema-backed Number/Vec2/Vec3/Vec4 arrays once.
- Fetch up to 64 matching entities per host call.
- Process complete groups with Odin `#simd` values.
- Handle the scalar tail.
- Commit only an explicit lane mask.

The host retains a compiled plan for each chunk shape. Ordinary calls therefore use a stable candidate-storage slot and direct typed field indices instead of resolving component and field names per entity.

Buffers remain extension-owned copies, so the ABI does not expose ECS pointers or storage layout. Chunks work best when the same simple operation applies to many entities. Cursor iteration remains clearer for branchy logic, sparse matches, and systems dominated by spawn or despawn commands.

Scrapbot's portable SIMD layer currently uses four `f32` lanes for matrix multiplication, frustum-plane work, sphere tests, and the native showcase's transform/lifetime/velocity kernels. Prefer private or wrapper-level lane types over putting `#simd` fields in persistent components or the C ABI: vector width and CPU features are implementation details, while project data must remain stable and serializable.

## Understand retained work

- Native deferred-command buffers persist across frames, start small, and grow geometrically when a system emits more commands. A compact ordered header stream addresses separate payload-kind arrays; queued spawns and component additions retain only components actually present, while schema-backed components retain only their supplied Number/Vec2/Vec3/Vec4 fields. Buffers impose no fixed per-frame command-count ceiling and retain each array's high-water capacity; fixed ABI limits apply only to caller-owned staging payloads.
- System dependency plans rebuild only when registered system topology changes.
- Runtime entity slots use a free-index stack and generation increments, while scene ordering uses a monotonic cursor, so spawn does not scan historical world capacity and stale handles remain invalid.
- Project-component membership is indexed in both directions. Queries can start from sparse storage, and despawn releases only the custom storages owned by that entity.
- Renderable membership follows structural and value dirty queues. The retained render list updates only changed entities and slots; an unchanged frame does not scan the active renderable set. Cameras and compact light sets remain cheap frame values because camera motion and lighting directly affect camera-dependent render state.
- WGPU retains persistent instance records by stable ECS render slot, coalesces nearby changed slots into bounded uploads, and preserves render/culling uniforms until their values change.
- Instance-to-LOD batch mappings and indirect templates are retained on stable frames. Transform-only changes upload 64-byte position/rotation/scale/local-bounds records; dirty-only compute expands them into model matrices, normal matrices, and world bounds while static material, shadow, batch, and LOD fields remain resident.
- Spawn and despawn within an existing geometry/material/LOD batch adjust retained membership without rebuilding the draw database. New batch keys or required capacity may still grow it.
- The backend computes camera and four-cascade shadow visibility on the GPU, then obtains per-batch instance counts through indexed indirect arguments.
- Geometry submission resolves from entity, Model asset, and project policy when retained topology changes. Automatic mode keeps small geometry conventional and selects a resident virtual cluster frontier for capable hierarchy-bearing geometry with at least 50,000 source triangles. Pinned coarse pages guarantee a fallback while asynchronous requests load finer pages under the project budget. Camera motion changes detail, never the selected submission path.
- A deterministic cluster-centric compute pass assigns the retained point-light list into 3,456 view-frustum clusters without CPU cluster construction. Light and cluster-index buffers grow geometrically.
- WGPU retains a 131,072-slot instance limit. Its draw database grows instead of imposing a fixed batch count.
- Scenes with at least 256 occupied instance slots build a max-depth Hi-Z pyramid after the depth prepass only on stable-instance frames. The following frame consumes it only while the camera matrix and persistent instance records remain unchanged. Camera movement or transform, membership, geometry, material, or LOD changes temporarily fall back to frustum culling rather than building or consuming depth that cannot be reused safely. Queries project an enclosing cube and use its nearest possible depth at a coarse mip covering the complete footprint. Objects crossing the camera plane or occupying a large near-field angle bypass occlusion and remain conservatively visible.
- Authored geometry LOD resources and importer-generated model LODs resolve alternate batches for classic GPU and CPU-reference submission. Each instance carries compact batch indices and descending screen-radius thresholds, and both paths select the same whole-object level. A supported continuous virtual hierarchy replaces that selection with its cluster frontier and omits the redundant alternate batches.
- Imported LOD simplification, vertex compaction, and product serialization run only when the Model import fingerprint changes. Stable frames consume retained Geometry handles. Alternate levels contribute batch topology on fallback paths, so tune the model recipe's level count and thresholds when their product size or fallback cost exceeds their triangle savings.
- UI structural synchronization is dirty-entity driven. Stable project and editor roots skip layout independently when their topology, layout values, and viewport are unchanged. Their resolved nodes and visual inputs are also independently signatured, so unchanged domains retain paint commands and skip traversal and glyph emission while interaction remains live.
- WGPU geometry and materials are cached by resource handle and version. Project UI, editor chrome, and editor-world overlays use independent monotonic output revisions, CPU vertex arrays, and GPU buffers. Typed ECS mutation, scrolling, interaction, or tooling motion invalidates only the affected stream. Unchanged frames avoid hierarchy and paint traversal, a full paint-array hash, vertex generation, and UI uploads; they only encode retained-buffer draws.
- WGPU builds the five-level bloom pyramid with five dispatches in one compute pass before one fullscreen composite, avoiding a chain of short intermediate render passes.
- The editor entity browser materializes authored entities plus an explicitly selected runtime entity rather than every short-lived runtime spawn. Selection and explicit structural invalidation rebuild it; periodic running-value refresh does not. The inspector follows the selected entity's component revision or selected resource version, so unrelated runtime churn does not rebuild stable component panels. Profiler revisions update only profiler rows and direct manipulation stays frame-responsive.

## Choose the right diagnostic

- Use the null backend for simulation, scheduler, query, lifecycle, and memory comparisons. Runtime-stat JSON includes `native_queries` counters for plan reuse, chunks, packed entities, and scalar tail lanes.
- Use `--scheduler-trace` to inspect worker count, parallel stages, and maximum native width.
- Use the Performance panel for frame-rate and active-CPU health, the Systems panel for CPU phase attribution, and `tests/fixtures/ui/ui-performance.json` for editor interaction costs.
- Use bounded headless WGPU plus a framegrab when renderer correctness or submission cost matters.
- Inspect structured `render_stats` for GPU-driven mode, retained `draw_batches`, camera `visible_batches`, nonempty `visible_meshlet_draws`, draw/slot/visibility capacity, database rebuilds, occupied slot span, cumulative instance upload calls/bytes, Hi-Z status and threshold, frustum candidates, separate object/meshlet occlusion rejects, per-LOD visible counts, and UI vertex rebuild/upload counts and bytes.

  `virtual_cluster_draws` is retained hierarchy command topology. `visible_virtual_clusters` counts
  selected resident camera clusters after ordinary visibility tests. `virtual_rejected_clusters`
  counts candidates rejected because another hierarchy level owns their screen-space region.

  `visible_virtual_triangles` is the useful virtual-geometry triangle count selected for the
  camera. Portable compact submission reports `compact_triangles` across conventional and virtual
  meshlets plus `compact_vertex_invocations`, including padded vertex work. Compare
  `compact_triangles * 3` with `compact_vertex_invocations` to measure lane utilization. The
  portable path groups selected records into 32-, 64-, 96-, and 124-triangle lanes, so smaller
  meshlets no longer pay the maximum 124-triangle vertex cost. Native multi-draw and classic whole-
  primitive submission leave both compact counters at zero.

  `virtual_geometry_page_budget_bytes`, `virtual_geometry_page_resident_bytes`, and the total,
  resident, pinned, and prefetched page counts describe current residency. Demand requests,
  prefetch requests, and overflow describe the latest completed asynchronous feedback. Prefetch
  group uploads, hits, and reclamations explain whether prediction arrived usefully or yielded to
  demand. Upload, drawable-group activation, byte, hit, reclamation, and eviction counts are
  cumulative; profile `counter_deltas` make cumulative counters frame-local.

  `visible_virtual_blend_clusters` counts selected clusters inside either the steady projected-error
  overlap or a streamed-admission handoff. `virtual_geometry_transitioning_groups` counts only the
  latter: refinements currently replacing their complete parents. A resident child passes a bounded
  demand-aware settling window and waits for its direct parent to settle. Both then remain drawable
  for a 16-render-frame admission transition. World, depth, and shadows use complementary coverage,
  so refinement does not introduce translucent overlap or a one-frame topology hole. TAA integrates
  a low-discrepancy camera mask into a soft fade. Its transition-aware history tolerates bounded
  parent/child depth changes and closes one-frame silhouette gaps. Non-temporal views and shadows
  keep a stable spatial partition.

  `meshlet_debug_records` counts the active Meshlet Visibility records or the live/frozen Occlusion Queries evidence; it is zero when neither diagnostic owns records. `instance_transform_uploads` and `instance_transform_upload_bytes` isolate the dense Transform-update stream from total instance traffic; ordinary Transform-only frames use one upload regardless of persistent-slot fragmentation. `instance_expand_dispatches` and `instance_expanded_slots` report the corresponding GPU expansion work. `ui_project_vertex_rebuilds`, `ui_editor_vertex_rebuilds`, and `ui_overlay_vertex_rebuilds` identify which retained domain invalidated.
- When `gpu_timestamps_supported` and `gpu_timestamps_valid` are true, `gpu_frame_ms` spans the earliest through latest executed timed pass boundaries, including UI when present. `gpu_scene_ms` shares that beginning and ends after composition, before UI. Cull, shadow, depth, world, Hi-Z, bloom, composite, and UI milliseconds come from separate pass timestamps for attribution; do not add them to reconstruct frame duration. Four-frame readback rings publish completed samples without synchronously waiting on the GPU. Use external GPU tooling for shader costs, bandwidth, occupancy, presentation, and deeper captures.

Avoid absolute cross-machine budgets in tests. Scrapbot's regression suite instead checks bounded work, topology reuse, linear cursor behavior, stable storage, zero post-teardown allocator bytes, and same-machine before/after measurements.
