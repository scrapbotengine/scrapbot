---
title: Queries and Views
description: Use typed query iteration for ergonomics and buffer-backed views for hot Luau loops.
---

Scrapbot provides two Luau query surfaces:

- `Query:iter(world)` for ergonomic typed component proxy iteration.
- `Query:view(world)` for high-cardinality hot loops that need bulk `f32` or `vec3` access.

## Typed Query Iteration

Use `Query:iter(world)` by default:

```lua
local Movers = ecs.query(Transform, Motion)

ecs.system("move_entities", {
  phase = "update",
  query = Movers,
  writes = ecs.refs(Transform),
  run = function(world, dt)
    for _entity, transform, motion in Movers:iter(world) do
      transform.position = {
        transform.position[1] + motion.velocity[1] * dt,
        transform.position[2] + motion.velocity[2] * dt,
        transform.position[3] + motion.velocity[3] * dt,
      }
    end
  end,
})
```

This is the preferred API until profiling shows the bridge cost matters.

## Prepared Query Plans

Reusable query objects cache hidden prepared plans across invocations.

The runtime invalidates those plans when component table identity changes, so systems can keep using the same query object while entities and component tables change over time.

## Buffer-Backed Views

For larger hot loops, capture a frame-local view:

```lua
local view = Comets:view(world)
local count = view:count()
local positions = view:read_vec3(Transform, "position")
local velocities = view:read_vec3(CometMotion, "velocity")

for index = 0, count - 1 do
  local offset = index * 12
  local x = buffer.readf32(positions, offset)
  local vx = buffer.readf32(velocities, offset)
  buffer.writef32(positions, offset, x + vx * dt)
end

view:write_vec3(Transform, "position", positions)
```

Supported bulk field views currently cover:

| Field type | Read | Write |
| --- | --- | --- |
| `f32` | `view:read_f32(Component, "field")` | `view:write_f32(Component, "field", buffer)` |
| `vec3` | `view:read_vec3(Component, "field")` | `view:write_vec3(Component, "field", buffer)` |

## Buffer Layout

Buffers use byte offsets:

- `f32` values are packed every 4 bytes.
- `vec3` values are packed every 12 bytes as `x, y, z`.

```lua
local f32_offset = index * 4
local vec3_offset = index * 12
```

## View Lifetime

Query views are transfer surfaces, not script-owned storage.

Do not keep a view or its buffers beyond the active system callback. The engine validates view usage against the active system and world generation.

## When To Use Views

Use views when all of these are true:

- The system touches many entities.
- The hot loop reads or writes simple `f32` or `vec3` fields.
- Profiling shows per-entity proxy bridge calls are meaningful.
- The lower-level buffer code is still understandable and covered by tests.

Keep small and medium systems on `Query:iter(world)`.
