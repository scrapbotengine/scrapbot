# ADR-050: Page virtual Geometry index streams

**Date:** 2026-07-31

## Context

ADR-049 established a crack-aware Geometry hierarchy and GPU-selected detail frontier. Its first
implementation expanded every hierarchy cluster into the WGPU index arena when a Geometry version
became visible. That made selection correct, but memory grew with the complete hierarchy.

Virtual Geometry needs a bounded resident representation. It must always retain drawable geometry
while finer detail is absent, and it must work through the portable WebGPU binding model.

## Decision

The engine-owned `geometry` package builds deterministic cluster pages beside every hierarchy.
Pages target 64 KiB of expanded `u32` indices and never split a hierarchy group. Groups and
clusters store their page ranges and page-local index offsets.

The coarsest hierarchy depth is pinned. Its pages are the guaranteed fallback frontier and may
raise effective residency above a configured budget.

Imported model products persist the complete hierarchy and page table. Their schema version
changes whenever this binary contract changes. Procedural, Luau, native, and built-in Geometry
build the same representation at explicit registration boundaries.

The WGPU backend initially uploads only pinned cluster-index pages. Canonical vertex and source
index arrays remain resident in this phase.

GPU frontier selection follows these rules:

1. A cluster can draw only while its own page is resident.
2. If finer detail is wanted and its complete group is resident, selection descends normally.
3. If finer detail is wanted but any group page is missing, the resident coarse cluster draws and
   emits the first missing page identity.

Page requests use a bounded tail in the existing visibility counter buffer. This preserves the
portable eight-storage-binding floor. Asynchronous visibility readback carries request identities
without stalling the rendering submission.

The CPU deduplicates requests by Geometry handle, generation, page, and frame. Requested pages are
uploaded into the shared index arena. Non-pinned pages use deterministic least-recently-requested
eviction when the project budget would be exceeded.

`[render].virtual_geometry_index_budget_mb` configures the expanded cluster-index budget. It
defaults to 64 MiB and accepts 0.125 through 16384 MiB.

Residency changes update only affected Geometry batches. Stable frames perform no hierarchy scan,
page upload, eviction, or meshlet-layout rewrite.

## Consequences

Large hierarchy index streams no longer need to be fully GPU resident. Rendering remains complete
under pressure because pinned coarse pages are selected while requested refinement is unavailable.

The `virtual_geometry` debug view colors branches with missing finer pages amber. Structured render
statistics expose budget, resident bytes, total/resident/pinned page counts, request overflow, and
cumulative uploads, bytes, and evictions. Profile rows expose the cumulative values and frame-local
deltas for page uploads and eviction.

Sponza uses a deliberately small 0.16 MiB budget as a pressure demonstration. The renderer contains
no Sponza-specific behavior.

This phase does not page canonical vertices, source indices, hierarchy metadata, or material data.
Those remain ordinary Geometry resources. Future work may move imported page payloads into a
streamable product without changing page identity or fallback selection.
