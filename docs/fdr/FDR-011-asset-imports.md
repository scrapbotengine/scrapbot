# FDR-011: Asset imports

**Status:** In Progress
**Last reviewed:** 2026-08-08

## Overview

Asset imports turn artist-authored texture, model, HDR environment, and SVG icon files under `assets/` into validated, renderer-ready project resources. Imports are incremental, reproducible, inspectable in the editor, and shared by project checking, development runs, and packaged builds.

## Behavior

- Texture resources import PNG sources with explicit color-space and mip-generation settings.
- Environment resources import 2:1 Radiance `.hdr` sources. The importer preserves a source-resolution linear RGBA16F panorama for an opt-in background and builds separate diffuse irradiance and roughness-prefiltered specular cubes. Panorama lookup is bilinear and seam-wrapped, while deterministic 256-sample GGX integration suppresses structured reflection noise; ordinary frames never decode or reconvolve the source panorama.
- Icon-set resources recursively import monochrome SVG symbols from one source directory. The importer normalizes supported paths, primitives, transforms, groups, and strokes into filled outlines, rejects unsupported SVG paint/effect features, and emits a deterministic MTSDF atlas plus symbol metadata. Runtime and packaged builds consume only that product.
- Material resources reference reusable Texture resources by UUID rather than embedding source paths.
- Model resources import the selected glTF 2.0 `.gltf` or `.glb` scene and only its reachable nodes, meshes, materials, and images. Supported data includes triangle geometry, TRS node transforms, metallic-roughness material factors, normal and occlusion strengths, emissive factors, opaque and alpha-cutout materials, double-sided surfaces, and base-color, metallic-roughness, normal, occlusion, and emissive images. Images may be embedded in GLB buffer views, encoded as base64 data URIs, or stored at safe relative paths beside the model.
- Model import generates up to three deterministic meshoptimizer LODs per eligible primitive by default. Project recipes control descending triangle ratios and projected screen-radius thresholds or disable generation. Small and topology-constrained primitives may retain fewer levels.
- Every imported primitive and generated LOD persists its crack-aware cluster hierarchy and deterministic page table in the Model product. Hierarchy reduction accounts for normals and UVs, protects texture seams during permissive fallback, and refuses attribute-blind fallback. Runtime registration validates and clones that product-owned hierarchy instead of rebuilding it.
- Every imported primitive compiles a padded mesh distance field through a temporary BVH. Model v18 stores signed 16-bit samples for watertight meshes and conservative unsigned samples for open or non-manifold geometry in a separate range-addressable chunk.
- Runtime Geometry retains each validated field descriptor and product range. WGPU loads, packs, and uploads samples only for a requesting GPU consumer; the `distance_field` camera debug view exercises that path without causing eager startup residency.
- The `world_distance_field` debug view composes requested instance fields into three snapped 32³ GPU clipmap cascades. It exposes the actual world-cache path, rebuild and dispatch counters, and stable-frame reuse before gameplay effects consume that cache.
- Import diagnostics report field count and payload size. Cache-hit catalog loading validates descriptors without reading samples.
- A Model recipe may prefer `auto`, `conventional`, or `virtual` submission. The preference is runtime policy metadata: products retain both canonical geometry and the hierarchy/page representation, so changing it neither discards geometry nor requires a distinct importer path.
- Imported images become owned mipmapped texture payloads on the Model's generated Material resources. Each texture slot preserves its glTF minification, magnification, mip, and U/V wrap policy. The WGPU material path renders them with GGX direct lighting, authored tangent-space normal mapping with a derivative fallback, ambient diffuse/specular response, HDR emission, bloom, and tone mapping.
- Project checking, building, and running automatically import products that are absent or stale. `scrapbot import` performs the same work explicitly and reports structured per-resource results.
- Imported products and manifests are generated under ignored project state. They are never hand-authored or committed as source authority.
- Model products use the common versioned asset-product envelope and a validated chunk directory. Cache-hit loading buffers catalog reads while preserving file-backed virtual-Geometry page ranges; it does not parse the source glTF or eagerly read skipped page payloads.
- Import validity includes source and dependency contents, settings, and importer version. Unchanged resources reuse their prior products without decoding or rebuilding them.
- A failed reimport reports an actionable error and preserves the last valid product. A project cannot silently start with a stale product when no valid product exists.
- Explicit editor reimport targets one Texture, Model, Environment, or Icon Set UUID without restarting Luau/native code; **Reimport All** forces every declared imported product. Automatic hot reload still uses the project asset stamp and importer cache until the platform watcher replaces polling. Ordinary simulation and render frames never scan the asset tree.
- The editor's resource browser lists textures, environments, and models alongside materials. Its inspector exposes the source dependency, product kind and byte size, warnings/errors, and current import state. Environment inspection reports the derived cube-map shape, and the scene's `scrapbot.world_environment` component selects lighting/background resources for ordinary world and model/material preview rendering. Textures render directly on the GPU with aspect-preserving fit. Models render their imported hierarchy, while Materials render on an isolated lit icosphere preview scene. All previews use the public ECS viewport component and independently sized pooled targets; interactive 3D previews support orbit, zoom, and reset.
- Reimport updates a live resource slot in place and reconciles affected model roots. Generated Geometry and Material products that disappear from a replaced or removed Model are retired with generation bumps, so stale handles cannot remain usable.
- Shadow caster/receiver markers authored on a Model root are inherited by its generated primitive entities when that model instance reconciles. Imported geometry therefore remains on the ordinary renderer and shadow-marker path instead of needing model-specific shadow submission.
- Imported models initially exclude animation, skins, morph targets, compressed geometry, non-UV0 texture mappings, texture transforms, blended transparency, and advanced material extensions; unsupported required glTF features reachable from the selected scene fail clearly.

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
**Tradeoff:** Imported nodes, meshes, primitives, materials, generated resource names, and derived ECS UUIDs use semantic keys rather than source-array positions. Authored names and hierarchy paths are preferred; unnamed or ambiguous objects receive content-based discriminators. Meaningful renames, reparenting, or otherwise ambiguous identical unnamed siblings can intentionally change identity, while harmless array reordering preserves it.

Model-root shadow markers are copied onto derived primitive entities during the same structural reconciliation. This keeps shadow membership explicit in ordinary ECS renderer state.

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

**Decision:** Decode a glTF material's five core metallic-roughness images into the versioned Model product, generate complete mip chains, preserve each texture slot's glTF sampler policy, and pass them through the ordinary generated Material registration and GPU-cache path. Fingerprint every glTF image dependency.
**Why:** Static models retain their authored surface response without adding a model-specific renderer. External image edits invalidate the model deterministically, while generated subresources avoid unstable user-addressable UUIDs before semantic imported-subresource identity is designed.
**Tradeoff:** Generated image payloads and their per-slot GPU samplers are model-owned rather than independently shareable Texture resources. Products store RGBA8 mip chains and do not yet use GPU-native texture compression.

### 11. Compile only the selected scene closure

**Decision:** Begin at the glTF default scene (or the first scene/root set when no default is declared), traverse its node hierarchy, and compact only referenced meshes and materials into the Model product.
**Why:** A glTF file may contain alternate scenes, export leftovers, and large unreachable libraries. Import cost, product size, runtime entities, and validation should describe the resource the project actually selected.
**Tradeoff:** Unsupported mesh, node, or material features outside the selected closure are ignored. File-wide features such as animation and required extensions remain importer-level constraints until those feature families are supported.

### 8. Preserve authored normal-map tangent frames

**Decision:** Import glTF `TANGENT` vectors, including their handedness, into the retained vertex format. Use them for normal mapping when present; reconstruct the frame from position and UV derivatives only when the tangent is zero.

**Why:** Author-provided tangent bases keep normal maps stable at mirrored UVs, discontinuous seams, and grazing edges. The zero-tangent fallback keeps generated, Luau, and native geometry usable without requiring tangent generation.

**Tradeoff:** Retained vertices grow from 32 to 48 bytes. Geometry without authored tangents still pays derivative reconstruction and may not match MikkTSpace exactly.

### 9. Precompute image-based lighting during import

**Decision:** Convert HDR equirectangular sources into a source-resolution linear panorama plus fixed renderer-ready diffuse and specular cube-map products in the importer. Use bilinear seam-wrapped panorama sampling and deterministic 256-sample GGX integration for specular prefiltering. Configure image-based lighting separately from the optional visible background and allow the background to use another Environment.
**Why:** Source decoding and convolution are asset work, not frame work. A standalone UUID resource can be reimported and cached independently of scenes while the renderer updates only when its handle, version, or global environment revision changes.
**Tradeoff:** The product uses fixed cube sizes and higher-quality CPU preprocessing, supports only Radiance HDR input, and retains the source-resolution panorama alongside both cubes. The denser prefilter makes a stale import more expensive to rebuild, but remains cached and never becomes frame work. Background blur reuses the prefiltered cube rather than a panorama mip chain. Local reflection probes remain future work.

### 10. Treat cutouts and transparency as different render classes

**Decision:** Import glTF `OPAQUE` and `MASK` materials, apply alpha cutoffs in color, depth, and shadow rendering, and preserve `doubleSided`. Reject `BLEND` materials until sorted transparent submission exists.
**Why:** Binary cutouts remain compatible with retained GPU-driven opaque batching and indirect draws, while blended surfaces require ordering and depth-write rules that cannot be approximated honestly by the opaque path.
**Tradeoff:** Foliage, fences, cards, and other cutout assets work correctly, but glass and translucent effects remain unsupported.

### 12. Compile imported LODs into the Model product

**Decision:** Simplify eligible indexed glTF primitives during import, compact each retained level, and persist its geometry, projected threshold, and measured error in the versioned Model product. Register generated levels as ordinary semantic Geometry subresources and attach them through the shared LOD contract. See ADR-047.

### 13. Persist streamable virtual Geometry pages

**Decision:** Build and validate each imported primitive hierarchy during import. Persist groups,
clusters, local streams, page identities, pinned-page flags, and self-contained vertex/index page
payloads in the versioned Model product. Runtime Geometry retains validated byte ranges so WGPU
can read refinement pages asynchronously without an importer-specific draw path. Publish cluster,
group, and page counts in import metadata. Simplification uses normal and UV attributes, protects
UV discontinuities when permissive reduction is necessary, and stops rather than using an
attribute-blind fallback. See ADR-050.

**Why:** Runtime startup should consume a compiled geometry product, not repeat simplification and
page partitioning for every imported model.

**Tradeoff:** Model products are larger and their schema changes when hierarchy serialization
changes. Attribute-rich or heavily seamed models may retain more clusters because visual
continuity takes precedence over reaching an aggressive reduction target. Procedural and
script-created Geometry still builds the same hierarchy at registration.

**Why:** Simplification is deterministic source-asset work. Persisting it keeps runtime registration bounded and lets models use the existing CPU/GPU selection, meshlet, debug, reload, and retirement paths.

**Tradeoff:** Products retain more geometry and rendered scenes retain more possible batch records. The simplifier may stop before a target ratio or omit a level when topology or the error bound prevents a useful reduction.

### 14. Give runtime products one common envelope

**Decision:** Wrap type-specific runtime payloads in an engine-owned, versioned header and bounded
chunk directory. Keep importer schemas responsible for the bytes inside each typed chunk. See
ADR-051.

**Why:** Runtime discovery, range validation, future compression, and export packaging should not
be reinvented for every importer. Development and exported games must consume the same products.

**Tradeoff:** The envelope adds a small fixed directory and requires each importer to validate its
own chunk relationships.

### 15. Split and stream large Model products

**Decision:** Model v18 separates material images, pinned coarse pages, evictable detail pages,
quantized mesh distance fields, and the runtime catalog into five product chunks. Build the product
with the common sequential writer; spool detail pages temporarily and emit the descriptor catalog
only after exact ranges are known.

The pinned chunk contains every terminal refinement-DAG group, not merely groups at the global
maximum hierarchy depth. Different regions may stop simplifying at different depths; evicting any
such terminal group would remove that region's last drawable fallback.

Hierarchy simplification also locks every topological boundary loop by canonical position. Coarser
frontiers may reduce interior detail but cannot enlarge source openings by moving their borders.

The v17 fingerprint invalidates products whose early terminal groups were incorrectly placed in
the evictable detail chunk.

The v18 fingerprint adds one independently addressable distance-field range per primitive. The
catalog stores descriptors, never bulk voxel samples. See ADR-055.

**Why:** Runtime startup should not walk gigabytes of payload bytes to discover a catalog. Import
should not require enough spare memory for both the decoded source model and a second complete
artifact-sized byte array.

**Tradeoff:** First import temporarily writes detail bytes twice: once to the spool and once to the
finished product. Compression is intentionally separate because virtual-Geometry pages need
independent decoding rather than whole-detail-chunk decompression.

## Related

- **ADRs:** ADR-002, ADR-010, ADR-024, ADR-030, ADR-031, ADR-032, ADR-036, ADR-037, ADR-038, ADR-041, ADR-046, ADR-047, ADR-050, ADR-051, ADR-054, ADR-055
- **FDRs:** FDR-002, FDR-003, FDR-008, FDR-009

## Open Questions

- Which compressed texture target should follow RGBA8 products first: BC, ASTC, ETC2, or KTX2/Basis Universal?
- When should complete model instances become unpackable persistent scene hierarchies?
- Which glTF material extensions should become native Scrapbot material fields first?
