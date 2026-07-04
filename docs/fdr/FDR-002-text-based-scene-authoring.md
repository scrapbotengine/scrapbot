# FDR-002: Text-Based Scene Authoring

**Status:** Active
**Last reviewed:** 2026-07-05

## Overview

Text-based scene authoring defines how projects describe scenes, entities, components, references, and prefab usage in source-controlled text files. It exists so humans, editors, scripts, and coding agents can all inspect and modify scene structure directly.

## Behavior

- Scenes are stored as text files in a documented, schema-validated format.
- Scene files describe entities, names, component data, and eventually hierarchy, references to assets, scripts, prefabs, and other project resources.
- The initial scene format uses TOML-shaped text files, starting with `scenes/main.scene.toml`.
- The current entity schema uses `[[entities]]` records with stable text ids and names, then component data under `[entities.components.<id>]` tables.
- Engine component tables currently include `[entities.components."machina.transform"]` with `position`, `rotation`, and `scale` `vec3` fields; `[entities.components."machina.geometry.primitive"]` for built-in primitive selection; `[entities.components."machina.material.surface"]` with base color; `[entities.components."machina.renderer"]` for the scene renderer singleton; legacy `[entities.components."machina.render.cube"]` with a `color` `vec3` field; `[entities.components."machina.camera"]` with projection fields; `[entities.components."machina.light.directional"]` with directional light fields; marker tables for `[entities.components."machina.shadow.caster"]` and `[entities.components."machina.shadow.receiver"]`; and UI tables such as `[entities.components."machina.ui.canvas"]`, `[entities.components."machina.ui.rect"]` with `position`, `size`, `color`, and `corner_radius`, `[entities.components."machina.ui.text"]`, `[entities.components."machina.ui.button"]`, `[entities.components."machina.ui.command"]`, `[entities.components."machina.ui.scroll_view"]`, `[entities.components."machina.ui.vbox"]`, `[entities.components."machina.ui.hgroup"]`, `[entities.components."machina.ui.stack"]`, `[entities.components."machina.ui.layout.item"]`, `[entities.components."machina.ui.spacer"]`, `[entities.components."machina.ui.text_block"]`, `[entities.components."machina.ui.toggle"]`, `[entities.components."machina.ui.progress_bar"]`, and `[entities.components."machina.ui.separator"]`.
- Runtime-only components such as `machina.ui.command_event` and `machina.input.*` are engine-owned transient data and should not be authored in scene files.
- Project and package component tables may appear in scenes after scripts register matching component schemas.
- Scene references are forward-slash, project-relative paths and may not escape the project directory.
- Scene files are stable under repeated editor saves when the scene has not changed.
- Invalid scene files produce precise diagnostics suitable for command-line and editor display.
- Duplicate entity ids are invalid because stable ids are the anchor for component lookup and future live reload patching.
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

### 3. Author explicit component tables

**Decision:** Scene entities author component instances as explicit component tables instead of top-level kind-specific fields.
**Why:** Component tables make scene data line up with the runtime ECS model, script-declared schemas, validation, and future editor inspection. It follows ADR-008 and ADR-010.
**Tradeoff:** Scene loading must build the script registry before validating component tables, and schema migrations need to account for both engine and script-defined components.

## Related

- **ADRs:** ADR-001, ADR-006, ADR-008, ADR-009
- **FDRs:** FDR-001, FDR-004, FDR-005, FDR-006, FDR-009, FDR-010, FDR-014, FDR-015, FDR-017, FDR-020

## Open Questions

- How much schema versioning is needed before the first playable slice?
