--!strict

local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
local Geometry = ecs.component<<ScrapbotGeometryPrimitive>>("scrapbot.geometry.primitive")
local Material = ecs.component<<ScrapbotSurfaceMaterial>>("scrapbot.material.surface")

local Renderables = ecs.query(Transform, Geometry, Material)
local elapsed = 0

ecs.system("animate_batches", {
  phase = "update",
  query = Renderables,
  writes = ecs.refs(Transform),
  run = function(world, dt)
    local previous = elapsed
    elapsed += dt

    for _entity, transform, geometry, material in Renderables:iter(world) do
      if geometry.primitive ~= "plane" then
        local color = material.base_color
        local primitive_weight = if geometry.primitive == "box" then 1.0 else 0.55
        local phase = transform.position[1] * 0.73 + transform.position[3] * 1.31 + color[2] * 2.0
        local wave_speed = 1.15 + color[1] * 0.45
        local wave_delta = (math.sin(elapsed * wave_speed + phase) - math.sin(previous * wave_speed + phase)) * 0.07

        transform.position = {
          transform.position[1],
          transform.position[2] + wave_delta,
          transform.position[3],
        }

        transform.rotation = {
          transform.rotation[1] + dt * (0.22 + color[3] * 0.5) * primitive_weight,
          transform.rotation[2] + dt * (0.48 + color[2] * 0.32) * primitive_weight,
          transform.rotation[3] + dt * (0.18 + color[1] * 0.28) * primitive_weight,
        }
      end
    end
  end,
})
