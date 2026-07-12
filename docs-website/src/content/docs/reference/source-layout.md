---
title: Source Layout
description: Ownership boundaries inside the Scrapbot engine source tree.
---

The `src/scrapbot` package is the public runtime facade used by the CLI. Most implementation code belongs to a narrower child package:

| Package | Responsibility |
| --- | --- |
| `shared` | Runtime data contracts shared between packages |
| `project` | Manifests, scene parsing, project creation, and loading |
| `ecs` | World state, queries, and deferred world commands |
| `component` | Component schemas, validation, and generated Luau types |
| `schedule` | Access declarations and conflict-free batch planning |
| `diagnostic` | Stable machine-readable diagnostic records for tools and commands |
| `package.odin` | Host-native game packaging and target selection |
| `script` | Luau lifecycle, bindings, systems, queries, commands, and value marshaling |
| `native` | Extension builds, discovery, loading, ABI registration, and native system execution |
| `resources` | Geometry, PNG texture, and material resource ownership plus primitive generation |
| `extension_api` | Stable C-compatible native extension contract |
| `extension` | Higher-level Odin API used by extension authors |
| `platform` | SDL window and event integration |
| `render` | Backend selection, WGPU and null backends, shader source, render math, and PNG output |

The command-line entry point lives in `src/scrapbot_cli` and delegates engine behavior to the public facade.

## File organization

Large integration packages are split by responsibility without introducing artificial package boundaries:

- `script.odin` owns Luau runtime setup and stepping; sibling files own API registration, components and systems, queries, deferred commands, and error conversion.
- `native.odin` owns loaded extensions and host ABI dispatch; `build.odin` and `files.odin` own compilation and source/output discovery.
- `wgpu.odin` owns frame rendering and command encoding; `wgpu_setup.odin`, `wgpu_shader.odin`, and `wgpu_math.odin` isolate device setup, shader, and transform concerns.

When adding engine code, use the narrowest package and file that owns the behavior. Keep the root `scrapbot` package focused on orchestration and the public API used by tools.
