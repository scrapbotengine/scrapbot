---
title: Rendering Overview
description: How Machina turns ECS scene data into WebGPU rendering.
---

Machina renders through `wgpu-native` behind an engine-owned renderer boundary.

The public scene authoring model is ECS data:

- `machina.transform`
- `machina.geometry.primitive`
- `machina.material.surface`
- `machina.renderer`
- `machina.camera`
- `machina.light.directional`
- `machina.shadow.caster`
- `machina.shadow.receiver`
- UI components such as `machina.ui.rect` and `machina.ui.text`

## Render Flow

Rendering uses an internal render world and render-phase schedule built with the same runtime ECS implementation as game worlds.

Each frame, render systems:

1. Extract renderable scene data into the render world.
2. Prepare mesh resources and instance buffers.
3. Queue mesh draw batches.
4. Process UI interaction state.
5. Prepare UI draw data.
6. Queue UI draw commands.
7. Draw queued meshes and UI.

The editor/debug overlay includes render-system timings from this internal render schedule.

## Renderer Settings

Scenes can include one `machina.renderer` component to configure the game-view render pipeline:

```toml
[[entities]]
id = "machina.renderer"
name = "Renderer"

[entities.components."machina.renderer"]
hdr = true
tone_mapping = "aces"
exposure = 0.0
postprocess_enabled = true
antialiasing = "fxaa"
bloom_enabled = true
bloom_threshold = 0.85
bloom_intensity = 0.12
bloom_radius = 1.0
vignette_enabled = true
vignette_strength = 0.24
vignette_radius = 0.82
chromatic_aberration_enabled = true
chromatic_aberration_strength = 0.0025
```

Only one renderer component may appear in a scene. `machina init` writes this singleton into the generated default scene.

Supported color settings:

- `hdr`: render scene color into an internal `rgba16_float` texture before final output.
- `tone_mapping`: `none`, `reinhard`, or `aces`.
- `exposure`: exposure compensation before tone mapping.

Supported postprocess settings:

- `antialiasing`: `none` or `fxaa`.
- `bloom_enabled`, `bloom_threshold`, `bloom_intensity`, `bloom_radius`.
- `vignette_enabled`, `vignette_strength`, `vignette_radius`.
- `chromatic_aberration_enabled`, `chromatic_aberration_strength`.

Scripts can query and write `machina.renderer` like any other component, so gameplay systems can animate exposure or effect strengths. HDR texture format is selected when the render target is created; changing `hdr` at runtime needs renderer recreation or scene reload in the current slice.

## Headful and Offscreen

Headful runs create a platform window and present to a surface:

```sh
machina run examples/showcase --editor
```

For bounded surface smoke tests that should not show a normal visible window, pair `--hidden` with a frame limit:

```sh
machina run examples/showcase --hidden --frames 2
```

Offscreen rendering writes PNG artifacts:

```sh
machina render examples/showcase zig-out/showcase.png
machina render --editor --select native-cyan-box examples/native_motion zig-out/native-motion-editor.png
machina render --editor --width 2560 --height 1800 --pixel-scale 2 examples/minimal zig-out/editor-hidpi.png
```

Offscreen verification checks for visible rendered content:

```sh
machina render-test examples/showcase zig-out/showcase-render-test.png
```

Use offscreen verification before relying on visible-window inspection for renderer or editor-layout changes. `--editor` includes engine chrome in the offscreen frame, `--select` preselects an entity for inspector verification, and `--pixel-scale` makes HiDPI physical/logical pixel assumptions explicit in generated artifacts.

## Camera and Lighting

If a scene provides a camera entity with `machina.transform` and `machina.camera`, the renderer uses it.

If a scene provides a directional light with `machina.light.directional`, the renderer uses it.

Fallback camera and light defaults exist so simple scenes can render before they author explicit camera/light data.

## UI Overlay

UI renders after 3D content as screen-space ECS data. The first UI system supports:

- Canvas markers.
- Rectangles.
- Text labels.
- Button markers.
- Command ids.
- Runtime command events.
- Engine-owned editor/debug overlay.
