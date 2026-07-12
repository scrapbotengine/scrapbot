---
title: Rendering And Testing
description: Run the null and WebGPU backends, smoke-test projects, and verify generated framegrabs.
---

Scrapbot has two rendering paths today:

- `null`: headless renderer for fast smoke tests.
- `wgpu`: SDL3 plus `wgpu-native` for indexed geometry, shared base-color and PNG-textured materials, ECS lighting, directional shadows, and instanced draw batching.

The WGPU path decodes material base colors to linear space, accumulates light there, tone maps the HDR result, and presents through an sRGB target. A scene with no ambient, directional, or point lights therefore renders its geometry black.

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

- PNG image data, 1280 x 720, RGBA.
- Signature starts with `8950 4e47 0d0a 1a0a`.
- Visual output shows shaded fountain cubes and the generated ground plane under ambient and directional light.
- Caster geometry projects directional shadows onto the receiver ground plane.

## Full local verification

```sh
mise test
git diff --check
```

`mise test` builds Luau, builds the Scrapbot CLI, checks the engine package, runs all Odin package tests, checks the CLI version, validates `examples/minimal`, and runs the null renderer.

WGPU smoke tests are not part of the default suite because they may need platform window-system access.
