# ADR-006: Use Luau for project scripting

**Date:** 2026-07-08

## Context

Scrapbot projects need a scripting language for project-local components, systems, editor automation, and hot reload. The runtime is written in Odin, but game code should not require recompiling native modules for every iteration.

The previous Zig prototype used Luau successfully. Alternatives such as Lua, Wren, Janet, and embedded JavaScript remain viable, but Luau has a strong sandboxing story, a gradual type system, good embedding APIs, and a gameplay-oriented ecosystem.

## Decision

Embed Luau as Scrapbot's project scripting language. Vendor Luau as a pinned source dependency and link the compiled runtime into the Scrapbot CLI.

The first integration executes `scripts/main.luau` when a project is run and exposes a tiny `scrapbot` API for logging and read-only ECS counts. Future slices will expand this into script components, scheduled script systems, typed API definitions, and hot reload.

## Consequences

Scrapbot gains a fast iteration path for project code without requiring native compilation. The engine can grow a stable scripting ABI around ECS concepts before exposing native extension boundaries.

Vendoring Luau adds a native C++ build step and platform-specific linker flags. Build tasks must keep that dependency explicit, and future Windows support will need a corresponding linker path.
