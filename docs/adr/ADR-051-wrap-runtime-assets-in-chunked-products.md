# ADR-051: Wrap runtime assets in chunked products

**Date:** 2026-08-02

## Context

ADR-036 separates source assets from imported runtime products. Each importer currently owns its
complete artifact layout, however, so the runtime has no common way to identify a product, reject
an incompatible container version, inspect its payload directory, or read only a required range.

The Model v13 format already leaves virtual-Geometry page payloads on disk and records their byte
ranges. Its catalog and payloads still share one importer-specific stream. Cache-hit loading also
issues tiny positional reads for individual scalar fields, making a large compiled catalog slow to
open even though the runtime correctly skips most payload bytes.

## Decision

Wrap imported runtime data in one engine-owned asset-product envelope. The envelope contains:

- an engine product magic and format version;
- the resource product kind;
- a bounded chunk directory;
- a stable `(kind, index)` identity for every chunk;
- flags plus stored and decoded byte sizes for future encodings;
- validated, non-overlapping file ranges.

Importer schemas continue to version type-specific payloads. The common envelope does not impose
one serialization schema on textures, models, environments, icon sets, or future resource kinds.
It provides their shared discovery, validation, range-access, and packaging boundary.

Development runs and exported games consume the same product bytes. Packaging may aggregate those
files into a larger archive, but it must not re-import source assets or invent a second runtime
representation. Source assets remain authoritative authoring inputs; products remain disposable,
reproducible derivatives.

The first consumer is Model schema v14. It stores its existing runtime stream in a typed product
chunk and reads the chunk through a bounded buffered reader. Large page payload ranges remain
skipped and file-backed. Later schema revisions may split the runtime catalog, material images,
coarse bootstrap data, and virtual-Geometry pages into independently compressed chunks without
changing the outer product contract.

## Consequences

Runtime loaders can reject malformed, truncated, overlapping, mismatched, or unsupported products
before interpreting type-specific bytes. Model cache-hit startup performs bulk catalog reads rather
than millions of scalar system calls while preserving exact page ranges for asynchronous streaming.

The initial Model migration has one runtime chunk, so it establishes the container and fixes read
amplification without yet reducing product size. Chunk splitting, compression, deduplication,
memory-mapped catalogs, source-free export packaging, and incremental per-chunk rebuilds remain
separate measured changes.
