const std = @import("std");
const Io = std.Io;
const wgpu = @import("wgpu");

const output_width = 640;
const output_height = 480;
const output_extent = wgpu.Extent3D{
    .width = output_width,
    .height = output_height,
    .depth_or_array_layers = 1,
};
const output_bytes_per_row = 4 * output_width;
const output_size = output_bytes_per_row * output_height;

pub const RenderError = error{
    NoAdapter,
    NoDevice,
    BufferMapFailed,
};

pub fn renderTriangleBmp(io: Io, output_path: []const u8) !void {
    const instance = wgpu.Instance.create(null) orelse return RenderError.NoAdapter;
    defer instance.release();

    const adapter_response = instance.requestAdapterSync(&wgpu.RequestAdapterOptions{}, 200_000_000);
    const adapter = switch (adapter_response.status) {
        .success => adapter_response.adapter orelse return RenderError.NoAdapter,
        else => return RenderError.NoAdapter,
    };
    defer adapter.release();

    const device_response = adapter.requestDeviceSync(instance, &wgpu.DeviceDescriptor{
        .required_limits = null,
    }, 200_000_000);
    const device = switch (device_response.status) {
        .success => device_response.device orelse return RenderError.NoDevice,
        else => return RenderError.NoDevice,
    };
    defer device.release();

    const queue = device.getQueue() orelse return RenderError.NoDevice;
    defer queue.release();

    const texture_format = wgpu.TextureFormat.bgra8_unorm_srgb;
    const target_texture = device.createTexture(&wgpu.TextureDescriptor{
        .label = wgpu.StringView.fromSlice("Machina triangle target"),
        .size = output_extent,
        .format = texture_format,
        .usage = wgpu.TextureUsages.render_attachment | wgpu.TextureUsages.copy_src,
    }) orelse return RenderError.NoDevice;
    defer target_texture.release();

    const target_view = target_texture.createView(&wgpu.TextureViewDescriptor{
        .label = wgpu.StringView.fromSlice("Machina triangle target view"),
        .mip_level_count = 1,
        .array_layer_count = 1,
    }) orelse return RenderError.NoDevice;
    defer target_view.release();

    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("shaders/triangle.wgsl"),
    })) orelse return RenderError.NoDevice;
    defer shader_module.release();

    const staging_buffer = device.createBuffer(&wgpu.BufferDescriptor{
        .label = wgpu.StringView.fromSlice("Machina triangle staging buffer"),
        .usage = wgpu.BufferUsages.map_read | wgpu.BufferUsages.copy_dst,
        .size = output_size,
        .mapped_at_creation = @as(u32, @intFromBool(false)),
    }) orelse return RenderError.NoDevice;
    defer staging_buffer.release();

    const color_targets = [_]wgpu.ColorTargetState{
        .{
            .format = texture_format,
            .blend = &wgpu.BlendState{
                .color = .{
                    .operation = .add,
                    .src_factor = .src_alpha,
                    .dst_factor = .one_minus_src_alpha,
                },
                .alpha = .{
                    .operation = .add,
                    .src_factor = .zero,
                    .dst_factor = .one,
                },
            },
        },
    };

    const pipeline = device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .vertex = .{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
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
    defer pipeline.release();

    const encoder = device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
        .label = wgpu.StringView.fromSlice("Machina triangle command encoder"),
    }) orelse return RenderError.NoDevice;
    defer encoder.release();

    const color_attachments = [_]wgpu.ColorAttachment{
        .{
            .view = target_view,
            .clear_value = .{
                .r = 0.02,
                .g = 0.02,
                .b = 0.025,
                .a = 1.0,
            },
        },
    };

    const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
        .color_attachment_count = color_attachments.len,
        .color_attachments = &color_attachments,
    }) orelse return RenderError.NoDevice;
    render_pass.setPipeline(pipeline);
    render_pass.draw(3, 1, 0, 0);
    render_pass.end();
    render_pass.release();

    encoder.copyTextureToBuffer(
        &wgpu.TexelCopyTextureInfo{
            .origin = .{},
            .texture = target_texture,
        },
        &wgpu.TexelCopyBufferInfo{
            .layout = .{
                .bytes_per_row = output_bytes_per_row,
                .rows_per_image = output_height,
            },
            .buffer = staging_buffer,
        },
        &output_extent,
    );

    const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor{
        .label = wgpu.StringView.fromSlice("Machina triangle command buffer"),
    }) orelse return RenderError.NoDevice;
    defer command_buffer.release();

    const command_buffers = [_]*const wgpu.CommandBuffer{command_buffer};
    queue.submit(&command_buffers);

    var map_complete = false;
    var map_status: wgpu.MapAsyncStatus = .unknown;
    _ = staging_buffer.mapAsync(wgpu.MapModes.read, 0, output_size, .{
        .callback = handleBufferMap,
        .userdata1 = @ptrCast(&map_complete),
        .userdata2 = @ptrCast(&map_status),
    });

    instance.processEvents();
    while (!map_complete) {
        instance.processEvents();
    }

    if (map_status != .success) {
        return RenderError.BufferMapFailed;
    }

    const mapped: [*]u8 = @ptrCast(@alignCast(staging_buffer.getMappedRange(0, output_size) orelse return RenderError.BufferMapFailed));
    defer staging_buffer.unmap();

    try write24BitBmp(io, output_path, mapped[0..output_size]);
}

fn handleBufferMap(status: wgpu.MapAsyncStatus, _: wgpu.StringView, userdata1: ?*anyopaque, userdata2: ?*anyopaque) callconv(.c) void {
    const complete: *bool = @ptrCast(@alignCast(userdata1));
    complete.* = true;

    const map_status: *wgpu.MapAsyncStatus = @ptrCast(@alignCast(userdata2));
    map_status.* = status;
}

fn write24BitBmp(io: Io, output_path: []const u8, bgra_data: []const u8) !void {
    var bytes: [bmpFileSize()]u8 = undefined;
    @memset(&bytes, 0);

    var cursor: usize = 0;
    putBytes(&bytes, &cursor, "BM");
    putInt(u32, &bytes, &cursor, bmpFileSize());
    putInt(u32, &bytes, &cursor, 0);
    putInt(u32, &bytes, &cursor, 54);
    putInt(u32, &bytes, &cursor, 40);
    putInt(u32, &bytes, &cursor, output_width);
    putInt(u32, &bytes, &cursor, output_height);
    putInt(u16, &bytes, &cursor, 1);
    putInt(u16, &bytes, &cursor, 24);
    cursor += 4 * 6;

    var line_buffer = [_]u8{0} ** bmp_bytes_per_line;
    const bgra_pixels_per_line = output_width * 4;
    for (0..output_height) |i_y| {
        const y = output_height - i_y - 1;
        const line_offset = y * bgra_pixels_per_line;
        for (0..output_width) |x| {
            const bgr_pixel_offset = x * 3;
            const bgra_pixel_offset = line_offset + (x * 4);
            line_buffer[bgr_pixel_offset] = bgra_data[bgra_pixel_offset];
            line_buffer[bgr_pixel_offset + 1] = bgra_data[bgra_pixel_offset + 1];
            line_buffer[bgr_pixel_offset + 2] = bgra_data[bgra_pixel_offset + 2];
        }
        putBytes(&bytes, &cursor, &line_buffer);
    }

    try Io.Dir.cwd().writeFile(io, .{
        .sub_path = output_path,
        .data = &bytes,
    });
}

fn putBytes(output: []u8, cursor: *usize, bytes: []const u8) void {
    @memcpy(output[cursor.*..][0..bytes.len], bytes);
    cursor.* += bytes.len;
}

fn putInt(comptime T: type, output: []u8, cursor: *usize, value: anytype) void {
    const size = @sizeOf(T);
    std.mem.writeInt(T, output[cursor.*..][0..size], @intCast(value), .little);
    cursor.* += size;
}

const bmp_colors_per_line = output_width * 3;
const bmp_bytes_per_line = if (bmp_colors_per_line & 0x00000003 == 0)
    bmp_colors_per_line
else
    (bmp_colors_per_line | 0x00000003) + 1;

fn bmpFileSize() usize {
    return 54 + (bmp_bytes_per_line * output_height);
}
