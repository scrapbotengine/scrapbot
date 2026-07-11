# Glossary

## Records

**ADR (Architecture Decision Record)** - A document in `docs/adr/` that captures a cross-cutting architecture decision and its consequences.

**FDR (Feature Decision Record)** - A document in `docs/fdr/` that describes one feature's behavior, design decisions, related ADRs, and open questions.

## Runtime

**ECS (Entity Component System)** - Scrapbot's runtime world model, where entities are identifiers, components hold data, and systems operate over matching component sets.

**Entity** - A generation-aware identifier for one object in a Scrapbot world. Luau receives entity handles with both index and generation so stale handles can be rejected.

**Component** - A typed piece of data attached to an entity, such as a transform, camera, or mesh reference. Single-token names like `autorotate` identify project-level components; dotted names like `scrapbot.transform` or `scrappyphysics.rigidbody` identify engine or library components.

**Component ID** - A runtime-local identifier assigned by the component registry. Luau component handles include both name and ID; project files remain name-based.

**Component registry** - The runtime registry of known component names, IDs, and simple field schemas. Scrapbot currently registers built-in `scrapbot.*` components and project components declared from Luau, and uses that metadata to generate project Luau type aliases.

**Component schema marker** - A typed Luau value such as `scrapbot.vec3` used in `scrapbot.component` schema tables to describe project component fields.

**Component storage group** - The ECS world storage for all project custom component instances of one component type.

**Query object** - A reusable Luau value created with `scrapbot.query(...)` that represents one component set. Query construction is order-insensitive, and repeated calls for the same component set return the same object. Query-driven systems can write back supported payloads when they declare matching write access.

**Query view** - A materialized view over one component or query object that yields alive entity/component results for scripting and future native systems.

**Joined query** - A query that matches only entities that have every requested component, such as `scrapbot.transform` and a project-defined `autorotate` component. Luau uses `scrapbot.query(a, b)` to create joined query objects.

**System** - Runtime logic that reads or writes components for matching entities.

**Scheduled system** - A system with declared component reads and writes. Scrapbot batches scheduled systems by access conflicts before executing them serially.

**Deferred command buffer** - A per-runtime queue of structural ECS mutations requested while systems are running. Scrapbot currently applies queued entity and component lifecycle commands after the scheduled frame step.

**SoA (Structure of Arrays)** - A data layout used for hot component storage, taking advantage of Odin's `#soa` support.

**World** - The in-memory ECS state built from a project scene and used by runtime systems and rendering.

## Projects

**Project directory** - The directory where a user runs Scrapbot. It contains `project.toml`, scene files, scripts, assets, and future native extension code.

**`project.toml`** - The project manifest in the root of a Scrapbot project directory.

**Scene file** - A TOML file that describes entities, built-in components, and simple project-defined component data. The generated default scene is `scenes/main.scene.toml`.

**Text-first project** - A Scrapbot project whose primary source of truth is ordinary text files that can be edited by humans, tools, and agents.

## Rendering

**Renderer backend** - A renderer implementation behind Scrapbot's rendering boundary, such as the null renderer or the `wgpu-native` backend.

**Null renderer** - The placeholder renderer that accepts world-derived frame data without opening a window or using the GPU.

**SDL3** - The first platform window layer for Scrapbot's headful runtime smoke tests and renderer surface creation.

**Render packet** - Planned name for backend-neutral render data extracted from the ECS world before submission to a renderer backend.

**WebGPU** - The modern graphics API model Scrapbot is targeting for its first real renderer.

**`wgpu-native`** - The first real renderer backend, using the native WebGPU implementation exposed through Odin's vendor bindings.

## Scripting And Editing

**Luau** - Scrapbot's embedded scripting language for project-local code, currently exposed through `scripts/main.luau` and a small `scrapbot` API for logging, systems, component schemas, custom component queries, and transform rotation helpers.

**Generated Luau types** - Project-local type definitions in `types/scrapbot.d.luau`. `scrapbot check` refreshes them from the component registry so editors can see engine and project component payload aliases, including readonly aliases for query snapshot payloads.

**Luau analyzer** - The external `luau-analyze` static checker. `scrapbot check` runs it when available to catch script type and syntax errors against generated Scrapbot types.

**Native extension** - Planned project-local compiled code that can register fast systems or engine integrations.

**Hot reload** - Runtime behavior where changed project files are reloaded without restarting the engine. Scrapbot currently supports periodic reload checks for the default scene TOML and `scripts/main.luau`.

**Editor GUI** - The planned in-engine editor interface toggled from a running project.
