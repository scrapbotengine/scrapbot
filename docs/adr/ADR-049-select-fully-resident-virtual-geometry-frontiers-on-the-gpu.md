# ADR-049: Select fully resident virtual Geometry frontiers on the GPU

**Date:** 2026-07-31

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

On adapters with indirect-first-instance and native multi-draw, WGPU expands all resident cluster
indices into the shared index arena and retains one indirect command per cluster. Requiring native
multi-draw is submission policy, not a Geometry-format distinction: a backend that expands each
fixed multi-draw range into CPU-encoded indirect calls would multiply work across the shadow,
depth, and world passes.

The compute culler projects each group's monotonic geometric error into pixels. It submits a
cluster exactly when:

1. its owning group exceeds the one-pixel error threshold; and
2. its refined group is absent or is at or below that threshold.

That rule selects one complete frontier. Camera and shadow visibility use the same selected
frontier before applying sphere, normal-cone, and Hi-Z tests. A hierarchy-bearing batch uses this
path even with one instance because geometric-detail selection does not require instance-count
amortization.

Adapters without either required capability retain classic indexed drawing and the existing
object-level imported LOD contract. The backend exposes hierarchy command, nonempty selected-
cluster, and instance-cluster threshold-rejection counters. The public `virtual_geometry` camera
debug view colors submitted clusters by identity within a mint-to-pink hierarchy-depth palette.

## Consequences

Imported, procedural, Luau-created, native, and built-in Geometry all enter one resource-owned
hierarchy path. Sponza is evidence for the feature, not a special renderer input.

The first implementation is fully resident. Hierarchy metadata and every cluster index stream are
uploaded with the Geometry version, so large resources can consume more index-arena memory than
ordinary meshlets. Imported object-level LODs remain available as a portable fallback and currently
also receive their own hierarchy.

This decision does not define persisted hierarchy products, page identifiers, sparse residency,
GPU request feedback, upload budgets, eviction, root-cluster pinning, or page-boundary diagnostics.
Those policies layer over the same Geometry hierarchy and shared arena ownership.
