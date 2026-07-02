--!strict

local Transform = ecs.component<<MachinaTransform>>("machina.transform")
local Geometry = ecs.component<<MachinaGeometryPrimitive>>("machina.geometry.primitive")
local Material = ecs.component<<MachinaSurfaceMaterial>>("machina.material.surface")
local ShadowCaster = ecs.component<<MachinaShadowCaster>>("machina.shadow.caster")

local Spawned = ecs.component("spawned", {
  fields = ecs.fields({
    angular_velocity = "vec3",
  }),
})

local SpawnedRenderables = ecs.query(Transform, Spawned)

ecs.system("spawn_renderables", {
  phase = "startup",
  writes = ecs.refs(Transform, Geometry, Material, ShadowCaster, Spawned),
  run = function(world, _dt)
    for row = 1, 3 do
      for column = 1, 8 do
        local index = (row - 1) * 8 + column
        local entity = world.spawn("spawned-" .. tostring(index), "Spawned " .. tostring(index))
        local x = (column - 4.5) * 0.62
        local y = (row - 2) * 0.62
        local z = -0.25 - row * 0.08
        local warm = index % 3 == 0
        local primitive = if warm then "uv_sphere" else "box"
        local color = if warm then { 1.0, 0.56, 0.08 } else { 0.0, 0.55, 1.0 }

        entity:add(Transform, {
          position = { x, y, z },
          rotation = { row * 0.12, column * 0.09, 0.0 },
          scale = { 0.22, 0.22, 0.22 },
        })
        entity:add(Geometry, {
          primitive = primitive,
          segments = if warm then 20 else 0,
          rings = if warm then 10 else 0,
        })
        entity:add(Material, {
          base_color = color,
        })
        entity:add(ShadowCaster)
        entity:add(Spawned, {
          angular_velocity = {
            0.08 + row * 0.05,
            0.22 + column * 0.015,
            0.04,
          },
        })
      end
    end
  end,
})

ecs.system("animate_spawned_renderables", {
  phase = "update",
  query = SpawnedRenderables,
  writes = ecs.refs(Transform),
  run = function(world, dt)
    for _entity, transform, spawned in SpawnedRenderables:iter(world) do
      transform.rotation = {
        transform.rotation[1] + spawned.angular_velocity[1] * dt,
        transform.rotation[2] + spawned.angular_velocity[2] * dt,
        transform.rotation[3] + spawned.angular_velocity[3] * dt,
      }
    end
  end,
})
