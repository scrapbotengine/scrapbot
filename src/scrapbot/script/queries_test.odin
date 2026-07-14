package script

import component "../component"
import ecs "../ecs"
import project "../project"
import resources "../resources"
import shared "../shared"
import "core:testing"

@(test)
test_luau_system_rotates_entities_with_custom_component :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a9000000-0000-4000-8000-000000000001"
name = "Spinner"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.mesh]
primitive = "cube"

[entities.components.autorotate]
velocity = [0, 2, 0]
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
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
	velocity = scrapbot.vec3,
}) :: Component<Autorotate>

scrapbot.system(function(time)
	scrapbot.query(AutorotateComponent):each(function(entity, autorotate: Autorotate)
		assert(entity.id == "a9000000-0000-4000-8000-000000000001")
		local rotation = scrapbot.get_rotation(entity)
		rotation.x += autorotate.velocity.x * time.delta_time
		rotation.y += autorotate.velocity.y * time.delta_time
		rotation.z += autorotate.velocity.z * time.delta_time
		scrapbot.set_rotation(entity, rotation)
	end)
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 0.5)
	testing.expect(t, step_err == "")
	testing.expect(t, world.transforms[0].rotation == shared.Vec3{0, 1, 0})
}

@(test)
test_luau_system_queries_transform_and_custom_component_together :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a9000000-0000-4000-8000-000000000002"
name = "Spinner"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.components.autorotate]
velocity = [0, 2, 0]
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})
assert(scrapbot.transform.id > 0)

local Autorotating = scrapbot.query(scrapbot.transform, AutorotateComponent)

scrapbot.system(Autorotating, {
	writes = { scrapbot.transform },
}, function(time, entity, transform, autorotate)
	transform.rotation.y += autorotate.velocity.y * time.delta_time
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)
	testing.expect(t, runtime.system_count == 1)
	testing.expect(t, runtime.systems[0].has_query)
	testing.expect(t, runtime.systems[0].declaration.access_count == 3)
	testing.expect(t, runtime.systems[0].declaration.accesses[0].component == "scrapbot.transform")
	testing.expect(t, runtime.systems[0].declaration.accesses[0].mode == .Read)
	testing.expect(t, runtime.systems[0].declaration.accesses[1].component == "autorotate")
	testing.expect(t, runtime.systems[0].declaration.accesses[1].mode == .Read)
	testing.expect(t, runtime.systems[0].declaration.accesses[2].component == "scrapbot.transform")
	testing.expect(t, runtime.systems[0].declaration.accesses[2].mode == .Write)

	step_err := step_runtime(&runtime, &world, 0.5)
	testing.expect(t, step_err == "")
	testing.expect(t, world.transforms[0].rotation.y == 1)
}

@(test)
test_luau_query_system_rejects_transform_payload_write_without_access :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a9000000-0000-4000-8000-000000000003"
name = "Spinner"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.components.autorotate]
velocity = [0, 2, 0]
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

local Autorotating = scrapbot.query(scrapbot.transform, AutorotateComponent)

scrapbot.system(Autorotating, function(time, entity, transform, autorotate)
	transform.rotation.y += autorotate.velocity.y * time.delta_time
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 0.5)
	testing.expect(
		t,
		step_err == "Luau system: system access declaration does not permit component write",
	)
	testing.expect(t, world.transforms[0].rotation.y == 0)
}

@(test)
test_luau_query_system_writes_project_component_payload :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a9000000-0000-4000-8000-000000000004"
name = "Spinner"

[entities.components.autorotate]
velocity = [0, 2, 0]
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

local Autorotating = scrapbot.query(AutorotateComponent)

scrapbot.system(Autorotating, {
	writes = { AutorotateComponent },
}, function(time, entity, autorotate)
	autorotate.velocity.y += 3 * time.delta_time
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 0.5)
	testing.expect(t, step_err == "")

	autorotate_id := runtime.registry.definitions[3].id
	autorotate, ok := ecs.custom_component_for_entity(&world, 0, autorotate_id, "autorotate")
	testing.expect(t, ok)
	testing.expect(t, autorotate.vec3_fields[0].value.y == 3.5)
}

@(test)
test_luau_query_system_rejects_project_component_payload_write_without_access :: proc(
	t: ^testing.T,
) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a9000000-0000-4000-8000-000000000005"
name = "Spinner"

[entities.components.autorotate]
velocity = [0, 2, 0]
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

local Autorotating = scrapbot.query(AutorotateComponent)

scrapbot.system(Autorotating, function(time, entity, autorotate)
	autorotate.velocity.y += 3 * time.delta_time
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 0.5)
	testing.expect(
		t,
		step_err == "Luau system: system access declaration does not permit component write",
	)

	autorotate_id := runtime.registry.definitions[3].id
	autorotate, ok := ecs.custom_component_for_entity(&world, 0, autorotate_id, "autorotate")
	testing.expect(t, ok)
	testing.expect(t, autorotate.vec3_fields[0].value.y == 2)
}

@(test)
test_luau_query_reuses_cached_object_for_same_component_set :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a9000000-0000-4000-8000-000000000006"
name = "Spinner"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.components.autorotate]
velocity = [0, 2, 0]
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

local first = scrapbot.query(scrapbot.transform, AutorotateComponent)
local repeated = scrapbot.query(scrapbot.transform, AutorotateComponent)
local reversed = scrapbot.query(AutorotateComponent, scrapbot.transform)
assert(first == repeated)
assert(first == reversed)

scrapbot.system({
	reads = { first },
}, function()
	local count = 0
	reversed:each(function(entity, transform, autorotate)
		count += 1
		assert(transform.rotation.y == 0)
		assert(autorotate.velocity.y == 2)
	end)
	assert(count == 1)
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)
	testing.expect(t, runtime.query_object_count == 1)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
}

@(test)
test_luau_query_matches_three_components :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a9000000-0000-4000-8000-000000000007"
name = "Spinner"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.mesh]
primitive = "cube"

[entities.components.autorotate]
velocity = [0, 2, 0]

[[entities]]
id = "a9000000-0000-4000-8000-000000000008"
name = "No Mesh"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.components.autorotate]
velocity = [0, 3, 0]
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

scrapbot.system({
	reads = { scrapbot.transform, scrapbot.mesh, AutorotateComponent },
}, function()
	local count = 0
	scrapbot.query(scrapbot.transform, scrapbot.mesh, AutorotateComponent):each(function(entity, transform, mesh, autorotate)
		count += 1
		assert(entity.name == "Spinner")
		assert(transform.rotation.y == 0)
		assert(mesh ~= nil)
		assert(autorotate.velocity.y == 2)
	end)
	assert(count == 1)
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
}

@(test)
test_luau_system_accepts_declared_component_access :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a9000000-0000-4000-8000-000000000009"
name = "Spinner"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.components.autorotate]
velocity = [0, 2, 0]
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})
assert(AutorotateComponent.id > 0)

scrapbot.system({
	reads = { AutorotateComponent },
	writes = { "scrapbot.transform" },
}, function(time)
	scrapbot.query(AutorotateComponent):each(function(entity, autorotate)
		local rotation = scrapbot.get_rotation(entity)
		rotation.y += autorotate.velocity.y * time.delta_time
		scrapbot.set_rotation(entity, rotation)
	end)
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)
	testing.expect(t, runtime.system_count == 1)
	testing.expect(t, runtime.systems[0].declaration.access_count == 2)
	testing.expect(t, runtime.systems[0].declaration.accesses[0].component == "autorotate")
	testing.expect(t, runtime.systems[0].declaration.accesses[0].mode == .Read)
	testing.expect(t, runtime.systems[0].declaration.accesses[1].component == "scrapbot.transform")
	testing.expect(t, runtime.systems[0].declaration.accesses[1].mode == .Write)
	testing.expect(t, len(world.custom_components) == 1)
	testing.expect(t, world.custom_components[0].component_id != shared.INVALID_COMPONENT_ID)
	autorotate_definition, autorotate_found := component.find_definition(
		&runtime.registry,
		"autorotate",
	)
	testing.expect(t, autorotate_found)
	testing.expect(t, world.custom_components[0].component_id == autorotate_definition.id)

	step_err := step_runtime(&runtime, &world, 0.5)
	testing.expect(t, step_err == "")
	testing.expect(t, world.transforms[0].rotation.y == 1)
}

@(test)
test_luau_view_returns_query_items_from_component_storage :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a9000000-0000-4000-8000-00000000000a"
name = "First"

[entities.components.autorotate]
velocity = [0, 1, 0]

[[entities]]
id = "a9000000-0000-4000-8000-00000000000b"
name = "Second"

[entities.components.autorotate]
velocity = [0, 2, 0]
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

scrapbot.system({
	reads = { AutorotateComponent },
}, function()
	local view = scrapbot.view(AutorotateComponent)
	assert(#view == 2)
	assert(view[1].entity.name == "First")
	assert(view[1].component.velocity.y == 1)
	assert(view[2].entity.name == "Second")
	assert(view[2].component.velocity.y == 2)
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
}

@(test)
test_luau_view_returns_multi_component_query_items :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a9000000-0000-4000-8000-00000000000c"
name = "Spinner"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 4, 0]
scale = [1, 1, 1]

[entities.components.autorotate]
velocity = [0, 2, 0]

[[entities]]
id = "a9000000-0000-4000-8000-00000000000d"
name = "Data Only"

[entities.components.autorotate]
velocity = [0, 3, 0]
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

scrapbot.system({
	reads = { scrapbot.transform, AutorotateComponent },
}, function()
	local view = scrapbot.view({ scrapbot.transform, AutorotateComponent })
	assert(#view == 1)
	assert(view[1].entity.name == "Spinner")
	assert(view[1].components[1].rotation.y == 4)
	assert(view[1].components[2].velocity.y == 2)
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
}

@(test)
test_luau_system_rejects_unregistered_access_components :: proc(t: ^testing.T) {
	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
scrapbot.system({
	writes = { "scrappyphysics.rigidbody" },
}, function() end)
`,
		"=test",
		nil,
	)

	testing.expect(t, !result.ran)
	testing.expect(
		t,
		result.err == "=test: system access declaration references unregistered component",
	)
}

@(test)
test_luau_declared_system_rejects_undeclared_component_reads :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a9000000-0000-4000-8000-00000000000e"
name = "Spinner"

[entities.components.autorotate]
velocity = [0, 1, 0]
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

scrapbot.system({
	reads = { "scrapbot.transform" },
}, function()
	scrapbot.view(AutorotateComponent)
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(
		t,
		step_err == "Luau system: system access declaration does not permit component read",
	)
}

@(test)
test_luau_declared_system_rejects_undeclared_multi_query_reads :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a9000000-0000-4000-8000-00000000000f"
name = "Spinner"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.components.autorotate]
velocity = [0, 1, 0]
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

scrapbot.system({
	reads = { AutorotateComponent },
}, function()
	scrapbot.query(scrapbot.transform, AutorotateComponent):each(function() end)
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(
		t,
		step_err == "Luau system: system access declaration does not permit component read",
	)
}

@(test)
test_luau_declared_system_accepts_query_object_reads :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a9000000-0000-4000-8000-000000000010"
name = "Spinner"

[entities.components.autorotate]
velocity = [0, 2, 0]
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})
local Autorotating = scrapbot.query(AutorotateComponent)

scrapbot.system({
	reads = { Autorotating },
}, function()
	local count = 0
	Autorotating:each(function(entity, autorotate)
		count += 1
		assert(autorotate.velocity.y == 2)
	end)
	assert(count == 1)
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)
	testing.expect(t, runtime.system_count == 1)
	testing.expect(t, runtime.systems[0].declaration.access_count == 1)
	testing.expect(t, runtime.systems[0].declaration.accesses[0].component == "autorotate")
	testing.expect(t, runtime.systems[0].declaration.accesses[0].mode == .Read)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
}

@(test)
test_luau_declared_system_rejects_undeclared_component_writes :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a9000000-0000-4000-8000-000000000011"
name = "Spinner"

[entities.components.autorotate]
velocity = [0, 1, 0]
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

scrapbot.system({
	reads = { AutorotateComponent },
}, function()
	scrapbot.query(AutorotateComponent):each(function(entity)
		scrapbot.remove_component(entity, AutorotateComponent)
	end)
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(
		t,
		step_err == "Luau system: system access declaration does not permit component write",
	)
}

@(test)
test_luau_declared_system_rejects_undeclared_spawn_component_writes :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a9000000-0000-4000-8000-000000000012"
name = "Source"
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

scrapbot.system({
	reads = { AutorotateComponent },
}, function()
	scrapbot.spawn({
		name = "Bad Spawn",
		components = {
			autorotate = {
				velocity = { x = 0, y = 1, z = 0 },
			},
		},
	})
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(
		t,
		step_err == "Luau system: system access declaration does not permit component write",
	)
	testing.expect(t, ecs.alive_entity_count(&world) == 1)
}
