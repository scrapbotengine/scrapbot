---
title: CLI Reference
description: Current Scrapbot command-line interface.
---

All commands run against a project directory. When omitted, the project path defaults to the current directory.

## Machine-readable output

`init`, `check`, `build`, and `run` accept `--json`. JSON mode emits exactly one document to stdout and suppresses project log lines:

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

Builds native extension targets and creates a runnable package under `build/<target>`. The package contains a renamed Scrapbot executable, project runtime data, and only the active compiled native extension artifacts. Native extension source and generated editor metadata are omitted.

The default target is the current host, such as `darwin_arm64` or `linux_amd64`. `--target host` is an explicit alias for it. Other Odin targets are modeled but currently rejected because Scrapbot does not yet provide target-built Luau, SDL3, and WGPU dependencies.

Run the packaged executable directly. It defaults to a windowed WGPU game; renderer and bounded-run options remain available for testing:

```sh
build/darwin_arm64/my-game
build/darwin_arm64/my-game --backend null --frames 1 --json
```

Successful JSON results include `target`, `output_directory`, and `executable` fields. Unsupported targets report `SCRAPBOT_UNSUPPORTED_TARGET`.

## `scrapbot check`

```sh
scrapbot check [path] [--json]
```

Performs project validation:

- reads `project.toml`;
- builds declared native extensions;
- loads native extension schemas and system declarations;
- builds the ECS world from the default scene;
- executes `scripts/main.luau` silently to collect schemas and systems;
- validates scene component data against the registry;
- refreshes `.scrapbot/types/scrapbot.d.luau`;
- runs `luau-analyze` when available.

## `scrapbot run`

```sh
scrapbot run [path] [--backend null|wgpu] [--window|--headless] [--hot-reload|--no-hot-reload] [--editor] [--scheduler-trace] [--runtime-stats] [--frames n] [--framegrab out.png] [--framegrab-region x,y,width,height] [--ui-script actions.json] [--ui-dump tree.json] [--json]
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
| `--headless` | Run without a visible window; select the null backend or request a WGPU framegrab. |
| `--editor` | Start with the editor shell visible. `Cmd/Ctrl+E` toggles it in a visible window. |
| `--hot-reload` | Explicitly enable the default project-file, script, asset, and native-extension polling. |
| `--no-hot-reload` | Disable source-project hot reload for deterministic runs. |
| `--scheduler-trace` | Print native worker count, parallel stage count, and maximum stage width. |
| `--runtime-stats` | Collect early/late engine-frame timing through render preparation, engine-allocator bytes, and ECS storage checkpoints. Windowed runs also require nonzero `--frames`. |
| `--frames n` | Limit renderer frames. |
| `--framegrab out.png` | Write the final headless WGPU frame to a PNG. |
| `--framegrab-region x,y,width,height` | Export only this top-left-origin 1:1 pixel region; requires `--framegrab`. |
| `--ui-script actions.json` | Replay a versioned semantic UI diagnostic script. A zero `--frames` value becomes a 240-frame safety bound. |
| `--ui-dump tree.json` | Write the final reconciled UI tree, geometry, control kinds, and interaction state as JSON, including on failure. |
| `--json` | Emit one versioned machine-readable result. |

The editor shell keeps the running project live across the complete central viewport with a camera aspect ratio derived from the available space. Transient editor-origin ECS UI entities build the shell, and an editor-origin scene camera navigates without changing the project's camera. Hold right mouse inside the viewport to capture the pointer, look with the mouse, move with WASD, rise with Space, and descend with Ctrl. Clicking rendered geometry selects the nearest project entity, reveals it in the scene sidebar, and drives an editable component inspector. The scene browser and inspector have independent pixel-continuous, smoothly scrolling, clipped panes with proportional scrollbars; neither pane snaps to lines. Selected entities with a Transform expose translation, rotation, and scale gizmo handles plus ECS UI controls for World or Local orientation. Inspector and gizmo gestures enter stopped-mode UUID-addressed undo/redo transactions. Stopped is authoring mode: supported scene-entity edits can be explicitly saved with the top-bar Save control or `Ctrl/Cmd+S`; Save compares dirty candidates with the disk-authored baseline and changes only semantically different fields. Revert discards unsaved authoring, clears history, and reloads scene entities from disk without reloading code or resources. Play snapshots the current authoring state in memory, and Stop restores that state while discarding playback mutations and runtime spawns. Runtime entities and running/paused mutations are never persisted. The browser distinguishes scene-authored names from runtime-spawned names and hides editor-origin entities. Combine `--editor`, `--headless`, `--ui-script`, `--ui-dump`, and `--framegrab` to reproduce and inspect editor interactions deterministically. Framegrabs are losslessly compressed; explicit regions or semantic capture targets change the output extent without scaling its pixels. See [Rendering And Testing](/guides/rendering-testing/#semantic-ui-diagnostics) for the script contract.

With `--runtime-stats`, JSON results include a `runtime_stats` object. It reports the frame count, warm-up and sample-window sizes, early and late nanoseconds per engine frame, their ratio, engine-allocator bytes, and early/late/peak/final ECS storage slot counts. Timing covers systems, engine UI/editor updates, render reconciliation, extraction, and batching preparation; it excludes GPU command encoding, submission, and execution. `allocator_final_bytes` is captured after project runtime teardown. Allocator numbers cover allocations routed through Odin's engine allocator; direct Luau, SDL, WGPU, driver, GPU, and OS allocations are outside this report.

JSON run results also include `render_stats`. For WGPU it reports whether compute culling is active; draw-database, instance-slot, and visibility-buffer capacities; database rebuilds and cumulative instance uploads; frustum candidates, visible and occlusion-rejected instances; per-LOD visible counts; Hi-Z state; and retained-UI vertex rebuild/upload counters, including separate project, editor, and editor-world overlay rebuild counts. When the adapter supports timestamp queries, `gpu_timestamps_supported` and `gpu_timestamps_valid` qualify asynchronous `gpu_frame_ms`, `gpu_cull_ms`, `gpu_shadow_ms`, `gpu_depth_ms`, `gpu_world_ms`, `gpu_hiz_ms`, `gpu_bloom_ms`, `gpu_composite_ms`, and `gpu_ui_ms` samples. Visibility counters and timestamps use multi-frame readback rings: the renderer never waits synchronously and retains the latest completed sample when a frame has no new result.

## `scrapbot help`

```sh
scrapbot help <command>
scrapbot --version
```

Prints generated command help or the engine version.
