---
title: Geometry and Materials
description: Author renderable meshes with built-in geometry primitives and surface materials.
---

The preferred renderable path is:

- `scrapbot.transform`
- `scrapbot.geometry.primitive`
- `scrapbot.material.surface`

## Transform

```toml
[entities.components."scrapbot.transform"]
position = [0.0, 0.0, 0.0]
rotation = [0.0, 0.0, 0.0]
scale = [1.0, 1.0, 1.0]
```

Fields:

| Field | Type |
| --- | --- |
| `position` | `vec3` |
| `rotation` | `vec3` |
| `scale` | `vec3` |

## Geometry Primitive

```toml
[entities.components."scrapbot.geometry.primitive"]
primitive = "uv_sphere"
segments = 32
rings = 16
```

Fields:

| Field | Type | Notes |
| --- | --- | --- |
| `primitive` | `string` | `box`, `plane`, `uv_sphere`, or `ico_sphere`. |
| `segments` | `int` | Used by sphere generators. Use `0` for primitives that ignore it. |
| `rings` | `int` | Used by UV sphere generation. Use `0` for primitives that ignore it. |

## Surface Material

```toml
[entities.components."scrapbot.material.surface"]
base_color = [0.0, 0.56, 1.0]
```

Fields:

| Field | Type | Notes |
| --- | --- | --- |
| `base_color` | `vec3` | RGB values in the `0.0` to `1.0` range. |

## Built-In Primitive Examples

Box:

```toml
[entities.components."scrapbot.geometry.primitive"]
primitive = "box"
segments = 0
rings = 0
```

Plane:

```toml
[entities.components."scrapbot.geometry.primitive"]
primitive = "plane"
segments = 0
rings = 0
```

UV sphere:

```toml
[entities.components."scrapbot.geometry.primitive"]
primitive = "uv_sphere"
segments = 32
rings = 16
```

Ico sphere:

```toml
[entities.components."scrapbot.geometry.primitive"]
primitive = "ico_sphere"
segments = 2
rings = 0
```

## Legacy Cube Renderer

`scrapbot.render.cube` still exists as a legacy shortcut:

```toml
[entities.components."scrapbot.render.cube"]
color = [0.2, 0.8, 1.0]
```

New scenes should prefer `scrapbot.geometry.primitive` plus `scrapbot.material.surface`.
