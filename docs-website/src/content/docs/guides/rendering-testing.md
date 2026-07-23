---
title: Rendering And Testing
description: Run the null and WebGPU backends, smoke-test projects, and verify generated framegrabs.
---

Scrapbot has two rendering paths today:

- `null`: headless renderer for fast smoke tests.
- `wgpu`: SDL3 plus `wgpu-native` for indexed geometry, metallic-roughness GGX materials with base-color, normal, occlusion, and emissive maps, ECS and imported HDR environment lighting, GPU-computed clustered point lights, four-cascade directional shadows, exposure, HDR bloom, tone mapping, persistent GPU instances, compute frustum culling, visibility compaction, and indexed indirect drawing.

WGPU retains geometry/material/LOD batches across Transform-only frames. Stable ECS render slots address a backend-owned instance table. Transform changes pack into one dense update stream and one upload before GPU matrix/bounds expansion; static record changes still upload only coalesced dirty ranges. One compute pass produces separate camera-visible and shadow-visible instance lists plus their indirect counts. The renderer supports 131,072 instance slots and grows its draw database geometrically; it uses conservative geometry-derived bounding spheres and one portable indirect call per retained batch.

Pass `--cpu-culling` to run the same bounding-sphere tests, screen-radius LOD selection, and compaction on the CPU while retaining WGPU storage-buffer shaders and indirect draws. This is useful as a correctness oracle and compatibility diagnostic; compute culling remains the default. Hi-Z rejection is GPU-only and therefore disabled on the reference path. The compute path also disables previous-frame Hi-Z rejection whenever the camera or a persistent instance record changes, then rebuilds the pyramid from the current conservative frustum result.

Run `mise test-gpu` for the bounded GPU acceptance gate. It drives a greater-than-64-batch stress scene through compute and CPU visibility, verifies adaptive Hi-Z rejection and asynchronous timestamps/counters, and requires byte-identical frames with meaningful color variance. A second authored-resource fixture places one instance in each of three GPU-selected geometry LODs and requires the CPU reference to make the same selections and produce the same pixels.

The WGPU path samples base-color and emissive maps as sRGB and material-data maps as linear values. Its GGX shader combines metallic-roughness factors, derivative-reconstructed tangent-space normals, occlusion, direct directional/point lights, and optional diffuse-irradiance plus roughness-prefiltered specular cubes imported from a project HDR environment. Point lights live outside the render uniform; a cluster-centric compute pass deterministically assigns up to 256 extracted lights into a 16×9×24 view-space grid. Every cluster can reference the complete bounded packet, so dense moving lights do not pop through a smaller hidden per-cluster limit. The pass reruns only when the camera, viewport, or point-light payload changes. A scene's World Environment independently selects image-based lighting and either an imported panorama or the built-in procedural atmosphere. The procedural sky exposes live sky/ground color, turbidity, atmosphere thickness, horizon softness, and an HDR sun direction, color, intensity, size, and glow. Its spherical horizon clips the sun, and elevation transitions the sky and hemispherical fill through daylight, twilight, and night. Above the horizon, the sun occupies the first directional-light render slot and therefore drives ordinary GGX lighting, shadow culling, and the primary shadow cascades; explicit ECS lights remain additive. Lighting, an enabled background, and material emission accumulate in an `RGBA16Float` scene target; world-environment exposure multiplied by active-camera exposure scales the result, and five successively smaller bright-pass levels produce broad bloom before one ACES-style tone-map pass presents through an sRGB target. Project UI, gizmos, and editor chrome render afterward, so world bloom never softens text or controls. Local reflection probes remain future work.

Use an emissive material when a visible surface should glow independently of lighting:

```luau
local neon = scrapbot.material.emissive("neon", 0.1, 0.5, 1.0, 8.0)
```

The non-negative RGB values define hue and `intensity` scales the emitted linear radiance. HDR values are intentionally not clamped to display white.

Screen-space ECS UI is reconciled after engine/project systems and painted as a blended overlay after world geometry. Visible windows feed platform pointer and keyboard state into the retained interaction system. Headless runs normally provide no interaction, but a semantic UI diagnostic script can drive the same reconciled controls deterministically without OS automation. `examples/ui-showcase` exercises the box model, hidden subtrees, nested horizontal and vertical stacks, titled panels, equal-width multi-column tables, selectable lists, progress indicators, smooth clipped scrolling, SDF-rounded styling, buttons, numeric and text inputs, checkboxes, and the embedded Inter typeface rendered from a precomputed MTSDF atlas. See [ECS UI](/guides/ecs-ui/) for the shared project/editor component contract.

With `--editor`, WGPU fills the complete central project viewport with world rendering and derives camera aspect from that live rectangle. Project UI retains one uniform canvas-to-window scale, is translated and clipped to the free-aspect viewport, and uses the inverse transform for pointer input and semantic diagnostics; it is never stretched independently along X and Y. Transient editor-origin ECS UI paints in a separate full-window coordinate and paint domain. Visible windows use the display's native pixel density while retaining logical editor dimensions, keeping UI text crisp on HiDPI displays. The editor-origin scene-camera entity clones the initial project view and supports right-mouse-captured WASD, Space, and Ctrl fly navigation in a visible window. Use `examples/ecs-showcase` to verify live geometry and `examples/ui-showcase` to verify project UI scaling:

```sh
bin/scrapbot run examples/ecs-showcase --backend wgpu --editor --headless --frames 20 --framegrab /tmp/scrapbot-editor.png
```

Use `examples/clustered-lights` as the interactive clustered-lighting showcase. It distributes 240 animated HDR point lights through a long architectural tunnel, with shared emissive marker batches and locally illuminated surfaces that make cluster boundaries and light range visually meaningful:

```sh
mise scrapbot -- run examples/clustered-lights --editor
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

Available actions are `click`, `hover`, `scroll` (`wheel_y`), `type` (`text`), `drag`, `key`, `wait` (`frames`), `expect`, and `capture`. Drag presses the target center, then moves either by `delta_x`/`delta_y` or to a semantic `destination` target before releasing. Set `destination_anchor` to `top`, `center` (the default), or `bottom` to distinguish insertion from into-row drops. Destination drags are preferred for list/tree drops and other target-oriented gestures because they survive layout changes; offsets remain useful for sliders and splitters. A positive `frames` value interpolates the movement across that many input frames for sustained gestures and performance diagnostics, while omitted or zero keeps the one-frame move. Keys include navigation, editing, Tab, Enter, Escape, Select All, Save, Undo, Redo, Editor Toggle, Run/Stop, and Pause/Step. Expectations cover `visible`, `hovered`, `active`, `focused`, `text`, and `inside_parent`; a text expectation compares the action's `text` value. Targets may combine `uuid`, `name`, `text`, and `origin`, plus a zero-based `occurrence` for duplicate matches. Set `part` to `panel_action` to resolve the first direct child button placed in a panel title instead of the panel's complete rectangle. A capture target supplies the framegrab region unless `--framegrab-region` is explicitly present. When `--frames` is omitted, a scripted run receives a 240-frame safety bound and exits as soon as all actions complete.

## Directional shadows

Shadow participation is explicit and independent:

```toml
[entities.shadow_caster]
[entities.shadow_receiver]
```

`shadow_caster` makes an entity contribute to the first directional light's shadow cascades. `shadow_receiver` makes it sample the selected cascade while evaluating directional light. An entity may have either marker, both, or neither. WGPU uses four 2048×2048 layers, practical logarithmic/uniform camera-depth splits out to 80 world units, texel-stabilized light projections, per-cascade GPU caster culling, and 3×3 PCF. Point-light shadows, multiple shadowed directional lights, cascade blending, and configurable quality are not yet provided.

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

The normal Odin suite also includes persistence torture harnesses. The scene harness drives seeded edits through a 512-entity scene, asserts that candidate classification scales with unique dirty UUIDs, keeps value-only comments and formatting intact during mixed structural saves, requires byte-identical repeated saves, excludes runtime entities, round-trips every scene component through structural serialization, injects write and generated-TOML failures, and crosses Save/Undo/Redo/Revert savepoints. The project transaction harness injects failures at every staging, backup, installation, and commit-marker phase, simulates crashes immediately before and after the commit boundary, verifies rollback or forward recovery for replacement and resource moves, rejects create conflicts, and reloads a jointly changed scene and resource registry. Resource lifecycle tests cover create, move, delete, UUID-preserving structural Undo/Redo, reference-aware deletion, and nested resource discovery. These are structural and golden-text assertions rather than machine-dependent timing thresholds.

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
