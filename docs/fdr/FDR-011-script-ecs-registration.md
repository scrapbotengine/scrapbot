# FDR-011: Script ECS Registration

**Status:** Active
**Last reviewed:** 2026-07-01

## Overview

Script ECS registration lets project and package scripts define new component and system types that participate in Machina's entity component runtime. It exists so gameplay code can extend the engine model without native recompilation while still preserving validation, reload safety, and editor visibility.

## Behavior

- Project scripts can register component and system types with project-local ids or qualified ids.
- Package scripts can register component and system types only with qualified ids.
- Engine-owned ids use the reserved `machina.*` namespace.
- Machina does not infer a default project namespace.
- Project metadata lists script files in a root-level `scripts = [...]` array.
- Script files use Luau source files and currently support a constrained declaration surface: `ecs.component(...)` and `ecs.system(...)`.
- Duplicate registration with an identical definition is accepted as reload-compatible.
- Duplicate registration with an incompatible definition fails validation.
- Systems declare the component types they read and write.
- Systems declare a phase; the current exposed schedule is the `update` phase.
- Systems may declare ordering relationships by system id.
- The native runtime builds update schedule batches from declared read/write access and before/after dependencies.
- Systems that only read compatible component sets can share a batch; write conflicts or order dependencies force later batches.
- Registration failures produce diagnostics suitable for command-line, editor, and reload surfaces.
- This slice does not execute Luau system bodies yet.

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

### 5. Start with Luau declarations before VM execution

**Decision:** The first implementation parses a constrained Luau declaration surface and does not execute `run` callbacks.
**Why:** Registration and scheduling shape the architecture more than callback execution. They can be validated headlessly and reloaded before the Luau runtime dependency is wired into the build.
**Tradeoff:** This is scripting metadata, not playable script behavior yet.

## Related

- **ADRs:** ADR-006, ADR-008, ADR-009, ADR-010
- **FDRs:** FDR-004, FDR-009, FDR-010

## Open Questions

- How should the real Luau VM be packaged and linked across platforms?
- How are Luau system bodies compiled, cached, invoked, and isolated?
- How will component defaults and migrations be represented in script schemas?
- Which system phases beyond `update` should be exposed to script-defined systems first?
