scrapbot.log("hello from examples/minimal")
scrapbot.log("entities: " .. tostring(scrapbot.entity_count()))
scrapbot.log("renderables: " .. tostring(scrapbot.renderable_count()))

local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = "vec3",
}) :: AutorotateComponent

scrapbot.system({
	reads = { AutorotateComponent },
	writes = { "scrapbot.transform" },
}, function(delta_seconds)
	scrapbot.query(AutorotateComponent, function(entity, autorotate: Autorotate)
		local rotation = scrapbot.get_rotation(entity)
		rotation.x += autorotate.velocity.x * delta_seconds
		rotation.y += autorotate.velocity.y * delta_seconds
		rotation.z += autorotate.velocity.z * delta_seconds
		scrapbot.set_rotation(entity, rotation)
	end)
end)
