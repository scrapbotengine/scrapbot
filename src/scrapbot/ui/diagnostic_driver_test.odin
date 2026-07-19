package ui

import ecs "../ecs"
import shared "../shared"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

DIAGNOSTIC_DRIVER_TEST_SCRIPT :: `{
  "schema_version": 1,
  "timeout_frames": 8,
  "actions": [
    {"action": "click", "target": {"text": "OPEN"}},
    {"action": "hover", "target": {"text": "CHOICE"}},
    {"action": "expect", "target": {"text": "CHOICE"}, "expect": "hovered"},
		{"action": "drag", "target": {"name": "Driver Number"}, "delta_x": 1.5, "frames": 4},
		{"action": "drag", "target": {"text": "OPEN"}, "destination": {"text": "CHOICE"}, "destination_anchor": "top", "frames": 2},
    {"action": "expect", "target": {"name": "Driver Number"}, "expect": "text", "text": "2"},
    {"action": "capture", "target": {"text": "CHOICE"}, "padding": 4}
  ]
}`

@(test)
test_diagnostic_driver_replays_semantic_actions_and_dumps_the_ui_tree :: proc(t: ^testing.T) {
	directory, directory_err := os.make_directory_temp(
		"",
		"scrapbot-ui-driver-*",
		context.temp_allocator,
	)
	testing.expect(t, directory_err == nil)
	if directory_err != nil {
		return
	}
	defer os.remove_all(directory)
	script_path, script_path_err := filepath.join({directory, "actions.json"})
	dump_path, dump_path_err := filepath.join({directory, "tree.json"})
	testing.expect(t, script_path_err == nil && dump_path_err == nil)
	if script_path_err != nil || dump_path_err != nil {
		return
	}
	defer delete(script_path)
	defer delete(dump_path)
	testing.expect(t, os.write_entire_file(script_path, DIAGNOSTIC_DRIVER_TEST_SCRIPT) == nil)

	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Driver Root"),
			name = "Driver Root",
			has_ui_layout = true,
			ui_layout = {size = {240, 100}, padding = {10, 10, 10, 10}},
			has_ui_vstack = true,
			ui_vstack = {gap = 4},
		},
		shared.Scene_Entity {
			id = ui_test_id("Driver Open"),
			name = "Driver Open",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Driver Root"), size = {220, 32}},
			has_ui_button = true,
			ui_button = {
				text = "OPEN",
				color = {1, 1, 1, 1},
				size = 16,
				hover_background = {0.2, 0.3, 0.4, 1},
			},
		},
		shared.Scene_Entity {
			id = ui_test_id("Driver Choice"),
			name = "Driver Choice",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Driver Root"), size = {220, 32}},
			has_ui_button = true,
			ui_button = {
				text = "CHOICE",
				color = {1, 1, 1, 1},
				size = 16,
				hover_background = {0.2, 0.3, 0.4, 1},
			},
		},
		shared.Scene_Entity {
			id = ui_test_id("Driver Number"),
			name = "Driver Number",
			has_ui_layout = true,
			ui_layout = {position = {260, 10}, size = {120, 32}},
			has_ui_input = true,
			ui_input = {text = "1", number = 1, step = 0.5, numeric = true},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 240, 100) == "")

	driver: Diagnostic_Driver
	testing.expect(t, diagnostic_driver_load(&driver, script_path) == "")
	defer diagnostic_driver_destroy(&driver)
	open_activated := false
	for _ in 0 ..< 20 {
		pointer, keyboard, driver_err := diagnostic_driver_input(&driver, state, &world, 240, 100)
		testing.expectf(t, driver_err == "", "driver failed: %s", driver_err)
		if driver_err != "" {
			return
		}
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, pointer, 240, 100, 1.0 / 60, keyboard) == "",
		)
		open_entity := world.entities[1]
		open_state := world.ui_states[open_entity.ui_state_index]
		open_activated = open_activated || open_state.activation_revision > 0
		if diagnostic_driver_is_complete(&driver) {
			break
		}
	}
	testing.expect(t, diagnostic_driver_is_complete(&driver))
	testing.expect(t, open_activated)
	testing.expect(t, world.ui_inputs[world.entities[3].ui_input_index].number == 2)
	choice_node := find_node(state, world.entities[2].id)
	testing.expect(t, choice_node >= 0 && state.nodes[choice_node].hovered)
	capture_rect, capture_found := diagnostic_driver_capture_rect(&driver, state, &world, 240, 100)
	testing.expect(t, capture_found)
	if capture_found && choice_node >= 0 {
		choice_screen_rect := diagnostic_node_screen_rect(
			state,
			state.nodes[choice_node],
			240,
			100,
		)
		testing.expect(t, capture_rect.x == choice_screen_rect.x - 4)
		testing.expect(t, capture_rect.width == choice_screen_rect.width + 8)
	}
	testing.expect(t, diagnostic_driver_write_dump(dump_path, state, &world, 240, 100) == "")
	dump, dump_err := os.read_entire_file(dump_path, context.temp_allocator)
	testing.expect(t, dump_err == nil)
	if dump_err == nil {
		dump_text := string(dump)
		testing.expect(t, strings.contains(dump_text, `"name":"Driver Choice"`))
		testing.expect(t, strings.contains(dump_text, `"hovered":true`))
		testing.expect(t, strings.contains(dump_text, `"screen_rect"`))
	}
}

@(test)
test_diagnostic_driver_rejects_an_unknown_schema :: proc(t: ^testing.T) {
	directory, directory_err := os.make_directory_temp(
		"",
		"scrapbot-ui-driver-schema-*",
		context.temp_allocator,
	)
	testing.expect(t, directory_err == nil)
	if directory_err != nil {
		return
	}
	defer os.remove_all(directory)
	script_path, path_err := filepath.join({directory, "actions.json"})
	testing.expect(t, path_err == nil)
	if path_err != nil {
		return
	}
	defer delete(script_path)
	testing.expect(
		t,
		os.write_entire_file(
			script_path,
			`{"schema_version":2,"actions":[{"action":"wait","frames":1}]}`,
		) ==
		nil,
	)
	driver: Diagnostic_Driver
	err := diagnostic_driver_load(&driver, script_path)
	testing.expect(t, strings.contains(err, "schema_version"))
	diagnostic_driver_destroy(&driver)
}

@(test)
test_diagnostic_driver_waits_for_retained_tree_after_world_replacement :: proc(t: ^testing.T) {
	directory, directory_err := os.make_directory_temp(
		"",
		"scrapbot-ui-driver-world-*",
		context.temp_allocator,
	)
	testing.expect(t, directory_err == nil)
	if directory_err != nil { return }
	defer os.remove_all(directory)
	script_path, path_err := filepath.join({directory, "actions.json"})
	testing.expect(t, path_err == nil)
	if path_err != nil { return }
	defer delete(script_path)
	testing.expect(
		t,
		os.write_entire_file(
			script_path,
			`{"schema_version":1,"actions":[{"action":"expect","target":{"name":"Replacement Status"},"expect":"text","text":"READY"}]}`,
		) ==
		nil,
	)

	old_scene := shared.Scene{}
	defer delete(old_scene.entities)
	append(
		&old_scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Old Status"),
			name = "Old Status",
			has_ui_layout = true,
			ui_layout = {size = {100, 30}},
			has_ui_text = true,
			ui_text = {text = "OLD", color = {1, 1, 1, 1}, size = 16},
		},
	)
	world := ecs.build_world(&old_scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")

	driver: Diagnostic_Driver
	testing.expect(t, diagnostic_driver_load(&driver, script_path) == "")
	defer diagnostic_driver_destroy(&driver)

	new_scene := shared.Scene{}
	defer delete(new_scene.entities)
	append(
		&new_scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Replacement Status"),
			name = "Replacement Status",
			has_ui_layout = true,
			ui_layout = {size = {100, 30}},
			has_ui_text = true,
			ui_text = {text = "READY", color = {1, 1, 1, 1}, size = 16},
		},
	)
	replacement := ecs.build_world(&new_scene)
	ecs.destroy_world(&world)
	world = replacement

	_, _, driver_err := diagnostic_driver_input(&driver, state, &world, 1280, 720)
	testing.expect(t, driver_err == "")
	testing.expect(t, driver.action_index == 0)
	testing.expect(t, !diagnostic_driver_is_complete(&driver))
}

@(test)
test_diagnostic_driver_reveals_targets_inside_scroll_areas :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Driver Scroll"),
			name = "Driver Scroll",
			has_ui_layout = true,
			ui_layout = {size = {200, 60}},
			has_ui_scroll_area = true,
			ui_scroll_area = shared.ui_scroll_area_default(),
		},
		shared.Scene_Entity {
			id = ui_test_id("Driver Scroll Content"),
			name = "Driver Scroll Content",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Driver Scroll"), size = {200, 180}},
		},
		shared.Scene_Entity {
			id = ui_test_id("Driver Offscreen Target"),
			name = "Driver Offscreen Target",
			has_ui_layout = true,
			ui_layout = {
				parent = ui_test_id("Driver Scroll Content"),
				position = {0, 140},
				size = {180, 30},
			},
			has_ui_button = true,
			ui_button = {text = "OFFSCREEN", color = {1, 1, 1, 1}, size = 16},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	target_node := find_node(state, world.entities[2].id)
	scroll_node := find_node(state, world.entities[0].id)
	testing.expect(t, target_node >= 0 && scroll_node >= 0)
	if target_node < 0 || scroll_node < 0 {
		return
	}
	before := diagnostic_node_visible_rect(state.nodes[target_node])
	testing.expect(t, before.height == 0)
	testing.expect(t, diagnostic_reveal_target(state, &world, target_node))
	testing.expect(t, state.nodes[scroll_node].scroll_offset > 0)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	after := diagnostic_node_visible_rect(state.nodes[target_node])
	testing.expect(t, after.height > 0)
}
