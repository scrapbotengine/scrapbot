package main

import "core:os"
import "core:testing"

@(test)
test_run_init_command_creates_checkable_project :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-init-project")
	defer os.remove_all(root)
	defer delete(root)

	exit_code := run_with_output([]string{"scrapbot", "init", root}, false)
	testing.expect_value(t, exit_code, 0)

	result := check_project(root)
	defer free_check_result(result)
	testing.expect_value(t, result.err, Project_Error.None)
	testing.expect_value(t, result.project.name, "cli-init-project")
}

@(test)
test_run_init_command_rejects_extra_arguments :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-init-extra")
	defer os.remove_all(root)
	defer delete(root)

	exit_code := run_with_output([]string{"scrapbot", "init", root, "extra"}, false)
	testing.expect_value(t, exit_code, 1)
	testing.expect_value(t, os.exists(root), false)
}

@(test)
test_run_build_command_creates_bundle :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-build-project")
	defer os.remove_all(root)
	defer delete(root)
	output_root := make_test_project_root(t, "cli-build-output")
	defer os.remove_all(output_root)
	defer delete(output_root)

	testing.expect_value(t, init_project(root, "CLI Build"), Project_Error.None)

	exit_code := run_with_output([]string{"scrapbot", "build", root, "--output", output_root, "--name", "cli-build", "--format=json"}, false)
	testing.expect_value(t, exit_code, 0)

	bundle_path := project_relative_path(output_root, "cli-build")
	defer delete(bundle_path)
	marker_path := project_relative_path(bundle_path, BUILD_BUNDLE_MARKER)
	defer delete(marker_path)
	packaged_project_path := project_relative_path(bundle_path, BUILD_PROJECT_DIR)
	defer delete(packaged_project_path)
	testing.expect_value(t, os.exists(marker_path), true)

	packaged := check_project(packaged_project_path)
	defer free_check_result(packaged)
	testing.expect_value(t, packaged.err, Project_Error.None)
	testing.expect_value(t, packaged.project.name, "CLI Build")
}

@(test)
test_run_build_command_rejects_extra_arguments :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-build-extra")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Build Extra"), Project_Error.None)

	exit_code := run_with_output([]string{"scrapbot", "build", root, "extra"}, false)
	testing.expect_value(t, exit_code, 1)
}

@(test)
test_run_check_command_accepts_json_format :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-check-json")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Check JSON"), Project_Error.None)

	exit_code := run_with_output([]string{"scrapbot", "check", root, "--format", "json"}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_step_command_accepts_initialized_project :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-step-project")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Step"), Project_Error.None)

	exit_code := run_with_output([]string{"scrapbot", "step", root, "--frames", "3", "--dt=0.5", "--format=json"}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_step_command_accepts_script_schedules :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-step-script-project")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Step Script\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")
	write_file(t, root, "scripts/gameplay.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({}),
})

local Flags = ecs.query(Flag)

ecs.system("observe_flags", {
  query = Flags,
})
`)

	exit_code := run_with_output([]string{"scrapbot", "step", root, "--frames=2"}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_step_command_rejects_invalid_frames_and_dt :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-step-invalid")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Step Invalid"), Project_Error.None)

	frames_exit_code := run_with_output([]string{"scrapbot", "step", root, "--frames", "0"}, false)
	testing.expect_value(t, frames_exit_code, 1)
	dt_exit_code := run_with_output([]string{"scrapbot", "step", root, "--dt", "-1.0"}, false)
	testing.expect_value(t, dt_exit_code, 1)
}

@(test)
test_run_step_command_rejects_extra_arguments :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-step-extra")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Step Extra"), Project_Error.None)

	exit_code := run_with_output([]string{"scrapbot", "step", root, "extra"}, false)
	testing.expect_value(t, exit_code, 1)
}
