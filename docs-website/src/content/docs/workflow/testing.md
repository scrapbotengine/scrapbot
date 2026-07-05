---
title: Testing and Verification
description: Validate projects, step simulations, run game-shaped tests, benchmark scenes, and verify renderer output.
---

Machina's headless commands are built for human, CI, editor, and agent workflows.

## Check

Validate a project:

```sh
machina check examples/showcase
```

Check covers project metadata, scene data, component schemas, scripts, native registrations, and schedule construction.

Use JSON when a tool needs structured output:

```sh
machina check examples/showcase --format json
```

## Step

Run deterministic simulation frames without opening a window:

```sh
machina step examples/showcase --frames 8 --dt 0.05
```

Use `step` for narrow ECS and script debugging.

## Project Tests

`machina test` runs game-shaped fixtures from `tests/projects/`.

Each test project has:

- `project.toml`
- A scene.
- Optional scripts.
- Optional native module.
- `test.machina.toml` with frame count, timestep, optional input replay frames, and ECS field assertions.

Example manifest:

```toml
frames = 1
dt = 1.0

[[expect.field]]
entity = "stats"
component = "lifecycle_stats"
field = "spawned_count"
equals_int = 2
```

Input replay frames are one-based and run through the same input, editor, scene UI, command-event, and script update path used by live projects:

```toml
frames = 2
dt = 0.016

[[input.frame]]
frame = 1
pointer = [20.0, 20.0]
wheel_delta = [0.0, -1.0]

[[input.frame]]
frame = 2
debug_overlay_visible = true
viewport = [1280.0, 720.0]
pointer = [36.0, 190.0]
wheel_delta = [0.0, -1.0]
system_profile_count_hint = 9

[[expect.field]]
entity = "scroll"
component = "machina.ui.scroll_view"
field = "content_offset"
equals_vec3 = [0.0, 48.0, 0.0]
```

Pointer button frames can also verify retained UI command routing:

```toml
frames = 1
dt = 0.016

[[input.frame]]
frame = 1
viewport = [1280.0, 720.0]
pointer = [180.0, 148.0]
primary_released = true

[[expect.field]]
entity = "flag"
component = "flag"
field = "active"
equals_bool = true
```

Run all project tests:

```sh
machina test tests/projects
```

Run one fixture:

```sh
machina test tests/projects/native_lifecycle
```

## Benchmarks

`machina bench` runs headless performance smoke coverage:

```sh
machina bench examples/spawn_swarm --frames 240
```

Benchmark output includes scene counts, renderable counts, render batch counts, startup time, update time, and time per frame.

## Render Tests

Render one BMP:

```sh
machina render examples/showcase zig-out/showcase.bmp
```

Render an editor/inspector state without clicking in a headful window:

```sh
machina render --editor --select native-cyan-box examples/native_motion zig-out/native-motion-editor.bmp
```

Render and verify visible output:

```sh
machina render-test examples/showcase zig-out/showcase-render-test.bmp
```

Render tests are deterministic and should be used before relying on headful screenshots for renderer or editor-layout work.

## Full Suite

The repository-level suite is:

```sh
mise test
```

It currently runs:

- Zig unit tests.
- Optimized CLI build.
- All `tests/projects/` fixtures.
- A benchmark smoke test.
- Offscreen render tests for key examples.
