local CELLS_X = 50
local CELLS_Y = 26
local CELLS_Z = 50
local VOXEL_SIZE = 0.24
local ORIGIN = { x = -6, y = -2.5, z = -6 }
local TERRAIN_ENTITY = "98000000-0000-4000-8000-000000000004"

local densities = {}

local function sphere_density(x: number, y: number, z: number, radius: number): number
	return radius - math.sqrt(x * x + y * y + z * z)
end

local function smooth_min(a: number, b: number, radius: number): number
	local blend = math.clamp(0.5 + 0.5 * (b - a) / radius, 0, 1)
	return b + (a - b) * blend - radius * blend * (1 - blend)
end

local function smooth_max(a: number, b: number, radius: number): number
	return -smooth_min(-a, -b, radius)
end

for z_index = 0, CELLS_Z do
	local z = ORIGIN.z + z_index * VOXEL_SIZE
	for y_index = 0, CELLS_Y do
		local y = ORIGIN.y + y_index * VOXEL_SIZE
		for x_index = 0, CELLS_X do
			local x = ORIGIN.x + x_index * VOXEL_SIZE

			local hill = 3.2 * math.exp(-(x * x + z * z) / 24)
			local ridges = math.sin(x * 0.62 + math.sin(z * 0.31) * 1.4) * 0.42
			local detail = math.sin(x * 1.52 - z * 1.08) * 0.1
			local density = hill + ridges + detail - 0.82 - y

			-- A genuine tunnel through the central hill: impossible for a heightfield.
			local tunnel_x = x + math.sin(z * 0.3) * 0.34
			local tunnel_y = y - 0.12 - math.sin(z * 0.22) * 0.14
			local tunnel = math.sqrt(tunnel_x * tunnel_x + tunnel_y * tunnel_y) - 1.5
			density = smooth_min(density, tunnel, 0.32)

			-- A freestanding stone arch joined into the landscape.
			local arch_x = x + 3.25
			local arch_y = y - 1.05
			local arch_ring = math.sqrt(arch_x * arch_x + arch_y * arch_y)
			local arch = 0.62 - math.sqrt((arch_ring - 1.8) ^ 2 + (z + 1.25) ^ 2)
			density = smooth_max(density, arch, 0.24)

			-- An asymmetric overhang on the right ridge.
			local shelf = sphere_density((x - 3.35) / 1.25, (y - 1.45) / 0.58, (z + 0.45) / 1.05, 1.72)
			local support = sphere_density((x - 2.8) / 0.62, (y - 0.2) / 1.25, (z + 0.2) / 0.82, 1.35)
			density = smooth_max(density, smooth_max(shelf, support, 0.2), 0.24)

			-- Close this standalone field inside its finite extraction box. Chunked
			-- terrain gets neighboring samples; this showcase deliberately has none.
			local inset = VOXEL_SIZE * 0.75
			local boundary = math.min(
				x - ORIGIN.x - inset,
				ORIGIN.x + CELLS_X * VOXEL_SIZE - x - inset,
				y - ORIGIN.y - inset,
				ORIGIN.y + CELLS_Y * VOXEL_SIZE - y - inset,
				z - ORIGIN.z - inset,
				ORIGIN.z + CELLS_Z * VOXEL_SIZE - z - inset
			)
			density = math.min(density, boundary)

			table.insert(densities, density)
		end
	end
end

local terrain_geometry = scrapbot.geometry.voxel_surface("voxel-terrain-lab", {
	origin = ORIGIN,
	voxel_size = VOXEL_SIZE,
	cells = { x = CELLS_X, y = CELLS_Y, z = CELLS_Z },
	densities = densities,
})

local TerrainAnchors = scrapbot.query(scrapbot.transform)
local attached = false
scrapbot.system(TerrainAnchors, {
	name = "spawn_voxel_terrain_lab",
	writes = { scrapbot.geometry_component },
}, function(time: ScrapbotTime, entity: ScrapbotEntity, _transform: ScrapbotTransform)
	if attached or time.frame_index ~= 1 or entity.id ~= TERRAIN_ENTITY then
		return
	end
	attached = true
	scrapbot.add_component(entity, scrapbot.geometry_component, {
		resource = terrain_geometry,
		geometry_mode = "conventional",
	})
end)
