# FDR-011: Script ECS Registration

**Status:** Planned
**Last reviewed:** 2026-07-01

## Overview

Script ECS registration lets project and package scripts define new component and system types that participate in Machina's entity component runtime. It exists so gameplay code can extend the engine model without native recompilation while still preserving validation, reload safety, and editor visibility.

## Behavior

- Scripts can register component types with explicit dotted ids.
- Scripts can register system types with explicit dotted ids.
- Engine-owned ids use the reserved `machina.*` namespace.
- Project and package scripts must choose their own non-reserved namespaces; Machina does not infer a default project namespace.
- Duplicate registration with an identical definition is accepted as reload-compatible.
- Duplicate registration with an incompatible definition fails validation.
- Systems declare the component types they read and write.
- Systems may declare ordering relationships by system id.
- Registration failures produce diagnostics suitable for command-line, editor, and reload surfaces.

## Design Decisions

### 1. Require explicit namespaces

**Decision:** Script-defined component and system ids must be explicit dotted ids, and `machina.*` is reserved for engine-owned types.
**Why:** Explicit ids make package boundaries, scene references, diagnostics, and reload behavior stable. It follows ADR-010.
**Tradeoff:** New projects must choose a namespace instead of relying on a built-in default.

### 2. Treat registration as schema definition

**Decision:** Scripts register component and system definitions, not raw native storage handles.
**Why:** The engine must own validation, storage, serialization, scheduling, and reload transactions. It follows ADR-008 and ADR-010.
**Tradeoff:** Script APIs need schema and access declaration design before they can expose full runtime power.

### 3. Make duplicate registration reload-aware

**Decision:** Re-registering the same id with the same definition succeeds, while incompatible duplicate definitions fail.
**Why:** Script reload should not fail just because a module runs its registration code again, but schema changes need explicit compatibility rules. It follows ADR-009 and ADR-010.
**Tradeoff:** Definition equality and future migration behavior must be kept deterministic.

## Related

- **ADRs:** ADR-006, ADR-008, ADR-009, ADR-010
- **FDRs:** FDR-004, FDR-009, FDR-010

## Open Questions

- Which Lua runtime becomes the first scripting backend?
- How will component defaults and migrations be represented in script schemas?
- Which system phases are exposed to script-defined systems first?
