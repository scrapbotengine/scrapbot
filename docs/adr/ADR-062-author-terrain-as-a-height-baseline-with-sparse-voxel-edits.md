# ADR-062: Author terrain as a height baseline with sparse voxel edits

**Date:** 2026-08-20

## Context

Heightfield terrain is compact and familiar to author, but it cannot represent caves, overhangs,
arches, or other topology that is not a single height for each horizontal position. A fully sparse
volumetric field can represent those shapes, but exposing field construction as the primary
authoring model makes ordinary terrain work abstract and cumbersome.

Terrain sculpting must also remain interactive. Rebuilding a complete terrain or synchronously
compiling every renderer representation after each brush sample would create visible multi-second
stalls and violate Scrapbot's change-driven derived-state invariant.

## Decision

Represent an authored Terrain resource as one canonical scalar field with two source layers:

- tiled height data defines the compact solid-below-surface baseline; and
- sparse signed-density voxel bricks store only deviations from that baseline.

Users author the baseline with familiar surface tools and author arbitrary topology with volumetric
add/subtract tools. Signed-distance operations may generate voxel changes, but the editor does not
expose an SDF graph as the ordinary authoring experience.

Partition surface extraction into fixed world-space chunks. Evaluate every chunk, including an
untouched baseline chunk, from the same canonical field and shared lattice samples. Use an
deterministic tetrahedralized-cube extraction contract with shared-edge interpolation so
independently built neighbors agree at their boundaries. This avoids ambiguous cube faces in the
first implementation while preserving a later path to a compatible indexed Marching Cubes table.

Brush input mutates only bounded source tiles and bricks and enqueues the intersecting extraction
chunks. Candidate meshing and Geometry construction run away from the interactive frame. The last
valid surface remains drawable until a complete candidate is ready, and main-thread commits and
uploads obey explicit per-frame work budgets. Stable frames scan, mesh, hash, and upload no terrain
state.

Store authored terrain source separately from derived render products. A Terrain project resource
owns stable UUID identity and a source package containing a text manifest plus independently
writable height and voxel tiles. Generated surface chunks, meshlets, hierarchy pages, and backend
caches are derived products. Stopped-mode gestures enter bounded authoring history; Save includes
changed terrain source files in the recoverable project transaction.

Generated surface chunks use ordinary Geometry resources and renderer contracts. Terrain owns
spatial chunk residency and invalidation; WGPU continues to own Geometry submission, meshlets,
Virtual Geometry pages, and backend caches without terrain-specific global capacity changes.

## Consequences

Ordinary hills remain compact and use familiar sculpting tools, while sparse edits can form smooth
caves and overhangs without allocating a dense volume for the complete world. Surface generation,
streaming, rendering, and persistence have explicit ownership and can remain proportional to actual
changes.

The engine gains a new persistent source format, resource registry, scene component, extraction
package, background candidate lifecycle, editor tool, and save/recovery coverage. Border sampling,
surface ambiguity resolution, cancellation, stale completion rejection, and Undo/Redo tile ownership
become correctness-critical.

The first feature slice is finite and editor-authored. Runtime deformation, unbounded world
streaming, material painting, erosion, persistent procedural modifiers, and tunnel splines build on
the same authority but are not implied by this decision.
