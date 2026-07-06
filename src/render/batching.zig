const std = @import("std");
const geometry = @import("../geometry.zig");
const runtime = @import("../runtime.zig");
const render_resources = @import("resources.zig");
const types = @import("types.zig");
const wgpu = @import("wgpu");

const RenderError = types.RenderError;
const InstanceAttributes = types.InstanceAttributes;

pub const BatchPlan = struct {
    allocator: std.mem.Allocator,
    renderables: []runtime.RenderableMesh,
    batches: []BatchPlanEntry,

    pub fn build(allocator: std.mem.Allocator, world: *const runtime.World) RenderError!BatchPlan {
        var renderables: std.ArrayList(runtime.RenderableMesh) = .empty;
        errdefer renderables.deinit(allocator);
        world.appendRenderableMeshes(allocator, &renderables) catch return RenderError.OutOfMemory;

        const renderable_slice = renderables.toOwnedSlice(allocator) catch return RenderError.OutOfMemory;
        errdefer allocator.free(renderable_slice);
        return buildFromOwnedRenderables(allocator, renderable_slice);
    }

    pub fn buildFromRenderables(allocator: std.mem.Allocator, renderables: []const runtime.RenderableMesh) RenderError!BatchPlan {
        const renderable_slice = allocator.dupe(runtime.RenderableMesh, renderables) catch return RenderError.OutOfMemory;
        errdefer allocator.free(renderable_slice);
        return buildFromOwnedRenderables(allocator, renderable_slice);
    }

    fn buildFromOwnedRenderables(allocator: std.mem.Allocator, renderable_slice: []runtime.RenderableMesh) RenderError!BatchPlan {
        var builds: std.ArrayList(BatchBuild) = .empty;
        errdefer {
            for (builds.items) |*pending_batch| {
                pending_batch.deinit(allocator);
            }
            builds.deinit(allocator);
        }

        for (renderable_slice, 0..) |renderable, render_index| {
            const geometry_key = GeometryKey.fromRenderable(renderable) orelse return RenderError.InvalidScene;
            const shadow_key = ShadowKey.fromRenderable(renderable);

            var batch_index: ?usize = null;
            for (builds.items, 0..) |pending_batch, index| {
                if (pending_batch.geometry_key.eql(geometry_key) and
                    pending_batch.shadow_key.eql(shadow_key))
                {
                    batch_index = index;
                    break;
                }
            }

            const index = batch_index orelse blk: {
                try builds.append(allocator, .{
                    .geometry_key = geometry_key,
                    .shadow_key = shadow_key,
                });
                break :blk builds.items.len - 1;
            };
            builds.items[index].render_indices.append(allocator, render_index) catch return RenderError.OutOfMemory;
        }

        const batches = allocator.alloc(BatchPlanEntry, builds.items.len) catch return RenderError.OutOfMemory;
        var copied: usize = 0;
        errdefer {
            for (batches[0..copied]) |entry| {
                allocator.free(entry.render_indices);
            }
            allocator.free(batches);
        }

        for (builds.items, 0..) |*pending_batch, index| {
            batches[index] = .{
                .geometry_key = pending_batch.geometry_key,
                .shadow_key = pending_batch.shadow_key,
                .render_indices = pending_batch.render_indices.toOwnedSlice(allocator) catch return RenderError.OutOfMemory,
            };
            copied += 1;
        }

        builds.deinit(allocator);
        return .{
            .allocator = allocator,
            .renderables = renderable_slice,
            .batches = batches,
        };
    }

    pub fn deinit(self: *BatchPlan) void {
        const allocator = self.allocator;
        for (self.batches) |entry| {
            allocator.free(entry.render_indices);
        }
        allocator.free(self.batches);
        allocator.free(self.renderables);
        self.* = .{
            .allocator = allocator,
            .renderables = &.{},
            .batches = &.{},
        };
    }
};

const BatchBuild = struct {
    geometry_key: GeometryKey,
    shadow_key: ShadowKey,
    render_indices: std.ArrayList(usize) = .empty,

    fn deinit(self: *BatchBuild, allocator: std.mem.Allocator) void {
        self.render_indices.deinit(allocator);
    }
};

pub const BatchPlanEntry = struct {
    geometry_key: GeometryKey,
    shadow_key: ShadowKey,
    render_indices: []usize,
};

pub const BatchResources = struct {
    geometry_key: GeometryKey,
    shadow_key: ShadowKey,
    vertex_buffer: *wgpu.Buffer,
    index_buffer: *wgpu.Buffer,
    instance_buffer: *wgpu.Buffer,
    vertex_buffer_size: u64,
    index_buffer_size: u64,
    instance_buffer_size: u64,
    index_count: u32,
    instance_count: u32,

    pub fn create(
        allocator: std.mem.Allocator,
        device: *wgpu.Device,
        entry: BatchPlanEntry,
    ) RenderError!BatchResources {
        var mesh = geometry.generatePrimitive(
            allocator,
            entry.geometry_key.primitive,
            entry.geometry_key.segments,
            entry.geometry_key.rings,
        ) catch |err| return mapGeometryError(err);
        defer mesh.deinit(allocator);

        const vertex_bytes = std.mem.sliceAsBytes(mesh.vertices);
        const index_bytes = std.mem.sliceAsBytes(mesh.indices);
        const vertex_buffer = try render_resources.createStaticBuffer(device, "Scrapbot mesh vertex buffer", wgpu.BufferUsages.vertex, vertex_bytes);
        errdefer vertex_buffer.release();

        const index_buffer = try render_resources.createStaticBuffer(device, "Scrapbot mesh index buffer", wgpu.BufferUsages.index, index_bytes);
        errdefer index_buffer.release();

        if (entry.render_indices.len > std.math.maxInt(u32)) {
            return RenderError.InvalidScene;
        }
        const instance_buffer_size = @sizeOf(InstanceAttributes) * entry.render_indices.len;
        const instance_buffer = device.createBuffer(&wgpu.BufferDescriptor{
            .label = wgpu.StringView.fromSlice("Scrapbot mesh instance buffer"),
            .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
            .size = @intCast(instance_buffer_size),
            .mapped_at_creation = @as(u32, @intFromBool(false)),
        }) orelse return RenderError.NoDevice;
        errdefer instance_buffer.release();

        return .{
            .geometry_key = entry.geometry_key,
            .shadow_key = entry.shadow_key,
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .instance_buffer = instance_buffer,
            .vertex_buffer_size = @intCast(vertex_bytes.len),
            .index_buffer_size = @intCast(index_bytes.len),
            .instance_buffer_size = @intCast(instance_buffer_size),
            .index_count = @intCast(mesh.indices.len),
            .instance_count = @intCast(entry.render_indices.len),
        };
    }

    pub fn matches(self: BatchResources, entry: BatchPlanEntry) bool {
        if (entry.render_indices.len > std.math.maxInt(u32)) {
            return false;
        }
        return self.geometry_key.eql(entry.geometry_key) and
            self.shadow_key.eql(entry.shadow_key) and
            self.instance_count == @as(u32, @intCast(entry.render_indices.len));
    }

    pub fn deinit(self: *BatchResources) void {
        self.instance_buffer.release();
        self.index_buffer.release();
        self.vertex_buffer.release();
    }
};

pub const GeometryKey = struct {
    primitive: geometry.Primitive,
    segments: i32,
    rings: i32,

    pub fn fromRenderable(renderable: runtime.RenderableMesh) ?GeometryKey {
        return .{
            .primitive = geometry.parsePrimitive(renderable.primitive) orelse return null,
            .segments = renderable.segments,
            .rings = renderable.rings,
        };
    }

    pub fn eql(self: GeometryKey, other: GeometryKey) bool {
        return self.primitive == other.primitive and self.segments == other.segments and self.rings == other.rings;
    }
};

pub const ShadowKey = struct {
    casts_shadow: bool,
    receives_shadow: bool,

    pub fn fromRenderable(renderable: runtime.RenderableMesh) ShadowKey {
        return .{
            .casts_shadow = renderable.casts_shadow,
            .receives_shadow = renderable.receives_shadow,
        };
    }

    pub fn eql(self: ShadowKey, other: ShadowKey) bool {
        return self.casts_shadow == other.casts_shadow and self.receives_shadow == other.receives_shadow;
    }
};

fn mapGeometryError(err: anyerror) RenderError {
    return switch (err) {
        error.OutOfMemory => RenderError.OutOfMemory,
        else => RenderError.InvalidScene,
    };
}
