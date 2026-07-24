# FDR-009: Project resources

**Status:** Active
**Last reviewed:** 2026-07-24

## Overview

Project resources are reusable, typed bags of authored data stored outside the ECS. The first supported resource type is `scrapbot.material`.

## Behavior

- Scrapbot discovers `resources/**/*.resource.toml` recursively.
- Every resource declares a unique non-zero UUID, type, and editable display name.
- A material resource stores base color, HDR emissive color, metallic and roughness factors, and an optional Texture resource reference.
- Scene material components reference a resource UUID, never its name or source path.
- Project loading rejects malformed resources, duplicate UUIDs, unsafe paths, invalid material data, and unresolved scene material references.
- Authored resources load before scene render reconciliation. Content reload preserves runtime handle identity and increments the resource version; removal invalidates old handles; reappearance reuses the registry slot with a new generation.
- Runtime-created Luau or native materials remain transient, name-addressed resources and cannot overwrite authored project materials.
- A reusable ECS-built resource browser lists authored materials alongside the scene browser. Selecting a resource opens the ordinary inspector stack with editable name and relative source path, inline base-color, emissive, metallic, and roughness controls, texture metadata, usage count, deletion availability, and Find Usage.
- While stopped, the browser can create, duplicate, rename, move, and delete resources. These operations preserve UUID references, enter bounded structural Undo/Redo history, and remain in memory until Save. Deletion is blocked while any live non-editor entity references the resource UUID.
- The entity material panel presents the referenced resource, stable UUID, and inline numeric controls for base color, emissive color, metallic, and roughness. A reusable ECS-built popup switches references between known authored materials.
- Inline material values use the ordinary numeric input contract during every playback state. Running or paused edits preview immediately as disposable runtime changes and Stop restores the captured authoring resource values. Stopped edits become authoring transactions with Undo/Redo. Resource-reference changes remain stopped-mode structural authoring. Save validates every dirty resource and scene candidate, then commits their standalone files together through one recoverable project transaction. Revert reloads project resources and scene entities without reloading Luau or Odin.
- Resource data itself is not an ECS entity or component. Only editor presentation uses the public ECS UI contract.

## Design Decisions

### 1. Keep project resources independent from scenes

**Decision:** Store resources under the project root rather than embedding them in a scene or giving them scene-owned ECS entities.
**Why:** Shared data must outlive and cross scene boundaries without acquiring fake entity semantics.
**Tradeoff:** Loading and persistence coordinate a resource registry alongside the world.

### 2. Reference authored resources by UUID

**Decision:** Serialize stable UUID references and reserve names and paths for presentation and storage.
**Why:** Renaming or moving a resource must not break every consumer.
**Tradeoff:** Text files are less mnemonic than name references, so tooling must show labels alongside IDs.

### 3. Use typed standalone files

**Decision:** Put one typed resource in each `.resource.toml` file and save only dirty files.
**Why:** Small isolated diffs, independent hot reload, and scalable authoring are more important than a single aggregate database.
**Tradeoff:** Cross-resource validation and bulk operations require project-wide discovery.

### 4. Keep runtime handles internal

**Decision:** Resolve UUIDs to generational handles when loading the world and let renderer caches use handle plus version.
**Why:** Runtime code needs compact validated references and efficient cache invalidation, while project files need stable identity.
**Tradeoff:** The engine maintains both persistent UUID identity and transient runtime identity.

### 5. Treat resource lifecycle as stopped authoring

**Decision:** Apply lifecycle operations to the registry through before/after resource snapshots and persist them only through explicit project Save.
**Why:** Undo/Redo, Play/Stop, Revert, and Save need one coherent authoring model, while runtime systems must never create accidental file mutations.
**Tradeoff:** Save must derive a filesystem delta from the disk baseline and the live registry, and deletion needs reference-aware validation.

## Related

- **ADRs:** ADR-002, ADR-010, ADR-023, ADR-027, ADR-030, ADR-031, ADR-036
- **FDRs:** FDR-002, FDR-003, FDR-008, FDR-011

## Open Questions

- Which resource types should follow materials next?
- When should Scrapbot expose authored resource lookup directly to Luau and native extensions?
- How should nested resource references and dependency cycles be represented?
