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
