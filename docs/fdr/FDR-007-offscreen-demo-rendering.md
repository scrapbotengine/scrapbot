# FDR-007: Offscreen Demo Rendering

**Status:** Active
**Last reviewed:** 2026-07-06

## Overview

Offscreen demo rendering proves that Scrapbot can initialize the WebGPU backend, create GPU resources, render through a graphics pipeline, read pixels back, and write an inspectable image artifact without opening a window.

**Odin migration note:** During the staged Odin rewrite, the Odin `render` and `render-test` commands currently validate projects, parse render flags, run bounded Luau frame simulation, check selected entity ids, and report render extraction stats with an explicit pending backend marker. Pixel output, metadata sidecars, image verification, and WebGPU readback still remain in the Zig implementation until the Odin `wgpu-native` renderer lands.

## Behavior

- Users can run `scrapbot render [--editor] [--select entity-id] [--frames N] [--width PX] [--height PX] [--pixel-scale S] [path] [output.png]` against a valid project.
- Users can run `scrapbot render-test [--editor] [--select entity-id] [--frames N] [--width PX] [--height PX] [--pixel-scale S] [path] [output.png]` to render offscreen and verify the generated image.
- The command validates the project before rendering.
- The command loads the project's default scene and draws one frame of its renderable mesh and UI overlay entities into an offscreen texture by default.
- When `--frames N` is greater than one, the command reuses the same offscreen GPU resources, runs fixed `1/60` updates, renders each frame, and writes or verifies the final frame.
- `--width` and `--height` override the default `640x480` physical offscreen target so editor chrome and inspector details can be verified at useful review sizes.
- `--pixel-scale` sets physical pixels per logical pixel for offscreen frame input. Command output and a `.metadata.json` sidecar next to the image report both the physical artifact size and the logical viewport size, for example a `1280x900` render at `--pixel-scale 2` is labeled as a `640x450` logical viewport.
- `--editor` renders the engine editor shell into the offscreen frame; `--select` implies editor rendering and preselects the named scene entity for inspector verification.
- Renderable entity position, rotation, scale, geometry, material base color, and spin values come from scene data.
- Legacy cube entities remain supported and render as box geometry with inline color material data.
- Camera projection/view data and the first directional light can come from scene data, with compatibility defaults when absent.
- Renderable meshes can cast or receive directional-light shadows when authored with shadow marker components.
- UI rectangles and text labels render after 3D scene content as an overlay.
- The renderer extracts scene data into an internal render ECS world, batches matching renderables, queues batch draw commands as render-world entities, and executes the render path through a render-phase system schedule.
- Renderable meshes render with depth testing, scene-driven directional diffuse shading, and receiver-side shadowing.
- The rendered pixels are copied back to CPU memory and written as a PNG file by default. Explicit `.bmp` output paths remain supported for compatibility.
- Render verification parses the image and checks dimensions, foreground pixel coverage, visible connected components, and expected warm/cool color groups derived from scene material and UI colors.
- The command works without a platform window. Editor chrome rendering is optional and driven through normal frame input.

## Design Decisions

### 1. Keep offscreen rendering available after headful rendering

**Decision:** The render command writes the loaded default scene to an image file without requiring a window surface.
**Why:** This validates `wgpu-native`, shader compilation, render pipeline creation, command submission, readback, and deterministic artifact output in a way that is useful for tests and agent workflows. It follows ADR-004 and ADR-005.
**Tradeoff:** It does not prove input, presentation timing, or live interaction.

### 2. Keep the external binding behind a renderer module

**Decision:** `wgpu-native` binding usage is isolated behind Scrapbot's renderer code.
**Why:** The Zig binding currently needs compatibility patches for the active Zig toolchain, and the official `wgpu-native` release stream moves independently. This follows ADR-005.
**Tradeoff:** The renderer module must expose deliberate engine-owned APIs as rendering grows.

### 3. Use the shared ECS for renderer-internal data flow

**Decision:** Offscreen rendering extracts scene data into a renderer-owned `runtime.World` and queues draw commands as internal ECS component data before issuing GPU commands.
**Why:** This keeps offscreen rendering aligned with the same world, query, and scheduling model used by scenes and scripts. It follows ADR-013.
**Tradeoff:** GPU buffers and bind groups are still renderer-owned side resources until native/internal component storage is designed.

### 4. Let offscreen rendering exercise editor frame input

**Decision:** `scrapbot render` and `scrapbot render-test` can render editor chrome and selected-entity inspector state by supplying editor-shaped frame input to the same offscreen renderer.
**Why:** Agent and CI workflows need to verify editor layout bugs without relying on OS window screenshots or manual clicks.
**Tradeoff:** The first selected-entity option is an inspection/debugging affordance, not a general editor automation API.

### 5. Let offscreen rendering run bounded frame sequences

**Decision:** `scrapbot render` and `scrapbot render-test` support `--frames N` for fixed-step offscreen frame sequences while reusing the same WebGPU device, render target, and renderer state.
**Why:** Setup-only render checks miss leaks and regressions that occur during repeated update/render loops. A bounded offscreen sequence keeps automation deterministic without requiring a platform window.
**Tradeoff:** Multi-frame offscreen rendering still does not prove SDL presentation behavior or GPU driver-level leak freedom.

### 6. Let offscreen renders choose output dimensions

**Decision:** `scrapbot render`, `scrapbot render-test`, and `scrapbot visual-test` accept positive integer `--width` and `--height` options. The defaults remain `640x480`.
**Why:** Small fixed render targets are fine for broad smoke coverage but can clip editor sidebars and hide detailed inspector controls. Configurable dimensions let agents create reviewable artifacts that match the UI area being debugged.
**Tradeoff:** Larger offscreen renders cost more GPU memory and readback time, so smoke tests should keep using small defaults unless the scenario needs more pixels.

### 7. Make offscreen DPI explicit

**Decision:** `scrapbot render`, `scrapbot render-test`, and `scrapbot visual-test` accept a positive finite `--pixel-scale` option. `--width` and `--height` remain physical artifact pixels, while frame input viewport dimensions are logical pixels derived as physical size divided by pixel scale.
**Why:** Editor chrome spacing, input padding, rounded corners, and hit testing are authored in logical pixels, but review artifacts are physical pixel images. Explicit scale labels prevent `@2x` screenshots from making a two-logical-pixel inset look like one CSS/display pixel.
**Tradeoff:** The image file itself is still a plain PNG/BMP without embedded custom metadata. The adjacent JSON sidecar must travel with the image until a richer snapshot manifest or embedded metadata format exists.

## Related

- **ADRs:** ADR-004, ADR-005, ADR-013
- **FDRs:** FDR-001, FDR-002, FDR-005, FDR-014, FDR-015, FDR-016, FDR-017

## Open Questions

- Should render snapshots move from the current adjacent metadata sidecar to embedded metadata or a richer snapshot manifest?
- Should render snapshots become part of `scrapbot check`, a separate test command, or stay as a standalone render command?
