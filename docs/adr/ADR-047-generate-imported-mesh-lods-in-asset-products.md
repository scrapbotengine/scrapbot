# ADR-047: Generate imported mesh LODs in asset products

**Date:** 2026-07-31

## Context

Scrapbot can select up to four Geometry levels on the GPU, but only generated icospheres currently
publish alternate levels. Imported glTF primitives always retain full triangle density regardless
of projected size.

Simplifying imported geometry during registration or an ordinary frame would mix source-asset work
with runtime resource ownership. A model-specific render path would also bypass the shared Geometry
LOD and meshlet contracts.

## Decision

Generate imported mesh LODs while compiling the versioned Model product. Model recipes enable this
by default and may supply up to three descending target ratios plus matching projected screen-radius
thresholds. Disabling generation leaves the canonical source primitive unchanged.

For every triangle primitive with at least 16 source triangles:

- simplify independently from the canonical indexed source with pinned meshoptimizer;
- include source normals and UV0 in the simplification error metric;
- cap geometric error progressively for farther levels;
- keep a level only when it has fewer indices than the preceding retained level;
- compact referenced vertices in deterministic first-use order;
- store screen radius and measured simplification error beside the generated vertices and indices.

Topology-constrained or already-small primitives may publish fewer levels. The canonical source
geometry always remains level zero.

The Model product schema owns the complete generated payload and reports separate source and LOD
vertex/index totals. Its import fingerprint includes the normalized LOD settings, so changing a
ratio, threshold, or enabled state rebuilds the product.

At resource registration, each imported primitive and retained LOD receives a name derived from
the Model UUID, primitive semantic key, and level number. Reimport therefore replaces surviving
Geometry entries in place. Removed levels are retired with generation bumps.

The base Geometry receives alternate handles, thresholds, and simplification-error metadata through
the public `set_geometry_lods` contract. Every level then builds ordinary resource-owned meshlets.
ECS model instances, CPU-reference selection, GPU visibility, debug views, and render submission
remain unaware of the import source.

## Consequences

Any imported static model can use the existing GPU LOD path without renderer-specific code.
Generated levels are deterministic cached asset work, while stable frames perform no simplification,
product scan, Geometry rebuild, or upload.

Model products and runtime registries retain additional geometry. Every retained alternate adds a
logical renderer batch even when GPU culling writes a zero indirect instance count. Shared WGPU
geometry arenas let compatible adjacent alternates share bindings and one fixed multi-draw
submission; see ADR-048. Projects can still reduce the number of levels, tune their thresholds, or
disable generation when retained topology or memory costs outweigh reduced triangle work.

The current simplifier preserves source attributes by choosing among source vertices. It does not
regenerate tangents, merge material primitives, or simplify animation, skins, or morph targets.
