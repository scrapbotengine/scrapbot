package main

import "core:c"
import "core:testing"

@(test)
test_wgpu_abi_structs_have_c_pointer_alignment :: proc(t: ^testing.T) {
	testing.expect_value(t, align_of(WGPU_String_View), align_of(rawptr))
	testing.expect_value(t, size_of(WGPU_String_View), size_of(rawptr) + size_of(c.size_t))
	testing.expect_value(t, align_of(WGPU_Chained_Struct), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Chained_Struct_Out), align_of(rawptr))
}

@(test)
test_wgpu_string_view_null_matches_c_abi_sentinel :: proc(t: ^testing.T) {
	view := wgpu_string_view_null()
	testing.expect_value(t, view.data, rawptr(nil))
	testing.expect_value(t, view.length, WGPU_STRLEN)
}

@(test)
test_wgpu_string_view_can_hold_explicit_pointer_and_length :: proc(t: ^testing.T) {
	bytes := [?]u8{'w', 'g', 'p', 'u'}
	view := wgpu_string_view_from_raw(rawptr(&bytes[0]), c.size_t(len(bytes)))
	testing.expect_value(t, view.data, rawptr(&bytes[0]))
	testing.expect_value(t, view.length, c.size_t(4))
}

@(test)
test_wgpu_renderer_formats_match_vendored_binding_values :: proc(t: ^testing.T) {
	testing.expect_value(t, WGPU_DEFAULT_TARGET_FORMAT, WGPU_Texture_Format(0x18))
	testing.expect_value(t, WGPU_DEPTH_FORMAT, WGPU_Texture_Format(0x28))
	testing.expect_value(t, WGPU_SHADOW_DEPTH_FORMAT, WGPU_Texture_Format(0x2A))
}

@(test)
test_wgpu_renderer_usage_helpers_match_zig_render_paths :: proc(t: ^testing.T) {
	testing.expect_value(t, wgpu_offscreen_texture_usage(), WGPU_TEXTURE_USAGE_RENDER_ATTACHMENT | WGPU_TEXTURE_USAGE_COPY_SRC)
	testing.expect_value(t, wgpu_staging_buffer_usage(), WGPU_BUFFER_USAGE_MAP_READ | WGPU_BUFFER_USAGE_COPY_DST)
}

@(test)
test_wgpu_platform_surface_stype_values_match_vendored_binding :: proc(t: ^testing.T) {
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_METAL_LAYER, WGPU_SType(0x00000004))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_WINDOWS_HWND, WGPU_SType(0x00000005))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_XLIB_WINDOW, WGPU_SType(0x00000006))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_WAYLAND_SURFACE, WGPU_SType(0x00000007))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_XCB_WINDOW, WGPU_SType(0x00000009))
}
