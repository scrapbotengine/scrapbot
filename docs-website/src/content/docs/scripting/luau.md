---
title: Luau Systems
description: Register components and systems in Luau, then run gameplay through Scrapbot's ECS scheduler.
---

Luau is Scrapbot's scripting language for gameplay logic.

Scrapbot expects scripts to be system-first:

- Define components.
- Define query objects.
- Define named systems with phase, reads, writes, and ordering.
- Mutate ECS data through world/entity/component APIs.

## Register Components

Use `ecs.component(...)` with `ecs.fields(...)` for project components:

```lua
--!strict

local Spin = ecs.component("spin", {
  fields = ecs.fields({
    angular_velocity = "vec3",
  }),
})
```

Scrapbot infers editor-facing Luau payload types from the field schema.

You can also provide an explicit payload type:

```lua
type Health = {
  current: number,
  max: number,
}

local HealthComponent = ecs.component<<Health>>("health", {
  fields = ecs.fields({
    current = "f32",
    max = "f32",
  }),
})
```

## Reference Engine Components

Engine components can be referenced by id and built-in type:

```lua
local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
local Geometry = ecs.component<<ScrapbotGeometryPrimitive>>("scrapbot.geometry.primitive")
local Material = ecs.component<<ScrapbotSurfaceMaterial>>("scrapbot.material.surface")
```

## Build Queries

Queries are reusable typed objects:

```lua
local Spinning = ecs.query(Transform, Spin)
```

Use `Query:iter(world)` for normal systems:

```lua
for _entity, transform, spin in Spinning:iter(world) do
  transform.rotation = {
    transform.rotation[1] + spin.angular_velocity[1] * dt,
    transform.rotation[2] + spin.angular_velocity[2] * dt,
    transform.rotation[3] + spin.angular_velocity[3] * dt,
  }
end
```

The iterator yields the entity plus the requested component proxies in query order.

## Register Systems

```lua
ecs.system("rotate_cubes", {
  phase = "update",
  query = Spinning,
  writes = ecs.refs(Transform),
  run = function(world, dt)
    for _entity, transform, spin in Spinning:iter(world) do
      transform.rotation = {
        transform.rotation[1] + spin.angular_velocity[1] * dt,
        transform.rotation[2] + spin.angular_velocity[2] * dt,
        transform.rotation[3] + spin.angular_velocity[3] * dt,
      }
    end
  end,
})
```

Rules:

- Systems need stable ids.
- Use `phase = "startup"` for one-time setup.
- Use `phase = "update"` for per-frame simulation.
- Declare writes with `ecs.refs(...)`.
- Use `before` and `after` for ordering.

## Spawn and Mutate Entities

Systems can create entities and attach components:

```lua
local entity = world.spawn("comet-1", "Comet 1")

entity:add(Transform, {
  position = { 0.0, 0.0, 0.0 },
  rotation = { 0.0, 0.0, 0.0 },
  scale = { 1.0, 1.0, 1.0 },
})

entity:add(Geometry, {
  primitive = "uv_sphere",
  segments = 24,
  rings = 12,
})
```

Remove a component:

```lua
entity:remove(Temporary)
```

Despawn an entity:

```lua
entity:despawn()
```

Lifecycle commands require declared write access. Despawning requires write access to every component currently attached to the entity.

## Performance Notes

Component proxy field access crosses the Luau/native bridge.

For ordinary systems, use readable `Query:iter(world)` loops. In large hot loops, use [buffer-backed query views](/scripting/queries-and-views/).

When using proxy loops, cache fields in locals if you reuse them several times:

```lua
local rotation = transform.rotation
local angular_velocity = spin.angular_velocity
```

This avoids repeated bridge calls and repeated vec3 table allocation.
