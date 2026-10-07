---
title: Asset Pipeline
description: How Scrapbot turns source assets into validated runtime products.
---

Scrapbot keeps authoring inputs separate from runtime data:

```text
Input assets → imported runtime products → startup and rendering
```

Input assets are ordinary files under a project's `assets/` directory. Resource declarations give
those files stable UUIDs and import settings. Scrapbot fingerprints the source, its dependencies,
and the importer schema, then writes disposable products under `.scrapbot/imported/`.

An exported game uses the same product representation as a development run. Products can be
regenerated from the source project; they are not a lower-quality replacement for it and do not
silently discard authored geometry.

## Product envelope

Every chunked product begins with an engine-owned envelope containing:

- the product format and resource kind;
- a bounded directory of typed chunks;
- each chunk's file offset and stored/decoded size;
- reserved encoding flags for future compression.

The loader validates the complete directory before an importer interprets its payloads. Importer
schemas version the contents of each chunk independently from the common envelope.

## Model products

Model v22 stores three independently addressable chunks:

1. Material image mip payloads.
2. Quantized mesh distance-field samples.
3. A catalog with materials, nodes, complete indexed meshes, ordinary LODs, and payload ranges.

The catalog is written last so its image and field ranges are known. Loading
reads complete meshes and material images. Distance-field samples remain lazy.
The registry owns the decoded vertex/index arrays for exact queries and direct
GPU upload.

Virtual Geometry pages, bootstrap tails, and refinement streaming are retired.
Older imported caches are rebuilt automatically.

## Import memory

The sequential writer emits image and distance-field payloads directly, then
writes one primitive catalog record at a time. It does not construct a second
complete product-sized byte array or spool geometry pages. The decoded source
model and offline LOD generation still have their own memory cost.

## Caching and invalidation

`scrapbot check`, `build`, `run`, and explicit editor reimport ensure products before runtime
registration. A matching source/dependency/settings fingerprint reuses the existing product. A
schema or content change rebuilds it.

Product and metadata writes use temporary paths. Failed conversion leaves the last installed
product available, while a successful import replaces the product consumed by the next registry
update.

## Import progress

The importer exposes typed lifecycle events for the complete batch and each individual asset.
Engine tools and game projects can attach their own observer without coupling import work to a
terminal, editor, or particular UI system.

Scrapbot's human CLI adapter writes these events to stderr. It announces an asset before expensive
processing begins and reports its cache status, elapsed time, and product shape when complete.
`--json` disables the human adapter so automation still receives exactly one JSON document on
stdout.

## Compression boundary

Model v22 also compiles one padded mesh distance field per primitive. Watertight meshes retain
signed distances; open or non-manifold meshes retain conservative unsigned surface distances. The
samples use signed 16-bit quantization and live in their own chunk, so runtime catalog loading
validates their descriptors without reading the voxel payload. Import progress reports both the
field count and its stored size.

Runtime Geometry keeps the validated descriptor and file range. The renderer loads and uploads the
samples lazily when a GPU consumer requests them; loading an ordinary scene does not make every
field GPU-resident. In the editor, choose **View / Distance Field** to inspect a middle voxel slice
through that same runtime cache. Cyan shows unsigned surface distance. Signed fields use warm
outside and blue inside values, with pale values nearest the surface.

Choose **View / World Distance Field** to build and inspect the first world-space clipmap consumer.
The renderer transforms imported fields through their ordinary GPU instance records, seeds three
camera-relative 32³ cascades, and propagates surface distance on the GPU. The view shows a top-down
projection of the nearest cascade: bright cyan is near represented geometry and slate is farther
away.

Clipmap centers snap to 1, 4, and 16-unit voxel grids. An unchanged debug frame reuses the retained
result without another upload or compute dispatch. A camera cell crossing scrolls retained seeds
and rasterizes only the exposed slab in each affected cascade. Viewport changes, Geometry
replacement, topology changes, and relevant instance/Transform dirtiness still trigger a complete
rebuild. Renderer diagnostics distinguish full rebuilds from scrolls and report exposed voxels.
This is currently a diagnostic foundation; HZB still owns production occlusion.

The chunk directory can describe encoded data, but Model v22 stores its chunks uncompressed.
Compression must preserve the runtime access pattern:

- catalogs and images may use whole-chunk codecs when measurement justifies eager decoding;
- distance-field payloads must retain independent access from eager mesh loading;
- decoded sizes and codec flags must be validated before allocation or upload.

This separation lets compression evolve without changing resource declarations, ECS components,
or the renderer's public Geometry contract.
