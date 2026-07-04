# FDR-008: Headful Demo Window

**Status:** Active
**Last reviewed:** 2026-07-04

## Overview

Headful demo rendering proves that Machina can create a platform window, hand its native surface to WebGPU, configure a presentable surface, and draw visible frames through the same renderer foundation used by offscreen rendering.

## Behavior

- Users can run `machina run [path]` against a valid project on supported desktop platforms with SDL3 available.
- The command validates the project before opening a window.
- The renderer opens a 16:9 visible window and presents the project's default scene until the window is closed.
- Renderable entity position, rotation, scale, geometry, material base color, and spin values come from scene data.
- Legacy cube entities remain supported and render as box geometry with inline color material data.
- Camera projection/view data and the first directional light can come from scene data, with compatibility defaults when absent.
- Each presented frame uses the same internal render ECS world and render-phase schedule as offscreen rendering.
- Renderables with matching geometry and compatible pipeline-affecting render state are drawn through automatic instanced render batches.
- Renderable meshes render with depth testing, scene-driven directional diffuse shading, and receiver-side shadowing.
- UI rectangles and text labels render after 3D scene content as an overlay.
- Users can run `machina run [path] --frames N` to exit after a fixed number of frames for smoke tests and automation.
- In headful runs, holding the right mouse button enables a fly camera. Mouse movement changes view direction; W/A/S/D moves relative to the camera; Space moves up; Ctrl moves down. While active, the SDL window uses relative mouse mode so view rotation can continue at window edges.
- The fly camera initializes from the scene-authored camera and applies as a render-only camera override. It does not mutate scene files or live scene camera components.
- When the editor/debug overlay is visible, fly-camera input only applies while the pointer is over the game viewport.
- The engine-owned editor/debug overlay is hidden by default; users can press Ctrl+Tab to toggle it.
- Users can run `machina run [path] --editor` to start with the editor/debug overlay visible.
- In editor mode, the game viewport fills the remaining area between editor chrome regions instead of preserving the default window's 16:9 aspect ratio.
- `machina render [path] [output.bmp]` remains the headless/offscreen snapshot command.

## Design Decisions

### 1. Make `run` the first headful command

**Decision:** `machina run` opens a visible rendering window instead of only loading and printing project state.
**Why:** Running a project should exercise the interactive runtime path. The previous command was only a placeholder, so changing it now avoids accumulating a false contract.
**Tradeoff:** Headful execution now depends on platform windowing support and may not run in every CI environment.

### 2. Use a larger 16:9 default viewport

**Decision:** The default headful window opens at 1280x720.
**Why:** The editor overlay and UI examples need enough room to be legible while preserving the common 16:9 shape used by current render examples.
**Tradeoff:** Smaller screens may need users to resize the window manually until project/window settings exist.

### 3. Use SDL3 for the desktop window backend

**Decision:** Desktop windowing uses SDL3 to create a native platform window. Machina creates the matching `wgpu-native` surface from SDL-provided native handles: Metal on macOS, Wayland/X11 on Linux, and Win32 HWND/HINSTANCE on Windows MSVC.
**Why:** SDL3 gives Machina a small C ABI windowing layer with cross-platform reach while keeping platform details behind the renderer boundary described in ADR-005.
**Tradeoff:** The first portable slice expects SDL3 to be installed as a system dependency. Bundled runtime packaging remains future work.

### 4. Keep the frame cap as a runtime option

**Decision:** `--frames N` is supported on the headful run command.
**Why:** A visible window normally runs until closed, but development agents and CI need a bounded smoke-test path that still initializes the same surface and presentation code.
**Tradeoff:** The option is an engine-runner concern rather than project data, so it should remain a CLI/runtime flag.

### 5. Keep editor visibility as a runtime option

**Decision:** `--editor` is supported on the headful run command and starts the engine-owned editor/debug overlay visible.
**Why:** Normal gameplay runs should show the game first, while editor sessions need immediate tooling chrome without mutating project data.
**Tradeoff:** Early editor state is controlled by runner flags until editor session persistence is designed.

### 6. Share the renderer ECS path with offscreen rendering

**Decision:** Headful rendering extracts, prepares, queues, and draws through the same renderer-owned ECS world and schedule as offscreen rendering.
**Why:** Visible windows and headless snapshots should exercise the same rendering architecture wherever possible. This follows ADR-013.
**Tradeoff:** Backend resource lifetime is still managed by the renderer facade until native/internal component storage exists.

### 7. Add a render-only fly camera for headful exploration

**Decision:** The headful runner owns a fly-camera transform initialized from the current scene camera. While right mouse is held, pointer delta and semantic movement input update that transform; rendering receives it as a frame camera override.
**Why:** Dense scenes such as `spawn_swarm` need interactive navigation before a full editor camera/tool mode exists. Keeping this as a render-only override gives immediate inspection value without changing project scene data or requiring a gameplay camera component model.
**Tradeoff:** This is not yet an authored camera controller, action-mapping system, editor camera asset, or persisted editor session state. Scene reload resets the fly camera to the new scene camera.

## Related

- **ADRs:** ADR-004, ADR-005, ADR-013, ADR-020
- **FDRs:** FDR-003, FDR-005, FDR-007, FDR-014, FDR-015, FDR-016, FDR-017

## Open Questions

- Should `run` eventually select scenes and windows from project configuration instead of fixed defaults?
- How should renderer failures be surfaced as structured diagnostics instead of coarse error names?
- How should release packaging bundle SDL3 and any required runtime libraries per platform?
