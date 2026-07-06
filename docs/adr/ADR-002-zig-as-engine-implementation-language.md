# ADR-002: Zig as the Engine Implementation Language

**Status:** Superseded by [ADR-023](ADR-023-odin-as-engine-implementation-language.md).

**Date:** 2026-07-01

## Context

Scrapbot needs a native, cross-platform implementation language suitable for engine runtime code, tooling, tests, and a single distributable binary. C and C++ are explicitly undesirable. Rust offers strong ecosystem advantages, especially around graphics, serialization, tooling, and package management, but it also introduces complexity around ownership, lifetimes, unsafe boundaries, compile times, and agent-generated refactors.

The engine is expected to contain substantial low-level systems: memory arenas, entity storage, renderer wrappers, asset caches, scripting bindings, UI layout, and platform integration. If a Rust implementation required large amounts of unsafe code in these areas, many of Rust's practical safety advantages would be reduced while its complexity would remain.

Zig offers explicit allocation, simple syntax, strong cross-compilation support, C ABI interop, and a low-level programming model that maps directly to engine work.

The repository uses `mise.toml` to select the Zig toolchain. This gives humans, agents, and CI a shared entrypoint for the currently intended stable Zig version without hard-coding local install paths.

## Decision

Scrapbot is implemented in Zig.

Development commands that invoke Zig should go through mise-managed tooling. The repository's `mise.toml` is the source of truth for the active Zig version.

The project will prefer explicit memory ownership, clear module boundaries, and simple data-oriented APIs over language-level abstraction. External dependencies are allowed where they provide substantial leverage, but the engine core remains Zig code.

## Consequences

The engine codebase should be easier to reason about as low-level systems code and may be friendlier to coding agents because control flow, allocation, and error handling are explicit.

Scrapbot gives up some of Rust's ecosystem advantages. The project will need to own more glue code for serialization, scripting bindings, build packaging, file watching, and native dependencies.

The team must be disciplined about memory safety and test coverage because Zig does not provide Rust's borrow checker or data-race guarantees. Debug and validation tooling become part of the safety strategy.

Using mise keeps local and automated Zig invocations aligned, but toolchain upgrades can still change compiler behavior because the configured Zig version tracks the latest stable release. Breakage from a new Zig release is treated as ordinary toolchain maintenance.
