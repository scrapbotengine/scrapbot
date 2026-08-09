# ADR-050: Page virtual Geometry payloads

**Date:** 2026-07-31
**Updated:** 2026-08-09

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
offset. Every terminal refinement-DAG group is pinned as the guaranteed fallback. Hierarchy
construction then grows an eagerly loaded bootstrap tail from those roots by admitting reachable
complete groups in descending geometric-error order.

The extra tail targets 1/32 of the hierarchy payload, with a 256 KiB minimum and 2 MiB maximum per
hierarchy. Terminal fallback bytes are mandatory and do not consume that allowance. A group that
does not fit remains streamable together with every descendant reachable only through it. This
makes the bootstrap set ancestor-closed without using a camera, example identity, elapsed time, or
backend capability during asset construction. Bootstrap refinements are ordinary evictable
residency after their first upload; only terminal groups remain pinned under global pressure.

All Geometry producers use one resource contract. Imported Geometry points at byte ranges in a
versioned Model product. Procedural, Luau, native, and built-in Geometry own the same payloads in
memory. The renderer branches only on source transport, never on project or importer identity.

Model schema v13 persists a compact runtime catalog: canonical counts, position-only query data,
the hierarchy, and exact page ranges. Complete render vertices and source indices exist only in
self-contained page payloads. The loader reads catalog fields directly from the product file and
skips payload byte ranges without allocating them. Decoding validates page count, vertex/index
counts, byte sizes, and file bounds before registering file-backed Geometry sources.

Runtime registration derives compatibility meshlets from the exact hierarchy leaves. It clones
one primitive at a time into the Geometry registry and releases the decoded catalog entry
immediately, so bootstrap does not retain both the complete decoded Model product and the complete
registered resource set.

File-backed Geometry retains canonical vertex/index counts, a position-only CPU query proxy, exact
leaf-cluster topology, and its immutable page source. It does not retain the complete render-vertex
or source-index arrays after registration. Exact CPU queries iterate the leaf clusters, including
leaves that terminate above maximum hierarchy depth, and resolve their canonical vertex IDs
through the position proxy.

The resource contract exposes an explicit canonical view for backend compatibility. Memory-backed
Geometry borrows its resident arrays. File-backed Geometry reconstructs render vertices and exact
leaf indices from every page containing leaf clusters into an owned temporary view. A consumer
must release that view; WGPU does so immediately after cache upload. Source indices are metadata,
not runtime topology authority, because hierarchy construction may remove degenerate triangles.

WGPU gives every streamed resident page an aligned vertex-arena range and index-arena range.
Cluster draw metadata uses that page-local base vertex and first index. Streamed Virtual Geometry
retains no complete canonical allocation in the WGPU arenas.

Portable compact submission allocates those ranges only inside the adapter's addressable storage
binding window. Fragmentation may leave free bytes outside that prefix or prevent one contiguous
admission even while the combined payload budget has room. In that case the refinement stays
deferred and the already-resident coarse frontier remains authoritative. WGPU never marks an
unaddressable page resident or publishes its offsets to cluster draw metadata.

When one Geometry's complete canonical vertex/index streams and expanded page indices fit the
remaining budget, WGPU admits that representation as a fast path. It avoids page-local vertex
duplication and retains classic indexed shadow submission. Under actual streaming pressure,
portable compact submission uses page-local vertices and indices for both camera and shadow work.
The retained root-page proxy remains a fallback; its presence does not force streamed resources
back onto classic cascade submission.

Cache creation also rebases the complete terminal frontier into one indexed compatibility proxy.
The proxy references only permanently pinned vertices, never evictable bootstrap refinements. It is
used by shadows where applicable and by world/depth classic submission whenever the detailed
visibility layout is unavailable. Capacity fallback is therefore a quality reduction rather than
an empty or multiply overdrawn hierarchy.

Meshlet and hierarchy-cluster visibility ranges use exact instance cardinality. They are addressed
as indices inside one shared storage binding and do not inherit the 256-byte dynamic-binding
alignment required by classic per-batch slices. The bounded layout guard therefore measures the
records that culling can actually emit instead of reserving 64 records for every cluster of a
single-instance model.

Bootstrap-tail pages and complete resources that fit the remaining budget are loaded while
the Geometry cache is established. Refinement reads for larger imported resources run on a
dedicated I/O worker. The render thread schedules exact immutable product ranges, continues drawing
the nearest resident fallback, and consumes completed payloads without waiting on file I/O.

Requests are deduplicated and prioritized by projected error. Admission and eviction remain group
atomic. Ordinary frames admit at most 512 KiB and 16 groups. The configured budget counts both
aligned vertex and index residency; only mandatory terminal fallback data may raise effective
residency above it.

Eviction removes a group from logical residency immediately, but its page ranges remain physically
retired until a completed visibility readback fences their last submitted use. Streaming cannot
overwrite vertex or index bytes that an in-flight depth, world, or shadow command may still read.
Retirement may temporarily make physical arena residency exceed the logical page budget.

When `[render].virtual_geometry_prefetch` is enabled, WGPU derives a bounded future camera from
smoothed frame-to-frame position and view-direction motion. A widened future frustum emits
speculative refinement requests through the same feedback channel. Visible demand always sorts
before speculative work. Demand may immediately reclaim prefetched groups; prefetch may evict only
groups outside the visible-use grace window. A sampled visible touch promotes prefetched residency
into ordinary visible residency.

Prediction is a residency hint, never a visibility or correctness input. Camera discontinuities,
world replacement, missing camera history, and negligible motion disable it for that frame. The
current camera alone chooses and culls the rendered frontier.

Completed reads carry Geometry handle, generation, version, and page identity. Stale completions
are discarded. Failed reads leave the coarse frontier intact and may be retried by later feedback.

`[render].virtual_geometry_budget_mb` defaults to 64 MiB and accepts 0.015625 through 16384 MiB.
The old `virtual_geometry_index_budget_mb` spelling remains a deprecated compatibility alias.
`[render].virtual_geometry_prefetch` defaults to `true` and may disable speculative requests without
changing demand streaming.

Stable frames with no feedback, completion, or residency change perform no hierarchy scan, file
read, payload construction, arena upload, or meshlet-layout rewrite.

## Consequences

Fine Geometry vertices and indices can now be absent from GPU memory and loaded directly from an
imported product without blocking a frame. Procedural Geometry exercises the same page layout and
residency machinery through a memory source. Resources that fit retain a faster canonical GPU
representation; resources that do not fit begin with a useful bounded bootstrap tail and use
self-contained pages without changing public APIs. The tail improves the first rendered frame but
does not accumulate as a permanently pinned per-asset memory tax.

Structured render statistics expose total/resident/pinned/prefetched pages; complete payload budget
and resident bytes; demand and prefetch requests; prefetch uploads, hits, and reclamations; request
overflow; page/group uploads and evictions; asynchronous read count, bytes, and failures; and
deferred admissions. Profile rows include frame-local cumulative-counter deltas.

Imported canonical CPU render vertices and source indices no longer remain resident. Picking and
future authoring queries use the position-only proxy plus exact leaf topology. Classic rendering,
CPU culling, resource previews, and adapters without the virtual path reconstruct a temporary
canonical view at Geometry-cache invalidation, upload it, and release it before the frame proceeds.
Procedural and runtime Geometry keeps resident arrays because its page source is memory-backed and
there is no persistent product from which to recover backend fallback data.

Cache-hit Model bootstrap no longer reads the complete artifact or reconstructs full canonical
geometry. On the pinned Sponza workload this reduced engine-allocator startup peak from
872,400,880 bytes to 449,408,061 bytes while preserving the same retained resource contract.

Sponza and the pressure fixture use ordinary engine behavior. No resource name, example path, or
scene-specific policy participates in paging.
