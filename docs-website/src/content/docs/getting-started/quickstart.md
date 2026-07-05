---
title: Quickstart
description: Build the CLI, run an example project, and verify a scene with Scrapbot's headless tools.
---

Scrapbot uses `mise` for local tool versions and task shortcuts.

## Platform Setup

Scrapbot builds with Zig and uses SDL3 for `scrapbot run`. Install SDL3 before building the headful runner.

### macOS

Install SDL3 with Homebrew:

```sh
brew install sdl3
```

Then build normally:

```sh
mise build
```

### Linux

Install SDL3 plus a Vulkan runtime. On Ubuntu or Debian systems with SDL3 packages:

```sh
sudo apt install libsdl3-dev
```

For CI or headless machines that need render and bounded window smoke coverage, also install Vulkan software drivers and Xvfb:

```sh
sudo apt install libvulkan1 mesa-vulkan-drivers xvfb
```

Then build normally:

```sh
mise build
```

### Windows

Use the MSVC toolchain and install SDL3 with vcpkg:

```powershell
vcpkg install sdl3:x64-windows
```

Build with the Windows MSVC target and pass the vcpkg SDL3 paths:

```powershell
zig build -Dtarget=x86_64-windows-msvc `
  -Dsdl3_include_path="$env:VCPKG_INSTALLATION_ROOT\installed\x64-windows\include" `
  -Dsdl3_library_path="$env:VCPKG_INSTALLATION_ROOT\installed\x64-windows\lib"
```

Copy `SDL3.dll` from the vcpkg `bin` directory next to `scrapbot.exe` before running the CLI:

```powershell
Copy-Item "$env:VCPKG_INSTALLATION_ROOT\installed\x64-windows\bin\SDL3.dll" zig-out\bin\
```

## Build the CLI

From the repository root:

```sh
mise build
```

This builds the optimized `scrapbot` CLI into `zig-out/bin/scrapbot`.

For Debug safety checks, use:

```sh
mise build-debug
```

## Create a Project

Create a project directory and run `scrapbot init` inside it:

```sh
mkdir mygame
cd mygame
scrapbot init
```

The command writes `project.toml`, `scenes/main.scene.toml`, and `assets/.gitkeep`. The generated scene is script-free and contains a renderer singleton, cube, camera, and directional light, so it can be validated immediately:

```sh
scrapbot check
```

`scrapbot init` does not overwrite an existing project. If the target directory already contains `project.toml` or legacy `project.scrapbot.toml`, the command fails.

## Run a Project

Run the showcase example in a headful window:

```sh
scrapbot run examples/showcase
```

Show the editor/debug overlay on startup:

```sh
scrapbot run examples/showcase --editor
```

In a headful run, press `Ctrl+Tab` to toggle the overlay. The overlay shows FPS plus rolling system timings for project systems and engine-internal render systems.

## Validate and Step

Check project metadata, scene data, script declarations, native registrations, and schedule construction:

```sh
scrapbot check examples/showcase
```

Step a project headlessly:

```sh
scrapbot step examples/showcase --frames 8 --dt 0.05
```

JSON output is available for agent and editor workflows:

```sh
scrapbot check examples/showcase --format json
scrapbot step examples/showcase --frames 8 --format json
```

## Render and Verify

Render one deterministic PNG artifact:

```sh
scrapbot render examples/showcase zig-out/showcase.png
```

Run an offscreen render verification:

```sh
scrapbot render-test examples/showcase zig-out/showcase-render-test.png
```

Render tests check that a frame is nonblank and has expected visible foreground content. They are the preferred automation surface for renderer changes.

## Run the Suite

Run all automated coverage currently wired into the repository:

```sh
mise test
```

The full suite includes Zig tests, project-shaped gameplay tests, a benchmark smoke test, and offscreen render verifications for the example projects.

## Useful Examples

- `examples/minimal/`: canonical smoke-test project.
- `examples/showcase/`: text-authored renderables, scripted animation, camera, and lighting.
- `examples/spawn_swarm/`: larger script-spawned scene with batching and editor profiling.
- `examples/ui_gallery/`: retained ECS UI primitives and layout controls.
- `examples/native_motion/`: project-local Zig native module.
