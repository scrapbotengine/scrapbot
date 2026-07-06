# TODO

## Landed Baseline

- [x] Text-first Zig engine with Luau scripting, project manifests, and TOML scenes.
- [x] Odin engine rewrite accepted as the target implementation direction.
- [x] Odin smoke build scaffold added beside the current Zig engine.
- [x] Odin `init` can create a checkable text project with the current starter scene.
- [x] Odin `build` can create a host-local bundle with project files, runtime, launcher, marker, and manifest.
- [x] Odin `check` can validate project metadata and referenced project files.
- [x] Odin `check` can validate first-pass scene structure and report entity/component counts.
- [x] Odin `check` can validate scene-authored engine component ids, fields, types, defaults, and renderer setting values.
- [x] Odin scene loading can materialize authored entities and typed component values into the runtime world.
- [x] Odin `check` can validate script/native-declared scene component schemas with first-pass static discovery.
- [x] Odin runtime has first-pass component registry and generation-aware entity identity.
- [x] Odin runtime has first-pass component storage and query iteration.
- [x] Odin runtime has first-pass system scheduling and deferred structural mutation.
- [x] Odin `check` can statically register Luau system declarations and validate phase schedules.
- [x] Odin `check` can report structured script registration and schedule diagnostics.
- [x] Odin `check` can load Luau scripts through the C ABI bridge and import component/system declarations.
- [x] Odin `step`, `bench`, and bounded `run` can execute Luau query/component-field systems against the Odin ECS world.
- [x] Odin Luau execution can process first-pass structural commands for spawn, add component, remove component, and despawn through deferred mutation flush/rollback.
- [x] Odin Luau execution supports direct entity vec3 get/set methods.
- [x] Odin Luau execution supports prepared query iteration and resolved-row component field access.
- [x] Odin Luau execution supports bulk f32/vec3 query views.
- [x] Odin Luau runtime bridge diagnostics include active system, component field, and runtime error context.
- [x] Odin `step` can validate projects and report deterministic frame/schedule summaries.
- [x] Odin `bench` can report validation/update timing with Odin Luau execution and pending render stats.
- [x] Odin `test` can discover test projects, validate test manifests, replay script-visible input resources, route retained scene UI commands/scroll, consume editor-chrome pointer input, replay editor play/pause and single-step buttons, replay first-pass editor entity-list/system-list/inspector scrolling, entity selection, inspector field selection, and splitter dragging, execute Luau-backed frame simulation, and evaluate first-pass field/editor assertions.
- [x] Odin `run` can validate projects and execute bounded hidden frame updates while rendering remains pending.
- [x] Odin render extraction can count renderables, batches, cameras, lights, and UI draw primitives.
- [x] Odin `render` and `render-test` can validate projects, run bounded frame simulation, check selected entities, and report pending backend render stats.
- [x] Odin `visual-test` can validate projects, expected/actual paths, selected entities, bounded frame simulation, and pending backend visual-comparison stats.
- [x] Odin `check` can statically register project-local native Odin component and system declarations from `native = "native/game.odin"`.
- [x] Odin runtime reports a structured runtime diagnostic when scheduled Odin-native systems reach the pending execution boundary.
- [x] Shared ECS runtime with generation-aware entities, component tables, system schedules, and script/native access.
- [x] Live reload for project metadata, scenes, scripts, and project-local native Zig modules.
- [x] WebGPU renderer with headful SDL windows, offscreen render verification, batching, shadows, and postprocess settings.
- [x] Built-in primitive geometry, surface materials, camera, light, and shadow components.
- [x] Engine-owned ECS UI primitives, editor shell, playback controls, system profiler, entity picking, translate gizmo, and component inspector.
- [x] Automated test coverage through `scrapbot test`, render tests, benchmarks, Luau checks, and game-shaped fixtures.
- [x] Built-in component reference covering rendering, renderer settings, retained UI, runtime input resources, and example project-local components.
- [x] ADRs, FDRs, glossary, docs website, NOTICE, and local agent skills.

## Next Slice

- [ ] Port remaining Scrapbot CLI commands from Zig to Odin.
- [x] Port first-pass project metadata loading and referenced-file validation from Zig to Odin.
- [x] Port first-pass project build packaging from Zig to Odin.
- [x] Port engine-owned scene component schema validation from Zig to Odin.
- [x] Port first-pass scene-to-runtime-world loading from Zig to Odin.
- [x] Port script-defined and native scene component registry validation from Zig to Odin.
- [x] Port first-pass ECS entity identity and component registry primitives from Zig to Odin.
- [x] Port first-pass ECS component storage and query iteration from Zig to Odin.
- [x] Port first-pass ECS schedules and deferred mutation from Zig to Odin.
- [x] Port first-pass script ECS registration and schedule validation from Zig to Odin.
- [x] Port first-pass structured script registration and schedule diagnostics from Zig to Odin.
- [x] Port Luau bridge-backed declaration loading from Zig to Odin.
- [x] Port first-pass Luau query/component-field callback execution from Zig to Odin.
- [x] Port first-pass Luau structural command callbacks from Zig to Odin.
- [x] Port direct Luau entity vec3 get/set callbacks from Zig to Odin.
- [x] Port prepared Luau query iteration and resolved-row field callbacks from Zig to Odin.
- [x] Port bulk f32/vec3 Luau query view callbacks from Zig to Odin.
- [x] Port detailed Luau runtime bridge diagnostics from Zig to Odin.
- [x] Port first-pass deterministic step command from Zig to Odin.
- [x] Port first-pass benchmark command from Zig to Odin.
- [x] Port first-pass test command discovery and manifest validation from Zig to Odin.
- [x] Port first-pass test command field assertion execution from Zig to Odin.
- [x] Port first-pass test command input resource replay from Zig to Odin.
- [x] Port first-pass retained scene UI command and scroll routing for Odin test replay.
- [x] Port first-pass editor chrome input ownership for Odin test replay.
- [x] Port first-pass editor playback button replay for Odin test replay.
- [x] Port first-pass editor entity-list selection replay for Odin test replay.
- [x] Port first-pass editor entity-list scroll replay for Odin test replay.
- [x] Port first-pass editor system-list scroll replay for Odin test replay.
- [x] Port first-pass editor inspector scroll replay for Odin test replay.
- [x] Port first-pass editor inspector field selection replay for Odin test replay.
- [x] Port first-pass editor splitter drag replay for Odin test replay.
- [x] Port first-pass editor inspector text editing replay for Odin test replay.
- [x] Port first-pass editor gizmo capture and drag replay for Odin test replay.
- [x] Port first-pass bounded run command parsing and validation from Zig to Odin.
- [x] Port first-pass renderer ECS extraction stats from Zig to Odin.
- [x] Port first-pass render/render-test command parsing and validation from Zig to Odin.
- [x] Port first-pass visual-test command parsing and validation from Zig to Odin.
- [x] Port first-pass project-local native Odin component/system declaration registration.
- [x] Port first-pass pending Odin-native system execution diagnostics.
- [x] Port first-pass Odin-native set-field system execution.
- [x] Port first-pass Odin-native lifecycle structural operations.
- [x] Port packaged `native_artifact` copying and build-manifest reporting to Odin `scrapbot build`.
- [x] Port SDL3 host-library discovery, copy, launcher search paths, and manifest reporting to Odin `scrapbot build`.
- [x] Port build-time Odin-native source compilation into packaged `native_artifact` output for `scrapbot build`.
- [x] Load packaged Odin native artifacts and execute first-pass query plus scalar field callbacks through the shared ECS schedule.
- [x] Port packaged Odin native vec3/string field callbacks and deferred structural callbacks through the native host API.
- [x] Load development-time `native = "native/game.odin"` sources that import `scrapbot:scrapbot_native` by rebuilding a dynamic artifact, registering it, and running native callbacks through the shared ECS schedule.
- [x] Port first-pass Odin native source reload transactions with last-known-good behavior for failed rebuilds.
- [x] Poll Odin native source reloads during bounded `scrapbot run --frames` execution.
- [x] Port first-pass Odin project metadata reload transactions and bounded `scrapbot run --frames` polling with last-known-good behavior.
- [x] Port first-pass Odin script source reload transactions and bounded `scrapbot run --frames` polling with last-known-good behavior.
- [x] Port first-pass Odin scene source reload transactions and bounded `scrapbot run --frames` polling with last-known-good behavior.
- [ ] Port remaining unbounded/window-loop reload diagnostics from Zig to Odin.
- [ ] Replace the vendored Zig `wgpu-native` binding with Odin C ABI bindings.
- [ ] Port Odin render image output, offscreen image verification, and hidden headful smoke paths.
- [ ] Complete unbounded/window-loop Odin project/scene/script/native live reload integration and replacement of the Zig reload path.
- [ ] Remove Zig build/test/dependency surfaces after Odin parity is verified.
- [ ] Add scroll support to inspector component vgroups.
- [ ] Add typed inspector controls for floats, ints, strings, and enums.
- [ ] Add editor controls to add and remove components on the selected entity.
- [ ] Add editor controls to spawn and despawn entities.
- [ ] Persist inspector edits back to text scene files.
- [ ] Add validation diagnostics for failed inspector edits.
- [ ] Add visual tests for inspector editing widgets.
- [ ] Polish selected-entity header truncation and copy behavior.
- [ ] Keep `examples/ui_gallery/` current with inspector control primitives.

## Editor Core

- [ ] Add a searchable entity browser for large worlds.
- [ ] Add hierarchy/grouping support for entity browsing.
- [ ] Add multi-selection and batch component editing.
- [ ] Add rotation and scale gizmos.
- [ ] Add local-space, world-space, and snapping modes for gizmos.
- [ ] Add hover styling and axis constraints for transform gizmos.
- [ ] Add undo grouping for drags and multi-field edits.
- [ ] Add editor transaction persistence across live reloads.
- [ ] Add ID-buffer or accelerated picking for precise selection.
- [ ] Add selectable non-renderable entities.

## UI System

- [ ] Formalize reusable editor controls as UI component patterns.
- [ ] Add margin, padding, border, and gap layout primitives.
- [ ] Add scrollable vgroup and hgroup containers as first-class primitives.
- [ ] Add dropdown, slider, checkbox, text area, and color picker controls.
- [ ] Add keyboard focus traversal for retained UI.
- [ ] Add text copy, paste, and clipboard support.
- [ ] Add SDF-based font rendering for scalable UI and editor text.
- [ ] Add disabled, hovered, active, focused, and invalid visual states.
- [ ] Add reusable UI themes and density settings.
- [ ] Add controller input support after keyboard and mouse stabilize.

## ECS And Scheduling

- [ ] Design parallel system scheduling from declared component access.
- [ ] Decide how Luau systems run across one or more VM instances.
- [ ] Add scheduler diagnostics for dependency conflicts.
- [ ] Add explicit system ordering constraints where access sets are insufficient.
- [ ] Add component lifecycle hooks or replacement rules.
- [ ] Add native component lifecycle rules for renderer-owned side resources.
- [ ] Add query filters for optional, changed, added, and removed components.
- [ ] Add SoA storage benchmarks for hot ECS paths.
- [ ] Add world snapshot and diff utilities for tests and tools.
- [ ] Expose safe bulk mutation APIs beyond f32 and vec3 query views.

## Scripting And Native Extensions

- [ ] Improve Luau diagnostics for typed query and component declaration failures.
- [ ] Add Luau type definitions for new editor and UI APIs.
- [ ] Add richer script reload diagnostics in the editor UI.
- [ ] Add static-link packaging for project-native modules after the Odin native-module contract is designed.
- [ ] Add project-native examples for custom components and systems.
- [ ] Add native API helpers for additional field types.
- [ ] Decide how script and native package namespaces are distributed.
- [ ] Document Luau performance guidance with measured examples.
- [ ] Add scripted editor extension points after core editor APIs settle.

## Rendering

- [ ] Add mesh asset import and asset-cache lifecycle.
- [ ] Add texture assets and texture-backed materials.
- [ ] Add material variants beyond flat surface color.
- [ ] Add render resource lifetime tracking for hot reload.
- [ ] Add frustum culling and renderer visibility diagnostics.
- [ ] Add light selection rules beyond the first directional light.
- [ ] Add multiple shadow-casting lights.
- [ ] Add scene cameras with editor camera override behavior.
- [ ] Add render debug views for batches, shadows, and picking.
- [ ] Add platform-specific renderer backend diagnostics.

## Project Model And Builds

- [ ] Decide scene edit persistence and formatting rules.
- [ ] Add asset references to text scene and project files.
- [ ] Add project templates for common game shapes.
- [ ] Add `scrapbot build` packaging for runnable game bundles.
- [ ] Add static native-link builds for restricted targets.
- [ ] Add project settings for default window and render quality.
- [ ] Add stable generated-file and cache cleanup commands.
- [ ] Add migration/versioning rules for scene schema changes.
- [ ] Add package/library dependency metadata.
- [ ] Document project directory conventions end to end.

## Testing And Tooling

- [ ] Add headful smoke coverage for editor selection and gizmo paths.
- [ ] Add screenshot assertions for editor layout regressions.
- [ ] Add benchmark thresholds or trend reporting.
- [ ] Add tests for scene edit persistence once implemented.
- [ ] Add fuzz-style tests for component reflection and field parsing.
- [ ] Add fixture coverage for invalid native extension reloads.
- [ ] Add docs checks to the default validation workflow.
- [ ] Add CI workflow once the repository is ready for remote checks.
- [ ] Keep agent rules synchronized with new architectural decisions.
- [ ] Keep ADRs and FDRs updated as TODO items graduate into designs.

## Later Big Swings

- [ ] Build a real dockable editor workspace.
- [ ] Add an asset browser and import pipeline UI.
- [ ] Add prefab or scene-instancing support.
- [ ] Add physics integration through ECS components.
- [ ] Add animation clips, skeletal meshes, and state machines.
- [ ] Add audio resources and runtime audio components.
- [ ] Add networking primitives for multiplayer experiments.
- [ ] Add terrain or large-world streaming primitives.
- [ ] Add editor plugins authored with the same ECS and UI model.
- [ ] Define the console and mobile publishing story.
