local GRID_CELLS = 128
local GRID_SIZE = 48

local function pressure_grid_descriptor()
	local vertices = {}
	local indices = {}
	local stride = GRID_CELLS + 1
	for row = 0, GRID_CELLS do
		for column = 0, GRID_CELLS do
			local x = (column / GRID_CELLS - 0.5) * GRID_SIZE
			local y = (row / GRID_CELLS - 0.5) * GRID_SIZE
			table.insert(vertices, {
				position = { x = x, y = y, z = 0 },
				normal = { x = 0, y = 0, z = 1 },
				uv = { x = column / GRID_CELLS, y = row / GRID_CELLS },
			})
		end
	end
	for row = 0, GRID_CELLS - 1 do
		for column = 0, GRID_CELLS - 1 do
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
	return {
		vertices = vertices,
		indices = indices,
	}
end

local PressureCamera = scrapbot.component("virtual_geometry_pressure_camera", {
	start_x = scrapbot.number,
	step_x = scrapbot.number,
	position_count = scrapbot.number,
	dwell_frames = scrapbot.number,
}, { advanced = true }) :: VirtualGeometryPressureCameraComponent

local Cameras = scrapbot.query(scrapbot.transform, PressureCamera)
scrapbot.system(Cameras, {
	name = "virtual_geometry_pressure_camera",
	writes = { scrapbot.transform },
	reads = { PressureCamera },
}, function(
	time: ScrapbotTime,
	_entity: ScrapbotEntity,
	transform: ScrapbotTransform,
	pressure: VirtualGeometryPressureCamera
)
	local position_count = math.max(1, math.floor(pressure.position_count))
	local dwell = math.max(1, math.floor(pressure.dwell_frames))
	local cycle_frames = position_count * dwell
	local position = ((time.frame_index - 1) % cycle_frames) / dwell
	transform.position.x = pressure.start_x + pressure.step_x * position
end)

local descriptor = pressure_grid_descriptor()
local geometries = {}
for index = 1, 8 do
	table.insert(geometries, scrapbot.geometry.create(
		string.format("virtual_geometry_pressure_grid_%d", index),
		descriptor
	))
end
local material = scrapbot.material.lit("virtual_geometry_pressure_material", 0.18, 0.7, 0.95, 1)
local spawned = false
scrapbot.system({
	name = "spawn_virtual_geometry_pressure_grid",
	writes = { scrapbot.transform, scrapbot.geometry_component, scrapbot.material_component },
}, function(time: ScrapbotTime)
	if spawned or time.frame_index ~= 1 then return end
	spawned = true
	for index, geometry in geometries do
		scrapbot.spawn({
			name = string.format("Virtual Geometry Pressure Grid %d", index),
			components = {
				["scrapbot.transform"] = {
					position = { x = -154 + (index - 1) * 44, y = 0, z = 0 },
					scale = { x = 1, y = 1, z = 1 },
				},
				["scrapbot.geometry"] = geometry,
				["scrapbot.material"] = material,
			},
		})
	end
end)
