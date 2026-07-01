# Machina Agent Guide

Machina is an experimental, text-first game engine written in Zig. The engine is intended to be friendly to agentic workflows: project state should be inspectable, editable, and reviewable as source text wherever possible. Binary files are for assets and build outputs, not core scene or project data.

## Project Shape

- `src/main.zig` contains the CLI entry point and command routing.
- `src/root.zig` owns project and scene loading/validation.
- `src/render.zig` owns the current WebGPU renderer and SDL-backed headful window path.
- `src/render_verify.zig` owns offscreen BMP verification.
- `src/shaders/` contains WGSL shaders embedded into the binary.
- `examples/minimal/` is the canonical smoke-test project.
- `docs/adr/` records architectural decisions.
- `docs/fdr/` records feature behavior and product/implementation decisions.
- `third_party/wgpu_native_zig/` is a vendored and locally patched Zig binding for `wgpu-native`.

## Current Engine Model

Projects have a `project.machina.toml` file and a default scene path. Scenes are TOML-shaped text files with root `name` and `version` fields plus `[[entities]]` records. The current renderable entity schema supports `kind = "cube"` with `position`, `rotation`, `scale`, `color`, and `spin` vectors.

Rendering uses `wgpu-native`. Headful rendering currently uses SDL3 on macOS via Homebrew paths in `build.zig`; offscreen rendering writes BMP artifacts and is the preferred automation surface.

The intended low-level runtime model is ECS-ish: stable entity identity, structured components, systems over component queries, and a scripting API that exposes those concepts directly. `src/runtime.zig` owns the current `World` and component storage. Scene loading builds a world, and rendering queries renderable components from that world.

Live reload is a core runtime capability. `machina run` currently uses a `LiveProject` session that tracks project metadata and the active scene as loaded text sources. Valid edits swap into the running renderer; invalid edits keep the last known good project and scene active. New architecture should preserve reloadable text data, stable ids, staged validation, and last-known-good behavior.

## Working Rules

- Keep project and scene data text-based and diffable.
- Prefer small vertical slices that leave `main` working.
- Update ADRs when changing architecture or backend choices.
- Update FDRs when changing feature behavior, command behavior, scene schema, or validation semantics.
- Route runtime state through the ECS-ish world instead of introducing renderer-specific or script-owned side channels.
- Script-defined ECS component and system types must use explicit non-reserved dotted ids. `machina.*` is engine-owned, and Machina does not infer a default project namespace.
- When adding a text-authored runtime resource, register it with the live reload path or document why it is intentionally not reloadable yet.
- Preserve last-known-good behavior for live reload. Failed reloads should produce diagnostics without destroying the running project state.
- For long-lived interactive state, use an allocator that can free replaced resources; avoid arena-backed state for reloadable worlds and scenes.
- For rendering changes, use deterministic offscreen verification before relying on visible-window inspection.
- For window-loop, surface, or live-reload changes in `machina run`, also run a bounded headful smoke test such as `mise machina run examples/minimal --frames 2`.
- Treat `examples/minimal/` as the smoke-test fixture; update it when the supported scene schema changes.
- Do not hide external backend APIs in scene, project, or scripting layers. Keep native dependency details behind engine-owned boundaries.

## Local Skills

- Use `.agents/skills/machina-render-verification` when changing rendering, shaders, scene-driven render data, or visual test expectations.
