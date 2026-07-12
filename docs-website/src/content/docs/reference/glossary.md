---
title: Glossary
description: Scrapbot project vocabulary.
---

## Runtime

**ECS**  
Scrapbot's world model. Entities are identifiers, components hold data, and systems operate over matching component sets.

**Entity**  
A generation-aware identifier for one object in a Scrapbot world.

**Component**  
A typed piece of data attached to an entity. Single-token names such as `autorotate` identify project-level components. Dotted names such as `scrapbot.transform` or `scrappyphysics.rigidbody` identify engine or library components.

**Component registry**  
The runtime registry of component names, IDs, owners, and simple field schemas. It feeds scene validation, generated Luau types, and query handles.

**Query object**  
A reusable Luau value created with `scrapbot.query(...)` that represents one component set.

**Scheduled system**  
A system with declared component reads and writes. Scrapbot currently batches scheduled systems by access conflicts, then executes them serially.

**Deferred command buffer**  
A runtime queue of entity/component lifecycle mutations applied after systems finish the frame.

## Projects

**Project directory**  
The directory where a user runs Scrapbot. It contains `project.toml`, scene files, scripts, generated types, assets, and optional native extension source.

**Text-first project**  
A project whose source of truth is ordinary text files that can be edited by humans, tools, and agents.

**Scene file**  
A TOML file describing entities, built-in components, and schema-backed custom component data.

## Scripting and native code

**Luau**  
Scrapbot's embedded scripting language for project-local code.

**Generated Luau types**  
Project-local type definitions in `types/scrapbot.d.luau`, refreshed by `scrapbot check`.

**Native extension**  
Project-local compiled code declared in `project.toml`, built into versioned dynamic libraries under `build/extensions`, and loaded through Scrapbot's C ABI. Native extensions can register component schemas and scheduled systems.

**Odin extension helper**
The `scrapbot:extension` package that wraps Scrapbot's raw native extension ABI with Odin-friendly component and field descriptors, registration accumulation, access declaration, query, transform, and vec3 field helpers.

**Hot reload**  
Runtime behavior where changed project files are reloaded without restarting the engine. Current hot reload covers `project.toml`, the default scene, `scripts/main.luau`, native extension libraries, and declared native extension source directories.

## Rendering

**Renderer backend**  
A renderer implementation behind Scrapbot's rendering boundary, such as the null renderer or the WebGPU backend.

**Null renderer**  
The placeholder renderer that accepts world-derived frame data without opening a window or using the GPU.

**WebGPU**  
The graphics API model Scrapbot targets for the first real renderer through `wgpu-native`.
