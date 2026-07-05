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
  machina build [path] [--output DIR] [--name NAME] [--force] [--format text|json]
  machina run [path] [--frames N] [--editor] [--hidden]
  machina render [--editor] [--select entity-id] [--frames N] [--width PX] [--height PX] [--pixel-scale S] [path] [output.png]
  machina render-test [--editor] [--select entity-id] [--frames N] [--width PX] [--height PX] [--pixel-scale S] [path] [output.png]
  machina visual-test [--editor] [--select entity-id] [--frames N] [--width PX] [--height PX] [--pixel-scale S] [--update] <path> <expected.png> [actual.png]
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
| `machina build [path]` | Package a host-platform runnable bundle. |
| `machina run [path]` | Run a headful interactive project. |
| `machina render [--editor] [--select entity-id] [--frames N] [--width PX] [--height PX] [--pixel-scale S] [path] [output.png]` | Render one or more offscreen frames to a PNG artifact. |
| `machina render-test [--editor] [--select entity-id] [--frames N] [--width PX] [--height PX] [--pixel-scale S] [path] [output.png]` | Render and verify visible output. |
| `machina visual-test [--editor] [--select entity-id] [--frames N] [--width PX] [--height PX] [--pixel-scale S] [--update] <path> <expected.png> [actual.png]` | Render and compare a golden visual fixture. |

## Format Options

These commands support `--format text|json`:

- `check`
- `step`
- `bench`
- `test`
- `build`

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

- `project.toml`
- `scenes/main.scene.toml`
- `assets/.gitkeep`
- a script-free scene with a cube, camera, and directional light

The command is non-destructive. If `project.toml` or legacy `project.machina.toml` already exists in the target directory, `machina init` fails instead of overwriting project files.

## Build Options

```sh
machina build examples/showcase
machina build examples/native_motion --output zig-out/packages --name native-motion --force
```

`machina build` validates the project and writes a host-platform bundle. The default output root is `build` inside the project directory, and the default bundle name is based on the project name and host platform.

- `--output DIR` chooses the output root.
- `--name NAME` chooses the bundle directory name.
- `--force` replaces an existing Machina-generated bundle.
- `--format json` emits machine-readable build output.

The bundle contains `bin/machina`, a copied `project/` directory, a `run` launcher, and `machina-build.json`. Project-local native Zig modules are compiled into a packaged `native_artifact`, so the bundled project does not need Zig installed to load native systems. When SDL3 is discoverable locally, it is copied into `lib/` and the launcher adds that directory to the platform library search path.

The first build format targets the current OS and architecture only. Cross-platform export, app signing, and fully static project-native executables are future packaging work.

For platform-specific bundle notes, see [Building Games](/workflow/building-games/).

## Render Options

```sh
machina render examples/native_motion zig-out/native-motion.png
machina render --editor --select native-cyan-box examples/native_motion zig-out/native-motion-editor.png
machina render examples/showcase --width 1280 --height 720 zig-out/showcase.png
machina render --editor --width 2560 --height 1800 --pixel-scale 2 examples/minimal zig-out/editor-hidpi.png
```

- `--editor` renders the engine editor shell into the offscreen frame.
- `--select entity-id` implies `--editor` and preselects a scene entity for inspector layout verification.
- `--frames N` renders multiple fixed-step offscreen frames and writes the final frame. The default is one startup frame.
- `--width PX` and `--height PX` set the physical offscreen output size in positive integer pixels.
- `--pixel-scale S` sets physical pixels per logical pixel for offscreen editor/UI verification. Render output also writes a `.metadata.json` sidecar with physical size, logical size, and pixel scale.

## Visual Test Options

```sh
machina visual-test tests/golden/postprocess_effects tests/golden/postprocess_effects/expected.png zig-out/postprocess-effects-actual.png
machina visual-test --update tests/golden/postprocess_effects tests/golden/postprocess_effects/expected.png
```

`visual-test` renders the project offscreen, compares the actual image against a checked-in golden image, and reports max channel delta, mean channel delta, and changed-pixel ratio. Use `--update` only when the current renderer output is the intended new baseline.

- `--frames N` renders multiple fixed-step offscreen frames and compares or updates the final frame. The default is one startup frame.
- `--width PX` and `--height PX` set the physical offscreen output size in positive integer pixels.
- `--pixel-scale S` sets physical pixels per logical pixel for offscreen editor/UI verification.

## Run Options

```sh
machina run examples/showcase --frames 240
machina run examples/showcase --editor
machina run examples/showcase --hidden --frames 2
```

- `--frames N` exits after a bounded number of frames.
- `--editor` starts with the editor/debug overlay visible.
- `--hidden` creates the window and presentation surface without showing a normal visible window. It requires `--frames N`.

## Timestep Options

`step` and `bench` accept:

- `--frames N`
- `--dt seconds`

Example:

```sh
machina step examples/showcase --frames 8 --dt 0.05
```
