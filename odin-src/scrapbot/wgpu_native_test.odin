package main

import "core:c"
import "core:dynlib"
import "core:os"
import "core:path/filepath"
import "core:testing"

@(test)
test_wgpu_abi_structs_have_c_pointer_alignment :: proc(t: ^testing.T) {
	testing.expect_value(t, align_of(WGPU_String_View), align_of(rawptr))
	testing.expect_value(t, size_of(WGPU_String_View), size_of(rawptr) + size_of(c.size_t))
	testing.expect_value(t, align_of(WGPU_Chained_Struct), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Chained_Struct_Out), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Surface_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Surface_Source_Android_Native_Window), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Surface_Source_Metal_Layer), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Surface_Source_Wayland_Surface), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Surface_Source_Windows_HWND), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Surface_Source_XCB_Window), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Surface_Source_Xlib_Window), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Surface_Configuration_Extras), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Surface_Configuration), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Surface_Capabilities), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Surface_Texture), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Buffer_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Texture_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Texture_View_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Texel_Copy_Texture_Info), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Texel_Copy_Buffer_Info), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Command_Encoder_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Command_Buffer_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Color_Attachment), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Depth_Stencil_Attachment), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Render_Pass_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Buffer_Binding_Layout), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Sampler_Binding_Layout), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Texture_Binding_Layout), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Storage_Texture_Binding_Layout), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Bind_Group_Layout_Entry), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Bind_Group_Layout_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Bind_Group_Entry), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Bind_Group_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Sampler_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Pipeline_Layout_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Shader_Source_WGSL), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Shader_Module_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Constant_Entry), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Vertex_Buffer_Layout), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Vertex_State), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Primitive_State), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Depth_Stencil_State), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Multisample_State), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Color_Target_State), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Fragment_State), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Render_Pipeline_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Instance_Capabilities), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Instance_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Request_Adapter_Options), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Queue_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Device_Lost_Callback_Info), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Uncaptured_Error_Callback_Info), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Device_Descriptor), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Request_Adapter_Callback_Info), align_of(rawptr))
	testing.expect_value(t, align_of(WGPU_Request_Device_Callback_Info), align_of(rawptr))
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
test_wgpu_surface_descriptors_point_at_platform_sources :: proc(t: ^testing.T) {
	label := wgpu_string_view_from_raw(rawptr(uintptr(0x1111)), 9)

	android := wgpu_surface_source_android_native_window(rawptr(uintptr(0xA001)))
	android_descriptor := wgpu_surface_descriptor_from_android_native_window(label, &android)
	testing.expect_value(t, android.chain.next, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, android.chain.s_type, WGPU_STYPE_SURFACE_SOURCE_ANDROID_NATIVE_WINDOW)
	testing.expect_value(t, android.window, rawptr(uintptr(0xA001)))
	testing.expect_value(t, android_descriptor.next_in_chain, &android.chain)
	testing.expect_value(t, android_descriptor.label, label)

	metal := wgpu_surface_source_metal_layer(rawptr(uintptr(0xA002)))
	metal_descriptor := wgpu_surface_descriptor_from_metal_layer(label, &metal)
	testing.expect_value(t, metal.chain.s_type, WGPU_STYPE_SURFACE_SOURCE_METAL_LAYER)
	testing.expect_value(t, metal.layer, rawptr(uintptr(0xA002)))
	testing.expect_value(t, metal_descriptor.next_in_chain, &metal.chain)

	wayland := wgpu_surface_source_wayland_surface(rawptr(uintptr(0xA003)), rawptr(uintptr(0xA004)))
	wayland_descriptor := wgpu_surface_descriptor_from_wayland_surface(label, &wayland)
	testing.expect_value(t, wayland.chain.s_type, WGPU_STYPE_SURFACE_SOURCE_WAYLAND_SURFACE)
	testing.expect_value(t, wayland.display, rawptr(uintptr(0xA003)))
	testing.expect_value(t, wayland.surface, rawptr(uintptr(0xA004)))
	testing.expect_value(t, wayland_descriptor.next_in_chain, &wayland.chain)

	windows := wgpu_surface_source_windows_hwnd(rawptr(uintptr(0xA005)), rawptr(uintptr(0xA006)))
	windows_descriptor := wgpu_surface_descriptor_from_windows_hwnd(label, &windows)
	testing.expect_value(t, windows.chain.s_type, WGPU_STYPE_SURFACE_SOURCE_WINDOWS_HWND)
	testing.expect_value(t, windows.hinstance, rawptr(uintptr(0xA005)))
	testing.expect_value(t, windows.hwnd, rawptr(uintptr(0xA006)))
	testing.expect_value(t, windows_descriptor.next_in_chain, &windows.chain)

	xcb := wgpu_surface_source_xcb_window(rawptr(uintptr(0xA007)), 0x55AA)
	xcb_descriptor := wgpu_surface_descriptor_from_xcb_window(label, &xcb)
	testing.expect_value(t, xcb.chain.s_type, WGPU_STYPE_SURFACE_SOURCE_XCB_WINDOW)
	testing.expect_value(t, xcb.connection, rawptr(uintptr(0xA007)))
	testing.expect_value(t, xcb.window, u32(0x55AA))
	testing.expect_value(t, xcb_descriptor.next_in_chain, &xcb.chain)

	xlib := wgpu_surface_source_xlib_window(rawptr(uintptr(0xA008)), 0x123456789ABC)
	xlib_descriptor := wgpu_surface_descriptor_from_xlib_window(label, &xlib)
	testing.expect_value(t, xlib.chain.s_type, WGPU_STYPE_SURFACE_SOURCE_XLIB_WINDOW)
	testing.expect_value(t, xlib.display, rawptr(uintptr(0xA008)))
	testing.expect_value(t, xlib.window, u64(0x123456789ABC))
	testing.expect_value(t, xlib_descriptor.next_in_chain, &xlib.chain)
}

@(test)
test_wgpu_surface_configuration_matches_window_defaults :: proc(t: ^testing.T) {
	device := WGPU_Device(rawptr(uintptr(0xBEEF)))
	config := wgpu_surface_configuration(device, WGPU_DEFAULT_TARGET_FORMAT, 640, 480)
	testing.expect_value(t, config.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, config.device, device)
	testing.expect_value(t, config.format, WGPU_TEXTURE_FORMAT_BGRA8_UNORM_SRGB)
	testing.expect_value(t, config.usage, WGPU_TEXTURE_USAGE_RENDER_ATTACHMENT)
	testing.expect_value(t, config.width, u32(640))
	testing.expect_value(t, config.height, u32(480))
	testing.expect_value(t, config.view_format_count, c.size_t(0))
	testing.expect_value(t, config.view_formats, ([^]WGPU_Texture_Format)(nil))
	testing.expect_value(t, config.alpha_mode, WGPU_COMPOSITE_ALPHA_MODE_AUTO)
	testing.expect_value(t, config.present_mode, WGPU_PRESENT_MODE_FIFO)

	texture := wgpu_surface_texture_error()
	testing.expect_value(t, texture.next_in_chain, (^WGPU_Chained_Struct_Out)(nil))
	testing.expect_value(t, texture.texture, WGPU_Texture(nil))
	testing.expect_value(t, texture.status, WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_ERROR)
}

@(test)
test_wgpu_surface_modes_and_texture_statuses_match_vendored_binding :: proc(t: ^testing.T) {
	testing.expect_value(t, WGPU_COMPOSITE_ALPHA_MODE_AUTO, WGPU_Composite_Alpha_Mode(0))
	testing.expect_value(t, WGPU_COMPOSITE_ALPHA_MODE_OPAQUE, WGPU_Composite_Alpha_Mode(1))
	testing.expect_value(t, WGPU_COMPOSITE_ALPHA_MODE_PREMULTIPLIED, WGPU_Composite_Alpha_Mode(2))
	testing.expect_value(t, WGPU_COMPOSITE_ALPHA_MODE_UNPREMULTIPLIED, WGPU_Composite_Alpha_Mode(3))
	testing.expect_value(t, WGPU_COMPOSITE_ALPHA_MODE_INHERIT, WGPU_Composite_Alpha_Mode(4))
	testing.expect_value(t, WGPU_PRESENT_MODE_UNDEFINED, WGPU_Present_Mode(0))
	testing.expect_value(t, WGPU_PRESENT_MODE_FIFO, WGPU_Present_Mode(1))
	testing.expect_value(t, WGPU_PRESENT_MODE_FIFO_RELAXED, WGPU_Present_Mode(2))
	testing.expect_value(t, WGPU_PRESENT_MODE_IMMEDIATE, WGPU_Present_Mode(3))
	testing.expect_value(t, WGPU_PRESENT_MODE_MAILBOX, WGPU_Present_Mode(4))
	testing.expect_value(t, WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_OPTIMAL, WGPU_Surface_Get_Current_Texture_Status(1))
	testing.expect_value(t, WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_SUBOPTIMAL, WGPU_Surface_Get_Current_Texture_Status(2))
	testing.expect_value(t, WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_TIMEOUT, WGPU_Surface_Get_Current_Texture_Status(3))
	testing.expect_value(t, WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_OUTDATED, WGPU_Surface_Get_Current_Texture_Status(4))
	testing.expect_value(t, WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_LOST, WGPU_Surface_Get_Current_Texture_Status(5))
	testing.expect_value(t, WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_OUT_OF_MEMORY, WGPU_Surface_Get_Current_Texture_Status(6))
	testing.expect_value(t, WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_DEVICE_LOST, WGPU_Surface_Get_Current_Texture_Status(7))
	testing.expect_value(t, WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_ERROR, WGPU_Surface_Get_Current_Texture_Status(8))
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

	upload_layout := wgpu_texel_copy_buffer_layout(128, 32, 16)
	testing.expect_value(t, upload_layout.offset, u64(16))
	testing.expect_value(t, upload_layout.bytes_per_row, u32(128))
	testing.expect_value(t, upload_layout.rows_per_image, u32(32))
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
test_wgpu_render_pass_descriptor_matches_mesh_draw_defaults :: proc(t: ^testing.T) {
	target_view := WGPU_Texture_View(rawptr(uintptr(0x4444)))
	depth_view := WGPU_Texture_View(rawptr(uintptr(0x5555)))
	clear := wgpu_color(0.0006, 0.0018, 0.0086, 1.0)
	color_attachments := [?]WGPU_Color_Attachment{wgpu_color_attachment_clear(target_view, clear)}
	depth := wgpu_depth_stencil_attachment_clear(depth_view)
	descriptor := wgpu_render_pass_descriptor(wgpu_string_view_empty(), &color_attachments[0], 1, &depth)

	testing.expect_value(t, color_attachments[0].next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, color_attachments[0].view, target_view)
	testing.expect_value(t, color_attachments[0].depth_slice, WGPU_DEPTH_SLICE_UNDEFINED)
	testing.expect_value(t, color_attachments[0].resolve_target, WGPU_Texture_View(nil))
	testing.expect_value(t, color_attachments[0].load_op, WGPU_LOAD_OP_CLEAR)
	testing.expect_value(t, color_attachments[0].store_op, WGPU_STORE_OP_STORE)
	testing.expect_value(t, color_attachments[0].clear_value, clear)

	testing.expect_value(t, depth.view, depth_view)
	testing.expect_value(t, depth.depth_load_op, WGPU_LOAD_OP_CLEAR)
	testing.expect_value(t, depth.depth_store_op, WGPU_STORE_OP_STORE)
	testing.expect_value(t, depth.depth_clear_value, f32(1.0))
	testing.expect_value(t, depth.depth_read_only, WGPU_FALSE)
	testing.expect_value(t, depth.stencil_load_op, WGPU_LOAD_OP_UNDEFINED)
	testing.expect_value(t, depth.stencil_store_op, WGPU_STORE_OP_UNDEFINED)

	testing.expect_value(t, descriptor.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, descriptor.label, wgpu_string_view_empty())
	testing.expect_value(t, descriptor.color_attachment_count, c.size_t(1))
	testing.expect_value(t, descriptor.color_attachments, &color_attachments[0])
	testing.expect_value(t, descriptor.depth_stencil_attachment, &depth)
	testing.expect_value(t, descriptor.occlusion_query_set, WGPU_Query_Set(nil))
	testing.expect_value(t, descriptor.timestamp_writes, rawptr(nil))
}

@(test)
test_wgpu_render_pass_load_attachment_matches_ui_pass_defaults :: proc(t: ^testing.T) {
	target_view := WGPU_Texture_View(rawptr(uintptr(0x6666)))
	attachment := wgpu_color_attachment_load(target_view)

	testing.expect_value(t, attachment.view, target_view)
	testing.expect_value(t, attachment.depth_slice, WGPU_DEPTH_SLICE_UNDEFINED)
	testing.expect_value(t, attachment.load_op, WGPU_LOAD_OP_LOAD)
	testing.expect_value(t, attachment.store_op, WGPU_STORE_OP_STORE)
	testing.expect_value(t, attachment.clear_value, WGPU_Color{})
}

@(test)
test_wgpu_bind_group_layout_descriptor_matches_mesh_frame_layout :: proc(t: ^testing.T) {
	label := wgpu_string_view_from_raw(rawptr(uintptr(0xCAFE)), 11)
	entries := [?]WGPU_Bind_Group_Layout_Entry{
		wgpu_bind_group_layout_entry_buffer(0, WGPU_SHADER_STAGE_VERTEX | WGPU_SHADER_STAGE_FRAGMENT, 256),
		wgpu_bind_group_layout_entry_texture(1, WGPU_SHADER_STAGE_FRAGMENT, WGPU_TEXTURE_SAMPLE_TYPE_DEPTH),
		wgpu_bind_group_layout_entry_sampler(2, WGPU_SHADER_STAGE_FRAGMENT, WGPU_SAMPLER_BINDING_TYPE_COMPARISON),
	}
	descriptor := wgpu_bind_group_layout_descriptor(label, &entries[0], len(entries))

	testing.expect_value(t, descriptor.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, descriptor.label, label)
	testing.expect_value(t, descriptor.entry_count, c.size_t(3))
	testing.expect_value(t, descriptor.entries, &entries[0])

	testing.expect_value(t, entries[0].binding, u32(0))
	testing.expect_value(t, entries[0].visibility, WGPU_SHADER_STAGE_VERTEX | WGPU_SHADER_STAGE_FRAGMENT)
	testing.expect_value(t, entries[0].buffer.type_, WGPU_BUFFER_BINDING_TYPE_UNIFORM)
	testing.expect_value(t, entries[0].buffer.min_binding_size, u64(256))
	testing.expect_value(t, entries[0].sampler.type_, WGPU_SAMPLER_BINDING_TYPE_BINDING_NOT_USED)
	testing.expect_value(t, entries[0].texture.sample_type, WGPU_TEXTURE_SAMPLE_TYPE_BINDING_NOT_USED)

	testing.expect_value(t, entries[1].binding, u32(1))
	testing.expect_value(t, entries[1].visibility, WGPU_SHADER_STAGE_FRAGMENT)
	testing.expect_value(t, entries[1].buffer.type_, WGPU_BUFFER_BINDING_TYPE_BINDING_NOT_USED)
	testing.expect_value(t, entries[1].texture.sample_type, WGPU_TEXTURE_SAMPLE_TYPE_DEPTH)
	testing.expect_value(t, entries[1].texture.view_dimension, WGPU_TEXTURE_VIEW_DIMENSION_2D)
	testing.expect_value(t, entries[1].texture.multisampled, WGPU_FALSE)

	testing.expect_value(t, entries[2].binding, u32(2))
	testing.expect_value(t, entries[2].sampler.type_, WGPU_SAMPLER_BINDING_TYPE_COMPARISON)
}

@(test)
test_wgpu_bind_group_descriptor_matches_frame_resources :: proc(t: ^testing.T) {
	label := wgpu_string_view_from_raw(rawptr(uintptr(0xCAFE)), 12)
	layout := WGPU_Bind_Group_Layout(rawptr(uintptr(0x1111)))
	buffer := WGPU_Buffer(rawptr(uintptr(0x2222)))
	texture_view := WGPU_Texture_View(rawptr(uintptr(0x3333)))
	sampler := WGPU_Sampler(rawptr(uintptr(0x4444)))
	entries := [?]WGPU_Bind_Group_Entry{
		wgpu_bind_group_entry_buffer(0, buffer, 256),
		wgpu_bind_group_entry_texture(1, texture_view),
		wgpu_bind_group_entry_sampler(2, sampler),
	}
	descriptor := wgpu_bind_group_descriptor(label, layout, &entries[0], len(entries))

	testing.expect_value(t, descriptor.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, descriptor.label, label)
	testing.expect_value(t, descriptor.layout, layout)
	testing.expect_value(t, descriptor.entry_count, c.size_t(3))
	testing.expect_value(t, descriptor.entries, &entries[0])

	testing.expect_value(t, entries[0].binding, u32(0))
	testing.expect_value(t, entries[0].buffer, buffer)
	testing.expect_value(t, entries[0].offset, u64(0))
	testing.expect_value(t, entries[0].size, u64(256))
	testing.expect_value(t, entries[0].sampler, WGPU_Sampler(nil))
	testing.expect_value(t, entries[0].texture_view, WGPU_Texture_View(nil))

	testing.expect_value(t, entries[1].binding, u32(1))
	testing.expect_value(t, entries[1].buffer, WGPU_Buffer(nil))
	testing.expect_value(t, entries[1].size, WGPU_WHOLE_SIZE)
	testing.expect_value(t, entries[1].texture_view, texture_view)

	testing.expect_value(t, entries[2].binding, u32(2))
	testing.expect_value(t, entries[2].sampler, sampler)
}

@(test)
test_wgpu_sampler_and_pipeline_layout_descriptors_match_renderer_defaults :: proc(t: ^testing.T) {
	label := wgpu_string_view_from_raw(rawptr(uintptr(0xCAFE)), 7)
	comparison := wgpu_sampler_descriptor_linear(label, WGPU_COMPARE_FUNCTION_LESS_EQUAL)
	testing.expect_value(t, comparison.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, comparison.label, label)
	testing.expect_value(t, comparison.address_mode_u, WGPU_ADDRESS_MODE_CLAMP_TO_EDGE)
	testing.expect_value(t, comparison.mag_filter, WGPU_FILTER_MODE_LINEAR)
	testing.expect_value(t, comparison.min_filter, WGPU_FILTER_MODE_LINEAR)
	testing.expect_value(t, comparison.mipmap_filter, WGPU_MIPMAP_FILTER_MODE_NEAREST)
	testing.expect_value(t, comparison.compare, WGPU_COMPARE_FUNCTION_LESS_EQUAL)
	testing.expect_value(t, comparison.max_anisotropy, u16(1))

	plain := wgpu_sampler_descriptor_default(wgpu_string_view_empty())
	testing.expect_value(t, plain.mag_filter, WGPU_FILTER_MODE_NEAREST)
	testing.expect_value(t, plain.compare, WGPU_COMPARE_FUNCTION_UNDEFINED)

	layouts := [?]WGPU_Bind_Group_Layout{WGPU_Bind_Group_Layout(rawptr(uintptr(0x5555)))}
	pipeline_layout := wgpu_pipeline_layout_descriptor(label, &layouts[0], len(layouts))
	testing.expect_value(t, pipeline_layout.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, pipeline_layout.label, label)
	testing.expect_value(t, pipeline_layout.bind_group_layout_count, c.size_t(1))
	testing.expect_value(t, pipeline_layout.bind_group_layouts, &layouts[0])
}

@(test)
test_wgpu_shader_module_descriptor_points_at_wgsl_source :: proc(t: ^testing.T) {
	label := wgpu_string_view_from_raw(rawptr(uintptr(0xCAFE)), 6)
	code := wgpu_string_view_from_raw(rawptr(uintptr(0xBEEF)), 19)
	source := wgpu_shader_source_wgsl(code)
	descriptor := wgpu_shader_module_descriptor_wgsl(label, &source)

	testing.expect_value(t, source.chain.next, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, source.chain.s_type, WGPU_STYPE_SHADER_SOURCE_WGSL)
	testing.expect_value(t, source.code, code)
	testing.expect_value(t, descriptor.next_in_chain, &source.chain)
	testing.expect_value(t, descriptor.label, label)
}

@(test)
test_wgpu_blend_state_matches_ui_alpha_defaults :: proc(t: ^testing.T) {
	replace := wgpu_blend_component_replace()
	testing.expect_value(t, replace.operation, WGPU_BLEND_OPERATION_ADD)
	testing.expect_value(t, replace.src_factor, WGPU_BLEND_FACTOR_ONE)
	testing.expect_value(t, replace.dst_factor, WGPU_BLEND_FACTOR_ZERO)

	over := wgpu_blend_component_over()
	testing.expect_value(t, over.operation, WGPU_BLEND_OPERATION_ADD)
	testing.expect_value(t, over.src_factor, WGPU_BLEND_FACTOR_ONE)
	testing.expect_value(t, over.dst_factor, WGPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA)

	alpha := wgpu_blend_state_alpha_blending()
	testing.expect_value(t, alpha.color.operation, WGPU_BLEND_OPERATION_ADD)
	testing.expect_value(t, alpha.color.src_factor, WGPU_BLEND_FACTOR_SRC_ALPHA)
	testing.expect_value(t, alpha.color.dst_factor, WGPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA)
	testing.expect_value(t, alpha.alpha, over)
}

@(test)
test_wgpu_render_pipeline_descriptor_matches_mesh_defaults :: proc(t: ^testing.T) {
	module := WGPU_Shader_Module(rawptr(uintptr(0x4444)))
	layout := WGPU_Pipeline_Layout(rawptr(uintptr(0x5555)))
	vertex_entry := wgpu_string_view_from_raw(rawptr(uintptr(0xAAAA)), 7)
	fragment_entry := wgpu_string_view_from_raw(rawptr(uintptr(0xBBBB)), 7)
	label := wgpu_string_view_from_raw(rawptr(uintptr(0xCCCC)), 13)
	attributes := [?]WGPU_Vertex_Attribute{
		wgpu_vertex_attribute(WGPU_VERTEX_FORMAT_FLOAT32X3, 0, 0),
		wgpu_vertex_attribute(WGPU_VERTEX_FORMAT_FLOAT32X2, 12, 1),
		wgpu_vertex_attribute(WGPU_VERTEX_FORMAT_FLOAT32X4, 20, 2),
	}
	buffers := [?]WGPU_Vertex_Buffer_Layout{
		wgpu_vertex_buffer_layout(WGPU_VERTEX_STEP_MODE_VERTEX, 36, &attributes[0], len(attributes)),
	}
	vertex := wgpu_vertex_state(module, vertex_entry, &buffers[0], len(buffers))
	primitive := wgpu_primitive_state(WGPU_CULL_MODE_BACK)
	depth := wgpu_depth_stencil_state(WGPU_DEPTH_FORMAT)
	multisample := wgpu_multisample_state_default()
	blend := wgpu_blend_state_alpha_blending()
	targets := [?]WGPU_Color_Target_State{
		wgpu_color_target_state(WGPU_DEFAULT_TARGET_FORMAT, &blend),
	}
	fragment := wgpu_fragment_state(module, fragment_entry, &targets[0], len(targets))
	descriptor := wgpu_render_pipeline_descriptor(label, layout, vertex, primitive, multisample, &fragment, &depth)

	testing.expect_value(t, attributes[0].format, WGPU_VERTEX_FORMAT_FLOAT32X3)
	testing.expect_value(t, attributes[0].offset, u64(0))
	testing.expect_value(t, attributes[0].shader_location, u32(0))
	testing.expect_value(t, attributes[1].format, WGPU_VERTEX_FORMAT_FLOAT32X2)
	testing.expect_value(t, attributes[1].offset, u64(12))
	testing.expect_value(t, attributes[2].format, WGPU_VERTEX_FORMAT_FLOAT32X4)
	testing.expect_value(t, attributes[2].offset, u64(20))

	testing.expect_value(t, buffers[0].step_mode, WGPU_VERTEX_STEP_MODE_VERTEX)
	testing.expect_value(t, buffers[0].array_stride, u64(36))
	testing.expect_value(t, buffers[0].attribute_count, c.size_t(3))
	testing.expect_value(t, buffers[0].attributes, &attributes[0])

	testing.expect_value(t, vertex.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, vertex.module, module)
	testing.expect_value(t, vertex.entry_point, vertex_entry)
	testing.expect_value(t, vertex.constant_count, c.size_t(0))
	testing.expect_value(t, vertex.constants, ([^]WGPU_Constant_Entry)(nil))
	testing.expect_value(t, vertex.buffer_count, c.size_t(1))
	testing.expect_value(t, vertex.buffers, &buffers[0])

	testing.expect_value(t, primitive.topology, WGPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST)
	testing.expect_value(t, primitive.strip_index_format, WGPU_INDEX_FORMAT_UNDEFINED)
	testing.expect_value(t, primitive.front_face, WGPU_FRONT_FACE_CCW)
	testing.expect_value(t, primitive.cull_mode, WGPU_CULL_MODE_BACK)
	testing.expect_value(t, primitive.unclipped_depth, WGPU_FALSE)

	testing.expect_value(t, depth.format, WGPU_DEPTH_FORMAT)
	testing.expect_value(t, depth.depth_write_enabled, WGPU_OPTIONAL_BOOL_TRUE)
	testing.expect_value(t, depth.depth_compare, WGPU_COMPARE_FUNCTION_LESS)
	testing.expect_value(t, depth.stencil_front, wgpu_stencil_face_state_default())
	testing.expect_value(t, depth.stencil_read_mask, u32(0xFFFFFFFF))
	testing.expect_value(t, depth.stencil_write_mask, u32(0xFFFFFFFF))

	testing.expect_value(t, multisample.count, u32(1))
	testing.expect_value(t, multisample.mask, u32(0xFFFFFFFF))
	testing.expect_value(t, multisample.alpha_to_coverage_enabled, WGPU_FALSE)

	testing.expect_value(t, targets[0].format, WGPU_DEFAULT_TARGET_FORMAT)
	testing.expect_value(t, targets[0].blend, &blend)
	testing.expect_value(t, targets[0].write_mask, WGPU_COLOR_WRITE_MASK_ALL)
	testing.expect_value(t, fragment.module, module)
	testing.expect_value(t, fragment.entry_point, fragment_entry)
	testing.expect_value(t, fragment.target_count, c.size_t(1))
	testing.expect_value(t, fragment.targets, &targets[0])

	testing.expect_value(t, descriptor.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, descriptor.label, label)
	testing.expect_value(t, descriptor.layout, layout)
	testing.expect_value(t, descriptor.vertex, vertex)
	testing.expect_value(t, descriptor.primitive, primitive)
	testing.expect_value(t, descriptor.depth_stencil, &depth)
	testing.expect_value(t, descriptor.multisample, multisample)
	testing.expect_value(t, descriptor.fragment, &fragment)
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

@(test)
test_wgpu_context_request_descriptors_match_open_gpu_defaults :: proc(t: ^testing.T) {
	instance := wgpu_instance_descriptor_default()
	testing.expect_value(t, instance.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, instance.features.next_in_chain, (^WGPU_Chained_Struct_Out)(nil))
	testing.expect_value(t, instance.features.timed_wait_any_enable, WGPU_FALSE)
	testing.expect_value(t, instance.features.timed_wait_any_max_count, c.size_t(0))

	adapter := wgpu_request_adapter_options(WGPU_Surface(rawptr(uintptr(0x7777))))
	testing.expect_value(t, adapter.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, adapter.feature_level, WGPU_FEATURE_LEVEL_CORE)
	testing.expect_value(t, adapter.power_preference, WGPU_POWER_PREFERENCE_UNDEFINED)
	testing.expect_value(t, adapter.force_fallback_adapter, WGPU_FALSE)
	testing.expect_value(t, adapter.backend_type, WGPU_BACKEND_TYPE_UNDEFINED)
	testing.expect_value(t, adapter.compatible_surface, WGPU_Surface(rawptr(uintptr(0x7777))))

	device := wgpu_device_descriptor_default()
	testing.expect_value(t, device.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, device.label, wgpu_string_view_empty())
	testing.expect_value(t, device.required_feature_count, c.size_t(0))
	testing.expect_value(t, device.required_features, rawptr(nil))
	testing.expect_value(t, device.required_limits, WGPU_Limits(nil))
	testing.expect_value(t, device.default_queue.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, device.default_queue.label, wgpu_string_view_empty())
	testing.expect_value(t, device.device_lost_callback_info.mode, WGPU_CALLBACK_MODE_ALLOW_PROCESS_EVENTS)
	testing.expect_value(t, device.device_lost_callback_info.callback, WGPU_Device_Lost_Callback(wgpu_default_device_lost_callback))
	testing.expect_value(t, device.uncaptured_error_callback_info.callback, WGPU_Uncaptured_Error_Callback(nil))
}

@(test)
test_wgpu_request_callback_infos_use_process_events_mode :: proc(t: ^testing.T) {
	userdata1 := rawptr(uintptr(0x1212))
	userdata2 := rawptr(uintptr(0x3434))
	adapter := wgpu_request_adapter_callback_info(wgpu_test_request_adapter_callback, userdata1, userdata2)
	testing.expect_value(t, adapter.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, adapter.mode, WGPU_CALLBACK_MODE_ALLOW_PROCESS_EVENTS)
	testing.expect_value(t, adapter.callback, WGPU_Request_Adapter_Callback(wgpu_test_request_adapter_callback))
	testing.expect_value(t, adapter.userdata1, userdata1)
	testing.expect_value(t, adapter.userdata2, userdata2)

	device := wgpu_request_device_callback_info(wgpu_test_request_device_callback, userdata1, userdata2)
	testing.expect_value(t, device.next_in_chain, (^WGPU_Chained_Struct)(nil))
	testing.expect_value(t, device.mode, WGPU_CALLBACK_MODE_ALLOW_PROCESS_EVENTS)
	testing.expect_value(t, device.callback, WGPU_Request_Device_Callback(wgpu_test_request_device_callback))
	testing.expect_value(t, device.userdata1, userdata1)
	testing.expect_value(t, device.userdata2, userdata2)
}

@(test)
test_wgpu_offscreen_proc_table_resolves_required_symbols :: proc(t: ^testing.T) {
	ctx := WGPU_Test_Resolver_Context{}
	procs, missing, ok := wgpu_resolve_offscreen_procs(wgpu_test_symbol_resolver, rawptr(&ctx))

	testing.expect_value(t, ok, true)
	testing.expect_value(t, missing, "")
	testing.expect_value(t, ctx.calls, 57)
	testing.expect_value(t, ctx.last_user_data, rawptr(&ctx))

	instance := procs.create_instance((^WGPU_Instance_Descriptor)(nil))
	testing.expect_value(t, instance, WGPU_Instance(rawptr(uintptr(0x100A))))
	surface := procs.instance_create_surface(instance, (^WGPU_Surface_Descriptor)(nil))
	testing.expect_value(t, surface, WGPU_Surface(rawptr(uintptr(0x1015))))
	procs.surface_configure(surface, (^WGPU_Surface_Configuration)(nil))
	capabilities := WGPU_Surface_Capabilities{}
	testing.expect_value(t, procs.surface_get_capabilities(surface, WGPU_Adapter(nil), &capabilities), WGPU_STATUS_SUCCESS)
	surface_texture := wgpu_surface_texture_error()
	procs.surface_get_current_texture(surface, &surface_texture)
	testing.expect_value(t, surface_texture.texture, WGPU_Texture(rawptr(uintptr(0x1016))))
	testing.expect_value(t, surface_texture.status, WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_OPTIMAL)
	testing.expect_value(t, procs.surface_present(surface), WGPU_STATUS_SUCCESS)
	procs.surface_unconfigure(surface)
	procs.surface_capabilities_free_members(capabilities)
	procs.surface_release(surface)

	texture := procs.device_create_texture(WGPU_Device(nil), (^WGPU_Texture_Descriptor)(nil))
	testing.expect_value(t, texture, WGPU_Texture(rawptr(uintptr(0x1001))))

	bind_group_layout := procs.device_create_bind_group_layout(WGPU_Device(nil), (^WGPU_Bind_Group_Layout_Descriptor)(nil))
	testing.expect_value(t, bind_group_layout, WGPU_Bind_Group_Layout(rawptr(uintptr(0x100F))))
	pipeline_layout := procs.device_create_pipeline_layout(WGPU_Device(nil), (^WGPU_Pipeline_Layout_Descriptor)(nil))
	testing.expect_value(t, pipeline_layout, WGPU_Pipeline_Layout(rawptr(uintptr(0x1010))))
	sampler := procs.device_create_sampler(WGPU_Device(nil), (^WGPU_Sampler_Descriptor)(nil))
	testing.expect_value(t, sampler, WGPU_Sampler(rawptr(uintptr(0x1011))))
	bind_group := procs.device_create_bind_group(WGPU_Device(nil), (^WGPU_Bind_Group_Descriptor)(nil))
	testing.expect_value(t, bind_group, WGPU_Bind_Group(rawptr(uintptr(0x1012))))
	shader_module := procs.device_create_shader_module(WGPU_Device(nil), (^WGPU_Shader_Module_Descriptor)(nil))
	testing.expect_value(t, shader_module, WGPU_Shader_Module(rawptr(uintptr(0x1013))))
	render_pipeline := procs.device_create_render_pipeline(WGPU_Device(nil), (^WGPU_Render_Pipeline_Descriptor)(nil))
	testing.expect_value(t, render_pipeline, WGPU_Render_Pipeline(rawptr(uintptr(0x1014))))

	command_buffer := procs.command_encoder_finish(WGPU_Command_Encoder(nil), (^WGPU_Command_Buffer_Descriptor)(nil))
	testing.expect_value(t, command_buffer, WGPU_Command_Buffer(rawptr(uintptr(0x1006))))

	future := procs.buffer_map_async(WGPU_Buffer(nil), WGPU_MAP_MODE_READ, 0, 16, wgpu_buffer_map_callback_info(wgpu_test_buffer_map_callback))
	testing.expect_value(t, future, WGPU_Future{id = 0x1008})

	queue := procs.device_get_queue(WGPU_Device(nil))
	testing.expect_value(t, queue, WGPU_Queue(rawptr(uintptr(0x100D))))
	buffer := WGPU_Buffer(rawptr(uintptr(0x2222)))
	upload_data := [?]u8{1, 2, 3, 4}
	procs.queue_write_buffer(queue, buffer, 8, rawptr(&upload_data[0]), len(upload_data))
	texture_destination := wgpu_texel_copy_texture_info(texture)
	texture_layout := wgpu_texel_copy_buffer_layout(4, 1)
	texture_extent := wgpu_extent_3d(1, 1)
	procs.queue_write_texture(queue, &texture_destination, rawptr(&upload_data[0]), len(upload_data), &texture_layout, &texture_extent)

	render_pass := procs.command_encoder_begin_render_pass(WGPU_Command_Encoder(nil), (^WGPU_Render_Pass_Descriptor)(nil))
	testing.expect_value(t, render_pass, WGPU_Render_Pass_Encoder(rawptr(uintptr(0x100E))))
	procs.render_pass_encoder_set_pipeline(render_pass, WGPU_Render_Pipeline(nil))
	procs.render_pass_encoder_set_bind_group(render_pass, 0, WGPU_Bind_Group(nil), 0, nil)
	procs.render_pass_encoder_set_vertex_buffer(render_pass, 0, WGPU_Buffer(nil), 0, 64)
	procs.render_pass_encoder_set_index_buffer(render_pass, WGPU_Buffer(nil), WGPU_INDEX_FORMAT_UINT16, 0, 32)
	procs.render_pass_encoder_set_viewport(render_pass, 0, 0, 640, 480, 0, 1)
	procs.render_pass_encoder_set_scissor_rect(render_pass, 0, 0, 640, 480)
	procs.render_pass_encoder_draw(render_pass, 3, 1, 0, 0)
	procs.render_pass_encoder_draw_indexed(render_pass, 36, 2, 0, 0, 0)
	procs.render_pass_encoder_end(render_pass)
}

@(test)
test_wgpu_offscreen_proc_table_reports_first_missing_symbol :: proc(t: ^testing.T) {
	ctx := WGPU_Test_Resolver_Context{missing = WGPU_SYMBOL_COMMAND_ENCODER_FINISH}
	_, missing, ok := wgpu_resolve_offscreen_procs(wgpu_test_symbol_resolver, rawptr(&ctx))

	testing.expect_value(t, ok, false)
	testing.expect_value(t, missing, WGPU_SYMBOL_COMMAND_ENCODER_FINISH)
	testing.expect_value(t, ctx.calls, 25)
}

@(test)
test_wgpu_offscreen_dynamic_library_loads_proc_table :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "wgpu-offscreen-dynlib")
	defer os.remove_all(root)
	defer delete(root)

	library_path := build_fake_wgpu_library(t, root, FAKE_WGPU_DYNAMIC_LIBRARY_SOURCE)
	defer delete(library_path)

	loaded, missing, ok := wgpu_load_offscreen_library(library_path)
	defer wgpu_unload_offscreen_library(&loaded)

	testing.expect_value(t, ok, true)
	testing.expect_value(t, missing, "")

	instance := loaded.procs.create_instance((^WGPU_Instance_Descriptor)(nil))
	testing.expect_value(t, instance, WGPU_Instance(rawptr(uintptr(0x200A))))
	surface := loaded.procs.instance_create_surface(instance, (^WGPU_Surface_Descriptor)(nil))
	testing.expect_value(t, surface, WGPU_Surface(rawptr(uintptr(0x2015))))
	loaded.procs.surface_configure(surface, (^WGPU_Surface_Configuration)(nil))
	capabilities := WGPU_Surface_Capabilities{}
	testing.expect_value(t, loaded.procs.surface_get_capabilities(surface, WGPU_Adapter(nil), &capabilities), WGPU_STATUS_SUCCESS)
	surface_texture := wgpu_surface_texture_error()
	loaded.procs.surface_get_current_texture(surface, &surface_texture)
	testing.expect_value(t, surface_texture.texture, WGPU_Texture(rawptr(uintptr(0x2016))))
	testing.expect_value(t, surface_texture.status, WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_OPTIMAL)
	testing.expect_value(t, loaded.procs.surface_present(surface), WGPU_STATUS_SUCCESS)
	loaded.procs.surface_unconfigure(surface)
	loaded.procs.surface_capabilities_free_members(capabilities)
	loaded.procs.surface_release(surface)

	adapter_future := loaded.procs.instance_request_adapter(WGPU_Instance(nil), (^WGPU_Request_Adapter_Options)(nil), wgpu_request_adapter_callback_info(wgpu_test_request_adapter_callback))
	testing.expect_value(t, adapter_future, WGPU_Future{id = 0x200B})

	device_future := loaded.procs.adapter_request_device(WGPU_Adapter(nil), (^WGPU_Device_Descriptor)(nil), wgpu_request_device_callback_info(wgpu_test_request_device_callback))
	testing.expect_value(t, device_future, WGPU_Future{id = 0x200C})

	queue := loaded.procs.device_get_queue(WGPU_Device(nil))
	testing.expect_value(t, queue, WGPU_Queue(rawptr(uintptr(0x200D))))
	upload_data := [?]u8{5, 6, 7, 8}
	loaded.procs.queue_write_buffer(queue, WGPU_Buffer(rawptr(uintptr(0x2020))), 4, rawptr(&upload_data[0]), len(upload_data))
	texture_destination := wgpu_texel_copy_texture_info(WGPU_Texture(rawptr(uintptr(0x2021))))
	texture_layout := wgpu_texel_copy_buffer_layout(4, 1)
	texture_extent := wgpu_extent_3d(1, 1)
	loaded.procs.queue_write_texture(queue, &texture_destination, rawptr(&upload_data[0]), len(upload_data), &texture_layout, &texture_extent)

	bind_group_layout := loaded.procs.device_create_bind_group_layout(WGPU_Device(nil), (^WGPU_Bind_Group_Layout_Descriptor)(nil))
	testing.expect_value(t, bind_group_layout, WGPU_Bind_Group_Layout(rawptr(uintptr(0x200F))))
	pipeline_layout := loaded.procs.device_create_pipeline_layout(WGPU_Device(nil), (^WGPU_Pipeline_Layout_Descriptor)(nil))
	testing.expect_value(t, pipeline_layout, WGPU_Pipeline_Layout(rawptr(uintptr(0x2010))))
	sampler := loaded.procs.device_create_sampler(WGPU_Device(nil), (^WGPU_Sampler_Descriptor)(nil))
	testing.expect_value(t, sampler, WGPU_Sampler(rawptr(uintptr(0x2011))))
	bind_group := loaded.procs.device_create_bind_group(WGPU_Device(nil), (^WGPU_Bind_Group_Descriptor)(nil))
	testing.expect_value(t, bind_group, WGPU_Bind_Group(rawptr(uintptr(0x2012))))
	shader_module := loaded.procs.device_create_shader_module(WGPU_Device(nil), (^WGPU_Shader_Module_Descriptor)(nil))
	testing.expect_value(t, shader_module, WGPU_Shader_Module(rawptr(uintptr(0x2013))))
	render_pipeline := loaded.procs.device_create_render_pipeline(WGPU_Device(nil), (^WGPU_Render_Pipeline_Descriptor)(nil))
	testing.expect_value(t, render_pipeline, WGPU_Render_Pipeline(rawptr(uintptr(0x2014))))

	render_pass := loaded.procs.command_encoder_begin_render_pass(WGPU_Command_Encoder(nil), (^WGPU_Render_Pass_Descriptor)(nil))
	testing.expect_value(t, render_pass, WGPU_Render_Pass_Encoder(rawptr(uintptr(0x200E))))
	loaded.procs.render_pass_encoder_set_pipeline(render_pass, WGPU_Render_Pipeline(nil))
	loaded.procs.render_pass_encoder_set_bind_group(render_pass, 0, WGPU_Bind_Group(nil), 0, nil)
	loaded.procs.render_pass_encoder_set_vertex_buffer(render_pass, 0, WGPU_Buffer(nil), 0, 64)
	loaded.procs.render_pass_encoder_set_index_buffer(render_pass, WGPU_Buffer(nil), WGPU_INDEX_FORMAT_UINT16, 0, 32)
	loaded.procs.render_pass_encoder_set_viewport(render_pass, 0, 0, 640, 480, 0, 1)
	loaded.procs.render_pass_encoder_set_scissor_rect(render_pass, 0, 0, 640, 480)
	loaded.procs.render_pass_encoder_draw(render_pass, 3, 1, 0, 0)
	loaded.procs.render_pass_encoder_draw_indexed(render_pass, 36, 2, 0, 0, 0)
	loaded.procs.render_pass_encoder_end(render_pass)

	texture := loaded.procs.device_create_texture(WGPU_Device(nil), (^WGPU_Texture_Descriptor)(nil))
	testing.expect_value(t, texture, WGPU_Texture(rawptr(uintptr(0x2001))))

	future := loaded.procs.buffer_map_async(WGPU_Buffer(nil), WGPU_MAP_MODE_READ, 0, 16, wgpu_buffer_map_callback_info(wgpu_test_buffer_map_callback))
	testing.expect_value(t, future, WGPU_Future{id = 0x2008})
}

@(test)
test_wgpu_offscreen_dynamic_library_reports_missing_required_symbol :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "wgpu-offscreen-dynlib-missing-symbol")
	defer os.remove_all(root)
	defer delete(root)

	library_path := build_fake_wgpu_library(t, root, FAKE_WGPU_MISSING_SYMBOL_DYNAMIC_LIBRARY_SOURCE)
	defer delete(library_path)

	loaded, missing, ok := wgpu_load_offscreen_library(library_path)

	testing.expect_value(t, ok, false)
	testing.expect_value(t, missing, WGPU_SYMBOL_COMMAND_ENCODER_FINISH)
	testing.expect_value(t, loaded.handle, dynlib.Library(nil))
}

@(test)
test_wgpu_offscreen_dynamic_library_reports_load_failure :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "wgpu-offscreen-dynlib-missing-file")
	defer os.remove_all(root)
	defer delete(root)

	library_path := join_test_path(t, root, dynamic_library_file_name())
	defer delete(library_path)

	loaded, missing, ok := wgpu_load_offscreen_library(library_path)

	testing.expect_value(t, ok, false)
	testing.expect_value(t, missing, WGPU_OFFSCREEN_LIBRARY_LOAD_ERROR)
	testing.expect_value(t, loaded.handle, dynlib.Library(nil))
}

@(test)
test_wgpu_native_dynamic_library_file_name_matches_host_platform :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		testing.expect_value(t, wgpu_native_dynamic_library_file_name(), "wgpu_native.dll")
	} else when ODIN_OS == .Darwin {
		testing.expect_value(t, wgpu_native_dynamic_library_file_name(), "libwgpu_native.dylib")
	} else {
		testing.expect_value(t, wgpu_native_dynamic_library_file_name(), "libwgpu_native.so")
	}
}

@(test)
test_wgpu_default_library_search_discovers_zig_package_cache_layout :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "wgpu-default-library-search")
	defer os.remove_all(root)
	defer delete(root)

	_, found_before := wgpu_find_default_offscreen_library(root)
	testing.expect_value(t, found_before, false)

	cache_library_path := stage_fake_wgpu_zig_package_library(t, root)
	defer delete(cache_library_path)

	found_path, found := wgpu_find_default_offscreen_library(root)
	defer if found { delete(found_path) }
	testing.expect_value(t, found, true)
	testing.expect_value(t, same_resolved_path(found_path, cache_library_path), true)
}

@(test)
test_wgpu_default_library_loader_uses_discovered_zig_package_cache_library :: proc(t: ^testing.T) {
	root := make_test_project_root(t, "wgpu-default-library-load")
	defer os.remove_all(root)
	defer delete(root)

	cache_library_path := stage_fake_wgpu_zig_package_library(t, root)
	defer delete(cache_library_path)

	loaded, missing, ok := wgpu_load_default_offscreen_library(root)
	defer wgpu_unload_offscreen_library(&loaded)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, missing, "")

	instance := loaded.procs.create_instance((^WGPU_Instance_Descriptor)(nil))
	testing.expect_value(t, instance, WGPU_Instance(rawptr(uintptr(0x200A))))
}

build_fake_wgpu_library :: proc(t: ^testing.T, root, source: string) -> string {
	write_file(t, root, "fake_wgpu.odin", source)

	output_name := dynamic_library_file_name()
	output_path := join_test_path(t, root, output_name)
	output_arg := build_prefixed_string("-out:", output_name)
	defer delete(output_arg)

	command := []string{"odin", "build", ".", "-build-mode:dll", output_arg}
	state, stdout, stderr, exec_err := os.process_exec(os.Process_Desc{
		working_dir = root,
		command = command,
	}, context.allocator)
	defer {
		if stdout != nil {
			delete(stdout)
		}
		if stderr != nil {
			delete(stderr)
		}
	}
	if exec_err != nil || !state.exited || state.exit_code != 0 || !os.exists(output_path) {
		delete(output_path)
		testing.fail_now(t, "failed to build fake wgpu dynamic library")
	}

	return output_path
}

stage_fake_wgpu_zig_package_library :: proc(t: ^testing.T, root: string) -> string {
	source_library := build_fake_wgpu_library(t, root, FAKE_WGPU_DYNAMIC_LIBRARY_SOURCE)
	defer delete(source_library)

	cache_lib_path, cache_lib_err := filepath.join([]string{root, "zig-pkg", "fake-wgpu-hash", "lib"})
	if cache_lib_err != nil {
		testing.fail_now(t, "failed to join fake zig package lib path")
	}
	defer delete(cache_lib_path)
	if os.mkdir_all(cache_lib_path) != nil {
		testing.fail_now(t, "failed to create fake zig package lib path")
	}

	destination_library, dest_err := filepath.join([]string{cache_lib_path, wgpu_native_dynamic_library_file_name()})
	if dest_err != nil {
		testing.fail_now(t, "failed to join fake wgpu library path")
	}
	if os.copy_file(destination_library, source_library) != nil {
		delete(destination_library)
		testing.fail_now(t, "failed to stage fake wgpu library")
	}
	return destination_library
}

wgpu_test_buffer_map_callback :: proc "c" (status: WGPU_Map_Async_Status, message: WGPU_String_View, userdata1, userdata2: rawptr) {
	_ = status
	_ = message
	_ = userdata1
	_ = userdata2
}

wgpu_test_request_adapter_callback :: proc "c" (status: WGPU_Request_Adapter_Status, adapter: WGPU_Adapter, message: WGPU_String_View, userdata1, userdata2: rawptr) {
	_ = status
	_ = adapter
	_ = message
	_ = userdata1
	_ = userdata2
}

wgpu_test_request_device_callback :: proc "c" (status: WGPU_Request_Device_Status, device: WGPU_Device, message: WGPU_String_View, userdata1, userdata2: rawptr) {
	_ = status
	_ = device
	_ = message
	_ = userdata1
	_ = userdata2
}

FAKE_WGPU_DYNAMIC_LIBRARY_SOURCE :: `package fake_wgpu

import "core:c"

WGPU_Future :: struct {
	id: u64,
}

WGPU_String_View :: struct #align(align_of(rawptr)) {
	data:   rawptr,
	length: c.size_t,
}

WGPU_Buffer_Map_Callback_Info :: struct #align(align_of(rawptr)) {
	next_in_chain: rawptr,
	mode:          u32,
	callback:      rawptr,
	userdata1:     rawptr,
	userdata2:     rawptr,
}

WGPU_Request_Adapter_Callback_Info :: struct #align(align_of(rawptr)) {
	next_in_chain: rawptr,
	mode:          u32,
	callback:      rawptr,
	userdata1:     rawptr,
	userdata2:     rawptr,
}

WGPU_Request_Device_Callback_Info :: struct #align(align_of(rawptr)) {
	next_in_chain: rawptr,
	mode:          u32,
	callback:      rawptr,
	userdata1:     rawptr,
	userdata2:     rawptr,
}

WGPU_Surface_Texture :: struct #align(align_of(rawptr)) {
	next_in_chain: rawptr,
	texture:       rawptr,
	status:        u32,
}

WGPU_Surface_Capabilities :: struct #align(align_of(rawptr)) {
	next_in_chain:     rawptr,
	usages:            u64,
	format_count:      c.size_t,
	formats:           rawptr,
	present_mode_count: c.size_t,
	present_modes:     rawptr,
	alpha_mode_count:  c.size_t,
	alpha_modes:       rawptr,
}

@(export)
wgpuCreateInstance :: proc "c" (descriptor: rawptr) -> rawptr {
	_ = descriptor
	return rawptr(uintptr(0x200A))
}

@(export)
wgpuInstanceCreateSurface :: proc "c" (instance, descriptor: rawptr) -> rawptr {
	_ = instance
	_ = descriptor
	return rawptr(uintptr(0x2015))
}

@(export)
wgpuSurfaceConfigure :: proc "c" (surface, config: rawptr) {
	_ = surface
	_ = config
}

@(export)
wgpuSurfaceGetCapabilities :: proc "c" (surface, adapter, capabilities: rawptr) -> u32 {
	_ = surface
	_ = adapter
	_ = capabilities
	return 1
}

@(export)
wgpuSurfaceGetCurrentTexture :: proc "c" (surface: rawptr, surface_texture: ^WGPU_Surface_Texture) {
	_ = surface
	surface_texture.texture = rawptr(uintptr(0x2016))
	surface_texture.status = 1
}

@(export)
wgpuSurfacePresent :: proc "c" (surface: rawptr) -> u32 {
	_ = surface
	return 1
}

@(export)
wgpuSurfaceUnconfigure :: proc "c" (surface: rawptr) {
	_ = surface
}

@(export)
wgpuSurfaceCapabilitiesFreeMembers :: proc "c" (capabilities: WGPU_Surface_Capabilities) {
	_ = capabilities
}

@(export)
wgpuSurfaceRelease :: proc "c" (surface: rawptr) {
	_ = surface
}

@(export)
wgpuInstanceRequestAdapter :: proc "c" (instance, options: rawptr, callback_info: WGPU_Request_Adapter_Callback_Info) -> WGPU_Future {
	_ = instance
	_ = options
	_ = callback_info
	return WGPU_Future{id = 0x200B}
}

@(export)
wgpuAdapterRequestDevice :: proc "c" (adapter, descriptor: rawptr, callback_info: WGPU_Request_Device_Callback_Info) -> WGPU_Future {
	_ = adapter
	_ = descriptor
	_ = callback_info
	return WGPU_Future{id = 0x200C}
}

@(export)
wgpuDeviceGetQueue :: proc "c" (device: rawptr) -> rawptr {
	_ = device
	return rawptr(uintptr(0x200D))
}

@(export)
wgpuDeviceCreateTexture :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x2001))
}

@(export)
wgpuDeviceCreateBuffer :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x2002))
}

@(export)
wgpuDeviceCreateBindGroupLayout :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x200F))
}

@(export)
wgpuDeviceCreatePipelineLayout :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x2010))
}

@(export)
wgpuDeviceCreateSampler :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x2011))
}

@(export)
wgpuDeviceCreateBindGroup :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x2012))
}

@(export)
wgpuDeviceCreateShaderModule :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x2013))
}

@(export)
wgpuDeviceCreateRenderPipeline :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x2014))
}

@(export)
wgpuDeviceCreateCommandEncoder :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x2003))
}

@(export)
wgpuTextureCreateView :: proc "c" (texture, descriptor: rawptr) -> rawptr {
	_ = texture
	_ = descriptor
	return rawptr(uintptr(0x2004))
}

@(export)
wgpuCommandEncoderCopyTextureToBuffer :: proc "c" (encoder, source, destination, copy_size: rawptr) {
	_ = encoder
	_ = source
	_ = destination
	_ = copy_size
}

@(export)
wgpuCommandEncoderBeginRenderPass :: proc "c" (encoder, descriptor: rawptr) -> rawptr {
	_ = encoder
	_ = descriptor
	return rawptr(uintptr(0x200E))
}

@(export)
wgpuRenderPassEncoderSetPipeline :: proc "c" (render_pass, pipeline: rawptr) {
	_ = render_pass
	_ = pipeline
}

@(export)
wgpuRenderPassEncoderSetBindGroup :: proc "c" (render_pass: rawptr, group_index: u32, group: rawptr, dynamic_offset_count: c.size_t, dynamic_offsets: rawptr) {
	_ = render_pass
	_ = group_index
	_ = group
	_ = dynamic_offset_count
	_ = dynamic_offsets
}

@(export)
wgpuRenderPassEncoderSetVertexBuffer :: proc "c" (render_pass: rawptr, slot: u32, buffer: rawptr, offset, size: u64) {
	_ = render_pass
	_ = slot
	_ = buffer
	_ = offset
	_ = size
}

@(export)
wgpuRenderPassEncoderSetIndexBuffer :: proc "c" (render_pass, buffer: rawptr, format: u32, offset, size: u64) {
	_ = render_pass
	_ = buffer
	_ = format
	_ = offset
	_ = size
}

@(export)
wgpuRenderPassEncoderSetViewport :: proc "c" (render_pass: rawptr, x, y, width, height, min_depth, max_depth: f32) {
	_ = render_pass
	_ = x
	_ = y
	_ = width
	_ = height
	_ = min_depth
	_ = max_depth
}

@(export)
wgpuRenderPassEncoderSetScissorRect :: proc "c" (render_pass: rawptr, x, y, width, height: u32) {
	_ = render_pass
	_ = x
	_ = y
	_ = width
	_ = height
}

@(export)
wgpuRenderPassEncoderDraw :: proc "c" (render_pass: rawptr, vertex_count, instance_count, first_vertex, first_instance: u32) {
	_ = render_pass
	_ = vertex_count
	_ = instance_count
	_ = first_vertex
	_ = first_instance
}

@(export)
wgpuRenderPassEncoderDrawIndexed :: proc "c" (render_pass: rawptr, index_count, instance_count, first_index: u32, base_vertex: i32, first_instance: u32) {
	_ = render_pass
	_ = index_count
	_ = instance_count
	_ = first_index
	_ = base_vertex
	_ = first_instance
}

@(export)
wgpuRenderPassEncoderEnd :: proc "c" (render_pass: rawptr) {
	_ = render_pass
}

@(export)
wgpuCommandEncoderFinish :: proc "c" (encoder, descriptor: rawptr) -> rawptr {
	_ = encoder
	_ = descriptor
	return rawptr(uintptr(0x2006))
}

@(export)
wgpuQueueSubmit :: proc "c" (queue: rawptr, command_count: c.size_t, commands: rawptr) {
	_ = queue
	_ = command_count
	_ = commands
}

@(export)
wgpuQueueWriteBuffer :: proc "c" (queue, buffer: rawptr, buffer_offset: u64, data: rawptr, size: c.size_t) {
	_ = queue
	_ = buffer
	_ = buffer_offset
	_ = data
	_ = size
}

@(export)
wgpuQueueWriteTexture :: proc "c" (queue, destination, data: rawptr, data_size: c.size_t, data_layout, write_size: rawptr) {
	_ = queue
	_ = destination
	_ = data
	_ = data_size
	_ = data_layout
	_ = write_size
}

@(export)
wgpuBufferMapAsync :: proc "c" (buffer: rawptr, mode: u64, offset, size: c.size_t, callback_info: WGPU_Buffer_Map_Callback_Info) -> WGPU_Future {
	_ = buffer
	_ = mode
	_ = offset
	_ = size
	_ = callback_info
	return WGPU_Future{id = 0x2008}
}

@(export)
wgpuBufferGetMappedRange :: proc "c" (buffer: rawptr, offset, size: c.size_t) -> rawptr {
	_ = buffer
	_ = offset
	_ = size
	return rawptr(uintptr(0x2009))
}

@(export)
wgpuBufferUnmap :: proc "c" (buffer: rawptr) {
	_ = buffer
}

@(export)
wgpuInstanceProcessEvents :: proc "c" (instance: rawptr) {
	_ = instance
}

@(export)
wgpuTextureRelease :: proc "c" (texture: rawptr) {
	_ = texture
}

@(export)
wgpuTextureViewRelease :: proc "c" (texture_view: rawptr) {
	_ = texture_view
}

@(export)
wgpuBufferRelease :: proc "c" (buffer: rawptr) {
	_ = buffer
}

@(export)
wgpuBindGroupLayoutRelease :: proc "c" (bind_group_layout: rawptr) {
	_ = bind_group_layout
}

@(export)
wgpuPipelineLayoutRelease :: proc "c" (pipeline_layout: rawptr) {
	_ = pipeline_layout
}

@(export)
wgpuSamplerRelease :: proc "c" (sampler: rawptr) {
	_ = sampler
}

@(export)
wgpuBindGroupRelease :: proc "c" (bind_group: rawptr) {
	_ = bind_group
}

@(export)
wgpuShaderModuleRelease :: proc "c" (shader_module: rawptr) {
	_ = shader_module
}

@(export)
wgpuRenderPipelineRelease :: proc "c" (pipeline: rawptr) {
	_ = pipeline
}

@(export)
wgpuCommandEncoderRelease :: proc "c" (encoder: rawptr) {
	_ = encoder
}

@(export)
wgpuCommandBufferRelease :: proc "c" (command_buffer: rawptr) {
	_ = command_buffer
}

@(export)
wgpuRenderPassEncoderRelease :: proc "c" (render_pass: rawptr) {
	_ = render_pass
}

@(export)
wgpuInstanceRelease :: proc "c" (instance: rawptr) {
	_ = instance
}

@(export)
wgpuAdapterRelease :: proc "c" (adapter: rawptr) {
	_ = adapter
}

@(export)
wgpuDeviceRelease :: proc "c" (device: rawptr) {
	_ = device
}

@(export)
wgpuQueueRelease :: proc "c" (queue: rawptr) {
	_ = queue
}
`

FAKE_WGPU_MISSING_SYMBOL_DYNAMIC_LIBRARY_SOURCE :: `package fake_wgpu

import "core:c"

WGPU_Future :: struct {
	id: u64,
}

WGPU_Buffer_Map_Callback_Info :: struct #align(align_of(rawptr)) {
	next_in_chain: rawptr,
	mode:          u32,
	callback:      rawptr,
	userdata1:     rawptr,
	userdata2:     rawptr,
}

WGPU_Request_Adapter_Callback_Info :: struct #align(align_of(rawptr)) {
	next_in_chain: rawptr,
	mode:          u32,
	callback:      rawptr,
	userdata1:     rawptr,
	userdata2:     rawptr,
}

WGPU_Request_Device_Callback_Info :: struct #align(align_of(rawptr)) {
	next_in_chain: rawptr,
	mode:          u32,
	callback:      rawptr,
	userdata1:     rawptr,
	userdata2:     rawptr,
}

WGPU_Surface_Texture :: struct #align(align_of(rawptr)) {
	next_in_chain: rawptr,
	texture:       rawptr,
	status:        u32,
}

WGPU_Surface_Capabilities :: struct #align(align_of(rawptr)) {
	next_in_chain:     rawptr,
	usages:            u64,
	format_count:      c.size_t,
	formats:           rawptr,
	present_mode_count: c.size_t,
	present_modes:     rawptr,
	alpha_mode_count:  c.size_t,
	alpha_modes:       rawptr,
}

@(export)
wgpuCreateInstance :: proc "c" (descriptor: rawptr) -> rawptr {
	_ = descriptor
	return rawptr(uintptr(0x300A))
}

@(export)
wgpuInstanceCreateSurface :: proc "c" (instance, descriptor: rawptr) -> rawptr {
	_ = instance
	_ = descriptor
	return rawptr(uintptr(0x3015))
}

@(export)
wgpuSurfaceConfigure :: proc "c" (surface, config: rawptr) {
	_ = surface
	_ = config
}

@(export)
wgpuSurfaceGetCapabilities :: proc "c" (surface, adapter, capabilities: rawptr) -> u32 {
	_ = surface
	_ = adapter
	_ = capabilities
	return 1
}

@(export)
wgpuSurfaceGetCurrentTexture :: proc "c" (surface: rawptr, surface_texture: ^WGPU_Surface_Texture) {
	_ = surface
	surface_texture.texture = rawptr(uintptr(0x3016))
	surface_texture.status = 1
}

@(export)
wgpuSurfacePresent :: proc "c" (surface: rawptr) -> u32 {
	_ = surface
	return 1
}

@(export)
wgpuSurfaceUnconfigure :: proc "c" (surface: rawptr) {
	_ = surface
}

@(export)
wgpuSurfaceCapabilitiesFreeMembers :: proc "c" (capabilities: WGPU_Surface_Capabilities) {
	_ = capabilities
}

@(export)
wgpuSurfaceRelease :: proc "c" (surface: rawptr) {
	_ = surface
}

@(export)
wgpuInstanceRequestAdapter :: proc "c" (instance, options: rawptr, callback_info: WGPU_Request_Adapter_Callback_Info) -> WGPU_Future {
	_ = instance
	_ = options
	_ = callback_info
	return WGPU_Future{id = 0x300B}
}

@(export)
wgpuAdapterRequestDevice :: proc "c" (adapter, descriptor: rawptr, callback_info: WGPU_Request_Device_Callback_Info) -> WGPU_Future {
	_ = adapter
	_ = descriptor
	_ = callback_info
	return WGPU_Future{id = 0x300C}
}

@(export)
wgpuDeviceGetQueue :: proc "c" (device: rawptr) -> rawptr {
	_ = device
	return rawptr(uintptr(0x300D))
}

@(export)
wgpuDeviceCreateTexture :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x3001))
}

@(export)
wgpuDeviceCreateBuffer :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x3002))
}

@(export)
wgpuDeviceCreateBindGroupLayout :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x300F))
}

@(export)
wgpuDeviceCreatePipelineLayout :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x3010))
}

@(export)
wgpuDeviceCreateSampler :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x3011))
}

@(export)
wgpuDeviceCreateBindGroup :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x3012))
}

@(export)
wgpuDeviceCreateShaderModule :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x3013))
}

@(export)
wgpuDeviceCreateRenderPipeline :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x3014))
}

@(export)
wgpuDeviceCreateCommandEncoder :: proc "c" (device, descriptor: rawptr) -> rawptr {
	_ = device
	_ = descriptor
	return rawptr(uintptr(0x3003))
}

@(export)
wgpuTextureCreateView :: proc "c" (texture, descriptor: rawptr) -> rawptr {
	_ = texture
	_ = descriptor
	return rawptr(uintptr(0x3004))
}

@(export)
wgpuCommandEncoderCopyTextureToBuffer :: proc "c" (encoder, source, destination, copy_size: rawptr) {
	_ = encoder
	_ = source
	_ = destination
	_ = copy_size
}

@(export)
wgpuCommandEncoderBeginRenderPass :: proc "c" (encoder, descriptor: rawptr) -> rawptr {
	_ = encoder
	_ = descriptor
	return rawptr(uintptr(0x300E))
}

@(export)
wgpuRenderPassEncoderSetPipeline :: proc "c" (render_pass, pipeline: rawptr) {
	_ = render_pass
	_ = pipeline
}

@(export)
wgpuRenderPassEncoderSetBindGroup :: proc "c" (render_pass: rawptr, group_index: u32, group: rawptr, dynamic_offset_count: c.size_t, dynamic_offsets: rawptr) {
	_ = render_pass
	_ = group_index
	_ = group
	_ = dynamic_offset_count
	_ = dynamic_offsets
}

@(export)
wgpuRenderPassEncoderSetVertexBuffer :: proc "c" (render_pass: rawptr, slot: u32, buffer: rawptr, offset, size: u64) {
	_ = render_pass
	_ = slot
	_ = buffer
	_ = offset
	_ = size
}

@(export)
wgpuRenderPassEncoderSetIndexBuffer :: proc "c" (render_pass, buffer: rawptr, format: u32, offset, size: u64) {
	_ = render_pass
	_ = buffer
	_ = format
	_ = offset
	_ = size
}

@(export)
wgpuRenderPassEncoderSetViewport :: proc "c" (render_pass: rawptr, x, y, width, height, min_depth, max_depth: f32) {
	_ = render_pass
	_ = x
	_ = y
	_ = width
	_ = height
	_ = min_depth
	_ = max_depth
}

@(export)
wgpuRenderPassEncoderSetScissorRect :: proc "c" (render_pass: rawptr, x, y, width, height: u32) {
	_ = render_pass
	_ = x
	_ = y
	_ = width
	_ = height
}

@(export)
wgpuRenderPassEncoderDraw :: proc "c" (render_pass: rawptr, vertex_count, instance_count, first_vertex, first_instance: u32) {
	_ = render_pass
	_ = vertex_count
	_ = instance_count
	_ = first_vertex
	_ = first_instance
}

@(export)
wgpuRenderPassEncoderDrawIndexed :: proc "c" (render_pass: rawptr, index_count, instance_count, first_index: u32, base_vertex: i32, first_instance: u32) {
	_ = render_pass
	_ = index_count
	_ = instance_count
	_ = first_index
	_ = base_vertex
	_ = first_instance
}

@(export)
wgpuRenderPassEncoderEnd :: proc "c" (render_pass: rawptr) {
	_ = render_pass
}

@(export)
wgpuQueueSubmit :: proc "c" (queue: rawptr, command_count: c.size_t, commands: rawptr) {
	_ = queue
	_ = command_count
	_ = commands
}

@(export)
wgpuQueueWriteBuffer :: proc "c" (queue, buffer: rawptr, buffer_offset: u64, data: rawptr, size: c.size_t) {
	_ = queue
	_ = buffer
	_ = buffer_offset
	_ = data
	_ = size
}

@(export)
wgpuQueueWriteTexture :: proc "c" (queue, destination, data: rawptr, data_size: c.size_t, data_layout, write_size: rawptr) {
	_ = queue
	_ = destination
	_ = data
	_ = data_size
	_ = data_layout
	_ = write_size
}

@(export)
wgpuBufferMapAsync :: proc "c" (buffer: rawptr, mode: u64, offset, size: c.size_t, callback_info: WGPU_Buffer_Map_Callback_Info) -> WGPU_Future {
	_ = buffer
	_ = mode
	_ = offset
	_ = size
	_ = callback_info
	return WGPU_Future{id = 0x3008}
}

@(export)
wgpuBufferGetMappedRange :: proc "c" (buffer: rawptr, offset, size: c.size_t) -> rawptr {
	_ = buffer
	_ = offset
	_ = size
	return rawptr(uintptr(0x3009))
}

@(export)
wgpuBufferUnmap :: proc "c" (buffer: rawptr) {
	_ = buffer
}

@(export)
wgpuInstanceProcessEvents :: proc "c" (instance: rawptr) {
	_ = instance
}

@(export)
wgpuTextureRelease :: proc "c" (texture: rawptr) {
	_ = texture
}

@(export)
wgpuTextureViewRelease :: proc "c" (texture_view: rawptr) {
	_ = texture_view
}

@(export)
wgpuBufferRelease :: proc "c" (buffer: rawptr) {
	_ = buffer
}

@(export)
wgpuBindGroupLayoutRelease :: proc "c" (bind_group_layout: rawptr) {
	_ = bind_group_layout
}

@(export)
wgpuPipelineLayoutRelease :: proc "c" (pipeline_layout: rawptr) {
	_ = pipeline_layout
}

@(export)
wgpuSamplerRelease :: proc "c" (sampler: rawptr) {
	_ = sampler
}

@(export)
wgpuBindGroupRelease :: proc "c" (bind_group: rawptr) {
	_ = bind_group
}

@(export)
wgpuShaderModuleRelease :: proc "c" (shader_module: rawptr) {
	_ = shader_module
}

@(export)
wgpuRenderPipelineRelease :: proc "c" (pipeline: rawptr) {
	_ = pipeline
}

@(export)
wgpuCommandEncoderRelease :: proc "c" (encoder: rawptr) {
	_ = encoder
}

@(export)
wgpuCommandBufferRelease :: proc "c" (command_buffer: rawptr) {
	_ = command_buffer
}

@(export)
wgpuRenderPassEncoderRelease :: proc "c" (render_pass: rawptr) {
	_ = render_pass
}

@(export)
wgpuInstanceRelease :: proc "c" (instance: rawptr) {
	_ = instance
}

@(export)
wgpuAdapterRelease :: proc "c" (adapter: rawptr) {
	_ = adapter
}

@(export)
wgpuDeviceRelease :: proc "c" (device: rawptr) {
	_ = device
}

@(export)
wgpuQueueRelease :: proc "c" (queue: rawptr) {
	_ = queue
}
`

WGPU_Test_Resolver_Context :: struct {
	missing:        string,
	calls:          int,
	last_user_data: rawptr,
}

wgpu_test_symbol_resolver :: proc(name: string, user_data: rawptr) -> rawptr {
	ctx := (^WGPU_Test_Resolver_Context)(user_data)
	ctx.calls += 1
	ctx.last_user_data = user_data
	if ctx.missing == name {
		return nil
	}
	switch name {
	case WGPU_SYMBOL_CREATE_INSTANCE:
		return rawptr(wgpu_test_create_instance)
	case WGPU_SYMBOL_INSTANCE_REQUEST_ADAPTER:
		return rawptr(wgpu_test_instance_request_adapter)
	case WGPU_SYMBOL_ADAPTER_REQUEST_DEVICE:
		return rawptr(wgpu_test_adapter_request_device)
	case WGPU_SYMBOL_DEVICE_GET_QUEUE:
		return rawptr(wgpu_test_device_get_queue)
	case WGPU_SYMBOL_DEVICE_CREATE_TEXTURE:
		return rawptr(wgpu_test_device_create_texture)
	case WGPU_SYMBOL_DEVICE_CREATE_BUFFER:
		return rawptr(wgpu_test_device_create_buffer)
	case WGPU_SYMBOL_DEVICE_CREATE_BIND_GROUP_LAYOUT:
		return rawptr(wgpu_test_device_create_bind_group_layout)
	case WGPU_SYMBOL_DEVICE_CREATE_PIPELINE_LAYOUT:
		return rawptr(wgpu_test_device_create_pipeline_layout)
	case WGPU_SYMBOL_DEVICE_CREATE_SAMPLER:
		return rawptr(wgpu_test_device_create_sampler)
	case WGPU_SYMBOL_DEVICE_CREATE_BIND_GROUP:
		return rawptr(wgpu_test_device_create_bind_group)
	case WGPU_SYMBOL_DEVICE_CREATE_SHADER_MODULE:
		return rawptr(wgpu_test_device_create_shader_module)
	case WGPU_SYMBOL_DEVICE_CREATE_RENDER_PIPELINE:
		return rawptr(wgpu_test_device_create_render_pipeline)
	case WGPU_SYMBOL_DEVICE_CREATE_COMMAND_ENCODER:
		return rawptr(wgpu_test_device_create_command_encoder)
	case WGPU_SYMBOL_INSTANCE_CREATE_SURFACE:
		return rawptr(wgpu_test_instance_create_surface)
	case WGPU_SYMBOL_SURFACE_CONFIGURE:
		return rawptr(wgpu_test_surface_configure)
	case WGPU_SYMBOL_SURFACE_GET_CAPABILITIES:
		return rawptr(wgpu_test_surface_get_capabilities)
	case WGPU_SYMBOL_SURFACE_GET_CURRENT_TEXTURE:
		return rawptr(wgpu_test_surface_get_current_texture)
	case WGPU_SYMBOL_SURFACE_PRESENT:
		return rawptr(wgpu_test_surface_present)
	case WGPU_SYMBOL_SURFACE_UNCONFIGURE:
		return rawptr(wgpu_test_surface_unconfigure)
	case WGPU_SYMBOL_SURFACE_CAPABILITIES_FREE_MEMBERS:
		return rawptr(wgpu_test_surface_capabilities_free_members)
	case WGPU_SYMBOL_SURFACE_RELEASE:
		return rawptr(wgpu_test_surface_release)
	case WGPU_SYMBOL_TEXTURE_CREATE_VIEW:
		return rawptr(wgpu_test_texture_create_view)
	case WGPU_SYMBOL_COMMAND_ENCODER_COPY_TEXTURE_TO_BUFFER:
		return rawptr(wgpu_test_command_encoder_copy_texture_to_buffer)
	case WGPU_SYMBOL_COMMAND_ENCODER_BEGIN_RENDER_PASS:
		return rawptr(wgpu_test_command_encoder_begin_render_pass)
	case WGPU_SYMBOL_COMMAND_ENCODER_FINISH:
		return rawptr(wgpu_test_command_encoder_finish)
	case WGPU_SYMBOL_QUEUE_SUBMIT:
		return rawptr(wgpu_test_queue_submit)
	case WGPU_SYMBOL_QUEUE_WRITE_BUFFER:
		return rawptr(wgpu_test_queue_write_buffer)
	case WGPU_SYMBOL_QUEUE_WRITE_TEXTURE:
		return rawptr(wgpu_test_queue_write_texture)
	case WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_PIPELINE:
		return rawptr(wgpu_test_render_pass_encoder_set_pipeline)
	case WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_BIND_GROUP:
		return rawptr(wgpu_test_render_pass_encoder_set_bind_group)
	case WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_VERTEX_BUFFER:
		return rawptr(wgpu_test_render_pass_encoder_set_vertex_buffer)
	case WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_INDEX_BUFFER:
		return rawptr(wgpu_test_render_pass_encoder_set_index_buffer)
	case WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_VIEWPORT:
		return rawptr(wgpu_test_render_pass_encoder_set_viewport)
	case WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_SCISSOR_RECT:
		return rawptr(wgpu_test_render_pass_encoder_set_scissor_rect)
	case WGPU_SYMBOL_RENDER_PASS_ENCODER_DRAW:
		return rawptr(wgpu_test_render_pass_encoder_draw)
	case WGPU_SYMBOL_RENDER_PASS_ENCODER_DRAW_INDEXED:
		return rawptr(wgpu_test_render_pass_encoder_draw_indexed)
	case WGPU_SYMBOL_RENDER_PASS_ENCODER_END:
		return rawptr(wgpu_test_render_pass_encoder_end)
	case WGPU_SYMBOL_BUFFER_MAP_ASYNC:
		return rawptr(wgpu_test_buffer_map_async)
	case WGPU_SYMBOL_BUFFER_GET_MAPPED_RANGE:
		return rawptr(wgpu_test_buffer_get_mapped_range)
	case WGPU_SYMBOL_BUFFER_UNMAP:
		return rawptr(wgpu_test_buffer_unmap)
	case WGPU_SYMBOL_INSTANCE_PROCESS_EVENTS:
		return rawptr(wgpu_test_instance_process_events)
	case WGPU_SYMBOL_TEXTURE_RELEASE:
		return rawptr(wgpu_test_texture_release)
	case WGPU_SYMBOL_TEXTURE_VIEW_RELEASE:
		return rawptr(wgpu_test_texture_view_release)
	case WGPU_SYMBOL_BUFFER_RELEASE:
		return rawptr(wgpu_test_buffer_release)
	case WGPU_SYMBOL_BIND_GROUP_LAYOUT_RELEASE:
		return rawptr(wgpu_test_bind_group_layout_release)
	case WGPU_SYMBOL_PIPELINE_LAYOUT_RELEASE:
		return rawptr(wgpu_test_pipeline_layout_release)
	case WGPU_SYMBOL_SAMPLER_RELEASE:
		return rawptr(wgpu_test_sampler_release)
	case WGPU_SYMBOL_BIND_GROUP_RELEASE:
		return rawptr(wgpu_test_bind_group_release)
	case WGPU_SYMBOL_SHADER_MODULE_RELEASE:
		return rawptr(wgpu_test_shader_module_release)
	case WGPU_SYMBOL_RENDER_PIPELINE_RELEASE:
		return rawptr(wgpu_test_render_pipeline_release)
	case WGPU_SYMBOL_COMMAND_ENCODER_RELEASE:
		return rawptr(wgpu_test_command_encoder_release)
	case WGPU_SYMBOL_COMMAND_BUFFER_RELEASE:
		return rawptr(wgpu_test_command_buffer_release)
	case WGPU_SYMBOL_RENDER_PASS_ENCODER_RELEASE:
		return rawptr(wgpu_test_render_pass_encoder_release)
	case WGPU_SYMBOL_INSTANCE_RELEASE:
		return rawptr(wgpu_test_instance_release)
	case WGPU_SYMBOL_ADAPTER_RELEASE:
		return rawptr(wgpu_test_adapter_release)
	case WGPU_SYMBOL_DEVICE_RELEASE:
		return rawptr(wgpu_test_device_release)
	case WGPU_SYMBOL_QUEUE_RELEASE:
		return rawptr(wgpu_test_queue_release)
	}
	return nil
}

wgpu_test_create_instance :: proc "c" (descriptor: ^WGPU_Instance_Descriptor) -> WGPU_Instance {
	_ = descriptor
	return WGPU_Instance(rawptr(uintptr(0x100A)))
}

wgpu_test_instance_request_adapter :: proc "c" (instance: WGPU_Instance, options: ^WGPU_Request_Adapter_Options, callback_info: WGPU_Request_Adapter_Callback_Info) -> WGPU_Future {
	_ = instance
	_ = options
	_ = callback_info
	return WGPU_Future{id = 0x100B}
}

wgpu_test_adapter_request_device :: proc "c" (adapter: WGPU_Adapter, descriptor: ^WGPU_Device_Descriptor, callback_info: WGPU_Request_Device_Callback_Info) -> WGPU_Future {
	_ = adapter
	_ = descriptor
	_ = callback_info
	return WGPU_Future{id = 0x100C}
}

wgpu_test_device_get_queue :: proc "c" (device: WGPU_Device) -> WGPU_Queue {
	_ = device
	return WGPU_Queue(rawptr(uintptr(0x100D)))
}

wgpu_test_device_create_texture :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Texture_Descriptor) -> WGPU_Texture {
	_ = device
	_ = descriptor
	return WGPU_Texture(rawptr(uintptr(0x1001)))
}

wgpu_test_device_create_buffer :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Buffer_Descriptor) -> WGPU_Buffer {
	_ = device
	_ = descriptor
	return WGPU_Buffer(rawptr(uintptr(0x1002)))
}

wgpu_test_device_create_bind_group_layout :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Bind_Group_Layout_Descriptor) -> WGPU_Bind_Group_Layout {
	_ = device
	_ = descriptor
	return WGPU_Bind_Group_Layout(rawptr(uintptr(0x100F)))
}

wgpu_test_device_create_pipeline_layout :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Pipeline_Layout_Descriptor) -> WGPU_Pipeline_Layout {
	_ = device
	_ = descriptor
	return WGPU_Pipeline_Layout(rawptr(uintptr(0x1010)))
}

wgpu_test_device_create_sampler :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Sampler_Descriptor) -> WGPU_Sampler {
	_ = device
	_ = descriptor
	return WGPU_Sampler(rawptr(uintptr(0x1011)))
}

wgpu_test_device_create_bind_group :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Bind_Group_Descriptor) -> WGPU_Bind_Group {
	_ = device
	_ = descriptor
	return WGPU_Bind_Group(rawptr(uintptr(0x1012)))
}

wgpu_test_device_create_shader_module :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Shader_Module_Descriptor) -> WGPU_Shader_Module {
	_ = device
	_ = descriptor
	return WGPU_Shader_Module(rawptr(uintptr(0x1013)))
}

wgpu_test_device_create_render_pipeline :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Render_Pipeline_Descriptor) -> WGPU_Render_Pipeline {
	_ = device
	_ = descriptor
	return WGPU_Render_Pipeline(rawptr(uintptr(0x1014)))
}

wgpu_test_device_create_command_encoder :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Command_Encoder_Descriptor) -> WGPU_Command_Encoder {
	_ = device
	_ = descriptor
	return WGPU_Command_Encoder(rawptr(uintptr(0x1003)))
}

wgpu_test_instance_create_surface :: proc "c" (instance: WGPU_Instance, descriptor: ^WGPU_Surface_Descriptor) -> WGPU_Surface {
	_ = instance
	_ = descriptor
	return WGPU_Surface(rawptr(uintptr(0x1015)))
}

wgpu_test_surface_configure :: proc "c" (surface: WGPU_Surface, config: ^WGPU_Surface_Configuration) {
	_ = surface
	_ = config
}

wgpu_test_surface_get_capabilities :: proc "c" (surface: WGPU_Surface, adapter: WGPU_Adapter, capabilities: ^WGPU_Surface_Capabilities) -> WGPU_Status {
	_ = surface
	_ = adapter
	_ = capabilities
	return WGPU_STATUS_SUCCESS
}

wgpu_test_surface_get_current_texture :: proc "c" (surface: WGPU_Surface, surface_texture: ^WGPU_Surface_Texture) {
	_ = surface
	surface_texture.texture = WGPU_Texture(rawptr(uintptr(0x1016)))
	surface_texture.status = WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_OPTIMAL
}

wgpu_test_surface_present :: proc "c" (surface: WGPU_Surface) -> WGPU_Status {
	_ = surface
	return WGPU_STATUS_SUCCESS
}

wgpu_test_surface_unconfigure :: proc "c" (surface: WGPU_Surface) {
	_ = surface
}

wgpu_test_surface_capabilities_free_members :: proc "c" (capabilities: WGPU_Surface_Capabilities) {
	_ = capabilities
}

wgpu_test_surface_release :: proc "c" (surface: WGPU_Surface) {
	_ = surface
}

wgpu_test_texture_create_view :: proc "c" (texture: WGPU_Texture, descriptor: ^WGPU_Texture_View_Descriptor) -> WGPU_Texture_View {
	_ = texture
	_ = descriptor
	return WGPU_Texture_View(rawptr(uintptr(0x1004)))
}

wgpu_test_command_encoder_copy_texture_to_buffer :: proc "c" (encoder: WGPU_Command_Encoder, source: ^WGPU_Texel_Copy_Texture_Info, destination: ^WGPU_Texel_Copy_Buffer_Info, copy_size: ^WGPU_Extent_3D) {
	_ = encoder
	_ = source
	_ = destination
	_ = copy_size
}

wgpu_test_command_encoder_begin_render_pass :: proc "c" (encoder: WGPU_Command_Encoder, descriptor: ^WGPU_Render_Pass_Descriptor) -> WGPU_Render_Pass_Encoder {
	_ = encoder
	_ = descriptor
	return WGPU_Render_Pass_Encoder(rawptr(uintptr(0x100E)))
}

wgpu_test_command_encoder_finish :: proc "c" (encoder: WGPU_Command_Encoder, descriptor: ^WGPU_Command_Buffer_Descriptor) -> WGPU_Command_Buffer {
	_ = encoder
	_ = descriptor
	return WGPU_Command_Buffer(rawptr(uintptr(0x1006)))
}

wgpu_test_queue_submit :: proc "c" (queue: WGPU_Queue, command_count: c.size_t, commands: [^]WGPU_Command_Buffer) {
	_ = queue
	_ = command_count
	_ = commands
}

wgpu_test_queue_write_buffer :: proc "c" (queue: WGPU_Queue, buffer: WGPU_Buffer, buffer_offset: u64, data: rawptr, size: c.size_t) {
	_ = queue
	_ = buffer
	_ = buffer_offset
	_ = data
	_ = size
}

wgpu_test_queue_write_texture :: proc "c" (queue: WGPU_Queue, destination: ^WGPU_Texel_Copy_Texture_Info, data: rawptr, data_size: c.size_t, data_layout: ^WGPU_Texel_Copy_Buffer_Layout, write_size: ^WGPU_Extent_3D) {
	_ = queue
	_ = destination
	_ = data
	_ = data_size
	_ = data_layout
	_ = write_size
}

wgpu_test_render_pass_encoder_set_pipeline :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, pipeline: WGPU_Render_Pipeline) {
	_ = render_pass
	_ = pipeline
}

wgpu_test_render_pass_encoder_set_bind_group :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, group_index: u32, group: WGPU_Bind_Group, dynamic_offset_count: c.size_t, dynamic_offsets: [^]u32) {
	_ = render_pass
	_ = group_index
	_ = group
	_ = dynamic_offset_count
	_ = dynamic_offsets
}

wgpu_test_render_pass_encoder_set_vertex_buffer :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, slot: u32, buffer: WGPU_Buffer, offset, size: u64) {
	_ = render_pass
	_ = slot
	_ = buffer
	_ = offset
	_ = size
}

wgpu_test_render_pass_encoder_set_index_buffer :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, buffer: WGPU_Buffer, format: WGPU_Index_Format, offset, size: u64) {
	_ = render_pass
	_ = buffer
	_ = format
	_ = offset
	_ = size
}

wgpu_test_render_pass_encoder_set_viewport :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, x, y, width, height, min_depth, max_depth: f32) {
	_ = render_pass
	_ = x
	_ = y
	_ = width
	_ = height
	_ = min_depth
	_ = max_depth
}

wgpu_test_render_pass_encoder_set_scissor_rect :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, x, y, width, height: u32) {
	_ = render_pass
	_ = x
	_ = y
	_ = width
	_ = height
}

wgpu_test_render_pass_encoder_draw :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, vertex_count, instance_count, first_vertex, first_instance: u32) {
	_ = render_pass
	_ = vertex_count
	_ = instance_count
	_ = first_vertex
	_ = first_instance
}

wgpu_test_render_pass_encoder_draw_indexed :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, index_count, instance_count, first_index: u32, base_vertex: i32, first_instance: u32) {
	_ = render_pass
	_ = index_count
	_ = instance_count
	_ = first_index
	_ = base_vertex
	_ = first_instance
}

wgpu_test_render_pass_encoder_end :: proc "c" (render_pass: WGPU_Render_Pass_Encoder) {
	_ = render_pass
}

wgpu_test_buffer_map_async :: proc "c" (buffer: WGPU_Buffer, mode: WGPU_Map_Mode, offset, size: c.size_t, callback_info: WGPU_Buffer_Map_Callback_Info) -> WGPU_Future {
	_ = buffer
	_ = mode
	_ = offset
	_ = size
	_ = callback_info
	return WGPU_Future{id = 0x1008}
}

wgpu_test_buffer_get_mapped_range :: proc "c" (buffer: WGPU_Buffer, offset, size: c.size_t) -> rawptr {
	_ = buffer
	_ = offset
	_ = size
	return rawptr(uintptr(0x1009))
}

wgpu_test_buffer_unmap :: proc "c" (buffer: WGPU_Buffer) {
	_ = buffer
}

wgpu_test_instance_process_events :: proc "c" (instance: WGPU_Instance) {
	_ = instance
}

wgpu_test_texture_release :: proc "c" (texture: WGPU_Texture) {
	_ = texture
}

wgpu_test_texture_view_release :: proc "c" (texture_view: WGPU_Texture_View) {
	_ = texture_view
}

wgpu_test_buffer_release :: proc "c" (buffer: WGPU_Buffer) {
	_ = buffer
}

wgpu_test_bind_group_layout_release :: proc "c" (bind_group_layout: WGPU_Bind_Group_Layout) {
	_ = bind_group_layout
}

wgpu_test_pipeline_layout_release :: proc "c" (pipeline_layout: WGPU_Pipeline_Layout) {
	_ = pipeline_layout
}

wgpu_test_sampler_release :: proc "c" (sampler: WGPU_Sampler) {
	_ = sampler
}

wgpu_test_bind_group_release :: proc "c" (bind_group: WGPU_Bind_Group) {
	_ = bind_group
}

wgpu_test_shader_module_release :: proc "c" (shader_module: WGPU_Shader_Module) {
	_ = shader_module
}

wgpu_test_render_pipeline_release :: proc "c" (pipeline: WGPU_Render_Pipeline) {
	_ = pipeline
}

wgpu_test_command_encoder_release :: proc "c" (encoder: WGPU_Command_Encoder) {
	_ = encoder
}

wgpu_test_command_buffer_release :: proc "c" (command_buffer: WGPU_Command_Buffer) {
	_ = command_buffer
}

wgpu_test_render_pass_encoder_release :: proc "c" (render_pass: WGPU_Render_Pass_Encoder) {
	_ = render_pass
}

wgpu_test_instance_release :: proc "c" (instance: WGPU_Instance) {
	_ = instance
}

wgpu_test_adapter_release :: proc "c" (adapter: WGPU_Adapter) {
	_ = adapter
}

wgpu_test_device_release :: proc "c" (device: WGPU_Device) {
	_ = device
}

wgpu_test_queue_release :: proc "c" (queue: WGPU_Queue) {
	_ = queue
}

@(test)
test_wgpu_platform_surface_stype_values_match_vendored_binding :: proc(t: ^testing.T) {
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_METAL_LAYER, WGPU_SType(0x00000004))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_WINDOWS_HWND, WGPU_SType(0x00000005))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_XLIB_WINDOW, WGPU_SType(0x00000006))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_WAYLAND_SURFACE, WGPU_SType(0x00000007))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_XCB_WINDOW, WGPU_SType(0x00000009))
}
