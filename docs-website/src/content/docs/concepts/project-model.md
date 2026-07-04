---
title: Project Model
description: How Machina projects, scenes, scripts, native modules, and generated files fit together.
---

A Machina project is a directory with a `project.machina.toml` manifest.

The manifest names the project, points at the default scene, lists scripts, and may declare one project-local native Zig module:

```toml
name = "Showcase"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/gameplay.luau"]
native = "native/game.zig"
```

## Directory Shape

A typical project looks like this:

```txt
project/
  project.machina.toml
  scenes/
    main.scene.toml
  scripts/
    gameplay.luau
  native/
    game.zig
```

Only the manifest and scene are required. Scripts and native modules are optional.

Use `machina init [path]` to create this required shape. The command writes a manifest and default scene, creates the target directory when needed, and refuses to overwrite an existing `project.machina.toml`.

## Text-First Runtime Data

Machina keeps core project state text-based:

- Project manifests are TOML.
- Scenes are TOML.
- Gameplay scripts are Luau.
- Native systems are Zig source files.
- Generated caches live under `.machina/` and should not be committed.

Assets can still be binary. The text-first rule applies to authored project structure and runtime data, not to images, audio, or future imported assets.

## Load Order

When Machina loads a project, it builds one component registry and schedule from engine, native, and script declarations:

1. Register engine components such as `machina.transform`, `machina.geometry.primitive`, and `machina.ui.text`.
2. Build and load the optional project-local native module.
3. Register native components.
4. Load Luau scripts so they can reference native components.
5. Register Luau components.
6. Register native systems.
7. Register Luau systems.
8. Build the runtime schedule from all declared system dependencies.
9. Validate the active scene against the resulting registry.

This order lets Luau reference native-defined components and lets native systems read or write Luau-defined components.

## One Runtime, Multiple Modes

The same project can run in several modes:

```sh
machina check .
machina step . --frames 60
machina bench . --frames 240
machina test .
machina run . --editor
machina render . output.bmp
machina render --editor --select some-entity . editor-output.bmp
machina render-test . output.bmp
```

Headless commands are first-class. They exist so humans, editors, CI, and coding agents can inspect behavior without driving a window.

## Generated Native Cache

During development, a project-local native module is built as a dynamic library under `.machina/native/`.

That cache is an implementation detail of the development loop:

- Do not commit generated `.machina/` directories.
- Keep native source in the project, usually `native/game.zig`.
- Future shipping builds are expected to statically link the same registration source on targets that cannot load dynamic code.
