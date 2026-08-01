# ADR-050: Page virtual Geometry payloads

**Date:** 2026-07-31
**Updated:** 2026-08-01

## Context

ADR-049 established a crack-aware Geometry hierarchy and GPU-selected detail frontier. The first
virtual-Geometry slice bounded expanded cluster indices, but every canonical vertex remained in
the WGPU arena. Imported products were also decoded as one eager object, so refinement could not
be fetched without render-thread work.

Virtual Geometry needs self-contained pages, a backend-independent source contract, and
asynchronous product reads. Coarse geometry must remain drawable while finer data is absent.

## Decision

The engine-owned `geometry` package builds deterministic, group-aligned pages. Each page contains:

- the unique canonical vertices referenced by its clusters;
- page-local expanded `u32` indices;
- vertex and index counts plus a byte range in its source.

Pages never split a hierarchy group. Clusters retain their page identity and page-local index
offset. The coarsest hierarchy depth is pinned as the guaranteed fallback frontier.

All Geometry producers use one resource contract. Imported Geometry points at byte ranges in a
versioned Model product. Procedural, Luau, native, and built-in Geometry own the same payloads in
memory. The renderer branches only on source transport, never on project or importer identity.

Model schema v12 persists each self-contained payload beside its hierarchy metadata. Product
decoding validates page count, vertex/index counts, byte sizes, and file bounds before registering
file-backed Geometry sources.

WGPU gives every streamed resident page an aligned vertex-arena range and index-arena range.
Cluster draw metadata uses that page-local base vertex and first index. Streamed Virtual Geometry
retains no complete canonical allocation in the WGPU arenas.

When one Geometry's complete canonical vertex/index streams and expanded page indices fit the
remaining budget, WGPU admits that representation as a fast path. It avoids page-local vertex
duplication and retains classic indexed shadow submission. Under actual streaming pressure,
portable compact submission uses page-local vertices and indices for both camera and shadow work.

Pinned bootstrap pages and complete resources that fit the remaining budget are loaded while the
Geometry cache is established. Refinement reads for larger imported resources run on a dedicated
I/O worker. The render thread schedules exact immutable product ranges, continues drawing the
nearest resident fallback, and consumes completed payloads without waiting on file I/O.

Requests are deduplicated and prioritized by projected error. Admission and eviction remain group
atomic. Ordinary frames admit at most 512 KiB and 16 groups. The configured budget counts both
aligned vertex and index residency; pinned fallback data may raise effective residency above it.

Completed reads carry Geometry handle, generation, version, and page identity. Stale completions
are discarded. Failed reads leave the coarse frontier intact and may be retried by later feedback.

`[render].virtual_geometry_budget_mb` defaults to 64 MiB and accepts 0.015625 through 16384 MiB.
The old `virtual_geometry_index_budget_mb` spelling remains a deprecated compatibility alias.

Stable frames with no feedback, completion, or residency change perform no hierarchy scan, file
read, payload construction, arena upload, or meshlet-layout rewrite.

## Consequences

Fine Geometry vertices and indices can now be absent from GPU memory and loaded directly from an
imported product without blocking a frame. Procedural Geometry exercises the same page layout and
residency machinery through a memory source. Resources that fit retain a faster canonical GPU
representation; resources that do not fit use self-contained pages without changing public APIs.

Structured render statistics expose total/resident/pinned pages; complete payload budget and
resident bytes; request overflow; page/group uploads and evictions; asynchronous read count,
bytes, and failures; and deferred admissions. Profile rows include frame-local counter deltas.

Canonical CPU vertices, source indices, hierarchy metadata, and material data remain resident for
backend-neutral fallback, picking, and authoring. Removing those CPU copies requires a separate
proxy/query design and is not implied by this decision.

Sponza and the pressure fixture use ordinary engine behavior. No resource name, example path, or
scene-specific policy participates in paging.
