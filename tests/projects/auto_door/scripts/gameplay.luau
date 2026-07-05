--!strict

local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")

local Switch = ecs.component("switch", {
  fields = ecs.fields({
    active = "boolean",
  }),
})

local Door = ecs.component("door", {
  fields = ecs.fields({
    openness = "f32",
    target = "f32",
    speed = "f32",
  }),
})

local Switches = ecs.query(Switch)
local Doors = ecs.query(Transform, Door)

ecs.system("drive_doors", {
  query = Doors,
  reads = ecs.refs(Switch),
  writes = ecs.refs(Transform, Door),
  run = function(world, dt)
    local any_active = false
    for _entity, switch in Switches:iter(world) do
      if switch.active then
        any_active = true
      end
    end

    for _entity, transform, door in Doors:iter(world) do
      local target = if any_active then door.target else 0
      local next_openness = door.openness
      if next_openness < target then
        next_openness = next_openness + door.speed * dt
        if next_openness > target then
          next_openness = target
        end
      elseif next_openness > target then
        next_openness = next_openness - door.speed * dt
        if next_openness < target then
          next_openness = target
        end
      end

      door.openness = next_openness
      transform.rotation = {
        transform.rotation[1],
        transform.rotation[2],
        next_openness * 1.5708,
      }
    end
  end,
})
