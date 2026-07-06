package main

import "core:os"
import "core:path/filepath"
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
