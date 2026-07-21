scrapbot.geometry.pyramid("scraproids.ship", 1.2, 1.8, 0.8)
scrapbot.geometry.icosphere("scraproids.asteroid", 1.0, 1)
local BulletGeometry = scrapbot.geometry.cylinder("scraproids.bullet", 0.11, 0.55, 10)
local BulletMaterial = scrapbot.material.emissive("scraproids.bullet", 0.1, 0.85, 1.6, 5.0)

local Ship = scrapbot.component("ship", {
	speed = scrapbot.field(scrapbot.number, { draggable = true, minimum = 0, maximum = 20, step = 0.1 }),
	fire_interval = scrapbot.field(scrapbot.number, { draggable = true, minimum = 0.04, maximum = 1, step = 0.01 }),
	cooldown = scrapbot.number,
})
local Velocity = scrapbot.component("velocity", { value = scrapbot.vec3 })
local Asteroid = scrapbot.component("asteroid", { radius = scrapbot.number })
local Bullet = scrapbot.component("bullet", { age = scrapbot.number, radius = scrapbot.number }, { advanced = true })
local Spin = scrapbot.component("spin", { value = scrapbot.vec3 })
local Hud = scrapbot.component("hud", {})
local score = 0

local Player = scrapbot.query(scrapbot.transform, Ship, Velocity)
scrapbot.system(Player, {
	name = "control",
	reads = { scrapbot.keyboard_input },
	writes = { scrapbot.transform, Ship, Velocity },
}, function(time: ScrapbotTime, _entity: ScrapbotEntity, transform: ScrapbotTransform, ship: Ship, velocity: Velocity)
	local x = 0
	local y = 0
	if scrapbot.input.key_down("a") or scrapbot.input.key_down("left") then x -= 1 end
	if scrapbot.input.key_down("d") or scrapbot.input.key_down("right") then x += 1 end
	if scrapbot.input.key_down("s") or scrapbot.input.key_down("down") then y -= 1 end
	if scrapbot.input.key_down("w") or scrapbot.input.key_down("up") then y += 1 end
	if x ~= 0 and y ~= 0 then
		x *= 0.70710678
		y *= 0.70710678
	end
	velocity.value.x = x * ship.speed
	velocity.value.y = y * ship.speed
	ship.cooldown = math.max(ship.cooldown - time.delta_time, 0)
	if scrapbot.input.key_down("space") and ship.cooldown <= 0 then
		ship.cooldown = ship.fire_interval
		scrapbot.spawn({
			name = "Photon Bolt",
			components = {
				["scrapbot.transform"] = {
					position = { x = transform.position.x, y = transform.position.y + 0.9, z = 0 },
					rotation = { x = 1.5707963, y = 0, z = 0 },
					scale = { x = 1, y = 1, z = 1 },
				},
				["scrapbot.geometry"] = BulletGeometry,
				["scrapbot.material"] = BulletMaterial,
				velocity = { value = { x = 0, y = 10.5, z = 0 } },
				bullet = { age = 0, radius = 0.18 },
			},
		})
	end
end)

local Moving = scrapbot.query(scrapbot.transform, Velocity)
scrapbot.system(Moving, {
	name = "move",
	writes = { scrapbot.transform },
	reads = { Velocity },
}, function(time: ScrapbotTime, _entity: ScrapbotEntity, transform: ScrapbotTransform, velocity: Velocity)
	transform.position.x += velocity.value.x * time.delta_time
	transform.position.y += velocity.value.y * time.delta_time
	if transform.position.x < -6.4 then transform.position.x = 6.4 end
	if transform.position.x > 6.4 then transform.position.x = -6.4 end
	if transform.position.y < -4.2 then transform.position.y = 4.2 end
	if transform.position.y > 5.2 then transform.position.y = -4.2 end
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

local Bullets = scrapbot.query(scrapbot.transform, Bullet)
scrapbot.system(Bullets, {
	name = "collide",
	writes = { Bullet },
	reads = { scrapbot.transform, Asteroid },
}, function(time: ScrapbotTime, bullet_entity: ScrapbotEntity, bullet_transform: ScrapbotTransform, bullet: Bullet)
	bullet.age += time.delta_time
	if bullet.age > 1.4 then
		scrapbot.despawn(bullet_entity)
		return
	end
	for _, item in scrapbot.view(scrapbot.query(scrapbot.transform, Asteroid)) do
		local dx = bullet_transform.position.x - item[1].position.x
		local dy = bullet_transform.position.y - item[1].position.y
		local radius = bullet.radius + item[2].radius
		if dx * dx + dy * dy <= radius * radius then
			scrapbot.despawn(bullet_entity)
			scrapbot.despawn(item.entity)
			score += 100
			return
		end
	end
end)

local Score = scrapbot.query(scrapbot.ui_text, Hud)
scrapbot.system(Score, {
	name = "score",
	writes = { scrapbot.ui_text },
	reads = { Hud },
}, function(_time: ScrapbotTime, _entity: ScrapbotEntity, text: ScrapbotUiText, _hud: Hud)
	text.text = string.format("SCRAPROIDS  /  SCORE %04d", score)
end)
