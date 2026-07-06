# FDR-012: Hybrid Luau and Zig Systems

**Status:** Active
**Last reviewed:** 2026-07-03

**Migration note:** This record describes the current Zig-backed native system behavior. [ADR-022](../adr/ADR-022-odin-as-engine-implementation-language.md) makes Odin the target engine implementation language, so future work should replace Zig-specific native module surfaces with Odin equivalents while preserving the language-neutral ECS contract. During the staged rewrite, the Odin `check` path can statically register component and system declarations from `native = "native/game.odin"`; compiling, loading, executing, and live-reloading Odin native modules remain pending.

## Overview

Hybrid Luau and Zig systems let game developers define ECS components and systems in either scripting code or native game code while sharing the same runtime world. The feature exists to support fast Luau prototyping first, then selective porting of hot paths to Zig when performance, platform integration, or native library access requires it.

## Behavior

- Developers can define components in Luau or Zig.
- Developers can define systems in Luau or Zig.
- Engine-linked Zig code can provide a `NativeExtension` with component and system registrations.
- Project-local Zig code can be declared with `native = "native/game.zig"` in `project.toml`.
- During the Odin migration, project-local Odin native declarations can be declared with `native = "native/game.odin"` for static component/system validation in the Odin `check` path.
- Project-local native modules export `scrapbot_register(api)` and import the engine-provided `scrapbot_native` API.
- During development, project-local native modules are built to `.scrapbot/native/`, loaded as dynamic libraries, and kept alive for the lifetime of the script program that registered their callbacks.
- Native components are registered before Luau scripts load, allowing Luau code to reference them with `ecs.component("id")`.
- Native systems are registered after Luau components, allowing Zig systems to read and write script-defined components.
- Luau-authored and Zig-authored systems participate in the same ECS schedule.
- Components use the same ids, schemas, validation rules, and scene references regardless of authoring language.
- Systems use the same phase, access declaration, and ordering model regardless of authoring language.
- A system can be ported from Luau to Zig without changing scene data or entity component ids.
- Native systems receive an opaque host context and use access-checked query/read/write helpers rather than direct `runtime.World` access.
- Native systems can read and write `bool`, `i32`, `f32`, `vec3`, and `string` component fields through the host facade.
- Native systems can spawn/despawn entities and add/remove components through deferred structural commands.
- Runtime diagnostics identify whether a failing component or system came from Luau script, native game code, or the engine.
- Native system runtime is profiled at the same scheduler dispatch boundary as Luau systems.
- Interactive workflows can reload Luau scripts without rebuilding native code.
- Interactive workflows reload project-local native source by rebuilding the dynamic library, re-registering the ECS program, validating the current scene, and swapping only on success.
- Failed native builds, loads, or registrations keep the last-known-good native program active and report structured diagnostics.
- Host game builds package project-local native code as a prebuilt artifact so the target machine does not need to rebuild it.
- Future static shipping builds should call the same registration entrypoint through static linking where dynamic code loading is impossible or forbidden.

## Design Decisions

### 1. Keep the ECS contract language-neutral

**Decision:** Components and systems are registered against the engine ECS model, not against a Luau-only or Zig-only model.
**Why:** The goal is interop. A component defined in Luau must be visible to Zig systems, and a component defined in Zig must be visible to Luau systems, editor tooling, validation, and scenes. This follows ADR-008 and ADR-010.
**Tradeoff:** Registration metadata must be rich and stable enough for both languages, which raises the bar for schema design.

### 2. Treat Luau as the prototyping path

**Decision:** The expected workflow is to prototype gameplay in Luau, then port specific systems to Zig when measurement shows a hot path.
**Why:** Luau gives fast iteration, readable text patches, and scripting ergonomics. Zig gives predictable native performance and lower-level integration when needed. This follows ADR-002 and ADR-006.
**Tradeoff:** Developers need a clear migration path and tooling that shows when the native port is behaviorally equivalent.

### 3. Make scheduling independent of implementation language

**Decision:** The scheduler uses declared phase, read/write access, and ordering constraints, not the language that implements the system.
**Why:** Parallelization, dependency validation, and reload safety depend on access declarations. Language-specific scheduling would fragment the runtime model. This follows ADR-008.
**Tradeoff:** Both Luau and Zig systems must declare access up front, even when the native implementation could technically do more dynamic work.

### 4. Keep native game modules optional at first

**Decision:** Hybrid registration can begin with engine-linked Zig systems before introducing per-game dynamic modules.
**Why:** Dynamic linking, platform support, symbol stability, ABI design, and hot reload are large architectural commitments. The user value starts with interop and a porting path, while dynamic native reload can come later. This follows ADR-005 and ADR-009.
**Tradeoff:** Early native systems may require rebuilding the engine or game binary until the module boundary exists.

### 5. Prefer a game-owned native extension boundary

**Decision:** The long-term model should allow a game project to provide a Zig native module or library that registers components and systems with the engine.
**Why:** Game-specific hot paths should not have to live inside the core engine repository. A module boundary preserves engine reuse while allowing native specialization.
**Tradeoff:** The engine must define a stable host ABI/API, reload lifecycle, diagnostics contract, and compatibility rules for native modules.

### 6. Start with engine-linked NativeExtension registration

**Decision:** The first active implementation is an engine-linked `NativeExtension` surface that registers native components and systems into `ScriptProgram` before the runtime schedule is built.
**Why:** This proves the shared ECS contract, schedule ordering, profiling, native diagnostics, and Luau/Zig component interop without prematurely committing to a dynamic library ABI. It follows ADR-018.
**Tradeoff:** The engine-linked surface remains useful for tests and built-in extensions, but project-local modules now use the same access-checked native host facade. Static shipping builds are still future work.

### 7. Add project-local native modules through a narrow host API

**Decision:** Game projects can declare one Zig source file with `native = "native/game.zig"`. Scrapbot builds it as a dynamic library during development, calls `scrapbot_register`, and exposes only the `scrapbot_native` registration/runtime facade.
**Why:** Project code should own its native hot paths without depending on engine internals or creating a second ECS. The narrow facade preserves the same scheduler access rules used by Luau and keeps a future static-link build path viable. This follows ADR-019.
**Tradeoff:** The facade must grow deliberately through typed callbacks and tests. It now supports scalar/string/vector field access plus structural lifecycle commands, but it still does not expose raw storage views, native pointers, or arbitrary engine internals.

### 8. Match Luau structural mutation semantics in native systems

**Decision:** Native entity spawns happen immediately and are tracked for rollback, while native add/remove component and despawn commands are queued and flushed only after the active system succeeds.
**Why:** Luau and Zig systems should have the same lifecycle model. Deferred structural mutation keeps queries stable during a system callback and prevents failed systems from leaving half-applied component changes behind.
**Tradeoff:** A native system cannot add a component and then read that component through a query in the same callback. The command becomes visible after the system returns successfully.

## Related

- **ADRs:** ADR-002, ADR-005, ADR-006, ADR-008, ADR-009, ADR-010, ADR-018, ADR-019
- **FDRs:** FDR-004, FDR-009, FDR-010, FDR-011

## Open Questions

- How are native module ABI compatibility and Zig compiler version compatibility handled across installed engine builds?
- What SDK shape should support static-link builds for platforms that forbid dynamic code loading?
- How do Luau and Zig share component storage layouts without leaking unstable engine internals?
- What tooling proves that a Zig port preserves behavior from the original Luau system?
- Which bulk/native storage view APIs are worth exposing without compromising storage encapsulation?
