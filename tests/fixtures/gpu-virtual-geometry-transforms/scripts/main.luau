local TransformCamera = scrapbot.component("virtual_geometry_transform_camera", {
	horizontal_amplitude = scrapbot.number,
	vertical_amplitude = scrapbot.number,
	yaw_amplitude = scrapbot.number,
}, { advanced = true }) :: VirtualGeometryTransformCameraComponent

local Cameras = scrapbot.query(scrapbot.transform, TransformCamera)
scrapbot.system(Cameras, {
	name = "virtual_geometry_transform_camera",
	writes = { scrapbot.transform },
	reads = { TransformCamera },
}, function(
	time: ScrapbotTime,
	_entity: ScrapbotEntity,
	transform: ScrapbotTransform,
	camera: VirtualGeometryTransformCamera
)
	local phase = time.elapsed_time * 0.8
	transform.position.x = math.sin(phase) * camera.horizontal_amplitude
	transform.position.y = math.sin(phase * 0.73) * camera.vertical_amplitude
	transform.rotation.y = math.sin(phase * 0.61) * camera.yaw_amplitude
end)

local geometry = scrapbot.geometry.icosphere(
	"virtual_geometry_transform_icosphere",
	1,
	4
)
local material = scrapbot.material.lit(
	"virtual_geometry_transform_material",
	0.12,
	0.74,
	0.92,
	1
)

local instances = {
	{
		name = "Tall Left",
		position = { x = -3.3, y = 0.2, z = 0 },
		rotation = { x = 0.28, y = 0.41, z = -0.17 },
		scale = { x = 0.12, y = 6.4, z = 0.48 },
	},
	{
		name = "Wide Center",
		position = { x = 0, y = 0, z = -0.45 },
		rotation = { x = -0.22, y = 0.65, z = 0.31 },
		scale = { x = 6.2, y = 0.14, z = 0.62 },
	},
	{
		name = "Deep Right",
		position = { x = 3.35, y = -0.1, z = 0.15 },
		rotation = { x = 0.47, y = -0.52, z = 0.19 },
		scale = { x = 0.16, y = 0.58, z = 6.1 },
	},
}

local spawned = false
scrapbot.system({
	name = "spawn_virtual_geometry_transform_fixture",
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
	for _, instance in instances do
		scrapbot.spawn({
			name = instance.name,
			components = {
				["scrapbot.transform"] = {
					position = instance.position,
					rotation = instance.rotation,
					scale = instance.scale,
				},
				["scrapbot.geometry"] = geometry,
				["scrapbot.material"] = material,
			},
		})
	end
end)
