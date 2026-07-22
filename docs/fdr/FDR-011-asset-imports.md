# FDR-011: Asset imports

**Status:** In Progress
**Last reviewed:** 2026-07-22

## Overview

Asset imports turn artist-authored texture, model, and HDR environment files under `assets/` into validated, renderer-ready project resources. Imports are incremental, reproducible, inspectable in the editor, and shared by project checking, development runs, and packaged builds.

## Behavior

- Texture resources import PNG sources with explicit color-space and mip-generation settings.
- Environment resources import 2:1 Radiance `.hdr` sources. The importer preserves a source-resolution linear RGBA16F panorama for an opt-in background and builds separate diffuse irradiance and roughness-prefiltered specular cubes; ordinary frames never decode or reconvolve the source panorama.
- Material resources reference reusable Texture resources by UUID rather than embedding source paths.
- Model resources import static glTF 2.0 `.gltf` and `.glb` files, including triangle geometry, TRS node transforms, metallic-roughness material factors, normal and occlusion strengths, emissive factors, opaque and alpha-cutout materials, double-sided surfaces, and base-color, metallic-roughness, normal, occlusion, and emissive images. Images may be embedded in GLB buffer views, encoded as base64 data URIs, or stored at safe relative paths beside the model.
- Imported images become owned mipmapped texture payloads on the Model's generated Material resources. The WGPU material path renders them with GGX direct lighting, tangent-free derivative normal mapping, ambient diffuse/specular response, HDR emission, anisotropic trilinear sampling, bloom, and tone mapping.
- Project checking, building, and running automatically import products that are absent or stale. `scrapbot import` performs the same work explicitly and reports structured per-resource results.
- Imported products and manifests are generated under ignored project state. They are never hand-authored or committed as source authority.
- Import validity includes source and dependency contents, settings, and importer version. Unchanged resources reuse their prior products without decoding or rebuilding them.
- A failed reimport reports an actionable error and preserves the last valid product. A project cannot silently start with a stale product when no valid product exists.
- Explicit editor reimport targets one Texture, Model, or Environment UUID without restarting Luau/native code; **Reimport All** forces every declared imported product. Automatic hot reload still uses the project asset stamp and importer cache until the platform watcher replaces polling. Ordinary simulation and render frames never scan the asset tree.
- The editor's resource browser lists textures, environments, and models alongside materials. Its inspector exposes the source dependency, product kind and byte size, warnings/errors, and current import state. Environment inspection reports the derived cube-map shape, and the selected project environment lights ordinary world and model/material preview rendering. Textures render directly on the GPU with aspect-preserving fit. Models render their imported hierarchy, while Materials render on an isolated lit icosphere preview scene. All previews use the public ECS viewport component and independently sized pooled targets; interactive 3D previews support orbit, zoom, and reset.
- Reimport updates a live resource slot in place and reconciles affected model roots. Generated Geometry and Material products that disappear from a replaced or removed Model are retired with generation bumps, so stale handles cannot remain usable.
- Imported models initially exclude animation, skins, morph targets, compressed geometry, non-UV0 texture mappings, texture transforms, sampler preservation, blended transparency, and advanced material extensions; unsupported required glTF features fail clearly.

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

### 7. Embed imported model images in generated materials

**Decision:** Decode a glTF material's five core metallic-roughness images into the versioned Model product, generate complete mip chains, and pass them through the ordinary generated Material registration and GPU-cache path. Fingerprint every glTF image dependency.
**Why:** Static models retain their authored surface response without adding a model-specific renderer. External image edits invalidate the model deterministically, while generated subresources avoid unstable user-addressable UUIDs before semantic imported-subresource identity is designed.
**Tradeoff:** Generated image payloads are model-owned rather than independently shareable Texture resources. Products store RGBA8 mip chains and preserve color-space meaning, but do not yet preserve glTF sampler state or use GPU-native texture compression.

### 8. Reconstruct the normal-map frame in the fragment shader

**Decision:** Reconstruct tangent and bitangent directions from world-position and UV derivatives instead of adding imported tangents to the retained vertex format.
**Why:** Core glTF normal maps work for existing and imported geometry without widening every vertex and GPU geometry cache entry. This keeps the feature inside the shared Material shader contract.
**Tradeoff:** Derivative reconstruction costs fragment work and cannot exactly reproduce authored tangent bases at mirrored or discontinuous UV seams. Imported tangent attributes and MikkTSpace parity remain a future quality/performance option.

### 9. Precompute image-based lighting during import

**Decision:** Convert HDR equirectangular sources into a source-resolution linear panorama plus fixed renderer-ready diffuse and specular cube-map products in the importer. Configure image-based lighting separately from the optional visible background and allow the background to use another Environment.
**Why:** Source decoding and convolution are asset work, not frame work. A standalone UUID resource can be reimported and cached independently of scenes while the renderer updates only when its handle, version, or global environment revision changes.
**Tradeoff:** The first product uses fixed cube sizes and CPU preprocessing, supports only Radiance HDR input, and retains the source-resolution panorama alongside both cubes. Background blur reuses the prefiltered cube rather than a panorama mip chain. Local reflection probes remain future work.

### 10. Treat cutouts and transparency as different render classes

**Decision:** Import glTF `OPAQUE` and `MASK` materials, apply alpha cutoffs in color, depth, and shadow rendering, and preserve `doubleSided`. Reject `BLEND` materials until sorted transparent submission exists.
**Why:** Binary cutouts remain compatible with retained GPU-driven opaque batching and indirect draws, while blended surfaces require ordering and depth-write rules that cannot be approximated honestly by the opaque path.
**Tradeoff:** Foliage, fences, cards, and other cutout assets work correctly, but glass and translucent effects remain unsupported.

## Related

- **ADRs:** ADR-002, ADR-010, ADR-024, ADR-030, ADR-031, ADR-032, ADR-036, ADR-037
- **FDRs:** FDR-002, FDR-003, FDR-008, FDR-009

## Open Questions

- Which compressed texture target should follow RGBA8 products first: BC, ASTC, ETC2, or KTX2/Basis Universal?
- When should complete model instances become unpackable persistent scene hierarchies?
- Which glTF material extensions should become native Scrapbot material fields first?
