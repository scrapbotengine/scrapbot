--!strict

local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")

local Velocity = ecs.component("velocity", {
  fields = ecs.fields({
    linear = "vec3",
  }),
})

local Lifetime = ecs.component("lifetime", {
  fields = ecs.fields({
    remaining = "f32",
    expired = "boolean",
  }),
})

local MovingProjectiles = ecs.query(Transform, Velocity)
local LiveProjectiles = ecs.query(Lifetime)

ecs.system("move_projectiles", {
  query = MovingProjectiles,
  writes = ecs.refs(Transform),
  run = function(world, dt)
    for _entity, transform, velocity in MovingProjectiles:iter(world) do
      transform.position = {
        transform.position[1] + velocity.linear[1] * dt,
        transform.position[2] + velocity.linear[2] * dt,
        transform.position[3] + velocity.linear[3] * dt,
      }
    end
  end,
})

ecs.system("tick_lifetime", {
  query = LiveProjectiles,
  writes = ecs.refs(Lifetime),
  run = function(world, dt)
    for _entity, lifetime in LiveProjectiles:iter(world) do
      local remaining = lifetime.remaining - dt
      if remaining <= 0 then
        lifetime.remaining = 0
        lifetime.expired = true
      else
        lifetime.remaining = remaining
      end
    end
  end,
})
