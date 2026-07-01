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

## Working Rules

- Keep project and scene data text-based and diffable.
- Prefer small vertical slices that leave `main` working.
- Update ADRs when changing architecture or backend choices.
- Update FDRs when changing feature behavior, command behavior, scene schema, or validation semantics.
- For rendering changes, prefer deterministic offscreen verification before relying on visible-window inspection.
- Treat `examples/minimal/` as the smoke-test fixture; update it when the supported scene schema changes.
- Do not hide external backend APIs in scene, project, or scripting layers. Keep native dependency details behind engine-owned boundaries.

## Local Skills

- Use `.agents/skills/render-verification` when changing rendering, shaders, scene-driven render data, or visual test expectations.

