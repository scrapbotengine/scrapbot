# Machina Agent Guide

Machina is an experimental, text-first game engine written in Zig. The engine is intended to be friendly to agentic workflows: project state should be inspectable, editable, and reviewable as source text wherever possible. Binary files are for assets and build outputs, not core scene or project data.

## Primary Goals & Features

- Built with Zig, with embedded Luau for scripting.
- Fully ECS based. The ECS is exposed to scripts. Users can author new component types and systems in Luau, and the engine will schedule them with native systems.
- Projects are split into scenes, which are mostly collections of entities, persisted as .toml files.
- Run your project by running `machina run` in your project directory.
- Press Ctrl+Tab in a headful run to toggle the engine UI overlay; `machina run --editor` shows it by default. The editor/debug overlay shows FPS plus live project and engine system timings.

Please add to this list as needed.

## Project Shape

- `src/main.zig` contains the CLI entry point and command routing.
- `src/root.zig` owns project and scene loading/validation.
- `src/script.zig` owns the current Luau-targeted script declaration boundary and script-driven ECS registration.
- `src/render.zig` owns the current WebGPU renderer and SDL-backed headful window path.
- `src/render_verify.zig` owns offscreen BMP verification.
- `src/shaders/` contains WGSL shaders embedded into the binary.
- `examples/minimal/` is the canonical smoke-test project.
- `examples/batching/` demonstrates automatic renderer batching with many Luau-animated text-authored entities sharing geometry and compatible render state.
- `examples/spawn_swarm/` demonstrates script-spawned swarm entities with startup-authored renderables and update-driven flock motion.
- `examples/spawning/` demonstrates script-driven entity spawning from an otherwise empty rendered scene.
- `examples/ui_overlay/` demonstrates the first engine-native UI primitives rendered from text-authored ECS component data.
- `examples/ui_gallery/` demonstrates the current retained UI primitive set: panels, text, button markers, command events, scroll views, vertical stacks, and script-mutated UI state.
- `examples/native_motion/` demonstrates a project-local Zig native module declared by the project manifest.
- `tests/projects/` contains game-shaped project fixtures used only by automated tests. Each runnable fixture has a `test.machina.toml` manifest with frames, timestep, and ECS field assertions.
- `docs/adr/` records architectural decisions.
- `docs/fdr/` records feature behavior and product/implementation decisions.
- `NOTICE` tracks third-party license notices for vendored code, data, generated source, and direct external binary dependencies.
- `tools/generate-ui-font.py` regenerates `src/ui_font.zig` from the checked-in Spleen BDF source.
- `third_party/wgpu_native_zig/` is a vendored and locally patched Zig binding for `wgpu-native`.
- `third_party/spleen/` contains the BSD-2 license and source BDF for the embedded Spleen-derived bitmap UI font data in `src/ui_font.zig`.

## Current Engine Model

Project data:

- Projects have a `project.machina.toml` file, a default scene path, and an optional `scripts = [...]` list.
- Projects may declare one project-local native Zig module with `native = "native/game.zig"`.
- Scenes are TOML-shaped text files with root `name` and `version` fields plus `[[entities]]` records.
- Entity data is authored as component tables such as `[entities.components."machina.transform"]`, `[entities.components."machina.geometry.primitive"]`, `[entities.components."machina.material.surface"]`, `[entities.components."machina.camera"]`, `[entities.components."machina.light.directional"]`, shadow markers like `[entities.components."machina.shadow.caster"]`, UI tables like `[entities.components."machina.ui.rect"]`, `[entities.components."machina.ui.text"]`, `[entities.components."machina.ui.command"]`, `[entities.components."machina.ui.scroll_view"]`, `[entities.components."machina.ui.vbox"]`, and `[entities.components."machina.ui.layout.item"]`, and project-local tables like `[entities.components.spin]`.
- Scene component ids and fields must validate against the engine/script component registry.

Rendering and UI:

- Rendering uses `wgpu-native`.
- Headful rendering currently uses SDL3 on macOS via Homebrew paths in `build.zig`.
- Offscreen rendering writes BMP artifacts and is the preferred automation surface.
- Renderable meshes, UI primitives, the active camera fallback, and the first directional light are resolved from ECS world data where available.
- New scene-authored renderables should use `machina.geometry.primitive` plus `machina.material.surface`.
- `machina.render.cube` is a legacy shortcut that renders as box geometry with inline color.
- Shadow behavior is authored with `machina.shadow.caster` and `machina.shadow.receiver` marker components.
- First-slice UI uses retained scene components: `machina.ui.canvas`, `machina.ui.rect`, `machina.ui.text`, `machina.ui.button`, `machina.ui.command`, `machina.ui.scroll_view`, `machina.ui.vbox`, and `machina.ui.layout.item`.
- UI renders as a screen-space overlay after 3D content, with fixed-pixel Spleen 16x32-derived built-in text.
- `machina.ui.scroll_view` provides a clipped screen-space viewport with `position`, `size`, and `content_offset`.
- `machina.ui.vbox` stacks direct children vertically from its local `position` with `spacing`.
- `machina.ui.layout.item` attaches an entity to a parent by stable entity id and `order`; do not use dense runtime entity indices as UI parent references.
- Headful input is translated into ECS frame input.
- Runtime input is represented as transient engine-owned ECS components on `machina.input.frame`: `machina.input.pointer`, `machina.input.keyboard`, and `machina.input.frame`.
- Input components are runtime resources, not scene-authored project data.
- Button markers derive ECS interaction state for hovered, held, and pressed visuals.
- Command buttons emit transient `machina.ui.command_event` components before update systems run.
- Headful runs can generate an engine-owned debug overlay in the render ECS world.
- The debug overlay is hidden by default, `machina run --editor` shows it on startup, Ctrl+Tab toggles it, and the current panel shows FPS plus project/native system timing rows and engine-internal render system timing rows.
- The debug overlay displays performance snapshots at a throttled human-readable cadence; keep measuring every frame, but do not make the visible table flicker every frame.
- The debug overlay performance table uses `machina.ui.scroll_view`, `machina.ui.vbox`, and `machina.ui.layout.item` for its clipped animated pixel-scroll viewport. It should not truncate the list to unreachable rows or regress to row-only, row-snapped, instant-jump scroll state, or private renderer-only list layout.
- The debug overlay performance table should favor readable full system ids and rolling average duration. Do not reintroduce phase prefixes or last-sample columns into the compact row format without a deliberate UI redesign.
- The editor overlay also owns playback controls, selected-entity inspection, click selection, and the first translate gizmo.
- Editor selection is generation-aware and should reject stale handles instead of silently selecting whatever now lives at the old dense index.
- The first click-selection path is CPU renderable-bounds picking; treat triangle-accurate picking, ID-buffer picking, acceleration structures, and selectable non-renderable entities as future design work.
- The first transform gizmo is world-space translate-only. Do not treat rotation, scale, snapping, local-space axes, hover styling, or undo support as already solved.
- The renderer owns an internal render world and render-phase schedule built with the same `runtime.World`, component registry, and scheduler implementation as game worlds.
- Matching geometry and shadow-state renderables are automatically grouped into instanced render batches below the scene authoring surface.
- Current base color is per-instance and should not split batches.
- GPU handles remain renderer-owned side resources until native/internal component storage has explicit lifecycle rules.

ECS runtime:

- The low-level runtime model is ECS-oriented: stable entity identity, structured components, systems over component queries, and a scripting API that exposes those concepts directly.
- `src/runtime.zig` owns the current `World`, component registry, and system schedule planning.
- Runtime-created entity handles are generation-aware. Preserve index+generation together across query, spawn, proxy, and bulk view bridge paths.
- Component storage is columnar per component type.
- Each component table has dense entity rows, a sparse entity-to-row index, and typed SoA field columns.
- Scene loading builds a world, scripts register ECS component/system types, and rendering queries renderable components from that world.
- Script systems can spawn/despawn entities and add/remove components through the ECS facade.
- Structural mutations must respect declared write access.
- Luau component add/remove/despawn calls are queued during the active system and flushed only after that system returns successfully; do not write examples/tests that expect same-callback queries to see queued structural changes.
- Native Zig components/systems go through `NativeExtension` and the same `runtime.ComponentRegistry`, `SystemRunner`, schedule, and profiling path as Luau systems; do not add a second ECS or scheduler for native hot paths.
- Project-local native Zig code imports `machina_native`, exports `machina_register(api)`, and is built into `.machina/native/` during development.
- Native system callbacks must use the access-checked host API in `machina_native`; do not expose or depend on raw `runtime.World` from project native modules.
- Native system callbacks can use `machina_native` typed field helpers for bool, i32, f32, vec3, and string fields.
- Native spawn/despawn/add/remove component commands use the same deferred mutation semantics as Luau: immediate spawns are rolled back on failure, queued structural changes flush only after the native system succeeds, and same-callback queries must not expect queued component changes to be visible.
- Native components register before Luau chunks load; native systems register after Luau components and before Luau systems so both languages can reference each other's component ids.
- Project system runtime profiling is collected at the scheduler dispatch boundary and exposed as rolling per-system snapshots for editor UI.
- Engine-internal render systems are also profiled at the render scheduler boundary and should appear in the same editor performance stream instead of a separate profiler model.

Luau scripting:

- Luau is the target scripting language.
- The current implementation parses a constrained Luau declaration surface for `ecs.component(...)`, `ecs.fields(...)`, `ecs.query(...)`, and `ecs.system(...)`.
- Machina stores real Luau system callbacks and runs them through the native scheduler.
- The preferred script API uses typed component handles and query objects.
- `ecs.component(...)` infers component payload editor types from `ecs.fields({ field = "vec3" })` using Luau type functions.
- `ecs.component<<T>>(...)` remains available for explicit payload schemas.
- `ecs.query(...)` creates a reusable typed query object.
- Systems attach that query object with `query = ...`.
- Runtime loops use `Query:iter(world)` to yield the entity plus requested component proxies.
- `Query:iter(world)` prepares component table and row positions internally for each iterator; keep the Luau API ergonomic and let the bridge/runtime optimize below it.
- Reusable query objects cache hidden prepared plans across invocations. If a change affects component table identity or table-index validity, update the world query-plan generation invalidation path.
- Large hot-loop systems may use `Query:view(world)` to capture the current query rows and bulk read/write `f32` or `vec3` fields through Luau buffers.
- Query views are frame-local transfer surfaces, not script-owned storage. Do not keep them beyond the active system invocation.
- Query view buffers use byte offsets: `f32` values are packed every 4 bytes, and `vec3` values are packed as xyz xyz every 12 bytes.
- `ecs.schema(...)` and `ecs.vec3()` are compatibility shims, not the default authoring style.
- Use `ecs.refs(...)` for explicit write access or extra manual access declarations.
- Startup systems run once for a loaded project/scene generation before update systems.
- Script-only reloads do not replay startup over existing live world state.
- Keep the public API system-first: scripts declare component access, and the native engine owns scheduling, validation, reload transactions, and future parallelization.
- Editor type checks require Luau's new solver; keep `mise luau-check` and VS Code settings aligned with that requirement.

Live reload:

- Live reload is a core runtime capability.
- `machina run` currently uses a `LiveProject` session that tracks project metadata and the active scene as loaded text sources.
- `LiveProject` also tracks project-listed script sources and optional project-local native source.
- Valid edits swap into the running renderer.
- Invalid edits keep the last known good project and scene active.
- Native reloads rebuild and reload the module, rebuild the ECS program, validate the scene, and preserve the last-known-good native program on build/load/registration failure.
- New architecture should preserve reloadable text data, stable ids, staged validation, and last-known-good behavior.

## Working Rules

- Use Conventional Commits for commit messages.
- Use Conventional Commits for PR titles. PR bodies should contain a descriptive list of the changes.
- Keep project and scene data text-based and diffable.
- Prefer small vertical slices that leave `main` working.
- Update ADRs when changing architecture or backend choices.
- Update FDRs when changing feature behavior, command behavior, scene schema, or validation semantics.
- Keep `NOTICE` current when adding, removing, replacing, or redistributing third-party code, assets, generated data, fonts, tools, native libraries, or fetched binary dependencies.
- When changing the built-in UI bitmap font, update `third_party/spleen/`, regenerate `src/ui_font.zig` with `tools/generate-ui-font.py`, and update `NOTICE`/FDRs if the source face changes.
- Route runtime state through the ECS world instead of introducing renderer-specific or script-owned side channels. Engine subsystems may own separate internal worlds and schedules, but they must use the shared runtime ECS implementation rather than creating a parallel ECS model.
- Keep input and UI interaction state ECS-shaped. SDL or platform event code should translate raw events into frame input; hover, press, focus, command routing, and editor state belong in ECS components/systems.
- Do not introduce UI-private or renderer-private input side channels. If a system needs keyboard or pointer state, route it through the shared `machina.input.*` components or explicitly document why that slice cannot yet do so.
- Treat `machina.ui.command_event` as runtime-only transient data. Do not author it in scene files; author `machina.ui.command` on button entities instead.
- Prefer reusable retained UI layout primitives over one-off renderer/editor layout shortcuts. Use `machina.ui.scroll_view` for clipped scrollable regions, `machina.ui.vbox` for vertical stacks, and `machina.ui.layout.item` with stable entity-id parents for child ordering.
- Keep editor/debug UI text legible at normal viewing sizes. Do not use built-in bitmap UI text below `1.0` scale for editor surfaces; prefer larger sizes for primary readouts and verify compact panels in a headful screenshot or smoke run.
- Keep editor/debug list rows bounded and readable. Use compact formatting, scrolling, windowing, or pagination for unbounded lists instead of drawing unreachable overflow or hidden `... more` rows.
- Keep smooth UI scrolling modeled as target pixel/float offsets, animated visible offsets, row-height-independent wheel distances, and clipping. Do not fake smooth scrolling with hidden whole-row windows, row-snapped targets, instant jumps, or by drawing unclipped overflow outside the viewport.
- For editor input bugs, add deterministic frame-replay coverage in Zig tests. Prefer replaying wheel/key/pointer frame sequences against editor state before relying on manual headful checks.
- Keep `examples/ui_gallery/` current when adding or materially changing UI primitives.
- Design editor surfaces for large worlds. Prefer selection-first, search, filtering, pagination, or virtualized lists over drawing every entity every frame.
- Keep editor state engine-owned and live-project authoritative. Playback controls should gate scheduled update systems without creating a renderer-only simulation state.
- Editor gizmos and editor chrome should be generated as engine-owned render/UI data and should not mutate project scene files or become selectable game entities.
- Script-defined ECS component and system types use explicit ids. Single lowercase ASCII identifier segments are project-local, qualified dotted ids are for packages/libraries, and `machina.*` is engine-owned. Machina does not infer a default project namespace.
- Author new Luau component schemas with `ecs.fields({ field = "type" })`. Do not use `ecs.schema(...)` or `ecs.vec3()` in new examples, features, or tests except for explicit compatibility coverage. If field-schema type inference regresses, fix the Luau type definitions/checker setup or runtime bridge support rather than reverting to marker-value inference.
- Keep script behavior system-first. Do not introduce arbitrary per-object script callbacks that bypass the component registry or native scheduler.
- In hot Luau system loops, cache component fields in locals before reusing them. Repeated `component.field` access crosses the host ECS bridge each time, and repeated vec3 field access allocates repeated Luau tables.
- For large measured Luau loops over many entities, prefer explicit `Query:view(world)` bulk `f32`/`vec3` buffers over per-entity proxy field access. Keep ordinary systems on `Query:iter(world)` unless the buffer offset code is justified.
- Measure Luau bridge hot-loop optimizations before keeping them. Query-local field-index caching has already been tried against `spawn_swarm` and regressed versus the simpler resolved-row path.
- Systems must declare phase plus read/write component access before they can participate in scheduling.
- Structural script mutations must happen inside scheduled systems through `world`/`entity` APIs. Adding or removing a component requires declared write access to that component; despawning an entity requires write access to every component currently attached to it.
- Keep `machina check --format=json` useful for editor and agent workflows. Successful JSON output should preserve project metadata and the validated schedule summary; add fields compatibly rather than removing or renaming existing ones.
- Runtime script host API failures should report the active system plus relevant component/field context. Avoid generic bridge errors when Zig can identify the denied access or failed mutation.
- Use `machina test` for automated gameplay fixture coverage. Use `machina step` for narrower deterministic script/ECS debugging and runtime diagnostic checks.
- Use `machina bench` for headless performance smoke coverage; keep renderable and render-batch counts useful enough to catch batching regressions.
- Keep `mise build` optimized for interactive CLI use. Use `mise build-debug` or `zig build test` when Debug safety checks are the point.
- When investigating performance, compare optimized and Debug builds, and separate headless update cost from headful render/presentation cost before changing engine architecture.
- When adding a text-authored runtime resource, register it with the live reload path or document why it is intentionally not reloadable yet.
- Preserve last-known-good behavior for live reload. Failed reloads should produce diagnostics without destroying the running project state.
- For long-lived interactive state, use an allocator that can free replaced resources; avoid arena-backed state for reloadable worlds and scenes.
- Do not commit generated `.machina/` project-native build caches.
- Keep project-native source modules small and explicit: registration entrypoint, component definitions, system definitions, and access-checked host API calls.
- Remember the static packaging direction: dynamic native loading is for the dev loop, while future `machina build` should be able to statically link the same native registration source for restricted targets.
- For rendering changes, use deterministic offscreen verification before relying on visible-window inspection.
- When a render example depends on startup-spawned content, run startup before offscreen verification and keep the example covered by `mise test`.
- For window-loop, surface, or live-reload changes in `machina run`, also run a bounded headful smoke test such as `mise machina run examples/minimal --frames 2`.
- Treat `examples/minimal/` as the smoke-test fixture; update it when the supported scene schema changes.
- Do not hide external backend APIs in scene, project, or scripting layers. Keep native dependency details behind engine-owned boundaries.

## Local Skills

- Use `.agents/skills/machina-render-verification` when changing rendering, shaders, scene-driven render data, or visual test expectations.
- Use `.agents/skills/machina-script-diagnostics` when changing script diagnostics, Luau bridge error reporting, `machina check` diagnostic output, script reload/runtime failure handling, or editor/agent-facing diagnostic surfaces.
- Feel free to add or change `machina-*` skills as needed.
