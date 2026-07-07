# FDR-008: Headful Demo Window

**Status:** Active
**Last reviewed:** 2026-07-05

## Overview

Headful demo rendering proves that Scrapbot can create a platform window, hand its native surface to WebGPU, configure a presentable surface, and draw visible frames through the same renderer foundation used by offscreen rendering.

**Odin migration note:** The Odin `run` command can execute bounded hidden frame loops and, with `--backend wgpu`, write a final offscreen WebGPU frame artifact through the Odin `wgpu-native` path and present the final simulated scene through a hidden SDL WebGPU surface. Visible software `run` now creates an SDL window, pumps quit/close events, drives the shared live-project frame tick with measured and clamped delta time, exits bounded runs after `--frames`, and exits unbounded runs on SDL quit/window close while pixel presentation remains pending. Bounded visible WebGPU `run` creates a visible SDL window, ticks the shared live-project reload/update path, and presents scene-derived frames through the Odin `wgpu-native` surface path until the frame limit or window close. The Odin SDL boundary can initialize video, create high-DPI windows, extract platform-native `wgpu-native` surface descriptors for Metal, Wayland/X11, or Win32, and present a single hidden clear frame through `scrapbot wgpu-surface-check`. Odin WebGPU smoke tasks stage the host `wgpu-native` runtime library into `odin-out/lib` directly instead of building the migration-era Zig engine to populate `zig-pkg`. Odin still rejects unbounded visible WebGPU presentation and WebGPU editor chrome until the full surface presentation loop is ported.

## Behavior

- Users can run `scrapbot run [path]` against a valid project on supported desktop platforms with SDL3 available.
- The command validates the project before opening a window.
- The renderer opens a 16:9 visible window and presents the project's default scene until the window is closed.
- Renderable entity position, rotation, scale, geometry, material base color, and spin values come from scene data.
- Legacy cube entities remain supported and render as box geometry with inline color material data.
- Camera projection/view data and the first directional light can come from scene data, with compatibility defaults when absent.
- Each presented frame uses the same scene-world render data flow and render-phase schedule as offscreen rendering.
- Renderables with matching geometry and compatible pipeline-affecting render state are drawn through automatic instanced render batches.
- Renderable meshes render with depth testing, scene-driven directional diffuse shading, and receiver-side shadowing.
- UI rectangles and text labels render after 3D scene content as an overlay.
- Users can run `scrapbot run [path] --frames N` to exit after a fixed number of frames for smoke tests and automation.
- Users can run `scrapbot run [path] --hidden --frames N` to create the SDL window and WebGPU presentation surface without showing a normal visible window. `--hidden` requires `--frames` so invisible runs remain bounded.
- Headful live updates use measured elapsed frame time capped at a short spike limit; headless `step`, `bench`, and `test` runs remain deterministic and use their explicit `--dt` or manifest timestep.
- In headful runs, holding the right mouse button enables a fly camera. Mouse movement changes view direction; W/A/S/D moves relative to the camera; Space moves up; Ctrl moves down. While active, the SDL window uses relative mouse mode so view rotation can continue at window edges.
- The fly camera initializes from the scene-authored camera and applies as a render-only camera override. It does not mutate scene files or live scene camera components.
- When the editor/debug overlay is visible, fly-camera input only applies while the pointer is over the game viewport.
- The engine-owned editor/debug overlay is hidden by default; users can press Ctrl+Tab to toggle it.
- Users can run `scrapbot run [path] --editor` to start with the editor/debug overlay visible.
- In editor mode, the game viewport fills the remaining area between editor chrome regions instead of preserving the default window's 16:9 aspect ratio.
- `scrapbot render [path] [output.png]` remains the headless/offscreen snapshot command.

## Design Decisions

### 1. Make `run` the first headful command

**Decision:** `scrapbot run` opens a visible rendering window instead of only loading and printing project state.
**Why:** Running a project should exercise the interactive runtime path. The previous command was only a placeholder, so changing it now avoids accumulating a false contract.
**Tradeoff:** Headful execution now depends on platform windowing support and may not run in every CI environment.

### 2. Use a larger 16:9 default viewport

**Decision:** The default headful window opens at 1280x720.
**Why:** The editor overlay and UI examples need enough room to be legible while preserving the common 16:9 shape used by current render examples.
**Tradeoff:** Smaller screens may need users to resize the window manually until project/window settings exist.

### 3. Use SDL3 for the desktop window backend

**Decision:** Desktop windowing uses SDL3 to create a native platform window. Scrapbot creates the matching `wgpu-native` surface from SDL-provided native handles: Metal on macOS, Wayland/X11 on Linux, and Win32 HWND/HINSTANCE on Windows MSVC.
**Why:** SDL3 gives Scrapbot a small C ABI windowing layer with cross-platform reach while keeping platform details behind the renderer boundary described in ADR-005.
**Tradeoff:** The development-time run path still expects SDL3 to be installed as a system dependency. Host build bundles can copy discoverable SDL3 runtime libraries into the bundle, but deeper app relocation and installer-grade dependency management remain packaging work.

### 4. Keep the frame cap as a runtime option

**Decision:** `--frames N` is supported on the headful run command.
**Why:** A visible window normally runs until closed, but development agents and CI need a bounded smoke-test path that still initializes the same surface and presentation code.
**Tradeoff:** The option is an engine-runner concern rather than project data, so it should remain a CLI/runtime flag.

### 4a. Support hidden bounded surface smoke tests

**Decision:** `--hidden` is supported on the headful run command when paired with `--frames N`.
**Why:** Agents and CI sometimes need to exercise SDL window creation, native surface extraction, WebGPU surface configuration, and presentation without interrupting a developer's desktop with a briefly appearing window.
**Tradeoff:** Hidden runs are automation smoke tests, not interactive sessions. Requiring `--frames` prevents an invisible run from continuing indefinitely with no window for the user to close.

### 5. Use measured elapsed time for live updates

**Decision:** Headful `scrapbot run` advances scripts, editor animation, and fly-camera motion with elapsed frame time measured from the window loop, clamped to a short maximum.
**Why:** Interactive runs should reflect real presentation cadence instead of moving a fixed amount per presented frame. The clamp prevents debugger pauses, reload stalls, or OS scheduling hiccups from injecting a large gameplay step.
**Tradeoff:** Live window runs are intentionally not deterministic across machines or frame rates. Deterministic scenarios should continue to use `scrapbot step`, `scrapbot bench`, or `scrapbot test` with explicit timesteps.

### 6. Keep editor visibility as a runtime option

**Decision:** `--editor` is supported on the headful run command and starts the engine-owned editor/debug overlay visible.
**Why:** Normal gameplay runs should show the game first, while editor sessions need immediate tooling chrome without mutating project data.
**Tradeoff:** Early editor state is controlled by runner flags until editor session persistence is designed.

### 7. Share the scene-world render path with offscreen rendering

**Decision:** Headful rendering reads scene render data directly from the project ECS world, prepares batches from a frame renderable snapshot, and draws through the same render schedule as offscreen rendering.
**Why:** Visible windows and headless snapshots should exercise the same rendering architecture wherever possible. This follows ADR-022.
**Tradeoff:** Backend resource lifetime is still managed by the renderer facade until native/internal component storage exists.

### 8. Add a render-only fly camera for headful exploration

**Decision:** The headful runner owns a fly-camera transform initialized from the current scene camera. While right mouse is held, pointer delta and semantic movement input update that transform; rendering receives it as a frame camera override.
**Why:** Dense scenes such as `spawn_swarm` need interactive navigation before a full editor camera/tool mode exists. Keeping this as a render-only override gives immediate inspection value without changing project scene data or requiring a gameplay camera component model.
**Tradeoff:** This is not yet an authored camera controller, action-mapping system, editor camera asset, or persisted editor session state. Scene reload resets the fly camera to the new scene camera.

## Related

- **ADRs:** ADR-004, ADR-005, ADR-020, ADR-022
- **FDRs:** FDR-003, FDR-005, FDR-007, FDR-014, FDR-015, FDR-016, FDR-017

## Open Questions

- Should `run` eventually select scenes and windows from project configuration instead of fixed defaults?
- How should renderer failures be surfaced as structured diagnostics instead of coarse error names?
- How should release packaging bundle SDL3 and any required runtime libraries per platform?
