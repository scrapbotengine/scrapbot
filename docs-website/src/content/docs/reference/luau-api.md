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
- `scrapbot.ui_panel`
- `scrapbot.ui_table`
- `scrapbot.ui_list`
- `scrapbot.ui_progress`
- `scrapbot.ui_state`
- `scrapbot.ui_scroll_area`
- `scrapbot.ui_text`
- `scrapbot.ui_button`
- `scrapbot.ui_input`
- `scrapbot.ui_checkbox`

Light query payloads expose `color` and `intensity`; directional lights also expose `direction`, and point lights expose `range`. Systems can animate a point light by writing the same entity's transform.

Shadow caster and receiver handles have empty marker payloads. They can be queried and used with deferred `spawn`, `add_component`, and `remove_component` calls.

UI query payloads expose the same complete layout, value, and style fields used by the editor. Layout payloads include `min_size`, per-axis `fill_width`/`fill_height`, per-axis `fit_content_width`/`fit_content_height`, and `fixed_in_fill` for fixed bars or headers inside a fill stack. `scrapbot.ui_table` exposes proportional and resizable column policies plus a minimum column width; the first row's authored cell widths supply the proportions. `scrapbot.ui_progress` provides a reusable value/maximum indicator with track, fill, inset, corner, and direction styling. Scrollbars, panel disclosures, input prefixes/selections/borders/carets, and checkbox boxes/checkmarks expose their geometry, colors, borders, and corner radii as ordinary mutable fields. `scrapbot.ui_input` also exposes reusable numeric values, bounds, stepping, and scrubbing. Every laid-out element receives a renderer-owned, read-only `scrapbot.ui_state` payload with hover/active/focus, activation/change, validity, submit/cancel edges, and monotonic revision counters. Transient booleans describe the most recent UI pass; revision counters let systems detect edges reliably.

`scrapbot.add_component` can attach or update any public UI component on a live entity, and UI payload fields are optional so systems can supply only the values they need. `scrapbot.remove_component` removes public UI components through the structural dirty path. Runtime-spawned entities can therefore acquire the exact same components used by scene TOML and editor chrome.

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

Query callbacks receive a `ScrapbotEntity` table with `id`, `name`, `index`, and `generation`. Use the UUID string in `id` for durable identity. Index and generation form the runtime handle used by immediate ECS operations and stale-reference checks.

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
| `scrapbot.system(options, callback)` | Register a system with an optional project-facing name and access declarations. |
| `scrapbot.system(query, callback)` | Register a query-driven system. |
| `scrapbot.system(query, options, callback)` | Register a query-driven system with explicit write access. |

System options use:

```lua
{
	name = "Movement",
	reads = { ComponentOrQuery },
	writes = { Component },
}
```

Query components are read automatically. Payload mutation requires write access.
The optional name appears in editor tooling. It must be a non-empty string of at most 96 bytes.

## Transform helpers

| API | Meaning |
| --- | --- |
| `scrapbot.get_rotation(entity)` | Read an entity's transform rotation. |
| `scrapbot.set_rotation(entity, rotation)` | Write an entity's transform rotation. |

Query-driven transform payload mutation is preferred for new systems.

## Deferred lifecycle

| API | Meaning |
| --- | --- |
| `scrapbot.spawn(options?)` | Queue entity creation and return its stable UUID for references such as UI parents. |
| `scrapbot.despawn(entity)` | Queue entity removal. |
| `scrapbot.add_component(entity, component, payload)` | Queue a component add or update. UI payloads merge with existing values, preserving omitted fields. |
| `scrapbot.remove_component(entity, component)` | Queue component removal. |

Lifecycle commands apply after the scheduled frame step.
