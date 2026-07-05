# TODO

## Landed Baseline

- [x] Text-first Zig engine with Luau scripting, project manifests, and TOML scenes.
- [x] Shared ECS runtime with generation-aware entities, component tables, system schedules, and script/native access.
- [x] Live reload for project metadata, scenes, scripts, and project-local native Zig modules.
- [x] WebGPU renderer with headful SDL windows, offscreen render verification, batching, shadows, and postprocess settings.
- [x] Built-in primitive geometry, surface materials, camera, light, and shadow components.
- [x] Engine-owned ECS UI primitives, editor shell, playback controls, system profiler, entity picking, translate gizmo, and component inspector.
- [x] Automated test coverage through `machina test`, render tests, benchmarks, Luau checks, and game-shaped fixtures.
- [x] Built-in component reference covering rendering, renderer settings, retained UI, runtime input resources, and example project-local components.
- [x] ADRs, FDRs, glossary, docs website, NOTICE, and local agent skills.

## Next Slice

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
- [ ] Add scrollable vbox and hbox containers as first-class primitives.
- [ ] Add dropdown, slider, checkbox, text area, and color picker controls.
- [ ] Add keyboard focus traversal for retained UI.
- [ ] Add text copy, paste, and clipboard support.
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
- [ ] Add static-link packaging for project-native Zig modules.
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
- [ ] Add `machina build` packaging for runnable game bundles.
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
