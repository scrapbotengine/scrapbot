package platform

import shared "../shared"
import "core:testing"
import sdl "vendor:sdl3"

@(test)
test_runtime_pointer_cursor_maps_ui_intents_to_sdl :: proc(t: ^testing.T) {
	testing.expect(t, runtime_pointer_system_cursor(.Default) == .DEFAULT)
	testing.expect(t, runtime_pointer_system_cursor(.Pointer) == .POINTER)
	testing.expect(t, runtime_pointer_system_cursor(.Text_Edit) == .TEXT)
	testing.expect(t, runtime_pointer_system_cursor(.Horizontal_Resize) == .EW_RESIZE)
	testing.expect(t, runtime_pointer_system_cursor(.Vertical_Resize) == .NS_RESIZE)
	testing.expect(t, runtime_pointer_system_cursor(.Move) == .MOVE)
	testing.expect(t, runtime_pointer_system_cursor(.Not_Allowed) == .NOT_ALLOWED)
}

@(test)
test_runtime_input_scancodes_map_to_backend_neutral_keys :: proc(t: ^testing.T) {
	key, ok := input_key_from_scancode(.W)
	testing.expect(t, ok && key == .W)
	key, ok = input_key_from_scancode(._7)
	testing.expect(t, ok && key == .Digit_7)
	key, ok = input_key_from_scancode(.LCTRL)
	testing.expect(t, ok && key == .Left_Control)
	_, ok = input_key_from_scancode(.UNKNOWN)
	testing.expect(t, !ok)
}

@(test)
test_runtime_window_size_preserves_requested_aspect_and_fits_usable_display :: proc(
	t: ^testing.T,
) {
	width, height := runtime_window_size_for_usable_bounds(1600, 900, 1920, 1080)
	testing.expect(t, width == 1600 && height == 900)

	width, height = runtime_window_size_for_usable_bounds(1600, 900, 1440, 900)
	testing.expect(t, width == 1296 && height == 729)
	testing.expect(t, width * 900 == height * 1600)

	width, height = runtime_window_size_for_usable_bounds(800, 600, 1440, 900)
	testing.expect(t, width == 800 && height == 600)
}

@(test)
test_editor_transform_pointer_wraps_at_window_edges :: proc(t: ^testing.T) {
	target, wrapped := runtime_editor_pointer_wrap_target({640, 360}, 1280, 720, 8)
	testing.expect(t, !wrapped && target == shared.Vec2{640, 360})

	target, wrapped = runtime_editor_pointer_wrap_target({1273, 360}, 1280, 720, 8)
	testing.expect(t, wrapped && target == shared.Vec2{9, 360})

	target, wrapped = runtime_editor_pointer_wrap_target({4, 715}, 1280, 720, 8)
	testing.expect(t, wrapped && target == shared.Vec2{1271, 9})

	target, wrapped = runtime_editor_pointer_wrap_target({1, 1}, 16, 16, 8)
	testing.expect(t, !wrapped && target == shared.Vec2{1, 1})
}

@(test)
test_editor_shortcuts_decode_to_centralized_semantic_actions :: proc(t: ^testing.T) {
	action, ok := editor_shortcut_action(.E, sdl.Keymod{.LCTRL}, false)
	testing.expect(t, ok && action == .Toggle_Editor)
	action, ok = editor_shortcut_action(.B, sdl.Keymod{.RGUI}, false)
	testing.expect(t, ok && action == .Toggle_Left_Sidebar)
	action, ok = editor_shortcut_action(.B, sdl.Keymod{.LCTRL, .RALT}, false)
	testing.expect(t, ok && action == .Toggle_Right_Sidebar)
	action, ok = editor_shortcut_action(.D, sdl.Keymod{.LGUI}, false)
	testing.expect(t, ok && action == .Duplicate_Entity)
	action, ok = editor_shortcut_action(.BACKSPACE, {}, false)
	testing.expect(t, ok && action == .Delete_Entity)
	action, ok = editor_shortcut_action(.DELETE, {}, false)
	testing.expect(t, ok && action == .Delete_Entity)
	action, ok = editor_shortcut_action(.F, {}, false)
	testing.expect(t, ok && action == .Focus_Selected)
	_, ok = editor_shortcut_action(.D, {}, false)
	testing.expect(t, !ok)
	_, ok = editor_shortcut_action(.DELETE, sdl.Keymod{.LGUI}, false)
	testing.expect(t, !ok)
	_, ok = editor_shortcut_action(.D, sdl.Keymod{.LGUI}, true)
	testing.expect(t, !ok)
}

@(test)
test_editor_gizmo_mode_shortcuts_leave_blender_transform_keys_to_chords :: proc(t: ^testing.T) {
	mode, ok := editor_gizmo_mode_shortcut(
		.W,
		{},
		false,
	); testing.expect(t, ok && mode == .Translate)
	mode, ok = editor_gizmo_mode_shortcut(.E, {}, false); testing.expect(t, ok && mode == .Rotate)
	_, ok = editor_gizmo_mode_shortcut(.R, {}, false); testing.expect(t, !ok)
	_, ok = editor_gizmo_mode_shortcut(.R, {}, true); testing.expect(t, !ok)
	_, ok = editor_gizmo_mode_shortcut(.R, sdl.Keymod{.LGUI}, false); testing.expect(t, !ok)
	_, ok = editor_gizmo_mode_shortcut(.E, sdl.Keymod{.LCTRL}, false); testing.expect(t, !ok)
	_, ok = editor_gizmo_mode_shortcut(.A, {}, false); testing.expect(t, !ok)
}

@(test)
test_runtime_text_input_decodes_blender_transform_chords :: proc(t: ^testing.T) {
	input: Runtime_Text_Input
	runtime_text_key(&input, .G, {}, false)
	runtime_text_key(&input, .X, sdl.Keymod{.LSHIFT}, false)
	testing.expect(t, input.transform_translate)
	testing.expect(t, input.transform_axis_x)
	testing.expect(t, input.shift)

	repeated: Runtime_Text_Input
	runtime_text_key(&repeated, .R, {}, true)
	testing.expect(t, !repeated.transform_rotate)
}

@(test)
test_scene_camera_input_maps_navigation_only_while_looking :: proc(t: ^testing.T) {
	keys := Scene_Camera_Key_State {
		forward = true,
		left = true,
		up = true,
		fast = true,
	}
	inactive := scene_camera_input_from_state(keys, {4, -2}, false, 1.5)
	testing.expect(t, !inactive.look_active)
	testing.expect(t, inactive.movement == shared.Vec3{})
	testing.expect_value(t, inactive.dolly, f32(1.5))

	active := scene_camera_input_from_state(keys, {4, -2}, true)
	testing.expect(t, active.look_active)
	testing.expect(t, active.movement == shared.Vec3{-1, 1, 1})
	testing.expect(t, active.look_delta == shared.Vec2{4, -2})
	testing.expect(t, active.move_fast)

	orbit := scene_camera_orbit_input({-3, 7}, 2)
	testing.expect(t, orbit.orbit_active)
	testing.expect(t, !orbit.look_active)
	testing.expect_value(t, orbit.look_delta, shared.Vec2{-3, 7})
	testing.expect_value(t, orbit.dolly, f32(2))
	testing.expect_value(t, orbit.movement, shared.Vec3{})
}

@(test)
test_scene_camera_capture_discards_relative_mode_warmup_deltas :: proc(t: ^testing.T) {
	warmup_samples := SCENE_CAMERA_CAPTURE_WARMUP_SAMPLES
	activation_warp := shared.Vec2{380, -240}
	followup_warp := shared.Vec2{-380, 240}
	user_delta := shared.Vec2{4, -2}

	testing.expect(
		t,
		scene_camera_capture_delta(activation_warp, &warmup_samples) == shared.Vec2{},
	)
	testing.expect(t, scene_camera_capture_delta(followup_warp, &warmup_samples) == shared.Vec2{})
	testing.expect(t, warmup_samples == 0)
	testing.expect(t, scene_camera_capture_delta(user_delta, &warmup_samples) == user_delta)
}

@(test)
test_live_resize_redraw_only_matches_live_exposes_for_runtime_window :: proc(t: ^testing.T) {
	window_id := sdl.WindowID(42)
	event := sdl.Event{}
	event.type = .WINDOW_EXPOSED
	event.window.windowID = window_id
	event.window.data1 = 1
	testing.expect(t, runtime_event_requests_live_resize_redraw(&event, window_id))

	event.window.data1 = 0
	testing.expect(t, !runtime_event_requests_live_resize_redraw(&event, window_id))
	event.window.data1 = 1
	testing.expect(t, !runtime_event_requests_live_resize_redraw(&event, sdl.WindowID(7)))
	event.type = .WINDOW_RESIZED
	testing.expect(t, !runtime_event_requests_live_resize_redraw(&event, window_id))
	testing.expect(t, !runtime_event_requests_live_resize_redraw(nil, window_id))
}

@(test)
test_runtime_text_keys_preserve_navigation_modifiers_and_shortcuts :: proc(t: ^testing.T) {
	input: Runtime_Text_Input
	runtime_text_key(&input, .TAB, sdl.Keymod{.LSHIFT})
	testing.expect(t, input.tab && input.shift)
	runtime_text_key(&input, .LEFT, sdl.Keymod{.LSHIFT})
	testing.expect(t, input.left && input.shift)
	runtime_text_key(&input, .UP, sdl.Keymod{})
	testing.expect(t, input.up)
	runtime_text_key(&input, .DOWN, sdl.Keymod{.LCTRL})
	testing.expect(t, input.down && input.fine)
	runtime_text_key(&input, .A, sdl.Keymod{.LGUI})
	testing.expect(t, input.select_all)
	runtime_text_key(&input, .S, sdl.Keymod{.LGUI})
	testing.expect(t, input.save)
	runtime_text_key(&input, .Z, sdl.Keymod{.LGUI})
	testing.expect(t, input.undo)
	runtime_text_key(&input, .Z, sdl.Keymod{.LGUI, .LSHIFT})
	testing.expect(t, input.redo)
	runtime_text_key(&input, .E, sdl.Keymod{.LGUI})
	testing.expect(t, input.editor_toggle)
	runtime_text_key(&input, .B, sdl.Keymod{.LGUI})
	testing.expect(t, input.toggle_left_sidebar && !input.toggle_right_sidebar)
	runtime_text_key(&input, .B, sdl.Keymod{.LCTRL, .LALT})
	testing.expect(t, input.toggle_right_sidebar)
	runtime_text_key(&input, .R, sdl.Keymod{.LCTRL})
	testing.expect(t, input.run_stop)
	runtime_text_key(&input, .T, sdl.Keymod{.RGUI})
	testing.expect(t, input.pause_step)
	runtime_text_key(&input, .D, sdl.Keymod{.LGUI})
	testing.expect(t, input.duplicate_entity)
	runtime_text_key(&input, .F, sdl.Keymod{})
	testing.expect(t, input.focus_selected)
	runtime_text_key(&input, .BACKSPACE, sdl.Keymod{})
	testing.expect(t, input.backspace && input.delete_entity)
	runtime_text_key(&input, .DELETE, sdl.Keymod{})
	testing.expect(t, input.delete_forward && input.delete_entity)
	repeated: Runtime_Text_Input
	runtime_text_key(&repeated, .E, sdl.Keymod{.LGUI}, true)
	runtime_text_key(&repeated, .R, sdl.Keymod{.LGUI}, true)
	runtime_text_key(&repeated, .T, sdl.Keymod{.LGUI}, true)
	runtime_text_key(&repeated, .B, sdl.Keymod{.LGUI}, true)
	runtime_text_key(&repeated, .D, sdl.Keymod{.LGUI}, true)
	runtime_text_key(&repeated, .F, sdl.Keymod{}, true)
	runtime_text_key(&repeated, .DELETE, sdl.Keymod{}, true)
	testing.expect(
		t,
		!repeated.editor_toggle &&
		!repeated.run_stop &&
		!repeated.pause_step &&
		!repeated.toggle_left_sidebar &&
		!repeated.toggle_right_sidebar &&
		!repeated.duplicate_entity &&
		!repeated.delete_entity &&
		!repeated.focus_selected,
	)
	runtime_text_key(&input, .ESCAPE, sdl.Keymod{.LCTRL})
	testing.expect(t, !input.escape)
	runtime_text_key(&input, .ESCAPE, {})
	testing.expect(t, input.escape)
}
