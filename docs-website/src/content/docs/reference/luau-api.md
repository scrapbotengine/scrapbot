---
title: Luau API Reference
description: Current project scripting API exposed through the scrapbot global.
---

The generated `.scrapbot/types/scrapbot.d.luau` file is the most precise API reference for a specific project. This page summarizes the current runtime surface.

## Runtime information

| API | Meaning |
| --- | --- |
| `scrapbot.log(message)` | Print a Luau log line. |
| `scrapbot.entity_count()` | Return alive entity count. |
| `scrapbot.renderable_count()` | Return renderable count. |

## Components

| API | Meaning |
| --- | --- |
| `scrapbot.component(name, schema, options?)` | Register a project-level component. Set `advanced = true` to keep it inspectable but initially collapse its editor panel. |
| `scrapbot.library_component(name, schema, options?)` | Register a dotted library component from Luau, with the same optional presentation metadata. |
| `scrapbot.component_handle(name)` | Retrieve an already registered component handle. |
| `scrapbot.number` | Schema field marker for scalar numeric payload fields. |
| `scrapbot.vec2`, `scrapbot.vec3`, `scrapbot.vec4` | Schema field markers for two-, three-, and four-channel numeric payloads. |
| `scrapbot.color` | Schema field marker for semantic RGBA payloads. Stored as four numbers and surfaced distinctly to tooling. |
| `scrapbot.field(type, options?)` | Add editor metadata to a field type. Options are `draggable`, positive `step`, `minimum`, and `maximum`. |

Legacy strings (`"number"`, `"vec2"`, `"vec3"`, `"vec4"`, and `"color"`) remain accepted, but marker values generate better project-local declarations. Numeric pointer dragging is opt-in through `scrapbot.field(..., { draggable = true })`; bounds and steps are schema metadata shared by the editor rather than Luau-only behavior.

Component options are tooling hints, not storage or visibility rules. `{ advanced = true }` leaves the component fully queryable, authorable, and visible in the inspector, but starts its inspector panel collapsed. This is appropriate for simulation bookkeeping that can still be useful while debugging.

Built-in handles:

- `scrapbot.transform`
- `scrapbot.camera`
- `scrapbot.mesh`
- `scrapbot.geometry_component`
- `scrapbot.material_component`
- `scrapbot.ambient_light`
- `scrapbot.directional_light`
- `scrapbot.point_light`
- `scrapbot.shadow_caster`
- `scrapbot.shadow_receiver`
- `scrapbot.keyboard_input` (derived singleton; access declarations only)
- `scrapbot.pointer_input` (derived singleton; access declarations only)
- `scrapbot.ui_layout`
- `scrapbot.ui_hstack`
- `scrapbot.ui_vstack`
- `scrapbot.ui_panel`
- `scrapbot.ui_table`
- `scrapbot.ui_list`
- `scrapbot.ui_progress`
- `scrapbot.ui_viewport`
- `scrapbot.ui_state`
- `scrapbot.ui_scroll_area`
- `scrapbot.ui_text`
- `scrapbot.ui_button`
- `scrapbot.ui_input`
- `scrapbot.ui_checkbox`

See the [Engine Component Reference](/reference/components/) for the complete field inventory, defaults, constraints, scene names, and native Odin descriptors. Camera, mesh, geometry, and material are currently membership handles with opaque resource-backed query payloads.

Light query payloads expose `color` and `intensity`; directional lights also expose `direction`, and point lights expose `range`. Systems can animate a point light by writing the same entity's transform.

World Environment queries expose the complete scene-authored payload. Declare `scrapbot.world_environment` in a system's `writes` before changing atmosphere or sun fields; accepted writeback advances the component revision consumed by the retained environment phase. `examples/ecs-showcase` combines it with a project-local `day_cycle` component to animate a complete day/night orbit.

Transform query payloads expose `parent`, `position`, `rotation`, and `scale`. `parent` is an entity UUID string or empty for a root, and TRS values are local to that parent. A parent without a Transform contributes an identity spatial basis. Writeback rejects a missing parent, self-parenting, and cycles. Rendering and spatial editor tools derive world transforms automatically.

Shadow caster and receiver handles have empty marker payloads. They can be queried and used with deferred `spawn`, `add_component`, and `remove_component` calls.

UI query payloads expose the same complete layout, value, and style fields used by the editor. Layout payloads include `min_size`, per-axis `fill_width`/`fill_height`, per-axis `fit_content_width`/`fit_content_height`, and `fixed_in_fill` for fixed bars or headers inside a fill stack. Tree rows additionally expose `tree_item`, semantic `tree_parent`, sibling-local `tree_order`, and `tree_collapsed`. `scrapbot.ui_table` exposes proportional and resizable column policies plus a minimum column width; the first row's authored cell widths supply the proportions. `scrapbot.ui_list` can opt into direct-child dragging with configurable edge zones, insertion lines, and into-row tint, or enable shared nested-tree flattening and mutation with `tree_enabled` and `tree_indent`. `scrapbot.ui_progress` provides a reusable value/maximum indicator with track, fill, inset, corner, and direction styling. `scrapbot.ui_viewport` exposes Texture/Model/Material/World targets, optional camera/root UUIDs, orbit, distance, clear color, and shared interaction policy. Scrollbars, panel disclosures, button icons/title placement, input prefixes/selections/borders/carets, and checkbox boxes/checkmarks expose their geometry, colors, borders, and corner radii as ordinary mutable fields. A direct child button with `panel_action = true` occupies its parent panel's title band and advances its own ordinary activation revision. `scrapbot.ui_input` also exposes reusable numeric values, bounds, stepping, and scrubbing. Every laid-out element receives a renderer-owned, read-only `scrapbot.ui_state` payload with hover/active/focus, activation/change, validity, submit/cancel edges, draggable-list source/target UUIDs, `drop_placement` (`none`, `before`, `into`, or `after`), and monotonic revision counters including `drop_revision`. Transient booleans describe the most recent UI pass; revision counters let systems detect edges reliably.

`scrapbot.add_component` can attach or update any public UI component on a live entity, and UI payload fields are optional so systems can supply only the values they need. `scrapbot.remove_component` removes public UI components through the structural dirty path. Runtime-spawned entities can therefore acquire the exact same components used by scene TOML and editor chrome.

## Runtime input

Declare the singleton you consume in the system's `reads`, then inspect the current immutable frame snapshot:

```lua
scrapbot.system(PlayerQuery, {
	name = "control",
	reads = { scrapbot.keyboard_input, scrapbot.pointer_input },
	writes = { scrapbot.transform },
}, function(time, entity, transform)
	if scrapbot.input.key_down("left") then
		transform.position.x -= 5 * time.delta_time
	end
	if scrapbot.input.key_pressed("space") then
		-- Fire once for this press.
	end
	local pointer = scrapbot.input.pointer()
	local down, pressed, released = scrapbot.input.pointer_button("primary")
end)
```

`key_down`, `key_pressed`, and `key_released` accept the physical key names listed in the [component reference](/reference/components/#runtime-input-singletons). `pointer()` returns `available`, `captured`, `position`, `delta`, and `wheel`. `pointer_button(name)` returns held, pressed, and released booleans for `primary`, `secondary`, `middle`, `back`, or `forward`. Positions and deltas are drawable pixels. A null or hidden headless backend returns unavailable zero snapshots.

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
| `scrapbot.material.emissive(name, r?, g?, b?, intensity?)` | Register an unlit HDR material. RGB defaults to white and intensity defaults to `4`; values above display white feed bloom. |
| `scrapbot.material.textured(name, asset_path, r?, g?, b?, a?)` | Decode a project PNG under `assets/` and register a textured, optionally tinted material. |

Texture paths must be project-relative paths beginning with `assets/`; absolute paths and parent traversal are rejected. Missing, invalid, oversized, or undecodable images fail `scrapbot check` and `run` while the script registers resources.

Named registration updates an existing transient runtime resource while preserving its handle. Spawn component maps use `scrapbot.geometry` and `scrapbot.material` names with the returned handles. These functions do not create persistent project resources; authored materials live in standalone `.resource.toml` files and scenes reference their UUIDs.

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
