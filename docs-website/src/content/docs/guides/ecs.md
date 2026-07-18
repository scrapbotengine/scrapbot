---
title: ECS Overview
description: How Scrapbot models entities, components, queries, systems, structural changes, resources, and authoring.
---

Scrapbot uses one ECS world for project simulation, rendering state, project UI, and editor UI. Scene TOML, Luau, native Odin extensions, and the live editor all operate on the same registered component types. The editor is a first-party consumer of this public surface rather than a separate widget or scene model.

## The model at a glance

| Concept | Role |
| --- | --- |
| Entity | A lightweight runtime handle plus a stable project-wide UUID. |
| Component | Plain data attached to an entity. Components contain state, not behavior. |
| Query | A reusable, order-insensitive set of required component types. |
| System | Behavior that runs over the world and declares the component data it reads and writes. |
| Resource | Shared data, such as geometry or a material, stored outside the ECS and referenced by components. |

An entity is the intersection of its components. For example, a renderable object usually has `scrapbot.transform`, `scrapbot.geometry`, and `scrapbot.material`; adding `scrapbot.point_light` makes the same entity a light source. There is no required inheritance tree or game-object class.

## Entity identity and origin

Every entity has two identities:

- Its UUID is stable across save/load and is the only durable project-wide identity. Scene TOML stores it in `id`, and cross-entity references such as UI parents use it. Names are human-facing labels and need not be unique.
- Its index and generation form an efficient handle for one in-memory lifetime. The generation rejects stale handles when a storage slot is reused.

The world also records how an entity entered it: scene-authored, runtime-spawned, or editor-owned. Origin does not change when component values change. This distinction lets the editor display runtime entities without accidentally persisting ordinary simulation output.

## Components and the registry

The component registry is the shared contract between scene loading, Luau, native extensions, inspectors, UI, and engine reconciliation. Register a component schema before loading values that use it.

Naming communicates ownership:

- A single token, such as `floating`, is project-owned.
- A dotted name, such as `scrappyphysics.rigidbody`, belongs to an engine or library namespace.
- The `scrapbot` namespace is reserved for engine components.

Project and library schemas currently expose named vec3 fields. Engine components have typed built-in payloads covering transforms, cameras, render membership, lights, and the reusable UI system. See the [Engine Component Reference](/reference/components/) for the canonical field inventory and surface-specific names.

Scene entities attach project or library components under their registered name:

```toml
[[entities]]
id = "20000000-0000-4000-8000-000000000001"
name = "Spinner"

[entities.transform]
position = [0, 1, 0]

[entities.components.autorotate]
speed = [0, 1, 0]
```

## Queries

A query matches entities that have every requested component. Component order is not significant, and the Luau runtime reuses equivalent query objects.

Frame iteration is storage-planned: Scrapbot starts with the smallest matching project-component storage when possible, then checks the other required components. The order in which matching entities are returned is an internal detail; systems must not assign gameplay meaning to it.

Luau query systems receive entity identity followed by component payloads:

```lua
local Autorotate = scrapbot.component("autorotate", {
	speed = scrapbot.vec3,
})

local Rotating = scrapbot.query(scrapbot.transform, Autorotate)

scrapbot.system(Rotating, {
	name = "autorotate",
	writes = { scrapbot.transform },
}, function(time, entity, transform, autorotate)
	transform.rotation.y += autorotate.speed.y * time.delta_time
end)
```

Native extensions use the same component sets through a forward-only query cursor. See [Luau API: Queries and views](/reference/luau-api/#queries-and-views) and [Native Extensions: Register a system](/guides/native-extensions/#register-a-system) for the exact APIs.

## Systems and scheduling

Systems provide behavior. Every system observes the same read-only frame-time snapshot, including `delta_time`, smoothed delta time, elapsed time, and frame index.

Access declarations are part of correctness as well as optimization:

- Query terms imply reads.
- Payload mutation requires a matching write declaration.
- Non-conflicting native systems can run concurrently on the worker pool.
- Conflicting systems retain registration order.
- Luau systems run serially as scheduler barriers.
- A native system without access declarations runs exclusively.

Keep systems narrow and named after one piece of simulation—`autorotate`, `rigidbody`, `floating`, or `orbit`—rather than one particular entity or scene feature.

## Value changes and structural changes

Writing a field on an existing component changes data immediately within the system's permitted write access. Changing the world structure is deferred:

- spawn an entity;
- despawn an entity;
- add or update a component;
- remove a component.

Deferred commands apply after the scheduled frame step. Native workers use private command buffers that are merged deterministically. This keeps query iteration stable while systems run and prevents one system from invalidating another system's current cursor.

See [Luau API: Deferred lifecycle](/reference/luau-api/#deferred-lifecycle) and [Native Extensions: Queue lifecycle commands](/guides/native-extensions/#queue-lifecycle-commands).

## Rendering and UI are ECS consumers

Rendering watches component membership rather than rebuilding ownership from entity names. When relevant components appear, disappear, or change, Scrapbot updates derived render membership and backend caches incrementally. Geometry and material components contain resolved resource handles; GPU objects remain backend-owned.

UI uses the same rule. Layout, stacks, panels, tables, lists, inputs, and other controls are ordinary public components. The UI system derives layout, paint commands, and read-only `scrapbot.ui_state` interaction data. Both project UI and editor chrome use these components. See [ECS UI](/guides/ecs-ui/).

Derived engine components and renderer state are not authoring data. For example, `scrapbot.render_instance` and `scrapbot.ui_state` are engine-owned outputs and cannot be authored or written by project systems.

## Resources are deliberately outside the ECS

Shared geometry and authored materials are resources, not singleton entities. Authored resources have stable UUIDs in standalone resource TOML files. At runtime, registries resolve those UUIDs to generational handles stored by ECS components. This lets many entities share one resource while render backends manage GPU lifetimes independently.

See [Project Files: Resources](/reference/project-files/#resource-files) and the component reference for the components that carry resource handles.

## Authoring and playback

The live editor edits the active ECS world while stopped and records completed gestures as UUID-addressed undo/redo transactions. Save compares dirty candidates with the authored baseline and writes only explicit authoring changes. Play captures an in-memory baseline; Stop discards disposable playback changes and runtime-spawned entities by restoring that baseline without reloading Luau or native Odin code.

This separation is intentional: an ECS mutation is not automatically a source-file mutation. See [Live Editor](/guides/live-editor/) for the complete transport and persistence model.

## Where to go next

- [Engine Component Reference](/reference/components/): every built-in component and public field.
- [Luau API Reference](/reference/luau-api/): component registration, queries, systems, views, and lifecycle calls.
- [Native Extensions](/guides/native-extensions/): Odin component schemas, scheduling declarations, cursors, and commands.
- [Project Files](/reference/project-files/): authored scene and resource syntax.
- [ECS UI](/guides/ecs-ui/): the reusable UI component system.
