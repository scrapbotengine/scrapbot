# ADR-019: Project-Local Native Zig Modules

**Date:** 2026-07-03

## Context

Machina's hybrid ECS model needs a way for game projects to own native Zig code without placing game-specific hot paths inside the engine binary. Developers should be able to prototype in Luau, then port measured systems to Zig while keeping the same component ids, scene data, scheduler declarations, profiling, and diagnostics.

Dynamic native code loading is useful for the development loop, but some targets may forbid or heavily constrain dynamic code loading. The source-level native module contract should therefore also support future static linking during `machina build`.

## Decision

Machina supports project-local native Zig modules declared in `project.machina.toml`:

```toml
native = "native/game.zig"
```

During project loading, Machina builds that source file as a dynamic library into the project's generated `.machina/native/` cache, opens the library, and calls:

```zig
export fn machina_register(api: *const machina.RegisterApi) callconv(.c) c_int
```

Project native code imports the generated `machina_native` API module. This API exposes:

- Component and system registration helpers.
- Opaque host context handles instead of raw engine internals.
- Query and typed field access helpers for `bool`, `i32`, `f32`, `vec3`, and `string` component fields.
- Deferred structural ECS commands for spawning/despawning entities and adding/removing components.

Native callbacks run through the same ECS schedule, access declarations, profiling boundary, and runtime diagnostics as Luau systems. Native systems use a host facade that enforces declared component reads and writes at query/read/write time.

Native source files participate in live reload. When the native source changes, Machina rebuilds and reloads the module, rebuilds the ECS program, validates the current scene against the new registry, and swaps only if every stage succeeds. Failed native builds, loads, or registrations keep the last-known-good program active.

The dynamic library is the development-time loading mechanism. Host-platform `machina build` bundles may package a prebuilt native dynamic library artifact so the target machine does not need to rebuild project-local source. The registration entrypoint and `machina_native` API remain intentionally source-level concepts that a future SDK/static build path can call through a statically linked game module on platforms where dynamic loading is impossible or forbidden.

## Consequences

Game projects can now keep hot native ECS systems beside their scene and script files. Native code can interoperate with Luau-defined components, and Luau can reference native-defined components.

The native ABI is intentionally narrow. This protects engine internals, preserves scheduler access validation, and gives Machina room to change internal storage without breaking project modules unnecessarily.

Dynamic native reload is now part of the development loop, but it remains platform-sensitive. Host game builds can package native artifacts for desktop-style platforms, while consoles and other locked-down targets still need a static-link SDK path.

Native system APIs remain intentionally narrow. The public host facade supports query iteration, typed field reads/writes, and structural commands through access-checked callbacks instead of exposing `runtime.World` or storage pointers. Added components are queued with typed field values and flushed only after the native system succeeds, matching Luau lifecycle semantics.

## Related

- **ADRs:** ADR-002, ADR-005, ADR-008, ADR-009, ADR-018
- **FDRs:** FDR-009, FDR-010, FDR-012, FDR-013
