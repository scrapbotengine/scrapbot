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

The WGPU backend admits a Geometry's complete cluster-index page set when it fits the remaining
project budget. Larger resources initially upload only pinned pages and refine through feedback.
Canonical vertex and source index arrays remain resident in this phase.

GPU frontier selection follows these rules:

1. A cluster can draw only while its own page is resident.
2. If finer detail is wanted and its complete group is resident, selection descends normally.
3. If finer detail is wanted but any group page is missing, the resident coarse cluster draws and
   emits its missing group identity and projected-error priority.

Requests and resident-group touches use a bounded tail in the existing visibility counter buffer.
Every visible instance can contribute feedback; deterministic identity hashing spreads resident
touches across a 16-frame cadence while missing-group requests remain immediate. Overflow is
explicit telemetry.

This preserves the portable eight-storage-binding floor. Asynchronous visibility readback carries
feedback without stalling rendering submission.

The CPU applies touches before admission, deduplicates requests by Geometry handle, generation,
and group, then processes the highest projected error first. Admission and eviction are group
atomic: a refinement group is either completely resident or absent.

Ordinary frames admit at most 512 KiB and 16 groups. All missing pages for one admitted group are
expanded into one contiguous transfer. Complete Geometry preloads likewise combine their selected
pages into one arena upload instead of issuing one queue write per page.

When the project budget would be exceeded, the CPU evicts the least-recently-used complete
non-pinned group outside a short feedback-readback grace period. Actual visible-group touches,
rather than request age, define recency.

`[render].virtual_geometry_index_budget_mb` configures the expanded cluster-index budget. It
defaults to 64 MiB and accepts 0.015625 through 16384 MiB.

Residency changes update only affected Geometry batches. Stable frames perform no hierarchy scan,
page upload, eviction, or meshlet-layout rewrite.

## Consequences

Large hierarchy index streams no longer need to be fully GPU resident. Rendering remains complete
under pressure because pinned coarse pages are selected while requested refinement is unavailable.

The `virtual_geometry` debug view colors branches with missing finer pages amber. Structured render
statistics expose budget, resident bytes, total/resident/pinned page counts, request overflow, and
cumulative page/group uploads, bytes, evictions, and deferred admissions. Profile rows expose the
cumulative values and frame-local deltas.

Sponza uses the normal project budget so the representative showcase converges to its intended
detail. The dedicated `gpu-virtual-geometry-pressure` fixture steps a camera across distinct
procedural multi-page resources under a 16 KiB budget and asserts streaming, fallback, group
eviction, and nonblank output. The renderer contains no fixture- or Sponza-specific behavior.

This phase does not page canonical vertices, source indices, hierarchy metadata, or material data.
Those remain ordinary Geometry resources. Future work may move imported page payloads into a
streamable product without changing page identity or fallback selection.
