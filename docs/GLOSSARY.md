# Glossary

This is Scrapbot's canonical engineering vocabulary. Code, editor copy, ADRs, FDRs, architecture documentation, public documentation, and agent discussion should use these terms consistently. The [public glossary](../docs-website/src/content/docs/reference/glossary.md) is a smaller, user-facing projection of this document.

## Usage rules

- Use **authored entity** for an entity that belongs to authoring state. Use **scene-origin entity** only when the `.Scene` origin classification itself matters.
- Use **runtime entity** for simulation-created, disposable state. Do not use _temporary entity_ when runtime origin is the important distinction.
- Use **keep on Stop** for transferring an eligible Play Mode edit back into authoring state. This does not mean the change has been **saved** to disk.
- Use **derived** for engine-maintained state reconstructed from another authority. Derived is not a synonym for runtime: an authored entity may own derived components or generated child entities.
- Use **UUID** for stable project identity and **handle** for a generation-checked in-memory reference. Do not call an ECS slot or resource handle an ID when the distinction matters.

## Records

**ADR (Architecture Decision Record)** - A document in `docs/adr/` that captures a cross-cutting architecture decision and its consequences.

**FDR (Feature Decision Record)** - A document in `docs/fdr/` that describes one feature's behavior, design decisions, related ADRs, and open questions.

## Runtime

**ECS (Entity Component System)** - Scrapbot's runtime world model, where entities are identifiers, components hold data, and systems operate over matching component sets.

**Entity** - One object in a Scrapbot world. Every entity has a stable UUID for project-wide identity plus an index-and-generation runtime handle so stale in-memory references can be rejected.

**Entity UUID** - A non-zero RFC UUID that identifies an entity independently from its editable name, scene order, or runtime storage slot. Scene UUIDs are serialized; each runtime-spawned lifetime receives a new UUID.

**Entity handle** - An index-and-generation reference to one live ECS entity. Handles are efficient and reject stale lifetimes, but they are runtime-local and must not be serialized or used as persistent identity.

**Entity origin** - The live entity's lifecycle classification: `.Scene`, `.Runtime`, or `.Editor`. Origin controls authoring eligibility and editor visibility independently from UUID identity. Explicit promotion changes a runtime entity to scene origin; duplicating an authored entity creates new scene-origin entities. See [ADR-016](adr/ADR-016-track-entity-origin-in-the-runtime-world.md).

**Authored entity** - A scene-origin entity that belongs to the in-memory authored scene and is eligible to be saved. It may have come from a scene file, a stopped-mode editor action, explicit promotion, or an authored duplication staged during Play Mode.

**Runtime entity** - A runtime-origin entity created for the current simulation, normally by a system or script. Stop discards it unless it was explicitly promoted while authoring is stopped.

**Editor entity** - An editor-origin entity owned by engine tooling, such as editor chrome or the scene camera. It is excluded from project authoring and ordinary scene browsing.

**Component** - A typed piece of data attached to an entity, such as a transform, camera, geometry reference, or material reference. Single-token names identify project components; dotted names identify engine or library components.

**Render resource** - Shared geometry or material data owned outside the ECS and referenced by generational handles from entity components. See [ADR-010](adr/ADR-010-keep-render-resources-outside-the-ecs.md).

**Project resource** - Persistent, UUID-addressed reusable project data stored outside the ECS in `resources/**/*.resource.toml`. Materials, textures, models, environments, icon sets, generated geometry, and UI themes are project-resource kinds. See [ADR-030](adr/ADR-030-identify-project-resources-by-uuid-outside-the-ecs.md).

**Resource UUID** - The non-zero project-wide UUID serialized in a project resource file and used by scene references. It remains stable across resource renames and moves and resolves to a transient generational runtime handle.

**Runtime resource** - Registry-owned geometry, material, or font data created while a project is loaded. Authored project resources resolve into runtime resources; Luau or native code can also create transient name-addressed runtime resources that are not saved automatically.

**Resource handle** - A generation-checked runtime reference to registry-owned resource data. Project files store resource UUIDs; loading resolves them to handles, which may change after unload, reload, or replacement.

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

**Scheduled system** - A system with declared component reads and writes. Scrapbot batches systems by access conflicts, executes conflict-free native systems concurrently, and treats Luau or undeclared systems as serial barriers.

**Deferred command buffer** - A per-runtime queue of structural ECS mutations requested while systems are running. Scrapbot currently applies queued entity and component lifecycle commands after the scheduled frame step.

**SoA (Structure of Arrays)** - A data layout used for hot component storage, taking advantage of Odin's `#soa` support.

**World** - The in-memory ECS state built from a project scene and used by runtime systems and rendering.

**Derived state** - Engine-maintained state reconstructed from authoritative ECS components, resources, or editor state. It is invalidated and reconciled through explicit changes rather than authored or saved independently.

**Structural change** - A mutation to entity or component membership, hierarchy, authored order, or resource membership. It is distinct from changing fields inside an existing component or resource.

**Spatial hierarchy** - The acyclic graph formed by optional parent UUIDs on Transform components. Parent links use stable entity identity rather than names or runtime storage slots.

**Local transform** - An entity's authored position, rotation, and scale relative to its Transform parent. A root entity's local transform is also its world transform.

**World transform** - The derived position, rotation, and scale produced by composing an entity's local Transform with its ancestor chain. Rendering and editor spatial tools consume this value; it is not separately authored.

**Transform origin** - The position represented by an entity's Transform. It is the canonical spatial point inherited by children and remains distinct from an editor manipulation pivot or a rendered-bounds center.

**Manipulation pivot** - The transient world-space point around which an editor transform gesture operates. Scrapbot can use the selected entity's Transform origin or derived rendered-bounds center without serializing another Transform field.

**Rendered-bounds center** - The center of the combined world-space Geometry bounds for a selected entity, its Transform descendants, and its generated Model children. Editor framing and Center-pivot manipulation derive this value on demand.

## Projects

**Project directory** - The directory where a user runs Scrapbot. It contains `project.toml`, scene files, standalone resources, scripts, assets, and optional native extension code.

**`project.toml`** - The project manifest in the root of a Scrapbot project directory. It names the project, selects the default scene, and can declare native extension targets.

**Scene file** - A TOML file that describes entities, built-in components, and simple project-defined component data. The generated default scene is `scenes/main.scene.toml`.

**Text-first project** - A Scrapbot project whose primary source of truth is ordinary text files that can be edited by humans, tools, and agents.

## Rendering

**Renderer backend** - A renderer implementation behind Scrapbot's rendering boundary, such as the null renderer or the `wgpu-native` backend.

**Null renderer** - The placeholder renderer that accepts world-derived frame data without opening a window or using the GPU.

**SDL3** - The first platform window layer for Scrapbot's headful runtime smoke tests and renderer surface creation.

**Render packet** - Backend-neutral frame data extracted from the ECS world before submission to a renderer backend. It contains render instances, the active camera, accumulated ambient light, bounded directional lights, and a growable retained point-light list.

**WebGPU** - The modern graphics API model Scrapbot is targeting for its first real renderer.

**`wgpu-native`** - The first real renderer backend, using the native WebGPU implementation exposed through Odin's vendor bindings.

**Hi-Z pyramid** - A mipmapped max-depth texture built from the depth prepass. The WGPU visibility shader samples a previous stable-camera pyramid to conservatively reject bounding spheres hidden behind nearer geometry.

**Geometry LOD** - One of several indexed geometry representations selected for an instance according to its projected screen radius. A project LOD resource owns one stable UUID and runtime base handle while WGPU selects among its retained alternate draw batches.

**Voxel Terrain** - Smooth authored terrain whose compact height baseline is modified by sparse volumetric density bricks so caves, arches, and overhangs remain possible. See [ADR-062](adr/ADR-062-author-terrain-as-a-height-baseline-with-sparse-voxel-edits.md).

## Scripting And Editing

**Luau** - Scrapbot's embedded scripting language for project-local code, currently exposed through `scripts/main.luau` and a small `scrapbot` API for logging, systems, component schemas, custom component queries, and transform rotation helpers.

**Generated Luau types** - Project-local type definitions in `.scrapbot/types/scrapbot.d.luau`. `scrapbot check` refreshes them from the component registry so editors can see engine, project, and library component payload aliases, including readonly aliases for query snapshot payloads.

**Luau analyzer** - The external `luau-analyze` static checker. `scrapbot check` runs it when available to catch script type and syntax errors against generated Scrapbot types.

**Native extension** - Project-local compiled code declared in `project.toml`, cached as versioned dynamic libraries under `.scrapbot/cache/extensions`, and loaded through Scrapbot's C ABI. The extension API lets native libraries register dotted library component schemas, scheduled native systems, and deferred lifecycle commands, including spawning simple renderables, before Luau runs.

**Odin extension helper** - The `scrapbot:extension` package that wraps Scrapbot's raw native extension ABI with Odin-friendly component and field descriptors, registration accumulation, access declaration, query, transform, vec3 field, and lifecycle command helpers.

**Hot reload** - Runtime behavior where changed project files are reloaded without restarting the engine. Current coverage includes `project.toml`, the default scene, standalone resources, `scripts/main.luau`, native extension libraries, and declared native extension source directories.

**Editor GUI** - The in-engine live editor toggled from a running project. It uses transient editor-origin entities and the same public ECS UI components available to projects.

## Authoring and playback

**Authoring state** - The current in-memory state of authored entities and project resources. It may include unsaved editor transactions and is the state that Save compares with the disk baseline.

**Disk baseline** - The last successfully loaded or saved text representation used to determine what Save must write. Revert reloads this state and discards in-memory authoring history.

**Play Mode** - Running or paused simulation over a world that began from the current authoring state. Systems may mutate this world, but those simulation mutations are disposable unless a specific editor change is eligible to keep.

**Playback baseline** - The in-memory snapshot of scene-origin state captured when Play Mode starts. Stop restores this baseline before applying eligible staged play edits.

**Staged play edit** - A completed editor operation recorded separately from mutable simulation state because it is eligible to keep on Stop. Component edits target one authored entity/component pair; authored Duplicate, Paste, Delete, and Cut operations stage structural batches. See [ADR-026](adr/ADR-026-separate-authoring-persistence-from-runtime-playback.md).

**System-written component** - One specific entity/component pair actually mutated by a project system during the current playback world. It is ineligible for staged editor persistence for the remainder of that playback, even if other instances of the same component type remain eligible.

**Keep on Stop** - Restore the playback baseline, then apply eligible staged play edits to authoring state as one undoable transaction. Keeping does not write project files.

**Save** - Explicitly commit dirty authoring state to project files through the recoverable project transaction. Save is a disk operation and is distinct from keeping an edit on Stop.

**Dirty authoring state** - Authoring state that differs from the last successful Save position or disk baseline. Staging an edit during Play Mode does not make authoring state dirty until Stop keeps it.
