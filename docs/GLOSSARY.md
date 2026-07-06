# Scrapbot Glossary

This glossary defines recurring Scrapbot terms in the project's context. It is a naming reference, not a tutorial or API reference; follow the linked ADRs, FDRs, and source files for full behavior.

## Project Model

**Scrapbot** - A text-first game engine migrating from Zig to Odin, with project-local Luau and optional native modules for gameplay behavior. See [ADR-001](adr/ADR-001-agent-native-text-first-project-model.md), [ADR-023](adr/ADR-023-odin-as-engine-implementation-language.md), and [ADR-006](adr/ADR-006-embeddable-scripting-language-for-game-logic.md).

**Text-first project model** - The rule that engine-authored project state lives in inspectable, reviewable text files while binary files are limited to source assets, generated artifacts, vendored dependencies, and build outputs. See [ADR-001](adr/ADR-001-agent-native-text-first-project-model.md).

**Project directory runtime** - The command model where Scrapbot commands discover and operate on a project from the current directory or an explicit project path. See [FDR-001](fdr/FDR-001-project-directory-runtime.md).

**Project metadata** - The `project.toml` file that declares project-level settings such as `default_scene`, `scripts`, and an optional `native` module path. See [FDR-001](fdr/FDR-001-project-directory-runtime.md) and [ADR-019](adr/ADR-019-project-local-native-zig-modules.md).

**Scene** - A text-authored TOML file that declares entities and component tables, starting from the default `scenes/main.scene.toml` convention. See [FDR-002](fdr/FDR-002-text-based-scene-authoring.md).

**Default scene** - The project-relative scene path selected by `default_scene` in project metadata and loaded by normal validation, stepping, rendering, and run commands. See [FDR-001](fdr/FDR-001-project-directory-runtime.md) and [FDR-002](fdr/FDR-002-text-based-scene-authoring.md).

**Scene entity id** - A stable text id on a scene entity, used for diagnostics, component lookup, editor selection, and future reload patching. See [FDR-002](fdr/FDR-002-text-based-scene-authoring.md) and [FDR-010](fdr/FDR-010-live-reload-for-scenes-and-scripts.md).

**Runtime resource** - Engine-owned state that is created during execution rather than authored in scene files, such as `scrapbot.input.*` and `scrapbot.ui.command_event`. See [ADR-020](adr/ADR-020-transient-ecs-input-resources.md) and [FDR-005](fdr/FDR-005-engine-ui-primitives.md).

**Asset cache** - Planned generated runtime-ready artifacts derived from authoritative source assets, kept outside the source project model. See [FDR-006](fdr/FDR-006-asset-import-and-cache.md).

## ECS Runtime

**ECS (Entity Component System)** - Scrapbot's shared runtime model for game state: entities carry components, and systems operate over declared component access. See [ADR-008](adr/ADR-008-component-system-runtime-model.md) and [FDR-009](fdr/FDR-009-entity-component-runtime.md).

**World** - A runtime container for entity identity, component storage, component validation, queries, mutation APIs, and system schedules. See [ADR-008](adr/ADR-008-component-system-runtime-model.md) and `src/runtime/main.zig`.

**Game world** - The ECS world that owns the loaded project's authoritative runtime scene and gameplay state. See [FDR-009](fdr/FDR-009-entity-component-runtime.md).

**Engine-internal world** - A subsystem-owned ECS world, such as the renderer's render world, that uses the shared runtime ECS implementation instead of a parallel storage model. See [ADR-013](adr/ADR-013-shared-ecs-for-engine-internal-worlds.md).

**Component registry** - The runtime catalog of engine, script, and native component schemas used to validate scene data, script declarations, native declarations, queries, and field access. See [FDR-009](fdr/FDR-009-entity-component-runtime.md) and `src/runtime/main.zig`.

**Component schema** - A component's declared fields and types, authored by the engine, Luau scripts, or native modules. See [FDR-011](fdr/FDR-011-script-ecs-registration.md).

**Component table** - Runtime storage for one component type, with dense entity rows, a sparse entity-to-row lookup, and typed field columns. See [ADR-008](adr/ADR-008-component-system-runtime-model.md).

**SoA (Structure of Arrays)** - The component storage layout where each component field is stored in its own typed column rather than one struct per entity. See [ADR-008](adr/ADR-008-component-system-runtime-model.md).

**Component id** - The stable string identifier for an ECS component type, such as `scrapbot.transform`, `spin`, or `com.example.stamina`. See [ADR-010](adr/ADR-010-local-and-qualified-ids-for-script-ecs-extensions.md).

**Engine-owned id** - A reserved `scrapbot.*` component or system id owned by the engine. See [ADR-010](adr/ADR-010-local-and-qualified-ids-for-script-ecs-extensions.md).

**Project-local id** - A single lowercase ASCII identifier segment, such as `spin`, valid only inside one project. See [ADR-010](adr/ADR-010-local-and-qualified-ids-for-script-ecs-extensions.md).

**Qualified id** - A dotted id with two or more lowercase ASCII segments, used for package or library types and required for reusable packages. See [ADR-010](adr/ADR-010-local-and-qualified-ids-for-script-ecs-extensions.md).

**Entity handle** - The runtime reference to an entity. Handles returned by public creation, lookup, query, proxy, and bulk-view paths carry generation data. See [ADR-016](adr/ADR-016-generation-aware-entity-handles.md).

**Generation-aware handle** - An entity handle that pairs a dense entity index with a generation so stale handles fail instead of aliasing another live entity after removal or compaction. See [ADR-016](adr/ADR-016-generation-aware-entity-handles.md).

**Structural mutation** - An entity or component membership change, such as spawning, despawning, adding a component, or removing a component. See [ADR-017](adr/ADR-017-deferred-script-structural-commands.md) and [FDR-009](fdr/FDR-009-entity-component-runtime.md).

**Deferred structural command** - A buffered script or native add/remove/despawn command that flushes only after the active system returns successfully. See [ADR-017](adr/ADR-017-deferred-script-structural-commands.md).

**Declared access** - A system's explicit read and write component declarations, used for validation, scheduling, mutation checks, diagnostics, and future parallel execution. See [FDR-009](fdr/FDR-009-entity-component-runtime.md).

**Phase** - A named schedule stage such as `startup` or `update`; systems declare their phase before the scheduler batches them. See [FDR-011](fdr/FDR-011-script-ecs-registration.md).

**Schedule batch** - A group of systems within a phase that can run without read/write conflicts or ordering violations. See [FDR-011](fdr/FDR-011-script-ecs-registration.md).

**System-first API** - The scripting model where scripts declare systems, component access, and schedules while the native engine owns storage, validation, and scheduling. See [ADR-006](adr/ADR-006-embeddable-scripting-language-for-game-logic.md).

## Scripting and Native Extensions

**Luau** - Scrapbot's embedded scripting language for project-local gameplay logic, declaration loading, and runtime systems. See [ADR-006](adr/ADR-006-embeddable-scripting-language-for-game-logic.md).

**Script ECS registration** - The process where Luau scripts define components, systems, access sets, phases, queries, and ordering through engine-provided `ecs.*` APIs. See [FDR-011](fdr/FDR-011-script-ecs-registration.md).

**World facade** - The narrow script-facing or native-facing host API for querying and mutating ECS state without exposing raw `runtime.World` internals. See [FDR-011](fdr/FDR-011-script-ecs-registration.md) and [ADR-019](adr/ADR-019-project-local-native-zig-modules.md).

**Component proxy** - A Luau-facing wrapper yielded by typed query iteration that exposes component fields while the host validates access and resolved row safety. See [ADR-014](adr/ADR-014-resolved-query-plans-for-luau-ecs-iteration.md).

**Query object** - A reusable typed Luau object created with `ecs.query(...)` for iterating entities that have a fixed component set. See [FDR-011](fdr/FDR-011-script-ecs-registration.md).

**Resolved query plan** - Cached internal query preparation that maps component ids to tables and rows so `Query:iter(world)` avoids repeated lookup work. See [ADR-014](adr/ADR-014-resolved-query-plans-for-luau-ecs-iteration.md).

**Query view** - The explicit `Query:view(world)` hot-loop API that snapshots matched rows and bulk-transfers `f32` or `vec3` fields through Luau buffers. See [ADR-015](adr/ADR-015-buffer-backed-luau-query-views.md).

**`ecs.fields(...)`** - The preferred Luau component field-schema declaration form, used by runtime validation and editor payload type inference. See [ADR-012](adr/ADR-012-luau-type-functions-for-ecs-editor-types.md).

**Project-local native module** - A project-owned native source file loaded through Scrapbot's native host boundary during development. The Zig engine currently builds and reloads `native = "native/game.zig"` modules; the Odin migration can statically validate component/system declarations from `native = "native/game.odin"` while Odin native execution remains pending. See [ADR-019](adr/ADR-019-project-local-native-zig-modules.md) and [ADR-023](adr/ADR-023-odin-as-engine-implementation-language.md).

**`scrapbot_native`** - The current generated Zig API module imported by project-local native code to register components/systems and use access-checked host callbacks. It is migration scaffolding until an Odin native-module API replaces it. See [ADR-019](adr/ADR-019-project-local-native-zig-modules.md) and [ADR-023](adr/ADR-023-odin-as-engine-implementation-language.md).

**Native extension** - An engine-linked Zig registration surface for native ECS components and systems, used before and alongside project-local native modules. See [ADR-018](adr/ADR-018-engine-linked-native-ecs-systems.md).

**Native host facade** - The access-checked native callback API that exposes queries, typed field reads/writes, profiling, diagnostics, and deferred structural commands without exposing engine internals. See [FDR-012](fdr/FDR-012-hybrid-luau-zig-systems.md).

## Live Reload and Diagnostics

**Live reload** - Runtime detection, validation, and staged replacement of changed scene, script, and project-local native files without restarting the engine. See [ADR-009](adr/ADR-009-live-reload-as-a-core-runtime-capability.md) and [FDR-010](fdr/FDR-010-live-reload-for-scenes-and-scripts.md).

**Last-known-good state** - The active valid runtime state preserved when a reload, script validation, native build, or registration step fails. See [ADR-009](adr/ADR-009-live-reload-as-a-core-runtime-capability.md) and [FDR-013](fdr/FDR-013-script-diagnostics.md).

**Scene generation** - A loaded project/scene generation for which startup systems run once; project and scene reloads create a fresh generation, while script-only and native-only reloads do not replay startup against the already-live world. See [FDR-011](fdr/FDR-011-script-ecs-registration.md) and [FDR-010](fdr/FDR-010-live-reload-for-scenes-and-scripts.md).

**Structured diagnostic** - A machine-consumable failure record with stage, path, optional system id, optional source position, and message. See [ADR-011](adr/ADR-011-structured-script-diagnostics.md) and [FDR-013](fdr/FDR-013-script-diagnostics.md).

**Diagnostic stage** - The lifecycle point where a script or native failure occurred, such as `load`, `native_build`, `native_load`, `native_registration`, `registration`, `schedule`, or `runtime`. See [FDR-013](fdr/FDR-013-script-diagnostics.md).

**Headless command** - A command such as `scrapbot check`, `scrapbot step`, `scrapbot bench`, `scrapbot test`, `scrapbot render-test`, or `scrapbot visual-test` that validates, executes, measures, or verifies a project without opening an interactive window. See [FDR-003](fdr/FDR-003-headless-validation-and-test-runner.md).

**Test project** - A complete text-authored Scrapbot project under `tests/projects/` used for automated behavior fixtures instead of as a user-facing example. See [FDR-003](fdr/FDR-003-headless-validation-and-test-runner.md).

**`test.scrapbot.toml`** - A test manifest that declares deterministic frame counts, input replay frames, and ECS field assertions for `scrapbot test`. See [FDR-003](fdr/FDR-003-headless-validation-and-test-runner.md).

## UI, Input, and Editor

**Engine-hosted UI** - Scrapbot UI built from engine-owned retained ECS primitives instead of a separate external editor application stack. See [ADR-007](adr/ADR-007-engine-hosted-ui-for-editor-tooling.md) and [FDR-005](fdr/FDR-005-engine-ui-primitives.md).

**Retained UI** - UI represented as persistent ECS component data, such as canvas, rect, text, command, scroll view, and layout components. See [FDR-005](fdr/FDR-005-engine-ui-primitives.md).

**UI canvas** - A `scrapbot.ui.canvas` component that defines a design size and scaling mode for scene-authored UI. See [FDR-005](fdr/FDR-005-engine-ui-primitives.md).

**UI command** - A `scrapbot.ui.command` authored on a button entity to identify the action emitted when the button is released successfully. See [FDR-005](fdr/FDR-005-engine-ui-primitives.md).

**UI command event** - A transient `scrapbot.ui.command_event` emitted for one frame after routed command activation; it is runtime-only and not scene-authored data. See [FDR-005](fdr/FDR-005-engine-ui-primitives.md).

**Hit area** - A non-rendering `scrapbot.ui.hit_area` rectangle used when a control's interaction target should differ from its visual rectangle. See [FDR-005](fdr/FDR-005-engine-ui-primitives.md).

**Layout item** - A `scrapbot.ui.layout.item` component that attaches a UI entity to a stable parent entity id with order, sizing, alignment, and margin metadata. See [FDR-005](fdr/FDR-005-engine-ui-primitives.md).

**Scroll view** - A retained `scrapbot.ui.scroll_view` viewport with content offset and clipping behavior for scene or editor UI. See [FDR-005](fdr/FDR-005-engine-ui-primitives.md).

**`ui_layout.routePointer`** - The shared retained UI routing entry point that composes command hits, scroll routing, and pointer capture intent. See [FDR-005](fdr/FDR-005-engine-ui-primitives.md) and `src/ui/layout.zig`.

**Transient input resources** - Current-frame input stored as engine-owned ECS resources such as `scrapbot.input.pointer`, `scrapbot.input.keyboard`, and `scrapbot.input.frame`. See [ADR-020](adr/ADR-020-transient-ecs-input-resources.md).

**Editor shell** - The engine-owned editor/debug overlay with chrome regions, playback controls, performance data, selected-entity inspection, and viewport routing. See [FDR-005](fdr/FDR-005-engine-ui-primitives.md) and [FDR-018](fdr/FDR-018-editor-entity-inspector.md).

**Game viewport** - The editor shell region where the running project scene and scene-authored UI render while editor chrome is visible. See [FDR-005](fdr/FDR-005-engine-ui-primitives.md) and [FDR-018](fdr/FDR-018-editor-entity-inspector.md).

**Selected-entity inspector** - The right-sidebar editor surface that displays the selected entity id/name and current ECS component fields. See [FDR-018](fdr/FDR-018-editor-entity-inspector.md).

**Translate gizmo** - Engine-generated render data for moving the selected renderable entity along X, Y, or Z without authoring editor objects into the project scene. See [FDR-018](fdr/FDR-018-editor-entity-inspector.md).

**Fly camera** - A headful-run render-only camera override controlled by right mouse plus movement keys for inspecting a scene without mutating scene camera components. See [FDR-008](fdr/FDR-008-headful-demo-window.md).

## Rendering

**`wgpu-native`** - The native WebGPU implementation used by Scrapbot's renderer behind engine-owned rendering boundaries. See [ADR-004](adr/ADR-004-webgpu-graphics-through-wgpu-native.md) and [ADR-005](adr/ADR-005-narrow-backend-boundaries-for-external-native-libraries.md).

**Headful run** - Interactive execution through `scrapbot run`, which opens an SDL-backed window, presents frames, and can show editor chrome. Bounded `--hidden --frames N` runs exercise the same window/surface path without showing a normal visible window. See [FDR-008](fdr/FDR-008-headful-demo-window.md).

**Offscreen rendering** - Rendering a project to an image artifact without opening a platform window, used by `scrapbot render` and `scrapbot render-test`. See [FDR-007](fdr/FDR-007-offscreen-demo-rendering.md).

**Render world** - Historical term for the former renderer-owned ECS world that mirrored scene render data. Scrapbot now resolves render-facing ECS data from the authoritative scene world and keeps only renderer side resources outside it. See [ADR-022](adr/ADR-022-single-world-render-data-flow.md) and [FDR-007](fdr/FDR-007-offscreen-demo-rendering.md).

**Renderer singleton** - The scene-authored `scrapbot.renderer` component that configures HDR color, tone mapping, antialiasing, bloom, chromatic aberration, and vignette for the game view. See [FDR-020](fdr/FDR-020-postprocess-and-hdr-render-settings.md).

**Renderable** - An entity with the ECS data needed to draw visible geometry, currently centered on `scrapbot.transform`, `scrapbot.geometry.primitive`, and `scrapbot.material.surface`. See [FDR-015](fdr/FDR-015-built-in-geometry-and-materials.md).

**Built-in primitive** - Engine-generated geometry selected through `scrapbot.geometry.primitive`, such as box, plane, sphere, UV sphere, or ico sphere. See [FDR-015](fdr/FDR-015-built-in-geometry-and-materials.md).

**Surface material** - The first material component, `scrapbot.material.surface`, which currently carries base color for scene-driven rendering. See [FDR-015](fdr/FDR-015-built-in-geometry-and-materials.md).

**Legacy cube** - The compatibility shortcut `scrapbot.render.cube`, still accepted but superseded for new scene-authored renderables by geometry plus material components. See [FDR-015](fdr/FDR-015-built-in-geometry-and-materials.md).

**Scene-driven camera and lighting** - Camera and directional light rendering state authored as ECS components instead of renderer-only constants. See [FDR-014](fdr/FDR-014-scene-driven-camera-and-lighting.md).

**Shadow marker** - A marker component such as `scrapbot.shadow.caster` or `scrapbot.shadow.receiver` that opts a renderable into shadow casting or receiving. See [FDR-017](fdr/FDR-017-shadow-components.md).

**Render batch** - A renderer-planned group of compatible renderables drawn as one instanced batch while preserving per-entity transform and base color. See [FDR-016](fdr/FDR-016-render-batching.md).

**Draw-command entity** - An internal render-world entity queued by render preparation to represent a batch or UI draw operation before GPU submission. See [ADR-013](adr/ADR-013-shared-ecs-for-engine-internal-worlds.md) and [FDR-016](fdr/FDR-016-render-batching.md).

**Render verification** - The offscreen PNG, pixel-analysis, and golden-image comparison workflow used to catch rendering regressions in automation. See [FDR-003](fdr/FDR-003-headless-validation-and-test-runner.md), [FDR-007](fdr/FDR-007-offscreen-demo-rendering.md), and `.agents/skills/scrapbot-render-verification/SKILL.md`.

## Records

**ADR (Architecture Decision Record)** - A durable record for architecture, backend, runtime, and persistent implementation decisions; the index lives at [docs/adr/INDEX.md](adr/INDEX.md).

**FDR (Feature Decision Record)** - A durable record for feature behavior, user-visible workflows, validation semantics, diagnostics, and examples that define supported behavior; the index lives at [docs/fdr/INDEX.md](fdr/INDEX.md).
