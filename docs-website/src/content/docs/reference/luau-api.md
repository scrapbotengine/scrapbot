---
title: Luau API Reference
description: Current project scripting API exposed through the scrapbot global.
---

The generated `types/scrapbot.d.luau` file is the most precise API reference for a specific project. This page summarizes the current runtime surface.

## Runtime information

| API | Meaning |
| --- | --- |
| `scrapbot.log(message)` | Print a Luau log line. |
| `scrapbot.entity_count()` | Return alive entity count. |
| `scrapbot.renderable_count()` | Return renderable count. |

## Components

| API | Meaning |
| --- | --- |
| `scrapbot.component(name, schema)` | Register a project-level component. |
| `scrapbot.library_component(name, schema)` | Register a dotted library component from Luau. |
| `scrapbot.component_handle(name)` | Retrieve an already registered component handle. |
| `scrapbot.vec3` | Schema field marker for vec3 payload fields. |

Built-in handles:

- `scrapbot.transform`
- `scrapbot.camera`
- `scrapbot.geometry_component`
- `scrapbot.material_component`

## Render resources

| API | Purpose |
| --- | --- |
| `scrapbot.geometry.create(name, descriptor)` | Register full position/normal/UV vertices and `u32` triangle indices. |
| `scrapbot.geometry.cube(name, size?)` | Generate and register indexed cube geometry. |
| `scrapbot.geometry.plane(name, width?, depth?)` | Generate and register indexed plane geometry. |
| `scrapbot.material.unlit(name, r?, g?, b?, a?)` | Register a shared unlit material. |

Named registration updates an existing resource while preserving its handle. Spawn component maps use `scrapbot.geometry` and `scrapbot.material` names with the returned handles.

## Queries and views

| API | Meaning |
| --- | --- |
| `scrapbot.query(component, ...)` | Create or retrieve a reusable query object. |
| `query:each(callback)` | Iterate matching entities. |
| `scrapbot.view(component)` | Return a materialized component view. |
| `scrapbot.view(query)` | Return a materialized joined query view. |
| `scrapbot.view({ component, ... })` | Return a materialized joined component view. |

Query construction is order-insensitive, and repeated calls for the same component set return the same object.

## Systems

| API | Meaning |
| --- | --- |
| `scrapbot.system(callback)` | Register a frame system. |
| `scrapbot.system(options, callback)` | Register a system with explicit access declarations. |
| `scrapbot.system(query, callback)` | Register a query-driven system. |
| `scrapbot.system(query, options, callback)` | Register a query-driven system with explicit write access. |

Access declarations use:

```lua
{
	reads = { ComponentOrQuery },
	writes = { Component },
}
```

Query components are read automatically. Payload mutation requires write access.

## Transform helpers

| API | Meaning |
| --- | --- |
| `scrapbot.get_rotation(entity)` | Read an entity's transform rotation. |
| `scrapbot.set_rotation(entity, rotation)` | Write an entity's transform rotation. |

Query-driven transform payload mutation is preferred for new systems.

## Deferred lifecycle

| API | Meaning |
| --- | --- |
| `scrapbot.spawn(options?)` | Queue entity creation. |
| `scrapbot.despawn(entity)` | Queue entity removal. |
| `scrapbot.add_component(entity, component, payload)` | Queue component addition. |
| `scrapbot.remove_component(entity, component)` | Queue component removal. |

Lifecycle commands apply after the scheduled frame step.
