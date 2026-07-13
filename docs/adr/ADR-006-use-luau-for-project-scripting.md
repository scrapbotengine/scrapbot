# ADR-006: Use Luau for project scripting

**Date:** 2026-07-08

## Context

Scrapbot projects need a scripting language for project-local components, systems, editor automation, and hot reload. The runtime is written in Odin, but game code should not require recompiling native modules for every iteration.

The previous Zig prototype used Luau successfully. Alternatives such as Lua, Wren, Janet, and embedded JavaScript remain viable, but Luau has a strong sandboxing story, a gradual type system, good embedding APIs, and a gameplay-oriented ecosystem.

## Decision

Embed Luau as Scrapbot's project scripting language. Vendor Luau as a pinned source dependency and link the compiled runtime into the Scrapbot CLI.

Project runs execute `scripts/main.luau` when present and expose a small `scrapbot` API for logging, ECS counts, project component declarations, frame systems, custom component queries, transform rotation mutation, and hot reload. Future slices will expand this into scheduled systems, richer typed APIs, modules, editor scripting, and native extension boundaries.

## Consequences

Scrapbot gains a fast iteration path for project code without requiring native compilation. Project scripts can define simple data components, attach systems to the runtime loop, and iterate through hot reload while the engine grows a stable scripting ABI around ECS concepts.

Vendoring Luau adds a native C++ build step and platform-specific linker flags. Build tasks must keep that dependency explicit, and future Windows support will need a corresponding linker path.
