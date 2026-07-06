package main

import "core:os"
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

[entities.components.marker]
value = true

[[entities]]
id = "dupe"
name = "Two"

[entities.components.marker]
value = true
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
