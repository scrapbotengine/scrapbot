type LocalVec3 = { x: number, y: number, z: number }

local function normalized(v: LocalVec3): LocalVec3
	local length = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	return { x = v.x / length, y = v.y / length, z = v.z / length }
end

local function midpoint(a: LocalVec3, b: LocalVec3): LocalVec3
	return normalized({ x = (a.x + b.x) * 0.5, y = (a.y + b.y) * 0.5, z = (a.z + b.z) * 0.5 })
end

local function flat_icosahedron(name: string, subdivisions: number)
	local golden = (1 + math.sqrt(5)) * 0.5
	local positions: { LocalVec3 } = {
		{ x = -1, y = golden, z = 0 }, { x = 1, y = golden, z = 0 },
		{ x = -1, y = -golden, z = 0 }, { x = 1, y = -golden, z = 0 },
		{ x = 0, y = -1, z = golden }, { x = 0, y = 1, z = golden },
		{ x = 0, y = -1, z = -golden }, { x = 0, y = 1, z = -golden },
		{ x = golden, y = 0, z = -1 }, { x = golden, y = 0, z = 1 },
		{ x = -golden, y = 0, z = -1 }, { x = -golden, y = 0, z = 1 },
	}
	for index, position in positions do
		positions[index] = normalized(position)
	end
	local faces: { { number } } = {
		{ 1, 12, 6 }, { 1, 6, 2 }, { 1, 2, 8 }, { 1, 8, 11 }, { 1, 11, 12 },
		{ 2, 6, 10 }, { 6, 12, 5 }, { 12, 11, 3 }, { 11, 8, 7 }, { 8, 2, 9 },
		{ 4, 10, 5 }, { 4, 5, 3 }, { 4, 3, 7 }, { 4, 7, 9 }, { 4, 9, 10 },
		{ 5, 10, 6 }, { 3, 5, 12 }, { 7, 3, 11 }, { 9, 7, 8 }, { 10, 9, 2 },
	}
	for _ = 1, subdivisions do
		local next_faces: { { number } } = {}
		for _, face in faces do
			local a, b, c = positions[face[1]], positions[face[2]], positions[face[3]]
			table.insert(positions, midpoint(a, b))
			local ab = #positions
			table.insert(positions, midpoint(b, c))
			local bc = #positions
			table.insert(positions, midpoint(c, a))
			local ca = #positions
			table.insert(next_faces, { face[1], ab, ca })
			table.insert(next_faces, { face[2], bc, ab })
			table.insert(next_faces, { face[3], ca, bc })
			table.insert(next_faces, { ab, bc, ca })
		end
		faces = next_faces
	end

	local vertices, indices = {}, {}
	for _, face in faces do
		local a, b, c = positions[face[1]], positions[face[2]], positions[face[3]]
		local ab = { x = b.x - a.x, y = b.y - a.y, z = b.z - a.z }
		local ac = { x = c.x - a.x, y = c.y - a.y, z = c.z - a.z }
		local normal = normalized({
			x = ab.y * ac.z - ab.z * ac.y,
			y = ab.z * ac.x - ab.x * ac.z,
			z = ab.x * ac.y - ab.y * ac.x,
		})
		for _, position in { a, b, c } do
			table.insert(vertices, { position = position, normal = normal, uv = { x = 0, y = 0 } })
			table.insert(indices, #vertices - 1)
		end
	end
	return scrapbot.geometry.create(name, { vertices = vertices, indices = indices })
end

scrapbot.geometry.pyramid("scraproids.ship", 1.2, 1.8, 0.8)
local AsteroidGeometryFine = flat_icosahedron("scraproids.asteroid", 1)
local AsteroidGeometryChunky = flat_icosahedron("scraproids.asteroid.chunky", 0)
local AsteroidFragmentMaterial = scrapbot.material.lit("scraproids.asteroid.fragments", 0.42, 0.34, 0.28, 1.0)
local BulletGeometry = scrapbot.geometry.cylinder("scraproids.bullet", 0.11, 0.55, 10)
local BulletMaterial = scrapbot.material.emissive("scraproids.bullet", 0.1, 0.85, 1.6, 5.0)

local Ship = scrapbot.component("ship", {
	speed = scrapbot.field(scrapbot.number, { draggable = true, minimum = 0, maximum = 20, step = 0.1 }),
	acceleration = scrapbot.field(scrapbot.number, { draggable = true, minimum = 0, maximum = 30, step = 0.5 }),
	turn_speed = scrapbot.field(scrapbot.number, { draggable = true, minimum = 0, maximum = 10, step = 0.1 }),
	drag = scrapbot.field(scrapbot.number, { draggable = true, minimum = 0, maximum = 5, step = 0.05 }),
	fire_interval = scrapbot.field(scrapbot.number, { draggable = true, minimum = 0.04, maximum = 1, step = 0.01 }),
	cooldown = scrapbot.number,
})
local Asteroid = scrapbot.component("asteroid", { radius = scrapbot.number })
local Velocity = scrapbot.component("velocity", { value = scrapbot.vec3 })
local Body = scrapbot.component("body", {
	radius = scrapbot.field(scrapbot.number, { draggable = true, minimum = 0, maximum = 5, step = 0.05 }),
	restitution = scrapbot.field(scrapbot.number, { draggable = true, minimum = 0, maximum = 1.2, step = 0.05 }),
})
local Bullet = scrapbot.component("bullet", { age = scrapbot.number, radius = scrapbot.number }, { advanced = true })
local Spin = scrapbot.component("spin", { value = scrapbot.vec3 })
local SpawnPop = scrapbot.component("spawn_pop", {
	age = scrapbot.number,
	duration = scrapbot.number,
	target_scale = scrapbot.vec3,
}, { advanced = true })
local CameraShake = scrapbot.component("camera_shake", {
	base_position = scrapbot.vec3,
	base_rotation = scrapbot.vec3,
	trauma = scrapbot.number,
}, { advanced = true })
local ShakeImpulse = scrapbot.component("shake_impulse", { amount = scrapbot.number }, { advanced = true })
local Hud = scrapbot.component("hud", {})
local score = 0
local random_state = 7331

local function random01(): number
	random_state = (random_state * 48271) % 2147483647
	return random_state / 2147483647
end

local function ease_out_back(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	local shifted = t - 1
	return 1 + c3 * shifted * shifted * shifted + c1 * shifted * shifted
end

local Player = scrapbot.query(scrapbot.transform, Ship, Velocity)
scrapbot.system(Player, {
	name = "control",
	reads = { scrapbot.keyboard_input },
	writes = {
		scrapbot.transform,
		scrapbot.geometry_component,
		scrapbot.material_component,
		Ship,
		Velocity,
		Body,
		Bullet,
	},
}, function(time: ScrapbotTime, _entity: ScrapbotEntity, transform: ScrapbotTransform, ship: Ship, velocity: Velocity)
	local turn = 0
	if scrapbot.input.key_down("a") or scrapbot.input.key_down("left") then
		turn += 1
	end
	if scrapbot.input.key_down("d") or scrapbot.input.key_down("right") then
		turn -= 1
	end
	transform.rotation.z += turn * ship.turn_speed * time.delta_time

	local thrust = 0
	if scrapbot.input.key_down("w") or scrapbot.input.key_down("up") then
		thrust += 1
	end
	if scrapbot.input.key_down("s") or scrapbot.input.key_down("down") then
		thrust -= 0.55
	end
	local forward_x = -math.sin(transform.rotation.z)
	local forward_y = math.cos(transform.rotation.z)
	velocity.value.x += forward_x * ship.acceleration * thrust * time.delta_time
	velocity.value.y += forward_y * ship.acceleration * thrust * time.delta_time
	local drag = math.exp(-ship.drag * time.delta_time)
	velocity.value.x *= drag
	velocity.value.y *= drag
	local speed = math.sqrt(velocity.value.x * velocity.value.x + velocity.value.y * velocity.value.y)
	if speed > ship.speed then
		local scale = ship.speed / speed
		velocity.value.x *= scale
		velocity.value.y *= scale
	end
	ship.cooldown = math.max(ship.cooldown - time.delta_time, 0)
	if scrapbot.input.key_down("space") and ship.cooldown <= 0 then
		ship.cooldown = ship.fire_interval
		scrapbot.spawn({
			name = "Photon Bolt",
			components = {
				["scrapbot.transform"] = {
					position = {
						x = transform.position.x + forward_x * 0.62,
						y = transform.position.y + forward_y * 0.62,
						z = 0,
					},
					rotation = { x = 1.5707963, y = 0, z = transform.rotation.z },
					scale = { x = 1, y = 1, z = 1 },
				},
				["scrapbot.geometry"] = BulletGeometry,
				["scrapbot.material"] = BulletMaterial,
				velocity = {
					value = {
						x = velocity.value.x + forward_x * 10.5,
						y = velocity.value.y + forward_y * 10.5,
						z = 0,
					},
				},
				body = { radius = 0.12, restitution = 0.92 },
				bullet = { age = 0, radius = 0.18 },
			},
		})
	end
end)

local Moving = scrapbot.query(scrapbot.transform, Velocity, Body)
scrapbot.system(Moving, {
	name = "move",
	writes = { scrapbot.transform, Velocity },
	reads = { Body },
}, function(time: ScrapbotTime, _entity: ScrapbotEntity, transform: ScrapbotTransform, velocity: Velocity, body: Body)
	transform.position.x += velocity.value.x * time.delta_time
	transform.position.y += velocity.value.y * time.delta_time
	local minimum_x = -6.4 + body.radius
	local maximum_x = 6.4 - body.radius
	local minimum_y = -4.2 + body.radius
	local maximum_y = 5.2 - body.radius
	if transform.position.x < minimum_x then
		transform.position.x = minimum_x
		velocity.value.x = math.abs(velocity.value.x) * body.restitution
	elseif transform.position.x > maximum_x then
		transform.position.x = maximum_x
		velocity.value.x = -math.abs(velocity.value.x) * body.restitution
	end
	if transform.position.y < minimum_y then
		transform.position.y = minimum_y
		velocity.value.y = math.abs(velocity.value.y) * body.restitution
	elseif transform.position.y > maximum_y then
		transform.position.y = maximum_y
		velocity.value.y = -math.abs(velocity.value.y) * body.restitution
	end
end)

local Spinning = scrapbot.query(scrapbot.transform, Spin)
scrapbot.system(Spinning, {
	name = "spin",
	writes = { scrapbot.transform },
	reads = { Spin },
}, function(time: ScrapbotTime, _entity: ScrapbotEntity, transform: ScrapbotTransform, spin: Spin)
	transform.rotation.x += spin.value.x * time.delta_time
	transform.rotation.y += spin.value.y * time.delta_time
	transform.rotation.z += spin.value.z * time.delta_time
end)

local Popping = scrapbot.query(scrapbot.transform, SpawnPop)
scrapbot.system(Popping, {
	name = "spawn_pop",
	writes = { scrapbot.transform, SpawnPop },
}, function(time: ScrapbotTime, entity: ScrapbotEntity, transform: ScrapbotTransform, pop: SpawnPop)
	pop.age += time.delta_time
	local t = math.min(pop.age / math.max(pop.duration, 0.001), 1)
	local eased = ease_out_back(t)
	transform.scale.x = pop.target_scale.x * eased
	transform.scale.y = pop.target_scale.y * eased
	transform.scale.z = pop.target_scale.z * eased
	if t >= 1 then
		scrapbot.remove_component(entity, SpawnPop)
	end
end)

local Asteroids = scrapbot.query(scrapbot.transform, Asteroid, Velocity)
local Bullets = scrapbot.query(scrapbot.transform, Bullet)
local collision_frame = -1
local destroyed_asteroids = {}
scrapbot.system(Bullets, {
	name = "collide",
	writes = {
		scrapbot.transform,
		scrapbot.geometry_component,
		scrapbot.material_component,
		scrapbot.shadow_caster,
		Asteroid,
		Bullet,
		Velocity,
		Body,
		Spin,
		SpawnPop,
		ShakeImpulse,
	},
	reads = { scrapbot.transform, Asteroid, Velocity },
}, function(time: ScrapbotTime, bullet_entity: ScrapbotEntity, bullet_transform: ScrapbotTransform, bullet: Bullet)
	if collision_frame ~= time.frame_index then
		collision_frame = time.frame_index
		destroyed_asteroids = {}
	end
	bullet.age += time.delta_time
	if bullet.age > 1.4 then
		scrapbot.despawn(bullet_entity)
		return
	end
	for _, item in scrapbot.view(Asteroids) do
		if destroyed_asteroids[item.entity.id] then continue end
		local asteroid_transform = item.components[1]
		local asteroid = item.components[2]
		local asteroid_velocity = item.components[3]
		local dx = bullet_transform.position.x - asteroid_transform.position.x
		local dy = bullet_transform.position.y - asteroid_transform.position.y
		local radius = bullet.radius + asteroid.radius
		if dx * dx + dy * dy <= radius * radius then
			destroyed_asteroids[item.entity.id] = true
			scrapbot.despawn(bullet_entity)
			scrapbot.despawn(item.entity)
			if asteroid.radius > 0.26 then
				local child_radius = asteroid.radius * 0.56
				local child_count = 2 + math.floor(random01() * 2)
				for child_index = 1, child_count do
					local angle = random01() * math.pi * 2 + child_index * (math.pi * 2 / child_count)
					local burst_speed = 1.25 + random01() * 1.15
					local target_scale = { x = child_radius, y = child_radius, z = child_radius }
					scrapbot.spawn({
						name = "Asteroid Fragment",
						components = {
							["scrapbot.transform"] = {
								position = {
									x = asteroid_transform.position.x + math.cos(angle) * child_radius * 0.45,
									y = asteroid_transform.position.y + math.sin(angle) * child_radius * 0.45,
									z = asteroid_transform.position.z,
								},
								rotation = {
									x = random01() * math.pi,
									y = random01() * math.pi,
									z = random01() * math.pi,
								},
								scale = {
									x = child_radius * 0.18,
									y = child_radius * 0.18,
									z = child_radius * 0.18,
								},
							},
							["scrapbot.geometry"] = if child_radius > 0.25 then AsteroidGeometryFine else AsteroidGeometryChunky,
							["scrapbot.material"] = AsteroidFragmentMaterial,
							["scrapbot.shadow_caster"] = {},
							asteroid = { radius = child_radius },
							body = { radius = child_radius, restitution = 0.96 },
							velocity = {
								value = {
									x = asteroid_velocity.value.x + math.cos(angle) * burst_speed,
									y = asteroid_velocity.value.y + math.sin(angle) * burst_speed,
									z = 0,
								},
							},
							spin = {
								value = {
									x = (random01() - 0.5) * 2.8,
									y = (random01() - 0.5) * 2.8,
									z = (random01() - 0.5) * 2.8,
								},
							},
							spawn_pop = { age = 0, duration = 0.24, target_scale = target_scale },
						}
					})
				end
			end
			scrapbot.spawn({
				name = "Camera Shake",
				components = { shake_impulse = { amount = math.min(0.28 + asteroid.radius * 0.38, 0.7) } },
			})
			score += math.floor(120 / asteroid.radius)
			return
		end
	end
end)

local ShakeImpulses = scrapbot.query(ShakeImpulse)
local ShakingCameras = scrapbot.query(scrapbot.transform, CameraShake)
scrapbot.system(ShakingCameras, {
	name = "camera_shake",
	writes = { scrapbot.transform, CameraShake },
	reads = { ShakeImpulse },
}, function(time: ScrapbotTime, _entity: ScrapbotEntity, transform: ScrapbotTransform, shake: CameraShake)
	for _, item in scrapbot.view(ShakeImpulses) do
		shake.trauma = math.min(shake.trauma + item.component.amount, 1)
		scrapbot.despawn(item.entity)
	end
	shake.trauma = math.max(shake.trauma - time.delta_time * 1.85, 0)
	local strength = shake.trauma * shake.trauma
	local phase = time.elapsed_time * 48
	transform.position.x = shake.base_position.x + math.sin(phase * 1.13) * 0.16 * strength
	transform.position.y = shake.base_position.y + math.sin(phase * 1.71 + 1.9) * 0.12 * strength
	transform.position.z = shake.base_position.z
	transform.rotation.x = shake.base_rotation.x
	transform.rotation.y = shake.base_rotation.y
	transform.rotation.z = shake.base_rotation.z + math.sin(phase * 2.07 + 0.7) * 0.018 * strength
end)

local Score = scrapbot.query(scrapbot.ui_text, Hud)
scrapbot.system(Score, {
	name = "score",
	writes = { scrapbot.ui_text },
	reads = { Hud },
}, function(_time: ScrapbotTime, _entity: ScrapbotEntity, text: ScrapbotUiText, _hud: Hud)
	text.text = string.format("SCRAPROIDS  /  SCORE %04d", score)
end)
