---
title: Project File Reference
description: The current manifest and scene file subset supported by Scrapbot.
---

Scrapbot's file formats intentionally cover a narrow subset right now. Valid TOML outside this subset may still fail.

## Manifest

`project.toml` supports:

```toml
name = "Minimal Example"
default_scene = "scenes/main.scene.toml"

[[native_extensions]]
name = "scrappyphysics"
source = "native/scrappyphysics"
```

Fields:

| Field | Required | Meaning |
| --- | --- | --- |
| `name` | Yes | Display name for the project. |
| `default_scene` | Yes | Safe relative path to the scene loaded by `check` and `run`. |
| `[[native_extensions]]` | No | Repeated table for project-local native extension targets. |
| `native_extensions.name` | Yes | Build output base name. Must be an identifier token. |
| `native_extensions.source` | Yes | Safe relative path to an Odin package directory. |

## Scene entities

Entities use repeated `[[entities]]` tables.

```toml
[[entities]]
name = "Main Camera"
```

Every entity must have a name.

## Built-in component sections

Transform:

```toml
[entities.transform]
position = [0, 2, 6]
rotation = [0, 0, 0]
scale = [1, 1, 1]
```

Camera:

```toml
[entities.camera]
fov = 60
near = 0.1
far = 100
```

Mesh:

```toml
[entities.geometry]
resource = "cube"

[entities.material]
resource = "coral"
```

Geometry and material names resolve against resources created by project Luau or native Odin code. Entities become renderable once transform, geometry, and material references are valid.

## Custom component sections

```toml
[entities.components.autorotate]
velocity = [0, 1.5707963, 0]

[entities.components.scrappyphysics.rigidbody]
velocity = [0, 0, 0]
```

Rules:

- single-token names are project components;
- dotted names are engine or library components;
- fields are single-token names;
- the current supported field value is a vec3 array;
- scene data must match a component schema collected from the engine, Luau, or native extensions.
