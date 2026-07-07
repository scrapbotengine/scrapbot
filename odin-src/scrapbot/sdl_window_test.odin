package main

import sdl3 "vendor:sdl3"
import "core:testing"

@(test)
test_sdl_window_flags_include_hidden_and_platform_surface_bits :: proc(t: ^testing.T) {
	hidden := sdl_window_flags(true)
	testing.expect_value(t, .HIDDEN in hidden, true)
	testing.expect_value(t, .RESIZABLE in hidden, true)
	testing.expect_value(t, .HIGH_PIXEL_DENSITY in hidden, true)
	when ODIN_OS == .Darwin {
		testing.expect_value(t, .METAL in hidden, true)
	}

	visible := sdl_window_flags(false)
	testing.expect_value(t, .HIDDEN in visible, false)
}

@(test)
test_sdl_run_loop_event_requests_quit_for_process_and_window_close :: proc(t: ^testing.T) {
	quit := sdl3.Event{type = .QUIT}
	testing.expect_value(t, sdl_run_loop_event_requests_quit(quit), true)

	close := sdl3.Event{type = .WINDOW_CLOSE_REQUESTED}
	testing.expect_value(t, sdl_run_loop_event_requests_quit(close), true)

	resize := sdl3.Event{type = .WINDOW_RESIZED}
	testing.expect_value(t, sdl_run_loop_event_requests_quit(resize), false)
}

@(test)
test_sdl_run_loop_frame_limit_only_stops_bounded_runs :: proc(t: ^testing.T) {
	testing.expect_value(t, sdl_run_loop_frame_limit_reached(0, 0), false)
	testing.expect_value(t, sdl_run_loop_frame_limit_reached(100, 0), false)
	testing.expect_value(t, sdl_run_loop_frame_limit_reached(1, 2), false)
	testing.expect_value(t, sdl_run_loop_frame_limit_reached(2, 2), true)
}

@(test)
test_sdl_run_loop_delta_seconds_is_measured_and_clamped :: proc(t: ^testing.T) {
	testing.expect_value(t, sdl_run_loop_delta_seconds(1_000, 1_000), SDL_RUN_LOOP_FIXED_DELTA_SECONDS)
	testing.expect_value(t, sdl_run_loop_delta_seconds(0, sdl3.NS_PER_MS * 16), f32(0.016))
	testing.expect_value(t, sdl_run_loop_delta_seconds(0, sdl3.NS_PER_SECOND), SDL_RUN_LOOP_MAX_DELTA_SECONDS)
}

@(test)
test_sdl_input_scales_pointer_to_high_density_pixels :: proc(t: ^testing.T) {
	size := Sdl_Window_Size{width = 1280, height = 720, pixel_width = 2560, pixel_height = 1440}
	state := Sdl_Input_State{}
	input := sdl_input_begin_frame(state, size, true)

	sdl_input_apply_mouse_motion(&state, &input, size, 20, 30, 20, 30)

	testing.expect_value(t, input.debug_overlay_visible, true)
	testing.expect_value(t, input.viewport_width, f32(2560))
	testing.expect_value(t, input.viewport_height, f32(1440))
	testing.expect_value(t, input.pointer.has_position, true)
	testing.expect_value(t, input.pointer.position, [2]f32{40, 60})
	testing.expect_value(t, input.pointer.delta, [2]f32{40, 60})

	sdl_input_apply_mouse_motion(&state, &input, size, 100, 120, 5, -2)
	testing.expect_value(t, input.pointer.position, [2]f32{200, 240})
	testing.expect_value(t, input.pointer.delta, [2]f32{50, 56})
}

@(test)
test_sdl_input_maps_mouse_buttons_and_wheel :: proc(t: ^testing.T) {
	size := Sdl_Window_Size{width = 100, height = 100, pixel_width = 100, pixel_height = 100}
	state := Sdl_Input_State{}
	input := sdl_input_begin_frame(state, size, false)

	sdl_input_apply_mouse_button(&state, &input, size, sdl3.BUTTON_LEFT, true, 10, 20)
	testing.expect_value(t, state.primary_down, true)
	testing.expect_value(t, input.pointer.primary_pressed, true)
	testing.expect_value(t, input.pointer.primary_down, true)

	input = sdl_input_begin_frame(state, size, false)
	sdl_input_apply_mouse_button(&state, &input, size, sdl3.BUTTON_LEFT, false, 10, 20)
	testing.expect_value(t, state.primary_down, false)
	testing.expect_value(t, input.pointer.primary_released, true)
	testing.expect_value(t, input.pointer.primary_down, false)

	sdl_input_apply_mouse_wheel(&state, &input, size, 0, 2, 10, 20, .FLIPPED)
	testing.expect_value(t, input.pointer.wheel_delta, [2]f32{0, -2})
}

@(test)
test_sdl_input_maps_keyboard_state_and_editor_shortcuts :: proc(t: ^testing.T) {
	state := Sdl_Input_State{}
	input := frame_input_default()

	sdl_input_apply_key(&state, &input, .LCTRL, true, false)
	sdl_input_apply_key(&state, &input, .A, true, false)
	testing.expect_value(t, state.ctrl_down, true)
	testing.expect_value(t, state.move_left, true)
	testing.expect_value(t, input.keyboard.ctrl_down, true)
	testing.expect_value(t, input.keyboard.move_left, true)
	testing.expect_value(t, input.keyboard.editor_select_all_pressed, true)

	input = sdl_input_begin_frame(state, Sdl_Window_Size{width = 100, height = 100, pixel_width = 100, pixel_height = 100}, false)
	sdl_input_apply_key(&state, &input, .BACKSPACE, true, false)
	testing.expect_value(t, input.keyboard.editor_backspace_pressed, true)

	input = sdl_input_begin_frame(state, Sdl_Window_Size{width = 100, height = 100, pixel_width = 100, pixel_height = 100}, false)
	sdl_input_apply_key(&state, &input, .LSHIFT, true, false)
	sdl_input_apply_key(&state, &input, .LEFT, true, true)
	testing.expect_value(t, input.keyboard.shift_down, true)
	testing.expect_value(t, input.keyboard.editor_left_pressed, true)
	sdl_input_apply_key(&state, &input, .RIGHT, true, true)
	testing.expect_value(t, input.keyboard.editor_right_pressed, true)
	sdl_input_apply_key(&state, &input, .HOME, true, false)
	testing.expect_value(t, input.keyboard.editor_home_pressed, true)
	sdl_input_apply_key(&state, &input, .END, true, false)
	testing.expect_value(t, input.keyboard.editor_end_pressed, true)

	sdl_input_apply_key(&state, &input, .LSHIFT, false, false)
	input = sdl_input_begin_frame(state, Sdl_Window_Size{width = 100, height = 100, pixel_width = 100, pixel_height = 100}, false)
	sdl_input_apply_key(&state, &input, .Z, true, false)
	testing.expect_value(t, input.keyboard.editor_undo_pressed, true)

	input = sdl_input_begin_frame(state, Sdl_Window_Size{width = 100, height = 100, pixel_width = 100, pixel_height = 100}, false)
	sdl_input_apply_key(&state, &input, .LSHIFT, true, false)
	sdl_input_apply_key(&state, &input, .Z, true, false)
	testing.expect_value(t, input.keyboard.editor_redo_pressed, true)

	input = sdl_input_begin_frame(state, Sdl_Window_Size{width = 100, height = 100, pixel_width = 100, pixel_height = 100}, false)
	sdl_input_apply_key(&state, &input, .LSHIFT, false, false)
	sdl_input_apply_key(&state, &input, .C, true, false)
	testing.expect_value(t, input.keyboard.editor_copy_pressed, true)

	input = sdl_input_begin_frame(state, Sdl_Window_Size{width = 100, height = 100, pixel_width = 100, pixel_height = 100}, false)
	sdl_input_apply_key(&state, &input, .V, true, false)
	testing.expect_value(t, input.keyboard.editor_paste_pressed, true)

	input = sdl_input_begin_frame(state, Sdl_Window_Size{width = 100, height = 100, pixel_width = 100, pixel_height = 100}, false)
	sdl_input_apply_key(&state, &input, .N, true, false)
	testing.expect_value(t, input.keyboard.editor_spawn_pressed, true)

	input = sdl_input_begin_frame(state, Sdl_Window_Size{width = 100, height = 100, pixel_width = 100, pixel_height = 100}, false)
	sdl_input_apply_key(&state, &input, .INSERT, true, false)
	testing.expect_value(t, input.keyboard.editor_spawn_pressed, true)

	input = sdl_input_begin_frame(state, Sdl_Window_Size{width = 100, height = 100, pixel_width = 100, pixel_height = 100}, false)
	sdl_input_apply_key(&state, &input, .DELETE, true, false)
	testing.expect_value(t, input.keyboard.editor_despawn_pressed, true)
	testing.expect_value(t, input.keyboard.editor_delete_pressed, true)

	input = sdl_input_begin_frame(state, Sdl_Window_Size{width = 100, height = 100, pixel_width = 100, pixel_height = 100}, false)
	sdl_input_apply_key(&state, &input, .Y, true, false)
	testing.expect_value(t, input.keyboard.editor_redo_pressed, true)

	input = sdl_input_begin_frame(state, Sdl_Window_Size{width = 100, height = 100, pixel_width = 100, pixel_height = 100}, false)
	sdl_input_apply_key(&state, &input, .TAB, true, false)
	testing.expect_value(t, input.keyboard.editor_toggle_pressed, true)

	input = sdl_input_begin_frame(state, Sdl_Window_Size{width = 100, height = 100, pixel_width = 100, pixel_height = 100}, false)
	sdl_input_apply_key(&state, &input, .SPACE, true, false)
	testing.expect_value(t, state.move_up, true)
	testing.expect_value(t, input.keyboard.move_up, true)
	sdl_input_apply_key(&state, &input, .E, true, false)
	sdl_input_apply_key(&state, &input, .SPACE, false, false)
	testing.expect_value(t, state.move_up, true)
	sdl_input_apply_key(&state, &input, .E, false, false)
	testing.expect_value(t, state.move_up, false)
}

@(test)
test_sdl_input_accumulates_text_input_for_current_frame :: proc(t: ^testing.T) {
	state := Sdl_Input_State{}
	input := frame_input_default()

	first := [?]u8{'4', '2', 0}
	second := [?]u8{'.', '5', 0}
	sdl_input_apply_text_input(&state, &input, cstring(raw_data(first[:])))
	sdl_input_apply_text_input(&state, &input, cstring(raw_data(second[:])))

	testing.expect_value(t, input.text_input, "42.5")

	sdl_input_clear_text_input(&state, &input)
	testing.expect_value(t, input.text_input, "")
	testing.expect_value(t, state.text_input_len, 0)
}

@(test)
test_sdl_run_loop_editor_toggle_updates_frame_visibility :: proc(t: ^testing.T) {
	editor_visible := false
	input := frame_input_default()
	input.debug_overlay_visible = false
	input.keyboard.editor_toggle_pressed = true

	sdl_run_loop_apply_editor_toggle(&editor_visible, &input)
	testing.expect_value(t, editor_visible, true)
	testing.expect_value(t, input.debug_overlay_visible, true)

	input.keyboard.editor_toggle_pressed = false
	input.debug_overlay_visible = false
	sdl_run_loop_apply_editor_toggle(&editor_visible, &input)
	testing.expect_value(t, editor_visible, true)
	testing.expect_value(t, input.debug_overlay_visible, true)

	input.keyboard.editor_toggle_pressed = true
	sdl_run_loop_apply_editor_toggle(&editor_visible, &input)
	testing.expect_value(t, editor_visible, false)
	testing.expect_value(t, input.debug_overlay_visible, false)
}

@(test)
test_sdl_fly_camera_capture_respects_editor_game_viewport :: proc(t: ^testing.T) {
	input := frame_input_default()
	input.viewport_width = 1280
	input.viewport_height = 720
	input.pointer.secondary_down = true
	input.pointer.has_position = true
	input.pointer.position = {640, 360}

	testing.expect_value(t, sdl_fly_camera_can_capture(input, false), true)
	testing.expect_value(t, sdl_fly_camera_can_capture(input, true), true)

	input.pointer.position = {8, 8}
	testing.expect_value(t, sdl_fly_camera_can_capture(input, true), false)

	input.pointer.secondary_down = false
	testing.expect_value(t, sdl_fly_camera_can_capture(input, false), false)
}

@(test)
test_sdl_fly_camera_initializes_from_scene_and_does_not_mutate_world_camera :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	camera_entity, entity_err := runtime_world_create_entity(&world, "camera", "Camera")
	testing.expect_value(t, entity_err, Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component(&world, camera_entity, TRANSFORM_COMPONENT_ID, []Runtime_Component_Field_Value{
		{name = "position", value = runtime_component_value_vec3([3]f32{1, 2, 3})},
		{name = "rotation", value = runtime_component_value_vec3([3]f32{0, 0, 0})},
		{name = "scale", value = runtime_component_value_vec3([3]f32{1, 1, 1})},
	}), Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component(&world, camera_entity, CAMERA_COMPONENT_ID, []Runtime_Component_Field_Value{
		{name = "fov_y_degrees", value = runtime_component_value_float(60)},
		{name = "near", value = runtime_component_value_float(0.1)},
		{name = "far", value = runtime_component_value_float(200)},
	}), Runtime_Error.None)

	input := frame_input_default()
	input.viewport_width = 1280
	input.viewport_height = 720
	input.pointer.secondary_down = true
	input.keyboard.move_forward = true

	fly_camera := Sdl_Fly_Camera_State{}
	sdl_fly_camera_update(&fly_camera, world, input, false, 0.5)

	testing.expect_value(t, fly_camera.initialized, true)
	testing.expect_value(t, fly_camera.active, true)
	testing.expect_value(t, fly_camera.position, [3]f32{1, 2, 0.5})
	testing.expect_value(t, fly_camera.rotation, [3]f32{0, 0, 0})

	scene_position, scene_position_err := runtime_world_get_vec3(world, camera_entity, TRANSFORM_COMPONENT_ID, "position")
	testing.expect_value(t, scene_position_err, Runtime_Error.None)
	testing.expect_value(t, scene_position, [3]f32{1, 2, 3})
}

@(test)
test_sdl_fly_camera_uses_pointer_delta_and_modifier_descent :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	input := frame_input_default()
	input.pointer.secondary_down = true
	input.pointer.delta = {10, -20}
	input.keyboard.ctrl_down = true

	fly_camera := Sdl_Fly_Camera_State{}
	sdl_fly_camera_update(&fly_camera, world, input, false, 1.0)

	testing.expect_value(t, fly_camera.active, true)
	testing.expect_value(t, fly_camera.rotation[0], f32(0.060000002))
	testing.expect_value(t, fly_camera.rotation[1], f32(0.030000001))
	testing.expect_value(t, fly_camera.position[1], f32(-5))
}

@(test)
test_sdl_fly_camera_resets_after_scene_stamp_changes :: proc(t: ^testing.T) {
	fly_camera := Sdl_Fly_Camera_State{
		initialized = true,
		active = true,
		position = {1, 2, 3},
	}
	before := Source_File_Stamp{size = 10, modification_time_ns = 100}
	same := Source_File_Stamp{size = 10, modification_time_ns = 100}
	changed := Source_File_Stamp{size = 11, modification_time_ns = 100}

	sdl_fly_camera_reset_after_scene_reload(&fly_camera, before, same)
	testing.expect_value(t, fly_camera.initialized, true)
	testing.expect_value(t, fly_camera.active, true)

	sdl_fly_camera_reset_after_scene_reload(&fly_camera, before, changed)
	testing.expect_value(t, fly_camera.initialized, false)
	testing.expect_value(t, fly_camera.active, false)
	testing.expect_value(t, fly_camera.position, [3]f32{1, 2, 3})
}

@(test)
test_sdl_wgpu_surface_descriptor_bundles_own_source_storage :: proc(t: ^testing.T) {
	label := wgpu_string_view_from_string("test")

	metal := Sdl_WGPU_Surface_Descriptor{}
	testing.expect_value(t, sdl_wgpu_surface_descriptor_init_metal_layer(&metal, label, rawptr(uintptr(0xAA01)), sdl3.MetalView(nil)), Sdl_Window_Error.None)
	testing.expect_value(t, metal.kind, Sdl_Surface_Source_Kind.Metal_Layer)
	testing.expect_value(t, metal.descriptor.next_in_chain, &metal.metal_source.chain)
	testing.expect_value(t, metal.metal_source.layer, rawptr(uintptr(0xAA01)))

	wayland := Sdl_WGPU_Surface_Descriptor{}
	testing.expect_value(t, sdl_wgpu_surface_descriptor_init_wayland(&wayland, label, rawptr(uintptr(0xAA02)), rawptr(uintptr(0xAA03))), Sdl_Window_Error.None)
	testing.expect_value(t, wayland.kind, Sdl_Surface_Source_Kind.Wayland_Surface)
	testing.expect_value(t, wayland.descriptor.next_in_chain, &wayland.wayland_source.chain)
	testing.expect_value(t, wayland.wayland_source.display, rawptr(uintptr(0xAA02)))
	testing.expect_value(t, wayland.wayland_source.surface, rawptr(uintptr(0xAA03)))

	xlib := Sdl_WGPU_Surface_Descriptor{}
	testing.expect_value(t, sdl_wgpu_surface_descriptor_init_xlib(&xlib, label, rawptr(uintptr(0xAA04)), 0x55AA), Sdl_Window_Error.None)
	testing.expect_value(t, xlib.kind, Sdl_Surface_Source_Kind.Xlib_Window)
	testing.expect_value(t, xlib.descriptor.next_in_chain, &xlib.xlib_source.chain)
	testing.expect_value(t, xlib.xlib_source.window, u64(0x55AA))

	windows := Sdl_WGPU_Surface_Descriptor{}
	testing.expect_value(t, sdl_wgpu_surface_descriptor_init_windows(&windows, label, rawptr(uintptr(0xAA05)), rawptr(uintptr(0xAA06))), Sdl_Window_Error.None)
	testing.expect_value(t, windows.kind, Sdl_Surface_Source_Kind.Windows_HWND)
	testing.expect_value(t, windows.descriptor.next_in_chain, &windows.windows_source.chain)
	testing.expect_value(t, windows.windows_source.hinstance, rawptr(uintptr(0xAA05)))
	testing.expect_value(t, windows.windows_source.hwnd, rawptr(uintptr(0xAA06)))
}

@(test)
test_sdl_wgpu_surface_descriptor_rejects_missing_handles :: proc(t: ^testing.T) {
	label := wgpu_string_view_empty()
	bundle := Sdl_WGPU_Surface_Descriptor{}
	testing.expect_value(t, sdl_wgpu_surface_descriptor_init_metal_layer(&bundle, label, nil, sdl3.MetalView(nil)), Sdl_Window_Error.Metal_Layer_Missing)
	testing.expect_value(t, sdl_wgpu_surface_descriptor_init_wayland(&bundle, label, nil, rawptr(uintptr(0x1))), Sdl_Window_Error.Native_Handle_Missing)
	testing.expect_value(t, sdl_wgpu_surface_descriptor_init_xlib(&bundle, label, rawptr(uintptr(0x1)), 0), Sdl_Window_Error.Native_Handle_Missing)
	testing.expect_value(t, sdl_wgpu_surface_descriptor_init_windows(&bundle, label, rawptr(uintptr(0x1)), nil), Sdl_Window_Error.Native_Handle_Missing)
}

@(test)
test_sdl_surface_kind_labels_are_stable_for_cli_output :: proc(t: ^testing.T) {
	testing.expect_value(t, sdl_surface_source_kind_label(.Metal_Layer), "metal-layer")
	testing.expect_value(t, sdl_surface_source_kind_label(.Wayland_Surface), "wayland-surface")
	testing.expect_value(t, sdl_surface_source_kind_label(.Xlib_Window), "xlib-window")
	testing.expect_value(t, sdl_surface_source_kind_label(.Windows_HWND), "windows-hwnd")
}

_ :: sdl3.Window
