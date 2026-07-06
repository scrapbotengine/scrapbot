package main

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_load_project_prefers_canonical_metadata :: proc(t: ^testing.T) {
	root := make_test_project(t, "prefers-canonical")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, LEGACY_PROJECT_FILE_NAME, "name = \"Legacy\"\nversion = 1\ndefault_scene = \"scenes/legacy.scene.toml\"\n")
	write_file(t, root, PROJECT_FILE_NAME, "name = \"Canonical\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	testing.expect_value(t, result.project.name, "Canonical")
	testing.expect_value(t, result.project.default_scene, "scenes/main.scene.toml")
}

@(test)
test_load_project_accepts_legacy_metadata :: proc(t: ^testing.T) {
	root := make_test_project(t, "accepts-legacy")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, LEGACY_PROJECT_FILE_NAME, "name = \"Legacy\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	testing.expect_value(t, result.project.name, "Legacy")
}

@(test)
test_check_project_rejects_unsupported_version :: proc(t: ^testing.T) {
	root := make_test_project(t, "unsupported-version")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 99\ndefault_scene = \"scenes/main.scene.toml\"\n")

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Unsupported_Project_Version)
}

@(test)
test_check_project_rejects_unsafe_default_scene :: proc(t: ^testing.T) {
	root := make_test_project(t, "unsafe-default-scene")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"../outside.scene.toml\"\n")

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Default_Scene)
}

@(test)
test_check_project_reports_missing_default_scene :: proc(t: ^testing.T) {
	root := make_test_project(t, "missing-default-scene")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/missing.scene.toml\"\n")

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Missing_Default_Scene)
}

@(test)
test_check_project_reports_missing_script :: proc(t: ^testing.T) {
	root := make_test_project(t, "missing-script")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Missing_Script)
}

@(test)
test_check_project_builds_script_system_schedules :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-system-schedules")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")
	write_file(t, root, "scripts/gameplay.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({}),
})

local Flags = ecs.query(Flag)

ecs.system("prepare_flags", {
  phase = "startup",
  writes = ecs.refs(Flag),
})

ecs.system("observe_flags", {
  query = Flags,
  after = { "prepare_flags" },
  run = function(world, dt)
  end,
})
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	testing.expect_value(t, runtime_system_schedule_system_count(result.startup_schedule), 1)
	testing.expect_value(t, runtime_system_schedule_system_count(result.update_schedule), 1)
	testing.expect_value(t, result.startup_schedule.batches[0].systems[0].id, "prepare_flags")
	testing.expect_value(t, result.update_schedule.batches[0].systems[0].id, "observe_flags")
	testing.expect_value(t, result.startup_schedule.batches[0].systems[0].runner.kind, Runtime_System_Runner_Kind.None)
	testing.expect_value(t, result.update_schedule.batches[0].systems[0].runner.kind, Runtime_System_Runner_Kind.Luau)
	testing.expect(t, result.update_schedule.batches[0].systems[0].runner.ref != 0)
}

@(test)
test_run_script_simulation_updates_vec3_fields :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-updates-vec3")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "cube"
name = "Cube"

[entities.components."scrapbot.transform"]
position = [0.0, 0.0, 0.0]
rotation = [0.0, 0.0, 0.0]
scale = [1.0, 1.0, 1.0]

[entities.components.spin]
angular_velocity = [1.0, 2.0, 3.0]

[entities.components.label]
value = "idle"
`)
	write_file(t, root, "scripts/gameplay.luau", `local Transform = ecs.component("scrapbot.transform")
local Spin = ecs.component("spin", {
  fields = ecs.fields({
    angular_velocity = "vec3",
  }),
})
local Label = ecs.component("label", {
  fields = ecs.fields({
    value = "string",
  }),
})

local Spinning = ecs.query(Transform, Spin)
local Labels = ecs.query(Label)

ecs.system("spin_cubes", {
  query = Spinning,
  writes = ecs.refs(Transform),
  run = function(world, dt)
    for _entity, transform, spin in Spinning:iter(world) do
      transform.rotation = {
        transform.rotation[1] + spin.angular_velocity[1] * dt,
        transform.rotation[2] + spin.angular_velocity[2] * dt,
        transform.rotation[3] + spin.angular_velocity[3] * dt,
      }
    end
  end,
})

ecs.system("mark_labels", {
  query = Labels,
  writes = ecs.refs(Label),
  run = function(world, dt)
    for _entity, label in Labels:iter(world) do
      label.value = "updated"
    end
  end,
})
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	simulation := run_script_simulation(&result, 2, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, true)
	testing.expect_value(t, simulation.completed_frames, 2)
	entity, found := runtime_world_find_entity_by_id(result.scene.world, "cube")
	testing.expect_value(t, found, true)
	rotation, rotation_err := runtime_world_get_component_field_value(result.scene.world, entity, TRANSFORM_COMPONENT_ID, "rotation")
	testing.expect_value(t, rotation_err, Runtime_Error.None)
	testing.expect_value(t, rotation.vec3, [3]f32{1.0, 2.0, 3.0})
	label, label_err := runtime_world_get_component_field_value(result.scene.world, entity, "label", "value")
	testing.expect_value(t, label_err, Runtime_Error.None)
	testing.expect_value(t, label.string_value, "updated")
}

@(test)
test_run_script_simulation_reports_runtime_access_diagnostic :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-runtime-diagnostic")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "cube"
name = "Cube"

[entities.components."scrapbot.transform"]
position = [0.0, 0.0, 0.0]
rotation = [0.0, 0.0, 0.0]
scale = [1.0, 1.0, 1.0]
`)
	write_file(t, root, "scripts/gameplay.luau", `local Transform = ecs.component("scrapbot.transform")
local Transforms = ecs.query(Transform)

ecs.system("bad_writer", {
  query = Transforms,
  run = function(world, dt)
    for _entity, transform in Transforms:iter(world) do
      transform.rotation = { dt, 0.0, 0.0 }
    end
  end,
})
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	simulation := run_script_simulation(&result, 1, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, false)
	testing.expect_value(t, simulation.completed_frames, 0)
	testing.expect_value(t, simulation.diagnostic.stage, Script_Diagnostic_Stage.Runtime)
	testing.expect_value(t, simulation.diagnostic.path, "scripts/gameplay.luau")
	testing.expect_value(t, simulation.diagnostic.system_id, "bad_writer")
	testing.expect(t, strings.contains(simulation.diagnostic.message, "bad_writer"))
	testing.expect(t, strings.contains(simulation.diagnostic.message, "scrapbot.transform.rotation"))
	testing.expect(t, strings.contains(simulation.diagnostic.message, "without declaring"))
}

@(test)
test_run_script_simulation_reports_runtime_field_context_diagnostic :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-runtime-field-context")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "stats"
name = "Stats"

[entities.components.stats]
health = 10
`)
	write_file(t, root, "scripts/gameplay.luau", `local Stats = ecs.component("stats", {
  fields = ecs.fields({
    health = "int",
  }),
})
local StatsQuery = ecs.query(Stats)

ecs.system("read_missing_field", {
  query = StatsQuery,
  run = function(world, dt)
    for _entity, stats in StatsQuery:iter(world) do
      local missing = stats.missing
    end
  end,
})
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	simulation := run_script_simulation(&result, 1, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, false)
	testing.expect_value(t, simulation.completed_frames, 0)
	testing.expect_value(t, simulation.diagnostic.stage, Script_Diagnostic_Stage.Runtime)
	testing.expect_value(t, simulation.diagnostic.path, "scripts/gameplay.luau")
	testing.expect_value(t, simulation.diagnostic.system_id, "read_missing_field")
	testing.expect(t, strings.contains(simulation.diagnostic.message, "read_missing_field"))
	testing.expect(t, strings.contains(simulation.diagnostic.message, "stats.missing"))
	testing.expect(t, strings.contains(simulation.diagnostic.message, "Unknown_Field"))
}

@(test)
test_run_script_simulation_reports_native_odin_execution_diagnostic :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-native-odin-diagnostic")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nnative = \"native/game.odin\"\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")
	write_file(t, root, "native/game.odin", `package game

scrapbot_register :: proc(api: ^scrapbot.Register_Api) -> bool {
    scrapbot.register_system(api, {
        id = "native_tick",
        phase = .Update,
    })
    return true
}
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	testing.expect_value(t, runtime_system_schedule_system_count(result.update_schedule), 1)
	simulation := run_script_simulation(&result, 1, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, false)
	testing.expect_value(t, simulation.completed_frames, 0)
	testing.expect_value(t, simulation.diagnostic.stage, Script_Diagnostic_Stage.Runtime)
	testing.expect_value(t, simulation.diagnostic.system_id, "native_tick")
	testing.expect(t, strings.contains(simulation.diagnostic.message, "native Odin system execution is not ported yet"))
}

@(test)
test_run_script_simulation_supports_direct_vec3_methods :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-direct-vec3")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "cube"
name = "Cube"

[entities.components."scrapbot.transform"]
position = [1.0, 2.0, 3.0]
rotation = [0.0, 0.0, 0.0]
scale = [1.0, 1.0, 1.0]
`)
	write_file(t, root, "scripts/gameplay.luau", `local Transform = ecs.component("scrapbot.transform")
local Transforms = ecs.query(Transform)

ecs.system("direct_vec3", {
  query = Transforms,
  writes = ecs.refs(Transform),
  run = function(world, dt)
    for entity, transform in Transforms:iter(world) do
      local position = entity:get_vec3("scrapbot.transform", "position")
      entity:set_vec3("scrapbot.transform", "rotation", { position[1] + dt, position[2] + dt, position[3] + dt })
    end
  end,
})
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	simulation := run_script_simulation(&result, 1, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, true)
	entity, found := runtime_world_find_entity_by_id(result.scene.world, "cube")
	testing.expect_value(t, found, true)
	rotation, rotation_err := runtime_world_get_component_field_value(result.scene.world, entity, TRANSFORM_COMPONENT_ID, "rotation")
	testing.expect_value(t, rotation_err, Runtime_Error.None)
	testing.expect_value(t, rotation.vec3, [3]f32{1.5, 2.5, 3.5})
}

@(test)
test_run_script_simulation_reports_direct_vec3_write_access_diagnostic :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-direct-vec3-diagnostic")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "cube"
name = "Cube"

[entities.components."scrapbot.transform"]
position = [0.0, 0.0, 0.0]
rotation = [0.0, 0.0, 0.0]
scale = [1.0, 1.0, 1.0]
`)
	write_file(t, root, "scripts/gameplay.luau", `local Transform = ecs.component("scrapbot.transform")
local Transforms = ecs.query(Transform)

ecs.system("bad_vec3_writer", {
  query = Transforms,
  run = function(world, dt)
    for entity, transform in Transforms:iter(world) do
      entity:set_vec3("scrapbot.transform", "rotation", { dt, 0.0, 0.0 })
    end
  end,
})
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	simulation := run_script_simulation(&result, 1, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, false)
	testing.expect_value(t, simulation.completed_frames, 0)
	testing.expect_value(t, simulation.diagnostic.stage, Script_Diagnostic_Stage.Runtime)
	testing.expect_value(t, simulation.diagnostic.path, "scripts/gameplay.luau")
	testing.expect_value(t, simulation.diagnostic.system_id, "bad_vec3_writer")
	testing.expect(t, strings.contains(simulation.diagnostic.message, "bad_vec3_writer"))
	testing.expect(t, strings.contains(simulation.diagnostic.message, "scrapbot.transform.rotation"))
	testing.expect(t, strings.contains(simulation.diagnostic.message, "without declaring"))
}

@(test)
test_run_script_simulation_supports_bulk_query_views :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-bulk-query-view")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "first"
name = "First"

[entities.components.motion]
position = [1.0, 2.0, 3.0]
velocity = [2.0, 0.0, -2.0]
speed = 10.0

[[entities]]
id = "second"
name = "Second"

[entities.components.motion]
position = [-1.0, 4.0, 0.5]
velocity = [0.0, -4.0, 1.0]
speed = 20.0
`)
	write_file(t, root, "scripts/gameplay.luau", `local Motion = ecs.component("motion", {
  fields = ecs.fields({
    position = "vec3",
    velocity = "vec3",
    speed = "f32",
  }),
})
local Movers = ecs.query(Motion)

ecs.system("advance_movers", {
  query = Movers,
  writes = ecs.refs(Motion),
  run = function(world, dt)
    local view = Movers:view(world)
    local count = view:count()
    local positions = view:read_vec3(Motion, "position")
    local velocities = view:read_vec3(Motion, "velocity")
    local speeds = view:read_f32(Motion, "speed")

    for index = 0, count - 1 do
      local f32_offset = index * 4
      local vec3_offset = index * 12
      local px = buffer.readf32(positions, vec3_offset)
      local py = buffer.readf32(positions, vec3_offset + 4)
      local pz = buffer.readf32(positions, vec3_offset + 8)
      local vx = buffer.readf32(velocities, vec3_offset)
      local vy = buffer.readf32(velocities, vec3_offset + 4)
      local vz = buffer.readf32(velocities, vec3_offset + 8)
      buffer.writef32(positions, vec3_offset, px + vx * dt)
      buffer.writef32(positions, vec3_offset + 4, py + vy * dt)
      buffer.writef32(positions, vec3_offset + 8, pz + vz * dt)
      buffer.writef32(speeds, f32_offset, buffer.readf32(speeds, f32_offset) + dt)
    end

    view:write_vec3(Motion, "position", positions)
    view:write_f32(Motion, "speed", speeds)
  end,
})
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	simulation := run_script_simulation(&result, 1, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, true)

	first, first_found := runtime_world_find_entity_by_id(result.scene.world, "first")
	testing.expect_value(t, first_found, true)
	first_position, first_position_err := runtime_world_get_component_field_value(result.scene.world, first, "motion", "position")
	testing.expect_value(t, first_position_err, Runtime_Error.None)
	testing.expect_value(t, first_position.vec3, [3]f32{2.0, 2.0, 2.0})
	first_speed, first_speed_err := runtime_world_get_component_field_value(result.scene.world, first, "motion", "speed")
	testing.expect_value(t, first_speed_err, Runtime_Error.None)
	testing.expect_value(t, first_speed.float, f32(10.5))

	second, second_found := runtime_world_find_entity_by_id(result.scene.world, "second")
	testing.expect_value(t, second_found, true)
	second_position, second_position_err := runtime_world_get_component_field_value(result.scene.world, second, "motion", "position")
	testing.expect_value(t, second_position_err, Runtime_Error.None)
	testing.expect_value(t, second_position.vec3, [3]f32{-1.0, 2.0, 1.0})
	second_speed, second_speed_err := runtime_world_get_component_field_value(result.scene.world, second, "motion", "speed")
	testing.expect_value(t, second_speed_err, Runtime_Error.None)
	testing.expect_value(t, second_speed.float, f32(20.5))
}

@(test)
test_run_script_simulation_reports_bulk_query_view_write_access_diagnostic :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-bulk-query-view-diagnostic")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "stats"
name = "Stats"

[entities.components.stats]
speed = 1.5
`)
	write_file(t, root, "scripts/gameplay.luau", `local Stats = ecs.component("stats", {
  fields = ecs.fields({
    speed = "f32",
  }),
})
local StatsQuery = ecs.query(Stats)

ecs.system("write_without_access", {
  query = StatsQuery,
  run = function(world, dt)
    local view = StatsQuery:view(world)
    local speeds = view:read_f32(Stats, "speed")
    view:write_f32(Stats, "speed", speeds)
  end,
})
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	simulation := run_script_simulation(&result, 1, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, false)
	testing.expect_value(t, simulation.completed_frames, 0)
	testing.expect_value(t, simulation.diagnostic.stage, Script_Diagnostic_Stage.Runtime)
	testing.expect_value(t, simulation.diagnostic.path, "scripts/gameplay.luau")
	testing.expect_value(t, simulation.diagnostic.system_id, "write_without_access")
	testing.expect(t, strings.contains(simulation.diagnostic.message, "bulk-write"))

	entity, found := runtime_world_find_entity_by_id(result.scene.world, "stats")
	testing.expect_value(t, found, true)
	speed, speed_err := runtime_world_get_component_field_value(result.scene.world, entity, "stats", "speed")
	testing.expect_value(t, speed_err, Runtime_Error.None)
	testing.expect_value(t, speed.float, f32(1.5))
}

@(test)
test_run_script_simulation_rejects_nonfinite_bulk_query_view_write :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-bulk-query-view-nonfinite")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "stats"
name = "Stats"

[entities.components.stats]
speed = 1.5
`)
	write_file(t, root, "scripts/gameplay.luau", `local Stats = ecs.component("stats", {
  fields = ecs.fields({
    speed = "f32",
  }),
})
local StatsQuery = ecs.query(Stats)

ecs.system("write_bad_value", {
  query = StatsQuery,
  writes = ecs.refs(Stats),
  run = function(world, dt)
    local view = StatsQuery:view(world)
    local speeds = view:read_f32(Stats, "speed")
    buffer.writef32(speeds, 0, 1e100)
    view:write_f32(Stats, "speed", speeds)
  end,
})
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	simulation := run_script_simulation(&result, 1, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, false)
	testing.expect_value(t, simulation.completed_frames, 0)
	testing.expect_value(t, simulation.diagnostic.stage, Script_Diagnostic_Stage.Runtime)
	testing.expect_value(t, simulation.diagnostic.system_id, "write_bad_value")
	testing.expect(t, strings.contains(simulation.diagnostic.message, "non-finite"))

	entity, found := runtime_world_find_entity_by_id(result.scene.world, "stats")
	testing.expect_value(t, found, true)
	speed, speed_err := runtime_world_get_component_field_value(result.scene.world, entity, "stats", "speed")
	testing.expect_value(t, speed_err, Runtime_Error.None)
	testing.expect_value(t, speed.float, f32(1.5))
}

@(test)
test_run_script_simulation_flushes_structural_commands :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-structural-flush")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")
	write_file(t, root, "scripts/gameplay.luau", `local Marker = ecs.component("marker", {
  fields = ecs.fields({
    value = "int",
  }),
})

ecs.system("spawn_marker", {
  phase = "startup",
  writes = ecs.refs(Marker),
  run = function(world, dt)
    local entity = world.spawn("spawned", "Spawned")
    entity:add(Marker, { value = 42 })
  end,
})
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	simulation := run_script_simulation(&result, 0, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, true)
	entity, found := runtime_world_find_entity_by_id(result.scene.world, "spawned")
	testing.expect_value(t, found, true)
	marker, marker_err := runtime_world_get_component_field_value(result.scene.world, entity, "marker", "value")
	testing.expect_value(t, marker_err, Runtime_Error.None)
	testing.expect_value(t, marker.int_value, 42)
}

@(test)
test_run_script_simulation_despawns_after_system_success :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-despawn")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "doomed"
name = "Doomed"

[entities.components.marker]
`)
	write_file(t, root, "scripts/gameplay.luau", `local Marker = ecs.component("marker", {
  fields = ecs.fields({}),
})

local Markers = ecs.query(Marker)

ecs.system("despawn_markers", {
  query = Markers,
  writes = ecs.refs(Marker),
  run = function(world, dt)
    for entity, marker in Markers:iter(world) do
      entity:despawn()
    end
  end,
})
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	simulation := run_script_simulation(&result, 1, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, true)
	_, found := runtime_world_find_entity_by_id(result.scene.world, "doomed")
	testing.expect_value(t, found, false)
}

@(test)
test_run_script_simulation_removes_component_after_system_success :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-remove-component")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "tagged"
name = "Tagged"

[entities.components.marker]
`)
	write_file(t, root, "scripts/gameplay.luau", `local Marker = ecs.component("marker", {
  fields = ecs.fields({}),
})

local Markers = ecs.query(Marker)

ecs.system("remove_markers", {
  query = Markers,
  writes = ecs.refs(Marker),
  run = function(world, dt)
    for entity, marker in Markers:iter(world) do
      entity:remove(Marker)
    end
  end,
})
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	simulation := run_script_simulation(&result, 1, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, true)
	entity, found := runtime_world_find_entity_by_id(result.scene.world, "tagged")
	testing.expect_value(t, found, true)
	has_marker, has_err := runtime_world_has_component(result.scene.world, entity, "marker")
	testing.expect_value(t, has_err, Runtime_Error.None)
	testing.expect_value(t, has_marker, false)
}

@(test)
test_run_script_simulation_rolls_back_spawn_after_structural_failure :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-structural-rollback")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")
	write_file(t, root, "scripts/gameplay.luau", `local Marker = ecs.component("marker", {
  fields = ecs.fields({
    value = "int",
  }),
})

ecs.system("bad_spawn", {
  phase = "startup",
  run = function(world, dt)
    local entity = world.spawn("rolled-back", "Rolled Back")
    entity:add(Marker, { value = 1 })
  end,
})
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	simulation := run_script_simulation(&result, 0, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, false)
	testing.expect_value(t, simulation.diagnostic.stage, Script_Diagnostic_Stage.Runtime)
	testing.expect_value(t, simulation.diagnostic.system_id, "bad_spawn")
	_, found := runtime_world_find_entity_by_id(result.scene.world, "rolled-back")
	testing.expect_value(t, found, false)
}

@(test)
test_check_project_rejects_cyclic_script_system_order :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-system-cycle")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")
	write_file(t, root, "scripts/gameplay.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({}),
})

ecs.system("first", {
  after = { "second" },
  writes = ecs.refs(Flag),
})

ecs.system("second", {
  after = { "first" },
  writes = ecs.refs(Flag),
})
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Script)
	testing.expect_value(t, result.diagnostic.stage, Script_Diagnostic_Stage.Schedule)
	testing.expect_value(t, result.diagnostic.message, "failed to build script schedule: update")
}

@(test)
test_check_project_returns_script_load_diagnostic :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-load-diagnostic")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")
	write_file(t, root, "scripts/gameplay.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({}),
})

ecs.system("broken", {
  writes = ecs.refs(Missing),
})
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Script)
	testing.expect_value(t, result.diagnostic.stage, Script_Diagnostic_Stage.Load)
	testing.expect_value(t, result.diagnostic.path, "scripts/gameplay.luau")
	testing.expect_value(t, result.diagnostic.system_id, "")
	testing.expect_value(t, result.diagnostic.has_start, true)
	testing.expect_value(t, result.diagnostic.start.line, 6)
	testing.expect(t, strings.contains(result.diagnostic.message, "invalid argument #1 to 'ecs.refs'"))
}

make_test_project :: proc(t: ^testing.T, name: string) -> string {
	root, join_err := filepath.join([]string{"odin-out", "odin-tests", name})
	if join_err != nil {
		testing.fail_now(t, "failed to join test project path")
	}
	os.remove_all(root)
	scenes_path, scenes_join_err := filepath.join([]string{root, "scenes"})
	if scenes_join_err != nil {
		testing.fail_now(t, "failed to join scenes path")
	}
	defer delete(scenes_path)
	err := os.mkdir_all(scenes_path)
	if err != nil {
		testing.fail_now(t, "failed to create test project")
	}
	return root
}

write_file :: proc(t: ^testing.T, root, relative_path, contents: string) {
	path, join_err := filepath.join([]string{root, relative_path})
	if join_err != nil {
		testing.fail_now(t, "failed to join test file path")
	}
	defer delete(path)
	dir, _ := filepath.split(path)
	if dir != "" && !os.exists(dir) {
		err := os.mkdir_all(dir)
		if err != nil {
			testing.fail_now(t, "failed to create test directory")
		}
	}
	err := os.write_entire_file(path, contents)
	if err != nil {
		testing.fail_now(t, "failed to write test file")
	}
}

write_valid_scene_file :: proc(t: ^testing.T, root, relative_path: string) {
	write_file(
		t,
		root,
		relative_path,
		`name = "Main"
version = 1

[[entities]]
id = "entity"
name = "Entity"

[entities.components."scrapbot.ui.button"]
`,
	)
}
