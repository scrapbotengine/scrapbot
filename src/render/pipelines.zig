const geometry = @import("../geometry.zig");
const types = @import("types.zig");
const wgpu = @import("wgpu");

const RenderError = types.RenderError;
const depth_format = types.depth_format;
const shadow_depth_format = types.shadow_depth_format;
const InstanceAttributes = types.InstanceAttributes;
const UiVertex = types.UiVertex;

pub fn createMeshPipeline(device: *wgpu.Device, texture_format: wgpu.TextureFormat, pipeline_layout: *wgpu.PipelineLayout) RenderError!*wgpu.RenderPipeline {
    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("../shaders/demo.wgsl"),
    })) orelse return RenderError.NoDevice;
    defer shader_module.release();

    const vertex_attributes = [_]wgpu.VertexAttribute{
        .{
            .format = .float32x3,
            .offset = @offsetOf(geometry.Vertex, "position"),
            .shader_location = 0,
        },
        .{
            .format = .float32x3,
            .offset = @offsetOf(geometry.Vertex, "normal"),
            .shader_location = 1,
        },
    };
    const vec4_size = @sizeOf([4]f32);
    const instance_attributes = [_]wgpu.VertexAttribute{
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "mvp") + vec4_size * 0,
            .shader_location = 2,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "mvp") + vec4_size * 1,
            .shader_location = 3,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "mvp") + vec4_size * 2,
            .shader_location = 4,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "mvp") + vec4_size * 3,
            .shader_location = 5,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "model") + vec4_size * 0,
            .shader_location = 6,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "model") + vec4_size * 1,
            .shader_location = 7,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "model") + vec4_size * 2,
            .shader_location = 8,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "model") + vec4_size * 3,
            .shader_location = 9,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "object_color"),
            .shader_location = 10,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 0,
            .shader_location = 11,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 1,
            .shader_location = 12,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 2,
            .shader_location = 13,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 3,
            .shader_location = 14,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_flags"),
            .shader_location = 15,
        },
    };
    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .step_mode = .vertex,
            .array_stride = @sizeOf(geometry.Vertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        },
        .{
            .step_mode = .instance,
            .array_stride = @sizeOf(InstanceAttributes),
            .attribute_count = instance_attributes.len,
            .attributes = &instance_attributes,
        },
    };

    const color_targets = [_]wgpu.ColorTargetState{
        .{
            .format = texture_format,
        },
    };
    const depth_stencil = wgpu.DepthStencilState{
        .format = depth_format,
        .depth_write_enabled = .true,
        .depth_compare = .less,
        .stencil_front = .{},
        .stencil_back = .{},
    };

    return device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .label = wgpu.StringView.fromSlice("Scrapbot mesh pipeline"),
        .layout = pipeline_layout,
        .vertex = .{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
            .buffer_count = vertex_buffers.len,
            .buffers = &vertex_buffers,
        },
        .primitive = .{
            .cull_mode = .none,
        },
        .depth_stencil = &depth_stencil,
        .fragment = &wgpu.FragmentState{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("fs_main"),
            .target_count = color_targets.len,
            .targets = &color_targets,
        },
        .multisample = .{},
    }) orelse return RenderError.NoDevice;
}

pub fn createShadowPipeline(device: *wgpu.Device, pipeline_layout: *wgpu.PipelineLayout) RenderError!*wgpu.RenderPipeline {
    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("../shaders/shadow.wgsl"),
    })) orelse return RenderError.NoDevice;
    defer shader_module.release();

    const vertex_attributes = [_]wgpu.VertexAttribute{
        .{
            .format = .float32x3,
            .offset = @offsetOf(geometry.Vertex, "position"),
            .shader_location = 0,
        },
    };
    const vec4_size = @sizeOf([4]f32);
    const instance_attributes = [_]wgpu.VertexAttribute{
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 0,
            .shader_location = 2,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 1,
            .shader_location = 3,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 2,
            .shader_location = 4,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 3,
            .shader_location = 5,
        },
    };
    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .step_mode = .vertex,
            .array_stride = @sizeOf(geometry.Vertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        },
        .{
            .step_mode = .instance,
            .array_stride = @sizeOf(InstanceAttributes),
            .attribute_count = instance_attributes.len,
            .attributes = &instance_attributes,
        },
    };

    const depth_stencil = wgpu.DepthStencilState{
        .format = shadow_depth_format,
        .depth_write_enabled = .true,
        .depth_compare = .less,
        .stencil_front = .{},
        .stencil_back = .{},
        .depth_bias = 2,
        .depth_bias_slope_scale = 2.0,
    };

    return device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .label = wgpu.StringView.fromSlice("Scrapbot shadow pipeline"),
        .layout = pipeline_layout,
        .vertex = .{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
            .buffer_count = vertex_buffers.len,
            .buffers = &vertex_buffers,
        },
        .primitive = .{
            .cull_mode = .back,
        },
        .depth_stencil = &depth_stencil,
        .multisample = .{},
    }) orelse return RenderError.NoDevice;
}

pub fn createUiPipeline(device: *wgpu.Device, texture_format: wgpu.TextureFormat, pipeline_layout: *wgpu.PipelineLayout) RenderError!*wgpu.RenderPipeline {
    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("../shaders/ui.wgsl"),
    })) orelse return RenderError.NoDevice;
    defer shader_module.release();

    const vertex_attributes = [_]wgpu.VertexAttribute{
        .{
            .format = .float32x2,
            .offset = @offsetOf(UiVertex, "position"),
            .shader_location = 0,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(UiVertex, "color"),
            .shader_location = 1,
        },
        .{
            .format = .float32x2,
            .offset = @offsetOf(UiVertex, "local_position"),
            .shader_location = 2,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(UiVertex, "rect_size_radius"),
            .shader_location = 3,
        },
    };
    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .step_mode = .vertex,
            .array_stride = @sizeOf(UiVertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        },
    };
    const color_targets = [_]wgpu.ColorTargetState{
        .{
            .format = texture_format,
            .blend = &wgpu.BlendState.alpha_blending,
        },
    };

    return device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .label = wgpu.StringView.fromSlice("Scrapbot UI pipeline"),
        .layout = pipeline_layout,
        .vertex = .{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
            .buffer_count = vertex_buffers.len,
            .buffers = &vertex_buffers,
        },
        .primitive = .{},
        .fragment = &wgpu.FragmentState{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("fs_main"),
            .target_count = color_targets.len,
            .targets = &color_targets,
        },
        .multisample = .{},
    }) orelse return RenderError.NoDevice;
}
