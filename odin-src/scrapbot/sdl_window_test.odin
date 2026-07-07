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
