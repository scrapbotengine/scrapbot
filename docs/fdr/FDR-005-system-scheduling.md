# FDR-005: System scheduling

**Status:** Active
**Last reviewed:** 2026-07-18

## Overview

System scheduling lets Scrapbot reason about which systems can run together by comparing declared component reads and writes. Conflict-free native systems execute concurrently, while Luau and undeclared systems remain serial barriers.

## Behavior

- Systems may declare component reads and writes.
- Systems with only read/read overlap can share a batch.
- Systems with read/write or write/write overlap are placed in separate batches.
- Systems without access declarations remain valid but execute exclusively because their data access is unknown.
- Luau systems may still use the legacy callback-only registration form.
- Luau systems may use an options table with an optional project-facing `name` and `reads` and `writes` arrays before the callback. Project-owned systems use single-token names; dotted multi-token names identify engine or library ownership.
- Luau access declarations may reference project component handles or registered component-name strings.
- Native extension systems declare component reads and writes through the native extension ABI.
- Component handles carry runtime component IDs, giving scheduler-facing declarations and runtime query paths a shared component-type identity.
- Unknown component names in system access declarations fail script loading.
- Systems with explicit access declarations may only read or write components covered by those declarations. Multi-component queries check every requested component against the active system declaration. Callback-only systems remain permissive.
- Conflict-free native systems execute concurrently on a persistent worker pool.
- Conflicting systems preserve registration order across scheduler stages.
- Luau systems execute serially on the calling thread and act as barriers between native stages.
- Each parallel native system receives a private deferred-command buffer; commands merge deterministically in system order after the stage completes.
- The combined frame schedule and native deferred-command buffers persist across frames. The schedule rebuilds only when system topology changes; buffers use compact ordered headers plus typed payload arrays, start small, and grow on demand.
- Every system in a frame observes the same read-only world time resource snapshot.
- `scrapbot run --scheduler-trace` reports worker count, parallel stage count, and maximum parallel width for the run.
- The runtime measures each project-Odin and Luau callback at its execution boundary and tags profiler entries with explicit Engine, Project Odin, or Luau provenance rather than inferring origin from names. The editor publishes every five successful frames from a rolling window of the last 50 successful frames and uses project-facing Luau names when provided; failed frames do not enter the sample.
- Structural world changes requested from Luau systems are queued in a deferred command buffer and applied after all scheduled systems finish for the frame.
- Deferred commands currently support spawning named entities with initial transform/project component payloads, despawning entities without shifting existing entity indices, and adding/removing `scrapbot.transform` or project components.
- Runtime spawns reuse dead entity slots and world-level free pools for transform, mesh, geometry, material, and render-instance storage regardless of the previous entity archetype. Reused entity slots retain their incremented generation, so handles from the previous entity lifetime remain stale.
- Every runtime-spawned entity lifetime receives a fresh UUID and is registered in the world's UUID lookup, even when its runtime storage slot is reused.
- Removing and re-adding supported built-in components returns their storage to the same free pools; mesh replacement updates owned storage and renderable records in place.
- Despawning invalidates the entity's custom-component and legacy-renderable records; later spawns reuse those records instead of growing per-frame query and render scans indefinitely.
- Multi-component queries choose the smallest requested project-component storage as their candidate set and validate remaining components against those candidates. Entities index their owned custom storages, so despawn and replacement release only attached records rather than scanning every registered component type.

## Design Decisions

### 1. Use access declarations for parallelism

**Decision:** Execute access-declared native systems in parallel when their reads and writes do not conflict, as established by ADR-009.
**Why:** The existing access contract provides a deterministic boundary for safe component-level parallelism.
**Tradeoff:** Incomplete declarations can cause data races inside native extensions, so undeclared systems execute exclusively and runtime access checks remain important.

### 2. Keep scheduling engine-level

**Decision:** Put scheduling in a runtime package independent of Luau.
**Why:** Native systems and future engine systems need the same conflict rules as script systems.
**Tradeoff:** Both the Luau bridge and native extension ABI must translate declarations into the engine-level scheduler model.

Component declarations are still stored by name for the scheduler, but handles now carry runtime component IDs that line up with ECS storage and query matching. That keeps the user-facing declaration format stable while the runtime moves toward ID-keyed system execution.

### 3. Preserve callback-only Luau systems

**Decision:** Keep `scrapbot.system(function)` as shorthand for a system with no declared access.
**Why:** This avoids making every small script declare access before the scheduler has visible parallel execution benefits.
**Tradeoff:** Callback-only systems are exclusive scheduler barriers and cannot benefit from parallel execution.

Declared systems now enforce their declared component access at the Luau API boundary and through the native system callback context. Callback-only Luau systems remain valid and permissive during the early scripting phase.

### 4. Defer structural world mutation until the frame boundary

**Decision:** Queue Luau entity/component lifecycle requests during system execution, then apply them after the scheduled frame step completes.
**Why:** Queries and future parallel system batches need stable entity/component storage while systems are running.
**Tradeoff:** Script code observes structural changes on the next frame. Command-buffer payload arrays grow geometrically to accept the frame's structural workload and retain their separate high-water allocations; caller-owned ABI staging payloads still have fixed limits.

### 5. Keep Luau on the calling thread

**Decision:** Run Luau systems serially after native work in each scheduler stage.
**Why:** Project scripts share one Luau VM, which is not a safe concurrent callback target. Native systems still gain parallelism without introducing multiple-VM state semantics.
**Tradeoff:** Luau-heavy frames remain mostly serial, and a future parallel script model would need isolated VMs or a different execution contract.

### 6. Merge native commands deterministically

**Decision:** Give parallel native systems private deferred-command buffers and merge them in scheduler order after all native work in the stage completes.
**Why:** A shared command buffer would race even when component accesses do not conflict, and completion-order merging would make lifecycle effects nondeterministic.
**Tradeoff:** Persistent buffers retain their high-water capacity and cannot expose one system's structural changes to another system in the same frame.

### 7. Recycle runtime entity storage with generation checks

**Decision:** Reuse dead entity slots, world-level built-in component free pools, custom-component records, and legacy-renderable records when deferred runtime mutations are applied.
**Why:** Short-lived runtime entities must not make per-frame entity, query, and render scans grow for the rest of the run. Incrementing the slot generation before reuse preserves stable indices without allowing stale handles to target a new entity lifetime.
**Tradeoff:** Component storage remains sparse, and every supported removal/despawn path must release ownership before a later entity can claim the slot.

### 8. Give each runtime lifetime a durable identity

**Decision:** Generate and register a fresh UUID when applying a spawn command, following ADR-023.
**Why:** Storage reuse must not make a newly spawned entity inherit the durable identity of the entity that previously occupied its slot.
**Tradeoff:** Spawn and despawn paths maintain both a generation-aware runtime handle and the UUID lookup map.

### 9. Measure callbacks at the scheduler boundary

**Decision:** Time each project-native worker callback and serial Luau callback where the scheduler invokes it, tag each fixed-storage entry with explicit provenance, retain the latest 50 successful samples in a fixed ring, and publish their rolling averages every five successful frames.
**Why:** The live editor needs useful per-system cost data without allocations, string formatting, or full-world work in the frame loop.
**Tradeoff:** The measurement excludes scheduler planning, deferred-command merging and application, rendering, and GPU execution. Engine provenance is reserved for engine-provided scheduled callbacks, which are not part of the current project callback snapshot. Each measured callback also pays for two monotonic-clock reads.

### 10. Retain stable frame scheduling work

**Decision:** Cache the dependency plan and per-native-system command buffers in the frame runtime. Rebuild the plan only after script or native-system topology changes, and clear rather than recreate command buffers between frames.
**Why:** A stable game loop should not repeatedly allocate command storage or recompute the same dependency graph. Small initial command buffers keep the persistent footprint proportional to actual structural mutation.
**Tradeoff:** Every topology-changing reload path must invalidate the cache, and command buffers retain their largest observed capacity until the frame runtime is destroyed.

### 11. Plan sparse queries from indexed membership

**Decision:** Keep bidirectional entity-to-project-component membership indexes and let a query cursor iterate the smallest requested custom storage before testing its remaining requirements.
**Why:** Sparse project components should make query and teardown work proportional to actual membership rather than world capacity or the number of registered component types.
**Tradeoff:** Every add, remove, restore, replacement, and despawn path must maintain both indexes. Cursor order is deliberately unspecified and must not become project semantics.

### 12. Store deferred commands by payload kind

**Decision:** Preserve command issue order in a compact header stream whose indices address separate spawn, despawn, add-component, and remove-component arrays. Copy only components actually present on a queued spawn into side arrays and remap those ranges when worker buffers merge.
**Why:** A single worst-case command record made every despawn reserve storage for a complete spawn, custom component arrays, and all UI payload variants. High-churn projects therefore paid the largest payload's memory and copy cost for their smallest lifecycle operation.
**Tradeoff:** Queue application and deterministic merging must resolve and remap payload indices correctly. Public Luau/native operations and their fixed-layout ABI staging values remain unchanged.

## Related

- **ADRs:** ADR-001, ADR-006, ADR-007, ADR-009, ADR-012, ADR-023, ADR-024
- **FDRs:** FDR-004, FDR-006

## Open Questions

- When should undeclared systems become warnings or errors?
- Should Luau eventually gain isolated worker VMs for parallel systems?
- Should deferred commands eventually flush between independent schedule batches, or only at frame boundaries?
