scrapbot.log("hello from examples/minimal")
scrapbot.log("entities: " .. tostring(scrapbot.entity_count()))
scrapbot.log("renderables: " .. tostring(scrapbot.renderable_count()))

local SpinComponent = scrapbot.component_handle("scrappyphysics.spin") :: ScrappyphysicsSpinComponent
local RigidbodyComponent = scrapbot.component_handle("scrappyphysics.rigidbody") :: ScrappyphysicsRigidbodyComponent

local Spinners = scrapbot.query(SpinComponent)
local Rigidbodies = scrapbot.query(RigidbodyComponent)

-- Scheduling metadata: this system reads native extension component data.
-- Systems whose declared component access does not conflict can share a scheduler batch.
scrapbot.system(Spinners, function(delta_seconds: number, entity: ScrapbotEntity, spin: ReadonlyScrappyphysicsSpin)
	assert(spin.angular_velocity.y >= -10)
end)

scrapbot.system(Rigidbodies, function(delta_seconds: number, entity: ScrapbotEntity, rigidbody: ReadonlyScrappyphysicsRigidbody)
	assert(rigidbody.velocity.y >= -100)
end)
