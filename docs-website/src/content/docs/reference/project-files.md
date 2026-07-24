---
title: Project File Reference
description: The current manifest, resource, and scene file subset supported by Scrapbot.
---

Scrapbot's file formats intentionally cover a narrow subset right now. Valid TOML outside this subset may still fail.

## Manifest

`project.toml` supports:

```toml
name = "Minimal Example"
default_scene = "scenes/main.scene.toml"

[window]
width = 1600
height = 900

[[native_extensions]]
name = "scrappyphysics"
source = "native/scrappyphysics"

[[fonts]]
name = "display"
source = "assets/fonts/Display.otf"
```

Fields:

| Field | Required | Meaning |
| --- | --- | --- |
| `name` | Yes | Display name for the project. |
| `default_scene` | Yes | Safe relative path to the scene loaded by `check` and `run`. |
| `[window]` | No | Initial logical window size. Omitted fields default to 1600×900. |
| `window.width` | No | Positive logical width up to 16384. |
| `window.height` | No | Positive logical height up to 16384. |
| `[[native_extensions]]` | No | Repeated table for project-local native extension targets. |
| `native_extensions.name` | Yes | Build output base name. Must be an identifier token. |
| `native_extensions.source` | Yes | Safe relative path to an Odin package directory. |
| `[[fonts]]` | No | Repeated table for project-local UI font resources; at most 15. |
| `fonts.name` | Yes | Resource name used by UI components. Must be a unique identifier token. |
| `fonts.source` | Yes | Safe path under `assets/` ending in `.ttf` or `.otf`. |

The legacy optional `[render]` environment fields remain accepted as a compatibility fallback for scenes without `scrapbot.world_environment`. New projects and migrated examples should author environment state on the scene entity; when present, that component is authoritative.

Visible windows preserve the requested aspect ratio but scale down when necessary to fit within 90% of the primary display's usable area. High-pixel-density displays may provide a larger physical-pixel framebuffer than this logical size. Headless framegrabs remain fixed at 1280×720 unless cropped.

Scrapbot automatically generates a 512×512 printable-ASCII MTSDF atlas and glyph metadata under `.scrapbot/cache/fonts/` when a declared source or the compiler settings change. Install `msdf-atlas-gen` so `scrapbot check`, `build`, or `run` can satisfy a cache miss (`brew install msdf-atlas-gen` on macOS), or point `SCRAPBOT_MSDF_ATLAS_GEN` at the executable. Packaged projects contain the generated artifacts and do not need the generator or platform font APIs at runtime. Font licensing remains the project's responsibility.

Embedded Inter is always available as the default and runtime fallback. The current font slice supports printable ASCII only; unsupported characters render as `?`, and shaping, kerning, variable-font axes, and Unicode fallback chains are not implemented yet.

## Project resources

Scrapbot recursively discovers standalone files under `resources/` whose names end in `.resource.toml`. Resources are typed project data outside the ECS and are not owned by a scene. Every resource has a unique, non-zero UUID; names and file paths remain editable labels and storage locations.

Texture import resources identify source images independently of materials:

```toml
id = "b1000000-0000-4000-8000-000000000002"
type = "scrapbot.texture"
name = "Coral Texture"

[texture]
source = "assets/coral.png"
color_space = "srgb"
generate_mipmaps = true
```

`source` must be a safe project-relative PNG path under `assets/`. `color_space` is `srgb` or `linear`; mip generation defaults to true. Scrapbot imports RGBA8 mip products into ignored `.scrapbot/imported/` state.

HDR environment resources identify reusable lighting sources:

```toml
id = "b1000000-0000-4000-8000-000000000004"
type = "scrapbot.environment"
name = "Studio"

[environment]
source = "assets/studio.hdr"
```

`source` must be a safe 2:1 Radiance `.hdr` path under `assets/`. Importing preserves the source-resolution panorama and derives a 32×32 diffuse irradiance cube plus an eight-level 128×128 roughness-prefiltered specular cube in linear RGBA16F. A scene's `scrapbot.world_environment` component selects image-based lighting independently from presentation. The visible background may select another Environment or use the built-in procedural haze sky. Background intensity, rotation, exposure compensation, and blur are independent. The runtime uploads changed panoramas and cubes only when their resource versions or environment settings change. Local reflection probes are not implemented yet.

Material resources store shared surface data and reference Texture UUIDs:

```toml
id = "b1000000-0000-4000-8000-000000000001"
type = "scrapbot.material"
name = "Coral"

[material]
base_color = [1.0, 0.25, 0.08, 1.0]
emissive = [0.0, 0.0, 0.0]
texture = "b1000000-0000-4000-8000-000000000002"
```

`base_color` defaults to white, `emissive` defaults to black and accepts finite non-negative HDR values, and `texture` is optional. Scrapbot loads authored resources into its runtime registry before resolving scene entities. A changed resource preserves its runtime handle and increments its content version; removal invalidates old handles. Resource files participate in hot reload and host-native packaging.

Static glTF model resources point at `.gltf` or `.glb` sources:

```toml
id = "b1000000-0000-4000-8000-000000000003"
type = "scrapbot.model"
name = "Crate"

[model]
source = "assets/models/crate.glb"
```

The importer starts at the selected/default glTF scene and includes only reachable nodes, meshes, materials, and images. It supports triangle primitives, positions, optional normals and UV0, optional indices, TRS node hierarchies, metallic-roughness material factors, normal and occlusion strengths, emissive factors, `OPAQUE` and alpha-cutout `MASK` materials, `alphaCutoff`, `doubleSided`, and base-color, metallic-roughness, normal, occlusion, and emissive images. Images may come from GLB buffer views, base64 data URIs, or safe relative files beside the `.gltf`; every image dependency participates in cache invalidation. Missing normals are generated. Imported subresources use semantic keys derived from authored names, hierarchy, and content where necessary, so harmless glTF array reordering preserves generated handles and derived entity UUIDs.

Imported images use complete RGBA8 mip chains. Base color and emissive use sRGB sampling; packed metallic-roughness, normal, and occlusion maps use linear sampling. Every material texture slot preserves its glTF minification, magnification, mip, and U/V wrap settings; omitted samplers use the glTF defaults. WGPU renders these through its shared GGX material path with derivative-reconstructed normal mapping, direct ECS lights, optional imported image-based environment lighting, HDR emission, bloom, exposure, and tone mapping. Masked alpha is applied consistently to the color pass, depth prepass, and directional shadow pass; double-sided materials disable back-face culling and shade back faces with an inverted surface normal. `BLEND` materials fail import until Scrapbot has sorted transparent rendering. Animation, skins, morph targets, matrix-authored nodes, Draco/required extensions, non-UV0 texture mappings, texture transforms, KTX2/Basis images, and advanced material extensions are not supported yet.

Generated icosphere LOD resources store one stable geometry identity plus up to four tessellation levels:

```toml
id = "b1000000-0000-4000-8000-000000000010"
type = "scrapbot.geometry_lod"
name = "Planet LOD"

[geometry_lod]
radius = 0.5
subdivisions = [4, 2, 0]
screen_radii = [0.15, 0.04]
```

`subdivisions` contains one to four icosphere subdivision levels from most detailed to least detailed; each value must be between `0` and `4`. `screen_radii` has one fewer value and must be positive and strictly descending. The WGPU visibility pass projects each instance's bounding sphere and selects the next level whenever its normalized screen radius falls below the corresponding threshold. The CPU-culling reference path uses the same rule. Editing the file and hot reloading preserves the stable base geometry handle while advancing renderer topology.

The live editor's Resources browser creates, duplicates, renames, moves, and deletes material resources as stopped-mode in-memory authoring transactions. Scene references remain stable because these operations preserve the resource UUID. Delete is unavailable while a live entity references the UUID. Explicit Save derives the required file writes and deletions from the disk baseline, rejects destination conflicts, and commits the complete project file set through the recoverable Save transaction. Geometry LOD resources are text-authored in this slice; editor creation and inline level editing remain follow-up work.

## Scene entities

Entities use repeated `[[entities]]` tables.

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000001"
name = "Main Camera"
```

Every entity must have a unique, non-zero RFC UUID in `id` and a `name`. The ID is stable project identity; the name is an editable display label.

## Built-in component sections

For a complete inventory of public engine components, reflected fields, defaults, constraints, and cross-surface names, see the [Engine Component Reference](/reference/components/).

Transform:

```toml
[entities.transform]
parent = "20000000-0000-4000-8000-000000000001"
position = [0, 2, 6]
rotation = [-0.321751, 0, 0]
scale = [1, 1, 1]
```

`parent` is optional. When present, it must be the UUID of another scene entity. Position, rotation, and scale are local to that parent; a parent without a Transform contributes an identity spatial basis, while roots use world-space values. Missing parents, self-parenting, and cycles fail validation. The derived world transform is runtime state and is never written as a second source value. This TRS model does not preserve shear beneath rotated non-uniform scale.

Camera:

```toml
[entities.camera]
fov = 60
near = 0.1
far = 100
exposure = 1
temporal_antialiasing = true
fast_antialiasing = false
ambient_occlusion = true
screen_space_reflections = false
bloom = true
```

A camera reads its world position and Euler orientation from the entity's resolved transform chain. Rotation is expressed in radians: X controls pitch, Y controls yaw, and Z controls roll. `exposure` is a positive linear multiplier, defaults to `1`, and combines with the World Environment exposure. TAA, GTAO ambient occlusion, and bloom default on; fast fullscreen antialiasing and material-aware screen-space reflections default off. Fast AA is used only when TAA is off. GTAO affects only indirect diffuse lighting and cannot see geometry absent from the current depth buffer. SSR reflects only current-frame, on-screen world surfaces and fades rough, distant, uncertain, and screen-edge hits. These switches are per camera and may be changed live through the generated inspector or Luau query writeback.

World environment:

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000002"
name = "World Environment"

[entities.world_environment]
lighting = "b1000000-0000-4000-8000-000000000004"
lighting_intensity = 1
lighting_rotation = 0
exposure = 1
background_visible = true
background = ""
background_intensity = 1
background_rotation = 0
background_exposure = 1
background_blur = 0
sky_tint = [1, 1, 1]
ground_color = [0.24, 0.235, 0.225]
turbidity = 2
atmosphere_thickness = 1
horizon_softness = 1
sun_direction = [-0.5, 0.25, -0.83]
sun_color = [1, 0.92, 0.72]
sun_intensity = 1
sun_size = 1
sun_glow = 1
```

A scene may contain at most one World Environment. `lighting` and `background` are optional Environment-resource UUIDs. An empty visible background reuses the lighting Environment; when both are empty, Scrapbot renders its built-in procedural haze sky. The atmosphere fields tune that procedural sky live and do not alter imported HDR backgrounds. Procedural sun elevation drives horizon occlusion and day/twilight/night presentation; above the horizon it also contributes the primary derived directional light and shadow direction. Explicit ECS lights remain additive. See the [component reference](/reference/components/#scrapbotworld_environment) for field constraints and change-driven runtime behavior.

Built-in primitive convenience:

```toml
[entities.mesh]
primitive = "cube"
```

The mesh component currently resolves `cube` into the built-in cube geometry and default material needed by the entity. It is the compact path used by generated projects.

Imported model instance:

```toml
[entities.model]
resource = "b1000000-0000-4000-8000-000000000003"
```

The UUID must name an authored `scrapbot.model` resource. Scrapbot retains the authored entity as the model root and reconciles imported nodes/primitives into stable derived ECS children. Their local transforms preserve the imported hierarchy; renderable children receive the generated Geometry and Material handles. Reimport/reload replaces only this derived hierarchy, never the authored root.

Explicit render resources:

```toml
[entities.geometry]
resource = "b1000000-0000-4000-8000-000000000010"

[entities.material]
resource = "b1000000-0000-4000-8000-000000000001"
```

Geometry accepts either a transient runtime resource name such as `cube` or a stable UUID for an authored `scrapbot.geometry_lod` resource. Material is a stable project resource UUID and must resolve to an authored `scrapbot.material` resource. Entities become renderable once transform, geometry, and material references are valid.

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

Casters write to the first directional light's four camera-relative shadow cascades. Receivers select and PCF-sample the appropriate cascade. The markers are independent, so geometry may cast without receiving or receive without casting.

Screen-space UI entities share a retained box model and compose container or content components:

For a task-oriented introduction covering layout, runtime construction, and interaction state, see [ECS UI](/guides/ecs-ui/).

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000010"
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
id = "d4000000-0000-4000-8000-000000000011"
name = "Title"

[entities.ui_layout]
parent = "d4000000-0000-4000-8000-000000000010"
size = [412, 52]

[entities.ui_text]
text = "SCRAPBOT UI"
font = "display"
color = [0.15, 0.95, 0.82, 1]
size = 32
alignment = "left"

[[entities]]
id = "d4000000-0000-4000-8000-000000000012"
name = "Launch"

[entities.ui_layout]
parent = "d4000000-0000-4000-8000-000000000010"
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
id = "d4000000-0000-4000-8000-000000000013"
name = "Player Name"

[entities.ui_layout]
parent = "d4000000-0000-4000-8000-000000000010"
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
id = "d4000000-0000-4000-8000-000000000019"
name = "Enabled"

[entities.ui_layout]
parent = "d4000000-0000-4000-8000-000000000010"
size = [40, 40]

[entities.ui_checkbox]
checked = true
box_size = 20
background = [0.025, 0.03, 0.04, 1]
checked_background = [0.08, 0.55, 0.46, 1]
border_color = [0.24, 0.27, 0.32, 1]
check_color = [0.95, 0.97, 0.98, 1]
hover_background = [0.12, 0.64, 0.54, 1]
active_background = [0.06, 0.42, 0.36, 1]
read_only = false

[[entities]]
id = "d4000000-0000-4000-8000-000000000014"
name = "Feature Scroll"

[entities.ui_layout]
parent = "d4000000-0000-4000-8000-000000000010"
size = [412, 160]
padding = [8, 8, 8, 8]
background = [0.08, 0.09, 0.11, 1]
corner_radius = 10

[entities.ui_scroll_area]
scroll_speed = 64
smoothness = 14

[[entities]]
id = "d4000000-0000-4000-8000-000000000015"
name = "Feature Pane"

[entities.ui_layout]
parent = "d4000000-0000-4000-8000-000000000014"
size = [396, 360]
min_size = [240, 160]
fill_width = true
fill_height = true
fit_content_height = true

[entities.ui_vstack]
gap = 8
```

Positions and sizes are screen pixels from the top-left. `margin` and `padding` use `[top, right, bottom, left]`. Layout `min_size` is a per-axis lower bound. `fill_width` and `fill_height` expand an element to the corresponding available parent axis; `fit_content_width` and `fit_content_height` expand or shrink it around visible children. Fill and fit can be combined, producing the larger of available space, visible content, and `min_size`. Resolved sizes remain renderer state and do not overwrite the authored `size` value. `border_color` and non-negative `border_width` add an inset signed-distance border that follows `corner_radius`. `hidden = true` removes the box and its descendant subtree from layout, paint, interaction, and parent content measurement without despawning their entities. Add `ui_hstack` or `ui_vstack` with a non-negative `gap` to arrange children in scene order; an element without either stack overlays its children inside the parent's padded content box. Set stack `fill = true` to treat authored child sizes as proportions along the stack axis and fill the available cross-axis. Set a child's layout `fixed_in_fill = true` to preserve its authored main-axis size while flexible siblings divide the remainder. Add `draggable = true` to turn the gaps into pointer-draggable separators; stack `min_size` sets the non-negative minimum pane extent on the stack axis. Draggable separators show the matching horizontal- or vertical-resize system cursor while hovered or dragged. Draggable stacks must also enable fill. A `ui_text` can set `alignment` to `"left"`, `"center"`, or `"right"` within its padded content box. Backgrounds, borders, corner radii, progress bars, checkbox boxes, and checkbox marks are rendered with signed-distance shapes. Parent UUIDs must resolve to another UI layout entity, cycles are rejected, and one entity cannot combine multiple flow containers (`ui_hstack`, `ui_vstack`, `ui_table`, or `ui_list`) or more than one of `ui_text`, `ui_button`, `ui_input`, and `ui_checkbox`.

A `ui_progress` component paints an optional track and a clamped fill inside its ordinary layout box. `inset` uses `[top, right, bottom, left]`; `right_to_left` anchors the fill to the opposite edge. A zero-alpha `background_color` omits the track:

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000016"
name = "Frame Budget"

[entities.ui_layout]
size = [320, 16]

[entities.ui_progress]
value = 3.25
maximum = 10
fill_color = [0.25, 0.75, 1, 1]
background_color = [0.08, 0.09, 0.11, 1]
inset = [5, 0, 5, 0]
corner_radius = 2
right_to_left = true
```

A `ui_viewport` embeds a renderer-backed Texture, Model, or Material resource—or the retained active World—inside its ordinary layout box. Model and Material targets frame themselves automatically; drag to orbit and use the wheel to zoom. Omit `resource` to render the World, optionally through a `camera` entity UUID and restricted to a `root` entity plus descendants:

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000017"
name = "Ship Preview"

[entities.ui_layout]
size = [480, 270]
corner_radius = 8

[entities.ui_viewport]
resource = "a7000000-0000-4000-8000-000000000001"
orbit = [-0.35, 0.55]
distance = 3
clear_color = [0.012, 0.017, 0.024, 1]
interactive = true
```

Viewport surfaces obey normal ancestor clipping, scrolling, and paint order. WGPU pools eight independently sized 64–1024-pixel targets. Static Texture, Model, and Material previews remain cached until their component, quantized target size/aspect, or referenced resources change.

The renderer automatically attaches a read-only `ui_state` component to every laid-out element. Project systems can query it for hover, active, focus, activation, change, validation, submission, cancellation, and draggable-list drop state. Transient booleans describe the most recent UI pass; the matching revision counters are monotonic counters for reliable edge detection. Projects do not author or mutate `ui_state`.

Pointer hit testing gives the topmost element under the pointer hover state. Pressing the primary button captures active state on that element until release and advances its public activation revision. Buttons can consume those generic states through `hover_background`, `active_background`, `hover_color`, and `active_color`; a zero-alpha state color falls back to the normal layout background or button text color. Button labels use `alignment = "left"`, `"center"`, or `"right"` inside the padded box and default to centered. A button may instead set `icon = "close"`, `"plus"`, `"chevron_right"`, or `"chevron_down"`; `icon_inset` and `icon_stroke` control its SDF geometry, and text is optional when an icon is present.

Set `font` on `ui_text`, `ui_button`, `ui_input`, or `ui_panel` to a name declared in `project.toml`; omit it to use Inter. A panel's selection applies to its title, while child controls select their own fonts independently.

Clicking a `ui_input` focuses it and selects all its text. Focused inputs support typed single-line ASCII text, Left/Right/Home/End movement, Shift selection, Backspace/Delete, Select All, and paint-order Tab/Shift+Tab traversal. Enter submits the current value and removes focus; Escape restores the value present when focus began. The component's `text` field changes during editing, while `ui_state.changed`, `submitted`, and `cancelled` plus their revision counters expose reusable interaction edges.

Set `numeric = true` to give an input a numeric `number`, positive `step`, optional `minimum`/`maximum`, Up/Down stepping, and validation through `ui_state.valid`. Add `draggable = true` to opt a writable numeric input into horizontal pointer scrubbing across the complete control surface. `prefix`, `prefix_width`, `prefix_color`, and `prefix_background` provide a reusable leading badge such as the inspector's X/Y/Z controls, but are not required for scrubbing. Set `read_only = true` to retain focus, selection, and traversal without allowing mutation. Clipboard operations, IME composition, Unicode shaping, and multiline editing are not implemented yet.

Control chrome is authored rather than editor-private. Scroll areas expose scrollbar width, right margin, vertical inset, minimum thumb size, track/thumb colors, and corner radius. Panels expose disclosure geometry plus trailing-action size, margin, icon inset, radius, and state colors. Inputs expose prefix gap/padding/radius, selection radius, focus and invalid borders, and caret color/width/inset. Checkboxes expose box and check radii, border width, and check inset. Set any corner radius to `0` for square corners; checkbox radii and check inset use `-1` as the automatic size-relative default.

A `ui_checkbox` stores its current boolean in `checked` and toggles on primary-button press. `box_size` controls the square inside the element's layout box; the remaining fields style its unchecked, checked, hover, active, border, and SDF checkmark colors. Set `read_only = true` to display state without accepting pointer changes. A successful toggle advances the element's public `ui_state.change_revision`.

A `ui_scroll_area` clips descendants to its padded content rectangle and scrolls vertically when the pointer wheel is over it. Give its nested pane an explicit size larger than the viewport; that pane may contain overlays or stacks of any size. `scroll_speed` is the target movement per wheel unit and `smoothness` controls frame-time interpolation toward that target. Both must be positive. Nested scroll clips intersect, and only the topmost hovered scroll area consumes a wheel update.

A `ui_list` lays out its direct children as full-width selectable rows in scene order. Clicking a row or any of its descendants stores that row's UUID in the list's ECS-owned `selected` field. `gap` controls row spacing, while `selection_background`, `hover_background`, and `active_background` style interaction states. Set `draggable = true` to resolve drag sources and targets to direct children. `drag_threshold` controls gesture recognition. `drop_edge_fraction` assigns the top and bottom portions of a target row to `before` and `after`; the middle is `into`. `drop_indicator_color`, `drop_indicator_thickness`, and `drop_indicator_inset` style insertion lines, while `drop_target_background` styles an into target. During a gesture, the list's read-only `ui_state` exposes `dragging`, `drag_source`, `drop_target`, and `drop_placement`; a completed in-list drop increments `drop_revision` and `change_revision`. An empty target UUID with `into` means the list background. Set `tree_enabled = true` to interpret direct children with layout `tree_item = true` as a nested tree. Their `tree_parent` is another row UUID, `tree_order` is sibling-local, and `tree_collapsed` hides descendants. `tree_indent` defaults to 14 pixels. Tree drops update those public layout fields: `into` reparents, while `before` and `after` can reparent and reorder in one operation. Combine the list with `ui_scroll_area` on the same entity for long lists:

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000030"
name = "Entity List"

[entities.ui_layout]
size = [280, 400]

[entities.ui_list]
gap = 2
selection_background = [0.045, 0.095, 0.105, 1]
hover_background = [0.028, 0.038, 0.050, 1]
active_background = [0.040, 0.055, 0.072, 1]

[entities.ui_scroll_area]
scroll_speed = 64
smoothness = 14
```

Each direct child supplies its own row height and may use an overlay or another flow container for its contents. A list cannot share its entity with another flow container.

Panels add a styled title band without choosing how their children flow, so they can compose with an overlay, stack, or nested table. Set `collapsible = true` on a titled panel to make its title band interactive. Its ECS-owned `collapsed` value selects the initial/current state: collapsed panels contract to the title height and omit ordinary descendants from layout, paint, focus traversal, and pointer interaction. A small SDF disclosure chevron shows the current state. To add title actions, create ordinary direct child buttons with `panel_action = true`; they may use text or the reusable `close` and `plus` SDF icons, activate independently, remain available while collapsed, and lay out from right to left. Tables place children in row-major order across 1–64 columns. Columns are equal by default. With `proportional_columns = true`, the first row's positive authored cell widths become reusable weights for every row; for example, widths `1` and `2` create a one-third/two-thirds split. `resizable_columns = true` turns column gaps into draggable separators and requires proportional columns; `min_column_width` limits adjacent-column shrinking. Resized proportions remain local to the current UI session. Child heights determine row height; `column_gap` and `row_gap` control spacing. A partial final row starts at the first column.

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000020"
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
collapsible = true
collapsed = false

[entities.ui_vstack]

[[entities]]
id = "d4000000-0000-4000-8000-000000000021"
name = "Stats Table"

[entities.ui_layout]
parent = "d4000000-0000-4000-8000-000000000020"
size = [340, 100]

[entities.ui_table]
columns = 3
column_gap = 8
row_gap = 4
proportional_columns = true
resizable_columns = true
min_column_width = 48
```

Each child of `Stats Table` occupies the next table cell. Give the first three child layouts the desired width weights; subsequent rows reuse them. A table is a flow container and therefore cannot share an entity with `ui_hstack`, `ui_vstack`, or `ui_list`; a panel is decoration and may share an entity with any flow container.

## Custom component sections

```toml
[entities.components.autorotate]
velocity = [0, 1.5707963, 0]

[entities.components.fountain]
spawn_rate = 18
wind = [0.25, 0]
tint = [1, 0.4, 0.1, 1]

[entities.components.scrappyphysics.rigidbody]
velocity = [0, 0, 0]
```

Rules:

- single-token names are project components;
- dotted names are engine or library components;
- fields are single-token names;
- supported field values are finite numbers and two-, three-, or four-number arrays according to the registered Number, Vec2, Vec3, Vec4, or Color schema;
- Color fields use four RGBA values and remain semantically distinct from ordinary Vec4 fields;
- scene data must match a component schema collected from the engine, Luau, or native extensions.
