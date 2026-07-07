# FDR-003: Pluggable rendering backends

**Status:** Active
**Last reviewed:** 2026-07-07

## Overview

Pluggable rendering backends allow Scrapbot to start with `wgpu-native` while keeping rendering replaceable enough for offscreen verification, editor viewports, and future experiments.

## Behavior

- The runtime can submit frame data through a renderer boundary.
- The current implementation supports the null backend.
- Users can select a renderer backend from the CLI.
- The `wgpu` backend opens an SDL3 window, creates a `wgpu-native` surface, clears one frame, presents it, and exits.
- The `wgpu` backend currently requires `--window`.
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

### 4. Keep the first WGPU implementation as a smoke renderer

**Decision:** The current `wgpu` backend only clears and presents one frame derived from the existing runtime flow.
**Why:** This proves the native window/surface/device/swapchain path before introducing pipelines, shaders, GPU resources, or render packets.
**Tradeoff:** The backend verifies presentation, not scene rendering.

## Related

- **ADRs:** ADR-003, ADR-005
- **FDRs:** FDR-001, FDR-002

## Open Questions

- What render packet shape should bridge ECS state into renderer-owned resources?
- How soon should offscreen rendering become part of verification?
- How long should the headful runtime loop live before the editor and game loop exist?
