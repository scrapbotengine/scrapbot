# FDR-002: Text-Based Scene Authoring

**Status:** Active
**Last reviewed:** 2026-07-01

## Overview

Text-based scene authoring defines how projects describe scenes, entities, components, references, and prefab usage in source-controlled text files. It exists so humans, editors, scripts, and coding agents can all inspect and modify scene structure directly.

## Behavior

- Scenes are stored as text files in a documented, schema-validated format.
- Scene files describe entities, names, hierarchy or relationships, components, and references to assets, scripts, prefabs, and other project resources.
- The initial scene format uses TOML-shaped text files, starting with `scenes/main.scene.toml`.
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

## Related

- **ADRs:** ADR-001, ADR-006
- **FDRs:** FDR-001, FDR-004, FDR-006

## Open Questions

- How much schema versioning is needed before the first playable slice?
