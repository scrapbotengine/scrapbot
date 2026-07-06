# ADR-022: Odin as the Engine Implementation Language

**Date:** 2026-07-06

## Status

Accepted. Supersedes [ADR-002](ADR-002-zig-as-engine-implementation-language.md).

## Context

Scrapbot began as a Zig engine because Zig gave the project explicit allocation, direct C ABI interop, cross-platform builds, and a simple low-level model for ECS storage, rendering, scripting bridges, editor tooling, and command-line workflows.

The project is now intentionally changing direction: the engine implementation should move to Odin. The request is not a renderer, scripting, ECS, or scene-format redesign. The target end state is still a compact text-first game engine with Luau scripting, TOML project and scene files, an ECS runtime, retained UI/editor tooling, `wgpu-native` rendering, and deterministic command-line verification. The implementation language and toolchain are what change.

The current codebase still contains substantial Zig implementation while the migration is underway. A single replacement commit would remove too much working behavior at once and would make verification nearly meaningless. The migration therefore needs a staged path where Odin code can be built and tested beside the existing Zig engine until each subsystem reaches parity.

## Decision

Scrapbot's engine implementation language is Odin.

New engine implementation work should move toward Odin modules and Odin build/test workflows. The repository may keep Zig implementation code temporarily as migration scaffolding, but Zig is no longer the desired end state for engine-owned runtime, renderer, scripting bridge, UI/editor, CLI, or test implementation.

The migration starts with a separate Odin source root and explicit Odin build tasks. Existing Zig commands remain available until their Odin replacements are feature-complete enough to preserve the current project, scene, scripting, rendering, editor, and verification contracts.

The migration keeps these architectural commitments unless later ADRs explicitly change them:

- Luau remains the project-local scripting language.
- Project and scene data remain text-first TOML files.
- Runtime behavior remains ECS-shaped, with component registry validation, access-checked schedules, generation-aware entity handles, and deferred structural mutation.
- Rendering continues through engine-owned abstractions backed by `wgpu-native` through C ABI boundaries.
- External native dependency details stay behind engine-owned boundaries.
- The `scrapbot` CLI remains the primary automation and verification surface.

Project-local native modules should migrate from the current Zig source contract to an Odin source contract once the Odin host API exists. Until then, existing Zig native-module support is compatibility scaffolding for the migration, not a permanent language decision.

## Consequences

The project gains a clear target language for future engine work and a concrete way to start porting without deleting working behavior prematurely.

The migration must replace several Zig-specific surfaces:

- `build.zig` and `build.zig.zon` package/build orchestration.
- The vendored Zig `wgpu-native` binding package.
- Project-local native Zig module builds, generated `scrapbot_native` APIs, fixtures, and diagnostics.
- Zig-specific CI setup, test commands, cache directories, and agent guidance.
- Zig tests that currently prove ECS, scripting, UI layout, renderer extraction, editor interaction, native reload, and CLI behavior.

Odin introduces its own toolchain and package conventions. The repository uses `mise.toml` as the shared tool entrypoint, so Odin provisioning and tasks should live there while the migration is active.

Until feature parity is reached, some documentation will necessarily describe both the current Zig implementation and the intended Odin target. Those references should be explicit about migration status rather than implying that both languages are equally supported end states.

## Migration Order

1. Add Odin toolchain provisioning and a buildable smoke executable.
2. Port the first CLI/project slice: `init`, host-local `build` packaging, project metadata parsing, safe project-relative path checks, referenced file existence, and text/JSON `check` output.
3. Port the first scene validation/loading slice: root scene metadata, entity blocks, duplicate entity ids, component table placement, scene summary counts, and scene-authored ECS world materialization.
4. Port scene-authored engine component schema validation: engine-owned component ids, runtime-only component rejection, field names, field types, defaulted fields, and renderer setting values.
5. Port first-pass runtime foundations: component registry validation, generation-aware entity identity, component storage, query iteration, schedule batching, and deferred structural mutation.
6. Port first-pass script/native component schema discovery for scene validation while full Luau/native execution remains in Zig.
7. Port first-pass script system declaration discovery and schedule validation while Luau callbacks still execute through the Zig engine.
8. Port first-pass structured script registration and schedule diagnostics for `check` output.
9. Port Luau bridge-backed script loading and declaration import for Odin `check` while callback execution still waits for host callbacks.
10. Port first-pass Luau query and component-field callbacks so Odin `step`, `bench`, and bounded `run` can execute common script systems against the Odin ECS world.
11. Port first-pass Luau structural callbacks through the Odin deferred mutation buffer: spawn, add component, remove component, despawn, flush on success, and rollback on failure.
12. Port direct Luau entity vec3 get/set callbacks so scripts using `entity:get_vec3` and `entity:set_vec3` can execute against the Odin ECS world.
13. Port prepared Luau query iteration and resolved-row component field callbacks so ordinary query proxies can use the same row-level access path as Zig.
14. Port bulk f32/vec3 Luau query view callbacks so buffer-backed hot-loop scripts can read and write packed field values through Odin.
15. Port first-pass deterministic stepping command output.
16. Port first-pass benchmark command output while renderer stats still wait for their Odin implementation.
17. Port first-pass test command discovery, manifest validation, and field assertion execution while deterministic input replay and native-backed fixtures still wait for their Odin ports.
18. Port first-pass bounded `run` command validation while the window loop still waits for the Odin renderer and full callback bridge.
19. Port first-pass renderer ECS extraction and batch-stat planning before backend-specific drawing.
20. Port first-pass `render`, `render-test`, and `visual-test` command validation/output while pixel rendering still waits for Odin `wgpu-native` bindings.
21. Port the rest of the pure engine foundations before backend-heavy systems, including math helpers and runtime diagnostics.
22. Port detailed Luau bridge runtime diagnostics while preserving existing script fixtures.
23. Port remaining native and reload runtime diagnostics.
24. Port `wgpu-native` bindings and offscreen render verification.
25. Port retained UI, editor routing, and headful window integration.
26. Port project-local native modules from Zig to Odin.
27. Remove Zig build/test/dependency surfaces only after Odin replacements pass equivalent checks.

## Related

- **Supersedes:** ADR-002
- **ADRs:** ADR-001, ADR-003, ADR-004, ADR-005, ADR-006, ADR-008, ADR-009, ADR-018, ADR-019, ADR-021
- **FDRs:** FDR-001, FDR-003, FDR-010, FDR-012, FDR-013, FDR-019
