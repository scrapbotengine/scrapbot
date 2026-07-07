package main

import "core:os"
import "core:testing"

@(test)
test_component_scan_parses_native_field_lines :: proc(t: ^testing.T) {
	line := `{name = "count", field_type = .Int},`
	name, name_ok := parse_assignment_string_value(line, "name")
	field_type, type_ok := parse_assignment_enum_value(line, "field_type")
	testing.expect_value(t, name_ok, true)
	testing.expect_value(t, name, "count")
	testing.expect_value(t, type_ok, true)
	testing.expect_value(t, field_type, "Int")
	runtime_type, runtime_type_ok := component_field_type_from_native(field_type)
	testing.expect_value(t, runtime_type_ok, true)
	testing.expect_value(t, runtime_type, Runtime_Field_Type.Int)

	samples := [4]string{
		`{name = "enabled", field_type = .Boolean},`,
		`{name = "speed", field_type = .Float},`,
		`{name = "direction", field_type = .Vec3},`,
		`{name = "label", field_type = .String},`,
	}
	expected_types := [4]string{"Boolean", "Float", "Vec3", "String"}
	for sample, index in samples {
		_, sample_name_ok := parse_assignment_string_value(sample, "name")
		sample_type, sample_type_ok := parse_assignment_enum_value(sample, "field_type")
		_, sample_runtime_type_ok := component_field_type_from_native(sample_type)
		testing.expect_value(t, sample_name_ok, true)
		testing.expect_value(t, sample_type_ok, true)
		testing.expect_value(t, sample_type, expected_types[index])
		testing.expect_value(t, sample_runtime_type_ok, true)
	}
}

@(test)
test_component_scan_parses_native_field_arrays :: proc(t: ^testing.T) {
	source := `stats_fields := []scrapbot.Component_Field{
    {name = "count", field_type = .Int},
    {name = "enabled", field_type = .Boolean},
    {name = "speed", field_type = .Float},
    {name = "direction", field_type = .Vec3},
    {name = "label", field_type = .String},
}
`
	fields, ok := parse_native_field_array(source, "stats_fields")
	testing.expect_value(t, ok, true)
	if !ok {
		return
	}
	defer delete(fields)
	testing.expect_value(t, len(fields), 5)
	testing.expect_value(t, fields[0].name, "count")
	testing.expect_value(t, fields[0].value_type, Runtime_Field_Type.Int)
	testing.expect_value(t, fields[4].name, "label")
	testing.expect_value(t, fields[4].value_type, Runtime_Field_Type.String)
}

@(test)
test_component_scan_rejects_zig_native_source_in_odin_engine :: proc(t: ^testing.T) {
	root := make_test_project(t, "component-scan-zig-native-rejected")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, "native/game.zig", `const scrapbot = @import("scrapbot_native");`)

	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)
	native_path := project_relative_path(root, "native/game.zig")
	defer delete(native_path)
	err := register_native_components_from_file(&registry, native_path)
	testing.expect_value(t, err, Project_Error.Invalid_Native)
}

@(test)
test_component_scan_parses_odin_native_field_arrays :: proc(t: ^testing.T) {
	source := `package game

stats_fields := []scrapbot.Component_Field{
    {name = "count", field_type = .Int},
    {name = "enabled", field_type = .Boolean},
    {name = "speed", field_type = .Float},
    {name = "direction", field_type = .Vec3},
    {name = "label", field_type = .String},
}
`
	fields, ok := parse_native_field_array(source, "stats_fields")
	testing.expect_value(t, ok, true)
	if !ok {
		return
	}
	defer delete(fields)
	testing.expect_value(t, len(fields), 5)
	testing.expect_value(t, fields[0].name, "count")
	testing.expect_value(t, fields[0].value_type, Runtime_Field_Type.Int)
	testing.expect_value(t, fields[4].name, "label")
	testing.expect_value(t, fields[4].value_type, Runtime_Field_Type.String)
}

@(test)
test_component_scan_registers_odin_native_components_and_systems :: proc(t: ^testing.T) {
	root := make_test_project(t, "component-scan-odin-native")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nnative = \"native/game.odin\"\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")
	write_file(t, root, "native/game.odin", `package game

stats_fields := []scrapbot.Component_Field{
    {name = "count", field_type = .Int},
}

native_reads := []string{"native_stats"}
native_writes := []string{"scrapbot.transform"}

scrapbot_register :: proc(api: ^scrapbot.Register_Api) -> bool {
    scrapbot.register_component(api, {
        id = "native_stats",
        fields = stats_fields[:],
    })
    scrapbot.register_system(api, {
        id = "native_move",
        phase = .Update,
        reads = native_reads[:],
        writes = native_writes[:],
    })
    return true
}
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	component, component_found := runtime_find_component(result.registry, "native_stats")
	testing.expect_value(t, component_found, true)
	if component_found {
		testing.expect_value(t, len(component.fields), 1)
		testing.expect_value(t, component.fields[0].name, "count")
	}
	system, system_found := runtime_find_system(result.registry, "native_move")
	testing.expect_value(t, system_found, true)
	if !system_found {
		return
	}
	testing.expect_value(t, system.phase, Runtime_System_Phase.Update)
	testing.expect_value(t, len(system.reads), 1)
	testing.expect_value(t, system.reads[0], "native_stats")
	testing.expect_value(t, len(system.writes), 1)
	testing.expect_value(t, system.writes[0], TRANSFORM_COMPONENT_ID)
	testing.expect_value(t, system.runner.kind, Runtime_System_Runner_Kind.Native)
	testing.expect(t, system.runner.ref != 0)
	testing.expect_value(t, runtime_system_schedule_system_count(result.update_schedule), 1)
	testing.expect_value(t, result.update_schedule.batches[0].systems[0].runner.kind, Runtime_System_Runner_Kind.Native)
}

@(test)
test_component_scan_parses_odin_native_lifecycle_operation :: proc(t: ^testing.T) {
	block := `{
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
    }`
	operation, found, ok := parse_native_execute_operation(block, "native_lifecycle", "native/game.odin", 3, 1)
	defer native_system_operation_free(operation)
	execute_block, execute_found, execute_ok := parse_native_block_field_value(block, "execute")
	testing.expect_value(t, execute_ok, true)
	testing.expect_value(t, execute_found, true)
	spawn_block, spawn_found, spawn_ok := parse_native_block_field_value(execute_block, "spawn")
	testing.expect_value(t, spawn_ok, true)
	testing.expect_value(t, spawn_found, true)
	fields_block, fields_found, fields_ok := parse_native_block_field_value(spawn_block, "fields")
	testing.expect_value(t, fields_ok, true)
	testing.expect_value(t, fields_found, true)
	fields, fields_parse_ok := parse_native_field_assignments(fields_block)
	defer {
		native_field_assignments_free(fields[:])
		if fields != nil do delete(fields)
	}
	testing.expect_value(t, fields_parse_ok, true)
	testing.expect_value(t, len(fields), 5)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, found, true)
	testing.expect_value(t, operation.kind, Native_System_Operation_Kind.Lifecycle)
	testing.expect_value(t, operation.has_spawn, true)
	testing.expect_value(t, operation.spawn_entity_id, "native-survivor")
	testing.expect_value(t, operation.spawn_component_id, "native_payload")
	testing.expect_value(t, len(operation.spawn_fields), 5)
	if len(operation.spawn_fields) == 5 {
		testing.expect_value(t, operation.spawn_fields[4].name, "label")
		testing.expect_value(t, operation.spawn_fields[4].value_text, `"spawned"`)
	}
	testing.expect_value(t, operation.has_remove, true)
	testing.expect_value(t, operation.remove_entity_id, "marked")
	testing.expect_value(t, operation.has_despawn, true)
	testing.expect_value(t, operation.despawn_entity_id, "doomed")
}

@(test)
test_component_scan_registers_script_marker_before_field_component :: proc(t: ^testing.T) {
	root := make_test_project(t, "component-scan-script-marker")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, "scripts/gameplay.luau", `local Marker = ecs.component("marker")
local Stats = ecs.component("stats", {
  fields = ecs.fields({
    count = "int",
  }),
})
`)

	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)
	script_path := project_relative_path(root, "scripts/gameplay.luau")
	defer delete(script_path)
	err := register_script_components_from_file(&registry, script_path)
	testing.expect_value(t, err, Project_Error.None)
	marker, marker_found := runtime_find_component(registry, "marker")
	stats, stats_found := runtime_find_component(registry, "stats")
	testing.expect_value(t, marker_found, true)
	testing.expect_value(t, len(marker.fields), 0)
	testing.expect_value(t, stats_found, true)
	testing.expect_value(t, len(stats.fields), 1)
	testing.expect_value(t, stats.fields[0].name, "count")
}

@(test)
test_component_scan_registers_script_system_access_and_order :: proc(t: ^testing.T) {
	root := make_test_project(t, "component-scan-script-system")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, "scripts/gameplay.luau", `local Transform = ecs.component<<ScrapbotTransform>>("scrapbot.transform")
local Health = ecs.component("health", {
  fields = ecs.fields({
    current = "f32",
  }),
})

local Moving = ecs.query(Transform, Health)

ecs.system("move_entities", {
  query = Moving,
  writes = ecs.refs(Transform),
  after = { "prepare_entities" },
})
`)

	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)
	engine_err := runtime_register_engine_components(&registry)
	testing.expect_value(t, engine_err, Runtime_Error.None)
	script_path := project_relative_path(root, "scripts/gameplay.luau")
	defer delete(script_path)
	err := register_script_components_from_file(&registry, script_path)
	testing.expect_value(t, err, Project_Error.None)

	system, found := runtime_find_system(registry, "move_entities")
	testing.expect_value(t, found, true)
	if !found {
		return
	}
	testing.expect_value(t, system.phase, Runtime_System_Phase.Update)
	testing.expect_value(t, len(system.reads), 1)
	testing.expect_value(t, system.reads[0], "health")
	testing.expect_value(t, len(system.writes), 1)
	testing.expect_value(t, system.writes[0], TRANSFORM_COMPONENT_ID)
	testing.expect_value(t, len(system.after), 1)
	testing.expect_value(t, system.after[0], "prepare_entities")
	testing.expect_value(t, system.runner.kind, Runtime_System_Runner_Kind.Luau)
}

@(test)
test_component_scan_rejects_script_system_unknown_ref :: proc(t: ^testing.T) {
	root := make_test_project(t, "component-scan-script-system-unknown-ref")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, "scripts/gameplay.luau", `ecs.system("broken", {
  writes = ecs.refs(Missing),
})
`)

	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)
	engine_err := runtime_register_engine_components(&registry)
	testing.expect_value(t, engine_err, Runtime_Error.None)
	script_path := project_relative_path(root, "scripts/gameplay.luau")
	defer delete(script_path)
	err := register_script_components_from_file(&registry, script_path)
	testing.expect_value(t, err, Project_Error.Invalid_Script)
}

@(test)
test_component_scan_returns_script_system_diagnostic :: proc(t: ^testing.T) {
	root := make_test_project(t, "component-scan-script-system-diagnostic")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, "scripts/gameplay.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({}),
})

ecs.system("broken", {
  phase = "late_update",
  writes = ecs.refs(Flag),
})
`)

	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)
	script_path := project_relative_path(root, "scripts/gameplay.luau")
	defer delete(script_path)
	err, diagnostic := register_script_components_from_file_detailed(&registry, script_path, "scripts/gameplay.luau")
	defer {
		mutable_diagnostic := diagnostic
		script_diagnostic_free(&mutable_diagnostic)
	}
	testing.expect_value(t, err, Project_Error.Invalid_Script)
	testing.expect_value(t, diagnostic.stage, Script_Diagnostic_Stage.Registration)
	testing.expect_value(t, diagnostic.path, "scripts/gameplay.luau")
	testing.expect_value(t, diagnostic.system_id, "broken")
	testing.expect_value(t, diagnostic.start.line, 5)
	testing.expect_value(t, diagnostic.message, "system phase is not supported")
}
