--!strict

local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
local Geometry = ecs.component<<ScrapbotGeometryPrimitive>>("scrapbot.geometry.primitive")
local Material = ecs.component<<ScrapbotSurfaceMaterial>>("scrapbot.material.surface")
local DirectionalLight = ecs.component<<ScrapbotDirectionalLight>>("scrapbot.light.directional")

local Spin = ecs.component("spin", {
  fields = ecs.fields({
    angular_velocity = "vec3",
  }),
})

local Bob = ecs.component("bob", {
  fields = ecs.fields({
    base_position = "vec3",
    amplitude = "f32",
    speed = "f32",
    phase = "f32",
  }),
})

local LightPulse = ecs.component("light_pulse", {
  fields = ecs.fields({
    phase = "f32",
    speed = "f32",
    amplitude = "f32",
    base_intensity = "f32",
  }),
})

local SpinningCubes = ecs.query(Transform, Spin)
local FloatingCubes = ecs.query(Transform, Bob)
local PulsingLights = ecs.query(DirectionalLight, LightPulse)
local RenderedMeshes = ecs.query(Transform, Geometry, Material)

ecs.system("rotate_cubes", {
  phase = "update",
  query = SpinningCubes,
  writes = ecs.refs(Transform),
  run = function(world, dt)
    for _entity, transform, spin in SpinningCubes:iter(world) do
      transform.rotation = {
        transform.rotation[1] + spin.angular_velocity[1] * dt,
        transform.rotation[2] + spin.angular_velocity[2] * dt,
        transform.rotation[3] + spin.angular_velocity[3] * dt,
      }
    end
  end,
})

ecs.system("float_cubes", {
  phase = "update",
  query = FloatingCubes,
  writes = ecs.refs(Transform, Bob),
  after = { "rotate_cubes" },
  run = function(world, dt)
    for _entity, transform, bob in FloatingCubes:iter(world) do
      local next_phase = bob.phase + bob.speed * dt
      bob.phase = next_phase
      transform.position = {
        bob.base_position[1],
        bob.base_position[2] + math.sin(next_phase) * bob.amplitude,
        bob.base_position[3],
      }
    end
  end,
})

ecs.system("pulse_key_light", {
  phase = "update",
  query = PulsingLights,
  writes = ecs.refs(DirectionalLight, LightPulse),
  run = function(world, dt)
    for _entity, light, pulse in PulsingLights:iter(world) do
      local next_phase = pulse.phase + pulse.speed * dt
      pulse.phase = next_phase
      light.intensity = pulse.base_intensity + math.sin(next_phase) * pulse.amplitude
    end
  end,
})

ecs.system("observe_rendered_meshes", {
  phase = "update",
  query = RenderedMeshes,
  after = { "float_cubes", "pulse_key_light" },
})
