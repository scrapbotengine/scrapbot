# FDR-009: Project resources

**Status:** Active
**Last reviewed:** 2026-08-12

## Overview

Project resources are reusable, typed bags of authored data stored outside the ECS. Supported types include renderer resources, compiled UI icon sets, and composition-time UI themes.

## Behavior

- Scrapbot discovers `resources/**/*.resource.toml` recursively.
- Every resource declares a unique non-zero UUID, type, and editable display name.
- An icon-set resource names a safe source directory under `assets/`. Each SVG filename defines a symbolic monochrome icon; runtime UI references the resource UUID plus that symbol rather than a mutable resource name.
- A material resource stores base color, HDR emissive color, metallic and roughness factors, and an optional Texture resource reference.
- A UI-theme resource explicitly inherits a built-in theme and overrides semantic HDR palette colors, metric scales, and a declared project font or embedded Inter. It resolves only at scene, Luau, native, or editor composition boundaries.
- Scene material components reference a resource UUID, never its name or source path.
- Project loading rejects malformed resources, duplicate UUIDs, unsafe paths, invalid material data, and unresolved scene material references.
- Authored resources load before scene render reconciliation. Content reload preserves runtime handle identity and increments the resource version; removal invalidates old handles; reappearance reuses the registry slot with a new generation.
- Runtime-created Luau or native materials remain transient, name-addressed resources and cannot overwrite authored project materials.
- A dedicated Resources dock presents the recursive `resources/` hierarchy through Back, Refresh, breadcrumb, search, type labels, and one public uniformly virtualized list. Folder navigation reads bounded file metadata only. Rows join registry resources to their authored source directory and include Materials, Textures, Environments, Models, Icon Sets, Shaders, Geometry LODs, and UI Themes.
- Resource rows show cached Texture, Model, or Material thumbnails when the renderer supports a preview, and atlas-backed type icons otherwise. Missing or stale laid-out previews render once through a scratch target into a 256-layer 64×64 texture-array cache (4 MiB), keyed by resource UUID, version, and dependency revisions with least-recently-used eviction. Model thumbnails request virtual submission and therefore use pinned coarse proxies for eligible large geometry instead of forcing complete conventional uploads; an unsupported primitive falls back to its type icon without failing the frame. Model rows retain stopped-mode drag placement.
- While stopped, the browser can create, duplicate, rename, move, and delete resources. These operations preserve UUID references, enter bounded structural Undo/Redo history, and remain in memory until Save. Deletion is blocked while any live non-editor entity references the resource UUID.
- The entity material panel presents the referenced resource, stable UUID, and inline numeric controls for base color, emissive color, metallic, and roughness. A reusable ECS-built popup switches references between known authored materials.
- Inline material values use the ordinary numeric input contract during every playback state. Running or paused edits preview immediately as disposable runtime changes and Stop restores the captured authoring resource values. Stopped edits become authoring transactions with Undo/Redo. Resource-reference changes remain stopped-mode structural authoring. Save validates every dirty resource and scene candidate, then commits their standalone files together through one recoverable project transaction. Revert reloads project resources and scene entities without reloading Luau or Odin.
- Resource data itself is not an ECS entity or component. Only editor presentation uses the public ECS UI contract.

## Design Decisions

### 0. Keep browsing separate from loading and filesystem capabilities

**Decision:** Build the Resource Browser over the rooted metadata model from ADR-060 and join visible paths to the authoritative resource registry.

**Why:** Directory discovery must stay cheap and reusable for later open/save dialogs without granting arbitrary filesystem mutation or duplicating resource ownership.

**Tradeoff:** Browser refresh is explicit and symlinked directories are excluded. Renderable thumbnails use a fixed 4 MiB GPU cache rather than eager directory-sized storage. Interactive Inspector/project surfaces retain the separate eight-target live viewport pool; a missing, evicted, unsupported, or not-yet-generated thumbnail shows its type icon.

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

### 6. Store project shader source as a typed resource

**Decision:** Give WGSL hook source its own UUID-backed `scrapbot.shader` resource and let Materials reference it plus four generic `Vec4` parameter slots. An optional typed `spectral_surface` block requests an engine-generated wind spectrum for the same shader.

**Why:** Shader identity, safe source paths, hot reload, cache versioning, and cross-resource validation belong to the same project-resource pipeline as other reusable assets.

**Tradeoff:** Parameters are intentionally fixed-size and unreflected in this slice. Spectral
surfaces reserve up to three portable 64×64 frequency bands and expose displacement, reconstructed
normals, crest compression, and current-advected foam history. Larger grids, spatial current and
shoreline masks, and scalable quality tiers remain follow-up work.

## Related

- **ADRs:** ADR-002, ADR-010, ADR-023, ADR-027, ADR-030, ADR-031, ADR-036, ADR-041, ADR-046, ADR-058, ADR-060
- **FDRs:** FDR-002, FDR-003, FDR-008, FDR-011

## Open Questions

- Which resource types should follow materials next?
- Which resource families besides UI themes should expose authored UUID lookup directly to Luau and native extensions?
- How should nested resource references and dependency cycles be represented?
