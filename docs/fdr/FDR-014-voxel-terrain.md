# FDR-014: Voxel Terrain

**Status:** Experimental
**Last reviewed:** 2026-08-20

## Overview

Voxel Terrain gives creators discrete, spatial add/remove actions like a block-building game while
extracting a smooth surface. A compact outdoor baseline can therefore grow caves, arches, and
overhangs without exposing an abstract field graph or forcing the visible result to look cubic.

## Current Experimental Slice

- `scrapbot.geometry.voxel_surface` converts a finite sampled density lattice into smooth indexed
  Geometry. Positive samples are solid and negative samples are empty.
- `examples/voxel-terrain-lab` demonstrates a rolling surface, a curved hill tunnel, a freestanding
  arch, and an overhang through ordinary Conventional Geometry and lighting. Its authored
  terrain shader applies matte world-space grass, soil, and rock variation by surface slope without
  coupling terrain extraction to one renderer material policy.
- The canonical terrain package composes a tiled height baseline with sparse lattice-density edits.
  Deterministic neighboring chunks agree at shared boundaries and reuse vertices along shared edges.
- Spherical add/subtract brush mutations enqueue only affected chunks. The dirty queue deduplicates
  repeated invalidations and yields bounded incremental rebuild work; stable frames yield no work.
- The current Luau Geometry bridge is transient and samples a dense finite field at startup. It is a
  runnable integration path, not the persistent terrain authoring contract.
- A transient voxel surface retains its source samples in the runtime Geometry entry. In stopped
  editor mode, selecting a scene-authored named Mesh backed by that surface reveals **Add Cell** and
  **Remove** tools. Exact triangle hits select one adjacent or interior voxel cell, and a green or
  red wireframe previews that fixed spatial operation.
- Each click changes at most one bounded 4 × 4 × 4 lattice neighborhood and enters ordinary
  Undo/Redo history. The experimental bridge still rebuilds its complete finite Geometry
  synchronously, and its source is not included in Save. Save remains unavailable until applied
  transient edits are undone. Revert restores one bounded baseline snapshot per edited voxel source,
  including changes older than the Undo window, and rolls that restoration back if the project
  transaction fails. Persistent chunk source and candidate meshing remain required before this
  becomes the durable Terrain resource workflow.

## Planned Authoring Contract

- A project can declare a finite Terrain resource and place it in a scene through one terrain root.
- Untouched terrain begins as a conventional height-based surface.
- Direct Add Cell and Remove Cell actions are the primary topology workflow. A click targets one
  quantized terrain cell from the pointed surface; dragging does not spray a continuous brush.
- Optional Raise, Lower, Smooth, and Flatten tools may later reshape broader baseline regions, but
  do not replace the direct cell workflow.
- Cell feedback remains responsive while affected surface regions rebuild incrementally.
- Unaffected regions remain visible and perform no rebuild work.
- Terrain edits made while authoring is stopped participate in Undo, Redo, Save, and Revert.
- Caves, overhangs, arches, and cliffs render, receive shadows, and can be selected through the same
  world-rendering behavior as other geometry.

## Design Decisions

### 1. Make authored intent discrete and spatial

**Decision:** Expose fixed, snapped Add Cell and Remove Cell operations as the primary topology
workflow while rendering their combined density field smoothly.
**Why:** Pointing at a surface and placing or removing one spatial unit is immediate, predictable,
and familiar from block-building games. It avoids radius/falloff management for ordinary edits.
**Tradeoff:** Broad shaping is slower until optional region, stamp, and baseline tools arrive;
procedural field graphs and editable operation stacks remain future tools.

### 2. Keep ordinary terrain compact

**Decision:** Treat the height surface as the default terrain and retain volumetric data only where
the authored result differs.
**Why:** Most terrain volume is predictable solid ground and should not consume explicit voxels.
**Tradeoff:** Editing the baseline beneath volumetric changes requires deterministic composition.

### 3. Never block an edit on the complete terrain

**Decision:** Preserve the last valid surface while changed regions rebuild independently under
bounded work budgets.
**Why:** Terrain authoring must remain interactive regardless of total world size.
**Tradeoff:** The final surface may follow the live brush preview by a short bounded delay.

### 4. Ship finite authoring before unbounded simulation

**Decision:** Begin with finite editor-authored terrain and persistent stopped-mode edits.
**Why:** This proves the source, topology, authoring, rendering, and lifecycle contracts before
adding runtime destruction or world-scale streaming policy.
**Tradeoff:** Games cannot yet mutate terrain during playback or stream an unbounded terrain world.

## Related

- **ADRs:** ADR-010, ADR-024, ADR-030, ADR-031, ADR-032, ADR-034, ADR-046, ADR-049, ADR-050, ADR-062
- **FDRs:** FDR-003, FDR-008, FDR-009, FDR-011

## Open Questions

- How should painted material layers augment the slope-driven authored terrain shader contract?
- Which persistent stamp and spline tools should remain editable instead of baking into voxel data?
