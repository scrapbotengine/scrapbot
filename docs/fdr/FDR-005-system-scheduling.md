# FDR-005: System scheduling

**Status:** Active
**Last reviewed:** 2026-07-12

## Overview

System scheduling lets Scrapbot reason about which systems can run together by comparing declared component reads and writes. The first implementation computes conflict-free batches for Luau and native systems but still executes them serially.

## Behavior

- Systems may declare component reads and writes.
- Systems with only read/read overlap can share a batch.
- Systems with read/write or write/write overlap are placed in separate batches.
- Systems without access declarations remain valid and can batch with any other system.
- Luau systems may still use the legacy callback-only registration form.
- Luau systems may use an options table with `reads` and `writes` arrays before the callback.
- Luau access declarations may reference project component handles or registered component-name strings.
- Native extension systems declare component reads and writes through the native extension ABI.
- Component handles carry runtime component IDs, giving scheduler-facing declarations and runtime query paths a shared component-type identity.
- Unknown component names in system access declarations fail script loading.
- Systems with explicit access declarations may only read or write components covered by those declarations. Multi-component queries check every requested component against the active system declaration. Callback-only systems remain permissive.
- Scheduled Luau and native batches currently execute serially in deterministic batch order.
- Structural world changes requested from Luau systems are queued in a deferred command buffer and applied after all scheduled systems finish for the frame.
- Deferred commands currently support spawning named entities with initial transform/project component payloads, despawning entities without shifting existing entity indices, and adding/removing `scrapbot.transform` or project components.

## Design Decisions

### 1. Start with access declarations before parallelism

**Decision:** Add declared reads/writes and conflict-free batching before introducing worker threads.
**Why:** Parallel execution needs a trustworthy data-access contract first. Batching gives us a testable scheduling boundary while the ECS storage model is still evolving.
**Tradeoff:** The scheduler can identify parallelism, but the runtime does not use extra CPU cores yet.

### 2. Keep scheduling engine-level

**Decision:** Put scheduling in a runtime package independent of Luau.
**Why:** Native systems and future engine systems need the same conflict rules as script systems.
**Tradeoff:** Both the Luau bridge and native extension ABI must translate declarations into the engine-level scheduler model.

Component declarations are still stored by name for the scheduler, but handles now carry runtime component IDs that line up with ECS storage and query matching. That keeps the user-facing declaration format stable while the runtime moves toward ID-keyed system execution.

### 3. Preserve callback-only Luau systems

**Decision:** Keep `scrapbot.system(function)` as shorthand for a system with no declared access.
**Why:** This avoids making every small script declare access before the scheduler has visible parallel execution benefits.
**Tradeoff:** Undeclared systems are less informative to the scheduler and may need stricter rules once true parallel execution arrives.

Declared systems now enforce their declared component access at the Luau API boundary and through the native system callback context. Callback-only Luau systems remain valid and permissive during the early scripting phase.

### 4. Defer structural world mutation until the frame boundary

**Decision:** Queue Luau entity/component lifecycle requests during system execution, then apply them after the scheduled frame step completes.
**Why:** Queries and future parallel system batches need stable entity/component storage while systems are running.
**Tradeoff:** Script code observes structural changes on the next frame, and the first command buffer has a fixed capacity and only supports basic transform/project-component mutation.

## Related

- **ADRs:** ADR-001, ADR-006, ADR-007
- **FDRs:** FDR-004, FDR-006

## Open Questions

- When should undeclared systems become warnings or errors?
- Should Luau systems remain main-thread-only once scheduler batches execute on worker threads?
- Should deferred commands eventually flush between independent schedule batches, or only at frame boundaries?
