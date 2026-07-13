scrapbot.geometry.cube("cube", 2)
scrapbot.material.textured("coral", "assets/checker.png")
scrapbot.material.unlit("teal", 0.08, 0.72, 0.68, 1)

scrapbot.log("hello from examples/minimal")
scrapbot.log("entities: " .. tostring(scrapbot.entity_count()))
scrapbot.log("renderables: " .. tostring(scrapbot.renderable_count()))

-- Luau-defined project component and system.
-- wave stores phase, angular speed, and amplitude.
local FloatComponent = scrapbot.component("float", {
	origin = scrapbot.vec3,
	wave = scrapbot.vec3,
}) :: FloatComponent

local SpinComponent = scrapbot.component_handle("scrappyphysics.spin") :: ScrappyphysicsSpinComponent
local RigidbodyComponent = scrapbot.component_handle("scrappyphysics.rigidbody") :: ScrappyphysicsRigidbodyComponent

local Floating = scrapbot.query(scrapbot.transform, FloatComponent)
local Spinners = scrapbot.query(SpinComponent)
local Rigidbodies = scrapbot.query(RigidbodyComponent)

scrapbot.system(Floating, {
	writes = { scrapbot.transform, FloatComponent },
}, function(time: ScrapbotTime, entity: ScrapbotEntity, transform: ScrapbotTransform, float: Float)
	float.wave.x += float.wave.y * time.delta_time
	transform.position.x = float.origin.x
	transform.position.y = float.origin.y + math.sin(float.wave.x) * float.wave.z
	transform.position.z = float.origin.z
end)

-- Scheduling metadata: this system reads native extension component data.
-- Systems whose declared component access does not conflict can share a scheduler batch.
scrapbot.system(Spinners, function(time: ScrapbotTime, entity: ScrapbotEntity, spin: ReadonlyScrappyphysicsSpin)
	assert(spin.angular_velocity.y >= -10)
end)

scrapbot.system(Rigidbodies, function(time: ScrapbotTime, entity: ScrapbotEntity, rigidbody: ReadonlyScrappyphysicsRigidbody)
	assert(rigidbody.velocity.y >= -100)
end)
