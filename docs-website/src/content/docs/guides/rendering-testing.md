---
title: Rendering And Testing
description: Run the null and WebGPU backends, smoke-test projects, and verify generated framegrabs.
---

Scrapbot has two rendering paths today:

- `null`: headless renderer for fast smoke tests.
- `wgpu`: SDL3 plus `wgpu-native` for the complete GPU-driven renderer.

The WGPU backend includes:

- metallic-roughness GGX materials and HDR environment lighting;
- GPU-clustered point lights and four directional-shadow cascades;
- retained instances, compute culling, visibility compaction, LOD selection, and indirect draws;
- TAA, fast AA, visibility-bitmask AO, SSR, bloom, and tone mapping.

## GPU-driven rendering

WGPU retains geometry/material/LOD batches across Transform-only frames. Stable ECS render slots address a backend-owned instance table. Transform changes pack into one dense update stream and one upload before GPU matrix/bounds expansion; static record changes still upload only coalesced dirty ranges. One compute pass produces separate camera-visible and shadow-visible instance lists plus their indirect counts. The renderer supports 131,072 instance slots and grows its draw database geometrically; it uses conservative geometry-derived bounding spheres and one portable indirect call per retained batch.

Pass `--cpu-culling` to run the same bounding-sphere tests, screen-radius LOD selection, and compaction on the CPU while retaining WGPU storage-buffer shaders and indirect draws. This is useful as a correctness oracle and compatibility diagnostic; compute culling remains the default. Hi-Z rejection is GPU-only and therefore disabled on the reference path. The compute path also disables previous-frame Hi-Z rejection whenever the camera or a persistent instance record changes, then rebuilds the pyramid from the current conservative frustum result.

Run `mise test-gpu` for the bounded GPU acceptance gate. It drives a greater-than-64-batch stress scene through compute and CPU visibility. It also verifies adaptive Hi-Z rejection plus asynchronous timestamps and counters.

The comparator permits at most one 8-bit channel step in sixteen channels across a complete frame. This covers harmless backend rounding without accepting a visible mismatch.

The gate pauses the dense Cluster Cathedral inside the editor and requires large near-field bounds to remain visible while Hi-Z rejects eligible hidden instances. A separate authored-resource fixture places one instance in each of three GPU-selected LODs and requires the CPU reference to select and render the same result.

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

The spherical horizon clips the sun and drives the daylight, twilight, and night transition. Above the horizon, the sun becomes the first directional render light and drives direct GGX lighting plus the primary shadow cascades. Explicit ECS lights remain additive.

### Volumetric fog

Add one `scrapbot.volumetric_fog` component to author global height and distance fog. The renderer integrates a fixed six-sample camera ray, stops it at opaque depth or the authored distance bound, and evaluates exponential density around a world-space height plane.

The primary directional light supplies anisotropic in-scattering. Its four cascaded shadows filter that contribution, so sunbeams and occluded haze follow the same shadow geometry as opaque surfaces. Ambient scattering remains available in shadow and at night.

Fog composes before TAA and bloom. Its sample positions are deterministic rather than freshly randomized per frame, avoiding temporal sparkle during slow camera motion. Remove the component or set `density = 0` to make it a no-op. See [`scrapbot.volumetric_fog`](/reference/components/#scrapbotvolumetric_fog) for every field.

This first implementation is one global volume. It does not yet scatter clustered point lights or support local fog shapes.

### Ambient occlusion

Enabled AO reconstructs view-space positions from depth and samples rotated slices around the mapped surface normal at half resolution. Each depth sample marks only its constant-thickness angular interval in a 32-sector visibility bitmask.

Visibility can therefore reopen behind thin geometry instead of one high horizon occluding the rest of a slice. Joint depth/normal filtering prevents the result from crossing incompatible surfaces.

AO attenuates only indirect diffuse light. It does not dirty direct lights, specular lighting, emission, or reflections.

### Reflections, antialiasing, and composite

Enabled SSR marches a reflected view ray through scene depth and samples HDR color only at confirmed on-screen hits. Confidence fades rough, distant, uncertain, and screen-edge hits.

Fog, AO, and SSR join the current HDR signal before temporal resolution. Enabled TAA uses an eight-sample projection-jitter sequence, camera reprojection, previous-depth rejection, and current-neighborhood clamping.

When TAA is off, the renderer removes projection jitter and history traffic. Optional fast AA then uses only the current resolved frame. Resize, world replacement, depth replacement, camera cuts, and TAA mode changes invalidate temporal history.

World-environment and active-camera exposure multiply together. Enabled bloom builds five bright-pass levels before one ACES-style tone-map pass presents through an sRGB target.

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

Use `--ui-script` to reproduce interactions against public project UI or transient editor UI by UUID, entity name, or visible text. The driver resolves the target from the retained tree, reveals it through clipped ancestor scroll areas, and feeds ordinary pointer and keyboard state back through the normal reconciler. `--ui-dump` writes the final tree even when the run fails, including hierarchy, text, control kinds, clipping, raw and visible screen rectangles, paint order, hover/active/focus state, embedded-viewport orbit/distance state, and the pending script action. Structured WGPU results additionally expose `ui_viewport_active_targets`, `ui_viewport_target_pixels`, `ui_viewport_target_resizes`, `ui_viewport_redraws`, and `ui_viewport_cache_hits` for target-pool and cache diagnostics.

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

`tests/fixtures/ui/authoring-history.json` covers the authoring-history boundary: it edits a scene Transform, verifies dirty state across Undo and Redo, uses Revert to reload scene entities without restarting project code, asserts the disk-authored value, and captures the transport controls.

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

- `click`, `hover`, `scroll`, `type`, `drag`, `key`, `wait`, `expect`, and `capture`;
- `scroll` takes `wheel_y`;
- `type` takes `text`;
- `wait` takes a frame count.

A drag starts at the target center. It moves by `delta_x`/`delta_y` or towards a semantic `destination`, then releases.

Use `destination_anchor` with `top`, `center` (the default), or `bottom` to distinguish insertion from an into-row drop. Semantic destinations are preferred for lists and trees because they survive layout changes. Offsets remain useful for sliders and splitters.

A positive drag `frames` value interpolates motion across multiple input frames. Omit it or use zero for a one-frame move.

Key actions cover navigation and editing plus Tab, Enter, Escape, Select All, Save, Undo, Redo, Editor Toggle, Run/Stop, and Pause/Step. Expectations cover `visible`, `hovered`, `active`, `focused`, `text`, and `inside_parent`.

Targets may combine `uuid`, `name`, `text`, and `origin`. Use a zero-based `occurrence` for duplicate matches. Set `part` to `panel_action` to target the first direct child button in a panel title.

A capture target supplies the framegrab region unless `--framegrab-region` is explicit. Without `--frames`, a scripted run gets a 240-frame safety bound and exits when all actions finish.

## Directional shadows

Shadow participation is explicit and independent:

```toml
[entities.shadow_caster]
[entities.shadow_receiver]
```

`shadow_caster` makes an entity contribute to the first directional light's shadow cascades. `shadow_receiver` makes it sample the selected cascade while evaluating directional light. An entity may have either marker, both, or neither. WGPU uses four 2048×2048 layers, practical logarithmic/uniform camera-depth splits out to 80 world units, texel-stabilized light projections, per-cascade GPU caster culling, slope-scaled caster depth bias, cascade-texel-scaled receiver-normal offset, and 3×3 PCF. Point-light shadows, multiple shadowed directional lights, cascade blending, and configurable quality are not yet provided.

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

## Headless WebGPU framegrab

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

WGPU smoke tests are not part of the default suite because they may need platform window-system access.

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
