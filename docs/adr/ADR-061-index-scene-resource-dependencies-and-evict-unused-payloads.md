# ADR-061: Index scene resource dependencies and evict unused payloads

**Date:** 2026-08-12

## Context

ADR-058 made scene replacement transactional, but the runtime still registered every declared project resource at startup. A project therefore paid the CPU memory cost of textures, environments, imported Model catalogs, generated Geometry and Materials, Shaders, and UI Themes even when its active scene could not reference them. Marking registry entries dead was also insufficient: several families retained their owned payload slices.

Scene transitions need bounded overlap without weakening stable UUID identity, generational handle safety, transactional activation, hot reload, or Revert. Resource dependencies must be known before a candidate World resolves handles. A failed candidate must not evict anything used by the active World.

## Decision

Project discovery computes a dependency-first, deduplicated resource closure for every scene. Direct references come from Model, Geometry, Material, UI Theme, Icon Set, and World Environment components. Material dependencies recursively include their Texture and Shader. Project-config lighting and background environments are always-resident dependencies.

The runtime owns a `Resource_Residency` service beside the project-wide `resources.Registry`. It owns cloned project declarations, active and staging closures, pending evictions, and a monotonic frame counter. Startup registers only the active closure plus always-resident resources.

A replace transition admits the complete destination closure before building and resolving the candidate World. Active and staging closures coexist during preparation. Candidate failure or cancellation retains the active closure and schedules staging-only resources for cleanup; successful activation atomically promotes staging ownership and schedules old-only resources for eviction.

Eviction has a three-frame grace period. A rapid return cancels pending eviction. Shared resources remain resident without re-registration. Actual retirement releases family-owned CPU payloads—including imported Model-generated Geometry and Material payloads—then increments generations so stale ECS and backend handles cannot become valid again accidentally. Registry indexes remain stable and authored UUID slots are reused on later admission.

The current admission step is synchronous. Time-budgeted/background preload, progress, cancellation exposed to projects, byte budgets, and pressure-driven early eviction remain later layers; they must preserve this ownership and activation contract.

## Consequences

Startup memory is proportional to the active scene's dependency closure rather than the complete project catalog. Repeated A↔B transitions reuse stable registry slots and cannot accumulate payloads from every visited scene. Transition peak CPU memory is the union of active and destination closures plus one candidate World; the grace window briefly retains resources from the previous scene after activation.

Scene discovery performs dependency analysis once per project load. Hot reload rebuilds the active closure transactionally, while Revert reloads only that closure. Adding a new resource-reference field requires adding it to validation and closure extraction in the same change.
