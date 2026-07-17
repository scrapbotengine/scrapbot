# ADR-010: Keep render resources outside the ECS

**Date:** 2026-07-12

## Context

Geometry and material data may be shared by many entities and may have backend-specific GPU representations. Storing complete geometry, material, or GPU objects in entity components would duplicate ownership and leak backend details into gameplay state.

## Decision

Own geometry and material descriptions in engine resource registries addressed by generational runtime handles. Authored project resources additionally have stable project-wide UUIDs outside the ECS; scene files serialize those UUIDs and world loading resolves them to handles. Store only resolved handles in public ECS components. Generate primitive geometry through the same full indexed-geometry representation used by custom and imported meshes. Keep backend GPU objects in backend-owned caches keyed by resource handle and content version. See ADR-030.

## Consequences

Entities can cheaply share geometry and materials, authored resource updates preserve handle identity across reloads, and rendering backends remain free to manage their own GPU lifetimes. The runtime must explicitly coordinate resource-registry, ECS-world, and backend-cache lifetimes. Persistent UUID references require validation and stale handles make an entity temporarily non-renderable.
