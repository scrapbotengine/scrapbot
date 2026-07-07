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

@(test)
test_wgpu_offscreen_proc_table_resolves_required_symbols :: proc(t: ^testing.T) {
	ctx := WGPU_Test_Resolver_Context{}
	procs, missing, ok := wgpu_resolve_offscreen_procs(wgpu_test_symbol_resolver, rawptr(&ctx))

	testing.expect_value(t, ok, true)
	testing.expect_value(t, missing, "")
	testing.expect_value(t, ctx.calls, 16)
	testing.expect_value(t, ctx.last_user_data, rawptr(&ctx))

	texture := procs.device_create_texture(WGPU_Device(nil), (^WGPU_Texture_Descriptor)(nil))
	testing.expect_value(t, texture, WGPU_Texture(rawptr(uintptr(0x1001))))

	command_buffer := procs.command_encoder_finish(WGPU_Command_Encoder(nil), (^WGPU_Command_Buffer_Descriptor)(nil))
	testing.expect_value(t, command_buffer, WGPU_Command_Buffer(rawptr(uintptr(0x1006))))

	future := procs.buffer_map_async(WGPU_Buffer(nil), WGPU_MAP_MODE_READ, 0, 16, wgpu_buffer_map_callback_info(wgpu_test_buffer_map_callback))
	testing.expect_value(t, future, WGPU_Future{id = 0x1008})
}

@(test)
test_wgpu_offscreen_proc_table_reports_first_missing_symbol :: proc(t: ^testing.T) {
	ctx := WGPU_Test_Resolver_Context{missing = WGPU_SYMBOL_COMMAND_ENCODER_FINISH}
	_, missing, ok := wgpu_resolve_offscreen_procs(wgpu_test_symbol_resolver, rawptr(&ctx))

	testing.expect_value(t, ok, false)
	testing.expect_value(t, missing, WGPU_SYMBOL_COMMAND_ENCODER_FINISH)
	testing.expect_value(t, ctx.calls, 6)
}

wgpu_test_buffer_map_callback :: proc "c" (status: WGPU_Map_Async_Status, message: WGPU_String_View, userdata1, userdata2: rawptr) {
	_ = status
	_ = message
	_ = userdata1
	_ = userdata2
}

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
	case WGPU_SYMBOL_DEVICE_CREATE_TEXTURE:
		return rawptr(wgpu_test_device_create_texture)
	case WGPU_SYMBOL_DEVICE_CREATE_BUFFER:
		return rawptr(wgpu_test_device_create_buffer)
	case WGPU_SYMBOL_DEVICE_CREATE_COMMAND_ENCODER:
		return rawptr(wgpu_test_device_create_command_encoder)
	case WGPU_SYMBOL_TEXTURE_CREATE_VIEW:
		return rawptr(wgpu_test_texture_create_view)
	case WGPU_SYMBOL_COMMAND_ENCODER_COPY_TEXTURE_TO_BUFFER:
		return rawptr(wgpu_test_command_encoder_copy_texture_to_buffer)
	case WGPU_SYMBOL_COMMAND_ENCODER_FINISH:
		return rawptr(wgpu_test_command_encoder_finish)
	case WGPU_SYMBOL_QUEUE_SUBMIT:
		return rawptr(wgpu_test_queue_submit)
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
	case WGPU_SYMBOL_COMMAND_ENCODER_RELEASE:
		return rawptr(wgpu_test_command_encoder_release)
	case WGPU_SYMBOL_COMMAND_BUFFER_RELEASE:
		return rawptr(wgpu_test_command_buffer_release)
	}
	return nil
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

wgpu_test_device_create_command_encoder :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Command_Encoder_Descriptor) -> WGPU_Command_Encoder {
	_ = device
	_ = descriptor
	return WGPU_Command_Encoder(rawptr(uintptr(0x1003)))
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

wgpu_test_command_encoder_release :: proc "c" (encoder: WGPU_Command_Encoder) {
	_ = encoder
}

wgpu_test_command_buffer_release :: proc "c" (command_buffer: WGPU_Command_Buffer) {
	_ = command_buffer
}

@(test)
test_wgpu_platform_surface_stype_values_match_vendored_binding :: proc(t: ^testing.T) {
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_METAL_LAYER, WGPU_SType(0x00000004))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_WINDOWS_HWND, WGPU_SType(0x00000005))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_XLIB_WINDOW, WGPU_SType(0x00000006))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_WAYLAND_SURFACE, WGPU_SType(0x00000007))
	testing.expect_value(t, WGPU_STYPE_SURFACE_SOURCE_XCB_WINDOW, WGPU_SType(0x00000009))
}
