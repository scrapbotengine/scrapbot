package main

import "core:c"

// First-pass wgpu-native C ABI surface used by the Odin renderer migration.
// This file intentionally avoids foreign procedure declarations until the Odin
// build owns platform-specific wgpu-native linking.

WGPU_U32_MAX :: u32(~u32(0))
WGPU_U64_MAX :: u64(~u64(0))
WGPU_USIZE_MAX :: uint(~uint(0))

WGPU_WHOLE_SIZE :: WGPU_U64_MAX
WGPU_STRLEN :: c.size_t(WGPU_USIZE_MAX)

WGPU_Bool :: u32
WGPU_Flags :: u64
WGPU_Buffer_Usage :: WGPU_Flags
WGPU_Texture_Usage :: WGPU_Flags
WGPU_Texture_Format :: u32
WGPU_Texture_Dimension :: u32
WGPU_Texture_View_Dimension :: u32
WGPU_Texture_Aspect :: u32
WGPU_Map_Mode :: WGPU_Flags
WGPU_Callback_Mode :: u32
WGPU_SType :: u32
WGPU_Status :: u32
WGPU_Optional_Bool :: u32
WGPU_Map_Async_Status :: u32

WGPU_Instance :: rawptr
WGPU_Adapter :: rawptr
WGPU_Device :: rawptr
WGPU_Queue :: rawptr
WGPU_Surface :: rawptr
WGPU_Texture :: rawptr
WGPU_Texture_View :: rawptr
WGPU_Buffer :: rawptr
WGPU_Shader_Module :: rawptr
WGPU_Render_Pipeline :: rawptr
WGPU_Pipeline_Layout :: rawptr
WGPU_Bind_Group :: rawptr
WGPU_Bind_Group_Layout :: rawptr
WGPU_Command_Encoder :: rawptr
WGPU_Command_Buffer :: rawptr
WGPU_Render_Pass_Encoder :: rawptr

WGPU_FALSE :: WGPU_Bool(0)
WGPU_TRUE :: WGPU_Bool(1)

WGPU_STATUS_SUCCESS :: WGPU_Status(0x00000001)
WGPU_STATUS_ERROR :: WGPU_Status(0x00000002)

WGPU_OPTIONAL_BOOL_FALSE :: WGPU_Optional_Bool(0x00000000)
WGPU_OPTIONAL_BOOL_TRUE :: WGPU_Optional_Bool(0x00000001)
WGPU_OPTIONAL_BOOL_UNDEFINED :: WGPU_Optional_Bool(0x00000002)

WGPU_MAP_ASYNC_STATUS_SUCCESS :: WGPU_Map_Async_Status(0x00000001)
WGPU_MAP_ASYNC_STATUS_INSTANCE_DROPPED :: WGPU_Map_Async_Status(0x00000002)
WGPU_MAP_ASYNC_STATUS_ERROR :: WGPU_Map_Async_Status(0x00000003)
WGPU_MAP_ASYNC_STATUS_ABORTED :: WGPU_Map_Async_Status(0x00000004)
WGPU_MAP_ASYNC_STATUS_UNKNOWN :: WGPU_Map_Async_Status(0x00000005)

WGPU_CALLBACK_MODE_WAIT_ANY_ONLY :: WGPU_Callback_Mode(0x00000001)
WGPU_CALLBACK_MODE_ALLOW_PROCESS_EVENTS :: WGPU_Callback_Mode(0x00000002)
WGPU_CALLBACK_MODE_ALLOW_SPONTANEOUS :: WGPU_Callback_Mode(0x00000003)

WGPU_STYPE_SHADER_SOURCE_SPIRV :: WGPU_SType(0x00000001)
WGPU_STYPE_SHADER_SOURCE_WGSL :: WGPU_SType(0x00000002)
WGPU_STYPE_RENDER_PASS_MAX_DRAW_COUNT :: WGPU_SType(0x00000003)
WGPU_STYPE_SURFACE_SOURCE_METAL_LAYER :: WGPU_SType(0x00000004)
WGPU_STYPE_SURFACE_SOURCE_WINDOWS_HWND :: WGPU_SType(0x00000005)
WGPU_STYPE_SURFACE_SOURCE_XLIB_WINDOW :: WGPU_SType(0x00000006)
WGPU_STYPE_SURFACE_SOURCE_WAYLAND_SURFACE :: WGPU_SType(0x00000007)
WGPU_STYPE_SURFACE_SOURCE_ANDROID_NATIVE_WINDOW :: WGPU_SType(0x00000008)
WGPU_STYPE_SURFACE_SOURCE_XCB_WINDOW :: WGPU_SType(0x00000009)

WGPU_STYPE_DEVICE_EXTRAS :: WGPU_SType(0x00030001)
WGPU_STYPE_NATIVE_LIMITS :: WGPU_SType(0x00030002)
WGPU_STYPE_PIPELINE_LAYOUT_EXTRAS :: WGPU_SType(0x00030003)
WGPU_STYPE_SHADER_SOURCE_GLSL :: WGPU_SType(0x00030004)
WGPU_STYPE_INSTANCE_EXTRAS :: WGPU_SType(0x00030006)
WGPU_STYPE_BIND_GROUP_ENTRY_EXTRAS :: WGPU_SType(0x00030007)
WGPU_STYPE_BIND_GROUP_LAYOUT_ENTRY_EXTRAS :: WGPU_SType(0x00030008)
WGPU_STYPE_QUERY_SET_DESCRIPTOR_EXTRAS :: WGPU_SType(0x00030009)
WGPU_STYPE_SURFACE_CONFIGURATION_EXTRAS :: WGPU_SType(0x0003000A)

WGPU_TEXTURE_FORMAT_UNDEFINED :: WGPU_Texture_Format(0x00000000)
WGPU_TEXTURE_FORMAT_RGBA8_UNORM :: WGPU_Texture_Format(0x00000012)
WGPU_TEXTURE_FORMAT_RGBA8_UNORM_SRGB :: WGPU_Texture_Format(0x00000013)
WGPU_TEXTURE_FORMAT_BGRA8_UNORM :: WGPU_Texture_Format(0x00000017)
WGPU_TEXTURE_FORMAT_BGRA8_UNORM_SRGB :: WGPU_Texture_Format(0x00000018)
WGPU_TEXTURE_FORMAT_DEPTH24_PLUS :: WGPU_Texture_Format(0x00000028)
WGPU_TEXTURE_FORMAT_DEPTH24_PLUS_STENCIL8 :: WGPU_Texture_Format(0x00000029)
WGPU_TEXTURE_FORMAT_DEPTH32_FLOAT :: WGPU_Texture_Format(0x0000002A)
WGPU_TEXTURE_FORMAT_DEPTH32_FLOAT_STENCIL8 :: WGPU_Texture_Format(0x0000002B)

WGPU_TEXTURE_DIMENSION_UNDEFINED :: WGPU_Texture_Dimension(0x00000000)
WGPU_TEXTURE_DIMENSION_1D :: WGPU_Texture_Dimension(0x00000001)
WGPU_TEXTURE_DIMENSION_2D :: WGPU_Texture_Dimension(0x00000002)
WGPU_TEXTURE_DIMENSION_3D :: WGPU_Texture_Dimension(0x00000003)

WGPU_TEXTURE_VIEW_DIMENSION_UNDEFINED :: WGPU_Texture_View_Dimension(0x00000000)
WGPU_TEXTURE_VIEW_DIMENSION_1D :: WGPU_Texture_View_Dimension(0x00000001)
WGPU_TEXTURE_VIEW_DIMENSION_2D :: WGPU_Texture_View_Dimension(0x00000002)
WGPU_TEXTURE_VIEW_DIMENSION_2D_ARRAY :: WGPU_Texture_View_Dimension(0x00000003)
WGPU_TEXTURE_VIEW_DIMENSION_CUBE :: WGPU_Texture_View_Dimension(0x00000004)
WGPU_TEXTURE_VIEW_DIMENSION_CUBE_ARRAY :: WGPU_Texture_View_Dimension(0x00000005)
WGPU_TEXTURE_VIEW_DIMENSION_3D :: WGPU_Texture_View_Dimension(0x00000006)

WGPU_TEXTURE_ASPECT_UNDEFINED :: WGPU_Texture_Aspect(0x00000000)
WGPU_TEXTURE_ASPECT_ALL :: WGPU_Texture_Aspect(0x00000001)
WGPU_TEXTURE_ASPECT_STENCIL_ONLY :: WGPU_Texture_Aspect(0x00000002)
WGPU_TEXTURE_ASPECT_DEPTH_ONLY :: WGPU_Texture_Aspect(0x00000003)

WGPU_BUFFER_USAGE_NONE :: WGPU_Buffer_Usage(0x0000000000000000)
WGPU_BUFFER_USAGE_MAP_READ :: WGPU_Buffer_Usage(0x0000000000000001)
WGPU_BUFFER_USAGE_MAP_WRITE :: WGPU_Buffer_Usage(0x0000000000000002)
WGPU_BUFFER_USAGE_COPY_SRC :: WGPU_Buffer_Usage(0x0000000000000004)
WGPU_BUFFER_USAGE_COPY_DST :: WGPU_Buffer_Usage(0x0000000000000008)
WGPU_BUFFER_USAGE_INDEX :: WGPU_Buffer_Usage(0x0000000000000010)
WGPU_BUFFER_USAGE_VERTEX :: WGPU_Buffer_Usage(0x0000000000000020)
WGPU_BUFFER_USAGE_UNIFORM :: WGPU_Buffer_Usage(0x0000000000000040)
WGPU_BUFFER_USAGE_STORAGE :: WGPU_Buffer_Usage(0x0000000000000080)
WGPU_BUFFER_USAGE_INDIRECT :: WGPU_Buffer_Usage(0x0000000000000100)
WGPU_BUFFER_USAGE_QUERY_RESOLVE :: WGPU_Buffer_Usage(0x0000000000000200)

WGPU_MAP_MODE_NONE :: WGPU_Map_Mode(0x0000000000000000)
WGPU_MAP_MODE_READ :: WGPU_Map_Mode(0x0000000000000001)
WGPU_MAP_MODE_WRITE :: WGPU_Map_Mode(0x0000000000000002)

WGPU_TEXTURE_USAGE_NONE :: WGPU_Texture_Usage(0x0000000000000000)
WGPU_TEXTURE_USAGE_COPY_SRC :: WGPU_Texture_Usage(0x0000000000000001)
WGPU_TEXTURE_USAGE_COPY_DST :: WGPU_Texture_Usage(0x0000000000000002)
WGPU_TEXTURE_USAGE_TEXTURE_BINDING :: WGPU_Texture_Usage(0x0000000000000004)
WGPU_TEXTURE_USAGE_STORAGE_BINDING :: WGPU_Texture_Usage(0x0000000000000008)
WGPU_TEXTURE_USAGE_RENDER_ATTACHMENT :: WGPU_Texture_Usage(0x0000000000000010)

WGPU_DEFAULT_TARGET_FORMAT :: WGPU_TEXTURE_FORMAT_BGRA8_UNORM_SRGB
WGPU_DEPTH_FORMAT :: WGPU_TEXTURE_FORMAT_DEPTH24_PLUS
WGPU_SHADOW_DEPTH_FORMAT :: WGPU_TEXTURE_FORMAT_DEPTH32_FLOAT
WGPU_ARRAY_LAYER_COUNT_UNDEFINED :: WGPU_U32_MAX
WGPU_MIP_LEVEL_COUNT_UNDEFINED :: WGPU_U32_MAX
WGPU_COPY_STRIDE_UNDEFINED :: WGPU_U32_MAX

WGPU_String_View :: struct #align(align_of(rawptr)) {
	data:   rawptr,
	length: c.size_t,
}

WGPU_Chained_Struct :: struct #align(align_of(rawptr)) {
	next:   ^WGPU_Chained_Struct,
	s_type: WGPU_SType,
}

WGPU_Chained_Struct_Out :: struct #align(align_of(rawptr)) {
	next:   ^WGPU_Chained_Struct_Out,
	s_type: WGPU_SType,
}

WGPU_Future :: struct {
	id: u64,
}

WGPU_Extent_3D :: struct {
	width:                 u32,
	height:                u32,
	depth_or_array_layers: u32,
}

WGPU_Origin_3D :: struct {
	x: u32,
	y: u32,
	z: u32,
}

WGPU_Buffer_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain:      ^WGPU_Chained_Struct,
	label:              WGPU_String_View,
	usage:              WGPU_Buffer_Usage,
	size:               u64,
	mapped_at_creation: WGPU_Bool,
}

WGPU_Texture_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain:    ^WGPU_Chained_Struct,
	label:            WGPU_String_View,
	usage:            WGPU_Texture_Usage,
	dimension:        WGPU_Texture_Dimension,
	size:             WGPU_Extent_3D,
	format:           WGPU_Texture_Format,
	mip_level_count:  u32,
	sample_count:     u32,
	view_format_count: c.size_t,
	view_formats:     rawptr,
}

WGPU_Texture_View_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain:    ^WGPU_Chained_Struct,
	label:            WGPU_String_View,
	format:           WGPU_Texture_Format,
	dimension:        WGPU_Texture_View_Dimension,
	base_mip_level:   u32,
	mip_level_count:  u32,
	base_array_layer: u32,
	array_layer_count: u32,
	aspect:           WGPU_Texture_Aspect,
	usage:            WGPU_Texture_Usage,
}

WGPU_Texel_Copy_Texture_Info :: struct #align(align_of(rawptr)) {
	texture:   WGPU_Texture,
	mip_level: u32,
	origin:    WGPU_Origin_3D,
	aspect:    WGPU_Texture_Aspect,
}

WGPU_Texel_Copy_Buffer_Layout :: struct {
	offset:         u64,
	bytes_per_row:  u32,
	rows_per_image: u32,
}

WGPU_Texel_Copy_Buffer_Info :: struct #align(align_of(rawptr)) {
	layout: WGPU_Texel_Copy_Buffer_Layout,
	buffer: WGPU_Buffer,
}

WGPU_Command_Encoder_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	label:         WGPU_String_View,
}

WGPU_Command_Buffer_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	label:         WGPU_String_View,
}

WGPU_Buffer_Map_Callback :: proc "c" (status: WGPU_Map_Async_Status, message: WGPU_String_View, userdata1, userdata2: rawptr)

WGPU_Buffer_Map_Callback_Info :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	mode:          WGPU_Callback_Mode,
	callback:      WGPU_Buffer_Map_Callback,
	userdata1:     rawptr,
	userdata2:     rawptr,
}

WGPU_Device_Create_Texture_Proc :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Texture_Descriptor) -> WGPU_Texture
WGPU_Device_Create_Buffer_Proc :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Buffer_Descriptor) -> WGPU_Buffer
WGPU_Device_Create_Command_Encoder_Proc :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Command_Encoder_Descriptor) -> WGPU_Command_Encoder
WGPU_Texture_Create_View_Proc :: proc "c" (texture: WGPU_Texture, descriptor: ^WGPU_Texture_View_Descriptor) -> WGPU_Texture_View
WGPU_Command_Encoder_Copy_Texture_To_Buffer_Proc :: proc "c" (encoder: WGPU_Command_Encoder, source: ^WGPU_Texel_Copy_Texture_Info, destination: ^WGPU_Texel_Copy_Buffer_Info, copy_size: ^WGPU_Extent_3D)
WGPU_Command_Encoder_Finish_Proc :: proc "c" (encoder: WGPU_Command_Encoder, descriptor: ^WGPU_Command_Buffer_Descriptor) -> WGPU_Command_Buffer
WGPU_Queue_Submit_Proc :: proc "c" (queue: WGPU_Queue, command_count: c.size_t, commands: [^]WGPU_Command_Buffer)
WGPU_Buffer_Map_Async_Proc :: proc "c" (buffer: WGPU_Buffer, mode: WGPU_Map_Mode, offset, size: c.size_t, callback_info: WGPU_Buffer_Map_Callback_Info) -> WGPU_Future
WGPU_Buffer_Get_Mapped_Range_Proc :: proc "c" (buffer: WGPU_Buffer, offset, size: c.size_t) -> rawptr
WGPU_Buffer_Unmap_Proc :: proc "c" (buffer: WGPU_Buffer)
WGPU_Instance_Process_Events_Proc :: proc "c" (instance: WGPU_Instance)
WGPU_Texture_Release_Proc :: proc "c" (texture: WGPU_Texture)
WGPU_Texture_View_Release_Proc :: proc "c" (texture_view: WGPU_Texture_View)
WGPU_Buffer_Release_Proc :: proc "c" (buffer: WGPU_Buffer)
WGPU_Command_Encoder_Release_Proc :: proc "c" (encoder: WGPU_Command_Encoder)
WGPU_Command_Buffer_Release_Proc :: proc "c" (command_buffer: WGPU_Command_Buffer)

wgpu_string_view_null :: proc() -> WGPU_String_View {
	return WGPU_String_View{data = nil, length = WGPU_STRLEN}
}

wgpu_string_view_empty :: proc() -> WGPU_String_View {
	return WGPU_String_View{data = nil, length = 0}
}

wgpu_string_view_from_raw :: proc(data: rawptr, length: c.size_t) -> WGPU_String_View {
	return WGPU_String_View{data = data, length = length}
}

wgpu_extent_3d :: proc(width, height: u32, depth_or_array_layers: u32 = 1) -> WGPU_Extent_3D {
	return WGPU_Extent_3D{
		width = width,
		height = height,
		depth_or_array_layers = depth_or_array_layers,
	}
}

wgpu_origin_3d_zero :: proc() -> WGPU_Origin_3D {
	return WGPU_Origin_3D{}
}

wgpu_texture_descriptor_2d :: proc(label: WGPU_String_View, width, height: u32, format: WGPU_Texture_Format, usage: WGPU_Texture_Usage) -> WGPU_Texture_Descriptor {
	return WGPU_Texture_Descriptor{
		next_in_chain = nil,
		label = label,
		usage = usage,
		dimension = WGPU_TEXTURE_DIMENSION_2D,
		size = wgpu_extent_3d(width, height),
		format = format,
		mip_level_count = 1,
		sample_count = 1,
		view_format_count = 0,
		view_formats = nil,
	}
}

wgpu_texture_view_descriptor_default :: proc(label: WGPU_String_View) -> WGPU_Texture_View_Descriptor {
	return WGPU_Texture_View_Descriptor{
		next_in_chain = nil,
		label = label,
		format = WGPU_TEXTURE_FORMAT_UNDEFINED,
		dimension = WGPU_TEXTURE_VIEW_DIMENSION_UNDEFINED,
		base_mip_level = 0,
		mip_level_count = WGPU_MIP_LEVEL_COUNT_UNDEFINED,
		base_array_layer = 0,
		array_layer_count = WGPU_ARRAY_LAYER_COUNT_UNDEFINED,
		aspect = WGPU_TEXTURE_ASPECT_ALL,
		usage = WGPU_TEXTURE_USAGE_NONE,
	}
}

wgpu_single_mip_texture_view_descriptor :: proc(label: WGPU_String_View) -> WGPU_Texture_View_Descriptor {
	descriptor := wgpu_texture_view_descriptor_default(label)
	descriptor.mip_level_count = 1
	descriptor.array_layer_count = 1
	return descriptor
}

wgpu_buffer_descriptor :: proc(label: WGPU_String_View, usage: WGPU_Buffer_Usage, size: u64, mapped_at_creation: bool = false) -> WGPU_Buffer_Descriptor {
	mapped := WGPU_FALSE
	if mapped_at_creation {
		mapped = WGPU_TRUE
	}
	return WGPU_Buffer_Descriptor{
		next_in_chain = nil,
		label = label,
		usage = usage,
		size = size,
		mapped_at_creation = mapped,
	}
}

wgpu_texel_copy_texture_info :: proc(texture: WGPU_Texture) -> WGPU_Texel_Copy_Texture_Info {
	return WGPU_Texel_Copy_Texture_Info{
		texture = texture,
		mip_level = 0,
		origin = wgpu_origin_3d_zero(),
		aspect = WGPU_TEXTURE_ASPECT_ALL,
	}
}

wgpu_texel_copy_buffer_info :: proc(buffer: WGPU_Buffer, bytes_per_row, rows_per_image: u32) -> WGPU_Texel_Copy_Buffer_Info {
	return WGPU_Texel_Copy_Buffer_Info{
		layout = WGPU_Texel_Copy_Buffer_Layout{
			offset = 0,
			bytes_per_row = bytes_per_row,
			rows_per_image = rows_per_image,
		},
		buffer = buffer,
	}
}

wgpu_command_encoder_descriptor :: proc(label: WGPU_String_View) -> WGPU_Command_Encoder_Descriptor {
	return WGPU_Command_Encoder_Descriptor{next_in_chain = nil, label = label}
}

wgpu_command_buffer_descriptor :: proc(label: WGPU_String_View) -> WGPU_Command_Buffer_Descriptor {
	return WGPU_Command_Buffer_Descriptor{next_in_chain = nil, label = label}
}

wgpu_buffer_map_callback_info :: proc(callback: WGPU_Buffer_Map_Callback, userdata1: rawptr = nil, userdata2: rawptr = nil) -> WGPU_Buffer_Map_Callback_Info {
	return WGPU_Buffer_Map_Callback_Info{
		next_in_chain = nil,
		mode = WGPU_CALLBACK_MODE_ALLOW_PROCESS_EVENTS,
		callback = callback,
		userdata1 = userdata1,
		userdata2 = userdata2,
	}
}

wgpu_offscreen_texture_usage :: proc() -> WGPU_Texture_Usage {
	return WGPU_TEXTURE_USAGE_RENDER_ATTACHMENT | WGPU_TEXTURE_USAGE_COPY_SRC
}

wgpu_staging_buffer_usage :: proc() -> WGPU_Buffer_Usage {
	return WGPU_BUFFER_USAGE_MAP_READ | WGPU_BUFFER_USAGE_COPY_DST
}
