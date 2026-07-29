# TODO

This file tracks current actionable engineering work. The broad product roadmap lives in [`README.md`](../README.md), detailed decisions live in ADRs and FDRs, and completed work lives in Git history.

## Rendering

- [ ] Design baked/captured local reflection-probe resources, ECS volume components, probe selection/blending, and an editor bake workflow on top of global imported IBL.
- [ ] Add GPU-native compressed texture products for imported images.
- [ ] Add sorted glTF `BLEND` transparency, richer PBR extensions, animation, skins, morph targets, and compressed geometry. (`OPAQUE`, `MASK`, alpha cutoffs, and double-sided materials are supported.)
- [ ] Add optional per-target post-processing, grids, axes, wireframe, and transparent presentation to embedded ECS viewports.
- [ ] Generalize retained-World viewport targets into explicitly addressable concurrent ECS worlds when multi-world runtime ownership exists.
- [ ] Replace aggregate asset polling with dependency-aware platform file watching that enqueues exact resource UUID reimports.
- [ ] Add imported mesh LODs and evaluate meshlets and richer submission against representative scenes.
- [ ] Extend the camera's authored TAA/fast-AA/AO/SSR/bloom controls with ambient-occlusion radius/intensity/thickness, reflection distance/thickness/roughness, bloom threshold/intensity/scatter, and temporal history/quality; evaluate whether advanced overrides become a separate post-processing component or volume. (AO and SSR sample quality are available.)
- [ ] Add hierarchical-Z ray marching, rough-reflection filtering, and temporal confidence accumulation to screen-space reflections; keep the current bounded linear ray march as the portable baseline.
- [ ] Add per-object motion vectors so temporal antialiasing can reproject animated geometry exactly instead of relying on depth rejection and neighborhood clamping.
- [ ] Extend `scrapbot.volumetric_fog` with local fog volumes and explicit quality controls; evaluate a froxel path beyond the current half-resolution integration. See [ADR-038](adr/ADR-038-author-scene-environments-as-ecs-components.md).
- [ ] Add Hi-Z, visibility, and LOD debug views.

## ECS UI

- [ ] Add project-defined named theme resources only if they can resolve explicitly without renderer state or stable-frame traversal. See [ADR-040](adr/ADR-040-resolve-ui-themes-into-component-values.md).

## Project Runtime And Scripting

- [ ] Layer persistent action maps, rebinding, focus/consumption, and controller devices over the ECS input singleton snapshots.
- [ ] Replace the narrow TOML reader or formally specify its supported project-file subset.
- [ ] Replace polling hot reload with platform file watching when runtime services exist.
- [ ] Add target-native Luau, SDL3, and WGPU toolchains for cross-platform exports.
- [ ] Expose textured materials through the project-local Odin extension API.

## Editor

- [ ] Add an opt-in runtime-entity browser policy on top of bounded, virtualized list rows.
- [ ] Add resizable dynamic-array schemas with inspector add, remove, and reorder controls.
- [ ] Extend project/native component schemas with enum choices so dynamic fields can use the reflected enum picker.
- [ ] Add transform snapping and multi-selection editing.
- [ ] Add a scalable picking broad phase or GPU identity pass before exact triangle tests.

## Testing And Diagnostics

- [ ] Extend offscreen WGPU CI coverage from Metal to representative Vulkan and D3D12 adapters.
- [ ] Apply a baseline `odinfmt` pass and promote formatting audit into the default test gate.
- [ ] Add OS resident-memory sampling for foreign-library and GPU allocations.
- [ ] Define an opt-in same-adapter GPU regression policy after benchmark history establishes normal variance.
