# FDR-007: Offscreen Triangle Rendering

**Status:** Active
**Last reviewed:** 2026-07-01

## Overview

Offscreen triangle rendering proves that Machina can initialize the WebGPU backend, create GPU resources, render through a graphics pipeline, read pixels back, and write an inspectable image artifact without opening a window.

## Behavior

- Users can run `machina render [path] [output.bmp]` against a valid project.
- The command validates the project before rendering.
- The renderer draws a colored triangle into an offscreen texture.
- The rendered pixels are copied back to CPU memory and written as a 24-bit BMP file.
- The command works without a platform window or editor.

## Design Decisions

### 1. Render offscreen before opening a window

**Decision:** The first rendering slice targets an image file rather than a window surface.
**Why:** This validates `wgpu-native`, shader compilation, render pipeline creation, command submission, readback, and deterministic artifact output while keeping platform windowing out of the same slice. It follows ADR-004 and ADR-005.
**Tradeoff:** It does not prove swapchain/surface handling, input, presentation timing, or live interaction.

### 2. Keep the external binding behind a renderer module

**Decision:** `wgpu-native` binding usage is isolated behind Machina's renderer code.
**Why:** The Zig binding currently needs compatibility patches for the active Zig toolchain, and the official `wgpu-native` release stream moves independently. This follows ADR-005.
**Tradeoff:** The renderer module must expose deliberate engine-owned APIs as rendering grows.

## Related

- **ADRs:** ADR-004, ADR-005
- **FDRs:** FDR-001, FDR-002

## Open Questions

- Should the renderer output BMP, PNG, or a custom snapshot format long term?
- Which windowing library should own the first interactive surface?
- Should render snapshots become part of `machina check`, a separate test command, or stay as a standalone render command?
