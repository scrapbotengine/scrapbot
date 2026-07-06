# FDR-009: Entity Component Runtime

**Status:** Active
**Last reviewed:** 2026-07-06

## Overview

The entity component runtime is the shared low-level model for game state. It gives scenes, scripts, editor tools, tests, and agents a consistent way to describe and mutate runtime objects through entities, components, and systems.

## Behavior

- Entities have stable ids suitable for text scene files, diagnostics, editor selection, and reload patching.
- Entities track whether they came from authored scene data, were spawned at runtime, or are engine-transient frame data.
- Components hold structured data and are validated against engine-owned or script-registered schemas.
- Systems operate over component queries rather than over renderer-specific or script-owned object lists.
- Scene files author entity and component data as text component tables.
- The runtime world stores component instances in per-component column tables rather than renderer-specific side arrays.
- Engine subsystems can own internal worlds that use the same `World`, component registry, query, and schedule implementation as game worlds when they need isolated transient data.
- Engine-owned rendering components include transform, built-in primitive geometry, surface material, legacy cube renderer, camera, directional light, shadow marker, and UI primitive data.
- The renderer reads scene mesh, camera, light, shadow, and renderer-setting data from the authoritative scene world, and creates frame-local editor/UI overlay entities in that same world with engine-transient provenance.
- Entity handles carry dense index plus generation. Generated handles fail if a removed entity slot is reused or compacted into a different live entity.
- Each component table owns dense entity rows, a sparse entity-to-row index, and typed SoA field columns derived from engine or script schemas.
- Scripts can query entities by component set and mutate supported component fields through the scripting API.
- Script query iteration preserves the public component proxy API while internally reusing resolved component table and row positions for the lifetime of an iterator.
- Reusable script query objects cache prepared component table plans across invocations and invalidate them when the active world or world query-plan generation changes.
- Script query views can snapshot a matched entity set and bulk-transfer `f32` or `vec3` fields through Luau buffers for high-cardinality hot loops.
- Scripts can spawn and despawn entities through the ECS facade.
- Script and native spawned entities are runtime-spawned by default rather than authored scene data.
- Scripts can add and remove registered components through the ECS facade.
- Script-driven structural mutations are checked against the active system's declared write access.
- Script component add/remove/despawn operations are queued during a Luau system and flushed after the system returns successfully.
- Entities spawned during a Luau system are rolled back if that system fails before its queued structural commands flush.
- Scripts can register new component and system types with project-local or qualified non-reserved ids.
- Engine-owned and script-defined systems declare phases, read/write component access, and optional before/after ordering relationships.
- Engine-linked native systems use the same registry, schedule, and profiling path as Luau systems.
- The runtime can build phase-specific system schedule batches from those declarations.
- Worlds record structural events for scene/runtime entity creation/removal and component addition/removal; engine-transient frame entities and explicit internal component writes do not enter the journal.
- Runtime query observers can retain membership for a component set and report existing, appeared, and disappeared entities across structural changes.
- The example script-authored system queries entities with `scrapbot.transform` and project-local `spin`, then applies `spin.angular_velocity` to `scrapbot.transform.rotation` during update.
- Invalid, duplicate, or unsupported entity/component data produces diagnostics suitable for command-line and editor display.

## Design Decisions

### 1. Make components and systems the project mental model

**Decision:** Scrapbot teaches users, scripts, agents, and editor tools to think in entities, components, and systems.
**Why:** A shared component-system model keeps scene data, scripting, validation, and editor inspection aligned. It follows ADR-008.
**Tradeoff:** The engine needs component schema and API design earlier than a hardcoded demo renderer would.

### 2. Store component instances in sparse column tables

**Decision:** The runtime world owns one table per component type. A table stores entity handles densely, maps entity indexes back to table rows sparsely, and stores each component field in its own typed column.
**Why:** SoA columns give systems and renderer adapters a real ECS storage shape while still supporting runtime-created Luau component schemas. It follows ADR-008.
**Tradeoff:** This is not yet chunked archetype storage, and query planning is still simple. Generation-safe handles, deferred command buffers, migration, and parallel iteration need follow-up design.

### 3. Expose a safe ECS facade to scripts

**Decision:** Scripts interact with entities and components through an engine-supported API, not through direct native pointers or authoritative script object graphs.
**Why:** This keeps script behavior reloadable, testable, and consistent with text scene data. It follows ADR-006 and ADR-008.
**Tradeoff:** Some low-level power is intentionally hidden until the API has clear safety and lifecycle rules.

### 4. Distinguish local and qualified script extension ids

**Decision:** Script-defined component and system types use project-local single-segment ids or qualified dotted ids, with `scrapbot.*` reserved for engine-owned types.
**Why:** Component and system references need to be ergonomic in local projects and stable across packages, reloads, and diagnostics. It follows ADR-010.
**Tradeoff:** Promoting a local type into a reusable package requires an explicit id migration.

### 5. Schedule by declared access

**Decision:** System definitions include phase, read components, write components, and ordering relationships. The native runtime uses those declarations to build batches of systems that can run without access conflicts.
**Why:** Explicit access keeps validation, reload, editor inspection, and future parallel execution aligned. It follows ADR-006 and ADR-008.
**Tradeoff:** Systems must be honest and explicit about access before the scheduler can safely parallelize them.

### 6. Keep scene render data in the authoritative world

**Decision:** Engine subsystems may create separate worlds for isolated non-scene data, but render-facing scene data and frame-local editor/UI overlay entities live in the project world. Overlay entities use engine-transient provenance and are cleared after render submission.
**Why:** The scene world should be the single authority for authored, runtime-spawned, and frame-local render-facing entities. This follows ADR-022 while preserving ADR-013's rule that any internal worlds use the shared runtime implementation.
**Tradeoff:** Native/backend-only values still need an explicit storage design before they can live fully inside ECS.

### 7. Gate structural mutation by declared access

**Decision:** Script systems may create entities directly, but adding/removing components requires write access to the affected component, and despawning an entity requires write access to every component currently attached to it.
**Why:** Structural mutation changes query membership and scheduler safety just like field writes do. Reusing declared access keeps validation, diagnostics, live reload, and future parallelization aligned with ADR-006 and ADR-008.
**Tradeoff:** Generic cleanup systems must declare broad write access or narrow their entity sets before despawning.

### 8. Prepare script query iteration against ECS storage

**Decision:** Luau query iterators resolve component tables and row positions behind the component proxy API instead of rediscovering them through component ids on every yielded access.
**Why:** Script systems need hot loops that still look like normal ECS component iteration. Reusing resolved storage positions and caching reusable query object plans follows ADR-014 while keeping scheduler validation and row safety in the runtime.
**Tradeoff:** The bridge has more internal state, and component field access still crosses the host boundary unless a system opts into query views.

### 9. Add explicit bulk query views for hot Luau systems

**Decision:** Query objects expose `Query:view(world)` for frame-local bulk `f32` and `vec3` transfers through Luau buffers.
**Why:** Large Luau systems need to amortize host bridge overhead without bypassing the shared ECS world, scheduler access checks, or resolved-row validation. It follows ADR-015.
**Tradeoff:** Buffer offset code is less ergonomic than component proxies, so it should be used deliberately for measured hot loops rather than becoming the default script style.

### 10. Validate generated entity handles

**Decision:** Runtime-created entity handles carry generations, and runtime accessors reject nonzero-generation handles that no longer match the entity record at their dense index.
**Why:** Dense entity removal can move another entity into a removed index. Generation checks prevent stale handles and script proxies from silently aliasing that moved entity. It follows ADR-016.
**Tradeoff:** Handles are safer but not fully stable across compaction; an old handle to a moved entity also becomes invalid until a stable slot/free-list model exists.

### 11. Defer script structural commands

**Decision:** Luau component add/remove/despawn operations are command-buffered during a system callback and flushed after the callback succeeds. Immediate spawns are tracked and rolled back if the callback fails before flush.
**Why:** Structural mutation changes query membership and should occur at a scheduler boundary instead of mid-system. This keeps runtime behavior closer to future parallel scheduling and gives failed script systems cleaner rollback semantics. It follows ADR-017.
**Tradeoff:** Scripts cannot query their own queued component mutations until a later system or frame, and fully queued spawn handles still need a future temporary-handle design.

### 12. Track entity provenance in the runtime record

**Decision:** Each entity records whether it is authored scene data, spawned runtime state, or engine-transient frame data.
**Why:** Scene saving and editor entity-management features need to know which live entities are eligible for persistence without inferring that from component shape, id format, or script behavior. Render and editor overlays also need normal ECS storage without becoming gameplay or persisted entities.
**Tradeoff:** Provenance is an entity-level distinction only. Component-level authored-vs-runtime differences and persistence policies still need future design before partial scene saves are supported.

### 13. Record structural events in worlds

**Decision:** Each world owns a structural event journal for non-transient entity creation/removal and component addition/removal, with component-filtered iteration for consumers interested in specific component types.
**Why:** Engine subsystems can react to ECS membership changes without adding per-entity callbacks. Engine-transient render/editor frame data is intentionally skipped so frame cleanup does not look like gameplay structure changing.
**Tradeoff:** The first journal records structural membership changes only. Field-level change tracking, event cursor ownership, and component-lifecycle hooks remain future work.

### 14. Observe query membership from structural events

**Decision:** Runtime query observers retain membership for fixed component sets and expose appeared/disappeared deltas after refresh. They reconcile incrementally from structural events when possible and fall back to full query diffs when journals were cleared or entity removals may have compacted dense indices.
**Why:** Engine subsystems need a shared ECS-native way to keep retained side state synchronized with component-set membership without rescanning every entity each frame. This follows ADR-023.
**Tradeoff:** Observers report structural membership changes only. Consumers still need separate invalidation for field-value changes, and clearing the world event journal can force a full observer diff.

## Related

- **ADRs:** ADR-001, ADR-006, ADR-008, ADR-010, ADR-014, ADR-015, ADR-016, ADR-017, ADR-018, ADR-022, ADR-023
- **FDRs:** FDR-002, FDR-004, FDR-005, FDR-010, FDR-011, FDR-014, FDR-015, FDR-016, FDR-017

## Open Questions

- What stable id format should entities use?
- Should entity handles eventually use stable slots and a free list instead of dense indices that invalidate moved handles?
- How much scheduler control should scripts get beyond phases, access declarations, and before/after relationships?
- Should script structural command buffers flush after each system, each schedule batch, or each phase once parallel execution is introduced?
- Should command flushes gain all-or-nothing transaction rollback, or should preflight validation make flush-time failures impossible?
- Which additional field types need bulk query view support beyond `f32` and `vec3`?
- Should structural events gain field-level changed events or schedule-bound clearing rules?
