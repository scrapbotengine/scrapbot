---
title: Quickstart
description: Build the CLI, run an example project, and verify a scene with Machina's headless tools.
---

Machina uses `mise` for local tool versions and task shortcuts.

## Platform Setup

Machina builds with Zig and uses SDL3 for `machina run`. Install SDL3 before building the headful runner.

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

Copy `SDL3.dll` from the vcpkg `bin` directory next to `machina.exe` before running the CLI:

```powershell
Copy-Item "$env:VCPKG_INSTALLATION_ROOT\installed\x64-windows\bin\SDL3.dll" zig-out\bin\
```

## Build the CLI

From the repository root:

```sh
mise build
```

This builds the optimized `machina` CLI into `zig-out/bin/machina`.

For Debug safety checks, use:

```sh
mise build-debug
```

## Create a Project

Create a project directory and run `machina init` inside it:

```sh
mkdir mygame
cd mygame
machina init
```

The command writes `project.machina.toml` and `scenes/main.scene.toml`. The generated scene is script-free and contains a cube, camera, and directional light, so it can be validated immediately:

```sh
machina check
```

`machina init` does not overwrite an existing project. If the target directory already contains `project.machina.toml`, the command fails.

## Run a Project

Run the showcase example in a headful window:

```sh
machina run examples/showcase
```

Show the editor/debug overlay on startup:

```sh
machina run examples/showcase --editor
```

In a headful run, press `Ctrl+Tab` to toggle the overlay. The overlay shows FPS plus rolling system timings for project systems and engine-internal render systems.

## Validate and Step

Check project metadata, scene data, script declarations, native registrations, and schedule construction:

```sh
machina check examples/showcase
```

Step a project headlessly:

```sh
machina step examples/showcase --frames 8 --dt 0.05
```

JSON output is available for agent and editor workflows:

```sh
machina check examples/showcase --format json
machina step examples/showcase --frames 8 --format json
```

## Render and Verify

Render one deterministic BMP artifact:

```sh
machina render examples/showcase zig-out/showcase.bmp
```

Run an offscreen render verification:

```sh
machina render-test examples/showcase zig-out/showcase-render-test.bmp
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
- `examples/comet_garden/`: startup-spawned entities, deferred lifecycle commands, and buffer-backed hot loops.
- `examples/spawn_swarm/`: larger script-spawned scene with batching and editor profiling.
- `examples/native_motion/`: project-local Zig native module.
- `examples/ui_overlay/`: retained ECS UI primitives.
