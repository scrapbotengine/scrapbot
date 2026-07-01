# FDR-002: Text-Based Scene Authoring

**Status:** Active
**Last reviewed:** 2026-07-01

## Overview

Text-based scene authoring defines how projects describe scenes, entities, components, references, and prefab usage in source-controlled text files. It exists so humans, editors, scripts, and coding agents can all inspect and modify scene structure directly.

## Behavior

- Scenes are stored as text files in a documented, schema-validated format.
- Scene files describe entities, names, component data, and eventually hierarchy, references to assets, scripts, prefabs, and other project resources.
- The initial scene format uses TOML-shaped text files, starting with `scenes/main.scene.toml`.
- The current renderable entity schema uses `[[entities]]` records with stable text ids, names, `kind = "cube"`, and vector properties for position, rotation, scale, color, and spin.
- Scene references are forward-slash, project-relative paths and may not escape the project directory.
- Scene files are stable under repeated editor saves when the scene has not changed.
- Invalid scene files produce precise diagnostics suitable for command-line and editor display.
- Scene authoring is separate from behavior scripting; scripts can be referenced by scene components but do not replace scene data.

## Design Decisions

### 1. Store scene structure as engine-owned data

**Decision:** Scenes are authoritative data files, not script files or serialized editor memory.
**Why:** This keeps structural project state diffable, validatable, and safe for agent edits. It follows ADR-001 and ADR-006.
**Tradeoff:** The engine must maintain a scene schema and migration story as scene capabilities evolve.

### 2. Require stable formatting from engine writes

**Decision:** Editor and tool writes should preserve deterministic ordering and formatting where possible.
**Why:** Clean diffs are central to human review and agentic workflows.
**Tradeoff:** File writers need deliberate formatting rules instead of naive serialization.

### 3. Start with explicit component-shaped fields

**Decision:** The first renderable entity schema uses named scalar/vector fields rather than embedding ad hoc script code or opaque blobs.
**Why:** It keeps the data easy to inspect, validate, diff, and edit by agents while leaving room to evolve toward explicit component tables later. It follows ADR-008.
**Tradeoff:** The schema is intentionally narrow and only supports cube renderables in this slice.

## Related

- **ADRs:** ADR-001, ADR-006, ADR-008, ADR-009
- **FDRs:** FDR-001, FDR-004, FDR-006, FDR-009, FDR-010

## Open Questions

- How much schema versioning is needed before the first playable slice?
