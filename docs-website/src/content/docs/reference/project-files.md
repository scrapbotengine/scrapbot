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
border_color = [0.18, 0.20, 0.24, 1]
border_width = 2
corner_radius = 20
hidden = false

[entities.ui_vstack]
gap = 14
fill = true
draggable = true
min_size = 64

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

[[entities]]
name = "Player Name"

[entities.ui_layout]
parent = "HUD"
size = [240, 40]
padding = [10, 12, 10, 12]
background = [0.025, 0.03, 0.04, 1]
border_color = [0.16, 0.18, 0.22, 1]
border_width = 1
corner_radius = 6

[entities.ui_input]
text = "SCRAPBOT"
color = [0.92, 0.93, 0.95, 1]
size = 16
selection_background = [0.15, 0.45, 0.40, 0.55]
focus_border_color = [0.15, 0.85, 0.72, 1]
read_only = false

[[entities]]
name = "Feature Scroll"

[entities.ui_layout]
parent = "HUD"
size = [412, 160]
padding = [8, 8, 8, 8]
background = [0.08, 0.09, 0.11, 1]
corner_radius = 10

[entities.ui_scroll_area]
scroll_speed = 64
smoothness = 14

[[entities]]
name = "Feature Pane"

[entities.ui_layout]
parent = "Feature Scroll"
size = [396, 360]

[entities.ui_vstack]
gap = 8
```

Positions and sizes are screen pixels from the top-left. `margin` and `padding` use `[top, right, bottom, left]`. `border_color` and non-negative `border_width` add an inset signed-distance border that follows `corner_radius`. `hidden = true` removes the box and its descendant subtree from layout, paint, and interaction without despawning their entities. Add `ui_hstack` or `ui_vstack` with a non-negative `gap` to arrange children in scene order; an element without either stack overlays its children inside the parent's padded content box. Set `fill = true` to treat authored child sizes as proportions along the stack axis and fill the available cross-axis. Add `draggable = true` to turn the gaps into pointer-draggable separators; `min_size` sets the non-negative minimum pane extent on the stack axis. Draggable stacks must also enable fill. Backgrounds, borders, and corner radii are rendered from the same signed-distance rounded rectangle. Parent names must resolve to another UI layout entity, cycles are rejected, and one entity cannot combine both stack directions or more than one of `ui_text`, `ui_button`, and `ui_input`.

Pointer hit testing gives the topmost element under the pointer hover state. Pressing the primary button captures active state on that element until release. Buttons can consume those generic states through `hover_background`, `active_background`, `hover_color`, and `active_color`; a zero-alpha state color falls back to the normal layout background or button text color. Button activation events are not emitted yet.

Clicking a `ui_input` focuses it and selects all its text. Focused inputs support typed single-line ASCII text, Left/Right/Home/End movement, Shift selection, Backspace/Delete, Select All, and paint-order Tab/Shift+Tab traversal. Enter accepts the current value and removes focus; Escape restores the text present when focus began. The component's `text` field changes during editing. Set `read_only = true` to retain focus, selection, and traversal without allowing mutation. Clipboard operations, IME composition, Unicode shaping, multiline editing, and public change/commit events are not implemented yet.

A `ui_scroll_area` clips descendants to its padded content rectangle and scrolls vertically when the pointer wheel is over it. Give its nested pane an explicit size larger than the viewport; that pane may contain overlays or stacks of any size. `scroll_speed` is the target movement per wheel unit and `smoothness` controls frame-time interpolation toward that target. Both must be positive. Nested scroll clips intersect, and only the topmost hovered scroll area consumes a wheel update.

Panels add a styled title band without choosing how their children flow, so they can compose with an overlay, stack, or nested table. Tables place children in row-major order across 1–64 equal-width columns. Child heights determine row height; `column_gap` and `row_gap` control spacing. A partial final row starts at the first column.

```toml
[[entities]]
name = "Stats Panel"

[entities.ui_layout]
size = [360, 150]
padding = [8, 10, 10, 10]
background = [0.06, 0.065, 0.075, 1]
border_color = [0.18, 0.19, 0.22, 1]
border_width = 1
corner_radius = 6

[entities.ui_panel]
title = "RENDER STATS"
title_color = [0.9, 0.91, 0.93, 1]
title_background = [0.10, 0.105, 0.12, 1]
title_size = 11
title_height = 28

[entities.ui_vstack]

[[entities]]
name = "Stats Table"

[entities.ui_layout]
parent = "Stats Panel"
size = [340, 100]

[entities.ui_table]
columns = 3
column_gap = 8
row_gap = 4
```

Each child of `Stats Table` occupies the next table cell. A table is a flow container and therefore cannot share an entity with `ui_hstack` or `ui_vstack`; a panel is decoration and may share an entity with either stack.

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
