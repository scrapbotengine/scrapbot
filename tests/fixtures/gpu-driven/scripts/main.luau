local cube = scrapbot.geometry.cube("stress_cube", 0.35)
local material = scrapbot.material.lit("stress_material", 0.15, 0.7, 1.0, 1.0)
local spawned = false


scrapbot.system({
	name = "spawn_gpu_stress",
	writes = { scrapbot.transform, scrapbot.geometry_component, scrapbot.material_component },
}, function()
	if spawned then
		return
	end
	spawned = true
	for row = 0, 8 do
		for column = 0, 8 do
			scrapbot.spawn({
				name = "GPU Instance",
				components = {
					["scrapbot.transform"] = {
						position = { x = (column - 4) * 0.7, y = (row - 4) * 0.7, z = 0 },
						scale = { x = 1, y = 1, z = 1 },
					},
					["scrapbot.geometry"] = cube,
					["scrapbot.material"] = material,
				},
			})
		end
	end
end)
