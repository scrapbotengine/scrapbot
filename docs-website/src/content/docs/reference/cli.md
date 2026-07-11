---
title: CLI Reference
description: Current Scrapbot command-line interface.
---

All commands run against a project directory. When omitted, the project path defaults to the current directory.

## `scrapbot init`

```sh
scrapbot init [path] [name]
```

Creates a project with:

- `project.toml`
- `scenes/main.scene.toml`
- `scripts/main.luau`
- `types/scrapbot.d.luau`
- `.vscode/settings.json`

## `scrapbot build`

```sh
scrapbot build [path]
```

Builds native extension targets declared in `project.toml` into `build/extensions`.

## `scrapbot check`

```sh
scrapbot check [path]
```

Performs project validation:

- reads `project.toml`;
- builds declared native extensions;
- loads native extension schemas;
- builds the ECS world from the default scene;
- executes `scripts/main.luau` silently to collect schemas and systems;
- validates scene component data against the registry;
- refreshes `types/scrapbot.d.luau`;
- runs `luau-analyze` when available.

## `scrapbot run`

```sh
scrapbot run [path] [--backend null|wgpu] [--window] [--hot-reload] [--frames n] [--framegrab out.png]
```

Runs a project through the selected renderer backend.

Options:

| Option | Meaning |
| --- | --- |
| `--backend null` | Use the headless null renderer. |
| `--backend wgpu` | Use the WebGPU renderer. |
| `--window` | Open a platform window. |
| `--headless` | Force headless mode. |
| `--hot-reload` | Poll project files, scripts, and native extension source/output changes while running. |
| `--frames n` | Limit renderer frames. |
| `--framegrab out.png` | Write the final headless WGPU frame to a PNG. |

## `scrapbot help`

```sh
scrapbot help <command>
scrapbot --version
```

Prints generated command help or the engine version.
