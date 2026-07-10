# FDR-004: Luau scripting

**Status:** Active
**Last reviewed:** 2026-07-11

## Overview

Luau scripting lets project directories include fast-iteration game code without rebuilding Scrapbot. The runtime loads `scripts/main.luau` during `scrapbot run`, keeps the Luau VM alive for the run, and lets scripts register frame systems.

## Behavior

- Projects may include `scripts/main.luau`.
- `scrapbot init` creates a starter `scripts/main.luau`.
- `scrapbot run` executes the script after scene loading and ECS world construction.
- Script errors fail the run with a Luau diagnostic.
- `scrapbot run --hot-reload` periodically checks `scripts/main.luau` and the default scene TOML while renderer frames are advancing.
- Successful script reload replaces the active Luau runtime; failed script reload keeps the last good runtime.
- Successful scene reload rebuilds the ECS world and validates `scripts/main.luau` against it before swapping state; failed scene reload keeps the last good world and runtime.
- `scrapbot check` executes `scripts/main.luau` silently to collect project component schemas, validate scene data, and refresh `types/scrapbot.d.luau`.
- Scripts can call `scrapbot.log(message)`.
- Scripts can read `scrapbot.entity_count()` and `scrapbot.renderable_count()`.
- Scripts can define project components with `scrapbot.component(name, schema)`, where the first supported field type is `"vec3"`.
- Single-token component names such as `autorotate` are project-level components.
- Multi-token dotted component names such as `scrapbot.transform` or `scrappyphysics.rigidbody` are reserved for engine or library components and must be registered before scene data can use them.
- The engine registry currently contains built-in `scrapbot.transform`, `scrapbot.camera`, and `scrapbot.mesh` component names.
- `scrapbot.component` returns a typed component handle that scripts can cast to a generated component handle type.
- Scripts can register frame systems with `scrapbot.system(function(delta_seconds) ... end)`.
- Scripts can declare system component access with `scrapbot.system({ reads = {...}, writes = {...} }, function(delta_seconds) ... end)`.
- Script system access declarations accept project component handles or registered component-name strings.
- Scripts can query scene-defined custom components with `scrapbot.query(component_handle, callback)`.
- Project scripts annotate query callback component parameters with generated component payload aliases such as `Autorotate`.
- Scripts can read and write entity rotation through `scrapbot.get_rotation(entity)` and `scrapbot.set_rotation(entity, rotation)`.
- Scene files can attach simple custom vec3 component data with `[entities.components.<name>]` sections.
- Scene custom component data must match its registered schema. Project-level component schemas come from `scripts/main.luau`; engine component schemas come from the engine registry.
- Projects include Luau LSP metadata so editors can type-check the `scrapbot` global, engine component aliases, and project component aliases.

## Design Decisions

### 1. Start with one project entry script

**Decision:** Execute `scripts/main.luau` if it exists.
**Why:** A single conventional entry point is enough to verify embedding, project layout, and CLI behavior before introducing modules or script systems.
**Tradeoff:** There is no module loading yet, and hot reload currently targets only this conventional entry script.

### 2. Expose read-only ECS inspection first

**Decision:** The initial API exposes logging and ECS counts only.
**Why:** Read-only calls prove the Odin/Luau bridge without committing to component mutation semantics too early.
**Tradeoff:** Useful gameplay scripting still needs component APIs, queries, and system scheduling.

This was the first scripting slice. The current API has since grown a narrow ECS bridge for frame systems, custom component queries, and transform rotation mutation.

Access-declared systems now feed the runtime scheduler, but Luau execution remains serial.

### 3. Vendor Luau from source

**Decision:** Keep Luau as a pinned git submodule and build static libraries through `mise`.
**Why:** The local package manager distribution provides a CLI but not the embeddable headers and libraries Scrapbot needs.
**Tradeoff:** Build tasks now own native dependency compilation and platform-specific linker flags.

### 4. Ship project-local Luau editor definitions

**Decision:** Generate `types/scrapbot.d.luau` and `.vscode/settings.json` for new projects, then refresh the type file during `scrapbot check`.
**Why:** The Luau language server uses `luau-lsp.types.definitionFiles` mappings for custom globals, and project scripts need the `scrapbot` global plus component payload aliases to be known outside the running engine.
**Tradeoff:** The first editor integration is VS Code-oriented. Other editors may need equivalent Luau LSP settings until Scrapbot has editor-agnostic project metadata generation. `scrapbot check` must execute top-level script registration code to discover project component schemas.

### 5. Start custom components as simple scene data

**Decision:** Allow scripts to define project components with `scrapbot.component(name, schema)` and let scene files attach matching data with `[entities.components.<name>]` sections whose initial fields are vec3 values. Single-token component names are owned by the project, while multi-token dotted names are reserved for engine or future library registrations. `scrapbot.component` registers a project component schema and returns a handle that selects the component at runtime, while query callbacks use generated Luau aliases for the component payload type.
**Why:** This is enough for the first project-owned system, `autorotate.velocity`, while keeping the parser and Luau bridge small.
**Tradeoff:** Component schemas are still string schemas at runtime, so the schema table is not yet generated from the Luau payload type. Library component registration does not exist yet. Luau receives component tables dynamically, and only transform rotation has mutation helpers.

### 6. Use a registry for component ownership and scene validation

**Decision:** Keep a runtime component registry with built-in engine component names and project component schemas registered by Luau.
**Why:** The registry gives scene validation, script registration, query handles, and generated Luau type aliases one shared source of component ownership and basic field schemas.
**Tradeoff:** The registry is intentionally small: it supports vec3 schema fields only and does not yet provide a package mechanism for third-party libraries.

### 7. Check project files periodically for first hot reload

**Decision:** `--hot-reload` checks file modification stamps on a short interval while renderer frames are advancing.
**Why:** Periodic checks are portable, backend-neutral, and enough to validate runtime state replacement before introducing platform file watching services.
**Tradeoff:** Reloads are not immediate, and the first implementation watches the active default scene and `scripts/main.luau` rather than every project asset.

### 8. Feed Luau system declarations into the scheduler

**Decision:** Let Luau systems declare component reads and writes in an options table before the callback.
**Why:** The same script API that users write now should produce the scheduling metadata needed for future parallel execution.
**Tradeoff:** Access declarations are manually maintained for now. The runtime validates component names, but it does not yet enforce that system bodies only touch declared components.

## Related

- **ADRs:** ADR-001, ADR-002, ADR-006
- **FDRs:** FDR-001, FDR-002, FDR-005

## Open Questions

- Should `scrapbot check` invoke a Luau analyzer once the local Luau toolchain builds one?
- Should Luau modules resolve from project-local script directories, engine packages, or both?
- What file-watching contract should replace polling once Scrapbot has runtime services?
