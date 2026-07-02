--!strict


local Transform = ecs.component<<MachinaTransform>>("machina.transform")
local RenderCube = ecs.component<<MachinaRenderCube>>("machina.render.cube")
local AutoRotate = ecs.component("spin", {
  fields = ecs.fields({
    angular_velocity = "vec3",
  }),
})

local RotatingCubes = ecs.query(Transform, AutoRotate)
local RenderedCubes = ecs.query(Transform, RenderCube)

ecs.system("autorotate", {
  phase = "update",
  query = RotatingCubes,
  writes = ecs.refs(Transform),
  run = function(world, dt)
    for _entity, transform, spin in RotatingCubes:iter(world) do
      transform.rotation = {
        transform.rotation[1] + spin.angular_velocity[1] * dt,
        transform.rotation[2] + spin.angular_velocity[2] * dt,
        transform.rotation[3] + spin.angular_velocity[3] * dt,
      }
    end
  end,
})

ecs.system("observe_cubes", {
  phase = "update",
  query = RenderedCubes,
  after = { "autorotate" },
})
