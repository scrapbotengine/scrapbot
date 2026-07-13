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
- `scrapbot.ambient_light`
- `scrapbot.directional_light`
- `scrapbot.point_light`
- `scrapbot.shadow_caster`
- `scrapbot.shadow_receiver`
- `scrapbot.ui_layout`
- `scrapbot.ui_hstack`
- `scrapbot.ui_vstack`
- `scrapbot.ui_scroll_area`
- `scrapbot.ui_text`
- `scrapbot.ui_button`

Light query payloads expose `color` and `intensity`; directional lights also expose `direction`, and point lights expose `range`. Systems can animate a point light by writing the same entity's transform.

Shadow caster and receiver handles have empty marker payloads. They can be queried and used with deferred `spawn`, `add_component`, and `remove_component` calls.

UI box, stack, scroll-area, text, and button handles currently expose entity presence for queries. UI creation and property mutation remain scene-authored in this first slice; deferred runtime UI commands and button activation are planned next.

## Render resources

| API | Purpose |
| --- | --- |
| `scrapbot.geometry.create(name, descriptor)` | Register full position/normal/UV vertices and `u32` triangle indices. |
| `scrapbot.geometry.cube(name, size?)` | Generate and register indexed cube geometry. |
| `scrapbot.geometry.plane(name, width?, depth?)` | Generate and register indexed plane geometry. |
| `scrapbot.geometry.icosphere(name, radius?, subdivisions?)` | Generate an indexed icosphere. Subdivisions range from 0 to 4. |
| `scrapbot.geometry.sphere(name, radius?, segments?, rings?)` | Generate an indexed UV sphere. |
| `scrapbot.geometry.pyramid(name, width?, height?, depth?)` | Generate an indexed square pyramid. |
| `scrapbot.geometry.cylinder(name, radius?, height?, segments?)` | Generate an indexed capped cylinder. |
| `scrapbot.material.lit(name, r?, g?, b?, a?)` | Register a shared Lambert-lit base-color material. |
| `scrapbot.material.unlit(name, r?, g?, b?, a?)` | Compatibility alias for `material.lit`. |
| `scrapbot.material.textured(name, asset_path, r?, g?, b?, a?)` | Decode a project PNG under `assets/` and register a textured, optionally tinted material. |

Texture paths must be project-relative paths beginning with `assets/`; absolute paths and parent traversal are rejected. Missing, invalid, oversized, or undecodable images fail `scrapbot check` and `run` while the script registers resources.

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

Every callback receives a read-only `ScrapbotTime` value as its first argument:

| Field | Meaning |
| --- | --- |
| `delta_time` | Current simulation step in seconds. |
| `smooth_delta_time` | Exponentially smoothed delta time for presentation. |
| `elapsed_time` | Accumulated simulation time in seconds. |
| `frame_index` | One-based frame count. |

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
