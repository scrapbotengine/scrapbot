# ADR-017: Deferred Script Structural Commands

**Date:** 2026-07-03

## Context

Script systems can spawn entities, add/remove components, and despawn entities. Immediate structural mutation during a system makes query membership change while the system is still executing, which complicates scheduler safety, future parallel execution, and rollback after script errors.

Machina needs script mutation semantics that keep scheduled systems as the authority for structural changes while still allowing ergonomic startup/gameplay code.

## Decision

Luau structural component/entity commands are buffered during a system invocation and flushed only after the Luau callback returns successfully.

- `world.spawn(...)` creates an entity immediately so the script can receive a generated handle for subsequent queued commands.
- `entity:add(...)`, `entity:remove(...)`, and `entity:despawn()` enqueue structural commands.
- Queued add commands deep-copy component ids, field names, and string payloads before returning to Luau.
- On successful system return, queued commands flush in call order while the active system context is still available for diagnostics.
- If the Luau callback fails before flush, queued commands are discarded and entities spawned immediately by that callback are rolled back.

The first implementation flushes after each Luau system, not after an entire batch or phase.

## Consequences

Script systems no longer observe their own component add/remove/despawn commands through queries until after the system returns and the queue flushes. Later systems in the same phase can observe flushed changes if schedule ordering places them after the mutating system.

Failed systems no longer leave behind entities they spawned before throwing, and queued component mutations do not partially apply before a script runtime error.

Flush-time host failures are still fail-fast diagnostics, not full world transactions. If a future command flush can fail after applying earlier commands, Machina should either make those failures impossible through preflight validation or add a world transaction/snapshot layer before promising all-or-nothing flush rollback.

The immediate-spawn plus queued-component model is a pragmatic bridge. A fuller command buffer can eventually represent spawn as a pure queued operation with temporary script handles, and can choose stricter batch/phase flush boundaries once scheduler parallelism needs it.
