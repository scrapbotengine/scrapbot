# FDR-006: Native extensions

**Status:** Active
**Last reviewed:** 2026-07-12

## Overview

Native extensions let project code add compiled engine/library behavior incrementally. Scrapbot builds project-declared Odin extension targets into dynamic libraries, loads them from the project directory, and lets them register component schemas and scheduled systems into the same runtime used by scene validation, Luau queries, generated Luau types, and frame execution.

## Behavior

- Projects declare native extension targets in `project.toml`.
- Each target has a stable `name` and an Odin source directory.
- `scrapbot build` compiles declared native extensions without running the project.
- `scrapbot check` and `scrapbot run` compile declared native extensions before loading them.
- Scrapbot writes native extension libraries to `build/extensions` under the project root.
- Built extension files include the target name, a source stamp, and the platform dynamic-library suffix, such as `.dylib` on macOS and `.so` on Linux.
- `build/extensions/.scrapbot-extensions` records the active output files for the latest build.
- Each extension must export `scrapbot_extension_register`.
- The register function receives a versioned C-compatible `extension_api.API`.
- Odin extensions can import `scrapbot:extension`, which wraps the raw ABI with helpers for components, systems, full geometry, generated cube/plane geometry, shared materials, queries, and deferred lifecycle commands.
- Odin extension authors can define `Component` and field descriptors once, then use those descriptors for schema registration, scheduler access, queries, and field reads/writes.
- `scrapbot.registry(ctx)` returns a small registration accumulator that records the first registration error so extension setup code can remain linear and return `scrapbot.err(&reg)` at the end.
- The API supports registering library component schemas with dotted, non-`scrapbot` names.
- The API supports registering native systems with declared component reads and writes.
- Native systems can query by component names, read/write `scrapbot.transform`, and read/write vec3 fields on schema-backed custom components through the callback context.
- Native callback contexts expose the frame's read-only time resource snapshot.
- Native systems can spawn entities referencing shared geometry and material resources alongside transform and schema-backed components.
- Native lifecycle commands use the same command buffer as Luau lifecycle commands and apply after scheduled systems finish for the frame.
- `scrapbot run`, `scrapbot check`, and hot reload load native extensions before running project Luau.
- Luau can retrieve a native-registered component handle with `scrapbot.component_handle(name)`.
- Generated Luau types include component aliases for native-registered components after `scrapbot check`.
- Hot reload treats `project.toml`, extension file changes, and declared extension source directory changes as project reload triggers.
- When declared extension source changes, hot reload rebuilds native extensions before reloading the world and Luau runtime.

## Design Decisions

### 1. Declare and build project-local extension targets

**Decision:** Put native extension targets in `project.toml` and let Scrapbot compile them into `build/extensions`.
**Why:** Game developers should be able to run `scrapbot check` or `scrapbot run` and have native extension schemas available without knowing the platform-specific `odin build -build-mode:shared` command.
**Tradeoff:** The first builder is Odin-specific and assumes the engine source collection is available as `scrapbot` during local development.

### 2. Load active project-local build outputs

**Decision:** Build extensions into `build/extensions` and load only the paths listed in `.scrapbot-extensions` when that manifest exists.
**Why:** The output directory still matches a generated-output workflow, while the manifest prevents stale libraries from being loaded after versioned hot-reload builds.
**Tradeoff:** Old versioned libraries can accumulate in `build/extensions` until cleanup exists.

### 3. Keep the native ECS API narrow

**Decision:** Expose component schema registration plus scheduled native systems with a small callback context for query, transform, mesh, vec3 field access, and deferred lifecycle commands.
**Why:** This proves the “move hot Luau code to compiled code” path while keeping extension authors away from internal ECS storage, allocator ownership, and threading details.
**Tradeoff:** Native systems can only touch the first supported ECS surface; they cannot yet allocate through a host allocator or access arbitrary component field types.

### 4. Provide an Odin authoring wrapper over the raw ABI

**Decision:** Add `scrapbot:extension` as a small Odin package that aliases the ABI types and offers descriptors plus helper procedures for common extension work.
**Why:** Extension authors should write idiomatic project/library code instead of repeating nil checks, component strings, raw pointer extraction, field counts, and table construction in every extension.
**Tradeoff:** The wrapper improves Odin ergonomics only. Non-Odin extension authors still target the raw C-compatible ABI or their own language bindings.

### 5. Reuse library component ownership

**Decision:** Native extensions register library-owned component names.
**Why:** Dotted library names already distinguish non-project components in scenes and generated types.
**Tradeoff:** There is not yet an authority model that ties a namespace to a specific package or extension binary.

### 6. Use versioned output names for reloadable libraries

**Decision:** Include a source tree stamp in built native extension filenames.
**Why:** Platform dynamic loaders can keep returning the already loaded library for the same path. A source-stamped filename gives each changed build a fresh path while the previous runtime can remain alive until the new runtime is ready.
**Tradeoff:** Source stamps are still detected by periodic polling, and the build directory needs future stale-output cleanup.

## Related

- **ADRs:** ADR-008, ADR-012
- **FDRs:** FDR-004, FDR-005

## Open Questions

- Should extension metadata include declared namespace ownership?
- What should the native ECS ABI expose next: richer field types, host allocator hooks, or richer renderable construction?
