# FDR-009: Entity Component Runtime

**Status:** Active
**Last reviewed:** 2026-07-02

## Overview

The entity component runtime is the shared low-level model for game state. It gives scenes, scripts, editor tools, tests, and agents a consistent way to describe and mutate runtime objects through entities, components, and systems.

## Behavior

- Entities have stable ids suitable for text scene files, diagnostics, editor selection, and reload patching.
- Components hold structured data and are validated against engine-owned or script-registered schemas.
- Systems operate over component queries rather than over renderer-specific or script-owned object lists.
- Scene files author entity and component data as text component tables.
- The runtime world stores component instances in per-component column tables rather than renderer-specific side arrays.
- Engine-owned rendering components include transform, cube renderer, camera, and directional light data.
- Each component table owns dense entity rows, a sparse entity-to-row index, and typed SoA field columns derived from engine or script schemas.
- Scripts can query entities by component set and mutate supported component fields through the scripting API.
- Scripts can register new component and system types with project-local or qualified non-reserved ids.
- Engine-owned and script-defined systems declare phases, read/write component access, and optional before/after ordering relationships.
- The runtime can build phase-specific system schedule batches from those declarations.
- The example script-authored system queries entities with `machina.transform` and project-local `spin`, then applies `spin.angular_velocity` to `machina.transform.rotation` during update.
- Invalid, duplicate, or unsupported entity/component data produces diagnostics suitable for command-line and editor display.

## Design Decisions

### 1. Make components and systems the project mental model

**Decision:** Machina teaches users, scripts, agents, and editor tools to think in entities, components, and systems.
**Why:** A shared component-system model keeps scene data, scripting, validation, and editor inspection aligned. It follows ADR-008.
**Tradeoff:** The engine needs component schema and API design earlier than a hardcoded demo renderer would.

### 2. Store component instances in sparse column tables

**Decision:** The runtime world owns one table per component type. A table stores entity handles densely, maps entity indexes back to table rows sparsely, and stores each component field in its own typed column.
**Why:** SoA columns give systems and renderer adapters a real ECS storage shape while still supporting runtime-created Luau component schemas. It follows ADR-008.
**Tradeoff:** This is not yet chunked archetype storage, and query planning is still simple. Structural mutation, removal, migration, and parallel iteration need follow-up design.

### 3. Expose a safe ECS facade to scripts

**Decision:** Scripts interact with entities and components through an engine-supported API, not through direct native pointers or authoritative script object graphs.
**Why:** This keeps script behavior reloadable, testable, and consistent with text scene data. It follows ADR-006 and ADR-008.
**Tradeoff:** Some low-level power is intentionally hidden until the API has clear safety and lifecycle rules.

### 4. Distinguish local and qualified script extension ids

**Decision:** Script-defined component and system types use project-local single-segment ids or qualified dotted ids, with `machina.*` reserved for engine-owned types.
**Why:** Component and system references need to be ergonomic in local projects and stable across packages, reloads, and diagnostics. It follows ADR-010.
**Tradeoff:** Promoting a local type into a reusable package requires an explicit id migration.

### 5. Schedule by declared access

**Decision:** System definitions include phase, read components, write components, and ordering relationships. The native runtime uses those declarations to build batches of systems that can run without access conflicts.
**Why:** Explicit access keeps validation, reload, editor inspection, and future parallel execution aligned. It follows ADR-006 and ADR-008.
**Tradeoff:** Systems must be honest and explicit about access before the scheduler can safely parallelize them.

## Related

- **ADRs:** ADR-001, ADR-006, ADR-008, ADR-010
- **FDRs:** FDR-002, FDR-004, FDR-010, FDR-011, FDR-014

## Open Questions

- What stable id format should entities use?
- How much scheduler control should scripts get beyond phases, access declarations, and before/after relationships?
