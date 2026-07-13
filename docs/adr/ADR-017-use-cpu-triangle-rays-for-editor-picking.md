# ADR-017: Use CPU triangle rays for editor picking

**Date:** 2026-07-13

## Context

The editor needs viewport selection that agrees with the live camera, resized viewport, entity transforms, and resource-backed geometry. Screen-space bounds are imprecise, while a dedicated GPU identity pass adds another render target, pipeline, and asynchronous readback path before the editor requires that complexity.

## Decision

Initial editor picking casts a ray from the active camera through the clicked viewport coordinate and tests it against CPU-resident geometry triangles after applying each entity's live transform. The nearest positive intersection wins. Picking uses the same geometry registry and camera defaults as rendering.

## Consequences

Picking is precise for current indexed triangle geometry, deterministic in tests, and immediately supports scene-authored and runtime-spawned renderables. Its cost grows with visible triangle count, so broad-phase acceleration or a GPU identity pass may replace or precede triangle tests as scenes become larger. Non-geometry entities remain selectable through the entity browser.
