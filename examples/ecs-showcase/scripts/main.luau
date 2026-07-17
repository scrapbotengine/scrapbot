scrapbot.geometry.cube("cube", 2)
scrapbot.geometry.plane("ground", 12, 12)
scrapbot.geometry.icosphere("icosphere", 1, 2)
scrapbot.geometry.sphere("sphere", 1, 32, 20)
scrapbot.geometry.pyramid("pyramid", 1.5, 1.8, 1.5)
scrapbot.geometry.cylinder("cylinder", 0.7, 1.8, 32)
scrapbot.log("hello from examples/ecs-showcase")
scrapbot.log("entities: " .. tostring(scrapbot.entity_count()))
scrapbot.log("renderables: " .. tostring(scrapbot.renderable_count()))

local FloatComponent = scrapbot.component("float", {
	origin = scrapbot.vec3,
	wave = scrapbot.vec3,
}) :: FloatComponent

local Floating = scrapbot.query(scrapbot.transform, FloatComponent)

scrapbot.system(Floating, {
	name = "floating",
	writes = { scrapbot.transform, FloatComponent },
}, function(time: ScrapbotTime, entity: ScrapbotEntity, transform: ScrapbotTransform, float: Float)
	float.wave.x += float.wave.y * time.delta_time
	transform.position.x = float.origin.x
	transform.position.y = float.origin.y + math.sin(float.wave.x) * float.wave.z
	transform.position.z = float.origin.z
end)
