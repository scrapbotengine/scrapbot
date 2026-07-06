package main

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_check_project_reports_scene_summary :: proc(t: ^testing.T) {
	root := make_test_project(t, "scene-summary")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_file(
		t,
		root,
		"scenes/main.scene.toml",
		`name = "Main"
version = 1

[[entities]]
id = "cube-1"
name = "Cube"

[entities.components."scrapbot.render.cube"]
color = [1.0, 0.0, 0.0]

[[entities]]
id = "empty-component"
name = "Button"

[entities.components."scrapbot.ui.button"]
`,
	)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	testing.expect_value(t, result.scene.name, "Main")
	testing.expect_value(t, result.scene.entity_count, 2)
	testing.expect_value(t, result.scene.component_instance_count, 2)
	testing.expect_value(t, result.scene.renderable_cube_count, 1)
}

@(test)
test_check_project_rejects_duplicate_scene_entity_ids :: proc(t: ^testing.T) {
	root := make_test_project(t, "duplicate-scene-entity")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_file(
		t,
		root,
		"scenes/main.scene.toml",
		`name = "Main"
version = 1

[[entities]]
id = "dupe"
name = "One"

[entities.components."scrapbot.ui.button"]

[[entities]]
id = "dupe"
name = "Two"

[entities.components."scrapbot.ui.button"]
`,
	)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Duplicate_Scene_Entity_ID)
}

@(test)
test_check_project_rejects_scene_without_entities :: proc(t: ^testing.T) {
	root := make_test_project(t, "scene-without-entities")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_file(t, root, "scenes/main.scene.toml", "name = \"Main\"\nversion = 1\n")

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Missing_Scene_Content)
}

@(test)
test_check_project_rejects_entity_without_component :: proc(t: ^testing.T) {
	root := make_test_project(t, "entity-without-component")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_file(
		t,
		root,
		"scenes/main.scene.toml",
		`name = "Main"
version = 1

[[entities]]
id = "empty"
name = "Empty"
`,
	)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Scene)
}

@(test)
test_check_project_rejects_unsupported_scene_version :: proc(t: ^testing.T) {
	root := make_test_project(t, "unsupported-scene-version")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_file(t, root, "scenes/main.scene.toml", "name = \"Main\"\nversion = 99\n")

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Unsupported_Scene_Version)
}

@(test)
test_check_project_rejects_unknown_engine_component :: proc(t: ^testing.T) {
	root := make_test_project(t, "unknown-engine-component")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_basic_scene_with_component(t, root, `[entities.components."scrapbot.render.unknown"]
color = [1.0, 0.0, 0.0]
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Scene)
}

@(test)
test_check_project_rejects_runtime_only_component :: proc(t: ^testing.T) {
	root := make_test_project(t, "runtime-only-component")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_basic_scene_with_component(t, root, `[entities.components."scrapbot.input.frame"]
ui_visible = true
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Scene)
}

@(test)
test_check_project_rejects_unknown_engine_component_field :: proc(t: ^testing.T) {
	root := make_test_project(t, "unknown-engine-component-field")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_basic_scene_with_component(t, root, `[entities.components."scrapbot.render.cube"]
color = [1.0, 0.0, 0.0]
opacity = 0.5
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Scene)
}

@(test)
test_check_project_rejects_duplicate_engine_component_field :: proc(t: ^testing.T) {
	root := make_test_project(t, "duplicate-engine-component-field")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_basic_scene_with_component(t, root, `[entities.components."scrapbot.render.cube"]
color = [1.0, 0.0, 0.0]
color = [0.0, 1.0, 0.0]
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Scene)
}

@(test)
test_check_project_rejects_invalid_engine_component_field_type :: proc(t: ^testing.T) {
	root := make_test_project(t, "invalid-engine-component-field-type")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_basic_scene_with_component(t, root, `[entities.components."scrapbot.transform"]
position = "nope"
rotation = [0.0, 0.0, 0.0]
scale = [1.0, 1.0, 1.0]
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Scene)
}

@(test)
test_check_project_rejects_missing_required_engine_component_field :: proc(t: ^testing.T) {
	root := make_test_project(t, "missing-required-engine-component-field")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_basic_scene_with_component(t, root, `[entities.components."scrapbot.transform"]
position = [0.0, 0.0, 0.0]
rotation = [0.0, 0.0, 0.0]
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Scene)
}

@(test)
test_check_project_rejects_missing_required_ui_component_field :: proc(t: ^testing.T) {
	root := make_test_project(t, "missing-required-ui-component-field")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_basic_scene_with_component(t, root, `[entities.components."scrapbot.ui.progress_bar"]
value = 0.5
max = 1.0
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Scene)
}

@(test)
test_check_project_rejects_invalid_renderer_setting_value :: proc(t: ^testing.T) {
	root := make_test_project(t, "invalid-renderer-setting-value")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_basic_scene_with_component(t, root, `[entities.components."scrapbot.renderer"]
tone_mapping = "cinematic"
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Scene)
}

@(test)
test_check_project_rejects_negative_renderer_setting_value :: proc(t: ^testing.T) {
	root := make_test_project(t, "negative-renderer-setting-value")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_basic_scene_with_component(t, root, `[entities.components."scrapbot.renderer"]
bloom_intensity = -1.0
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Scene)
}

@(test)
test_check_project_accepts_defaulted_engine_component_fields :: proc(t: ^testing.T) {
	root := make_test_project(t, "defaulted-engine-component-fields")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_basic_scene_with_component(t, root, `[entities.components."scrapbot.ui.rect"]
position = [0.0, 0.0, 0.0]
size = [10.0, 10.0, 0.0]
color = [1.0, 1.0, 1.0]

[entities.components."scrapbot.renderer"]
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	testing.expect_value(t, result.scene.component_instance_count, 2)
}

@(test)
test_check_project_rejects_undeclared_project_local_component :: proc(t: ^testing.T) {
	root := make_test_project(t, "undeclared-project-local-component")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")
	write_basic_scene_with_component(t, root, `[entities.components.health]
current = 5.0
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Scene)
}

@(test)
test_check_project_accepts_script_defined_scene_component_schema :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-defined-scene-component")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_file(t, root, "scripts/gameplay.luau", `--!strict

local Health = ecs.component("health", {
  fields = ecs.fields({
    current = "f32",
    max = "int",
    alive = "boolean",
    label = "string",
    direction = "vec3",
  }),
})
`)
	write_basic_scene_with_component(t, root, `[entities.components.health]
current = 5.0
max = 10
alive = true
label = "ready"
direction = [0.0, 1.0, 0.0]
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
}

@(test)
test_check_project_rejects_script_defined_scene_component_field_mismatch :: proc(t: ^testing.T) {
	root := make_test_project(t, "script-defined-scene-component-mismatch")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_file(t, root, "scripts/gameplay.luau", `--!strict

ecs.component("health", {
  fields = ecs.fields({
    current = "f32",
  }),
})
`)
	write_basic_scene_with_component(t, root, `[entities.components.health]
current = "not a float"
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.Invalid_Scene)
}

@(test)
test_check_project_accepts_native_defined_scene_component_schema :: proc(t: ^testing.T) {
	root := make_test_project(t, "native-defined-scene-component")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Game\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nnative = \"native/game.zig\"\n")
	write_file(t, root, "native/game.zig", `const scrapbot = @import("scrapbot_native");

const stats_fields = [_]scrapbot.ComponentField{
    .{ .name = "count", .field_type = .int },
    .{ .name = "enabled", .field_type = .boolean },
    .{ .name = "speed", .field_type = .float },
    .{ .name = "direction", .field_type = .vec3 },
    .{ .name = "label", .field_type = .string },
};

export fn scrapbot_register(api: *const scrapbot.RegisterApi) callconv(.c) c_int {
    scrapbot.registerComponent(api, .{
        .id = "native_stats",
        .fields = stats_fields[0..],
    }) catch return 0;
    return 1;
}
`)
	write_basic_scene_with_component(t, root, `[entities.components.native_stats]
count = 2
enabled = true
speed = 1.5
direction = [1.0, 2.0, 3.0]
label = "ready"
`)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
}

write_basic_scene_with_component :: proc(t: ^testing.T, root, component_body: string) {
	scene, concat_err := strings.concatenate([]string{`name = "Main"
version = 1

[[entities]]
id = "entity"
name = "Entity"

`, component_body})
	testing.expect_value(t, concat_err, nil)
	defer delete(scene)
	write_file(t, root, "scenes/main.scene.toml", scene)
}
