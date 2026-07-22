local Turntable = scrapbot.component("turntable", {
	speed = scrapbot.vec3,
})

local Turning = scrapbot.query(scrapbot.transform, Turntable)

scrapbot.system(Turning, {
	name = "turntable",
	writes = { scrapbot.transform },
}, function(time: ScrapbotTime, _entity: ScrapbotEntity, transform: ScrapbotTransform, turntable: Turntable)
	transform.rotation.x += turntable.speed.x * time.delta_time
	transform.rotation.y += turntable.speed.y * time.delta_time
	transform.rotation.z += turntable.speed.z * time.delta_time
end)
