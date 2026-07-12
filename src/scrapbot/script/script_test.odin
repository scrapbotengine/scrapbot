package script

import "core:testing"
import component "../component"
import ecs "../ecs"
import project "../project"
import resources "../resources"
import shared "../shared"

@(test)
test_luau_creates_full_geometry_material_and_renderable_entity :: proc(t: ^testing.T) {
	world: ecs.World; defer ecs.destroy_world(&world)
	registry: component.Registry; component.init_registry(&registry)
	resource_registry: resources.Registry; resources.init_registry(&resource_registry); defer resources.destroy_registry(&resource_registry)
	runtime: Runtime; defer destroy_runtime(&runtime)
	result := run_source_with_registry(&runtime, `
local triangle = scrapbot.geometry.create("triangle", {
  vertices = {
    { position = {x=-1,y=0,z=0}, normal = {x=0,y=0,z=1}, uv = {x=0,y=0} },
    { position = {x=1,y=0,z=0}, normal = {x=0,y=0,z=1}, uv = {x=1,y=0} },
    { position = {x=0,y=1,z=0}, normal = {x=0,y=0,z=1}, uv = {x=0.5,y=1} },
  }, indices = {0,1,2},
})
local red = scrapbot.material.unlit("red", 1, 0, 0, 1)
scrapbot.spawn({components = {
  ["scrapbot.transform"] = {position={x=0,y=0,z=0}, scale={x=1,y=1,z=1}},
  ["scrapbot.geometry"] = triangle,
  ["scrapbot.material"] = red,
}})
`, "=geometry-test", &world, &registry, Source_Options{resource_registry=&resource_registry})
	testing.expectf(t, result.err == "", "script failed: %s", result.err)
	testing.expect(t, ecs.apply_commands(&world, &runtime.commands) == "")
	ecs.reconcile_render_instances(&world, &resource_registry)
	testing.expect(t, len(world.entities) == 1)
	testing.expect(t, world.entities[0].render_instance_index >= 0)
	geometry, ok := resources.geometry_by_name(&resource_registry, "triangle")
	testing.expect(t, ok)
	geometry_data, valid := resources.get_geometry(&resource_registry, geometry)
	testing.expect(t, valid && len(geometry_data.indices) == 3)
}

@(test)
test_luau_registers_generated_geometry_primitives :: proc(t: ^testing.T) {
	world: ecs.World; defer ecs.destroy_world(&world)
	registry: component.Registry; component.init_registry(&registry)
	resource_registry: resources.Registry; resources.init_registry(&resource_registry); defer resources.destroy_registry(&resource_registry)
	runtime: Runtime; defer destroy_runtime(&runtime)
	result := run_source_with_registry(&runtime, `
scrapbot.geometry.icosphere("ico", 1, 1)
scrapbot.geometry.sphere("sphere", 1, 12, 8)
scrapbot.geometry.pyramid("pyramid", 2, 3, 2)
scrapbot.geometry.cylinder("cylinder", 1, 2, 12)
`, "=primitive-test", &world, &registry, Source_Options{resource_registry=&resource_registry})
	testing.expectf(t, result.err == "", "script failed: %s", result.err)
	names := [?]string{"ico","sphere","pyramid","cylinder"}
	for name in names {
		_, ok := resources.geometry_by_name(&resource_registry,name)
		testing.expectf(t,ok,"expected geometry %s",name)
	}
}

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
	velocity = scrapbot.vec3,
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
	velocity = scrapbot.vec3,
}) :: Component<Autorotate>

scrapbot.system(function(delta_seconds)
	scrapbot.query(AutorotateComponent):each(function(entity, autorotate: Autorotate)
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
test_luau_system_queries_transform_and_custom_component_together :: proc(t: ^testing.T) {
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
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})
assert(scrapbot.transform.id > 0)

local Autorotating = scrapbot.query(scrapbot.transform, AutorotateComponent)

scrapbot.system(Autorotating, {
	writes = { scrapbot.transform },
}, function(delta_seconds, entity, transform, autorotate)
	transform.rotation.y += autorotate.velocity.y * delta_seconds
end)
`, "=test", &world)
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
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

local Autorotating = scrapbot.query(scrapbot.transform, AutorotateComponent)

scrapbot.system(Autorotating, function(delta_seconds, entity, transform, autorotate)
	transform.rotation.y += autorotate.velocity.y * delta_seconds
end)
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 0.5)
	testing.expect(t, step_err == "Luau system: system access declaration does not permit component write")
	testing.expect(t, world.transforms[0].rotation.y == 0)
}

@(test)
test_luau_query_system_writes_project_component_payload :: proc(t: ^testing.T) {
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
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

local Autorotating = scrapbot.query(AutorotateComponent)

scrapbot.system(Autorotating, {
	writes = { AutorotateComponent },
}, function(delta_seconds, entity, autorotate)
	autorotate.velocity.y += 3 * delta_seconds
end)
`, "=test", &world)
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
test_luau_query_system_rejects_project_component_payload_write_without_access :: proc(t: ^testing.T) {
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
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

local Autorotating = scrapbot.query(AutorotateComponent)

scrapbot.system(Autorotating, function(delta_seconds, entity, autorotate)
	autorotate.velocity.y += 3 * delta_seconds
end)
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 0.5)
	testing.expect(t, step_err == "Luau system: system access declaration does not permit component write")

	autorotate_id := runtime.registry.definitions[3].id
	autorotate, ok := ecs.custom_component_for_entity(&world, 0, autorotate_id, "autorotate")
	testing.expect(t, ok)
	testing.expect(t, autorotate.vec3_fields[0].value.y == 2)
}

@(test)
test_luau_query_reuses_cached_object_for_same_component_set :: proc(t: ^testing.T) {
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
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)
	testing.expect(t, runtime.query_object_count == 1)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
}

@(test)
test_luau_query_matches_three_components :: proc(t: ^testing.T) {
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

[[entities]]
name = "No Mesh"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.components.autorotate]
velocity = [0, 3, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
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
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
}

@(test)
test_luau_system_accepts_declared_component_access :: proc(t: ^testing.T) {
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
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})
assert(AutorotateComponent.id > 0)

scrapbot.system({
	reads = { AutorotateComponent },
	writes = { "scrapbot.transform" },
}, function(delta_seconds)
	scrapbot.query(AutorotateComponent):each(function(entity, autorotate)
		local rotation = scrapbot.get_rotation(entity)
		rotation.y += autorotate.velocity.y * delta_seconds
		scrapbot.set_rotation(entity, rotation)
	end)
end)
`, "=test", &world)
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
	autorotate_definition, autorotate_found := component.find_definition(&runtime.registry, "autorotate")
	testing.expect(t, autorotate_found)
	testing.expect(t, world.custom_components[0].component_id == autorotate_definition.id)

	step_err := step_runtime(&runtime, &world, 0.5)
	testing.expect(t, step_err == "")
	testing.expect(t, world.transforms[0].rotation.y == 1)
}

@(test)
test_luau_view_returns_query_items_from_component_storage :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "First"

[entities.components.autorotate]
velocity = [0, 1, 0]

[[entities]]
name = "Second"

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
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
}

@(test)
test_luau_view_returns_multi_component_query_items :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Spinner"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 4, 0]
scale = [1, 1, 1]

[entities.components.autorotate]
velocity = [0, 2, 0]

[[entities]]
name = "Data Only"

[entities.components.autorotate]
velocity = [0, 3, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
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
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
}

@(test)
test_luau_system_rejects_unregistered_access_components :: proc(t: ^testing.T) {
	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
scrapbot.system({
	writes = { "scrappyphysics.rigidbody" },
}, function() end)
`, "=test", nil)

	testing.expect(t, !result.ran)
	testing.expect(t, result.err == "=test: system access declaration references unregistered component")
}

@(test)
test_luau_declared_system_rejects_undeclared_component_reads :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Spinner"

[entities.components.autorotate]
velocity = [0, 1, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

scrapbot.system({
	reads = { "scrapbot.transform" },
}, function()
	scrapbot.view(AutorotateComponent)
end)
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "Luau system: system access declaration does not permit component read")
}

@(test)
test_luau_declared_system_rejects_undeclared_multi_query_reads :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Spinner"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.components.autorotate]
velocity = [0, 1, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})

scrapbot.system({
	reads = { AutorotateComponent },
}, function()
	scrapbot.query(scrapbot.transform, AutorotateComponent):each(function() end)
end)
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "Luau system: system access declaration does not permit component read")
}

@(test)
test_luau_declared_system_accepts_query_object_reads :: proc(t: ^testing.T) {
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
`, "=test", &world)
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
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Spinner"

[entities.components.autorotate]
velocity = [0, 1, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
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
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "Luau system: system access declaration does not permit component write")
}

@(test)
test_luau_declared_system_rejects_undeclared_spawn_component_writes :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Source"
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
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
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "Luau system: system access declaration does not permit component write")
	testing.expect(t, ecs.alive_entity_count(&world) == 1)
}

@(test)
test_luau_spawn_is_deferred_until_after_system_step :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Source"
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
local frame = 0

scrapbot.system(function()
	frame += 1
	if frame == 1 then
		assert(scrapbot.entity_count() == 1)
		scrapbot.spawn({ name = "Deferred Spawn" })
		assert(scrapbot.entity_count() == 1)
	else
		assert(scrapbot.entity_count() == 2)
	end
end)
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
	testing.expect(t, ecs.alive_entity_count(&world) == 2)
	testing.expect(t, world.entities[1].name == "Deferred Spawn")

	step_err = step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
	testing.expect(t, ecs.alive_entity_count(&world) == 2)
}

@(test)
test_luau_despawn_is_deferred_until_after_query_iteration :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "First"

[entities.components.autorotate]
velocity = [0, 1, 0]

[[entities]]
name = "Second"

[entities.components.autorotate]
velocity = [0, 1, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})
local frame = 0

scrapbot.system(function()
	frame += 1
	local query_count = 0
	scrapbot.query(AutorotateComponent):each(function(entity)
		query_count += 1
		if frame == 1 then
			scrapbot.despawn(entity)
		end
	end)

	if frame == 1 then
		assert(query_count == 2)
		assert(scrapbot.entity_count() == 2)
	else
		assert(query_count == 0)
		assert(scrapbot.entity_count() == 0)
	end
end)
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
	testing.expect(t, ecs.alive_entity_count(&world) == 0)

	step_err = step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
	testing.expect(t, ecs.alive_entity_count(&world) == 0)
}

@(test)
test_luau_deferred_commands_are_discarded_when_system_errors :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Source"
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
local frame = 0

scrapbot.system(function()
	frame += 1
	if frame == 1 then
		scrapbot.spawn({ name = "Should Not Exist" })
		error("failed frame")
	end
end)
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err != "")
	testing.expect(t, ecs.alive_entity_count(&world) == 1)

	step_err = step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
	testing.expect(t, ecs.alive_entity_count(&world) == 1)
}

@(test)
test_luau_spawn_can_include_initial_transform_and_custom_components :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Source"
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})
local frame = 0

scrapbot.system(function()
	frame += 1
	if frame == 1 then
		scrapbot.spawn({
			name = "Spawned Spinner",
			components = {
				["scrapbot.transform"] = {
					position = { x = 1, y = 2, z = 3 },
					rotation = { x = 0, y = 4, z = 0 },
					scale = { x = 1, y = 1, z = 1 },
				},
				autorotate = {
					velocity = { x = 0, y = 5, z = 0 },
				},
			},
		})
	else
		local query_count = 0
		scrapbot.query(AutorotateComponent):each(function(entity, autorotate)
			query_count += 1
			assert(entity.name == "Spawned Spinner")
			assert(autorotate.velocity.y == 5)
			local rotation = scrapbot.get_rotation(entity)
			assert(rotation.y == 4)
		end)
		assert(query_count == 1)
	end
end)
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
	testing.expect(t, ecs.alive_entity_count(&world) == 2)
	testing.expect(t, world.entities[1].name == "Spawned Spinner")
	testing.expect(t, world.entities[1].transform_index >= 0)

	step_err = step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
}

@(test)
test_luau_add_component_is_deferred_until_after_system_step :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Target"
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})
local frame = 0
local target = nil

scrapbot.system(function()
	frame += 1
	if frame == 1 then
		assert(scrapbot.entity_count() == 1)
		scrapbot.spawn({ name = "Probe" })
	elseif frame == 2 then
		scrapbot.query(AutorotateComponent):each(function()
			error("component should not exist before add")
		end)
	end
end)

scrapbot.system(function()
	if frame == 1 then
		return
	end
	if frame == 2 then
		scrapbot.query(AutorotateComponent):each(function()
			error("component should still be deferred")
		end)
		target = { index = 1, generation = 1 }
		scrapbot.add_component(target, AutorotateComponent, {
			velocity = { x = 0, y = 7, z = 0 },
		})
	else
		local query_count = 0
		scrapbot.query(AutorotateComponent):each(function(entity, autorotate)
			query_count += 1
			assert(entity.index == 1)
			assert(autorotate.velocity.y == 7)
		end)
		assert(query_count == 1)
	end
end)
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
	step_err = step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
	step_err = step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
}

@(test)
test_luau_remove_component_is_deferred_until_after_query_iteration :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Spinner"

[entities.components.autorotate]
velocity = [0, 1, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})
local frame = 0

scrapbot.system(function()
	frame += 1
	local query_count = 0
	scrapbot.query(AutorotateComponent):each(function(entity)
		query_count += 1
		if frame == 1 then
			scrapbot.remove_component(entity, AutorotateComponent)
		end
	end)

	if frame == 1 then
		assert(query_count == 1)
	else
		assert(query_count == 0)
	end
end)
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
	step_err = step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
}

@(test)
test_luau_entity_handles_reject_stale_generations :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(`[[entities]]
name = "Spinner"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.components.autorotate]
velocity = [0, 1, 0]
`)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(&runtime, `
local AutorotateComponent = scrapbot.component("autorotate", {
	velocity = scrapbot.vec3,
})
local saved = nil
local frame = 0

scrapbot.system(function()
	frame += 1
	if frame == 1 then
		scrapbot.query(AutorotateComponent):each(function(entity)
			saved = entity
			scrapbot.despawn(entity)
		end)
	else
		assert(scrapbot.get_rotation(saved) == nil)
		scrapbot.set_rotation(saved, { x = 9, y = 9, z = 9 })
	end
end)
`, "=test", &world)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
	testing.expect(t, ecs.alive_entity_count(&world) == 0)
	step_err = step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
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
}, function(delta_seconds, entity, rigidbody)
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
scrapbot.system(Rigidbodies, function(delta_seconds, entity, rigidbody)
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
