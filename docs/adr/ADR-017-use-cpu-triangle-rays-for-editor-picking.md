# ADR-017: Use CPU triangle rays for editor spatial queries (superseded for selection by ADR-057)

**Date:** 2026-07-13

## Context

The editor needs viewport selection that agrees with the live camera, resized viewport, entity transforms, and resource-backed geometry. Screen-space bounds are imprecise, while a dedicated GPU identity pass adds another render target, pipeline, and asynchronous readback path before the editor requires that complexity.

## Decision

Initial editor picking casts a ray from the active camera through the clicked viewport coordinate and tests it against CPU-resident geometry triangles after applying each entity's live transform. The nearest positive intersection wins. Picking uses the same geometry registry and camera defaults as rendering.

ADR-057 supersedes this decision for click and marquee entity selection. CPU triangle rays remain the backend-neutral spatial-query contract for placement and transform tools that need a world position and normal rather than rendered identity.

## Consequences

CPU spatial queries remain precise and deterministic for tools that require surface data. Selection no longer inherits their linear instance discovery or canonical-triangle traversal cost on WGPU. The Null backend retains CPU picking as its deterministic fallback.
