---
title: Engine Components
description: Built-in Scrapbot component ids, fields, defaults, and authoring rules.
---

Scrapbot registers these engine component types before project scripts and native modules are validated. Scene files can author most `scrapbot.*` components directly under `entities.components`; runtime-only components are documented here so scripts and tools can read their field names and types consistently.

Most component fields are required in scene TOML. The exceptions are listed in the **Scene default** column below. If a component field has no scene default, omitting it makes the scene invalid.

## Authoring Rules

- Engine-owned component ids use the `scrapbot.*` namespace.
- Single lowercase ASCII ids such as `spin` are project-local.
- Qualified dotted ids outside `scrapbot.*` are reserved for packages or libraries.
- Runtime-only components such as `scrapbot.input.*` and `scrapbot.ui.command_event` are written by the engine during execution; do not author them in scene files.
- `scrapbot.renderer` is a scene singleton. A scene with more than one renderer component is invalid.
- New scene renderables should use `scrapbot.geometry.primitive` plus `scrapbot.material.surface`; `scrapbot.render.cube` is a legacy shortcut.

## Rendering

Renderable 3D entities usually combine `scrapbot.transform`, `scrapbot.geometry.primitive`, and `scrapbot.material.surface`.

```toml
[[entities]]
id = "blue-box"
name = "Blue Box"

[entities.components."scrapbot.transform"]
position = [0.0, 0.0, 0.0]
rotation = [0.0, 0.0, 0.0]
scale = [1.0, 1.0, 1.0]

[entities.components."scrapbot.geometry.primitive"]
primitive = "box"
segments = 0
rings = 0

[entities.components."scrapbot.material.surface"]
base_color = [0.0, 0.56, 1.0]
```

### `scrapbot.transform`

Spatial transform used by rendering and gameplay systems.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `position` | `vec3` | Required | World-space position. |
| `rotation` | `vec3` | Required | Euler rotation data used by current render paths. |
| `scale` | `vec3` | Required | Per-axis scale. |

### `scrapbot.geometry.primitive`

Selects a built-in generated mesh.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `primitive` | `string` | Required | `box`, `plane`, `sphere`, `uv_sphere`, `uvsphere`, `ico_sphere`, or `icosphere`. |
| `segments` | `int` | Required | Sphere resolution input. Use `0` for primitives that ignore it. |
| `rings` | `int` | Required | UV sphere ring count. Use `0` for primitives that ignore it. |

Prefer canonical names in new scenes: `box`, `plane`, `uv_sphere`, and `ico_sphere`.

### `scrapbot.material.surface`

Surface material data for primitive geometry.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `base_color` | `vec3` | Required | RGB values. Existing examples use `0.0` to `1.0` color components. |

### `scrapbot.render.cube`

Legacy cube renderer shortcut.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `color` | `vec3` | Required | RGB color for the legacy cube path. |

Use `scrapbot.geometry.primitive` plus `scrapbot.material.surface` in new scene data.

### `scrapbot.camera`

Camera projection data. Pair with `scrapbot.transform` on the same entity.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `fov_y_degrees` | `float` | Required | Vertical field of view in degrees. |
| `near` | `float` | Required | Near clipping plane. |
| `far` | `float` | Required | Far clipping plane. |

If no camera entity is present, the renderer uses a fallback camera.

### `scrapbot.light.directional`

Scene-driven directional light data.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `direction` | `vec3` | Required | Direction vector for the light. |
| `color` | `vec3` | Required | RGB light color. |
| `intensity` | `float` | Required | Direct light strength. |
| `ambient` | `float` | Required | Ambient contribution. |

If no directional light is present, the renderer uses a fallback light.

### `scrapbot.shadow.caster`

Marker component. Entities with this component cast shadows.

### `scrapbot.shadow.receiver`

Marker component. Entities with this component receive shadows.

## Renderer Settings

`scrapbot.renderer` configures the game-view render pipeline. A scene can author at most one renderer component.

```toml
[[entities]]
id = "scrapbot.renderer"
name = "Renderer"

[entities.components."scrapbot.renderer"]
hdr = true
tone_mapping = "aces"
exposure = 0.0
postprocess_enabled = true
antialiasing = "fxaa"
bloom_enabled = true
bloom_threshold = 0.85
bloom_intensity = 0.12
bloom_radius = 1.0
vignette_enabled = true
vignette_strength = 0.24
vignette_radius = 0.82
chromatic_aberration_enabled = true
chromatic_aberration_strength = 0.0025
```

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `hdr` | `boolean` | `true` | Uses an internal HDR scene target when the render target is created. |
| `tone_mapping` | `string` | `"aces"` | `none`, `reinhard`, or `aces`. |
| `exposure` | `float` | `0.0` | Exposure compensation before tone mapping. Must be finite. |
| `postprocess_enabled` | `boolean` | `true` | Enables built-in postprocess effects. |
| `antialiasing` | `string` | `"fxaa"` | `none` or `fxaa`. |
| `bloom_enabled` | `boolean` | `true` | Enables bloom. |
| `bloom_threshold` | `float` | `0.85` | Brightness threshold. Must be finite and non-negative. |
| `bloom_intensity` | `float` | `0.12` | Bloom blend strength. Must be finite and non-negative. |
| `bloom_radius` | `float` | `1.0` | Bloom radius input. Must be finite and non-negative. |
| `vignette_enabled` | `boolean` | `true` | Enables vignette. |
| `vignette_strength` | `float` | `0.24` | Vignette strength. Must be finite and non-negative. |
| `vignette_radius` | `float` | `0.82` | Vignette radius. Must be finite and at least `0.0001`. |
| `chromatic_aberration_enabled` | `boolean` | `true` | Enables chromatic aberration. |
| `chromatic_aberration_strength` | `float` | `0.0025` | Effect strength. Must be finite and non-negative. |

Runtime systems can read and write these fields through normal ECS access. Most changes affect later frames immediately. Changing `hdr` requires the render target to be recreated before the new HDR setting is visible.

## Retained UI

Scene-authored UI is retained ECS data. Rendering, clipping, command routing, hover and pressed button state, scroll routing, and canvas scaling all resolve through the same retained layout path.

```toml
[[entities]]
id = "panel"
name = "Panel"

[entities.components."scrapbot.ui.canvas"]
design_size = [640.0, 480.0, 0.0]
scale_mode = "fit"

[entities.components."scrapbot.ui.rect"]
position = [16.0, 16.0, 0.0]
size = [240.0, 96.0, 0.0]
color = [0.059, 0.09, 0.165]
corner_radius = 6.0

[entities.components."scrapbot.ui.border"]
color = [0.148, 0.2, 0.282]
thickness = 1.0
```

UI positions and sizes are screen-space values with a top-left origin. `vec3` fields use the first two components for 2D layout in current UI primitives.

### `scrapbot.ui.canvas`

Canvas root for scene UI scaling.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `design_size` | `vec3` | `[0.0, 0.0, 0.0]` | Design-space width and height. |
| `scale_mode` | `string` | `"none"` | `none`, `fit`, or `fill`. |

`fit` scales and centers the design size inside the target viewport. `fill` scales enough to cover it. The target is the full window in normal runs and the editor game viewport while editor chrome is visible.

### `scrapbot.ui.rect`

Screen-space rectangle.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `position` | `vec3` | Required | Top-left position. |
| `size` | `vec3` | Required | Width and height. |
| `color` | `vec3` | Required | RGB fill color. |
| `corner_radius` | `float` | `0.0` | Uniform rounded-corner radius in pixels. |

### `scrapbot.ui.border`

Uniform border for a `scrapbot.ui.rect` on the same entity.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `color` | `vec3` | Required | RGB border color. |
| `thickness` | `float` | Required | Border thickness in pixels. |

### `scrapbot.ui.text`

Screen-space bitmap text.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `position` | `vec3` | Required | Top-left text position before layout parenting. |
| `size` | `float` | Required | Bitmap font scale. Do not use below `1.0` for editor surfaces. |
| `color` | `vec3` | Required | RGB text color. |
| `value` | `string` | Required | Text content. |

### `scrapbot.ui.button`

Marker component. Adds button interaction state to a UI entity. A command button normally combines `scrapbot.ui.rect`, `scrapbot.ui.button`, and `scrapbot.ui.command`.

### `scrapbot.ui.hit_area`

Optional non-rendering interaction rectangle.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `position` | `vec3` | Required | Top-left hit area position before layout parenting. |
| `size` | `vec3` | Required | Width and height. |

When present on a button entity, the hit area is preferred over the visual rect for command routing.

### `scrapbot.ui.command`

Command id emitted by a command button.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `command` | `string` | Required | Command identifier consumed by scripts or editor systems. |

Command ids are plain strings. Use stable, descriptive ids such as `menu.open` or `inventory.toggle`.

### `scrapbot.ui.command_event`

Runtime-only transient command event. Do not author this component in scene files.

| Field | Type | Notes |
| --- | --- | --- |
| `command` | `string` | Command id from the pressed button. |
| `source` | `string` | Source entity id. |

The engine emits command events into the live project world before update systems run.

### `scrapbot.ui.scroll_view`

Clipped scroll viewport.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `position` | `vec3` | Required | Top-left viewport position. |
| `size` | `vec3` | Required | Viewport width and height. |
| `content_offset` | `vec3` | Required | Current scroll offset in pixels. |

Descendant layout items are offset by `content_offset` and clipped to the viewport. Mouse wheel input updates scene-authored scroll views under the pointer in headful runs.

### `scrapbot.ui.vgroup`

Vertical group with proportional grow-height distribution.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `position` | `vec3` | Required | Group origin. |
| `size` | `vec3` | Required | Group width and height. |
| `spacing` | `float` | Required | Pixels between ordered direct children. |
| `padding` | `vec3` | Required | Symmetric padding used by current layout. |

Children with positive `scrapbot.ui.layout.item.grow` receive proportional extra height after fixed heights, minimum sizes, padding, and spacing are accounted for. `align = fill` fills the available width.

### `scrapbot.ui.hgroup`

Horizontal group with proportional grow-width distribution.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `position` | `vec3` | Required | Group origin. |
| `size` | `vec3` | Required | Group width and height. |
| `spacing` | `float` | Required | Pixels between ordered direct children. |
| `padding` | `vec3` | Required | Symmetric padding used by current layout. |

Children with positive `scrapbot.ui.layout.item.grow` receive proportional extra width after fixed widths, minimum sizes, padding, and spacing are accounted for. `align = fill` fills the available height.

### `scrapbot.ui.stack`

Direction-aware stack container.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `position` | `vec3` | Required | Stack origin. |
| `spacing` | `float` | Required | Pixels between ordered direct children. |
| `direction` | `string` | Required | `vertical`, `column`, `horizontal`, or `row`. |
| `padding` | `vec3` | Required | Symmetric padding used by current layout. |

`vertical` and `column` stack top to bottom. `horizontal` and `row` stack left to right.

### `scrapbot.ui.layout.item`

Attaches an entity to a retained layout parent by stable scene entity id.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `parent` | `string` | Required | Parent entity id, not a dense runtime handle. |
| `order` | `int` | Required | Sort key among direct children. |
| `min_size` | `vec3` | `[0.0, 0.0, 0.0]` | Minimum layout size. |
| `preferred_size` | `vec3` | `[0.0, 0.0, 0.0]` | Preferred layout size when non-zero. |
| `max_size` | `vec3` | `[0.0, 0.0, 0.0]` | Maximum layout size when non-zero. |
| `grow` | `float` | `0.0` | Grow ratio for `scrapbot.ui.hgroup` and `scrapbot.ui.vgroup` children. |
| `shrink` | `float` | `0.0` | Shrink ratio for `scrapbot.ui.hgroup` and `scrapbot.ui.vgroup` children. |
| `align` | `string` | `"start"` | `start`, `center`, `end`, or `fill`. |
| `margin` | `vec3` | `[0.0, 0.0, 0.0]` | Symmetric margin used by current layout. |

Children can target layout containers such as `scrapbot.ui.vgroup`, `scrapbot.ui.hgroup`, `scrapbot.ui.stack`, and `scrapbot.ui.scroll_view`. They can also target non-container UI rects, text, or separators to inherit that parent's resolved position. This is the preferred pattern for button labels and compact composite controls.

### `scrapbot.ui.spacer`

Non-rendering layout item.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `size` | `vec3` | Required | Spacer width and height. |

### `scrapbot.ui.text_block`

Content box and alignment metadata for a `scrapbot.ui.text` entity.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `size` | `vec3` | Required | Text content box width and height. |
| `horizontal_align` | `string` | Required | `start`, `center`, or `end`. |
| `vertical_align` | `string` | Required | `start`, `center`, or `end`. |

Use `scrapbot.ui.text_block` when a label should be centered or end-aligned inside a button or panel region.

### `scrapbot.ui.toggle`

Checked state for toggle-like controls.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `checked` | `boolean` | Required | Influences current rect/button visuals. |

This component does not toggle itself automatically. Scripts or editor systems own mutation for now.

### `scrapbot.ui.progress_bar`

Progress fill rendered inside the entity's rect.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `value` | `float` | Required | Current value. |
| `max` | `float` | Required | Maximum value. |
| `fill_color` | `vec3` | Required | RGB fill color. |

Pair with `scrapbot.ui.rect` for the progress bar track.

### `scrapbot.ui.separator`

Thin semantic divider.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `position` | `vec3` | Required | Top-left separator position before layout parenting. |
| `size` | `vec3` | Required | Width and height. |
| `color` | `vec3` | Required | RGB separator color. |

## Runtime Input Resources

The platform input layer writes these ECS resources every frame. They are runtime-only and should not be authored in scene files.

### `scrapbot.input.pointer`

| Field | Type | Notes |
| --- | --- | --- |
| `position` | `vec3` | Current pointer position. |
| `delta` | `vec3` | Pointer movement since the previous frame. |
| `has_position` | `boolean` | Whether `position` is valid for this frame. |
| `primary_down` | `boolean` | Primary pointer button is held. |
| `primary_pressed` | `boolean` | Primary pointer button pressed this frame. |
| `primary_released` | `boolean` | Primary pointer button released this frame. |
| `secondary_down` | `boolean` | Secondary pointer button is held. |
| `secondary_pressed` | `boolean` | Secondary pointer button pressed this frame. |
| `secondary_released` | `boolean` | Secondary pointer button released this frame. |
| `wheel_delta` | `vec3` | Mouse-wheel delta for scroll routing. |

### `scrapbot.input.keyboard`

| Field | Type | Notes |
| --- | --- | --- |
| `ctrl_down` | `boolean` | Ctrl modifier is held. |
| `shift_down` | `boolean` | Shift modifier is held. |
| `alt_down` | `boolean` | Alt modifier is held. |
| `super_down` | `boolean` | Super modifier is held. |
| `move_forward` | `boolean` | Forward movement action is active. |
| `move_back` | `boolean` | Back movement action is active. |
| `move_left` | `boolean` | Left movement action is active. |
| `move_right` | `boolean` | Right movement action is active. |
| `move_up` | `boolean` | Up movement action is active. |
| `move_down` | `boolean` | Down movement action is active. |
| `editor_toggle_pressed` | `boolean` | Editor visibility toggle was pressed this frame. |

### `scrapbot.input.frame`

| Field | Type | Notes |
| --- | --- | --- |
| `ui_visible` | `boolean` | Engine-owned editor/debug UI is visible. |
| `debug_overlay_visible` | `boolean` | Debug overlay visibility flag. |
| `viewport` | `vec3` | Current game viewport size. |

## Project-Local Example Component

### `spin`

The examples currently use a project-local `spin` component.

| Field | Type | Scene default | Notes |
| --- | --- | --- | --- |
| `angular_velocity` | `vec3` | Required | Example rotation speed used by scripts and native examples. |

`spin` is not engine-owned. It exists only in projects that register it through their scripts or native module.

## Field Types

| Scene/schema type | Runtime type |
| --- | --- |
| `boolean`, `bool` | Boolean |
| `int`, `i32` | 32-bit signed integer |
| `float`, `f32` | 32-bit float |
| `vec3` | Three `f32` values |
| `string` | Engine-owned string |
