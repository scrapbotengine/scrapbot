local GRID_CELLS_X = 384
local GRID_CELLS_Y = 256
local GRID_WIDTH = 18
local GRID_HEIGHT = 11

local LabCamera = scrapbot.component("virtual_geometry_lab_camera", {
	start_distance = scrapbot.number,
	end_distance = scrapbot.number,
	approach_frames = scrapbot.number,
}, { advanced = true }) :: VirtualGeometryLabCameraComponent

local Cameras = scrapbot.query(scrapbot.transform, LabCamera)
scrapbot.system(Cameras, {
	name = "virtual_geometry_lab_camera",
	writes = { scrapbot.transform },
	reads = { LabCamera },
}, function(
	time: ScrapbotTime,
	_entity: ScrapbotEntity,
	transform: ScrapbotTransform,
	camera: VirtualGeometryLabCamera
)
	local duration = math.max(1, math.floor(camera.approach_frames))
	local phase = ((time.frame_index - 1) % duration) / (duration - 1)
	local eased = phase * phase * (3 - 2 * phase)
	transform.position.z = camera.start_distance +
		(camera.end_distance - camera.start_distance) * eased
	transform.position.x = math.sin(phase * math.pi * 2) * 0.35
	transform.position.y = math.sin(phase * math.pi) * 0.18
end)

local function coverage_wall_descriptor()
	local vertices = {}
	local indices = {}
	local stride = GRID_CELLS_X + 1
	for row = 0, GRID_CELLS_Y do
		local v = row / GRID_CELLS_Y
		local y = (v - 0.5) * GRID_HEIGHT
		for column = 0, GRID_CELLS_X do
			local u = column / GRID_CELLS_X
			local x = (u - 0.5) * GRID_WIDTH
			local z =
				math.sin(x * 11.3 + y * 0.7) * 0.22 +
				math.sin(y * 13.1 - x * 0.4) * 0.16 +
				math.sin((x + y) * 5.7) * 0.08
			table.insert(vertices, {
				position = { x = x, y = y, z = z },
				normal = { x = 0, y = 0, z = 1 },
				uv = { x = u, y = v },
			})
		end
	end
	for row = 0, GRID_CELLS_Y - 1 do
		for column = 0, GRID_CELLS_X - 1 do
			local top_left = row * stride + column
			local top_right = top_left + 1
			local bottom_left = top_left + stride
			local bottom_right = bottom_left + 1
			table.insert(indices, top_left)
			table.insert(indices, top_right)
			table.insert(indices, bottom_right)
			table.insert(indices, top_left)
			table.insert(indices, bottom_right)
			table.insert(indices, bottom_left)
		end
	end
	return { vertices = vertices, indices = indices }
end

local geometry = scrapbot.geometry.create(
	"virtual_geometry_lab_coverage_wall",
	coverage_wall_descriptor()
)
local material = scrapbot.material.lit(
	"virtual_geometry_lab_coverage_material",
	0.18,
	0.72,
	0.92,
	1
)

local spawned = false
scrapbot.system({
	name = "spawn_virtual_geometry_lab",
	writes = {
		scrapbot.transform,
		scrapbot.geometry_component,
		scrapbot.material_component,
	},
}, function(time: ScrapbotTime)
	if spawned or time.frame_index ~= 1 then
		return
	end
	spawned = true
	scrapbot.spawn({
		name = "Dense Coverage Wall",
		components = {
			["scrapbot.transform"] = {
				position = { x = 0, y = 0, z = 0 },
				rotation = { x = 0, y = 0, z = 0 },
				scale = { x = 5, y = 7, z = 4 },
			},
			["scrapbot.geometry"] = geometry,
			["scrapbot.material"] = material,
		},
	})
end)
