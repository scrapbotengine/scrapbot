---
title: Engine Components
description: Built-in Machina component ids and fields.
---

Machina registers these engine component types before project scripts and native modules are validated.

## Rendering Components

| Component | Fields | Notes |
| --- | --- | --- |
| `machina.transform` | `position: vec3`, `rotation: vec3`, `scale: vec3` | Spatial transform used by rendering and gameplay. |
| `machina.geometry.primitive` | `primitive: string`, `segments: int`, `rings: int` | Built-in geometry generator selector. |
| `machina.material.surface` | `base_color: vec3` | Current surface material data. |
| `machina.render.cube` | `color: vec3` | Legacy cube renderer shortcut. Prefer geometry + material. |
| `machina.camera` | `fov_y_degrees: f32`, `near: f32`, `far: f32` | Scene-driven camera data. |
| `machina.light.directional` | `direction: vec3`, `color: vec3`, `intensity: f32`, `ambient: f32` | Scene-driven directional light data. |
| `machina.shadow.caster` | Marker | Entity casts shadows. |
| `machina.shadow.receiver` | Marker | Entity receives shadows. |

## UI Components

| Component | Fields | Notes |
| --- | --- | --- |
| `machina.ui.canvas` | `design_size: vec3`, `scale_mode: string` | UI canvas root. `scale_mode` can be `none`, `fit`, or `fill`; old marker-style scenes default to `none`. Fit/fill target the full window normally and the editor game viewport when editor chrome is visible. |
| `machina.ui.rect` | `position: vec3`, `size: vec3`, `color: vec3`, `corner_radius: f32` | Screen-space rectangle with optional rounded corners. |
| `machina.ui.border` | `color: vec3`, `thickness: f32` | Uniform rounded border for a rect. |
| `machina.ui.text` | `position: vec3`, `size: f32`, `color: vec3`, `value: string` | Screen-space bitmap text. |
| `machina.ui.button` | Marker | Adds button interaction behavior to a rect. |
| `machina.ui.command` | `command: string` | Command id emitted by a button press. |
| `machina.ui.command_event` | `command: string`, `source: string` | Runtime-only transient event. Do not author in scenes. |
| `machina.ui.scroll_view` | `position: vec3`, `size: vec3`, `content_offset: vec3` | Clips and offsets descendant layout items. |
| `machina.ui.vbox` | `position: vec3`, `spacing: f32` | Vertical layout container. |
| `machina.ui.stack` | `position: vec3`, `spacing: f32`, `direction: string`, `padding: vec3` | Direction-aware layout container. `direction` supports `vertical`, `column`, `horizontal`, and `row`. |
| `machina.ui.layout.item` | `parent: string`, `order: int`, `min_size: vec3`, `grow: f32`, `align: string`, `margin: vec3` | Attaches an entity to a layout parent by stable scene id. Children can also target a non-container UI rect/text/separator to inherit that parent's resolved position. |
| `machina.ui.spacer` | `size: vec3` | Non-rendering layout item. |
| `machina.ui.text_block` | `size: vec3`, `horizontal_align: string`, `vertical_align: string` | Gives a text entity a content box with `start`, `center`, or `end` alignment. |
| `machina.ui.toggle` | `checked: bool` | State marker that influences rect/button visuals. Scripts own mutation for now. |
| `machina.ui.progress_bar` | `value: f32`, `max: f32`, `fill_color: vec3` | Renders a fill inside the entity's rect. |
| `machina.ui.separator` | `position: vec3`, `size: vec3`, `color: vec3` | Thin semantic divider. |
| `machina.input.pointer` | `position: vec3`, `has_position: bool`, primary button state, `wheel_delta: vec3` | Runtime-only current pointer frame state. Do not author in scenes. |
| `machina.input.keyboard` | modifier state, `editor_toggle_pressed: bool` | Runtime-only current keyboard frame state. Do not author in scenes. |
| `machina.input.frame` | `ui_visible: bool`, `debug_overlay_visible: bool`, `viewport: vec3` | Runtime-only frame input state. Do not author in scenes. |

Retained UI layout is resolved consistently for rendering and input. Scene UI hit testing, button hover/press visuals, command dispatch, scroll handling, clipping, and canvas fit/fill scaling use the same `scroll_view`, `vbox`, `stack`, and `layout.item` semantics that render the controls. Command buttons are ordinary retained UI entities: `machina.ui.rect` + `machina.ui.button` + `machina.ui.command`.

## Built-In But Project-Local Today

| Component | Fields | Notes |
| --- | --- | --- |
| `spin` | `angular_velocity: vec3` | Current simple spin component used by examples and runtime helpers. |

## Field Types

| Scene/schema type | Runtime type |
| --- | --- |
| `boolean`, `bool` | Boolean |
| `int`, `i32` | 32-bit signed integer |
| `float`, `f32` | 32-bit float |
| `vec3` | Three `f32` values |
| `string` | Engine-owned string |

## Component ID Rules

- Single lowercase ASCII segments such as `spin` are project-local.
- Dotted ids are for packages and libraries.
- `machina.*` is engine-owned.
- Machina does not infer a default project namespace.
