package main

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_run_version_command_matches_top_level_cli :: proc(t: ^testing.T) {
	testing.expect_value(t, run_with_output([]string{"scrapbot", "--version"}, false), 0)
	testing.expect_value(t, run_with_output([]string{"scrapbot", "version"}, false), 0)
}

@(test)
test_run_wgpu_check_command_reports_missing_library :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-wgpu-check-missing")
	defer os.remove_all(root)
	defer delete(root)

	testing.expect_value(t, run_with_output([]string{"scrapbot", "wgpu-check", root}, false), 1)
}

@(test)
test_run_wgpu_check_command_loads_odin_out_library :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-wgpu-check-loads")
	defer os.remove_all(root)
	defer delete(root)

	staged_library := stage_fake_wgpu_odin_out_library(t, root)
	defer delete(staged_library)

	testing.expect_value(t, run_with_output([]string{"scrapbot", "wgpu-check", root}, false), 0)
}

@(test)
test_run_wgpu_render_test_command_reports_missing_library :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-wgpu-render-test-missing")
	defer os.remove_all(root)
	defer delete(root)

	output_path := join_test_path(t, root, "out.png")
	defer delete(output_path)

	testing.expect_value(t, run_with_output([]string{"scrapbot", "wgpu-render-test", root, output_path}, false), 1)
}

@(test)
test_run_wgpu_render_test_command_writes_odin_out_library_png :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-wgpu-render-test-loads")
	defer os.remove_all(root)
	defer delete(root)

	staged_library := stage_fake_wgpu_odin_out_library(t, root)
	defer delete(staged_library)

	output_path := join_test_path(t, root, "wgpu-render.png")
	defer delete(output_path)

	testing.expect_value(t, run_with_output([]string{"scrapbot", "wgpu-render-test", root, output_path}, false), 0)

	image, image_err := render_load_rgb_image(output_path)
	defer render_image_free(&image)
	testing.expect_value(t, image_err, Render_Image_Error.None)
	testing.expect_value(t, image.width, DEFAULT_WGPU_RENDER_TEST_WIDTH)
	testing.expect_value(t, image.height, DEFAULT_WGPU_RENDER_TEST_HEIGHT)
	testing.expect_value(t, image.rgb[0], u8(255))
	testing.expect_value(t, image.rgb[1], u8(0))
	testing.expect_value(t, image.rgb[2], u8(0))
}

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
test_bench_renderer_backend_labels_render_extraction :: proc(t: ^testing.T) {
	testing.expect_value(t, bench_renderer_backend_label(), "odin render extraction")
	testing.expect_value(t, bench_renderer_backend_json_label(), "odin_render_extraction")
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

@(test)
test_run_test_command_replays_editor_entity_selection :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-entity-selection")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Entity Selection Test"
version = 1

[[entities]]
id = "first"
name = "First"

[entities.components.flag]
value = 1

[[entities]]
id = "second"
name = "Second"

[entities.components.flag]
value = 2
`)
	write_file(t, root, "scripts/components.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({
    value = "int",
  }),
})
`)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Entity Selection Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 1
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 528.0]
primary_pressed = true
primary_down = true

[[expect.editor]]
selected_entity = "second"
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_entity_spawn :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-entity-spawn")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Entity Spawn Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({
    value = "int",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Entity Spawn Test"
version = 1

[[entities]]
id = "base"
name = "Base"

[entities.components.flag]
value = 1
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 1
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
editor_spawn_pressed = true

[[expect.editor]]
selected_entity = "editor-spawn-1"
entity_count = 3
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_routes_editor_spawn_button :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-spawn-button")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Spawn Button Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({
    value = "int",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Spawn Button Test"
version = 1

[[entities]]
id = "base"
name = "Base"

[entities.components.flag]
value = 1
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 1
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [210.0, 442.0]
primary_pressed = true
primary_down = true

[[expect.editor]]
selected_entity = "editor-spawn-1"
entity_count = 3
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_entity_despawn :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-entity-despawn")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Entity Despawn Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({
    value = "int",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Entity Despawn Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.flag]
value = 1
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 2
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
editor_despawn_pressed = true

[[expect.editor]]
entity_count = 1
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_routes_editor_despawn_button :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-despawn-button")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Despawn Button Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({
    value = "int",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Despawn Button Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.flag]
value = 1
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 2
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [254.0, 442.0]
primary_pressed = true
primary_down = true

[[expect.editor]]
entity_count = 1
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_add_component :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-add-component")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Add Component Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({
    value = "int",
  }),
})

local Extra = ecs.component("extra", {
  fields = ecs.fields({
    value = "int",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Add Component Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.flag]
value = 1
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 2
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
editor_add_component = "extra"

[[expect.editor]]
selected_entity = "target"
selected_has_component = "extra"
selected_component = "extra"
selected_field = "value"

[[expect.field]]
entity = "target"
component = "extra"
field = "value"
equals_int = 0
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_remove_component :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-remove-component")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Remove Component Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({
    value = "int",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Remove Component Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.flag]
value = 1
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 2
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
editor_remove_component = "flag"

[[expect.editor]]
selected_entity = "target"
selected_missing_component = "flag"
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_routes_editor_add_component_button :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-add-component-button")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Add Component Button Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({
    value = "int",
  }),
})

local Extra = ecs.component("extra", {
  fields = ecs.fields({
    value = "int",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Add Component Button Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.flag]
value = 1
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 2
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [1168.0, 100.0]
primary_pressed = true
primary_down = true

[[expect.editor]]
selected_entity = "target"
selected_has_component = "extra"
selected_component = "extra"
selected_field = "value"

[[expect.field]]
entity = "target"
component = "extra"
field = "value"
equals_int = 0
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_routes_editor_remove_component_button :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-remove-component-button")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Remove Component Button Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({
    value = "int",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Remove Component Button Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.flag]
value = 1
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 3
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [1000.0, 170.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 3
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [1220.0, 100.0]
primary_pressed = true
primary_down = true

[[expect.editor]]
selected_entity = "target"
selected_missing_component = "flag"
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_entity_scroll_selection :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-entity-scroll-selection")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Entity Scroll Selection Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local Flag = ecs.component("flag", {
  fields = ecs.fields({
    value = "int",
  }),
})
`)
	scene := strings.builder_make()
	defer strings.builder_destroy(&scene)
	strings.write_string(&scene, "name = \"Editor Entity Scroll Selection Test\"\nversion = 1\n")
	for index := 0; index < 20; index += 1 {
		append_test_format(&scene, "\n[[entities]]\nid = \"entity-%d\"\nname = \"Entity %d\"\n\n[entities.components.flag]\nvalue = %d\n", index, index, index)
	}
	write_file(t, root, "scenes/main.scene.toml", strings.to_string(scene))
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 2
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 510.0]
wheel = [0.0, -6.0]

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 510.0]
primary_pressed = true
primary_down = true

[[expect.editor]]
selected_entity = "entity-3"
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_system_scroll :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-system-scroll")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "Editor System Scroll Test"), Project_Error.None)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 1
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 140.0]
wheel = [0.0, -1.0]
system_profile_count_hint = 9

[[expect.editor]]
system_scroll_y = 18.0
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_inspector_scroll :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-inspector-scroll")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Inspector Scroll Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local function schema()
  return ecs.fields({
    a = "float",
    b = "float",
    c = "float",
  })
end

local C0 = ecs.component("c0", { fields = schema() })
local C1 = ecs.component("c1", { fields = schema() })
local C2 = ecs.component("c2", { fields = schema() })
local C3 = ecs.component("c3", { fields = schema() })
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Inspector Scroll Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.c0]
a = 1.0
b = 2.0
c = 3.0

[entities.components.c1]
a = 1.0
b = 2.0
c = 3.0

[entities.components.c2]
a = 1.0
b = 2.0
c = 3.0

[entities.components.c3]
a = 1.0
b = 2.0
c = 3.0
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 2
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [900.0, 190.0]
wheel = [0.0, -1.0]

[[expect.editor]]
selected_entity = "target"
inspector_scroll_y = 18.0
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_editor_inspector_routing_uses_scroll_view_component_stack :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	entity, entity_err := runtime_world_create_entity(&world, "selected", "Selected")
	testing.expect_value(t, entity_err, Runtime_Error.None)
	component_ids := [?]string{"c0", "c1", "c2", "c3", "c4", "c5"}
	for component_id in component_ids {
		fields := [?]Runtime_Component_Field_Value{
			{name = "a", value = runtime_component_value_float(1.0)},
			{name = "b", value = runtime_component_value_float(2.0)},
			{name = "c", value = runtime_component_value_float(3.0)},
		}
		testing.expect_value(t, runtime_world_set_component(&world, entity, component_id, fields[:]), Runtime_Error.None)
	}

	input := frame_input_default()
	input.debug_overlay_visible = true
	input.viewport_width = 1280.0
	input.viewport_height = 720.0
	input.pointer.has_position = true
	input.pointer.position = {900.0, 190.0}
	state := Editor_Test_Input_State{
		selected_entity = entity,
		has_selected_entity = true,
		inspector_scroll_y = 80.0,
	}
	routing_world, routing_ok := editor_inspector_routing_world(world, state, input, state.inspector_scroll_y)
	testing.expect_value(t, routing_ok, true)
	defer runtime_world_free(&routing_world)

	scroll, scroll_found := runtime_world_find_entity_by_id(routing_world, "scrapbot.editor.inspector.scroll")
	testing.expect_value(t, scroll_found, true)
	has_scroll, scroll_err := runtime_world_has_component(routing_world, scroll, UI_SCROLL_VIEW_COMPONENT_ID)
	testing.expect_value(t, scroll_err, Runtime_Error.None)
	testing.expect_value(t, has_scroll, true)
	stack, stack_found := runtime_world_find_entity_by_id(routing_world, "scrapbot.editor.inspector.components")
	testing.expect_value(t, stack_found, true)
	has_stack, stack_err := runtime_world_has_component(routing_world, stack, UI_VGROUP_COMPONENT_ID)
	testing.expect_value(t, stack_err, Runtime_Error.None)
	testing.expect_value(t, has_stack, true)
	parent, parent_err := runtime_world_get_string(routing_world, stack, UI_LAYOUT_ITEM_COMPONENT_ID, "parent")
	testing.expect_value(t, parent_err, Runtime_Error.None)
	testing.expect_value(t, parent, "scrapbot.editor.inspector.scroll")

	max_y, max_err := scroll_max_y(routing_world, scroll)
	testing.expect_value(t, max_err, Runtime_Error.None)
	testing.expect(t, max_y > 0)
	next_y, next_ok := editor_inspector_retained_scroll_next(world, state, input, state.inspector_scroll_y, -1.0)
	testing.expect_value(t, next_ok, true)
	testing.expect_value(t, next_y, state.inspector_scroll_y + UI_EDITOR_SCROLL_PIXELS_PER_WHEEL)
}

@(test)
test_editor_inspector_copies_focused_text_selection :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	entity, entity_err := runtime_world_create_entity(&world, "selected", "Selected")
	testing.expect_value(t, entity_err, Runtime_Error.None)
	fields := [?]Runtime_Component_Field_Value{{name = "label", value = runtime_component_value_string("alpha")}}
	testing.expect_value(t, runtime_world_set_component(&world, entity, "c0", fields[:]), Runtime_Error.None)

	state := Editor_Test_Input_State{
		selected_entity = entity,
		has_selected_entity = true,
	}
	focused := focus_editor_test_text_input(world, &state, "c0", "label", 0)
	testing.expect_value(t, focused, true)
	select_all_editor_test_text_input(&state)
	testing.expect_value(t, copy_editor_test_text_input_selection(&state), true)
	testing.expect_value(t, editor_test_clipboard_text(&state), "alpha")
}

@(test)
test_run_test_command_replays_editor_inspector_field_selection :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-inspector-field-selection")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Inspector Field Selection Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local C0 = ecs.component("c0", {
  fields = ecs.fields({
    a = "float",
    b = "float",
    c = "float",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Inspector Field Selection Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.c0]
a = 1.0
b = 2.0
c = 3.0
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 2
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [900.0, 285.0]
primary_pressed = true
primary_down = true

[[expect.editor]]
selected_entity = "target"
selected_component = "c0"
selected_field = "b"
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_inspector_text_edit :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-inspector-text-edit")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Inspector Text Edit Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local C0 = ecs.component("c0", {
  fields = ecs.fields({
    a = "float",
    b = "float",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Inspector Text Edit Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.c0]
a = 1.0
b = 2.0
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 3
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [900.0, 285.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 3
editor_visible = true
viewport = [1280.0, 720.0]
text_input = "7.5"
editor_enter_pressed = true

[[expect.editor]]
selected_entity = "target"
selected_component = "c0"
selected_field = "b"

[[expect.field]]
entity = "target"
component = "c0"
field = "b"
equals_float = 7.5
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)

	scene_path := project_relative_path(root, "scenes/main.scene.toml")
	defer delete(scene_path)
	scene_contents, read_err := os.read_entire_file(scene_path, context.allocator)
	if read_err != nil {
		testing.fail_now(t, "failed to read edited scene file")
	}
	defer delete(scene_contents)
	testing.expect(t, strings.contains(string(scene_contents), "\nb = 7.5\n"))
	testing.expect(t, !strings.contains(string(scene_contents), "\nb = 2.0\n"))
}

@(test)
test_run_test_command_replays_editor_inspector_clipboard_copy_paste :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-inspector-clipboard-copy-paste")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Inspector Clipboard Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local C0 = ecs.component("c0", {
  fields = ecs.fields({
    a = "float",
    b = "float",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Inspector Clipboard Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.c0]
a = 1.0
b = 2.0
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 5
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
editor_copy_pressed = true

[[input.frame]]
frame = 3
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [900.0, 285.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 4
editor_visible = true
viewport = [1280.0, 720.0]
clipboard_text = "7.5"
editor_paste_pressed = true

[[input.frame]]
frame = 5
editor_visible = true
viewport = [1280.0, 720.0]
editor_enter_pressed = true

[[expect.editor]]
selected_entity = "target"
selected_component = "c0"
selected_field = "b"
clipboard = "target"

[[expect.field]]
entity = "target"
component = "c0"
field = "b"
equals_float = 7.5
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_selected_header_copy :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-selected-header-copy")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Selected Header Copy Test"
version = 1
default_scene = "scenes/main.scene.toml"
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Selected Header Copy Test"
version = 1

[[entities]]
id = "target-with-a-very-long-id-that-must-copy-in-full"
name = "Target With A Very Long Name"

[entities.components."scrapbot.render.cube"]
color = [0.2, 0.4, 0.8]
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 2
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [920.0, 100.0]
primary_pressed = true
primary_down = true

[[expect.editor]]
selected_entity = "target-with-a-very-long-id-that-must-copy-in-full"
clipboard = "target-with-a-very-long-id-that-must-copy-in-full"
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_reports_editor_inspector_invalid_text_edit :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-inspector-invalid-text-edit")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Inspector Invalid Text Edit Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local C0 = ecs.component("c0", {
  fields = ecs.fields({
    a = "float",
    b = "float",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Inspector Invalid Text Edit Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.c0]
a = 1.0
b = 2.0
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 3
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [900.0, 285.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 3
editor_visible = true
viewport = [1280.0, 720.0]
text_input = "oops"
editor_enter_pressed = true

[[expect.editor]]
selected_entity = "target"
selected_component = "c0"
selected_field = "b"
diagnostic = "invalid value for c0.b"

[[expect.field]]
entity = "target"
component = "c0"
field = "b"
equals_float = 2.0
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_inspector_text_edit_undo :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-inspector-text-edit-undo")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Inspector Text Edit Undo Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local C0 = ecs.component("c0", {
  fields = ecs.fields({
    a = "float",
    b = "float",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Inspector Text Edit Undo Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.c0]
a = 1.0
b = 2.0
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 4
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [900.0, 285.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 3
editor_visible = true
viewport = [1280.0, 720.0]
text_input = "7.5"
editor_enter_pressed = true

[[input.frame]]
frame = 4
editor_visible = true
viewport = [1280.0, 720.0]
editor_undo_pressed = true

[[expect.editor]]
selected_entity = "target"
selected_component = "c0"
selected_field = "b"

[[expect.field]]
entity = "target"
component = "c0"
field = "b"
equals_float = 2.0
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_inspector_text_edit_redo :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-inspector-text-edit-redo")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Inspector Text Edit Redo Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local C0 = ecs.component("c0", {
  fields = ecs.fields({
    a = "float",
    b = "float",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Inspector Text Edit Redo Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.c0]
a = 1.0
b = 2.0
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 5
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [900.0, 285.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 3
editor_visible = true
viewport = [1280.0, 720.0]
text_input = "7.5"
editor_enter_pressed = true

[[input.frame]]
frame = 4
editor_visible = true
viewport = [1280.0, 720.0]
editor_undo_pressed = true

[[input.frame]]
frame = 5
editor_visible = true
viewport = [1280.0, 720.0]
editor_redo_pressed = true

[[expect.editor]]
selected_entity = "target"
selected_component = "c0"
selected_field = "b"

[[expect.field]]
entity = "target"
component = "c0"
field = "b"
equals_float = 7.5
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_inspector_text_caret_selection :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-inspector-text-caret-selection")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Inspector Text Caret Selection Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local C0 = ecs.component("c0", {
  fields = ecs.fields({
    label = "string",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Inspector Text Caret Selection Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.c0]
label = "alpha-beta"
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 8
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [900.0, 250.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 3
editor_visible = true
viewport = [1280.0, 720.0]
editor_home_pressed = true

[[input.frame]]
frame = 4
editor_visible = true
viewport = [1280.0, 720.0]
editor_right_pressed = true

[[input.frame]]
frame = 5
editor_visible = true
viewport = [1280.0, 720.0]
editor_right_pressed = true

[[input.frame]]
frame = 6
editor_visible = true
viewport = [1280.0, 720.0]
editor_left_pressed = true

[[input.frame]]
frame = 7
editor_visible = true
viewport = [1280.0, 720.0]
shift_down = true
editor_end_pressed = true

[[input.frame]]
frame = 8
editor_visible = true
viewport = [1280.0, 720.0]
text_input = "mega"
editor_enter_pressed = true

[[expect.editor]]
selected_entity = "target"
selected_component = "c0"
selected_field = "label"

[[expect.field]]
entity = "target"
component = "c0"
field = "label"
equals_string = "amega"
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_inspector_vec3_lane_text_edit :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-inspector-vec3-lane-text-edit")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Inspector Vec3 Lane Text Edit Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local C0 = ecs.component("c0", {
  fields = ecs.fields({
    position = "vec3",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Inspector Vec3 Lane Text Edit Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.c0]
position = [1.0, 2.0, 3.0]
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 3
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [1230.0, 250.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 3
editor_visible = true
viewport = [1280.0, 720.0]
text_input = "9.0"
editor_enter_pressed = true

[[expect.editor]]
selected_entity = "target"
selected_component = "c0"
selected_field = "position"
selected_lane = 2

[[expect.field]]
entity = "target"
component = "c0"
field = "position"
equals_vec3 = [1.0, 2.0, 9.0]
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_inspector_boolean_toggle :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-inspector-boolean-toggle")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Inspector Boolean Toggle Test"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local C0 = ecs.component("c0", {
  fields = ecs.fields({
    enabled = "boolean",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Inspector Boolean Toggle Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.c0]
enabled = false
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 2
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [900.0, 250.0]
primary_pressed = true
primary_down = true

[[expect.editor]]
selected_entity = "target"
selected_component = "c0"
selected_field = "enabled"

[[expect.field]]
entity = "target"
component = "c0"
field = "enabled"
equals_bool = true
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_inspector_primitive_selector :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-inspector-primitive-selector")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Inspector Primitive Selector Test"
version = 1
default_scene = "scenes/main.scene.toml"
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Inspector Primitive Selector Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components."scrapbot.geometry.primitive"]
primitive = "box"
segments = 16
rings = 8
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 2
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [900.0, 250.0]
primary_pressed = true
primary_down = true

[[expect.editor]]
selected_entity = "target"
selected_component = "scrapbot.geometry.primitive"
selected_field = "primitive"

[[expect.field]]
entity = "target"
component = "scrapbot.geometry.primitive"
field = "primitive"
equals_string = "plane"
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_inspector_renderer_selector :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-inspector-renderer-selector")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Inspector Renderer Selector Test"
version = 1
default_scene = "scenes/main.scene.toml"
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Inspector Renderer Selector Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components."scrapbot.renderer"]
hdr = true
tone_mapping = "aces"
exposure = 0.0
postprocess_enabled = true
antialiasing = "fxaa"
bloom_enabled = true
bloom_threshold = 0.85
bloom_intensity = 0.12
bloom_radius = 1.0
vignette_enabled = true
vignette_strength = 0.24
vignette_radius = 0.82
chromatic_aberration_enabled = true
chromatic_aberration_strength = 0.0025
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 2
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [900.0, 294.0]
primary_pressed = true
primary_down = true

[[expect.editor]]
selected_entity = "target"
selected_component = "scrapbot.renderer"
selected_field = "tone_mapping"

[[expect.field]]
entity = "target"
component = "scrapbot.renderer"
field = "tone_mapping"
equals_string = "none"
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_inspector_primitive_selector_undo :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-inspector-primitive-selector-undo")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Inspector Primitive Selector Undo Test"
version = 1
default_scene = "scenes/main.scene.toml"
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Inspector Primitive Selector Undo Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components."scrapbot.geometry.primitive"]
primitive = "box"
segments = 16
rings = 8
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 3
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [900.0, 250.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 3
editor_visible = true
viewport = [1280.0, 720.0]
editor_undo_pressed = true

[[expect.editor]]
selected_entity = "target"
selected_component = "scrapbot.geometry.primitive"
selected_field = "primitive"

[[expect.field]]
entity = "target"
component = "scrapbot.geometry.primitive"
field = "primitive"
equals_string = "box"
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_gizmo_drag :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-gizmo-drag")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "Editor Gizmo Drag Test"
version = 1
default_scene = "scenes/main.scene.toml"
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Editor Gizmo Drag Test"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.scrapbot.transform]
position = [0.0, 0.0, 0.0]
rotation = [0.0, 0.0, 0.0]
scale = [1.0, 1.0, 1.0]
`)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 4
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [20.0, 500.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [660.0, 358.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 3
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [760.0, 358.0]
primary_down = true

[[input.frame]]
frame = 4
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [760.0, 358.0]
primary_released = true

[[expect.editor]]
selected_entity = "target"

[[expect.field]]
entity = "target"
component = "scrapbot.transform"
field = "position"
equals_vec3 = [1.2, 0.0, 0.0]
`)

	exit_code := run_with_output([]string{"scrapbot", "test", root}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_run_test_command_replays_editor_splitter_drag :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-test-editor-splitter-drag")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "Editor Splitter Drag Test"), Project_Error.None)
	write_file(t, root, TEST_MANIFEST_NAME, `frames = 3
dt = 0.016

[[input.frame]]
frame = 1
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [325.0, 100.0]
primary_pressed = true
primary_down = true

[[input.frame]]
frame = 2
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [525.0, 100.0]
primary_down = true

[[input.frame]]
frame = 3
editor_visible = true
viewport = [1280.0, 720.0]
pointer = [525.0, 100.0]
primary_released = true

[[expect.editor]]
left_sidebar_width = 520.0
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
test_run_command_accepts_development_odin_native_project :: proc(t: ^testing.T) {
	root := make_test_project(t, "cli-run-development-odin-native-project")
	defer os.remove_all(root)
	defer delete(root)
	write_native_counter_project(t, root, "1")

	exit_code := run_with_output([]string{"scrapbot", "run", root, "--frames=2", "--hidden"}, false)
	testing.expect_value(t, exit_code, 0)
}

@(test)
test_parse_run_options_accepts_frames_editor_and_hidden_flags :: proc(t: ^testing.T) {
	options, ok := parse_run_options(
		[]string{"--frames", "12", "--editor", "--hidden", "--backend", "software", "--render-width=320", "--render-height", "240", "--render-pixel-scale", "2.0"},
		false,
	)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, options.max_frames, 12)
	testing.expect_value(t, options.editor, true)
	testing.expect_value(t, options.hidden, true)
	testing.expect_value(t, options.backend, Render_Backend.Software)
	testing.expect_value(t, options.render_width, 320)
	testing.expect_value(t, options.render_height, 240)
	testing.expect_value(t, options.render_pixel_scale, f32(2.0))
}

@(test)
test_run_options_use_sdl_window_loop_for_bounded_visible_software_runs :: proc(t: ^testing.T) {
	visible, visible_ok := parse_run_options([]string{"--frames", "2", "--backend", "software"}, false)
	testing.expect_value(t, visible_ok, true)
	testing.expect_value(t, run_options_use_sdl_window_loop(visible), true)

	unbounded, unbounded_ok := parse_run_options([]string{"--backend", "software"}, false)
	testing.expect_value(t, unbounded_ok, true)
	testing.expect_value(t, run_options_use_sdl_window_loop(unbounded), true)

	hidden, hidden_ok := parse_run_options([]string{"--frames", "2", "--hidden", "--backend", "software"}, false)
	testing.expect_value(t, hidden_ok, true)
	testing.expect_value(t, run_options_use_sdl_window_loop(hidden), false)
}

@(test)
test_run_options_use_sdl_window_loop_for_visible_wgpu_runs :: proc(t: ^testing.T) {
	visible, visible_ok := parse_run_options([]string{"--frames", "2", "--backend", "wgpu"}, false)
	testing.expect_value(t, visible_ok, true)
	testing.expect_value(t, run_options_use_sdl_window_loop(visible), true)
	testing.expect_value(t, run_options_use_wgpu_sdl_window_loop(visible), true)

	hidden, hidden_ok := parse_run_options([]string{"--frames", "2", "--hidden", "--backend", "wgpu"}, false)
	testing.expect_value(t, hidden_ok, true)
	testing.expect_value(t, run_options_use_sdl_window_loop(hidden), false)
	testing.expect_value(t, run_options_use_wgpu_sdl_window_loop(hidden), false)

	hidden_editor, hidden_editor_ok := parse_run_options([]string{"--frames", "2", "--hidden", "--editor", "--backend", "wgpu"}, false)
	testing.expect_value(t, hidden_editor_ok, true)
	testing.expect_value(t, hidden_editor.editor, true)
	testing.expect_value(t, run_options_use_sdl_window_loop(hidden_editor), false)
	testing.expect_value(t, run_options_use_wgpu_sdl_window_loop(hidden_editor), false)

	unbounded, unbounded_ok := parse_run_options([]string{"--backend", "wgpu"}, false)
	testing.expect_value(t, unbounded_ok, true)
	testing.expect_value(t, run_options_use_sdl_window_loop(unbounded), true)
	testing.expect_value(t, run_options_use_wgpu_sdl_window_loop(unbounded), true)

	editor, editor_ok := parse_run_options([]string{"--frames", "2", "--editor", "--backend", "wgpu"}, false)
	testing.expect_value(t, editor_ok, true)
	testing.expect_value(t, editor.editor, true)
	testing.expect_value(t, run_options_use_sdl_window_loop(editor), true)
	testing.expect_value(t, run_options_use_wgpu_sdl_window_loop(editor), true)
}

@(test)
test_print_run_reload_events_since_returns_total_seen_events :: proc(t: ^testing.T) {
	report := Live_Project_Run_Report{}
	defer live_project_run_report_free(&report)

	append(&report.reloads, Live_Reload_Event{frame = 0, info = Live_Reload_Info{project_reloaded = true, entity_count = 1, system_count = 1}})
	append(&report.reloads, Live_Reload_Event{frame = 1, info = Live_Reload_Info{scripts_reloaded = true, entity_count = 1, system_count = 1}})

	testing.expect_value(t, print_run_reload_events_since(report, 2), 2)
	testing.expect_value(t, print_run_reload_events_since(report, 99), 2)
}

@(test)
test_run_command_rejects_hidden_without_frame_limit :: proc(t: ^testing.T) {
	exit_code := run_with_output([]string{"scrapbot", "run", "--hidden"}, false)
	testing.expect_value(t, exit_code, 1)
}

@(test)
test_run_command_rejects_hidden_unbounded_wgpu :: proc(t: ^testing.T) {
	exit_code := run_with_output([]string{"scrapbot", "run", "--hidden", "--backend", "wgpu"}, false)
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
test_parse_render_options_accepts_dimensions_backend_editor_and_select :: proc(t: ^testing.T) {
	options, ok := parse_render_options(
		[]string{"--frames", "4", "--width=320", "--height", "240", "--pixel-scale", "2.0", "--backend", "wgpu", "--select", "cube", "--inspector-scroll-y", "24.0", "project", "out.png"},
		DEFAULT_RENDER_OUTPUT,
		false,
	)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, options.frames, 4)
	testing.expect_value(t, options.width, 320)
	testing.expect_value(t, options.height, 240)
	testing.expect_value(t, options.pixel_scale, f32(2.0))
	testing.expect_value(t, options.backend, Render_Backend.WebGPU)
	testing.expect_value(t, options.editor, true)
	testing.expect_value(t, options.selected_entity_id, "cube")
	testing.expect_value(t, options.inspector_scroll_y, f32(24.0))
	testing.expect_value(t, options.target_path, "project")
	testing.expect_value(t, options.output_path, "out.png")
}

@(test)
test_run_render_command_writes_wgpu_backend_png_with_fake_library :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-render-wgpu-backend")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Render WGPU"), Project_Error.None)

	staged_library := stage_fake_wgpu_odin_out_library(t, root)
	defer delete(staged_library)

	output_path := project_relative_path(root, "wgpu-render.png")
	defer delete(output_path)

	exit_code := run_with_output([]string{"scrapbot", "render", "--backend", "wgpu", "--width", "1", "--height", "1", root, output_path}, false)
	testing.expect_value(t, exit_code, 0)

	image, image_err := render_load_rgb_image(output_path)
	defer render_image_free(&image)
	testing.expect_value(t, image_err, Render_Image_Error.None)
	testing.expect_value(t, image.width, 1)
	testing.expect_value(t, image.height, 1)
	expect_render_pixel(t, image, 0, 0, {255, 0, 0})

	metadata_path := render_artifact_metadata_path(output_path)
	defer delete(metadata_path)
	metadata, metadata_err := os.read_entire_file(metadata_path, context.allocator)
	if metadata_err != nil {
		testing.fail_now(t, "failed to read render metadata")
	}
	defer delete(metadata)
	testing.expect_value(t, strings.contains(string(metadata), `"backend": "wgpu"`), true)
}

@(test)
test_run_render_command_writes_wgpu_editor_chrome_with_fake_library :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-render-wgpu-editor")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Render WGPU Editor"), Project_Error.None)
	staged_library := stage_fake_wgpu_odin_out_library(t, root)
	defer delete(staged_library)

	output_path := project_relative_path(root, "wgpu-editor-render.png")
	defer delete(output_path)

	exit_code := run_with_output([]string{"scrapbot", "render", "--backend", "wgpu", "--editor", "--width", "16", "--height", "16", root, output_path}, false)
	testing.expect_value(t, exit_code, 0)
	expect_file_prefix(t, output_path, []u8{0x89, 'P', 'N', 'G'})
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
test_run_render_command_writes_png_artifact :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-render-writes-png")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Render PNG"), Project_Error.None)
	output_path := project_relative_path(root, "render.png")
	defer delete(output_path)

	exit_code := run_with_output([]string{"scrapbot", "render", root, output_path}, false)
	testing.expect_value(t, exit_code, 0)
	expect_file_prefix(t, output_path, []u8{0x89, 'P', 'N', 'G'})
	metadata_path := render_artifact_metadata_path(output_path)
	defer delete(metadata_path)
	expect_file_prefix(t, metadata_path, []u8{'{', '\n'})
}

@(test)
test_run_render_command_writes_editor_chrome_pixels :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-render-editor-chrome")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Render Editor Chrome"), Project_Error.None)
	output_path := project_relative_path(root, "editor-render.png")
	defer delete(output_path)

	exit_code := run_with_output(
		[]string{
			"scrapbot",
			"render",
			"--editor",
			"--select",
			"018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001",
			"--width",
			"320",
			"--height",
			"240",
			root,
			output_path,
		},
		false,
	)
	testing.expect_value(t, exit_code, 0)

	image, image_err := render_load_rgb_image(output_path)
	if image_err != .None {
		testing.fail_now(t, "failed to load rendered editor image")
	}
	defer render_image_free(&image)
	expect_render_pixel(t, image, 4, 4, EDITOR_CHROME_TOP_COLOR)
	expect_render_pixel(t, image, 8, 40, EDITOR_CHROME_PANEL_COLOR)
	expect_render_pixel(t, image, 26, 34, EDITOR_CHROME_BUTTON_COLOR)
	expect_render_pixel(t, image, 32, 40, EDITOR_CHROME_BUTTON_ACCENT_COLOR)
	expect_render_pixel(t, image, 51, 40, EDITOR_CHROME_BUTTON_DESTRUCTIVE_COLOR)
	expect_render_pixel(t, image, 278, 36, EDITOR_CHROME_BUTTON_COLOR)
	expect_render_pixel(t, image, 284, 37, EDITOR_CHROME_BUTTON_ACCENT_COLOR)
	expect_render_pixel(t, image, 303, 39, EDITOR_CHROME_BUTTON_DESTRUCTIVE_COLOR)
	expect_render_pixel(t, image, 236, 38, EDITOR_CHROME_SELECTION_COLOR)
	expect_render_pixel(t, image, 72, 24, EDITOR_CHROME_VIEWPORT_COLOR)
	expect_render_pixel(t, image, 238, 62, EDITOR_CHROME_INSPECTOR_CARD_HEADER_COLOR)
	expect_render_pixel(t, image, 244, 78, EDITOR_CHROME_INSPECTOR_FIELD_COLOR)
}

@(test)
test_run_render_command_applies_editor_inspector_scroll_pixels :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-render-editor-inspector-scroll")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Render Editor Inspector Scroll"), Project_Error.None)
	output_path := project_relative_path(root, "editor-scroll-render.png")
	defer delete(output_path)

	exit_code := run_with_output(
		[]string{
			"scrapbot",
			"render",
			"--editor",
			"--select",
			"018f6f78-4b6f-74a2-9f8f-5d7f3a8d0001",
			"--inspector-scroll-y",
			"24",
			"--width",
			"320",
			"--height",
			"240",
			root,
			output_path,
		},
		false,
	)
	testing.expect_value(t, exit_code, 0)

	image, image_err := render_load_rgb_image(output_path)
	if image_err != .None {
		testing.fail_now(t, "failed to load rendered editor image")
	}
	defer render_image_free(&image)
	expect_render_pixel(t, image, 238, 62, EDITOR_CHROME_INSPECTOR_CARD_COLOR)
	expect_render_pixel(t, image, 244, 62, EDITOR_CHROME_INSPECTOR_FIELD_COLOR)
	expect_render_pixel(t, image, 238, 92, EDITOR_CHROME_INSPECTOR_CARD_HEADER_COLOR)
}

@(test)
test_run_render_command_writes_typed_inspector_control_pixels :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-render-editor-typed-inspector-controls")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "CLI Render Editor Typed Inspector Controls"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local Controls = ecs.component("controls", {
  fields = ecs.fields({
    enabled = "boolean",
    count = "int",
    speed = "float",
    label = "string",
    tint = "vec3",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Typed Inspector Controls"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.controls]
enabled = true
count = 2
speed = 1.5
label = "alpha"
tint = [1.0, 0.5, 0.25]
`)
	output_path := project_relative_path(root, "typed-inspector-render.png")
	defer delete(output_path)

	exit_code := run_with_output(
		[]string{
			"scrapbot",
			"render",
			"--editor",
			"--select",
			"target",
			"--width",
			"320",
			"--height",
			"240",
			root,
			output_path,
		},
		false,
	)
	testing.expect_value(t, exit_code, 0)

	image, image_err := render_load_rgb_image(output_path)
	if image_err != .None {
		testing.fail_now(t, "failed to load rendered editor image")
	}
	defer render_image_free(&image)
	expect_render_pixel(t, image, 284, 78, EDITOR_CHROME_INSPECTOR_BOOL_ON_COLOR)
	expect_render_pixel(t, image, 296, 78, EDITOR_CHROME_INSPECTOR_TOGGLE_KNOB_COLOR)
	expect_render_pixel(t, image, 278, 86, EDITOR_CHROME_INSPECTOR_SCALAR_CONTROL_COLOR)
	expect_render_pixel(t, image, 278, 94, EDITOR_CHROME_INSPECTOR_SCALAR_CONTROL_COLOR)
	expect_render_pixel(t, image, 278, 102, EDITOR_CHROME_INSPECTOR_STRING_CONTROL_COLOR)
	expect_render_pixel(t, image, 274, 110, EDITOR_CHROME_INSPECTOR_VEC3_X_COLOR)
	expect_render_pixel(t, image, 284, 110, EDITOR_CHROME_INSPECTOR_VEC3_Y_COLOR)
	expect_render_pixel(t, image, 294, 110, EDITOR_CHROME_INSPECTOR_VEC3_Z_COLOR)
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
test_run_render_test_command_writes_bmp_artifact :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-render-test-writes-bmp")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Render Test BMP"), Project_Error.None)
	output_path := project_relative_path(root, "render-test.bmp")
	defer delete(output_path)

	exit_code := run_with_output([]string{"scrapbot", "render-test", root, output_path}, false)
	testing.expect_value(t, exit_code, 0)
	expect_file_prefix(t, output_path, []u8{'B', 'M'})
	metadata_path := render_artifact_metadata_path(output_path)
	defer delete(metadata_path)
	expect_file_prefix(t, metadata_path, []u8{'{', '\n'})
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
	actual_path := project_relative_path(root, "actual.png")
	defer delete(actual_path)

	update_exit_code := run_with_output([]string{"scrapbot", "visual-test", "--update", root, expected_path}, false)
	testing.expect_value(t, update_exit_code, 0)
	exit_code := run_with_output([]string{"scrapbot", "visual-test", root, expected_path, actual_path}, false)
	testing.expect_value(t, exit_code, 0)
	expect_file_prefix(t, actual_path, []u8{0x89, 'P', 'N', 'G'})
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
	expect_file_prefix(t, expected_path, []u8{0x89, 'P', 'N', 'G'})
	metadata_path := render_artifact_metadata_path(expected_path)
	defer delete(metadata_path)
	expect_file_prefix(t, metadata_path, []u8{'{', '\n'})
}

@(test)
test_run_visual_test_command_compares_typed_inspector_controls :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-visual-editor-typed-inspector-controls")
	defer os.remove_all(root)
	defer delete(root)
	write_file(t, root, PROJECT_FILE_NAME, `name = "CLI Visual Editor Typed Inspector Controls"
version = 1
default_scene = "scenes/main.scene.toml"
scripts = ["scripts/components.luau"]
`)
	write_file(t, root, "scripts/components.luau", `local Controls = ecs.component("controls", {
  fields = ecs.fields({
    enabled = "boolean",
    count = "int",
    speed = "float",
    label = "string",
    tint = "vec3",
  }),
})
`)
	write_file(t, root, "scenes/main.scene.toml", `name = "Typed Inspector Controls"
version = 1

[[entities]]
id = "target"
name = "Target"

[entities.components.controls]
enabled = true
count = 2
speed = 1.5
label = "alpha"
tint = [1.0, 0.5, 0.25]
`)

	expected_path := project_relative_path(root, "typed-inspector-expected.png")
	defer delete(expected_path)
	actual_path := project_relative_path(root, "typed-inspector-actual.png")
	defer delete(actual_path)

	update_exit_code := run_with_output(
		[]string{
			"scrapbot",
			"visual-test",
			"--update",
			"--editor",
			"--select",
			"target",
			"--width",
			"320",
			"--height",
			"240",
			root,
			expected_path,
		},
		false,
	)
	testing.expect_value(t, update_exit_code, 0)

	exit_code := run_with_output(
		[]string{
			"scrapbot",
			"visual-test",
			"--editor",
			"--select",
			"target",
			"--width",
			"320",
			"--height",
			"240",
			root,
			expected_path,
			actual_path,
		},
		false,
	)
	testing.expect_value(t, exit_code, 0)

	image, image_err := render_load_rgb_image(actual_path)
	if image_err != .None {
		testing.fail_now(t, "failed to load visual-test editor image")
	}
	defer render_image_free(&image)
	expect_render_pixel(t, image, 284, 78, EDITOR_CHROME_INSPECTOR_BOOL_ON_COLOR)
	expect_render_pixel(t, image, 296, 78, EDITOR_CHROME_INSPECTOR_TOGGLE_KNOB_COLOR)
	expect_render_pixel(t, image, 278, 86, EDITOR_CHROME_INSPECTOR_SCALAR_CONTROL_COLOR)
	expect_render_pixel(t, image, 278, 94, EDITOR_CHROME_INSPECTOR_SCALAR_CONTROL_COLOR)
	expect_render_pixel(t, image, 278, 102, EDITOR_CHROME_INSPECTOR_STRING_CONTROL_COLOR)
	expect_render_pixel(t, image, 274, 110, EDITOR_CHROME_INSPECTOR_VEC3_X_COLOR)
	expect_render_pixel(t, image, 284, 110, EDITOR_CHROME_INSPECTOR_VEC3_Y_COLOR)
	expect_render_pixel(t, image, 294, 110, EDITOR_CHROME_INSPECTOR_VEC3_Z_COLOR)
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
	update_exit_code := run_with_output([]string{"scrapbot", "visual-test", "--update", root, expected_path}, false)
	testing.expect_value(t, update_exit_code, 0)
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

	exit_code := run_with_output([]string{"scrapbot", "visual-test", "--update", "--select", "missing", root, expected_path}, false)
	testing.expect_value(t, exit_code, 1)
}

@(test)
test_run_visual_test_command_rejects_mismatched_actual_image :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "cli-visual-mismatch")
	defer os.remove_all(root)
	defer delete(root)
	testing.expect_value(t, init_project(root, "CLI Visual Mismatch"), Project_Error.None)
	expected_path := project_relative_path(root, "expected.png")
	defer delete(expected_path)
	actual_path := project_relative_path(root, "actual.png")
	defer delete(actual_path)

	update_exit_code := run_with_output([]string{"scrapbot", "visual-test", "--update", "--width", "320", root, expected_path}, false)
	testing.expect_value(t, update_exit_code, 0)
	exit_code := run_with_output([]string{"scrapbot", "visual-test", root, expected_path, actual_path}, false)
	testing.expect_value(t, exit_code, 1)
	expect_file_prefix(t, actual_path, []u8{0x89, 'P', 'N', 'G'})
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
	actual_path := project_relative_path(root, "actual.png")
	defer delete(actual_path)
	update_exit_code := run_with_output([]string{"scrapbot", "visual-test", "--update", root, expected_path}, false)
	testing.expect_value(t, update_exit_code, 0)

	default_exit_code := run_with_output([]string{"scrapbot", "visual-test", root, expected_path, actual_path}, false)
	testing.expect_value(t, default_exit_code, 0)
	two_frame_exit_code := run_with_output([]string{"scrapbot", "visual-test", "--frames=2", root, expected_path}, false)
	testing.expect_value(t, two_frame_exit_code, 1)
}

expect_file_prefix :: proc(t: ^testing.T, path: string, prefix: []u8) {
	contents, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		testing.fail_now(t, "failed to read output artifact")
	}
	defer delete(contents)
	if len(contents) < len(prefix) {
		testing.fail_now(t, "output artifact is too short")
	}
	for byte, index in prefix {
		testing.expect_value(t, contents[index], byte)
	}
}

expect_render_pixel :: proc(t: ^testing.T, image: Render_Image, x, y: int, color: [3]u8) {
	if x < 0 || y < 0 || x >= image.width || y >= image.height {
		testing.fail_now(t, "pixel coordinate outside rendered image")
	}
	offset := (y * image.width + x) * 3
	testing.expect_value(t, image.rgb[offset], color[0])
	testing.expect_value(t, image.rgb[offset + 1], color[1])
	testing.expect_value(t, image.rgb[offset + 2], color[2])
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

[[expect.editor]]
selected_entity = "counter"
`)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, summary.frames, 2)
	testing.expect_value(t, summary.input_frames, 1)
	testing.expect_value(t, summary.expectations, 3)
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
