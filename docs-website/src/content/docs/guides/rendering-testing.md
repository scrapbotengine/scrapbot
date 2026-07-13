---
title: Rendering And Testing
description: Run the null and WebGPU backends, smoke-test projects, and verify generated framegrabs.
---

Scrapbot has two rendering paths today:

- `null`: headless renderer for fast smoke tests.
- `wgpu`: SDL3 plus `wgpu-native` for indexed geometry, shared base-color and PNG-textured materials, ECS lighting, directional shadows, and instanced draw batching.

The WGPU path decodes material base colors to linear space, accumulates light there, tone maps the HDR result, and presents through an sRGB target. A scene with no ambient, directional, or point lights therefore renders its geometry black.

Screen-space ECS UI is reconciled after engine/project systems and painted as a blended overlay after world geometry. Visible windows feed pointer position and primary-button state into topmost-element hit testing; hidden framegrabs deliberately render with no pointer interaction. `examples/ui-showcase` exercises the box model, nested horizontal and vertical stacks, smooth clipped scrolling, SDF-rounded backgrounds, pointer-styled buttons, and the embedded Inter typeface rendered from a precomputed MTSDF atlas.

With `--editor`, WGPU fills the complete central project viewport with world rendering and project UI, derives camera aspect from that live rectangle, remaps project pointer coordinates, and paints engine-owned chrome in a separate full-window overlay pass. Visible windows use the display's native pixel density while retaining logical editor dimensions, keeping UI text crisp on HiDPI displays. The editor-origin scene-camera entity clones the initial project view and supports right-mouse-captured WASD, Space, and Ctrl fly navigation in a visible window. Use `examples/ecs-showcase` to verify live geometry and `examples/ui-showcase` to verify project UI scaling:

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
