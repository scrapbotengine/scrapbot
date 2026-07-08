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
- [ ] Add file watching for scene hot reload.
- [ ] Add structured diagnostics for `scrapbot check`.

## ECS And Scripting

- [ ] Add a reflected component registry.
- [ ] Add scheduled systems with declared component access.
- [x] Execute a project-local Luau entry script during `scrapbot run`.
- [ ] Add Luau scripting for project-local systems.
- [ ] Add native Odin extension loading and hot reload.

## Editor

- [ ] Add an editor GUI toggle from a running project.
- [ ] Add an entity browser and component inspector.

## Documentation And Examples

- [ ] Add ADR/FDR update guidance to contributor documentation.
