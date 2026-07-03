const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const geometry = @import("geometry.zig");
const runtime = @import("runtime.zig");
const ui_font = @import("ui_font.zig");
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
const render_ui_button_state_component_id = "machina.render.internal.ui.button_state";
const render_draw_batch_component_id = "machina.render.internal.draw.batch";
const render_draw_ui_component_id = "machina.render.internal.draw.ui";
const render_extract_system_id = "machina.render.extract";
const render_prepare_meshes_system_id = "machina.render.prepare_meshes";
const render_queue_meshes_system_id = "machina.render.queue_meshes";
const render_interact_ui_system_id = "machina.render.interact_ui";
const render_prepare_ui_system_id = "machina.render.prepare_ui";
const render_queue_ui_system_id = "machina.render.queue_ui";
const render_draw_meshes_system_id = "machina.render.draw_meshes";
const default_window_width = 1280;
const default_window_height = 720;
const editor_performance_display_interval_ns: u64 = 333_000_000;
const editor_system_profile_max_rows = 7;
const editor_system_profile_id_chars = 15;
const editor_system_panel_width: f32 = 650.0;
const editor_debug_fps_size: f32 = 1.6;
const editor_system_text_size: f32 = 1.0;
const editor_system_header_y: f32 = 104.0;
const editor_system_first_row_y: f32 = 136.0;
const editor_system_row_stride: f32 = 32.0;
const render_system_profile_window_frames: usize = 120;
const editor_controls_panel_width: f32 = 360.0;
const editor_controls_panel_height: f32 = 102.0;
const editor_controls_panel_x: f32 = 12.0;
const editor_controls_panel_y: f32 = 12.0;
const editor_control_button_y: f32 = 58.0;
const editor_play_button_x: f32 = 28.0;
const editor_step_button_x: f32 = 148.0;
const editor_control_button_width: f32 = 104.0;
const editor_control_button_height: f32 = 36.0;
const editor_inspector_panel_width: f32 = 430.0;
const editor_inspector_panel_height: f32 = 548.0;
const editor_inspector_empty_panel_height: f32 = 178.0;
const editor_inspector_panel_margin: f32 = 12.0;
const editor_inspector_text_size: f32 = 1.0;
const editor_inspector_line_stride: f32 = 28.0;
const editor_inspector_max_lines: usize = 18;
const editor_gizmo_axis_length: f32 = 1.25;
const editor_gizmo_axis_thickness: f32 = 0.035;
const editor_gizmo_pick_radius_px: f32 = 18.0;

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

pub const Stats = struct {
    renderables: usize,
    render_batches: usize,
    ui_rects: usize,
    ui_texts: usize,
};

pub const WindowOptions = struct {
    max_frames: ?u32 = null,
    editor: bool = false,
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
    step: *const fn (context: *anyopaque, delta_seconds: f32, input: *FrameInput) void,
};

pub const PointerInput = struct {
    position: [2]f32 = .{ 0.0, 0.0 },
    has_position: bool = false,
    primary_down: bool = false,
    primary_pressed: bool = false,
    primary_released: bool = false,
    wheel_delta: [2]f32 = .{ 0.0, 0.0 },

    fn beginFrame(self: *PointerInput) void {
        self.primary_pressed = false;
        self.primary_released = false;
        self.wheel_delta = .{ 0.0, 0.0 };
    }
};

pub const KeyboardInput = struct {
    ctrl_down: bool = false,
    shift_down: bool = false,
    alt_down: bool = false,
    super_down: bool = false,
    editor_toggle_pressed: bool = false,

    fn beginFrame(self: *KeyboardInput) void {
        self.editor_toggle_pressed = false;
    }
};

pub const EditorAxis = enum {
    none,
    x,
    y,
    z,
};

pub const EditorState = struct {
    paused: bool = false,
    selected_entity: ?runtime.EntityHandle = null,
    dragging_axis: EditorAxis = .none,
    captured_pointer: bool = false,
    system_scroll_offset: usize = 0,
    last_pointer: [2]f32 = .{ 0.0, 0.0 },
    has_last_pointer: bool = false,
};

pub const EditorFrameState = struct {
    paused: bool = false,
    selected_entity: ?runtime.EntityHandle = null,
    dragging_axis: EditorAxis = .none,
    system_scroll_offset: usize = 0,
    entity_count: usize = 0,
    component_instance_count: usize = 0,
    renderable_count: usize = 0,
};

pub const EditorUpdate = struct {
    consumed_pointer: bool = false,
    step_once: bool = false,
};

pub const EditorError = runtime.WorldError || error{InvalidScene};

pub const FrameInput = struct {
    pointer: PointerInput = .{},
    keyboard: KeyboardInput = .{},
    ui_visible: bool = true,
    debug_overlay_visible: bool = false,
    fps: f32 = 0.0,
    viewport_width: f32 = 0.0,
    viewport_height: f32 = 0.0,
    editor: EditorFrameState = .{},
    system_profiles: []const runtime.SystemProfileSnapshot = &.{},

    fn beginFrame(self: *FrameInput) void {
        self.pointer.beginFrame();
        self.keyboard.beginFrame();
    }
};

fn toggleDebugOverlay(input: *FrameInput) void {
    input.debug_overlay_visible = !input.debug_overlay_visible;
    input.keyboard.editor_toggle_pressed = true;
}

fn isEditorToggleShortcut(key: sdl.SDL_Keycode, modifiers: sdl.SDL_Keymod) bool {
    return key == sdl.SDLK_TAB and (modifiers & sdl.SDL_KMOD_CTRL) != 0;
}

fn updateKeyboardModifiers(keyboard: *KeyboardInput, modifiers: sdl.SDL_Keymod) void {
    keyboard.ctrl_down = (modifiers & sdl.SDL_KMOD_CTRL) != 0;
    keyboard.shift_down = (modifiers & sdl.SDL_KMOD_SHIFT) != 0;
    keyboard.alt_down = (modifiers & sdl.SDL_KMOD_ALT) != 0;
    keyboard.super_down = (modifiers & sdl.SDL_KMOD_GUI) != 0;
}

pub fn editorFrameState(world: *const runtime.World, state: EditorState) EditorFrameState {
    return .{
        .paused = state.paused,
        .selected_entity = validatedEditorSelection(world, state.selected_entity),
        .dragging_axis = state.dragging_axis,
        .system_scroll_offset = state.system_scroll_offset,
        .entity_count = world.entityCount(),
        .component_instance_count = world.componentInstanceCount(),
        .renderable_count = world.renderableMeshCount(),
    };
}

fn clampEditorSystemScroll(state: *EditorState, profile_count: usize) void {
    state.system_scroll_offset = @min(state.system_scroll_offset, editorSystemMaxScroll(profile_count));
}

fn scrollEditorSystemList(state: *EditorState, profile_count: usize, scroll_delta_y: f32) void {
    const max_scroll = editorSystemMaxScroll(profile_count);
    if (max_scroll == 0) {
        state.system_scroll_offset = 0;
        return;
    }

    const rows = @max(@as(usize, 1), @as(usize, @intFromFloat(@ceil(@abs(scroll_delta_y)))));
    if (scroll_delta_y < 0.0) {
        state.system_scroll_offset = @min(max_scroll, state.system_scroll_offset + rows);
    } else {
        state.system_scroll_offset = if (rows > state.system_scroll_offset) 0 else state.system_scroll_offset - rows;
    }
}

pub fn updateEditorState(world: *runtime.World, state: *EditorState, input: FrameInput) EditorError!EditorUpdate {
    state.selected_entity = validatedEditorSelection(world, state.selected_entity);
    if (!input.debug_overlay_visible) {
        state.dragging_axis = .none;
        state.captured_pointer = false;
        state.has_last_pointer = false;
        return .{};
    }
    clampEditorSystemScroll(state, input.system_profiles.len);

    if (input.pointer.wheel_delta[1] != 0.0 and (!input.pointer.has_position or hitEditorSystemPanel(input))) {
        scrollEditorSystemList(state, input.system_profiles.len, input.pointer.wheel_delta[1]);
        return .{ .consumed_pointer = true };
    }

    if (!input.pointer.has_position) {
        state.dragging_axis = .none;
        state.has_last_pointer = false;
        return .{};
    }

    const release_consumes = input.pointer.primary_released and
        (state.captured_pointer or state.dragging_axis != .none or hitEditorChrome(input));
    if (input.pointer.primary_released) {
        state.dragging_axis = .none;
        state.captured_pointer = false;
        state.has_last_pointer = false;
    }

    if (input.pointer.primary_pressed) {
        if (hitEditorPlayButton(input.pointer.position)) {
            state.paused = !state.paused;
            state.captured_pointer = true;
            return .{ .consumed_pointer = true };
        }
        if (hitEditorStepButton(input.pointer.position)) {
            state.paused = true;
            state.captured_pointer = true;
            return .{ .consumed_pointer = true, .step_once = true };
        }
        if (hitEditorChrome(input)) {
            state.captured_pointer = true;
            return .{ .consumed_pointer = true };
        }

        if (state.selected_entity) |selected| {
            const axis = try pickEditorGizmoAxis(world, selected, input);
            if (axis != .none) {
                state.dragging_axis = axis;
                state.captured_pointer = true;
                state.last_pointer = input.pointer.position;
                state.has_last_pointer = true;
                return .{ .consumed_pointer = true };
            }
        }

        state.selected_entity = try pickRenderableEntity(world, input);
        state.captured_pointer = state.selected_entity != null;
        return .{ .consumed_pointer = state.selected_entity != null };
    }

    if (input.pointer.primary_down and state.dragging_axis != .none) {
        try dragSelectedEntity(world, state, input);
        return .{ .consumed_pointer = true };
    }

    if (release_consumes) {
        return .{ .consumed_pointer = true };
    }

    state.has_last_pointer = false;
    return .{};
}

pub fn stats(allocator: std.mem.Allocator, scene: Scene) RenderError!Stats {
    var state = try RenderEcsState.init(allocator);
    defer state.deinit();

    try state.extractScene(scene);
    var plan = try BatchPlan.build(allocator, &state.world);
    defer plan.deinit();

    return .{
        .renderables = state.world.renderableMeshCount(),
        .render_batches = plan.batches.len,
        .ui_rects = state.world.uiRectCount(),
        .ui_texts = state.world.uiTextCount(),
    };
}

const UiButtonState = struct {
    hovered: bool = false,
    held: bool = false,
    pressed: bool = false,
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
    const window = sdl.SDL_CreateWindow(title_z.ptr, default_window_width, default_window_height, window_flags) orelse return RenderError.WindowCreateFailed;
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
    var input: FrameInput = .{ .debug_overlay_visible = options.editor };
    var last_frame_ticks = sdl.SDL_GetTicksNS();
    var last_performance_display_ticks: u64 = 0;
    var smoothed_fps: f32 = 0.0;
    var displayed_fps: f32 = 0.0;
    while (running) {
        input.beginFrame();

        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event)) {
            switch (event.type) {
                sdl.SDL_EVENT_QUIT => running = false,
                sdl.SDL_EVENT_KEY_DOWN => {
                    updateKeyboardModifiers(&input.keyboard, event.key.mod);
                    if (!event.key.repeat and isEditorToggleShortcut(event.key.key, event.key.mod)) {
                        toggleDebugOverlay(&input);
                    }
                },
                sdl.SDL_EVENT_KEY_UP => {
                    updateKeyboardModifiers(&input.keyboard, event.key.mod);
                },
                sdl.SDL_EVENT_MOUSE_MOTION => {
                    updatePointerFromWindow(&input.pointer, window, event.motion.x, event.motion.y);
                },
                sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    updatePointerFromWindow(&input.pointer, window, event.button.x, event.button.y);
                    if (event.button.button == sdl.SDL_BUTTON_LEFT) {
                        input.pointer.primary_down = true;
                        input.pointer.primary_pressed = true;
                    }
                },
                sdl.SDL_EVENT_MOUSE_BUTTON_UP => {
                    updatePointerFromWindow(&input.pointer, window, event.button.x, event.button.y);
                    if (event.button.button == sdl.SDL_BUTTON_LEFT) {
                        input.pointer.primary_down = false;
                        input.pointer.primary_released = true;
                    }
                },
                sdl.SDL_EVENT_MOUSE_WHEEL => {
                    updatePointerFromWindow(&input.pointer, window, event.wheel.mouse_x, event.wheel.mouse_y);
                    input.pointer.wheel_delta[0] += event.wheel.x;
                    input.pointer.wheel_delta[1] += event.wheel.y;
                },
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

        const frame_ticks = sdl.SDL_GetTicksNS();
        if (frame_ticks > last_frame_ticks) {
            const elapsed_ns = frame_ticks - last_frame_ticks;
            last_frame_ticks = frame_ticks;
            const instant_fps = 1_000_000_000.0 / @as(f32, @floatFromInt(elapsed_ns));
            smoothed_fps = if (smoothed_fps == 0.0) instant_fps else smoothed_fps * 0.9 + instant_fps * 0.1;
            if (displayed_fps == 0.0 or frame_ticks - last_performance_display_ticks >= editor_performance_display_interval_ns) {
                displayed_fps = smoothed_fps;
                last_performance_display_ticks = frame_ticks;
            }
            input.fps = displayed_fps;
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
        input.viewport_width = @floatFromInt(width);
        input.viewport_height = @floatFromInt(height);
        if (options.frame_update) |frame_update| {
            frame_update.step(frame_update.context, delta_seconds, &input);
        }

        try configureSurfaceFromWindow(surface, gpu.device, window, surface_format, &width, &height);
        try depth.ensure(gpu.device, width, height);
        try drawMeshToSurface(surface, gpu.device, gpu.queue, &demo, depth.view orelse return RenderError.NoDevice, .{
            .width = width,
            .height = height,
            .scene = scene,
            .input = input,
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
    input: FrameInput = .{},
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

const RenderSystemProfileState = struct {
    id: []const u8,
    phase: runtime.SystemPhase,
    samples_ns: [render_system_profile_window_frames]u64 = [_]u64{0} ** render_system_profile_window_frames,
    sample_count: usize = 0,
    next_sample: usize = 0,
    total_ns: u64 = 0,
    last_ns: u64 = 0,

    fn deinit(self: *RenderSystemProfileState, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        self.* = undefined;
    }

    fn record(self: *RenderSystemProfileState, duration_ns: u64) void {
        if (self.sample_count < render_system_profile_window_frames) {
            self.samples_ns[self.next_sample] = duration_ns;
            self.sample_count += 1;
            self.total_ns += duration_ns;
        } else {
            self.total_ns -= self.samples_ns[self.next_sample];
            self.samples_ns[self.next_sample] = duration_ns;
            self.total_ns += duration_ns;
        }

        self.next_sample = (self.next_sample + 1) % render_system_profile_window_frames;
        self.last_ns = duration_ns;
    }

    fn snapshot(self: RenderSystemProfileState) runtime.SystemProfileSnapshot {
        const average_ns = if (self.sample_count == 0) 0 else self.total_ns / self.sample_count;
        return .{
            .id = self.id,
            .phase = self.phase,
            .sample_count = @intCast(self.sample_count),
            .window_size = @intCast(render_system_profile_window_frames),
            .last_ns = self.last_ns,
            .rolling_average_ns = average_ns,
        };
    }
};

const RenderEcsState = struct {
    allocator: std.mem.Allocator,
    registry: runtime.ComponentRegistry,
    schedule: runtime.SystemSchedule,
    world: runtime.World,
    system_profiles: std.ArrayList(RenderSystemProfileState) = .empty,
    system_profile_snapshots: std.ArrayList(runtime.SystemProfileSnapshot) = .empty,
    combined_system_profile_snapshots: std.ArrayList(runtime.SystemProfileSnapshot) = .empty,
    display_system_profile_snapshots: std.ArrayList(runtime.SystemProfileSnapshot) = .empty,
    display_system_profile_ids: std.ArrayList([]u8) = .empty,
    last_display_system_profile_update_ns: i128 = 0,

    fn init(allocator: std.mem.Allocator) RenderError!RenderEcsState {
        var registry = runtime.ComponentRegistry.init(allocator);
        errdefer registry.deinit();

        registerRenderEcsTypes(&registry) catch |err| return mapEngineSetupError(err);

        var schedule = registry.buildSchedule(allocator, .render) catch |err| return mapEngineSetupError(err);
        errdefer schedule.deinit();

        var state = RenderEcsState{
            .allocator = allocator,
            .registry = registry,
            .schedule = schedule,
            .world = runtime.World.init(allocator),
        };
        errdefer state.deinit();
        try state.initializeSystemProfiles();
        return state;
    }

    fn deinit(self: *RenderEcsState) void {
        self.clearDisplaySystemProfileSnapshots();
        self.display_system_profile_ids.deinit(self.allocator);
        self.display_system_profile_snapshots.deinit(self.allocator);
        self.combined_system_profile_snapshots.deinit(self.allocator);
        self.system_profile_snapshots.deinit(self.allocator);
        self.clearSystemProfiles();
        self.system_profiles.deinit(self.allocator);
        self.world.deinit();
        self.schedule.deinit();
        self.registry.deinit();
        self.* = undefined;
    }

    fn systemProfileSnapshots(self: *RenderEcsState) []const runtime.SystemProfileSnapshot {
        self.system_profile_snapshots.clearRetainingCapacity();
        for (self.system_profiles.items) |profile| {
            self.system_profile_snapshots.appendAssumeCapacity(profile.snapshot());
        }
        return self.system_profile_snapshots.items;
    }

    fn combineSystemProfileSnapshots(
        self: *RenderEcsState,
        project_profiles: []const runtime.SystemProfileSnapshot,
    ) RenderError![]const runtime.SystemProfileSnapshot {
        const now_ns = monotonicTimestampNs();
        if (self.display_system_profile_snapshots.items.len > 0 and
            now_ns - self.last_display_system_profile_update_ns < @as(i128, editor_performance_display_interval_ns))
        {
            return self.display_system_profile_snapshots.items;
        }

        const render_profiles = self.systemProfileSnapshots();
        try self.refreshDisplaySystemProfileSnapshots(project_profiles, render_profiles);
        self.last_display_system_profile_update_ns = now_ns;
        return self.display_system_profile_snapshots.items;
    }

    fn refreshDisplaySystemProfileSnapshots(
        self: *RenderEcsState,
        project_profiles: []const runtime.SystemProfileSnapshot,
        render_profiles: []const runtime.SystemProfileSnapshot,
    ) RenderError!void {
        self.clearDisplaySystemProfileSnapshots();
        self.display_system_profile_snapshots.ensureTotalCapacity(self.allocator, project_profiles.len + render_profiles.len) catch return RenderError.OutOfMemory;
        self.display_system_profile_ids.ensureTotalCapacity(self.allocator, project_profiles.len + render_profiles.len) catch return RenderError.OutOfMemory;
        self.combined_system_profile_snapshots.clearRetainingCapacity();
        self.combined_system_profile_snapshots.ensureTotalCapacity(self.allocator, project_profiles.len + render_profiles.len) catch return RenderError.OutOfMemory;

        for (project_profiles) |profile| {
            try self.appendDisplaySystemProfileSnapshot(profile);
        }
        for (render_profiles) |profile| {
            try self.appendDisplaySystemProfileSnapshot(profile);
        }
    }

    fn appendDisplaySystemProfileSnapshot(self: *RenderEcsState, profile: runtime.SystemProfileSnapshot) RenderError!void {
        const owned_id = self.allocator.dupe(u8, profile.id) catch return RenderError.OutOfMemory;
        errdefer self.allocator.free(owned_id);
        self.display_system_profile_ids.appendAssumeCapacity(owned_id);
        const copied = runtime.SystemProfileSnapshot{
            .id = owned_id,
            .phase = profile.phase,
            .sample_count = profile.sample_count,
            .window_size = profile.window_size,
            .last_ns = profile.last_ns,
            .rolling_average_ns = profile.rolling_average_ns,
        };
        self.display_system_profile_snapshots.appendAssumeCapacity(copied);
        self.combined_system_profile_snapshots.appendAssumeCapacity(copied);
    }

    fn clearDisplaySystemProfileSnapshots(self: *RenderEcsState) void {
        for (self.display_system_profile_ids.items) |id| {
            self.allocator.free(id);
        }
        self.display_system_profile_ids.clearRetainingCapacity();
        self.display_system_profile_snapshots.clearRetainingCapacity();
        self.combined_system_profile_snapshots.clearRetainingCapacity();
    }

    fn initializeSystemProfiles(self: *RenderEcsState) RenderError!void {
        self.clearSystemProfiles();
        self.system_profile_snapshots.clearRetainingCapacity();
        self.combined_system_profile_snapshots.clearRetainingCapacity();
        self.clearDisplaySystemProfileSnapshots();
        self.last_display_system_profile_update_ns = 0;

        const system_count = self.schedule.systemCount();
        self.system_profiles.ensureTotalCapacity(self.allocator, system_count) catch return RenderError.OutOfMemory;
        self.system_profile_snapshots.ensureTotalCapacity(self.allocator, system_count) catch return RenderError.OutOfMemory;

        for (self.schedule.batches) |batch| {
            for (batch.systems) |system| {
                const owned_id = self.allocator.dupe(u8, system.id) catch return RenderError.OutOfMemory;
                self.system_profiles.appendAssumeCapacity(.{
                    .id = owned_id,
                    .phase = batch.phase,
                });
            }
        }
    }

    fn clearSystemProfiles(self: *RenderEcsState) void {
        for (self.system_profiles.items) |*profile| {
            profile.deinit(self.allocator);
        }
        self.system_profiles.clearRetainingCapacity();
    }

    fn recordSystemDuration(self: *RenderEcsState, system: runtime.ScheduledSystem, phase: runtime.SystemPhase, duration_ns: u64) void {
        for (self.system_profiles.items) |*profile| {
            if (profile.phase == phase and std.mem.eql(u8, profile.id, system.id)) {
                profile.record(duration_ns);
                return;
            }
        }
    }

    fn extractScene(self: *RenderEcsState, scene: Scene) RenderError!void {
        try self.extractSceneWithInput(scene, .{});
    }

    fn extractSceneWithInput(self: *RenderEcsState, scene: Scene, input: FrameInput) RenderError!void {
        var next_world = runtime.World.init(self.allocator);
        errdefer next_world.deinit();

        try setRenderFrameInput(&next_world, input);

        var mesh_index: usize = 0;
        var meshes = scene.world.renderableMeshes();
        while (meshes.next()) |mesh| {
            try extractMeshInto(self.allocator, &next_world, mesh_index, mesh);
            mesh_index += 1;
        }

        if (input.debug_overlay_visible) {
            try extractEditorGizmoInto(self.allocator, &next_world, scene.world, input);
        }

        if (input.ui_visible) {
            var ui_canvas_index: usize = 0;
            var ui_canvas_cursor: usize = 0;
            const ui_canvas_query = [_][]const u8{runtime.ui_canvas_component_id};
            while (scene.world.queryNext(&ui_canvas_query, &ui_canvas_cursor)) |canvas| {
                const stored_canvas = scene.world.entity(canvas) catch return RenderError.InvalidScene;
                try extractUiCanvasInto(self.allocator, &next_world, ui_canvas_index, stored_canvas.name);
                ui_canvas_index += 1;
            }

            var ui_rect_index: usize = 0;
            var ui_rects = scene.world.uiRects();
            while (ui_rects.next()) |rect| {
                try extractUiRectInto(self.allocator, &next_world, ui_rect_index, rect);
                ui_rect_index += 1;
            }

            var ui_text_index: usize = 0;
            var ui_texts = scene.world.uiTexts();
            while (ui_texts.next()) |text| {
                try extractUiTextInto(self.allocator, &next_world, ui_text_index, text);
                ui_text_index += 1;
            }
        }

        if (input.debug_overlay_visible) {
            try extractDebugOverlayInto(self.allocator, &next_world, input, scene.world);
        }

        try extractCameraInto(&next_world, try cameraState(scene.world));
        try extractDirectionalLightInto(&next_world, try directionalLightState(scene.world));

        self.world.deinit();
        self.world = next_world;
    }

    fn updateUiInteractions(self: *RenderEcsState) RenderError!void {
        const input = try renderFrameInput(&self.world);
        if (!input.ui_visible) {
            return;
        }

        var cursor: usize = 0;
        const button_query = [_][]const u8{
            runtime.ui_rect_component_id,
            runtime.ui_button_component_id,
        };
        while (self.world.queryNext(&button_query, &cursor)) |entity| {
            const position = self.world.getVec3(entity, runtime.ui_rect_component_id, "position") catch |err| return mapWorldError(err);
            const size = self.world.getVec3(entity, runtime.ui_rect_component_id, "size") catch |err| return mapWorldError(err);
            const state = evaluateUiButtonState(input, position, size);
            try setRenderUiButtonState(&self.world, entity, state);
        }
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

    fn queueUiDraw(self: *RenderEcsState) RenderError!void {
        if (self.world.uiRectCount() == 0 and self.world.uiTextCount() == 0) {
            return;
        }
        const entity = self.world.createEntity("machina.render.draw.ui", "UI Draw") catch |err| return mapWorldError(err);
        self.world.setComponent(entity, render_draw_ui_component_id, &.{}) catch |err| return mapWorldError(err);
    }

    fn drawCommandCount(self: RenderEcsState) usize {
        return self.world.componentInstanceCountFor(render_draw_batch_component_id);
    }

    fn uiDrawCommandCount(self: RenderEcsState) usize {
        return self.world.componentInstanceCountFor(render_draw_ui_component_id);
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

    const ui_button_state_fields = [_]runtime.ComponentFieldDefinition{
        .{ .name = "hovered", .value_type = .boolean },
        .{ .name = "held", .value_type = .boolean },
        .{ .name = "pressed", .value_type = .boolean },
    };
    try registry.registerEngineComponent(.{
        .id = render_ui_button_state_component_id,
        .version = 1,
        .fields = &ui_button_state_fields,
    });
    const draw_batch_fields = [_]runtime.ComponentFieldDefinition{
        .{ .name = "batch_index", .value_type = .int },
    };
    try registry.registerEngineComponent(.{
        .id = render_draw_batch_component_id,
        .version = 1,
        .fields = &draw_batch_fields,
    });
    try registry.registerEngineComponent(.{
        .id = render_draw_ui_component_id,
        .version = 1,
    });

    const extract_writes = [_][]const u8{
        runtime.transform_component_id,
        runtime.geometry_primitive_component_id,
        runtime.surface_material_component_id,
        runtime.camera_component_id,
        runtime.directional_light_component_id,
        runtime.shadow_caster_component_id,
        runtime.shadow_receiver_component_id,
        runtime.ui_canvas_component_id,
        runtime.ui_rect_component_id,
        runtime.ui_text_component_id,
        runtime.ui_button_component_id,
        runtime.input_pointer_component_id,
        runtime.input_keyboard_component_id,
        runtime.input_frame_component_id,
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

    const interact_ui_reads = [_][]const u8{
        runtime.input_pointer_component_id,
        runtime.input_frame_component_id,
        runtime.ui_rect_component_id,
        runtime.ui_button_component_id,
    };
    const interact_ui_writes = [_][]const u8{render_ui_button_state_component_id};
    try registry.registerEngineSystem(.{
        .id = render_interact_ui_system_id,
        .phase = .render,
        .reads = &interact_ui_reads,
        .writes = &interact_ui_writes,
        .after = &after_extract,
    });

    const prepare_ui_reads = [_][]const u8{
        runtime.ui_rect_component_id,
        runtime.ui_text_component_id,
        runtime.ui_button_component_id,
        render_ui_button_state_component_id,
    };
    const after_queue_meshes = [_][]const u8{ render_queue_meshes_system_id, render_interact_ui_system_id };
    try registry.registerEngineSystem(.{
        .id = render_prepare_ui_system_id,
        .phase = .render,
        .reads = &prepare_ui_reads,
        .after = &after_queue_meshes,
    });

    const queue_ui_reads = [_][]const u8{
        runtime.ui_rect_component_id,
        runtime.ui_text_component_id,
    };
    const queue_ui_writes = [_][]const u8{render_draw_ui_component_id};
    const after_prepare_ui = [_][]const u8{render_prepare_ui_system_id};
    try registry.registerEngineSystem(.{
        .id = render_queue_ui_system_id,
        .phase = .render,
        .reads = &queue_ui_reads,
        .writes = &queue_ui_writes,
        .after = &after_prepare_ui,
    });

    const draw_reads = [_][]const u8{
        render_draw_batch_component_id,
        render_draw_ui_component_id,
        runtime.transform_component_id,
        runtime.geometry_primitive_component_id,
        runtime.surface_material_component_id,
        runtime.camera_component_id,
        runtime.directional_light_component_id,
        runtime.shadow_caster_component_id,
        runtime.shadow_receiver_component_id,
        runtime.ui_rect_component_id,
        runtime.ui_text_component_id,
        runtime.ui_button_component_id,
        runtime.input_pointer_component_id,
        runtime.input_keyboard_component_id,
        runtime.input_frame_component_id,
        render_ui_button_state_component_id,
    };
    const after_queue = [_][]const u8{render_queue_ui_system_id};
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

fn extractEditorGizmoInto(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    scene_world: *const runtime.World,
    input: FrameInput,
) RenderError!void {
    const selected = input.editor.selected_entity orelse return;
    const selected_transform = (scene_world.getTransform(selected) catch return RenderError.InvalidScene) orelse return;
    const axes = [_]struct {
        id: []const u8,
        axis: EditorAxis,
        position_offset: [3]f32,
        scale: [3]f32,
        color: [3]f32,
        active_color: [3]f32,
    }{
        .{
            .id = "x",
            .axis = .x,
            .position_offset = .{ editor_gizmo_axis_length * 0.5, 0.0, 0.0 },
            .scale = .{ editor_gizmo_axis_length, editor_gizmo_axis_thickness, editor_gizmo_axis_thickness },
            .color = .{ 0.94, 0.267, 0.267 },
            .active_color = .{ 1.0, 0.455, 0.455 },
        },
        .{
            .id = "y",
            .axis = .y,
            .position_offset = .{ 0.0, editor_gizmo_axis_length * 0.5, 0.0 },
            .scale = .{ editor_gizmo_axis_thickness, editor_gizmo_axis_length, editor_gizmo_axis_thickness },
            .color = .{ 0.133, 0.773, 0.369 },
            .active_color = .{ 0.455, 0.914, 0.573 },
        },
        .{
            .id = "z",
            .axis = .z,
            .position_offset = .{ 0.0, 0.0, editor_gizmo_axis_length * 0.5 },
            .scale = .{ editor_gizmo_axis_thickness, editor_gizmo_axis_thickness, editor_gizmo_axis_length },
            .color = .{ 0.231, 0.51, 0.965 },
            .active_color = .{ 0.576, 0.773, 0.992 },
        },
    };

    for (axes) |entry| {
        const entity_id = std.fmt.allocPrint(allocator, "machina.editor.gizmo.{s}", .{entry.id}) catch return RenderError.OutOfMemory;
        defer allocator.free(entity_id);
        const entity = world.createEntity(entity_id, "Editor Translate Gizmo") catch |err| return mapWorldError(err);
        world.setTransform(entity, .{
            .position = addVec3(selected_transform.position, entry.position_offset),
            .scale = entry.scale,
        }) catch |err| return mapWorldError(err);
        world.setGeometryPrimitive(entity, .{
            .primitive = "box",
            .segments = 0,
            .rings = 0,
        }) catch |err| return mapWorldError(err);
        world.setSurfaceMaterial(entity, .{
            .base_color = if (input.editor.dragging_axis == entry.axis) entry.active_color else entry.color,
        }) catch |err| return mapWorldError(err);
    }
}

fn extractUiCanvasInto(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    ui_index: usize,
    name: []const u8,
) RenderError!void {
    const entity_id = std.fmt.allocPrint(allocator, "machina.render.extract.ui.canvas.{d}", .{ui_index}) catch return RenderError.OutOfMemory;
    defer allocator.free(entity_id);

    const entity = world.createEntity(entity_id, name) catch |err| return mapWorldError(err);
    world.setUiCanvas(entity) catch |err| return mapWorldError(err);
}

fn extractUiRectInto(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    ui_index: usize,
    rect: runtime.UiRect,
) RenderError!void {
    const entity_id = std.fmt.allocPrint(allocator, "machina.render.extract.ui.rect.{d}", .{ui_index}) catch return RenderError.OutOfMemory;
    defer allocator.free(entity_id);

    const entity = world.createEntity(entity_id, rect.name) catch |err| return mapWorldError(err);
    world.setUiRect(entity, .{
        .position = rect.position,
        .size = rect.size,
        .color = rect.color,
    }) catch |err| return mapWorldError(err);
    if (rect.is_button) {
        world.setUiButton(entity) catch |err| return mapWorldError(err);
    }
}

fn extractUiTextInto(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    ui_index: usize,
    text: runtime.UiText,
) RenderError!void {
    const entity_id = std.fmt.allocPrint(allocator, "machina.render.extract.ui.text.{d}", .{ui_index}) catch return RenderError.OutOfMemory;
    defer allocator.free(entity_id);

    const entity = world.createEntity(entity_id, text.name) catch |err| return mapWorldError(err);
    world.setUiText(entity, .{
        .position = text.position,
        .size = text.size,
        .color = text.color,
        .value = text.value,
    }) catch |err| return mapWorldError(err);
}

const EditorVBox = struct {
    allocator: std.mem.Allocator,
    world: *runtime.World,
    id_prefix: []const u8,
    x: f32,
    y: f32,
    row_stride: f32,
    row: usize = 0,

    fn init(
        allocator: std.mem.Allocator,
        world: *runtime.World,
        id_prefix: []const u8,
        x: f32,
        y: f32,
        row_stride: f32,
    ) EditorVBox {
        return .{
            .allocator = allocator,
            .world = world,
            .id_prefix = id_prefix,
            .x = x,
            .y = y,
            .row_stride = row_stride,
        };
    }

    fn text(self: *EditorVBox, name: []const u8, value: []const u8, size: f32, color: [3]f32) RenderError!void {
        const entity_id = std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ self.id_prefix, self.row }) catch return RenderError.OutOfMemory;
        defer self.allocator.free(entity_id);
        const entity = self.world.createEntity(entity_id, name) catch |err| return mapWorldError(err);
        self.world.setUiText(entity, .{
            .position = .{
                self.x,
                self.y + @as(f32, @floatFromInt(self.row)) * self.row_stride,
                0.0,
            },
            .size = size,
            .color = color,
            .value = value,
        }) catch |err| return mapWorldError(err);
        self.row += 1;
    }
};

fn extractDebugOverlayInto(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    input: FrameInput,
    scene_world: *const runtime.World,
) RenderError!void {
    const has_profiles = input.system_profiles.len > 0;
    const panel_size = editorDebugPanelSize(input);

    const canvas = world.createEntity("machina.editor.debug.canvas", "Editor Debug Canvas") catch |err| return mapWorldError(err);
    world.setUiCanvas(canvas) catch |err| return mapWorldError(err);

    const panel = world.createEntity("machina.editor.debug.panel", "Editor Debug Panel") catch |err| return mapWorldError(err);
    world.setUiRect(panel, .{
        .position = .{ 12.0, 12.0, 0.0 },
        .size = .{ panel_size[0], panel_size[1], 0.0 },
        .color = .{ 0.059, 0.09, 0.165 },
    }) catch |err| return mapWorldError(err);

    const accent = world.createEntity("machina.editor.debug.accent", "Editor Debug Accent") catch |err| return mapWorldError(err);
    world.setUiRect(accent, .{
        .position = .{ 12.0, 12.0, 0.0 },
        .size = .{ panel_size[0], 4.0, 0.0 },
        .color = .{ 0.056, 0.749, 0.823 },
    }) catch |err| return mapWorldError(err);

    const fps_text = formatFpsLabel(allocator, input.fps) catch return RenderError.OutOfMemory;
    defer allocator.free(fps_text);

    const label = world.createEntity("machina.editor.debug.fps", "Editor Debug FPS") catch |err| return mapWorldError(err);
    world.setUiText(label, .{
        .position = .{ 28.0, 24.0, 0.0 },
        .size = editor_debug_fps_size,
        .color = .{ 0.93, 0.969, 1.0 },
        .value = fps_text,
    }) catch |err| return mapWorldError(err);

    try extractEditorPlaybackControlsInto(world, input);

    if (!has_profiles) {
        try extractEditorInspectorInto(allocator, world, scene_world, input);
        return;
    }

    const header_text = formatSystemProfileHeader(allocator, input.system_profiles) catch return RenderError.OutOfMemory;
    defer allocator.free(header_text);
    const header = world.createEntity("machina.editor.debug.systems.header", "Editor Debug Systems Header") catch |err| return mapWorldError(err);
    world.setUiText(header, .{
        .position = .{ 28.0, editor_system_header_y, 0.0 },
        .size = editor_system_text_size,
        .color = .{ 0.56, 0.737, 0.949 },
        .value = header_text,
    }) catch |err| return mapWorldError(err);

    const visible_range = editorSystemVisibleRange(input);
    var system_rows = EditorVBox.init(allocator, world, "machina.editor.debug.systems.row", 28.0, editor_system_first_row_y, editor_system_row_stride);
    for (input.system_profiles[visible_range.start..visible_range.end]) |profile| {
        const line_text = formatSystemProfileLine(allocator, profile) catch return RenderError.OutOfMemory;
        defer allocator.free(line_text);
        try system_rows.text("Editor Debug System Row", line_text, editor_system_text_size, .{ 0.889, 0.949, 0.992 });
    }

    if (editorSystemNeedsScroll(input.system_profiles.len)) {
        const footer_text = std.fmt.allocPrint(allocator, "ROWS {d}-{d}/{d}  WHEEL", .{
            visible_range.start + 1,
            visible_range.end,
            input.system_profiles.len,
        }) catch return RenderError.OutOfMemory;
        defer allocator.free(footer_text);
        try system_rows.text("Editor Debug Systems Footer", footer_text, editor_system_text_size, .{ 0.56, 0.737, 0.949 });
    }

    try extractEditorInspectorInto(allocator, world, scene_world, input);
}

fn extractEditorPlaybackControlsInto(world: *runtime.World, input: FrameInput) RenderError!void {
    const play_label = if (input.editor.paused) "PLAY" else "PAUSE";
    const play_color: [3]f32 = if (input.editor.paused) .{ 0.063, 0.725, 0.506 } else .{ 0.961, 0.62, 0.043 };
    const play = world.createEntity("machina.editor.controls.play", "Editor Play Button") catch |err| return mapWorldError(err);
    world.setUiRect(play, .{
        .position = .{ editor_play_button_x, editor_control_button_y, 0.0 },
        .size = .{ editor_control_button_width, editor_control_button_height, 0.0 },
        .color = play_color,
    }) catch |err| return mapWorldError(err);
    const play_text = world.createEntity("machina.editor.controls.play.label", "Editor Play Label") catch |err| return mapWorldError(err);
    world.setUiText(play_text, .{
        .position = .{ editor_play_button_x + 18.0, editor_control_button_y + 8.0, 0.0 },
        .size = 1.0,
        .color = .{ 0.953, 0.969, 0.996 },
        .value = play_label,
    }) catch |err| return mapWorldError(err);

    const step = world.createEntity("machina.editor.controls.step", "Editor Step Button") catch |err| return mapWorldError(err);
    world.setUiRect(step, .{
        .position = .{ editor_step_button_x, editor_control_button_y, 0.0 },
        .size = .{ editor_control_button_width, editor_control_button_height, 0.0 },
        .color = .{ 0.129, 0.161, 0.216 },
    }) catch |err| return mapWorldError(err);
    const step_text = world.createEntity("machina.editor.controls.step.label", "Editor Step Label") catch |err| return mapWorldError(err);
    world.setUiText(step_text, .{
        .position = .{ editor_step_button_x + 22.0, editor_control_button_y + 8.0, 0.0 },
        .size = 1.0,
        .color = .{ 0.889, 0.949, 0.992 },
        .value = "STEP",
    }) catch |err| return mapWorldError(err);
}

fn extractEditorInspectorInto(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    scene_world: *const runtime.World,
    input: FrameInput,
) RenderError!void {
    const panel_x = @max(editorViewportWidth(input) - editor_inspector_panel_width - editor_inspector_panel_margin, editor_inspector_panel_margin);
    const panel_y = editor_inspector_panel_margin;
    const panel_height = editorInspectorPanelHeight(input);

    const panel = world.createEntity("machina.editor.inspector.panel", "Editor Inspector Panel") catch |err| return mapWorldError(err);
    world.setUiRect(panel, .{
        .position = .{ panel_x, panel_y, 0.0 },
        .size = .{ editor_inspector_panel_width, panel_height, 0.0 },
        .color = .{ 0.059, 0.09, 0.165 },
    }) catch |err| return mapWorldError(err);

    const accent = world.createEntity("machina.editor.inspector.accent", "Editor Inspector Accent") catch |err| return mapWorldError(err);
    world.setUiRect(accent, .{
        .position = .{ panel_x, panel_y, 0.0 },
        .size = .{ editor_inspector_panel_width, 4.0, 0.0 },
        .color = .{ 0.056, 0.749, 0.823 },
    }) catch |err| return mapWorldError(err);

    var row: usize = 0;
    try extractEditorInspectorLine(allocator, world, row, panel_x, panel_y, "INSPECTOR", 1.15, .{ 0.93, 0.969, 1.0 });
    row += 1;

    const counts = std.fmt.allocPrint(allocator, "ENTITIES {d} COMPONENTS {d}", .{
        input.editor.entity_count,
        input.editor.component_instance_count,
    }) catch return RenderError.OutOfMemory;
    defer allocator.free(counts);
    try extractEditorInspectorLine(allocator, world, row, panel_x, panel_y, counts, editor_inspector_text_size, .{ 0.56, 0.737, 0.949 });
    row += 1;

    const renderables = std.fmt.allocPrint(allocator, "RENDERABLES {d}", .{input.editor.renderable_count}) catch return RenderError.OutOfMemory;
    defer allocator.free(renderables);
    try extractEditorInspectorLine(allocator, world, row, panel_x, panel_y, renderables, editor_inspector_text_size, .{ 0.56, 0.737, 0.949 });
    row += 1;

    const selected = input.editor.selected_entity orelse {
        try extractEditorInspectorLine(allocator, world, row, panel_x, panel_y, "NO ENTITY SELECTED", editor_inspector_text_size, .{ 0.889, 0.949, 0.992 });
        row += 1;
        try extractEditorInspectorLine(allocator, world, row, panel_x, panel_y, "CLICK A MESH", editor_inspector_text_size, .{ 0.647, 0.725, 0.839 });
        return;
    };

    const entity = scene_world.entity(selected) catch {
        try extractEditorInspectorLine(allocator, world, row, panel_x, panel_y, "SELECTION UNAVAILABLE", editor_inspector_text_size, .{ 0.992, 0.443, 0.443 });
        return;
    };

    const handle = std.fmt.allocPrint(allocator, "HANDLE {d}:{d}", .{ selected.index, selected.generation }) catch return RenderError.OutOfMemory;
    defer allocator.free(handle);
    try extractEditorInspectorLine(allocator, world, row, panel_x, panel_y, handle, editor_inspector_text_size, .{ 0.889, 0.949, 0.992 });
    row += 1;

    const name = std.fmt.allocPrint(allocator, "NAME {s}", .{entity.name}) catch return RenderError.OutOfMemory;
    defer allocator.free(name);
    try extractEditorInspectorLine(allocator, world, row, panel_x, panel_y, name, editor_inspector_text_size, .{ 0.889, 0.949, 0.992 });
    row += 1;

    const id = std.fmt.allocPrint(allocator, "ID {s}", .{entity.id}) catch return RenderError.OutOfMemory;
    defer allocator.free(id);
    try extractEditorInspectorLine(allocator, world, row, panel_x, panel_y, id, editor_inspector_text_size, .{ 0.889, 0.949, 0.992 });
    row += 1;

    if (scene_world.getTransform(selected) catch null) |transform_value| {
        const position = formatInspectorVec3(allocator, "POS", transform_value.position) catch return RenderError.OutOfMemory;
        defer allocator.free(position);
        try extractEditorInspectorLine(allocator, world, row, panel_x, panel_y, position, editor_inspector_text_size, .{ 0.86, 0.917, 0.996 });
        row += 1;
    }

    var overflow = false;
    var components = scene_world.entityComponents(selected) catch {
        return;
    };
    while (components.next()) |component_id| {
        if (row >= editor_inspector_max_lines) {
            overflow = true;
            break;
        }
        const component_line = std.fmt.allocPrint(allocator, "[{s}]", .{component_id}) catch return RenderError.OutOfMemory;
        defer allocator.free(component_line);
        try extractEditorInspectorLine(allocator, world, row, panel_x, panel_y, component_line, editor_inspector_text_size, .{ 0.253, 0.827, 0.933 });
        row += 1;

        const field_count = scene_world.componentFieldCount(component_id);
        for (0..field_count) |field_index| {
            if (row >= editor_inspector_max_lines) {
                overflow = true;
                break;
            }
            const field_name = scene_world.componentFieldNameAt(component_id, field_index) orelse continue;
            const value = scene_world.getComponentFieldValue(selected, component_id, field_name) catch continue;
            const field_line = formatInspectorFieldValue(allocator, field_name, value) catch return RenderError.OutOfMemory;
            defer allocator.free(field_line);
            try extractEditorInspectorLine(allocator, world, row, panel_x, panel_y, field_line, editor_inspector_text_size, .{ 0.889, 0.949, 0.992 });
            row += 1;
        }
        if (overflow) {
            break;
        }
    }

    if (overflow and row < editor_inspector_max_lines + 1) {
        try extractEditorInspectorLine(allocator, world, row, panel_x, panel_y, "... MORE", editor_inspector_text_size, .{ 0.56, 0.737, 0.949 });
    }
}

fn extractEditorInspectorLine(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    row: usize,
    panel_x: f32,
    panel_y: f32,
    value: []const u8,
    size: f32,
    color: [3]f32,
) RenderError!void {
    const entity_id = std.fmt.allocPrint(allocator, "machina.editor.inspector.line.{d}", .{row}) catch return RenderError.OutOfMemory;
    defer allocator.free(entity_id);
    const entity = world.createEntity(entity_id, "Editor Inspector Line") catch |err| return mapWorldError(err);
    world.setUiText(entity, .{
        .position = .{
            panel_x + 16.0,
            panel_y + 18.0 + @as(f32, @floatFromInt(row)) * editor_inspector_line_stride,
            0.0,
        },
        .size = size,
        .color = color,
        .value = value,
    }) catch |err| return mapWorldError(err);
}

fn formatInspectorVec3(allocator: std.mem.Allocator, label: []const u8, value: [3]f32) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(allocator, "{s} {d:.2} {d:.2} {d:.2}", .{ label, value[0], value[1], value[2] });
}

fn formatInspectorFieldValue(allocator: std.mem.Allocator, field_name: []const u8, value: runtime.ComponentValue) error{OutOfMemory}![]const u8 {
    return switch (value) {
        .boolean => |payload| std.fmt.allocPrint(allocator, "  {s} {s}", .{ field_name, if (payload) "TRUE" else "FALSE" }),
        .int => |payload| std.fmt.allocPrint(allocator, "  {s} {d}", .{ field_name, payload }),
        .float => |payload| std.fmt.allocPrint(allocator, "  {s} {d:.3}", .{ field_name, payload }),
        .vec3 => |payload| std.fmt.allocPrint(allocator, "  {s} {d:.2} {d:.2} {d:.2}", .{ field_name, payload[0], payload[1], payload[2] }),
        .string => |payload| blk: {
            const max_len: usize = 26;
            const visible = if (payload.len > max_len) payload[0..max_len] else payload;
            const suffix = if (payload.len > max_len) "..." else "";
            break :blk std.fmt.allocPrint(allocator, "  {s} {s}{s}", .{ field_name, visible, suffix });
        },
    };
}

fn editorDebugPanelSize(input: FrameInput) [2]f32 {
    const visible_range = editorSystemVisibleRange(input);
    const profile_rows = visible_range.end - visible_range.start;
    const has_profiles = input.system_profiles.len > 0;
    const panel_width: f32 = if (has_profiles) editor_system_panel_width else editor_controls_panel_width;
    var panel_height: f32 = 108.0;
    if (has_profiles) {
        panel_height = 146.0 + @as(f32, @floatFromInt(profile_rows)) * editor_system_row_stride;
        if (editorSystemNeedsScroll(input.system_profiles.len)) {
            panel_height += editor_system_row_stride;
        }
    }
    return .{ panel_width, panel_height };
}

const EditorSystemVisibleRange = struct {
    start: usize,
    end: usize,
};

fn editorSystemVisibleRange(input: FrameInput) EditorSystemVisibleRange {
    const profile_count = input.system_profiles.len;
    const visible_count = @min(profile_count, editor_system_profile_max_rows);
    const max_start = editorSystemMaxScroll(profile_count);
    const start = @min(input.editor.system_scroll_offset, max_start);
    return .{
        .start = start,
        .end = @min(profile_count, start + visible_count),
    };
}

fn editorSystemNeedsScroll(profile_count: usize) bool {
    return profile_count > editor_system_profile_max_rows;
}

fn editorSystemMaxScroll(profile_count: usize) usize {
    return if (profile_count > editor_system_profile_max_rows)
        profile_count - editor_system_profile_max_rows
    else
        0;
}

fn editorInspectorPanelHeight(input: FrameInput) f32 {
    return if (input.editor.selected_entity == null)
        editor_inspector_empty_panel_height
    else
        editor_inspector_panel_height;
}

fn formatFpsLabel(allocator: std.mem.Allocator, fps: f32) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(allocator, "FPS {d}", .{roundedFps(fps)});
}

fn formatSystemProfileHeader(allocator: std.mem.Allocator, profiles: []const runtime.SystemProfileSnapshot) error{OutOfMemory}![]const u8 {
    const window_size = if (profiles.len == 0) 0 else profiles[0].window_size;
    return std.fmt.allocPrint(allocator, "SYS {d} AVG {d}F SNAP 3HZ", .{ profiles.len, window_size });
}

fn formatSystemProfileLine(allocator: std.mem.Allocator, profile: runtime.SystemProfileSnapshot) error{OutOfMemory}![]const u8 {
    const phase = systemPhaseLabel(profile.phase);
    const id_prefix = if (profile.id.len > editor_system_profile_id_chars)
        profile.id[0 .. editor_system_profile_id_chars - 3]
    else
        profile.id;
    const ellipsis = if (profile.id.len > editor_system_profile_id_chars) "..." else "";

    if (profile.sample_count == 0) {
        return std.fmt.allocPrint(allocator, "{s} {s}{s} A-- L--", .{
            phase,
            id_prefix,
            ellipsis,
        });
    }

    var average_buffer: [16]u8 = undefined;
    var last_buffer: [16]u8 = undefined;
    const average = formatDurationShort(&average_buffer, profile.rolling_average_ns);
    const last = formatDurationShort(&last_buffer, profile.last_ns);
    return std.fmt.allocPrint(allocator, "{s} {s}{s} A{s} L{s}", .{
        phase,
        id_prefix,
        ellipsis,
        average,
        last,
    });
}

fn formatDurationShort(buffer: *[16]u8, ns: u64) []const u8 {
    const micros = nsToMicrosRounded(ns);
    if (micros < 10_000) {
        return std.fmt.bufPrint(buffer, "{d}U", .{micros}) catch "----";
    }
    return std.fmt.bufPrint(buffer, "{d}MS", .{(micros + 500) / 1000}) catch "----";
}

fn systemPhaseLabel(phase: runtime.SystemPhase) []const u8 {
    return switch (phase) {
        .startup => "STA",
        .update => "UPD",
        .fixed_update => "FIX",
        .render => "RND",
    };
}

fn nsToMicrosRounded(ns: u64) u64 {
    return (ns + 500) / 1000;
}

fn elapsedNanosecondsSince(started_ns: i128) u64 {
    const elapsed_ns = monotonicTimestampNs() - started_ns;
    if (elapsed_ns <= 0) {
        return 0;
    }
    return @intCast(@min(elapsed_ns, std.math.maxInt(u64)));
}

fn monotonicTimestampNs() i128 {
    const io = Io.Threaded.global_single_threaded.io();
    return Io.Timestamp.now(io, .awake).nanoseconds;
}

fn roundedFps(fps: f32) i32 {
    if (!std.math.isFinite(fps) or fps <= 0.0) {
        return 0;
    }
    const clamped = @min(fps, 9999.0);
    return @intFromFloat(@round(clamped));
}

pub fn writeFrameInput(world: *runtime.World, input: FrameInput) runtime.WorldError!void {
    const entity = world.findEntityById(runtime.input_entity_id) orelse try world.createEntity(runtime.input_entity_id, "Input Frame");
    try world.setInputPointer(entity, .{
        .position = .{ input.pointer.position[0], input.pointer.position[1], 0.0 },
        .has_position = input.pointer.has_position,
        .primary_down = input.pointer.primary_down,
        .primary_pressed = input.pointer.primary_pressed,
        .primary_released = input.pointer.primary_released,
        .wheel_delta = .{ input.pointer.wheel_delta[0], input.pointer.wheel_delta[1], 0.0 },
    });
    try world.setInputKeyboard(entity, .{
        .ctrl_down = input.keyboard.ctrl_down,
        .shift_down = input.keyboard.shift_down,
        .alt_down = input.keyboard.alt_down,
        .super_down = input.keyboard.super_down,
        .editor_toggle_pressed = input.keyboard.editor_toggle_pressed,
    });
    try world.setInputFrame(entity, .{
        .ui_visible = input.ui_visible,
        .debug_overlay_visible = input.debug_overlay_visible,
        .viewport = .{ input.viewport_width, input.viewport_height, 0.0 },
    });
}

fn setRenderFrameInput(world: *runtime.World, input: FrameInput) RenderError!void {
    writeFrameInput(world, input) catch |err| return mapWorldError(err);
}

fn renderFrameInput(world: *const runtime.World) RenderError!FrameInput {
    const entity = world.findEntityById(runtime.input_entity_id) orelse return RenderError.InvalidScene;
    const position = world.getVec3(entity, runtime.input_pointer_component_id, "position") catch |err| return mapWorldError(err);
    const wheel_delta = world.getVec3(entity, runtime.input_pointer_component_id, "wheel_delta") catch |err| return mapWorldError(err);
    const viewport = world.getVec3(entity, runtime.input_frame_component_id, "viewport") catch |err| return mapWorldError(err);
    return .{
        .pointer = .{
            .position = .{ position[0], position[1] },
            .has_position = world.getBoolean(entity, runtime.input_pointer_component_id, "has_position") catch |err| return mapWorldError(err),
            .primary_down = world.getBoolean(entity, runtime.input_pointer_component_id, "primary_down") catch |err| return mapWorldError(err),
            .primary_pressed = world.getBoolean(entity, runtime.input_pointer_component_id, "primary_pressed") catch |err| return mapWorldError(err),
            .primary_released = world.getBoolean(entity, runtime.input_pointer_component_id, "primary_released") catch |err| return mapWorldError(err),
            .wheel_delta = .{ wheel_delta[0], wheel_delta[1] },
        },
        .keyboard = .{
            .ctrl_down = world.getBoolean(entity, runtime.input_keyboard_component_id, "ctrl_down") catch |err| return mapWorldError(err),
            .shift_down = world.getBoolean(entity, runtime.input_keyboard_component_id, "shift_down") catch |err| return mapWorldError(err),
            .alt_down = world.getBoolean(entity, runtime.input_keyboard_component_id, "alt_down") catch |err| return mapWorldError(err),
            .super_down = world.getBoolean(entity, runtime.input_keyboard_component_id, "super_down") catch |err| return mapWorldError(err),
            .editor_toggle_pressed = world.getBoolean(entity, runtime.input_keyboard_component_id, "editor_toggle_pressed") catch |err| return mapWorldError(err),
        },
        .ui_visible = world.getBoolean(entity, runtime.input_frame_component_id, "ui_visible") catch |err| return mapWorldError(err),
        .debug_overlay_visible = world.getBoolean(entity, runtime.input_frame_component_id, "debug_overlay_visible") catch |err| return mapWorldError(err),
        .viewport_width = viewport[0],
        .viewport_height = viewport[1],
    };
}

fn setRenderUiButtonState(world: *runtime.World, entity: runtime.EntityHandle, state: UiButtonState) RenderError!void {
    const fields = [_]runtime.ComponentFieldValue{
        .{ .name = "hovered", .value = .{ .boolean = state.hovered } },
        .{ .name = "held", .value = .{ .boolean = state.held } },
        .{ .name = "pressed", .value = .{ .boolean = state.pressed } },
    };
    world.setComponent(entity, render_ui_button_state_component_id, &fields) catch |err| return mapWorldError(err);
}

fn renderUiButtonState(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?UiButtonState {
    if (!(world.hasComponent(entity, render_ui_button_state_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return .{
        .hovered = world.getBoolean(entity, render_ui_button_state_component_id, "hovered") catch |err| return mapWorldError(err),
        .held = world.getBoolean(entity, render_ui_button_state_component_id, "held") catch |err| return mapWorldError(err),
        .pressed = world.getBoolean(entity, render_ui_button_state_component_id, "pressed") catch |err| return mapWorldError(err),
    };
}

fn evaluateUiButtonState(input: FrameInput, position: [3]f32, size: [3]f32) UiButtonState {
    const hovered = input.pointer.has_position and runtime.pointInsideUiRect(input.pointer.position, position, size);
    return .{
        .hovered = hovered,
        .held = hovered and input.pointer.primary_down,
        .pressed = hovered and input.pointer.primary_released,
    };
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
    renderables: []runtime.RenderableMesh,
    batches: []BatchPlanEntry,

    fn build(allocator: std.mem.Allocator, world: *const runtime.World) RenderError!BatchPlan {
        var renderables: std.ArrayList(runtime.RenderableMesh) = .empty;
        errdefer renderables.deinit(allocator);

        var builds: std.ArrayList(BatchBuild) = .empty;
        errdefer {
            for (builds.items) |*pending_batch| {
                pending_batch.deinit(allocator);
            }
            builds.deinit(allocator);
        }

        var meshes = world.renderableMeshes();
        while (meshes.next()) |renderable| {
            const render_index = renderables.items.len;
            renderables.append(allocator, renderable) catch return RenderError.OutOfMemory;
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

        const renderable_slice = renderables.toOwnedSlice(allocator) catch return RenderError.OutOfMemory;
        errdefer allocator.free(renderable_slice);

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

    fn deinit(self: *BatchPlan) void {
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

const BatchPlanEntry = struct {
    geometry_key: GeometryKey,
    shadow_key: ShadowKey,
    render_indices: []usize,
};

const UiDrawResources = struct {
    vertex_buffer: ?*wgpu.Buffer = null,
    vertex_buffer_size: u64 = 0,
    vertex_count: u32 = 0,

    fn update(
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
                .label = wgpu.StringView.fromSlice("Machina UI vertex buffer"),
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

    fn deinit(self: *UiDrawResources) void {
        if (self.vertex_buffer) |buffer| {
            buffer.release();
        }
        self.* = .{};
    }
};

const MeshDemo = struct {
    allocator: std.mem.Allocator,
    pipeline: *wgpu.RenderPipeline,
    shadow_pipeline: *wgpu.RenderPipeline,
    ui_pipeline: *wgpu.RenderPipeline,
    bind_group_layout: *wgpu.BindGroupLayout,
    pipeline_layout: *wgpu.PipelineLayout,
    shadow_pipeline_layout: *wgpu.PipelineLayout,
    ui_pipeline_layout: *wgpu.PipelineLayout,
    frame_uniform_buffer: *wgpu.Buffer,
    bind_group: *wgpu.BindGroup,
    shadow_target: ShadowTarget,
    shadow_sampler: *wgpu.Sampler,
    render_state: RenderEcsState,
    batches: []BatchResources,
    ui_draw: UiDrawResources = .{},

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

        const ui_pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Machina UI pipeline layout"),
            .bind_group_layout_count = empty_bind_group_layouts.len,
            .bind_group_layouts = &empty_bind_group_layouts,
        }) orelse return RenderError.NoDevice;
        errdefer ui_pipeline_layout.release();

        const ui_pipeline = try createUiPipeline(device, texture_format, ui_pipeline_layout);
        errdefer ui_pipeline.release();

        return .{
            .allocator = allocator,
            .pipeline = pipeline,
            .shadow_pipeline = shadow_pipeline,
            .ui_pipeline = ui_pipeline,
            .bind_group_layout = bind_group_layout,
            .pipeline_layout = pipeline_layout,
            .shadow_pipeline_layout = shadow_pipeline_layout,
            .ui_pipeline_layout = ui_pipeline_layout,
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
        self.ui_pipeline.release();
        self.pipeline_layout.release();
        self.shadow_pipeline_layout.release();
        self.ui_pipeline_layout.release();
        self.bind_group_layout.release();
        self.ui_draw.deinit();
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

        var profiled_context = context;
        profiled_context.frame.input.system_profiles = try self.render_state.combineSystemProfileSnapshots(context.frame.input.system_profiles);

        for (self.render_state.schedule.batches) |batch| {
            for (batch.systems) |system| {
                const started_ns = monotonicTimestampNs();
                const result = self.runRenderSystem(system, profiled_context, &maybe_plan);
                self.render_state.recordSystemDuration(system, batch.phase, elapsedNanosecondsSince(started_ns));
                try result;
            }
        }
    }

    fn runRenderSystem(
        self: *MeshDemo,
        system: runtime.ScheduledSystem,
        context: RenderSystemContext,
        maybe_plan: *?BatchPlan,
    ) RenderError!void {
        if (std.mem.eql(u8, system.id, render_extract_system_id)) {
            try self.render_state.extractSceneWithInput(context.frame.scene, context.frame.input);
        } else if (std.mem.eql(u8, system.id, render_prepare_meshes_system_id)) {
            var plan = try BatchPlan.build(self.allocator, &self.render_state.world);
            var plan_transferred = false;
            errdefer if (!plan_transferred) {
                plan.deinit();
            };
            try self.prepareBatchResources(context.device, plan);
            try self.updateBatchInstances(context.queue, plan, context.frame);
            maybe_plan.* = plan;
            plan_transferred = true;
        } else if (std.mem.eql(u8, system.id, render_queue_meshes_system_id)) {
            const plan = maybe_plan.* orelse return RenderError.InvalidScene;
            try self.render_state.queueBatchDraws(plan.batches.len);
        } else if (std.mem.eql(u8, system.id, render_interact_ui_system_id)) {
            try self.render_state.updateUiInteractions();
        } else if (std.mem.eql(u8, system.id, render_prepare_ui_system_id)) {
            try self.prepareUiDrawResources(context.device, context.queue, context.frame);
        } else if (std.mem.eql(u8, system.id, render_queue_ui_system_id)) {
            try self.render_state.queueUiDraw();
        } else if (std.mem.eql(u8, system.id, render_draw_meshes_system_id)) {
            try self.drawQueuedBatches(context);
        } else {
            return RenderError.InvalidScene;
        }
    }

    fn prepareUiDrawResources(self: *MeshDemo, device: *wgpu.Device, queue: *wgpu.Queue, config: FrameConfig) RenderError!void {
        var vertices = try buildUiVertices(self.allocator, &self.render_state.world, config.width, config.height);
        defer vertices.deinit(self.allocator);
        try self.ui_draw.update(device, queue, vertices.items);
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
                if (render_index >= plan.renderables.len) {
                    return RenderError.InvalidScene;
                }
                const mesh = plan.renderables[render_index];
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

        const should_draw_ui = self.render_state.uiDrawCommandCount() > 0 and self.ui_draw.vertex_count > 0;

        const encoder = context.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh command encoder"),
        }) orelse return RenderError.NoDevice;
        defer encoder.release();

        try self.drawShadowPass(encoder, draw_batch_indices.items);

        const color_attachments = [_]wgpu.ColorAttachment{
            .{
                .view = context.target_view,
                .clear_value = .{
                    .r = 0.0006,
                    .g = 0.0018,
                    .b = 0.0086,
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

        if (should_draw_ui) {
            try self.drawUiPass(encoder, context.target_view);
        }

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

    fn drawUiPass(self: *MeshDemo, encoder: *wgpu.CommandEncoder, target_view: *wgpu.TextureView) RenderError!void {
        const color_attachments = [_]wgpu.ColorAttachment{
            .{
                .view = target_view,
                .load_op = .load,
                .store_op = .store,
            },
        };
        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .label = wgpu.StringView.fromSlice("Machina UI pass"),
            .color_attachment_count = color_attachments.len,
            .color_attachments = &color_attachments,
        }) orelse return RenderError.NoDevice;
        defer render_pass.release();

        render_pass.setPipeline(self.ui_pipeline);
        const vertex_buffer = self.ui_draw.vertex_buffer orelse return RenderError.NoDevice;
        render_pass.setVertexBuffer(0, vertex_buffer, 0, self.ui_draw.vertex_buffer_size);
        render_pass.draw(self.ui_draw.vertex_count, 1, 0, 0);
        render_pass.end();
    }
};

const BatchResources = struct {
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

fn updatePointerFromWindow(pointer: *PointerInput, window: *sdl.SDL_Window, x: f32, y: f32) void {
    var window_width: c_int = 0;
    var window_height: c_int = 0;
    var pixel_width: c_int = 0;
    var pixel_height: c_int = 0;

    const has_window_size = sdl.SDL_GetWindowSize(window, &window_width, &window_height);
    const has_pixel_size = sdl.SDL_GetWindowSizeInPixels(window, &pixel_width, &pixel_height);
    if (!has_window_size or !has_pixel_size or window_width <= 0 or window_height <= 0) {
        pointer.position = .{ x, y };
        pointer.has_position = true;
        return;
    }

    const scale_x = @as(f32, @floatFromInt(@max(pixel_width, 1))) / @as(f32, @floatFromInt(window_width));
    const scale_y = @as(f32, @floatFromInt(@max(pixel_height, 1))) / @as(f32, @floatFromInt(window_height));
    pointer.position = .{ x * scale_x, y * scale_y };
    pointer.has_position = true;
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

fn createUiPipeline(device: *wgpu.Device, texture_format: wgpu.TextureFormat, pipeline_layout: *wgpu.PipelineLayout) RenderError!*wgpu.RenderPipeline {
    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("shaders/ui.wgsl"),
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
        },
    };

    return device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .label = wgpu.StringView.fromSlice("Machina UI pipeline"),
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

const EditorRay = struct {
    origin: [3]f32,
    direction: [3]f32,
};

fn validatedEditorSelection(world: *const runtime.World, selected: ?runtime.EntityHandle) ?runtime.EntityHandle {
    const entity = selected orelse return null;
    _ = world.entity(entity) catch return null;
    if (!(world.hasComponent(entity, runtime.transform_component_id) catch return null)) {
        return null;
    }
    if (!(world.hasComponent(entity, runtime.geometry_primitive_component_id) catch false) and
        !(world.hasComponent(entity, runtime.cube_renderer_component_id) catch false))
    {
        return null;
    }
    return entity;
}

fn pickRenderableEntity(world: *const runtime.World, input: FrameInput) EditorError!?runtime.EntityHandle {
    const ray = try editorRayFromInput(world, input);
    var best_entity: ?runtime.EntityHandle = null;
    var best_t = std.math.inf(f32);

    var meshes = world.renderableMeshes();
    while (meshes.next()) |mesh| {
        const radius = editorPickRadiusForMesh(mesh);
        const hit_t = intersectRaySphere(ray, mesh.position, radius) orelse continue;
        if (hit_t >= 0.0 and hit_t < best_t) {
            best_t = hit_t;
            best_entity = mesh.entity;
        }
    }

    return best_entity;
}

fn pickEditorGizmoAxis(world: *const runtime.World, selected: runtime.EntityHandle, input: FrameInput) EditorError!EditorAxis {
    const transform_value = (try world.getTransform(selected)) orelse return .none;
    const camera = cameraState(world) catch return error.InvalidScene;
    const origin_screen = projectWorldToScreen(transform_value.position, camera, input) orelse return .none;
    const axes = [_]struct {
        axis: EditorAxis,
        vector: [3]f32,
    }{
        .{ .axis = .x, .vector = .{ 1.0, 0.0, 0.0 } },
        .{ .axis = .y, .vector = .{ 0.0, 1.0, 0.0 } },
        .{ .axis = .z, .vector = .{ 0.0, 0.0, 1.0 } },
    };

    var best_axis = EditorAxis.none;
    var best_distance = editor_gizmo_pick_radius_px;
    for (axes) |entry| {
        const end_screen = projectWorldToScreen(addVec3(transform_value.position, scaleVec3(entry.vector, editor_gizmo_axis_length)), camera, input) orelse continue;
        const distance = distancePointToScreenSegment(input.pointer.position, origin_screen, end_screen);
        if (distance < best_distance) {
            best_distance = distance;
            best_axis = entry.axis;
        }
    }
    return best_axis;
}

fn dragSelectedEntity(world: *runtime.World, state: *EditorState, input: FrameInput) EditorError!void {
    const selected = state.selected_entity orelse return;
    const transform_value = (try world.getTransform(selected)) orelse return;
    if (!state.has_last_pointer) {
        state.last_pointer = input.pointer.position;
        state.has_last_pointer = true;
        return;
    }

    const axis = editorAxisVector(state.dragging_axis) orelse return;
    const camera = cameraState(world) catch return error.InvalidScene;
    const origin_screen = projectWorldToScreen(transform_value.position, camera, input) orelse return;
    const axis_screen_end = projectWorldToScreen(addVec3(transform_value.position, scaleVec3(axis, editor_gizmo_axis_length)), camera, input) orelse return;
    const axis_screen_delta = subtractVec2(axis_screen_end, origin_screen);
    const axis_screen_length = vec2Length(axis_screen_delta);
    if (axis_screen_length < 0.001) {
        state.last_pointer = input.pointer.position;
        return;
    }

    const axis_screen = scaleVec2(axis_screen_delta, 1.0 / axis_screen_length);
    const pointer_delta = subtractVec2(input.pointer.position, state.last_pointer);
    const projected_pixels = dotVec2(pointer_delta, axis_screen);
    const camera_distance = vec3Length(subtractVec3(transform_value.position, camera.transform.position));
    const units_per_pixel = @max(camera_distance, 1.0) * 0.0025;
    const world_delta = projected_pixels * units_per_pixel;
    const next_position = addVec3(transform_value.position, scaleVec3(axis, world_delta));

    try world.setVec3(selected, runtime.transform_component_id, "position", next_position);
    state.last_pointer = input.pointer.position;
}

fn editorRayFromInput(world: *const runtime.World, input: FrameInput) EditorError!EditorRay {
    const width = editorViewportWidth(input);
    const height = editorViewportHeight(input);
    if (width <= 0.0 or height <= 0.0) {
        return error.InvalidScene;
    }
    const camera = cameraState(world) catch return error.InvalidScene;
    const aspect = width / height;
    const tan_half_fov = @tan(std.math.degreesToRadians(camera.fov_y_degrees) * 0.5);
    const ndc_x = (input.pointer.position[0] / width) * 2.0 - 1.0;
    const ndc_y = 1.0 - (input.pointer.position[1] / height) * 2.0;
    const local_direction = normalizeVec3(.{
        ndc_x * tan_half_fov * aspect,
        ndc_y * tan_half_fov,
        -1.0,
    });
    return .{
        .origin = camera.transform.position,
        .direction = rotateDirection(camera.transform.rotation, local_direction),
    };
}

fn projectWorldToScreen(position: [3]f32, camera_value: CameraState, input: FrameInput) ?[2]f32 {
    const width = editorViewportWidth(input);
    const height = editorViewportHeight(input);
    if (width <= 0.0 or height <= 0.0) {
        return null;
    }
    const camera = validateCamera(camera_value) catch return null;
    const view = cameraViewMatrix(camera.transform);
    const projection = perspective(std.math.degreesToRadians(camera.fov_y_degrees), width / height, camera.near, camera.far);
    const clip = transformPoint(matMul(projection, view), .{ position[0], position[1], position[2], 1.0 });
    if (@abs(clip[3]) < 0.00001) {
        return null;
    }
    const ndc_x = clip[0] / clip[3];
    const ndc_y = clip[1] / clip[3];
    if (!std.math.isFinite(ndc_x) or !std.math.isFinite(ndc_y)) {
        return null;
    }
    return .{
        (ndc_x + 1.0) * 0.5 * width,
        (1.0 - ndc_y) * 0.5 * height,
    };
}

fn intersectRaySphere(ray: EditorRay, center: [3]f32, radius: f32) ?f32 {
    const oc = subtractVec3(ray.origin, center);
    const a = dotVec3(ray.direction, ray.direction);
    const b = 2.0 * dotVec3(oc, ray.direction);
    const c = dotVec3(oc, oc) - radius * radius;
    const discriminant = b * b - 4.0 * a * c;
    if (discriminant < 0.0) {
        return null;
    }
    const root = @sqrt(discriminant);
    const near_t = (-b - root) / (2.0 * a);
    if (near_t >= 0.0) {
        return near_t;
    }
    const far_t = (-b + root) / (2.0 * a);
    return if (far_t >= 0.0) far_t else null;
}

fn editorPickRadiusForMesh(mesh: runtime.RenderableMesh) f32 {
    return @max(@max(@abs(mesh.scale[0]), @abs(mesh.scale[1])), @abs(mesh.scale[2])) * 1.25;
}

fn editorAxisVector(axis: EditorAxis) ?[3]f32 {
    return switch (axis) {
        .none => null,
        .x => .{ 1.0, 0.0, 0.0 },
        .y => .{ 0.0, 1.0, 0.0 },
        .z => .{ 0.0, 0.0, 1.0 },
    };
}

fn hitEditorPlayButton(position: [2]f32) bool {
    return pointInsideScreenRect(position, .{ editor_play_button_x, editor_control_button_y }, .{ editor_control_button_width, editor_control_button_height });
}

fn hitEditorStepButton(position: [2]f32) bool {
    return pointInsideScreenRect(position, .{ editor_step_button_x, editor_control_button_y }, .{ editor_control_button_width, editor_control_button_height });
}

fn hitEditorChrome(input: FrameInput) bool {
    const width = editorViewportWidth(input);
    const inspector_x = @max(width - editor_inspector_panel_width - editor_inspector_panel_margin, editor_inspector_panel_margin);
    return hitEditorSystemPanel(input) or
        pointInsideScreenRect(input.pointer.position, .{ inspector_x, editor_inspector_panel_margin }, .{ editor_inspector_panel_width, editorInspectorPanelHeight(input) });
}

fn hitEditorSystemPanel(input: FrameInput) bool {
    return pointInsideScreenRect(input.pointer.position, .{ editor_controls_panel_x, editor_controls_panel_y }, editorDebugPanelSize(input));
}

fn pointInsideScreenRect(position: [2]f32, origin: [2]f32, size: [2]f32) bool {
    return position[0] >= origin[0] and position[1] >= origin[1] and position[0] <= origin[0] + size[0] and position[1] <= origin[1] + size[1];
}

fn editorViewportWidth(input: FrameInput) f32 {
    return if (input.viewport_width > 0.0) input.viewport_width else @as(f32, @floatFromInt(output_width));
}

fn editorViewportHeight(input: FrameInput) f32 {
    return if (input.viewport_height > 0.0) input.viewport_height else @as(f32, @floatFromInt(output_height));
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

fn addVec3(left: [3]f32, right: [3]f32) [3]f32 {
    return .{ left[0] + right[0], left[1] + right[1], left[2] + right[2] };
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

fn addVec2(left: [2]f32, right: [2]f32) [2]f32 {
    return .{ left[0] + right[0], left[1] + right[1] };
}

fn subtractVec2(left: [2]f32, right: [2]f32) [2]f32 {
    return .{ left[0] - right[0], left[1] - right[1] };
}

fn scaleVec2(value: [2]f32, scalar: f32) [2]f32 {
    return .{ value[0] * scalar, value[1] * scalar };
}

fn dotVec2(left: [2]f32, right: [2]f32) f32 {
    return left[0] * right[0] + left[1] * right[1];
}

fn vec2Length(value: [2]f32) f32 {
    return @sqrt(value[0] * value[0] + value[1] * value[1]);
}

fn distancePointToScreenSegment(point: [2]f32, start: [2]f32, end: [2]f32) f32 {
    const segment = subtractVec2(end, start);
    const segment_len_sq = dotVec2(segment, segment);
    if (segment_len_sq <= 0.00001) {
        return vec2Length(subtractVec2(point, start));
    }
    const raw_t = dotVec2(subtractVec2(point, start), segment) / segment_len_sq;
    const t = @max(0.0, @min(1.0, raw_t));
    const closest = addVec2(start, scaleVec2(segment, t));
    return vec2Length(subtractVec2(point, closest));
}

fn rotateDirection(rotation: [3]f32, direction: [3]f32) [3]f32 {
    const matrix = matMul(
        rotationZ(rotation[2]),
        matMul(
            rotationY(rotation[1]),
            rotationX(rotation[0]),
        ),
    );
    const rotated = transformPoint(matrix, .{ direction[0], direction[1], direction[2], 0.0 });
    return normalizeVec3(.{ rotated[0], rotated[1], rotated[2] });
}

fn transformPoint(matrix: [16]f32, point: [4]f32) [4]f32 {
    return .{
        matrix[0] * point[0] + matrix[4] * point[1] + matrix[8] * point[2] + matrix[12] * point[3],
        matrix[1] * point[0] + matrix[5] * point[1] + matrix[9] * point[2] + matrix[13] * point[3],
        matrix[2] * point[0] + matrix[6] * point[1] + matrix[10] * point[2] + matrix[14] * point[3],
        matrix[3] * point[0] + matrix[7] * point[1] + matrix[11] * point[2] + matrix[15] * point[3],
    };
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

test "editor raycast selects nearest renderable mesh" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const far = try world.createEntity("far", "Far");
    try world.setTransform(far, .{ .position = .{ 0.0, 0.0, -2.0 } });
    try world.setCubeRenderer(far, .{ .color = .{ 0.2, 0.4, 0.8 } });

    const near = try world.createEntity("near", "Near");
    try world.setTransform(near, .{ .position = .{ 0.0, 0.0, 0.0 } });
    try world.setCubeRenderer(near, .{ .color = .{ 0.8, 0.4, 0.2 } });

    var editor_state = EditorState{};
    const update = try updateEditorState(&world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 960.0,
        .viewport_height = 540.0,
        .pointer = .{
            .position = .{ 480.0, 270.0 },
            .has_position = true,
            .primary_pressed = true,
            .primary_down = true,
        },
    });

    try std.testing.expect(update.consumed_pointer);
    try std.testing.expect(editor_state.selected_entity != null);
    try std.testing.expectEqual(near.index, editor_state.selected_entity.?.index);
    try std.testing.expectEqual(near.generation, editor_state.selected_entity.?.generation);
}

test "editor gizmo drag mutates selected transform position" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("selected", "Selected");
    try world.setTransform(entity, .{ .position = .{ 0.0, 0.0, 0.0 } });
    try world.setCubeRenderer(entity, .{ .color = .{ 0.8, 0.4, 0.2 } });

    var editor_state = EditorState{
        .selected_entity = entity,
        .dragging_axis = .x,
        .last_pointer = .{ 480.0, 270.0 },
        .has_last_pointer = true,
    };
    const update = try updateEditorState(&world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 960.0,
        .viewport_height = 540.0,
        .pointer = .{
            .position = .{ 520.0, 270.0 },
            .has_position = true,
            .primary_down = true,
        },
    });

    const transform_value = (try world.getTransform(entity)) orelse return error.TestExpectedEqual;
    try std.testing.expect(update.consumed_pointer);
    try std.testing.expect(transform_value.position[0] > 0.0);
    try std.testing.expectEqual(@as(f32, 0.0), transform_value.position[1]);
    try std.testing.expectEqual(@as(f32, 0.0), transform_value.position[2]);
}

test "editor playback controls toggle pause and request single step" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    var editor_state = EditorState{};
    const pause_update = try updateEditorState(&world, &editor_state, .{
        .debug_overlay_visible = true,
        .pointer = .{
            .position = .{ editor_play_button_x + 4.0, editor_control_button_y + 4.0 },
            .has_position = true,
            .primary_pressed = true,
            .primary_down = true,
        },
    });
    try std.testing.expect(pause_update.consumed_pointer);
    try std.testing.expect(editor_state.paused);

    const release_update = try updateEditorState(&world, &editor_state, .{
        .debug_overlay_visible = true,
        .pointer = .{
            .position = .{ editor_play_button_x + 4.0, editor_control_button_y + 4.0 },
            .has_position = true,
            .primary_released = true,
        },
    });
    try std.testing.expect(release_update.consumed_pointer);
    try std.testing.expect(!editor_state.captured_pointer);

    const step_update = try updateEditorState(&world, &editor_state, .{
        .debug_overlay_visible = true,
        .pointer = .{
            .position = .{ editor_step_button_x + 4.0, editor_control_button_y + 4.0 },
            .has_position = true,
            .primary_pressed = true,
            .primary_down = true,
        },
    });
    try std.testing.expect(step_update.consumed_pointer);
    try std.testing.expect(step_update.step_once);
    try std.testing.expect(editor_state.paused);
}

test "editor system list scroll state responds to wheel input" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{ .id = "system.0", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.1", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.2", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.3", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.4", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.5", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.6", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.7", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.8", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
    };

    var editor_state = EditorState{};
    const down_update = try updateEditorState(&world, &editor_state, .{
        .debug_overlay_visible = true,
        .system_profiles = &profiles,
        .pointer = .{
            .position = .{ editor_controls_panel_x + 12.0, editor_system_first_row_y },
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });
    try std.testing.expect(down_update.consumed_pointer);
    try std.testing.expectEqual(@as(usize, 1), editor_state.system_scroll_offset);

    const up_update = try updateEditorState(&world, &editor_state, .{
        .debug_overlay_visible = true,
        .system_profiles = &profiles,
        .pointer = .{
            .position = .{ editor_controls_panel_x + 12.0, editor_system_first_row_y },
            .has_position = true,
            .wheel_delta = .{ 0.0, 1.0 },
        },
    });
    try std.testing.expect(up_update.consumed_pointer);
    try std.testing.expectEqual(@as(usize, 0), editor_state.system_scroll_offset);
}

test "render ECS schedule orders extract prepare queue and draw systems" {
    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();

    try std.testing.expectEqual(@as(usize, 7), state.schedule.systemCount());
    try std.testing.expectEqual(@as(usize, 6), state.schedule.batchCount());

    const expected = [_][]const u8{
        render_extract_system_id,
        render_prepare_meshes_system_id,
        render_interact_ui_system_id,
        render_queue_meshes_system_id,
        render_prepare_ui_system_id,
        render_queue_ui_system_id,
        render_draw_meshes_system_id,
    };
    var expected_index: usize = 0;
    for (state.schedule.batches) |batch| {
        try std.testing.expectEqual(runtime.SystemPhase.render, batch.phase);
        for (batch.systems) |system| {
            try std.testing.expect(expected_index < expected.len);
            try std.testing.expectEqualStrings(expected[expected_index], system.id);
            expected_index += 1;
        }
    }
    try std.testing.expectEqual(expected.len, expected_index);
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

    const canvas = try scene_world.createEntity("debug-canvas", "Debug Canvas");
    try scene_world.setUiCanvas(canvas);

    const panel = try scene_world.createEntity("debug-panel", "Debug Panel");
    try scene_world.setUiRect(panel, .{
        .position = .{ 24.0, 24.0, 0.0 },
        .size = .{ 180.0, 58.0, 0.0 },
        .color = .{ 0.02, 0.08, 0.16 },
    });
    try scene_world.setUiButton(panel);

    const label = try scene_world.createEntity("debug-label", "Debug Label");
    try scene_world.setUiText(label, .{
        .position = .{ 38.0, 42.0, 0.0 },
        .size = 2.0,
        .color = .{ 1.0, 0.68, 0.16 },
        .value = "UI READY",
    });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractScene(.{ .world = &scene_world });

    try std.testing.expectEqual(@as(usize, 8), state.world.entityCount());
    try std.testing.expectEqual(@as(usize, 2), state.world.renderableMeshCount());
    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.ui_canvas_component_id));
    try std.testing.expectEqual(@as(usize, 1), state.world.uiRectCount());
    try std.testing.expectEqual(@as(usize, 1), state.world.uiTextCount());
    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.input_pointer_component_id));
    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.input_keyboard_component_id));
    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.input_frame_component_id));
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

    const extracted_panel = state.world.uiRectAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expect(extracted_panel.is_button);
    const extracted_label = state.world.uiTextAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("UI READY", extracted_label.value);
    try state.queueUiDraw();
    try std.testing.expectEqual(@as(usize, 1), state.uiDrawCommandCount());
}

test "batch plan groups matching geometry and shadow state with per-instance color" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    try addBatchTestRenderable(&scene_world, "blue-box-a", "box", 0, 0, .{ -1.6, 0.0, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "gold-sphere", "uv_sphere", 16, 8, .{ 0.0, 0.0, 0.0 }, .{ 1.0, 0.56, 0.1 }, .{});
    try addBatchTestRenderable(&scene_world, "blue-box-b", "box", 0, 0, .{ 1.6, 0.0, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "red-box", "box", 0, 0, .{ 0.0, 1.2, 0.0 }, .{ 0.95, 0.12, 0.18 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "blue-box-receiver", "box", 0, 0, .{ 0.0, -1.2, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .receives_shadow = true });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractScene(.{ .world = &scene_world });

    var plan = try BatchPlan.build(std.testing.allocator, &state.world);
    defer plan.deinit();

    try std.testing.expectEqual(@as(usize, 3), plan.batches.len);
    try std.testing.expectEqual(geometry.Primitive.box, plan.batches[0].geometry_key.primitive);
    try std.testing.expect(plan.batches[0].shadow_key.casts_shadow);
    try std.testing.expect(!plan.batches[0].shadow_key.receives_shadow);
    try std.testing.expectEqual(@as(usize, 3), plan.batches[0].render_indices.len);
    try std.testing.expectEqual(@as(usize, 0), plan.batches[0].render_indices[0]);
    try std.testing.expectEqual(@as(usize, 2), plan.batches[0].render_indices[1]);
    try std.testing.expectEqual(@as(usize, 3), plan.batches[0].render_indices[2]);

    try std.testing.expectEqual(geometry.Primitive.uv_sphere, plan.batches[1].geometry_key.primitive);
    try std.testing.expectEqual(@as(usize, 1), plan.batches[1].render_indices.len);
    try std.testing.expectEqual(@as(usize, 1), plan.batches[1].render_indices[0]);

    try std.testing.expectEqual(geometry.Primitive.box, plan.batches[2].geometry_key.primitive);
    try std.testing.expect(!plan.batches[2].shadow_key.casts_shadow);
    try std.testing.expect(plan.batches[2].shadow_key.receives_shadow);
    try std.testing.expectEqual(@as(usize, 1), plan.batches[2].render_indices.len);
    try std.testing.expectEqual(@as(usize, 4), plan.batches[2].render_indices[0]);

    try state.queueBatchDraws(plan.batches.len);
    try std.testing.expectEqual(@as(usize, 3), state.drawCommandCount());
}

test "render stats reports mesh renderables and planned batches" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    try addBatchTestRenderable(&scene_world, "blue-box-a", "box", 0, 0, .{ -1.6, 0.0, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "gold-sphere", "uv_sphere", 16, 8, .{ 0.0, 0.0, 0.0 }, .{ 1.0, 0.56, 0.1 }, .{});
    try addBatchTestRenderable(&scene_world, "blue-box-b", "box", 0, 0, .{ 1.6, 0.0, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "red-box", "box", 0, 0, .{ 0.0, 1.2, 0.0 }, .{ 0.95, 0.12, 0.18 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "blue-box-receiver", "box", 0, 0, .{ 0.0, -1.2, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .receives_shadow = true });

    const result = try stats(std.testing.allocator, .{ .world = &scene_world });

    try std.testing.expectEqual(@as(usize, 5), result.renderables);
    try std.testing.expectEqual(@as(usize, 3), result.render_batches);
    try std.testing.expectEqual(@as(usize, 0), result.ui_rects);
    try std.testing.expectEqual(@as(usize, 0), result.ui_texts);
}

test "UI vertex builder expands rects and fixed pixel text" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const panel = try world.createEntity("panel", "Panel");
    try world.setUiRect(panel, .{
        .position = .{ 32.0, 24.0, 0.0 },
        .size = .{ 120.0, 48.0, 0.0 },
        .color = .{ 0.0, 0.2, 0.4 },
    });

    const label = try world.createEntity("label", "Label");
    try world.setUiText(label, .{
        .position = .{ 42.0, 36.0, 0.0 },
        .size = 2.0,
        .color = .{ 1.0, 0.8, 0.2 },
        .value = "UI 1",
    });

    var vertices = try buildUiVertices(std.testing.allocator, &world, 640, 480);
    defer vertices.deinit(std.testing.allocator);

    try std.testing.expect(vertices.items.len > 6);
    try std.testing.expectEqual(@as(f32, -0.9), vertices.items[0].position[0]);
    try std.testing.expect(vertices.items[0].position[1] > 0.8);
}

test "UI hit testing uses half-open screen rects" {
    const position = [3]f32{ 32.0, 24.0, 0.0 };
    const size = [3]f32{ 120.0, 48.0, 0.0 };

    try std.testing.expect(runtime.pointInsideUiRect(.{ 32.0, 24.0 }, position, size));
    try std.testing.expect(runtime.pointInsideUiRect(.{ 151.99, 71.99 }, position, size));
    try std.testing.expect(!runtime.pointInsideUiRect(.{ 152.0, 72.0 }, position, size));
    try std.testing.expect(!runtime.pointInsideUiRect(.{ 31.99, 24.0 }, position, size));
}

test "render ECS derives UI button interaction state from frame input" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const button = try scene_world.createEntity("button", "Button");
    try scene_world.setUiRect(button, .{
        .position = .{ 32.0, 24.0, 0.0 },
        .size = .{ 120.0, 48.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
    });
    try scene_world.setUiButton(button);

    const panel = try scene_world.createEntity("panel", "Panel");
    try scene_world.setUiRect(panel, .{
        .position = .{ 180.0, 24.0, 0.0 },
        .size = .{ 80.0, 48.0, 0.0 },
        .color = .{ 0.2, 0.2, 0.2 },
    });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();

    try state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .pointer = .{
            .position = .{ 48.0, 36.0 },
            .has_position = true,
            .primary_down = true,
        },
    });
    try state.updateUiInteractions();

    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(render_ui_button_state_component_id));
    const extracted_button = state.world.uiRectAt(0) orelse return error.TestExpectedEqual;
    const held_state = (try renderUiButtonState(&state.world, extracted_button.entity)) orelse return error.TestExpectedEqual;
    try std.testing.expect(held_state.hovered);
    try std.testing.expect(held_state.held);
    try std.testing.expect(!held_state.pressed);

    const extracted_panel = state.world.uiRectAt(1) orelse return error.TestExpectedEqual;
    try std.testing.expect((try renderUiButtonState(&state.world, extracted_panel.entity)) == null);

    try state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .pointer = .{
            .position = .{ 48.0, 36.0 },
            .has_position = true,
            .primary_released = true,
        },
    });
    try state.updateUiInteractions();

    const pressed_button = state.world.uiRectAt(0) orelse return error.TestExpectedEqual;
    const pressed_state = (try renderUiButtonState(&state.world, pressed_button.entity)) orelse return error.TestExpectedEqual;
    try std.testing.expect(pressed_state.hovered);
    try std.testing.expect(!pressed_state.held);
    try std.testing.expect(pressed_state.pressed);
}

test "hidden UI overlay skips UI extraction but keeps frame input" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const button = try scene_world.createEntity("button", "Button");
    try scene_world.setUiRect(button, .{
        .position = .{ 32.0, 24.0, 0.0 },
        .size = .{ 120.0, 48.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
    });
    try scene_world.setUiButton(button);

    const label = try scene_world.createEntity("label", "Label");
    try scene_world.setUiText(label, .{
        .position = .{ 42.0, 36.0, 0.0 },
        .size = 2.0,
        .color = .{ 1.0, 0.8, 0.2 },
        .value = "HIDDEN",
    });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractSceneWithInput(.{ .world = &scene_world }, .{ .ui_visible = false });
    try state.updateUiInteractions();

    try std.testing.expectEqual(@as(usize, 0), state.world.uiRectCount());
    try std.testing.expectEqual(@as(usize, 0), state.world.uiTextCount());
    try std.testing.expectEqual(@as(usize, 0), state.world.componentInstanceCountFor(render_ui_button_state_component_id));

    const input = try renderFrameInput(&state.world);
    try std.testing.expect(!input.ui_visible);
    try std.testing.expect(!input.debug_overlay_visible);
}

test "frame input round trips through ECS input components" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try writeFrameInput(&world, .{
        .pointer = .{
            .position = .{ 44.0, 55.0 },
            .has_position = true,
            .primary_down = true,
            .wheel_delta = .{ 0.0, -3.0 },
        },
        .keyboard = .{
            .ctrl_down = true,
            .editor_toggle_pressed = true,
        },
        .ui_visible = false,
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    });

    const input = try renderFrameInput(&world);
    try std.testing.expect(input.pointer.has_position);
    try std.testing.expectEqual(@as(f32, 44.0), input.pointer.position[0]);
    try std.testing.expectEqual(@as(f32, -3.0), input.pointer.wheel_delta[1]);
    try std.testing.expect(input.keyboard.ctrl_down);
    try std.testing.expect(input.keyboard.editor_toggle_pressed);
    try std.testing.expect(!input.ui_visible);
    try std.testing.expect(input.debug_overlay_visible);
    try std.testing.expectEqual(@as(f32, 1280.0), input.viewport_width);
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(runtime.input_pointer_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(runtime.input_keyboard_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(runtime.input_frame_component_id));
}

test "ctrl-tab debug overlay toggle updates editor visibility only" {
    var input = FrameInput{ .debug_overlay_visible = true };

    toggleDebugOverlay(&input);
    try std.testing.expect(!input.debug_overlay_visible);
    try std.testing.expect(input.ui_visible);
    try std.testing.expect(input.keyboard.editor_toggle_pressed);

    input.beginFrame();
    try std.testing.expect(!input.keyboard.editor_toggle_pressed);

    toggleDebugOverlay(&input);
    try std.testing.expect(input.debug_overlay_visible);
    try std.testing.expect(input.ui_visible);
    try std.testing.expect(input.keyboard.editor_toggle_pressed);

    try std.testing.expect(isEditorToggleShortcut(sdl.SDLK_TAB, sdl.SDL_KMOD_CTRL));
    try std.testing.expect(isEditorToggleShortcut(sdl.SDLK_TAB, sdl.SDL_KMOD_LCTRL));
    try std.testing.expect(!isEditorToggleShortcut(sdl.SDLK_TAB, sdl.SDL_KMOD_NONE));
    try std.testing.expect(!isEditorToggleShortcut(sdl.SDLK_F1, sdl.SDL_KMOD_NONE));
}

test "debug overlay extracts FPS label when visible" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .ui_visible = false,
        .debug_overlay_visible = true,
        .fps = 59.6,
    });

    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.ui_canvas_component_id));
    try std.testing.expectEqual(@as(usize, 6), state.world.uiRectCount());
    try std.testing.expectEqual(@as(usize, 8), state.world.uiTextCount());

    const label = state.world.uiTextAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("FPS 60", label.value);

    const input = try renderFrameInput(&state.world);
    try std.testing.expect(!input.ui_visible);
    try std.testing.expect(input.debug_overlay_visible);

    try state.queueUiDraw();
    try std.testing.expectEqual(@as(usize, 1), state.uiDrawCommandCount());
}

test "debug overlay extracts system profile rows when available" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{
            .id = "spawn_initial",
            .phase = .startup,
            .sample_count = 0,
            .window_size = 120,
            .last_ns = 0,
            .rolling_average_ns = 0,
        },
        .{
            .id = "rotate_cubes",
            .phase = .update,
            .sample_count = 3,
            .window_size = 120,
            .last_ns = 123_400,
            .rolling_average_ns = 56_700,
        },
    };

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .debug_overlay_visible = true,
        .fps = 60.0,
        .system_profiles = &profiles,
    });

    try std.testing.expectEqual(@as(usize, 6), state.world.uiRectCount());
    try std.testing.expectEqual(@as(usize, 11), state.world.uiTextCount());

    var saw_header = false;
    var saw_startup = false;
    var saw_update = false;
    var saw_pause = false;
    var saw_no_selection = false;
    var texts = state.world.uiTexts();
    while (texts.next()) |text| {
        try std.testing.expect(text.size >= 1.0);
        if (std.mem.indexOf(u8, text.value, "SYS 2 AVG 120F SNAP 3HZ") != null) {
            saw_header = true;
        }
        if (std.mem.indexOf(u8, text.value, "STA spawn_initial A-- L--") != null) {
            saw_startup = true;
        }
        if (std.mem.indexOf(u8, text.value, "UPD rotate_cubes A57U L123U") != null) {
            saw_update = true;
        }
        if (std.mem.indexOf(u8, text.value, "PAUSE") != null) {
            saw_pause = true;
        }
        if (std.mem.indexOf(u8, text.value, "NO ENTITY SELECTED") != null) {
            saw_no_selection = true;
        }
    }

    try std.testing.expect(saw_header);
    try std.testing.expect(saw_startup);
    try std.testing.expect(saw_update);
    try std.testing.expect(saw_pause);
    try std.testing.expect(saw_no_selection);
}

test "debug overlay renders a scrolled system profile window" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{ .id = "system.zero", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1_000, .rolling_average_ns = 1_000 },
        .{ .id = "system.one", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 2_000, .rolling_average_ns = 2_000 },
        .{ .id = "system.two", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 3_000, .rolling_average_ns = 3_000 },
        .{ .id = "system.three", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 4_000, .rolling_average_ns = 4_000 },
        .{ .id = "system.four", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 5_000, .rolling_average_ns = 5_000 },
        .{ .id = "system.five", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 6_000, .rolling_average_ns = 6_000 },
        .{ .id = "system.six", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 7_000, .rolling_average_ns = 7_000 },
        .{ .id = "system.seven", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 8_000, .rolling_average_ns = 8_000 },
        .{ .id = "system.eight", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 9_000, .rolling_average_ns = 9_000 },
    };

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .debug_overlay_visible = true,
        .fps = 60.0,
        .system_profiles = &profiles,
        .editor = .{ .system_scroll_offset = 2 },
    });

    var saw_zero = false;
    var saw_two = false;
    var saw_eight = false;
    var saw_footer = false;
    var texts = state.world.uiTexts();
    while (texts.next()) |text| {
        if (std.mem.indexOf(u8, text.value, "system.zero") != null) {
            saw_zero = true;
        }
        if (std.mem.indexOf(u8, text.value, "system.two") != null) {
            saw_two = true;
        }
        if (std.mem.indexOf(u8, text.value, "system.eight") != null) {
            saw_eight = true;
        }
        if (std.mem.indexOf(u8, text.value, "ROWS 3-9/9  WHEEL") != null) {
            saw_footer = true;
        }
        try std.testing.expect(text.value.len <= 36 or std.mem.indexOf(u8, text.value, "NO ENTITY SELECTED") != null);
    }

    try std.testing.expect(!saw_zero);
    try std.testing.expect(saw_two);
    try std.testing.expect(saw_eight);
    try std.testing.expect(saw_footer);
}

test "editor overlay extracts selected entity inspector and translate gizmo" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const entity = try scene_world.createEntity("selected", "Selected Box");
    try scene_world.setTransform(entity, .{ .position = .{ 0.25, 0.5, 0.0 } });
    try scene_world.setCubeRenderer(entity, .{ .color = .{ 0.8, 0.4, 0.2 } });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .debug_overlay_visible = true,
        .viewport_width = 960.0,
        .viewport_height = 540.0,
        .editor = .{
            .selected_entity = entity,
            .entity_count = scene_world.entityCount(),
            .component_instance_count = scene_world.componentInstanceCount(),
            .renderable_count = scene_world.renderableMeshCount(),
        },
    });

    try std.testing.expectEqual(@as(usize, 4), state.world.renderableMeshCount());
    try std.testing.expectEqual(@as(usize, 6), state.world.uiRectCount());

    var saw_handle = false;
    var saw_transform = false;
    var texts = state.world.uiTexts();
    while (texts.next()) |text| {
        if (std.mem.indexOf(u8, text.value, "HANDLE") != null) {
            saw_handle = true;
        }
        if (std.mem.indexOf(u8, text.value, "[machina.transform]") != null) {
            saw_transform = true;
        }
    }
    try std.testing.expect(saw_handle);
    try std.testing.expect(saw_transform);
}

test "render ECS profiles internal systems for editor overlay" {
    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();

    const initial_profiles = state.systemProfileSnapshots();
    try std.testing.expectEqual(@as(usize, 7), initial_profiles.len);
    try std.testing.expectEqualStrings(render_extract_system_id, initial_profiles[0].id);
    try std.testing.expectEqual(runtime.SystemPhase.render, initial_profiles[0].phase);
    try std.testing.expectEqual(@as(u32, 0), initial_profiles[0].sample_count);
    try std.testing.expectEqual(@as(u32, render_system_profile_window_frames), initial_profiles[0].window_size);

    const first_batch = state.schedule.batches[0];
    state.recordSystemDuration(first_batch.systems[0], first_batch.phase, 12_300);

    const recorded_profiles = state.systemProfileSnapshots();
    try std.testing.expectEqual(@as(u32, 1), recorded_profiles[0].sample_count);
    try std.testing.expectEqual(@as(u64, 12_300), recorded_profiles[0].last_ns);
    try std.testing.expectEqual(@as(u64, 12_300), recorded_profiles[0].rolling_average_ns);
}

test "editor profile input combines project and engine system rows" {
    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();

    const project_profiles = [_]runtime.SystemProfileSnapshot{
        .{
            .id = "game.update",
            .phase = .update,
            .sample_count = 2,
            .window_size = 120,
            .last_ns = 1_000,
            .rolling_average_ns = 900,
        },
    };

    const combined = try state.combineSystemProfileSnapshots(project_profiles[0..]);
    try std.testing.expectEqual(project_profiles.len + state.system_profiles.items.len, combined.len);
    try std.testing.expectEqualStrings("game.update", combined[0].id);
    try std.testing.expectEqualStrings(render_extract_system_id, combined[1].id);
    try std.testing.expectEqual(runtime.SystemPhase.render, combined[1].phase);
}

test "editor profile display snapshots are copied and throttled" {
    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();

    const first_project_profiles = [_]runtime.SystemProfileSnapshot{
        .{
            .id = "game.fast",
            .phase = .update,
            .sample_count = 1,
            .window_size = 120,
            .last_ns = 1_000,
            .rolling_average_ns = 1_000,
        },
    };
    const first = try state.combineSystemProfileSnapshots(first_project_profiles[0..]);
    try std.testing.expectEqualStrings("game.fast", first[0].id);
    try std.testing.expect(first[0].id.ptr != first_project_profiles[0].id.ptr);
    try std.testing.expectEqual(@as(u64, 1_000), first[0].last_ns);

    const second_project_profiles = [_]runtime.SystemProfileSnapshot{
        .{
            .id = "game.slow",
            .phase = .update,
            .sample_count = 1,
            .window_size = 120,
            .last_ns = 9_000,
            .rolling_average_ns = 9_000,
        },
    };
    const throttled = try state.combineSystemProfileSnapshots(second_project_profiles[0..]);
    try std.testing.expectEqualStrings("game.fast", throttled[0].id);
    try std.testing.expectEqual(@as(u64, 1_000), throttled[0].last_ns);

    state.last_display_system_profile_update_ns -= @as(i128, editor_performance_display_interval_ns);
    const refreshed = try state.combineSystemProfileSnapshots(second_project_profiles[0..]);
    try std.testing.expectEqualStrings("game.slow", refreshed[0].id);
    try std.testing.expectEqual(@as(u64, 9_000), refreshed[0].last_ns);
}

test "UI vertex builder reflects button interaction state" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const button = try world.createEntity("button", "Button");
    try world.setUiRect(button, .{
        .position = .{ 32.0, 24.0, 0.0 },
        .size = .{ 120.0, 48.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
    });
    try world.setUiButton(button);
    try setRenderUiButtonState(&world, button, .{ .hovered = true });

    var hovered_vertices = try buildUiVertices(std.testing.allocator, &world, 640, 480);
    defer hovered_vertices.deinit(std.testing.allocator);
    try std.testing.expectApproxEqAbs(@as(f32, 0.112), hovered_vertices.items[0].color[0], 0.001);

    try setRenderUiButtonState(&world, button, .{ .held = true });
    var held_vertices = try buildUiVertices(std.testing.allocator, &world, 640, 480);
    defer held_vertices.deinit(std.testing.allocator);
    try std.testing.expect(held_vertices.items[6].color[0] < held_vertices.items[12].color[0]);
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

fn buildUiVertices(allocator: std.mem.Allocator, world: *const runtime.World, width: u32, height: u32) RenderError!std.ArrayList(UiVertex) {
    if (width == 0 or height == 0) {
        return RenderError.InvalidScene;
    }

    var vertices: std.ArrayList(UiVertex) = .empty;
    errdefer vertices.deinit(allocator);

    var rects = world.uiRects();
    while (rects.next()) |rect| {
        const maybe_button_state = if (rect.is_button) try renderUiButtonState(world, rect.entity) else null;
        var rect_color = rect.color;
        if (maybe_button_state) |state| {
            if (state.held) {
                rect_color = scaleColor(rect.color, 0.82);
            } else if (state.pressed) {
                rect_color = scaleColor(rect.color, 1.18);
            } else if (state.hovered) {
                rect_color = scaleColor(rect.color, 1.12);
            }
        }

        try appendUiRect(&vertices, allocator, width, height, rect.position, rect.size, rect_color);
        if (rect.is_button) {
            var top_color = scaleColor(rect_color, 1.35);
            var bottom_color = scaleColor(rect_color, 0.65);
            if (maybe_button_state) |state| {
                if (state.held) {
                    top_color = scaleColor(rect_color, 0.65);
                    bottom_color = scaleColor(rect_color, 1.35);
                }
            }

            try appendUiRect(&vertices, allocator, width, height, rect.position, .{ rect.size[0], @min(2.0, rect.size[1]), 0.0 }, top_color);
            try appendUiRect(
                &vertices,
                allocator,
                width,
                height,
                .{ rect.position[0], rect.position[1] + @max(rect.size[1] - 2.0, 0.0), rect.position[2] },
                .{ rect.size[0], @min(2.0, rect.size[1]), 0.0 },
                bottom_color,
            );
        }
    }

    var texts = world.uiTexts();
    while (texts.next()) |text| {
        try appendUiText(&vertices, allocator, width, height, text);
    }

    return vertices;
}

fn appendUiText(
    vertices: *std.ArrayList(UiVertex),
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    text: runtime.UiText,
) RenderError!void {
    if (!isFiniteVec3(text.position) or
        !std.math.isFinite(text.size) or
        text.size <= 0.0 or
        !isFiniteVec3(text.color))
    {
        return RenderError.InvalidScene;
    }

    const origin_x = text.position[0];
    var cursor_x = origin_x;
    var cursor_y = text.position[1];
    for (text.value) |byte| {
        if (byte == '\n') {
            cursor_x = origin_x;
            cursor_y += text.size * @as(f32, @floatFromInt(ui_font.height));
            continue;
        }
        try appendGlyph(vertices, allocator, width, height, cursor_x, cursor_y, text.size, text.color, byte);
        cursor_x += text.size * @as(f32, @floatFromInt(ui_font.advance));
    }
}

fn appendGlyph(
    vertices: *std.ArrayList(UiVertex),
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    x: f32,
    y: f32,
    size: f32,
    color: [3]f32,
    byte: u8,
) RenderError!void {
    const rows = ui_font.glyphRows(byte);
    for (rows, 0..) |row_bits, row| {
        for (0..ui_font.width) |column| {
            const bit: ui_font.BitShift = @intCast(ui_font.width - 1 - column);
            if ((row_bits & (@as(ui_font.Row, 1) << bit)) == 0) {
                continue;
            }
            try appendUiRect(
                vertices,
                allocator,
                width,
                height,
                .{ x + @as(f32, @floatFromInt(column)) * size, y + @as(f32, @floatFromInt(row)) * size, 0.0 },
                .{ size, size, 0.0 },
                color,
            );
        }
    }
}

fn appendUiRect(
    vertices: *std.ArrayList(UiVertex),
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    position: [3]f32,
    size: [3]f32,
    color: [3]f32,
) RenderError!void {
    if (!isFiniteVec3(position) or !isFiniteVec3(size) or !isFiniteVec3(color) or size[0] <= 0.0 or size[1] <= 0.0) {
        return RenderError.InvalidScene;
    }

    const left = screenToClipX(position[0], width);
    const right = screenToClipX(position[0] + size[0], width);
    const top = screenToClipY(position[1], height);
    const bottom = screenToClipY(position[1] + size[1], height);
    const vertex_color = [4]f32{ clamp01(color[0]), clamp01(color[1]), clamp01(color[2]), 1.0 };

    const quad = [_]UiVertex{
        .{ .position = .{ left, top }, .color = vertex_color },
        .{ .position = .{ right, top }, .color = vertex_color },
        .{ .position = .{ right, bottom }, .color = vertex_color },
        .{ .position = .{ left, top }, .color = vertex_color },
        .{ .position = .{ right, bottom }, .color = vertex_color },
        .{ .position = .{ left, bottom }, .color = vertex_color },
    };
    try vertices.appendSlice(allocator, &quad);
}

fn screenToClipX(value: f32, width: u32) f32 {
    return (value / @as(f32, @floatFromInt(width))) * 2.0 - 1.0;
}

fn screenToClipY(value: f32, height: u32) f32 {
    return 1.0 - (value / @as(f32, @floatFromInt(height))) * 2.0;
}

fn scaleColor(color: [3]f32, scale: f32) [3]f32 {
    return .{
        clamp01(color[0] * scale),
        clamp01(color[1] * scale),
        clamp01(color[2] * scale),
    };
}

fn clamp01(value: f32) f32 {
    return @min(@max(value, 0.0), 1.0);
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

const UiVertex = extern struct {
    position: [2]f32,
    color: [4]f32,
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
