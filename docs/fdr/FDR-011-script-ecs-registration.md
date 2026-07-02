# FDR-011: Script ECS Registration

**Status:** Active
**Last reviewed:** 2026-07-02

## Overview

Script ECS registration lets project and package scripts define new component and system types that participate in Machina's entity component runtime. It exists so gameplay code can extend the engine model without native recompilation while still preserving validation, reload safety, and editor visibility.

## Behavior

- Project scripts can register component and system types with project-local ids or qualified ids.
- Package scripts can register component and system types only with qualified ids.
- Engine-owned ids use the reserved `machina.*` namespace.
- Machina does not infer a default project namespace.
- Project metadata lists script files in a root-level `scripts = [...]` array.
- Script files use Luau source files executed by the embedded Luau VM.
- Project scripts are type-checked as strict Luau in the repository editor configuration.
- Scripts register component and system definitions through the engine-provided `ecs.component(...)` and `ecs.system(...)` globals.
- The example project's rotating cube behavior declares `spin` as a project-local component instead of relying on an engine-owned spin type.
- Duplicate registration with an identical definition is accepted as reload-compatible.
- Duplicate registration with an incompatible definition fails validation.
- Systems declare the component types they read and write.
- Systems declare a phase; the current exposed schedule is the `update` phase.
- Systems may declare ordering relationships by system id.
- The native runtime builds update schedule batches from declared read/write access and before/after dependencies.
- Systems that only read compatible component sets can share a batch; write conflicts or order dependencies force later batches.
- Script-authored systems can provide Luau `run` callbacks that execute during the native update schedule.
- Script system callbacks receive an engine-provided world facade instead of direct component storage ownership.
- `ecs.component(...)` returns a typed component handle.
- Component handle type-brand metadata supports editor analysis and is not callable gameplay API.
- Scripts use `ecs.fields(...)` to declare component field maps with editor-visible field type validation.
- Component payload editor types can be inferred from literal `ecs.fields(...)` declarations.
- Legacy `ecs.schema(...)` marker declarations remain available for compatibility, but new script examples use `ecs.fields(...)`.
- Scripts use `ecs.query(...)` to create reusable typed query objects from component handles.
- Systems may attach a query object; unwritten query components become inferred read access.
- Scripts use `ecs.refs(...)` to erase typed component handles into explicit `reads` or `writes` declarations when needed.
- The preferred runtime loop calls `Query:iter(world)` and receives the entity plus component proxies for the requested components.
- The lower-level `world.query(...)` loop remains available for compatibility and debugging.
- Low-level entity vector accessors remain available for compatibility and debugging.
- Script-driven world mutation is checked against the system's declared component access.
- Component proxies can read and write registered boolean, integer, float, string, and Vec3 fields through the typed query API.
- Non-finite script values that reach host mutation APIs fail the system invocation for that frame instead of corrupting world state.
- Registration failures produce structured diagnostics suitable for command-line, editor, and reload surfaces.
- Script runtime failures keep the last loaded project state active and surface diagnostics with script path, system id, stage, and message where available.

## Design Decisions

### 1. Distinguish local and package ids

**Decision:** Project code may use single-segment local ids or qualified ids, while package code must use qualified ids. `machina.*` is reserved for engine-owned types.
**Why:** Local ids keep project authoring lightweight, while qualified ids make package boundaries, scene references, diagnostics, and reload behavior stable. It follows ADR-010.
**Tradeoff:** Moving a local project component into a reusable package requires an explicit id migration.

### 2. Treat registration as schema definition

**Decision:** Scripts register component and system definitions, not raw native storage handles.
**Why:** The engine must own validation, storage, serialization, scheduling, and reload transactions. It follows ADR-008 and ADR-010.
**Tradeoff:** Script APIs need schema and access declaration design before they can expose full runtime power.

### 3. Make duplicate registration reload-aware

**Decision:** Re-registering the same id with the same definition succeeds, while incompatible duplicate definitions fail.
**Why:** Script reload should not fail just because a module runs its registration code again, but schema changes need explicit compatibility rules. It follows ADR-009 and ADR-010.
**Tradeoff:** Definition equality and future migration behavior must be kept deterministic.

### 4. Keep scheduling native

**Decision:** Scripts declare systems and access sets, but the native runtime owns scheduling.
**Why:** The engine needs deterministic validation, dependency planning, parallel batch construction, and a path toward multiple Luau VM partitions. It follows ADR-006 and ADR-008.
**Tradeoff:** Script authors must describe access up front, and dynamic component access needs explicit API design before it can be supported.

### 5. Execute real Luau, keep host APIs narrow

**Decision:** Project scripts run in the embedded Luau VM. `ecs.component` and `ecs.system` are host-provided globals, and system `run` callbacks are stored and invoked as real Luau functions. Runtime world access is exposed through narrow host APIs.
**Why:** Running real Luau keeps script behavior honest, reloadable, and compatible with editor tooling while preserving native ownership of ECS storage and scheduling. Narrow host APIs prevent scripts from bypassing validation while the ECS query/mutation model matures.
**Tradeoff:** Each host API must be designed, typed, validated, and diagnosed explicitly before scripts can use it.

### 6. Prefer typed field schemas and query objects

**Decision:** `ecs.component(...)` returns an opaque typed component handle with guarded type-brand metadata, `ecs.fields(...)` declares runtime field schemas and drives editor payload inference through Luau type functions, `ecs.query(...)` turns one or more handles into a reusable query object, systems can attach that query object, and runtime loops iterate it through the world facade.
**Why:** Field schemas should be written once and read directly by both the runtime and the editor. Query objects keep the component set explicit, reusable, and easy for Luau tooling to type while avoiding repeated string or handle lists inside hot loops. Inferring reads from the query object lets scripts describe the common "iterate these components" case once, while explicit writes still keep scheduling honest. It follows ADR-006, ADR-008, and ADR-012.
**Tradeoff:** Script authors introduce a named query before system registration. The typed editor surface supports a practical maximum query arity rather than arbitrary compile-time tuple lengths, and the editor type surface now depends on Luau's new solver.

### 7. Vendor the initial Luau runtime behind the scripting boundary

**Decision:** Machina vendors the embeddable Luau compiler and VM source subset and wraps it behind a small C ABI bridge.
**Why:** Homebrew provides Luau command-line tools but not the embeddable library surface Machina needs. Keeping Luau behind the scripting boundary follows ADR-005 and lets the Zig runtime avoid depending on Luau internals directly.
**Tradeoff:** The repository carries third-party source and must periodically update the vendored subset deliberately.

## Related

- **ADRs:** ADR-006, ADR-008, ADR-009, ADR-010, ADR-011, ADR-012
- **FDRs:** FDR-004, FDR-009, FDR-010, FDR-012, FDR-013

## Open Questions

- How will component defaults and migrations be represented in script schemas?
- Which system phases beyond `update` should be exposed to script-defined systems first?
- Which structured field accessors beyond scalar values and `vec3` should be added to the Luau runtime bridge?
- How should component insertion/removal work from scripts, and which phases may perform structural changes?
- How should script runtime errors include full stack context and source spans?
