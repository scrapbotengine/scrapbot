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

The first consumer was Model schema v14. It stored its existing runtime stream in one typed chunk
and established the common envelope plus bounded buffered reads.

Model schema v15 uses four chunks:

- material image mip payloads;
- pinned coarse-Geometry pages required for the fallback frontier;
- evictable detail-Geometry pages requested by virtual-Geometry streaming;
- a catalog of materials, nodes, hierarchy data, query positions, and validated payload ranges.

Import writes the product sequentially instead of assembling a complete artifact byte array.
Pinned pages stream directly into the product. Detail pages use a bounded temporary spool so they
can become one contiguous chunk without rebuilding page payloads or retaining the entire product
in memory. The catalog is written last, after exact file ranges are known.

Chunk-level or page-level compression may be added without changing the outer product contract.
Randomly accessed Geometry pages must remain independently decodable; compressing the complete
detail chunk as one stream is not acceptable.

## Consequences

Runtime loaders can reject malformed, truncated, overlapping, mismatched, or unsupported products
before interpreting type-specific bytes. Model cache-hit startup performs bulk catalog reads rather
than millions of scalar system calls while preserving exact page ranges for asynchronous streaming.

Model startup can read the catalog without scanning image or Geometry payloads. Material images
are loaded from validated image-chunk ranges. Geometry registration retains only absolute ranges
into the immutable coarse or detail chunk, so the existing asynchronous page reader remains the
sole refinement I/O path.

Streaming construction bounds peak serialization memory by one primitive-level page build, one
primitive-level catalog record, and a fixed copy buffer. It uses temporary disk capacity for detail
pages during import.

Compression, deduplication, memory-mapped catalogs, source-free export packaging, and incremental
per-chunk rebuilds remain separate measured changes.
