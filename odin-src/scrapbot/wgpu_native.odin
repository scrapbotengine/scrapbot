package main

import "core:c"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

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
WGPU_Index_Format :: u32
WGPU_Load_Op :: u32
WGPU_Store_Op :: u32
WGPU_Shader_Stage :: WGPU_Flags
WGPU_Buffer_Binding_Type :: u32
WGPU_Sampler_Binding_Type :: u32
WGPU_Texture_Sample_Type :: u32
WGPU_Storage_Texture_Access :: u32
WGPU_Address_Mode :: u32
WGPU_Filter_Mode :: u32
WGPU_Mipmap_Filter_Mode :: u32
WGPU_Compare_Function :: u32
WGPU_Vertex_Step_Mode :: u32
WGPU_Vertex_Format :: u32
WGPU_Primitive_Topology :: u32
WGPU_Front_Face :: u32
WGPU_Cull_Mode :: u32
WGPU_Stencil_Operation :: u32
WGPU_Blend_Operation :: u32
WGPU_Blend_Factor :: u32
WGPU_Color_Write_Mask :: WGPU_Flags
WGPU_Feature_Level :: u32
WGPU_Power_Preference :: u32
WGPU_Backend_Type :: u32
WGPU_Request_Adapter_Status :: u32
WGPU_Request_Device_Status :: u32
WGPU_Device_Lost_Reason :: u32
WGPU_Error_Type :: u32
WGPU_Composite_Alpha_Mode :: u32
WGPU_Present_Mode :: u32
WGPU_Surface_Get_Current_Texture_Status :: u32
WGPU_Feature_Name :: u32
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
WGPU_Sampler :: rawptr
WGPU_Command_Encoder :: rawptr
WGPU_Command_Buffer :: rawptr
WGPU_Render_Pass_Encoder :: rawptr
WGPU_Limits :: rawptr
WGPU_Query_Set :: rawptr

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

WGPU_INDEX_FORMAT_UNDEFINED :: WGPU_Index_Format(0x00000000)
WGPU_INDEX_FORMAT_UINT16 :: WGPU_Index_Format(0x00000001)
WGPU_INDEX_FORMAT_UINT32 :: WGPU_Index_Format(0x00000002)

WGPU_LOAD_OP_UNDEFINED :: WGPU_Load_Op(0x00000000)
WGPU_LOAD_OP_LOAD :: WGPU_Load_Op(0x00000001)
WGPU_LOAD_OP_CLEAR :: WGPU_Load_Op(0x00000002)

WGPU_STORE_OP_UNDEFINED :: WGPU_Store_Op(0x00000000)
WGPU_STORE_OP_STORE :: WGPU_Store_Op(0x00000001)
WGPU_STORE_OP_DISCARD :: WGPU_Store_Op(0x00000002)

WGPU_SHADER_STAGE_NONE :: WGPU_Shader_Stage(0x0000000000000000)
WGPU_SHADER_STAGE_VERTEX :: WGPU_Shader_Stage(0x0000000000000001)
WGPU_SHADER_STAGE_FRAGMENT :: WGPU_Shader_Stage(0x0000000000000002)
WGPU_SHADER_STAGE_COMPUTE :: WGPU_Shader_Stage(0x0000000000000004)

WGPU_BUFFER_BINDING_TYPE_BINDING_NOT_USED :: WGPU_Buffer_Binding_Type(0x00000000)
WGPU_BUFFER_BINDING_TYPE_UNDEFINED :: WGPU_Buffer_Binding_Type(0x00000001)
WGPU_BUFFER_BINDING_TYPE_UNIFORM :: WGPU_Buffer_Binding_Type(0x00000002)
WGPU_BUFFER_BINDING_TYPE_STORAGE :: WGPU_Buffer_Binding_Type(0x00000003)
WGPU_BUFFER_BINDING_TYPE_READ_ONLY_STORAGE :: WGPU_Buffer_Binding_Type(0x00000004)

WGPU_SAMPLER_BINDING_TYPE_BINDING_NOT_USED :: WGPU_Sampler_Binding_Type(0x00000000)
WGPU_SAMPLER_BINDING_TYPE_UNDEFINED :: WGPU_Sampler_Binding_Type(0x00000001)
WGPU_SAMPLER_BINDING_TYPE_FILTERING :: WGPU_Sampler_Binding_Type(0x00000002)
WGPU_SAMPLER_BINDING_TYPE_NON_FILTERING :: WGPU_Sampler_Binding_Type(0x00000003)
WGPU_SAMPLER_BINDING_TYPE_COMPARISON :: WGPU_Sampler_Binding_Type(0x00000004)

WGPU_TEXTURE_SAMPLE_TYPE_BINDING_NOT_USED :: WGPU_Texture_Sample_Type(0x00000000)
WGPU_TEXTURE_SAMPLE_TYPE_UNDEFINED :: WGPU_Texture_Sample_Type(0x00000001)
WGPU_TEXTURE_SAMPLE_TYPE_FLOAT :: WGPU_Texture_Sample_Type(0x00000002)
WGPU_TEXTURE_SAMPLE_TYPE_UNFILTERABLE_FLOAT :: WGPU_Texture_Sample_Type(0x00000003)
WGPU_TEXTURE_SAMPLE_TYPE_DEPTH :: WGPU_Texture_Sample_Type(0x00000004)
WGPU_TEXTURE_SAMPLE_TYPE_SINT :: WGPU_Texture_Sample_Type(0x00000005)
WGPU_TEXTURE_SAMPLE_TYPE_UINT :: WGPU_Texture_Sample_Type(0x00000006)

WGPU_STORAGE_TEXTURE_ACCESS_BINDING_NOT_USED :: WGPU_Storage_Texture_Access(0x00000000)
WGPU_STORAGE_TEXTURE_ACCESS_UNDEFINED :: WGPU_Storage_Texture_Access(0x00000001)
WGPU_STORAGE_TEXTURE_ACCESS_WRITE_ONLY :: WGPU_Storage_Texture_Access(0x00000002)
WGPU_STORAGE_TEXTURE_ACCESS_READ_ONLY :: WGPU_Storage_Texture_Access(0x00000003)
WGPU_STORAGE_TEXTURE_ACCESS_READ_WRITE :: WGPU_Storage_Texture_Access(0x00000004)

WGPU_ADDRESS_MODE_UNDEFINED :: WGPU_Address_Mode(0x00000000)
WGPU_ADDRESS_MODE_CLAMP_TO_EDGE :: WGPU_Address_Mode(0x00000001)
WGPU_ADDRESS_MODE_REPEAT :: WGPU_Address_Mode(0x00000002)
WGPU_ADDRESS_MODE_MIRROR_REPEAT :: WGPU_Address_Mode(0x00000003)

WGPU_FILTER_MODE_UNDEFINED :: WGPU_Filter_Mode(0x00000000)
WGPU_FILTER_MODE_NEAREST :: WGPU_Filter_Mode(0x00000001)
WGPU_FILTER_MODE_LINEAR :: WGPU_Filter_Mode(0x00000002)

WGPU_MIPMAP_FILTER_MODE_UNDEFINED :: WGPU_Mipmap_Filter_Mode(0x00000000)
WGPU_MIPMAP_FILTER_MODE_NEAREST :: WGPU_Mipmap_Filter_Mode(0x00000001)
WGPU_MIPMAP_FILTER_MODE_LINEAR :: WGPU_Mipmap_Filter_Mode(0x00000002)

WGPU_COMPARE_FUNCTION_UNDEFINED :: WGPU_Compare_Function(0x00000000)
WGPU_COMPARE_FUNCTION_NEVER :: WGPU_Compare_Function(0x00000001)
WGPU_COMPARE_FUNCTION_LESS :: WGPU_Compare_Function(0x00000002)
WGPU_COMPARE_FUNCTION_EQUAL :: WGPU_Compare_Function(0x00000003)
WGPU_COMPARE_FUNCTION_LESS_EQUAL :: WGPU_Compare_Function(0x00000004)
WGPU_COMPARE_FUNCTION_GREATER :: WGPU_Compare_Function(0x00000005)
WGPU_COMPARE_FUNCTION_NOT_EQUAL :: WGPU_Compare_Function(0x00000006)
WGPU_COMPARE_FUNCTION_GREATER_EQUAL :: WGPU_Compare_Function(0x00000007)
WGPU_COMPARE_FUNCTION_ALWAYS :: WGPU_Compare_Function(0x00000008)

WGPU_VERTEX_STEP_MODE_VERTEX_BUFFER_NOT_USED :: WGPU_Vertex_Step_Mode(0x00000000)
WGPU_VERTEX_STEP_MODE_UNDEFINED :: WGPU_Vertex_Step_Mode(0x00000001)
WGPU_VERTEX_STEP_MODE_VERTEX :: WGPU_Vertex_Step_Mode(0x00000002)
WGPU_VERTEX_STEP_MODE_INSTANCE :: WGPU_Vertex_Step_Mode(0x00000003)

WGPU_VERTEX_FORMAT_FLOAT32X2 :: WGPU_Vertex_Format(0x0000001D)
WGPU_VERTEX_FORMAT_FLOAT32X3 :: WGPU_Vertex_Format(0x0000001E)
WGPU_VERTEX_FORMAT_FLOAT32X4 :: WGPU_Vertex_Format(0x0000001F)

WGPU_PRIMITIVE_TOPOLOGY_UNDEFINED :: WGPU_Primitive_Topology(0x00000000)
WGPU_PRIMITIVE_TOPOLOGY_POINT_LIST :: WGPU_Primitive_Topology(0x00000001)
WGPU_PRIMITIVE_TOPOLOGY_LINE_LIST :: WGPU_Primitive_Topology(0x00000002)
WGPU_PRIMITIVE_TOPOLOGY_LINE_STRIP :: WGPU_Primitive_Topology(0x00000003)
WGPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST :: WGPU_Primitive_Topology(0x00000004)
WGPU_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP :: WGPU_Primitive_Topology(0x00000005)

WGPU_FRONT_FACE_UNDEFINED :: WGPU_Front_Face(0x00000000)
WGPU_FRONT_FACE_CCW :: WGPU_Front_Face(0x00000001)
WGPU_FRONT_FACE_CW :: WGPU_Front_Face(0x00000002)

WGPU_CULL_MODE_UNDEFINED :: WGPU_Cull_Mode(0x00000000)
WGPU_CULL_MODE_NONE :: WGPU_Cull_Mode(0x00000001)
WGPU_CULL_MODE_FRONT :: WGPU_Cull_Mode(0x00000002)
WGPU_CULL_MODE_BACK :: WGPU_Cull_Mode(0x00000003)

WGPU_STENCIL_OPERATION_UNDEFINED :: WGPU_Stencil_Operation(0x00000000)
WGPU_STENCIL_OPERATION_KEEP :: WGPU_Stencil_Operation(0x00000001)
WGPU_STENCIL_OPERATION_ZERO :: WGPU_Stencil_Operation(0x00000002)
WGPU_STENCIL_OPERATION_REPLACE :: WGPU_Stencil_Operation(0x00000003)
WGPU_STENCIL_OPERATION_INVERT :: WGPU_Stencil_Operation(0x00000004)
WGPU_STENCIL_OPERATION_INCREMENT_CLAMP :: WGPU_Stencil_Operation(0x00000005)
WGPU_STENCIL_OPERATION_DECREMENT_CLAMP :: WGPU_Stencil_Operation(0x00000006)
WGPU_STENCIL_OPERATION_INCREMENT_WRAP :: WGPU_Stencil_Operation(0x00000007)
WGPU_STENCIL_OPERATION_DECREMENT_WRAP :: WGPU_Stencil_Operation(0x00000008)

WGPU_BLEND_OPERATION_UNDEFINED :: WGPU_Blend_Operation(0x00000000)
WGPU_BLEND_OPERATION_ADD :: WGPU_Blend_Operation(0x00000001)
WGPU_BLEND_OPERATION_SUBTRACT :: WGPU_Blend_Operation(0x00000002)
WGPU_BLEND_OPERATION_REVERSE_SUBTRACT :: WGPU_Blend_Operation(0x00000003)
WGPU_BLEND_OPERATION_MIN :: WGPU_Blend_Operation(0x00000004)
WGPU_BLEND_OPERATION_MAX :: WGPU_Blend_Operation(0x00000005)

WGPU_BLEND_FACTOR_UNDEFINED :: WGPU_Blend_Factor(0x00000000)
WGPU_BLEND_FACTOR_ZERO :: WGPU_Blend_Factor(0x00000001)
WGPU_BLEND_FACTOR_ONE :: WGPU_Blend_Factor(0x00000002)
WGPU_BLEND_FACTOR_SRC :: WGPU_Blend_Factor(0x00000003)
WGPU_BLEND_FACTOR_ONE_MINUS_SRC :: WGPU_Blend_Factor(0x00000004)
WGPU_BLEND_FACTOR_SRC_ALPHA :: WGPU_Blend_Factor(0x00000005)
WGPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA :: WGPU_Blend_Factor(0x00000006)
WGPU_BLEND_FACTOR_DST :: WGPU_Blend_Factor(0x00000007)
WGPU_BLEND_FACTOR_ONE_MINUS_DST :: WGPU_Blend_Factor(0x00000008)
WGPU_BLEND_FACTOR_DST_ALPHA :: WGPU_Blend_Factor(0x00000009)
WGPU_BLEND_FACTOR_ONE_MINUS_DST_ALPHA :: WGPU_Blend_Factor(0x0000000A)
WGPU_BLEND_FACTOR_SRC_ALPHA_SATURATED :: WGPU_Blend_Factor(0x0000000B)
WGPU_BLEND_FACTOR_CONSTANT :: WGPU_Blend_Factor(0x0000000C)
WGPU_BLEND_FACTOR_ONE_MINUS_CONSTANT :: WGPU_Blend_Factor(0x0000000D)
WGPU_BLEND_FACTOR_SRC1 :: WGPU_Blend_Factor(0x0000000E)
WGPU_BLEND_FACTOR_ONE_MINUS_SRC1 :: WGPU_Blend_Factor(0x0000000F)
WGPU_BLEND_FACTOR_SRC1_ALPHA :: WGPU_Blend_Factor(0x00000010)
WGPU_BLEND_FACTOR_ONE_MINUS_SRC1_ALPHA :: WGPU_Blend_Factor(0x00000011)

WGPU_COLOR_WRITE_MASK_NONE :: WGPU_Color_Write_Mask(0x0000000000000000)
WGPU_COLOR_WRITE_MASK_RED :: WGPU_Color_Write_Mask(0x0000000000000001)
WGPU_COLOR_WRITE_MASK_GREEN :: WGPU_Color_Write_Mask(0x0000000000000002)
WGPU_COLOR_WRITE_MASK_BLUE :: WGPU_Color_Write_Mask(0x0000000000000004)
WGPU_COLOR_WRITE_MASK_ALPHA :: WGPU_Color_Write_Mask(0x0000000000000008)
WGPU_COLOR_WRITE_MASK_ALL :: WGPU_Color_Write_Mask(0x000000000000000F)

WGPU_FEATURE_LEVEL_COMPATIBILITY :: WGPU_Feature_Level(0x00000001)
WGPU_FEATURE_LEVEL_CORE :: WGPU_Feature_Level(0x00000002)

WGPU_POWER_PREFERENCE_UNDEFINED :: WGPU_Power_Preference(0x00000000)
WGPU_POWER_PREFERENCE_LOW_POWER :: WGPU_Power_Preference(0x00000001)
WGPU_POWER_PREFERENCE_HIGH_PERFORMANCE :: WGPU_Power_Preference(0x00000002)

WGPU_BACKEND_TYPE_UNDEFINED :: WGPU_Backend_Type(0x00000000)
WGPU_BACKEND_TYPE_NULL :: WGPU_Backend_Type(0x00000001)
WGPU_BACKEND_TYPE_WEBGPU :: WGPU_Backend_Type(0x00000002)
WGPU_BACKEND_TYPE_D3D11 :: WGPU_Backend_Type(0x00000003)
WGPU_BACKEND_TYPE_D3D12 :: WGPU_Backend_Type(0x00000004)
WGPU_BACKEND_TYPE_METAL :: WGPU_Backend_Type(0x00000005)
WGPU_BACKEND_TYPE_VULKAN :: WGPU_Backend_Type(0x00000006)
WGPU_BACKEND_TYPE_OPENGL :: WGPU_Backend_Type(0x00000007)
WGPU_BACKEND_TYPE_OPENGL_ES :: WGPU_Backend_Type(0x00000008)

WGPU_REQUEST_ADAPTER_STATUS_SUCCESS :: WGPU_Request_Adapter_Status(0x00000001)
WGPU_REQUEST_ADAPTER_STATUS_INSTANCE_DROPPED :: WGPU_Request_Adapter_Status(0x00000002)
WGPU_REQUEST_ADAPTER_STATUS_UNAVAILABLE :: WGPU_Request_Adapter_Status(0x00000003)
WGPU_REQUEST_ADAPTER_STATUS_ERROR :: WGPU_Request_Adapter_Status(0x00000004)
WGPU_REQUEST_ADAPTER_STATUS_UNKNOWN :: WGPU_Request_Adapter_Status(0x00000005)

WGPU_REQUEST_DEVICE_STATUS_SUCCESS :: WGPU_Request_Device_Status(0x00000001)
WGPU_REQUEST_DEVICE_STATUS_INSTANCE_DROPPED :: WGPU_Request_Device_Status(0x00000002)
WGPU_REQUEST_DEVICE_STATUS_ERROR :: WGPU_Request_Device_Status(0x00000003)
WGPU_REQUEST_DEVICE_STATUS_UNKNOWN :: WGPU_Request_Device_Status(0x00000004)

WGPU_DEVICE_LOST_REASON_UNKNOWN :: WGPU_Device_Lost_Reason(0x00000001)
WGPU_DEVICE_LOST_REASON_DESTROYED :: WGPU_Device_Lost_Reason(0x00000002)
WGPU_DEVICE_LOST_REASON_INSTANCE_DROPPED :: WGPU_Device_Lost_Reason(0x00000003)
WGPU_DEVICE_LOST_REASON_FAILED_CREATION :: WGPU_Device_Lost_Reason(0x00000004)

WGPU_ERROR_TYPE_NO_ERROR :: WGPU_Error_Type(0x00000001)
WGPU_ERROR_TYPE_VALIDATION :: WGPU_Error_Type(0x00000002)
WGPU_ERROR_TYPE_OUT_OF_MEMORY :: WGPU_Error_Type(0x00000003)
WGPU_ERROR_TYPE_INTERNAL :: WGPU_Error_Type(0x00000004)
WGPU_ERROR_TYPE_UNKNOWN :: WGPU_Error_Type(0x00000005)

WGPU_COMPOSITE_ALPHA_MODE_AUTO :: WGPU_Composite_Alpha_Mode(0x00000000)
WGPU_COMPOSITE_ALPHA_MODE_OPAQUE :: WGPU_Composite_Alpha_Mode(0x00000001)
WGPU_COMPOSITE_ALPHA_MODE_PREMULTIPLIED :: WGPU_Composite_Alpha_Mode(0x00000002)
WGPU_COMPOSITE_ALPHA_MODE_UNPREMULTIPLIED :: WGPU_Composite_Alpha_Mode(0x00000003)
WGPU_COMPOSITE_ALPHA_MODE_INHERIT :: WGPU_Composite_Alpha_Mode(0x00000004)

WGPU_PRESENT_MODE_UNDEFINED :: WGPU_Present_Mode(0x00000000)
WGPU_PRESENT_MODE_FIFO :: WGPU_Present_Mode(0x00000001)
WGPU_PRESENT_MODE_FIFO_RELAXED :: WGPU_Present_Mode(0x00000002)
WGPU_PRESENT_MODE_IMMEDIATE :: WGPU_Present_Mode(0x00000003)
WGPU_PRESENT_MODE_MAILBOX :: WGPU_Present_Mode(0x00000004)

WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_OPTIMAL :: WGPU_Surface_Get_Current_Texture_Status(0x00000001)
WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_SUBOPTIMAL :: WGPU_Surface_Get_Current_Texture_Status(0x00000002)
WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_TIMEOUT :: WGPU_Surface_Get_Current_Texture_Status(0x00000003)
WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_OUTDATED :: WGPU_Surface_Get_Current_Texture_Status(0x00000004)
WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_LOST :: WGPU_Surface_Get_Current_Texture_Status(0x00000005)
WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_OUT_OF_MEMORY :: WGPU_Surface_Get_Current_Texture_Status(0x00000006)
WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_DEVICE_LOST :: WGPU_Surface_Get_Current_Texture_Status(0x00000007)
WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_ERROR :: WGPU_Surface_Get_Current_Texture_Status(0x00000008)

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
WGPU_DEPTH_SLICE_UNDEFINED :: WGPU_U32_MAX

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

WGPU_Surface_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	label:         WGPU_String_View,
}

WGPU_Surface_Source_Android_Native_Window :: struct #align(align_of(rawptr)) {
	chain:  WGPU_Chained_Struct,
	window: rawptr,
}

WGPU_Surface_Source_Metal_Layer :: struct #align(align_of(rawptr)) {
	chain: WGPU_Chained_Struct,
	layer: rawptr,
}

WGPU_Surface_Source_Wayland_Surface :: struct #align(align_of(rawptr)) {
	chain:   WGPU_Chained_Struct,
	display: rawptr,
	surface: rawptr,
}

WGPU_Surface_Source_Windows_HWND :: struct #align(align_of(rawptr)) {
	chain:     WGPU_Chained_Struct,
	hinstance: rawptr,
	hwnd:      rawptr,
}

WGPU_Surface_Source_XCB_Window :: struct #align(align_of(rawptr)) {
	chain:      WGPU_Chained_Struct,
	connection: rawptr,
	window:     u32,
}

WGPU_Surface_Source_Xlib_Window :: struct #align(align_of(rawptr)) {
	chain:   WGPU_Chained_Struct,
	display: rawptr,
	window:  u64,
}

WGPU_Surface_Configuration_Extras :: struct #align(align_of(rawptr)) {
	chain:                         WGPU_Chained_Struct,
	desired_maximum_frame_latency: u32,
}

WGPU_Surface_Configuration :: struct #align(align_of(rawptr)) {
	next_in_chain:    ^WGPU_Chained_Struct,
	device:           WGPU_Device,
	format:           WGPU_Texture_Format,
	usage:            WGPU_Texture_Usage,
	width:            u32,
	height:           u32,
	view_format_count: c.size_t,
	view_formats:     [^]WGPU_Texture_Format,
	alpha_mode:       WGPU_Composite_Alpha_Mode,
	present_mode:     WGPU_Present_Mode,
}

WGPU_Surface_Capabilities :: struct #align(align_of(rawptr)) {
	next_in_chain:     ^WGPU_Chained_Struct_Out,
	usages:            WGPU_Texture_Usage,
	format_count:      c.size_t,
	formats:           [^]WGPU_Texture_Format,
	present_mode_count: c.size_t,
	present_modes:     [^]WGPU_Present_Mode,
	alpha_mode_count:  c.size_t,
	alpha_modes:       [^]WGPU_Composite_Alpha_Mode,
}

WGPU_Surface_Texture :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct_Out,
	texture:       WGPU_Texture,
	status:        WGPU_Surface_Get_Current_Texture_Status,
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

WGPU_Color :: struct {
	r: f64,
	g: f64,
	b: f64,
	a: f64,
}

WGPU_Color_Attachment :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	view:          WGPU_Texture_View,
	depth_slice:   u32,
	resolve_target: WGPU_Texture_View,
	load_op:       WGPU_Load_Op,
	store_op:      WGPU_Store_Op,
	clear_value:   WGPU_Color,
}

WGPU_Depth_Stencil_Attachment :: struct #align(align_of(rawptr)) {
	view:                WGPU_Texture_View,
	depth_load_op:       WGPU_Load_Op,
	depth_store_op:      WGPU_Store_Op,
	depth_clear_value:   f32,
	depth_read_only:     WGPU_Bool,
	stencil_load_op:     WGPU_Load_Op,
	stencil_store_op:    WGPU_Store_Op,
	stencil_clear_value: u32,
	stencil_read_only:   WGPU_Bool,
}

WGPU_Render_Pass_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain:              ^WGPU_Chained_Struct,
	label:                      WGPU_String_View,
	color_attachment_count:     c.size_t,
	color_attachments:          [^]WGPU_Color_Attachment,
	depth_stencil_attachment:   ^WGPU_Depth_Stencil_Attachment,
	occlusion_query_set:        WGPU_Query_Set,
	timestamp_writes:           rawptr,
}

WGPU_Buffer_Binding_Layout :: struct #align(align_of(rawptr)) {
	next_in_chain:      ^WGPU_Chained_Struct,
	type_:              WGPU_Buffer_Binding_Type,
	has_dynamic_offset: WGPU_Bool,
	min_binding_size:   u64,
}

WGPU_Sampler_Binding_Layout :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	type_:         WGPU_Sampler_Binding_Type,
}

WGPU_Texture_Binding_Layout :: struct #align(align_of(rawptr)) {
	next_in_chain:  ^WGPU_Chained_Struct,
	sample_type:    WGPU_Texture_Sample_Type,
	view_dimension: WGPU_Texture_View_Dimension,
	multisampled:   WGPU_Bool,
}

WGPU_Storage_Texture_Binding_Layout :: struct #align(align_of(rawptr)) {
	next_in_chain:  ^WGPU_Chained_Struct,
	access:         WGPU_Storage_Texture_Access,
	format:         WGPU_Texture_Format,
	view_dimension: WGPU_Texture_View_Dimension,
}

WGPU_Bind_Group_Layout_Entry :: struct #align(align_of(rawptr)) {
	next_in_chain:   ^WGPU_Chained_Struct,
	binding:         u32,
	visibility:      WGPU_Shader_Stage,
	buffer:          WGPU_Buffer_Binding_Layout,
	sampler:         WGPU_Sampler_Binding_Layout,
	texture:         WGPU_Texture_Binding_Layout,
	storage_texture: WGPU_Storage_Texture_Binding_Layout,
}

WGPU_Bind_Group_Layout_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	label:         WGPU_String_View,
	entry_count:   c.size_t,
	entries:       [^]WGPU_Bind_Group_Layout_Entry,
}

WGPU_Bind_Group_Entry :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	binding:       u32,
	buffer:        WGPU_Buffer,
	offset:        u64,
	size:          u64,
	sampler:       WGPU_Sampler,
	texture_view:  WGPU_Texture_View,
}

WGPU_Bind_Group_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	label:         WGPU_String_View,
	layout:        WGPU_Bind_Group_Layout,
	entry_count:   c.size_t,
	entries:       [^]WGPU_Bind_Group_Entry,
}

WGPU_Sampler_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain:  ^WGPU_Chained_Struct,
	label:          WGPU_String_View,
	address_mode_u: WGPU_Address_Mode,
	address_mode_v: WGPU_Address_Mode,
	address_mode_w: WGPU_Address_Mode,
	mag_filter:     WGPU_Filter_Mode,
	min_filter:     WGPU_Filter_Mode,
	mipmap_filter:  WGPU_Mipmap_Filter_Mode,
	lod_min_clamp:  f32,
	lod_max_clamp:  f32,
	compare:        WGPU_Compare_Function,
	max_anisotropy: u16,
}

WGPU_Pipeline_Layout_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain:           ^WGPU_Chained_Struct,
	label:                   WGPU_String_View,
	bind_group_layout_count: c.size_t,
	bind_group_layouts:      [^]WGPU_Bind_Group_Layout,
}

WGPU_Shader_Source_WGSL :: struct #align(align_of(rawptr)) {
	chain: WGPU_Chained_Struct,
	code:  WGPU_String_View,
}

WGPU_Shader_Module_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	label:         WGPU_String_View,
}

WGPU_Constant_Entry :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	key:           WGPU_String_View,
	value:         f64,
}

WGPU_Vertex_Attribute :: struct {
	format:          WGPU_Vertex_Format,
	offset:          u64,
	shader_location: u32,
}

WGPU_Vertex_Buffer_Layout :: struct #align(align_of(rawptr)) {
	step_mode:       WGPU_Vertex_Step_Mode,
	array_stride:    u64,
	attribute_count: c.size_t,
	attributes:      [^]WGPU_Vertex_Attribute,
}

WGPU_Vertex_State :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	module:        WGPU_Shader_Module,
	entry_point:   WGPU_String_View,
	constant_count: c.size_t,
	constants:     [^]WGPU_Constant_Entry,
	buffer_count:  c.size_t,
	buffers:       [^]WGPU_Vertex_Buffer_Layout,
}

WGPU_Primitive_State :: struct #align(align_of(rawptr)) {
	next_in_chain:     ^WGPU_Chained_Struct,
	topology:          WGPU_Primitive_Topology,
	strip_index_format: WGPU_Index_Format,
	front_face:        WGPU_Front_Face,
	cull_mode:         WGPU_Cull_Mode,
	unclipped_depth:   WGPU_Bool,
}

WGPU_Stencil_Face_State :: struct {
	compare:       WGPU_Compare_Function,
	fail_op:       WGPU_Stencil_Operation,
	depth_fail_op: WGPU_Stencil_Operation,
	pass_op:       WGPU_Stencil_Operation,
}

WGPU_Depth_Stencil_State :: struct #align(align_of(rawptr)) {
	next_in_chain:          ^WGPU_Chained_Struct,
	format:                 WGPU_Texture_Format,
	depth_write_enabled:    WGPU_Optional_Bool,
	depth_compare:          WGPU_Compare_Function,
	stencil_front:          WGPU_Stencil_Face_State,
	stencil_back:           WGPU_Stencil_Face_State,
	stencil_read_mask:      u32,
	stencil_write_mask:     u32,
	depth_bias:             i32,
	depth_bias_slope_scale: f32,
	depth_bias_clamp:       f32,
}

WGPU_Multisample_State :: struct #align(align_of(rawptr)) {
	next_in_chain:            ^WGPU_Chained_Struct,
	count:                    u32,
	mask:                     u32,
	alpha_to_coverage_enabled: WGPU_Bool,
}

WGPU_Blend_Component :: struct {
	operation:  WGPU_Blend_Operation,
	src_factor: WGPU_Blend_Factor,
	dst_factor: WGPU_Blend_Factor,
}

WGPU_Blend_State :: struct {
	color: WGPU_Blend_Component,
	alpha: WGPU_Blend_Component,
}

WGPU_Color_Target_State :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	format:        WGPU_Texture_Format,
	blend:         ^WGPU_Blend_State,
	write_mask:    WGPU_Color_Write_Mask,
}

WGPU_Fragment_State :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	module:        WGPU_Shader_Module,
	entry_point:   WGPU_String_View,
	constant_count: c.size_t,
	constants:     [^]WGPU_Constant_Entry,
	target_count:  c.size_t,
	targets:       [^]WGPU_Color_Target_State,
}

WGPU_Render_Pipeline_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	label:         WGPU_String_View,
	layout:        WGPU_Pipeline_Layout,
	vertex:        WGPU_Vertex_State,
	primitive:     WGPU_Primitive_State,
	depth_stencil: ^WGPU_Depth_Stencil_State,
	multisample:   WGPU_Multisample_State,
	fragment:      ^WGPU_Fragment_State,
}

WGPU_Instance_Capabilities :: struct #align(align_of(rawptr)) {
	next_in_chain:            ^WGPU_Chained_Struct_Out,
	timed_wait_any_enable:    WGPU_Bool,
	timed_wait_any_max_count: c.size_t,
}

WGPU_Instance_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	features:      WGPU_Instance_Capabilities,
}

WGPU_Request_Adapter_Options :: struct #align(align_of(rawptr)) {
	next_in_chain:          ^WGPU_Chained_Struct,
	feature_level:          WGPU_Feature_Level,
	power_preference:       WGPU_Power_Preference,
	force_fallback_adapter: WGPU_Bool,
	backend_type:           WGPU_Backend_Type,
	compatible_surface:     WGPU_Surface,
}

WGPU_Queue_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	label:         WGPU_String_View,
}

WGPU_Device_Lost_Callback :: proc "c" (device: rawptr, reason: WGPU_Device_Lost_Reason, message: WGPU_String_View, userdata1, userdata2: rawptr)

WGPU_Device_Lost_Callback_Info :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	mode:          WGPU_Callback_Mode,
	callback:      WGPU_Device_Lost_Callback,
	userdata1:     rawptr,
	userdata2:     rawptr,
}

WGPU_Uncaptured_Error_Callback :: proc "c" (device: WGPU_Device, error_type: WGPU_Error_Type, message: WGPU_String_View, userdata1, userdata2: rawptr)

WGPU_Uncaptured_Error_Callback_Info :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	callback:      WGPU_Uncaptured_Error_Callback,
	userdata1:     rawptr,
	userdata2:     rawptr,
}

WGPU_Device_Descriptor :: struct #align(align_of(rawptr)) {
	next_in_chain:                  ^WGPU_Chained_Struct,
	label:                          WGPU_String_View,
	required_feature_count:         c.size_t,
	required_features:              rawptr,
	required_limits:                WGPU_Limits,
	default_queue:                  WGPU_Queue_Descriptor,
	device_lost_callback_info:      WGPU_Device_Lost_Callback_Info,
	uncaptured_error_callback_info: WGPU_Uncaptured_Error_Callback_Info,
}

WGPU_Request_Adapter_Callback :: proc "c" (status: WGPU_Request_Adapter_Status, adapter: WGPU_Adapter, message: WGPU_String_View, userdata1, userdata2: rawptr)

WGPU_Request_Adapter_Callback_Info :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	mode:          WGPU_Callback_Mode,
	callback:      WGPU_Request_Adapter_Callback,
	userdata1:     rawptr,
	userdata2:     rawptr,
}

WGPU_Request_Device_Callback :: proc "c" (status: WGPU_Request_Device_Status, device: WGPU_Device, message: WGPU_String_View, userdata1, userdata2: rawptr)

WGPU_Request_Device_Callback_Info :: struct #align(align_of(rawptr)) {
	next_in_chain: ^WGPU_Chained_Struct,
	mode:          WGPU_Callback_Mode,
	callback:      WGPU_Request_Device_Callback,
	userdata1:     rawptr,
	userdata2:     rawptr,
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
WGPU_Device_Create_Bind_Group_Layout_Proc :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Bind_Group_Layout_Descriptor) -> WGPU_Bind_Group_Layout
WGPU_Device_Create_Pipeline_Layout_Proc :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Pipeline_Layout_Descriptor) -> WGPU_Pipeline_Layout
WGPU_Device_Create_Sampler_Proc :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Sampler_Descriptor) -> WGPU_Sampler
WGPU_Device_Create_Bind_Group_Proc :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Bind_Group_Descriptor) -> WGPU_Bind_Group
WGPU_Device_Create_Shader_Module_Proc :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Shader_Module_Descriptor) -> WGPU_Shader_Module
WGPU_Device_Create_Render_Pipeline_Proc :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Render_Pipeline_Descriptor) -> WGPU_Render_Pipeline
WGPU_Device_Create_Command_Encoder_Proc :: proc "c" (device: WGPU_Device, descriptor: ^WGPU_Command_Encoder_Descriptor) -> WGPU_Command_Encoder
WGPU_Instance_Create_Surface_Proc :: proc "c" (instance: WGPU_Instance, descriptor: ^WGPU_Surface_Descriptor) -> WGPU_Surface
WGPU_Surface_Configure_Proc :: proc "c" (surface: WGPU_Surface, config: ^WGPU_Surface_Configuration)
WGPU_Surface_Get_Capabilities_Proc :: proc "c" (surface: WGPU_Surface, adapter: WGPU_Adapter, capabilities: ^WGPU_Surface_Capabilities) -> WGPU_Status
WGPU_Surface_Get_Current_Texture_Proc :: proc "c" (surface: WGPU_Surface, surface_texture: ^WGPU_Surface_Texture)
WGPU_Surface_Present_Proc :: proc "c" (surface: WGPU_Surface) -> WGPU_Status
WGPU_Surface_Unconfigure_Proc :: proc "c" (surface: WGPU_Surface)
WGPU_Surface_Capabilities_Free_Members_Proc :: proc "c" (capabilities: WGPU_Surface_Capabilities)
WGPU_Surface_Release_Proc :: proc "c" (surface: WGPU_Surface)
WGPU_Texture_Create_View_Proc :: proc "c" (texture: WGPU_Texture, descriptor: ^WGPU_Texture_View_Descriptor) -> WGPU_Texture_View
WGPU_Command_Encoder_Copy_Texture_To_Buffer_Proc :: proc "c" (encoder: WGPU_Command_Encoder, source: ^WGPU_Texel_Copy_Texture_Info, destination: ^WGPU_Texel_Copy_Buffer_Info, copy_size: ^WGPU_Extent_3D)
WGPU_Command_Encoder_Begin_Render_Pass_Proc :: proc "c" (encoder: WGPU_Command_Encoder, descriptor: ^WGPU_Render_Pass_Descriptor) -> WGPU_Render_Pass_Encoder
WGPU_Command_Encoder_Finish_Proc :: proc "c" (encoder: WGPU_Command_Encoder, descriptor: ^WGPU_Command_Buffer_Descriptor) -> WGPU_Command_Buffer
WGPU_Queue_Submit_Proc :: proc "c" (queue: WGPU_Queue, command_count: c.size_t, commands: [^]WGPU_Command_Buffer)
WGPU_Queue_Write_Buffer_Proc :: proc "c" (queue: WGPU_Queue, buffer: WGPU_Buffer, buffer_offset: u64, data: rawptr, size: c.size_t)
WGPU_Queue_Write_Texture_Proc :: proc "c" (queue: WGPU_Queue, destination: ^WGPU_Texel_Copy_Texture_Info, data: rawptr, data_size: c.size_t, data_layout: ^WGPU_Texel_Copy_Buffer_Layout, write_size: ^WGPU_Extent_3D)
WGPU_Render_Pass_Encoder_Set_Pipeline_Proc :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, pipeline: WGPU_Render_Pipeline)
WGPU_Render_Pass_Encoder_Set_Bind_Group_Proc :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, group_index: u32, group: WGPU_Bind_Group, dynamic_offset_count: c.size_t, dynamic_offsets: [^]u32)
WGPU_Render_Pass_Encoder_Set_Vertex_Buffer_Proc :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, slot: u32, buffer: WGPU_Buffer, offset, size: u64)
WGPU_Render_Pass_Encoder_Set_Index_Buffer_Proc :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, buffer: WGPU_Buffer, format: WGPU_Index_Format, offset, size: u64)
WGPU_Render_Pass_Encoder_Set_Viewport_Proc :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, x, y, width, height, min_depth, max_depth: f32)
WGPU_Render_Pass_Encoder_Set_Scissor_Rect_Proc :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, x, y, width, height: u32)
WGPU_Render_Pass_Encoder_Draw_Proc :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, vertex_count, instance_count, first_vertex, first_instance: u32)
WGPU_Render_Pass_Encoder_Draw_Indexed_Proc :: proc "c" (render_pass: WGPU_Render_Pass_Encoder, index_count, instance_count, first_index: u32, base_vertex: i32, first_instance: u32)
WGPU_Render_Pass_Encoder_End_Proc :: proc "c" (render_pass: WGPU_Render_Pass_Encoder)
WGPU_Buffer_Map_Async_Proc :: proc "c" (buffer: WGPU_Buffer, mode: WGPU_Map_Mode, offset, size: c.size_t, callback_info: WGPU_Buffer_Map_Callback_Info) -> WGPU_Future
WGPU_Buffer_Get_Mapped_Range_Proc :: proc "c" (buffer: WGPU_Buffer, offset, size: c.size_t) -> rawptr
WGPU_Buffer_Unmap_Proc :: proc "c" (buffer: WGPU_Buffer)
WGPU_Instance_Process_Events_Proc :: proc "c" (instance: WGPU_Instance)
WGPU_Texture_Release_Proc :: proc "c" (texture: WGPU_Texture)
WGPU_Texture_View_Release_Proc :: proc "c" (texture_view: WGPU_Texture_View)
WGPU_Buffer_Release_Proc :: proc "c" (buffer: WGPU_Buffer)
WGPU_Bind_Group_Layout_Release_Proc :: proc "c" (bind_group_layout: WGPU_Bind_Group_Layout)
WGPU_Pipeline_Layout_Release_Proc :: proc "c" (pipeline_layout: WGPU_Pipeline_Layout)
WGPU_Sampler_Release_Proc :: proc "c" (sampler: WGPU_Sampler)
WGPU_Bind_Group_Release_Proc :: proc "c" (bind_group: WGPU_Bind_Group)
WGPU_Shader_Module_Release_Proc :: proc "c" (shader_module: WGPU_Shader_Module)
WGPU_Render_Pipeline_Release_Proc :: proc "c" (pipeline: WGPU_Render_Pipeline)
WGPU_Command_Encoder_Release_Proc :: proc "c" (encoder: WGPU_Command_Encoder)
WGPU_Command_Buffer_Release_Proc :: proc "c" (command_buffer: WGPU_Command_Buffer)
WGPU_Render_Pass_Encoder_Release_Proc :: proc "c" (render_pass: WGPU_Render_Pass_Encoder)
WGPU_Create_Instance_Proc :: proc "c" (descriptor: ^WGPU_Instance_Descriptor) -> WGPU_Instance
WGPU_Instance_Request_Adapter_Proc :: proc "c" (instance: WGPU_Instance, options: ^WGPU_Request_Adapter_Options, callback_info: WGPU_Request_Adapter_Callback_Info) -> WGPU_Future
WGPU_Adapter_Request_Device_Proc :: proc "c" (adapter: WGPU_Adapter, descriptor: ^WGPU_Device_Descriptor, callback_info: WGPU_Request_Device_Callback_Info) -> WGPU_Future
WGPU_Device_Get_Queue_Proc :: proc "c" (device: WGPU_Device) -> WGPU_Queue
WGPU_Instance_Release_Proc :: proc "c" (instance: WGPU_Instance)
WGPU_Adapter_Release_Proc :: proc "c" (adapter: WGPU_Adapter)
WGPU_Device_Release_Proc :: proc "c" (device: WGPU_Device)
WGPU_Queue_Release_Proc :: proc "c" (queue: WGPU_Queue)
WGPU_Device_Poll_Proc :: proc "c" (device: WGPU_Device, wait: WGPU_Bool, submission_index: rawptr) -> WGPU_Bool

WGPU_Symbol_Resolver :: proc(name: string, user_data: rawptr) -> rawptr

WGPU_OFFSCREEN_LIBRARY_LOAD_ERROR :: "load_library"
WGPU_OFFSCREEN_LIBRARY_NOT_FOUND :: "library_not_found"
WGPU_OFFSCREEN_INSTANCE_CREATE_ERROR :: "create_instance"
WGPU_OFFSCREEN_ADAPTER_REQUEST_ERROR :: "request_adapter"
WGPU_OFFSCREEN_DEVICE_REQUEST_ERROR :: "request_device"
WGPU_OFFSCREEN_QUEUE_GET_ERROR :: "get_queue"
WGPU_OFFSCREEN_REQUEST_TIMEOUT_ERROR :: "request_timeout"
WGPU_OFFSCREEN_TEXTURE_CREATE_ERROR :: "create_texture"
WGPU_OFFSCREEN_TEXTURE_VIEW_CREATE_ERROR :: "create_texture_view"
WGPU_OFFSCREEN_BUFFER_CREATE_ERROR :: "create_staging_buffer"
WGPU_OFFSCREEN_COMMAND_ENCODER_CREATE_ERROR :: "create_command_encoder"
WGPU_OFFSCREEN_RENDER_PASS_CREATE_ERROR :: "begin_render_pass"
WGPU_OFFSCREEN_COMMAND_BUFFER_CREATE_ERROR :: "finish_command_buffer"
WGPU_OFFSCREEN_MAP_ERROR :: "map_buffer"
WGPU_OFFSCREEN_MAPPED_RANGE_ERROR :: "get_mapped_range"
WGPU_OFFSCREEN_READBACK_ERROR :: "readback_pixel"
WGPU_OFFSCREEN_INVALID_SIZE_ERROR :: "invalid_size"
WGPU_OFFSCREEN_SHADER_MODULE_CREATE_ERROR :: "create_shader_module"
WGPU_OFFSCREEN_PIPELINE_LAYOUT_CREATE_ERROR :: "create_pipeline_layout"
WGPU_OFFSCREEN_RENDER_PIPELINE_CREATE_ERROR :: "create_render_pipeline"
WGPU_OFFSCREEN_LIBRARY_ENV :: "SCRAPBOT_WGPU_NATIVE_LIBRARY"
WGPU_OFFSCREEN_REQUEST_POLL_LIMIT :: 2048

WGPU_OFFSCREEN_TRIANGLE_WGSL :: `@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> @builtin(position) vec4<f32> {
	var positions = array<vec2<f32>, 3>(
		vec2<f32>(-1.0, -1.0),
		vec2<f32>(3.0, -1.0),
		vec2<f32>(-1.0, 3.0),
	);
	let position = positions[vertex_index];
	return vec4<f32>(position, 0.0, 1.0);
}

@fragment
fn fs_main() -> @location(0) vec4<f32> {
	return vec4<f32>(1.0, 0.0, 0.0, 1.0);
}
`

WGPU_SCENE_RECT_WGSL_HEADER :: `struct VertexOut {
	@builtin(position) position: vec4<f32>,
	@location(0) color: vec3<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOut {
	var out: VertexOut;
	out.position = vec4<f32>(POSITIONS[vertex_index], 0.0, 1.0);
	out.color = COLORS[vertex_index];
	return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
	return vec4<f32>(in.color, 1.0);
}
`

WGPU_Scene_Vertex :: struct {
	position: [2]f32,
	color:    [3]f32,
}

WGPU_SYMBOL_DEVICE_CREATE_TEXTURE :: "wgpuDeviceCreateTexture"
WGPU_SYMBOL_DEVICE_CREATE_BUFFER :: "wgpuDeviceCreateBuffer"
WGPU_SYMBOL_DEVICE_CREATE_BIND_GROUP_LAYOUT :: "wgpuDeviceCreateBindGroupLayout"
WGPU_SYMBOL_DEVICE_CREATE_PIPELINE_LAYOUT :: "wgpuDeviceCreatePipelineLayout"
WGPU_SYMBOL_DEVICE_CREATE_SAMPLER :: "wgpuDeviceCreateSampler"
WGPU_SYMBOL_DEVICE_CREATE_BIND_GROUP :: "wgpuDeviceCreateBindGroup"
WGPU_SYMBOL_DEVICE_CREATE_SHADER_MODULE :: "wgpuDeviceCreateShaderModule"
WGPU_SYMBOL_DEVICE_CREATE_RENDER_PIPELINE :: "wgpuDeviceCreateRenderPipeline"
WGPU_SYMBOL_DEVICE_CREATE_COMMAND_ENCODER :: "wgpuDeviceCreateCommandEncoder"
WGPU_SYMBOL_INSTANCE_CREATE_SURFACE :: "wgpuInstanceCreateSurface"
WGPU_SYMBOL_SURFACE_CONFIGURE :: "wgpuSurfaceConfigure"
WGPU_SYMBOL_SURFACE_GET_CAPABILITIES :: "wgpuSurfaceGetCapabilities"
WGPU_SYMBOL_SURFACE_GET_CURRENT_TEXTURE :: "wgpuSurfaceGetCurrentTexture"
WGPU_SYMBOL_SURFACE_PRESENT :: "wgpuSurfacePresent"
WGPU_SYMBOL_SURFACE_UNCONFIGURE :: "wgpuSurfaceUnconfigure"
WGPU_SYMBOL_SURFACE_CAPABILITIES_FREE_MEMBERS :: "wgpuSurfaceCapabilitiesFreeMembers"
WGPU_SYMBOL_SURFACE_RELEASE :: "wgpuSurfaceRelease"
WGPU_SYMBOL_TEXTURE_CREATE_VIEW :: "wgpuTextureCreateView"
WGPU_SYMBOL_COMMAND_ENCODER_COPY_TEXTURE_TO_BUFFER :: "wgpuCommandEncoderCopyTextureToBuffer"
WGPU_SYMBOL_COMMAND_ENCODER_BEGIN_RENDER_PASS :: "wgpuCommandEncoderBeginRenderPass"
WGPU_SYMBOL_COMMAND_ENCODER_FINISH :: "wgpuCommandEncoderFinish"
WGPU_SYMBOL_QUEUE_SUBMIT :: "wgpuQueueSubmit"
WGPU_SYMBOL_QUEUE_WRITE_BUFFER :: "wgpuQueueWriteBuffer"
WGPU_SYMBOL_QUEUE_WRITE_TEXTURE :: "wgpuQueueWriteTexture"
WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_PIPELINE :: "wgpuRenderPassEncoderSetPipeline"
WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_BIND_GROUP :: "wgpuRenderPassEncoderSetBindGroup"
WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_VERTEX_BUFFER :: "wgpuRenderPassEncoderSetVertexBuffer"
WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_INDEX_BUFFER :: "wgpuRenderPassEncoderSetIndexBuffer"
WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_VIEWPORT :: "wgpuRenderPassEncoderSetViewport"
WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_SCISSOR_RECT :: "wgpuRenderPassEncoderSetScissorRect"
WGPU_SYMBOL_RENDER_PASS_ENCODER_DRAW :: "wgpuRenderPassEncoderDraw"
WGPU_SYMBOL_RENDER_PASS_ENCODER_DRAW_INDEXED :: "wgpuRenderPassEncoderDrawIndexed"
WGPU_SYMBOL_RENDER_PASS_ENCODER_END :: "wgpuRenderPassEncoderEnd"
WGPU_SYMBOL_BUFFER_MAP_ASYNC :: "wgpuBufferMapAsync"
WGPU_SYMBOL_BUFFER_GET_MAPPED_RANGE :: "wgpuBufferGetMappedRange"
WGPU_SYMBOL_BUFFER_UNMAP :: "wgpuBufferUnmap"
WGPU_SYMBOL_INSTANCE_PROCESS_EVENTS :: "wgpuInstanceProcessEvents"
WGPU_SYMBOL_TEXTURE_RELEASE :: "wgpuTextureRelease"
WGPU_SYMBOL_TEXTURE_VIEW_RELEASE :: "wgpuTextureViewRelease"
WGPU_SYMBOL_BUFFER_RELEASE :: "wgpuBufferRelease"
WGPU_SYMBOL_BIND_GROUP_LAYOUT_RELEASE :: "wgpuBindGroupLayoutRelease"
WGPU_SYMBOL_PIPELINE_LAYOUT_RELEASE :: "wgpuPipelineLayoutRelease"
WGPU_SYMBOL_SAMPLER_RELEASE :: "wgpuSamplerRelease"
WGPU_SYMBOL_BIND_GROUP_RELEASE :: "wgpuBindGroupRelease"
WGPU_SYMBOL_SHADER_MODULE_RELEASE :: "wgpuShaderModuleRelease"
WGPU_SYMBOL_RENDER_PIPELINE_RELEASE :: "wgpuRenderPipelineRelease"
WGPU_SYMBOL_COMMAND_ENCODER_RELEASE :: "wgpuCommandEncoderRelease"
WGPU_SYMBOL_COMMAND_BUFFER_RELEASE :: "wgpuCommandBufferRelease"
WGPU_SYMBOL_RENDER_PASS_ENCODER_RELEASE :: "wgpuRenderPassEncoderRelease"
WGPU_SYMBOL_CREATE_INSTANCE :: "wgpuCreateInstance"
WGPU_SYMBOL_INSTANCE_REQUEST_ADAPTER :: "wgpuInstanceRequestAdapter"
WGPU_SYMBOL_ADAPTER_REQUEST_DEVICE :: "wgpuAdapterRequestDevice"
WGPU_SYMBOL_DEVICE_GET_QUEUE :: "wgpuDeviceGetQueue"
WGPU_SYMBOL_INSTANCE_RELEASE :: "wgpuInstanceRelease"
WGPU_SYMBOL_ADAPTER_RELEASE :: "wgpuAdapterRelease"
WGPU_SYMBOL_DEVICE_RELEASE :: "wgpuDeviceRelease"
WGPU_SYMBOL_QUEUE_RELEASE :: "wgpuQueueRelease"
WGPU_SYMBOL_DEVICE_POLL :: "wgpuDevicePoll"

WGPU_Offscreen_Procs :: struct {
	create_instance:                        WGPU_Create_Instance_Proc,
	instance_request_adapter:               WGPU_Instance_Request_Adapter_Proc,
	adapter_request_device:                 WGPU_Adapter_Request_Device_Proc,
	device_get_queue:                       WGPU_Device_Get_Queue_Proc,
	device_create_texture:                  WGPU_Device_Create_Texture_Proc,
	device_create_buffer:                   WGPU_Device_Create_Buffer_Proc,
	device_create_bind_group_layout:        WGPU_Device_Create_Bind_Group_Layout_Proc,
	device_create_pipeline_layout:          WGPU_Device_Create_Pipeline_Layout_Proc,
	device_create_sampler:                  WGPU_Device_Create_Sampler_Proc,
	device_create_bind_group:               WGPU_Device_Create_Bind_Group_Proc,
	device_create_shader_module:            WGPU_Device_Create_Shader_Module_Proc,
	device_create_render_pipeline:          WGPU_Device_Create_Render_Pipeline_Proc,
	device_create_command_encoder:          WGPU_Device_Create_Command_Encoder_Proc,
	instance_create_surface:                WGPU_Instance_Create_Surface_Proc,
	surface_configure:                      WGPU_Surface_Configure_Proc,
	surface_get_capabilities:               WGPU_Surface_Get_Capabilities_Proc,
	surface_get_current_texture:            WGPU_Surface_Get_Current_Texture_Proc,
	surface_present:                        WGPU_Surface_Present_Proc,
	surface_unconfigure:                    WGPU_Surface_Unconfigure_Proc,
	surface_capabilities_free_members:      WGPU_Surface_Capabilities_Free_Members_Proc,
	surface_release:                        WGPU_Surface_Release_Proc,
	texture_create_view:                    WGPU_Texture_Create_View_Proc,
	command_encoder_copy_texture_to_buffer: WGPU_Command_Encoder_Copy_Texture_To_Buffer_Proc,
	command_encoder_begin_render_pass:      WGPU_Command_Encoder_Begin_Render_Pass_Proc,
	command_encoder_finish:                 WGPU_Command_Encoder_Finish_Proc,
	queue_submit:                           WGPU_Queue_Submit_Proc,
	queue_write_buffer:                     WGPU_Queue_Write_Buffer_Proc,
	queue_write_texture:                    WGPU_Queue_Write_Texture_Proc,
	render_pass_encoder_set_pipeline:       WGPU_Render_Pass_Encoder_Set_Pipeline_Proc,
	render_pass_encoder_set_bind_group:     WGPU_Render_Pass_Encoder_Set_Bind_Group_Proc,
	render_pass_encoder_set_vertex_buffer:  WGPU_Render_Pass_Encoder_Set_Vertex_Buffer_Proc,
	render_pass_encoder_set_index_buffer:   WGPU_Render_Pass_Encoder_Set_Index_Buffer_Proc,
	render_pass_encoder_set_viewport:       WGPU_Render_Pass_Encoder_Set_Viewport_Proc,
	render_pass_encoder_set_scissor_rect:   WGPU_Render_Pass_Encoder_Set_Scissor_Rect_Proc,
	render_pass_encoder_draw:               WGPU_Render_Pass_Encoder_Draw_Proc,
	render_pass_encoder_draw_indexed:       WGPU_Render_Pass_Encoder_Draw_Indexed_Proc,
	render_pass_encoder_end:                WGPU_Render_Pass_Encoder_End_Proc,
	buffer_map_async:                       WGPU_Buffer_Map_Async_Proc,
	buffer_get_mapped_range:                WGPU_Buffer_Get_Mapped_Range_Proc,
	buffer_unmap:                           WGPU_Buffer_Unmap_Proc,
	instance_process_events:                WGPU_Instance_Process_Events_Proc,
	texture_release:                        WGPU_Texture_Release_Proc,
	texture_view_release:                   WGPU_Texture_View_Release_Proc,
	buffer_release:                         WGPU_Buffer_Release_Proc,
	bind_group_layout_release:              WGPU_Bind_Group_Layout_Release_Proc,
	pipeline_layout_release:                WGPU_Pipeline_Layout_Release_Proc,
	sampler_release:                        WGPU_Sampler_Release_Proc,
	bind_group_release:                     WGPU_Bind_Group_Release_Proc,
	shader_module_release:                  WGPU_Shader_Module_Release_Proc,
	render_pipeline_release:                WGPU_Render_Pipeline_Release_Proc,
	command_encoder_release:                WGPU_Command_Encoder_Release_Proc,
	command_buffer_release:                 WGPU_Command_Buffer_Release_Proc,
	render_pass_encoder_release:            WGPU_Render_Pass_Encoder_Release_Proc,
	instance_release:                       WGPU_Instance_Release_Proc,
	adapter_release:                        WGPU_Adapter_Release_Proc,
	device_release:                         WGPU_Device_Release_Proc,
	queue_release:                          WGPU_Queue_Release_Proc,
	device_poll:                            WGPU_Device_Poll_Proc,
}

WGPU_Offscreen_Dynamic_Library :: struct {
	handle: dynlib.Library,
	procs:  WGPU_Offscreen_Procs,
}

WGPU_Dynlib_Resolver_Context :: struct {
	library: dynlib.Library,
}

WGPU_Adapter_Request_State :: struct {
	complete: bool,
	status:   WGPU_Request_Adapter_Status,
	adapter:  WGPU_Adapter,
}

WGPU_Device_Request_State :: struct {
	complete: bool,
	status:   WGPU_Request_Device_Status,
	device:   WGPU_Device,
}

WGPU_Buffer_Map_State :: struct {
	complete: bool,
	status:   WGPU_Map_Async_Status,
}

wgpu_string_view_null :: proc() -> WGPU_String_View {
	return WGPU_String_View{data = nil, length = WGPU_STRLEN}
}

wgpu_string_view_empty :: proc() -> WGPU_String_View {
	return WGPU_String_View{data = nil, length = 0}
}

wgpu_string_view_from_raw :: proc(data: rawptr, length: c.size_t) -> WGPU_String_View {
	return WGPU_String_View{data = data, length = length}
}

wgpu_string_view_from_string :: proc(value: string) -> WGPU_String_View {
	return WGPU_String_View{data = raw_data(value), length = c.size_t(len(value))}
}

wgpu_surface_source_android_native_window :: proc(window: rawptr) -> WGPU_Surface_Source_Android_Native_Window {
	return WGPU_Surface_Source_Android_Native_Window{
		chain = WGPU_Chained_Struct{next = nil, s_type = WGPU_STYPE_SURFACE_SOURCE_ANDROID_NATIVE_WINDOW},
		window = window,
	}
}

wgpu_surface_source_metal_layer :: proc(layer: rawptr) -> WGPU_Surface_Source_Metal_Layer {
	return WGPU_Surface_Source_Metal_Layer{
		chain = WGPU_Chained_Struct{next = nil, s_type = WGPU_STYPE_SURFACE_SOURCE_METAL_LAYER},
		layer = layer,
	}
}

wgpu_surface_source_wayland_surface :: proc(display, surface: rawptr) -> WGPU_Surface_Source_Wayland_Surface {
	return WGPU_Surface_Source_Wayland_Surface{
		chain = WGPU_Chained_Struct{next = nil, s_type = WGPU_STYPE_SURFACE_SOURCE_WAYLAND_SURFACE},
		display = display,
		surface = surface,
	}
}

wgpu_surface_source_windows_hwnd :: proc(hinstance, hwnd: rawptr) -> WGPU_Surface_Source_Windows_HWND {
	return WGPU_Surface_Source_Windows_HWND{
		chain = WGPU_Chained_Struct{next = nil, s_type = WGPU_STYPE_SURFACE_SOURCE_WINDOWS_HWND},
		hinstance = hinstance,
		hwnd = hwnd,
	}
}

wgpu_surface_source_xcb_window :: proc(connection: rawptr, window: u32) -> WGPU_Surface_Source_XCB_Window {
	return WGPU_Surface_Source_XCB_Window{
		chain = WGPU_Chained_Struct{next = nil, s_type = WGPU_STYPE_SURFACE_SOURCE_XCB_WINDOW},
		connection = connection,
		window = window,
	}
}

wgpu_surface_source_xlib_window :: proc(display: rawptr, window: u64) -> WGPU_Surface_Source_Xlib_Window {
	return WGPU_Surface_Source_Xlib_Window{
		chain = WGPU_Chained_Struct{next = nil, s_type = WGPU_STYPE_SURFACE_SOURCE_XLIB_WINDOW},
		display = display,
		window = window,
	}
}

wgpu_surface_descriptor :: proc(label: WGPU_String_View, chain: ^WGPU_Chained_Struct) -> WGPU_Surface_Descriptor {
	return WGPU_Surface_Descriptor{next_in_chain = chain, label = label}
}

wgpu_surface_descriptor_from_android_native_window :: proc(label: WGPU_String_View, source: ^WGPU_Surface_Source_Android_Native_Window) -> WGPU_Surface_Descriptor {
	return wgpu_surface_descriptor(label, &source.chain)
}

wgpu_surface_descriptor_from_metal_layer :: proc(label: WGPU_String_View, source: ^WGPU_Surface_Source_Metal_Layer) -> WGPU_Surface_Descriptor {
	return wgpu_surface_descriptor(label, &source.chain)
}

wgpu_surface_descriptor_from_wayland_surface :: proc(label: WGPU_String_View, source: ^WGPU_Surface_Source_Wayland_Surface) -> WGPU_Surface_Descriptor {
	return wgpu_surface_descriptor(label, &source.chain)
}

wgpu_surface_descriptor_from_windows_hwnd :: proc(label: WGPU_String_View, source: ^WGPU_Surface_Source_Windows_HWND) -> WGPU_Surface_Descriptor {
	return wgpu_surface_descriptor(label, &source.chain)
}

wgpu_surface_descriptor_from_xcb_window :: proc(label: WGPU_String_View, source: ^WGPU_Surface_Source_XCB_Window) -> WGPU_Surface_Descriptor {
	return wgpu_surface_descriptor(label, &source.chain)
}

wgpu_surface_descriptor_from_xlib_window :: proc(label: WGPU_String_View, source: ^WGPU_Surface_Source_Xlib_Window) -> WGPU_Surface_Descriptor {
	return wgpu_surface_descriptor(label, &source.chain)
}

wgpu_surface_configuration :: proc(device: WGPU_Device, format: WGPU_Texture_Format, width, height: u32, usage: WGPU_Texture_Usage = WGPU_TEXTURE_USAGE_RENDER_ATTACHMENT, present_mode: WGPU_Present_Mode = WGPU_PRESENT_MODE_FIFO, alpha_mode: WGPU_Composite_Alpha_Mode = WGPU_COMPOSITE_ALPHA_MODE_AUTO) -> WGPU_Surface_Configuration {
	return WGPU_Surface_Configuration{
		next_in_chain = nil,
		device = device,
		format = format,
		usage = usage,
		width = width,
		height = height,
		view_format_count = 0,
		view_formats = nil,
		alpha_mode = alpha_mode,
		present_mode = present_mode,
	}
}

wgpu_surface_texture_error :: proc() -> WGPU_Surface_Texture {
	return WGPU_Surface_Texture{
		next_in_chain = nil,
		texture = nil,
		status = WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_ERROR,
	}
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

wgpu_texel_copy_buffer_layout :: proc(bytes_per_row, rows_per_image: u32, offset: u64 = 0) -> WGPU_Texel_Copy_Buffer_Layout {
	return WGPU_Texel_Copy_Buffer_Layout{
		offset = offset,
		bytes_per_row = bytes_per_row,
		rows_per_image = rows_per_image,
	}
}

wgpu_texel_copy_buffer_info :: proc(buffer: WGPU_Buffer, bytes_per_row, rows_per_image: u32) -> WGPU_Texel_Copy_Buffer_Info {
	return WGPU_Texel_Copy_Buffer_Info{
		layout = wgpu_texel_copy_buffer_layout(bytes_per_row, rows_per_image),
		buffer = buffer,
	}
}

wgpu_command_encoder_descriptor :: proc(label: WGPU_String_View) -> WGPU_Command_Encoder_Descriptor {
	return WGPU_Command_Encoder_Descriptor{next_in_chain = nil, label = label}
}

wgpu_command_buffer_descriptor :: proc(label: WGPU_String_View) -> WGPU_Command_Buffer_Descriptor {
	return WGPU_Command_Buffer_Descriptor{next_in_chain = nil, label = label}
}

wgpu_color :: proc(r, g, b, a: f64) -> WGPU_Color {
	return WGPU_Color{r = r, g = g, b = b, a = a}
}

wgpu_color_attachment_clear :: proc(view: WGPU_Texture_View, clear_value: WGPU_Color) -> WGPU_Color_Attachment {
	return WGPU_Color_Attachment{
		next_in_chain = nil,
		view = view,
		depth_slice = WGPU_DEPTH_SLICE_UNDEFINED,
		resolve_target = nil,
		load_op = WGPU_LOAD_OP_CLEAR,
		store_op = WGPU_STORE_OP_STORE,
		clear_value = clear_value,
	}
}

wgpu_color_attachment_load :: proc(view: WGPU_Texture_View) -> WGPU_Color_Attachment {
	return WGPU_Color_Attachment{
		next_in_chain = nil,
		view = view,
		depth_slice = WGPU_DEPTH_SLICE_UNDEFINED,
		resolve_target = nil,
		load_op = WGPU_LOAD_OP_LOAD,
		store_op = WGPU_STORE_OP_STORE,
		clear_value = WGPU_Color{},
	}
}

wgpu_depth_stencil_attachment_clear :: proc(view: WGPU_Texture_View, depth_clear_value: f32 = 1.0) -> WGPU_Depth_Stencil_Attachment {
	return WGPU_Depth_Stencil_Attachment{
		view = view,
		depth_load_op = WGPU_LOAD_OP_CLEAR,
		depth_store_op = WGPU_STORE_OP_STORE,
		depth_clear_value = depth_clear_value,
		depth_read_only = WGPU_FALSE,
		stencil_load_op = WGPU_LOAD_OP_UNDEFINED,
		stencil_store_op = WGPU_STORE_OP_UNDEFINED,
		stencil_clear_value = 0,
		stencil_read_only = WGPU_FALSE,
	}
}

wgpu_render_pass_descriptor :: proc(label: WGPU_String_View, color_attachments: [^]WGPU_Color_Attachment, color_attachment_count: c.size_t, depth_stencil_attachment: ^WGPU_Depth_Stencil_Attachment = nil) -> WGPU_Render_Pass_Descriptor {
	return WGPU_Render_Pass_Descriptor{
		next_in_chain = nil,
		label = label,
		color_attachment_count = color_attachment_count,
		color_attachments = color_attachments,
		depth_stencil_attachment = depth_stencil_attachment,
		occlusion_query_set = nil,
		timestamp_writes = nil,
	}
}

wgpu_buffer_binding_layout_not_used :: proc() -> WGPU_Buffer_Binding_Layout {
	return WGPU_Buffer_Binding_Layout{
		next_in_chain = nil,
		type_ = WGPU_BUFFER_BINDING_TYPE_BINDING_NOT_USED,
		has_dynamic_offset = WGPU_FALSE,
		min_binding_size = 0,
	}
}

wgpu_uniform_buffer_binding_layout :: proc(min_binding_size: u64) -> WGPU_Buffer_Binding_Layout {
	return WGPU_Buffer_Binding_Layout{
		next_in_chain = nil,
		type_ = WGPU_BUFFER_BINDING_TYPE_UNIFORM,
		has_dynamic_offset = WGPU_FALSE,
		min_binding_size = min_binding_size,
	}
}

wgpu_sampler_binding_layout_not_used :: proc() -> WGPU_Sampler_Binding_Layout {
	return WGPU_Sampler_Binding_Layout{
		next_in_chain = nil,
		type_ = WGPU_SAMPLER_BINDING_TYPE_BINDING_NOT_USED,
	}
}

wgpu_sampler_binding_layout :: proc(type_: WGPU_Sampler_Binding_Type) -> WGPU_Sampler_Binding_Layout {
	return WGPU_Sampler_Binding_Layout{
		next_in_chain = nil,
		type_ = type_,
	}
}

wgpu_texture_binding_layout_not_used :: proc() -> WGPU_Texture_Binding_Layout {
	return WGPU_Texture_Binding_Layout{
		next_in_chain = nil,
		sample_type = WGPU_TEXTURE_SAMPLE_TYPE_BINDING_NOT_USED,
		view_dimension = WGPU_TEXTURE_VIEW_DIMENSION_2D,
		multisampled = WGPU_FALSE,
	}
}

wgpu_texture_binding_layout_2d :: proc(sample_type: WGPU_Texture_Sample_Type) -> WGPU_Texture_Binding_Layout {
	return WGPU_Texture_Binding_Layout{
		next_in_chain = nil,
		sample_type = sample_type,
		view_dimension = WGPU_TEXTURE_VIEW_DIMENSION_2D,
		multisampled = WGPU_FALSE,
	}
}

wgpu_storage_texture_binding_layout_not_used :: proc() -> WGPU_Storage_Texture_Binding_Layout {
	return WGPU_Storage_Texture_Binding_Layout{
		next_in_chain = nil,
		access = WGPU_STORAGE_TEXTURE_ACCESS_BINDING_NOT_USED,
		format = WGPU_TEXTURE_FORMAT_UNDEFINED,
		view_dimension = WGPU_TEXTURE_VIEW_DIMENSION_2D,
	}
}

wgpu_bind_group_layout_entry_buffer :: proc(binding: u32, visibility: WGPU_Shader_Stage, min_binding_size: u64) -> WGPU_Bind_Group_Layout_Entry {
	return WGPU_Bind_Group_Layout_Entry{
		next_in_chain = nil,
		binding = binding,
		visibility = visibility,
		buffer = wgpu_uniform_buffer_binding_layout(min_binding_size),
		sampler = wgpu_sampler_binding_layout_not_used(),
		texture = wgpu_texture_binding_layout_not_used(),
		storage_texture = wgpu_storage_texture_binding_layout_not_used(),
	}
}

wgpu_bind_group_layout_entry_texture :: proc(binding: u32, visibility: WGPU_Shader_Stage, sample_type: WGPU_Texture_Sample_Type) -> WGPU_Bind_Group_Layout_Entry {
	return WGPU_Bind_Group_Layout_Entry{
		next_in_chain = nil,
		binding = binding,
		visibility = visibility,
		buffer = wgpu_buffer_binding_layout_not_used(),
		sampler = wgpu_sampler_binding_layout_not_used(),
		texture = wgpu_texture_binding_layout_2d(sample_type),
		storage_texture = wgpu_storage_texture_binding_layout_not_used(),
	}
}

wgpu_bind_group_layout_entry_sampler :: proc(binding: u32, visibility: WGPU_Shader_Stage, type_: WGPU_Sampler_Binding_Type) -> WGPU_Bind_Group_Layout_Entry {
	return WGPU_Bind_Group_Layout_Entry{
		next_in_chain = nil,
		binding = binding,
		visibility = visibility,
		buffer = wgpu_buffer_binding_layout_not_used(),
		sampler = wgpu_sampler_binding_layout(type_),
		texture = wgpu_texture_binding_layout_not_used(),
		storage_texture = wgpu_storage_texture_binding_layout_not_used(),
	}
}

wgpu_bind_group_layout_descriptor :: proc(label: WGPU_String_View, entries: [^]WGPU_Bind_Group_Layout_Entry, entry_count: c.size_t) -> WGPU_Bind_Group_Layout_Descriptor {
	return WGPU_Bind_Group_Layout_Descriptor{
		next_in_chain = nil,
		label = label,
		entry_count = entry_count,
		entries = entries,
	}
}

wgpu_bind_group_entry_buffer :: proc(binding: u32, buffer: WGPU_Buffer, size: u64, offset: u64 = 0) -> WGPU_Bind_Group_Entry {
	return WGPU_Bind_Group_Entry{
		next_in_chain = nil,
		binding = binding,
		buffer = buffer,
		offset = offset,
		size = size,
		sampler = nil,
		texture_view = nil,
	}
}

wgpu_bind_group_entry_texture :: proc(binding: u32, texture_view: WGPU_Texture_View) -> WGPU_Bind_Group_Entry {
	return WGPU_Bind_Group_Entry{
		next_in_chain = nil,
		binding = binding,
		buffer = nil,
		offset = 0,
		size = WGPU_WHOLE_SIZE,
		sampler = nil,
		texture_view = texture_view,
	}
}

wgpu_bind_group_entry_sampler :: proc(binding: u32, sampler: WGPU_Sampler) -> WGPU_Bind_Group_Entry {
	return WGPU_Bind_Group_Entry{
		next_in_chain = nil,
		binding = binding,
		buffer = nil,
		offset = 0,
		size = WGPU_WHOLE_SIZE,
		sampler = sampler,
		texture_view = nil,
	}
}

wgpu_bind_group_descriptor :: proc(label: WGPU_String_View, layout: WGPU_Bind_Group_Layout, entries: [^]WGPU_Bind_Group_Entry, entry_count: c.size_t) -> WGPU_Bind_Group_Descriptor {
	return WGPU_Bind_Group_Descriptor{
		next_in_chain = nil,
		label = label,
		layout = layout,
		entry_count = entry_count,
		entries = entries,
	}
}

wgpu_sampler_descriptor_default :: proc(label: WGPU_String_View) -> WGPU_Sampler_Descriptor {
	return WGPU_Sampler_Descriptor{
		next_in_chain = nil,
		label = label,
		address_mode_u = WGPU_ADDRESS_MODE_CLAMP_TO_EDGE,
		address_mode_v = WGPU_ADDRESS_MODE_CLAMP_TO_EDGE,
		address_mode_w = WGPU_ADDRESS_MODE_CLAMP_TO_EDGE,
		mag_filter = WGPU_FILTER_MODE_NEAREST,
		min_filter = WGPU_FILTER_MODE_NEAREST,
		mipmap_filter = WGPU_MIPMAP_FILTER_MODE_NEAREST,
		lod_min_clamp = 0.0,
		lod_max_clamp = 32.0,
		compare = WGPU_COMPARE_FUNCTION_UNDEFINED,
		max_anisotropy = 1,
	}
}

wgpu_sampler_descriptor_linear :: proc(label: WGPU_String_View, compare: WGPU_Compare_Function = WGPU_COMPARE_FUNCTION_UNDEFINED) -> WGPU_Sampler_Descriptor {
	descriptor := wgpu_sampler_descriptor_default(label)
	descriptor.mag_filter = WGPU_FILTER_MODE_LINEAR
	descriptor.min_filter = WGPU_FILTER_MODE_LINEAR
	descriptor.compare = compare
	return descriptor
}

wgpu_pipeline_layout_descriptor :: proc(label: WGPU_String_View, bind_group_layouts: [^]WGPU_Bind_Group_Layout, bind_group_layout_count: c.size_t) -> WGPU_Pipeline_Layout_Descriptor {
	return WGPU_Pipeline_Layout_Descriptor{
		next_in_chain = nil,
		label = label,
		bind_group_layout_count = bind_group_layout_count,
		bind_group_layouts = bind_group_layouts,
	}
}

wgpu_shader_source_wgsl :: proc(code: WGPU_String_View) -> WGPU_Shader_Source_WGSL {
	return WGPU_Shader_Source_WGSL{
		chain = WGPU_Chained_Struct{next = nil, s_type = WGPU_STYPE_SHADER_SOURCE_WGSL},
		code = code,
	}
}

wgpu_shader_module_descriptor_wgsl :: proc(label: WGPU_String_View, source: ^WGPU_Shader_Source_WGSL) -> WGPU_Shader_Module_Descriptor {
	return WGPU_Shader_Module_Descriptor{
		next_in_chain = &source.chain,
		label = label,
	}
}

wgpu_vertex_attribute :: proc(format: WGPU_Vertex_Format, offset: u64, shader_location: u32) -> WGPU_Vertex_Attribute {
	return WGPU_Vertex_Attribute{
		format = format,
		offset = offset,
		shader_location = shader_location,
	}
}

wgpu_vertex_buffer_layout :: proc(step_mode: WGPU_Vertex_Step_Mode, array_stride: u64, attributes: [^]WGPU_Vertex_Attribute, attribute_count: c.size_t) -> WGPU_Vertex_Buffer_Layout {
	return WGPU_Vertex_Buffer_Layout{
		step_mode = step_mode,
		array_stride = array_stride,
		attribute_count = attribute_count,
		attributes = attributes,
	}
}

wgpu_vertex_state :: proc(module: WGPU_Shader_Module, entry_point: WGPU_String_View, buffers: [^]WGPU_Vertex_Buffer_Layout = nil, buffer_count: c.size_t = 0) -> WGPU_Vertex_State {
	return WGPU_Vertex_State{
		next_in_chain = nil,
		module = module,
		entry_point = entry_point,
		constant_count = 0,
		constants = nil,
		buffer_count = buffer_count,
		buffers = buffers,
	}
}

wgpu_primitive_state :: proc(cull_mode: WGPU_Cull_Mode = WGPU_CULL_MODE_NONE) -> WGPU_Primitive_State {
	return WGPU_Primitive_State{
		next_in_chain = nil,
		topology = WGPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
		strip_index_format = WGPU_INDEX_FORMAT_UNDEFINED,
		front_face = WGPU_FRONT_FACE_CCW,
		cull_mode = cull_mode,
		unclipped_depth = WGPU_FALSE,
	}
}

wgpu_stencil_face_state_default :: proc() -> WGPU_Stencil_Face_State {
	return WGPU_Stencil_Face_State{
		compare = WGPU_COMPARE_FUNCTION_ALWAYS,
		fail_op = WGPU_STENCIL_OPERATION_KEEP,
		depth_fail_op = WGPU_STENCIL_OPERATION_KEEP,
		pass_op = WGPU_STENCIL_OPERATION_KEEP,
	}
}

wgpu_depth_stencil_state :: proc(format: WGPU_Texture_Format, depth_write_enabled: WGPU_Optional_Bool = WGPU_OPTIONAL_BOOL_TRUE, depth_compare: WGPU_Compare_Function = WGPU_COMPARE_FUNCTION_LESS) -> WGPU_Depth_Stencil_State {
	return WGPU_Depth_Stencil_State{
		next_in_chain = nil,
		format = format,
		depth_write_enabled = depth_write_enabled,
		depth_compare = depth_compare,
		stencil_front = wgpu_stencil_face_state_default(),
		stencil_back = wgpu_stencil_face_state_default(),
		stencil_read_mask = 0xFFFFFFFF,
		stencil_write_mask = 0xFFFFFFFF,
		depth_bias = 0,
		depth_bias_slope_scale = 0,
		depth_bias_clamp = 0,
	}
}

wgpu_multisample_state_default :: proc() -> WGPU_Multisample_State {
	return WGPU_Multisample_State{
		next_in_chain = nil,
		count = 1,
		mask = 0xFFFFFFFF,
		alpha_to_coverage_enabled = WGPU_FALSE,
	}
}

wgpu_blend_component_replace :: proc() -> WGPU_Blend_Component {
	return WGPU_Blend_Component{
		operation = WGPU_BLEND_OPERATION_ADD,
		src_factor = WGPU_BLEND_FACTOR_ONE,
		dst_factor = WGPU_BLEND_FACTOR_ZERO,
	}
}

wgpu_blend_component_over :: proc() -> WGPU_Blend_Component {
	return WGPU_Blend_Component{
		operation = WGPU_BLEND_OPERATION_ADD,
		src_factor = WGPU_BLEND_FACTOR_ONE,
		dst_factor = WGPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
	}
}

wgpu_blend_state_alpha_blending :: proc() -> WGPU_Blend_State {
	return WGPU_Blend_State{
		color = WGPU_Blend_Component{
			operation = WGPU_BLEND_OPERATION_ADD,
			src_factor = WGPU_BLEND_FACTOR_SRC_ALPHA,
			dst_factor = WGPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
		},
		alpha = wgpu_blend_component_over(),
	}
}

wgpu_color_target_state :: proc(format: WGPU_Texture_Format, blend: ^WGPU_Blend_State = nil) -> WGPU_Color_Target_State {
	return WGPU_Color_Target_State{
		next_in_chain = nil,
		format = format,
		blend = blend,
		write_mask = WGPU_COLOR_WRITE_MASK_ALL,
	}
}

wgpu_fragment_state :: proc(module: WGPU_Shader_Module, entry_point: WGPU_String_View, targets: [^]WGPU_Color_Target_State, target_count: c.size_t) -> WGPU_Fragment_State {
	return WGPU_Fragment_State{
		next_in_chain = nil,
		module = module,
		entry_point = entry_point,
		constant_count = 0,
		constants = nil,
		target_count = target_count,
		targets = targets,
	}
}

wgpu_render_pipeline_descriptor :: proc(label: WGPU_String_View, layout: WGPU_Pipeline_Layout, vertex: WGPU_Vertex_State, primitive: WGPU_Primitive_State, multisample: WGPU_Multisample_State, fragment: ^WGPU_Fragment_State = nil, depth_stencil: ^WGPU_Depth_Stencil_State = nil) -> WGPU_Render_Pipeline_Descriptor {
	return WGPU_Render_Pipeline_Descriptor{
		next_in_chain = nil,
		label = label,
		layout = layout,
		vertex = vertex,
		primitive = primitive,
		depth_stencil = depth_stencil,
		multisample = multisample,
		fragment = fragment,
	}
}

wgpu_instance_descriptor_default :: proc() -> WGPU_Instance_Descriptor {
	return WGPU_Instance_Descriptor{
		next_in_chain = nil,
		features = WGPU_Instance_Capabilities{
			next_in_chain = nil,
			timed_wait_any_enable = WGPU_FALSE,
			timed_wait_any_max_count = 0,
		},
	}
}

wgpu_request_adapter_options :: proc(compatible_surface: WGPU_Surface = nil) -> WGPU_Request_Adapter_Options {
	return WGPU_Request_Adapter_Options{
		next_in_chain = nil,
		feature_level = WGPU_FEATURE_LEVEL_CORE,
		power_preference = WGPU_POWER_PREFERENCE_UNDEFINED,
		force_fallback_adapter = WGPU_FALSE,
		backend_type = WGPU_BACKEND_TYPE_UNDEFINED,
		compatible_surface = compatible_surface,
	}
}

wgpu_queue_descriptor :: proc(label: WGPU_String_View) -> WGPU_Queue_Descriptor {
	return WGPU_Queue_Descriptor{
		next_in_chain = nil,
		label = label,
	}
}

wgpu_device_lost_callback_info :: proc(callback: WGPU_Device_Lost_Callback, userdata1: rawptr = nil, userdata2: rawptr = nil) -> WGPU_Device_Lost_Callback_Info {
	return WGPU_Device_Lost_Callback_Info{
		next_in_chain = nil,
		mode = WGPU_CALLBACK_MODE_ALLOW_PROCESS_EVENTS,
		callback = callback,
		userdata1 = userdata1,
		userdata2 = userdata2,
	}
}

wgpu_uncaptured_error_callback_info :: proc(callback: WGPU_Uncaptured_Error_Callback = nil, userdata1: rawptr = nil, userdata2: rawptr = nil) -> WGPU_Uncaptured_Error_Callback_Info {
	return WGPU_Uncaptured_Error_Callback_Info{
		next_in_chain = nil,
		callback = callback,
		userdata1 = userdata1,
		userdata2 = userdata2,
	}
}

wgpu_device_descriptor_default :: proc() -> WGPU_Device_Descriptor {
	return WGPU_Device_Descriptor{
		next_in_chain = nil,
		label = wgpu_string_view_empty(),
		required_feature_count = 0,
		required_features = nil,
		required_limits = nil,
		default_queue = wgpu_queue_descriptor(wgpu_string_view_empty()),
		device_lost_callback_info = wgpu_device_lost_callback_info(wgpu_default_device_lost_callback),
		uncaptured_error_callback_info = wgpu_uncaptured_error_callback_info(),
	}
}

wgpu_request_adapter_callback_info :: proc(callback: WGPU_Request_Adapter_Callback, userdata1: rawptr = nil, userdata2: rawptr = nil) -> WGPU_Request_Adapter_Callback_Info {
	return WGPU_Request_Adapter_Callback_Info{
		next_in_chain = nil,
		mode = WGPU_CALLBACK_MODE_ALLOW_PROCESS_EVENTS,
		callback = callback,
		userdata1 = userdata1,
		userdata2 = userdata2,
	}
}

wgpu_request_device_callback_info :: proc(callback: WGPU_Request_Device_Callback, userdata1: rawptr = nil, userdata2: rawptr = nil) -> WGPU_Request_Device_Callback_Info {
	return WGPU_Request_Device_Callback_Info{
		next_in_chain = nil,
		mode = WGPU_CALLBACK_MODE_ALLOW_PROCESS_EVENTS,
		callback = callback,
		userdata1 = userdata1,
		userdata2 = userdata2,
	}
}

wgpu_default_device_lost_callback :: proc "c" (device: rawptr, reason: WGPU_Device_Lost_Reason, message: WGPU_String_View, userdata1, userdata2: rawptr) {
	_ = device
	_ = reason
	_ = message
	_ = userdata1
	_ = userdata2
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

wgpu_resolve_offscreen_procs :: proc(resolver: WGPU_Symbol_Resolver, user_data: rawptr = nil) -> (WGPU_Offscreen_Procs, string, bool) {
	procs: WGPU_Offscreen_Procs
	symbol: rawptr

	symbol = resolver(WGPU_SYMBOL_CREATE_INSTANCE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_CREATE_INSTANCE, false
	procs.create_instance = cast(WGPU_Create_Instance_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_INSTANCE_REQUEST_ADAPTER, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_INSTANCE_REQUEST_ADAPTER, false
	procs.instance_request_adapter = cast(WGPU_Instance_Request_Adapter_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_ADAPTER_REQUEST_DEVICE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_ADAPTER_REQUEST_DEVICE, false
	procs.adapter_request_device = cast(WGPU_Adapter_Request_Device_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_DEVICE_GET_QUEUE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_DEVICE_GET_QUEUE, false
	procs.device_get_queue = cast(WGPU_Device_Get_Queue_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_DEVICE_CREATE_TEXTURE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_DEVICE_CREATE_TEXTURE, false
	procs.device_create_texture = cast(WGPU_Device_Create_Texture_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_DEVICE_CREATE_BUFFER, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_DEVICE_CREATE_BUFFER, false
	procs.device_create_buffer = cast(WGPU_Device_Create_Buffer_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_DEVICE_CREATE_BIND_GROUP_LAYOUT, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_DEVICE_CREATE_BIND_GROUP_LAYOUT, false
	procs.device_create_bind_group_layout = cast(WGPU_Device_Create_Bind_Group_Layout_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_DEVICE_CREATE_PIPELINE_LAYOUT, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_DEVICE_CREATE_PIPELINE_LAYOUT, false
	procs.device_create_pipeline_layout = cast(WGPU_Device_Create_Pipeline_Layout_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_DEVICE_CREATE_SAMPLER, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_DEVICE_CREATE_SAMPLER, false
	procs.device_create_sampler = cast(WGPU_Device_Create_Sampler_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_DEVICE_CREATE_BIND_GROUP, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_DEVICE_CREATE_BIND_GROUP, false
	procs.device_create_bind_group = cast(WGPU_Device_Create_Bind_Group_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_DEVICE_CREATE_SHADER_MODULE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_DEVICE_CREATE_SHADER_MODULE, false
	procs.device_create_shader_module = cast(WGPU_Device_Create_Shader_Module_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_DEVICE_CREATE_RENDER_PIPELINE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_DEVICE_CREATE_RENDER_PIPELINE, false
	procs.device_create_render_pipeline = cast(WGPU_Device_Create_Render_Pipeline_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_DEVICE_CREATE_COMMAND_ENCODER, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_DEVICE_CREATE_COMMAND_ENCODER, false
	procs.device_create_command_encoder = cast(WGPU_Device_Create_Command_Encoder_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_INSTANCE_CREATE_SURFACE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_INSTANCE_CREATE_SURFACE, false
	procs.instance_create_surface = cast(WGPU_Instance_Create_Surface_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_SURFACE_CONFIGURE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_SURFACE_CONFIGURE, false
	procs.surface_configure = cast(WGPU_Surface_Configure_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_SURFACE_GET_CAPABILITIES, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_SURFACE_GET_CAPABILITIES, false
	procs.surface_get_capabilities = cast(WGPU_Surface_Get_Capabilities_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_SURFACE_GET_CURRENT_TEXTURE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_SURFACE_GET_CURRENT_TEXTURE, false
	procs.surface_get_current_texture = cast(WGPU_Surface_Get_Current_Texture_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_SURFACE_PRESENT, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_SURFACE_PRESENT, false
	procs.surface_present = cast(WGPU_Surface_Present_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_SURFACE_UNCONFIGURE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_SURFACE_UNCONFIGURE, false
	procs.surface_unconfigure = cast(WGPU_Surface_Unconfigure_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_SURFACE_CAPABILITIES_FREE_MEMBERS, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_SURFACE_CAPABILITIES_FREE_MEMBERS, false
	procs.surface_capabilities_free_members = cast(WGPU_Surface_Capabilities_Free_Members_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_SURFACE_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_SURFACE_RELEASE, false
	procs.surface_release = cast(WGPU_Surface_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_TEXTURE_CREATE_VIEW, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_TEXTURE_CREATE_VIEW, false
	procs.texture_create_view = cast(WGPU_Texture_Create_View_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_COMMAND_ENCODER_COPY_TEXTURE_TO_BUFFER, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_COMMAND_ENCODER_COPY_TEXTURE_TO_BUFFER, false
	procs.command_encoder_copy_texture_to_buffer = cast(WGPU_Command_Encoder_Copy_Texture_To_Buffer_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_COMMAND_ENCODER_BEGIN_RENDER_PASS, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_COMMAND_ENCODER_BEGIN_RENDER_PASS, false
	procs.command_encoder_begin_render_pass = cast(WGPU_Command_Encoder_Begin_Render_Pass_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_COMMAND_ENCODER_FINISH, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_COMMAND_ENCODER_FINISH, false
	procs.command_encoder_finish = cast(WGPU_Command_Encoder_Finish_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_QUEUE_SUBMIT, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_QUEUE_SUBMIT, false
	procs.queue_submit = cast(WGPU_Queue_Submit_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_QUEUE_WRITE_BUFFER, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_QUEUE_WRITE_BUFFER, false
	procs.queue_write_buffer = cast(WGPU_Queue_Write_Buffer_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_QUEUE_WRITE_TEXTURE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_QUEUE_WRITE_TEXTURE, false
	procs.queue_write_texture = cast(WGPU_Queue_Write_Texture_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_PIPELINE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_PIPELINE, false
	procs.render_pass_encoder_set_pipeline = cast(WGPU_Render_Pass_Encoder_Set_Pipeline_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_BIND_GROUP, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_BIND_GROUP, false
	procs.render_pass_encoder_set_bind_group = cast(WGPU_Render_Pass_Encoder_Set_Bind_Group_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_VERTEX_BUFFER, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_VERTEX_BUFFER, false
	procs.render_pass_encoder_set_vertex_buffer = cast(WGPU_Render_Pass_Encoder_Set_Vertex_Buffer_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_INDEX_BUFFER, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_INDEX_BUFFER, false
	procs.render_pass_encoder_set_index_buffer = cast(WGPU_Render_Pass_Encoder_Set_Index_Buffer_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_VIEWPORT, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_VIEWPORT, false
	procs.render_pass_encoder_set_viewport = cast(WGPU_Render_Pass_Encoder_Set_Viewport_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_SCISSOR_RECT, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_RENDER_PASS_ENCODER_SET_SCISSOR_RECT, false
	procs.render_pass_encoder_set_scissor_rect = cast(WGPU_Render_Pass_Encoder_Set_Scissor_Rect_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_RENDER_PASS_ENCODER_DRAW, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_RENDER_PASS_ENCODER_DRAW, false
	procs.render_pass_encoder_draw = cast(WGPU_Render_Pass_Encoder_Draw_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_RENDER_PASS_ENCODER_DRAW_INDEXED, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_RENDER_PASS_ENCODER_DRAW_INDEXED, false
	procs.render_pass_encoder_draw_indexed = cast(WGPU_Render_Pass_Encoder_Draw_Indexed_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_RENDER_PASS_ENCODER_END, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_RENDER_PASS_ENCODER_END, false
	procs.render_pass_encoder_end = cast(WGPU_Render_Pass_Encoder_End_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_BUFFER_MAP_ASYNC, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_BUFFER_MAP_ASYNC, false
	procs.buffer_map_async = cast(WGPU_Buffer_Map_Async_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_BUFFER_GET_MAPPED_RANGE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_BUFFER_GET_MAPPED_RANGE, false
	procs.buffer_get_mapped_range = cast(WGPU_Buffer_Get_Mapped_Range_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_BUFFER_UNMAP, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_BUFFER_UNMAP, false
	procs.buffer_unmap = cast(WGPU_Buffer_Unmap_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_INSTANCE_PROCESS_EVENTS, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_INSTANCE_PROCESS_EVENTS, false
	procs.instance_process_events = cast(WGPU_Instance_Process_Events_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_TEXTURE_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_TEXTURE_RELEASE, false
	procs.texture_release = cast(WGPU_Texture_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_TEXTURE_VIEW_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_TEXTURE_VIEW_RELEASE, false
	procs.texture_view_release = cast(WGPU_Texture_View_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_BUFFER_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_BUFFER_RELEASE, false
	procs.buffer_release = cast(WGPU_Buffer_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_BIND_GROUP_LAYOUT_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_BIND_GROUP_LAYOUT_RELEASE, false
	procs.bind_group_layout_release = cast(WGPU_Bind_Group_Layout_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_PIPELINE_LAYOUT_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_PIPELINE_LAYOUT_RELEASE, false
	procs.pipeline_layout_release = cast(WGPU_Pipeline_Layout_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_SAMPLER_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_SAMPLER_RELEASE, false
	procs.sampler_release = cast(WGPU_Sampler_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_BIND_GROUP_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_BIND_GROUP_RELEASE, false
	procs.bind_group_release = cast(WGPU_Bind_Group_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_SHADER_MODULE_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_SHADER_MODULE_RELEASE, false
	procs.shader_module_release = cast(WGPU_Shader_Module_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_RENDER_PIPELINE_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_RENDER_PIPELINE_RELEASE, false
	procs.render_pipeline_release = cast(WGPU_Render_Pipeline_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_COMMAND_ENCODER_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_COMMAND_ENCODER_RELEASE, false
	procs.command_encoder_release = cast(WGPU_Command_Encoder_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_COMMAND_BUFFER_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_COMMAND_BUFFER_RELEASE, false
	procs.command_buffer_release = cast(WGPU_Command_Buffer_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_RENDER_PASS_ENCODER_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_RENDER_PASS_ENCODER_RELEASE, false
	procs.render_pass_encoder_release = cast(WGPU_Render_Pass_Encoder_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_INSTANCE_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_INSTANCE_RELEASE, false
	procs.instance_release = cast(WGPU_Instance_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_ADAPTER_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_ADAPTER_RELEASE, false
	procs.adapter_release = cast(WGPU_Adapter_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_DEVICE_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_DEVICE_RELEASE, false
	procs.device_release = cast(WGPU_Device_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_QUEUE_RELEASE, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_QUEUE_RELEASE, false
	procs.queue_release = cast(WGPU_Queue_Release_Proc)symbol

	symbol = resolver(WGPU_SYMBOL_DEVICE_POLL, user_data)
	if symbol == nil do return procs, WGPU_SYMBOL_DEVICE_POLL, false
	procs.device_poll = cast(WGPU_Device_Poll_Proc)symbol

	return procs, "", true
}

wgpu_load_offscreen_library :: proc(path: string) -> (WGPU_Offscreen_Dynamic_Library, string, bool) {
	loaded: WGPU_Offscreen_Dynamic_Library

	library, library_ok := dynlib.load_library(path)
	if !library_ok {
		return loaded, WGPU_OFFSCREEN_LIBRARY_LOAD_ERROR, false
	}

	resolver_context := WGPU_Dynlib_Resolver_Context{library = library}
	procs, missing, procs_ok := wgpu_resolve_offscreen_procs(wgpu_dynlib_symbol_resolver, rawptr(&resolver_context))
	if !procs_ok {
		dynlib.unload_library(library)
		return loaded, missing, false
	}

	loaded.handle = library
	loaded.procs = procs
	return loaded, "", true
}

wgpu_native_dynamic_library_file_name :: proc() -> string {
	when ODIN_OS == .Windows {
		return "wgpu_native.dll"
	}
	when ODIN_OS == .Darwin {
		return "libwgpu_native.dylib"
	}
	return "libwgpu_native.so"
}

wgpu_load_default_offscreen_library :: proc(root: string = ".") -> (WGPU_Offscreen_Dynamic_Library, string, bool) {
	loaded: WGPU_Offscreen_Dynamic_Library
	path, found := wgpu_find_default_offscreen_library(root)
	if !found {
		return loaded, WGPU_OFFSCREEN_LIBRARY_NOT_FOUND, false
	}
	defer delete(path)
	return wgpu_load_offscreen_library(path)
}

wgpu_smoke_offscreen_instance :: proc(procs: WGPU_Offscreen_Procs) -> (string, bool) {
	descriptor := wgpu_instance_descriptor_default()
	instance := procs.create_instance(&descriptor)
	if instance == nil {
		return WGPU_OFFSCREEN_INSTANCE_CREATE_ERROR, false
	}
	procs.instance_release(instance)
	return "", true
}

wgpu_smoke_offscreen_context :: proc(procs: WGPU_Offscreen_Procs, backend_type: WGPU_Backend_Type = WGPU_BACKEND_TYPE_UNDEFINED) -> (string, bool) {
	descriptor := wgpu_instance_descriptor_default()
	instance := procs.create_instance(&descriptor)
	if instance == nil {
		return WGPU_OFFSCREEN_INSTANCE_CREATE_ERROR, false
	}
	defer procs.instance_release(instance)

	adapter, adapter_error, adapter_ok := wgpu_request_adapter_sync(procs, instance, backend_type)
	if !adapter_ok {
		return adapter_error, false
	}
	defer procs.adapter_release(adapter)

	device, device_error, device_ok := wgpu_request_device_sync(procs, instance, adapter)
	if !device_ok {
		return device_error, false
	}
	defer procs.device_release(device)

	queue := procs.device_get_queue(device)
	if queue == nil {
		return WGPU_OFFSCREEN_QUEUE_GET_ERROR, false
	}
	defer procs.queue_release(queue)

	return "", true
}

wgpu_smoke_offscreen_clear_readback :: proc(procs: WGPU_Offscreen_Procs, backend_type: WGPU_Backend_Type = WGPU_BACKEND_TYPE_UNDEFINED) -> (string, bool) {
	descriptor := wgpu_instance_descriptor_default()
	instance := procs.create_instance(&descriptor)
	if instance == nil {
		return WGPU_OFFSCREEN_INSTANCE_CREATE_ERROR, false
	}
	defer procs.instance_release(instance)

	adapter, adapter_error, adapter_ok := wgpu_request_adapter_sync(procs, instance, backend_type)
	if !adapter_ok {
		return adapter_error, false
	}
	defer procs.adapter_release(adapter)

	device, device_error, device_ok := wgpu_request_device_sync(procs, instance, adapter)
	if !device_ok {
		return device_error, false
	}
	defer procs.device_release(device)

	queue := procs.device_get_queue(device)
	if queue == nil {
		return WGPU_OFFSCREEN_QUEUE_GET_ERROR, false
	}
	defer procs.queue_release(queue)

	width :: u32(4)
	height :: u32(4)
	bytes_per_row :: u32(256)
	buffer_size :: u64(bytes_per_row) * u64(height)

	texture_descriptor := wgpu_texture_descriptor_2d(wgpu_string_view_empty(), width, height, WGPU_DEFAULT_TARGET_FORMAT, wgpu_offscreen_texture_usage())
	texture := procs.device_create_texture(device, &texture_descriptor)
	if texture == nil {
		return WGPU_OFFSCREEN_TEXTURE_CREATE_ERROR, false
	}
	defer procs.texture_release(texture)

	view_descriptor := wgpu_single_mip_texture_view_descriptor(wgpu_string_view_empty())
	texture_view := procs.texture_create_view(texture, &view_descriptor)
	if texture_view == nil {
		return WGPU_OFFSCREEN_TEXTURE_VIEW_CREATE_ERROR, false
	}
	defer procs.texture_view_release(texture_view)

	buffer_descriptor := wgpu_buffer_descriptor(wgpu_string_view_empty(), wgpu_staging_buffer_usage(), buffer_size)
	staging_buffer := procs.device_create_buffer(device, &buffer_descriptor)
	if staging_buffer == nil {
		return WGPU_OFFSCREEN_BUFFER_CREATE_ERROR, false
	}
	defer procs.buffer_release(staging_buffer)

	encoder_descriptor := wgpu_command_encoder_descriptor(wgpu_string_view_empty())
	encoder := procs.device_create_command_encoder(device, &encoder_descriptor)
	if encoder == nil {
		return WGPU_OFFSCREEN_COMMAND_ENCODER_CREATE_ERROR, false
	}
	defer procs.command_encoder_release(encoder)

	color_attachments := [?]WGPU_Color_Attachment{
		wgpu_color_attachment_clear(texture_view, wgpu_color(1.0, 1.0, 1.0, 1.0)),
	}
	pass_descriptor := wgpu_render_pass_descriptor(wgpu_string_view_empty(), &color_attachments[0], 1)
	render_pass := procs.command_encoder_begin_render_pass(encoder, &pass_descriptor)
	if render_pass == nil {
		return WGPU_OFFSCREEN_RENDER_PASS_CREATE_ERROR, false
	}
	procs.render_pass_encoder_end(render_pass)
	procs.render_pass_encoder_release(render_pass)

	source := wgpu_texel_copy_texture_info(texture)
	destination := wgpu_texel_copy_buffer_info(staging_buffer, bytes_per_row, height)
	copy_size := wgpu_extent_3d(width, height)
	procs.command_encoder_copy_texture_to_buffer(encoder, &source, &destination, &copy_size)

	command_buffer_descriptor := wgpu_command_buffer_descriptor(wgpu_string_view_empty())
	command_buffer := procs.command_encoder_finish(encoder, &command_buffer_descriptor)
	if command_buffer == nil {
		return WGPU_OFFSCREEN_COMMAND_BUFFER_CREATE_ERROR, false
	}

	command_buffers := [?]WGPU_Command_Buffer{command_buffer}
	procs.queue_submit(queue, 1, &command_buffers[0])
	procs.command_buffer_release(command_buffer)

	map_state := WGPU_Buffer_Map_State{}
	_ = procs.buffer_map_async(
		staging_buffer,
		WGPU_MAP_MODE_READ,
		0,
		c.size_t(buffer_size),
		wgpu_buffer_map_callback_info(wgpu_buffer_map_sync_callback, rawptr(&map_state)),
	)
	if !wgpu_poll_device_until_complete(procs, device, &map_state.complete) {
		return WGPU_OFFSCREEN_REQUEST_TIMEOUT_ERROR, false
	}
	if map_state.status != WGPU_MAP_ASYNC_STATUS_SUCCESS {
		return WGPU_OFFSCREEN_MAP_ERROR, false
	}
	defer procs.buffer_unmap(staging_buffer)

	mapped_raw := procs.buffer_get_mapped_range(staging_buffer, 0, c.size_t(buffer_size))
	if mapped_raw == nil {
		return WGPU_OFFSCREEN_MAPPED_RANGE_ERROR, false
	}

	pixels := transmute([^]u8)mapped_raw
	if pixels[0] < 240 || pixels[1] < 240 || pixels[2] < 240 || pixels[3] < 240 {
		return WGPU_OFFSCREEN_READBACK_ERROR, false
	}

	return "", true
}

wgpu_smoke_offscreen_triangle_readback :: proc(procs: WGPU_Offscreen_Procs, backend_type: WGPU_Backend_Type = WGPU_BACKEND_TYPE_UNDEFINED) -> (string, bool) {
	descriptor := wgpu_instance_descriptor_default()
	instance := procs.create_instance(&descriptor)
	if instance == nil {
		return WGPU_OFFSCREEN_INSTANCE_CREATE_ERROR, false
	}
	defer procs.instance_release(instance)

	adapter, adapter_error, adapter_ok := wgpu_request_adapter_sync(procs, instance, backend_type)
	if !adapter_ok {
		return adapter_error, false
	}
	defer procs.adapter_release(adapter)

	device, device_error, device_ok := wgpu_request_device_sync(procs, instance, adapter)
	if !device_ok {
		return device_error, false
	}
	defer procs.device_release(device)

	queue := procs.device_get_queue(device)
	if queue == nil {
		return WGPU_OFFSCREEN_QUEUE_GET_ERROR, false
	}
	defer procs.queue_release(queue)

	width :: u32(4)
	height :: u32(4)
	bytes_per_row :: u32(256)
	buffer_size :: u64(bytes_per_row) * u64(height)

	texture_descriptor := wgpu_texture_descriptor_2d(wgpu_string_view_empty(), width, height, WGPU_DEFAULT_TARGET_FORMAT, wgpu_offscreen_texture_usage())
	texture := procs.device_create_texture(device, &texture_descriptor)
	if texture == nil {
		return WGPU_OFFSCREEN_TEXTURE_CREATE_ERROR, false
	}
	defer procs.texture_release(texture)

	view_descriptor := wgpu_single_mip_texture_view_descriptor(wgpu_string_view_empty())
	texture_view := procs.texture_create_view(texture, &view_descriptor)
	if texture_view == nil {
		return WGPU_OFFSCREEN_TEXTURE_VIEW_CREATE_ERROR, false
	}
	defer procs.texture_view_release(texture_view)

	buffer_descriptor := wgpu_buffer_descriptor(wgpu_string_view_empty(), wgpu_staging_buffer_usage(), buffer_size)
	staging_buffer := procs.device_create_buffer(device, &buffer_descriptor)
	if staging_buffer == nil {
		return WGPU_OFFSCREEN_BUFFER_CREATE_ERROR, false
	}
	defer procs.buffer_release(staging_buffer)

	shader_source := wgpu_shader_source_wgsl(wgpu_string_view_from_string(WGPU_OFFSCREEN_TRIANGLE_WGSL))
	shader_descriptor := wgpu_shader_module_descriptor_wgsl(wgpu_string_view_empty(), &shader_source)
	shader_module := procs.device_create_shader_module(device, &shader_descriptor)
	if shader_module == nil {
		return WGPU_OFFSCREEN_SHADER_MODULE_CREATE_ERROR, false
	}
	defer procs.shader_module_release(shader_module)

	pipeline_layout_descriptor := wgpu_pipeline_layout_descriptor(wgpu_string_view_empty(), nil, 0)
	pipeline_layout := procs.device_create_pipeline_layout(device, &pipeline_layout_descriptor)
	if pipeline_layout == nil {
		return WGPU_OFFSCREEN_PIPELINE_LAYOUT_CREATE_ERROR, false
	}
	defer procs.pipeline_layout_release(pipeline_layout)

	vertex := wgpu_vertex_state(shader_module, wgpu_string_view_from_string("vs_main"))
	color_targets := [?]WGPU_Color_Target_State{
		wgpu_color_target_state(WGPU_DEFAULT_TARGET_FORMAT),
	}
	fragment := wgpu_fragment_state(shader_module, wgpu_string_view_from_string("fs_main"), &color_targets[0], 1)
	pipeline_descriptor := wgpu_render_pipeline_descriptor(
		wgpu_string_view_empty(),
		pipeline_layout,
		vertex,
		wgpu_primitive_state(),
		wgpu_multisample_state_default(),
		&fragment,
	)
	render_pipeline := procs.device_create_render_pipeline(device, &pipeline_descriptor)
	if render_pipeline == nil {
		return WGPU_OFFSCREEN_RENDER_PIPELINE_CREATE_ERROR, false
	}
	defer procs.render_pipeline_release(render_pipeline)

	encoder_descriptor := wgpu_command_encoder_descriptor(wgpu_string_view_empty())
	encoder := procs.device_create_command_encoder(device, &encoder_descriptor)
	if encoder == nil {
		return WGPU_OFFSCREEN_COMMAND_ENCODER_CREATE_ERROR, false
	}
	defer procs.command_encoder_release(encoder)

	color_attachments := [?]WGPU_Color_Attachment{
		wgpu_color_attachment_clear(texture_view, wgpu_color(0.0, 0.0, 0.0, 1.0)),
	}
	pass_descriptor := wgpu_render_pass_descriptor(wgpu_string_view_empty(), &color_attachments[0], 1)
	render_pass := procs.command_encoder_begin_render_pass(encoder, &pass_descriptor)
	if render_pass == nil {
		return WGPU_OFFSCREEN_RENDER_PASS_CREATE_ERROR, false
	}
	procs.render_pass_encoder_set_pipeline(render_pass, render_pipeline)
	procs.render_pass_encoder_draw(render_pass, 3, 1, 0, 0)
	procs.render_pass_encoder_end(render_pass)
	procs.render_pass_encoder_release(render_pass)

	source := wgpu_texel_copy_texture_info(texture)
	destination := wgpu_texel_copy_buffer_info(staging_buffer, bytes_per_row, height)
	copy_size := wgpu_extent_3d(width, height)
	procs.command_encoder_copy_texture_to_buffer(encoder, &source, &destination, &copy_size)

	command_buffer_descriptor := wgpu_command_buffer_descriptor(wgpu_string_view_empty())
	command_buffer := procs.command_encoder_finish(encoder, &command_buffer_descriptor)
	if command_buffer == nil {
		return WGPU_OFFSCREEN_COMMAND_BUFFER_CREATE_ERROR, false
	}

	command_buffers := [?]WGPU_Command_Buffer{command_buffer}
	procs.queue_submit(queue, 1, &command_buffers[0])
	procs.command_buffer_release(command_buffer)

	map_state := WGPU_Buffer_Map_State{}
	_ = procs.buffer_map_async(
		staging_buffer,
		WGPU_MAP_MODE_READ,
		0,
		c.size_t(buffer_size),
		wgpu_buffer_map_callback_info(wgpu_buffer_map_sync_callback, rawptr(&map_state)),
	)
	if !wgpu_poll_device_until_complete(procs, device, &map_state.complete) {
		return WGPU_OFFSCREEN_REQUEST_TIMEOUT_ERROR, false
	}
	if map_state.status != WGPU_MAP_ASYNC_STATUS_SUCCESS {
		return WGPU_OFFSCREEN_MAP_ERROR, false
	}
	defer procs.buffer_unmap(staging_buffer)

	mapped_raw := procs.buffer_get_mapped_range(staging_buffer, 0, c.size_t(buffer_size))
	if mapped_raw == nil {
		return WGPU_OFFSCREEN_MAPPED_RANGE_ERROR, false
	}

	pixels := transmute([^]u8)mapped_raw
	if pixels[0] > 16 || pixels[1] > 16 || pixels[2] < 240 || pixels[3] < 240 {
		return WGPU_OFFSCREEN_READBACK_ERROR, false
	}

	return "", true
}

wgpu_render_offscreen_triangle_image :: proc(procs: WGPU_Offscreen_Procs, width, height: int, backend_type: WGPU_Backend_Type = WGPU_BACKEND_TYPE_UNDEFINED) -> (Render_Image, string, bool) {
	if width <= 0 || height <= 0 {
		return Render_Image{}, WGPU_OFFSCREEN_INVALID_SIZE_ERROR, false
	}

	descriptor := wgpu_instance_descriptor_default()
	instance := procs.create_instance(&descriptor)
	if instance == nil {
		return Render_Image{}, WGPU_OFFSCREEN_INSTANCE_CREATE_ERROR, false
	}
	defer procs.instance_release(instance)

	adapter, adapter_error, adapter_ok := wgpu_request_adapter_sync(procs, instance, backend_type)
	if !adapter_ok {
		return Render_Image{}, adapter_error, false
	}
	defer procs.adapter_release(adapter)

	device, device_error, device_ok := wgpu_request_device_sync(procs, instance, adapter)
	if !device_ok {
		return Render_Image{}, device_error, false
	}
	defer procs.device_release(device)

	queue := procs.device_get_queue(device)
	if queue == nil {
		return Render_Image{}, WGPU_OFFSCREEN_QUEUE_GET_ERROR, false
	}
	defer procs.queue_release(queue)

	width_u32 := u32(width)
	height_u32 := u32(height)
	bytes_per_row := wgpu_align_to_u32(width_u32 * 4, 256)
	buffer_size := u64(bytes_per_row) * u64(height_u32)

	texture_descriptor := wgpu_texture_descriptor_2d(wgpu_string_view_empty(), width_u32, height_u32, WGPU_DEFAULT_TARGET_FORMAT, wgpu_offscreen_texture_usage())
	texture := procs.device_create_texture(device, &texture_descriptor)
	if texture == nil {
		return Render_Image{}, WGPU_OFFSCREEN_TEXTURE_CREATE_ERROR, false
	}
	defer procs.texture_release(texture)

	view_descriptor := wgpu_single_mip_texture_view_descriptor(wgpu_string_view_empty())
	texture_view := procs.texture_create_view(texture, &view_descriptor)
	if texture_view == nil {
		return Render_Image{}, WGPU_OFFSCREEN_TEXTURE_VIEW_CREATE_ERROR, false
	}
	defer procs.texture_view_release(texture_view)

	buffer_descriptor := wgpu_buffer_descriptor(wgpu_string_view_empty(), wgpu_staging_buffer_usage(), buffer_size)
	staging_buffer := procs.device_create_buffer(device, &buffer_descriptor)
	if staging_buffer == nil {
		return Render_Image{}, WGPU_OFFSCREEN_BUFFER_CREATE_ERROR, false
	}
	defer procs.buffer_release(staging_buffer)

	shader_source := wgpu_shader_source_wgsl(wgpu_string_view_from_string(WGPU_OFFSCREEN_TRIANGLE_WGSL))
	shader_descriptor := wgpu_shader_module_descriptor_wgsl(wgpu_string_view_empty(), &shader_source)
	shader_module := procs.device_create_shader_module(device, &shader_descriptor)
	if shader_module == nil {
		return Render_Image{}, WGPU_OFFSCREEN_SHADER_MODULE_CREATE_ERROR, false
	}
	defer procs.shader_module_release(shader_module)

	pipeline_layout_descriptor := wgpu_pipeline_layout_descriptor(wgpu_string_view_empty(), nil, 0)
	pipeline_layout := procs.device_create_pipeline_layout(device, &pipeline_layout_descriptor)
	if pipeline_layout == nil {
		return Render_Image{}, WGPU_OFFSCREEN_PIPELINE_LAYOUT_CREATE_ERROR, false
	}
	defer procs.pipeline_layout_release(pipeline_layout)

	vertex := wgpu_vertex_state(shader_module, wgpu_string_view_from_string("vs_main"))
	color_targets := [?]WGPU_Color_Target_State{
		wgpu_color_target_state(WGPU_DEFAULT_TARGET_FORMAT),
	}
	fragment := wgpu_fragment_state(shader_module, wgpu_string_view_from_string("fs_main"), &color_targets[0], 1)
	pipeline_descriptor := wgpu_render_pipeline_descriptor(
		wgpu_string_view_empty(),
		pipeline_layout,
		vertex,
		wgpu_primitive_state(),
		wgpu_multisample_state_default(),
		&fragment,
	)
	render_pipeline := procs.device_create_render_pipeline(device, &pipeline_descriptor)
	if render_pipeline == nil {
		return Render_Image{}, WGPU_OFFSCREEN_RENDER_PIPELINE_CREATE_ERROR, false
	}
	defer procs.render_pipeline_release(render_pipeline)

	encoder_descriptor := wgpu_command_encoder_descriptor(wgpu_string_view_empty())
	encoder := procs.device_create_command_encoder(device, &encoder_descriptor)
	if encoder == nil {
		return Render_Image{}, WGPU_OFFSCREEN_COMMAND_ENCODER_CREATE_ERROR, false
	}
	defer procs.command_encoder_release(encoder)

	color_attachments := [?]WGPU_Color_Attachment{
		wgpu_color_attachment_clear(texture_view, wgpu_color(0.0, 0.0, 0.0, 1.0)),
	}
	pass_descriptor := wgpu_render_pass_descriptor(wgpu_string_view_empty(), &color_attachments[0], 1)
	render_pass := procs.command_encoder_begin_render_pass(encoder, &pass_descriptor)
	if render_pass == nil {
		return Render_Image{}, WGPU_OFFSCREEN_RENDER_PASS_CREATE_ERROR, false
	}
	procs.render_pass_encoder_set_pipeline(render_pass, render_pipeline)
	procs.render_pass_encoder_draw(render_pass, 3, 1, 0, 0)
	procs.render_pass_encoder_end(render_pass)
	procs.render_pass_encoder_release(render_pass)

	source := wgpu_texel_copy_texture_info(texture)
	destination := wgpu_texel_copy_buffer_info(staging_buffer, bytes_per_row, height_u32)
	copy_size := wgpu_extent_3d(width_u32, height_u32)
	procs.command_encoder_copy_texture_to_buffer(encoder, &source, &destination, &copy_size)

	command_buffer_descriptor := wgpu_command_buffer_descriptor(wgpu_string_view_empty())
	command_buffer := procs.command_encoder_finish(encoder, &command_buffer_descriptor)
	if command_buffer == nil {
		return Render_Image{}, WGPU_OFFSCREEN_COMMAND_BUFFER_CREATE_ERROR, false
	}

	command_buffers := [?]WGPU_Command_Buffer{command_buffer}
	procs.queue_submit(queue, 1, &command_buffers[0])
	procs.command_buffer_release(command_buffer)

	map_state := WGPU_Buffer_Map_State{}
	_ = procs.buffer_map_async(
		staging_buffer,
		WGPU_MAP_MODE_READ,
		0,
		c.size_t(buffer_size),
		wgpu_buffer_map_callback_info(wgpu_buffer_map_sync_callback, rawptr(&map_state)),
	)
	if !wgpu_poll_device_until_complete(procs, device, &map_state.complete) {
		return Render_Image{}, WGPU_OFFSCREEN_REQUEST_TIMEOUT_ERROR, false
	}
	if map_state.status != WGPU_MAP_ASYNC_STATUS_SUCCESS {
		return Render_Image{}, WGPU_OFFSCREEN_MAP_ERROR, false
	}
	defer procs.buffer_unmap(staging_buffer)

	mapped_raw := procs.buffer_get_mapped_range(staging_buffer, 0, c.size_t(buffer_size))
	if mapped_raw == nil {
		return Render_Image{}, WGPU_OFFSCREEN_MAPPED_RANGE_ERROR, false
	}

	rgb := make([]u8, width * height * 3)
	if rgb == nil {
		return Render_Image{}, WGPU_OFFSCREEN_READBACK_ERROR, false
	}

	pixels := transmute([^]u8)mapped_raw
	for y in 0 ..< height {
		source_row := y * int(bytes_per_row)
		for x in 0 ..< width {
			source_pixel := source_row + x * 4
			target_pixel := (y * width + x) * 3
			rgb[target_pixel + 0] = pixels[source_pixel + 2]
			rgb[target_pixel + 1] = pixels[source_pixel + 1]
			rgb[target_pixel + 2] = pixels[source_pixel + 0]
		}
	}

	return Render_Image{width = width, height = height, rgb = rgb}, "", true
}

wgpu_render_scene_image :: proc(world: Runtime_World, options: Render_Options, backend_type: WGPU_Backend_Type = WGPU_BACKEND_TYPE_UNDEFINED) -> (Render_Image, string, bool) {
	path, found := wgpu_find_default_offscreen_library(options.target_path)
	if !found && options.target_path != "." {
		path, found = wgpu_find_default_offscreen_library(".")
	}
	if !found {
		return Render_Image{}, WGPU_OFFSCREEN_LIBRARY_NOT_FOUND, false
	}
	defer delete(path)

	loaded, missing, loaded_ok := wgpu_load_offscreen_library(path)
	defer wgpu_unload_offscreen_library(&loaded)
	if !loaded_ok {
		if missing == "" {
			missing = WGPU_OFFSCREEN_LIBRARY_LOAD_ERROR
		}
		return Render_Image{}, missing, false
	}

	return wgpu_render_scene_image_with_procs(loaded.procs, world, options, backend_type)
}

wgpu_render_scene_image_with_procs :: proc(procs: WGPU_Offscreen_Procs, world: Runtime_World, options: Render_Options, backend_type: WGPU_Backend_Type = WGPU_BACKEND_TYPE_UNDEFINED) -> (Render_Image, string, bool) {
	if options.width <= 0 || options.height <= 0 {
		return Render_Image{}, WGPU_OFFSCREEN_INVALID_SIZE_ERROR, false
	}

	vertices: [dynamic]WGPU_Scene_Vertex
	defer delete(vertices)
	wgpu_collect_scene_vertices_with_options(&vertices, world, options)
	if options.editor {
		if options.selected_entity_id != "" {
			wgpu_append_editor_chrome_vertices_for_selection(
				&vertices,
				world,
				options.width,
				options.height,
				options.selected_entity_id,
				options.inspector_scroll_y,
				options.gizmo_axis,
				options.gizmo_hover_axis,
				options.gizmo_local_space,
				options.camera_override_enabled,
				options.camera_override,
			)
		} else {
			wgpu_append_editor_chrome_vertices(&vertices, options.width, options.height)
		}
	}

	descriptor := wgpu_instance_descriptor_default()
	instance := procs.create_instance(&descriptor)
	if instance == nil {
		return Render_Image{}, WGPU_OFFSCREEN_INSTANCE_CREATE_ERROR, false
	}
	defer procs.instance_release(instance)

	adapter, adapter_error, adapter_ok := wgpu_request_adapter_sync(procs, instance, backend_type)
	if !adapter_ok {
		return Render_Image{}, adapter_error, false
	}
	defer procs.adapter_release(adapter)

	device, device_error, device_ok := wgpu_request_device_sync(procs, instance, adapter)
	if !device_ok {
		return Render_Image{}, device_error, false
	}
	defer procs.device_release(device)

	queue := procs.device_get_queue(device)
	if queue == nil {
		return Render_Image{}, WGPU_OFFSCREEN_QUEUE_GET_ERROR, false
	}
	defer procs.queue_release(queue)

	width_u32 := u32(options.width)
	height_u32 := u32(options.height)
	bytes_per_row := wgpu_align_to_u32(width_u32 * 4, 256)
	buffer_size := u64(bytes_per_row) * u64(height_u32)

	texture_descriptor := wgpu_texture_descriptor_2d(wgpu_string_view_empty(), width_u32, height_u32, WGPU_DEFAULT_TARGET_FORMAT, wgpu_offscreen_texture_usage())
	texture := procs.device_create_texture(device, &texture_descriptor)
	if texture == nil {
		return Render_Image{}, WGPU_OFFSCREEN_TEXTURE_CREATE_ERROR, false
	}
	defer procs.texture_release(texture)

	view_descriptor := wgpu_single_mip_texture_view_descriptor(wgpu_string_view_empty())
	texture_view := procs.texture_create_view(texture, &view_descriptor)
	if texture_view == nil {
		return Render_Image{}, WGPU_OFFSCREEN_TEXTURE_VIEW_CREATE_ERROR, false
	}
	defer procs.texture_view_release(texture_view)

	staging_descriptor := wgpu_buffer_descriptor(wgpu_string_view_empty(), wgpu_staging_buffer_usage(), buffer_size)
	staging_buffer := procs.device_create_buffer(device, &staging_descriptor)
	if staging_buffer == nil {
		return Render_Image{}, WGPU_OFFSCREEN_BUFFER_CREATE_ERROR, false
	}
	defer procs.buffer_release(staging_buffer)

	shader_module: WGPU_Shader_Module
	pipeline_layout: WGPU_Pipeline_Layout
	render_pipeline: WGPU_Render_Pipeline
	defer wgpu_release_scene_pipeline_resources(procs, &shader_module, &pipeline_layout, &render_pipeline)
	if len(vertices) > 0 {
		shader_code := wgpu_scene_rect_wgsl(vertices[:])
		defer delete(shader_code)
		shader_source := wgpu_shader_source_wgsl(wgpu_string_view_from_string(shader_code))
		shader_descriptor := wgpu_shader_module_descriptor_wgsl(wgpu_string_view_empty(), &shader_source)
		shader_module = procs.device_create_shader_module(device, &shader_descriptor)
		if shader_module == nil {
			return Render_Image{}, WGPU_OFFSCREEN_SHADER_MODULE_CREATE_ERROR, false
		}

		pipeline_layout_descriptor := wgpu_pipeline_layout_descriptor(wgpu_string_view_empty(), nil, 0)
		pipeline_layout = procs.device_create_pipeline_layout(device, &pipeline_layout_descriptor)
		if pipeline_layout == nil {
			return Render_Image{}, WGPU_OFFSCREEN_PIPELINE_LAYOUT_CREATE_ERROR, false
		}

		vertex := wgpu_vertex_state(shader_module, wgpu_string_view_from_string("vs_main"))
		color_targets := [?]WGPU_Color_Target_State{
			wgpu_color_target_state(WGPU_DEFAULT_TARGET_FORMAT),
		}
		fragment := wgpu_fragment_state(shader_module, wgpu_string_view_from_string("fs_main"), &color_targets[0], 1)
		pipeline_descriptor := wgpu_render_pipeline_descriptor(
			wgpu_string_view_empty(),
			pipeline_layout,
			vertex,
			wgpu_primitive_state(),
			wgpu_multisample_state_default(),
			&fragment,
		)
		render_pipeline = procs.device_create_render_pipeline(device, &pipeline_descriptor)
		if render_pipeline == nil {
			return Render_Image{}, WGPU_OFFSCREEN_RENDER_PIPELINE_CREATE_ERROR, false
		}
	}

	encoder_descriptor := wgpu_command_encoder_descriptor(wgpu_string_view_empty())
	encoder := procs.device_create_command_encoder(device, &encoder_descriptor)
	if encoder == nil {
		return Render_Image{}, WGPU_OFFSCREEN_COMMAND_ENCODER_CREATE_ERROR, false
	}
	defer procs.command_encoder_release(encoder)

	background := wgpu_color(0.006049, 0.008023, 0.012286, 1.0)
	color_attachments := [?]WGPU_Color_Attachment{
		wgpu_color_attachment_clear(texture_view, background),
	}
	pass_descriptor := wgpu_render_pass_descriptor(wgpu_string_view_empty(), &color_attachments[0], 1)
	render_pass := procs.command_encoder_begin_render_pass(encoder, &pass_descriptor)
	if render_pass == nil {
		return Render_Image{}, WGPU_OFFSCREEN_RENDER_PASS_CREATE_ERROR, false
	}
	if len(vertices) > 0 {
		procs.render_pass_encoder_set_pipeline(render_pass, render_pipeline)
		procs.render_pass_encoder_draw(render_pass, u32(len(vertices)), 1, 0, 0)
	}
	procs.render_pass_encoder_end(render_pass)
	procs.render_pass_encoder_release(render_pass)

	source := wgpu_texel_copy_texture_info(texture)
	destination := wgpu_texel_copy_buffer_info(staging_buffer, bytes_per_row, height_u32)
	copy_size := wgpu_extent_3d(width_u32, height_u32)
	procs.command_encoder_copy_texture_to_buffer(encoder, &source, &destination, &copy_size)

	command_buffer_descriptor := wgpu_command_buffer_descriptor(wgpu_string_view_empty())
	command_buffer := procs.command_encoder_finish(encoder, &command_buffer_descriptor)
	if command_buffer == nil {
		return Render_Image{}, WGPU_OFFSCREEN_COMMAND_BUFFER_CREATE_ERROR, false
	}

	command_buffers := [?]WGPU_Command_Buffer{command_buffer}
	procs.queue_submit(queue, 1, &command_buffers[0])
	procs.command_buffer_release(command_buffer)

	map_state := WGPU_Buffer_Map_State{}
	_ = procs.buffer_map_async(
		staging_buffer,
		WGPU_MAP_MODE_READ,
		0,
		c.size_t(buffer_size),
		wgpu_buffer_map_callback_info(wgpu_buffer_map_sync_callback, rawptr(&map_state)),
	)
	if !wgpu_poll_device_until_complete(procs, device, &map_state.complete) {
		return Render_Image{}, WGPU_OFFSCREEN_REQUEST_TIMEOUT_ERROR, false
	}
	if map_state.status != WGPU_MAP_ASYNC_STATUS_SUCCESS {
		return Render_Image{}, WGPU_OFFSCREEN_MAP_ERROR, false
	}
	defer procs.buffer_unmap(staging_buffer)

	mapped_raw := procs.buffer_get_mapped_range(staging_buffer, 0, c.size_t(buffer_size))
	if mapped_raw == nil {
		return Render_Image{}, WGPU_OFFSCREEN_MAPPED_RANGE_ERROR, false
	}

	rgb := make([]u8, options.width * options.height * 3)
	if rgb == nil {
		return Render_Image{}, WGPU_OFFSCREEN_READBACK_ERROR, false
	}

	pixels := transmute([^]u8)mapped_raw
	for y in 0 ..< options.height {
		source_row := y * int(bytes_per_row)
		for x in 0 ..< options.width {
			source_pixel := source_row + x * 4
			target_pixel := (y * options.width + x) * 3
			rgb[target_pixel + 0] = pixels[source_pixel + 2]
			rgb[target_pixel + 1] = pixels[source_pixel + 1]
			rgb[target_pixel + 2] = pixels[source_pixel + 0]
		}
	}

	return Render_Image{width = options.width, height = options.height, rgb = rgb}, "", true
}

wgpu_collect_scene_vertices :: proc(vertices: ^[dynamic]WGPU_Scene_Vertex, world: Runtime_World, width, height: int) {
	wgpu_collect_scene_vertices_with_options(vertices, world, Render_Options{width = width, height = height})
}

wgpu_collect_scene_vertices_with_options :: proc(vertices: ^[dynamic]WGPU_Scene_Vertex, world: Runtime_World, options: Render_Options) {
	cursor := 0
	index := 0
	for {
		entity, found := runtime_world_query_next(world, []string{TRANSFORM_COMPONENT_ID}, &cursor)
		if !found {
			break
		}
		has_geometry := render_entity_has_component(world, entity, GEOMETRY_PRIMITIVE_COMPONENT_ID) &&
		                render_entity_has_component(world, entity, SURFACE_MATERIAL_COMPONENT_ID)
		has_legacy_cube := render_entity_has_component(world, entity, CUBE_RENDERER_COMPONENT_ID)
		if !has_geometry && !has_legacy_cube {
			continue
		}
		color := render_entity_color(world, entity, index)
		rect, rect_ok := render_renderable_rect_for_entity(world, entity, options.width, options.height, index, options)
		if rect_ok {
			wgpu_append_rect_vertices(vertices, options.width, options.height, rect, color)
		}
		index += 1
	}
}

wgpu_append_editor_chrome_vertices :: proc(vertices: ^[dynamic]WGPU_Scene_Vertex, width, height: int) -> int {
	if width <= 0 || height <= 0 {
		return 0
	}
	top_height := min(max(24, height / 12), max(1, height / 3))
	bottom_height := min(max(18, height / 16), max(1, height / 5))
	body_y := top_height
	body_height := max(0, height - top_height - bottom_height)
	left_width := min(max(72, width / 5), max(1, width / 3))
	right_width := min(max(96, width * 3 / 10), max(1, width / 3))
	if left_width + right_width + 48 > width {
		left_width = max(8, width / 5)
		right_width = max(8, width / 4)
	}
	viewport_x := left_width
	viewport_width := max(0, width - left_width - right_width)

	count := 0
	count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = 0, y = 0, width = width, height = top_height}, EDITOR_CHROME_TOP_COLOR)
	count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = 0, y = height - bottom_height, width = width, height = bottom_height}, EDITOR_CHROME_BOTTOM_COLOR)
	count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = 0, y = body_y, width = left_width, height = body_height}, EDITOR_CHROME_PANEL_COLOR)
	count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = width - right_width, y = body_y, width = right_width, height = body_height}, EDITOR_CHROME_PANEL_COLOR)
	count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = 0, y = top_height - 2, width = width, height = 2}, EDITOR_CHROME_RULE_COLOR)
	count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = 0, y = height - bottom_height, width = width, height = 2}, EDITOR_CHROME_RULE_COLOR)
	count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = left_width - 2, y = body_y, width = 2, height = body_height}, EDITOR_CHROME_RULE_COLOR)
	count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = width - right_width, y = body_y, width = 2, height = body_height}, EDITOR_CHROME_RULE_COLOR)
	if viewport_width > 0 && body_height > 0 {
		count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = viewport_x, y = body_y, width = viewport_width, height = 2}, EDITOR_CHROME_VIEWPORT_COLOR)
		count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = viewport_x, y = body_y + body_height - 2, width = viewport_width, height = 2}, EDITOR_CHROME_VIEWPORT_COLOR)
		count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = viewport_x, y = body_y, width = 2, height = body_height}, EDITOR_CHROME_VIEWPORT_COLOR)
		count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = viewport_x + viewport_width - 2, y = body_y, width = 2, height = body_height}, EDITOR_CHROME_VIEWPORT_COLOR)
	}
	return count
}

wgpu_append_editor_chrome_vertices_for_selection :: proc(
	vertices: ^[dynamic]WGPU_Scene_Vertex,
	world: Runtime_World,
	width, height: int,
	selected_entity_id: string,
	inspector_scroll_y: f32 = 0,
	gizmo_axis: Editor_Test_Axis = .None,
	gizmo_hover_axis: Editor_Test_Axis = .None,
	gizmo_local_space: bool = false,
	camera_override_enabled: bool = false,
	camera_override: Editor_Test_Camera_State = {},
) -> int {
	count := wgpu_append_editor_chrome_vertices(vertices, width, height)
	if selected_entity_id == "" || width <= 0 || height <= 0 {
		return count
	}
	count += wgpu_append_editor_gizmo_vertices(
		vertices,
		world,
		width,
		height,
		selected_entity_id,
		gizmo_axis,
		gizmo_hover_axis,
		gizmo_local_space,
		camera_override_enabled,
		camera_override,
	)

	top_height := min(max(24, height / 12), max(1, height / 3))
	bottom_height := min(max(18, height / 16), max(1, height / 5))
	body_y := top_height
	body_height := max(0, height - top_height - bottom_height)
	right_width := min(max(96, width * 3 / 10), max(1, width / 3))
	left_width := min(max(72, width / 5), max(1, width / 3))
	if left_width + right_width + 48 > width {
		right_width = max(8, width / 4)
	}
	if right_width <= 24 || body_height <= 28 {
		return count
	}

	right_x := width - right_width
	accent_x := right_x + 12
	accent_y := body_y + 14
	accent_width := max(4, right_width - 24)
	accent_height := min(max(8, body_height / 18), body_height - 28)
	count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = accent_x, y = accent_y, width = accent_width, height = accent_height}, EDITOR_CHROME_SELECTION_COLOR)
	count += wgpu_append_editor_inspector_card_vertices(vertices, world, width, height, selected_entity_id, right_x, body_y, right_width, body_height, inspector_scroll_y)
	return count
}

wgpu_append_editor_gizmo_vertices :: proc(
	vertices: ^[dynamic]WGPU_Scene_Vertex,
	world: Runtime_World,
	width, height: int,
	selected_entity_id: string,
	active_axis: Editor_Test_Axis,
	hover_axis: Editor_Test_Axis,
	local_space: bool,
	camera_override_enabled: bool,
	camera_override: Editor_Test_Camera_State,
) -> int {
	entity, entity_ok := runtime_world_find_entity_by_id(world, selected_entity_id)
	if !entity_ok {
		return 0
	}
	position, position_ok := editor_test_transform_position(world, entity)
	if !position_ok {
		return 0
	}
	camera := render_options_camera(
		world,
		Render_Options{
			width = width,
			height = height,
			editor = true,
			camera_override_enabled = camera_override_enabled,
			camera_override = camera_override,
		},
	)
	viewport := render_scene_viewport(width, height, true)
	origin, origin_ok := render_project_world_to_viewport(position, camera, viewport)
	if !origin_ok || !render_screen_point_in_viewport(origin, viewport) {
		return 0
	}
	count := 0
	axes := [?]Editor_Test_Axis{.X, .Y, .Z}
	for axis in axes {
		vector, vector_ok := editor_gizmo_axis_vector(world, entity, axis, local_space)
		if !vector_ok {
			continue
		}
		end, end_ok := render_project_world_to_viewport(editor_test_add_vec3(position, editor_test_scale_vec3(vector, EDITOR_TEST_GIZMO_AXIS_LENGTH)), camera, viewport)
		if !end_ok || !render_screen_point_in_viewport(end, viewport) {
			continue
		}
		color := render_gizmo_axis_color(axis, active_axis, hover_axis)
		thickness := 3
		if axis == active_axis {
			thickness = 5
		} else if axis == hover_axis {
			thickness = 4
		}
		count += wgpu_append_screen_line_rects(vertices, width, height, origin, end, thickness, color)
		tip_size := thickness + 2
		tip_radius := max(2, tip_size / 2)
		tip_x := int(end[0] + 0.5) - tip_radius
		tip_y := int(end[1] + 0.5) - tip_radius
		count += wgpu_append_chrome_rect(
			vertices,
			width,
			height,
			Renderable_Rect{x = tip_x, y = tip_y, width = tip_radius * 2 + 1, height = tip_radius * 2 + 1},
			color,
		)
	}
	return count
}

wgpu_append_screen_line_rects :: proc(
	vertices: ^[dynamic]WGPU_Scene_Vertex,
	width, height: int,
	start, end: [2]f32,
	thickness: int,
	color: [3]u8,
) -> int {
	dx := end[0] - start[0]
	dy := end[1] - start[1]
	steps := max(1, int(max_f32(render_abs_f32(dx), render_abs_f32(dy)) + 0.5))
	radius := max(1, thickness / 2)
	count := 0
	for step in 0 ..= steps {
		t := f32(step) / f32(steps)
		x := int(start[0] + dx * t + 0.5)
		y := int(start[1] + dy * t + 0.5)
		count += wgpu_append_chrome_rect(
			vertices,
			width,
			height,
			Renderable_Rect{x = x - radius, y = y - radius, width = max(1, thickness), height = max(1, thickness)},
			color,
		)
	}
	return count
}

wgpu_append_editor_inspector_card_vertices :: proc(
	vertices: ^[dynamic]WGPU_Scene_Vertex,
	world: Runtime_World,
	width, height: int,
	selected_entity_id: string,
	right_x, body_y, right_width, body_height: int,
	scroll_y: f32,
) -> int {
	selected, selected_ok := runtime_world_find_entity_by_id(world, selected_entity_id)
	if !selected_ok {
		return 0
	}
	selected_index, selected_err := runtime_world_entity_index(world, selected)
	if selected_err != .None {
		return 0
	}

	count := 0
	card_x := right_x + 12
	card_y := body_y + 36 - int(max_f32(scroll_y, 0.0) + 0.5)
	card_width := max(4, right_width - 24)
	clip_top := body_y + 36
	clip_bottom := body_y + body_height - 8
	for table in world.component_tables {
		if selected_index >= len(table.rows_by_entity) || table.rows_by_entity[selected_index] < 0 {
			continue
		}
		field_count := len(table.columns)
		card_height := 24 + max(1, field_count) * 8
		if card_y >= clip_bottom {
			break
		}

		draw_y := card_y
		draw_height := card_height
		header_offset := 0
		if draw_y < clip_top {
			header_offset = clip_top - draw_y
			draw_height -= header_offset
			draw_y = clip_top
		}
		if draw_y + draw_height > clip_bottom {
			draw_height = max(0, clip_bottom - draw_y)
		}
		if draw_height > 0 {
			count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = card_x, y = draw_y, width = card_width, height = draw_height}, EDITOR_CHROME_INSPECTOR_CARD_COLOR)
			count += wgpu_append_chrome_stroke_rect(vertices, width, height, Renderable_Rect{x = card_x, y = draw_y, width = card_width, height = draw_height}, EDITOR_CHROME_RULE_COLOR)
			if header_offset < 12 {
				header_y := max(card_y + 2, clip_top)
				header_available := draw_y + draw_height - header_y
				if header_available > 0 {
					header_height := min(10 - header_offset, header_available)
					count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = card_x + 2, y = header_y, width = max(1, card_width - 4), height = header_height}, EDITOR_CHROME_INSPECTOR_CARD_HEADER_COLOR)
				}
			}
			field_y := card_y + 16
			for column in table.columns {
				if field_y + 5 >= card_y + card_height - 2 {
					break
				}
				if field_y + 5 >= clip_top && field_y < clip_bottom {
					clipped_y := max(field_y, clip_top)
					clipped_height := min(5, clip_bottom - clipped_y)
					if clipped_height > 0 {
						count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = card_x + 6, y = clipped_y, width = max(1, card_width - 12), height = clipped_height}, EDITOR_CHROME_INSPECTOR_FIELD_COLOR)
						value, value_err := runtime_world_get_component_field_value(world, selected, table.id, column.name)
						if value_err == .None && clipped_height >= 3 {
							count += wgpu_append_editor_inspector_typed_control_vertices(vertices, width, height, card_x, card_width, clipped_y, clipped_height, value)
						}
					}
				}
				field_y += 8
			}
		}
		card_y += card_height + 4
	}
	return count
}

wgpu_append_editor_inspector_typed_control_vertices :: proc(
	vertices: ^[dynamic]WGPU_Scene_Vertex,
	width, height: int,
	card_x, card_width, y, control_height: int,
	value: Runtime_Component_Value,
) -> int {
	control_y := y
	control_h := min(control_height, 5)
	switch value.value_type {
	case .Boolean:
		rect_width := min(18, max(8, card_width / 4))
		control_x := card_x + card_width - rect_width - 8
		color := value.boolean ? EDITOR_CHROME_INSPECTOR_BOOL_ON_COLOR : EDITOR_CHROME_INSPECTOR_BOOL_OFF_COLOR
		count := wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = control_x, y = control_y, width = rect_width, height = control_h}, color)
		if rect_width > 8 {
			knob_x := value.boolean ? control_x + rect_width - 5 : control_x + 2
			count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = knob_x, y = control_y + 1, width = 3, height = max(1, control_h - 2)}, EDITOR_CHROME_INSPECTOR_TOGGLE_KNOB_COLOR)
		}
		return count
	case .Int, .Float:
		rect_width := min(26, max(10, card_width / 3))
		control_x := card_x + card_width - rect_width - 8
		return wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = control_x, y = control_y, width = rect_width, height = control_h}, EDITOR_CHROME_INSPECTOR_SCALAR_CONTROL_COLOR)
	case .String:
		rect_width := min(26, max(10, card_width / 3))
		control_x := card_x + card_width - rect_width - 8
		return wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = control_x, y = control_y, width = rect_width, height = control_h}, EDITOR_CHROME_INSPECTOR_STRING_CONTROL_COLOR)
	case .Vec3:
		lane_width := min(8, max(3, (card_width - 20) / 6))
		gap := 2
		total_width := lane_width * 3 + gap * 2
		control_x := card_x + card_width - total_width - 8
		count := 0
		count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = control_x, y = control_y, width = lane_width, height = control_h}, EDITOR_CHROME_INSPECTOR_VEC3_X_COLOR)
		count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = control_x + lane_width + gap, y = control_y, width = lane_width, height = control_h}, EDITOR_CHROME_INSPECTOR_VEC3_Y_COLOR)
		count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = control_x + (lane_width + gap) * 2, y = control_y, width = lane_width, height = control_h}, EDITOR_CHROME_INSPECTOR_VEC3_Z_COLOR)
		return count
	}
	return 0
}

wgpu_append_chrome_stroke_rect :: proc(vertices: ^[dynamic]WGPU_Scene_Vertex, width, height: int, rect: Renderable_Rect, color: [3]u8) -> int {
	count := 0
	count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = rect.x, y = rect.y, width = rect.width, height = 1}, color)
	count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = rect.x, y = rect.y + rect.height - 1, width = rect.width, height = 1}, color)
	count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = rect.x, y = rect.y, width = 1, height = rect.height}, color)
	count += wgpu_append_chrome_rect(vertices, width, height, Renderable_Rect{x = rect.x + rect.width - 1, y = rect.y, width = 1, height = rect.height}, color)
	return count
}

wgpu_append_chrome_rect :: proc(vertices: ^[dynamic]WGPU_Scene_Vertex, width, height: int, rect: Renderable_Rect, color: [3]u8) -> int {
	before := len(vertices^)
	wgpu_append_rect_vertices(vertices, width, height, rect, color)
	return (len(vertices^) - before) / 6
}

wgpu_append_rect_vertices :: proc(vertices: ^[dynamic]WGPU_Scene_Vertex, image_width, image_height: int, rect: Renderable_Rect, color: [3]u8) {
	min_x := max(0, rect.x)
	min_y := max(0, rect.y)
	max_x := min(image_width, rect.x + rect.width)
	max_y := min(image_height, rect.y + rect.height)
	if min_x >= max_x || min_y >= max_y {
		return
	}

	x0 := (f32(min_x) / f32(image_width)) * 2.0 - 1.0
	x1 := (f32(max_x) / f32(image_width)) * 2.0 - 1.0
	y0 := 1.0 - (f32(min_y) / f32(image_height)) * 2.0
	y1 := 1.0 - (f32(max_y) / f32(image_height)) * 2.0
	vertex_color := [3]f32{f32(color[0]) / 255.0, f32(color[1]) / 255.0, f32(color[2]) / 255.0}

	append(vertices, WGPU_Scene_Vertex{position = {x0, y0}, color = vertex_color})
	append(vertices, WGPU_Scene_Vertex{position = {x0, y1}, color = vertex_color})
	append(vertices, WGPU_Scene_Vertex{position = {x1, y0}, color = vertex_color})
	append(vertices, WGPU_Scene_Vertex{position = {x1, y0}, color = vertex_color})
	append(vertices, WGPU_Scene_Vertex{position = {x0, y1}, color = vertex_color})
	append(vertices, WGPU_Scene_Vertex{position = {x1, y1}, color = vertex_color})
}

wgpu_scene_rect_wgsl :: proc(vertices: []WGPU_Scene_Vertex) -> string {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	strings.write_string(&builder, "const POSITIONS = array<vec2<f32>, ")
	strings.write_string(&builder, fmt.tprintf("%d", len(vertices)))
	strings.write_string(&builder, ">(\n")
	for vertex in vertices {
		strings.write_string(&builder, "\tvec2<f32>(")
		strings.write_string(&builder, wgpu_format_f32(vertex.position[0]))
		strings.write_string(&builder, ", ")
		strings.write_string(&builder, wgpu_format_f32(vertex.position[1]))
		strings.write_string(&builder, "),\n")
	}
	strings.write_string(&builder, ");\n\n")

	strings.write_string(&builder, "const COLORS = array<vec3<f32>, ")
	strings.write_string(&builder, fmt.tprintf("%d", len(vertices)))
	strings.write_string(&builder, ">(\n")
	for vertex in vertices {
		strings.write_string(&builder, "\tvec3<f32>(")
		strings.write_string(&builder, wgpu_format_f32(vertex.color[0]))
		strings.write_string(&builder, ", ")
		strings.write_string(&builder, wgpu_format_f32(vertex.color[1]))
		strings.write_string(&builder, ", ")
		strings.write_string(&builder, wgpu_format_f32(vertex.color[2]))
		strings.write_string(&builder, "),\n")
	}
	strings.write_string(&builder, ");\n\n")
	strings.write_string(&builder, WGPU_SCENE_RECT_WGSL_HEADER)

	return strings.clone(strings.to_string(builder))
}

wgpu_release_scene_pipeline_resources :: proc(
	procs: WGPU_Offscreen_Procs,
	shader_module: ^WGPU_Shader_Module,
	pipeline_layout: ^WGPU_Pipeline_Layout,
	render_pipeline: ^WGPU_Render_Pipeline,
) {
	if render_pipeline^ != nil {
		procs.render_pipeline_release(render_pipeline^)
		render_pipeline^ = nil
	}
	if pipeline_layout^ != nil {
		procs.pipeline_layout_release(pipeline_layout^)
		pipeline_layout^ = nil
	}
	if shader_module^ != nil {
		procs.shader_module_release(shader_module^)
		shader_module^ = nil
	}
}

wgpu_format_f32 :: proc(value: f32) -> string {
	return fmt.tprintf("%.6f", value)
}

wgpu_align_to_u32 :: proc(value, alignment: u32) -> u32 {
	if alignment == 0 {
		return value
	}
	return ((value + alignment - 1) / alignment) * alignment
}

wgpu_poll_device_until_complete :: proc(procs: WGPU_Offscreen_Procs, device: WGPU_Device, complete: ^bool) -> bool {
	for poll_index := 0; poll_index < WGPU_OFFSCREEN_REQUEST_POLL_LIMIT && !complete^; poll_index += 1 {
		_ = procs.device_poll(device, WGPU_TRUE, nil)
	}
	return complete^
}

wgpu_smoke_default_offscreen_instance :: proc(root: string = ".") -> (string, string, bool) {
	path, found := wgpu_find_default_offscreen_library(root)
	if !found {
		return "", WGPU_OFFSCREEN_LIBRARY_NOT_FOUND, false
	}

	loaded, missing, loaded_ok := wgpu_load_offscreen_library(path)
	if !loaded_ok {
		delete(path)
		return "", missing, false
	}
	defer wgpu_unload_offscreen_library(&loaded)

	smoke_error, smoke_ok := wgpu_smoke_offscreen_instance(loaded.procs)
	if !smoke_ok {
		delete(path)
		return "", smoke_error, false
	}

	return path, "", true
}

wgpu_smoke_default_offscreen_context :: proc(root: string = ".", backend_type: WGPU_Backend_Type = WGPU_BACKEND_TYPE_UNDEFINED) -> (string, string, bool) {
	path, found := wgpu_find_default_offscreen_library(root)
	if !found {
		return "", WGPU_OFFSCREEN_LIBRARY_NOT_FOUND, false
	}

	loaded, missing, loaded_ok := wgpu_load_offscreen_library(path)
	if !loaded_ok {
		delete(path)
		return "", missing, false
	}
	defer wgpu_unload_offscreen_library(&loaded)

	smoke_error, smoke_ok := wgpu_smoke_offscreen_context(loaded.procs, backend_type)
	if !smoke_ok {
		delete(path)
		return "", smoke_error, false
	}

	return path, "", true
}

wgpu_smoke_default_offscreen_clear_readback :: proc(root: string = ".", backend_type: WGPU_Backend_Type = WGPU_BACKEND_TYPE_UNDEFINED) -> (string, string, bool) {
	path, found := wgpu_find_default_offscreen_library(root)
	if !found {
		return "", WGPU_OFFSCREEN_LIBRARY_NOT_FOUND, false
	}

	loaded, missing, loaded_ok := wgpu_load_offscreen_library(path)
	if !loaded_ok {
		delete(path)
		return "", missing, false
	}
	defer wgpu_unload_offscreen_library(&loaded)

	smoke_error, smoke_ok := wgpu_smoke_offscreen_clear_readback(loaded.procs, backend_type)
	if !smoke_ok {
		delete(path)
		return "", smoke_error, false
	}

	return path, "", true
}

wgpu_smoke_default_offscreen_triangle_readback :: proc(root: string = ".", backend_type: WGPU_Backend_Type = WGPU_BACKEND_TYPE_UNDEFINED) -> (string, string, bool) {
	path, found := wgpu_find_default_offscreen_library(root)
	if !found {
		return "", WGPU_OFFSCREEN_LIBRARY_NOT_FOUND, false
	}

	loaded, missing, loaded_ok := wgpu_load_offscreen_library(path)
	if !loaded_ok {
		delete(path)
		return "", missing, false
	}
	defer wgpu_unload_offscreen_library(&loaded)

	smoke_error, smoke_ok := wgpu_smoke_offscreen_triangle_readback(loaded.procs, backend_type)
	if !smoke_ok {
		delete(path)
		return "", smoke_error, false
	}

	return path, "", true
}

wgpu_request_adapter_sync :: proc(
	procs: WGPU_Offscreen_Procs,
	instance: WGPU_Instance,
	backend_type: WGPU_Backend_Type = WGPU_BACKEND_TYPE_UNDEFINED,
	compatible_surface: WGPU_Surface = nil,
) -> (WGPU_Adapter, string, bool) {
	state := WGPU_Adapter_Request_State{}
	options := wgpu_request_adapter_options(compatible_surface)
	options.backend_type = backend_type
	_ = procs.instance_request_adapter(instance, &options, wgpu_request_adapter_callback_info(wgpu_request_adapter_sync_callback, rawptr(&state)))
	if !wgpu_poll_request_until_complete(procs, instance, &state.complete) {
		return nil, WGPU_OFFSCREEN_REQUEST_TIMEOUT_ERROR, false
	}
	if state.status != WGPU_REQUEST_ADAPTER_STATUS_SUCCESS || state.adapter == nil {
		return nil, WGPU_OFFSCREEN_ADAPTER_REQUEST_ERROR, false
	}
	return state.adapter, "", true
}

wgpu_request_device_sync :: proc(procs: WGPU_Offscreen_Procs, instance: WGPU_Instance, adapter: WGPU_Adapter) -> (WGPU_Device, string, bool) {
	state := WGPU_Device_Request_State{}
	descriptor := wgpu_device_descriptor_default()
	_ = procs.adapter_request_device(adapter, &descriptor, wgpu_request_device_callback_info(wgpu_request_device_sync_callback, rawptr(&state)))
	if !wgpu_poll_request_until_complete(procs, instance, &state.complete) {
		return nil, WGPU_OFFSCREEN_REQUEST_TIMEOUT_ERROR, false
	}
	if state.status != WGPU_REQUEST_DEVICE_STATUS_SUCCESS || state.device == nil {
		return nil, WGPU_OFFSCREEN_DEVICE_REQUEST_ERROR, false
	}
	return state.device, "", true
}

wgpu_poll_request_until_complete :: proc(procs: WGPU_Offscreen_Procs, instance: WGPU_Instance, complete: ^bool) -> bool {
	for poll_index := 0; poll_index < WGPU_OFFSCREEN_REQUEST_POLL_LIMIT && !complete^; poll_index += 1 {
		procs.instance_process_events(instance)
	}
	return complete^
}

wgpu_request_adapter_sync_callback :: proc "c" (status: WGPU_Request_Adapter_Status, adapter: WGPU_Adapter, message: WGPU_String_View, userdata1, userdata2: rawptr) {
	_ = message
	_ = userdata2
	if userdata1 == nil {
		return
	}
	state := (^WGPU_Adapter_Request_State)(userdata1)
	state.status = status
	state.adapter = adapter
	state.complete = true
}

wgpu_request_device_sync_callback :: proc "c" (status: WGPU_Request_Device_Status, device: WGPU_Device, message: WGPU_String_View, userdata1, userdata2: rawptr) {
	_ = message
	_ = userdata2
	if userdata1 == nil {
		return
	}
	state := (^WGPU_Device_Request_State)(userdata1)
	state.status = status
	state.device = device
	state.complete = true
}

wgpu_buffer_map_sync_callback :: proc "c" (status: WGPU_Map_Async_Status, message: WGPU_String_View, userdata1, userdata2: rawptr) {
	_ = message
	_ = userdata2
	if userdata1 == nil {
		return
	}
	state := (^WGPU_Buffer_Map_State)(userdata1)
	state.status = status
	state.complete = true
}

wgpu_find_default_offscreen_library :: proc(root: string = ".") -> (string, bool) {
	if env_path, env_found := os.lookup_env(WGPU_OFFSCREEN_LIBRARY_ENV, context.allocator); env_found {
		defer delete(env_path)
		if env_path != "" && os.exists(env_path) {
			owned, clone_err := filepath.abs(env_path)
			if clone_err == nil {
				return owned, true
			}
		}
	}

	candidates := [?][]string{
		{root, "odin-out", wgpu_native_dynamic_library_file_name()},
		{root, "odin-out", "lib", wgpu_native_dynamic_library_file_name()},
		{root, wgpu_native_dynamic_library_file_name()},
	}
	for candidate in candidates {
		if path, ok := wgpu_find_existing_path(candidate); ok {
			return path, true
		}
	}

	return "", false
}

wgpu_find_existing_path :: proc(parts: []string) -> (string, bool) {
	path, join_err := filepath.join(parts)
	if join_err != nil {
		return "", false
	}
	if !os.exists(path) {
		delete(path)
		return "", false
	}
	absolute, abs_err := filepath.abs(path)
	delete(path)
	if abs_err != nil {
		return "", false
	}
	return absolute, true
}

wgpu_unload_offscreen_library :: proc(loaded: ^WGPU_Offscreen_Dynamic_Library) -> bool {
	if loaded == nil || loaded.handle == dynlib.Library(nil) {
		return true
	}
	unload_ok := dynlib.unload_library(loaded.handle)
	loaded^ = WGPU_Offscreen_Dynamic_Library{}
	return unload_ok
}

wgpu_dynlib_symbol_resolver :: proc(name: string, user_data: rawptr) -> rawptr {
	if user_data == nil {
		return nil
	}
	resolver_context := (^WGPU_Dynlib_Resolver_Context)(user_data)
	symbol, symbol_ok := dynlib.symbol_address(resolver_context.library, name)
	if !symbol_ok {
		return nil
	}
	return symbol
}

wgpu_offscreen_texture_usage :: proc() -> WGPU_Texture_Usage {
	return WGPU_TEXTURE_USAGE_RENDER_ATTACHMENT | WGPU_TEXTURE_USAGE_COPY_SRC
}

wgpu_staging_buffer_usage :: proc() -> WGPU_Buffer_Usage {
	return WGPU_BUFFER_USAGE_MAP_READ | WGPU_BUFFER_USAGE_COPY_DST
}
