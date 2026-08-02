# TODO

This file tracks current actionable engineering work. The broad product roadmap lives in [`README.md`](../README.md), detailed decisions live in ADRs and FDRs, and completed work lives in Git history.

## Rendering

- [ ] Maintain a repeatable 60 Hz adaptive-quality baseline matrix across representative integrated/discrete GPUs; record settled world, shadow, and post tiers. See [ADR-052](adr/ADR-052-coordinate-adaptive-render-quality-from-one-frame-budget.md).
- [ ] Compress Model v16 catalogs, material images, and virtual-Geometry pages with independently decodable page records; measure import time, product size, startup, and streaming cost on `impossible-archive` unhinged.
- [ ] Strip source assets from exported games and package the same validated runtime products used by development runs.
- [ ] Re-evaluate Metal multi-draw and benchmark virtual geometry after wgpu's native ICB paths land ([issue #61](https://github.com/scrapbotengine/scrapbot/issues/61)).
- [ ] Design baked/captured local reflection-probe resources, ECS volume components, probe selection/blending, and an editor bake workflow on top of global imported IBL.
- [ ] Add GPU-native compressed texture products for imported images.
- [ ] Add sorted glTF `BLEND` transparency, richer PBR extensions, animation, skins, morph targets, and compressed geometry. (`OPAQUE`, `MASK`, alpha cutoffs, and double-sided materials are supported.)
- [ ] Add a bounded GPU sort path for large transparent sets; project-shader transparency currently performs exact CPU back-to-front instance sorting.
- [ ] Add custom-vertex depth and shadow variants so displaced opaque geometry participates in the prepass and cascades without running a mismatched vertex contract.
- [ ] Surface WGSL compilation and pipeline-validation failures as structured project diagnostics instead of allowing wgpu-native's default uncaptured-error handler to abort.
- [ ] Add optional per-target post-processing, grids, axes, wireframe, and transparent presentation to embedded ECS viewports.
- [ ] Generalize retained-World viewport targets into explicitly addressable concurrent ECS worlds when multi-world runtime ownership exists.
- [ ] Replace aggregate asset polling with dependency-aware platform file watching that enqueues exact resource UUID reimports.
- [ ] Extend the camera's authored TAA/fast-AA/AO/SSR/bloom controls with ambient-occlusion radius/intensity/thickness, reflection distance/thickness/roughness, bloom threshold/intensity/scatter, and temporal history/quality; evaluate whether advanced overrides become a separate post-processing component or volume. (AO and SSR sample quality are available.)
- [ ] Add hierarchical-Z ray marching, rough-reflection filtering, and temporal confidence accumulation to screen-space reflections; keep the current bounded linear ray march as the portable baseline.
- [ ] Add per-object motion vectors so temporal antialiasing can reproject animated geometry exactly instead of relying on depth rejection and neighborhood clamping.
- [ ] Extend `scrapbot.volumetric_fog` with local fog volumes and explicit quality controls; evaluate a froxel path beyond the current half-resolution integration. See [ADR-038](adr/ADR-038-author-scene-environments-as-ecs-components.md).

## Project Runtime And Scripting

- [ ] Layer persistent action maps, rebinding, focus/consumption, and controller devices over the ECS input singleton snapshots.
- [ ] Replace the narrow TOML reader or formally specify its supported project-file subset.
- [ ] Replace polling hot reload with platform file watching when runtime services exist.
- [ ] Add target-native Luau, SDL3, and WGPU toolchains for cross-platform exports.
- [ ] Expose textured materials through the project-local Odin extension API.

## Editor

- [ ] Extend public dock spaces with same-group tab ordering, automatic empty-split collapse, floating windows, and persisted dock placement plus panel order and sizes. Panels and tabs already transfer across containers and create public resizable splits from enabled edges. See [ADR-045](adr/ADR-045-compose-docking-from-public-groups-and-layout.md).
- [ ] Add an opt-in runtime-entity browser policy on top of bounded, virtualized list rows.
- [ ] Add resizable dynamic-array schemas with inspector add, remove, and reorder controls.
- [ ] Extend project/native component schemas with enum choices so dynamic fields can use the reflected enum picker.
- [ ] Add transform snapping and multi-selection editing.
- [ ] Add a scalable picking broad phase or GPU identity pass before exact triangle tests.
- [ ] Add opt-in collision-aware editor fly-camera navigation on top of a scalable scene-query broad phase.

## Testing And Diagnostics

- [ ] Extend offscreen WGPU CI coverage from Metal to representative Vulkan and D3D12 adapters.
- [ ] Apply a baseline `odinfmt` pass and promote formatting audit into the default test gate.
- [ ] Add OS resident-memory sampling for foreign-library and GPU allocations.
- [ ] Define an opt-in same-adapter GPU regression policy after benchmark history establishes normal variance.
