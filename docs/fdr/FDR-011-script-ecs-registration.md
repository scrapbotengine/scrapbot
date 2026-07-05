# FDR-011: Script ECS Registration

**Status:** Active
**Last reviewed:** 2026-07-03

## Overview

Script ECS registration lets project and package scripts define new component and system types that participate in Scrapbot's entity component runtime. It exists so gameplay code can extend the engine model without native recompilation while still preserving validation, reload safety, and editor visibility.

## Behavior

- Project scripts can register component and system types with project-local ids or qualified ids.
- Package scripts can register component and system types only with qualified ids.
- Engine-owned ids use the reserved `scrapbot.*` namespace.
- Scrapbot does not infer a default project namespace.
- Project metadata lists script files in a root-level `scripts = [...]` array.
- Script files use Luau source files executed by the embedded Luau VM.
- Project scripts are type-checked as strict Luau in the repository editor configuration.
- Scripts register component and system definitions through the engine-provided `ecs.component(...)` and `ecs.system(...)` globals.
- The example project's rotating cube behavior declares `spin` as a project-local component instead of relying on an engine-owned spin type.
- Duplicate registration with an identical definition is accepted as reload-compatible.
- Duplicate registration with an incompatible definition fails validation.
- Systems declare the component types they read and write.
- Systems declare a phase; the current exposed phases are `startup` and `update`.
- Startup systems run once for a loaded project/scene generation before update systems.
- Script-only reloads replace the script program for future systems but do not replay startup against an already-started live world.
- Systems may declare ordering relationships by system id.
- The native runtime builds phase-specific schedule batches from declared read/write access and before/after dependencies.
- Systems that only read compatible component sets can share a batch; write conflicts or order dependencies force later batches.
- `scrapbot check --format=json` exposes the validated schedule so editor tools and agents can inspect phases, system batches, runner kinds, access declarations, and ordering relationships without running a window.
- Script-authored systems can provide Luau `run` callbacks that execute during the native schedule.
- Script system callbacks receive an engine-provided world facade instead of direct component storage ownership.
- Script systems can call the world facade to spawn entities.
- Script-created and query-yielded entity proxies carry generated entity handles so stale proxies fail instead of aliasing a different live entity after despawn/compaction.
- Script systems can call entity facade methods to add/remove registered components or despawn entities.
- Adding/removing a component requires the active system to declare write access to that component.
- Despawning an entity requires the active system to declare write access to every component currently attached to the entity.
- Component add/remove/despawn calls from Luau are queued and flushed only after the current system returns successfully.
- Entities spawned by a failing Luau system are rolled back with that system's unflushed structural command queue.
- `ecs.component(...)` returns a typed component handle.
- Component handle type-brand metadata supports editor analysis and is not callable gameplay API.
- Scripts use `ecs.fields(...)` to declare component field maps with editor-visible field type validation.
- Component payload editor types can be inferred from literal `ecs.fields(...)` declarations.
- Legacy `ecs.schema(...)` marker declarations remain available for compatibility, but new script examples use `ecs.fields(...)`.
- Scripts use `ecs.query(...)` to create reusable typed query objects from component handles.
- Systems may attach a query object; unwritten query components become inferred read access.
- Scripts use `ecs.refs(...)` to erase typed component handles into explicit `reads` or `writes` declarations when needed.
- The preferred runtime loop calls `Query:iter(world)` and receives the entity plus component proxies for the requested components.
- `Query:iter(world)` prepares its component set for the iterator so repeated loop rows can reuse resolved ECS table and row positions behind the proxy API.
- Reusable query objects keep a hidden prepared plan across system invocations and invalidate it when used with a different active world or a newer world query-plan generation.
- High-cardinality runtime loops can call `Query:view(world)` to capture the current matched rows and bulk read/write `f32` or `vec3` fields through Luau buffers.
- The lower-level `world.query(...)` loop remains available for compatibility and debugging.
- Low-level entity vector accessors remain available for compatibility and debugging.
- Script-driven world mutation is checked against the system's declared component access.
- Component proxies can read and write registered boolean, integer, float, string, and Vec3 fields through the typed query API.
- Non-finite script values that reach host mutation APIs fail the system invocation for that frame instead of corrupting world state.
- Registration failures produce structured diagnostics suitable for command-line, editor, and reload surfaces.
- Script runtime failures keep the last loaded project state active and surface diagnostics with script path, system id, stage, and messages that identify denied or failed component access where available.

## Design Decisions

### 1. Distinguish local and package ids

**Decision:** Project code may use single-segment local ids or qualified ids, while package code must use qualified ids. `scrapbot.*` is reserved for engine-owned types.
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

**Decision:** Scrapbot vendors the embeddable Luau compiler and VM source subset and wraps it behind a small C ABI bridge.
**Why:** Homebrew provides Luau command-line tools but not the embeddable library surface Scrapbot needs. Keeping Luau behind the scripting boundary follows ADR-005 and lets the Zig runtime avoid depending on Luau internals directly.
**Tradeoff:** The repository carries third-party source and must periodically update the vendored subset deliberately.

### 8. Treat startup as scene generation

**Decision:** Startup systems run once before update for a loaded project/scene generation. Project reloads and scene reloads create a fresh generation and can run startup again; script-only reloads do not replay startup against already-live world state.
**Why:** Startup systems are allowed to perform structural mutation such as spawning renderables. Replaying them on script-only reload would duplicate or destroy live state without a migration model.
**Tradeoff:** Adding a new startup system while a live scene is already running requires a project/scene reload or a future explicit restart/migration command before that startup logic affects the active world.

### 9. Require write access for structural component mutation

**Decision:** Script systems may spawn new entities, but component insertion/removal and entity despawn are constrained by declared writes.
**Why:** The scheduler and diagnostics already use reads/writes as the source of truth for mutation. Structural changes alter query membership and must obey the same contract to stay compatible with future parallel execution.
**Tradeoff:** Dynamic entity lifecycle systems carry more explicit access declarations.

### 10. Hide hot-loop query preparation behind typed query objects

**Decision:** Typed query objects keep the author-facing Luau API stable while the bridge prepares component table and row access internally for each iterator.
**Why:** Authors and agents should keep writing clear ECS loops, and the engine should optimize the storage path under that API. Reusable query objects can persist prepared table plans across invocations and invalidate them when the world generation changes. It follows ADR-014.
**Tradeoff:** The bridge must preserve compatibility with the lower-level string-based query path, and per-field proxy access still has a host-call cost unless the system opts into query views.

### 11. Make bulk query views an explicit hot-path API

**Decision:** Query objects expose `Query:view(world)` for scripts that want buffer-backed `f32` and `vec3` access over the current query result.
**Why:** The ordinary proxy API should remain readable, but large script systems need a way to reduce Luau/native bridge calls without leaving the ECS/scheduler model. It follows ADR-015.
**Tradeoff:** Buffer code uses byte offsets and is easier to get wrong than proxy field access, so examples should reserve it for measured hot loops and keep ordinary logic on `Query:iter(world)`.

### 12. Carry entity generations through script proxies

**Decision:** Entity proxies and component proxies created by Luau queries or `world.spawn` carry the runtime entity generation alongside the dense index.
**Why:** Script code can hold proxies past structural mutation. Generation-aware callbacks prevent stale proxies from mutating the wrong live entity after dense removal. It follows ADR-016.
**Tradeoff:** The host bridge has a wider callback ABI, and stale proxies fail rather than continuing to track entities that moved to a different dense index.

### 13. Flush structural commands after successful systems

**Decision:** Luau structural component/entity commands are buffered during a system and flushed after that system returns successfully.
**Why:** Systems should not change query membership while they are still executing, and script errors should not leave partially applied queued component mutations. It follows ADR-017.
**Tradeoff:** A script cannot immediately query components it just added in the same callback; use a later ordered system or later frame for that observation.

## Related

- **ADRs:** ADR-006, ADR-008, ADR-009, ADR-010, ADR-011, ADR-012, ADR-014, ADR-015, ADR-016, ADR-017
- **FDRs:** FDR-004, FDR-009, FDR-010, FDR-012, FDR-013

## Open Questions

- How will component defaults and migrations be represented in script schemas?
- Which system phases beyond `startup` and `update` should be exposed to script-defined systems first?
- Which structured field accessors and query view transfers beyond scalar values and `vec3` should be added to the Luau runtime bridge?
- How should live script reload handle startup changes, schema changes, and world migrations without replaying unsafe mutations?
- How should script runtime errors include full stack context and source spans?
