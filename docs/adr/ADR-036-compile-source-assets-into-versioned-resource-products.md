# ADR-036: Compile source assets into versioned resource products

**Date:** 2026-07-21

## Context

Scrapbot currently decodes a material's PNG source directly while loading project resources and stores the resulting pixels inside that Material. This couples source-file formats, project loading, material identity, CPU memory, and GPU texture caching. Static meshes are limited to built-in or programmatically registered geometry, so adding glTF directly to scene loading would repeat the same coupling at a larger scale.

Source assets also have different lifecycle requirements from authored resource declarations. They may have external dependencies, expensive conversion work, importer settings and versions, multiple generated subresources, and recoverable failures. Reprocessing them on every run or inside ordinary render frames would violate Scrapbot's change-driven derived-state invariant.

## Decision

Treat files under `assets/` as immutable source inputs and compile them through registered importers into versioned products under ignored `.scrapbot/imported/` engine state. An import key includes the source and dependency content, importer identity and version, and normalized settings. `check`, `build`, and `run` ensure required imports before constructing the runtime registry; `scrapbot import` exposes the same operation explicitly through structured diagnostics. Product writes are atomic, and a failed reimport does not replace the last valid product.

Keep authored resource declarations under `resources/` as the persistent UUID authority. Texture and model declarations reference safe asset paths and importer settings. Their runtime registry entries retain generational handles and content versions, while imported products contain renderer-ready texture, geometry, material, and model data. Materials reference Texture UUIDs in project files and Texture handles at runtime instead of owning decoded source pixels. Runtime-created materials may still use explicitly supplied transient texture data through the scripting/native API.

Importers publish their dependencies and generated subresource keys in a manifest. A model's imported subresources derive stable identities from the parent model UUID plus retained semantic keys, not transient runtime indexes. File watching and hot reload enqueue only resources affected by a changed source or dependency. Render and editor caches consume resource versions and never scan the asset tree during ordinary frames.

The first model importer targets core static glTF 2.0 and GLB: triangle primitives, positions, normals, UV0, indices, node transforms, base-color/emissive material data, and PNG/JPEG images. Animation, skins, morph targets, compression extensions, and richer PBR features remain explicit later extensions to the importer and renderer contracts.

## Consequences

Source formats and conversion cost move out of runtime rendering, textures can be shared independently of materials, failed imports preserve a usable last-good product, and glTF can produce many related resources through one generic dependency-aware pipeline. Packaged builds can ship products without source assets, while source projects retain text-first UUID declarations and deterministic cache regeneration.

The engine gains an import manifest/database, artifact schemas and version migration, dependency invalidation, atomic cache writes, new Texture and Model registries, and editor import-status presentation. Changing importer output requires a version bump and reimport. Imported model subresource stability is more bookkeeping than indexing glTF arrays directly, and the initially supported glTF subset must reject unsupported required extensions with actionable diagnostics.
