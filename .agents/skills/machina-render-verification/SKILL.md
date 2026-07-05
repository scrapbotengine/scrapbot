---
name: machina-render-verification
description: Use when changing Machina rendering, WGSL shaders, scene-driven render data, or visual test expectations. Provides the offscreen render verification workflow and explains what render-test can and cannot prove.
---

# Render Verification

Machina verifies rendering primarily through offscreen PNG output. Use this workflow for renderer, shader, scene-data, or visual-regression work.

## Workflow

1. Build and run Zig tests.
2. Run the offscreen visual checks against `examples/minimal` and `examples/batching`.
3. Run a bounded headful smoke test only when the change touches window/surface presentation.
4. Inspect or improve `src/render_verify.zig` if the failure is about visual assertions rather than rendering itself.

## Verification Surface

`machina render-test [project] [output.png]`:

- validates and loads the project scene,
- renders the scene offscreen,
- reads the image artifact back,
- verifies image shape,
- checks foreground pixel coverage,
- checks visible connected components,
- checks expected warm/cool color groups derived from scene material colors.

This catches failures such as blank frames, invalid artifacts, the prior class of bug where multiple scene cubes collapsed to one visible object/color due to shared uniform state, and broad batching regressions where repeated renderables stop appearing.

## Limits

`render-test` is not a golden-image comparison and does not prove exact object count or pixel-perfect layout. If a rendering change needs stricter guarantees, extend the verifier deliberately instead of replacing it with manual screenshot inspection.

Use headful `run --frames N` as smoke coverage for SDL/window/surface setup. Prefer offscreen checks for repeatable assertions.
