scrapbot.geometry.cube("cube", 2)
scrapbot.geometry.plane("ground", 12, 12)
scrapbot.geometry.icosphere("icosphere", 1, 2)
scrapbot.geometry.sphere("sphere", 1, 32, 20)
scrapbot.geometry.pyramid("pyramid", 1.5, 1.8, 1.5)
scrapbot.geometry.cylinder("cylinder", 0.7, 1.8, 32)
scrapbot.material.lit("marker", 1, 0.3, 0.15, 1)
scrapbot.material.lit("ground", 0.12, 0.18, 0.22, 1)
scrapbot.material.lit("icosphere", 0.12, 0.75, 0.42, 1)
scrapbot.material.lit("sphere", 0.2, 0.48, 1, 1)
scrapbot.material.lit("pyramid", 1, 0.72, 0.08, 1)
scrapbot.material.lit("cylinder", 0.72, 0.2, 0.92, 1)
scrapbot.material.lit("warm-light", 1, 0.12, 0.03, 1)
scrapbot.material.lit("cool-light", 0.03, 0.3, 1, 1)

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
local LightOrbitComponent = scrapbot.component_handle("showcase.light_orbit") :: ShowcaseLightOrbitComponent

local Floating = scrapbot.query(scrapbot.transform, FloatComponent)
local Emitters = scrapbot.query(scrapbot.transform, EmitterComponent)
local FountainBodies = scrapbot.query(scrapbot.transform, LifetimeComponent, VelocityComponent)
local Spinners = scrapbot.query(SpinComponent)
local OrbitingLights = scrapbot.query(scrapbot.point_light, LightOrbitComponent)

scrapbot.system(Floating, {
	writes = { scrapbot.transform, FloatComponent },
}, function(time: ScrapbotTime, entity: ScrapbotEntity, transform: ScrapbotTransform, float: Float)
	float.wave.x += float.wave.y * time.delta_time
	transform.position.x = float.origin.x
	transform.position.y = float.origin.y + math.sin(float.wave.x) * float.wave.z
	transform.position.z = float.origin.z
end)

scrapbot.system(Emitters, function(time: ScrapbotTime, entity: ScrapbotEntity, transform: ReadonlyScrapbotTransform, emitter: ReadonlyShowcaseEmitter)
	assert(emitter.state.y > 0)
	assert(transform.position.y < 0)
end)

scrapbot.system(FountainBodies, function(time: ScrapbotTime, entity: ScrapbotEntity, transform: ReadonlyScrapbotTransform, lifetime: ReadonlyShowcaseLifetime, velocity: ReadonlyShowcaseVelocity)
	assert(lifetime.timer.y > 0)
	assert(velocity.value.y < 5)
end)

scrapbot.system(Spinners, function(time: ScrapbotTime, entity: ScrapbotEntity, spin: ReadonlyShowcaseSpin)
	assert(spin.angular_velocity.y ~= 0)
end)

scrapbot.system(OrbitingLights, function(time: ScrapbotTime, entity: ScrapbotEntity, light: ReadonlyScrapbotPointLight, orbit: ReadonlyShowcaseLightOrbit)
	assert(light.range > 0)
	assert(orbit.settings.x > 0)
end)
