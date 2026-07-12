scrapbot.geometry.cube("cube", 2)
scrapbot.geometry.plane("ground", 12, 12)
scrapbot.material.unlit("marker", 1, 0.3, 0.15, 1)
scrapbot.material.unlit("ground", 0.12, 0.18, 0.22, 1)

scrapbot.log("hello from examples/ecs-showcase")
scrapbot.log("entities: " .. tostring(scrapbot.entity_count()))
scrapbot.log("renderables: " .. tostring(scrapbot.renderable_count()))

local FloatComponent = scrapbot.component("float", {
	origin = scrapbot.vec3,
	wave = scrapbot.vec3,
}) :: FloatComponent

local EmitterComponent = scrapbot.component_handle("showcase.emitter") :: ShowcaseEmitterComponent
local LifetimeComponent = scrapbot.component_handle("showcase.lifetime") :: ShowcaseLifetimeComponent
local SpinComponent = scrapbot.component_handle("showcase.spin") :: ShowcaseSpinComponent
local VelocityComponent = scrapbot.component_handle("showcase.velocity") :: ShowcaseVelocityComponent

local Floating = scrapbot.query(scrapbot.transform, FloatComponent)
local Emitters = scrapbot.query(scrapbot.transform, EmitterComponent)
local FountainBodies = scrapbot.query(scrapbot.transform, LifetimeComponent, VelocityComponent)
local Spinners = scrapbot.query(SpinComponent)

scrapbot.system(Floating, {
	writes = { scrapbot.transform, FloatComponent },
}, function(delta_seconds: number, entity: ScrapbotEntity, transform: ScrapbotTransform, float: Float)
	float.wave.x += float.wave.y * delta_seconds
	transform.position.x = float.origin.x
	transform.position.y = float.origin.y + math.sin(float.wave.x) * float.wave.z
	transform.position.z = float.origin.z
end)

scrapbot.system(Emitters, function(delta_seconds: number, entity: ScrapbotEntity, transform: ReadonlyScrapbotTransform, emitter: ReadonlyShowcaseEmitter)
	assert(emitter.state.y > 0)
	assert(transform.position.y < 0)
end)

scrapbot.system(FountainBodies, function(delta_seconds: number, entity: ScrapbotEntity, transform: ReadonlyScrapbotTransform, lifetime: ReadonlyShowcaseLifetime, velocity: ReadonlyShowcaseVelocity)
	assert(lifetime.timer.y > 0)
	assert(velocity.value.y < 5)
end)

scrapbot.system(Spinners, function(delta_seconds: number, entity: ScrapbotEntity, spin: ReadonlyShowcaseSpin)
	assert(spin.angular_velocity.y ~= 0)
end)
