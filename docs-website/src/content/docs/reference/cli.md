---
title: CLI Reference
description: Commands exposed by the Machina CLI.
---

Machina is operated through one CLI binary.

```txt
machina - agent-native game engine

Usage:
  machina --version
  machina help
  machina init [path]
  machina check [path] [--format text|json]
  machina step [path] [--frames N] [--dt seconds] [--format text|json]
  machina bench [path] [--frames N] [--dt seconds] [--format text|json]
  machina test [tests-path|project-path] [--format text|json]
  machina run [path] [--frames N] [--editor]
  machina render [--editor] [--select entity-id] [path] [output.bmp]
  machina render-test [--editor] [--select entity-id] [path] [output.bmp]
```

## Commands

| Command | Purpose |
| --- | --- |
| `machina --version` | Print the CLI version. |
| `machina help` | Print command usage. |
| `machina init [path]` | Create a fresh project in the current or specified directory. |
| `machina check [path]` | Validate project, scene, scripts, native code, and schedule. |
| `machina step [path]` | Run deterministic headless simulation frames. |
| `machina bench [path]` | Run headless benchmark smoke coverage. |
| `machina test [path]` | Run game-shaped project tests. |
| `machina run [path]` | Run a headful interactive project. |
| `machina render [--editor] [--select entity-id] [path] [output.bmp]` | Render one offscreen BMP artifact. |
| `machina render-test [--editor] [--select entity-id] [path] [output.bmp]` | Render and verify visible output. |

## Format Options

These commands support `--format text|json`:

- `check`
- `step`
- `bench`
- `test`

Use JSON for editor, CI, and agent integrations.

## Init

```sh
mkdir mygame
cd mygame
machina init
```

`machina init` creates a project in the current directory by default. The usual workflow is to create a project directory, enter it, and run `machina init`.

Passing a path also works:

```sh
machina init games/hello-machina
```

Machina creates the target directory when needed and uses the final path segment as the project name.

A fresh project contains:

- `project.machina.toml`
- `scenes/main.scene.toml`
- a script-free scene with a cube, camera, and directional light

The command is non-destructive. If `project.machina.toml` already exists in the target directory, `machina init` fails instead of overwriting project files.

## Render Options

```sh
machina render examples/native_motion zig-out/native-motion.bmp
machina render --editor --select native-cyan-box examples/native_motion zig-out/native-motion-editor.bmp
```

- `--editor` renders the engine editor shell into the offscreen frame.
- `--select entity-id` implies `--editor` and preselects a scene entity for inspector layout verification.

## Run Options

```sh
machina run examples/showcase --frames 240
machina run examples/showcase --editor
```

- `--frames N` exits after a bounded number of frames.
- `--editor` starts with the editor/debug overlay visible.

## Timestep Options

`step` and `bench` accept:

- `--frames N`
- `--dt seconds`

Example:

```sh
machina step examples/showcase --frames 8 --dt 0.05
```
