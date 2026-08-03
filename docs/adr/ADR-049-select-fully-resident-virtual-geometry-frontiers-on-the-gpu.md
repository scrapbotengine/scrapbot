# ADR-049: Select fully resident virtual Geometry frontiers on the GPU

**Date:** 2026-07-31

**Updated:** 2026-08-03

## Context

Scrapbot's imported LODs select one independently simplified Geometry at object granularity. Its
meshlets cull bounded pieces inside that selected level, but they do not change geometric detail.
The shared WGPU arenas established physical suballocation without defining hierarchical geometry.

A virtual-geometry system needs a crack-free hierarchy before it needs streaming. Building page
tables first would only make independently simplified chunks resident; it would not make them a
valid continuously selectable surface.

## Decision

Every Geometry registration or replacement derives a cluster hierarchy from its canonical indexed
triangles. Scrapbot uses the pinned meshoptimizer cluster-LOD builder through a narrow C bridge.
The builder partitions clusters spatially, locks boundaries shared between simplification groups,
and emits monotonic group errors. All clusters continue to reference the canonical vertex array.

Geometry owns:

- groups with depth, conservative bounds, simplification error, and cluster ranges;
- clusters with local index streams, culling bounds, normal cones, owning group, and refined group;
- the maximum hierarchy depth.

Clone, replacement, hot reload, and destruction treat these arrays as part of the exact Geometry
version. Construction happens only at explicit resource registration boundaries. Stable frames do
not simplify, partition, hash, or rebuild hierarchy data.

WGPU expands all resident cluster indices into the shared index arena. Adapters with indirect-
first-instance and native multi-draw retain one indexed-indirect command per cluster and submit
compatible command ranges together.

Adapters with indirect-first-instance but no native multi-draw instead append selected
`{instance slot, cluster index}` records into a bounded camera storage stream. A compatible run of
clusters sharing one material owns one retained record span and one non-indexed indirect command.
Its vertex shader pulls cluster indices and packed attributes directly from the shared geometry
arenas. Every selected record renders the fixed maximum cluster vertex count; invocations beyond
the cluster's triangle count degenerate to its first vertex.

The portable path renders directional shadows from the already GPU-selected object LOD through
classic indexed-indirect commands. It retains a separate indexed shadow template because the
camera template is non-indexed. This keeps cascade visibility GPU-produced while avoiding four
repeated hierarchy traversals and fixed-maximum vertex pulling for depth-only shadow work.

Both submission modes are GPU-produced. Ordinary frames neither read selected clusters back nor
expand their command topology on the CPU.

The compute culler projects each group's monotonic geometric error into pixels. A narrow overlap
band spans 98% through 102% of the active error threshold. Within that band, it submits adjacent
hierarchy levels together as complete opaque surfaces. Outside the band, it
submits a cluster exactly when:

1. its owning group exceeds the one-pixel error threshold; and
2. its refined group is absent or is at or below that threshold.

That rule selects one complete frontier for camera rendering. The overlap temporarily broadens
that frontier. Both opaque levels remain complete and depth-test normally because adjacent
simplifications do not guarantee identical pixel coverage around thin surfaces and silhouettes;
complementary fragment discard can expose background where only one side has geometry. A
transition-only reactive marker lets the temporal resolver retain compatible history across
bounded parent/child depth and silhouette changes.

Shadow overlap submits both hierarchy levels without fragment coverage discard. The depth-only
result conservatively retains the nearest caster and cannot leak stochastic light through small
parent/child silhouette differences.

A newly resident child does not immediately make its coarse parent ineligible. GPU camera and
shadow selection keep the parent submitted throughout the bounded admission transition, even when
the child's projected error would otherwise select the child alone. Both complete opaque surfaces
remain depth-testable until the handoff completes; residency and transition coverage cannot expose
cluster-shaped gaps by removing or discarding the only surface at a pixel.

Native multi-draw adapters also use the hierarchy for shadows before applying cascade sphere and
normal-cone tests. The portable path uses the camera-selected object LOD for conservative cascade
visibility. A hierarchy-bearing batch uses cluster camera submission even with one instance because
geometric-detail selection does not require instance-count amortization.

Adapters without indirect-first-instance, capacity-limited layouts, and `--cpu-culling` retain
classic indexed drawing and the existing object-level imported LOD contract. The backend exposes
hierarchy command, nonempty selected-cluster, instance-cluster threshold-rejection, and compacted-
submission counters. The public `virtual_geometry` camera debug view colors submitted clusters by
identity within a mint-to-pink hierarchy-depth palette.

## Consequences

Imported, procedural, Luau-created, native, and built-in Geometry all enter one resource-owned
hierarchy path. Sponza is evidence for the feature, not a special renderer input.

Virtual Geometry now operates on Metal adapters that expose indirect-first-instance even though
their WGPU implementation does not expose native multi-draw. Compatible material runs amortize
submission without requiring mesh shaders, backend-specific argument buffers, or one encoded draw
per cluster. The portable camera path spends extra GPU culling and vertex-pulling work to preserve
stable CPU frame cost. Its indexed shadow fallback preserves that CPU behavior while reducing GPU
work on adapters where fixed-vertex compact shadow records are more expensive than indexed
geometry.

The first implementation is fully resident. Hierarchy metadata and every cluster index stream are
uploaded with the Geometry version, so large resources can consume more index-arena memory than
ordinary meshlets. Imported object-level LODs remain available as a portable fallback and currently
also receive their own hierarchy.

This decision does not define persisted hierarchy products, page identifiers, sparse residency,
GPU request feedback, upload budgets, eviction, root-cluster pinning, or page-boundary diagnostics.
Those policies layer over the same Geometry hierarchy and shared arena ownership.

ADR-050 adds those policies for self-contained vertex/index payloads while retaining canonical CPU
source data.
