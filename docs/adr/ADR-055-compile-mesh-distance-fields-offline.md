# ADR-055: Compile mesh distance fields offline

**Status:** Accepted
**Date:** 2026-08-08

## Context

World-space ambient occlusion, soft shadows, particle collision, and coarse spatial queries can all
consume the same mesh distance representation. Building that representation during startup would
make runtime cost depend on source triangle count, duplicate work across systems, and prevent
exported games from shipping only renderer-ready products.

An arbitrary imported primitive is not necessarily a closed solid. Assigning negative distances to
an open or non-manifold mesh from a fragile parity guess would make downstream queries confidently
wrong.

## Decision

Scrapbot owns one backend-independent offline mesh-distance-field compiler in the geometry package.
It builds a deterministic, padded voxel grid from indexed positions and accelerates nearest-
triangle and inside tests through a temporary bounding-volume hierarchy.

The compiler classifies topology before assigning a sign:

- A watertight mesh, where every undirected edge has exactly two incident triangles, produces a
  signed field.
- Open or non-manifold geometry produces an unsigned field. Consumers must treat it as distance to
  a surface, not distance to a solid interior.

The native compiler has a narrow allocation-owning C boundary. Odin validates and copies the result
into engine-owned memory before releasing native storage. Field construction remains invalidated
asset work; ordinary frames must never invoke it.

The compiler first produces full-precision samples so its accuracy and topology contract can be
tested independently. Model v18 then quantizes every sample into one signed 16-bit value with a
per-field scale. Zero remains exact, sign is preserved, and maximum reconstruction error is half
one quantization step.

Quantized samples live in an independently addressable Model-product chunk. Primitive catalog
records contain only dimensions, bounds, voxel and value scales, topology classification, and a
validated absolute byte range. Catalog loading does not read sample payloads. One range loader
reconstructs engine-owned quantized samples only for a consumer that requests them.

Runtime Geometry retains the validated descriptor and immutable Model-product range. The WGPU
backend lazily loads and packs a field into a geometry-versioned storage buffer only when a GPU
consumer requests it. Replacement, retirement, or renderer shutdown releases that cache; stable
frames neither read the product nor repeat the upload.

The camera's `distance_field` debug view samples a middle slice of the first submitted field. It uses
the same retained descriptor, bounded range loader, packing contract, and GPU buffer intended for
future consumers, so the visualization verifies the actual runtime path rather than a separate
importer preview.

The WGPU backend can compose requested mesh fields into three camera-relative world clipmaps. Each
32³ cascade snaps independently to its voxel grid at 1, 4, and 16 world-unit resolution. Geometry
samples seed the clipmaps through retained GPU instance transforms, and a five-step jump-flood
pass derives unsigned world-space surface distance without a CPU voxel rebuild.

The initial clipmap consumer is the `world_distance_field` debug view. It rebuilds only when its
snapped centers, viewport, world topology, Geometry topology, or relevant instance/Transform dirty
queues change. Stable debug frames retain the buffers and issue no clipmap upload or dispatch.
Incremental toroidal updates and production AO, shadow, particle, or visibility consumers remain
later slices.

HZB remains the primary visibility mechanism until a same-workload profile proves that
distance-assisted coarse rejection is cheaper and equally safe.

## Consequences

- AO, shadows, particles, and experimental visibility can converge on one geometry-derived input.
- Open assets remain useful without pretending they enclose a volume.
- The temporary BVH makes preprocessing scale better than testing every voxel against every
  triangle, but import time and product resolution still require representative benchmarks.
- Model products grow by two bytes per compiled voxel, while cache-hit catalog loading remains
  independent of that payload size.
- GPU residency is opt-in and change-driven; merely registering imported Geometry does not upload
  its distance field.
- World composition remains a backend-owned derived cache. It does not create an ECS component or
  a second asset representation.
