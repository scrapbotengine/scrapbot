# FDR-006: Native extensions

**Status:** Active
**Last reviewed:** 2026-07-11

## Overview

Native extensions let project code add compiled engine/library behavior incrementally. Scrapbot builds project-declared Odin extension targets into dynamic libraries, loads them from the project directory, and lets them register component schemas into the same registry used by scene validation, Luau queries, and generated Luau types.

## Behavior

- Projects declare native extension targets in `project.toml`.
- Each target has a stable `name` and an Odin source directory.
- `scrapbot build` compiles declared native extensions without running the project.
- `scrapbot check` and `scrapbot run` compile declared native extensions before loading them.
- Scrapbot looks for native extension libraries in `build/extensions` under the project root.
- Extension files use the platform dynamic-library suffix, such as `.dylib` on macOS and `.so` on Linux.
- Each extension must export `scrapbot_extension_register`.
- The register function receives a versioned C-compatible `extension_api.API`.
- The first API supports registering library component schemas with dotted, non-`scrapbot` names.
- `scrapbot run`, `scrapbot check`, and hot reload load native extensions before running project Luau.
- Luau can retrieve a native-registered component handle with `scrapbot.component_handle(name)`.
- Generated Luau types include component aliases for native-registered components after `scrapbot check`.
- Hot reload treats extension file additions, removals, and modified stamps as project reload triggers.

## Design Decisions

### 1. Declare and build project-local extension targets

**Decision:** Put native extension targets in `project.toml` and let Scrapbot compile them into `build/extensions`.
**Why:** Game developers should be able to run `scrapbot check` or `scrapbot run` and have native extension schemas available without knowing the platform-specific `odin build -build-mode:shared` command.
**Tradeoff:** The first builder is Odin-specific and assumes the engine source collection is available as `scrapbot` during local development.

### 2. Load project-local build outputs

**Decision:** Load extensions from `build/extensions`.
**Why:** The path matches a generated-output workflow and avoids scanning source trees.
**Tradeoff:** Stale manually placed libraries can still be loaded if they remain in the output directory.

### 3. Start with schema registration only

**Decision:** Expose only component schema registration in the first native ABI.
**Why:** Component registration exercises the dynamic boundary while keeping world mutation, scheduler integration, and memory ownership out of the first ABI.
**Tradeoff:** Native extensions cannot yet define systems or operate directly on ECS storage.

### 4. Reuse library component ownership

**Decision:** Native extensions register library-owned component names.
**Why:** Dotted library names already distinguish non-project components in scenes and generated types.
**Tradeoff:** There is not yet an authority model that ties a namespace to a specific package or extension binary.

## Related

- **ADRs:** ADR-008
- **FDRs:** FDR-004, FDR-005

## Open Questions

- What should the native system ABI look like once systems can participate in scheduling?
- How should native extension source watching trigger rebuilds during hot reload?
- Should extension metadata include declared namespace ownership?
