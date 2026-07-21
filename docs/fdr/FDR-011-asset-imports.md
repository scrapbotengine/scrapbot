# FDR-011: Asset imports

**Status:** In Progress
**Last reviewed:** 2026-07-21

## Overview

Asset imports turn artist-authored texture and model files under `assets/` into validated, renderer-ready project resources. Imports are incremental, reproducible, inspectable in the editor, and shared by project checking, development runs, and packaged builds.

## Behavior

- Texture resources import PNG sources with explicit color-space and mip-generation settings.
- Material resources reference reusable Texture resources by UUID rather than embedding source paths.
- Model resources import static glTF 2.0 `.gltf` and `.glb` files, including triangle geometry, TRS node transforms, and base-color and emissive material factors. glTF image textures are rejected until they can become proper Texture resources.
- Project checking, building, and running automatically import products that are absent or stale. `scrapbot import` performs the same work explicitly and reports structured per-resource results.
- Imported products and manifests are generated under ignored project state. They are never hand-authored or committed as source authority.
- Import validity includes source and dependency contents, settings, and importer version. Unchanged resources reuse their prior products without decoding or rebuilding them.
- A failed reimport reports an actionable error and preserves the last valid product. A project cannot silently start with a stale product when no valid product exists.
- Explicit editor reimport targets one Texture or Model UUID without restarting Luau/native code; **Reimport All** forces every declared imported product. Automatic hot reload still uses the project asset stamp and importer cache until the platform watcher replaces polling. Ordinary simulation and render frames never scan the asset tree.
- The editor's resource browser lists textures and models alongside materials. Its inspector exposes the source dependency, product kind and byte size, warnings/errors, and current import state. Textures render directly on the GPU with aspect-preserving fit. Models render their imported hierarchy, while Materials render on an isolated lit icosphere preview scene. All three use the public ECS viewport component and independently sized pooled targets; interactive 3D previews support orbit, zoom, and reset.
- Reimport updates a live resource slot in place and reconciles affected model roots. Generated Geometry and Material products that disappear from a replaced or removed Model are retired with generation bumps, so stale handles cannot remain usable.
- Imported models initially exclude animation, skins, morph targets, compressed geometry, and advanced material extensions; unsupported required glTF features fail clearly.

## Design Decisions

### 1. Separate source assets from imported products

**Decision:** Keep source files in `assets/`, UUID-backed import recipes in `resources/`, and generated products in ignored engine state.
**Why:** Artist sources, text-first project identity, and platform/runtime-ready data have different ownership and lifecycle requirements. See ADR-032 and ADR-036.
**Tradeoff:** Source projects manage a derived cache and importer versioning.

### 2. Make textures first-class resources

**Decision:** Give textures persistent UUIDs and runtime handles, and let materials reference them.
**Why:** Textures need sharing, independent reload/versioning, import settings, previews, and future compression without duplicating decoded pixels in every material.
**Tradeoff:** Existing material texture paths require a breaking migration to Texture resources.

### 3. Import glTF as a related resource bundle

**Decision:** Preserve one authored Model UUID while publishing imported geometry, material, and node subresources beneath it. Model scene components reconcile these into derived ECS node/primitive entities.
**Why:** A glTF file is a graph with multiple reusable products, not one mesh blob.
**Tradeoff:** Reimport must eventually retain semantic subresource identity across source edits and report removed outputs. The first implementation derives child identity from model/root identity plus node and primitive indexes.

### 4. Keep importing change-driven and recoverable

**Decision:** Fingerprint declared dependencies, import before runtime bootstrap, and atomically replace products only after complete validation.
**Why:** Ordinary frames must stay free of filesystem scans and a broken source edit must not destroy the last usable imported data.
**Tradeoff:** Development state records both the current source fingerprint and last-good product.

### 5. Keep editor import actions targeted

**Decision:** Route Reimport through an explicit runtime callback keyed by resource UUID, and keep the resource browser UI as a consumer of ordinary ECS UI buttons, panels, stacks, and fields.
**Why:** An artist should be able to recover or refresh one asset without rebuilding scripts, native extensions, the scene world, or unrelated resources. The editor must not become a second widget or rendering system.
**Tradeoff:** The current polled automatic hot-reload path remains coarser than the explicit action until dependency-aware platform file watching lands.

### 6. Preview resources through the public viewport path

**Decision:** Resolve viewport resource UUIDs across Texture, Model, and Material registries. Render Models and Materials through isolated renderer-owned preview scenes, render Textures through a direct GPU pass, and cache each stable target by its exact resource and presentation revisions.
**Why:** Asset inspection should show the real renderer product without creating editor-private drawing code or spawning preview-only entities into the project's active ECS world.
**Tradeoff:** Preview scenes are derived renderer state rather than independently simulated ECS worlds. The initial pool is bounded to eight targets and 1024 pixels per axis.

## Related

- **ADRs:** ADR-002, ADR-010, ADR-024, ADR-030, ADR-031, ADR-032, ADR-036, ADR-037
- **FDRs:** FDR-002, FDR-003, FDR-008, FDR-009

## Open Questions

- Which compressed texture target should follow RGBA8 products first: BC, ASTC, ETC2, or KTX2/Basis Universal?
- When should complete model instances become unpackable persistent scene hierarchies?
- Which glTF material extensions should become native Scrapbot material fields first?
