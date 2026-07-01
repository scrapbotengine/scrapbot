# FDR-007: Offscreen Demo Rendering

**Status:** Active
**Last reviewed:** 2026-07-01

## Overview

Offscreen demo rendering proves that Machina can initialize the WebGPU backend, create GPU resources, render through a graphics pipeline, read pixels back, and write an inspectable image artifact without opening a window.

## Behavior

- Users can run `machina render [path] [output.bmp]` against a valid project.
- Users can run `machina render-test [path] [output.bmp]` to render offscreen and verify the generated BMP.
- The command validates the project before rendering.
- The command loads the project's default scene and draws one frame of its cube entities into an offscreen texture.
- Cube entity position, rotation, scale, color, and spin values come from scene data.
- Cubes render with depth testing and simple directional diffuse shading.
- The rendered pixels are copied back to CPU memory and written as a 24-bit BMP file.
- Render verification parses the BMP and checks dimensions, foreground pixel coverage, visible connected components, and expected warm/cool color groups derived from scene cube colors.
- The command works without a platform window or editor.

## Design Decisions

### 1. Keep offscreen rendering available after headful rendering

**Decision:** The render command writes the loaded default scene to an image file without requiring a window surface.
**Why:** This validates `wgpu-native`, shader compilation, render pipeline creation, command submission, readback, and deterministic artifact output in a way that is useful for tests and agent workflows. It follows ADR-004 and ADR-005.
**Tradeoff:** It does not prove input, presentation timing, or live interaction.

### 2. Keep the external binding behind a renderer module

**Decision:** `wgpu-native` binding usage is isolated behind Machina's renderer code.
**Why:** The Zig binding currently needs compatibility patches for the active Zig toolchain, and the official `wgpu-native` release stream moves independently. This follows ADR-005.
**Tradeoff:** The renderer module must expose deliberate engine-owned APIs as rendering grows.

## Related

- **ADRs:** ADR-004, ADR-005
- **FDRs:** FDR-001, FDR-002

## Open Questions

- Should the renderer output BMP, PNG, or a custom snapshot format long term?
- Should render snapshots become part of `machina check`, a separate test command, or stay as a standalone render command?
