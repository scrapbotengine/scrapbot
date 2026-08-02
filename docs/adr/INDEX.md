# Architecture Decision Records

| # | Decision | Date |
|---|----------|------|
| [ADR-001](ADR-001-use-odin-for-engine-runtime.md) | Use Odin for the engine runtime | 2026-07-07 |
| [ADR-002](ADR-002-use-text-first-project-files.md) | Use text-first project files | 2026-07-07 |
| [ADR-003](ADR-003-use-pluggable-rendering-backends.md) | Use pluggable rendering backends | 2026-07-07 |
| [ADR-004](ADR-004-use-core-flags-for-command-options.md) | Use core:flags for command options | 2026-07-07 |
| [ADR-005](ADR-005-use-sdl3-for-platform-windows.md) | Use SDL3 for platform windows | 2026-07-07 |
| [ADR-006](ADR-006-use-luau-for-project-scripting.md) | Use Luau for project scripting | 2026-07-08 |
| [ADR-007](ADR-007-use-id-keyed-component-storage.md) | Use ID-keyed component storage | 2026-07-11 |
| [ADR-008](ADR-008-use-a-small-c-abi-for-native-extensions.md) | Use a small C ABI for native extensions | 2026-07-12 |
| [ADR-009](ADR-009-parallelize-access-declared-native-systems.md) | Parallelize access-declared native systems | 2026-07-12 |
| [ADR-010](ADR-010-keep-render-resources-outside-the-ecs.md) | Keep render resources outside the ECS | 2026-07-12 |
| [ADR-011](ADR-011-extract-ecs-lights-into-bounded-render-packets.md) | Extract ECS lights into bounded render packets | 2026-07-12 |
| [ADR-012](ADR-012-model-frame-time-as-a-world-resource.md) | Model frame time as a world resource | 2026-07-12 |
| [ADR-013](ADR-013-precompute-mtsdf-font-atlases.md) | Precompute MTSDF font atlases | 2026-07-12 |
| [ADR-014](ADR-014-compose-ui-from-boxes-and-controls.md) | Compose UI from boxes and controls | 2026-07-13 |
| [ADR-015](ADR-015-keep-editor-chrome-engine-owned.md) | Keep editor chrome engine-owned | 2026-07-13 |
| [ADR-016](ADR-016-track-entity-origin-in-the-runtime-world.md) | Track entity origin in the runtime world | 2026-07-13 |
| [ADR-017](ADR-017-use-cpu-triangle-rays-for-editor-picking.md) | Use CPU triangle rays for editor picking | 2026-07-13 |
| [ADR-018](ADR-018-render-editor-gizmos-as-screen-overlays.md) | Render editor gizmos as screen overlays | 2026-07-13 |
| [ADR-019](ADR-019-model-the-editor-scene-camera-as-a-transient-ecs-entity.md) | Model the editor scene camera as a transient ECS entity | 2026-07-13 |
| [ADR-020](ADR-020-keep-scroll-state-in-retained-ui-and-clip-on-the-gpu.md) | Keep scroll state in retained UI and clip on the GPU | 2026-07-13 |
| [ADR-021](ADR-021-model-editor-chrome-as-transient-ecs-ui.md) | Model editor chrome as transient ECS UI | 2026-07-14 |
| [ADR-022](ADR-022-record-editor-edits-as-runtime-commands.md) | Record editor edits as runtime commands (superseded by ADR-027) | 2026-07-14 |
| [ADR-023](ADR-023-identify-entities-with-project-wide-uuids.md) | Identify entities with project-wide UUIDs | 2026-07-14 |
| [ADR-024](ADR-024-update-derived-ecs-state-from-structural-changes.md) | Update derived ECS state from structural changes | 2026-07-14 |
| [ADR-025](ADR-025-use-one-public-ecs-ui-contract.md) | Use one public ECS UI contract | 2026-07-15 |
| [ADR-026](ADR-026-separate-authoring-persistence-from-runtime-playback.md) | Separate authoring persistence from runtime playback | 2026-07-15 |
| [ADR-027](ADR-027-use-authoring-transactions-for-editor-changes.md) | Use authoring transactions for editor changes | 2026-07-15 |
| [ADR-028](ADR-028-persist-structural-authoring-by-uuid-scoped-entity-blocks.md) | Persist structural authoring by UUID-scoped entity blocks | 2026-07-15 |
| [ADR-029](ADR-029-postprocess-hdr-world-before-ui.md) | Postprocess the HDR world before UI composition | 2026-07-16 |
| [ADR-030](ADR-030-identify-project-resources-by-uuid-outside-the-ecs.md) | Identify project resources by UUID outside the ECS | 2026-07-17 |
| [ADR-031](ADR-031-commit-project-save-as-one-recoverable-transaction.md) | Commit project Save as one recoverable transaction | 2026-07-17 |
| [ADR-032](ADR-032-separate-project-source-state-and-products.md) | Separate project source, engine state, and products | 2026-07-17 |
| [ADR-033](ADR-033-model-spatial-hierarchy-with-local-transforms-and-uuid-parents.md) | Model spatial hierarchy with local transforms and UUID parents | 2026-07-18 |
| [ADR-034](ADR-034-keep-gpu-visibility-backend-owned.md) | Keep GPU visibility backend-owned | 2026-07-19 |
| [ADR-035](ADR-035-model-runtime-input-as-ecs-singletons.md) | Model runtime input as ECS singletons | 2026-07-21 |
| [ADR-036](ADR-036-compile-source-assets-into-versioned-resource-products.md) | Compile source assets into versioned resource products | 2026-07-21 |
| [ADR-037](ADR-037-compose-embedded-worlds-through-ecs-ui-viewports.md) | Compose embedded worlds through ECS UI viewports | 2026-07-21 |
| [ADR-038](ADR-038-author-scene-environments-as-ecs-components.md) | Author scene environments as ECS components | 2026-07-22 |
| [ADR-039](ADR-039-keep-clustered-lighting-and-shadow-cascades-backend-owned.md) | Keep clustered lighting and shadow cascades backend-owned | 2026-07-22 |
| [ADR-040](ADR-040-resolve-ui-themes-into-component-values.md) | Resolve UI themes into explicit component values | 2026-07-28 |
| [ADR-041](ADR-041-compile-svg-icon-sets-into-mtsdf-resources.md) | Compile SVG icon sets into MTSDF resources | 2026-07-29 |
| [ADR-042](ADR-042-publish-ui-interactions-as-immutable-events.md) | Publish UI interactions as immutable events | 2026-07-29 |
| [ADR-043](ADR-043-model-responsive-ui-as-an-authored-canvas-transform.md) | Model responsive UI as an authored canvas transform | 2026-07-29 |
| [ADR-044](ADR-044-resolve-intrinsic-and-flex-ui-layout-in-retained-passes.md) | Resolve intrinsic and flex UI layout in retained passes | 2026-07-30 |
| [ADR-045](ADR-045-compose-docking-from-public-groups-and-layout.md) | Compose docking from public groups and layout | 2026-07-30 |
| [ADR-046](ADR-046-store-meshlets-with-geometry-resources.md) | Store meshlets with geometry resources | 2026-07-30 |
| [ADR-047](ADR-047-generate-imported-mesh-lods-in-asset-products.md) | Generate imported mesh LODs in asset products | 2026-07-31 |
| [ADR-048](ADR-048-suballocate-geometry-in-shared-wgpu-arenas.md) | Suballocate geometry in shared WGPU arenas | 2026-07-31 |
| [ADR-049](ADR-049-select-fully-resident-virtual-geometry-frontiers-on-the-gpu.md) | Select fully resident virtual Geometry frontiers on the GPU | 2026-07-31 |
| [ADR-050](ADR-050-page-virtual-geometry-payloads.md) | Page virtual Geometry payloads | 2026-07-31 |
| [ADR-051](ADR-051-wrap-runtime-assets-in-chunked-products.md) | Wrap runtime assets in chunked products | 2026-08-02 |
| [ADR-052](ADR-052-coordinate-adaptive-render-quality-from-one-frame-budget.md) | Coordinate adaptive render quality from one frame budget | 2026-08-02 |
