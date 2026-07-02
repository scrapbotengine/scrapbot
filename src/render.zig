const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const geometry = @import("geometry.zig");
const runtime = @import("runtime.zig");
const wgpu = @import("wgpu");

const sdl = if (builtin.os.tag == .macos) @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_metal.h");
}) else struct {};

const output_width = 640;
const output_height = 480;
const output_extent = wgpu.Extent3D{
    .width = output_width,
    .height = output_height,
    .depth_or_array_layers = 1,
};
const output_bytes_per_row = 4 * output_width;
const output_size = output_bytes_per_row * output_height;
const depth_format = wgpu.TextureFormat.depth24_plus;
const shadow_depth_format = wgpu.TextureFormat.depth32_float;
const shadow_map_size = 1024;
const render_draw_batch_component_id = "machina.render.internal.draw.batch";
const render_extract_system_id = "machina.render.extract";
const render_prepare_meshes_system_id = "machina.render.prepare_meshes";
const render_queue_meshes_system_id = "machina.render.queue_meshes";
const render_draw_meshes_system_id = "machina.render.draw_meshes";

pub const RenderError = error{
    NoAdapter,
    NoDevice,
    NoSurface,
    NoSurfaceFormat,
    SurfaceFailed,
    WindowingUnsupported,
    SdlInitFailed,
    WindowCreateFailed,
    MetalViewCreateFailed,
    MetalLayerMissing,
    BufferMapFailed,
    OutOfMemory,
    InvalidScene,
};

pub const WindowOptions = struct {
    max_frames: ?u32 = null,
    scene_reload: ?SceneReloadHook = null,
    frame_update: ?FrameUpdateHook = null,
};

pub const Scene = struct {
    world: *const runtime.World,
};

pub const SceneReloadHook = struct {
    context: *anyopaque,
    poll: *const fn (context: *anyopaque) ?Scene,
};

pub const FrameUpdateHook = struct {
    context: *anyopaque,
    step: *const fn (context: *anyopaque, delta_seconds: f32) void,
};

pub fn renderDemoBmp(io: Io, allocator: std.mem.Allocator, output_path: []const u8, scene: Scene) !void {
    const instance = wgpu.Instance.create(null) orelse return RenderError.NoAdapter;
    defer instance.release();

    var gpu = try openGpu(instance, null);
    defer gpu.deinit();

    const texture_format = wgpu.TextureFormat.bgra8_unorm_srgb;
    const target_texture = gpu.device.createTexture(&wgpu.TextureDescriptor{
        .label = wgpu.StringView.fromSlice("Machina mesh target"),
        .size = output_extent,
        .format = texture_format,
        .usage = wgpu.TextureUsages.render_attachment | wgpu.TextureUsages.copy_src,
    }) orelse return RenderError.NoDevice;
    defer target_texture.release();

    const target_view = target_texture.createView(&wgpu.TextureViewDescriptor{
        .label = wgpu.StringView.fromSlice("Machina mesh target view"),
        .mip_level_count = 1,
        .array_layer_count = 1,
    }) orelse return RenderError.NoDevice;
    defer target_view.release();

    var demo = try MeshDemo.create(allocator, gpu.device, gpu.queue, texture_format, scene);
    defer demo.deinit();

    var depth = try DepthTarget.create(gpu.device, output_width, output_height);
    defer depth.deinit();

    const staging_buffer = gpu.device.createBuffer(&wgpu.BufferDescriptor{
        .label = wgpu.StringView.fromSlice("Machina mesh staging buffer"),
        .usage = wgpu.BufferUsages.map_read | wgpu.BufferUsages.copy_dst,
        .size = output_size,
        .mapped_at_creation = @as(u32, @intFromBool(false)),
    }) orelse return RenderError.NoDevice;
    defer staging_buffer.release();

    try demo.draw(gpu.device, gpu.queue, target_view, depth.view orelse return RenderError.NoDevice, .{
        .width = output_width,
        .height = output_height,
        .scene = scene,
    });

    const encoder = gpu.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
        .label = wgpu.StringView.fromSlice("Machina mesh copy encoder"),
    }) orelse return RenderError.NoDevice;
    defer encoder.release();

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
        .label = wgpu.StringView.fromSlice("Machina mesh copy command buffer"),
    }) orelse return RenderError.NoDevice;
    defer command_buffer.release();

    const command_buffers = [_]*const wgpu.CommandBuffer{command_buffer};
    gpu.queue.submit(&command_buffers);

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

    try write24BitBmp(io, allocator, output_path, mapped[0..output_size]);
}

pub fn runDemoWindow(allocator: std.mem.Allocator, title: []const u8, options: WindowOptions, initial_scene: Scene) !void {
    if (builtin.os.tag != .macos) {
        return RenderError.WindowingUnsupported;
    }

    const title_z = try allocator.dupeZ(u8, title);
    defer allocator.free(title_z);

    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        return RenderError.SdlInitFailed;
    }
    defer sdl.SDL_Quit();

    const window_flags = @as(sdl.SDL_WindowFlags, sdl.SDL_WINDOW_METAL | sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_HIGH_PIXEL_DENSITY);
    const window = sdl.SDL_CreateWindow(title_z.ptr, 960, 540, window_flags) orelse return RenderError.WindowCreateFailed;
    defer sdl.SDL_DestroyWindow(window);

    const metal_view = sdl.SDL_Metal_CreateView(window) orelse return RenderError.MetalViewCreateFailed;
    defer sdl.SDL_Metal_DestroyView(metal_view);

    const metal_layer = sdl.SDL_Metal_GetLayer(metal_view) orelse return RenderError.MetalLayerMissing;

    const instance = wgpu.Instance.create(null) orelse return RenderError.NoAdapter;
    defer instance.release();

    var surface_descriptor = wgpu.surfaceDescriptorFromMetalLayer(.{
        .label = "Machina window surface",
        .layer = metal_layer,
    });
    const surface = instance.createSurface(&surface_descriptor) orelse return RenderError.NoSurface;
    defer surface.release();
    defer surface.unconfigure();

    var gpu = try openGpu(instance, surface);
    defer gpu.deinit();

    var capabilities: wgpu.SurfaceCapabilities = undefined;
    if (surface.getCapabilities(gpu.adapter, &capabilities) != .success) {
        return RenderError.SurfaceFailed;
    }
    defer capabilities.freeMembers();

    const surface_format = chooseSurfaceFormat(capabilities) orelse return RenderError.NoSurfaceFormat;
    var scene = initial_scene;
    var demo = try MeshDemo.create(allocator, gpu.device, gpu.queue, surface_format, scene);
    defer demo.deinit();

    var depth = DepthTarget{};
    defer depth.deinit();

    var width: u32 = 0;
    var height: u32 = 0;
    try configureSurfaceFromWindow(surface, gpu.device, window, surface_format, &width, &height);
    try depth.ensure(gpu.device, width, height);

    var running = true;
    var frame_count: u32 = 0;
    while (running) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event)) {
            switch (event.type) {
                sdl.SDL_EVENT_QUIT => running = false,
                sdl.SDL_EVENT_WINDOW_RESIZED,
                sdl.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
                sdl.SDL_EVENT_WINDOW_METAL_VIEW_RESIZED,
                => {
                    try configureSurfaceFromWindow(surface, gpu.device, window, surface_format, &width, &height);
                    try depth.ensure(gpu.device, width, height);
                },
                else => {},
            }
        }

        if (!running) {
            break;
        }

        if (options.scene_reload) |reload| {
            if (reload.poll(reload.context)) |reloaded_scene| {
                const reloaded_demo = try MeshDemo.create(allocator, gpu.device, gpu.queue, surface_format, reloaded_scene);
                demo.deinit();
                demo = reloaded_demo;
                scene = reloaded_scene;
            }
        }

        const delta_seconds: f32 = 0.025;
        if (options.frame_update) |frame_update| {
            frame_update.step(frame_update.context, delta_seconds);
        }

        try configureSurfaceFromWindow(surface, gpu.device, window, surface_format, &width, &height);
        try depth.ensure(gpu.device, width, height);
        try drawMeshToSurface(surface, gpu.device, gpu.queue, &demo, depth.view orelse return RenderError.NoDevice, .{
            .width = width,
            .height = height,
            .scene = scene,
        });
        instance.processEvents();

        frame_count += 1;
        if (options.max_frames) |max_frames| {
            if (frame_count >= max_frames) {
                break;
            }
        }

        sdl.SDL_Delay(1);
    }
}

const FrameConfig = struct {
    width: u32,
    height: u32,
    scene: Scene,
};

const InstanceConfig = struct {
    width: u32,
    height: u32,
    mesh: *const runtime.RenderableMesh,
    camera: CameraState,
    light_view_projection: [16]f32,
};

const CameraState = struct {
    transform: runtime.Transform = .{ .position = .{ 0.0, 0.0, 4.8 } },
    fov_y_degrees: f32 = 48.0,
    near: f32 = 0.1,
    far: f32 = 100.0,
};

const DirectionalLightState = struct {
    direction: [3]f32 = .{ 0.35, 0.68, 0.64 },
    color: [3]f32 = .{ 1.0, 1.0, 1.0 },
    intensity: f32 = 0.78,
    ambient: f32 = 0.18,
};

const RenderSystemContext = struct {
    device: *wgpu.Device,
    queue: *wgpu.Queue,
    target_view: *wgpu.TextureView,
    depth_view: *wgpu.TextureView,
    frame: FrameConfig,
};

const RenderEcsState = struct {
    allocator: std.mem.Allocator,
    registry: runtime.ComponentRegistry,
    schedule: runtime.SystemSchedule,
    world: runtime.World,

    fn init(allocator: std.mem.Allocator) RenderError!RenderEcsState {
        var registry = runtime.ComponentRegistry.init(allocator);
        errdefer registry.deinit();

        registerRenderEcsTypes(&registry) catch |err| return mapEngineSetupError(err);

        var schedule = registry.buildSchedule(allocator, .render) catch |err| return mapEngineSetupError(err);
        errdefer schedule.deinit();

        return .{
            .allocator = allocator,
            .registry = registry,
            .schedule = schedule,
            .world = runtime.World.init(allocator),
        };
    }

    fn deinit(self: *RenderEcsState) void {
        self.world.deinit();
        self.schedule.deinit();
        self.registry.deinit();
        self.* = undefined;
    }

    fn extractScene(self: *RenderEcsState, scene: Scene) RenderError!void {
        var next_world = runtime.World.init(self.allocator);
        errdefer next_world.deinit();

        var mesh_index: usize = 0;
        var meshes = scene.world.renderableMeshes();
        while (meshes.next()) |mesh| {
            try extractMeshInto(self.allocator, &next_world, mesh_index, mesh);
            mesh_index += 1;
        }

        try extractCameraInto(&next_world, try cameraState(scene.world));
        try extractDirectionalLightInto(&next_world, try directionalLightState(scene.world));

        self.world.deinit();
        self.world = next_world;
    }

    fn queueBatchDraws(self: *RenderEcsState, batch_count: usize) RenderError!void {
        for (0..batch_count) |batch_index| {
            if (batch_index > std.math.maxInt(i32)) {
                return RenderError.InvalidScene;
            }
            const entity_id = std.fmt.allocPrint(self.allocator, "machina.render.draw.batch.{d}", .{batch_index}) catch return RenderError.OutOfMemory;
            defer self.allocator.free(entity_id);

            const entity = self.world.createEntity(entity_id, "Batch Draw") catch |err| return mapWorldError(err);
            const fields = [_]runtime.ComponentFieldValue{
                .{ .name = "batch_index", .value = .{ .int = @intCast(batch_index) } },
            };
            self.world.setComponent(entity, render_draw_batch_component_id, &fields) catch |err| return mapWorldError(err);
        }
    }

    fn drawCommandCount(self: RenderEcsState) usize {
        return self.world.componentInstanceCountFor(render_draw_batch_component_id);
    }

    fn drawCommandBatchIndex(self: RenderEcsState, entity: runtime.EntityHandle) RenderError!usize {
        return batchIndexFromDrawEntity(&self.world, entity);
    }
};

const GpuContext = struct {
    adapter: *wgpu.Adapter,
    device: *wgpu.Device,
    queue: *wgpu.Queue,

    fn deinit(self: *GpuContext) void {
        self.queue.release();
        self.device.release();
        self.adapter.release();
    }
};

const DepthTarget = struct {
    texture: ?*wgpu.Texture = null,
    view: ?*wgpu.TextureView = null,
    width: u32 = 0,
    height: u32 = 0,

    fn create(device: *wgpu.Device, width: u32, height: u32) RenderError!DepthTarget {
        var target = DepthTarget{};
        try target.ensure(device, width, height);
        return target;
    }

    fn ensure(self: *DepthTarget, device: *wgpu.Device, width: u32, height: u32) RenderError!void {
        if (self.view != null and self.width == width and self.height == height) {
            return;
        }

        self.deinit();

        const texture = device.createTexture(&wgpu.TextureDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh depth texture"),
            .size = .{
                .width = width,
                .height = height,
                .depth_or_array_layers = 1,
            },
            .format = depth_format,
            .usage = wgpu.TextureUsages.render_attachment,
        }) orelse return RenderError.NoDevice;
        errdefer texture.release();

        const view = texture.createView(&wgpu.TextureViewDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh depth view"),
            .mip_level_count = 1,
            .array_layer_count = 1,
        }) orelse return RenderError.NoDevice;

        self.texture = texture;
        self.view = view;
        self.width = width;
        self.height = height;
    }

    fn deinit(self: *DepthTarget) void {
        if (self.view) |view| {
            view.release();
        }
        if (self.texture) |texture| {
            texture.release();
        }
        self.* = .{};
    }
};

const ShadowTarget = struct {
    texture: ?*wgpu.Texture = null,
    view: ?*wgpu.TextureView = null,

    fn create(device: *wgpu.Device) RenderError!ShadowTarget {
        const texture = device.createTexture(&wgpu.TextureDescriptor{
            .label = wgpu.StringView.fromSlice("Machina shadow map texture"),
            .size = .{
                .width = shadow_map_size,
                .height = shadow_map_size,
                .depth_or_array_layers = 1,
            },
            .format = shadow_depth_format,
            .usage = wgpu.TextureUsages.render_attachment | wgpu.TextureUsages.texture_binding,
        }) orelse return RenderError.NoDevice;
        errdefer texture.release();

        const view = texture.createView(&wgpu.TextureViewDescriptor{
            .label = wgpu.StringView.fromSlice("Machina shadow map view"),
            .mip_level_count = 1,
            .array_layer_count = 1,
            .aspect = .depth_only,
        }) orelse return RenderError.NoDevice;

        return .{
            .texture = texture,
            .view = view,
        };
    }

    fn deinit(self: *ShadowTarget) void {
        if (self.view) |view| {
            view.release();
        }
        if (self.texture) |texture| {
            texture.release();
        }
        self.* = .{};
    }
};

fn registerRenderEcsTypes(registry: *runtime.ComponentRegistry) !void {
    try runtime.registerEngineComponents(registry);

    const draw_batch_fields = [_]runtime.ComponentFieldDefinition{
        .{ .name = "batch_index", .value_type = .int },
    };
    try registry.registerEngineComponent(.{
        .id = render_draw_batch_component_id,
        .version = 1,
        .fields = &draw_batch_fields,
    });

    const extract_writes = [_][]const u8{
        runtime.transform_component_id,
        runtime.geometry_primitive_component_id,
        runtime.surface_material_component_id,
        runtime.camera_component_id,
        runtime.directional_light_component_id,
        runtime.shadow_caster_component_id,
        runtime.shadow_receiver_component_id,
    };
    try registry.registerEngineSystem(.{
        .id = render_extract_system_id,
        .phase = .render,
        .writes = &extract_writes,
    });

    const prepare_reads = [_][]const u8{
        runtime.transform_component_id,
        runtime.geometry_primitive_component_id,
        runtime.surface_material_component_id,
        runtime.shadow_caster_component_id,
        runtime.shadow_receiver_component_id,
    };
    const after_extract = [_][]const u8{render_extract_system_id};
    try registry.registerEngineSystem(.{
        .id = render_prepare_meshes_system_id,
        .phase = .render,
        .reads = &prepare_reads,
        .after = &after_extract,
    });

    const queue_reads = [_][]const u8{
        runtime.transform_component_id,
        runtime.geometry_primitive_component_id,
        runtime.surface_material_component_id,
        runtime.shadow_caster_component_id,
        runtime.shadow_receiver_component_id,
    };
    const queue_writes = [_][]const u8{render_draw_batch_component_id};
    const after_prepare = [_][]const u8{render_prepare_meshes_system_id};
    try registry.registerEngineSystem(.{
        .id = render_queue_meshes_system_id,
        .phase = .render,
        .reads = &queue_reads,
        .writes = &queue_writes,
        .after = &after_prepare,
    });

    const draw_reads = [_][]const u8{
        render_draw_batch_component_id,
        runtime.transform_component_id,
        runtime.geometry_primitive_component_id,
        runtime.surface_material_component_id,
        runtime.camera_component_id,
        runtime.directional_light_component_id,
        runtime.shadow_caster_component_id,
        runtime.shadow_receiver_component_id,
    };
    const after_queue = [_][]const u8{render_queue_meshes_system_id};
    try registry.registerEngineSystem(.{
        .id = render_draw_meshes_system_id,
        .phase = .render,
        .reads = &draw_reads,
        .after = &after_queue,
    });
}

fn extractMeshInto(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    render_index: usize,
    mesh: runtime.RenderableMesh,
) RenderError!void {
    const entity_id = std.fmt.allocPrint(allocator, "machina.render.extract.mesh.{d}", .{render_index}) catch return RenderError.OutOfMemory;
    defer allocator.free(entity_id);

    const entity = world.createEntity(entity_id, mesh.name) catch |err| return mapWorldError(err);
    world.setTransform(entity, .{
        .position = mesh.position,
        .rotation = mesh.rotation,
        .scale = mesh.scale,
    }) catch |err| return mapWorldError(err);
    world.setGeometryPrimitive(entity, .{
        .primitive = mesh.primitive,
        .segments = mesh.segments,
        .rings = mesh.rings,
    }) catch |err| return mapWorldError(err);
    world.setSurfaceMaterial(entity, .{
        .base_color = mesh.base_color,
    }) catch |err| return mapWorldError(err);
    if (mesh.casts_shadow) {
        world.setShadowCaster(entity) catch |err| return mapWorldError(err);
    }
    if (mesh.receives_shadow) {
        world.setShadowReceiver(entity) catch |err| return mapWorldError(err);
    }
}

fn extractCameraInto(world: *runtime.World, camera: CameraState) RenderError!void {
    const entity = world.createEntity("machina.render.extract.camera", "Render Camera") catch |err| return mapWorldError(err);
    world.setTransform(entity, camera.transform) catch |err| return mapWorldError(err);
    world.setCamera(entity, .{
        .fov_y_degrees = camera.fov_y_degrees,
        .near = camera.near,
        .far = camera.far,
    }) catch |err| return mapWorldError(err);
}

fn extractDirectionalLightInto(world: *runtime.World, light: DirectionalLightState) RenderError!void {
    const entity = world.createEntity("machina.render.extract.directional_light", "Render Directional Light") catch |err| return mapWorldError(err);
    world.setDirectionalLight(entity, .{
        .direction = light.direction,
        .color = light.color,
        .intensity = light.intensity,
        .ambient = light.ambient,
    }) catch |err| return mapWorldError(err);
}

fn batchIndexFromDrawEntity(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!usize {
    const value = world.getComponentFieldValue(entity, render_draw_batch_component_id, "batch_index") catch |err| return mapWorldError(err);
    const batch_index = switch (value) {
        .int => |payload| payload,
        else => return RenderError.InvalidScene,
    };
    if (batch_index < 0) {
        return RenderError.InvalidScene;
    }
    return @intCast(batch_index);
}

fn mapEngineSetupError(err: anyerror) RenderError {
    return switch (err) {
        error.OutOfMemory => RenderError.OutOfMemory,
        else => RenderError.InvalidScene,
    };
}

fn mapWorldError(err: anyerror) RenderError {
    return switch (err) {
        error.OutOfMemory => RenderError.OutOfMemory,
        else => RenderError.InvalidScene,
    };
}

fn mapGeometryError(err: anyerror) RenderError {
    return switch (err) {
        error.OutOfMemory => RenderError.OutOfMemory,
        else => RenderError.InvalidScene,
    };
}

const BatchPlan = struct {
    allocator: std.mem.Allocator,
    batches: []BatchPlanEntry,

    fn build(allocator: std.mem.Allocator, world: *const runtime.World) RenderError!BatchPlan {
        var builds: std.ArrayList(BatchBuild) = .empty;
        errdefer {
            for (builds.items) |*pending_batch| {
                pending_batch.deinit(allocator);
            }
            builds.deinit(allocator);
        }

        const mesh_count = world.renderableMeshCount();
        for (0..mesh_count) |render_index| {
            const renderable = world.renderableMeshAt(render_index) orelse return RenderError.InvalidScene;
            const geometry_key = GeometryKey.fromRenderable(renderable) orelse return RenderError.InvalidScene;
            const material_key = MaterialKey.fromRenderable(renderable);
            const shadow_key = ShadowKey.fromRenderable(renderable);

            var batch_index: ?usize = null;
            for (builds.items, 0..) |pending_batch, index| {
                if (pending_batch.geometry_key.eql(geometry_key) and
                    pending_batch.material_key.eql(material_key) and
                    pending_batch.shadow_key.eql(shadow_key))
                {
                    batch_index = index;
                    break;
                }
            }

            const index = batch_index orelse blk: {
                try builds.append(allocator, .{
                    .geometry_key = geometry_key,
                    .material_key = material_key,
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
                .material_key = pending_batch.material_key,
                .shadow_key = pending_batch.shadow_key,
                .render_indices = pending_batch.render_indices.toOwnedSlice(allocator) catch return RenderError.OutOfMemory,
            };
            copied += 1;
        }

        builds.deinit(allocator);
        return .{
            .allocator = allocator,
            .batches = batches,
        };
    }

    fn deinit(self: *BatchPlan) void {
        const allocator = self.allocator;
        for (self.batches) |entry| {
            allocator.free(entry.render_indices);
        }
        allocator.free(self.batches);
        self.* = .{
            .allocator = allocator,
            .batches = &.{},
        };
    }
};

const BatchBuild = struct {
    geometry_key: GeometryKey,
    material_key: MaterialKey,
    shadow_key: ShadowKey,
    render_indices: std.ArrayList(usize) = .empty,

    fn deinit(self: *BatchBuild, allocator: std.mem.Allocator) void {
        self.render_indices.deinit(allocator);
    }
};

const BatchPlanEntry = struct {
    geometry_key: GeometryKey,
    material_key: MaterialKey,
    shadow_key: ShadowKey,
    render_indices: []usize,
};

const MeshDemo = struct {
    allocator: std.mem.Allocator,
    pipeline: *wgpu.RenderPipeline,
    shadow_pipeline: *wgpu.RenderPipeline,
    bind_group_layout: *wgpu.BindGroupLayout,
    pipeline_layout: *wgpu.PipelineLayout,
    shadow_pipeline_layout: *wgpu.PipelineLayout,
    frame_uniform_buffer: *wgpu.Buffer,
    bind_group: *wgpu.BindGroup,
    shadow_target: ShadowTarget,
    shadow_sampler: *wgpu.Sampler,
    render_state: RenderEcsState,
    batches: []BatchResources,

    fn create(
        allocator: std.mem.Allocator,
        device: *wgpu.Device,
        queue: *wgpu.Queue,
        texture_format: wgpu.TextureFormat,
        scene: Scene,
    ) RenderError!MeshDemo {
        const bind_group_layout_entries = [_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = wgpu.ShaderStages.vertex | wgpu.ShaderStages.fragment,
                .buffer = .{
                    .type = .uniform,
                    .min_binding_size = @sizeOf(FrameUniforms),
                },
            },
            .{
                .binding = 1,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = .{
                    .sample_type = .depth,
                    .view_dimension = .@"2d",
                },
            },
            .{
                .binding = 2,
                .visibility = wgpu.ShaderStages.fragment,
                .sampler = .{
                    .type = .comparison,
                },
            },
        };
        const bind_group_layout = device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh bind group layout"),
            .entry_count = bind_group_layout_entries.len,
            .entries = &bind_group_layout_entries,
        }) orelse return RenderError.NoDevice;
        errdefer bind_group_layout.release();

        const frame_uniform_buffer = device.createBuffer(&wgpu.BufferDescriptor{
            .label = wgpu.StringView.fromSlice("Machina frame uniforms"),
            .usage = wgpu.BufferUsages.uniform | wgpu.BufferUsages.copy_dst,
            .size = @sizeOf(FrameUniforms),
            .mapped_at_creation = @as(u32, @intFromBool(false)),
        }) orelse return RenderError.NoDevice;
        errdefer frame_uniform_buffer.release();

        var initial_uniforms = try frameUniforms(.{});
        writeUniforms(queue, frame_uniform_buffer, &initial_uniforms);

        var shadow_target = try ShadowTarget.create(device);
        errdefer shadow_target.deinit();

        const shadow_sampler = device.createSampler(&wgpu.SamplerDescriptor{
            .label = wgpu.StringView.fromSlice("Machina shadow comparison sampler"),
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
            .mag_filter = .linear,
            .min_filter = .linear,
            .mipmap_filter = .nearest,
            .compare = .less_equal,
        }) orelse return RenderError.NoDevice;
        errdefer shadow_sampler.release();

        const bind_group_entries = [_]wgpu.BindGroupEntry{
            .{
                .binding = 0,
                .buffer = frame_uniform_buffer,
                .size = @sizeOf(FrameUniforms),
            },
            .{
                .binding = 1,
                .texture_view = shadow_target.view orelse return RenderError.NoDevice,
            },
            .{
                .binding = 2,
                .sampler = shadow_sampler,
            },
        };
        const bind_group = device.createBindGroup(&wgpu.BindGroupDescriptor{
            .label = wgpu.StringView.fromSlice("Machina frame bind group"),
            .layout = bind_group_layout,
            .entry_count = bind_group_entries.len,
            .entries = &bind_group_entries,
        }) orelse return RenderError.NoDevice;
        errdefer bind_group.release();

        var render_state = try RenderEcsState.init(allocator);
        errdefer render_state.deinit();
        try render_state.extractScene(scene);

        const batches = allocator.alloc(BatchResources, 0) catch return RenderError.OutOfMemory;
        errdefer allocator.free(batches);

        const bind_group_layouts = [_]*wgpu.BindGroupLayout{bind_group_layout};
        const pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh pipeline layout"),
            .bind_group_layout_count = bind_group_layouts.len,
            .bind_group_layouts = &bind_group_layouts,
        }) orelse return RenderError.NoDevice;
        errdefer pipeline_layout.release();

        const pipeline = try createMeshPipeline(device, texture_format, pipeline_layout);
        errdefer pipeline.release();

        const empty_bind_group_layouts = [_]*wgpu.BindGroupLayout{};
        const shadow_pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Machina shadow pipeline layout"),
            .bind_group_layout_count = empty_bind_group_layouts.len,
            .bind_group_layouts = &empty_bind_group_layouts,
        }) orelse return RenderError.NoDevice;
        errdefer shadow_pipeline_layout.release();

        const shadow_pipeline = try createShadowPipeline(device, shadow_pipeline_layout);
        errdefer shadow_pipeline.release();

        return .{
            .allocator = allocator,
            .pipeline = pipeline,
            .shadow_pipeline = shadow_pipeline,
            .bind_group_layout = bind_group_layout,
            .pipeline_layout = pipeline_layout,
            .shadow_pipeline_layout = shadow_pipeline_layout,
            .frame_uniform_buffer = frame_uniform_buffer,
            .bind_group = bind_group,
            .shadow_target = shadow_target,
            .shadow_sampler = shadow_sampler,
            .render_state = render_state,
            .batches = batches,
        };
    }

    fn deinit(self: *MeshDemo) void {
        self.render_state.deinit();
        for (self.batches) |*batch| {
            batch.deinit();
        }
        self.allocator.free(self.batches);
        self.bind_group.release();
        self.frame_uniform_buffer.release();
        self.shadow_sampler.release();
        self.shadow_target.deinit();
        self.pipeline.release();
        self.shadow_pipeline.release();
        self.pipeline_layout.release();
        self.shadow_pipeline_layout.release();
        self.bind_group_layout.release();
    }

    fn draw(
        self: *MeshDemo,
        device: *wgpu.Device,
        queue: *wgpu.Queue,
        target_view: *wgpu.TextureView,
        depth_view: *wgpu.TextureView,
        config: FrameConfig,
    ) RenderError!void {
        try self.runRenderSchedule(.{
            .device = device,
            .queue = queue,
            .target_view = target_view,
            .depth_view = depth_view,
            .frame = config,
        });
    }

    fn runRenderSchedule(self: *MeshDemo, context: RenderSystemContext) RenderError!void {
        var maybe_plan: ?BatchPlan = null;
        defer if (maybe_plan) |*plan| {
            plan.deinit();
        };

        for (self.render_state.schedule.batches) |batch| {
            for (batch.systems) |system| {
                if (std.mem.eql(u8, system.id, render_extract_system_id)) {
                    try self.render_state.extractScene(context.frame.scene);
                } else if (std.mem.eql(u8, system.id, render_prepare_meshes_system_id)) {
                    var plan = try BatchPlan.build(self.allocator, &self.render_state.world);
                    var plan_transferred = false;
                    errdefer if (!plan_transferred) {
                        plan.deinit();
                    };
                    try self.prepareBatchResources(context.device, plan);
                    try self.updateBatchInstances(context.queue, plan, context.frame);
                    maybe_plan = plan;
                    plan_transferred = true;
                } else if (std.mem.eql(u8, system.id, render_queue_meshes_system_id)) {
                    const plan = maybe_plan orelse return RenderError.InvalidScene;
                    try self.render_state.queueBatchDraws(plan.batches.len);
                } else if (std.mem.eql(u8, system.id, render_draw_meshes_system_id)) {
                    try self.drawQueuedBatches(context);
                } else {
                    return RenderError.InvalidScene;
                }
            }
        }
    }

    fn prepareBatchResources(self: *MeshDemo, device: *wgpu.Device, plan: BatchPlan) RenderError!void {
        if (self.batchResourcesMatchPlan(plan)) {
            return;
        }

        const new_batches = self.allocator.alloc(BatchResources, plan.batches.len) catch return RenderError.OutOfMemory;
        var batch_count: usize = 0;
        errdefer {
            for (new_batches[0..batch_count]) |*batch| {
                batch.deinit();
            }
            self.allocator.free(new_batches);
        }

        for (plan.batches, 0..) |entry, index| {
            new_batches[index] = try BatchResources.create(self.allocator, device, entry);
            batch_count += 1;
        }

        for (self.batches) |*batch| {
            batch.deinit();
        }
        self.allocator.free(self.batches);
        self.batches = new_batches;
    }

    fn batchResourcesMatchPlan(self: MeshDemo, plan: BatchPlan) bool {
        if (self.batches.len != plan.batches.len) {
            return false;
        }
        for (plan.batches, self.batches) |entry, batch| {
            if (!batch.matches(entry)) {
                return false;
            }
        }
        return true;
    }

    fn updateBatchInstances(self: *MeshDemo, queue: *wgpu.Queue, plan: BatchPlan, config: FrameConfig) RenderError!void {
        const camera = try cameraState(&self.render_state.world);
        const light = try directionalLightState(&self.render_state.world);
        const light_view_projection = try shadowLightViewProjection(light);
        for (plan.batches, 0..) |entry, batch_index| {
            if (batch_index >= self.batches.len) {
                return RenderError.InvalidScene;
            }

            const instances = self.allocator.alloc(InstanceAttributes, entry.render_indices.len) catch return RenderError.OutOfMemory;
            defer self.allocator.free(instances);

            for (entry.render_indices, 0..) |render_index, instance_index| {
                const mesh = self.render_state.world.renderableMeshAt(render_index) orelse return RenderError.InvalidScene;
                instances[instance_index] = try instanceAttributes(.{
                    .width = config.width,
                    .height = config.height,
                    .mesh = &mesh,
                    .camera = camera,
                    .light_view_projection = light_view_projection,
                });
            }

            const bytes = std.mem.sliceAsBytes(instances);
            queue.writeBuffer(self.batches[batch_index].instance_buffer, 0, bytes.ptr, bytes.len);
        }
    }

    fn drawQueuedBatches(self: *MeshDemo, context: RenderSystemContext) RenderError!void {
        const light = try directionalLightState(&self.render_state.world);
        var frame_uniforms = try frameUniforms(light);
        writeUniforms(context.queue, self.frame_uniform_buffer, &frame_uniforms);

        var draw_batch_indices: std.ArrayList(usize) = .empty;
        defer draw_batch_indices.deinit(self.allocator);

        var draw_cursor: usize = 0;
        const draw_query = [_][]const u8{render_draw_batch_component_id};
        while (self.render_state.world.queryNext(&draw_query, &draw_cursor)) |draw_entity| {
            const batch_index = try self.render_state.drawCommandBatchIndex(draw_entity);
            if (batch_index >= self.batches.len) {
                return RenderError.InvalidScene;
            }
            draw_batch_indices.append(self.allocator, batch_index) catch return RenderError.OutOfMemory;
        }

        const encoder = context.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh command encoder"),
        }) orelse return RenderError.NoDevice;
        defer encoder.release();

        try self.drawShadowPass(encoder, draw_batch_indices.items);

        const color_attachments = [_]wgpu.ColorAttachment{
            .{
                .view = context.target_view,
                .clear_value = .{
                    .r = 0.025,
                    .g = 0.028,
                    .b = 0.032,
                    .a = 1.0,
                },
            },
        };
        const depth_attachment = wgpu.DepthStencilAttachment{
            .view = context.depth_view,
            .depth_load_op = .clear,
            .depth_store_op = .store,
            .depth_clear_value = 1.0,
        };

        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .color_attachment_count = color_attachments.len,
            .color_attachments = &color_attachments,
            .depth_stencil_attachment = &depth_attachment,
        }) orelse return RenderError.NoDevice;
        defer render_pass.release();
        render_pass.setPipeline(self.pipeline);
        render_pass.setBindGroup(0, self.bind_group, 0, null);
        for (draw_batch_indices.items) |batch_index| {
            const batch = self.batches[batch_index];
            render_pass.setVertexBuffer(0, batch.vertex_buffer, 0, batch.vertex_buffer_size);
            render_pass.setVertexBuffer(1, batch.instance_buffer, 0, batch.instance_buffer_size);
            render_pass.setIndexBuffer(batch.index_buffer, .uint16, 0, batch.index_buffer_size);
            render_pass.drawIndexed(batch.index_count, batch.instance_count, 0, 0, 0);
        }
        render_pass.end();

        const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh command buffer"),
        }) orelse return RenderError.NoDevice;
        defer command_buffer.release();

        const command_buffers = [_]*const wgpu.CommandBuffer{command_buffer};
        context.queue.submit(&command_buffers);
    }

    fn drawShadowPass(self: *MeshDemo, encoder: *wgpu.CommandEncoder, draw_batch_indices: []const usize) RenderError!void {
        const shadow_view = self.shadow_target.view orelse return RenderError.NoDevice;
        const depth_attachment = wgpu.DepthStencilAttachment{
            .view = shadow_view,
            .depth_load_op = .clear,
            .depth_store_op = .store,
            .depth_clear_value = 1.0,
        };
        const color_attachments = [_]wgpu.ColorAttachment{};
        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .label = wgpu.StringView.fromSlice("Machina shadow pass"),
            .color_attachment_count = color_attachments.len,
            .color_attachments = &color_attachments,
            .depth_stencil_attachment = &depth_attachment,
        }) orelse return RenderError.NoDevice;
        defer render_pass.release();

        render_pass.setPipeline(self.shadow_pipeline);
        for (draw_batch_indices) |batch_index| {
            const batch = self.batches[batch_index];
            if (!batch.shadow_key.casts_shadow) {
                continue;
            }
            render_pass.setVertexBuffer(0, batch.vertex_buffer, 0, batch.vertex_buffer_size);
            render_pass.setVertexBuffer(1, batch.instance_buffer, 0, batch.instance_buffer_size);
            render_pass.setIndexBuffer(batch.index_buffer, .uint16, 0, batch.index_buffer_size);
            render_pass.drawIndexed(batch.index_count, batch.instance_count, 0, 0, 0);
        }
        render_pass.end();
    }
};

const BatchResources = struct {
    geometry_key: GeometryKey,
    material_key: MaterialKey,
    shadow_key: ShadowKey,
    vertex_buffer: *wgpu.Buffer,
    index_buffer: *wgpu.Buffer,
    instance_buffer: *wgpu.Buffer,
    vertex_buffer_size: u64,
    index_buffer_size: u64,
    instance_buffer_size: u64,
    index_count: u32,
    instance_count: u32,

    fn create(
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
        const vertex_buffer = try createStaticBuffer(device, "Machina mesh vertex buffer", wgpu.BufferUsages.vertex, vertex_bytes);
        errdefer vertex_buffer.release();

        const index_buffer = try createStaticBuffer(device, "Machina mesh index buffer", wgpu.BufferUsages.index, index_bytes);
        errdefer index_buffer.release();

        if (entry.render_indices.len > std.math.maxInt(u32)) {
            return RenderError.InvalidScene;
        }
        const instance_buffer_size = @sizeOf(InstanceAttributes) * entry.render_indices.len;
        const instance_buffer = device.createBuffer(&wgpu.BufferDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh instance buffer"),
            .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
            .size = @intCast(instance_buffer_size),
            .mapped_at_creation = @as(u32, @intFromBool(false)),
        }) orelse return RenderError.NoDevice;
        errdefer instance_buffer.release();

        return .{
            .geometry_key = entry.geometry_key,
            .material_key = entry.material_key,
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

    fn matches(self: BatchResources, entry: BatchPlanEntry) bool {
        if (entry.render_indices.len > std.math.maxInt(u32)) {
            return false;
        }
        return self.geometry_key.eql(entry.geometry_key) and
            self.material_key.eql(entry.material_key) and
            self.shadow_key.eql(entry.shadow_key) and
            self.instance_count == @as(u32, @intCast(entry.render_indices.len));
    }

    fn deinit(self: *BatchResources) void {
        self.instance_buffer.release();
        self.index_buffer.release();
        self.vertex_buffer.release();
    }
};

const GeometryKey = struct {
    primitive: geometry.Primitive,
    segments: i32,
    rings: i32,

    fn fromRenderable(renderable: runtime.RenderableMesh) ?GeometryKey {
        return .{
            .primitive = geometry.parsePrimitive(renderable.primitive) orelse return null,
            .segments = renderable.segments,
            .rings = renderable.rings,
        };
    }

    fn eql(self: GeometryKey, other: GeometryKey) bool {
        return self.primitive == other.primitive and self.segments == other.segments and self.rings == other.rings;
    }
};

const MaterialKey = struct {
    base_color: [3]f32,

    fn fromRenderable(renderable: runtime.RenderableMesh) MaterialKey {
        return .{ .base_color = renderable.base_color };
    }

    fn eql(self: MaterialKey, other: MaterialKey) bool {
        return self.base_color[0] == other.base_color[0] and
            self.base_color[1] == other.base_color[1] and
            self.base_color[2] == other.base_color[2];
    }
};

const ShadowKey = struct {
    casts_shadow: bool,
    receives_shadow: bool,

    fn fromRenderable(renderable: runtime.RenderableMesh) ShadowKey {
        return .{
            .casts_shadow = renderable.casts_shadow,
            .receives_shadow = renderable.receives_shadow,
        };
    }

    fn eql(self: ShadowKey, other: ShadowKey) bool {
        return self.casts_shadow == other.casts_shadow and self.receives_shadow == other.receives_shadow;
    }
};

fn openGpu(instance: *wgpu.Instance, compatible_surface: ?*wgpu.Surface) RenderError!GpuContext {
    const adapter_response = instance.requestAdapterSync(&wgpu.RequestAdapterOptions{
        .compatible_surface = compatible_surface,
    }, 200_000_000);
    const adapter = switch (adapter_response.status) {
        .success => adapter_response.adapter orelse return RenderError.NoAdapter,
        else => return RenderError.NoAdapter,
    };
    errdefer adapter.release();

    const device_response = adapter.requestDeviceSync(instance, &wgpu.DeviceDescriptor{
        .required_limits = null,
    }, 200_000_000);
    const device = switch (device_response.status) {
        .success => device_response.device orelse return RenderError.NoDevice,
        else => return RenderError.NoDevice,
    };
    errdefer device.release();

    const queue = device.getQueue() orelse return RenderError.NoDevice;
    errdefer queue.release();

    return .{
        .adapter = adapter,
        .device = device,
        .queue = queue,
    };
}

fn chooseSurfaceFormat(capabilities: wgpu.SurfaceCapabilities) ?wgpu.TextureFormat {
    for (capabilities.formats[0..capabilities.format_count]) |format| {
        if (format == .bgra8_unorm_srgb) {
            return format;
        }
    }

    if (capabilities.format_count == 0) {
        return null;
    }
    return capabilities.formats[0];
}

fn configureSurfaceFromWindow(
    surface: *wgpu.Surface,
    device: *wgpu.Device,
    window: *sdl.SDL_Window,
    format: wgpu.TextureFormat,
    current_width: *u32,
    current_height: *u32,
) !void {
    var pixel_width: c_int = 0;
    var pixel_height: c_int = 0;
    if (!sdl.SDL_GetWindowSizeInPixels(window, &pixel_width, &pixel_height)) {
        return RenderError.SurfaceFailed;
    }

    const width: u32 = @intCast(@max(pixel_width, 1));
    const height: u32 = @intCast(@max(pixel_height, 1));
    if (width == current_width.* and height == current_height.*) {
        return;
    }

    surface.configure(&wgpu.SurfaceConfiguration{
        .device = device,
        .format = format,
        .width = width,
        .height = height,
        .present_mode = .fifo,
    });
    current_width.* = width;
    current_height.* = height;
}

fn drawMeshToSurface(
    surface: *wgpu.Surface,
    device: *wgpu.Device,
    queue: *wgpu.Queue,
    demo: *MeshDemo,
    depth_view: *wgpu.TextureView,
    config: FrameConfig,
) !void {
    var surface_texture = wgpu.SurfaceTexture{
        .next_in_chain = null,
        .texture = null,
        .status = .@"error",
    };
    surface.getCurrentTexture(&surface_texture);
    switch (surface_texture.status) {
        .success_optimal, .success_suboptimal => {},
        else => return RenderError.SurfaceFailed,
    }

    const texture = surface_texture.texture orelse return RenderError.SurfaceFailed;
    defer texture.release();

    const view = texture.createView(&wgpu.TextureViewDescriptor{
        .label = wgpu.StringView.fromSlice("Machina surface texture view"),
        .mip_level_count = 1,
        .array_layer_count = 1,
    }) orelse return RenderError.NoDevice;
    defer view.release();

    try demo.draw(device, queue, view, depth_view, config);
    if (surface.present() != .success) {
        return RenderError.SurfaceFailed;
    }
}

fn createMeshPipeline(device: *wgpu.Device, texture_format: wgpu.TextureFormat, pipeline_layout: *wgpu.PipelineLayout) RenderError!*wgpu.RenderPipeline {
    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("shaders/demo.wgsl"),
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
        .label = wgpu.StringView.fromSlice("Machina mesh pipeline"),
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

fn createShadowPipeline(device: *wgpu.Device, pipeline_layout: *wgpu.PipelineLayout) RenderError!*wgpu.RenderPipeline {
    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("shaders/shadow.wgsl"),
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
        .label = wgpu.StringView.fromSlice("Machina shadow pipeline"),
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

fn createStaticBuffer(device: *wgpu.Device, label: []const u8, usage: wgpu.BufferUsage, data: []const u8) RenderError!*wgpu.Buffer {
    const buffer = device.createBuffer(&wgpu.BufferDescriptor{
        .label = wgpu.StringView.fromSlice(label),
        .usage = usage,
        .size = data.len,
        .mapped_at_creation = @as(u32, @intFromBool(true)),
    }) orelse return RenderError.NoDevice;
    errdefer buffer.release();

    const mapped: [*]u8 = @ptrCast(@alignCast(buffer.getMappedRange(0, data.len) orelse return RenderError.NoDevice));
    @memcpy(mapped[0..data.len], data);
    buffer.unmap();
    return buffer;
}

fn writeUniforms(queue: *wgpu.Queue, buffer: *wgpu.Buffer, uniforms: *const FrameUniforms) void {
    const bytes = std.mem.asBytes(uniforms);
    queue.writeBuffer(buffer, 0, bytes.ptr, bytes.len);
}

fn frameUniforms(light_value: DirectionalLightState) RenderError!FrameUniforms {
    const light = try validateDirectionalLight(light_value);
    const normalized_light = normalizeVec3(light.direction);

    return .{
        .light_dir = .{ normalized_light[0], normalized_light[1], normalized_light[2], 0.0 },
        .light_color = .{ light.color[0], light.color[1], light.color[2], 1.0 },
        .lighting = .{ light.ambient, light.intensity, 0.0, 0.0 },
    };
}

fn instanceAttributes(config: InstanceConfig) RenderError!InstanceAttributes {
    const aspect = @as(f32, @floatFromInt(config.width)) / @as(f32, @floatFromInt(config.height));
    const mesh = config.mesh;
    const rotation = matMul(
        rotationZ(mesh.rotation[2]),
        matMul(
            rotationY(mesh.rotation[1]),
            rotationX(mesh.rotation[0]),
        ),
    );
    const model = matMul(
        translation(mesh.position[0], mesh.position[1], mesh.position[2]),
        matMul(rotation, scaling(mesh.scale[0], mesh.scale[1], mesh.scale[2])),
    );
    const camera = try validateCamera(config.camera);
    const view = cameraViewMatrix(camera.transform);
    const projection = perspective(std.math.degreesToRadians(camera.fov_y_degrees), aspect, camera.near, camera.far);
    const mvp = matMul(projection, matMul(view, model));
    const shadow_mvp = matMul(config.light_view_projection, model);

    return .{
        .mvp = mvp,
        .model = model,
        .object_color = .{ mesh.base_color[0], mesh.base_color[1], mesh.base_color[2], 1.0 },
        .shadow_mvp = shadow_mvp,
        .shadow_flags = .{
            @floatFromInt(@as(u32, @intFromBool(mesh.receives_shadow))),
            @floatFromInt(@as(u32, @intFromBool(mesh.casts_shadow))),
            0.0,
            0.0,
        },
    };
}

fn shadowLightViewProjection(light_value: DirectionalLightState) RenderError![16]f32 {
    const light = try validateDirectionalLight(light_value);
    const light_direction = normalizeVec3(light.direction);
    const eye = scaleVec3(light_direction, 7.5);
    const target = [3]f32{ 0.0, 0.0, 0.0 };
    const preferred_up = [3]f32{ 0.0, 1.0, 0.0 };
    const up = if (@abs(dotVec3(light_direction, preferred_up)) > 0.95)
        [3]f32{ 0.0, 0.0, 1.0 }
    else
        preferred_up;
    const view = lookAt(eye, target, up);
    const projection = orthographic(-5.2, 5.2, -3.9, 3.9, 0.1, 18.0);
    return matMul(projection, view);
}

fn cameraState(world: *const runtime.World) RenderError!CameraState {
    if (world.renderCamera()) |camera| {
        return validateCamera(.{
            .transform = camera.transform,
            .fov_y_degrees = camera.fov_y_degrees,
            .near = camera.near,
            .far = camera.far,
        });
    }
    if (world.componentInstanceCountFor(runtime.camera_component_id) != 0) {
        return RenderError.InvalidScene;
    }
    return .{};
}

fn directionalLightState(world: *const runtime.World) RenderError!DirectionalLightState {
    if (world.renderDirectionalLight()) |light| {
        return validateDirectionalLight(.{
            .direction = light.direction,
            .color = light.color,
            .intensity = light.intensity,
            .ambient = light.ambient,
        });
    }
    return .{};
}

fn validateCamera(camera: CameraState) RenderError!CameraState {
    if (!isFiniteVec3(camera.transform.position) or
        !isFiniteVec3(camera.transform.rotation) or
        !isFiniteVec3(camera.transform.scale) or
        !std.math.isFinite(camera.fov_y_degrees) or
        !std.math.isFinite(camera.near) or
        !std.math.isFinite(camera.far) or
        camera.fov_y_degrees <= 0.0 or
        camera.fov_y_degrees >= 179.0 or
        camera.near <= 0.0 or
        camera.far <= camera.near)
    {
        return RenderError.InvalidScene;
    }
    return camera;
}

fn validateDirectionalLight(light: DirectionalLightState) RenderError!DirectionalLightState {
    if (!isFiniteVec3(light.direction) or
        !isFiniteVec3(light.color) or
        !std.math.isFinite(light.intensity) or
        !std.math.isFinite(light.ambient) or
        vec3Length(light.direction) == 0.0 or
        light.intensity < 0.0 or
        light.ambient < 0.0)
    {
        return RenderError.InvalidScene;
    }
    return light;
}

fn cameraViewMatrix(transform_value: runtime.Transform) [16]f32 {
    const inverse_translation = translation(
        -transform_value.position[0],
        -transform_value.position[1],
        -transform_value.position[2],
    );
    return matMul(
        rotationX(-transform_value.rotation[0]),
        matMul(
            rotationY(-transform_value.rotation[1]),
            matMul(rotationZ(-transform_value.rotation[2]), inverse_translation),
        ),
    );
}

fn lookAt(eye: [3]f32, target: [3]f32, up: [3]f32) [16]f32 {
    const z = normalizeVec3(subtractVec3(eye, target));
    const x = normalizeVec3(crossVec3(up, z));
    const y = crossVec3(z, x);

    return .{
        x[0],             y[0],             z[0],             0.0,
        x[1],             y[1],             z[1],             0.0,
        x[2],             y[2],             z[2],             0.0,
        -dotVec3(x, eye), -dotVec3(y, eye), -dotVec3(z, eye), 1.0,
    };
}

fn isFiniteVec3(value: [3]f32) bool {
    return std.math.isFinite(value[0]) and std.math.isFinite(value[1]) and std.math.isFinite(value[2]);
}

fn subtractVec3(left: [3]f32, right: [3]f32) [3]f32 {
    return .{ left[0] - right[0], left[1] - right[1], left[2] - right[2] };
}

fn scaleVec3(value: [3]f32, scalar: f32) [3]f32 {
    return .{ value[0] * scalar, value[1] * scalar, value[2] * scalar };
}

fn dotVec3(left: [3]f32, right: [3]f32) f32 {
    return left[0] * right[0] + left[1] * right[1] + left[2] * right[2];
}

fn crossVec3(left: [3]f32, right: [3]f32) [3]f32 {
    return .{
        left[1] * right[2] - left[2] * right[1],
        left[2] * right[0] - left[0] * right[2],
        left[0] * right[1] - left[1] * right[0],
    };
}

fn normalizeVec3(value: [3]f32) [3]f32 {
    const length = vec3Length(value);
    if (length == 0.0) {
        return .{ 0.0, 0.0, 1.0 };
    }
    return .{ value[0] / length, value[1] / length, value[2] / length };
}

fn vec3Length(value: [3]f32) f32 {
    return @sqrt(value[0] * value[0] + value[1] * value[1] + value[2] * value[2]);
}

test "camera state falls back only when no camera component exists" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const fallback = try cameraState(&world);
    try std.testing.expectEqual(@as(f32, 4.8), fallback.transform.position[2]);

    const camera_entity = try world.createEntity("camera", "Camera");
    try world.setCamera(camera_entity, .{});
    try std.testing.expectError(RenderError.InvalidScene, cameraState(&world));

    try world.setTransform(camera_entity, .{ .position = .{ 0.0, 0.0, 6.0 } });
    const resolved = try cameraState(&world);
    try std.testing.expectEqual(@as(f32, 6.0), resolved.transform.position[2]);
}

test "render ECS schedule orders extract prepare queue and draw systems" {
    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();

    try std.testing.expectEqual(@as(usize, 4), state.schedule.systemCount());
    try std.testing.expectEqual(@as(usize, 4), state.schedule.batchCount());

    const expected = [_][]const u8{
        render_extract_system_id,
        render_prepare_meshes_system_id,
        render_queue_meshes_system_id,
        render_draw_meshes_system_id,
    };
    for (expected, state.schedule.batches) |system_id, batch| {
        try std.testing.expectEqual(runtime.SystemPhase.render, batch.phase);
        try std.testing.expectEqual(@as(usize, 1), batch.systems.len);
        try std.testing.expectEqualStrings(system_id, batch.systems[0].id);
    }
}

test "render ECS extracts scene data and queues mesh draw commands" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const cool_box = try scene_world.createEntity("cool-box", "Cool Box");
    try scene_world.setTransform(cool_box, .{
        .position = .{ -1.0, 0.0, 0.0 },
        .rotation = .{ 0.1, 0.2, 0.3 },
    });
    try scene_world.setCubeRenderer(cool_box, .{
        .color = .{ 0.1, 0.5, 1.0 },
    });
    try scene_world.setShadowCaster(cool_box);

    const warm_sphere = try scene_world.createEntity("warm-sphere", "Warm Sphere");
    try scene_world.setTransform(warm_sphere, .{
        .position = .{ 1.0, 0.0, 0.0 },
        .scale = .{ 0.8, 0.8, 0.8 },
    });
    try scene_world.setGeometryPrimitive(warm_sphere, .{
        .primitive = "uv_sphere",
        .segments = 16,
        .rings = 8,
    });
    try scene_world.setSurfaceMaterial(warm_sphere, .{
        .base_color = .{ 1.0, 0.35, 0.12 },
    });
    try scene_world.setShadowReceiver(warm_sphere);

    const camera = try scene_world.createEntity("camera", "Camera");
    try scene_world.setTransform(camera, .{ .position = .{ 0.0, 1.0, 7.0 } });
    try scene_world.setCamera(camera, .{ .fov_y_degrees = 52.0 });

    const light = try scene_world.createEntity("key-light", "Key Light");
    try scene_world.setDirectionalLight(light, .{ .intensity = 1.25 });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractScene(.{ .world = &scene_world });

    try std.testing.expectEqual(@as(usize, 4), state.world.entityCount());
    try std.testing.expectEqual(@as(usize, 2), state.world.renderableMeshCount());
    try std.testing.expectEqual(@as(f32, 52.0), (state.world.renderCamera() orelse return error.TestExpectedEqual).fov_y_degrees);
    try std.testing.expectEqual(@as(f32, 1.25), (state.world.renderDirectionalLight() orelse return error.TestExpectedEqual).intensity);
    const extracted_sphere = state.world.renderableMeshAt(1) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("uv_sphere", extracted_sphere.primitive);
    try std.testing.expectEqual(@as(f32, 0.35), extracted_sphere.base_color[1]);
    const extracted_box = state.world.renderableMeshAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expect(extracted_box.casts_shadow);
    try std.testing.expect(!extracted_box.receives_shadow);
    try std.testing.expect(!extracted_sphere.casts_shadow);
    try std.testing.expect(extracted_sphere.receives_shadow);

    var plan = try BatchPlan.build(std.testing.allocator, &state.world);
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 2), plan.batches.len);

    try state.queueBatchDraws(plan.batches.len);
    try std.testing.expectEqual(@as(usize, 2), state.drawCommandCount());

    var cursor: usize = 0;
    const draw_query = [_][]const u8{render_draw_batch_component_id};
    const first_draw = state.world.queryNext(&draw_query, &cursor) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 0), try state.drawCommandBatchIndex(first_draw));
    const second_draw = state.world.queryNext(&draw_query, &cursor) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), try state.drawCommandBatchIndex(second_draw));
    try std.testing.expect(state.world.queryNext(&draw_query, &cursor) == null);
}

test "batch plan groups matching geometry and material renderables" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    try addBatchTestRenderable(&scene_world, "blue-box-a", "box", 0, 0, .{ -1.6, 0.0, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "gold-sphere", "uv_sphere", 16, 8, .{ 0.0, 0.0, 0.0 }, .{ 1.0, 0.56, 0.1 }, .{});
    try addBatchTestRenderable(&scene_world, "blue-box-b", "box", 0, 0, .{ 1.6, 0.0, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "red-box", "box", 0, 0, .{ 0.0, 1.2, 0.0 }, .{ 0.95, 0.12, 0.18 }, .{});
    try addBatchTestRenderable(&scene_world, "blue-box-receiver", "box", 0, 0, .{ 0.0, -1.2, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .receives_shadow = true });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractScene(.{ .world = &scene_world });

    var plan = try BatchPlan.build(std.testing.allocator, &state.world);
    defer plan.deinit();

    try std.testing.expectEqual(@as(usize, 4), plan.batches.len);
    try std.testing.expectEqual(geometry.Primitive.box, plan.batches[0].geometry_key.primitive);
    try std.testing.expect(plan.batches[0].shadow_key.casts_shadow);
    try std.testing.expect(!plan.batches[0].shadow_key.receives_shadow);
    try std.testing.expectEqual(@as(usize, 2), plan.batches[0].render_indices.len);
    try std.testing.expectEqual(@as(usize, 0), plan.batches[0].render_indices[0]);
    try std.testing.expectEqual(@as(usize, 2), plan.batches[0].render_indices[1]);

    try std.testing.expectEqual(geometry.Primitive.uv_sphere, plan.batches[1].geometry_key.primitive);
    try std.testing.expectEqual(@as(usize, 1), plan.batches[1].render_indices.len);
    try std.testing.expectEqual(@as(usize, 1), plan.batches[1].render_indices[0]);

    try std.testing.expectEqual(geometry.Primitive.box, plan.batches[2].geometry_key.primitive);
    try std.testing.expectEqual(@as(usize, 1), plan.batches[2].render_indices.len);
    try std.testing.expectEqual(@as(usize, 3), plan.batches[2].render_indices[0]);

    try std.testing.expectEqual(geometry.Primitive.box, plan.batches[3].geometry_key.primitive);
    try std.testing.expect(!plan.batches[3].shadow_key.casts_shadow);
    try std.testing.expect(plan.batches[3].shadow_key.receives_shadow);
    try std.testing.expectEqual(@as(usize, 1), plan.batches[3].render_indices.len);
    try std.testing.expectEqual(@as(usize, 4), plan.batches[3].render_indices[0]);

    try state.queueBatchDraws(plan.batches.len);
    try std.testing.expectEqual(@as(usize, 4), state.drawCommandCount());
}

const BatchTestShadowFlags = struct {
    casts_shadow: bool = false,
    receives_shadow: bool = false,
};

fn addBatchTestRenderable(
    world: *runtime.World,
    id: []const u8,
    primitive: []const u8,
    segments: i32,
    rings: i32,
    position: [3]f32,
    base_color: [3]f32,
    shadow_flags: BatchTestShadowFlags,
) !void {
    const entity = try world.createEntity(id, id);
    try world.setTransform(entity, .{ .position = position });
    try world.setGeometryPrimitive(entity, .{
        .primitive = primitive,
        .segments = segments,
        .rings = rings,
    });
    try world.setSurfaceMaterial(entity, .{ .base_color = base_color });
    if (shadow_flags.casts_shadow) {
        try world.setShadowCaster(entity);
    }
    if (shadow_flags.receives_shadow) {
        try world.setShadowReceiver(entity);
    }
}

fn perspective(fovy_radians: f32, aspect: f32, near: f32, far: f32) [16]f32 {
    const f = 1.0 / @tan(fovy_radians * 0.5);
    return .{
        f / aspect, 0.0, 0.0,                         0.0,
        0.0,        f,   0.0,                         0.0,
        0.0,        0.0, far / (near - far),          -1.0,
        0.0,        0.0, (far * near) / (near - far), 0.0,
    };
}

fn orthographic(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) [16]f32 {
    return .{
        2.0 / (right - left),             0.0,                              0.0,                 0.0,
        0.0,                              2.0 / (top - bottom),             0.0,                 0.0,
        0.0,                              0.0,                              1.0 / (near - far),  0.0,
        -(right + left) / (right - left), -(top + bottom) / (top - bottom), near / (near - far), 1.0,
    };
}

fn translation(x: f32, y: f32, z: f32) [16]f32 {
    return .{
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        x,   y,   z,   1.0,
    };
}

fn scaling(x: f32, y: f32, z: f32) [16]f32 {
    return .{
        x,   0.0, 0.0, 0.0,
        0.0, y,   0.0, 0.0,
        0.0, 0.0, z,   0.0,
        0.0, 0.0, 0.0, 1.0,
    };
}

fn rotationX(angle: f32) [16]f32 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{
        1.0, 0.0, 0.0, 0.0,
        0.0, c,   s,   0.0,
        0.0, -s,  c,   0.0,
        0.0, 0.0, 0.0, 1.0,
    };
}

fn rotationY(angle: f32) [16]f32 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{
        c,   0.0, -s,  0.0,
        0.0, 1.0, 0.0, 0.0,
        s,   0.0, c,   0.0,
        0.0, 0.0, 0.0, 1.0,
    };
}

fn rotationZ(angle: f32) [16]f32 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{
        c,   s,   0.0, 0.0,
        -s,  c,   0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    };
}

fn matMul(a: [16]f32, b: [16]f32) [16]f32 {
    var out: [16]f32 = undefined;
    for (0..4) |column| {
        for (0..4) |row| {
            var sum: f32 = 0.0;
            for (0..4) |k| {
                sum += a[k * 4 + row] * b[column * 4 + k];
            }
            out[column * 4 + row] = sum;
        }
    }
    return out;
}

const FrameUniforms = extern struct {
    light_dir: [4]f32,
    light_color: [4]f32,
    lighting: [4]f32,
};

const InstanceAttributes = extern struct {
    mvp: [16]f32,
    model: [16]f32,
    object_color: [4]f32,
    shadow_mvp: [16]f32,
    shadow_flags: [4]f32,
};

fn handleBufferMap(status: wgpu.MapAsyncStatus, _: wgpu.StringView, userdata1: ?*anyopaque, userdata2: ?*anyopaque) callconv(.c) void {
    const complete: *bool = @ptrCast(@alignCast(userdata1));
    complete.* = true;

    const map_status: *wgpu.MapAsyncStatus = @ptrCast(@alignCast(userdata2));
    map_status.* = status;
}

fn write24BitBmp(io: Io, allocator: std.mem.Allocator, output_path: []const u8, bgra_data: []const u8) !void {
    const bytes = try allocator.alloc(u8, bmpFileSize());
    defer allocator.free(bytes);
    @memset(bytes, 0);

    var cursor: usize = 0;
    putBytes(bytes, &cursor, "BM");
    putInt(u32, bytes, &cursor, bmpFileSize());
    putInt(u32, bytes, &cursor, 0);
    putInt(u32, bytes, &cursor, 54);
    putInt(u32, bytes, &cursor, 40);
    putInt(u32, bytes, &cursor, output_width);
    putInt(u32, bytes, &cursor, output_height);
    putInt(u16, bytes, &cursor, 1);
    putInt(u16, bytes, &cursor, 24);
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
        putBytes(bytes, &cursor, &line_buffer);
    }

    try Io.Dir.cwd().writeFile(io, .{
        .sub_path = output_path,
        .data = bytes,
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
