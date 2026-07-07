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
test_run_script_simulation_executes_native_odin_set_field_operation :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-native-odin-set-field")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nnative = \"native/game.odin\"\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.stats]
count = 0
`)
	write_file(t, root, "native/game.odin", `package game

stats_fields := []scrapbot.Component_Field{
    {name = "count", field_type = .Int},
}

native_tick_writes := []string{"stats"}

scrapbot_register :: proc(api: ^scrapbot.Register_Api) -> bool {
    scrapbot.register_component(api, {
        id = "stats",
        fields = stats_fields[:],
    })
    scrapbot.register_system(api, {
        id = "native_tick",
        phase = .Update,
        writes = native_tick_writes[:],
        execute = {
            entity = "target",
            component = "stats",
            field = "count",
            value = 2,
        },
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
	testing.expect_value(t, simulation.ok, true)
	testing.expect_value(t, simulation.completed_frames, 1)
	entity, entity_found := runtime_world_find_entity_by_id(result.scene.world, "target")
	testing.expect(t, entity_found)
	value, value_err := runtime_world_get_component_field_value(result.scene.world, entity, "stats", "count")
	testing.expect_value(t, value_err, Runtime_Error.None)
	testing.expect_value(t, value.value_type, Runtime_Field_Type.Int)
	testing.expect_value(t, value.int_value, 2)
}

@(test)
test_run_script_simulation_executes_packaged_odin_native_artifact_callback :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-packaged-odin-native")
	defer os.remove_all(root)
	defer delete(root)
	output_root := make_test_project_root(t, "script-simulation-packaged-odin-native-output")
	defer os.remove_all(output_root)
	defer delete(output_root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nnative = \"native/game.odin\"\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.stats]
count = 1
ready = true
gain = 1.5
direction = [1.0, 2.0, 3.0]
label = "start"

[[entities]]
id = "marked"
name = "Marked"

[entities.components.marker]
value = 3

[[entities]]
id = "doomed"
name = "Doomed"

[entities.components.marker]
value = 4
`)
	write_file(t, root, "native/game.odin", `package game

import scrapbot "scrapbot:scrapbot_native"

stats_fields := []scrapbot.Component_Field{
    {name = "count", field_type = .Int},
    {name = "ready", field_type = .Bool},
    {name = "gain", field_type = .Float},
    {name = "direction", field_type = .Vec3},
    {name = "label", field_type = .String},
}

payload_fields := []scrapbot.Component_Field{
    {name = "count", field_type = .Int},
    {name = "ready", field_type = .Bool},
    {name = "gain", field_type = .Float},
    {name = "direction", field_type = .Vec3},
    {name = "label", field_type = .String},
}

marker_fields := []scrapbot.Component_Field{
    {name = "value", field_type = .Int},
}

native_tick_writes := []string{"stats", "payload", "marker"}
stats_query := []string{"stats"}
marker_query := []string{"marker"}

native_tick :: proc "c" (ctx: ^scrapbot.System_Context) -> bool {
    cursor := 0
    for {
        entity, found := scrapbot.query_next(ctx, stats_query[:], &cursor)
        if !found {
            break
        }
        count, count_ok := scrapbot.get_int(ctx, entity, "stats", "count")
        if !count_ok {
            return false
        }
        if !scrapbot.set_int(ctx, entity, "stats", "count", count + 1) {
            return false
        }
        ready, ready_ok := scrapbot.get_bool(ctx, entity, "stats", "ready")
        if !ready_ok || !scrapbot.set_bool(ctx, entity, "stats", "ready", !ready) {
            return false
        }
        gain, gain_ok := scrapbot.get_float(ctx, entity, "stats", "gain")
        if !gain_ok || !scrapbot.set_float(ctx, entity, "stats", "gain", gain + f32(ctx.delta_seconds)) {
            return false
        }
        direction, direction_ok := scrapbot.get_vec3(ctx, entity, "stats", "direction")
        if !direction_ok {
            return false
        }
        next_direction := scrapbot.Vec3{x = direction.x + 1, y = direction.y + 2, z = direction.z + 3}
        if !scrapbot.set_vec3(ctx, entity, "stats", "direction", next_direction) {
            return false
        }
        label, label_ok := scrapbot.get_string(ctx, entity, "stats", "label")
        if !label_ok || label != "start" {
            return false
        }
        if !scrapbot.set_string(ctx, entity, "stats", "label", "done") {
            return false
        }
    }

    survivor, survivor_ok := scrapbot.spawn_entity(ctx, "native-survivor", "Native Survivor")
    if !survivor_ok {
        return false
    }
    payload := []scrapbot.Field_Value{
        scrapbot.field_int("count", 7),
        scrapbot.field_bool("ready", true),
        scrapbot.field_float("gain", 2.5),
        scrapbot.field_vec3("direction", scrapbot.Vec3{x = 5, y = 6, z = 7}),
        scrapbot.field_string("label", "spawned"),
    }
    if !scrapbot.add_component(ctx, survivor, "payload", payload[:]) {
        return false
    }

    marker_cursor := 0
    for {
        marker_entity, found := scrapbot.query_next(ctx, marker_query[:], &marker_cursor)
        if !found {
            break
        }
        value, value_ok := scrapbot.get_int(ctx, marker_entity, "marker", "value")
        if !value_ok {
            return false
        }
        if value == 3 {
            if !scrapbot.remove_component(ctx, marker_entity, "marker") {
                return false
            }
        } else if value == 4 {
            if !scrapbot.despawn_entity(ctx, marker_entity) {
                return false
            }
        }
    }
    return true
}

@(export)
scrapbot_register :: proc "c" (api: ^scrapbot.Register_Api) -> bool {
    if !scrapbot.register_component(api, {
        id = "stats",
        fields = stats_fields[:],
    }) {
        return false
    }
    if !scrapbot.register_component(api, {
        id = "payload",
        fields = payload_fields[:],
    }) {
        return false
    }
    if !scrapbot.register_component(api, {
        id = "marker",
        fields = marker_fields[:],
    }) {
        return false
    }
    return scrapbot.register_system(api, {
        id = "native_tick",
        phase = .Update,
        writes = native_tick_writes[:],
        run = native_tick,
    })
}
`)

	build, build_err := build_project(Build_Options{
		target_path = root,
		output_root = output_root,
		name = "packaged-native",
	})
	defer free_build_result(build)
	testing.expect_value(t, build_err, Project_Error.None)
	testing.expect(t, build.native_artifact != "")

	result := check_project(build.project_path)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	testing.expect_value(t, runtime_system_schedule_system_count(result.update_schedule), 1)
	simulation := run_script_simulation(&result, 1, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, true)
	testing.expect_value(t, simulation.completed_frames, 1)

	entity, entity_found := runtime_world_find_entity_by_id(result.scene.world, "target")
	testing.expect(t, entity_found)
	value, value_err := runtime_world_get_component_field_value(result.scene.world, entity, "stats", "count")
	testing.expect_value(t, value_err, Runtime_Error.None)
	testing.expect_value(t, value.value_type, Runtime_Field_Type.Int)
	testing.expect_value(t, value.int_value, 2)
	ready, ready_err := runtime_world_get_component_field_value(result.scene.world, entity, "stats", "ready")
	testing.expect_value(t, ready_err, Runtime_Error.None)
	testing.expect_value(t, ready.boolean, false)
	gain, gain_err := runtime_world_get_component_field_value(result.scene.world, entity, "stats", "gain")
	testing.expect_value(t, gain_err, Runtime_Error.None)
	testing.expect_value(t, gain.float, f32(2.0))
	direction, direction_err := runtime_world_get_component_field_value(result.scene.world, entity, "stats", "direction")
	testing.expect_value(t, direction_err, Runtime_Error.None)
	testing.expect_value(t, direction.vec3, [3]f32{2.0, 4.0, 6.0})
	label, label_err := runtime_world_get_component_field_value(result.scene.world, entity, "stats", "label")
	testing.expect_value(t, label_err, Runtime_Error.None)
	testing.expect_value(t, label.string_value, "done")

	survivor, survivor_found := runtime_world_find_entity_by_id(result.scene.world, "native-survivor")
	testing.expect(t, survivor_found)
	payload_count, payload_count_err := runtime_world_get_component_field_value(result.scene.world, survivor, "payload", "count")
	testing.expect_value(t, payload_count_err, Runtime_Error.None)
	testing.expect_value(t, payload_count.int_value, 7)
	payload_ready, payload_ready_err := runtime_world_get_component_field_value(result.scene.world, survivor, "payload", "ready")
	testing.expect_value(t, payload_ready_err, Runtime_Error.None)
	testing.expect_value(t, payload_ready.boolean, true)
	payload_gain, payload_gain_err := runtime_world_get_component_field_value(result.scene.world, survivor, "payload", "gain")
	testing.expect_value(t, payload_gain_err, Runtime_Error.None)
	testing.expect_value(t, payload_gain.float, f32(2.5))
	payload_direction, payload_direction_err := runtime_world_get_component_field_value(result.scene.world, survivor, "payload", "direction")
	testing.expect_value(t, payload_direction_err, Runtime_Error.None)
	testing.expect_value(t, payload_direction.vec3, [3]f32{5.0, 6.0, 7.0})
	payload_label, payload_label_err := runtime_world_get_component_field_value(result.scene.world, survivor, "payload", "label")
	testing.expect_value(t, payload_label_err, Runtime_Error.None)
	testing.expect_value(t, payload_label.string_value, "spawned")

	marked, marked_found := runtime_world_find_entity_by_id(result.scene.world, "marked")
	testing.expect(t, marked_found)
	has_marker, has_marker_err := runtime_world_has_component(result.scene.world, marked, "marker")
	testing.expect_value(t, has_marker_err, Runtime_Error.None)
	testing.expect_value(t, has_marker, false)
	_, doomed_found := runtime_world_find_entity_by_id(result.scene.world, "doomed")
	testing.expect_value(t, doomed_found, false)
}

@(test)
test_run_script_simulation_executes_development_odin_native_source_callback :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-development-odin-native-source")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nnative = \"native/game.odin\"\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.stats]
count = 4
`)
	write_file(t, root, "native/game.odin", `package game

import scrapbot "scrapbot:scrapbot_native"

stats_fields := []scrapbot.Component_Field{
    {name = "count", field_type = .Int},
}

native_tick_writes := []string{"stats"}

native_tick :: proc "c" (ctx: ^scrapbot.System_Context) -> bool {
    query := []string{"stats"}
    cursor := 0
    entity, entity_ok := scrapbot.query_next(ctx, query[:], &cursor)
    if !entity_ok {
        return false
    }
    count, count_ok := scrapbot.get_int(ctx, entity, "stats", "count")
    if !count_ok {
        return false
    }
    return scrapbot.set_int(ctx, entity, "stats", "count", count + 3)
}

@(export)
scrapbot_register :: proc "c" (api: ^scrapbot.Register_Api) -> bool {
    if !scrapbot.register_component(api, {
        id = "stats",
        fields = stats_fields[:],
    }) {
        return false
    }
    return scrapbot.register_system(api, {
        id = "native_tick",
        phase = .Update,
        writes = native_tick_writes[:],
        run = native_tick,
    })
}
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	testing.expect_value(t, runtime_system_schedule_system_count(result.update_schedule), 1)

	simulation := run_script_simulation(&result, 1, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, true)
	testing.expect_value(t, simulation.completed_frames, 1)

	target, target_found := runtime_world_find_entity_by_id(result.scene.world, "target")
	testing.expect_value(t, target_found, true)
	count, count_err := runtime_world_get_component_field_value(result.scene.world, target, "stats", "count")
	testing.expect_value(t, count_err, Runtime_Error.None)
	testing.expect_value(t, count.int_value, 7)
}

@(test)
test_check_project_reports_development_odin_native_source_build_diagnostic :: proc(t: ^testing.T) {
	root := make_test_project(t, "check-development-odin-native-build-diagnostic")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nnative = \"native/game.odin\"\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")
	write_file(t, root, "native/game.odin", `package game

import scrapbot "scrapbot:scrapbot_native"

@(export)
scrapbot_register :: proc "c" (api: ^scrapbot.Register_Api) -> bool {
    return true
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Native_Build)
	testing.expect_value(t, result.diagnostic.stage, Script_Diagnostic_Stage.Native_Build)
	testing.expect_value(t, result.diagnostic.path, "native/game.odin")
	testing.expect(t, strings.contains(result.diagnostic.message, "failed to build Odin native module"))
}

@(test)
test_live_project_reloads_development_odin_native_source_callback :: proc(t: ^testing.T) {
	root := make_test_project(t, "live-project-odin-native-source-reload")
	defer os.remove_all(root)
	defer delete(root)

	write_native_counter_project(t, root, "1")
	live, init_err := live_project_init(root)
	defer live_project_free(&live)
	testing.expect_value(t, init_err, Project_Error.None)

	first := live_project_update(&live, 1, 0.5)
	defer script_diagnostic_free(&first.diagnostic)
	testing.expect_value(t, first.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 2)

	write_development_native_counter_source(t, root, "10")
	reload, reload_err := live_project_poll_native_source(&live)
	testing.expect_value(t, reload_err, Project_Error.None)
	testing.expect_value(t, reload.changed, true)
	testing.expect_value(t, reload.info.native_reloaded, true)
	testing.expect_value(t, reload.info.scripts_reloaded, true)

	second := live_project_update(&live, 1, 0.5)
	defer script_diagnostic_free(&second.diagnostic)
	testing.expect_value(t, second.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 12)
}

@(test)
test_live_project_keeps_last_good_after_bad_development_odin_native_reload :: proc(t: ^testing.T) {
	root := make_test_project(t, "live-project-odin-native-source-reload-failure")
	defer os.remove_all(root)
	defer delete(root)

	write_native_counter_project(t, root, "1")
	live, init_err := live_project_init(root)
	defer live_project_free(&live)
	testing.expect_value(t, init_err, Project_Error.None)

	first := live_project_update(&live, 1, 0.5)
	defer script_diagnostic_free(&first.diagnostic)
	testing.expect_value(t, first.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 2)

	write_broken_development_native_counter_source(t, root)
	bad_reload, bad_reload_err := live_project_poll_native_source(&live)
	testing.expect_value(t, bad_reload_err, Project_Error.Invalid_Native_Build)
	testing.expect_value(t, bad_reload.changed, false)
	diagnostic, diagnostic_found := live_project_last_diagnostic(&live)
	testing.expect_value(t, diagnostic_found, true)
	testing.expect_value(t, diagnostic.stage, Script_Diagnostic_Stage.Native_Build)
	testing.expect_value(t, diagnostic.path, "native/game.odin")

	still_old := live_project_update(&live, 1, 0.5)
	defer script_diagnostic_free(&still_old.diagnostic)
	testing.expect_value(t, still_old.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 3)

	write_development_native_counter_source(t, root, "10")
	fixed_reload, fixed_reload_err := live_project_poll_native_source(&live)
	testing.expect_value(t, fixed_reload_err, Project_Error.None)
	testing.expect_value(t, fixed_reload.changed, true)
	_, after_fixed_diagnostic_found := live_project_last_diagnostic(&live)
	testing.expect_value(t, after_fixed_diagnostic_found, false)

	after_fixed := live_project_update(&live, 1, 0.5)
	defer script_diagnostic_free(&after_fixed.diagnostic)
	testing.expect_value(t, after_fixed.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 13)
}

@(test)
test_live_project_run_frames_polls_development_odin_native_source_between_frames :: proc(t: ^testing.T) {
	root := make_test_project(t, "live-project-run-polls-odin-native-source")
	defer os.remove_all(root)
	defer delete(root)

	write_native_counter_project(t, root, "1")
	live, init_err := live_project_init(root)
	defer live_project_free(&live)
	testing.expect_value(t, init_err, Project_Error.None)

	hook_data := Live_Project_Native_Reload_Test_Hook_Data{t = t, root = root}
	report := Live_Project_Run_Report{}
	defer live_project_run_report_free(&report)
	simulation := live_project_run_frames_with_report(&live, 2, 0.5, live_project_native_reload_test_hook, rawptr(&hook_data), &report)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, true)
	testing.expect_value(t, simulation.completed_frames, 2)
	testing.expect_value(t, hook_data.rewrote_source, true)
	testing.expect_value(t, live_project_counter_value(t, live), 12)
	expect_reload_event(t, report, 0, 1, false, false, true, true)
}

@(test)
test_live_project_reloads_luau_script_source_callback :: proc(t: ^testing.T) {
	root := make_test_project(t, "live-project-luau-script-source-reload")
	defer os.remove_all(root)
	defer delete(root)

	write_script_counter_project(t, root, "1")
	live, init_err := live_project_init(root)
	defer live_project_free(&live)
	testing.expect_value(t, init_err, Project_Error.None)

	first := live_project_run_frames(&live, 1, 0.5)
	defer script_diagnostic_free(&first.diagnostic)
	testing.expect_value(t, first.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 2)

	write_script_counter_source(t, root, "10")
	reload, reload_err := live_project_poll_script_sources(&live)
	testing.expect_value(t, reload_err, Project_Error.None)
	testing.expect_value(t, reload.changed, true)
	testing.expect_value(t, reload.info.scripts_reloaded, true)
	testing.expect_value(t, reload.info.native_reloaded, false)

	second := live_project_run_frames(&live, 1, 0.5)
	defer script_diagnostic_free(&second.diagnostic)
	testing.expect_value(t, second.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 12)
}

@(test)
test_live_project_keeps_last_good_after_bad_luau_script_reload :: proc(t: ^testing.T) {
	root := make_test_project(t, "live-project-luau-script-source-reload-failure")
	defer os.remove_all(root)
	defer delete(root)

	write_script_counter_project(t, root, "1")
	live, init_err := live_project_init(root)
	defer live_project_free(&live)
	testing.expect_value(t, init_err, Project_Error.None)

	first := live_project_run_frames(&live, 1, 0.5)
	defer script_diagnostic_free(&first.diagnostic)
	testing.expect_value(t, first.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 2)

	write_broken_script_counter_source(t, root)
	bad_reload, bad_reload_err := live_project_poll_script_sources(&live)
	testing.expect_value(t, bad_reload_err, Project_Error.Invalid_Script)
	testing.expect_value(t, bad_reload.changed, false)
	diagnostic, diagnostic_found := live_project_last_diagnostic(&live)
	testing.expect_value(t, diagnostic_found, true)
	testing.expect_value(t, diagnostic.stage, Script_Diagnostic_Stage.Load)
	testing.expect_value(t, diagnostic.path, "scripts/gameplay.luau")

	still_old := live_project_run_frames(&live, 1, 0.5)
	defer script_diagnostic_free(&still_old.diagnostic)
	testing.expect_value(t, still_old.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 3)

	write_script_counter_source(t, root, "10")
	fixed_reload, fixed_reload_err := live_project_poll_script_sources(&live)
	testing.expect_value(t, fixed_reload_err, Project_Error.None)
	testing.expect_value(t, fixed_reload.changed, true)
	_, after_fixed_diagnostic_found := live_project_last_diagnostic(&live)
	testing.expect_value(t, after_fixed_diagnostic_found, false)

	after_fixed := live_project_run_frames(&live, 1, 0.5)
	defer script_diagnostic_free(&after_fixed.diagnostic)
	testing.expect_value(t, after_fixed.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 13)
}

@(test)
test_live_project_run_frames_polls_luau_script_source_between_frames :: proc(t: ^testing.T) {
	root := make_test_project(t, "live-project-run-polls-luau-script-source")
	defer os.remove_all(root)
	defer delete(root)

	write_script_counter_project(t, root, "1")
	live, init_err := live_project_init(root)
	defer live_project_free(&live)
	testing.expect_value(t, init_err, Project_Error.None)

	hook_data := Live_Project_Script_Reload_Test_Hook_Data{t = t, root = root}
	report := Live_Project_Run_Report{}
	defer live_project_run_report_free(&report)
	simulation := live_project_run_frames_with_report(&live, 2, 0.5, live_project_script_reload_test_hook, rawptr(&hook_data), &report)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, true)
	testing.expect_value(t, simulation.completed_frames, 2)
	testing.expect_value(t, hook_data.rewrote_source, true)
	testing.expect_value(t, live_project_counter_value(t, live), 12)
	expect_reload_event(t, report, 0, 1, false, false, true, false)
}

@(test)
test_live_project_run_frame_reports_script_reload_for_window_loop_tick :: proc(t: ^testing.T) {
	root := make_test_project(t, "live-project-run-frame-script-reload")
	defer os.remove_all(root)
	defer delete(root)

	write_script_counter_project(t, root, "1")
	live, init_err := live_project_init(root)
	defer live_project_free(&live)
	testing.expect_value(t, init_err, Project_Error.None)

	report := Live_Project_Run_Report{}
	defer live_project_run_report_free(&report)
	first := live_project_run_frame_with_report(&live, 0.5, 0, &report)
	defer script_diagnostic_free(&first.diagnostic)
	testing.expect_value(t, first.ok, true)
	testing.expect_value(t, first.completed_frames, 1)
	testing.expect_value(t, live_project_counter_value(t, live), 2)
	testing.expect_value(t, len(report.reloads), 0)

	write_script_counter_source(t, root, "10")
	second := live_project_run_frame_with_report(&live, 0.5, first.completed_frames, &report)
	defer script_diagnostic_free(&second.diagnostic)
	testing.expect_value(t, second.ok, true)
	testing.expect_value(t, second.completed_frames, 2)
	testing.expect_value(t, live_project_counter_value(t, live), 12)
	expect_reload_event(t, report, 0, 1, false, false, true, false)
}

@(test)
test_live_project_run_frame_with_editor_input_can_pause_updates :: proc(t: ^testing.T) {
	root := make_test_project(t, "live-editor-input-pause")
	defer os.remove_all(root)
	defer delete(root)

	write_script_counter_project(t, root, "1")
	live, init_err := live_project_init(root)
	defer live_project_free(&live)
	testing.expect_value(t, init_err, Project_Error.None)

	editor_state := Editor_Test_Input_State{}
	pause_input := frame_input_default()
	pause_input.debug_overlay_visible = true
	pause_input.viewport_width = 1280
	pause_input.viewport_height = 720
	pause_input.pointer.has_position = true
	pause_input.pointer.position = {1040, 20}
	pause_input.pointer.primary_pressed = true
	pause_input.pointer.primary_down = true

	first := live_project_run_frame_with_input(&live, 0.5, 0, nil, &editor_state, pause_input)
	defer script_diagnostic_free(&first.diagnostic)
	testing.expect_value(t, first.ok, true)
	testing.expect_value(t, first.completed_frames, 1)
	testing.expect_value(t, editor_state.paused, true)
	testing.expect_value(t, live_project_counter_value(t, live), 1)

	next_input := frame_input_default()
	next_input.debug_overlay_visible = true
	next_input.viewport_width = 1280
	next_input.viewport_height = 720
	second := live_project_run_frame_with_input(&live, 0.5, first.completed_frames, nil, &editor_state, next_input)
	defer script_diagnostic_free(&second.diagnostic)
	testing.expect_value(t, second.ok, true)
	testing.expect_value(t, second.completed_frames, 2)
	testing.expect_value(t, live_project_counter_value(t, live), 1)
}

@(test)
test_live_project_reloads_scene_source_and_resets_startup :: proc(t: ^testing.T) {
	root := make_test_project(t, "live-project-scene-source-reload")
	defer os.remove_all(root)
	defer delete(root)

	write_script_counter_project(t, root, "1")
	live, init_err := live_project_init(root)
	defer live_project_free(&live)
	testing.expect_value(t, init_err, Project_Error.None)

	first := live_project_run_frames(&live, 1, 0.5)
	defer script_diagnostic_free(&first.diagnostic)
	testing.expect_value(t, first.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 2)

	write_counter_scene(t, root, "20")
	reload, reload_err := live_project_poll_scene_source(&live)
	testing.expect_value(t, reload_err, Project_Error.None)
	testing.expect_value(t, reload.changed, true)
	testing.expect_value(t, reload.info.scene_reloaded, true)
	testing.expect_value(t, reload.info.scripts_reloaded, false)
	testing.expect_value(t, reload.info.native_reloaded, false)
	testing.expect_value(t, live_project_counter_value(t, live), 20)

	second := live_project_run_frames(&live, 1, 0.5)
	defer script_diagnostic_free(&second.diagnostic)
	testing.expect_value(t, second.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 21)
}

@(test)
test_live_project_script_reload_leaves_changed_scene_pending :: proc(t: ^testing.T) {
	root := make_test_project(t, "live-project-script-reload-leaves-scene-pending")
	defer os.remove_all(root)
	defer delete(root)

	write_script_counter_project(t, root, "1")
	live, init_err := live_project_init(root)
	defer live_project_free(&live)
	testing.expect_value(t, init_err, Project_Error.None)

	first := live_project_run_frames(&live, 1, 0.5)
	defer script_diagnostic_free(&first.diagnostic)
	testing.expect_value(t, first.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 2)

	write_counter_scene(t, root, "20")
	write_script_counter_source(t, root, "10")
	script_reload, script_reload_err := live_project_poll_script_sources(&live)
	testing.expect_value(t, script_reload_err, Project_Error.None)
	testing.expect_value(t, script_reload.changed, true)
	testing.expect_value(t, live_project_counter_value(t, live), 2)

	scene_reload, scene_reload_err := live_project_poll_scene_source(&live)
	testing.expect_value(t, scene_reload_err, Project_Error.None)
	testing.expect_value(t, scene_reload.changed, true)
	testing.expect_value(t, live_project_counter_value(t, live), 20)

	second := live_project_run_frames(&live, 1, 0.5)
	defer script_diagnostic_free(&second.diagnostic)
	testing.expect_value(t, second.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 30)
}

@(test)
test_live_project_keeps_last_good_after_bad_scene_reload :: proc(t: ^testing.T) {
	root := make_test_project(t, "live-project-scene-source-reload-failure")
	defer os.remove_all(root)
	defer delete(root)

	write_script_counter_project(t, root, "1")
	live, init_err := live_project_init(root)
	defer live_project_free(&live)
	testing.expect_value(t, init_err, Project_Error.None)
	testing.expect_value(t, live_project_counter_value(t, live), 1)

	write_file(t, root, "scenes/main.scene.toml", "name = \"Main\"\nversion = 1\n")
	bad_reload, bad_reload_err := live_project_poll_scene_source(&live)
	testing.expect_value(t, bad_reload_err, Project_Error.Missing_Scene_Content)
	testing.expect_value(t, bad_reload.changed, false)
	testing.expect_value(t, live_project_counter_value(t, live), 1)

	write_counter_scene(t, root, "7")
	fixed_reload, fixed_reload_err := live_project_poll_scene_source(&live)
	testing.expect_value(t, fixed_reload_err, Project_Error.None)
	testing.expect_value(t, fixed_reload.changed, true)
	testing.expect_value(t, live_project_counter_value(t, live), 7)
}

@(test)
test_live_project_run_frames_polls_scene_source_between_frames :: proc(t: ^testing.T) {
	root := make_test_project(t, "live-project-run-polls-scene-source")
	defer os.remove_all(root)
	defer delete(root)

	write_script_counter_project(t, root, "1")
	live, init_err := live_project_init(root)
	defer live_project_free(&live)
	testing.expect_value(t, init_err, Project_Error.None)

	hook_data := Live_Project_Scene_Reload_Test_Hook_Data{t = t, root = root}
	report := Live_Project_Run_Report{}
	defer live_project_run_report_free(&report)
	simulation := live_project_run_frames_with_report(&live, 2, 0.5, live_project_scene_reload_test_hook, rawptr(&hook_data), &report)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, true)
	testing.expect_value(t, simulation.completed_frames, 2)
	testing.expect_value(t, hook_data.rewrote_source, true)
	testing.expect_value(t, live_project_counter_value(t, live), 21)
	expect_reload_event(t, report, 0, 1, false, true, false, false)
}

@(test)
test_live_project_reloads_project_metadata_default_scene_and_scripts :: proc(t: ^testing.T) {
	root := make_test_project(t, "live-project-project-source-reload")
	defer os.remove_all(root)
	defer delete(root)

	write_script_counter_project(t, root, "1")
	live, init_err := live_project_init(root)
	defer live_project_free(&live)
	testing.expect_value(t, init_err, Project_Error.None)

	first := live_project_run_frames(&live, 1, 0.5)
	defer script_diagnostic_free(&first.diagnostic)
	testing.expect_value(t, first.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 2)

	write_counter_scene_at(t, root, "scenes/alternate.scene.toml", "20")
	write_script_counter_source_at(t, root, "scripts/fast.luau", "10")
	write_counter_project_metadata(t, root, "Reloaded Game", "scenes/alternate.scene.toml", "scripts/fast.luau")
	reload, reload_err := live_project_poll_project_source(&live)
	testing.expect_value(t, reload_err, Project_Error.None)
	testing.expect_value(t, reload.changed, true)
	testing.expect_value(t, reload.info.project_reloaded, true)
	testing.expect_value(t, reload.info.scene_reloaded, true)
	testing.expect_value(t, reload.info.scripts_reloaded, true)
	testing.expect_value(t, reload.info.native_reloaded, false)
	testing.expect_value(t, live.check.project.name, "Reloaded Game")
	testing.expect_value(t, live.check.project.default_scene, "scenes/alternate.scene.toml")
	testing.expect_value(t, live_project_counter_value(t, live), 20)

	second := live_project_run_frames(&live, 1, 0.5)
	defer script_diagnostic_free(&second.diagnostic)
	testing.expect_value(t, second.ok, true)
	testing.expect_value(t, live_project_counter_value(t, live), 30)
}

@(test)
test_live_project_keeps_last_good_after_bad_project_metadata_reload :: proc(t: ^testing.T) {
	root := make_test_project(t, "live-project-project-source-reload-failure")
	defer os.remove_all(root)
	defer delete(root)

	write_script_counter_project(t, root, "1")
	live, init_err := live_project_init(root)
	defer live_project_free(&live)
	testing.expect_value(t, init_err, Project_Error.None)
	testing.expect_value(t, live.check.project.name, "Game")
	testing.expect_value(t, live_project_counter_value(t, live), 1)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Broken Game\"\nversion = 99\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	bad_reload, bad_reload_err := live_project_poll_project_source(&live)
	testing.expect_value(t, bad_reload_err, Project_Error.Unsupported_Project_Version)
	testing.expect_value(t, bad_reload.changed, false)
	testing.expect_value(t, live.check.project.name, "Game")
	testing.expect_value(t, live_project_counter_value(t, live), 1)

	write_counter_project_metadata(t, root, "Fixed Game", "scenes/main.scene.toml", "scripts/gameplay.luau")
	fixed_reload, fixed_reload_err := live_project_poll_project_source(&live)
	testing.expect_value(t, fixed_reload_err, Project_Error.None)
	testing.expect_value(t, fixed_reload.changed, true)
	testing.expect_value(t, fixed_reload.info.project_reloaded, true)
	testing.expect_value(t, live.check.project.name, "Fixed Game")
	testing.expect_value(t, live_project_counter_value(t, live), 1)
}

@(test)
test_live_project_run_frames_polls_project_metadata_between_frames :: proc(t: ^testing.T) {
	root := make_test_project(t, "live-project-run-polls-project-source")
	defer os.remove_all(root)
	defer delete(root)

	write_script_counter_project(t, root, "1")
	live, init_err := live_project_init(root)
	defer live_project_free(&live)
	testing.expect_value(t, init_err, Project_Error.None)

	hook_data := Live_Project_Project_Reload_Test_Hook_Data{t = t, root = root}
	report := Live_Project_Run_Report{}
	defer live_project_run_report_free(&report)
	simulation := live_project_run_frames_with_report(&live, 2, 0.5, live_project_project_reload_test_hook, rawptr(&hook_data), &report)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, true)
	testing.expect_value(t, simulation.completed_frames, 2)
	testing.expect_value(t, hook_data.rewrote_source, true)
	testing.expect_value(t, live.check.project.default_scene, "scenes/alternate.scene.toml")
	testing.expect_value(t, live_project_counter_value(t, live), 30)
	expect_reload_event(t, report, 0, 1, true, true, true, false)
}

@(test)
test_run_script_simulation_reports_native_odin_set_field_write_access_diagnostic :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-native-odin-set-field-write-access")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nnative = \"native/game.odin\"\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.stats]
count = 0
`)
	write_file(t, root, "native/game.odin", `package game

stats_fields := []scrapbot.Component_Field{
    {name = "count", field_type = .Int},
}

scrapbot_register :: proc(api: ^scrapbot.Register_Api) -> bool {
    scrapbot.register_component(api, {
        id = "stats",
        fields = stats_fields[:],
    })
    scrapbot.register_system(api, {
        id = "native_tick",
        phase = .Update,
        execute = {
            entity = "target",
            component = "stats",
            field = "count",
            value = 2,
        },
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
	testing.expect_value(t, simulation.diagnostic.path, "native/game.odin")
	testing.expect_value(t, simulation.diagnostic.system_id, "native_tick")
	testing.expect(t, strings.contains(simulation.diagnostic.message, "did not declare"))
}

@(test)
test_run_script_simulation_executes_native_odin_lifecycle_operation :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-native-odin-lifecycle")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nnative = \"native/game.odin\"\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "marked"
name = "Marked"

[entities.components.native_marker]
value = 1

[[entities]]
id = "doomed"
name = "Doomed"

[entities.components.native_marker]
value = 2
`)
	write_file(t, root, "native/game.odin", `package game

payload_fields := []scrapbot.Component_Field{
    {name = "count", field_type = .Int},
    {name = "enabled", field_type = .Boolean},
    {name = "speed", field_type = .Float},
    {name = "direction", field_type = .Vec3},
    {name = "label", field_type = .String},
}

marker_fields := []scrapbot.Component_Field{
    {name = "value", field_type = .Int},
}

native_lifecycle_writes := []string{"native_payload", "native_marker"}

scrapbot_register :: proc(api: ^scrapbot.Register_Api) -> bool {
    scrapbot.register_component(api, {
        id = "native_payload",
        fields = payload_fields[:],
    })
    scrapbot.register_component(api, {
        id = "native_marker",
        fields = marker_fields[:],
    })
    scrapbot.register_system(api, {
        id = "native_lifecycle",
        phase = .Startup,
        writes = native_lifecycle_writes[:],
        execute = {
            spawn = {
                entity = "native-survivor",
                name = "Native Survivor",
                component = "native_payload",
                fields = {
                    count = 7,
                    enabled = true,
                    speed = 1.75,
                    direction = [3.0, 2.0, 1.0],
                    label = "spawned",
                },
            },
            remove = {
                entity = "marked",
                component = "native_marker",
            },
            despawn = {
                entity = "doomed",
            },
        },
    })
    return true
}
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	testing.expect_value(t, runtime_system_schedule_system_count(result.startup_schedule), 1)
	simulation := run_script_simulation(&result, 0, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, true)

	survivor, survivor_found := runtime_world_find_entity_by_id(result.scene.world, "native-survivor")
	testing.expect_value(t, survivor_found, true)
	count, count_err := runtime_world_get_component_field_value(result.scene.world, survivor, "native_payload", "count")
	testing.expect_value(t, count_err, Runtime_Error.None)
	testing.expect_value(t, count.int_value, 7)
	enabled, enabled_err := runtime_world_get_component_field_value(result.scene.world, survivor, "native_payload", "enabled")
	testing.expect_value(t, enabled_err, Runtime_Error.None)
	testing.expect_value(t, enabled.boolean, true)
	speed, speed_err := runtime_world_get_component_field_value(result.scene.world, survivor, "native_payload", "speed")
	testing.expect_value(t, speed_err, Runtime_Error.None)
	testing.expect_value(t, speed.float, f32(1.75))
	direction, direction_err := runtime_world_get_component_field_value(result.scene.world, survivor, "native_payload", "direction")
	testing.expect_value(t, direction_err, Runtime_Error.None)
	testing.expect_value(t, direction.vec3, [3]f32{3.0, 2.0, 1.0})
	label, label_err := runtime_world_get_component_field_value(result.scene.world, survivor, "native_payload", "label")
	testing.expect_value(t, label_err, Runtime_Error.None)
	testing.expect_value(t, label.string_value, "spawned")

	marked, marked_found := runtime_world_find_entity_by_id(result.scene.world, "marked")
	testing.expect_value(t, marked_found, true)
	has_marker, has_marker_err := runtime_world_has_component(result.scene.world, marked, "native_marker")
	testing.expect_value(t, has_marker_err, Runtime_Error.None)
	testing.expect_value(t, has_marker, false)
	_, doomed_found := runtime_world_find_entity_by_id(result.scene.world, "doomed")
	testing.expect_value(t, doomed_found, false)
}

@(test)
test_run_script_simulation_rolls_back_native_odin_lifecycle_spawn_after_access_failure :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-simulation-native-odin-lifecycle-rollback")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nnative = \"native/game.odin\"\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")
	write_file(t, root, "native/game.odin", `package game

payload_fields := []scrapbot.Component_Field{
    {name = "count", field_type = .Int},
}

scrapbot_register :: proc(api: ^scrapbot.Register_Api) -> bool {
    scrapbot.register_component(api, {
        id = "native_payload",
        fields = payload_fields[:],
    })
    scrapbot.register_system(api, {
        id = "native_lifecycle",
        phase = .Startup,
        execute = {
            spawn = {
                entity = "native-survivor",
                name = "Native Survivor",
                component = "native_payload",
                fields = {
                    count = 7,
                },
            },
        },
    })
    return true
}
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	simulation := run_script_simulation(&result, 0, 0.5)
	defer script_diagnostic_free(&simulation.diagnostic)
	testing.expect_value(t, simulation.ok, false)
	testing.expect_value(t, simulation.completed_frames, 0)
	testing.expect_value(t, simulation.diagnostic.stage, Script_Diagnostic_Stage.Runtime)
	testing.expect_value(t, simulation.diagnostic.path, "native/game.odin")
	testing.expect_value(t, simulation.diagnostic.system_id, "native_lifecycle")
	testing.expect(t, strings.contains(simulation.diagnostic.message, "Access_Denied"))
	_, survivor_found := runtime_world_find_entity_by_id(result.scene.world, "native-survivor")
	testing.expect_value(t, survivor_found, false)
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

write_native_counter_project :: proc(t: ^testing.T, root, increment: string) {
	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nnative = \"native/game.odin\"\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.stats]
count = 1
`)
	write_development_native_counter_source(t, root, increment)
}

write_development_native_counter_source :: proc(t: ^testing.T, root, increment: string) {
	source := strings.builder_make()
	defer strings.builder_destroy(&source)
	strings.write_string(&source, `package game

import scrapbot "scrapbot:scrapbot_native"

stats_fields := []scrapbot.Component_Field{
    {name = "count", field_type = .Int},
}

native_tick_writes := []string{"stats"}

native_tick :: proc "c" (ctx: ^scrapbot.System_Context) -> bool {
    query := []string{"stats"}
    cursor := 0
    entity, entity_ok := scrapbot.query_next(ctx, query[:], &cursor)
    if !entity_ok {
        return false
    }
    count, count_ok := scrapbot.get_int(ctx, entity, "stats", "count")
    if !count_ok {
        return false
    }
    return scrapbot.set_int(ctx, entity, "stats", "count", count + `)
	strings.write_string(&source, increment)
	strings.write_string(&source, `)
}

@(export)
scrapbot_register :: proc "c" (api: ^scrapbot.Register_Api) -> bool {
    if !scrapbot.register_component(api, {
        id = "stats",
        fields = stats_fields[:],
    }) {
        return false
    }
    return scrapbot.register_system(api, {
        id = "native_tick",
        phase = .Update,
        writes = native_tick_writes[:],
        run = native_tick,
    })
}
`)
	write_file(t, root, "native/game.odin", strings.to_string(source))
}

write_broken_development_native_counter_source :: proc(t: ^testing.T, root: string) {
	write_file(t, root, "native/game.odin", `package game

import scrapbot "scrapbot:scrapbot_native"

@(export)
scrapbot_register :: proc "c" (api: ^scrapbot.Register_Api) -> bool {
    return true
`)
}

Live_Project_Native_Reload_Test_Hook_Data :: struct {
	t:              ^testing.T,
	root:           string,
	rewrote_source: bool,
}

live_project_native_reload_test_hook :: proc(project: ^Live_Project, completed_frames: int, user_data: rawptr) -> bool {
	_ = project
	data := cast(^Live_Project_Native_Reload_Test_Hook_Data)user_data
	if data == nil {
		return false
	}
	if completed_frames == 1 && !data.rewrote_source {
		write_development_native_counter_source(data.t, data.root, "10")
		data.rewrote_source = true
	}
	return true
}

write_script_counter_project :: proc(t: ^testing.T, root, increment: string) {
	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_file(t, root, "scenes/main.scene.toml", `name = "Main"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.stats]
count = 1
`)
	write_script_counter_source(t, root, increment)
}

write_script_counter_source :: proc(t: ^testing.T, root, increment: string) {
	write_script_counter_source_at(t, root, "scripts/gameplay.luau", increment)
}

write_broken_script_counter_source :: proc(t: ^testing.T, root: string) {
	write_file(t, root, "scripts/gameplay.luau", `local Stats = ecs.component("stats", {
  fields = ecs.fields({
    count = "int",
  }),
})

ecs.system("script_tick", {
  phase = "update",
`)
}

Live_Project_Script_Reload_Test_Hook_Data :: struct {
	t:              ^testing.T,
	root:           string,
	rewrote_source: bool,
}

live_project_script_reload_test_hook :: proc(project: ^Live_Project, completed_frames: int, user_data: rawptr) -> bool {
	_ = project
	data := cast(^Live_Project_Script_Reload_Test_Hook_Data)user_data
	if data == nil {
		return false
	}
	if completed_frames == 1 && !data.rewrote_source {
		write_script_counter_source(data.t, data.root, "10")
		data.rewrote_source = true
	}
	return true
}

Live_Project_Scene_Reload_Test_Hook_Data :: struct {
	t:              ^testing.T,
	root:           string,
	rewrote_source: bool,
}

live_project_scene_reload_test_hook :: proc(project: ^Live_Project, completed_frames: int, user_data: rawptr) -> bool {
	_ = project
	data := cast(^Live_Project_Scene_Reload_Test_Hook_Data)user_data
	if data == nil {
		return false
	}
	if completed_frames == 1 && !data.rewrote_source {
		write_counter_scene(data.t, data.root, "20")
		data.rewrote_source = true
	}
	return true
}

Live_Project_Project_Reload_Test_Hook_Data :: struct {
	t:              ^testing.T,
	root:           string,
	rewrote_source: bool,
}

live_project_project_reload_test_hook :: proc(project: ^Live_Project, completed_frames: int, user_data: rawptr) -> bool {
	_ = project
	data := cast(^Live_Project_Project_Reload_Test_Hook_Data)user_data
	if data == nil {
		return false
	}
	if completed_frames == 1 && !data.rewrote_source {
		write_counter_scene_at(data.t, data.root, "scenes/alternate.scene.toml", "20")
		write_script_counter_source_at(data.t, data.root, "scripts/fast.luau", "10")
		write_counter_project_metadata(data.t, data.root, "Reloaded Game", "scenes/alternate.scene.toml", "scripts/fast.luau")
		data.rewrote_source = true
	}
	return true
}

expect_reload_event :: proc(t: ^testing.T, report: Live_Project_Run_Report, index, frame: int, project, scene, scripts, native: bool) {
	testing.expect_value(t, len(report.reloads) > index, true)
	if len(report.reloads) <= index {
		return
	}
	event := report.reloads[index]
	testing.expect_value(t, event.frame, frame)
	testing.expect_value(t, event.info.project_reloaded, project)
	testing.expect_value(t, event.info.scene_reloaded, scene)
	testing.expect_value(t, event.info.scripts_reloaded, scripts)
	testing.expect_value(t, event.info.native_reloaded, native)
	testing.expect_value(t, event.info.entity_count > 0, true)
	testing.expect_value(t, event.info.system_count > 0, true)
}

live_project_counter_value :: proc(t: ^testing.T, live: Live_Project) -> int {
	target, target_found := runtime_world_find_entity_by_id(live.check.scene.world, "target")
	if !target_found {
		testing.fail_now(t, "missing target entity")
	}
	value, value_err := runtime_world_get_component_field_value(live.check.scene.world, target, "stats", "count")
	if value_err != .None {
		testing.fail_now(t, "failed to read stats.count")
	}
	return value.int_value
}

write_counter_project_metadata :: proc(t: ^testing.T, root, name, scene_path, script_path: string) {
	metadata := strings.builder_make()
	defer strings.builder_destroy(&metadata)
	strings.write_string(&metadata, "name = \"")
	strings.write_string(&metadata, name)
	strings.write_string(&metadata, "\"\nversion = 1\ndefault_scene = \"")
	strings.write_string(&metadata, scene_path)
	strings.write_string(&metadata, "\"\nscripts = [\"")
	strings.write_string(&metadata, script_path)
	strings.write_string(&metadata, "\"]\n")
	write_file(t, root, PROJECT_FILE_NAME, strings.to_string(metadata))
}

write_counter_scene :: proc(t: ^testing.T, root, count: string) {
	write_counter_scene_at(t, root, "scenes/main.scene.toml", count)
}

write_counter_scene_at :: proc(t: ^testing.T, root, scene_path, count: string) {
	scene := strings.builder_make()
	defer strings.builder_destroy(&scene)
	strings.write_string(&scene, `name = "Main"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.stats]
count = `)
	strings.write_string(&scene, count)
	strings.write_string(&scene, "\n")
	write_file(t, root, scene_path, strings.to_string(scene))
}

write_script_counter_source_at :: proc(t: ^testing.T, root, script_path, increment: string) {
	source := strings.builder_make()
	defer strings.builder_destroy(&source)
	strings.write_string(&source, `local Stats = ecs.component("stats", {
  fields = ecs.fields({
    count = "int",
  }),
})

local StatsQuery = ecs.query(Stats)

ecs.system("script_tick", {
  phase = "update",
  query = StatsQuery,
  writes = ecs.refs(Stats),
  run = function(world, _dt)
    for _entity, stats in StatsQuery:iter(world) do
      stats.count = stats.count + `)
	strings.write_string(&source, increment)
	strings.write_string(&source, `
    end
  end,
})
`)
	write_file(t, root, script_path, strings.to_string(source))
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
