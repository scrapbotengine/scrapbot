# FDR-003: Pluggable rendering backends

**Status:** Active
**Last reviewed:** 2026-07-07

## Overview

Pluggable rendering backends allow Scrapbot to start with `wgpu-native` while keeping rendering replaceable enough for offscreen verification, editor viewports, and future experiments.

## Behavior

- The runtime can submit frame data through a renderer boundary.
- The current implementation supports the null backend.
- Users can select a renderer backend from the CLI.
- The `wgpu` backend opens an SDL3 window, creates a `wgpu-native` surface, and runs a simple triangle render loop.
- The `wgpu` backend can also render a headless final-frame PNG with `--framegrab`.
- The `wgpu` backend currently requires `--window` or `--framegrab`.
- Renderer runs can be limited with `--frames`; windowed `0` means run until the window closes, while headless `0` captures one frame.
- Users can request a short-lived SDL3 window with the null backend for platform smoke checks.
- Future backends should not require scene files or gameplay code to know backend-specific GPU handles.

## Design Decisions

### 1. Start with a null renderer

**Decision:** The initial runtime submits a frame summary to a null renderer.
**Why:** This proves project loading, ECS world construction, and runtime flow before introducing GPU setup. See ADR-003.
**Tradeoff:** It does not verify graphics output yet.

### 2. Make wgpu-native the first real backend

**Decision:** Implement the first headful renderer with `wgpu-native`.
**Why:** It matches the desired WebGPU direction, supports modern native graphics backends, and is available through Odin's vendor bindings. See ADR-003.
**Tradeoff:** WebGPU concepts and validation rules shape the renderer abstraction early.

### 3. Use SDL3 for the first window path

**Decision:** Open platform windows through SDL3.
**Why:** SDL3 is available through Odin's vendor bindings and gives the renderer a portable surface path. See ADR-005.
**Tradeoff:** Headful runtime work now depends on SDL3 being available in development and distribution environments.

### 4. Keep the first WGPU implementation as a triangle renderer

**Decision:** The current `wgpu` backend creates a minimal WGSL render pipeline and draws a filled triangle in a window loop.
**Why:** This proves the native window/surface/device/swapchain path plus shader and pipeline creation before introducing render packets, buffers, assets, or scene-driven drawing.
**Tradeoff:** The backend verifies a render loop and draw call, not scene rendering.

### 5. Add headless framegrabs before scene rendering

**Decision:** Headless WGPU renders the same triangle pipeline into an offscreen texture, reads the final frame back to CPU memory, and writes a PNG.
**Why:** This gives agents and tests a visual artifact before the renderer is scene-driven.
**Tradeoff:** On macOS, the current implementation creates a hidden SDL3 window for Metal adapter bootstrap even though the captured frame is rendered offscreen.

## Related

- **ADRs:** ADR-003, ADR-005
- **FDRs:** FDR-001, FDR-002

## Open Questions

- What render packet shape should bridge ECS state into renderer-owned resources?
- How should offscreen render output be compared once scene rendering exists?
- How long should the headful runtime loop live before the editor and game loop exist?
