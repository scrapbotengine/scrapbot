---
title: Glossary
description: Scrapbot project vocabulary.
---

## Runtime

**ECS**  
Scrapbot's world model. Entities are identifiers, components hold data, and systems operate over matching component sets.

**Entity**  
A Scrapbot world object with two complementary identities: a stable project-wide UUID and a generation-aware runtime handle.

**Entity UUID**<br>
A non-zero RFC UUID that identifies an entity independently from its editable name, scene order, or runtime storage slot. Scene UUIDs are serialized; runtime spawns mint a new UUID for each lifetime.

**Component**  
A typed piece of data attached to an entity. Single-token names such as `autorotate` identify project-level components. Dotted names such as `scrapbot.transform` or `scrappyphysics.rigidbody` identify engine or library components.

**Component registry**  
The runtime registry of component names, IDs, owners, and simple field schemas. It feeds scene validation, generated Luau types, and query handles.

**Query object**  
A reusable Luau value created with `scrapbot.query(...)` that represents one component set.

**Scheduled system**  
A system with declared component reads and writes. Scrapbot batches scheduled systems by access conflicts, executes conflict-free native systems concurrently, and treats Luau or undeclared systems as serial barriers.

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
Project-local compiled code declared in `project.toml`, built into versioned dynamic libraries under `build/extensions`, and loaded through Scrapbot's C ABI. Native extensions can register component schemas, scheduled systems, and deferred lifecycle commands, including spawning simple renderables.

**Odin extension helper**
The `scrapbot:extension` package that wraps Scrapbot's raw native extension ABI with Odin-friendly component and field descriptors, registration accumulation, access declaration, query, transform, vec3 field, and lifecycle command helpers.

**Hot reload**  
Runtime behavior where changed project files are reloaded without restarting the engine. Current hot reload covers `project.toml`, the default scene, `scripts/main.luau`, native extension libraries, and declared native extension source directories.

## Rendering

**Renderer backend**  
A renderer implementation behind Scrapbot's rendering boundary, such as the null renderer or the WebGPU backend.

**Null renderer**  
The placeholder renderer that accepts world-derived frame data without opening a window or using the GPU.

**WebGPU**  
The graphics API model Scrapbot targets for the first real renderer through `wgpu-native`.

**Shadow caster**
An entity marked to contribute geometry to the first directional light's shadow map.

**Shadow receiver**
An entity marked to sample the directional shadow map when its directional lighting is evaluated.

**ECS UI**
Screen-space UI described by public `scrapbot.ui_*` entities and components. Scene TOML, Luau, native Odin, and editor chrome share the same retained layout, panels, tables, selectable lists, progress indicators, scrolling, controls, styles, and renderer-owned interaction state.

## Live editor

**Entity provenance**
The origin recorded for a live entity: scene-authored, runtime-spawned, or editor-owned. Provenance remains separate from the entity's generation-aware identity.

**Editor scene camera**
A transient editor-owned ECS entity used to navigate the live viewport without mutating the project's camera.

**Transform gizmo**
Transient editor state attached to the selected entity and rendered as screen-legible handles. Its ECS-visible mode and World/Local orientation support X, Y, and Z translation, rotation, and scale in the running world.
