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

Open the editor to compare individual engine, project-Odin, and Luau systems. The Systems panel publishes a rolling 50-frame average every five frames. Engine phases and project systems measure their CPU callback boundaries. `scrapbot.render` covers CPU render preparation and submission, not asynchronous GPU execution.

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

## Understand retained work

- Native deferred-command buffers persist across frames, start small, and grow only when a system actually emits more commands.
- System dependency plans rebuild only when registered system topology changes.
- Runtime entity slots use a free-index stack and generation increments, so spawn does not scan historical world capacity and stale handles remain invalid.
- Project-component membership is indexed in both directions. Queries can start from sparse storage, and despawn releases only the custom storages owned by that entity.
- Renderable, camera, and light membership follows structural dirty queues. Render-list CPU storage is reused each frame, while WGPU draw grouping and aligned visibility slices rebuild only when render topology changes.
- WGPU addresses persistent instance records by stable ECS render slot, uploads contiguous changed ranges, computes camera and shadow frustum visibility on the GPU, and obtains per-batch instance counts through indexed indirect arguments. The first backend limit is 131,072 slots and 64 geometry/material batches.
- UI structural synchronization is dirty-entity driven. Stable project and editor roots skip layout independently when their topology, layout values, and viewport are unchanged; painting and interaction remain live.
- WGPU geometry and materials are cached by resource handle and version. UI vertex CPU storage and the GPU vertex buffer grow to capacity and are reused.
- Editor entity/resource/inspector snapshots refresh at tool cadence, while profiler revisions update only profiler rows and direct manipulation stays frame-responsive.

## Choose the right diagnostic

- Use the null backend for simulation, scheduler, query, lifecycle, and memory comparisons.
- Use `--scheduler-trace` to inspect worker count, parallel stages, and maximum native width.
- Use the Systems panel and `tests/fixtures/ui/ui-performance.json` for editor interaction costs.
- Use bounded headless WGPU plus a framegrab when renderer correctness or submission cost matters.
- Inspect structured `render_stats` for GPU-driven mode, slot and visibility capacity, occupied slot span, and cumulative instance upload calls/bytes. These counters require no GPU readback.
- Use external GPU tooling when you need whole-frame or per-pass GPU timings, shader costs, bandwidth, or occupancy detail. The Systems panel deliberately avoids synchronous GPU readback because it can distort runtime performance.

Avoid absolute cross-machine budgets in tests. Scrapbot's regression suite instead checks bounded work, topology reuse, linear cursor behavior, stable storage, zero post-teardown allocator bytes, and same-machine before/after measurements.
