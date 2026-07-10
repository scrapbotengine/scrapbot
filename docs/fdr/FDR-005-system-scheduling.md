# FDR-005: System scheduling

**Status:** Active
**Last reviewed:** 2026-07-11

## Overview

System scheduling lets Scrapbot reason about which systems can run together by comparing declared component reads and writes. The first implementation computes conflict-free batches but still executes them serially.

## Behavior

- Systems may declare component reads and writes.
- Systems with only read/read overlap can share a batch.
- Systems with read/write or write/write overlap are placed in separate batches.
- Systems without access declarations remain valid and can batch with any other system.
- Luau systems may still use the legacy callback-only registration form.
- Luau systems may use an options table with `reads` and `writes` arrays before the callback.
- Luau access declarations may reference project component handles or registered component-name strings.
- Unknown component names in system access declarations fail script loading.
- Scheduled Luau batches currently execute serially in deterministic batch order.

## Design Decisions

### 1. Start with access declarations before parallelism

**Decision:** Add declared reads/writes and conflict-free batching before introducing worker threads.
**Why:** Parallel execution needs a trustworthy data-access contract first. Batching gives us a testable scheduling boundary while the ECS storage model is still evolving.
**Tradeoff:** The scheduler can identify parallelism, but the runtime does not use extra CPU cores yet.

### 2. Keep scheduling engine-level

**Decision:** Put scheduling in a runtime package independent of Luau.
**Why:** Native systems and future engine systems need the same conflict rules as script systems.
**Tradeoff:** The Luau bridge must translate script declarations into the engine-level scheduler model.

### 3. Preserve callback-only Luau systems

**Decision:** Keep `scrapbot.system(function)` as shorthand for a system with no declared access.
**Why:** This avoids making every small script declare access before the scheduler has visible parallel execution benefits.
**Tradeoff:** Undeclared systems are less informative to the scheduler and may need stricter rules once true parallel execution arrives.

## Related

- **ADRs:** ADR-001, ADR-006
- **FDRs:** FDR-004

## Open Questions

- When should undeclared systems become warnings or errors?
- How should deferred world mutations be represented between scheduled batches?
- Should Luau systems remain main-thread-only once native systems start running in parallel?
