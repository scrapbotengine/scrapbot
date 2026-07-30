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
| `scrapbot.world_environment` | `[entities.world_environment]` | `scrapbot.world_environment` | Use `scrapbot.Component{name = "scrapbot.world_environment"}` for membership. |
| `scrapbot.volumetric_fog` | `[entities.components.scrapbot.volumetric_fog]` | `scrapbot.volumetric_fog` | Use `scrapbot.Component{name = "scrapbot.volumetric_fog"}` for membership. |
| `scrapbot.mesh` | `[entities.mesh]` | `scrapbot.mesh` | `scrapbot.Mesh_Component` |
| `scrapbot.geometry` | `[entities.geometry]` | `scrapbot.geometry_component` | Use `scrapbot.Component{name = "scrapbot.geometry"}` for membership. |
| `scrapbot.material` | `[entities.material]` | `scrapbot.material_component` | Use `scrapbot.Component{name = "scrapbot.material"}` for membership. |
| `scrapbot.<name>` | `[entities.<name>]` | `scrapbot.<name>` | `scrapbot.<Name>_Component` when the helper exports one. |

`scrapbot.geometry` and `scrapbot.material` are resource-creation namespaces in Luau, so their component handles use the `_component` suffix. Scene geometry names, material UUIDs, and `mesh.primitive` strings resolve to generational resource handles when the world is built.

The generated `.scrapbot/types/scrapbot.d.luau` file is the precise type reference for the current project. Resource-backed mesh, geometry, and material payloads are not exposed for Luau mutation yet; their handles currently provide query membership.

## Complete public inventory

<!-- inventory:public-engine-components:start -->
| Component | Kind | Purpose |
| --- | --- | --- |
| `scrapbot.transform` | Data | Optional UUID parent plus local position, Euler rotation, and scale. |
| `scrapbot.camera` | Data | Perspective camera projection. |
| `scrapbot.world_environment` | Data/resource references | Singleton scene lighting, sky presentation, and base exposure. |
| `scrapbot.volumetric_fog` | Data | Singleton global height/distance fog with shadowed directional and clustered point-light scattering. |
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
| `scrapbot.ui_layout` | UI box | Required geometry, hierarchy, sizing, SDF box style, and optional popup-root behavior. |
| `scrapbot.ui_canvas` | UI canvas | Optional singleton root policy for logical size, output scaling/alignment, safe area, and scale bounds. |
| `scrapbot.ui_hstack` | UI flow | Horizontal child layout. |
| `scrapbot.ui_vstack` | UI flow | Vertical child layout. |
| `scrapbot.ui_scroll_area` | UI viewport | Clipping, smooth pixel scrolling, and scrollbar style. |
| `scrapbot.ui_panel` | UI framing | Optional title band and collapsible disclosure. |
| `scrapbot.ui_dock_space` | UI flow | Styled direct-child tab group and cross-group transfer target. |
| `scrapbot.ui_dock_item` | UI framing | Titled, optionally movable direct dock-space child. |
| `scrapbot.ui_table` | UI flow | Row-major multi-column layout. |
| `scrapbot.ui_list` | UI flow | Filterable, virtualizable selectable direct-child rows and trees. |
| `scrapbot.ui_progress` | UI indicator | Track and clamped progress fill. |
| `scrapbot.ui_viewport` | UI content | Interactive renderer-backed Texture, Model, Material, or World view. |
| `scrapbot.ui_state` | UI interaction | Renderer-owned interaction values and edge revisions. |
| `scrapbot.ui_icon` | UI content | UUID-backed symbolic MTSDF icon with an HDR tint. |
| `scrapbot.ui_text` | UI content | Text label. |
| `scrapbot.ui_button` | UI content | Activatable text and/or SDF-icon button with an optional popup target. |
| `scrapbot.ui_input` | UI content | Single-line text or numeric input. |
| `scrapbot.ui_checkbox` | UI content | Boolean control. |
| `scrapbot.ui_color_picker` | UI content | Linear RGBA picker with optional HDR exposure and alpha controls. |
| `scrapbot.ui_action` | UI semantics | Inheritable semantic action and optional event payload. |
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
| `resolution_scale` | number | World/depth/post render-grid scale from `0.5` to `1`. Defaults to native resolution (`1`). When dynamic resolution is enabled, this is its maximum scale. |
| `dynamic_resolution` | boolean | Lets WGPU lower and recover world resolution against a GPU-time budget. Defaults to `false`. |
| `dynamic_resolution_min_scale` | number | Dynamic-resolution floor from `0.5` through `resolution_scale`. Defaults to `0.5`. |
| `dynamic_resolution_target_ms` | number | Scalable-world GPU-time target from `1` to `100` milliseconds. Defaults to `16.667`. |
| `exposure` | number | Positive linear exposure multiplier. Defaults to `1`; it is fixed exposure when automatic exposure is off and compensation when it is on. |
| `automatic_exposure` | boolean | Enables GPU-resident, viewport-scoped luminance metering and adaptation. Defaults to `false`. |
| `automatic_exposure_min` | number | Positive minimum automatic exposure. Defaults to `0.125`. |
| `automatic_exposure_max` | number | Maximum automatic exposure, at least the minimum. Defaults to `8`. |
| `automatic_exposure_speed` | number | Positive adaptation rate in inverse seconds. Defaults to `2`. |
| `temporal_antialiasing` | boolean | Enables projection jitter and retained depth-aware temporal resolution. Defaults to `true`. |
| `fast_antialiasing` | boolean | Enables a lightweight current-frame fullscreen edge filter when temporal antialiasing is disabled. Defaults to `false`; TAA takes precedence when both are enabled. |
| `ambient_occlusion` | boolean | Enables half-resolution, thickness-aware visibility-bitmask ambient occlusion with mapped surface normals, joint depth/normal filtering, and indirect-diffuse-only composition. Defaults to `true`. |
| `ambient_occlusion_quality` | number | Selects a bounded AO sampling tier from `0.25` to `1`. Defaults to the balanced `0.5` tier (16 samples per half-resolution pixel); `0.25`, `0.75`, and `1` use 8, 24, and 36 samples. |
| `screen_space_reflections` | boolean | Enables material-aware screen-space reflections for sufficiently smooth visible surfaces. Defaults to `false`. |
| `screen_space_reflections_quality` | number | Selects a bounded SSR ray-march tier from `0.25` to `1`. Defaults to the balanced `0.5` tier (32 steps per eligible pixel); `0.25`, `0.75`, and `1` use 16, 48, and 64 steps. |
| `bloom` | boolean | Enables the five-level HDR bloom pyramid. Defaults to `true`. |

The camera reads position and orientation from a Transform on the same entity. The active camera's resolution, exposure, and render-feature policy controls that rendered view, including while an editor fly camera supplies the editor viewport's pose.

Reducing `resolution_scale` lowers the world, depth, Hi-Z, and post-processing pixel workload. The renderer composites that result into the native output target before drawing project UI, gizmos, and editor chrome at native resolution.

With `dynamic_resolution = true`, WGPU treats `resolution_scale` as a ceiling and `dynamic_resolution_min_scale` as a floor. It uses asynchronous GPU timestamps, a filtered signal, asymmetric hysteresis, and 5% scale steps. Editor/project UI timing is excluded so expensive chrome does not lower world quality. Backends without GPU timestamps use the authored ceiling unchanged.

A scale step rebuilds only size-dependent render targets and rejects temporal history. Stable scale reuses them. The performance inspector and `scrapbot profile` report the effective scale.

Automatic exposure samples only the active rendered viewport—not editor chrome—and adapts one persistent GPU exposure value without a CPU readback. Bloom and final composition consume the same value. Disabling it skips the metering dispatch and preserves the fixed-exposure path.

SSR ray-marches the current frame's HDR color, depth, and material surface data. As a screen-space effect, it cannot reflect off-screen or occluded objects and fades uncertain, rough, distant, and screen-edge hits.

AO and SSR quality change only bounded shader work; neither reallocates a target. Lower SSR tiers widen their step stride to preserve approximately the same ray reach with coarser intersection precision. Disabling AO, SSR, or bloom skips their compute work; disabling TAA removes jitter and history sampling. Luau queries expose and may write the complete payload when the system declares `scrapbot.camera` in `writes`.

### `scrapbot.world_environment`

A scene may contain at most one World Environment component. It belongs on an ordinary named entity, so the generated inspector, authoring history, Save/Revert, and playback restore treat environment configuration like other scene data.

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `lighting` | string | empty | Optional UUID of a `scrapbot.environment` resource used for diffuse/specular image-based lighting. |
| `lighting_intensity` | number | `1` | Non-negative multiplier shared by diffuse and specular environment lighting. |
| `reflection_intensity` | number | `1` | Additional non-negative multiplier for specular environment reflections. Use it to art-direct reflection strength without dimming diffuse image-based lighting. |
| `lighting_rotation` | number | `0` | Lighting Y rotation in degrees. |
| `exposure` | number | `1` | Positive base linear exposure multiplied by active-camera exposure. |
| `background_visible` | boolean | `true` | Enables the infinite camera-oriented background. |
| `background` | string | empty | Optional Environment UUID for the visible panorama. Empty uses the procedural haze sky independently of `lighting`. |
| `background_intensity` | number | `1` | Non-negative background-only multiplier. |
| `background_rotation` | number | `0` | Background Y rotation in degrees. |
| `background_exposure` | number | `1` | Positive background-only exposure compensation. |
| `background_blur` | number | `0` | Imported-background blur from `0` to `1`. |
| `sky_tint` | vec3 | `[1, 1, 1]` | Non-negative linear RGB multiplier for the procedural sky and atmospheric haze. |
| `ground_color` | vec3 | `[0.24, 0.235, 0.225]` | Non-negative linear RGB color at the procedural ground horizon. |
| `turbidity` | number | `2` | Atmospheric haze and warmth from `0` (clear) to `10` (hazy). |
| `atmosphere_thickness` | number | `1` | Haze reach from `0.1` to `5`. Larger values carry haze farther from the horizon. |
| `horizon_softness` | number | `1` | Horizon transition and glow width from `0.1` to `5`. |
| `sun_direction` | vec3 | `[-0.5, 0.25, -0.83]` | Non-zero world-space direction from the observer toward the procedural sun. The renderer normalizes it; elevation drives horizon occlusion and the day/night transition. |
| `sun_color` | vec3 | `[1, 0.92, 0.72]` | Non-negative linear HDR color of the procedural sun disc, halo, and derived directional light. |
| `sun_intensity` | number | `1` | Procedural sun radiance multiplier from `0` to `50`; `0` hides its disc/glow and disables its directional-light contribution. |
| `sun_size` | number | `1` | Procedural sun-disc size multiplier from `0` to `10`; `0` hides the disc and glow. |
| `sun_glow` | number | `1` | Sun halo multiplier from `0` to `10` without changing direct-light intensity. |

The fixed `scrapbot.environment` engine phase retains the selected entity and component revision. Stable frames do not scan all entities or resources. Structural membership changes rediscover the singleton, and value changes resolve only the referenced UUIDs before advancing the renderer environment revision.

Luau queries expose the complete payload. A scheduled system may animate it by declaring `scrapbot.world_environment` in `writes`; validated writeback updates the ECS value and component revision so the retained environment phase sees only the changed singleton. The ECS showcase uses this path for its editable `day_cycle` component and 30-second solar orbit.

The final ten fields art-direct only the built-in procedural atmosphere; imported backgrounds ignore them. Their reflected controls are generated automatically from the component's runtime field shape and numeric editor metadata. The spherical ground clips the sun disc at the horizon. Solar elevation drives day, twilight, and night colors plus hemispherical sky/ground fill. Above the horizon, Scrapbot derives the first directional-light render input from the sun, so it participates in ordinary GGX lighting, shadow culling, and the primary directional shadow map; below the horizon, that light disappears. This does not create an authored entity. Explicit Ambient, Directional, and Point Light components remain additive, with three directional slots left while the sun is active. The observer-above-ground approximation gives the horizon subtle perspective curvature.

### `scrapbot.volumetric_fog`

A scene may contain at most one Volumetric Fog component. It is an ordinary reflected component: its inspector card and controls come from the runtime registry, and scene persistence, Luau access, history, and playback use the generic component paths.

```toml
[entities.components.scrapbot.volumetric_fog]
color = [0.56, 0.65, 0.75]
density = 0.024
height = 0
height_falloff = 0.12
max_distance = 65
anisotropy = 0.48
ambient_intensity = 0.22
light_intensity = 1.1
point_light_intensity = 0.6
```

| Field | Type | Effective default | Meaning |
| --- | --- | --- | --- |
| `color` | Vec3 | `[0.62, 0.72, 0.82]` | Non-negative linear HDR scattering color. |
| `density` | number | `0` | Base extinction density from `0` to `1`. Zero disables fog. |
| `height` | number | `0` | World-space reference height at which base density applies. |
| `height_falloff` | number | `0.2` | Exponential density falloff above `height`, from `0` to `10`. |
| `max_distance` | number | `100` | Maximum camera-ray distance affected by fog, from `0.1` to `10000`. |
| `anisotropy` | number | `0.35` | Directional scattering bias from `-0.9` to `0.9`. Positive values emphasize forward scattering. |
| `ambient_intensity` | number | `0.15` | Unshadowed ambient scattering multiplier from `0` to `10`. |
| `light_intensity` | number | `1` | Primary directional-light scattering multiplier from `0` to `10`. |
| `point_light_intensity` | number | `0` | Clustered point-light scattering multiplier from `0` to `10`. Zero disables local-light scattering. |

The renderer integrates 16 stable midpoint samples per half-resolution camera ray. Density varies exponentially with world height and stops at scene depth or `max_distance`. The first directional light contributes anisotropic in-scattering and is filtered through the same four shadow cascades used by opaque geometry.

When enabled, each midpoint reads every relevant point light from the same GPU-built view-frustum cluster used by opaque surface lighting. Point-light scattering is currently unshadowed.

Fog is depth-aware upsampled before temporal antialiasing and bloom. Its low-discrepancy sub-step offset rotates across the eight-frame temporal sequence, allowing TAA to integrate smooth shafts without exposing fixed ray-march slices. Local fog volumes, froxels, and explicit quality controls remain follow-up work.

Luau systems can query and write the complete payload after declaring `scrapbot.volumetric_fog` in their access lists. Presence enables the feature; removing the component or setting `density` to zero skips the fog dispatch. The retained half-resolution target follows the normal post-target resize lifecycle.

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

The authored entity is the model root. Resource initialization and reload reconcile the imported glTF node hierarchy into derived runtime ECS entities with Transform, Geometry, and Material state. `shadow_caster` and `shadow_receiver` markers on the root are inherited by every generated primitive during that reconciliation. Models may contain multiple meshes and primitives; the renderer continues to consume ordinary renderable ECS entities rather than a model-specific draw path. Luau and native systems can query membership, but model resource replacement is currently a scene/editor authoring operation rather than a runtime payload write.

## Lights and shadows

| Component | Fields | Runtime behavior |
| --- | --- | --- |
| `scrapbot.ambient_light` | `color: Vec3`, `intensity: number` | Adds a scene-wide ambient contribution; no Transform required. |
| `scrapbot.directional_light` | `direction: Vec3`, `color: Vec3`, `intensity: number` | Adds directional lighting; no Transform required. The first directional light owns the current four-cascade shadow set. |
| `scrapbot.point_light` | `color: Vec3`, `intensity: number`, `range: number` | Reads world position from a Transform on the same entity. Range and intensity are non-negative. Luau deferred spawn accepts a validated initial payload when the system declares Point Light write access. |
| `scrapbot.shadow_caster` | No fields | Marks renderable geometry as a directional-shadow caster. |
| `scrapbot.shadow_receiver` | No fields | Marks renderable geometry as a directional-shadow receiver. |

Light query payloads expose the listed data fields. Shadow components are empty marker payloads. The two shadow markers are independent. WGPU retains all active point lights in growable GPU storage and assigns them to view-frustum clusters on the GPU. Every cluster can reference the complete retained list, while ordinary fragments evaluate only the lights overlapping their cluster.

## UI composition rules

Every UI entity requires `scrapbot.ui_layout`. An entity may have at most one flow component—HStack, VStack, table, list, or dock space—and at most one content control—icon, text, button, input, checkbox, or color picker. Panel, scroll-area, dock-item, and progress components compose with those roles. One root per entity-origin domain may additionally carry `scrapbot.ui_canvas`. The renderer attaches `scrapbot.ui_state`; projects never author or write it.

Themes are optional composition-time recipes, not renderer state. They resolve palette, metric, and control-role choices into the same fields listed below, after which per-entity values can override any result. See [UI theming](../../guides/ui-theming/) for the resolution order and contrasting examples.

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
| `basis`, `grow`, `shrink: number` | Non-negative flex sizing. Zero basis uses authored/intrinsic size; grow distributes positive space and shrink removes overflow without crossing `min_size`. |
| `horizontal_alignment`, `vertical_alignment: string` | Independently place the box at `start`, `center`, or `end`, or `stretch` it through the available parent axis. |
| `tree_item: bool`, `tree_parent: string`, `tree_order: number`, `tree_collapsed: bool` | Opt a direct child of a tree-enabled list into its semantic hierarchy. Parent is another row UUID, order is sibling-local, and collapse omits descendants without despawning them. |
| `stack_order: number` | Sibling-local order under any HStack or VStack. Equal values retain stable entity order; drops normalize affected siblings to consecutive values. |
| `popup: bool`, `popup_anchor: string`, `popup_open: bool`, `popup_close_on_selection: bool` | Make this root a floating popup anchored to another UI UUID. Closed popups leave layout/paint/interaction; selection dismissal applies to descendant lists. Popup roots cannot have a parent. |
| `popup_gap: number`, `popup_min_width: number`, `popup_max_width: number`, `popup_max_height: number`, `popup_viewport_margin: number` | Non-negative placement constraints. Zero maximums mean unbounded. A non-zero maximum width must be at least the minimum width. Placement prefers below the anchor, flips above when needed, and clamps to the UI viewport without overwriting authored geometry. |

### `scrapbot.ui_canvas`

The canvas must share an entity with a root `ui_layout`. Only one canvas may
exist in the project/scene origin and one in the editor origin. Its safe area
constrains the canvas root's children but leaves the root background at the
complete logical viewport.

| Field | Default | Meaning |
| --- | --- | --- |
| `reference_size: Vec2` | `{1280, 720}` | Positive logical design size. |
| `scale_mode: string` | `expand` | `fit`, `fill`, `expand`, `stretch`, `pixel_perfect`, or `none`. |
| `horizontal_alignment`, `vertical_alignment: string` | `center` | Place scaled output at `start`, `center`, or `end` when it does not match the host. |
| `safe_area: Vec4` | `{0, 0, 0, 0}` | Non-negative logical `[top, right, bottom, left]` child insets smaller than the reference size. |
| `min_scale`, `max_scale: number` | `0`, `0` | Optional non-negative bounds; zero is unbounded and a non-zero maximum must be at least the minimum. |

`fit` preserves the reference aspect and may letterbox. `fill` preserves aspect
and may crop. `expand` uses the fit scale but reveals additional logical space
on the host's longer axis. `stretch` scales each axis independently.
`pixel_perfect` chooses a fitting whole-number scale at or above one when
possible. `none` follows output pixel density and exposes the host in logical
units. Without a canvas, project UI retains the legacy top-left 1280×720 fit.

### `scrapbot.ui_hstack` and `scrapbot.ui_vstack`

Both use the same payload:

| Field | Default | Meaning |
| --- | --- | --- |
| `gap` | `0` | Non-negative spacing between children. |
| `fill` | `false` | Treat authored main-axis sizes as proportions and fill available space. |
| `draggable` | `false` | Turn gaps into resize separators; requires `fill`. |
| `min_size` | `0` | Minimum pane extent along the stack axis. |
| `reorderable` | `false` | Allow movable direct-child panels to reorder or transfer through title dragging. |
| `drag_threshold` | `5` | Non-negative pointer distance before title interaction becomes a drag instead of a collapse click. |
| `drop_indicator_color` | `[0.42, 0.92, 0.84, 1]` | HDR insertion-line color. |
| `drop_indicator_thickness`, `drop_indicator_inset` | `2`, `8` | Non-negative insertion-line geometry. |
| `wrap` | `false` | Pack children into additional lines when their preferred outer sizes exceed the main axis. Cannot be combined with legacy `fill`, resize separators, or reordering. |
| `line_gap` | `0` | Non-negative spacing between wrapped lines; `gap` remains spacing between children on one line. |

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
| `disclosure_size`, `disclosure_margin`, `disclosure_gap`, `disclosure_inset` | `10`, `10`, `8`, `0`; all non-negative. The disclosure uses the built-in icon catalog. |
| `collapsible: bool`, `collapsed: bool` | A collapsed panel must be collapsible. |
| `movable: bool` | `false`. A movable panel requires a title and becomes a drag source in a reorderable stack or compatible dock space. |

Panels do not own a special close/remove control. Any direct child `ui_button` with `panel_action = true` is placed in the trailing title band and remains interactive while the panel is collapsed. Multiple actions lay out from right to left.

For a movable panel, pressing the unoccupied title band arms both familiar
behaviors: release inside the drag threshold toggles collapse, while movement
past the threshold starts a workspace drag. Releasing that drag without a valid
destination cancels without toggling collapse. Compatible reorderable stacks
accept insertion transfers, and compatible dock spaces accept the panel as a
new tab by changing its ordinary UUID parent. While docked, the tab uses the
panel title and replaces the internal title band; dragging that tab can return
the panel to a stack. The destination publishes `ui_state` drop metadata and an
immutable UI event. Separators remain independently controlled by the parent
stack's `fill`, `draggable`, and `min_size` fields.

### `scrapbot.ui_dock_space`

A dock space turns each direct child carrying `ui_dock_item`, or each direct
titled `ui_panel`, into one tab. Panels derive the tab title and movement policy
from `ui_panel`; explicit dock items use `ui_dock_item`. Only the active item
participates in descendant layout, paint, focus, and pointer interaction. If
`active` is empty or no longer names an eligible child, the first direct item is
displayed without rewriting authored data.

| Field | Default | Meaning |
| --- | --- | --- |
| `active: string` | Empty UUID | Direct dock-item child UUID selected for display. Authored non-empty references must resolve to one of this space's direct children. |
| `font: string` | Embedded Inter | Font used to measure and paint tab titles. |
| `tab_height` | `32` | Positive height reserved above the active item. |
| `tab_min_width`, `tab_max_width` | `72`, `180` | Positive title-width bounds; maximum must be at least minimum. |
| `tab_gap`, `tab_padding` | `2`, `12` | Non-negative spacing between tabs and horizontal title inset. |
| `tab_size`, `tab_corner_radius` | `12`, `4` | Positive title size and non-negative SDF corner radius. |
| `tab_color` | `[0.68, 0.70, 0.76, 1]` | Inactive title color. |
| `tab_active_color` | `[0.94, 0.95, 0.98, 1]` | Active title color. |
| `tab_background` | `[0.055, 0.060, 0.072, 1]` | Inactive tab background. |
| `tab_hover_background` | `[0.075, 0.082, 0.098, 1]` | Hovered tab background. |
| `tab_active_background` | `[0.105, 0.115, 0.135, 1]` | Active tab background. |
| `drop_background` | `[0.12, 0.72, 0.64, 0.22]` | Destination overlay while a movable tab is dragged over this group. |
| `draggable` | `true` | Accept movable dock items or panels from another compatible container. |
| `split_horizontal`, `split_vertical` | `false`, `false` | Allow edge drops to create left/right or above/below panes from ordinary public layout entities. |
| `split_ratio` | `0.5` | Fraction of available split-axis space assigned to the newly dropped pane. |
| `split_edge_fraction` | `0.25` | Fraction of each enabled content edge that activates its directional drop target. |
| `split_gap` | `4` | Gap between the two generated panes; this becomes the draggable stack separator. |
| `split_min_size` | `120` | Minimum split-axis size for each pane. Edge targets are disabled when both panes plus the gap cannot fit. |

RGB style channels are linear and may exceed `1` for HDR presentation; every
color component must remain finite. Dock regions themselves are ordinary
layout: place dock spaces inside draggable fill HStacks or VStacks to build a
resizable workspace.

With either split axis enabled, dragging a movable panel or tab onto an enabled
content edge replaces the target space in-place with an ordinary public
`ui_hstack` or `ui_vstack`. The existing space and a newly created
`ui_dock_space` become its fill children, and the dropped item becomes the new
space's active child. Center drops retain the tab/stack transfer behavior. The
generated topology uses the same public components, HDR styles, UUID parents,
layout invalidation, and separator interaction available to project-authored
game UI; the editor has no private dock tree.

When a dock item contains a reorderable HStack or VStack, its tab header is a
drop target for that descendant stack. The nearest matching stack wins,
including inside an inactive retained item. Empty dock-space chrome remains the
target for making a movable panel into a sibling tab. An accepting header uses
`drop_background` while targeted, including when its inactive descendant cannot
paint an insertion indicator.

A panel's own reorderable stack becomes a tab-header destination when that
panel is a direct dock-space child. While the panel is nested inside another
stack, the containing stack remains the panel-drop destination.

### `scrapbot.ui_dock_item`

| Field | Default | Meaning |
| --- | --- | --- |
| `title: string` | Required | Non-empty tab title. |
| `movable` | `true` | Allow this item to transfer to another draggable dock space. |

A dock item must be a direct child of a dock space. Dragging its tab across the
five-pixel gesture threshold and releasing over another compatible space
changes the item's public `ui_layout.parent`, activates it in the destination,
updates the destination's read-only drop state, and publishes a `dropped` UI
event. A docked panel may also transfer into a reorderable stack. The current
contract preserves same-group tab order; tab reordering, floating windows,
automatic empty-branch collapse, and persisted workspace layouts are not yet
provided.

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
| `filter_input` | Empty UUID |
| `gap` | `0` |
| `selection_background` | `[0.045, 0.095, 0.105, 1]` |
| `hover_background` | `[0.028, 0.038, 0.050, 1]` |
| `active_background` | `[0.040, 0.055, 0.072, 1]` |
| `highlight_corner_radius` | `4` |
| `draggable` | `false` |
| `drag_threshold` | `5` |
| `drop_edge_fraction` | `0.25` |
| `drop_target_background` | `[0.055, 0.12, 0.13, 1]` |
| `drop_indicator_color` | `[0.42, 0.92, 0.84, 1]` |
| `drop_indicator_thickness` | `2` |
| `drop_indicator_inset` | `8` |
| `tree_enabled` | `false` |
| `tree_indent` | `14` |
| `virtualized` | `false` |
| `item_height` | `0` |
| `overscan` | `0` |

Direct children become full-width selectable rows. Clicking a row or descendant stores the direct child's UUID in `selected`. `highlight_corner_radius` applies to selection, hover, active, and `into` drop-target backgrounds; set it to `0` for square highlights. With `draggable = true`, dragging resolves source and target to direct children. The top and bottom `drop_edge_fraction` of a row classify as `before` and `after` and paint a clipped lander line; its middle classifies as `into` and paints `drop_target_background`. The placement is published through the list's `ui_state`. Radius, threshold, indicator thickness, and inset must be non-negative; the edge fraction must be between 0 and 0.5.

With `tree_enabled = true`, direct children whose layout has `tree_item = true` are flattened depth-first after ordinary direct children. `tree_parent` references another tree row UUID, `tree_order` orders siblings, `tree_indent` offsets row contents without narrowing the full-width selection box, and `tree_collapsed` suppresses descendants. Invalid or cyclic metadata is rendered safely and deterministically. A successful drop mutates the source row's public `tree_parent` and normalizes the affected sibling orders: `into` reparents beneath the target, while `before`/`after` adopts the target's parent and inserts beside it. Descendants follow their row automatically. Disclosure controls remain ordinary composable buttons whose project system toggles `tree_collapsed`.

Set `filter_input` to the UUID of a same-origin `scrapbot.ui_input`. Its text filters rows by an ASCII case-insensitive substring match over descendant `ui_text`, `ui_button`, and `ui_input` text. Tree filtering retains matching rows and their ancestors and temporarily traverses collapsed branches without changing `tree_collapsed`.

Set `virtualized = true` with a positive uniform `item_height` to lay out only the visible rows plus `overscan` rows on each side. The list still reports the exact complete scroll extent when combined with `ui_scroll_area`. Filtering and tree ordering are cached until structure or relevant UI content changes; scrolling does not rescan all rows. `overscan` must be non-negative.

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

### `scrapbot.ui_icon`

| Field | Default | Meaning |
| --- | --- | --- |
| `icon_set` | Empty UUID | Required UUID of a project `scrapbot.icon_set` resource or the built-in catalog. |
| `icon` | Empty | Required SVG filename stem/symbol name in the selected set. |
| `color` | White | Finite, non-negative linear RGBA tint. RGB may exceed `1` for HDR UI. |
| `inset` | `0` | Non-negative inset inside the layout's padded content box. |

The renderer preserves the compiled icon plane aspect and centers it in the available rectangle. Icon resources use the same change-driven registry and MTSDF texture-array path whether they come from a project, a theme, a control, or editor chrome.

The embedded catalog has UUID `a11c0000-0000-4000-8000-000000000001` and symbols `x`, `plus`, `caret-right`, `caret-down`, `magnifying-glass`, `play`, `pause`, `stop`, and `skip-forward`. Luau exposes the UUID as `scrapbot.ui.builtin_icon_set`; native Odin exposes `scrapbot.ui_builtin_icon_set()`.

### `scrapbot.ui_text`

| Field | Default | Meaning |
| --- | --- | --- |
| `text`, `font` | Empty | Text is required and non-empty. Empty font selects embedded Inter. |
| `color`, `size` | White, `16` | Size must be positive. |
| `alignment` | `left` | `left`, `center`, or `right`. |
| `wrap` | `false` | Break at whitespace to fit the padded content width, falling back to glyph boundaries for oversized words. Explicit newlines always start a line. |
| `line_height` | `0` | Positive line advance in logical pixels; zero uses `size`. |

### `scrapbot.ui_button`

| Field | Default | Meaning |
| --- | --- | --- |
| `text`, `font` | Empty | Text is optional when an icon is present. Empty font selects Inter. |
| `color`, `size`, `alignment` | White, `16`, `center` | Normal label style. |
| `hover_background`, `active_background` | Transparent | State-specific layout background overrides. |
| `hover_color`, `active_color` | Transparent | State-specific text colors; transparent falls back to normal color. |
| `icon_set`, `icon` | Empty | Optional icon-set UUID plus symbol name. Text is optional when both are present. |
| `icon_position` | `leading` | `leading` or `trailing` relative to text. |
| `icon_size` | `0` | Icon box size in pixels; `0` derives it from the button content height. |
| `icon_gap`, `icon_inset` | `6`, `6` | Non-negative spacing between icon/text and inset inside the icon box. |
| `panel_action` | `false` | Place this direct child button in its parent's panel title band. |
| `popup` | Empty UUID | Target a popup-layout root. Activation assigns this button as its anchor, toggles it, and closes another open popup in the same UI domain. |

Same-domain pointer presses outside a popup and Escape close it through shared UI mechanics. Combine a popup root with ordinary stack, list, and scroll-area components rather than creating a private menu widget.

### `scrapbot.ui_input`

| Fields | Defaults and rules |
| --- | --- |
| `text`, `font`, `prefix` | Empty. Empty font selects Inter. |
| `icon_set`, `icon` | Empty. Optional icon-set UUID plus symbol; both must be set together. |
| `icon_position` | `leading`. The prefix badge, when present, remains outside a leading icon. |
| `icon_color` | White. HDR tint for the monochrome icon mask. |
| `icon_size`, `icon_gap`, `icon_inset` | `0`, `6`, `0`. Zero size derives a box from the input text/content height; geometry must be non-negative. |
| `color`, `size` | White, `16`; size must be positive. |
| `prefix_color`, `prefix_background`, `prefix_width` | White, transparent, `0`. |
| `selection_background`, `selection_corner_radius` | `[0.15, 0.45, 0.40, 0.55]`, `2`. |
| `focus_border_color`, `focus_border_width` | `[0.15, 0.85, 0.72, 1]`, `1`. |
| `invalid_border_color`, `invalid_border_width` | `[0.92, 0.24, 0.28, 1]`, `1.5`. |
| `caret_color`, `caret_width`, `caret_inset` | Transparent, `1`, `2`. Transparent caret color falls back to text color. |
| `prefix_gap`, `prefix_corner_radius`, `prefix_text_padding` | `3`, `2`, `3`. |
| `number`, `step`, `minimum`, `maximum` | `0`, `1`, `0`, `0`. Step must be positive in numeric mode. |
| `read_only`, `numeric`, `draggable`, `has_minimum`, `has_maximum` | `false`. Bounds apply only when their matching flag is true. Writable inputs use the text-edit cursor; `draggable` opts a numeric input into horizontal pointer scrubbing and switches to its resize cursor while armed or active. |

Numeric values and enabled bounds must be finite, the number must remain inside enabled bounds, and minimum cannot exceed maximum. Icon, prefix, selection, border, caret, and radius geometry is non-negative. The icon stays fixed while long editable text scrolls within the remaining clipped content.

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

### `scrapbot.ui_color_picker`

| Field | Default | Meaning |
| --- | --- | --- |
| `value` | `[1, 1, 1, 1]` | Canonical direct linear RGBA color. RGB channels are finite and non-negative; alpha is in `[0, 1]`. |
| `hdr` | `true` | Enables RGB values above `1` and shows the exposure track. When false, RGB is bounded to `[0, 1]` and exposure must be zero. |
| `show_alpha` | `true` | Shows the checker-backed alpha track. |
| `read_only` | `false` | Paints the control without accepting pointer edits. |
| `exposure`, `maximum_exposure` | `0`, `16` | Current and maximum EV presentation values. Both are finite, non-negative, and at most `32`; exposure cannot exceed the maximum. |
| `track_height`, `gap`, `thumb_radius` | `14`, `8`, `6` | Positive track/thumb geometry with a non-negative gap. |
| `thumb_color`, `thumb_border_color`, `thumb_border_width` | White, near-black, `2` | Shared pad/track marker style. Border width is non-negative. |
| `checker_light`, `checker_dark` | Light gray, dark gray | Alpha-track checker colors. |

Dragging writes `value` directly in linear space and advances `ui_state.change_revision`; releasing advances `submit_revision` once. HDR is not an encoded display-space color: the EV control changes direct RGB magnitude, while painting uses a bounded preview. Compose the picker directly or place it in a public popup targeted by an ordinary `ui_button`.

### `scrapbot.ui_action`

| Field | Default | Meaning |
| --- | --- | --- |
| `action` | Required | Non-empty semantic action name, at most 64 UTF-8 bytes. |
| `payload` | Empty | Optional opaque project payload, at most 256 UTF-8 bytes. |

Attach `ui_action` to an interactive control or any of its UI layout ancestors. When the control activates, changes, submits, cancels, or completes a drop, the published event copies the nearest action and payload while retaining the exact interacted entity UUID.

`ui_action` does not make an entity interactive and does not affect layout or paint. It adds project meaning to existing reusable controls.

## Related references

- [Project File Reference](/reference/project-files/) shows complete TOML examples.
- [Luau API](/reference/luau-api/) covers queries, systems, resources, and lifecycle commands.
- [ECS UI](/guides/ecs-ui/) explains composition and interaction patterns.
- [Native Extensions](/guides/native-extensions/) documents typed Odin payloads and access declarations.
