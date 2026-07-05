const std = @import("std");
const types = @import("types.zig");
const wgpu = @import("wgpu");

const RenderError = types.RenderError;
const UiVertex = types.UiVertex;

pub const UiDrawResources = struct {
    vertex_buffer: ?*wgpu.Buffer = null,
    vertex_buffer_size: u64 = 0,
    vertex_count: u32 = 0,

    pub fn update(
        self: *UiDrawResources,
        device: *wgpu.Device,
        queue: *wgpu.Queue,
        vertices: []const UiVertex,
    ) RenderError!void {
        if (vertices.len > std.math.maxInt(u32)) {
            return RenderError.InvalidScene;
        }

        self.vertex_count = @intCast(vertices.len);
        if (vertices.len == 0) {
            return;
        }

        const bytes = std.mem.sliceAsBytes(vertices);
        if (self.vertex_buffer == null or self.vertex_buffer_size < bytes.len) {
            const buffer = device.createBuffer(&wgpu.BufferDescriptor{
                .label = wgpu.StringView.fromSlice("Scrapbot UI vertex buffer"),
                .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
                .size = @intCast(bytes.len),
                .mapped_at_creation = @as(u32, @intFromBool(false)),
            }) orelse return RenderError.NoDevice;
            if (self.vertex_buffer) |old_buffer| {
                old_buffer.release();
            }
            self.vertex_buffer = buffer;
            self.vertex_buffer_size = @intCast(bytes.len);
        }

        queue.writeBuffer(self.vertex_buffer orelse return RenderError.NoDevice, 0, bytes.ptr, bytes.len);
    }

    pub fn deinit(self: *UiDrawResources) void {
        if (self.vertex_buffer) |buffer| {
            buffer.release();
        }
        self.* = .{};
    }
};
