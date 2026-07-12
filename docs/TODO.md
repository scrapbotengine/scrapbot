# TODO

## Rendering

- [x] Add a `wgpu-native` surface smoke backend.
- [x] Use the SDL3 window path to create a `wgpu-native` surface.
- [x] Replace the WGPU clear smoke with a simple triangle render loop.
- [x] Add a headless WGPU PNG framegrab path.
- [x] Replace the WGPU triangle loop with an ECS-driven rotating cube renderer.
- [x] Define the first renderable query boundary between ECS state and renderer backends.
- [x] Expand the WGPU renderer beyond the first cube renderable.
- [x] Expand the WGPU renderer beyond cube primitives.
- [x] Add full indexed geometry resources with cube, plane, icosphere, UV sphere, pyramid, and cylinder generators.
- [x] Add geometry/material ECS references and internal render reconciliation.
- [x] Cache geometry and material resources in the WGPU backend.
- [x] Add ECS ambient, directional, and point lights to the WGPU backend.
- [x] Add directional shadow maps with explicit shadow caster and receiver components.
- [ ] Add light selection or clustered lighting beyond the initial fixed limits.
- [ ] Add visual comparison for offscreen render output.

## Project Runtime

- [ ] Add a real TOML parser or formalize the supported scene subset.
- [x] Add component indexes so sparse ECS component storage maps entities precisely.
- [x] Add polling hot reload for the default scene and project Luau script.
- [ ] Replace polling hot reload with platform file watching when runtime services exist.
- [x] Add structured command diagnostics and JSON output.

## ECS And Scripting

- [x] Add a shared frame time resource with raw and smoothed delta time.
- [x] Reflect component registry metadata into editor/tooling APIs.
- [x] Add scheduled systems with declared component access.
- [x] Execute a project-local Luau entry script during `scrapbot run`.
- [x] Add Luau LSP metadata for the built-in `scrapbot` global.
- [x] Add a first Luau system bridge for project-local systems.
- [x] Add scene-defined custom component data for Luau systems.
- [x] Validate scene custom components against Luau-defined component schemas.
- [x] Add typed Luau component handles for query callbacks.
- [x] Add reflected Luau component schemas and generated typed component APIs.
- [x] Add an engine component registry for dotted component names.
- [x] Add deferred Luau spawn/despawn commands.
- [x] Add deferred Luau component add/remove commands.
- [x] Group project component storage by runtime component ID.
- [x] Add bulk Luau query views.
- [x] Add multi-component Luau queries.
- [x] Add typed multi-component Luau queries.
- [x] Add reusable Luau query objects.
- [x] Enforce declared component access for declared Luau systems.
- [x] Add write-back for declared `scrapbot.transform` payload mutation in Luau query systems.
- [x] Add write-back for declared project component payload mutation in Luau query systems.
- [x] Add readonly generated Luau payload types for query snapshots.
- [x] Add typed Luau schema markers for project component declarations.
- [x] Add library component registration for dotted component names.
- [x] Add a Luau analyzer check for example project scripts.
- [x] Add native Odin extension loading and hot reload.
- [x] Add project-declared native extension builds.
- [x] Package host-native games with project data and active extension artifacts.
- [ ] Add target-native Luau, SDL3, and WGPU toolchains for cross-platform exports.
- [x] Rebuild native extension sources during hot reload.
- [x] Add native ECS systems that participate in scheduling.
- [x] Execute conflict-free native systems in parallel.

## Editor

- [ ] Add an editor GUI toggle from a running project.
- [ ] Add an entity browser and component inspector.

## Documentation And Examples

- [ ] Add ADR/FDR update guidance to contributor documentation.
