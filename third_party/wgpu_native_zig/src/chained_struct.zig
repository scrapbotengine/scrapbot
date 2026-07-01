pub const SType = enum(u32) {
    shader_source_spirv                  = 0x00000001,
    shader_source_wgsl                   = 0x00000002,
    render_pass_max_draw_count           = 0x00000003,
    surface_source_metal_layer           = 0x00000004,
    surface_source_windows_hwnd          = 0x00000005,
    surface_source_xlib_window           = 0x00000006,
    surface_source_wayland_surface       = 0x00000007,
    surface_source_android_native_window = 0x00000008,
    surface_source_xcb_window            = 0x00000009, 

    // wgpu-native extras (wgpu.h)
    device_extras                        = 0x00030001,
    native_limits                        = 0x00030002,
    pipeline_layout_extras               = 0x00030003,
    shader_source_glsl                   = 0x00030004,
    instance_extras                      = 0x00030006,
    bind_group_entry_extras              = 0x00030007,
    bind_group_layout_entry_extras       = 0x00030008,
    query_set_descriptor_extras          = 0x00030009,
    surface_configuration_extras         = 0x0003000A,
};

pub const ChainedStruct = extern struct {
    next: ?*const ChainedStruct = null,
    s_type: SType,
};

pub const ChainedStructOut = extern struct {
    next: ?*ChainedStructOut = null,
    s_type: SType,
};