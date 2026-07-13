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
rotation = [-0.321751, 0, 0]
scale = [1, 1, 1]
```

Camera:

```toml
[entities.camera]
fov = 60
near = 0.1
far = 100
```

A camera reads its position and Euler orientation from the entity's transform. Rotation is expressed in radians: X controls pitch, Y controls yaw, and Z controls roll.

Mesh:

```toml
[entities.geometry]
resource = "cube"

[entities.material]
resource = "coral"
```

Geometry and material names resolve against resources created by project Luau or native Odin code. Entities become renderable once transform, geometry, and material references are valid.

Lights:

```toml
[entities.ambient_light]
color = [0.3, 0.35, 0.45]
intensity = 0.25

[entities.directional_light]
direction = [-0.5, -1, -0.3]
color = [1, 0.95, 0.85]
intensity = 0.8

[entities.point_light]
color = [1, 0.2, 0.05]
intensity = 2
range = 6
```

Ambient and directional lights do not need transforms. A point light reads its world-space position from the entity's transform, so moving that transform moves the light.

Directional shadow markers have no fields:

```toml
[entities.shadow_caster]
[entities.shadow_receiver]
```

Casters write to the first directional light's shadow map. Receivers sample it. The markers are independent, so geometry may cast without receiving or receive without casting.

Screen-space UI entities share a retained box model and compose container or content components:

```toml
[[entities]]
name = "HUD"

[entities.ui_layout]
position = [40, 40]
size = [460, 280]
padding = [24, 24, 24, 24]
background = [0.035, 0.055, 0.105, 0.96]
corner_radius = 20

[entities.ui_vstack]
gap = 14

[[entities]]
name = "Title"

[entities.ui_layout]
parent = "HUD"
size = [412, 52]

[entities.ui_text]
text = "SCRAPBOT UI"
color = [0.15, 0.95, 0.82, 1]
size = 32

[[entities]]
name = "Launch"

[entities.ui_layout]
parent = "HUD"
margin = [0, 0, 0, 8]
size = [180, 48]
padding = [13, 18, 11, 18]
background = [0.31, 0.26, 0.86, 1]
corner_radius = 12

[entities.ui_button]
text = "LAUNCH"
color = [1, 1, 1, 1]
size = 16
hover_background = [0.39, 0.33, 0.96, 1]
active_background = [0.22, 0.18, 0.68, 1]
active_color = [0.82, 0.84, 1, 1]
```

Positions and sizes are screen pixels from the top-left. `margin` and `padding` use `[top, right, bottom, left]`. Add `ui_hstack` or `ui_vstack` with a non-negative `gap` to arrange children in scene order; an element without either stack overlays its children. Background corner radii are rendered as signed-distance rounded rectangles. Parent names must resolve to another UI layout entity, cycles are rejected, and one entity cannot combine both stack directions or both text and button content.

Pointer hit testing gives the topmost element under the pointer hover state. Pressing the primary button captures active state on that element until release. Buttons can consume those generic states through `hover_background`, `active_background`, `hover_color`, and `active_color`; a zero-alpha state color falls back to the normal layout background or button text color. Button activation events are not emitted yet.

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
