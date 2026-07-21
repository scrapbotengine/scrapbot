# ADR-008: Use a small C ABI for native extensions

**Date:** 2026-07-12

## Context

Scrapbot projects should be able to move hot code from Luau into compiled native modules over time. The engine is written in Odin, but extension authors may eventually use Odin or another compiled language. That boundary needs to be stable enough for dynamic loading and hot reload experiments without exposing internal engine package layouts.

## Decision

Let projects declare native extension targets in `project.toml`, build those targets into `.scrapbot/cache/extensions`, load the resulting platform dynamic libraries, and look for a `scrapbot_extension_register` export. The ABI is a small C-compatible table in `extension_api`: opaque host userdata, functions for registering library component schemas and systems, and a callback context for scheduled system execution and deferred lifecycle commands. Host and extensions evolve in lockstep while Scrapbot builds extensions from project source. Build artifacts fingerprint both project extension source and the host extension API/helper source, while explicit ABI version negotiation is deferred until precompiled third-party extensions exist.

Odin extension authors should use the `scrapbot:extension` helper package over that raw ABI. The helper performs the common ABI checks and exposes typed Number, Vec2, Vec3, Vec4, and Color field descriptors, editor metadata, a registration accumulator, and small procedures for component registration, access declarations, query iteration, transform access, typed field access, chunked field processing, portable four-lane SIMD values, and lifecycle command queuing, while still exporting the same `scrapbot_extension_register` entry point.

High-volume native systems may bind caller-owned arrays to a query chunk. The host copies up to 64 matching entities into those fixed-capacity scratch arrays, never exposes pointers into ECS storage, and validates every binding against the system's declared component access. Writable bindings carry an explicit 64-bit lane mask; only those lanes are committed and publish the corresponding exact dirty signals. This preserves allocator, storage, and scheduler boundaries while amortizing ABI calls and allowing extension code to process four or more entities at once with Odin SIMD.

The host compiles each distinct chunk descriptor into a bounded per-system plan. Plans retain stable custom-storage indices and typed field-array offsets, survive ordinary component membership churn, and invalidate when the World, component registry, or available storage families change. The opaque plan fields in the C ABI are host-owned implementation details.

Native extensions can register dotted, non-`scrapbot` library component names into the same component registry used by Luau scripts, scene validation, queries, and generated Luau types. They can also register scheduled systems with declared component reads and writes. Project runs and checks build and load native extensions before executing `scripts/main.luau`, so scripts can retrieve native-registered component handles with `scrapbot.component_handle(name)`, and runtime frames can batch native and Luau systems with the same scheduler rules.

## Consequences

The native extension surface remains intentionally narrow: component and system registration, shared geometry/material registration, query-by-component-name, scalar or chunked transform and typed scalar/vector field access, and deferred lifecycle commands using resource handles. This supports dynamic loading, generated types, hot reload, native system execution, generic inspection, and resource-backed rendering without exposing internal ECS storage, GPU objects, allocators, or threading primitives.

The C ABI keeps the runtime boundary language-neutral and avoids coupling extensions to Scrapbot internals. The tradeoff is that the API must use plain data shapes and explicit versioning. The Odin wrapper can improve authoring ergonomics without changing that boundary, including descriptor-driven code that avoids repeating component strings. The first build path is Odin-specific for developer ergonomics, but the loaded library boundary remains language-neutral. Extension libraries must remain loaded while any runtime registry copied from their cstring metadata is in use.
