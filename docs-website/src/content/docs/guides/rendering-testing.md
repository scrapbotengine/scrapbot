---
title: Rendering And Testing
description: Run the null and WebGPU backends, smoke-test projects, and verify generated framegrabs.
---

Scrapbot has two rendering paths today:

- `null`: headless renderer for fast smoke tests.
- `wgpu`: SDL3 plus `wgpu-native` for indexed geometry, shared base-color, emissive HDR, and PNG-textured materials, ECS lighting, directional shadows, bloom, tone mapping, and instanced draw batching.

The WGPU path decodes material base colors to linear space and accumulates lighting plus material emission into an `RGBA16Float` scene target. Five successively smaller bright-pass levels produce broad bloom before one ACES-style tone-map pass presents through an sRGB target. Project UI, gizmos, and editor chrome render afterward, so world bloom never softens text or controls. A lit scene with no ambient, directional, point, or emissive contribution therefore renders its geometry black.

Use an emissive material when a visible surface should glow independently of lighting:

```luau
local neon = scrapbot.material.emissive("neon", 0.1, 0.5, 1.0, 8.0)
```

The non-negative RGB values define hue and `intensity` scales the emitted linear radiance. HDR values are intentionally not clamped to display white.

Screen-space ECS UI is reconciled after engine/project systems and painted as a blended overlay after world geometry. Visible windows feed platform pointer and keyboard state into the retained interaction system. Headless runs normally provide no interaction, but a semantic UI diagnostic script can drive the same reconciled controls deterministically without OS automation. `examples/ui-showcase` exercises the box model, hidden subtrees, nested horizontal and vertical stacks, titled panels, equal-width multi-column tables, selectable lists, progress indicators, smooth clipped scrolling, SDF-rounded styling, buttons, numeric and text inputs, checkboxes, and the embedded Inter typeface rendered from a precomputed MTSDF atlas. See [ECS UI](/guides/ecs-ui/) for the shared project/editor component contract.

With `--editor`, WGPU fills the complete central project viewport with world rendering and project UI, derives camera aspect from that live rectangle, remaps project pointer coordinates, and paints transient editor-origin ECS UI in a separate full-window coordinate and paint domain. Visible windows use the display's native pixel density while retaining logical editor dimensions, keeping UI text crisp on HiDPI displays. The editor-origin scene-camera entity clones the initial project view and supports right-mouse-captured WASD, Space, and Ctrl fly navigation in a visible window. Use `examples/ecs-showcase` to verify live geometry and `examples/ui-showcase` to verify project UI scaling:

```sh
bin/scrapbot run examples/ecs-showcase --backend wgpu --editor --headless --frames 20 --framegrab /tmp/scrapbot-editor.png
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

Use `--ui-script` to reproduce interactions against public project UI or transient editor UI by UUID, entity name, or visible text. The driver resolves the target from the retained tree, reveals it through clipped ancestor scroll areas, and feeds ordinary pointer and keyboard state back through the normal reconciler. `--ui-dump` writes the final tree even when the run fails, including hierarchy, text, control kinds, clipping, raw and visible screen rectangles, paint order, hover/active/focus state, and the pending script action.

The checked-in component-picker scenario stops the project, selects an entity, opens the popup, hovers Camera, asserts the hover state, and requests a small target crop:

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
    {"action": "click", "target": {"text": "STOP", "origin": "editor"}},
    {"action": "hover", "target": {"text": "+  camera", "origin": "editor"}},
    {"action": "expect", "target": {"text": "+  camera"}, "expect": "hovered"},
    {"action": "capture", "target": {"text": "+  camera"}, "padding": 12}
  ]
}
```

Available actions are `click`, `hover`, `scroll` (`wheel_y`), `type` (`text`), `drag` (`delta_x`, `delta_y`), `key`, `wait` (`frames`), `expect`, and `capture`. Drag presses the target center, moves by the requested screen-space offset, and releases on the following frame. Keys include navigation, editing, Tab, Enter, Escape, Select All, Save, Undo, Redo, Editor Toggle, Run/Stop, and Pause/Step. Expectations cover `visible`, `hovered`, `active`, `focused`, `text`, and `inside_parent`; a text expectation compares the action's `text` value. Targets may combine `uuid`, `name`, `text`, and `origin`, plus a zero-based `occurrence` for duplicate matches. A capture target supplies the framegrab region unless `--framegrab-region` is explicitly present. When `--frames` is omitted, a scripted run receives a 240-frame safety bound and exits as soon as all actions complete.

## Directional shadows

Shadow participation is explicit and independent:

```toml
[entities.shadow_caster]
[entities.shadow_receiver]
```

`shadow_caster` makes an entity contribute to the first directional light's shadow map. `shadow_receiver` makes it sample that map while evaluating directional light. An entity may have either marker, both, or neither. The initial implementation uses one fixed 2048×2048 orthographic shadow map; it does not yet provide cascades or point-light shadows.

## Null renderer

The null backend is the default and does not open a window:

```sh
mise scrapbot -- run examples/minimal --backend null
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

The normal Odin suite also includes persistence torture harnesses. The scene harness drives seeded edits through a 512-entity scene, asserts that candidate classification scales with unique dirty UUIDs, keeps value-only comments and formatting intact during mixed structural saves, requires byte-identical repeated saves, excludes runtime entities, round-trips every scene component through structural serialization, injects write and generated-TOML failures, and crosses Save/Undo/Redo/Revert savepoints. The project transaction harness injects failures at every staging, backup, installation, and commit-marker phase, simulates crashes immediately before and after the commit boundary, verifies rollback or forward recovery, and reloads a jointly changed scene and resource registry. These are structural and golden-text assertions rather than machine-dependent timing thresholds.

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
