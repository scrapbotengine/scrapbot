---
title: Rendering And Testing
description: Run the null and WebGPU backends, smoke-test projects, and verify generated framegrabs.
---

Scrapbot has two rendering paths today:

- `null`: headless renderer for fast smoke tests.
- `wgpu`: SDL3 plus `wgpu-native` for indexed geometry, shared materials, and instanced draw batching.

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
  --frames 2 \
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
- Visual output shows the fountain cubes and generated ground plane with distinct shared materials.

## Full local verification

```sh
mise test
git diff --check
```

`mise test` builds Luau, builds the Scrapbot CLI, checks the engine package, runs all Odin package tests, checks the CLI version, validates `examples/minimal`, and runs the null renderer.

WGPU smoke tests are not part of the default suite because they may need platform window-system access.
