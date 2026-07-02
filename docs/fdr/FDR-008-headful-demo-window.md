# FDR-008: Headful Demo Window

**Status:** Active
**Last reviewed:** 2026-07-02

## Overview

Headful demo rendering proves that Machina can create a platform window, hand its native surface to WebGPU, configure a presentable surface, and draw visible frames through the same renderer foundation used by offscreen rendering.

## Behavior

- Users can run `machina run [path]` against a valid project.
- The command validates the project before opening a window.
- The renderer opens a visible window and presents the project's default scene until the window is closed.
- Cube entity position, rotation, scale, color, and spin values come from scene data.
- Camera projection/view data and the first directional light can come from scene data, with compatibility defaults when absent.
- Cubes render with depth testing and scene-driven directional diffuse shading.
- Users can run `machina run [path] --frames N` to exit after a fixed number of frames for smoke tests and automation.
- `machina render [path] [output.bmp]` remains the headless/offscreen snapshot command.

## Design Decisions

### 1. Make `run` the first headful command

**Decision:** `machina run` opens a visible rendering window instead of only loading and printing project state.
**Why:** Running a project should exercise the interactive runtime path. The previous command was only a placeholder, so changing it now avoids accumulating a false contract.
**Tradeoff:** Headful execution now depends on platform windowing support and may not run in every CI environment.

### 2. Use SDL3 for the first window backend

**Decision:** The first macOS window path uses SDL3 to create a Metal-capable window and obtain a `CAMetalLayer` for `wgpu-native`.
**Why:** SDL3 gives Machina a small C ABI windowing layer with cross-platform reach while keeping platform details behind the renderer boundary described in ADR-005.
**Tradeoff:** The current build assumes Homebrew SDL3 on macOS. Dependency discovery and packaging need to become first-class before this is portable.

### 3. Keep the frame cap as a runtime option

**Decision:** `--frames N` is supported on the headful run command.
**Why:** A visible window normally runs until closed, but development agents and CI need a bounded smoke-test path that still initializes the same surface and presentation code.
**Tradeoff:** The option is an engine-runner concern rather than project data, so it should remain a CLI/runtime flag.

## Related

- **ADRs:** ADR-004, ADR-005
- **FDRs:** FDR-003, FDR-007, FDR-014

## Open Questions

- How should SDL3 be discovered on non-Homebrew macOS installations and other platforms?
- Should `run` eventually select scenes and windows from project configuration instead of fixed defaults?
- How should renderer failures be surfaced as structured diagnostics instead of coarse error names?
