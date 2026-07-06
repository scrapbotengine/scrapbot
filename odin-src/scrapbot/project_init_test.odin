package main

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_project_name_from_path_uses_final_segment :: proc(t: ^testing.T) {
	testing.expect_value(t, project_name_from_path("games/demo"), "demo")
	testing.expect_value(t, project_name_from_path("games/demo/"), "demo")
	testing.expect_value(t, project_name_from_path("."), "Scrapbot Project")
}

@(test)
test_init_project_creates_checkable_project :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "init-project")
	defer os.remove_all(root)
	defer delete(root)

	err := init_project(root, project_name_from_path(root))
	testing.expect_value(t, err, Project_Error.None)

	project_path := project_relative_path(root, PROJECT_FILE_NAME)
	defer delete(project_path)
	scene_path := project_relative_path(root, DEFAULT_SCENE_PATH)
	defer delete(scene_path)
	gitkeep_path := project_relative_path(root, "assets/.gitkeep")
	defer delete(gitkeep_path)
	native_path := project_relative_path(root, "native/game.odin")
	defer delete(native_path)
	testing.expect_value(t, os.exists(project_path), true)
	testing.expect_value(t, os.exists(scene_path), true)
	testing.expect_value(t, os.exists(gitkeep_path), true)
	testing.expect_value(t, os.exists(native_path), false)

	metadata, read_err := os.read_entire_file(project_path, context.allocator)
	testing.expect_value(t, read_err, nil)
	defer delete(metadata)
	testing.expect(t, strings.contains(string(metadata), "\n# native = \"native/game.odin\"\n"))

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	testing.expect_value(t, result.project.name, "init-project")
	testing.expect_value(t, result.scene.entity_count, 4)
	testing.expect_value(t, result.scene.component_instance_count, 7)
}

@(test)
test_init_project_escapes_project_name :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "init-escaped-project")
	defer os.remove_all(root)
	defer delete(root)

	err := init_project(root, `Agent "One"`)
	testing.expect_value(t, err, Project_Error.None)

	project_path := project_relative_path(root, PROJECT_FILE_NAME)
	defer delete(project_path)
	metadata, read_err := os.read_entire_file(project_path, context.allocator)
	testing.expect_value(t, read_err, nil)
	defer delete(metadata)
	testing.expect(t, strings.contains(string(metadata), `name = "Agent \"One\""`))

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	testing.expect_value(t, result.project.name, `Agent "One"`)
}

@(test)
test_init_project_refuses_existing_project_metadata :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "init-existing-project")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, ensure_directory(root), true)
	write_file(t, root, PROJECT_FILE_NAME, "name = \"Existing\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")

	err := init_project(root, "Demo")
	testing.expect_value(t, err, Project_Error.Already_Exists)
}

@(test)
test_init_project_refuses_existing_legacy_metadata :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "init-existing-legacy-project")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, ensure_directory(root), true)
	write_file(t, root, LEGACY_PROJECT_FILE_NAME, "name = \"Existing\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\n")

	err := init_project(root, "Demo")
	testing.expect_value(t, err, Project_Error.Already_Exists)
}

make_test_project_root :: proc(t: ^testing.T, name: string) -> string {
	base := "odin-out/odin-tests"
	if !ensure_directory(base) {
		testing.fail_now(t, "failed to create test project parent")
	}
	root, join_err := filepath.join([]string{"odin-out", "odin-tests", name})
	if join_err != nil {
		testing.fail_now(t, "failed to join test project path")
	}
	os.remove_all(root)
	return root
}
