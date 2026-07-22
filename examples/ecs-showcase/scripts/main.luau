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

local DayCycleComponent = scrapbot.component("day_cycle", {
	duration_seconds = scrapbot.field(scrapbot.number, {
		draggable = true,
		minimum = 1,
		maximum = 300,
		step = 1,
	}),
	time_of_day = scrapbot.field(scrapbot.number, {
		draggable = true,
		minimum = 0,
		maximum = 1,
		step = 0.01,
	}),
}) :: DayCycleComponent

local Floating = scrapbot.query(scrapbot.transform, FloatComponent)
local DayCycles = scrapbot.query(scrapbot.world_environment, DayCycleComponent)

scrapbot.system(DayCycles, {
	name = "day_cycle",
	writes = { scrapbot.world_environment, DayCycleComponent },
}, function(
	time: ScrapbotTime,
	entity: ScrapbotEntity,
	environment: ScrapbotWorldEnvironment,
	cycle: DayCycle
)
	local duration = math.max(cycle.duration_seconds, 1)
	cycle.time_of_day = (cycle.time_of_day + time.delta_time / duration) % 1

	-- Keep the daylight half of the orbit on the showcase camera's side of
	-- the sky: sunrise at 0.0, noon at 0.25, sunset at 0.5, and midnight at
	-- 0.75. The negative Z bias still leaves the night half below the horizon.
	local solar_angle = cycle.time_of_day * math.pi * 2
	environment.sun_direction.x = -0.515 * math.cos(solar_angle)
	environment.sun_direction.y = 0.24 * math.sin(solar_angle)
	environment.sun_direction.z = -0.857
end)

scrapbot.system(Floating, {
	name = "floating",
	writes = { scrapbot.transform, FloatComponent },
}, function(time: ScrapbotTime, entity: ScrapbotEntity, transform: ScrapbotTransform, float: Float)
	float.wave.x += float.wave.y * time.delta_time
	transform.position.x = float.origin.x
	transform.position.y = float.origin.y + math.sin(float.wave.x) * float.wave.z
	transform.position.z = float.origin.z
end)
