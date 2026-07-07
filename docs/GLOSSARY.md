# Glossary

## Records

**ADR (Architecture Decision Record)** - A document in `docs/adr/` that captures a cross-cutting architecture decision and its consequences.

**FDR (Feature Decision Record)** - A document in `docs/fdr/` that describes one feature's behavior, design decisions, related ADRs, and open questions.

## Runtime

**ECS (Entity Component System)** - Scrapbot's runtime world model, where entities are identifiers, components hold data, and systems operate over matching component sets.

**Entity** - A generation-aware identifier for one object in a Scrapbot world.

**Component** - A typed piece of data attached to an entity, such as a transform, camera, or mesh reference.

**System** - Runtime logic that reads or writes components for matching entities.

**SoA (Structure of Arrays)** - A data layout used for hot component storage, taking advantage of Odin's `#soa` support.

**World** - The in-memory ECS state built from a project scene and used by runtime systems and rendering.

## Projects

**Project directory** - The directory where a user runs Scrapbot. It contains `project.toml`, scene files, scripts, assets, and future native extension code.

**`project.toml`** - The project manifest in the root of a Scrapbot project directory.

**Scene file** - A TOML file that describes entities and known components. The generated default scene is `scenes/main.scene.toml`.

**Text-first project** - A Scrapbot project whose primary source of truth is ordinary text files that can be edited by humans, tools, and agents.

## Rendering

**Renderer backend** - A renderer implementation behind Scrapbot's rendering boundary, such as the current null renderer or the planned `wgpu-native` backend.

**Null renderer** - The placeholder renderer that accepts world-derived frame data without opening a window or using the GPU.

**SDL3** - The first platform window layer for Scrapbot's headful runtime smoke tests and future renderer surface creation.

**Render packet** - Planned name for backend-neutral render data extracted from the ECS world before submission to a renderer backend.

**WebGPU** - The modern graphics API model Scrapbot is targeting for its first real renderer.

**`wgpu-native`** - The planned first real renderer backend, using the native WebGPU implementation exposed through Odin's vendor bindings.

## Scripting And Editing

**Luau** - The planned embedded scripting language for project-local components and systems.

**Native extension** - Planned project-local compiled code that can register fast systems or engine integrations.

**Hot reload** - Planned runtime behavior where scene files, scripts, shaders, or native extension code can be reloaded without restarting the engine.

**Editor GUI** - The planned in-engine editor interface toggled from a running project.
