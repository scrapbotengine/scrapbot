---
title: CLI Reference
description: Current Scrapbot command-line interface.
---

All commands run against a project directory. When omitted, the project path defaults to the current directory.

## Machine-readable output

`init`, `import`, `check`, `build`, `run`, and `profile` accept `--json`. JSON mode emits exactly one document to stdout and suppresses project log lines:

```json
{
  "schema_version": 1,
  "command": "check",
  "ok": false,
  "diagnostics": [
    {
      "code": "SCRAPBOT_CHECK_FAILED",
      "severity": "error",
      "message": "failed to read project.toml",
      "path": "my-game"
    }
  ],
  "result": {}
}
```

Diagnostic codes are stable automation identifiers. Messages remain human-readable context. Successful command envelopes have an empty diagnostics array and command-specific result fields.

Human-mode `import`, `check`, `build`, and source-project `run` commands report asset processing progress to stderr. JSON mode suppresses these progress lines so stdout remains exactly one JSON document.

## `scrapbot init`

```sh
scrapbot init [path] [name] [--json]
```

Creates a project with:

- `project.toml`
- `scenes/main.scene.toml`
- `resources/default.resource.toml`
- `scripts/main.luau`
- `assets/`
- `native/`
- `.scrapbot/types/scrapbot.d.luau`
- `.vscode/settings.json`
- `.gitignore`

When `name` is omitted, Scrapbot uses the destination directory name. The command accepts a new or existing directory but preflights its owned files and refuses to overwrite any of them. `.scrapbot/` contains ignored generated state; `build/` is reserved for packages.

## `scrapbot build`

```sh
scrapbot build [path] [--target host] [--json]
```

Ensures source asset imports, builds native extension targets, and creates a runnable package under `build/<target>`. The package contains a renamed Scrapbot executable, project runtime data, imported asset products, and only the active compiled native extension artifacts. Native extension source and generated editor metadata are omitted.

The default target is the current host, such as `darwin_arm64` or `linux_amd64`. `--target host` is an explicit alias for it. Other Odin targets are modeled but currently rejected because Scrapbot does not yet provide target-built Luau, SDL3, and WGPU dependencies.

Run the packaged executable directly. It defaults to a windowed WGPU game; renderer and bounded-run options remain available for testing:

```sh
build/darwin_arm64/my-game
build/darwin_arm64/my-game --backend null --frames 1 --json
```

Successful JSON results include `target`, `output_directory`, and `executable` fields. Unsupported targets report `SCRAPBOT_UNSUPPORTED_TARGET`.

## `scrapbot import`

```sh
scrapbot import [path] [--json]
```

Compiles declared Texture, Model, Environment, and Icon Set sources into versioned products under `.scrapbot/imported/`. Model products include configured offline mesh LODs. Unchanged source/dependency/settings fingerprints reuse cached products.

Human output identifies the active asset before processing begins. Its completion line reports the elapsed time, cache result, and a compact product summary:

- Texture and Environment summaries include dimensions and mip counts.
- Model summaries include primitive, vertex, LOD, cluster-page, and byte counts.
- Icon Set summaries include symbol and atlas dimensions.

A failed asset names its source, elapsed time, and error immediately. JSON results contain `imported`, `cached`, and `products` without emitting progress lines.

Import failures report `SCRAPBOT_IMPORT_FAILED` and leave a prior valid product untouched.

## `scrapbot check`

```sh
scrapbot check [path] [--json]
```

Performs project validation:

- reads `project.toml`;
- ensures declared source asset imports;
- builds declared native extensions;
- loads native extension schemas and system declarations;
- builds the ECS world from the default scene;
- executes `scripts/main.luau` silently to collect schemas and systems;
- validates scene component data against the registry;
- refreshes `.scrapbot/types/scrapbot.d.luau`;
- runs `luau-analyze` when available.

## `scrapbot run`

```sh
scrapbot run [path] [--backend null|wgpu] [--window|--headless] [--hot-reload|--no-hot-reload] [--editor] [--live-debug] [--live-debug-port n] [--scheduler-trace] [--runtime-stats] [--frames n] [--framegrab out.png] [--framegrab-region x,y,width,height] [--ui-script actions.json] [--ui-dump tree.json] [--json]
```

Runs a project through the selected renderer backend after stepping registered native and Luau systems. Source-project runs default to WGPU, a visible window, and hot reload:

```sh
scrapbot run my-game
```

Packaged executables also default to windowed WGPU, but do not watch development source files.

Options:

| Option | Meaning |
| --- | --- |
| `--backend null` | Use the null renderer instead of the default WGPU renderer. |
| `--backend wgpu` | Explicitly use the default WebGPU renderer. |
| `--cpu-culling` | Keep WGPU storage and indirect drawing, but compute camera/shadow visibility through the deterministic CPU reference path. |
| `--window` | Explicitly open the default platform window. |
| `--headless` | Run without SDL or a presentation surface. WGPU renders to an offscreen texture even when no framegrab is requested. |
| `--editor` | Start with the editor shell visible. `Cmd/Ctrl+E` toggles it in a visible window. |
| `--live-debug` | Expose the token-authenticated live debug API on loopback. Windowed editor runs enable it automatically. |
| `--live-debug-port n` | Request a loopback port for live debugging. Zero selects an available port. |
| `--hot-reload` | Explicitly enable the default project-file, script, asset, and native-extension polling. |
| `--no-hot-reload` | Disable source-project hot reload for deterministic runs. |
| `--scheduler-trace` | Print native worker count, parallel stage count, and maximum stage width. |
| `--runtime-stats` | Collect early/late engine-frame timing through render preparation, engine-allocator bytes, and ECS storage checkpoints. Windowed runs also require nonzero `--frames`. |
| `--frames n` | Limit renderer frames. A zero value renders one headless frame or runs a window until close. |
| `--framegrab out.png` | Write the final headless WGPU frame to a PNG. |
| `--framegrab-region x,y,width,height` | Export only this top-left-origin 1:1 pixel region; requires `--framegrab`. |
| `--ui-script actions.json` | Replay a versioned semantic UI diagnostic script. A zero `--frames` value becomes a 240-frame safety bound. |
| `--ui-dump tree.json` | Write the final reconciled UI tree, geometry, control kinds, and interaction state as JSON, including on failure. |
| `--json` | Emit one versioned machine-readable result. |

The editor shell keeps the running project live across the complete central viewport. Its camera aspect ratio follows the available space, and an editor-origin scene camera navigates without changing the project's camera.

The shell is built from transient editor-origin ECS UI entities. Its tools include:

- A revision-driven Performance panel for rolling frame health and current rendering counters.
- An independently sampled Systems panel for CPU phase attribution.
- Smoothly scrolling, clipped Scene and Inspector panes with proportional scrollbars.
- Translation, rotation, and scale gizmos with World and Local orientation controls.

Hold right mouse inside the viewport to capture the pointer. Look with the mouse, move with WASD, rise with Space, and descend with Ctrl. Clicking rendered geometry selects the nearest project entity, reveals it in the Scene pane, and drives the component inspector.

Stopped is authoring mode. Inspector and gizmo gestures enter UUID-addressed undo/redo transactions. Save from the top bar or press `Ctrl/Cmd+S`; only fields that differ semantically from the disk-authored baseline are written. Revert discards unsaved authoring, clears history, and reloads scene entities without reloading code or resources.

Play snapshots the current authoring state in memory. Stop restores that state and discards playback mutations and runtime spawns. Runtime entities and running or paused mutations are never persisted. The Scene pane distinguishes authored entities from runtime spawns and hides editor-origin entities.

Combine `--editor`, `--headless`, `--ui-script`, `--ui-dump`, and `--framegrab` to reproduce editor interactions deterministically. Framegrabs are losslessly compressed; explicit regions or semantic capture targets crop the output without scaling its pixels. See [Rendering And Testing](/guides/rendering-testing/#semantic-ui-diagnostics) for the script contract.

The [Live Debug API](/guides/live-debug-api/) exposes current camera, viewport, renderer, virtual-geometry, and GPU timing state to local tools. It can also preserve a bounded sequence of consecutive telemetry snapshots and frame-matched composited WGPU images from the running process.

With `--runtime-stats`, JSON results include a `runtime_stats` object. It reports the frame count, warm-up and sample-window sizes, early and late nanoseconds per engine frame, their ratio, engine-allocator bytes, and early/late/peak/final ECS storage slot counts. Timing covers systems, engine UI/editor updates, render reconciliation, extraction, and batching preparation; it excludes GPU command encoding, submission, and execution. `allocator_final_bytes` is captured after project runtime teardown. Allocator numbers cover allocations routed through Odin's engine allocator; direct Luau, SDL, WGPU, driver, GPU, and OS allocations are outside this report.

JSON run results also include `render_stats`. For WGPU, the object groups together:

- Active-path flags for compute culling, any active meshlet batch, native multi-draw acceleration, portable virtual-geometry compaction, and clustered lighting. `virtual_geometry_compacted` is true when camera-selected clusters flow through GPU-produced instance/cluster streams instead of native multi-draw. Portable shadows still use GPU-produced visibility and indexed-indirect commands for the selected object LOD. A capable frame may mix classic and cluster camera batches.
- Meshlet capability, retained `draw_batches`, compatible fixed multi-draw spans in `draw_submissions`, selected meshlet command count in `meshlet_draws`, camera `visible_batches`, nonempty `visible_meshlet_draws`, visibility capacity, separate object/meshlet frustum, cone, and occlusion counters, and the opt-in `meshlet_debug_records` count.
- Virtual-geometry topology and residency: page budget, resident bytes, total/resident/pinned pages, request/feedback counts, overflow, cumulative page/group uploads, evictions, upload bytes, and deferred group admissions.
- Virtual-geometry selection and handoff: the active drawable frontier, projected-error overlap, drawable-group activations, `virtual_geometry_transitioning_groups`, and `visible_virtual_blend_clusters`. `visible_virtual_triangles` reports useful selected geometry, while `compact_vertex_invocations` includes padded portable-path vertex work.
- Visibility capacity: `candidate_record_overflow`, `visible_record_overflow`, and `shadow_record_overflow` count GPU records rejected because their retained slice was full. Healthy frames report zero. On the portable compact path, `shadow_visible_meshlets` remains zero while `shadow_visible_instances` reports conservative indexed object-LOD cascade visibility.
- Shadow refresh mask, per-cascade visible meshlet counts, cluster count, per-cluster light capacity, clustered-point-light count, and cluster-dispatch values.
- Draw-database, instance-slot, and visibility-buffer capacities, database rebuilds, and cumulative instance uploads.
- Shared vertex/index arena capacity and resident bytes plus cumulative geometry uploads, upload bytes, and backing-buffer growths.
- Frustum candidates, explicit frustum rejections, visible instances, per-LOD visible counts, and Hi-Z validity, status, mip count, and adaptive instance threshold.
- Retained-UI vertex rebuild and upload counters for project UI, editor UI, and editor-world overlays.

When the adapter supports timestamp queries, `gpu_timestamps_supported` and `gpu_timestamps_valid` qualify asynchronous `gpu_frame_ms` and `gpu_scene_ms` ordered pass-boundary spans. Separate `gpu_cull_ms`, aggregate `gpu_shadow_ms`, `gpu_shadow_cascade_ms`, `gpu_depth_ms`, `gpu_world_ms`, `gpu_hiz_ms`, `gpu_bloom_ms`, `gpu_composite_ms`, and `gpu_ui_ms` values attribute individual passes and are not summed into frame duration. A zero far-cascade value can represent a deliberately retained layer; inspect `shadow_cascade_render_mask` before treating it as absent work.

Visibility counters and timestamps use multi-frame readback rings. The renderer never waits synchronously and retains the latest completed sample when a frame has no new result.

## `scrapbot profile`

```sh
scrapbot profile [path] [--warmup n] [--frames n] [--resolution WIDTHxHEIGHT] [--capture-range START:END] [--framegrab-region x,y,width,height] [--editor] [--ui-script actions.json] [--cpu-culling] [--disabled-features names] [--out directory] [--json]
```

Runs a bounded headless WGPU measurement after an excluded warmup. The output bundle contains raw exact-frame CPU/GPU telemetry in `profile.json` and a final `overview.png`. Profile schema version 2 defines GPU frame and scene time as ordered pass-boundary spans; version 1 used an additive pass total and is intentionally not comparison-compatible. A capture range triggers a fresh replay and writes a lossless PNG sequence, keeping pixel readback stalls outside the measured pass.

`--disabled-features` accepts comma-separated `automatic-exposure`, `temporal-antialiasing`, `fast-antialiasing`, `ambient-occlusion`, `screen-space-reflections`, `bloom`, and `volumetric-fog`. These profile-only overrides do not mutate project data.

Use `mise profile-analyze` to summarize or compare reports, `mise profile-sweep` to repeat the workload at a bounded resolution matrix, and `mise profile-features` for paired feature ablation. See [Rendering And Testing](/guides/rendering-testing/#render-profiling) for artifact fields, comparison rules, and agent-oriented workflows.

## `scrapbot help`

```sh
scrapbot help <command>
scrapbot --version
```

Prints generated command help or the engine version.
