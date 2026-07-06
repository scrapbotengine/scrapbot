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
test_run_test_command_fails_mismatched_assertion :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-mismatched-assertion")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "Mismatched Test"), Project_Error.None)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 1
dt = 1.0

[[expect.field]]
entity = "scrapbot.renderer"
component = "scrapbot.renderer"
field = "hdr"
equals_bool = false
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 1)
}

@(test)
test_run_test_command_replays_input_resources :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-input-replay")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "Input Replay Test"), Project_Error.None)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Input Replay Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/gameplay.luau"]
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Input Replay Test"
version = 1

[[entities]]
id = "flag"
name = "Flag"

[entities.components.flag]
active = false
`)
	write_file(t, root, "scripts/gameplay.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({
    active = "boolean",
  }),
})
local Pointer = ecs.component("scrapbot.input.pointer")
local Keyboard = ecs.component("scrapbot.input.keyboard")
local Frame = ecs.component("scrapbot.input.frame")

local Flags = ecs.query(Flag)
local Inputs = ecs.query(Pointer, Keyboard, Frame)

ecs.system("read_input", {
  phase = "update",
  query = Inputs,
  reads = ecs.refs(Pointer, Keyboard, Frame),
  writes = ecs.refs(Flag),
  run = function(world, _dt)
    for _input_entity, pointer, keyboard, frame in Inputs:iter(world) do
      if pointer.has_position and pointer.primary_released and keyboard.move_forward and frame.debug_overlay_visible then
        for _flag_entity, flag in Flags:iter(world) do
          flag.active = true
        end
      end
    end
  end,
})
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 1
dt = 0.016

[[input.frame]]
frame = 1
debug_overlay_visible = true
viewport = [1280.0, 720.0]
pointer = [500.0, 148.0]
primary_released = true
move_forward = true

[[expect.field]]
entity = "flag"
component = "flag"
field = "active"
equals_bool = true
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_retained_ui_commands :: proc(t: ^testing.T) {
	exit_code := run_with_output([]string{"scrapbot", "test", "tests/projects/ui_command_replay"}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_retained_ui_scroll :: proc(t: ^testing.T) {
	exit_code := run_with_output([]string{"scrapbot", "test", "tests/projects/ui_scroll_replay"}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_consumes_editor_chrome_input :: proc(t: ^testing.T) {
	exit_code := run_with_output([]string{"scrapbot", "test", "tests/projects/editor_chrome_input"}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_play_pause :: proc(t: ^testing.T) {
	root := make_editor_playback_test_project(t, "cli-test-editor-play-pause")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 2
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [1040.0, 20.0]
primary_pressed = true
primary_down = true

[[expect.field]]
entity = "counter"
component = "counter"
field = "ticks"
equals_int = 0
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_single_step :: proc(t: ^testing.T) {
	root := make_editor_playback_test_project(t, "cli-test-editor-single-step")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 2
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [1160.0, 20.0]
primary_pressed = true
primary_down = true

[[expect.field]]
entity = "counter"
component = "counter"
field = "ticks"
equals_int = 1
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

make_editor_playback_test_project :: proc(t: ^testing.T, name: string) -> string {
	root := make_test_project_root(t, name)
	testing.expect_value(t, init_project(root, "Editor Playback Test"), Project_Error.None)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Playback Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/gameplay.luau"]
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Playback Test"
version = 1

[[entities]]
id = "counter"
name = "Counter"

[entities.components.counter]
ticks = 0
`)
	write_file(t, root, "scripts/gameplay.luau", `local Counter = ecs.component("counter", {
  fields = ecs.fields({
    ticks = "int",
  }),
})

local Counters = ecs.query(Counter)

ecs.system("tick_counter", {
  phase = "update",
  query = Counters,
  writes = ecs.refs(Counter),
  run = function(world, _dt)
    for _entity, counter in Counters:iter(world) do
      counter.ticks = counter.ticks + 1
    end
  end,
})
`)
	return root
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
test_parse_render_options_accepts_dimensions_editor_and_select :: proc(t: ^testing.T) {
	options, ok := parse_render_options(
		[]string{"--frames", "4", "--width=320", "--height", "240", "--pixel-scale", "2.0", "--select", "cube", "project", "out.png"},
		DEFAULT_RENDER_OUTPUT,
		false,
	)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, options.frames, 4)
	testing.expect_value(t, options.width, 320)
	testing.expect_value(t, options.height, 240)
	testing.expect_value(t, options.pixel_scale, f32(2.0))
	testing.expect_value(t, options.editor, true)
	testing.expect_value(t, options.selected_entity_id, "cube")
	testing.expect_value(t, options.target_path, "project")
	testing.expect_value(t, options.output_path, "out.png")
}

@(test)
test_run_render_command_accepts_initialized_project :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-render-project")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Render"), Project_Error.None)

	exit_code := run_with_output([]string{"scrapbot", "render", "--frames=2", "--width", "320", "--height=240", root, "odin-out/test-render.png"}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_render_command_updates_only_extra_frames :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-render-extra-frame-updates")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Render Frames\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")
	write_file(t, root, "scripts/gameplay.luau", `ecs.system("fails_on_update", {
  phase = "update",
  run = function()
    error("update should only run for extra render frames")
  end,
})
`)

	default_exit_code := run_with_output([]string{"scrapbot", "render", root}, false)
	testing.expect_value(t, default_exit_code, 0)
	two_frame_exit_code := run_with_output([]string{"scrapbot", "render", "--frames=2", root}, false)
	testing.expect_value(t, two_frame_exit_code, 1)
}

@(test)
test_run_render_test_command_accepts_selected_entity :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-render-test-project")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Render Test"), Project_Error.None)

	exit_code := run_with_output([]string{"scrapbot", "render-test", "--select", "018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_render_command_rejects_missing_selected_entity :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-render-missing-selection")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Render Missing Selection"), Project_Error.None)

	exit_code := run_with_output([]string{"scrapbot", "render", "--select", "missing", root}, false)
	testing.expect_value(t, exit_code, 1)
}

@(test)
test_run_render_command_rejects_invalid_dimensions_and_extra_arguments :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-render-invalid")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Render Invalid"), Project_Error.None)

	width_exit_code := run_with_output([]string{"scrapbot", "render", root, "--width", "0"}, false)
	testing.expect_value(t, width_exit_code, 1)
	extra_exit_code := run_with_output([]string{"scrapbot", "render", root, "out.png", "extra"}, false)
	testing.expect_value(t, extra_exit_code, 1)
}

@(test)
test_parse_visual_test_options_accepts_expected_actual_update_and_render_flags :: proc(t: ^testing.T) {
	options, ok := parse_visual_test_options(
		[]string{"--update", "--select", "cube", "--frames=4", "--width", "320", "--height=240", "--pixel-scale", "2.0", "project", "expected.png", "actual.png"},
		false,
	)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, options.update, true)
	testing.expect_value(t, options.expected_path, "expected.png")
	testing.expect_value(t, options.render.target_path, "project")
	testing.expect_value(t, options.render.output_path, "actual.png")
	testing.expect_value(t, options.render.frames, 4)
	testing.expect_value(t, options.render.width, 320)
	testing.expect_value(t, options.render.height, 240)
	testing.expect_value(t, options.render.pixel_scale, f32(2.0))
	testing.expect_value(t, options.render.editor, true)
	testing.expect_value(t, options.render.selected_entity_id, "cube")
}

@(test)
test_run_visual_test_command_accepts_initialized_project_with_expected_fixture :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-visual-project")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Visual"), Project_Error.None)

	expected_path := project_relative_path(root, "expected.png")
	defer delete(expected_path)
	write_file(t, root, "expected.png", "not a real png yet")

	exit_code := run_with_output([]string{"scrapbot", "visual-test", root, expected_path, "odin-out/test-visual-actual.png"}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_visual_test_command_accepts_update_without_existing_expected_fixture :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-visual-update")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Visual Update"), Project_Error.None)

	expected_path := project_relative_path(root, "missing-expected.png")
	defer delete(expected_path)

	exit_code := run_with_output([]string{"scrapbot", "visual-test", "--update", root, expected_path}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_visual_test_command_rejects_missing_expected_and_same_actual_path :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-visual-invalid")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Visual Invalid"), Project_Error.None)

	expected_path := project_relative_path(root, "expected.png")
	defer delete(expected_path)

	missing_exit_code := run_with_output([]string{"scrapbot", "visual-test", root, expected_path}, false)
	testing.expect_value(t, missing_exit_code, 1)
	write_file(t, root, "expected.png", "not a real png yet")
	same_path_exit_code := run_with_output([]string{"scrapbot", "visual-test", root, expected_path, expected_path}, false)
	testing.expect_value(t, same_path_exit_code, 1)
}

@(test)
test_run_visual_test_command_rejects_missing_selected_entity :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-visual-missing-selection")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Visual Missing Selection"), Project_Error.None)

	expected_path := project_relative_path(root, "expected.png")
	defer delete(expected_path)
	write_file(t, root, "expected.png", "not a real png yet")

	exit_code := run_with_output([]string{"scrapbot", "visual-test", "--select", "missing", root, expected_path}, false)
	testing.expect_value(t, exit_code, 1)
}

@(test)
test_run_visual_test_command_updates_only_extra_frames :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-visual-extra-frame-updates")
	defer os.remove_all(root)
	defer delete(root)

	write_file(t, root, PROJECT_FILE_NAME, "name = \"Visual Frames\"\nversion = 1\ndefault_scene = \"scenes/main.scene.toml\"\nscripts = [\"scripts/gameplay.luau\"]\n")
	write_valid_scene_file(t, root, "scenes/main.scene.toml")
	write_file(t, root, "scripts/gameplay.luau", `ecs.system("fails_on_update", {
  phase = "update",
  run = function()
    error("update should only run for extra visual-test frames")
  end,
})
`)
	expected_path := project_relative_path(root, "expected.png")
	defer delete(expected_path)
	write_file(t, root, "expected.png", "not a real png yet")

	default_exit_code := run_with_output([]string{"scrapbot", "visual-test", root, expected_path}, false)
	testing.expect_value(t, default_exit_code, 0)
	two_frame_exit_code := run_with_output([]string{"scrapbot", "visual-test", "--frames=2", root, expected_path}, false)
	testing.expect_value(t, two_frame_exit_code, 1)
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

@(test)
test_parse_test_manifest_rejects_duplicate_input_frames :: proc(t: ^testing.T) {
	_, ok := parse_test_manifest(`frames = 2
dt = 0.016

[[input.frame]]
frame = 1
pointer = [20.0, 20.0]

[[input.frame]]
frame = 1
pointer = [40.0, 40.0]

[[expect.field]]
entity = "flag"
component = "flag"
field = "active"
equals_bool = true
`)
	testing.expect_value(t, ok, false)
}

write_valid_test_manifest :: proc(t: ^testing.T, root: string) {
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 1
dt = 1.0

[[expect.field]]
entity = "scrapbot.renderer"
component = "scrapbot.renderer"
field = "hdr"
equals_bool = true
`)
}
