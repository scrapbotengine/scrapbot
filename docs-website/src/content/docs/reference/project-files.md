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

[render]
virtual_geometry_budget_mb = 64

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
| `[render]` | No | Renderer-wide project policy. |
| `render.virtual_geometry_budget_mb` | No | Budget for resident virtual-geometry vertex and index pages, from 0.015625 to 16384 MiB. Defaults to 64 MiB. Pinned coarse fallback pages may exceed it. |
| `render.virtual_geometry_prefetch` | No | Predict refinement from bounded camera motion and a widened future view. Defaults to `true`; visible demand remains available when disabled. |
| `render.virtual_geometry_index_budget_mb` | No | Deprecated alias for `render.virtual_geometry_budget_mb`; retained for existing projects. |
| `[[native_extensions]]` | No | Repeated table for project-local native extension targets. |
| `native_extensions.name` | Yes | Build output base name. Must be an identifier token. |
| `native_extensions.source` | Yes | Safe relative path to an Odin package directory. |
| `[[fonts]]` | No | Repeated table for project-local UI font resources; at most 15. |
| `fonts.name` | Yes | Resource name used by UI components. Must be a unique identifier token. |
| `fonts.source` | Yes | Safe path under `assets/` ending in `.ttf` or `.otf`. |

The optional `[render]` table owns renderer-wide policy such as the virtual-geometry payload budget.
Its environment fields remain accepted as a compatibility fallback for scenes without
`scrapbot.world_environment`. New projects should author environment state on the scene entity;
when present, that component is authoritative.

Visible windows preserve the requested aspect ratio but scale down when necessary to fit within 90% of the primary display's usable area. High-pixel-density displays may provide a larger physical-pixel framebuffer than this logical size. Headless framegrabs remain fixed at 1280×720 unless cropped.

Scrapbot automatically generates a 512×512 printable-ASCII MTSDF atlas and glyph metadata under `.scrapbot/cache/fonts/` when a declared source or the compiler settings change. Install `msdf-atlas-gen` 1.4.0 so `scrapbot check`, `build`, or `run` can satisfy a cache miss (`brew install msdf-atlas-gen` on macOS), or point `SCRAPBOT_MSDF_ATLAS_GEN` at the executable. `mise setup` validates that exact generator version. Packaged projects contain the generated artifacts and do not need the generator or platform font APIs at runtime. Font licensing remains the project's responsibility.

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

Icon-set resources compile directories of project-authored SVG symbols:

```toml
id = "b1000000-0000-4000-8000-000000000005"
type = "scrapbot.icon_set"
name = "Game Icons"

[icon_set]
source = "assets/icons"
```

`source` must be a safe project-relative directory under `assets/`. Scrapbot discovers `.svg` files recursively in deterministic path order; each filename stem becomes its symbol name. Sets support up to 256 unique monochrome symbols. The compiler normalizes supported primitives, groups, transforms, strokes, and compound paths, then writes a 512×512 linear RGBA8 MTSDF atlas plus versioned symbol metadata under `.scrapbot/imported/`.

Animation, external references, filters, masks, embedded raster images, gradients, and multicolor paint are rejected with resource-specific diagnostics. Symbol paths are at most 63 ASCII bytes so every public scene, Luau, and native button transport can represent them. A cache miss requires the validated `msdf-atlas-gen` 1.4.0 tool; its exact version is part of the importer schema and changing it invalidates cached products. The packaged runtime contains only compiled products and never parses SVG. The embedded catalog UUID is `a11c0000-0000-4000-8000-000000000001`.

Material resources store shared surface data and reference Texture UUIDs:

```toml
id = "b1000000-0000-4000-8000-000000000001"
type = "scrapbot.material"
name = "Coral"

[material]
base_color = [1.0, 0.25, 0.08, 1.0]
emissive = [0.0, 0.0, 0.0]
metallic = 0.0
roughness = 0.8
texture = "b1000000-0000-4000-8000-000000000002"
```

`base_color` defaults to white, `emissive` defaults to black and accepts finite non-negative HDR values, `metallic` defaults to `0`, and `roughness` defaults to `0.8`. Metallic and roughness are finite factors from `0` to `1`. `texture` is optional. Scrapbot loads authored resources into its runtime registry before resolving scene entities. A changed resource preserves its runtime handle and increments its content version; removal invalidates old handles. Resource files participate in hot reload and host-native packaging.

Materials may also reference an authored project shader:

```toml
[material]
shader = "b1000000-0000-4000-8000-000000000006"
shader_parameters = [0.05, 0.4, 0.5, 0.75, 0, 0.1, 0.2, 0.02, 1, 1, 1, 0.01, 0.2, 0.7, 0.8, 1]
alpha_mode = "blend"
double_sided = true
```

`shader_parameters` is four generic `Vec4` slots in row-major order. `alpha_mode` accepts `opaque`, `mask`, or `blend`; blended materials require a custom shader. They render after opaque geometry, test but do not write depth, and may sample the opaque scene color and depth through the shader ABI.

Shader resources point at WGSL hook source under `shaders/`:

```toml
id = "b1000000-0000-4000-8000-000000000006"
type = "scrapbot.shader"
name = "Coastal Water"

[shader]
source = "shaders/coastal-water.wgsl"
cull_mode = "none"
```

The source defines `fn scrapbot_vertex(input: Scrapbot_Vertex) -> Scrapbot_Vertex` and `fn scrapbot_fragment(input: Scrapbot_Fragment) -> Scrapbot_Surface`. Scrapbot owns entry points, camera and instance transport, render targets, and blending. Vertex input includes the object model and normal matrices so displacement can be authored in world scale without hard-coding an entity's transform.

Fragment input exposes viewport-local `screen_uv` for procedural effects and full-target `scene_uv` for scene texture reads. Hooks can use:

- `scrapbot_parameter`, `scrapbot_time_seconds`, `scrapbot_delta_seconds`, and `scrapbot_frame_index` for authored data and animation;
- `scrapbot_pixel_size` for viewport-local derivatives and `scrapbot_scene_pixel_size` for target texture offsets;
- `scrapbot_scene_color`, `scrapbot_scene_depth`, and `scrapbot_scene_view_depth` for opaque-scene sampling;
- `scrapbot_scene_uv` and `scrapbot_scene_uv_valid` to convert and guard displaced samples inside the active viewport; and
- `scrapbot_environment_reflection` for the active roughness-filtered reflection environment.

Scene sampling functions accept full-target UVs. Use `input.scene_uv` as the undisplaced sample; passing `input.screen_uv` directly is incorrect when rendering inside an offset editor or game viewport.

Custom shaders currently require `alpha_mode = "blend"`. Opaque custom materials need matching displaced depth-prepass and shadow contracts before they can be enabled safely. Blended draws are sorted back-to-front per instance on the CPU; a bounded GPU sort for very large transparent sets remains tracked work.

A shader that computes ordinary translucent coverage returns that coverage in `Scrapbot_Surface.color.a`. A single-layer transmission shader may instead sample the opaque scene, compose transmission and reflection itself, and return alpha one so the pass does not blend the background into the result twice.

UI-theme resources customize the shared semantic recipe vocabulary:

```toml
id = "71c20000-0000-4000-8000-000000000001"
type = "scrapbot.ui_theme"
name = "Neon Overdrive"

[theme]
base = "reduced_dark"

[theme.palette]
panel = [0.10, 0.015, 0.18, 0.98]
accent = [0.35, 1, 0.22, 1]
accent_soft = [1.4, 0.08, 0.38, 1]
text_secondary = [0.25, 0.92, 1, 1]

[theme.metrics]
control_height = 82
radius = 18
radius_large = 40
padding_control = [24, 20, 18, 20]

[theme.typography]
font = "Inter"
```

`theme.base` is required and currently accepts `reduced_dark`. Omitted palette, metric, and typography fields inherit from that baseline. RGB channels are finite non-negative HDR values; alpha remains from zero to one. Metrics are finite and non-negative, with positive text sizes and container heights. `font` is embedded `Inter` or a name declared in `project.toml`.

The complete palette fields are `canvas`, `region`, `panel`, `raised`, `control`, `overlay`, `border`, `border_strong`, `text`, `text_secondary`, `text_muted`, `accent`, `accent_text`, `accent_soft`, `hover`, `active`, `selection`, `focus`, `warning`, `warning_soft`, `danger`, `danger_soft`, `data_engine`, `data_native`, `data_script`, `axis_x`, `axis_y`, `axis_z`, `axis_w`, `light_overlay`, and `dark_overlay`.

The complete metric fields are `text_size`, `small_text_size`, `control_height`, `row_height`, `title_height`, `radius_small`, `radius`, `radius_large`, `border_width`, `gap_small`, `gap`, `gap_large`, `padding_small`, `padding_control`, and `padding_panel`.

Static glTF model resources point at `.gltf` or `.glb` sources:

```toml
id = "b1000000-0000-4000-8000-000000000003"
type = "scrapbot.model"
name = "Crate"

[model]
source = "assets/models/crate.glb"
generate_lods = true
lod_ratios = [0.5, 0.25, 0.125]
lod_screen_radii = [0.18, 0.07, 0.025]
```

The importer starts at the selected/default glTF scene and includes only reachable nodes, meshes, materials, and images. It supports triangle primitives, positions, optional normals, tangents, and UV0, optional indices, TRS node hierarchies, metallic-roughness material factors, normal and occlusion strengths, emissive factors, `OPAQUE` and alpha-cutout `MASK` materials, `alphaCutoff`, `doubleSided`, and base-color, metallic-roughness, normal, occlusion, and emissive images.

Images may come from GLB buffer views, base64 data URIs, or safe relative files beside the `.gltf`; every image dependency participates in cache invalidation. Missing normals are generated. Imported subresources use semantic keys derived from authored names, hierarchy, and content where necessary, so harmless glTF array reordering preserves generated handles and derived entity UUIDs.

Imported mesh LOD generation is enabled by default with the values shown above. `lod_ratios` gives each alternate level's target index ratio relative to the source. `lod_screen_radii` gives the matching descending projected-radius threshold at which the renderer selects that level. Both arrays must contain the same non-zero number of values, up to three.

The importer uses meshoptimizer with position, normal, and UV evidence, compacts each retained level, and stores measured simplification error in the product. A primitive with fewer than 16 triangles, or one that cannot meet the next useful reduction within its error bound, retains fewer levels. Set `generate_lods = false` to keep only source geometry; ratio and radius arrays are then ignored.

Imported images use complete RGBA8 mip chains. Base color and emissive use sRGB sampling; packed metallic-roughness, normal, and occlusion maps use linear sampling. Every material texture slot preserves its glTF minification, magnification, mip, and U/V wrap settings; omitted samplers use the glTF defaults.

WGPU renders these through its shared GGX material path. Authored tangent vectors and handedness drive imported normal maps; geometry without tangents uses derivative reconstruction. Direct ECS lights, optional imported image-based environment lighting, HDR emission, bloom, exposure, and tone mapping then share the same surface result.

Masked alpha is applied consistently to the color, depth-prepass, and directional-shadow passes. Double-sided materials disable back-face culling and shade back faces with an inverted surface normal.

`BLEND` materials fail import until Scrapbot has sorted transparent rendering. Animation, skins, morph targets, matrix-authored nodes, Draco/required extensions, non-UV0 texture mappings, texture transforms, KTX2/Basis images, and advanced material extensions are not supported yet.

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

The live editor's Resources browser creates, duplicates, renames, moves, and deletes material resources as stopped-mode in-memory authoring transactions. Scene references remain stable because these operations preserve the resource UUID. Delete is unavailable while a live entity references the UUID. Explicit Save derives the required file writes and deletions from the disk baseline, rejects destination conflicts, and commits the complete project file set through the recoverable Save transaction. Geometry LOD and UI-theme resources are text-authored in this slice; the editor lists and inspects themes read-only.

## Scene entities

Entities use repeated `[[entities]]` tables.

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000001"
name = "Main Camera"
```

Every entity must have a unique, non-zero RFC UUID in `id` and a `name`. The ID is stable project identity; the name is an editable display label.

UI entities may resolve a built-in theme name or declared UI-theme UUID through ordered composition recipes:

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000002"
name = "Primary Action"
ui_theme = "reduced_dark"
ui_recipes = ["primary_button"]

[entities.ui_layout]
size = [240, 72]
corner_radius = 24

[entities.ui_button]
text = "BOOST"
```

`ui_theme` and `ui_recipes` must appear together in the entity table. A UUID must resolve to a declared `scrapbot.ui_theme` resource. Recipes create the relevant ordinary `ui_*` component values in array order; component sections then override any field. An entity may compose up to 16 recipes. The supported built-in theme and recipe names are listed in [UI theming](/guides/ui-theming/).

Reusable controls can carry semantic project meaning without changing their visual or interaction components:

```toml
[entities.ui_action]
action = "menu.launch"
payload = "campaign"
```

`action` is required and limited to 64 UTF-8 bytes; `payload` is optional and limited to 256 bytes. The interaction pass inherits the nearest action from the exact control or its UI ancestors and publishes it through the Luau/native immutable event API.

Responsive project UI can define one root canvas:

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000010"
name = "Game UI"

[entities.ui_layout]
size = [1280, 720]
fill_width = true
fill_height = true

[entities.ui_canvas]
reference_size = [1280, 720]
scale_mode = "expand"
horizontal_alignment = "center"
vertical_alignment = "center"
safe_area = [24, 32, 24, 32]
min_scale = 0
max_scale = 0
```

`scale_mode` accepts `fit`, `fill`, `expand`, `stretch`, `pixel_perfect`, or
`none`. Canvas alignment accepts `start`, `center`, or `end`; safe-area order is
top, right, bottom, left. The canvas requires a root `ui_layout`, only one may
exist in the scene origin, and zero scale bounds mean unbounded.

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
debug_view = "lit"
debug_hiz_mip = 0
debug_occlusion_freeze = false
exposure = 1
automatic_exposure = false
automatic_exposure_min = 0.125
automatic_exposure_max = 8
automatic_exposure_speed = 2
temporal_antialiasing = true
fast_antialiasing = false
ambient_occlusion = true
ambient_occlusion_quality = 0.5
screen_space_reflections = false
screen_space_reflections_quality = 0.5
bloom = true
```

A camera reads its world position and Euler orientation from the entity's resolved transform chain. Rotation is expressed in radians: X controls pitch, Y controls yaw, and Z controls roll.

`debug_view = "occlusion_queries"` overlays the exact screen-space rectangles tested by GPU Hi-Z culling. Set `debug_occlusion_freeze = true` to preserve the latest valid query evidence while the view remains selected. These fields use the same public camera payload in scene TOML, Luau, native Odin, and the editor's transient extracted-camera override.

`debug_view = "virtual_geometry"` shows the exact fully resident cluster frontier selected by the GPU. Individual clusters vary in color; the mint-to-pink palette moves from fine source clusters toward coarser hierarchy levels. The view works through native multi-draw or portable GPU-compacted submission. Adapters without indirect-first-instance and capacity-limited layouts display the ordinary whole-primitive fallback instead of claiming virtual-geometry selection occurred.

`exposure` is a positive linear multiplier and defaults to `1`. With automatic exposure disabled, it combines directly with World Environment exposure. With automatic exposure enabled, it becomes compensation around GPU-metered exposure, clamped by `automatic_exposure_min` and `automatic_exposure_max` and approached at `automatic_exposure_speed`.

Automatic metering samples only the active game viewport. It does not include editor chrome and does not read luminance back to the CPU.

TAA, visibility-bitmask ambient occlusion, and bloom default on; fast fullscreen antialiasing and material-aware screen-space reflections default off. Fast AA is used only when TAA is off.

Ambient occlusion models visible depth samples with constant thickness so thin geometry does not permanently close a whole sampling slice. It affects only indirect diffuse lighting and cannot see geometry absent from the current depth buffer. `ambient_occlusion_quality` selects bounded `0.25`, `0.5`, `0.75`, and `1` sampling tiers; the balanced `0.5` default uses 16 samples per half-resolution pixel.

SSR reflects only current-frame, on-screen world surfaces and fades rough, distant, uncertain, and screen-edge hits. `screen_space_reflections_quality` uses the same four authored tiers with 16, 32, 48, and 64 ray-march steps. Lower tiers widen their stride to preserve approximately the same reach with coarser intersection precision. These camera values may be changed live through the generated inspector or Luau query writeback.

World environment:

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000002"
name = "World Environment"

[entities.world_environment]
lighting = "b1000000-0000-4000-8000-000000000004"
lighting_intensity = 1
reflection_intensity = 1
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

A scene may contain at most one World Environment. `lighting` and `background` are optional Environment-resource UUIDs. `lighting_intensity` scales all environment lighting; `reflection_intensity` independently scales its specular part.

An empty visible background reuses the lighting Environment. When both are empty, Scrapbot renders its built-in procedural haze sky. The atmosphere fields tune only that procedural sky and do not alter imported HDR backgrounds.

The analytic sky, ground, haze, and sun model supplies roughness-aware diffuse and specular environment lighting, so metallic materials remain meaningfully lit without an imported HDR probe. Procedural sun elevation drives horizon occlusion and day/twilight/night presentation. Above the horizon, it also contributes the primary derived directional light and shadow direction; explicit ECS lights remain additive.

See the [component reference](/reference/components/#scrapbotworld_environment) for field constraints and change-driven runtime behavior.

Built-in primitive convenience:

```toml
[entities.mesh]
primitive = "cube"
```

The mesh component resolves `cube` or `plane` into built-in geometry and supplies the default material when no authored material is present. The plane is a reusable 64×64 grid suitable for vertex-displaced surfaces. This is the compact primitive path used by generated projects and small text-authored scenes.

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
icon_set = "a11c0000-0000-4000-8000-000000000001"
icon = "magnifying-glass"
icon_position = "leading"
icon_color = [0.65, 0.68, 0.74, 1]
icon_size = 14
icon_gap = 6
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

Positions and sizes are logical pixels from the top-left. `margin` and `padding` use `[top, right, bottom, left]`. Layout `min_size` is a per-axis lower bound. `fill_width` and `fill_height` expand an element to the corresponding available parent axis; `fit_content_width` and `fit_content_height` expand or shrink it around visible children and intrinsic text/button content. Fill and fit can be combined, producing the larger of available space, visible content, and `min_size`. Resolved sizes remain renderer state and do not overwrite the authored `size` value. `border_color` and non-negative `border_width` add an inset signed-distance border that follows `corner_radius`. `hidden = true` removes the box and its descendant subtree from layout, paint, interaction, and parent content measurement without despawning their entities.

Set `popup = true` on a root layout to make it a floating popup. `popup_anchor` identifies the UI element it follows, while a `ui_button.popup` target assigns that button as the anchor and toggles `popup_open`. `popup_gap`, `popup_min_width`, `popup_max_width`, `popup_max_height`, and `popup_viewport_margin` constrain derived placement; all are non-negative, zero maximums are unbounded, and a non-zero maximum width cannot be smaller than the minimum. Shared UI prefers placement below the anchor, flips above when needed, clamps to the viewport, and never overwrites authored geometry. Same-domain outside presses and Escape close an open popup; `popup_close_on_selection = true` also closes it after a descendant-list selection. Popup roots cannot have a parent, and scene UUID references must resolve to valid UI entities.

Add `ui_hstack` or `ui_vstack` with a non-negative `gap` to arrange children in scene order; an element without either stack overlays its children inside the parent's padded content box. Set stack `fill = true` to treat authored child sizes as proportions along the stack axis and fill the available cross-axis. Set a child's layout `fixed_in_fill = true` to preserve its authored main-axis size while flexible siblings divide the remainder. Add `draggable = true` to turn the gaps into pointer-draggable separators; stack `min_size` sets the non-negative minimum pane extent on the stack axis. Draggable separators show the matching horizontal- or vertical-resize system cursor while hovered or dragged. Draggable stacks must also enable fill.

Every HStack and VStack sorts direct children by layout `stack_order`, with stable entity order breaking ties. Set `reorderable = true` to additionally accept title-dragged panels. A direct-child `ui_panel` with `movable = true` uses an unoccupied title-band press as a click-or-drag gesture: release within `drag_threshold` retains collapse behavior, while crossing the threshold starts a workspace drag. Release without a compatible destination cancels. Reorderable stacks accept insertion transfers; draggable dock spaces accept the panel as a tab. Drop indicator color, thickness, and inset are public HDR style fields. Wrapped stacks cannot be reorderable.

For responsive flow, set a child's non-negative `basis`, `grow`, and `shrink`. Zero basis uses its authored or resolved intrinsic main-axis size. Positive space is divided by grow factors; overflow is removed by shrink factors without crossing the child's `min_size`. Set stack `wrap = true` to pack preferred outer sizes into multiple lines, with `gap` between siblings and `line_gap` between lines. Each line distributes its own positive or negative space. Wrapped stacks cannot use legacy proportional fill or draggable separators.

A `ui_text` can set `alignment` to `"left"`, `"center"`, or `"right"` within its padded content box. `wrap = true` breaks text at whitespace to fit that width and falls back to glyph boundaries for a word wider than one line. Explicit newlines always break. `line_height = 0` uses the text size; a positive value supplies an explicit line advance. Wrapped intrinsic height uses the same selected-font metrics and line boundaries as paint.

Backgrounds, borders, corner radii, progress bars, checkbox boxes, and checkbox marks are rendered with signed-distance shapes. Parent UUIDs must resolve to another UI layout entity, cycles are rejected, and one entity cannot combine multiple flow containers (`ui_hstack`, `ui_vstack`, `ui_table`, `ui_list`, or `ui_dock_space`) or more than one of `ui_icon`, `ui_text`, `ui_button`, `ui_input`, `ui_checkbox`, and `ui_color_picker`.

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

Pointer hit testing gives the topmost element under the pointer hover state. Pressing the primary button captures active state on that element until release and advances its public activation revision. Buttons can consume those generic states through `hover_background`, `active_background`, `hover_color`, and `active_color`; a zero-alpha state color falls back to the normal layout background or button text color. Button labels use `alignment = "left"`, `"center"`, or `"right"` inside the padded box and default to centered.

Windowed runs use the system pointer cursor over buttons, selectable list rows, writable checkboxes and color pickers, interactive viewports, and collapsible panel titles. Writable inputs use the text-edit cursor. Draggable numeric inputs switch to the horizontal-resize cursor while scrubbing is armed or active; draggable stack and table separators keep their directional resize cursors.

A standalone `ui_icon` or icon-bearing button references `icon_set` by UUID and `icon` by symbol name. Buttons may place the icon `"leading"` or `"trailing"`, derive its size from the content height or set `icon_size`, and control `icon_gap` plus `icon_inset`. Text remains optional when a complete icon reference is present. Project loading rejects unknown icon-set UUIDs.

Set `font` on `ui_text`, `ui_button`, `ui_input`, `ui_panel`, or `ui_dock_space` to a name declared in `project.toml`; omit it to use Inter. A panel or dock-space selection applies to its title chrome, while child controls select their own fonts independently.

Clicking a `ui_input` focuses it and selects all its text. Focused inputs support typed single-line ASCII text, Left/Right/Home/End movement, Shift selection, Backspace/Delete, Select All, and paint-order Tab/Shift+Tab traversal. Enter submits the current value and removes focus; Escape restores the value present when focus began. The component's `text` field changes during editing, while `ui_state.changed`, `submitted`, and `cancelled` plus their revision counters expose reusable interaction edges.

Set `numeric = true` to give an input a numeric `number`, positive `step`, optional `minimum`/`maximum`, Up/Down stepping, and validation through `ui_state.valid`. Add `draggable = true` to opt a writable numeric input into horizontal pointer scrubbing across the complete control surface. `prefix`, `prefix_width`, `prefix_color`, and `prefix_background` provide a reusable leading badge such as the inspector's X/Y/Z controls, but are not required for scrubbing. Set `read_only = true` to retain focus, selection, and traversal without allowing mutation. Clipboard operations, IME composition, Unicode shaping, and multiline editing are not implemented yet.

Control chrome is authored rather than editor-private. Scroll areas expose scrollbar width, right margin, vertical inset, minimum thumb size, track/thumb colors, and corner radius. Panels expose built-in disclosure icon size, margin, gap, and inset. Inputs expose prefix gap/padding/radius, selection radius, focus and invalid borders, and caret color/width/inset. Checkboxes expose box and check radii, border width, and check inset. Set any corner radius to `0` for square corners; checkbox radii and check inset use `-1` as the automatic size-relative default.

A `ui_checkbox` stores its current boolean in `checked` and toggles on primary-button press. `box_size` controls the square inside the element's layout box; the remaining fields style its unchecked, checked, hover, active, border, and SDF checkmark colors. Set `read_only = true` to display state without accepting pointer changes. A successful toggle advances the element's public `ui_state.change_revision`.

A `ui_scroll_area` clips descendants to its padded content rectangle and scrolls vertically when the pointer wheel is over it. Give its nested pane an explicit size larger than the viewport; that pane may contain overlays or stacks of any size. `scroll_speed` is the target movement per wheel unit and `smoothness` controls frame-time interpolation toward that target. Both must be positive. Nested scroll clips intersect, and only the topmost hovered scroll area consumes a wheel update.

A `ui_list` lays out its direct children as full-width selectable rows in scene order. Clicking a row or any descendant stores the direct row's UUID in the list's ECS-owned `selected` field. `gap` controls spacing; `selection_background`, `hover_background`, and `active_background` style interaction states.

Set `filter_input` to a same-origin `ui_input` UUID to filter rows by an ASCII case-insensitive substring match over descendant text, button, and input content. Tree filters retain matching ancestors and reveal matches below collapsed branches without changing collapse state.

For long uniform lists, set `virtualized = true`, a positive `item_height`, and a non-negative `overscan`. The layout then retains the exact complete scroll extent while materializing only the visible row window plus overscan.

Set `draggable = true` to resolve drag sources and targets to direct children:

- `drag_threshold` controls gesture recognition.
- `drop_edge_fraction` maps a target row's top and bottom zones to `before` and `after`; its middle is `into`.
- `drop_indicator_color`, `drop_indicator_thickness`, and `drop_indicator_inset` style insertion lines.
- `drop_target_background` styles an `into` target.

During a gesture, read-only `ui_state` fields expose `dragging`, `drag_source`, `drop_target`, and `drop_placement`. A completed in-list drop increments `drop_revision` and `change_revision`. An empty target UUID with `into` means the list background.

Set `tree_enabled = true` to interpret direct children whose layouts have `tree_item = true` as a nested tree. `tree_parent` identifies another row UUID, `tree_order` is sibling-local, `tree_collapsed` hides descendants, and `tree_indent` defaults to 14 pixels. An `into` drop reparents; `before` and `after` may reparent and reorder in one operation.

Combine the list with `ui_scroll_area` on the same entity for long lists:

```toml
[[entities]]
id = "d4000000-0000-4000-8000-000000000030"
name = "Entity List"

[entities.ui_layout]
size = [280, 400]

[entities.ui_list]
gap = 2
virtualized = true
item_height = 32
overscan = 2
selection_background = [0.045, 0.095, 0.105, 1]
hover_background = [0.028, 0.038, 0.050, 1]
active_background = [0.040, 0.055, 0.072, 1]

[entities.ui_scroll_area]
scroll_speed = 64
smoothness = 14
```

Each direct child supplies its own row height and may use an overlay or another flow container for its contents. A list cannot share its entity with another flow container.

Panels add a styled title band without choosing how their children flow, so they compose with overlays, stacks, and nested tables.

Set `collapsible = true` to make a titled panel interactive. Its ECS-owned `collapsed` value selects the initial and current state. A collapsed panel contracts to the title height and omits ordinary descendants from layout, paint, focus traversal, and pointer interaction. The disclosure uses `caret-right` or `caret-down` from the ordinary built-in icon set.

Set `movable = true` when the panel is a direct child of a reorderable stack. Title actions remain excluded from the drag handle. Add those actions as ordinary direct child buttons with `panel_action = true`; they may use text or any public icon, activate independently, remain available while collapsed, and lay out from right to left.

Tables place children in row-major order across 1–64 columns. Columns are equal by default. With `proportional_columns = true`, the first row's positive authored cell widths become reusable weights for every row. For example, widths `1` and `2` create a one-third/two-thirds split.

Set `resizable_columns = true` to turn column gaps into draggable separators; this requires proportional columns. `min_column_width` limits adjacent-column shrinking, and resized proportions remain local to the current UI session. Child heights determine row height, `column_gap` and `row_gap` control spacing, and a partial final row starts at the first column.

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

Each child of `Stats Table` occupies the next table cell. Give the first three child layouts the desired width weights; subsequent rows reuse them. A table is a flow container and therefore cannot share an entity with `ui_hstack`, `ui_vstack`, `ui_list`, or `ui_dock_space`; a panel is decoration and may share an entity with any flow container.

A `ui_dock_space` is the flow container for a tab group. Every direct child
carrying `ui_dock_item` contributes its required non-empty `title`. A direct
titled `ui_panel` also contributes its title and `movable` policy; the tab
replaces the panel's internal title band while docked. The dock space's
`active` UUID must be empty or identify one of those direct children. It
reserves `tab_height` above the active item, measures titles with its selected
`font`, clamps them between `tab_min_width` and `tab_max_width`, and uses the
public tab and drop HDR colors for interaction. Inactive items remain authored
but leave layout, paint, focus, and pointer interaction.

`tab_strip_background` paints only the tab rail, which is useful when the
active pane is renderer-backed and must remain unobscured.
`content_background`, `content_corner_radius`, and `content_padding` define one
shared sheet behind the active pane. `tab_connection_height` paints a square
strip across the bottom of the active tab, and `tab_content_overlap` extends it
over that sheet so the two surfaces read as one physical object. Set the
connection height to `0` for detached pills, or combine a positive value with a
transparent `tab_background` and subtle hover background for quiet inactive
labels.

Set an item's `movable = false` to lock it. Set a space's `draggable = false`
to reject transfers. Otherwise, dragging a tab into another dock space changes
the item's ordinary `ui_layout.parent` UUID and activates it in the
destination. A panel tab may instead enter a reorderable stack, and a movable
stack panel may enter a dock space as a new tab. Build resize topology by
placing dock spaces inside the same draggable fill stacks described above; the
docking component does not own a second split tree.

Set `split_horizontal = true` and/or `split_vertical = true` to let an edge
drop build that resize topology interactively. The engine replaces the target
in its current parent with a public fill HStack or VStack, keeps the existing
dock on one side, creates another public dock for the dropped item, and exposes
their separator through normal stack dragging. `split_ratio` defaults to
`0.5`, `split_edge_fraction` to `0.25`, `split_gap` to `4`, and
`split_min_size` to `120`. Directional targets disappear when the available
axis cannot fit two minimum panes plus the gap; a center drop retains ordinary
tab/stack behavior.

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
