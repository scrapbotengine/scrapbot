# ADR-008: Use a small C ABI for native extensions

**Date:** 2026-07-12

## Context

Scrapbot projects should be able to move hot code from Luau into compiled native modules over time. The engine is written in Odin, but extension authors may eventually use Odin or another compiled language. That boundary needs to be stable enough for dynamic loading and hot reload experiments without exposing internal engine package layouts.

## Decision

Let projects declare native extension targets in `project.toml`, build those targets into `build/extensions`, load the resulting platform dynamic libraries, and look for a `scrapbot_extension_register` export. The ABI is a small C-compatible table in `extension_api`: opaque host userdata, functions for registering library component schemas and systems, and a callback context for scheduled system execution and deferred lifecycle commands. Host and extensions evolve in lockstep while Scrapbot builds extensions from project source. Build artifacts fingerprint both project extension source and the host extension API/helper source, while explicit ABI version negotiation is deferred until precompiled third-party extensions exist.

Odin extension authors should use the `scrapbot:extension` helper package over that raw ABI. The helper performs the common ABI checks and exposes component and field descriptors, a registration accumulator, and small procedures for component registration, access declarations, query iteration, transform access, vec3 field access, and lifecycle command queuing, while still exporting the same `scrapbot_extension_register` entry point.

Native extensions can register dotted, non-`scrapbot` library component names into the same component registry used by Luau scripts, scene validation, queries, and generated Luau types. They can also register scheduled systems with declared component reads and writes. Project runs and checks build and load native extensions before executing `scripts/main.luau`, so scripts can retrieve native-registered component handles with `scrapbot.component_handle(name)`, and runtime frames can batch native and Luau systems with the same scheduler rules.

## Consequences

The native extension surface remains intentionally narrow: component and system registration, shared geometry/material registration, query-by-component-name, transform and vec3 field access, and deferred lifecycle commands using resource handles. This supports dynamic loading, generated types, hot reload, native system execution, and resource-backed rendering without exposing internal ECS storage, GPU objects, allocators, or threading primitives.

The C ABI keeps the runtime boundary language-neutral and avoids coupling extensions to Scrapbot internals. The tradeoff is that the API must use plain data shapes and explicit versioning. The Odin wrapper can improve authoring ergonomics without changing that boundary, including descriptor-driven code that avoids repeating component strings. The first build path is Odin-specific for developer ergonomics, but the loaded library boundary remains language-neutral. Extension libraries must remain loaded while any runtime registry copied from their cstring metadata is in use.
