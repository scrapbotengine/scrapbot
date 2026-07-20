package script

import component "../component"
import ecs "../ecs"
import project "../project"
import resources "../resources"
import shared "../shared"
import "core:testing"

@(test)
test_luau_custom_component_writeback_supports_all_numeric_field_shapes :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a7000000-0000-4000-8000-000000000010"
name = "Typed"
[entities.components.typed]
amount = 1
uv = [2, 3]
direction = [4, 5, 6]
tint = [0.1, 0.2, 0.3, 0.4]
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
local Typed = scrapbot.component("typed", {
	amount = scrapbot.field(scrapbot.number, { draggable = true, step = 0.25, minimum = 0 }),
	uv = scrapbot.vec2,
	direction = scrapbot.vec3,
	tint = scrapbot.color,
})
scrapbot.system(scrapbot.query(Typed), { writes = { Typed } }, function(_, _, value)
	value.amount = 7
	value.uv = { x = 8, y = 9 }
	value.direction = { x = 10, y = 11, z = 12 }
	value.tint = { x = 0.5, y = 0.6, z = 0.7, w = 0.8 }
end)
`,
		"=test",
		&world,
	)
	testing.expectf(t, result.err == "", "script failed: %s", result.err)
	testing.expect(t, result.ran)
	testing.expect(t, step_runtime(&runtime, &world, 1.0) == "")
	definition, registered := component.find_definition(&runtime.registry, "typed")
	testing.expect(t, registered)
	custom, found := ecs.custom_component_for_entity_ref(&world, 0, definition.id, "typed")
	testing.expect(t, found)
	if found {
		testing.expect(t, custom.number_fields[0].value == 7)
		testing.expect(t, custom.vec2_fields[0].value == shared.Vec2{8, 9})
		testing.expect(t, custom.vec3_fields[0].value == shared.Vec3{10, 11, 12})
		testing.expect(t, custom.vec4_fields[0].value == shared.Vec4{0.5, 0.6, 0.7, 0.8})
	}
	if registered {
		amount, found := component.lookup_field_definition(definition, "amount")
		testing.expect(t, found)
		testing.expect(t, amount.editor.draggable)
		testing.expect(t, amount.editor.step == 0.25)
		testing.expect(t, amount.editor.has_minimum)
	}
}

@(test)
test_luau_spawn_is_deferred_until_after_system_step :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a7000000-0000-4000-8000-000000000001"
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
`,
		"=test",
		&world,
	)
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
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a7000000-0000-4000-8000-000000000002"
name = "First"

[entities.components.autorotate]
velocity = [0, 1, 0]

[[entities]]
id = "a7000000-0000-4000-8000-000000000003"
name = "Second"

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
`,
		"=test",
		&world,
	)
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
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a7000000-0000-4000-8000-000000000004"
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
local frame = 0

scrapbot.system(function()
	frame += 1
	if frame == 1 then
		scrapbot.spawn({ name = "Should Not Exist" })
		error("failed frame")
	end
end)
`,
		"=test",
		&world,
	)
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
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a7000000-0000-4000-8000-000000000005"
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
`,
		"=test",
		&world,
	)
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
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a7000000-0000-4000-8000-000000000006"
name = "Target"
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
`,
		"=test",
		&world,
	)
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
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a7000000-0000-4000-8000-000000000007"
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
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
	step_err = step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
}

@(test)
test_luau_entity_handles_reject_stale_generations :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "a7000000-0000-4000-8000-000000000008"
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
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)

	step_err := step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
	testing.expect(t, ecs.alive_entity_count(&world) == 0)
	step_err = step_runtime(&runtime, &world, 1.0)
	testing.expect(t, step_err == "")
}
