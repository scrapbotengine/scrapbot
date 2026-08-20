# TODO

This file tracks current actionable engineering work. The broad product roadmap lives in [`README.md`](../README.md), detailed decisions live in ADRs and FDRs, and completed work lives in Git history.

## Rendering

- [ ] Calibrate resident-Geometry tail quality and byte caps across representative scanned, hard-surface, foliage, and multi-primitive assets.
- [ ] Calibrate the automatic Conventional/Virtual Geometry crossover across qualified adapter classes and representative asset shapes while preserving ADR-054's stable layered policy.
- [ ] Partition or bound portable compact submission so visibility-table pressure cannot globally disable virtual submission or leave streamed resources undrawable; add an over-cap mixed-batch GPU fixture.
- [ ] Partition geometry storage bindings or use relative page offsets so portable vertex pulling can use residency beyond the currently correctness-bounded single-binding prefix; measure and reduce fragmentation-driven detail deferrals.
- [ ] Partition or clamp conventional shared geometry arenas to the adapter's maximum buffer size; the Virtual Wilds CPU-reference control currently requests a 512 MiB vertex arena on a 256 MiB adapter.
- [ ] Deduplicate virtual-Geometry page feedback by group before bounded GPU readback, then shrink the temporary 32,768-record demand lane while preserving zero-overflow moving high-detail views.
- [ ] Gate foreground and depth completeness in both the synthetic virtual-geometry lab and the external single-cliff regression across compact GPU and full-index reference captures.
- [ ] Maintain a repeatable 60 Hz adaptive-quality baseline matrix across representative integrated/discrete GPUs; record settled world, shadow, and post tiers. See [ADR-052](adr/ADR-052-coordinate-adaptive-render-quality-from-one-frame-budget.md).
- [ ] Evaluate exact portable cluster compaction or a non-vertex-pulling path when triangle-lane utilization and same-adapter profiles still miss the frame budget; preserve zero-hole fallback behavior.
- [ ] Compress Model v21 catalogs, material images, distance fields, and virtual-Geometry pages with independently decodable records; measure import time, product size, startup, and streaming cost on `impossible-archive` unhinged.
- [ ] Strip source assets from exported games and package the same validated runtime products used by development runs.
- [ ] Re-evaluate Metal multi-draw and benchmark virtual geometry after wgpu's native ICB paths land ([issue #61](https://github.com/scrapbotengine/scrapbot/issues/61)).
- [ ] Evaluate world-space AO, soft shadows, particles, and measured coarse-occlusion assistance as independent consumers of the incrementally scrolled world distance field. Retain HZB as primary visibility until profiles justify otherwise. See [ADR-055](adr/ADR-055-compile-mesh-distance-fields-offline.md).
- [ ] Design baked/captured local reflection-probe resources, ECS volume components, probe selection/blending, and an editor bake workflow on top of global imported IBL.
- [ ] Add GPU-native compressed texture products for imported images.
- [ ] Add mip-resident texture streaming so projects can use 2K–8K source images without eagerly expanding every complete RGBA8 mip chain on the GPU.
- [ ] Add sorted glTF `BLEND` transparency, richer PBR extensions, animation, skins, morph targets, and compressed geometry. (`OPAQUE`, `MASK`, alpha cutoffs, and double-sided materials are supported.)
- [ ] Add a bounded GPU sort path for large transparent sets; project-shader transparency currently performs exact CPU back-to-front instance sorting.
- [ ] Add Virtual Geometry submission for opaque project shaders; the current custom-surface path intentionally uses Conventional Geometry.
- [ ] Promote spectral surfaces into reusable water resources with authored water influences, water-body depth/shape, and adaptive quality; add simulation, foam, current, and deformation masks. See [FDR-003](fdr/FDR-003-pluggable-rendering-backends.md#25-generate-reusable-spectral-surfaces-for-project-shaders).
- [ ] Add custom-vertex depth and shadow variants so displaced opaque geometry participates in the prepass and cascades without running a mismatched vertex contract.
- [ ] Surface WGSL compilation and pipeline-validation failures as structured project diagnostics instead of allowing wgpu-native's default uncaptured-error handler to abort.
- [ ] Add optional per-target post-processing, grids, axes, wireframe, and transparent presentation to embedded ECS viewports.
- [ ] Generalize retained-World viewport targets into explicitly addressable concurrent ECS worlds when multi-world runtime ownership exists.
- [ ] Replace aggregate asset polling with dependency-aware platform file watching that enqueues exact resource UUID reimports.
- [ ] Extend the camera's authored TAA/fast-AA/AO/SSR/bloom controls with ambient-occlusion radius/intensity/thickness, reflection distance/thickness/roughness, bloom threshold/intensity/scatter, and temporal history/quality; evaluate whether advanced overrides become a separate post-processing component or volume. (AO and SSR sample quality are available.)
- [ ] Add hierarchical-Z ray marching, rough-reflection filtering, and temporal confidence accumulation to screen-space reflections; keep the current bounded linear ray march as the portable baseline.
- [ ] Add per-object motion vectors so temporal antialiasing can reproject animated geometry exactly instead of relying on depth rejection and neighborhood clamping.
- [ ] Extend `scrapbot.volumetric_fog` with local fog volumes and an explicit ray-sample quality control; evaluate a froxel path beyond the current scalable screen-space integration. See [ADR-038](adr/ADR-038-author-scene-environments-as-ecs-components.md).

## Project Runtime And Scripting

- [ ] Complete persistent finite Terrain resources, chunk Geometry ownership, background candidate meshing, and stale-result rejection on top of [ADR-062](adr/ADR-062-author-terrain-as-a-height-baseline-with-sparse-voxel-edits.md) and [FDR-014](fdr/FDR-014-voxel-terrain.md).
- [ ] Add time-budgeted/background scene preparation with project-visible preload/progress/cancellation while preserving ADR-061's active/staging ownership and transactional activation. See [ADR-058](adr/ADR-058-identify-scenes-by-uuid-and-replace-worlds-transactionally.md).
- [ ] Add configurable CPU/GPU scene-residency byte budgets, pressure-driven early eviction, and structured residency telemetry on top of dependency-indexed closures and delayed payload eviction. See [ADR-061](adr/ADR-061-index-scene-resource-dependencies-and-evict-unused-payloads.md).
- [ ] Design additive scene instances, explicit unload, persistent layers, and scoped cross-scene references. See [FDR-013](fdr/FDR-013-scene-assets-and-transitions.md).
- [ ] Add persistent project action maps, rebinding, controller snapshots, and per-player routing over the canonical physical-frame/action layer. See [ADR-059](adr/ADR-059-route-input-from-one-physical-frame.md).
- [ ] Replace the narrow TOML reader or formally specify its supported project-file subset.
- [ ] Replace polling hot reload with platform file watching when runtime services exist.
- [ ] Add target-native Luau, SDL3, and WGPU toolchains for cross-platform exports.
- [ ] Expose textured materials through the project-local Odin extension API.

## Editor

- [ ] Add viewport Raise, Lower, Smooth, Flatten, Add, and Subtract terrain brushes with bounded previews, Undo/Redo tile snapshots, transactional save/revert, and semantic tool-state cues. See [FDR-014](fdr/FDR-014-voxel-terrain.md).
- [ ] Track exact field-level runtime mutation provenance so play-mode editing can safely unlock fields disjoint from system writes. See [FDR-008](fdr/FDR-008-editor-shell.md).
- [ ] Reuse the rooted file-browser model for explicit open/save/import dialogs with consumer-owned capabilities, filename validation, overwrite confirmation, and asynchronous scan cancellation. See [ADR-060](adr/ADR-060-browse-files-through-rooted-metadata-models.md).
- [ ] Extend public dock spaces with same-group tab ordering, automatic empty-split collapse, floating windows, and persisted dock placement plus panel order and sizes. Panels and tabs already transfer across containers and create public resizable splits from enabled edges. See [ADR-045](adr/ADR-045-compose-docking-from-public-groups-and-layout.md).
- [ ] Add an opt-in runtime-entity browser policy on top of bounded, virtualized list rows.
- [ ] Add resizable dynamic-array schemas with inspector add, remove, and reorder controls.
- [ ] Extend project/native component schemas with enum choices so dynamic fields can use the reflected enum picker.
- [ ] Add a retained scene spatial index or canonical-geometry acceleration structure for CPU contact queries used by placement and collision-aware editor tools; WGPU entity selection now uses an on-demand identity pass.
- [ ] Add opt-in collision-aware editor fly-camera navigation on top of a scalable scene-query broad phase.

## Testing And Diagnostics

- [ ] Restore deterministic transition coverage in the virtual-geometry pressure GPU fixture after startup residency eliminated its hard-coded transition window.
- [ ] Auto-enable live debug whenever the windowed editor shell is visible, including the default source-project launch.
- [ ] Add scoped screen-space regions and a per-pixel geometry-identity image to live-debug captures when visibility records alone cannot isolate overlapping clusters ([ADR-053](adr/ADR-053-expose-live-debugging-through-a-transport-independent-service.md)).
- [ ] Replace map-per-record visibility CBOR with a versioned compact record-array schema; preserve the summary decoder and measure multi-frame artifact size before changing the transport contract ([ADR-053](adr/ADR-053-expose-live-debugging-through-a-transport-independent-service.md)).
- [ ] Add a generated Connect/protobuf transport when Odin schema tooling can preserve presence, oneofs, unknown fields, and deterministic evolution ([ADR-053](adr/ADR-053-expose-live-debugging-through-a-transport-independent-service.md)).
- [ ] Extend offscreen WGPU CI coverage from Metal to representative Vulkan and D3D12 adapters.
- [ ] Add reusable named camera-path and depth/meshlet-debug matrices for external example render regressions.
- [ ] Apply a baseline `odinfmt` pass and promote formatting audit into the default test gate.
- [ ] Add OS resident-memory sampling for foreign-library and GPU allocations.
- [ ] Define an opt-in same-adapter GPU regression policy after benchmark history establishes normal variance.
