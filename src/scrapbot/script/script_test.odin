package script

import "core:testing"
import ecs "../ecs"
import project "../project"
import shared "../shared"

@(test)
test_luau_script_can_read_ecs_counts :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(project.default_scene_template())
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
type Vec3 = {
	x: number,
	y: number,
	z: number,
}

type Component<T> = {
	name: string,
}

type Autorotate = {
	velocity: Vec3,
}

local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = "vec3",
}) :: Component<Autorotate>

assert(scrapbot.entity_count() == 2)
assert(scrapbot.renderable_count() == 1)
`, "=test", &world)

	testing.expect(t, result.ran)
	testing.expect(t, result.err == "")
}

@(test)
test_luau_script_reports_runtime_errors :: proc(t: ^testing.T) {
	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `error("boom")`, "=test", nil)

	testing.expect(t, !result.ran)
	testing.expect(t, result.err != "")
}

@(test)
test_luau_system_rotates_entities_with_custom_component :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Spinner"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.mesh]
primitive = "cube"

[entities.components.autorotate]
velocity = [0, 2, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
type Vec3 = {
	x: number,
	y: number,
	z: number,
}

type Component<T> = {
	name: string,
}

type Autorotate = {
	velocity: Vec3,
}

local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = "vec3",
}) :: Component<Autorotate>

scrapbot.system(function(delta_seconds)
	scrapbot.query(AutorotateComponent, function(entity, autorotate: Autorotate)
		local rotation = scrapbot.get_rotation(entity)
		rotation.x += autorotate.velocity.x * delta_seconds
		rotation.y += autorotate.velocity.y * delta_seconds
		rotation.z += autorotate.velocity.z * delta_seconds
		scrapbot.set_rotation(entity, rotation)
	end)
end)
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 0.5)
	testing.expect(t, step_err == "")
	testing.expect(t, world.transforms[0].rotation == shared.Vec3{0, 1, 0})
}

@(test)
test_luau_script_must_define_scene_custom_components :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Spinner"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.components.autorotate]
velocity = [0, 2, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `scrapbot.log("missing component declaration")`, "=test", &world)

	testing.expect(t, !result.ran)
	testing.expect(t, result.err == `scene component "autorotate" is not defined by scripts/main.luau; add scrapbot.component("autorotate", schema)`)
}

@(test)
test_luau_component_schema_must_define_scene_fields :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Spinner"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.components.autorotate]
velocity = [0, 2, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
scrapbot.component("autorotate", {
	speed = "vec3",
})
`, "=test", &world)

	testing.expect(t, !result.ran)
	testing.expect(t, result.err == `scene component "autorotate" has field "velocity" that is not defined by scripts/main.luau`)
}

@(test)
test_luau_scripts_can_only_define_project_level_components :: proc(t: ^testing.T) {
	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
scrapbot.component("scrapbot.transform", {
	position = "vec3",
})
`, "=test", nil)

	testing.expect(t, !result.ran)
	testing.expect(t, result.err == "=test: project scripts can only define single-token project component names")
}

@(test)
test_luau_script_validation_accepts_registered_engine_scene_components :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Body"

[entities.components.scrapbot.transform]
position = [0, 0, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `scrapbot.log("engine component")`, "=test", &world)

	testing.expect(t, result.ran)
	testing.expect(t, result.err == "")
}

@(test)
test_luau_script_validation_rejects_unknown_namespaced_scene_components :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Body"

[entities.components.scrappyphysics.rigidbody]
velocity = [0, 0, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `scrapbot.log("unknown namespaced component")`, "=test", &world)

	testing.expect(t, !result.ran)
	testing.expect(t, result.err == `scene component "scrappyphysics.rigidbody" is not registered`)
}

@(test)
test_luau_query_requires_component_handle :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Spinner"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.components.autorotate]
velocity = [0, 2, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
scrapbot.component("autorotate", {
	velocity = "vec3",
})

scrapbot.system(function()
	scrapbot.query("autorotate", function() end)
end)
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 0.5)
	testing.expect(t, step_err == "Luau system: scrapbot.query expects a component handle and callback")
}
