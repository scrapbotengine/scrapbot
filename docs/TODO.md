# TODO

## Rendering

- [x] Add a `wgpu-native` surface smoke backend.
- [x] Use the SDL3 window path to create a `wgpu-native` surface.
- [x] Replace the WGPU clear smoke with a simple triangle render loop.
- [x] Add a headless WGPU PNG framegrab path.
- [x] Replace the WGPU triangle loop with an ECS-driven rotating cube renderer.
- [x] Define the first renderable query boundary between ECS state and renderer backends.
- [x] Expand the WGPU renderer beyond the first cube renderable.
- [ ] Expand the WGPU renderer beyond cube primitives.
- [ ] Add visual comparison for offscreen render output.

## Project Runtime

- [ ] Add a real TOML parser or formalize the supported scene subset.
- [x] Add component indexes so sparse ECS component storage maps entities precisely.
- [x] Add polling hot reload for the default scene and project Luau script.
- [ ] Replace polling hot reload with platform file watching when runtime services exist.
- [ ] Add structured diagnostics for `scrapbot check`.

## ECS And Scripting

- [ ] Add a reflected component registry.
- [ ] Add scheduled systems with declared component access.
- [x] Execute a project-local Luau entry script during `scrapbot run`.
- [x] Add Luau LSP metadata for the built-in `scrapbot` global.
- [x] Add a first Luau system bridge for project-local systems.
- [x] Add scene-defined custom component data for Luau systems.
- [x] Validate scene custom components against Luau-defined component schemas.
- [x] Add typed Luau component handles for query callbacks.
- [ ] Add reflected Luau component schemas and generated typed component APIs.
- [ ] Add an engine/library component registry for dotted component names.
- [ ] Add a Luau analyzer check for example project scripts.
- [ ] Add native Odin extension loading and hot reload.

## Editor

- [ ] Add an editor GUI toggle from a running project.
- [ ] Add an entity browser and component inspector.

## Documentation And Examples

- [ ] Add ADR/FDR update guidance to contributor documentation.
