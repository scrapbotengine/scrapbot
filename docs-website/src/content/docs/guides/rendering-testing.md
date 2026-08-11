---
title: Rendering And Testing
description: Run the null and WebGPU backends, smoke-test projects, and verify generated framegrabs.
---

Scrapbot has two renderer backends today:

- `null`: deterministic simulation/render-extraction smoke tests without a GPU.
- `wgpu`: the complete GPU-driven renderer, using SDL3 only for visible surface runs and a
  surface-free native adapter for offscreen runs.

The WGPU backend includes:

- metallic-roughness GGX materials and HDR environment lighting;
- GPU-clustered point lights and four directional-shadow cascades;
- retained instances, compute culling, visibility compaction, LOD selection, and indirect draws;
- TAA, fast AA, visibility-bitmask AO, SSR, bloom, and tone mapping.

## GPU-driven rendering

WGPU retains geometry/material/LOD batches across Transform-only frames. Stable ECS render slots address a backend-owned instance table. Transform changes pack into one dense update stream and one upload before GPU matrix/bounds expansion; static record changes still upload only coalesced dirty ranges. One compute pass produces separate camera-visible and shadow-visible instance lists plus their indirect counts. The renderer supports 131,072 instance slots and grows its draw database geometrically.

Ordinary Geometry versions occupy aligned ranges in shared WGPU vertex and index arenas. Virtual
Geometry uses self-contained, group-aligned pages containing the referenced vertices and
page-local indices. Streamed resident pages receive ranges in both arenas; absent pages consume no
GPU vertex or index memory. A complete resource that fits the remaining budget retains canonical
vertex/index ranges plus expanded page indices as a faster nonduplicating path. Changed versions
reuse fitting ranges or allocate from coalescing free lists, and backing buffers grow
geometrically.

Every registered Geometry also owns deterministic meshlets capped at 64 vertices and 124 triangles,
including local index streams, conservative sphere bounds, and normal cones. Imported Model
products persist a compact runtime catalog plus their page payloads inside Scrapbot's common
versioned product envelope. Cache-hit loading validates the chunk directory, buffers catalog reads,
skips payload byte ranges, and derives compatibility meshlets from exact hierarchy leaves. Other
Geometry producers build the same data in memory only when the resource is created or replaced.

Imported Geometry does not decode its complete CPU render vertices and source indices during a
cache-hit bootstrap. It retains canonical counts, exact leaf-cluster topology, and a position-only
query proxy for picking and tooling. Registration publishes and releases decoded catalog entries
incrementally. Classic rendering, `--cpu-culling`, resource previews, and adapters
without virtual submission reconstruct a temporary canonical view from leaf-containing product
pages when that Geometry version enters the WGPU cache. The upload consumes and releases the view;
stable frames do not repeat reconstruction or file reads. Procedural/runtime Geometry retains its
canonical arrays because its fallback source exists only in memory.

Imported models compile eligible primitives into up to three deterministic compact LOD Geometry resources before runtime bootstrap. Their semantic handles survive harmless source reordering and reimport. The base resource publishes the same thresholds and alternate handles as procedural LOD resources, so classic GPU and CPU-reference selection have no importer-specific path. When WGPU can submit the base Geometry's continuous virtual hierarchy, that hierarchy performs the detail selection and the renderer omits the redundant discrete LOD batches.

When an adapter exposes indirect-first-instance, WGPU projects each hierarchy group's monotonic
geometric error into pixels. A Geometry's complete page set is admitted immediately when it fits
the remaining project budget. For larger resources, coarsest pages remain pinned; if finer pages
are absent, the GPU draws the nearest resident frontier and requests refinement through
asynchronous visibility feedback. Feedback includes projected-error priority for missing groups
and actual use touches from visible instances. Deterministic hashing spreads resident touches over
16 frames; missing-group requests remain immediate.

The CPU processes the highest-priority groups first. Imported refinement pages are read from exact
Model-product byte ranges on a dedicated I/O worker; rendering continues with the nearest resident
fallback. Completed payloads are admitted and complete groups evicted under
`render.virtual_geometry_budget_mb`, with fixed per-frame byte and group limits. Demand protects a
stronger recent working set, prefetch never displaces demand residency, and each resident child
keeps its direct parent fallback available until the child is released. Residency changes patch
only affected cluster ranges. The budget counts both vertex and index residency.

Admission is capped at four hierarchy groups and 512 KiB per frame. This bounds CPU upload work
during camera motion; excess refinement remains queued while the pinned coarse frontier stays
complete.

On portable compact paths, page vertices and indices must also fit inside the adapter's storage
binding window. Scrapbot defers a refinement that cannot receive legal ranges and keeps its coarse
fallback visible. A large configured payload budget can therefore improve native indexed paths
without allowing portable vertex pulling to address beyond the device limit.

A resident hierarchy does not switch levels at one exact projected-error boundary. Adjacent levels
overlap from 98% through 102% around the active camera target. World, depth, and cascade shadow
passes submit both complete opaque levels and let ordinary depth testing retain the nearest
surface. TAA receives a transition marker so it can reject incompatible history around bounded
depth and silhouette changes.

Residency pressure never changes that target. If requested detail does not fit, Scrapbot keeps the
resident parent drawable and prioritizes or evicts complete groups. Native indexed submission uses
a one-pixel maximum-quality target. Portable compact submission starts at two pixels when virtual
batches are active because its padded vertex-pulling lanes have a different measured cost/quality
crossover. Dynamic resolution first reduces the viewport-local render grid; after reaching its
authored scale floor, the same frame-budget controller may select coarser power-of-two tiers. The
camera's adaptive-quality floor bounds the coarsest permitted tier.

A newly streamed child also does not replace its parent in one frame. It first passes a bounded
demand-aware settling window. After any direct-parent handoff settles, both levels are submitted for
a 16-render-frame admission transition. That temporal progress limits the same complementary
coverage contract. The child becomes the logical refinement only when the handoff completes; nested
admission transitions therefore proceed one hierarchy level at a time.

Native multi-draw adapters retain one indexed-indirect command and exact per-cluster
visible-instance slice, and use that frontier for shadows too. These shared-buffer slices reserve
one element per possible instance; they do not inherit classic batches' 256-byte dynamic-binding
alignment. Other capable adapters append selected `{instance slot, cluster index}` records into a
bounded camera stream. A first GPU pass builds batch-local instance candidates. Parallel camera
and shadow passes then test one hierarchy cluster per invocation, avoiding a serial complete-model
walk for a large single-instance resource. Compatible same-material batches share one record span
and indirect command; the vertex shader pulls cluster indices and attributes directly from the
shared geometry arenas.

Portable shadows use classic indexed submission while the complete resource is resident. Under
actual page pressure, they switch to the same page-local compact representation as the camera, so
evicted canonical geometry is never required. Selection, compaction, cascade visibility, and
command counts remain GPU-produced. Near cascades retain a finer hierarchy frontier; farther
cascades use progressively coarser error thresholds to bound vertex-pulling and raster work.

Small Geometry whose hierarchy cannot simplify retains ordinary meshlets. Those batches require
at least two instances to amortize cluster culling; a single-instance batch keeps one whole-
primitive command. Native multi-draw adapters retain one indexed command per meshlet. Other
indirect-first-instance adapters feed ordinary meshlets through the same candidate and parallel
meshlet stages as virtual Geometry, then vertex-pull at most four triangle-count lanes per
compatible material span.

After whole-object rejection and LOD selection, compute tests camera meshlets against the frustum,
single-sided normal cone, and Hi-Z; shadow lanes test each cascade frustum. World and depth can mix
whole-primitive indirect draws with native cluster multi-draw or portable compact spans. Shadows
mix whole-primitive draws, native cluster multi-draw, compact conventional spans, classic indexed
spans for complete portable virtual resources, and compact page-local spans for streamed virtual
resources.

Arena-global offsets let adjacent same-material LOD commands share one native multi-draw span. On
portable compact paths, compatible material batches share bounded record spans. Meshlets, Meshlet
Visibility, and Occlusion Queries force eligible batches through the detailed native/emulated
meshlet path so diagnostics cover the complete retained cluster layout.

Set `scrapbot.camera.debug_view` to `base_color`, `world_normals`, `roughness`, `metallic`, `depth`, `meshlets`, `lod`, `meshlet_visibility`, `hiz`, `occlusion_queries`, `virtual_geometry`, `distance_field`, or `world_distance_field` to capture the same diagnostics without opening the editor.

`virtual_geometry` colors the GPU-selected resident cluster frontier by cluster identity and
hierarchy depth. Amber marks a branch whose finer group is not completely resident. Cyan marks a
selected page that arrived through future-camera prefetch and has not yet been promoted by sampled
visible use.

Sponza uses the normal renderer budget so it remains a representative quality showcase. The
generated Impossible Archive uses a 64 MiB budget so its showcase preset remains fully resident
while a cinematic camera moves across dense, unique relief geometry and periodically jumps back to
its starting point. Lower that public project setting, or generate the `unhinged` preset, when the
goal is to study streaming pressure instead of presentation quality. Dedicated pressure fixtures
exercise stricter persistent fallback and eviction contracts.
`debug_hiz_mip` selects the retained
pyramid level for `hiz`; `debug_occlusion_freeze` preserves the latest valid query records for
`occlusion_queries`.

The checked-in semantic replays `tests/fixtures/ui/game-debug-meshlets.json`,
`game-debug-lod.json`, `game-debug-visibility.json`, `game-debug-hiz.json`,
`game-debug-occlusion.json`, and `game-debug-virtual-geometry.json` drive the editor selector and
capture only Game. Pair LOD with `tests/fixtures/gpu-lod` for exact CPU/GPU parity. Pair visibility
or Hi-Z with `examples/ecs-showcase`, the meshlet and virtual-geometry views with
`examples/sponza`, and the automated Occlusion Queries gate with `tests/fixtures/gpu-driven` for a
deterministic wall-and-hidden-bounds workload. Use the dense `examples/clustered-lights` cathedral
to explore occlusion queries interactively in a representative scene.

Visibility diagnostics remain GPU-native. The culling pass emits records into an aligned diagnostic range only while a matching view is active, copies its count into an indirect line draw, and publishes `meshlet_debug_records` through the existing asynchronous statistics path. Meshlet Visibility records rejected bounds. Occlusion Queries records the exact query rectangle, selected mip, nearest bound depth, sampled farthest depth, identity, and decision for every tested object or meshlet.

Freeze stops replacing only the diagnostic range and indirect count. It does not pause simulation or reuse stale Hi-Z for real visibility decisions. Leaving the view invalidates the retained evidence. No topology rebuild or synchronous CPU readback is required.

`--cpu-culling`, adapters without indirect-first-instance, non-hierarchical single-instance batches,
and layouts exceeding 1,048,576 cluster-visible entries use whole-primitive indexed-indirect
submission. Complete resources use their canonical or imported-LOD payload. Streamed virtual
Geometry instead uses the indexed compatibility proxy assembled from its pinned coarse pages, so
capacity pressure lowers detail rather than emitting an empty draw.

This is a policy, capability, or memory fallback, not a different project-facing geometry format.
The compact path is what prevents an adapter without native multi-draw from turning fixed cluster
ranges into thousands of CPU-encoded calls.

Pass `--cpu-culling` to run the same bounding-sphere tests, screen-radius LOD selection, and compaction on the CPU while retaining WGPU storage-buffer shaders and indirect draws. This is useful as a correctness oracle and compatibility diagnostic; compute culling remains the default. Hi-Z rejection is GPU-only and therefore disabled on the reference path.

The compute path never applies previous-camera Hi-Z after camera motion. With stable instance data, it renders a complete coarse virtual frontier into transient current-camera depth, builds Hi-Z, and reruns detailed visibility before clearing and writing final depth. Persistent instance changes retain the conservative frustum-only fallback for that frame.

Run `mise test-gpu` for the complete bounded GPU regression suite. It drives a greater-than-64-batch stress scene through compute and CPU visibility. It also verifies adaptive Hi-Z rejection plus asynchronous timestamps and counters.

The same gate opens both distance-field views against imported glTF geometry. The local view proves
lazy product loading and signed-sample packing. The world view requires one retained three-cascade
build, 98,304 derived voxels, seven compute dispatches, no repeated stable-frame rebuild, and a
fixed image contract separating near geometry from empty field space.

Run `mise test-virtual-geometry-gpu` for the dedicated residency-pressure gate. Its scripted camera
traverses distinct procedural 48-page resources under a 64 KiB payload budget and requires
streaming, prefetch promotion, whole-group eviction, fallback residency, bounded feedback, and a
nonblank framegrab.

For streaming, residency, LOD, temporal-history, animation, hot-reload, or camera-motion work, a
single final frame is not sufficient evidence. Capture at least five consecutive frames with
`scrapbot profile --capture-range START:END`, then build a contact sheet and amplified adjacent-frame
difference sheet:

```sh
mise frame-sequence-sheet -- /tmp/profile/frames /tmp/profile/sequence.png
```

Inspect every source frame as well as the sheets. Correlate suspicious transitions with the matching
profile rows and `counter_deltas`; ordinary camera motion can change many pixels, while an isolated
full-screen spike or a fixed-camera topology change is evidence of a temporal rendering defect.

Whole-primitive compute/CPU comparisons permit at most one 8-bit channel step in sixteen channels across a complete frame. This covers harmless backend rounding without accepting a visible mismatch. The LOD fixture instead requires 44 dB PSNR: both paths must choose the same imported object LOD, while the compute path may additionally select its sub-object virtual-geometry frontier.

The gate pauses the dense Cluster Cathedral inside the editor and requires large near-field bounds to remain visible while Hi-Z rejects eligible hidden instances. A separate authored-resource fixture places one instance in each of three GPU-selected LODs and requires the CPU reference to select and render the same result.

For a smaller CI qualification with persistent diagnostics, run:

```sh
mise test-gpu-offscreen -- --out /tmp/scrapbot-gpu-offscreen
```

This surface-free gate renders the minimal, GPU-visibility, CPU-reference, and deterministic PBR
scenes. It checks nonblank output, compute/reference agreement, renderer diagnostics, timestamp
coherence when supported, and the PBR image contract.

The output directory contains:

- `manifest.json`, with host information plus per-case GPU timings and renderer counters;
- one complete Scrapbot JSON envelope and stderr log per case;
- one lossless 1:1 PNG per case.

Artifacts survive failures. CI uploads the complete directory even when a case fails, so inspect
the manifest before rerunning or guessing from the job log. GPU timings are evidence, not portable
pass/fail thresholds.

## Lighting and postprocessing

### Materials and environments

The WGPU path samples base-color and emissive maps as sRGB. Metallic-roughness, normal, occlusion, and imported-environment data remain linear.

Its GGX shader combines material factors, tangent-space normals, direct lights, and environment lighting. Imported glTF geometry keeps authored tangent handedness for stable normal maps across UV seams; geometry without tangents falls back to derivative reconstruction. Imported HDR environments provide diffuse-irradiance and roughness-prefiltered specular cubes. Specular ambient occlusion and normal-map-only horizon occlusion suppress impossible below-surface environment reflections without dimming unperturbed materials. World Environment exposes a second reflection multiplier when specular art direction should differ from diffuse fill.

The procedural atmosphere evaluates equivalent diffuse and roughness-aware specular radiance from its sky, ground, haze, and sun. Metallic materials therefore retain reflected environment color even when no imported probe is selected.

Environment import uses seam-wrapped bilinear panorama lookup and deterministic 256-sample GGX prefiltering. This prevents close glossy surfaces from magnifying blocky integration noise.

### Clustered and directional lighting

Point lights live outside the render uniform. A cluster-centric compute pass assigns the retained light list into a 16×9×24 view-frustum grid.

Every cluster can reference the complete light list, so dense moving lights do not pop through a smaller hidden per-cluster limit. Fragment lookup accounts for the rendered viewport origin and extent, including editor chrome. The pass reruns only when the camera, viewport, point-light payload, or buffer capacity changes.

A scene's World Environment independently selects lighting and its visible background. The procedural sky exposes:

- sky and ground color;
- turbidity, atmosphere thickness, and horizon softness;
- sun direction, color, intensity, size, and glow.

The spherical horizon clips the sun and drives the daylight, twilight, and night transition. Above the horizon, the sun becomes the first directional render light and drives direct GGX lighting plus the primary shadow cascades.

Explicit ECS lights remain additive. Only the first directional render light owns the current shadow cascades and directional volumetric scattering. Later directional lights are unshadowed surface contributions.

Use either the procedural sun or one authored directional light when a scene needs a single coherent sun.

### Volumetric fog

Add one `scrapbot.volumetric_fog` component to author global height and distance fog. A scalable compute pass integrates 16–64 samples along each camera ray, stops at opaque depth or the authored distance bound, and evaluates exponential density around a world-space height plane. `resolution_scale` sizes that target from `0.25` to `1` of the camera render grid and defaults to `0.25`.

The primary directional light supplies anisotropic in-scattering. Its four cascaded shadows filter that contribution, so sunbeams and occluded haze follow the same shadow geometry as opaque surfaces. Ambient scattering remains available in shadow and at night.

`point_light_intensity` independently opts clustered point lights into the medium. Every ray step reuses its complete GPU-built view-frustum cluster; Scrapbot does not build or upload another fog-only light list.

Fog resolves a dedicated scattering/transmittance history before reconstruction, TAA, and bloom. An integer-scrambled sequence decorrelates ray samples across fog texels and 256 frames. Surface fog reprojects from finite depth; background fog uses a finite representative point inside the medium.

Previous depth rejects disocclusions. Current scattering bounds stale radiance, while camera motion and lighting change reduce history weight. This converges low-resolution variance without leaving a sampling lattice or dragging old shadow shafts through the sky. With unavailable, disabled, or newly enabled history, the ray march uses a stable midpoint.

Remove the component or set `density = 0` to skip the fog dispatch. See [`scrapbot.volumetric_fog`](/reference/components/#scrapbotvolumetric_fog) for every field.

This implementation remains one global volume. It does not yet support local fog shapes or an authored ray-sample count.

### Ambient occlusion

Enabled AO reconstructs view-space positions from depth and samples rotated slices around the mapped surface normal at the target selected by `ambient_occlusion_resolution_scale`. Each depth sample marks only its constant-thickness angular interval in a 32-sector visibility bitmask.

Visibility can therefore reopen behind thin geometry instead of one high horizon occluding the rest of a slice. Joint depth/normal filtering prevents the result from crossing incompatible surfaces.

AO attenuates only indirect diffuse light. It does not dirty direct lights, specular lighting, emission, or reflections.

### Reflections, antialiasing, and composite

Enabled SSR marches a reflected view ray through scene depth and samples HDR color only at confirmed on-screen hits. Confidence fades rough, distant, uncertain, and screen-edge hits.

Resolved fog, AO, and SSR join the current HDR signal before surface temporal resolution. Enabled TAA uses an eight-sample projection-jitter sequence bounded to a quarter pixel. Scene-color history lives on a stable output grid and is camera-reprojected with the sample offset removed. A local depth match and YCoCg variance clipping reject invalid surface history without making a motionless view follow the jitter pattern.

TAA alternates two retained HDR color/depth pairs between current output and previous history. This avoids copying full-resolution history every frame. When TAA is off, the renderer removes projection jitter and history sampling. Optional fast AA then uses only the current resolved frame. Resize, world replacement, depth replacement, camera cuts, and TAA mode changes invalidate temporal history.

### World resolution scale

Set `scrapbot.camera.resolution_scale` from `0.5` to `1` to trade world sharpness for GPU pixel cost. The world, depth, Hi-Z, and post chain use the scaled grid. Final composition upscales into the native output before project UI, gizmos, and editor chrome render at native resolution.

The default is `1`. Start with `0.75` for a heavy scene on a HiDPI display, then profile and inspect the result. A scale change replaces size-dependent targets and rejects temporal history once; an unchanged scale performs no target allocation work.

The primary directional light uses four stabilized shadow cascades. Opaque receivers resolve each cascade with a wider tent-weighted filter and blend across cascade boundaries; volumetric fog uses a cheaper filtered lookup at every ray-march step.

World-environment and active-camera exposure multiply together. A camera may instead enable automatic exposure: one GPU workgroup meters 256 viewport-stratified log-luminance samples, clamps the target, and exponentially adapts a persistent GPU scalar. There is no CPU readback or synchronization point. The manual camera exposure becomes compensation, and both bloom extraction and final composition consume the same adapted scalar.

Enabled bloom builds five bright-pass levels before one ACES-style tone-map pass presents through an sRGB target. A fixed screen-space sub-LSB dither breaks up 8-bit bands in smooth sky and fog gradients without introducing a temporally changing pattern.

Optional scene-owned `scrapbot.lens_flare` and `scrapbot.lens_dirt` components consume that bloom energy inside the same final composite. Flares add a bounded chromatic ghost train and halo; procedural dirt modulates only bloom and flare light. `scrapbot.vignette` then frames the tone-mapped image independently. Removing any component disables only that effect, while disabling camera bloom suppresses both optical effects. See the [component reference](/reference/components/#scrapbotlens_flare) for every field.

Disabled AO, SSR, and bloom skip their compute dispatches. Project UI, gizmos, and editor chrome render afterward, so world postprocessing never softens text or controls.

### Screen-space limits

AO and SSR cannot recover off-screen or occluded geometry. AO thickness is necessarily approximate because a single depth layer cannot reveal a surface's true back face. Animated objects rely on temporal rejection and clamping until per-object motion vectors land.

Reflection probes and off-screen or hierarchical tracing remain future work.

Use an emissive material when a visible surface should glow independently of lighting:

```luau
local neon = scrapbot.material.emissive("neon", 0.1, 0.5, 1.0, 8.0)
```

The non-negative RGB values define hue and `intensity` scales the emitted linear radiance. HDR values are intentionally not clamped to display white.

Use `examples/pbr-materials` as the small, deterministic authored-material reference. Its upper row is dielectric, its lower row is metallic, and roughness increases from left to right. The scene intentionally disables ambient occlusion, reflections, bloom, and external assets so changes to direct GGX material behavior are easy to isolate:

```sh
scrapbot run examples/pbr-materials
```

`mise test-gpu` captures this scene at 1280×720 and checks broad luminance, contrast, and chroma contracts over named material regions. The contract intentionally allows small cross-GPU differences while catching broken tone mapping, lost rough-metal energy, and reversed roughness response. See `tests/fixtures/visual/pbr-materials.json`.

Screen-space ECS UI reconciles after engine/project systems and paints after world geometry. Visible windows feed platform pointer and keyboard state into retained interaction.

Headless runs normally have no interaction. A semantic UI script can drive the same controls deterministically without OS automation.

`examples/ui-showcase` exercises layout, panels, tables, lists, progress, scrolling, SDF styling, inputs, buttons, checkboxes, and the embedded Inter MTSDF atlas. See [ECS UI](/guides/ecs-ui/) for the shared project/editor contract.

With `--editor`, WGPU fills the central project viewport and derives camera aspect from that live rectangle. Project UI uses one uniform canvas scale, viewport translation, and clipping. Pointer input and semantic diagnostics invert the same transform; the canvas never stretches independently on each axis.

Editor-origin ECS UI paints in a separate full-window domain. Visible windows use native pixel density with logical editor dimensions to keep text crisp.

The editor scene camera clones the initial project view and supports right-mouse-captured WASD, Space, and Ctrl fly navigation. Use `examples/ecs-showcase` to verify live geometry and `examples/ui-showcase` to verify project UI scaling:

```sh
bin/scrapbot run examples/ecs-showcase --backend wgpu --editor --headless --frames 20 --framegrab /tmp/scrapbot-editor.png
```

Use `examples/clustered-lights` as the interactive clustered-lighting showcase. It distributes 320 animated HDR point lights through a long architectural tunnel, crossing the renderer's initial 256-light GPU capacity, with shared emissive marker batches and locally illuminated surfaces that make cluster boundaries and light range visually meaningful:

```sh
mise scrapbot -- run examples/clustered-lights --editor
```

Use `examples/sponza` for the heavyweight real-world importer and architectural-rendering workload. `mise setup-assets` installs the pinned Khronos model plus Poly Haven's CC0 Kloppenheim 01 Pure Sky HDRI into ignored development state. The neutral outdoor probe avoids reflecting studio walls and softboxes across Sponza's glossy materials:

```sh
mise setup-assets
mise scrapbot -- run examples/sponza --editor
```

Use `examples/impossible-archive` to inspect virtual geometry across a dense generated scene. Its
deterministic generator writes an ordinary GLB; the project then exercises
the public model importer, ECS scene components, Luau camera mutation, and standard renderer
configuration without an example-specific backend path:

```sh
mise archive-assets --preset showcase
mise scrapbot -- run examples/impossible-archive --editor
```

Choose **Virtual Geometry** in the Game debug-view selector to inspect the resident cluster
frontier. Use `mise archive-profile` for a bounded 1600×900 profile of the showcase preset.

Use `examples/virtual-wilds` when virtual geometry needs real photogrammetry rather than generated
geometry. It imports twelve pinned CC0 Poly Haven models containing 3.54 million source triangles,
generates their LOD and cluster hierarchies, and flies along a coastal route while 9,112 imported
pages compete for a 192 MiB residency budget:

```sh
mise setup-assets
mise scrapbot -- run examples/virtual-wilds --editor
```

The example is an ordinary project. Its glTF resources, scene components, Luau camera system, and
render settings use the same public paths available to games.

A deterministic Luau scatter system adds 220 procedural rocks through public Geometry, Material,
ECS spawn, and Transform APIs. Authored shared-model foliage and landscape instances bring the scene
to 1,425 renderables while continuous virtual geometry submits 26 retained material batches.

`mise test-virtual-wilds` rebuilds and validates the pinned import products.
`mise test-virtual-wilds-gpu` profiles deterministic fixed-camera coverage and moving-camera
refinement segments, preserves consecutive PNGs, and rejects feedback overflow, page-read failure,
or an unbounded GPU workload. Import-level tests separately prove that every hierarchy region owns a
resident terminal fallback and that source boundary loops survive into that fallback frontier.

The GPU virtual-geometry pressure test also captures an active refinement. Its sequence gate
requires at least one transitioning group, visible clusters using blended coverage, and a settled
endpoint, preserving the complete handoff for inspection:

```sh
node tools/test_render_sequence.mjs \
  --project tests/fixtures/gpu-virtual-geometry-pressure \
  --warmup 0 --frames 80 --capture-range 36:52 \
  --resolution 960x540 --require-transition \
  --out /tmp/scrapbot-virtual-geometry-transition
```

Projects can use the same reusable sequence gate directly:

```sh
node tools/test_render_sequence.mjs --project examples/virtual-wilds \
  --warmup 120 --frames 120 --capture-range 56:63 \
  --stable-frontier --out /tmp/virtual-wilds-sequence
```

`examples/virtual-geometry-cliff` removes Wilds' water, foliage, scatter, scripts,
post-processing, and competing geometry while preserving one real Coastal Cliff 04 instance at the
captured near-cliff transform and camera pose. Its 32 MiB budget cannot retain the complete
3,996-page product, so the renderer must preserve a complete coarse fallback while streaming
detail:

```sh
mise setup-assets
mise test-virtual-geometry-cliff
mise scrapbot run examples/virtual-geometry-cliff --live-debug
```

Use this project to reproduce imported hierarchy or residency defects before returning to the
integrated Wilds workload. Approaching, crossing, or orbiting the cliff may change geometric detail;
it must not expose the background through missing clusters.

`examples/virtual-geometry-lab` isolates near-camera hierarchy coverage from imported assets,
streaming-world composition, and postprocessing. Its roughly 197,000-triangle warped wall uses a
strongly nonuniform world transform and fills the viewport while a deterministic camera moves
toward it. A deliberately small residency budget keeps most hierarchy pages nonresident and forces
deferred admission under pressure.

The dedicated gate renders each captured frame through both GPU virtual geometry and full-index CPU
submission. It rejects per-frame image mismatches, unhealthy residency, missing pressure, and any
candidate, camera, or shadow visibility record overflow:

```sh
mise test-virtual-geometry-coverage-gpu
```

Projects can opt into the same reference comparison with `--cpu-reference`. Use
`--minimum-psnr <dB>` to select the tolerated image difference; exact matches are accepted without
special casing. Add `--require-residency-pressure` when the project must prove that its bounded
working set reaches at least 90% of budget, leaves pages nonresident, and exercises eviction or
deferred admission.

`--stable-frontier` rejects active admission transitions as well as uploads, evictions, policy changes,
feedback overflow, and page-read failures. Use `--require-transition` on a transition-focused
capture; it requires an active handoff, a visible blended cluster somewhere in the range, and a
zero-transition final frame. Use `--require-transition-activity` for a streaming-world capture that
must exercise healthy blended handoffs but is not expected to settle the entire visible working set.

Add `--golden-dir <directory> --minimum-psnr <dB>` for platform-qualified golden images. Prefer a
tolerant PSNR baseline per adapter family over byte equality across different GPU implementations.

```sh
scrapbot run examples/ui-showcase --backend wgpu --headless --frames 2 --framegrab /tmp/scrapbot-ui.png
```

Keep the full 1280×720 frame when overall composition matters. For a pixel-level question, export a 1:1 region instead of rescaling the frame:

```sh
scrapbot run examples/ui-showcase --backend wgpu --headless --frames 2 \
  --framegrab /tmp/scrapbot-ui-panel.png \
  --framegrab-region 40,40,560,600
```

Region coordinates are `x,y,width,height` from the top-left of the complete frame. The output PNG contains exactly those source pixels and is not resized.

## Semantic UI diagnostics

Use `--ui-script` to reproduce interactions against public project UI or transient editor UI by UUID, entity name, or visible text. The driver resolves the target from the retained tree, reveals it through clipped ancestor scroll areas, and feeds ordinary pointer and keyboard state back through the normal reconciler. `--ui-dump` writes the final tree even when the run fails, including hierarchy, text, control kinds, clipping, raw and visible screen rectangles, scroll offset/extent, paint order, hover/active/focus state, embedded-viewport orbit/distance state, and the pending script action. Structured WGPU results additionally expose `ui_viewport_active_targets`, `ui_viewport_target_pixels`, `ui_viewport_target_resizes`, `ui_viewport_redraws`, and `ui_viewport_cache_hits` for target-pool and cache diagnostics.

## Engine failure reports

Scrapbot's development and optimized CLI builds retain native debug symbols. An engine panic, failed internal invariant, or unexpected renderer task failure prints its exact detection site and a best-effort bounded platform stack. Panics and fatal invariants trap; task failures still return through the ordinary CLI error path. The `bin/scrapbot-dev` build also maintains an instrumented Odin call stack, so these engine failures include a reliable source-level backtrace even on platforms where native unwinding cannot cross optimized Odin frames.

Use `mise build-dev`, then reproduce the failure with `bin/scrapbot-dev ...` when a complete engine call chain matters. Expected project, asset, command-line, and unsupported renderer-capability failures remain ordinary text or `--json` diagnostics; they do not emit a misleading crash trace.

The checked-in component-picker scenario exercises live and stopped component addition, removes components through a reusable icon button placed in the panel title, verifies Stop-time disposal, and requests a tight action crop:

```sh
bin/scrapbot run examples/ecs-showcase \
  --backend wgpu \
  --editor \
  --headless \
  --ui-script tests/fixtures/ui/component-picker.json \
  --ui-dump /tmp/component-picker-tree.json \
  --framegrab /tmp/component-picker.png \
  --json
```

`tests/fixtures/ui/playback-authoring.json` covers the editor transport boundary: it stops initial playback, creates an unsaved authored entity, plays, stops again, and asserts that the entity survives restoration.

`tests/fixtures/ui/entity-actions.json` selects an authored entity during playback, duplicates it through the semantic keyboard command, verifies that the disposable copy is visible, deletes it through the matching command, and captures the icon toolbar. The focused unit contract separately proves that duplication moves editor selection to the copy and that playback actions do not enter authoring history.

`tests/fixtures/ui/virtual-geometry-duplicate-resume.json` selects a streamed Model root, pauses playback, duplicates the selected copy repeatedly, resumes, and retains twelve subsequent frames. It guards the boundary where editor selection feedback must reuse virtual Geometry's pinned proxy instead of creating a conventional cache that consumes its bounded storage-address window.

`tests/fixtures/ui/authoring-history.json` covers the authoring-history boundary: it edits a scene Transform, verifies dirty state across Undo and Redo, uses Revert to reload scene entities without restarting project code, asserts the disk-authored value, and captures the transport controls.

`tests/fixtures/ui/gizmo-center-pivot.json` selects a renderable entity, activates the transient Center manipulation pivot through the public ECS toolbar, and captures its selected visual state.

`tests/fixtures/ui/infinite-grid.json` fixes the editor camera, lets the procedural ground grid settle through the world/post chain, and captures the complete Game viewport so depth intersection, axis color, line scale, and distance fade remain visually reviewable.

Scripts use schema version 1 and execute actions sequentially:

```json
{
  "schema_version": 1,
  "timeout_frames": 120,
  "actions": [
    {"action": "click", "target": {"text": "Add Component", "origin": "editor"}},
    {"action": "hover", "target": {"text": "camera", "origin": "editor"}},
    {"action": "expect", "target": {"text": "camera"}, "expect": "hovered"},
    {"action": "capture", "target": {"text": "CAMERA", "part": "panel_action"}, "padding": 8}
  ]
}
```

Available actions are:

- `click`, `hover`, `scroll`, `type`, `drag`, `key`, `wait`, `expect`, `capture`, and `set_editor_camera`;
- `scroll` takes `wheel_y`;
- `type` takes `text`;
- `wait` takes a frame count.

`set_editor_camera` takes `position` and `rotation` Vec3 objects. It requires `--editor` and sets the transient fly camera without moving or replacing the project's camera entity. Use it before a multi-frame wait or profile capture to reproduce viewpoint-dependent rendering behavior while project simulation continues independently.

A drag starts at the target center. It moves by `delta_x`/`delta_y` or towards a semantic `destination`, then releases.

Use `destination_anchor` with `left`, `top`, `center` (the default), `bottom`, or `right` to distinguish insertion and dock-split edges from an into-row or center drop. Semantic destinations are preferred for lists, trees, and dock spaces because they survive layout changes. Offsets remain useful for sliders and splitters.

A positive drag `frames` value interpolates motion across multiple input frames. Omit it or use zero for a one-frame move.

Key actions cover navigation and editing plus Tab, Enter, Escape, Select All, Save, Undo, Redo, Editor Toggle, Run/Stop, and Pause/Step. Expectations cover `visible`, `hovered`, `active`, `focused`, `text`, and `inside_parent`.

Targets may combine `uuid`, `name`, `text`, and `origin`. Use a zero-based `occurrence` for duplicate matches. Set `part` to `panel_action` to target the first direct child button in a panel title, or target a dock-item entity with `part: "dock_tab"` to click, drag, or capture its derived tab chrome.

A capture target supplies the framegrab region unless `--framegrab-region` is explicit. Without `--frames`, a scripted run gets a 240-frame safety bound and exits when all actions finish.

## Directional shadows

Shadow participation is explicit and independent:

```toml
[entities.shadow_caster]
[entities.shadow_receiver]
```

`shadow_caster` makes an entity contribute to the first directional light's shadow cascades. `shadow_receiver` makes it sample the selected cascade while evaluating directional light. An entity may have either marker, both, or neither.

WGPU retains four 2048×2048 layers. With dynamic resolution enabled, the frame-budget controller can rasterize a quantized 2048, 1024, or 512 square region without reallocating that texture or rebuilding bindings.

The active size also controls cascade stabilization, bias, filtering, and virtual-geometry detail selection. A lower-resolution shadow pass therefore avoids processing geometric detail it cannot represent. The editor's Performance panel reports the active `SHADOW MAP` size.

The cascades use practical logarithmic/uniform camera-depth splits out to 80 world units, texel-stabilized light projections, per-cascade GPU caster culling, slope-scaled caster depth bias, cascade-texel-scaled receiver-normal offset, and a tent-weighted nine-comparison PCF kernel. The final 10% of each slice blends into its successor. The final slice fades to unshadowed beyond the shadow distance.

The near cascade refreshes every frame. Farther cascades retain their stabilized projection and depth between staggered 2/4/8-frame refreshes, so ordinary frames update at most one far layer alongside the near layer. Scene or Transform changes, camera cuts, light activation, and shadow-resolution changes refresh all four layers immediately.

Point-light shadows, multiple shadowed directional lights, and authored shadow-quality bounds are not yet provided.

## Null renderer

The null backend is the deterministic automation path and does not open a window:

```sh
mise scrapbot -- run examples/minimal --backend null --headless --no-hot-reload --frames 1
```

It reports frame counts for entities, cameras, geometry references, renderables, and draw batches.

## Windowed WebGPU

```sh
bin/scrapbot run examples/minimal --backend wgpu --window --frames 3
```

Visible WGPU windows keep stepping and presenting while the platform window is being resized. Each live-resize expose reuses the normal frame path, so the surface, camera aspect, project viewport, and editor layout follow the currently available pixel area during the drag.

Use `--frames` for automated smoke checks so the command returns.

## Render profiling

Use `scrapbot profile` for repeatable renderer CPU/GPU evidence:

```sh
bin/scrapbot profile examples/sponza \
  --warmup 60 \
  --frames 240 \
  --resolution 1920x1080 \
  --capture-range 100:104 \
  --out /tmp/scrapbot-sponza-profile \
  --json
```

The measurement pass runs headless with hot reload disabled and a fixed simulation delta. Warmup frames execute but do not enter the report.

The output directory contains:

- `profile.json` with raw frame rows and median, p95, and maximum summaries.
- `overview.png` from the final measured frame.
- An optional `frames/` sequence for the inclusive range passed to `--capture-range`.

Each row includes active CPU time, exact per-pass GPU time, their summed GPU frame duration, logical and physical dimensions, pixel density, viewport, shaded pixels, and a raw renderer snapshot. The snapshot includes effective `render_scale`, `shadow_resolution`, `virtual_geometry_error_pixels`, `adaptive_post_quality`, whether adaptation is active, and its filtered scalable-GPU signal.

The `workload` object records the dispatch size, render extent, encoded draw-submission spans,
instances, or sample count behind each pass. Shadow workload dimensions report the active raster
resolution rather than retained capacity. The raw renderer snapshot's
`shadow_cascade_render_mask` and the `shadow_cascade_0` through `shadow_cascade_3` workload entries
report exactly which retained layers rendered and how many clusters they processed. A zero timing
on a skipped far cascade means its prior depth layer was retained; it does not mean shadows were
unsupported. Spectral-surface workload reports its fixed field dimensions,
both inverse-FFT axes, and spatial finalization pass for every active Shader resource.

This makes a timing actionable. It distinguishes an expensive shader at a modest resolution from
expected cost at a HiDPI physical resolution.

`counter_deltas` turns cumulative upload, rebuild, dispatch, resize, redraw, cache-hit, geometry-
arena mutation, and virtual page/group totals into the work attributable to that frame. Stable
measured rows should report zero geometry arena uploads, growths, page/group uploads, drawable
group activations, evictions, and deferred admissions. Virtual-geometry metadata upload count and
bytes expose the queue writes used to patch changed cluster records, indirect templates, and debug
identities; they remain zero when residency and activation are stable.

GPU timestamps arrive asynchronously. Scrapbot tags every readback with its originating frame and merges it into that exact row. Check `gpu_timing_valid` before using a row.

### Dynamic resolution

Set the policy on the active `scrapbot.camera`:

```toml
[entities.camera]
resolution_scale = 1
dynamic_resolution = true
dynamic_resolution_min_scale = 0.6
dynamic_resolution_target_ms = 16.667
adaptive_quality_minimum = 0.25
```

The manual scale is the ceiling, not a second multiplier. WGPU processes every completed scene-span timestamp sample once, filters the result, and advances at most one step on a shared quality ladder. Delayed samples from an old quality generation or active project camera are discarded.

The ladder coordinates 5% world-resolution steps, 2048²/1024²/512² directional-shadow tiers,
virtual-geometry projected-error tiers, and a normalized post factor. Native indexed virtual
submission starts at one pixel; portable compact virtual submission starts at two pixels. The post
factor scales the authored AO and SSR quality ceilings and volumetric-fog ray count.
`adaptive_quality_minimum` bounds the last outputs. Quality returns in the exact reverse order only
after sustained headroom, preventing adjacent tiers from fighting each other.

Every step shares one cooldown and measurement generation. Scale changes reject temporal history and resize only scale-dependent targets; shadow and post-only changes retain those targets. Backends without timestamps stay at authored maxima.

Use a long enough warmup when profiling adaptive policy. The measured rows should represent its settled scale rather than startup convergence. For fixed-scale feature comparisons, disable dynamic resolution.

Image capture uses a fresh second replay. Before applying its bounded map-request timeout, capture
drains the submitted GPU queue so a deliberately unpaced heavy replay is not mistaken for a failed
readback. PNG mapping can stall the pipeline, so capture time never enters the telemetry report.
Keep the range narrow and use `--framegrab-region` when only one area matters.

For valid before/after comparisons, hold these constant:

- executable and project state;
- machine and GPU adapter;
- resolution and crop;
- culling mode and editor visibility;
- warmup, measured frames, and semantic UI script.

`cpu_active_ms` measures active engine work, not presentation idle or observed window FPS. Profile results are same-machine evidence, not portable hardware scores.

Summarize a report or compare compatible before/after bundles:

```sh
mise profile-analyze -- /tmp/before/profile.json
mise profile-analyze -- /tmp/before/profile.json /tmp/after/profile.json
```

The analyzer prints the representative workload next to each timed pass. The comparator checks the backend, adapter, physical dimensions, density, viewport, and shaded pixels before calculating pass and counter deltas. Exit status `2` means the inputs are not comparable.

To identify fixed overhead versus pixel-scaled work, run the same project at a bounded resolution matrix:

```sh
mise profile-sweep -- examples/sponza \
  --binary bin/scrapbot \
  --warmup 60 \
  --frames 240 \
  --out /tmp/sponza-resolution-sweep
```

The default matrix is 960×540, 1280×720, and 1920×1080. Repeat `--resolution WIDTHxHEIGHT` for an explicit matrix. The driver preserves each complete profile bundle and writes machine-readable `sweep.json`.

To estimate which authored effects dominate one workload, run paired feature ablation:

```sh
mise profile-features -- examples/sponza \
  --feature ambient-occlusion \
  --feature screen-space-reflections \
  --resolution 1920x1080 \
  --out /tmp/sponza-feature-sweep
```

For every selected feature, the driver records a fresh reference immediately before profiling the same scene with only that feature disabled. This limits warmup, scheduler, and thermal drift that can invalidate one shared baseline across a long sweep. The overrides exist only in the bounded profile run; they do not mutate the scene or camera. The resulting `feature-sweep.json` keeps both report paths and the estimated p95 GPU cost.

### Historical benchmark bundles

Build the representative benchmark matrix locally with:

```sh
mise setup-assets
mise gpu-benchmarks -- --out /tmp/scrapbot-gpu-benchmarks
```

The bundle contains `minimal`, `ecs-showcase`, and `sponza` sweeps at 540p, 720p, and 1080p,
plus a top-level manifest and Markdown summary. Use `--without-sponza` for a bounded run that
does not require the external Sponza fixture.

Compare two bundles with:

```sh
mise gpu-benchmark-compare -- \
  /tmp/baseline \
  /tmp/candidate \
  /tmp/comparison
```

The comparator reuses the render profiler's compatibility contract. It reports timing deltas only
when backend, adapter, timestamp support, culling mode, physical dimensions, density, viewport,
and shaded pixels match. Incompatible points remain visible as incompatible evidence.

The scheduled/manual `GPU Benchmarks` GitHub Actions workflow runs this matrix on its pinned Metal
runner. It downloads the previous successful artifact of the same architecture, writes the
comparison into the job summary, and retains the complete current bundle for 90 days.

Do not treat this history as a cross-machine leaderboard or a hard portable gate. Use it to spot a
trend, then reproduce that trend with controlled before/after profiles on the same machine.

## Headless WebGPU framegrab

A bounded offscreen GPU run needs neither a window nor a capture:

```sh
bin/scrapbot run examples/minimal \
  --backend wgpu \
  --headless \
  --frames 120 \
  --json
```

This creates no SDL window or presentation surface and allocates no pixel-readback buffer.
The host must still expose a compatible native GPU adapter.

Add `--framegrab` when pixels are part of the verification:

```sh
bin/scrapbot run examples/minimal \
  --backend wgpu \
  --headless \
  --frames 120 \
  --framegrab /tmp/scrapbot-framegrab.png
```

Verify the artifact:

```sh
file /tmp/scrapbot-framegrab.png
xxd -l 16 /tmp/scrapbot-framegrab.png
```

Expected basics:

- PNG image data, 1280 x 720, RGBA for a full frame, or the requested region dimensions.
- Signature starts with `8950 4e47 0d0a 1a0a`.
- Visual output shows shaded fountain cubes and the generated ground plane under ambient and directional light.
- Caster geometry projects directional shadows onto the receiver ground plane.

## Full local verification

```sh
mise test
git diff --check
```

`mise test` builds Luau, builds the Scrapbot CLI, checks the engine package, runs all Odin package tests, checks the CLI version, validates the examples, runs null-renderer smoke tests, and applies a 2,000-frame lifecycle CPU/RAM growth gate.

The normal Odin suite includes persistence torture harnesses:

- The scene harness drives seeded edits through 512 entities. It checks dirty-UUID scaling, formatting preservation, byte-identical repeated saves, runtime-entity exclusion, component round trips, injected failures, and Save/Undo/Redo/Revert boundaries.
- The project transaction harness injects failures at every staging, backup, installation, and commit-marker phase. It simulates crashes around the commit boundary and verifies rollback or forward recovery.
- Resource lifecycle tests cover create, move, delete, UUID-preserving structural Undo/Redo, reference-aware deletion, and nested discovery.

These are structural and golden-text assertions, not machine-dependent timing thresholds.

WGPU smoke tests are not part of the default suite because many ordinary CI workers and managed
sandboxes expose no native graphics adapter. Offscreen runs do not require a window system, but
they still require Metal, Vulkan, or D3D12 device access.

## Runtime growth checks

The default Odin tests track unfreed allocations and include a deterministic 1,000-cycle entity/component churn test. For a complete bounded project run, request structured runtime statistics:

```sh
bin/scrapbot run examples/ecs-showcase \
  --backend null \
  --frames 10000 \
  --runtime-stats \
  --json
```

Runtime statistics compare an early steady-state sample with the final sample window. They include engine-frame nanoseconds through render-list preparation, allocations routed through Odin's engine allocator, post-teardown retained bytes, and detailed ECS storage slot counts. Windowed collection requires a nonzero `--frames` limit. The report does not include direct allocations by Luau, SDL, WGPU, GPU drivers, or the operating system.

Run the calibrated lifecycle soak with:

```sh
mise test-soak
```

The extended soak runs `examples/ecs-showcase` for 10,000 fixed-step null frames. It fails if allocated ECS storage grows between early, late, and final checkpoints; engine-allocator growth or post-teardown retention exceeds 64 KiB; or late engine-frame cost exceeds 1.5 times the early cost. Live entity count may fluctuate without changing allocated storage. Override its controls with `SCRAPBOT_SOAK_FRAMES`, `SCRAPBOT_SOAK_MAX_ALLOCATOR_GROWTH`, `SCRAPBOT_SOAK_MAX_FINAL_ALLOCATOR_BYTES`, and `SCRAPBOT_SOAK_MAX_CPU_GROWTH`.

On Linux, `mise test-sanitize` runs the Odin package tests under AddressSanitizer, and Linux CI runs it after the default suite. The current Odin and Apple sanitizer runtimes are incompatible, so this task is explicitly skipped on macOS; normal Odin allocation tracking and the soak remain available there.
