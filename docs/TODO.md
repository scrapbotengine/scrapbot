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
- [x] Track renderable, camera, and light membership incrementally without full-world render extraction scans.
- [x] Add directional shadow maps with explicit shadow caster and receiver components.
- [x] Render world geometry into an HDR target with emissive materials, multi-scale bloom, and final ACES-style tone mapping.
- [ ] Expose camera exposure and bloom threshold, intensity, and scatter as project settings.
- [ ] Add light selection or clustered lighting beyond the initial fixed limits.
- [ ] Add visual comparison for offscreen render output.

## ECS UI

- [x] Add scene-defined UI layout and text components.
- [x] Incrementally synchronize appearing and disappearing UI entities into retained state.
- [x] Traverse retained UI hierarchy links in linear time during layout and painting.
- [x] Render panel and scalable MTSDF text paint commands after world geometry.
- [x] Auto-atlas named project TTF/OTF resources and retain embedded Inter as fallback.
- [x] Add row, column, and overlay hierarchy layout.
- [x] Add per-edge margins and padding, SDF-rounded backgrounds, horizontal and vertical stack components, and button controls.
- [x] Expose UI creation and mutation through Luau and native extensions.
- [x] Add pointer input, topmost-element hit testing, retained hover/active state, and button hover/press styling.
- [ ] Emit button activation and other UI command events.
- [x] Add nested paint/hit-test clipping and smooth vertical scroll areas.
- [x] Add proportional fill stacks with draggable separators and minimum pane sizes.
- [x] Add reusable per-axis fill, minimum-size, and fit-to-content layout policies.
- [x] Add reusable styled progress indicators.
- [x] Add reusable single-line input controls with selection, cursor commands, focus, and Tab traversal.
- [x] Add reusable boolean checkbox controls with SDF rendering and inspector bindings.
- [x] Add reusable selectable lists with full-width rows, UUID-backed selection, and composable scrolling.
- [x] Expose the complete public UI payload/state/mutation contract through the native extension ABI with fixed-layout payloads and bounded inline strings.
- [ ] Add canvas scaling and richer sizing/alignment.

## Project Runtime

- [x] Add standalone UUID-backed project resources with material resources as the first type.
- [x] Resolve scene material UUID references through the runtime registry and hot-reload changed resources.
- [ ] Add a real TOML parser or formalize the supported scene subset.
- [x] Add component indexes so sparse ECS component storage maps entities precisely.
- [x] Add polling hot reload for the default scene and project Luau script.
- [ ] Replace polling hot reload with platform file watching when runtime services exist.
- [x] Add structured command diagnostics and JSON output.

## ECS And Scripting

- [x] Add a shared frame time resource with raw and smoothed delta time.
- [x] Reflect component registry metadata into editor/tooling APIs.
- [x] Add scheduled systems with declared component access.
- [x] Add optional project-facing names for Luau systems and expose them in the profiler.
- [x] Show system provenance and full-width absolute callback-time bars in the live profiler.
- [x] Include editor, ECS UI, render preparation, and render submission systems in the live profiler.
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
- [x] Add project PNG textures with validation, WGPU upload, hot reload, and packaging.
- [ ] Expose textured materials through the project-local Odin extension API.

## Editor

- [x] Add a transient ECS-built editor shell toggled with Cmd/Ctrl+E.
- [x] Add a selectable, smoothly scrolling system list with five-frame updates over rolling 50-frame callback-time averages.
- [x] Keep the running project live across the complete available viewport with a dynamic camera aspect ratio.
- [x] Add a flush selectable entity list with smooth scrolling, scene/runtime provenance, and stable selection.
- [x] Add a smoothly scrolling component field/value inspector for the selected entity.
- [x] Add nearest-triangle entity picking in the live viewport.
- [x] Add functional world-space X/Y/Z translation handles for selected entities.
- [x] Add functional rotation rings and per-axis scale handles with W/E/R mode shortcuts.
- [x] Add XY/XZ/YZ plane handles, camera-plane free translation, and uniform XYZ scaling.
- [x] Add an ECS-owned World/Local gizmo orientation with viewport controls and stable drag bases.
- [x] Add an editor-origin ECS scene camera with RMB-captured WASD, Space, and Ctrl fly navigation.
- [x] Add live inspector editing for transform, camera, light, and custom Vec3 fields.
- [x] Add numeric validation, keyboard stepping, full-control scrubbing, and bounded inspector undo/redo.
- [x] Unify numeric, boolean, and transform-gizmo edits as UUID-addressed authoring transactions.
- [x] Add Play, Pause, fixed-frame Step, non-destructive Stop restoration, stopped-mode Undo/Redo, explicit Save, and destructive Revert controls.
- [x] Add Cmd/Ctrl editor, Play/Stop, and Pause/Step command shortcuts with project-input and fly-camera ownership guards.
- [x] Persist only semantic differences for dirty stopped-mode scene entities while preserving unchanged TOML text and excluding runtime entities.
- [x] Add UUID-addressed create, duplicate, rename, delete, runtime promotion, and component add/remove transactions with structural scene persistence.
- [x] Generalize component value editing across every currently registered Bool, String, Number, Vec2, Vec3, and Vec4 field shape.
- [x] Add a resource-reference picker and inline authoring for project material resources.
- [x] Commit dirty scene and resource files through one validated, recoverable project Save transaction.
- [ ] Add specialized enum, color, and entity-reference inspector pickers, followed by array and nested-value editing.

## Documentation And Examples

- [ ] Add ADR/FDR update guidance to contributor documentation.

## Testing And Diagnostics

- [x] Pin OLS and `odinfmt` with shared project configuration, mise tasks, and a staged-content pre-commit check.
- [ ] Apply a dedicated baseline `odinfmt` pass and promote format checking into the default test gate.
- [x] Add compile-time-gated world-integrity validation and seeded editor lifecycle state-machine coverage.
- [x] Add a large-scene persistence torture harness for mixed value/structural diffs, idempotent saves, runtime exclusion, Save/Undo/Redo/Revert savepoints, complete scene-component round trips, and failed-write preservation.
- [x] Inject project-save failures and crashes across staging, backup, installation, commit, rollback, and startup recovery.
- [x] Add structured runtime storage, allocator, and update-cost statistics.
- [x] Add deterministic entity/component churn invariants to the normal test suite.
- [x] Add an opt-in lifecycle-heavy CPU/RAM growth soak.
- [x] Add a Linux AddressSanitizer test lane.
- [x] Run bounded lifecycle growth thresholds in the default suite and Linux CI.
- [ ] Add OS resident-memory sampling for foreign-library and GPU allocations.
