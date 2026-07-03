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
| `machina.ui.canvas` | Marker | Marks UI canvas roots. |
| `machina.ui.rect` | `position: vec3`, `size: vec3`, `color: vec3` | Screen-space rectangle. |
| `machina.ui.text` | `position: vec3`, `size: f32`, `color: vec3`, `value: string` | Screen-space bitmap text. |
| `machina.ui.button` | Marker | Adds button interaction behavior to a rect. |
| `machina.ui.command` | `command: string` | Command id emitted by a button press. |
| `machina.ui.command_event` | `command: string`, `source: string` | Runtime-only transient event. Do not author in scenes. |
| `machina.input.pointer` | `position: vec3`, `has_position: bool`, primary button state, `wheel_delta: vec3` | Runtime-only current pointer frame state. Do not author in scenes. |
| `machina.input.keyboard` | modifier state, `editor_toggle_pressed: bool` | Runtime-only current keyboard frame state. Do not author in scenes. |
| `machina.input.frame` | `ui_visible: bool`, `debug_overlay_visible: bool`, `viewport: vec3` | Runtime-only frame input state. Do not author in scenes. |

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
