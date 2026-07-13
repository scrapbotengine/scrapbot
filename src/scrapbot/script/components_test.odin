package script

import "core:testing"
import component "../component"
import ecs "../ecs"
import project "../project"
import resources "../resources"
import shared "../shared"

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
	speed = scrapbot.vec3,
})
`, "=test", &world)

	testing.expect(t, !result.ran)
	testing.expect(t, result.err == `scene component "autorotate" has field "velocity" that is not defined by scripts/main.luau`)
}

@(test)
test_luau_component_schema_accepts_legacy_vec3_string :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Spinner"

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
`, "=test", &world)

	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)
}

@(test)
test_luau_scripts_can_only_define_project_level_components :: proc(t: ^testing.T) {
	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
scrapbot.component("scrapbot.transform", {
	position = scrapbot.vec3,
})
`, "=test", nil)

	testing.expect(t, !result.ran)
	testing.expect(t, result.err == "=test: project scripts can only define single-token project component names")
}

@(test)
test_luau_scripts_can_register_library_components :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Body"

[entities.components.scrappyphysics.rigidbody]
velocity = [0, 3, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
local RigidbodyComponent = scrapbot.library_component("scrappyphysics.rigidbody", {
	velocity = scrapbot.vec3,
})
local Rigidbodies = scrapbot.query(RigidbodyComponent)

scrapbot.system(Rigidbodies, {
	writes = { RigidbodyComponent },
}, function(time, entity, rigidbody)
	rigidbody.velocity.y += 2
end)
`, "=test", &world)

	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)
	definition, definition_ok := component.find_definition(&runtime.registry, "scrappyphysics.rigidbody")
	testing.expect(t, definition_ok)
	testing.expect(t, definition.owner == .Library)
	testing.expect(t, world.custom_components[0].component_id == definition.id)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
	rigidbody, rigidbody_ok := ecs.custom_component_for_entity(&world, 0, definition.id, "scrappyphysics.rigidbody")
	testing.expect(t, rigidbody_ok)
	velocity, velocity_ok := custom_component_vec3_field(rigidbody, "velocity")
	testing.expect(t, velocity_ok)
	testing.expect(t, velocity.y == 5)
}

@(test)
test_luau_scripts_can_get_pre_registered_component_handles :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Body"

[entities.components.scrappyphysics.rigidbody]
velocity = [0, 3, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	registry: component.Registry
	component.init_registry(&registry)
	definition := component.Definition{name = "scrappyphysics.rigidbody", field_count = 1}
	definition.fields[0] = component.Field_Definition{name = "velocity", field_type = .Vec3}
	register_err := component.register_library_component(&registry, definition)
	testing.expect(t, register_err == "")

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source_with_registry(&runtime, `
local RigidbodyComponent = scrapbot.component_handle("scrappyphysics.rigidbody")
assert(RigidbodyComponent.name == "scrappyphysics.rigidbody")

local Rigidbodies = scrapbot.query(RigidbodyComponent)
scrapbot.system(Rigidbodies, function(time, entity, rigidbody)
	assert(rigidbody.velocity.y == 3)
end)
`, "=test", &world, &registry, Source_Options{})

	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)
	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
}

@(test)
test_luau_library_components_must_use_dotted_non_engine_names :: proc(t: ^testing.T) {
	runtime: Runtime
	defer destroy_runtime(&runtime)

	result := run_source(&runtime, `
scrapbot.library_component("rigidbody", {
	velocity = scrapbot.vec3,
})
`, "=test", nil)
	testing.expect(t, !result.ran)
	testing.expect(t, result.err == "=test: library components must use dotted component names")

	result = run_source(&runtime, `
scrapbot.library_component("scrapbot.rigidbody", {
	velocity = scrapbot.vec3,
})
`, "=test", nil)
	testing.expect(t, !result.ran)
	testing.expect(t, result.err == "=test: library components cannot use the scrapbot namespace")
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
	velocity = scrapbot.vec3,
})

scrapbot.system(function()
	scrapbot.query("autorotate")
end)
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 0.5)
	testing.expect(t, step_err == "Luau system: scrapbot.query component arguments must be component handles")
}
