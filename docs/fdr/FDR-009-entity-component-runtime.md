# FDR-009: Entity Component Runtime

**Status:** Planned
**Last reviewed:** 2026-07-01

## Overview

The entity component runtime is the shared low-level model for game state. It gives scenes, scripts, editor tools, tests, and agents a consistent way to describe and mutate runtime objects through entities, components, and systems.

## Behavior

- Entities have stable ids suitable for text scene files, diagnostics, editor selection, and reload patching.
- Components hold structured data and are validated against engine-owned schemas.
- Systems operate over component queries rather than over renderer-specific or script-owned object lists.
- Scene files author entity and component data as text.
- Scripts can query, add, update, and remove supported components through the scripting API.
- Scripts can register new component and system types with explicit non-reserved dotted ids.
- Engine-owned and script-defined systems can participate in the runtime lifecycle once scheduling rules exist.
- Invalid, duplicate, or unsupported entity/component data produces diagnostics suitable for command-line and editor display.

## Design Decisions

### 1. Make components and systems the project mental model

**Decision:** Machina teaches users, scripts, agents, and editor tools to think in entities, components, and systems.
**Why:** A shared component-system model keeps scene data, scripting, validation, and editor inspection aligned. It follows ADR-008.
**Tradeoff:** The engine needs component schema and API design earlier than a hardcoded demo renderer would.

### 2. Commit to ECS semantics before committing to ECS storage

**Decision:** The feature commits to entity/component/system behavior now, while storage layout, archetypes, scheduling, and library choices remain implementation decisions.
**Why:** Early slices should not lock the engine into a performance strategy before real workloads exist. It follows ADR-008.
**Tradeoff:** Implementation needs discipline so temporary native structures do not become permanent side channels.

### 3. Expose a safe ECS facade to scripts

**Decision:** Scripts interact with entities and components through an engine-supported API, not through direct native pointers or authoritative script object graphs.
**Why:** This keeps script behavior reloadable, testable, and consistent with text scene data. It follows ADR-006 and ADR-008.
**Tradeoff:** Some low-level power is intentionally hidden until the API has clear safety and lifecycle rules.

### 4. Require explicit script extension ids

**Decision:** Script-defined component and system types use explicit dotted ids, with `machina.*` reserved for engine-owned types.
**Why:** Component and system references need to be stable across scenes, packages, reloads, and diagnostics. It follows ADR-010.
**Tradeoff:** Projects must choose a namespace before registering script-defined ECS types.

## Related

- **ADRs:** ADR-001, ADR-006, ADR-008, ADR-010
- **FDRs:** FDR-002, FDR-004, FDR-010, FDR-011

## Open Questions

- What stable id format should entities use?
- What is the first explicit component table syntax in scene files?
- How much system scheduling control should scripts get in the first playable slice?
