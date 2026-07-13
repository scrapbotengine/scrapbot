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
- `scripts/main.luau`
- `assets/`
- `types/scrapbot.d.luau`
- `.vscode/settings.json`

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
- refreshes `types/scrapbot.d.luau`;
- runs `luau-analyze` when available.

## `scrapbot run`

```sh
scrapbot run [path] [--backend null|wgpu] [--window] [--editor] [--hot-reload] [--scheduler-trace] [--runtime-stats] [--frames n] [--framegrab out.png] [--framegrab-region x,y,width,height] [--json]
```

Runs a project through the selected renderer backend after stepping registered native and Luau systems.

Options:

| Option | Meaning |
| --- | --- |
| `--backend null` | Use the headless null renderer. |
| `--backend wgpu` | Use the WebGPU renderer. |
| `--window` | Open a platform window. |
| `--headless` | Force headless mode. |
| `--editor` | Start with the editor shell visible. `Ctrl+Esc` toggles it in a visible window. |
| `--hot-reload` | Poll project files, scripts, and native extension source/output changes while running. |
| `--scheduler-trace` | Print native worker count, parallel stage count, and maximum stage width. |
| `--runtime-stats` | Collect early/late engine-frame timing through render preparation, engine-allocator bytes, and ECS storage checkpoints. Windowed runs also require nonzero `--frames`. |
| `--frames n` | Limit renderer frames. |
| `--framegrab out.png` | Write the final headless WGPU frame to a PNG. |
| `--framegrab-region x,y,width,height` | Export only this top-left-origin 1:1 pixel region; requires `--framegrab`. |
| `--json` | Emit one versioned machine-readable result. |

The editor shell keeps the running project live across the complete central viewport with a camera aspect ratio derived from the available space. It creates an inspectable editor-origin scene camera without changing the project's camera. Hold right mouse inside the viewport to capture the pointer, look with the mouse, move with WASD, rise with Space, and descend with Ctrl. Clicking rendered geometry selects the nearest entity, reveals it in the scene sidebar, and drives a read-only inspector containing component fields and live values. The scene browser and inspector have independent pixel-continuous, smoothly scrolling, clipped panes with proportional scrollbars; neither pane snaps to lines. Selected entities with a Transform expose functional world-space X/Y/Z translation handles; these edits affect only the running world for now. The browser distinguishes scene-authored, runtime-spawned, and editor-owned entities. Combine `--editor`, `--headless`, and `--framegrab` to capture the editor deterministically. Framegrabs are losslessly compressed; region export changes the output extent without scaling its pixels.

With `--runtime-stats`, JSON results include a `runtime_stats` object. It reports the frame count, warm-up and sample-window sizes, early and late nanoseconds per engine frame, their ratio, engine-allocator bytes, and early/late/peak/final ECS storage slot counts. Timing covers systems, engine UI/editor updates, render reconciliation, extraction, and batching preparation; it excludes GPU command encoding, submission, and execution. `allocator_final_bytes` is captured after project runtime teardown. Allocator numbers cover allocations routed through Odin's engine allocator; direct Luau, SDL, WGPU, driver, GPU, and OS allocations are outside this report.

## `scrapbot help`

```sh
scrapbot help <command>
scrapbot --version
```

Prints generated command help or the engine version.
