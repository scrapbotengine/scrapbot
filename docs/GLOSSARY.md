# Glossary

## Records

**ADR (Architecture Decision Record)** - A document in `docs/adr/` that captures a cross-cutting architecture decision and its consequences.

**FDR (Feature Decision Record)** - A document in `docs/fdr/` that describes one feature's behavior, design decisions, related ADRs, and open questions.

## Runtime

**ECS (Entity Component System)** - Scrapbot's runtime world model, where entities are identifiers, components hold data, and systems operate over matching component sets.

**Entity** - One object in a Scrapbot world. Every entity has a stable UUID for project-wide identity plus an index-and-generation runtime handle so stale in-memory references can be rejected.

**Entity UUID** - A non-zero RFC UUID that identifies an entity independently from its editable name, scene order, or runtime storage slot. Scene UUIDs are serialized; each runtime-spawned lifetime receives a new UUID.

**Component** - A typed piece of data attached to an entity, such as a transform, camera, geometry reference, or material reference. Single-token names identify project components; dotted names identify engine or library components.

**Render resource** - Shared geometry or material data owned outside the ECS and referenced by generational handles from entity components. See [ADR-010](adr/ADR-010-keep-render-resources-outside-the-ecs.md).

**Render reconciliation** - The change-driven engine step that adds, updates, or removes internal render-instance components based on an entity's transform and valid geometry/material references. Structural dirty entities are synchronized into a dense active-renderable set instead of rescanning all entity membership every frame.

**Component ID** - A runtime-local identifier assigned by the component registry. Luau component handles include both name and ID; project files remain name-based.

**Component registry** - The runtime registry of known component names, IDs, owners, and simple field schemas. Scrapbot registers built-in `scrapbot.*` components plus project components declared from Luau and library components declared from Luau or native extensions, then uses that metadata to validate scenes and generate project Luau type aliases.

**Component schema marker** - A typed Luau value such as `scrapbot.vec3` used in `scrapbot.component` and `scrapbot.library_component` schema tables to describe custom component fields.

**Component storage group** - The ECS world storage for all schema-backed custom component instances of one component type.

**Library component** - A dotted, non-`scrapbot` component name registered from Luau with `scrapbot.library_component` or from a native extension, representing data owned by an engine library rather than by a single project.

**Query object** - A reusable Luau value created with `scrapbot.query(...)` that represents one component set. Query construction is order-insensitive, and repeated calls for the same component set return the same object. Query-driven systems can write back supported payloads when they declare matching write access.

**Query view** - A materialized view over one component or query object that yields alive entity/component results for scripting and future native systems.

**Joined query** - A query that matches only entities that have every requested component, such as `scrapbot.transform` and a project-defined `autorotate` component. Luau uses `scrapbot.query(a, b)` to create joined query objects.

**System** - Runtime logic that reads or writes components for matching entities. Systems can currently be registered from Luau scripts or native extensions.

**Scheduled system** - A system with declared component reads and writes. Scrapbot batches Luau and native systems together by access conflicts before executing them serially.

**Deferred command buffer** - A per-runtime queue of structural ECS mutations requested while systems are running. Scrapbot currently applies queued entity and component lifecycle commands after the scheduled frame step.

**SoA (Structure of Arrays)** - A data layout used for hot component storage, taking advantage of Odin's `#soa` support.

**World** - The in-memory ECS state built from a project scene and used by runtime systems and rendering.

## Projects

**Project directory** - The directory where a user runs Scrapbot. It contains `project.toml`, scene files, scripts, assets, and optional native extension code.

**`project.toml`** - The project manifest in the root of a Scrapbot project directory. It names the project, selects the default scene, and can declare native extension targets.

**Scene file** - A TOML file that describes entities, built-in components, and simple project-defined component data. The generated default scene is `scenes/main.scene.toml`.

**Text-first project** - A Scrapbot project whose primary source of truth is ordinary text files that can be edited by humans, tools, and agents.

## Rendering

**Renderer backend** - A renderer implementation behind Scrapbot's rendering boundary, such as the null renderer or the `wgpu-native` backend.

**Null renderer** - The placeholder renderer that accepts world-derived frame data without opening a window or using the GPU.

**SDL3** - The first platform window layer for Scrapbot's headful runtime smoke tests and renderer surface creation.

**Render packet** - Backend-neutral frame data extracted from the ECS world before submission to a renderer backend. It contains render instances, the active camera, accumulated ambient light, and bounded directional and point-light arrays.

**WebGPU** - The modern graphics API model Scrapbot is targeting for its first real renderer.

**`wgpu-native`** - The first real renderer backend, using the native WebGPU implementation exposed through Odin's vendor bindings.

## Scripting And Editing

**Luau** - Scrapbot's embedded scripting language for project-local code, currently exposed through `scripts/main.luau` and a small `scrapbot` API for logging, systems, component schemas, custom component queries, and transform rotation helpers.

**Generated Luau types** - Project-local type definitions in `types/scrapbot.d.luau`. `scrapbot check` refreshes them from the component registry so editors can see engine, project, and library component payload aliases, including readonly aliases for query snapshot payloads.

**Luau analyzer** - The external `luau-analyze` static checker. `scrapbot check` runs it when available to catch script type and syntax errors against generated Scrapbot types.

**Native extension** - Project-local compiled code declared in `project.toml`, built into versioned dynamic libraries under `build/extensions`, and loaded through Scrapbot's C ABI. The extension API lets native libraries register dotted library component schemas, scheduled native systems, and deferred lifecycle commands, including spawning simple renderables, before Luau runs.

**Odin extension helper** - The `scrapbot:extension` package that wraps Scrapbot's raw native extension ABI with Odin-friendly component and field descriptors, registration accumulation, access declaration, query, transform, vec3 field, and lifecycle command helpers.

**Hot reload** - Runtime behavior where changed project files are reloaded without restarting the engine. Scrapbot currently supports periodic reload checks for `project.toml`, the default scene TOML, `scripts/main.luau`, native libraries in `build/extensions`, and declared native extension source directories.

**Editor GUI** - The in-engine live editor toggled from a running project. It uses transient editor-origin entities and the same public ECS UI components available to projects.
