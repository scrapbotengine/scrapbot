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
- [ ] Extend the camera's authored TAA/fast-AA/AO/SSR/bloom switches with ambient-occlusion radius/intensity/quality/thickness, reflection distance/thickness/roughness/quality, bloom threshold/intensity/scatter, temporal history/quality, and automatic/adaptive exposure controls; evaluate whether advanced overrides become a separate post-processing component or volume.
- [ ] Add hierarchical-Z ray marching, rough-reflection filtering, and temporal confidence accumulation to screen-space reflections; keep the current bounded linear ray march as the portable baseline.
- [ ] Add per-object motion vectors so temporal antialiasing can reproject animated geometry exactly instead of relying on depth rejection and neighborhood clamping.
- [ ] Add a separate authored volumetric-media component and renderer pass for height/distance fog, directional shadowed scattering, clustered point-light volumes, temporal stabilization, and explicit quality controls; do not grow `scrapbot.world_environment` into a general render-settings bag. See [ADR-038](adr/ADR-038-author-scene-environments-as-ecs-components.md).
- [ ] Add Hi-Z, visibility, and LOD debug views.

## ECS UI

- [ ] Emit reusable button activation and other UI command events.
- [ ] Add virtualized reusable list/tree views with filtering for large data sets.
- [ ] Add canvas scaling and richer sizing and alignment policies.

## Project Runtime And Scripting

- [ ] Layer persistent action maps, rebinding, focus/consumption, and controller devices over the ECS input singleton snapshots.
- [ ] Replace the narrow TOML reader or formally specify its supported project-file subset.
- [ ] Replace polling hot reload with platform file watching when runtime services exist.
- [ ] Add target-native Luau, SDL3, and WGPU toolchains for cross-platform exports.
- [ ] Expose textured materials through the project-local Odin extension API.

## Editor

- [ ] Add an opt-in runtime-entity browser policy on top of bounded, virtualized list rows.
- [ ] Add specialized enum, color, and entity-reference inspectors, followed by array and nested-value editing.
- [ ] Add searchable scene, resource, component, and system browsers.
- [ ] Add transform snapping and multi-selection editing.
- [ ] Add a scalable picking broad phase or GPU identity pass before exact triangle tests.

## Testing And Diagnostics

- [ ] Apply a baseline `odinfmt` pass and promote formatting audit into the default test gate.
- [ ] Add OS resident-memory sampling for foreign-library and GPU allocations.
- [ ] Add persisted benchmark trend reporting for representative simulation, editor, and rendering workloads (local profile and high-churn native-query runners now cover bounded same-machine comparisons).
