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
const render_draw_mesh_component_id = "machina.render.internal.draw.mesh";
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

const ObjectConfig = struct {
    width: u32,
    height: u32,
    mesh: *const runtime.RenderableMesh,
    camera: CameraState,
    light: DirectionalLightState,
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

    fn queueMeshDraws(self: *RenderEcsState) RenderError!void {
        const count = self.world.renderableMeshCount();
        for (0..count) |render_index| {
            if (render_index > std.math.maxInt(i32)) {
                return RenderError.InvalidScene;
            }
            const entity_id = std.fmt.allocPrint(self.allocator, "machina.render.draw.mesh.{d}", .{render_index}) catch return RenderError.OutOfMemory;
            defer self.allocator.free(entity_id);

            const entity = self.world.createEntity(entity_id, "Mesh Draw") catch |err| return mapWorldError(err);
            const fields = [_]runtime.ComponentFieldValue{
                .{ .name = "render_index", .value = .{ .int = @intCast(render_index) } },
            };
            self.world.setComponent(entity, render_draw_mesh_component_id, &fields) catch |err| return mapWorldError(err);
        }
    }

    fn drawCommandCount(self: RenderEcsState) usize {
        return self.world.componentInstanceCountFor(render_draw_mesh_component_id);
    }

    fn drawCommandRenderIndex(self: RenderEcsState, entity: runtime.EntityHandle) RenderError!usize {
        return renderIndexFromDrawEntity(&self.world, entity);
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

fn registerRenderEcsTypes(registry: *runtime.ComponentRegistry) !void {
    try runtime.registerEngineComponents(registry);

    const draw_mesh_fields = [_]runtime.ComponentFieldDefinition{
        .{ .name = "render_index", .value_type = .int },
    };
    try registry.registerEngineComponent(.{
        .id = render_draw_mesh_component_id,
        .version = 1,
        .fields = &draw_mesh_fields,
    });

    const extract_writes = [_][]const u8{
        runtime.transform_component_id,
        runtime.geometry_primitive_component_id,
        runtime.surface_material_component_id,
        runtime.camera_component_id,
        runtime.directional_light_component_id,
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
    };
    const queue_writes = [_][]const u8{render_draw_mesh_component_id};
    const after_prepare = [_][]const u8{render_prepare_meshes_system_id};
    try registry.registerEngineSystem(.{
        .id = render_queue_meshes_system_id,
        .phase = .render,
        .reads = &queue_reads,
        .writes = &queue_writes,
        .after = &after_prepare,
    });

    const draw_reads = [_][]const u8{
        render_draw_mesh_component_id,
        runtime.transform_component_id,
        runtime.geometry_primitive_component_id,
        runtime.surface_material_component_id,
        runtime.camera_component_id,
        runtime.directional_light_component_id,
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

fn renderIndexFromDrawEntity(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!usize {
    const value = world.getComponentFieldValue(entity, render_draw_mesh_component_id, "render_index") catch |err| return mapWorldError(err);
    const render_index = switch (value) {
        .int => |payload| payload,
        else => return RenderError.InvalidScene,
    };
    if (render_index < 0) {
        return RenderError.InvalidScene;
    }
    return @intCast(render_index);
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

const MeshDemo = struct {
    allocator: std.mem.Allocator,
    pipeline: *wgpu.RenderPipeline,
    bind_group_layout: *wgpu.BindGroupLayout,
    pipeline_layout: *wgpu.PipelineLayout,
    render_state: RenderEcsState,
    objects: []ObjectResources,

    fn create(
        allocator: std.mem.Allocator,
        device: *wgpu.Device,
        _: *wgpu.Queue,
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
        };
        const bind_group_layout = device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh bind group layout"),
            .entry_count = bind_group_layout_entries.len,
            .entries = &bind_group_layout_entries,
        }) orelse return RenderError.NoDevice;
        errdefer bind_group_layout.release();

        var render_state = try RenderEcsState.init(allocator);
        errdefer render_state.deinit();
        try render_state.extractScene(scene);

        const objects = allocator.alloc(ObjectResources, 0) catch return RenderError.OutOfMemory;
        errdefer allocator.free(objects);

        const bind_group_layouts = [_]*wgpu.BindGroupLayout{bind_group_layout};
        const pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh pipeline layout"),
            .bind_group_layout_count = bind_group_layouts.len,
            .bind_group_layouts = &bind_group_layouts,
        }) orelse return RenderError.NoDevice;
        errdefer pipeline_layout.release();

        const pipeline = try createMeshPipeline(device, texture_format, pipeline_layout);
        errdefer pipeline.release();

        return .{
            .allocator = allocator,
            .pipeline = pipeline,
            .bind_group_layout = bind_group_layout,
            .pipeline_layout = pipeline_layout,
            .render_state = render_state,
            .objects = objects,
        };
    }

    fn deinit(self: *MeshDemo) void {
        self.render_state.deinit();
        self.pipeline.release();
        self.pipeline_layout.release();
        self.bind_group_layout.release();
        for (self.objects) |*object| {
            object.deinit();
        }
        self.allocator.free(self.objects);
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
        for (self.render_state.schedule.batches) |batch| {
            for (batch.systems) |system| {
                if (std.mem.eql(u8, system.id, render_extract_system_id)) {
                    try self.render_state.extractScene(context.frame.scene);
                } else if (std.mem.eql(u8, system.id, render_prepare_meshes_system_id)) {
                    try self.ensureObjectResources(context.device, context.queue);
                } else if (std.mem.eql(u8, system.id, render_queue_meshes_system_id)) {
                    try self.render_state.queueMeshDraws();
                } else if (std.mem.eql(u8, system.id, render_draw_meshes_system_id)) {
                    try self.drawQueuedMeshes(context);
                } else {
                    return RenderError.InvalidScene;
                }
            }
        }
    }

    fn ensureObjectResources(self: *MeshDemo, device: *wgpu.Device, queue: *wgpu.Queue) RenderError!void {
        const mesh_count = self.render_state.world.renderableMeshCount();
        if (mesh_count == self.objects.len and self.objectResourcesMatchRenderWorld()) {
            return;
        }

        const new_objects = self.allocator.alloc(ObjectResources, mesh_count) catch return RenderError.OutOfMemory;
        var object_count: usize = 0;
        errdefer {
            for (new_objects[0..object_count]) |*object| {
                object.deinit();
            }
            self.allocator.free(new_objects);
        }

        var meshes = self.render_state.world.renderableMeshes();
        while (meshes.next()) |mesh| {
            new_objects[object_count] = try ObjectResources.create(self.allocator, device, queue, self.bind_group_layout, mesh);
            object_count += 1;
        }
        if (object_count != mesh_count) {
            return RenderError.InvalidScene;
        }

        for (self.objects) |*object| {
            object.deinit();
        }
        self.allocator.free(self.objects);
        self.objects = new_objects;
    }

    fn objectResourcesMatchRenderWorld(self: MeshDemo) bool {
        var index: usize = 0;
        var meshes = self.render_state.world.renderableMeshes();
        while (meshes.next()) |mesh| {
            if (index >= self.objects.len or !self.objects[index].matches(mesh)) {
                return false;
            }
            index += 1;
        }
        return index == self.objects.len;
    }

    fn drawQueuedMeshes(self: *MeshDemo, context: RenderSystemContext) RenderError!void {
        const camera = try cameraState(&self.render_state.world);
        const light = try directionalLightState(&self.render_state.world);
        var draw_indices: std.ArrayList(usize) = .empty;
        defer draw_indices.deinit(self.allocator);

        var draw_cursor: usize = 0;
        const draw_query = [_][]const u8{render_draw_mesh_component_id};
        while (self.render_state.world.queryNext(&draw_query, &draw_cursor)) |draw_entity| {
            const render_index = try self.render_state.drawCommandRenderIndex(draw_entity);
            if (render_index >= self.objects.len) {
                return RenderError.InvalidScene;
            }
            const mesh = self.render_state.world.renderableMeshAt(render_index) orelse return RenderError.InvalidScene;
            var uniforms = try frameUniforms(.{
                .width = context.frame.width,
                .height = context.frame.height,
                .mesh = &mesh,
                .camera = camera,
                .light = light,
            });
            writeUniforms(context.queue, self.objects[render_index].uniform_buffer, &uniforms);
            draw_indices.append(self.allocator, render_index) catch return RenderError.OutOfMemory;
        }

        const encoder = context.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh command encoder"),
        }) orelse return RenderError.NoDevice;
        defer encoder.release();

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
        for (draw_indices.items) |render_index| {
            const object = self.objects[render_index];
            render_pass.setVertexBuffer(0, object.vertex_buffer, 0, object.vertex_buffer_size);
            render_pass.setIndexBuffer(object.index_buffer, .uint16, 0, object.index_buffer_size);
            render_pass.setBindGroup(0, object.bind_group, 0, null);
            render_pass.drawIndexed(object.index_count, 1, 0, 0, 0);
        }
        render_pass.end();

        const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh command buffer"),
        }) orelse return RenderError.NoDevice;
        defer command_buffer.release();

        const command_buffers = [_]*const wgpu.CommandBuffer{command_buffer};
        context.queue.submit(&command_buffers);
    }
};

const ObjectResources = struct {
    geometry_key: GeometryKey,
    vertex_buffer: *wgpu.Buffer,
    index_buffer: *wgpu.Buffer,
    vertex_buffer_size: u64,
    index_buffer_size: u64,
    index_count: u32,
    uniform_buffer: *wgpu.Buffer,
    bind_group: *wgpu.BindGroup,

    fn create(
        allocator: std.mem.Allocator,
        device: *wgpu.Device,
        queue: *wgpu.Queue,
        bind_group_layout: *wgpu.BindGroupLayout,
        renderable: runtime.RenderableMesh,
    ) RenderError!ObjectResources {
        const geometry_key = GeometryKey.fromRenderable(renderable) orelse return RenderError.InvalidScene;
        var mesh = geometry.generatePrimitive(
            allocator,
            geometry_key.primitive,
            geometry_key.segments,
            geometry_key.rings,
        ) catch |err| return mapGeometryError(err);
        defer mesh.deinit(allocator);

        const vertex_bytes = std.mem.sliceAsBytes(mesh.vertices);
        const index_bytes = std.mem.sliceAsBytes(mesh.indices);
        const vertex_buffer = try createStaticBuffer(device, "Machina mesh vertex buffer", wgpu.BufferUsages.vertex, vertex_bytes);
        errdefer vertex_buffer.release();

        const index_buffer = try createStaticBuffer(device, "Machina mesh index buffer", wgpu.BufferUsages.index, index_bytes);
        errdefer index_buffer.release();

        const uniform_buffer = device.createBuffer(&wgpu.BufferDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh object uniforms"),
            .usage = wgpu.BufferUsages.uniform | wgpu.BufferUsages.copy_dst,
            .size = @sizeOf(FrameUniforms),
            .mapped_at_creation = @as(u32, @intFromBool(false)),
        }) orelse return RenderError.NoDevice;
        errdefer uniform_buffer.release();

        var initial_uniforms = try frameUniforms(.{
            .width = output_width,
            .height = output_height,
            .mesh = &renderable,
            .camera = .{},
            .light = .{},
        });
        writeUniforms(queue, uniform_buffer, &initial_uniforms);

        const bind_group_entries = [_]wgpu.BindGroupEntry{
            .{
                .binding = 0,
                .buffer = uniform_buffer,
                .size = @sizeOf(FrameUniforms),
            },
        };
        const bind_group = device.createBindGroup(&wgpu.BindGroupDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh object bind group"),
            .layout = bind_group_layout,
            .entry_count = bind_group_entries.len,
            .entries = &bind_group_entries,
        }) orelse return RenderError.NoDevice;

        return .{
            .geometry_key = geometry_key,
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .vertex_buffer_size = @intCast(vertex_bytes.len),
            .index_buffer_size = @intCast(index_bytes.len),
            .index_count = @intCast(mesh.indices.len),
            .uniform_buffer = uniform_buffer,
            .bind_group = bind_group,
        };
    }

    fn matches(self: ObjectResources, renderable: runtime.RenderableMesh) bool {
        const geometry_key = GeometryKey.fromRenderable(renderable) orelse return false;
        return self.geometry_key.eql(geometry_key);
    }

    fn deinit(self: *ObjectResources) void {
        self.bind_group.release();
        self.uniform_buffer.release();
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
    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .array_stride = @sizeOf(geometry.Vertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
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
            .cull_mode = .back,
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

fn frameUniforms(config: ObjectConfig) RenderError!FrameUniforms {
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
    const light = try validateDirectionalLight(config.light);
    const view = cameraViewMatrix(camera.transform);
    const projection = perspective(std.math.degreesToRadians(camera.fov_y_degrees), aspect, camera.near, camera.far);
    const mvp = matMul(projection, matMul(view, model));
    const normalized_light = normalizeVec3(light.direction);

    return .{
        .mvp = mvp,
        .model = model,
        .light_dir = .{ normalized_light[0], normalized_light[1], normalized_light[2], 0.0 },
        .light_color = .{ light.color[0], light.color[1], light.color[2], 1.0 },
        .object_color = .{ mesh.base_color[0], mesh.base_color[1], mesh.base_color[2], 1.0 },
        .lighting = .{ light.ambient, light.intensity, 0.0, 0.0 },
    };
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

fn isFiniteVec3(value: [3]f32) bool {
    return std.math.isFinite(value[0]) and std.math.isFinite(value[1]) and std.math.isFinite(value[2]);
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

    try state.queueMeshDraws();
    try std.testing.expectEqual(@as(usize, 2), state.drawCommandCount());

    var cursor: usize = 0;
    const draw_query = [_][]const u8{render_draw_mesh_component_id};
    const first_draw = state.world.queryNext(&draw_query, &cursor) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 0), try state.drawCommandRenderIndex(first_draw));
    const second_draw = state.world.queryNext(&draw_query, &cursor) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), try state.drawCommandRenderIndex(second_draw));
    try std.testing.expect(state.world.queryNext(&draw_query, &cursor) == null);
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
    mvp: [16]f32,
    model: [16]f32,
    light_dir: [4]f32,
    light_color: [4]f32,
    object_color: [4]f32,
    lighting: [4]f32,
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
