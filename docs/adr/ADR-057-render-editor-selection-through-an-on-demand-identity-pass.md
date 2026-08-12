# ADR-057: Render editor selection through an on-demand identity pass

**Date:** 2026-08-12

## Context

Click selection needs the nearest rendered object, while marquee selection needs exact visible identity intersected with strict projected-bounds containment. Bounded CPU rays approximate marquee visibility, miss small exposed fragments, and scale with candidate count and triangle-query cost. A continuously attached object-ID target would provide exact identity but charge every frame for an editor gesture that occurs only occasionally.

## Decision

WGPU performs selection through an on-demand integer identity pass. A released click or marquee requests one pass over the already retained render scene, using the same visibility buffers, submission modes, transforms, material alpha masks, custom vertex programs, and depth ordering as world rendering.

The pass renders stable instance-slot tokens into an `R32Uint` target with a dedicated depth attachment and scissors rasterization to the requested region. It copies only that region into a three-slot asynchronous readback ring. Each request snapshots slot-to-project-UUID ownership before submission, so a delayed result cannot resolve through a recycled ECS or renderer slot.

Click requests inspect a three-by-three neighborhood and choose the identity nearest the pointer center. Marquee requests deduplicate every visible identity and intersect that set with entities whose complete projected geometry bounds fit inside the rectangle. Generated Model primitives resolve to their root UUID. Editor overlay icons remain selected through their exact overlay hit regions.

Keep the identity target and readbacks backend-owned. Ordinary frames encode no selection pass and perform no selection readback. The Null backend retains deterministic CPU triangle picking and bounded visibility sampling as a fallback. CPU scene rays remain authoritative for tools such as placement that need a world-space contact and normal.

## Consequences

Selection follows the rendered scene's silhouettes, depth, alpha masking, custom displacement, conventional geometry, and virtual-geometry submission instead of approximating visibility with a handful of rays. Large marquee regions pay proportional readback bandwidth only on release, while ordinary rendering remains unchanged.

Selection results arrive asynchronously, normally on a later frame. The editor retains the current selection until completion. Transparent custom surfaces participate according to their shader-produced opacity and depth order; screen-space post effects, UI, outlines, grids, and non-pickable editor overlays do not become scene identities.

Every render path that changes vertex coverage or material opacity must preserve its selection variant. Backend-neutral callers receive UUID-based selection results rather than WGPU textures, slot numbers, or mapped buffers.
