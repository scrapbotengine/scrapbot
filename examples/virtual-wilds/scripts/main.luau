local WildsCamera = scrapbot.component("wilds_camera", {
	origin = scrapbot.vec3,
	travel = scrapbot.number,
	duration = scrapbot.number,
	lead_in = scrapbot.number,
}, { advanced = true }) :: WildsCameraComponent

local Cameras = scrapbot.query(scrapbot.transform, WildsCamera)

scrapbot.system(Cameras, {
	name = "virtual_wilds.camera",
	writes = { scrapbot.transform },
	reads = { WildsCamera },
}, function(
	time: ScrapbotTime,
	_entity: ScrapbotEntity,
	transform: ScrapbotTransform,
	camera: WildsCamera
)
	local duration = math.max(camera.duration, 0.001)
	local tour_frames = math.max(duration * 60, 1)
	local lead_in_frames = math.max(camera.lead_in * 60, 0)
	local cycle_frames = tour_frames + lead_in_frames
	local cycle_frame = (time.frame_index - 1) % cycle_frames
	local progress = math.max(cycle_frame - lead_in_frames, 0) / tour_frames
	local eased = progress * progress * (3 - 2 * progress)
	local passage = math.sin(progress * math.pi)

	transform.position.x = camera.origin.x + math.sin(progress * math.pi * 3) * 3.2 * passage
	transform.position.y = camera.origin.y + math.sin(progress * math.pi * 2) * 0.8 + eased * 2.2
	transform.position.z = camera.origin.z - camera.travel * eased
	transform.rotation.x = -0.08 + math.sin(progress * math.pi * 2) * 0.025
	transform.rotation.y = math.sin(progress * math.pi * 3 + 0.35) * 0.11 * passage
end)

local scatterRock = scrapbot.geometry.icosphere("wilds_scatter_rock", 1, 1)
local scatterTrunk = scrapbot.geometry.cylinder("wilds_scatter_trunk", 0.34, 2.8, 8)
local function coniferCrownDescriptor()
	local vertices = {}
	local indices = {}
	local segments = 12
	for segment = 0, segments - 1 do
		local angle0 = segment / segments * math.pi * 2
		local angle1 = (segment + 1) / segments * math.pi * 2
		local middle = (angle0 + angle1) * 0.5
		local normal = {
			x = math.cos(middle) * 0.9,
			y = 0.44,
			z = math.sin(middle) * 0.9,
		}
		local base = #vertices
		table.insert(vertices, {
			position = { x = 0, y = 1, z = 0 },
			normal = normal,
			uv = { x = 0.5, y = 0 },
		})
		table.insert(vertices, {
			position = { x = math.cos(angle0), y = -1, z = math.sin(angle0) },
			normal = normal,
			uv = { x = 0, y = 1 },
		})
		table.insert(vertices, {
			position = { x = math.cos(angle1), y = -1, z = math.sin(angle1) },
			normal = normal,
			uv = { x = 1, y = 1 },
		})
		table.insert(indices, base)
		table.insert(indices, base + 1)
		table.insert(indices, base + 2)
	end
	return { vertices = vertices, indices = indices }
end
local scatterCrown = scrapbot.geometry.create("wilds_scatter_crown", coniferCrownDescriptor())
local scatterRockMaterial = scrapbot.material.lit("wilds_scatter_rock", 0.14, 0.13, 0.11, 1)
local scatterTrunkMaterial = scrapbot.material.lit("wilds_scatter_trunk", 0.11, 0.065, 0.035, 1)
local scatterCrownMaterial = scrapbot.material.lit("wilds_scatter_crown", 0.045, 0.2, 0.09, 1)

local scatterState = 0x28c4a11
local function scatterRandom(): number
	scatterState = bit32.bxor(scatterState, bit32.lshift(scatterState, 13))
	scatterState = bit32.bxor(scatterState, bit32.rshift(scatterState, 17))
	scatterState = bit32.bxor(scatterState, bit32.lshift(scatterState, 5))
	return bit32.band(scatterState, 0xffffffff) / 0x100000000
end

local function scatterBetween(minimum: number, maximum: number): number
	return minimum + (maximum - minimum) * scatterRandom()
end

local function scatterSide(): number
	if scatterRandom() < 0.5 then
		return -1
	end
	return 1
end

local function spawnScatterRenderable(
	name: string,
	geometry: ScrapbotGeometryResource,
	material: ScrapbotMaterialResource,
	position: Vec3,
	rotation: Vec3,
	scale: Vec3
)
	scrapbot.spawn({
		name = name,
		components = {
			["scrapbot.transform"] = {
				position = position,
				rotation = rotation,
				scale = scale,
			},
			["scrapbot.geometry"] = geometry,
			["scrapbot.material"] = material,
			["scrapbot.shadow_receiver"] = {},
		},
	})
end

local scatterSpawned = false
scrapbot.system({
	name = "virtual_wilds.scatter",
	writes = {
		scrapbot.transform,
		scrapbot.geometry_component,
		scrapbot.material_component,
		scrapbot.shadow_receiver,
	},
}, function(time: ScrapbotTime)
	if scatterSpawned or time.frame_index ~= 1 then
		return
	end
	scatterSpawned = true

	for index = 1, 220 do
		local side = scatterSide()
		local lateral = scatterBetween(11, 39)
		local size = scatterBetween(0.38, 1.55)
		spawnScatterRenderable(
			string.format("Scatter Rock %03d", index),
			scatterRock,
			scatterRockMaterial,
			{
				x = side * lateral,
				y = -0.15 + (lateral - 11) * 0.18 + scatterBetween(-0.35, 0.25),
				z = scatterBetween(-198, 30),
			},
			{
				x = scatterBetween(-0.18, 0.18),
				y = scatterBetween(-math.pi, math.pi),
				z = scatterBetween(-0.18, 0.18),
			},
			{
				x = size * scatterBetween(0.85, 1.4),
				y = size * scatterBetween(0.65, 1.15),
				z = size * scatterBetween(0.85, 1.4),
			}
		)
	end

	for index = 1, 80 do
		local side = scatterSide()
		local lateral = scatterBetween(18, 38)
		local height = scatterBetween(2.8, 5.6)
		local x = side * lateral
		local y = 1.5 + (lateral - 12) * 0.2 + scatterBetween(-0.2, 0.35)
		local z = scatterBetween(-194, 25)
		local yaw = scatterBetween(-math.pi, math.pi)

		spawnScatterRenderable(
			string.format("Scatter Pine Trunk %03d", index),
			scatterTrunk,
			scatterTrunkMaterial,
			{ x = x, y = y + height * 0.24, z = z },
			{ x = 0, y = yaw, z = 0 },
			{ x = height * 0.14, y = height * 0.34, z = height * 0.14 }
		)
		spawnScatterRenderable(
			string.format("Scatter Pine Lower Crown %03d", index),
			scatterCrown,
			scatterCrownMaterial,
			{ x = x, y = y + height * 0.67, z = z },
			{ x = 0, y = yaw, z = 0 },
			{ x = height * 0.34, y = height * 0.39, z = height * 0.34 }
		)
		spawnScatterRenderable(
			string.format("Scatter Pine Upper Crown %03d", index),
			scatterCrown,
			scatterCrownMaterial,
			{
				x = x + scatterBetween(-0.12, 0.12),
				y = y + height * 0.98,
				z = z + scatterBetween(-0.12, 0.12),
			},
			{ x = 0, y = yaw + 0.7, z = 0 },
			{ x = height * 0.22, y = height * 0.3, z = height * 0.22 }
		)
	end
end)
