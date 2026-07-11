scrapbot.log("hello from examples/minimal")
scrapbot.log("entities: " .. tostring(scrapbot.entity_count()))
scrapbot.log("renderables: " .. tostring(scrapbot.renderable_count()))

local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
}) :: AutorotateComponent

local RigidbodyComponent = scrapbot.component_handle("scrappyphysics.rigidbody") :: ScrappyphysicsRigidbodyComponent

local Autorotating = scrapbot.query(scrapbot.transform, AutorotateComponent)
local Rigidbodies = scrapbot.query(RigidbodyComponent)

-- Scheduling metadata: this system reads the autorotating query and writes engine transforms.
-- Systems whose declared component access does not conflict can share a scheduler batch.
scrapbot.system(Autorotating, {
	writes = { "scrapbot.transform" },
}, function(delta_seconds: number, entity: ScrapbotEntity, transform: ScrapbotTransform, autorotate: Autorotate)
	transform.rotation.x += autorotate.velocity.x * delta_seconds
	transform.rotation.y += autorotate.velocity.y * delta_seconds
	transform.rotation.z += autorotate.velocity.z * delta_seconds
end)

scrapbot.system(Rigidbodies, function(delta_seconds: number, entity: ScrapbotEntity, rigidbody: ReadonlyScrappyphysicsRigidbody)
	assert(rigidbody.velocity.y >= -100)
end)
