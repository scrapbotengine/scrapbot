---
title: Quickstart
description: Build Scrapbot, create or run a project, and verify the current engine slice.
---

Scrapbot is developed from the repository root. The current workflow uses `mise` tasks to build the Odin CLI and vendored Luau libraries.

## Set up a checkout

```sh
mise setup
```

This installs the pinned tools, initializes Git submodules, downloads checksum-verified external development fixtures, and configures the tracked pre-commit hook. The operation is idempotent.

Heavyweight or license-constrained fixtures are stored as ignored local state instead of Git. `mise setup-assets` installs only those fixtures, while `mise check-assets` verifies an existing installation without accessing the network. These downloads are development inputs and are never included in Scrapbot's own repository or releases. See the tracked `tests/fixtures/external/README.md` for their sources and licenses before packaging or redistributing a fixture-backed example yourself.

The setup task also places required fixture bytes into ignored example asset directories. After running it, launch `mise scrapbot run examples/gltf-showcase --editor` to inspect the pinned Khronos Damaged Helmet through Scrapbot's static glTF importer, generated materials, and live editor. Use `mise scrapbot run examples/sponza --editor` for the heavyweight external-file path: the pinned Khronos atrium imports as 103 ordinary ECS renderables with generated PBR materials, shadows, environment lighting, and clustered point lights.

## Build the CLI

```sh
mise build
```

This writes the local CLI to `bin/scrapbot`.

## Run the minimal example

```sh
mise scrapbot -- check examples/minimal
mise scrapbot -- run examples/minimal
```

`check` validates `project.toml`, builds declared native extensions, loads component schemas, validates the scene, refreshes Luau editor types, and runs Luau static analysis when `luau-analyze` is available.

`run` builds declared native extensions, loads the scene into the ECS world, executes `scripts/main.luau`, steps registered native and Luau systems, and opens a WGPU window with hot reload. Use `--backend null --headless --no-hot-reload --frames 1` for a bounded automation run.

The minimal example intentionally contains both sides of the current ECS authoring model: Luau registers a project-level `float` component and bounded floating system, while the project-local Odin extension registers `scrappyphysics.*` components and native systems.

## Run the ECS showcase

```sh
mise scrapbot -- check examples/ecs-showcase
mise scrapbot -- run examples/ecs-showcase --backend null --headless --no-hot-reload --frames 540
```

The ECS showcase is a denser project for exercising the runtime. It combines a Luau-defined floating marker with an Odin-driven object fountain that spawns visible cube renderables, moves them through native velocity systems, spins them, and despawns them after their lifetimes expire. Two point-light entities orbit through a native ECS system, while a project-local Luau `day_cycle` component and system move the procedural sun through a configurable 30-second day/night cycle.

## Create a new project

```sh
mise scrapbot -- init my-game "My Game"
mise scrapbot -- check my-game
mise scrapbot -- run my-game
```

Generated projects include:

- `project.toml`
- `scenes/main.scene.toml`
- `resources/default.resource.toml`
- `scripts/main.luau`
- `assets/`
- `native/`
- `.scrapbot/types/scrapbot.d.luau`
- `.vscode/settings.json`
- `.gitignore`

Omit the display name to derive it from the destination directory. `init` refuses to overwrite any project file it owns.

## Useful commands

```sh
mise test
bin/scrapbot --version
bin/scrapbot help run
bin/scrapbot help build
```

Use `mise test` before committing engine changes. It builds the CLI, runs Odin package tests, checks the minimal example, and runs the null renderer smoke path.

## Renderer smoke tests

Use the null backend for a fast bounded smoke test without a window:

```sh
mise scrapbot -- run examples/minimal --backend null --headless --no-hot-reload --frames 1
```

Windowed WebGPU opens an SDL3 window:

```sh
bin/scrapbot run examples/minimal --frames 3
```

Press `Cmd/Ctrl+E` during an unbounded windowed run to open Scrapbot's editor shell around the live project. Toggling the shell does not change whether the project is running, paused, or stopped. To start open or capture the shell directly, pass `--editor`:

```sh
bin/scrapbot run examples/ecs-showcase --editor
bin/scrapbot run examples/ecs-showcase --backend wgpu --editor --headless --frames 20 --framegrab /tmp/scrapbot-editor.png
```

The live editor can browse scene-authored and runtime entities, profile systems, inspect and edit component fields, manage entity and component structure, pick geometry in the viewport, fly an independent scene camera, and translate, rotate, or scale selected entities. Play snapshots the current authoring state in memory; Stop restores it after simulation, preserving unsaved authored changes while discarding runtime mutations and unkept runtime entities. Scene changes can then be saved explicitly. See [Live Editor](/guides/live-editor/) for controls and current limitations.

Headless WebGPU can write a framegrab:

```sh
bin/scrapbot run examples/minimal --backend wgpu --headless --frames 2 --framegrab /tmp/scrapbot-framegrab.png
```

On macOS, WGPU framegrabs still need the platform window system because the current Metal bootstrap uses SDL3 internally.
