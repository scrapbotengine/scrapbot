# Source Map

**Last verified:** 2026-07-29

| Path | Responsibility | Important boundaries |
| --- | --- | --- |
| `src/scrapbot_cli/main.odin` | CLI entry point and command dispatch. | Human/JSON diagnostics delegate into engine packages. |
| `src/scrapbot/scrapbot.odin` | Runtime composition, native/Luau scheduling, profiling, project load/run orchestration. | Joins registries, executor, resources, renderer, and hot reload. |
| `src/scrapbot/shared/` | Cross-package POD types, UUIDs, transforms, camera math, public world shapes, and canonical UI theme vocabulary/resolution. | Avoid backend-owned objects and allocator-sensitive ABI leakage. Theme recipes may produce only ordinary public UI component values. |
| `src/scrapbot/component/` | Component registry and generated Luau declarations. | Canonical component names, ownership, storage kind, lifecycle, and field schemas. |
| `src/scrapbot/ecs/` | World storage, typed mutation, commands, authoring snapshots, hierarchy, integrity, UI storage. | All mutation must preserve indexes and publish structural/render/UI invalidation. |
| `src/scrapbot/project/` | Project/scene parsing, UI theme authoring resolution, resource discovery, fonts, configuration, recoverable save transaction. | Persistent source identity and validation. Theme directives are consumed before explicit component fields. |
| `src/scrapbot/asset_import/` | Incremental source-asset importers, atomic products, SVG-to-MTSDF icon compilation, texture mips, static glTF decoding, and HDR-to-IBL preprocessing. | Source/dependency fingerprints and versioned `.scrapbot/imported/` products; never ordinary-frame work. |
| `src/scrapbot/resources/` | Runtime geometry/texture/environment/icon-set/model/material/font registries and generational handles. | Shared descriptions outside ECS; UI and backend caches consume versions. |
| `src/scrapbot/schedule/` | Access-derived plan and native worker executor. | Native parallel batches, conflicts, and serial barriers. |
| `src/scrapbot/script/` | Luau VM, public APIs, schemas, queries, write-back, UI theme/component composition, generated-type integration. | Theme resolution returns mutable ordinary component maps; deferred lifecycle and declared-write enforcement remain at attachment. |
| `src/scrapbot/extension_api/` | Raw C-compatible native extension ABI. | Fixed layouts and callbacks only, including host-owned UI theme resolution into caller buffers. |
| `src/scrapbot/extension/` | Idiomatic Odin wrapper for extension authors. | Typed descriptors, UI theme recipes, and payloads over the raw ABI. |
| `src/scrapbot/native/` | Native extension building, loading, registration, callbacks, UI theme/component bridging. | Host validation, dynamic-library lifetime, and per-system command buffers. |
| `src/scrapbot/ui/` | Retained ECS UI, interaction, editor ECS composition, runtime component-payload inspection/bindings, diagnostics, fonts. | Editor recipes consume the shared composition contract and resolve to ordinary public components before storage. Generic mechanics stay public; editor meaning stays in bindings/orchestration. Component cards may not be hand-authored per type. |
| `src/scrapbot/render/` | Backend interface, null backend, surface/offscreen WGPU rendering, GPU-driven visibility, picking, gizmos, embedded UI viewports, postprocess, and bounded profile collection. | Backend-neutral inputs; WGPU owns GPU state, pooled adaptive viewport targets, isolated resource-preview scenes, caches, optional capture readback, and tagged asynchronous timing readbacks. |
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
