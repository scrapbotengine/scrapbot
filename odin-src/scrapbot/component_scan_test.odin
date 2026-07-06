package main

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_component_scan_parses_native_field_lines :: proc(t: ^testing.T) {
	line := `.{ .name = "count", .field_type = .int },`
	name, name_ok := parse_assignment_string_value(line, ".name")
	field_type, type_ok := parse_assignment_enum_value(line, ".field_type")
	testing.expect_value(t, name_ok, true)
	testing.expect_value(t, name, "count")
	testing.expect_value(t, type_ok, true)
	testing.expect_value(t, field_type, "int")
	runtime_type, runtime_type_ok := component_field_type_from_native(field_type)
	testing.expect_value(t, runtime_type_ok, true)
	testing.expect_value(t, runtime_type, Runtime_Field_Type.Int)

	samples := [4]string{
		`.{ .name = "enabled", .field_type = .boolean },`,
		`.{ .name = "speed", .field_type = .float },`,
		`.{ .name = "direction", .field_type = .vec3 },`,
		`.{ .name = "label", .field_type = .string },`,
	}
	expected_types := [4]string{"boolean", "float", "vec3", "string"}
	for sample, index in samples {
		_, sample_name_ok := parse_assignment_string_value(sample, ".name")
		sample_type, sample_type_ok := parse_assignment_enum_value(sample, ".field_type")
		_, sample_runtime_type_ok := component_field_type_from_native(sample_type)
		testing.expect_value(t, sample_name_ok, true)
		testing.expect_value(t, sample_type_ok, true)
		testing.expect_value(t, sample_type, expected_types[index])
		testing.expect_value(t, sample_runtime_type_ok, true)
	}
}

@(test)
test_component_scan_parses_native_field_arrays :: proc(t: ^testing.T) {
	source := `const scrapbot = @import("scrapbot_native");

const stats_fields = [_]scrapbot.ComponentField{
    .{ .name = "count", .field_type = .int },
    .{ .name = "enabled", .field_type = .boolean },
    .{ .name = "speed", .field_type = .float },
    .{ .name = "direction", .field_type = .vec3 },
    .{ .name = "label", .field_type = .string },
};
`
	start := strings.index(source, "stats_fields")
	testing.expect(t, start >= 0)
	type_index := strings.index(source[start + len("stats_fields"):], "scrapbot.ComponentField{")
	testing.expect(t, type_index >= 0)
	body_fragment := source[start + len("stats_fields") + type_index + len("scrapbot.ComponentField{"):]
	end := strings.index(body_fragment, "};")
	testing.expect(t, end >= 0)
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
test_component_scan_registers_native_components :: proc(t: ^testing.T) {
	root := make_test_project(t, "component-scan-native")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, "native/game.zig", `const scrapbot = @import("scrapbot_native");

const stats_fields = [_]scrapbot.ComponentField{
    .{ .name = "count", .field_type = .int },
};

export fn scrapbot_register(api: *const scrapbot.RegisterApi) callconv(.c) c_int {
    scrapbot.registerComponent(api, .{
        .id = "native_stats",
        .fields = stats_fields[0..],
    }) catch return 0;
    return 1;
}
`)

	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)
	native_path := project_relative_path(root, "native/game.zig")
	defer delete(native_path)
	err := register_native_components_from_file(&registry, native_path)
	testing.expect_value(t, err, Project_Error.None)
	_, found := runtime_find_component(registry, "native_stats")
	testing.expect_value(t, found, true)
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
