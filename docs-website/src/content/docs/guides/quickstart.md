---
title: Quickstart
description: Build Scrapbot, create or run a project, and verify the current engine slice.
---

Scrapbot is developed from the repository root. The current workflow uses `mise` tasks to build the Odin CLI and vendored Luau libraries.

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

`run` builds declared native extensions, loads the scene into the ECS world, executes `scripts/main.luau`, steps registered native and Luau systems, and renders through the selected backend.

The minimal example intentionally contains both sides of the current ECS authoring model: Luau registers a project-level `float` component and bounded floating system, while the project-local Odin extension registers `scrappyphysics.*` components and native systems.

## Run the ECS showcase

```sh
mise scrapbot -- check examples/ecs-showcase
mise scrapbot -- run examples/ecs-showcase --backend null --frames 540
```

The ECS showcase is a denser project for exercising the runtime. It combines a Luau-defined floating component and system with Odin-defined `showcase.*` components, scheduled native systems, component add/remove commands, despawn, and native entity spawning.

## Create a new project

```sh
mise scrapbot -- init my-game "My Game"
mise scrapbot -- check my-game
mise scrapbot -- run my-game
```

Generated projects include:

- `project.toml`
- `scenes/main.scene.toml`
- `scripts/main.luau`
- `types/scrapbot.d.luau`
- `.vscode/settings.json`

## Useful commands

```sh
mise test
bin/scrapbot --version
bin/scrapbot help run
bin/scrapbot help build
```

Use `mise test` before committing engine changes. It builds the CLI, runs Odin package tests, checks the minimal example, and runs the null renderer smoke path.

## Renderer smoke tests

The null backend is the default:

```sh
mise scrapbot -- run examples/minimal --backend null
```

Windowed WebGPU opens an SDL3 window:

```sh
bin/scrapbot run examples/minimal --backend wgpu --window --frames 3
```

Headless WebGPU can write a framegrab:

```sh
bin/scrapbot run examples/minimal --backend wgpu --headless --frames 2 --framegrab /tmp/scrapbot-framegrab.png
```

On macOS, WGPU framegrabs still need the platform window system because the current Metal bootstrap uses SDL3 internally.
