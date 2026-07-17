# FDR-002: Text-first projects

**Status:** Active
**Last reviewed:** 2026-07-17

## Overview

Text-first projects let users run Scrapbot from an ordinary project directory containing a manifest and scene files. The format is meant to be inspectable and editable by humans and agents.

## Behavior

- A project has a `project.toml` manifest in its root directory.
- The manifest names the project and points at a default scene.
- The manifest can declare native extension targets with a name and source directory.
- The default generated scene lives at `scenes/main.scene.toml`, and its default material lives at `resources/default.resource.toml`.
- Authored project inputs use the conventional top-level directories `assets/`, `native/`, `resources/`, `scenes/`, and `scripts/`.
- Engine-generated editor metadata and caches live under ignored `.scrapbot/`; distributable package output alone lives under `build/`.
- `scrapbot init` creates a runnable camera-and-cube starter, derives the project name from the destination when omitted, creates ignore and Luau editor metadata, and refuses to overwrite any file it owns.
- Scene files describe entities and known components in TOML.
- Every scene entity has a required, non-zero, project-wide UUID. Names are editable display labels, and cross-entity references use UUIDs.
- Authored resources live in standalone `resources/**/*.resource.toml` files, have their own project-wide UUIDs, and are referenced by UUID from scenes. Resources are project data outside the ECS and are not owned by a scene.
- Project validation rejects missing manifests, unsafe scene or resource paths, malformed project metadata, malformed scene or resource data, duplicate resource UUIDs, unresolved resource references, unknown scene components, and scene data that does not match registered component schemas.
- Project validation refreshes generated Luau type definitions from the component registry.
- Project validation builds declared native extension targets before loading extension schemas.
- Example project directories live under `examples/` and can be used for smoke verification.

## Design Decisions

### 1. Use project.toml as the manifest

**Decision:** The project manifest is named `project.toml`.
**Why:** The name is short, conventional, and not tied to a prior engine name. See ADR-002.
**Tradeoff:** Generic filenames can collide with other tools in unusual project layouts, though this is unlikely for game project roots.

### 2. Start with a narrow TOML subset

**Decision:** The runtime currently parses only the schema subset Scrapbot generates.
**Why:** The first slice needed a small project contract without taking a dependency decision on a TOML parser. See ADR-002.
**Tradeoff:** Hand-authored files that use valid TOML features outside the subset may fail validation.

### 3. Validate scene components through the registry

**Decision:** `scrapbot check` executes `scripts/main.luau` silently to collect project-level and library component schemas, then validates all scene custom component data against the resulting registry.
**Why:** Project and library component data is only meaningful after scripts register matching schemas, while engine components are available from the initial registry.
**Tradeoff:** Project scripts should keep top-level work limited to registration and other check-safe setup until Scrapbot has a module/package loader for library registration.

### 4. Let project.toml declare native extension targets

**Decision:** Native extension build targets live in `[[native_extensions]]` manifest tables with a stable target name and source directory.
**Why:** Project authors should not need to remember platform output paths or external build scripts before running or checking a project.
**Tradeoff:** The manifest parser still supports only Scrapbot's narrow TOML subset, and extension targets currently assume Odin source directories.

### 5. Serialize entity identity separately from labels

**Decision:** Require a unique UUID in each scene entity's `id` field and reserve `name` for display, following ADR-023.
**Why:** Renaming a label must not break hierarchy links, editor selection, or future serialized references.
**Tradeoff:** Existing scene files need explicit IDs, and duplication tools must mint new IDs instead of copying them blindly.

### 6. Separate authored inputs, engine state, and products

**Decision:** Keep authored inputs in plainly named source directories, put regenerable engine state under `.scrapbot/`, and reserve `build/` for packages. See ADR-032.
**Why:** Projects should be easy to navigate and version-control without mixing source, IDE metadata, caches, and distributable output at the same level.
**Tradeoff:** Existing generated `types/` and `build/extensions`/`build/fonts` paths move and must be regenerated.

## Related

- **ADRs:** ADR-002, ADR-008, ADR-023, ADR-032
- **FDRs:** FDR-001, FDR-004, FDR-006

## Open Questions

- Should Scrapbot adopt a full TOML parser or publish a formal supported scene subset?
- How should scene migrations be represented once project files evolve?
