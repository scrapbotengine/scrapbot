# FDR-004: Luau scripting

**Status:** Active
**Last reviewed:** 2026-07-08

## Overview

Luau scripting lets project directories include fast-iteration game code without rebuilding Scrapbot. The runtime loads `scripts/main.luau` during `scrapbot run`, keeps the Luau VM alive for the run, and lets scripts register frame systems.

## Behavior

- Projects may include `scripts/main.luau`.
- `scrapbot init` creates a starter `scripts/main.luau`.
- `scrapbot run` executes the script after scene loading and ECS world construction.
- Script errors fail the run with a Luau diagnostic.
- Scripts can call `scrapbot.log(message)`.
- Scripts can read `scrapbot.entity_count()` and `scrapbot.renderable_count()`.
- Scripts can define project components with `scrapbot.component(name, schema)`, where the first supported field type is `"vec3"`.
- Single-token component names such as `autorotate` are project-level components.
- Multi-token dotted component names such as `scrapbot.transform` or `scrappyphysics.rigidbody` are reserved for engine or library components.
- `scrapbot.component` returns a typed component handle that scripts can cast to a project-local handle type.
- Scripts can register frame systems with `scrapbot.system(function(delta_seconds) ... end)`.
- Scripts can query scene-defined custom components with `scrapbot.query(component_handle, callback)`.
- Project scripts annotate query callback component parameters with their local component payload type.
- Scripts can read and write entity rotation through `scrapbot.get_rotation(entity)` and `scrapbot.set_rotation(entity, rotation)`.
- Scene files can attach simple custom vec3 component data with `[entities.components.<name>]` sections.
- Scene custom component data must match a component schema defined by `scripts/main.luau`.
- Projects include Luau LSP metadata so editors can type-check the `scrapbot` global.

## Design Decisions

### 1. Start with one project entry script

**Decision:** Execute `scripts/main.luau` if it exists.
**Why:** A single conventional entry point is enough to verify embedding, project layout, and CLI behavior before introducing modules or script systems.
**Tradeoff:** There is no module loading or hot reload yet.

### 2. Expose read-only ECS inspection first

**Decision:** The initial API exposes logging and ECS counts only.
**Why:** Read-only calls prove the Odin/Luau bridge without committing to component mutation semantics too early.
**Tradeoff:** Useful gameplay scripting still needs component APIs, queries, and system scheduling.

This was the first scripting slice. The current API has since grown a narrow ECS bridge for frame systems, custom component queries, and transform rotation mutation.

### 3. Vendor Luau from source

**Decision:** Keep Luau as a pinned git submodule and build static libraries through `mise`.
**Why:** The local package manager distribution provides a CLI but not the embeddable headers and libraries Scrapbot needs.
**Tradeoff:** Build tasks now own native dependency compilation and platform-specific linker flags.

### 4. Ship project-local Luau editor definitions

**Decision:** Generate `types/scrapbot.d.luau` and `.vscode/settings.json` for new projects.
**Why:** The Luau language server uses `luau-lsp.types.definitionFiles` mappings for custom globals, and project scripts need the `scrapbot` global to be known outside the running engine.
**Tradeoff:** The first editor integration is VS Code-oriented. Other editors may need equivalent Luau LSP settings until Scrapbot has editor-agnostic project metadata generation.

### 5. Start custom components as simple scene data

**Decision:** Allow scripts to define project components with `scrapbot.component(name, schema)` and let scene files attach matching data with `[entities.components.<name>]` sections whose initial fields are vec3 values. Single-token component names are owned by the project, while multi-token dotted names are reserved for the engine or future libraries. `scrapbot.component` returns a handle that selects the component at runtime, while query callbacks use explicit Luau annotations for the component payload type.
**Why:** This is enough for the first project-owned system, `autorotate.velocity`, while keeping the parser and Luau bridge small.
**Tradeoff:** Component schemas are still string schemas at runtime, so the schema table is not yet generated from the Luau payload type. Namespaced component schemas are not registered yet. Luau receives component tables dynamically, and only transform rotation has mutation helpers.

## Related

- **ADRs:** ADR-001, ADR-002, ADR-006
- **FDRs:** FDR-001, FDR-002

## Open Questions

- How should script systems declare component access before the ECS scheduler becomes real?
- How should component schemas become typed generated Luau APIs instead of stringly runtime declarations?
- Should Luau modules resolve from project-local script directories, engine packages, or both?
- What file-watching contract should drive script hot reload?
