---
title: Engine Component Reference
description: Every component provided by Scrapbot, including fields, ownership, authoring names, and runtime behavior.
---

This page is the canonical inventory of engine-owned ECS components. The runtime registry in `src/scrapbot/component/registry.odin` is the source of truth for public component names and reflected fields.

Project components use one token, such as `autorotate`. Engine and library components use dotted names. The `scrapbot` namespace is reserved for the engine.

## Surface naming

Most components use the same suffix in every public surface:

| Registry and lifecycle name | Scene TOML | Luau handle | Native Odin descriptor |
| --- | --- | --- | --- |
| `scrapbot.transform` | `[entities.transform]` | `scrapbot.transform` | `scrapbot.Transform_Component` |
| `scrapbot.camera` | `[entities.camera]` | `scrapbot.camera` | Use `scrapbot.Component{name = "scrapbot.camera"}` for membership. |
| `scrapbot.mesh` | `[entities.mesh]` | `scrapbot.mesh` | `scrapbot.Mesh_Component` |
| `scrapbot.geometry` | `[entities.geometry]` | `scrapbot.geometry_component` | Use `scrapbot.Component{name = "scrapbot.geometry"}` for membership. |
| `scrapbot.material` | `[entities.material]` | `scrapbot.material_component` | Use `scrapbot.Component{name = "scrapbot.material"}` for membership. |
| `scrapbot.<name>` | `[entities.<name>]` | `scrapbot.<name>` | `scrapbot.<Name>_Component` when the helper exports one. |

`scrapbot.geometry` and `scrapbot.material` are resource-creation namespaces in Luau, so their component handles use the `_component` suffix. Scene geometry names, material UUIDs, and `mesh.primitive` strings resolve to generational resource handles when the world is built.

The generated `.scrapbot/types/scrapbot.d.luau` file is the precise type reference for the current project. Camera fields and the resource-backed mesh, geometry, and material payloads are not exposed for Luau mutation yet; their handles currently provide query membership.

## Complete public inventory

<!-- inventory:public-engine-components:start -->
| Component | Kind | Purpose |
| --- | --- | --- |
| `scrapbot.transform` | Data | Optional UUID parent plus local position, Euler rotation, and scale. |
| `scrapbot.camera` | Data | Perspective camera projection. |
| `scrapbot.ambient_light` | Data | Scene-wide ambient contribution. |
| `scrapbot.directional_light` | Data | Directional light and the source for the current shadow map. |
| `scrapbot.point_light` | Data | Distance-attenuated light positioned by a Transform. |
| `scrapbot.mesh` | Resource reference | Built-in primitive convenience component. |
| `scrapbot.geometry` | Resource reference | Named shared geometry reference. |
| `scrapbot.material` | Resource reference | UUID-backed shared project material reference. |
| `scrapbot.model` | Resource reference | UUID-backed static imported model root. |
| `scrapbot.shadow_caster` | Marker | Opts renderable geometry into directional shadow casting. |
| `scrapbot.shadow_receiver` | Marker | Opts renderable geometry into directional shadow sampling. |
| `scrapbot.keyboard_input` | Derived singleton | Read-only keyboard held/pressed/released frame snapshot. |
| `scrapbot.pointer_input` | Derived singleton | Read-only pointer position/delta/wheel/button frame snapshot. |
| `scrapbot.ui_layout` | UI box | Required geometry, hierarchy, sizing, and SDF box style. |
| `scrapbot.ui_hstack` | UI flow | Horizontal child layout. |
| `scrapbot.ui_vstack` | UI flow | Vertical child layout. |
| `scrapbot.ui_scroll_area` | UI viewport | Clipping, smooth pixel scrolling, and scrollbar style. |
| `scrapbot.ui_panel` | UI framing | Optional title band and collapsible disclosure. |
| `scrapbot.ui_table` | UI flow | Row-major multi-column layout. |
| `scrapbot.ui_list` | UI flow | Selectable direct-child rows. |
| `scrapbot.ui_progress` | UI indicator | Track and clamped progress fill. |
| `scrapbot.ui_viewport` | UI content | Interactive renderer-backed Texture, Model, Material, or World view. |
| `scrapbot.ui_state` | UI interaction | Renderer-owned interaction values and edge revisions. |
| `scrapbot.ui_text` | UI content | Text label. |
| `scrapbot.ui_button` | UI content | Activatable text and/or SDF-icon button. |
| `scrapbot.ui_input` | UI content | Single-line text or numeric input. |
| `scrapbot.ui_checkbox` | UI content | Boolean control. |
<!-- inventory:public-engine-components:end -->

The engine also registers two internal derived components. Render reconciliation adds or removes `scrapbot.internal.render_instance` when an entity's Transform, geometry, and material references become renderable. Editor selection reconciliation adds or removes `scrapbot.internal.editor_transform_gizmo` when the selected entity can be manipulated. Both may appear as collapsed, read-only cards in the runtime type-inspected editor, but are intentionally unavailable to scene files, project Luau, native extensions, component membership actions, and persistence.

## Runtime input singletons

`scrapbot.keyboard_input` and `scrapbot.pointer_input` are registry-known, derived component resources stored once per World. Systems use them in `reads` declarations, but they are not attached to entities and therefore cannot be queried, authored in TOML, added, removed, persisted, or mutated.

The keyboard snapshot provides availability/focus plus held, pressed-this-frame, and released-this-frame state through the Luau and native input helpers. Supported names are lowercase letters and digits; arrows; Space, Enter, Escape, Tab, Backspace, Delete, Home, End, Page Up/Down; left/right Shift, Control, Alt, Meta; and F1–F12. The pointer snapshot provides availability, editor capture, pixel position/delta, wheel delta, and held/pressed/released primary, secondary, middle, back, and forward buttons. See [Luau API: Runtime input](/reference/luau-api/#runtime-input).

| Singleton | Public snapshot fields |
| --- | --- |
| `scrapbot.keyboard_input` | `available`, `focused`; key held/pressed/released state is accessed through input helpers. |
| `scrapbot.pointer_input` | `available`, `captured`, `position`, `delta`, `wheel`; button held/pressed/released state is accessed through input helpers. |

## Transform, camera, and rendering

### `scrapbot.transform`

| Field | Type | Meaning |
| --- | --- | --- |
| `parent` | string | Optional parent entity UUID. Empty means this Transform is a root. |
| `position` | Vec3 | Local position relative to `parent`; world position for a root. |
| `rotation` | Vec3 | Local Euler rotation in radians: X pitch, Y yaw, Z roll. |
| `scale` | Vec3 | Local X/Y/Z scale. An entirely omitted or zero scene scale normalizes to `[1, 1, 1]`. |

Parent UUIDs must resolve to another entity with a Transform and may not form a self-reference or cycle. Rendering, cameras, point lights, picking, and gizmos consume the world transform derived from the complete chain. Luau queries expose all four fields. A system must declare `scrapbot.transform` in `writes` before mutating its query payload; invalid parent writeback is rejected.

### `scrapbot.camera`

| Scene field | Type | Meaning |
| --- | --- | --- |
| `fov` | number | Vertical field of view in degrees. The editor constrains authored values to 1–179. |
| `near` | number | Positive near clipping plane. |
| `far` | number | Far clipping plane, greater than `near`. |
| `exposure` | number | Positive linear camera-exposure multiplier. Defaults to `1` and multiplies project render exposure. |

The camera reads position and orientation from a Transform on the same entity. The active camera's exposure affects direct lighting, image-based lighting, the visible environment, emission, and bloom together before tone mapping. Its Luau component handle currently exposes membership only; camera field mutation is an editor/scene-authoring surface in this slice.

### `scrapbot.mesh`

| Scene field | Type | Meaning |
| --- | --- | --- |
| `primitive` | string | Non-empty primitive name. The current built-in path supports `cube`. |

This is the legacy convenience path used by generated projects. It currently resolves the built-in cube geometry and default material needed for a renderable and exposes membership-only query payloads.

### `scrapbot.geometry` and `scrapbot.material`

| Component | Scene field | Meaning |
| --- | --- | --- |
| `scrapbot.geometry` | `resource` | Non-empty geometry name registered by Luau or native Odin. |
| `scrapbot.material` | `resource` | UUID of an authored `scrapbot.material` project resource. |

An entity using this resource-backed path becomes renderable when it has a Transform plus valid geometry and material handles. Materials may contribute metallic-roughness factors, mipmapped base-color/normal/occlusion/emissive images, and unbounded linear HDR emission that feeds world bloom. Imported glTF models populate that complete PBR contract; authored project materials currently expose base color, an optional Texture resource, and emission. The ECS stores generational resource handles; scene files store geometry names and stable material resource UUIDs. Luau and native material creation remains a transient runtime facility rather than authored project-resource persistence. See [Project File Reference](/reference/project-files/#project-resources) and [Luau API: Render resources](/reference/luau-api/#render-resources).

### `scrapbot.model`

| Scene field | Type | Meaning |
| --- | --- | --- |
| `resource` | UUID string | Authored `scrapbot.model` project resource to instantiate. |

The authored entity is the model root. Resource initialization and reload reconcile the imported glTF node hierarchy into derived runtime ECS entities with Transform, Geometry, and Material state. Models may contain multiple meshes and primitives; the renderer continues to consume ordinary renderable ECS entities rather than a model-specific draw path. Luau and native systems can query membership, but model resource replacement is currently a scene/editor authoring operation rather than a runtime payload write.

## Lights and shadows

| Component | Fields | Runtime behavior |
| --- | --- | --- |
| `scrapbot.ambient_light` | `color: Vec3`, `intensity: number` | Adds a scene-wide ambient contribution; no Transform required. |
| `scrapbot.directional_light` | `direction: Vec3`, `color: Vec3`, `intensity: number` | Adds directional lighting; no Transform required. The first directional light owns the current shadow map. |
| `scrapbot.point_light` | `color: Vec3`, `intensity: number`, `range: number` | Reads world position from a Transform on the same entity. Range and intensity are non-negative in editor authoring. |
| `scrapbot.shadow_caster` | No fields | Marks renderable geometry as a directional-shadow caster. |
| `scrapbot.shadow_receiver` | No fields | Marks renderable geometry as a directional-shadow receiver. |

Light query payloads expose the listed data fields. Shadow components are empty marker payloads. The two shadow markers are independent.

## UI composition rules

Every UI entity requires `scrapbot.ui_layout`. An entity may have at most one flow component—HStack, VStack, table, or list—and at most one content control—text, button, input, or checkbox. Panel, scroll-area, and progress components compose with those roles. The renderer attaches `scrapbot.ui_state`; projects never author or write it.

Vectors use `{x, y}`, `{x, y, z}`, or `{x, y, z, w}` in Luau and fixed arrays in TOML. Insets use `[top, right, bottom, left]`. Colors are RGBA Vec4 values. Unless a non-zero default is listed below, omitted UI fields begin empty, zero, or false.

### `scrapbot.ui_layout`

| Fields | Rules |
| --- | --- |
| `parent: string`, `position: Vec2`, `size: Vec2`, `min_size: Vec2` | `parent` is an entity UUID. `size` must be positive; `min_size` is non-negative. |
| `margin: Vec4`, `padding: Vec4` | Every inset component is non-negative. |
| `background: Vec4`, `border_color: Vec4`, `border_width: number`, `corner_radius: number` | Border width and radius are non-negative SDF geometry values. |
| `hidden: bool` | Removes the complete subtree from layout, painting, focus, and pointer input. |
| `fill_width: bool`, `fill_height: bool` | Consume available parent space on each axis. |
| `fit_content_width: bool`, `fit_content_height: bool` | Size around visible descendants on each axis. |
| `fixed_in_fill: bool` | Preserve authored main-axis size while flexible stack siblings divide remaining space. |
| `tree_item: bool`, `tree_parent: string`, `tree_order: number`, `tree_collapsed: bool` | Opt a direct child of a tree-enabled list into its semantic hierarchy. Parent is another row UUID, order is sibling-local, and collapse omits descendants without despawning them. |

### `scrapbot.ui_hstack` and `scrapbot.ui_vstack`

Both use the same payload:

| Field | Default | Meaning |
| --- | --- | --- |
| `gap` | `0` | Non-negative spacing between children. |
| `fill` | `false` | Treat authored main-axis sizes as proportions and fill available space. |
| `draggable` | `false` | Turn gaps into resize separators; requires `fill`. |
| `min_size` | `0` | Minimum pane extent along the stack axis. |

### `scrapbot.ui_scroll_area`

| Field | Default |
| --- | --- |
| `scroll_speed`, `smoothness` | `48`, `14` |
| `scrollbar_width`, `scrollbar_right`, `scrollbar_vertical_inset` | `3`, `4`, `5` |
| `minimum_thumb_size`, `scrollbar_corner_radius` | `18`, `1.5` |
| `scrollbar_track_color` | `[0.08, 0.09, 0.11, 0.78]` |
| `scrollbar_thumb_color` | `[0.34, 0.37, 0.42, 0.92]` |

Speed and smoothness must be positive; scrollbar geometry is non-negative. Descendants clip to the padded content rectangle. Nested scroll areas route wheel input to the deepest hovered scroll viewport.

### `scrapbot.ui_panel`

| Fields | Defaults and rules |
| --- | --- |
| `title: string`, `font: string` | Empty by default. A collapsible panel requires a title. |
| `title_color: Vec4`, `title_background: Vec4` | White title text and transparent background by default. |
| `title_size: number`, `title_height: number` | `12`, `32`; both must be positive when a title is present. |
| `disclosure_size`, `disclosure_margin`, `disclosure_gap`, `disclosure_corner_radius` | `10`, `10`, `8`, `1.35`; all non-negative. |
| `collapsible: bool`, `collapsed: bool` | A collapsed panel must be collapsible. |

Panels do not own a special close/remove control. Any direct child `ui_button` with `panel_action = true` is placed in the trailing title band and remains interactive while the panel is collapsed. Multiple actions lay out from right to left.

### `scrapbot.ui_table`

| Field | Default | Meaning |
| --- | --- | --- |
| `columns` | `1` | Integral column count from 1 through 64. |
| `column_gap`, `row_gap` | `0`, `0` | Non-negative cell spacing. |
| `proportional_columns` | `false` | Use first-row authored widths as reusable column weights. |
| `resizable_columns` | `false` | Make column gaps draggable; requires proportional columns. |
| `min_column_width` | `32` | Non-negative resize limit. |

### `scrapbot.ui_list`

| Field | Default |
| --- | --- |
| `selected` | Empty UUID |
| `gap` | `0` |
| `selection_background` | `[0.045, 0.095, 0.105, 1]` |
| `hover_background` | `[0.028, 0.038, 0.050, 1]` |
| `active_background` | `[0.040, 0.055, 0.072, 1]` |
| `draggable` | `false` |
| `drag_threshold` | `5` |
| `drop_edge_fraction` | `0.25` |
| `drop_target_background` | `[0.055, 0.12, 0.13, 1]` |
| `drop_indicator_color` | `[0.42, 0.92, 0.84, 1]` |
| `drop_indicator_thickness` | `2` |
| `drop_indicator_inset` | `8` |
| `tree_enabled` | `false` |
| `tree_indent` | `14` |

Direct children become full-width selectable rows. Clicking a row or descendant stores the direct child's UUID in `selected`. With `draggable = true`, dragging resolves source and target to direct children. The top and bottom `drop_edge_fraction` of a row classify as `before` and `after` and paint a clipped lander line; its middle classifies as `into` and paints `drop_target_background`. The placement is published through the list's `ui_state`. Threshold, indicator thickness, and inset must be non-negative; the edge fraction must be between 0 and 0.5.

With `tree_enabled = true`, direct children whose layout has `tree_item = true` are flattened depth-first after ordinary direct children. `tree_parent` references another tree row UUID, `tree_order` orders siblings, `tree_indent` offsets row contents without narrowing the full-width selection box, and `tree_collapsed` suppresses descendants. Invalid or cyclic metadata is rendered safely and deterministically. A successful drop mutates the source row's public `tree_parent` and normalizes the affected sibling orders: `into` reparents beneath the target, while `before`/`after` adopts the target's parent and inserts beside it. Descendants follow their row automatically. Disclosure controls remain ordinary composable buttons whose project system toggles `tree_collapsed`.

### `scrapbot.ui_progress`

| Field | Default | Meaning |
| --- | --- | --- |
| `value`, `maximum` | `0`, `1` | Fill uses `value / maximum`, clamped to the track; maximum must be positive. |
| `fill_color`, `background_color` | White, transparent | Fill and optional track color. |
| `inset` | Zero Vec4 | Non-negative track inset. |
| `corner_radius` | `0` | Non-negative SDF radius. |
| `right_to_left` | `false` | Anchor fill to the right edge. |

### `scrapbot.ui_viewport`

| Field | Default | Meaning |
| --- | --- | --- |
| `resource` | Empty UUID | Render this Texture, Model, or Material resource. When empty, render the current retained World. |
| `camera` | Empty UUID | Optional camera entity for a World target. The active project camera is used when empty. |
| `root` | Empty UUID | Optional World subtree root; only that entity and its descendants render. |
| `orbit` | `[-0.35, 0.55]` | Preview pitch and yaw in radians. |
| `distance` | `3` | 3D preview-radius camera multiplier; must be finite and at least `1.1`. |
| `clear_color` | `[0.012, 0.017, 0.024, 1]` | Offscreen surface clear color. |
| `interactive` | `true` | Drag to orbit and use the wheel to zoom. |

The viewport is an ordinary UI element: `ui_layout` controls its size, padding ancestors can frame it, scroll areas clip it, and its render surface participates in normal paint order. Texture targets use an aspect-preserving GPU pass. Model targets render imported Geometry and Materials, while Material targets use an isolated lit icosphere preview scene. Stable resource targets remain cached until presentation state, target size/aspect, exact resource content, or a relevant registry revision changes. World targets consume the retained active World's render list and may select a camera or subtree by stable entity UUID.

WGPU pools eight independently sized targets. Each visible viewport is quantized to 32-pixel increments between 64 and 1024 pixels per axis, so small inspectors and large preview panes do not pay the same fixed allocation or rendering cost. Renderer diagnostics report active targets, target pixels, resizes, redraws, and cache hits. Resource preview scenes are renderer-owned derived presentation; they are not separately simulated ECS worlds.

### `scrapbot.ui_state`

| Fields | Meaning |
| --- | --- |
| `hovered`, `active`, `focused` | Current pointer and keyboard state. |
| `activated`, `changed`, `submitted`, `cancelled` | Transient edges from the latest UI pass. |
| `valid` | Current input validity. |
| `activation_revision`, `change_revision`, `submit_revision`, `cancel_revision` | Monotonic counters for systems that may miss transient booleans. |
| `dragging`, `drag_source`, `drop_target`, `drop_placement` | Current draggable-list gesture, direct-child UUIDs, and `none`/`before`/`into`/`after` placement. An empty target with `into` means list background. |
| `drop_revision` | Monotonic counter advanced by a completed drop inside the source list. |

This component is renderer-owned and read-only. It is queryable from Luau and native systems but invalid in scene TOML, spawn payloads, and component writes.

### `scrapbot.ui_text`

| Field | Default | Meaning |
| --- | --- | --- |
| `text`, `font` | Empty | Text is required and non-empty. Empty font selects embedded Inter. |
| `color`, `size` | White, `16` | Size must be positive. |
| `alignment` | `left` | `left`, `center`, or `right`. |

### `scrapbot.ui_button`

| Field | Default | Meaning |
| --- | --- | --- |
| `text`, `font` | Empty | Text is optional when an icon is present. Empty font selects Inter. |
| `color`, `size`, `alignment` | White, `16`, `center` | Normal label style. |
| `hover_background`, `active_background` | Transparent | State-specific layout background overrides. |
| `hover_color`, `active_color` | Transparent | State-specific text colors; transparent falls back to normal color. |
| `icon` | `none` | `none`, `close`, `plus`, `chevron_right`, or `chevron_down`; an icon-only button needs no text. |
| `icon_inset`, `icon_stroke` | `6`, `1.5` | Non-negative SDF icon geometry. Twice the inset cannot exceed the button's layout width or height. |
| `panel_action` | `false` | Place this direct child button in its parent's panel title band. |

### `scrapbot.ui_input`

| Fields | Defaults and rules |
| --- | --- |
| `text`, `font`, `prefix` | Empty. Empty font selects Inter. |
| `color`, `size` | White, `16`; size must be positive. |
| `prefix_color`, `prefix_background`, `prefix_width` | White, transparent, `0`. |
| `selection_background`, `selection_corner_radius` | `[0.15, 0.45, 0.40, 0.55]`, `2`. |
| `focus_border_color`, `focus_border_width` | `[0.15, 0.85, 0.72, 1]`, `1`. |
| `invalid_border_color`, `invalid_border_width` | `[0.92, 0.24, 0.28, 1]`, `1.5`. |
| `caret_color`, `caret_width`, `caret_inset` | Transparent, `1`, `2`. Transparent caret color falls back to text color. |
| `prefix_gap`, `prefix_corner_radius`, `prefix_text_padding` | `3`, `2`, `3`. |
| `number`, `step`, `minimum`, `maximum` | `0`, `1`, `0`, `0`. Step must be positive in numeric mode. |
| `read_only`, `numeric`, `draggable`, `has_minimum`, `has_maximum` | `false`. Bounds apply only when their matching flag is true. `draggable` opts a writable numeric input into horizontal pointer scrubbing and its resize cursor. |

Numeric values and enabled bounds must be finite, the number must remain inside enabled bounds, and minimum cannot exceed maximum. Prefix, selection, border, caret, and radius geometry is non-negative.

### `scrapbot.ui_checkbox`

| Field | Default |
| --- | --- |
| `checked`, `read_only` | `false`, `false` |
| `box_size` | `18` |
| `background`, `checked_background` | `[0.025, 0.030, 0.040, 1]`, `[0.08, 0.55, 0.46, 1]` |
| `border_color`, `check_color` | `[0.24, 0.27, 0.32, 1]`, `[0.95, 0.97, 0.98, 1]` |
| `hover_background`, `active_background` | `[0.12, 0.64, 0.54, 1]`, `[0.06, 0.42, 0.36, 1]` |
| `corner_radius`, `check_inset`, `check_corner_radius` | `-1`, `-1`, `-1` for automatic size-relative values. |
| `border_width` | `1` |

Box size must be positive. Automatic geometry fields accept `-1`; explicit values and border width must be non-negative.

## Related references

- [Project File Reference](/reference/project-files/) shows complete TOML examples.
- [Luau API](/reference/luau-api/) covers queries, systems, resources, and lifecycle commands.
- [ECS UI](/guides/ecs-ui/) explains composition and interaction patterns.
- [Native Extensions](/guides/native-extensions/) documents typed Odin payloads and access declarations.
