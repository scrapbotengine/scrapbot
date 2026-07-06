package main

import "core:c"
import "core:testing"

@(test)
test_wgpu_abi_structs_have_c_pointer_alignment :: proc(t: ^testing.T) {
	testing.expect_value(t, align_of(WGPU_String_View), align_of(rawptr))
	testing.expect_value(t, size_of(WGPU_String_View), size_of(rawptr) + size_of(c.size_t))
	testing.expect_value(t, align_of(WGPU_Chained_Struct), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Chained_Struct_Out), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Buffer_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Texture_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Texture_View_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Texel_Copy_Texture_Info), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Texel_Copy_Buffer_Info), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Command_Encoder_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Command_Buffer_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Buffer_Map_Callback_Info), align_of(rawptr))
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
test_wgpu_texture_descriptor_matches_offscreen_target_defaults :: proc(t: ^testing.T) {
	label := wgpu_string_view_from_raw(rawptr(uintptr(0x1234)), 6)
	descriptor := wgpu_texture_descriptor_2d(label, 640, 480, WGPU_DEFAULT_TARGET_FORMAT, wgpu_offscreen_texture_usage())
	testing.expect_value(t, descriptor.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, descriptor.label, label)
	testing.expect_value(t, descriptor.usage, WGPU_TEXTURE_USAGE_RENDER_ATTACHMENT | WGPU_TEXTURE_USAGE_COPY_SRC)
	testing.expect_value(t, descriptor.dimension, WGPU_TEXTURE_DIMENSION_2D)
	testing.expect_value(t, descriptor.size, WGPU_Extent_3D{width = 640, height = 480, depth_or_array_layers = 1})
	testing.expect_value(t, descriptor.format, WGPU_TEXTURE_FORMAT_BGRA8_UNORM_SRGB)
	testing.expect_value(t, descriptor.mip_level_count, u32(1))
	testing.expect_value(t, descriptor.sample_count, u32(1))
	testing.expect_value(t, descriptor.view_format_count, c.size_t(0))
	testing.expect_value(t, descriptor.view_formats, rawptr(nil))
}

@(test)
test_wgpu_texture_view_descriptor_matches_single_mip_render_view :: proc(t: ^testing.T) {
	descriptor := wgpu_single_mip_texture_view_descriptor(wgpu_string_view_empty())
	testing.expect_value(t, descriptor.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, descriptor.label, wgpu_string_view_empty())
	testing.expect_value(t, descriptor.format, WGPU_TEXTURE_FORMAT_UNDEFINED)
	testing.expect_value(t, descriptor.dimension, WGPU_TEXTURE_VIEW_DIMENSION_UNDEFINED)
	testing.expect_value(t, descriptor.base_mip_level, u32(0))
	testing.expect_value(t, descriptor.mip_level_count, u32(1))
	testing.expect_value(t, descriptor.base_array_layer, u32(0))
	testing.expect_value(t, descriptor.array_layer_count, u32(1))
	testing.expect_value(t, descriptor.aspect, WGPU_TEXTURE_ASPECT_ALL)
	testing.expect_value(t, descriptor.usage, WGPU_TEXTURE_USAGE_NONE)
}

@(test)
test_wgpu_buffer_descriptor_matches_offscreen_staging_defaults :: proc(t: ^testing.T) {
	descriptor := wgpu_buffer_descriptor(wgpu_string_view_empty(), wgpu_staging_buffer_usage(), 4096)
	testing.expect_value(t, descriptor.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, descriptor.label, wgpu_string_view_empty())
	testing.expect_value(t, descriptor.usage, WGPU_BUFFER_USAGE_MAP_READ | WGPU_BUFFER_USAGE_COPY_DST)
	testing.expect_value(t, descriptor.size, u64(4096))
	testing.expect_value(t, descriptor.mapped_at_creation, WGPU_FALSE)
}

@(test)
test_wgpu_copy_texture_to_buffer_structs_match_offscreen_readback_defaults :: proc(t: ^testing.T) {
	texture := WGPU_Texture(rawptr(uintptr(0x4444)))
	buffer := WGPU_Buffer(rawptr(uintptr(0x5555)))

	source := wgpu_texel_copy_texture_info(texture)
	testing.expect_value(t, source.texture, texture)
	testing.expect_value(t, source.mip_level, u32(0))
	testing.expect_value(t, source.origin, WGPU_Origin_3D{})
	testing.expect_value(t, source.aspect, WGPU_TEXTURE_ASPECT_ALL)

	destination := wgpu_texel_copy_buffer_info(buffer, 2560, 480)
	testing.expect_value(t, destination.buffer, buffer)
	testing.expect_value(t, destination.layout.offset, u64(0))
	testing.expect_value(t, destination.layout.bytes_per_row, u32(2560))
	testing.expect_value(t, destination.layout.rows_per_image, u32(480))
}

@(test)
test_wgpu_command_descriptors_hold_labels_and_no_chains :: proc(t: ^testing.T) {
	label := wgpu_string_view_from_raw(rawptr(uintptr(0x9876)), 13)
	encoder := wgpu_command_encoder_descriptor(label)
	command_buffer := wgpu_command_buffer_descriptor(label)

	testing.expect_value(t, encoder.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, encoder.label, label)
	testing.expect_value(t, command_buffer.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, command_buffer.label, label)
}

@(test)
test_wgpu_buffer_map_callback_info_uses_process_events_mode :: proc(t: ^testing.T) {
	userdata1 := rawptr(uintptr(0x1111))
	userdata2 := rawptr(uintptr(0x2222))
	info := wgpu_buffer_map_callback_info(wgpu_test_buffer_map_callback, userdata1, userdata2)
	testing.expect_value(t, info.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, info.mode, WGPU_CALLBACK_MODE_ALLOW_PROCESS_EVENTS)
	testing.expect_value(t, info.callback, WGPU_Buffer_Map_Callback(wgpu_test_buffer_map_callback))
	testing.expect_value(t, info.userdata1, userdata1)
	testing.expect_value(t, info.userdata2, userdata2)
}

wgpu_test_buffer_map_callback :: proc "c" (status: WGPU_Map_Async_Status, message: WGPU_String_View, userdata1, userdata2: rawptr) {
	_ = status
	_ = message
	_ = userdata1
	_ = userdata2
}

@(test)
test_wgpu_platform_surface_stype_values_match_vendored_binding :: proc(t: ^testing.T) {
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_METAL_LAYER, WGPU_SType(0x00000004))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_WINDOWS_HWND, WGPU_SType(0x00000005))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_XLIB_WINDOW, WGPU_SType(0x00000006))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_WAYLAND_SURFACE, WGPU_SType(0x00000007))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_XCB_WINDOW, WGPU_SType(0x00000009))
}
