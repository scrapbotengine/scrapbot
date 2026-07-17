# FDR-004: Luau scripting

**Status:** Active
**Last reviewed:** 2026-07-16

## Overview

Luau scripting lets project directories include fast-iteration game code without rebuilding Scrapbot. The runtime loads `scripts/main.luau` during `scrapbot run`, keeps the Luau VM alive for the run, and lets scripts register frame systems.

## Behavior

- Projects may include `scripts/main.luau`.
- `scrapbot init` creates a starter `scripts/main.luau`.
- `scrapbot run` executes the script after scene loading and ECS world construction.
- Script errors fail the run with a Luau diagnostic.
- `scrapbot run --hot-reload` periodically checks `project.toml`, the default scene TOML, `scripts/main.luau`, `assets/`, native extension libraries, and declared native extension source directories while renderer frames are advancing.
- Successful script reload replaces the active Luau runtime; failed script reload keeps the last good runtime.
- Successful scene reload rebuilds the ECS world and validates `scripts/main.luau` against it before swapping state; failed scene reload keeps the last good world and runtime.
- `scrapbot check` executes `scripts/main.luau` silently to collect project and library component schemas, validate scene data, and refresh `.scrapbot/types/scrapbot.d.luau`.
- When `luau-analyze` is available, `scrapbot check` also statically analyzes `scripts/main.luau` against the refreshed generated types.
- Scripts can call `scrapbot.log(message)`.
- Scripts can read `scrapbot.entity_count()` and `scrapbot.renderable_count()`.
- Scripts can define project components with `scrapbot.component(name, schema)`, where the first supported field marker is `scrapbot.vec3`.
- Scripts can define library components with `scrapbot.library_component(name, schema)`.
- Scripts can retrieve already registered engine, library, or native-extension component handles with `scrapbot.component_handle(name)`.
- Component schemas still accept the legacy `"vec3"` field type string for compatibility.
- Single-token component names such as `autorotate` are project-level components.
- Multi-token dotted component names such as `scrapbot.transform` or `scrappyphysics.rigidbody` are reserved for engine or library components and must be registered before scene data can use them.
- Library component names must be dotted and cannot use the reserved `scrapbot` namespace.
- The engine registry contains built-in transform, camera, geometry, material, lighting, shadow, UI box/stack/control, and internal render-instance component names.
- `scrapbot.component` and `scrapbot.library_component` return typed component handles with runtime component IDs and names. Scripts can cast them to generated component handle types.
- `scrapbot.component_handle` returns the same handle shape for components registered before script execution, including native extension schemas.
- The `scrapbot` API exposes public transform, camera, geometry, material, lighting, shadow, UI layout, horizontal-stack, vertical-stack, text, and button component handles.
- Scripts can define full named indexed geometry, generate cubes, planes, icospheres, UV spheres, pyramids, and capped cylinders, and define shared Lambert-lit base-color, unlit emissive HDR, or project-PNG-textured materials.
- Scripts can register frame systems with `scrapbot.system(function(time) ... end)`.
- Scripts can give systems a project-facing name through the optional system-options `name` field. Project-owned names use one token; dotted multi-token names are reserved for engine or library systems. Named systems use that label in editor tooling; unnamed legacy registrations retain an ordinal fallback.
- Scripts can declare system component access with `scrapbot.system({ reads = {...}, writes = {...} }, function(time) ... end)`.
- Every system receives the same read-only time resource snapshot with delta time, smoothed delta time, elapsed time, and frame index.
- Script system access declarations accept component handles, query objects for reads, or registered component-name strings.
- Scripts can create reusable query objects with `scrapbot.query(component_a, component_b, ...)`.
- Query object construction is order-insensitive: repeated calls with the same component set return the same object, and query payloads use Scrapbot's canonical component order.
- Query objects can iterate matching entities with `query:each(callback)`. Callback parameters receive the entity followed by component payloads in query order.
- Scripts can pass a query object to `scrapbot.system(query, options?, callback)` to run the system callback once per matching entity. Query components are declared as system reads automatically.
- Query-driven systems can mutate `scrapbot.transform` and schema-backed project or library component payload tables directly when the system declares matching write access.
- Mutating a query-system payload table without declared write access fails the system step and leaves the world unchanged.
- Generated Luau types provide readonly payload aliases for `query:each` and query-driven systems that do not pass options.
- Generated Luau types validate query-system options and support mutable payload annotations for writable query-driven systems.
- Generated Luau types keep `scrapbot.system` itself permissive because Luau LSP cannot reliably resolve overloaded generic query callbacks. Query construction, payload aliases, readonly fields, and explicitly annotated callback parameters remain typed, while the runtime validates each supported registration form.
- Scripts can request a bulk query result with `scrapbot.view(component_handle)`, which returns alive entity/component items for the component type.
- Scripts can request a joined bulk query result with `scrapbot.view(query)` or `scrapbot.view({ component_a, component_b })`, which returns alive entities and a component payload array in query order.
- Runtime queries use component IDs from handles to select one component storage group, while project files and diagnostics remain name-based.
- Project scripts annotate query callback component parameters with generated component payload aliases such as `Autorotate`.
- Scripts can read and write entity rotation through `scrapbot.get_rotation(entity)` and `scrapbot.set_rotation(entity, rotation)`, but query-driven systems should prefer direct `scrapbot.transform` payload mutation.
- Script entity handles include an entity index, generation, and optional name. APIs reject stale handles whose generation no longer matches the world.
- Scripts can queue entity lifecycle changes with `scrapbot.spawn({ name = "..." })` and `scrapbot.despawn(entity)`.
- Spawn options may include initial `scrapbot.transform` data and schema-backed project or library component payloads.
- Scripts can queue component lifecycle changes with `scrapbot.add_component(entity, component, payload)` and `scrapbot.remove_component(entity, component)`.
- Spawn, despawn, add-component, and remove-component requests are deferred until after all scheduled systems have run for the frame.
- Scene files can attach simple custom vec3 component data with `[entities.components.<name>]` sections.
- Scene custom component data must match its registered schema. Project-level and library component schemas come from `scripts/main.luau`; engine component schemas come from the engine registry.
- Projects include Luau LSP metadata so editors can type-check the `scrapbot` global, engine component aliases, project component aliases, and script-registered library component aliases.
- Static analyzer diagnostics fail `scrapbot check` when they include Luau type or syntax errors. Lint-only output does not currently fail the project check.

## Design Decisions

### 1. Start with one project entry script

**Decision:** Execute `scripts/main.luau` if it exists.
**Why:** A single conventional entry point is enough to verify embedding, project layout, CLI behavior, hot reload, component APIs, and system scheduling before introducing modules.
**Tradeoff:** There is no module loading yet, and hot reload currently targets only this conventional entry script.

### 2. Expose read-only ECS inspection first

**Decision:** The initial API exposes logging and ECS counts only.
**Why:** Read-only calls prove the Odin/Luau bridge without committing to component mutation semantics too early.
**Tradeoff:** Useful gameplay scripting still needs component APIs, queries, and system scheduling.

This was the first scripting slice. The current API has since grown a narrow ECS bridge for frame systems, custom component queries, transform rotation mutation, and deferred entity/component lifecycle mutation.

Access-declared systems now feed the runtime scheduler, but Luau execution remains serial.

Structural mutations requested by Luau systems are now deferred through an engine command buffer and applied after the frame's scheduled systems have completed.

### 3. Vendor Luau from source

**Decision:** Keep Luau as a pinned git submodule and build static libraries through `mise`.
**Why:** The local package manager distribution provides a CLI but not the embeddable headers and libraries Scrapbot needs.
**Tradeoff:** Build tasks now own native dependency compilation and platform-specific linker flags.

### 4. Ship project-local Luau editor definitions

**Decision:** Generate `.scrapbot/types/scrapbot.d.luau` and `.vscode/settings.json` for new projects, then refresh the type file during `scrapbot check`.
**Why:** The Luau language server uses `luau-lsp.types.definitionFiles` mappings for custom globals, and project scripts need the `scrapbot` global plus component payload aliases to be known outside the running engine.
**Tradeoff:** The first editor integration is VS Code-oriented. Other editors may need equivalent Luau LSP settings until Scrapbot has editor-agnostic project metadata generation. `scrapbot check` must execute top-level script registration code to discover project and library component schemas.

The generated `scrapbot.system` function type is intentionally permissive. Luau LSP currently reports valid generic query callbacks as ambiguous or incompatible when the API is represented as an intersection of overloads, despite the standalone analyzer accepting the same source. Strong typing therefore lives on component handles, query objects, query iteration, payload aliases, and callback annotations; runtime registration validates the system call shape and access options.

### 5. Start custom components as simple scene data

**Decision:** Allow scripts to define project components with `scrapbot.component(name, schema)` and library components with `scrapbot.library_component(name, schema)`, then let scene files attach matching data with `[entities.components.<name>]` sections whose initial fields are vec3 values. Single-token component names are owned by the project, while multi-token dotted names are owned by engine or library registrations. Both registration APIs return handles that select the component at runtime, while query callbacks use generated Luau aliases for the component payload type.
**Why:** This is enough for the first project-owned system, `autorotate.velocity`, while keeping the parser and Luau bridge small.
**Tradeoff:** Component schemas are still declared separately from payload aliases, so the schema table is not yet generated from the Luau payload type. Library components can be registered explicitly, but there is not yet a module/package loader that scopes registration authority to a real library. Luau receives component tables dynamically, and direct payload write-back is limited to query-driven systems. The legacy `"vec3"` string remains accepted, but generated projects use `scrapbot.vec3`.

### 6. Use a registry for component ownership and scene validation

**Decision:** Keep a runtime component registry with built-in engine component names plus project and library component schemas registered by Luau.
**Why:** The registry gives scene validation, script registration, query handles, and generated Luau type aliases one shared source of component ownership and basic field schemas.
**Tradeoff:** The registry is intentionally small: it supports vec3 schema fields only and has explicit library component registration but not a full package mechanism for third-party libraries.

Registered component definitions also receive runtime-local component IDs. Luau handles carry those IDs, and loaded scene component storage is bound to them after scripts register schemas.

### 7. Check project files periodically for first hot reload

**Decision:** `--hot-reload` checks file modification stamps on a short interval while renderer frames are advancing.
**Why:** Periodic checks are portable, backend-neutral, and enough to validate runtime state replacement before introducing platform file watching services.
**Tradeoff:** Reloads are not immediate, and the first implementation recursively stamps the whole assets directory rather than using platform file-watching services or dependency-specific watches.

### 8. Feed Luau system declarations into the scheduler

**Decision:** Let Luau systems declare a project-facing name plus component reads and writes in an options table before the callback. Use the component ownership convention for system names: one token for project systems and dotted multi-token names for engine or library systems.
**Why:** The same script API that users write now should produce both the scheduling metadata needed for parallel execution and the identity needed by live tooling.
**Tradeoff:** Names and access declarations are manually maintained for now. The naming convention is not runtime-enforced because system registration does not yet carry explicit project, engine, or library ownership. The runtime validates the option shapes and component names and enforces writes that go through Scrapbot APIs or query-system payload write-back, but it does not yet statically prove that system bodies only touch declared components.

### 9. Expose entity and component lifecycle through deferred commands

**Decision:** Add `scrapbot.spawn`, `scrapbot.despawn`, `scrapbot.add_component`, and `scrapbot.remove_component` as deferred Luau APIs instead of mutating the world immediately.
**Why:** Project systems need a basic way to create and remove gameplay state, but immediate structural mutation would make queries and future parallel scheduling much harder to reason about.
**Tradeoff:** Lifecycle changes are visible after the current frame step. Runtime component mutation currently supports `scrapbot.transform` and schema-backed project or library vec3 components, not arbitrary engine storage.

### 10. Include generations in Luau entity handles

**Decision:** Pass entity generation numbers to Luau and validate them when scripts call entity APIs.
**Why:** Stable indices alone are not enough once entities can be despawned. Generation checks prevent stale handles from mutating a different lifetime of the same slot later.
**Tradeoff:** Scripts cannot fabricate useful entity handles from indices alone; they need handles received from Scrapbot APIs or must know the current generation during low-level tests.

### 11. Query custom components by component ID

**Decision:** Group schema-backed custom component instances by component type and use registry-assigned component IDs for runtime query and lifecycle paths.
**Why:** Name matching is useful at text/project boundaries but too weak as an execution-time storage key. ID-keyed groups are a better base for bulk query views, native systems, and parallel scheduling.
**Tradeoff:** Component IDs are runtime-local and must be rebound after scene load and script registration. Names remain the persistent source of truth in project files.

### 12. Expose bulk and joined query views before native iterators

**Decision:** Add `scrapbot.view(component)` and joined `scrapbot.view({ ... })` calls as table results built from the same internal query path as callback queries.
**Why:** This gives scripts a batch-shaped API and lets the engine test component matching semantics before committing to native iterators or lower-level query planners.
**Tradeoff:** The first view API materializes Luau tables each call. It is ergonomic and testable, but it is not the final zero-allocation iteration path.

### 13. Make built-in components queryable handles

**Decision:** Expose built-in component handles such as `scrapbot.transform` directly on the Luau API and allow query objects and views to mix those handles with project and library component handles.
**Why:** Gameplay systems usually operate over a set of components, not one project component plus ad hoc helper calls. Built-in and library handles make query code and system access declarations line up.
**Tradeoff:** Built-in component payloads are still copied into Luau tables, and only transform exposes real writable fields today. Direct payload write-back is currently limited to query-driven systems that declare matching writes; `query:each` and bulk views remain read/copy APIs.

### 14. Make queries reusable values

**Decision:** Make `scrapbot.query` construct reusable query objects instead of immediately iterating, and let query objects drive `query:each`, bulk views, access declarations, and query systems.
**Why:** Queries are first-class ECS concepts. Reusable query values give scripts one object to use for iteration, scheduling metadata, tests, and future editor/native-system integration.
**Tradeoff:** Query objects are component sets, so construction order is not a semantic part of the query. Luau's analyzer still has limits around generic overloaded callbacks. Generated types keep `query:each` and read-only query systems precise for the first three arities; writable query systems type-check their options and rely on explicit callback parameter annotations for mutable payloads.

### 15. Analyze project scripts after type generation

**Decision:** Run `luau-analyze` during `scrapbot check` when the analyzer executable is available, using a temporary analyzer fixture built from the refreshed generated types and `scripts/main.luau`.
**Why:** Runtime script execution cannot catch editor-facing type definition regressions or statically invalid project scripts. Running the analyzer after type generation checks the same type surface users see in their editor.
**Tradeoff:** The first implementation is optional when `luau-analyze` is not on `PATH`, and diagnostics point at a temporary combined file rather than original project paths. This should be replaced by analyzer support that consumes project-local definition files directly.

### 16. Let Luau use pre-registered component handles

**Decision:** Add `scrapbot.component_handle(name)` for components that already exist in the runtime registry before the script runs.
**Why:** Native extensions and future engine libraries can register component schemas before Luau executes, and scripts still need typed handles for queries, systems, access declarations, and lifecycle commands.
**Tradeoff:** The call is dynamic and errors at runtime when a name is not registered. Generated types can describe the payload shape after `scrapbot check`, but the name-to-type cast remains explicit in script code.

## Related

- **ADRs:** ADR-001, ADR-002, ADR-006, ADR-007, ADR-008, ADR-010, ADR-012, ADR-029
- **FDRs:** FDR-001, FDR-002, FDR-003, FDR-005, FDR-006

## Open Questions

- Should Luau modules resolve from project-local script directories, engine packages, or both?
- What file-watching contract should replace polling once Scrapbot has runtime services?
