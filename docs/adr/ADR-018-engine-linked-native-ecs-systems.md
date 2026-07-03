# ADR-018: Engine-Linked Native ECS Systems

**Date:** 2026-07-03

## Context

Machina's long-term scripting model should let developers prototype systems in Luau and port measured hot paths to Zig without changing entity ids, component ids, scene data, or scheduler semantics.

Dynamic per-game native modules are still a large commitment: they need an ABI, platform-specific loading rules, reload lifecycle, symbol compatibility, and diagnostics. Machina needs an interop slice before locking down that module boundary.

## Decision

Machina supports engine-linked native ECS systems through a `NativeExtension` registration surface.

- Native extensions can register project components.
- Native extensions can register project systems with the same id, phase, read/write access, and before/after ordering model as Luau systems.
- Native components are registered before Luau chunks load so scripts can reference them with `ecs.component("id")`.
- Native systems are registered after Luau components so native systems can read and write script-defined components.
- The runtime schedule uses one `SystemRunner` union with `none`, `luau`, and `native` runner variants.
- Native systems run through the same schedule batches and profiling boundary as Luau systems.
- Native callbacks receive a narrow `NativeSystemContext` containing the world, delta seconds, and system id.

The first implementation is linked into the engine/test binary. It is not a dynamic per-game library loader and does not hot-reload native code.

## Consequences

Luau and Zig systems now interoperate over the same ECS registry, component storage, schedule, and profiling data. A hot Luau system can be ported toward Zig while keeping component ids and scheduler declarations stable.

Native callbacks are currently trusted Zig code with direct `World` access. Their declared read/write sets drive scheduling and diagnostics, but the host does not yet enforce those declarations at every `World` method call the way the Luau bridge does.

The dynamic module boundary remains future work. That boundary should build on this registration model instead of introducing a second ECS or scheduler.
