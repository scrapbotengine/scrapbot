---
title: ECS Runtime
description: How Scrapbot stores components, schedules systems, and keeps scripting and rendering on one runtime model.
---

Scrapbot's runtime is built around entities, components, and systems.

- Entities are stable handles with index and generation.
- Entities track whether they came from authored scene data or were spawned at runtime.
- Components are typed data tables.
- Systems declare phase, reads, writes, and ordering constraints.
- The scheduler builds batches from those declarations.

## Component Storage

Component storage is columnar per component type.

Each component table has:

- Dense rows for entities that have that component.
- A sparse entity-to-row lookup.
- Typed Structure-of-Arrays field columns.

This lets dynamically registered Luau and native components share one storage model without requiring native structs for every project component.

Supported field types are:

| Type | Meaning |
| --- | --- |
| `boolean` or `bool` | Boolean value |
| `int` or `i32` | 32-bit signed integer |
| `float` or `f32` | 32-bit floating point value |
| `vec3` | Three `f32` values |
| `string` | Engine-owned string data |

## Systems

Systems declare what they need before they run:

```lua
ecs.system("float_cubes", {
  phase = "update",
  query = FloatingCubes,
  writes = ecs.refs(Transform, Bob),
  after = { "rotate_cubes" },
  run = function(world, dt)
    -- mutate components here
  end,
})
```

The current runtime phases are:

| Phase | Use |
| --- | --- |
| `startup` | Run once when a loaded project/scene generation starts. |
| `update` | Run every simulation frame. |
| `fixed_update` | Reserved for fixed-step work. |
| `render` | Used by engine-internal render systems. |

## Access Declarations

Systems must declare component access before they run.

- Query components become reads unless also listed in writes.
- `writes = ecs.refs(...)` declares components the system can mutate.
- Manual reads can be added with `reads = ecs.refs(...)`.
- Ordering uses `before = { ... }` and `after = { ... }`.

Scrapbot uses those declarations for:

- Schedule construction.
- Conflict detection.
- Runtime host API permission checks.
- Future parallelization.
- Editor performance reporting.

## Structural Mutations

Systems can spawn/despawn entities and add/remove components through ECS APIs.

Entities created by `world.spawn` or native spawn APIs are runtime-spawned entities. They live in the same ECS world as scene-authored entities, but they are not authored scene TOML data.

Structural mutations are intentionally staged:

- Spawns happen immediately and are tracked for rollback if the system fails.
- Add/remove component and despawn commands are queued.
- Queued commands flush only after the active system returns successfully.
- Same-callback queries should not expect queued component changes to be visible.

This rule applies to both Luau systems and native Zig systems.

## Engine Internals Use the Same ECS

The renderer owns an internal render world and a render-phase schedule built with the same `runtime.World`, component registry, and scheduler implementation used by game worlds.

Render systems currently extract scene data, prepare mesh batches, process UI interaction state, queue draw commands, and draw. Editor performance UI includes those internal render systems beside project systems.
