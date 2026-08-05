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

Model schema v15 divides one `.model.bin` product into four regions:

1. Material image mip payloads.
2. Pinned coarse Geometry pages used as the always-resident fallback.
3. Evictable detail Geometry pages requested by virtual-Geometry feedback.
4. A catalog containing materials, nodes, LODs, hierarchy data, query positions, and payload ranges.

The catalog is physically last because its exact ranges are known only after the payload chunks
have been written. Its directory entry makes its location immediate; the runtime does not scan the
preceding bytes.

At startup, Scrapbot reads the catalog and material images. It registers ordinary engine Geometry
and Material resources while retaining validated file ranges for page payloads. The rendering
backend asks the shared asynchronous page reader for detail only when visibility feedback needs it.

## Bounded import memory

Large Model products are written sequentially instead of being assembled as one giant byte array.
Pinned pages stream directly into the final product. Detail pages use a temporary disk spool so
they can form one contiguous chunk without rebuilding them or retaining all of them in RAM.

Peak serialization memory is therefore bounded by:

- the current primitive-level page build;
- the current primitive-level catalog record;
- a fixed-size spool copy buffer.

The decoded source model and offline hierarchy construction still have their own memory cost.
Future work can reduce that independently through staged source processing and incremental catalog
construction.

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

The chunk directory can describe encoded data, but Model v17 stores its chunks uncompressed.
Compression must preserve the runtime access pattern:

- catalogs and images may use whole-chunk codecs when measurement justifies eager decoding;
- virtual-Geometry pages need independent records so one request never decompresses the complete
  detail chunk;
- decoded sizes and codec flags must be validated before allocation or upload.

This separation lets compression evolve without changing resource declarations, ECS components,
or the renderer's public Geometry contract.
