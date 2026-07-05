---
title: Scene Authoring
description: How text-authored scenes define entities and component data.
---

Scenes are TOML files made of entity records. Each entity has a stable `id`, a display `name`, and zero or more component tables.

```toml
name = "Main"
version = 1

[[entities]]
id = "player"
name = "Player"

[entities.components."machina.transform"]
position = [0.0, 0.0, 0.0]
rotation = [0.0, 0.0, 0.0]
scale = [1.0, 1.0, 1.0]
```

## Entity IDs

Entity ids are stable text ids used by scene data, tests, diagnostics, and runtime lookup.

Use ids that are:

- Stable across edits.
- Meaningful in diagnostics.
- Unique within a scene.

Entities loaded from scene TOML are authored entities. Runtime systems can also spawn entities while the project runs; those spawned entities share the same ECS world, but they are not scene-authored data.

## Component Tables

Component tables live under `entities.components`.

Engine component ids are qualified under `machina.*`:

```toml
[entities.components."machina.geometry.primitive"]
primitive = "uv_sphere"
segments = 32
rings = 16
```

Project-local component ids can be single lowercase ASCII segments:

```toml
[entities.components.spin]
angular_velocity = [0.0, 1.2, 0.0]
```

Qualified dotted ids are reserved for packages and libraries. `machina.*` is engine-owned.

## Validation

Scene component ids and fields must validate against the active component registry.

The registry includes:

- Built-in engine components.
- Components registered by the optional native Zig module.
- Components registered by Luau scripts.

Run validation with:

```sh
machina check path/to/project
```

Use JSON output when integrating with editor or agent workflows:

```sh
machina check path/to/project --format json
```

## Scene-Driven Rendering

Renderable scene entities usually combine:

- `machina.transform`
- `machina.geometry.primitive`
- `machina.material.surface`

Example:

```toml
[[entities]]
id = "warm-sphere"
name = "Warm Sphere"

[entities.components."machina.transform"]
position = [-1.42, -0.24, -0.48]
rotation = [0.15, 0.1, 0.25]
scale = [0.46, 0.46, 0.46]

[entities.components."machina.geometry.primitive"]
primitive = "uv_sphere"
segments = 32
rings = 16

[entities.components."machina.material.surface"]
base_color = [1.0, 0.5, 0.08]
```

## Runtime-Spawned Scenes

Scenes can also start nearly empty and let startup systems build the world.

That pattern is useful for:

- Procedural examples.
- Tests that prove lifecycle APIs.
- Scenes with many similar entities.

Startup-spawned data is still ECS data. It participates in rendering, batching, tests, and diagnostics after the startup systems run, but it is not persisted as scene TOML unless a future editor save flow explicitly authors it.
