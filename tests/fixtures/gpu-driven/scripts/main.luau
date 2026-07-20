local cube = scrapbot.geometry.cube("stress_cube", 0.35)
local occluder_material = scrapbot.material.lit("stress_occluder", 0.2, 0.9, 0.35, 1.0)
local hidden_material = scrapbot.material.lit("hidden_stress_material", 1.0, 0.0, 0.0, 1.0)
local spawned = false
local hidden_index = 0


scrapbot.system({
	name = "spawn_gpu_stress",
	writes = { scrapbot.transform, scrapbot.geometry_component, scrapbot.material_component },
}, function()
	if not spawned then
		spawned = true
		for row = 0, 8 do
			for column = 0, 8 do
			local material = scrapbot.material.lit(
				string.format("stress_material_%d_%d", row, column),
				0.15 + row * 0.01,
				0.62 + column * 0.01,
				1.0,
				1.0
			)
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
		scrapbot.spawn({
			name = "GPU Occluder",
			components = {
				["scrapbot.transform"] = {
					position = { x = 0, y = 0, z = 0 },
					scale = { x = 8, y = 8, z = 0.5 },
				},
				["scrapbot.geometry"] = cube,
				["scrapbot.material"] = occluder_material,
			},
		})
	end
	local last_hidden = math.min(hidden_index + 39, 299)
	for index = hidden_index, last_hidden do
		local row = math.floor(index / 9) % 9
		local column = index % 9
		scrapbot.spawn({
			name = "Occluded GPU Instance",
			components = {
				["scrapbot.transform"] = {
					position = { x = (column - 4) * 0.05, y = (row - 4) * 0.05, z = -2 },
					scale = { x = 0.2, y = 0.2, z = 0.2 },
				},
				["scrapbot.geometry"] = cube,
				["scrapbot.material"] = hidden_material,
			},
		})
	end
	hidden_index = last_hidden + 1
end)
