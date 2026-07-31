# Source Map

**Last verified:** 2026-07-31

| Path | Responsibility | Important boundaries |
| --- | --- | --- |
| `src/scrapbot_cli/main.odin` | CLI entry point and command dispatch. | Human/JSON diagnostics delegate into engine packages. |
| `src/scrapbot/scrapbot.odin` | Runtime composition, native/Luau scheduling, profiling, project load/run orchestration. | Joins registries, executor, resources, renderer, and hot reload. |
| `src/scrapbot/shared/` | Cross-package POD types, UUIDs, transforms, camera math, public world shapes, and canonical UI theme vocabulary/resolution. | Avoid backend-owned objects and allocator-sensitive ABI leakage. Theme recipes may produce only ordinary public UI component values. |
| `src/scrapbot/component/` | Component registry and generated Luau declarations. | Canonical component names, ownership, storage kind, lifecycle, and field schemas. |
| `src/scrapbot/ecs/` | World storage, typed mutation, commands, authoring snapshots, hierarchy, integrity, UI storage, and bounded immutable UI event history. | All mutation must preserve indexes and publish structural/render/UI invalidation. Event readers never mutate or drain the history. |
| `src/scrapbot/project/` | Project/scene parsing, UI theme authoring resolution, resource discovery, fonts, configuration, recoverable save transaction. | Persistent source identity and validation. Theme directives are consumed before explicit component fields. |
| `src/scrapbot/asset_import/` | Incremental source-asset importers, atomic products, SVG-to-MTSDF icon compilation, texture mips, static glTF decoding/LOD simplification, and HDR-to-IBL preprocessing. | Source/dependency/settings fingerprints and versioned `.scrapbot/imported/` products; never ordinary-frame work. |
| `src/scrapbot/resources/` | Runtime geometry/texture/environment/icon-set/model/material/font/UI-theme registries, generational handles, imported/generated LOD attachment, and resource-owned meshlet/hierarchy construction. | Shared descriptions outside ECS; LOD, meshlet, and hierarchy data share exact Geometry lifetime/versioning; UI/backend caches consume render-resource versions, while theme versions serve explicit composition and editor inspection only. |
| `native/clusterlod/`, `third_party/meshoptimizer/` | Narrow Scrapbot C bridge plus pinned upstream geometry simplification, clustering, crack-aware cluster-LOD, and bounds implementation. | Model LOD simplification runs only during invalidated import; hierarchy construction runs only at Geometry registration/replacement; neither is ordinary-frame work. |
| `src/scrapbot/schedule/` | Access-derived plan and native worker executor. | Native parallel batches, conflicts, and serial barriers. |
| `src/scrapbot/script/` | Luau VM, public APIs, schemas, queries, write-back, UI theme/component composition, UI event snapshots, generated-type integration. | Theme resolution returns mutable ordinary component maps; event cursors are per consumer; deferred lifecycle and declared-write enforcement remain at attachment. |
| `src/scrapbot/extension_api/` | Raw C-compatible native extension ABI. | Fixed layouts and callbacks only, including host-owned UI theme resolution and bounded UI event copies into caller buffers. |
| `src/scrapbot/extension/` | Idiomatic Odin wrapper for extension authors. | Typed descriptors, UI theme recipes, and payloads over the raw ABI. |
| `src/scrapbot/native/` | Native extension building, loading, registration, callbacks, UI theme/component bridging. | Host validation, dynamic-library lifetime, and per-system command buffers. |
| `src/scrapbot/ui/` | Retained ECS UI, intrinsic/flex/dock layout, interaction, editor ECS composition, runtime component-payload inspection/bindings, diagnostics, fonts. | Layout and paint share active-font line breaking; wrapped flex and direct-child dock-tab work are bounded and revision-driven. Dock transfers mutate public UUID parents and publish generic events. Editor recipes and workspace groups consume the shared public contract; editor meaning stays in bindings/orchestration. |
| `src/scrapbot/render/` | Backend interface, null backend, surface/offscreen WGPU rendering, shared geometry arenas, GPU-driven object/meshlet visibility and indirect submission, picking, gizmos, embedded UI viewports, postprocess, and bounded profile collection. | Backend-neutral inputs; WGPU owns geometry-versioned arena ranges, capability-gated draw state, pooled adaptive viewport targets, isolated resource-preview scenes, optional capture readback, and tagged asynchronous timing/visibility readbacks. |
| `src/scrapbot/platform/` | SDL window/input/cursor integration for visible runs. | OS events are translated into engine-owned input snapshots; offscreen WGPU does not initialize this boundary. |
| `src/scrapbot/hot_reload.odin` | Project source/product change detection and safe runtime replacement. | Failed reload retains last-good runtime/world. |
| `src/scrapbot/playback.odin` | Play/Stop baseline capture and restoration. | Restores ECS/resource authoring state without reloading code. |
| `src/scrapbot/scene_*.odin`, `project_save.odin` | Scene serialization, semantic/structural patching, project-wide persistence. | Stable UUID targeting and recoverable multi-file commits. |
| `src/scrapbot/package.odin` | Packaged-project product assembly. | Separates source state from build products. |
| `docs/adr/`, `docs/fdr/`, `docs/architecture/` | Decisions, feature contracts, and current source map. | Keep rationale, behavior, and inventory distinct. |
| `docs-website/` | Public user documentation. | Canonical user-facing APIs and workflows. |
| `tools/analyze_render_profile.mjs`, `tools/profile_resolution_sweep.mjs`, `tools/run_gpu_benchmarks.mjs`, `tools/compare_gpu_benchmarks.mjs`, `tools/test_gpu_offscreen.mjs` | Agent-oriented render-profile analysis, bounded pixel-cost sweeps, historical benchmark bundles/comparison, and artifact-preserving offscreen GPU acceptance. | Consume or orchestrate bounded renderer runs; never participate in ordinary engine frames. Hardware histories compare only adapter- and dimension-compatible evidence. |

## Dependency direction

- `shared` defines neutral data used across engine packages.
- `component`, `ecs`, `project`, and `resources` define runtime data and ownership.
- `script` and `native` adapt project-authored behavior onto those contracts.
- `ui` and `render` consume ECS/resources while retaining derived state behind explicit invalidation.
- the root runtime composes lifetimes and frame order; the CLI remains outside engine internals.

Avoid importing renderer/backend details into public ECS components, project resources, scripting payloads, or native ABI types.
