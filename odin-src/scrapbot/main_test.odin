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
test_run_check_command_accepts_equals_json_format :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-check-equals-json")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Check Equals JSON"), Project_Error.None)

	exit_code := run_with_output([]string{"scrapbot", "check", root, "--format=json"}, false)
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

@(test)
test_run_bench_command_accepts_initialized_project :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-bench-project")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Bench"), Project_Error.None)

	exit_code := run_with_output([]string{"scrapbot", "bench", root, "--frames", "3", "--dt=0.5", "--format=json"}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_bench_command_accepts_script_schedules :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-bench-script-project")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Bench Script\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")
	write_file(t, root, "scripts/gameplay.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({}),
})

local Flags = ecs.query(Flag)

ecs.system("observe_flags", {
  query = Flags,
})
`)

	exit_code := run_with_output([]string{"scrapbot", "bench", root, "--frames=2"}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_bench_command_rejects_invalid_frames_and_dt :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-bench-invalid")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Bench Invalid"), Project_Error.None)

	frames_exit_code := run_with_output([]string{"scrapbot", "bench", root, "--frames", "0"}, false)
	testing.expect_value(t, frames_exit_code, 1)
	dt_exit_code := run_with_output([]string{"scrapbot", "bench", root, "--dt", "-1.0"}, false)
	testing.expect_value(t, dt_exit_code, 1)
}

@(test)
test_run_bench_command_rejects_extra_arguments :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-bench-extra")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Bench Extra"), Project_Error.None)

	exit_code := run_with_output([]string{"scrapbot", "bench", root, "extra"}, false)
	testing.expect_value(t, exit_code, 1)
}

@(test)
test_run_test_command_accepts_test_project_directory :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-project")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Test"), Project_Error.None)
	write_valid_test_manifest(t, root)

	exit_code := run_with_output([]string{"scrapbot", "test", root, "--format=json"}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_discovers_child_test_projects :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-suite")
	defer os.remove_all(root)
	defer delete(root)

	first := project_relative_path(root, "first")
	defer delete(first)
	second := project_relative_path(root, "second")
	defer delete(second)
	testing.expect_value(t, init_project(first, "First Test"), Project_Error.None)
	testing.expect_value(t, init_project(second, "Second Test"), Project_Error.None)
	write_valid_test_manifest(t, first)
	write_valid_test_manifest(t, second)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_reports_no_projects :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-empty")
	defer os.remove_all(root)
	defer delete(root)

	exit_code := run_with_output([]string{"scrapbot", "test", root, "--format=json"}, false)
	testing.expect_value(t, exit_code, 1)
}

@(test)
test_run_test_command_rejects_invalid_manifest :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-invalid-manifest")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "Invalid Test"), Project_Error.None)
	write_file(t, root, TEST_MANIFEST_NAME, "frames = 1\ndt = 1.0\n")

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 1)
}

@(test)
test_run_command_accepts_initialized_project :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-run-project")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Run"), Project_Error.None)

	exit_code := run_with_output([]string{"scrapbot", "run", root, "--frames=2", "--hidden"}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_parse_run_options_accepts_frames_editor_and_hidden_flags :: proc(t: ^testing.T) {
	options, ok := parse_run_options([]string{"--frames", "12", "--editor", "--hidden"}, false)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, options.max_frames, 12)
	testing.expect_value(t, options.editor, true)
	testing.expect_value(t, options.hidden, true)
}

@(test)
test_run_command_rejects_hidden_without_frame_limit :: proc(t: ^testing.T) {
	exit_code := run_with_output([]string{"scrapbot", "run", "--hidden"}, false)
	testing.expect_value(t, exit_code, 1)
}

@(test)
test_run_command_rejects_extra_arguments :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-run-extra")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Run Extra"), Project_Error.None)

	exit_code := run_with_output([]string{"scrapbot", "run", root, "extra"}, false)
	testing.expect_value(t, exit_code, 1)
}

@(test)
test_run_command_rejects_extra_argument_after_explicit_current_directory :: proc(t: ^testing.T) {
	exit_code := run_with_output([]string{"scrapbot", "run", ".", "extra"}, false)
	testing.expect_value(t, exit_code, 1)
}

@(test)
test_parse_test_manifest_summary_counts_expectations_and_input_frames :: proc(t: ^testing.T) {
	summary, ok := parse_test_manifest_summary(`frames = 2
dt = 0.016

[[input.frame]]
frame = 1
viewport = [1280.0, 720.0]
pointer = [20.0, 20.0]
primary_held = true
primary_released = true

[[expect.field]]
entity = "flag"
component = "flag"
field = "active"
equals_bool = true

[[expect.field]]
entity = "counter"
component = "counter"
field = "value"
equals_int = 2
`)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, summary.frames, 2)
	testing.expect_value(t, summary.input_frames, 1)
	testing.expect_value(t, summary.expectations, 2)
}

write_valid_test_manifest :: proc(t: ^testing.T, root: string) {
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 1
dt = 1.0

[[expect.field]]
entity = "entity"
component = "scrapbot.ui.button"
field = "pressed"
equals_bool = false
`)
}
