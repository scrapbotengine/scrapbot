# Machina Agent Guide

Machina is an experimental, text-first game engine written in Zig with embedded Luau for project-local scripting. This file is the authoritative home for rules agents must follow before changing code. ADRs, FDRs, and skills are further reading, not replacements for these rules.

## Project Goals

- Keep project state inspectable, editable, and reviewable as source text wherever possible.
- Use binary files only for assets, generated data, vendored dependencies, and build outputs.
- Keep the engine friendly to agent workflows: small vertical slices, clear diffs, deterministic checks, and documented decisions.
- Run projects with `machina run` from the project directory. `machina run --editor` starts with the editor shell visible; Ctrl+Tab toggles it in headful runs.

## Non-Negotiable Design Rules

- The engine is implemented in Zig. Luau is for project-local game scripting only; do not implement engine features in Luau.
- Implement behavior through reusable ECS components, systems, schedules, and shared runtime services. Do not add per-entity callbacks or hardcoded one-off entity logic that bypasses the ECS model.
- Route runtime state through ECS worlds. Engine subsystems may own internal worlds and schedules, but they must use the shared runtime ECS implementation rather than a parallel ECS model.
- Preserve component registry validation for scene data, script ECS declarations, native ECS declarations, and project-local component ids.
- Preserve generation-aware entity handles across query, spawn, despawn, proxy, selection, and bulk-view paths. Reject stale handles instead of silently reusing dense indices.
- Preserve deferred structural mutation semantics. Script and native add/remove/despawn commands queued during a system must flush only after that system succeeds; same-callback queries must not observe queued structural changes.
- Preserve live reload's staged validation and last-known-good behavior. Failed reloads must produce diagnostics without destroying the running project state.
- Long-lived reloadable state must use allocation strategies that can free replaced resources; avoid arena-backed state for reloadable worlds and scenes.
- Keep external backend and native dependency details behind engine-owned boundaries. Do not expose backend APIs through scene, project, or scripting layers.

## Project and Scene Data

- Keep project and scene data text-based, inspectable, and diffable.
- Projects use `project.machina.toml`, a default scene path, optional `scripts = [...]`, and at most one project-local native Zig module declared with `native = "native/game.zig"`.
- Scenes are TOML files with root `name` and `version` fields plus `[[entities]]` records containing component tables.
- Scene-authored component ids and fields must validate against the engine, script, and native component registry.
- New scene-authored renderables should use `machina.geometry.primitive` plus `machina.material.surface`; treat `machina.render.cube` as a legacy shortcut.
- Input components such as `machina.input.pointer`, `machina.input.keyboard`, and `machina.input.frame` are runtime resources, not scene-authored data.
- Treat `machina.ui.command_event` as runtime-only transient data. Author `machina.ui.command` on button entities instead.
- Do not commit generated `.machina/` project-native build caches.

## ECS, Scripting, and Native Modules

- `src/runtime.zig` owns the shared `World`, component registry, component tables, and schedule planning model.
- Systems must declare phase plus read/write component access before participating in scheduling.
- Structural mutations must happen inside scheduled systems through the ECS APIs. Adding or removing a component requires declared write access to that component; despawning requires write access to every component currently attached to the entity.
- Script-defined component and system types use explicit ids. Single lowercase ASCII identifier segments are project-local; qualified dotted ids are for packages or libraries; `machina.*` is engine-owned.
- New Luau component schemas should use `ecs.fields({ field = "type" })`. Do not use `ecs.schema(...)` or `ecs.vec3()` in new examples, features, or tests except for explicit compatibility coverage.
- Keep the public script API system-first: scripts declare component access, and the native engine owns scheduling, validation, reload transactions, diagnostics, and future parallelization.
- In hot Luau loops, cache component fields in locals before reusing them. Repeated field access crosses the host ECS bridge, and repeated vec3 field access allocates tables.
- For large measured Luau loops, prefer explicit `Query:view(world)` bulk `f32`/`vec3` buffers over per-entity proxy access only when the buffer complexity is justified.
- Measure Luau bridge hot-loop optimizations before keeping them. Query-local field-index caching has already regressed versus the simpler resolved-row path in `spawn_swarm`.
- Project-local native Zig code imports `machina_native`, exports `machina_register(api)`, and uses the access-checked host API. Do not expose or depend on raw `runtime.World` from project native modules.
- Native systems and components must use the same component registry, scheduler, profiling path, and deferred mutation semantics as Luau systems.

## UI, Input, and Editor Rules

- Keep input and UI interaction state ECS-shaped. SDL or platform event code translates raw events into frame input; hover, press, focus, command routing, and editor state belong in ECS components/systems.
- Route UI layout, hit testing, scroll handling, button commands, hover/press visuals, canvas viewport scaling, editor chrome, and editor controls through public `machina.ui.*`, `machina.input.*`, and `src/ui_layout.zig`.
- Do not add renderer-private, editor-private, or example-private UI/input paths when retained ECS UI can represent the behavior.
- Use `ui_layout.routePointer` as the default entry point when a feature needs command, scroll, and capture ownership from one pointer frame. Keep lower-level `commandAt`, `routeScrollWheelAt`, and `applyScrollWheelAt` consistent with it.
- Route retained command buttons through `ui_layout.commandAt` or `routePointer` after any needed viewport/design-space conversion.
- Route scroll-wheel handling through `ui_layout.routePointer`, `routeScrollWheelAt`, or `applyScrollWheelAt` against retained `machina.ui.scroll_view` data.
- Scene-authored UI input routing must use the retained layout model before hit testing. Do not hit-test raw `machina.ui.rect.position` unless parent layout and clipping have been resolved.
- Prefer reusable retained layout primitives over one-off renderer/editor layout shortcuts: `scroll_view` for clipped scrolling, `vbox` for vertical stacks, `hgroup` for resizable horizontal regions, `stack` for general layout, and `layout.item` with stable entity-id parents for child ordering.
- If editor chrome needs a new control, layout behavior, input rule, or renderer capability, add it as reusable `machina.ui.*`, `machina.input.*`, shared `ui_layout`, or shared render-system behavior first, then consume it from the editor.
- Engine-owned editor chrome may generate retained ECS UI entities procedurally, but must not introduce private UI primitives, layout math, input routing, or render paths when public ECS UI can represent the behavior.
- Editor gizmos and editor chrome should be generated as engine-owned render/UI data and must not mutate project scene files or become selectable game entities.
- Keep editor/debug and example UI text legible at normal viewing sizes. Do not use built-in bitmap UI text below `1.0` scale for editor surfaces.
- Keep editor/debug lists bounded and readable. Use compact formatting, scrolling, windowing, pagination, or virtualization for unbounded lists.
- Keep smooth scrolling modeled as target pixel/float offsets, animated visible offsets, row-height-independent wheel distances, and clipping. Do not fake smooth scrolling with row-snapped windows, instant jumps, or unclipped overflow.
- When editor chrome is visible, wheel input should go to the hovered scrollable editor surface; scene-authored scroll views inside the game viewport must still receive wheel input unless editor chrome intentionally consumes it.

## Rendering and Assets

- Rendering uses `wgpu-native`; keep backend details behind engine-owned render boundaries.
- Offscreen rendering is the preferred automation surface for visual verification.
- Renderable meshes, UI primitives, active camera fallback, lights, shadows, batching, and editor render data should resolve from ECS world data where possible.
- Do not add renderer-only UI geometry or per-example hacks for behavior represented by shared `machina.ui.*` components.
- When changing the built-in UI bitmap font, update `third_party/spleen/`, regenerate `src/ui_font.zig` with `tools/generate-ui-font.py`, and update `NOTICE` and FDRs if the source face changes.
- Keep `NOTICE` current when adding, removing, replacing, or redistributing third-party code, assets, generated data, fonts, tools, native libraries, or fetched binary dependencies.

## Documentation and Decision Records

- Use the `todo-list` skill when creating, updating, or auditing task tracking.
- Keep `docs/TODO.md` synchronized with legitimate follow-up work discovered during planning, implementation, review, and verification.
- Read `docs/TODO.md` before choosing the next slice or making roadmap claims, and remove or rewrite completed items as work lands.
- Keep `docs/TODO.md` as a concise task index; put detailed rationale in ADRs, FDRs, issues, or docs and link out when useful.
- Update ADRs when changing architecture, backend choices, runtime model, or persistent implementation strategy.
- Update FDRs when changing feature behavior, command behavior, scene schema, validation semantics, diagnostics, examples that define supported behavior, or user-visible workflows.
- Update `docs/fdr/INDEX.md` and `docs/adr/INDEX.md` when adding records.
- Keep `machina check --format=json` useful for editor and agent workflows. Add fields compatibly; do not remove or rename existing successful-output metadata without an explicit compatibility decision.
- Runtime script host API failures should report the active system plus relevant component/field context. Avoid generic bridge errors when Zig can identify the denied access or failed mutation.

## Verification Rules

- Use `machina test` for automated gameplay and UI input replay fixture coverage.
- Use `machina step` for narrow deterministic script/ECS debugging and runtime diagnostic checks.
- Use `machina bench` for headless performance smoke coverage; keep renderable and render-batch counts useful enough to catch batching regressions.
- Use `mise build` for normal optimized builds.
- Use `mise build-debug` or `zig build test` when Debug safety checks matter.
- Do not run `zig build test` and `mise test` concurrently. The current tests use shared fixed temp project paths, so parallel invocations can collide and produce misleading filesystem failures.
- For rendering, shader, scene-driven render data, or visual expectation changes, use `.agents/skills/machina-render-verification`.
- For script diagnostics, Luau bridge error reporting, `machina check` output, script reload/runtime failure handling, or editor/agent diagnostic surfaces, use `.agents/skills/machina-script-diagnostics`.
- For editor layout changes, prefer engine-generated offscreen artifacts with `machina render --editor`; use `--select <entity-id>` when selected-entity inspector state matters.
- When a render example depends on startup-spawned content, run startup before offscreen verification and keep the example covered by `mise test`.
- For `machina run` window-loop, surface, or live-reload changes, run a bounded headful smoke test such as `mise machina run examples/minimal --frames 2`.
- For editor input bugs, add deterministic frame-replay coverage in Zig tests before relying on manual headful checks.
- When investigating performance, compare optimized and Debug builds, and separate headless update cost from headful render/presentation cost before changing engine architecture.

## Project Map

- Project task index: `docs/TODO.md`
- CLI entry point and command routing: `src/main.zig`
- Project and scene loading/validation: `src/root.zig`
- ECS runtime, registry, and scheduling: `src/runtime.zig`
- Luau declaration boundary and script ECS registration: `src/script.zig`
- WebGPU renderer and SDL-backed headful window path: `src/render.zig`
- Shared retained UI layout and input resolution: `src/ui_layout.zig`
- Offscreen BMP verification: `src/render_verify.zig`
- WGSL shaders embedded into the binary: `src/shaders/`
- Canonical smoke-test project: `examples/minimal/`
- Retained UI primitive gallery: `examples/ui_gallery/`
- Project-local native Zig module example: `examples/native_motion/`
- Automated game-shaped fixtures: `tests/projects/`

## Further Reading

- Outstanding work: `docs/TODO.md`
- Architecture decisions: `docs/adr/INDEX.md`
- Feature behavior: `docs/fdr/INDEX.md`
- UI/editor model: `docs/adr/ADR-007-engine-hosted-ui-for-editor-tooling.md`, `docs/adr/ADR-020-transient-ecs-input-resources.md`, `docs/fdr/FDR-005-engine-ui-primitives.md`, `docs/fdr/FDR-018-editor-entity-inspector.md`
- Runtime/ECS model: `docs/adr/ADR-008-component-system-runtime-model.md`, `docs/adr/ADR-013-shared-ecs-for-engine-internal-worlds.md`, `docs/adr/ADR-016-generation-aware-entity-handles.md`, `docs/adr/ADR-017-deferred-script-structural-commands.md`, `docs/fdr/FDR-009-entity-component-runtime.md`
- Scripting/native model: `docs/adr/ADR-006-embeddable-scripting-language-for-game-logic.md`, `docs/adr/ADR-012-luau-type-functions-for-ecs-editor-types.md`, `docs/adr/ADR-018-engine-linked-native-ecs-systems.md`, `docs/adr/ADR-019-project-local-native-zig-modules.md`, `docs/fdr/FDR-011-script-ecs-registration.md`, `docs/fdr/FDR-012-hybrid-luau-zig-systems.md`, `docs/fdr/FDR-013-script-diagnostics.md`
- Rendering model: `docs/adr/ADR-004-webgpu-graphics-through-wgpu-native.md`, `docs/fdr/FDR-014-scene-driven-camera-and-lighting.md`, `docs/fdr/FDR-015-built-in-geometry-and-materials.md`, `docs/fdr/FDR-016-render-batching.md`, `docs/fdr/FDR-017-shadow-components.md`

## Working Rules

- Use Conventional Commits for commit messages and PR titles.
- PR bodies should contain a descriptive list of changes.
- Write PR bodies to a Markdown file and pass it with `gh pr create --body-file` or `gh pr edit --body-file`. Do not inline multiline PR bodies with escaped `\n`; verify the saved body with `gh pr view --json body`.
- Prefer small vertical slices that leave `main` working.
- Use `examples/minimal/` as the smoke-test fixture and update it when the supported scene schema changes.
- Keep `examples/ui_gallery/` current when adding or materially changing UI primitives.
- New text-authored runtime resources must be registered with live reload or explicitly documented as not reloadable yet.
