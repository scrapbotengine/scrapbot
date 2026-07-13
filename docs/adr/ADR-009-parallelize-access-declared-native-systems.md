# ADR-009: Parallelize access-declared native systems

**Date:** 2026-07-12

## Context

Scrapbot already groups systems from declared component reads and writes, but executes every group serially. Native Odin systems can use multiple CPU cores when their component access does not conflict. Luau callbacks share one VM, and systems without access declarations do not provide enough information to run safely beside other work.

## Decision

Execute conflict-free native systems concurrently on a runtime-owned worker pool. Preserve registration order between conflicting systems, give each native worker a private deferred-command buffer, and merge those commands deterministically after the native stage. Execute Luau systems serially on the calling thread as barriers. Treat systems without access declarations as exclusive.

## Consequences

Access-declared native systems can use multiple CPU cores without changing the extension API. Conflicting systems, Luau callbacks, and undeclared systems remain deterministic. Native extension authors must declare complete access sets to gain parallel execution. Worker-pool lifecycle, thread-safe native callbacks, and deterministic command merging become runtime responsibilities.
