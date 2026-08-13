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

	orbit := scene_camera_orbit_input({-3, 7}, 2, true)
	testing.expect(t, orbit.orbit_active)
	testing.expect(t, orbit.orbit_started)
	testing.expect(t, !orbit.look_active)
	testing.expect_value(t, orbit.look_delta, shared.Vec2{-3, 7})
	testing.expect_value(t, orbit.dolly, f32(2))
	testing.expect_value(t, orbit.movement, shared.Vec3{})
}

@(test)
test_scene_camera_capture_starts_at_zero_and_uses_absolute_pointer_motion :: proc(t: ^testing.T) {
	previous: shared.Vec2
	valid := false
	testing.expect(t, scene_camera_pointer_delta({400, 240}, &previous, &valid) == shared.Vec2{})
	testing.expect(t, valid)
	testing.expect_value(t, previous, shared.Vec2{400, 240})
	testing.expect_value(
		t,
		scene_camera_pointer_delta({407, 236}, &previous, &valid),
		shared.Vec2{7, -4},
	)
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
test_runtime_text_keys_preserve_text_navigation_and_repeats :: proc(t: ^testing.T) {
	input: shared.Text_Input
	runtime_text_key(&input, .TAB)
	testing.expect(t, input.tab)
	runtime_text_key(&input, .LEFT)
	testing.expect(t, input.left)
	runtime_text_key(&input, .UP)
	testing.expect(t, input.up)
	runtime_text_key(&input, .DOWN)
	testing.expect(t, input.down)
	runtime_text_key(&input, .BACKSPACE)
	testing.expect(t, input.backspace)
	runtime_text_key(&input, .DELETE)
	testing.expect(t, input.delete_forward)
	repeated: shared.Text_Input
	runtime_text_key(&repeated, .LEFT, true)
	testing.expect(t, repeated.left)
	runtime_text_key(&input, .ESCAPE)
	testing.expect(t, input.escape)
	repeated = {}
	runtime_text_key(&repeated, .RETURN, true)
	runtime_text_key(&repeated, .TAB, true)
	runtime_text_key(&repeated, .ESCAPE, true)
	testing.expect(t, !repeated.enter && !repeated.tab && !repeated.escape)
}
