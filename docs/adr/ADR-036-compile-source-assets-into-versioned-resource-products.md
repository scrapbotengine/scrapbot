# ADR-036: Compile source assets into versioned resource products

**Date:** 2026-07-21

## Context

Scrapbot currently decodes a material's PNG source directly while loading project resources and stores the resulting pixels inside that Material. This couples source-file formats, project loading, material identity, CPU memory, and GPU texture caching. Static meshes are limited to built-in or programmatically registered geometry, so adding glTF directly to scene loading would repeat the same coupling at a larger scale.

Source assets also have different lifecycle requirements from authored resource declarations. They may have external dependencies, expensive conversion work, importer settings and versions, multiple generated subresources, and recoverable failures. Reprocessing them on every run or inside ordinary render frames would violate Scrapbot's change-driven derived-state invariant.

## Decision

Treat files under `assets/` as immutable source inputs and compile them through registered importers into versioned products under ignored `.scrapbot/imported/` engine state. An import key includes the source and dependency content, importer identity and version, and normalized settings. `check`, `build`, and `run` ensure required imports before constructing the runtime registry; `scrapbot import` exposes the same operation explicitly through structured diagnostics. Product writes are atomic, and a failed reimport does not replace the last valid product.

Keep authored resource declarations under `resources/` as the persistent UUID authority. Texture, model, and environment declarations reference safe asset paths and importer settings. Their runtime registry entries retain generational handles and content versions, while imported products contain renderer-ready texture, geometry, material, model, and image-based-lighting data. Materials reference Texture UUIDs in project files and Texture handles at runtime instead of owning decoded source pixels. Runtime-created materials may still use explicitly supplied transient texture data through the scripting/native API.

Importers fingerprint their source dependencies and publish generated products. A model scene component derives ECS node and primitive entities from the root entity UUID, Model UUID, and imported node/primitive indexes. Durable semantic keys across source reordering remain a follow-up; runtime storage indexes are never persisted. Explicit editor reimport is UUID-targeted and bypasses the cache only for the requested product; Reimport All forces the complete import set. Replaced and disappearing Models retire generated Geometry and Material handles that are no longer outputs. File watching and hot reload enqueue asset-driven reload work. Render and editor caches consume resource versions and never scan the asset tree during ordinary frames.

The environment importer validates 2:1 Radiance HDR panoramas and precomputes renderer-ready linear diffuse-irradiance and roughness-prefiltered specular cube maps. The project manifest selects one Environment UUID plus intensity, Y rotation, and exposure; no environment conversion or resource scan runs in ordinary frames.

The first model importer targets core static glTF 2.0 and GLB: triangle primitives, positions, normals, UV0, indices, TRS node transforms, and base-color/emissive material factors. Matrix-authored transforms, animation, skins, morph targets, compression extensions, and richer PBR features remain explicit later extensions to the importer and renderer contracts.

## Consequences

Source formats and conversion cost move out of runtime rendering, textures can be shared independently of materials, failed imports preserve a usable last-good product, and glTF can produce many related resources through one generic dependency-aware pipeline. Packaged builds include the products alongside project source assets in the first slice; the product boundary enables a later source-stripping mode. Source projects retain text-first UUID declarations and deterministic cache regeneration.

The engine gains an import manifest/database, artifact schemas and version migration, dependency invalidation, atomic cache writes, new Texture, Environment, and Model registries, and editor import-status presentation. Changing importer output requires a version bump and reimport. Imported model subresource stability is more bookkeeping than indexing glTF arrays directly, and the initially supported glTF subset must reject unsupported required extensions with actionable diagnostics.
