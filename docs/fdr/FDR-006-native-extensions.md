# FDR-006: Native extensions

**Status:** Active
**Last reviewed:** 2026-07-20

## Overview

Native extensions let project code add compiled engine/library behavior incrementally. Scrapbot builds project-declared Odin extension targets into dynamic libraries, loads them from the project directory, and lets them register component schemas and scheduled systems into the same runtime used by scene validation, Luau queries, generated Luau types, and frame execution.

## Behavior

- Projects declare native extension targets in `project.toml`.
- Each target has a stable `name` and an Odin source directory.
- `scrapbot build` compiles declared native extensions and includes the active outputs in a host-native game package without running the project.
- `scrapbot check` and `scrapbot run` compile declared native extensions before loading them.
- Scrapbot writes native extension libraries to `.scrapbot/cache/extensions` under the project root.
- Built extension files include the target name, build profile, a source stamp, and the platform dynamic-library suffix, such as `.dylib` on macOS and `.so` on Linux.
- `.scrapbot/cache/extensions/.scrapbot-extensions` records the active output files for the latest build.
- Each extension must export `scrapbot_extension_register`.
- The register function receives a lockstep C-compatible `extension_api.API`.
- Odin extensions can import `scrapbot:extension`, which wraps the raw ABI with helpers for components, systems, full geometry, generated cube/plane geometry, shared lit and emissive HDR materials, public ECS UI, queries, and deferred lifecycle commands.
- Project-local system callbacks use ordinary contextless Odin procedures; the helper owns stable callback bindings and hides the C-compatible trampoline.
- Odin extension authors can define `Component` and field descriptors once, then use those descriptors for schema registration, scheduler access, queries, and field reads/writes.
- `scrapbot.registry(ctx)` returns a small registration accumulator that records the first registration error so extension setup code can remain linear and return `scrapbot.err(&reg)` at the end.
- The API supports registering library component schemas with dotted, non-`scrapbot` names.
- The API supports registering native systems with declared component reads and writes.
- Project-owned native systems use single-token names; dotted multi-token names identify engine or library ownership. The convention is shared with Luau systems but is not yet runtime-enforced.
- Native systems can query by component names, read/write `scrapbot.transform`, read/write Number/Vec2/Vec3/Vec4/Color fields on schema-backed custom components, and read/write the complete value and style payloads of public `scrapbot.ui_*` components through the callback context.
- High-volume Odin systems can bind caller-owned fixed arrays to 64-entity query chunks. Chunk iteration amortizes host calls, supports portable four-lane SIMD helpers, and commits writable fields through explicit per-lane masks.
- Native systems can read renderer-owned `scrapbot.ui_state` payloads, including stable activation and change revisions, but cannot write that derived state.
- Native callback contexts expose the frame's read-only time resource snapshot.
- Native systems can spawn entities referencing shared geometry and material resources alongside transform, schema-backed components, and public UI components. The spawn helper returns the new entity's stable UUID so one deferred batch can establish UI parent relationships.
- Native lifecycle commands use the same command buffer as Luau lifecycle commands and apply after scheduled systems finish for the frame.
- `scrapbot run`, `scrapbot check`, and hot reload load native extensions before running project Luau.
- Luau can retrieve a native-registered component handle with `scrapbot.component_handle(name)`.
- Generated Luau types include component aliases for native-registered components after `scrapbot check`.
- Hot reload treats `project.toml`, extension file changes, and declared extension source directory changes as project reload triggers.
- When declared extension source changes, hot reload rebuilds native extensions before reloading the world and Luau runtime.

## Design Decisions

### 1. Declare and build project-local extension targets

**Decision:** Put native extension targets in `project.toml` and let Scrapbot compile them into `.scrapbot/cache/extensions`.
**Why:** Game developers should be able to run `scrapbot check` or `scrapbot run` and have native extension schemas available without knowing the platform-specific `odin build -build-mode:shared` command.
**Tradeoff:** The first builder is Odin-specific and assumes the engine source collection is available as `scrapbot` during local development.

### 2. Load active project-local build outputs

**Decision:** Build extensions into `.scrapbot/cache/extensions` and load only the paths listed in `.scrapbot-extensions` when that manifest exists.
**Why:** The cache is explicitly engine-owned and ignored, while the manifest prevents stale libraries from being loaded after versioned hot-reload builds.
**Tradeoff:** Old versioned libraries can accumulate in `.scrapbot/cache/extensions` until cleanup exists.

### 3. Keep the native ECS API narrow

**Decision:** Expose component schema registration plus scheduled native systems with a small callback context for query, transform, mesh, Number/Vec2/Vec3/Vec4/Color field access, typed public UI access, and deferred lifecycle commands. Carry editor metadata beside custom field types so native and Luau schemas drive the same generic inspector controls.
**Why:** This proves the “move hot Luau code to compiled code” path while keeping extension authors away from internal ECS storage, allocator ownership, and threading details.
**Tradeoff:** Native systems can only touch the supported typed ECS surfaces; they cannot yet allocate through a host allocator or access arbitrary nested/collection field types.

### 4. Keep UI payload ownership ABI-safe

**Decision:** Carry every public UI value and style in fixed-layout native payloads. Text and font names use bounded inline byte arrays, UI interaction state is read-only, and writes remain deferred through the ordinary command buffer.
**Why:** Native extensions need the same widgets as scenes, Luau, and editor chrome without sharing Odin strings, allocators, or pointers into engine storage across a dynamic-library boundary. See ADR-025.
**Tradeoff:** Native UI writes replace a complete typed payload after a read/modify/write cycle, strings have fixed maximum lengths, and a spawn contains at most the command buffer's fixed component capacity.

### 5. Provide an Odin authoring wrapper over the raw ABI

**Decision:** Add `scrapbot:extension` as a small Odin package that aliases the ABI types and offers descriptors plus helper procedures for common extension work.
**Why:** Extension authors should write idiomatic project/library code instead of repeating nil checks, component strings, raw pointer extraction, field counts, and table construction in every extension.
**Tradeoff:** The wrapper improves Odin ergonomics only. Non-Odin extension authors still target the raw C-compatible ABI or their own language bindings.

### 6. Reuse library component ownership

**Decision:** Native extensions register library-owned component names.
**Why:** Dotted library names already distinguish non-project components in scenes and generated types.
**Tradeoff:** There is not yet an authority model that ties a namespace to a specific package or extension binary.

### 7. Use versioned output names for reloadable libraries

**Decision:** Include a source tree stamp in built native extension filenames.
**Why:** Platform dynamic loaders can keep returning the already loaded library for the same path. A source-stamped filename gives each changed build a fresh path while the previous runtime can remain alive until the new runtime is ready.
**Tradeoff:** Source stamps are still detected by periodic polling, and the build directory needs future stale-output cleanup.

### 8. Prefer cursor iteration for native frame systems

**Decision:** Add an ABI-safe query cursor and `scrapbot.next` wrapper that advances through matching entities in one forward pass. Retain `count` and `entity_at` for compatibility and random-access tooling.
**Why:** The former count-plus-index loop rescanned the complete world for every match and became quadratic for dense systems. Native gameplay examples now demonstrate the linear iterator.
**Tradeoff:** The cursor currently scans world slots and checks every query term. A future storage-driven planner can choose the smallest component set without changing the public iteration shape.

### 9. Add scratch-buffer chunks without exposing ECS storage

**Decision:** Let native systems bind caller-owned arrays for Transform and schema-backed Number/Vec2/Vec3/Vec4 values, fill at most 64 matching lanes per call, and explicitly mark writable lanes before committing them.
**Why:** A scalar getter/setter pair per entity dominates simple compiled systems and prevents extensions from expressing portable lane-wise work. Caller-owned buffers amortize the ABI boundary and let Odin code use `#simd` while keeping internal ECS layouts, allocator ownership, and pointers private.
**Tradeoff:** Chunks copy values into scratch arrays and writable bindings require an extra commit. The API does not promise direct storage, alignment beyond the caller's arrays, stable candidate order, or automatic vectorization. Systems with branchy or low-volume behavior should keep using `scrapbot.next`.

### 10. Select optimization profiles by workflow

**Decision:** Compile extension checks with `-o:minimal`, source-project runs and hot reload with `-o:speed`, and packaged builds with `-o:speed`. Include the profile in cache artifact names.
**Why:** Fast checks and optimized play loops are different workflows, and sharing one output path can silently reuse code compiled for the wrong goal.
**Tradeoff:** A profile change creates another cached dynamic library. Release and performance currently share Odin's speed optimizer; release remains a distinct artifact/lifecycle profile for future stripping and distribution policy.

## Related

- **ADRs:** ADR-008, ADR-010, ADR-012, ADR-025, ADR-029
- **FDRs:** FDR-003, FDR-004, FDR-005, FDR-007

## Open Questions

- Should extension metadata include declared namespace ownership?
- Should chunk bindings eventually support booleans, resource handles, or optional fields?
