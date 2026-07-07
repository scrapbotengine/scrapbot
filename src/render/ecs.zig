const std = @import("std");
const runtime = @import("../runtime.zig");
const editor_gizmo = @import("../editor/gizmo.zig");
const editor_metrics = @import("../editor/metrics.zig");
const editor_theme = @import("../editor/theme.zig");
const render_input = @import("input.zig");
const render_editor_extract = @import("editor/extract.zig");
const render_types = @import("types.zig");
const render_ui = @import("ui.zig");

const FrameInput = render_input.FrameInput;
const RenderError = render_types.RenderError;
const UiCanvasTransform = render_ui.UiCanvasTransform;
const extractDebugOverlayInto = render_editor_extract.extractDebugOverlayInto;
const monotonicTimestampNs = render_editor_extract.monotonicTimestampNs;
const setRenderFrameInput = render_ui.setRenderFrameInput;
const renderFrameInput = render_ui.renderFrameInput;
const setRenderUiButtonState = render_ui.setRenderUiButtonState;
const resolveUiLayout = render_ui.resolveUiLayout;
const sceneUiCanvasTransform = render_ui.sceneUiCanvasTransform;
const isEditorUiEntityId = render_ui.isEditorUiEntityId;
const applyUiCanvasLayout = render_ui.applyUiCanvasLayout;
const scaleUiSize = render_ui.scaleUiSize;
const resolveUiScreenLayout = render_ui.resolveUiScreenLayout;
const evaluateUiButtonState = render_ui.evaluateUiButtonState;
const render_ui_button_state_component_id = render_ui.render_ui_button_state_component_id;
const render_ui_clip_component_id = render_ui.render_ui_clip_component_id;

pub const editor_performance_display_interval_ns = editor_metrics.editor_performance_display_interval_ns;
pub const render_system_profile_window_frames = editor_metrics.render_system_profile_window_frames;
pub const render_draw_batch_component_id = "scrapbot.render.internal.draw.batch";
const render_draw_ui_component_id = "scrapbot.render.internal.draw.ui";
pub const render_extract_system_id = "scrapbot.render.extract";
pub const render_prepare_meshes_system_id = "scrapbot.render.prepare_meshes";
pub const render_queue_meshes_system_id = "scrapbot.render.queue_meshes";
pub const render_interact_ui_system_id = "scrapbot.render.interact_ui";
pub const render_prepare_ui_system_id = "scrapbot.render.prepare_ui";
pub const render_queue_ui_system_id = "scrapbot.render.queue_ui";
pub const render_draw_meshes_system_id = "scrapbot.render.draw_meshes";
const editor_palette = editor_theme.palette;

pub const Scene = struct {
    world: *runtime.World,
};

const RenderSystemProfileState = struct {
    id: []const u8,
    phase: runtime.SystemPhase,
    samples_ns: [render_system_profile_window_frames]u64 = [_]u64{0} ** render_system_profile_window_frames,
    sample_count: usize = 0,
    next_sample: usize = 0,
    total_ns: u64 = 0,
    last_ns: u64 = 0,

    pub fn deinit(self: *RenderSystemProfileState, allocator: std.mem.Allocator) void {
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

    fn reset(self: *RenderSystemProfileState) void {
        self.samples_ns = [_]u64{0} ** render_system_profile_window_frames;
        self.sample_count = 0;
        self.next_sample = 0;
        self.total_ns = 0;
        self.last_ns = 0;
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

fn showProfileInLivePerformancePanel(profile: runtime.SystemProfileSnapshot) bool {
    return profile.phase != .startup;
}

pub const RenderEcsState = struct {
    allocator: std.mem.Allocator,
    registry: runtime.ComponentRegistry,
    schedule: runtime.SystemSchedule,
    world: *runtime.World = undefined,
    extracted_renderables: std.ArrayList(runtime.RenderableMesh) = .empty,
    scratch_renderables: std.ArrayList(runtime.RenderableMesh) = .empty,
    ui_draw_queued: bool = false,
    system_profiles: std.ArrayList(RenderSystemProfileState) = .empty,
    system_profile_snapshots: std.ArrayList(runtime.SystemProfileSnapshot) = .empty,
    combined_system_profile_snapshots: std.ArrayList(runtime.SystemProfileSnapshot) = .empty,
    display_system_profile_snapshots: std.ArrayList(runtime.SystemProfileSnapshot) = .empty,
    display_system_profile_ids: std.ArrayList([]u8) = .empty,
    last_display_system_profile_update_ns: i128 = 0,

    pub fn init(allocator: std.mem.Allocator) RenderError!RenderEcsState {
        var registry = runtime.ComponentRegistry.init(allocator);
        errdefer registry.deinit();

        registerRenderEcsTypes(&registry) catch |err| return mapEngineSetupError(err);

        var schedule = registry.buildSchedule(allocator, .render) catch |err| return mapEngineSetupError(err);
        errdefer schedule.deinit();

        var state = RenderEcsState{
            .allocator = allocator,
            .registry = registry,
            .schedule = schedule,
        };
        errdefer state.deinit();
        try state.initializeSystemProfiles();
        return state;
    }

    pub fn deinit(self: *RenderEcsState) void {
        self.clearDisplaySystemProfileSnapshots();
        self.display_system_profile_ids.deinit(self.allocator);
        self.display_system_profile_snapshots.deinit(self.allocator);
        self.combined_system_profile_snapshots.deinit(self.allocator);
        self.system_profile_snapshots.deinit(self.allocator);
        self.clearSystemProfiles();
        self.system_profiles.deinit(self.allocator);
        self.scratch_renderables.deinit(self.allocator);
        self.extracted_renderables.deinit(self.allocator);
        self.schedule.deinit();
        self.registry.deinit();
        self.* = undefined;
    }

    pub fn systemProfileSnapshots(self: *RenderEcsState) []const runtime.SystemProfileSnapshot {
        self.system_profile_snapshots.clearRetainingCapacity();
        for (self.system_profiles.items) |profile| {
            self.system_profile_snapshots.appendAssumeCapacity(profile.snapshot());
        }
        return self.system_profile_snapshots.items;
    }

    pub fn combineSystemProfileSnapshots(
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
            if (!showProfileInLivePerformancePanel(profile)) {
                continue;
            }
            try self.appendDisplaySystemProfileSnapshot(profile);
        }
        for (render_profiles) |profile| {
            if (!showProfileInLivePerformancePanel(profile)) {
                continue;
            }
            try self.appendDisplaySystemProfileSnapshot(profile);
        }
    }

    pub fn appendDisplaySystemProfileSnapshot(self: *RenderEcsState, profile: runtime.SystemProfileSnapshot) RenderError!void {
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

    pub fn clearDisplaySystemProfileSnapshots(self: *RenderEcsState) void {
        for (self.display_system_profile_ids.items) |id| {
            self.allocator.free(id);
        }
        self.display_system_profile_ids.clearRetainingCapacity();
        self.display_system_profile_snapshots.clearRetainingCapacity();
        self.combined_system_profile_snapshots.clearRetainingCapacity();
    }

    pub fn initializeSystemProfiles(self: *RenderEcsState) RenderError!void {
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

    pub fn clearSystemProfiles(self: *RenderEcsState) void {
        for (self.system_profiles.items) |*profile| {
            profile.deinit(self.allocator);
        }
        self.system_profiles.clearRetainingCapacity();
    }

    pub fn recordSystemDuration(self: *RenderEcsState, system: runtime.ScheduledSystem, phase: runtime.SystemPhase, duration_ns: u64) void {
        for (self.system_profiles.items) |*profile| {
            if (profile.phase == phase and std.mem.eql(u8, profile.id, system.id)) {
                profile.record(duration_ns);
                return;
            }
        }
    }

    pub fn resetSystemProfileSamples(self: *RenderEcsState) void {
        for (self.system_profiles.items) |*profile| {
            profile.reset();
        }
    }

    pub fn extractScene(self: *RenderEcsState, scene: Scene) RenderError!void {
        try self.extractSceneWithInput(scene, .{});
    }

    pub fn extractSceneWithInput(self: *RenderEcsState, scene: Scene, input: FrameInput) RenderError!void {
        self.world = scene.world;
        self.scratch_renderables.clearRetainingCapacity();
        self.ui_draw_queued = false;
        try self.beginFrameState(scene.world);
        errdefer self.clearFrameState(scene.world) catch {};

        setRenderFrameInput(scene.world, input) catch |err| {
            std.log.err("render extract failed while setting frame input: {s}", .{@errorName(err)});
            return err;
        };

        var meshes = scene.world.renderableMeshes();
        while (meshes.next()) |mesh| {
            const entity = scene.world.entity(mesh.entity) catch continue;
            if (entity.provenance == .engine_transient) {
                continue;
            }
            self.scratch_renderables.append(self.allocator, mesh) catch return RenderError.OutOfMemory;
        }

        if (input.debug_overlay_visible) {
            extractEditorGizmoInto(self.allocator, scene.world, scene.world, input) catch |err| {
                std.log.err("render extract failed while extracting editor gizmo: {s}", .{@errorName(err)});
                return err;
            };
            self.appendExtractedEditorGizmoMeshes(input.editor.selected_entity) catch |err| {
                std.log.err("render extract failed while snapshotting editor gizmo: {s}", .{@errorName(err)});
                return err;
            };
        }

        if (input.debug_overlay_visible) {
            extractDebugOverlayInto(self.allocator, scene.world, input, scene.world) catch |err| {
                std.log.err("render extract failed while extracting editor overlay: {s}", .{@errorName(err)});
                return err;
            };
        }

        std.mem.swap(std.ArrayList(runtime.RenderableMesh), &self.extracted_renderables, &self.scratch_renderables);
        try self.finishFrameState(scene.world);
    }

    pub fn extractedRenderableMeshes(self: *const RenderEcsState) []const runtime.RenderableMesh {
        return self.extracted_renderables.items;
    }

    pub fn beginFrameState(self: *RenderEcsState, world: *runtime.World) RenderError!void {
        _ = self;
        world.beginEngineTransientFrame();
        world.removeAllComponentsSilently(render_draw_batch_component_id) catch |err| return mapWorldError(err);
        world.removeAllComponentsSilently(render_draw_ui_component_id) catch |err| return mapWorldError(err);
    }

    pub fn finishFrameState(self: *RenderEcsState, world: *runtime.World) RenderError!void {
        _ = self;
        world.clearUnusedEngineTransientEntities() catch |err| return mapWorldError(err);
    }

    pub fn clearFrameState(self: *RenderEcsState, world: *runtime.World) RenderError!void {
        _ = self;
        world.removeAllComponentsSilently(render_ui_button_state_component_id) catch |err| return mapWorldError(err);
        world.removeAllComponentsSilently(render_ui_clip_component_id) catch |err| return mapWorldError(err);
        world.removeAllComponentsSilently(render_draw_batch_component_id) catch |err| return mapWorldError(err);
        world.removeAllComponentsSilently(render_draw_ui_component_id) catch |err| return mapWorldError(err);
        world.clearEngineTransientEntities() catch |err| return mapWorldError(err);
    }

    fn appendExtractedEditorGizmoMeshes(self: *RenderEcsState, selected_entity: ?runtime.EntityHandle) RenderError!void {
        const selected = selected_entity orelse return;
        _ = (self.world.getTransform(selected) catch return) orelse return;
        for (editor_gizmo.translate_entity_ids) |entity_id| {
            const entity = self.world.findEntityById(entity_id) orelse continue;
            const mesh = self.world.renderableMeshForEntity(entity) orelse continue;
            self.scratch_renderables.append(self.allocator, mesh) catch return RenderError.OutOfMemory;
        }
    }

    pub fn updateUiInteractions(self: *RenderEcsState) RenderError!void {
        const input = try renderFrameInput(self.world);
        if (!input.ui_visible) {
            return;
        }

        var cursor: usize = 0;
        const button_query = [_][]const u8{
            runtime.ui_rect_component_id,
            runtime.ui_button_component_id,
        };
        while (self.world.queryNext(&button_query, &cursor)) |entity| {
            const stored_entity = self.world.entity(entity) catch |err| return mapWorldError(err);
            const position = self.world.getVec3(entity, runtime.ui_rect_component_id, "position") catch |err| return mapWorldError(err);
            const size = self.world.getVec3(entity, runtime.ui_rect_component_id, "size") catch |err| return mapWorldError(err);
            const layout = try resolveUiLayout(self.world, entity, position);
            const canvas_transform = if (input.viewport_width > 0.0 and input.viewport_height > 0.0)
                try sceneUiCanvasTransform(self.world, input, input.viewport_width, input.viewport_height)
            else
                UiCanvasTransform{};
            const canvas_layout = applyUiCanvasLayout(canvas_transform, stored_entity.id, layout);
            const screen_size = if (isEditorUiEntityId(stored_entity.id)) size else scaleUiSize(canvas_transform, size);
            const screen_layout = try resolveUiScreenLayout(input, stored_entity.id, canvas_layout, screen_size);
            var interaction_position = screen_layout.position;
            var interaction_size = screen_size;
            var interaction_clip = screen_layout.clip;
            if (self.world.hasComponent(entity, runtime.ui_hit_area_component_id) catch |err| return mapWorldError(err)) {
                const hit_position = self.world.getVec3(entity, runtime.ui_hit_area_component_id, "position") catch |err| return mapWorldError(err);
                const hit_size = self.world.getVec3(entity, runtime.ui_hit_area_component_id, "size") catch |err| return mapWorldError(err);
                const hit_layout = try resolveUiLayout(self.world, entity, hit_position);
                const hit_canvas_layout = applyUiCanvasLayout(canvas_transform, stored_entity.id, hit_layout);
                const hit_screen_size = if (isEditorUiEntityId(stored_entity.id)) hit_size else scaleUiSize(canvas_transform, hit_size);
                const hit_screen_layout = try resolveUiScreenLayout(input, stored_entity.id, hit_canvas_layout, hit_screen_size);
                interaction_position = hit_screen_layout.position;
                interaction_size = hit_screen_size;
                interaction_clip = hit_screen_layout.clip;
            }
            const state = evaluateUiButtonState(input, interaction_position, interaction_size, interaction_clip);
            try setRenderUiButtonState(self.world, entity, state);
        }
    }

    pub fn queueBatchDraws(self: *RenderEcsState, batch_count: usize) RenderError!void {
        for (0..batch_count) |batch_index| {
            if (batch_index > std.math.maxInt(i32)) {
                return RenderError.InvalidScene;
            }
            const entity_id = std.fmt.allocPrint(self.allocator, "scrapbot.render.draw.batch.{d}", .{batch_index}) catch return RenderError.OutOfMemory;
            defer self.allocator.free(entity_id);

            const entity = self.world.createEngineTransientEntity(entity_id, "Batch Draw") catch |err| return mapWorldError(err);
            const fields = [_]runtime.ComponentFieldValue{
                .{ .name = "batch_index", .value = .{ .int = @intCast(batch_index) } },
            };
            self.world.setComponentSilently(entity, render_draw_batch_component_id, &fields) catch |err| return mapWorldError(err);
        }
    }

    pub fn queueUiDraw(self: *RenderEcsState) RenderError!void {
        const input = try renderFrameInput(self.world);
        self.ui_draw_queued = hasDrawableUi(self.world, input);
    }

    pub fn drawCommandCount(self: RenderEcsState) usize {
        return self.world.componentInstanceCountFor(render_draw_batch_component_id);
    }

    pub fn uiDrawCommandCount(self: RenderEcsState) usize {
        return @intFromBool(self.ui_draw_queued);
    }

    pub fn drawCommandBatchIndex(self: RenderEcsState, entity: runtime.EntityHandle) RenderError!usize {
        return batchIndexFromDrawEntity(self.world, entity);
    }
};

fn hasDrawableUi(world: *const runtime.World, input: FrameInput) bool {
    var rects = world.uiRects();
    while (rects.next()) |rect| {
        if (shouldQueueUiEntity(input, rect.id)) {
            return true;
        }
    }
    var separators = world.uiSeparators();
    while (separators.next()) |separator| {
        if (shouldQueueUiEntity(input, separator.id)) {
            return true;
        }
    }
    var texts = world.uiTexts();
    while (texts.next()) |text| {
        if (shouldQueueUiEntity(input, text.id)) {
            return true;
        }
    }
    return false;
}

fn shouldQueueUiEntity(input: FrameInput, entity_id: []const u8) bool {
    if (isEditorUiEntityId(entity_id)) {
        return input.debug_overlay_visible;
    }
    return input.ui_visible;
}

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
    const ui_clip_fields = [_]runtime.ComponentFieldDefinition{
        .{ .name = "position", .value_type = .vec3 },
        .{ .name = "size", .value_type = .vec3 },
    };
    try registry.registerEngineComponent(.{
        .id = render_ui_clip_component_id,
        .version = 1,
        .fields = &ui_clip_fields,
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
        runtime.renderer_component_id,
        runtime.camera_component_id,
        runtime.directional_light_component_id,
        runtime.shadow_caster_component_id,
        runtime.shadow_receiver_component_id,
        runtime.ui_canvas_component_id,
        runtime.ui_rect_component_id,
        runtime.ui_border_component_id,
        runtime.ui_text_component_id,
        runtime.ui_button_component_id,
        runtime.ui_command_component_id,
        runtime.ui_scroll_view_component_id,
        runtime.ui_vgroup_component_id,
        runtime.ui_hgroup_component_id,
        runtime.ui_table_component_id,
        runtime.ui_stack_component_id,
        runtime.ui_layout_item_component_id,
        runtime.ui_spacer_component_id,
        runtime.ui_text_block_component_id,
        runtime.ui_toggle_component_id,
        runtime.ui_progress_bar_component_id,
        runtime.ui_separator_component_id,
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
        runtime.ui_scroll_view_component_id,
        runtime.ui_vgroup_component_id,
        runtime.ui_hgroup_component_id,
        runtime.ui_table_component_id,
        runtime.ui_stack_component_id,
        runtime.ui_layout_item_component_id,
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
        runtime.ui_border_component_id,
        runtime.ui_text_component_id,
        runtime.ui_button_component_id,
        runtime.ui_scroll_view_component_id,
        runtime.ui_vgroup_component_id,
        runtime.ui_hgroup_component_id,
        runtime.ui_table_component_id,
        runtime.ui_stack_component_id,
        runtime.ui_layout_item_component_id,
        runtime.ui_spacer_component_id,
        runtime.ui_text_block_component_id,
        runtime.ui_toggle_component_id,
        runtime.ui_progress_bar_component_id,
        runtime.ui_separator_component_id,
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
        runtime.ui_border_component_id,
        runtime.ui_text_component_id,
        runtime.ui_separator_component_id,
        runtime.ui_progress_bar_component_id,
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
        runtime.renderer_component_id,
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
        runtime.ui_scroll_view_component_id,
        runtime.ui_vgroup_component_id,
        runtime.ui_hgroup_component_id,
        runtime.ui_table_component_id,
        runtime.ui_stack_component_id,
        runtime.ui_layout_item_component_id,
        runtime.ui_spacer_component_id,
        runtime.ui_text_block_component_id,
        runtime.ui_toggle_component_id,
        runtime.ui_progress_bar_component_id,
        runtime.ui_separator_component_id,
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

fn extractEditorGizmoInto(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    scene_world: *const runtime.World,
    input: FrameInput,
) RenderError!void {
    editor_gizmo.extractTranslateInto(
        allocator,
        world,
        scene_world,
        input.editor.selected_entity,
        input.editor.dragging_axis,
        .{
            .danger = editor_palette.danger,
            .success = editor_palette.success,
            .primary = editor_palette.primary,
            .accent_soft = editor_palette.accent_soft,
        },
    ) catch |err| return mapEditorGizmoError(err);
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

pub fn mapWorldError(err: anyerror) RenderError {
    return switch (err) {
        error.OutOfMemory => RenderError.OutOfMemory,
        else => RenderError.InvalidScene,
    };
}

fn mapLayoutError(err: anyerror) RenderError {
    return switch (err) {
        error.OutOfMemory => RenderError.OutOfMemory,
        else => RenderError.InvalidScene,
    };
}

fn mapEditorGizmoError(err: anyerror) RenderError {
    return switch (err) {
        error.OutOfMemory => RenderError.OutOfMemory,
        else => RenderError.InvalidScene,
    };
}
