--!strict

local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
local Geometry = ecs.component<<ScrapbotGeometryPrimitive>>("scrapbot.geometry.primitive")
local Material = ecs.component<<ScrapbotSurfaceMaterial>>("scrapbot.material.surface")
local ShadowCaster = ecs.component<<ScrapbotShadowCaster>>("scrapbot.shadow.caster")
local ShadowReceiver = ecs.component<<ScrapbotShadowReceiver>>("scrapbot.shadow.receiver")

local SwarmMotion = ecs.component("swarm_motion", {
  fields = ecs.fields({
    home = "vec3",
    phase = "f32",
    orbit_radius = "f32",
    speed = "f32",
  }),
})

local Swarm = ecs.query(Transform, SwarmMotion)
local elapsed = 0

local function palette(index: number): { number }
  local bucket = index % 6
  if bucket == 0 then
    return { 2.15, 0.55, 0.12 }
  elseif bucket == 1 then
    return { 0.14, 0.86, 2.3 }
  elseif bucket == 2 then
    return { 0.58, 1.85, 0.42 }
  elseif bucket == 3 then
    return { 2.45, 1.65, 0.25 }
  elseif bucket == 4 then
    return { 1.35, 0.62, 2.18 }
  else
    return { 0.1, 1.72, 1.5 }
  end
end

local function primitiveFor(index: number): (string, number, number)
  local bucket = index % 4
  if bucket == 0 then
    return "uv_sphere", 14, 8
  elseif bucket == 1 then
    return "box", 0, 0
  elseif bucket == 2 then
    return "ico_sphere", 2, 0
  else
    return "box", 0, 0
  end
end

ecs.system("spawn_swarm", {
  phase = "startup",
  writes = ecs.refs(Transform, Geometry, Material, ShadowCaster, ShadowReceiver, SwarmMotion),
  run = function(world, _dt)
    local floor = world.spawn("swarm-floor", "Swarm Floor")
    floor:add(Transform, {
      position = { 0.0, -1.25, -0.35 },
      rotation = { 0.0, 0.0, 0.0 },
      scale = { 15.5, 1.0, 10.2 },
    })
    floor:add(Geometry, {
      primitive = "plane",
      segments = 0,
      rings = 0,
    })
    floor:add(Material, {
      base_color = { 0.055, 0.078, 0.12 },
    })
    floor:add(ShadowReceiver)

    local core = world.spawn("swarm-core", "Swarm Core")
    core:add(Transform, {
      position = { 0.0, 1.02, -0.72 },
      rotation = { 0.0, 0.0, 0.0 },
      scale = { 0.34, 0.34, 0.34 },
    })
    core:add(Geometry, {
      primitive = "uv_sphere",
      segments = 24,
      rings = 12,
    })
    core:add(Material, {
      base_color = { 3.4, 1.85, 0.48 },
    })
    core:add(ShadowCaster)

    local index = 0
    for ring = 1, 8 do
      local members = 36 + ring * 14
      local ring_radius = 0.65 + ring * 0.48
      for slot = 1, members do
        index += 1
        local angle = (slot / members) * math.pi * 2.0 + ring * 0.23
        local lift = -0.76 + ring * 0.3
        local home = {
          math.cos(angle) * ring_radius * 1.18,
          lift + math.sin(slot * 0.61) * 0.24,
          -0.7 + math.sin(angle) * ring_radius * 0.82 + math.sin(angle * 2.0) * 0.18,
        }
        local primitive, segments, rings = primitiveFor(index)
        local entity = world.spawn("swarm-" .. tostring(index), "Swarm " .. tostring(index))
        local scale = 0.074 + ring * 0.006

        entity:add(Transform, {
          position = home,
          rotation = { angle * 0.25, ring * 0.18, slot * 0.07 },
          scale = { scale, scale, scale },
        })
        entity:add(Geometry, {
          primitive = primitive,
          segments = segments,
          rings = rings,
        })
        entity:add(Material, {
          base_color = palette(index),
        })
        entity:add(ShadowCaster)
        entity:add(SwarmMotion, {
          home = home,
          phase = ring * 0.71 + slot * 0.19,
          orbit_radius = 0.12 + ring * 0.028,
          speed = 0.64 + ring * 0.035 + (slot % 7) * 0.018,
        })
      end
    end
  end,
})

ecs.system("animate_swarm", {
  phase = "update",
  query = Swarm,
  writes = ecs.refs(Transform),
  run = function(world, dt)
    elapsed += dt

    local view = Swarm:view(world)
    local count = view:count()
    local homes = view:read_vec3(SwarmMotion, "home")
    local phases = view:read_f32(SwarmMotion, "phase")
    local orbit_radii = view:read_f32(SwarmMotion, "orbit_radius")
    local speeds = view:read_f32(SwarmMotion, "speed")
    local positions = view:read_vec3(Transform, "position")
    local rotations = view:read_vec3(Transform, "rotation")

    for index = 0, count - 1 do
      local f32_offset = index * 4
      local vec3_offset = index * 12
      local home_x = buffer.readf32(homes, vec3_offset)
      local home_y = buffer.readf32(homes, vec3_offset + 4)
      local home_z = buffer.readf32(homes, vec3_offset + 8)
      local rotation_x = buffer.readf32(rotations, vec3_offset)
      local rotation_y = buffer.readf32(rotations, vec3_offset + 4)
      local rotation_z = buffer.readf32(rotations, vec3_offset + 8)
      local speed = buffer.readf32(speeds, f32_offset)
      local orbit_radius = buffer.readf32(orbit_radii, f32_offset)
      local t = elapsed * speed + buffer.readf32(phases, f32_offset)
      local orbit_x = math.cos(t) * orbit_radius
      local orbit_z = math.sin(t * 0.91) * orbit_radius
      local bob = math.sin(t * 1.7) * 0.18

      buffer.writef32(positions, vec3_offset, home_x + orbit_x)
      buffer.writef32(positions, vec3_offset + 4, home_y + bob)
      buffer.writef32(positions, vec3_offset + 8, home_z + orbit_z)

      buffer.writef32(rotations, vec3_offset, rotation_x + dt * (0.55 + speed * 0.35))
      buffer.writef32(rotations, vec3_offset + 4, rotation_y + dt * (0.9 + orbit_radius))
      buffer.writef32(rotations, vec3_offset + 8, rotation_z + dt * (0.25 + math.sin(t) * 0.2))
    end

    view:write_vec3(Transform, "position", positions)
    view:write_vec3(Transform, "rotation", rotations)
  end,
})
