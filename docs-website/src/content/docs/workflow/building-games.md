---
title: Building Games
description: Package a Machina project into runnable host-platform bundles for macOS, Linux, and Windows.
---

`machina build` packages a project for the operating system and CPU architecture running the command.

The first build format is a host-platform folder bundle. It is not a cross-platform exporter: to make macOS, Linux, and Windows builds, run `machina build` once on each target platform or in matching CI jobs.

## Build a Bundle

From the engine workspace, build the CLI first:

```sh
mise build
```

Then build a game project:

```sh
zig-out/bin/machina build examples/minimal
```

The default output root is `build` inside the project directory. The default bundle name uses the project name plus the host platform, such as `minimal-aarch64-macos`.

Use `--output` and `--name` when you want predictable distribution paths:

```sh
zig-out/bin/machina build examples/minimal --output dist --name minimal-macos --force
```

The bundle contains:

- `bin/machina` or `bin/machina.exe`
- `project/`, a copied project tree
- `run` or `run.cmd`, the launcher
- `lib/`, for copied runtime libraries such as SDL3 when discoverable
- `machina-build.json`, the build manifest

## macOS

Build on macOS:

```sh
zig-out/bin/machina build path/to/game --output dist --name game-macos --force
```

Run the bundle:

```sh
dist/game-macos/run
```

The launcher adds `lib/` to `DYLD_LIBRARY_PATH` before starting `bin/machina`. When SDL3 is found in common Homebrew locations, the build copies it into `lib/`.

Codesigning, notarization, and `.app` bundle generation are not part of the first build format.

## Linux

Build on Linux:

```sh
zig-out/bin/machina build path/to/game --output dist --name game-linux --force
```

Run the bundle:

```sh
dist/game-linux/run
```

The launcher adds `lib/` to `LD_LIBRARY_PATH` before starting `bin/machina`. If SDL3 is not copied into the bundle, install a compatible SDL3 runtime on the target machine.

## Windows

Build on Windows from a Machina CLI built for Windows:

```powershell
zig-out\bin\machina.exe build path\to\game --output dist --name game-windows --force
```

Run the bundle:

```powershell
dist\game-windows\run.cmd
```

The launcher prepends the bundle's `lib` and `bin` directories to `PATH` before starting `bin\machina.exe`.

The generated `native_artifact` manifest path uses forward slashes because it is project metadata, not a Windows filesystem path.

## Native Zig Projects

Projects with `native = "..."` are built into a packaged dynamic library artifact during `machina build`.

The copied project manifest receives a generated `native_artifact` entry:

```toml
native_artifact = ".machina/build/native/libmachina_project.dylib"
```

On Windows the file name is `machina_project.dll`; on Linux it is `libmachina_project.so`.

Machina validates the copied packaged project before reporting success. That validation loads and registers the packaged native artifact, so ReleaseFast native build, load, and registration failures are reported during `machina build` instead of only when a player launches the bundle.

## Current Limits

- Builds target only the current host OS and architecture.
- There is no `--target` option yet.
- Mobile, console, web, `.app`, installer, codesigning, and notarization workflows are future packaging work.
- Fully static project-native builds require a future Machina SDK or relinkable engine package.
- SDL3 remains the main external runtime dependency risk when it cannot be discovered and copied.
