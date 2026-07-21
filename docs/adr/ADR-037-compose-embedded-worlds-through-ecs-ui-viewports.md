# ADR-037: Compose embedded worlds through ECS UI viewports

**Date:** 2026-07-21

## Context

Resource inspectors and project tools need real, interactive 3D previews. Reconstructing models as colored UI boxes loses geometry, materials, depth, and perspective, while editor-specific preview drawing would violate Scrapbot's single public ECS UI contract. Embedded views also need to remain correctly ordered, clipped, and scrolled with ordinary UI content without rebuilding the main UI stream or allocating renderer objects every frame.

## Decision

Add the authored public `scrapbot.ui_viewport` component. It targets a Texture, Model, or Material resource UUID, or the retained active World when the UUID is empty, with optional root and camera entity UUIDs. The component owns declarative orbit, distance, clear color, and interaction policy; the shared retained UI system owns pointer orbit/zoom behavior.

WGPU owns a bounded pool of independently sized color/depth targets, one slot per visible embedded viewport. Target dimensions follow the laid-out surface, are quantized to avoid resize churn, and remain bounded. The normal UI shader samples each pooled target as a paint command, preserving UI paint order, clipping, scrolling, and editor/project parity.

A resource UUID resolves to a Model, Material, or Texture target. Models render their imported hierarchy; Materials render on renderer-owned preview geometry; Textures use a direct aspect-preserving GPU presentation pass. These resource targets are isolated preview scenes with their own camera, lighting, environment color, and temporary presentation geometry. Static resource targets retain a cache keyed by component state, target aspect and size, exact resource versions, and relevant registry revisions. An empty resource UUID still targets the retained active World, with optional camera/root filtering, and consumes its retained render list rather than scanning ECS storage.

## Consequences

Projects, Luau, native Odin extensions, and editor composition use the same embedded viewport component. Texture, Model, and Material inspectors now share real GPU previews; interactive 3D previews support orbit, zoom, and reset through ordinary ECS controls. The initial WGPU pool supports eight simultaneous targets between 64 and 1024 pixels per axis and at most the backend's bounded preview draw capacity. Pool diagnostics expose active targets, pixels, resize count, redraw count, and cache hits.

Resource preview scenes are intentionally renderer-owned derived presentation, not independently simulated ECS worlds. World targets currently address the active retained World only. Explicit concurrent-world identity/lifecycle, per-target post-processing, and richer debug presentation remain future work. WGPU is the first implementing backend, while the public component remains backend-independent.
