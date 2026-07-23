local TAU = math.pi * 2
local RING_COUNT = 20
local LIGHTS_PER_RING = 16
local LIGHT_COUNT = RING_COUNT * LIGHTS_PER_RING

local LightMotion = scrapbot.component("light_motion", {
	center = scrapbot.vec3,
	base_angle = scrapbot.number,
	radius_x = scrapbot.number,
	radius_y = scrapbot.number,
	speed = scrapbot.number,
	phase = scrapbot.number,
	base_intensity = scrapbot.number,
}, { advanced = true }) :: LightMotionComponent

local CameraDrift = scrapbot.component("camera_drift", {
	origin = scrapbot.vec3,
}) :: CameraDriftComponent

local SculptureSpin = scrapbot.component("sculpture_spin", {
	speed = scrapbot.vec3,
}) :: SculptureSpinComponent

local LightMarkerGeometry = scrapbot.geometry.sphere("cluster.marker", 0.11, 10, 6)
local ArchitectureGeometry = scrapbot.geometry.cube("cluster.architecture", 1)
local SculptureGeometry = scrapbot.geometry.icosphere("cluster.sculpture", 0.8, 1)
local DarkMaterial = scrapbot.material.lit("cluster.dark", 0.18, 0.2, 0.27, 1)
local MidMaterial = scrapbot.material.lit("cluster.mid", 0.32, 0.35, 0.45, 1)
local SculptureMaterial = scrapbot.material.lit("cluster.sculpture", 0.45, 0.48, 0.58, 1)

local function hsv_to_rgb(hue: number, saturation: number, value: number)
	local sector = math.floor(hue * 6)
	local fraction = hue * 6 - sector
	local p = value * (1 - saturation)
	local q = value * (1 - fraction * saturation)
	local t = value * (1 - (1 - fraction) * saturation)
	local wrapped = sector % 6
	if wrapped == 0 then return { r = value, g = t, b = p } end
	if wrapped == 1 then return { r = q, g = value, b = p } end
	if wrapped == 2 then return { r = p, g = value, b = t } end
	if wrapped == 3 then return { r = p, g = q, b = value } end
	if wrapped == 4 then return { r = t, g = p, b = value } end
	return { r = value, g = p, b = q }
end

local Palette = {}
local MarkerMaterials = {}
for index = 1, 12 do
	local color = hsv_to_rgb((index - 1) / 12, 0.82, 1)
	Palette[index] = color
	MarkerMaterials[index] = scrapbot.material.emissive(
		string.format("cluster.neon.%02d", index),
		color.r,
		color.g,
		color.b,
		3.8
	)
end

local function spawn_block(
	name: string,
	x: number,
	y: number,
	z: number,
	scale_x: number,
	scale_y: number,
	scale_z: number,
	material: any
)
	scrapbot.spawn({
		name = name,
		components = {
			["scrapbot.transform"] = {
				position = { x = x, y = y, z = z },
				scale = { x = scale_x, y = scale_y, z = scale_z },
			},
			["scrapbot.geometry"] = ArchitectureGeometry,
			["scrapbot.material"] = material,
			["scrapbot.shadow_caster"] = {},
			["scrapbot.shadow_receiver"] = {},
		},
	})
end

scrapbot.system({
	name = "build_cathedral",
	writes = {
		scrapbot.transform,
		scrapbot.geometry_component,
		scrapbot.material_component,
		scrapbot.point_light,
		scrapbot.shadow_caster,
		scrapbot.shadow_receiver,
		LightMotion,
		SculptureSpin,
	},
}, function(time: ScrapbotTime)
	-- Stop replaces the ECS world without reloading this Luau environment.
	-- Build from world-relative state so every fresh playback world gets the demo.
	if time.frame_index ~= 1 then return end

	spawn_block("Cathedral Floor", 0, -0.35, -19, 10, 0.25, 27, DarkMaterial)
	spawn_block("Cathedral Ceiling", 0, 8.35, -19, 10, 0.2, 27, DarkMaterial)
	spawn_block("Cathedral Left Wall", -10.15, 4, -19, 0.2, 4.2, 27, DarkMaterial)
	spawn_block("Cathedral Right Wall", 10.15, 4, -19, 0.2, 4.2, 27, DarkMaterial)
	spawn_block("Cathedral End Wall", 0, 4, -46, 10, 4.2, 0.25, DarkMaterial)

	for ring = 0, RING_COUNT - 1 do
		local z = 3 - ring * 3.25
		local rib_material = if ring % 2 == 0 then MidMaterial else DarkMaterial
		spawn_block("Left Rib", -8.7, 3.45, z, 0.3, 3.45, 0.3, rib_material)
		spawn_block("Right Rib", 8.7, 3.45, z, 0.3, 3.45, 0.3, rib_material)
		spawn_block("Ceiling Rib", 0, 7.15, z, 8.7, 0.28, 0.3, rib_material)

		for pedestal = -1, 1 do
			local x = pedestal * 4.8
			local height = 0.3 + ((ring + pedestal + 3) % 4) * 0.18
			spawn_block("Floor Prism", x, height * 0.5 - 0.08, z, 0.62, height, 0.62, MidMaterial)
		end

		if ring % 2 == 0 then
			scrapbot.spawn({
				name = "Suspended Sculpture",
				components = {
					["scrapbot.transform"] = {
						position = {
							x = math.sin(ring * 1.7) * 2.4,
							y = 3.1 + math.cos(ring * 0.9) * 0.7,
							z = z - 1.45,
						},
						rotation = { x = ring * 0.17, y = ring * 0.29, z = 0 },
						scale = { x = 0.72, y = 0.72, z = 0.72 },
					},
					["scrapbot.geometry"] = SculptureGeometry,
					["scrapbot.material"] = SculptureMaterial,
					["scrapbot.shadow_caster"] = {},
					["scrapbot.shadow_receiver"] = {},
					sculpture_spin = {
						speed = {
							x = 0.09 + ring * 0.004,
							y = 0.18 + ring * 0.007,
							z = 0.055,
						},
					},
				},
			})
		end

		for light_index = 0, LIGHTS_PER_RING - 1 do
			local inner_orbit = light_index >= 12
			local orbit_index = if inner_orbit then light_index - 12 else light_index
			local orbit_count = if inner_orbit then 4 else 12
			local base_angle = orbit_index / orbit_count * TAU + if inner_orbit then ring * 0.19 else 0
			local palette_index = (light_index + ring * 3) % #Palette + 1
			local color = Palette[palette_index]
			local radius_x = if inner_orbit then 2.55 else 7.45 + math.sin(ring * 0.8) * 0.35
			local radius_y = if inner_orbit then 1.35 else 3.0 + math.cos(ring * 0.65) * 0.22
			local center_y = if inner_orbit then 2.15 else 3.8
			local direction = if ring % 2 == 0 then 1 else -1
			local speed_scale = if inner_orbit then 1.7 else 1
			local speed = direction * (0.12 + (ring % 4) * 0.018) * speed_scale
			local phase = ring * 0.73 + light_index * 0.31
			local base_intensity = 21 + (light_index % 4) * 2.5
			local light_range = if inner_orbit then 5.4 else 6.4
			scrapbot.spawn({
				name = string.format("Cluster Light %03d", ring * LIGHTS_PER_RING + light_index + 1),
				components = {
					["scrapbot.transform"] = {
						position = {
							x = math.cos(base_angle) * radius_x,
							y = center_y + math.sin(base_angle) * radius_y,
							z = z,
						},
						scale = { x = 1, y = 1, z = 1 },
					},
					["scrapbot.geometry"] = LightMarkerGeometry,
					["scrapbot.material"] = MarkerMaterials[palette_index],
					["scrapbot.point_light"] = {
						color = { x = color.r, y = color.g, z = color.b },
						intensity = base_intensity,
						range = light_range,
					},
					light_motion = {
						center = { x = 0, y = center_y, z = z },
						base_angle = base_angle,
						radius_x = radius_x,
						radius_y = radius_y,
						speed = speed,
						phase = phase,
						base_intensity = base_intensity,
					},
				},
			})
		end
	end

	scrapbot.log(string.format("Cluster Cathedral: %d animated GPU-clustered point lights", LIGHT_COUNT))
end)

local MovingLights = scrapbot.query(scrapbot.transform, scrapbot.point_light, LightMotion)
scrapbot.system(MovingLights, {
	name = "animate_lights",
	writes = { scrapbot.transform },
	reads = { scrapbot.point_light, LightMotion },
}, function(
	time: ScrapbotTime,
	_entity: ScrapbotEntity,
	transform: ScrapbotTransform,
	_light: ReadonlyScrapbotPointLight,
	motion: LightMotion
)
	local angle = motion.base_angle + time.elapsed_time * motion.speed
	local shimmer = math.sin(time.elapsed_time * 0.47 + motion.phase)
	transform.position.x = motion.center.x + math.cos(angle) * (motion.radius_x + shimmer * 0.22)
	transform.position.y = motion.center.y + math.sin(angle) * motion.radius_y
	transform.position.z = motion.center.z + math.sin(angle * 2 + time.elapsed_time * 0.31) * 0.38
	local traveling_wave = math.sin(time.elapsed_time * 2.35 - motion.center.z * 0.42 + motion.phase)
	local sparkle = math.sin(time.elapsed_time * 5.1 + motion.phase * 2.7)
	local marker_scale = 0.9 + traveling_wave * 0.18 + sparkle * 0.08
	transform.scale.x = marker_scale
	transform.scale.y = marker_scale
	transform.scale.z = marker_scale
end)

local SpinningSculptures = scrapbot.query(scrapbot.transform, SculptureSpin)
scrapbot.system(SpinningSculptures, {
	name = "spin_sculptures",
	writes = { scrapbot.transform },
	reads = { SculptureSpin },
}, function(
	time: ScrapbotTime,
	_entity: ScrapbotEntity,
	transform: ScrapbotTransform,
	spin: SculptureSpin
)
	transform.rotation.x += spin.speed.x * time.delta_time
	transform.rotation.y += spin.speed.y * time.delta_time
	transform.rotation.z += spin.speed.z * time.delta_time
end)

local Cameras = scrapbot.query(scrapbot.transform, CameraDrift)
scrapbot.system(Cameras, {
	name = "camera_drift",
	writes = { scrapbot.transform },
	reads = { CameraDrift },
}, function(
	time: ScrapbotTime,
	_entity: ScrapbotEntity,
	transform: ScrapbotTransform,
	drift: CameraDrift
)
	transform.position.x = drift.origin.x + math.sin(time.elapsed_time * 0.16) * 1.15
	transform.position.y = drift.origin.y + math.sin(time.elapsed_time * 0.23) * 0.32
	transform.position.z = drift.origin.z + math.sin(time.elapsed_time * 0.11) * 0.8
	transform.rotation.x = -0.02 + math.sin(time.elapsed_time * 0.19) * 0.018
	transform.rotation.y = math.sin(time.elapsed_time * 0.13) * 0.055
end)
