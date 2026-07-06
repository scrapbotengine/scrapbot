const std = @import("std");
const geometry = @import("../../geometry.zig");
const runtime = @import("../../runtime.zig");
const render = @import("../engine.zig");
const render_batching = @import("../batching.zig");
const render_input = @import("../input.zig");
const render_platform = @import("../platform.zig");
const render_ui = @import("../ui.zig");
const ui_layout = @import("../../ui_layout.zig");

const RenderError = render.RenderError;
const FrameInput = render.FrameInput;
const RenderEcsState = render.RenderEcsState;
const BatchPlan = render_batching.BatchPlan;
const buildUiVertices = render_ui.buildUiVertices;
const renderFrameInput = render_ui.renderFrameInput;
const renderUiButtonState = render_ui.renderUiButtonState;
const render_ui_button_state_component_id = render_ui.render_ui_button_state_component_id;
const resolveUiLayout = render_ui.resolveUiLayout;
const resolveUiTextPosition = render_ui.resolveUiTextPosition;
const setRenderUiButtonState = render_ui.setRenderUiButtonState;
const textPixelSize = render_ui.textPixelSize;
const writeFrameInput = render_ui.writeFrameInput;
const screenToClipX = render_ui.screenToClipX;
const screenToClipY = render_ui.screenToClipY;
const toggleDebugOverlay = render_input.toggleDebugOverlay;
const sdl = render_platform.sdl;
const editorGameViewport = @import("../../editor/layout.zig").gameViewport;
const isEditorToggleShortcut = render.isEditorToggleShortcut;
const liveRunDeltaSecondsFromElapsedNs = render.liveRunDeltaSecondsFromElapsedNs;
const live_run_default_delta_seconds = render.live_run_default_delta_seconds;
const pointInsideUiRect = runtime.pointInsideUiRect;
const layoutItem = ui_layout.layoutItem;
const resolvedItemRect = ui_layout.resolvedItemRect;
const render_draw_batch_component_id = render.render_draw_batch_component_id;
const render_extract_system_id = render.render_extract_system_id;
const render_prepare_meshes_system_id = render.render_prepare_meshes_system_id;
const render_interact_ui_system_id = render.render_interact_ui_system_id;
const render_queue_meshes_system_id = render.render_queue_meshes_system_id;
const render_prepare_ui_system_id = render.render_prepare_ui_system_id;
const render_queue_ui_system_id = render.render_queue_ui_system_id;
const render_draw_meshes_system_id = render.render_draw_meshes_system_id;
const stats = render.stats;

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
    try scene_world.setUiCanvas(canvas, .{});

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
    try std.testing.expectEqual(@as(usize, 2), state.extractedRenderableMeshes().len);
    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.ui_canvas_component_id));
    try std.testing.expectEqual(@as(usize, 1), state.world.uiRectCount());
    try std.testing.expectEqual(@as(usize, 1), state.world.uiTextCount());
    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.input_pointer_component_id));
    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.input_keyboard_component_id));
    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.input_frame_component_id));
    try std.testing.expectEqual(@as(f32, 52.0), (scene_world.renderCamera() orelse return error.TestExpectedEqual).fov_y_degrees);
    try std.testing.expectEqual(@as(f32, 1.25), (scene_world.renderDirectionalLight() orelse return error.TestExpectedEqual).intensity);
    const extracted_sphere = state.extractedRenderableMeshes()[1];
    try std.testing.expectEqualStrings("uv_sphere", extracted_sphere.primitive);
    try std.testing.expectEqual(@as(f32, 0.35), extracted_sphere.base_color[1]);
    const extracted_box = state.extractedRenderableMeshes()[0];
    try std.testing.expect(extracted_box.casts_shadow);
    try std.testing.expect(!extracted_box.receives_shadow);
    try std.testing.expect(!extracted_sphere.casts_shadow);
    try std.testing.expect(extracted_sphere.receives_shadow);

    var plan = try BatchPlan.buildFromRenderables(std.testing.allocator, state.extractedRenderableMeshes());
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

    var plan = try BatchPlan.buildFromRenderables(std.testing.allocator, state.extractedRenderableMeshes());
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

test "batch plan from extracted renderables matches render world plan" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    try addBatchTestRenderable(&scene_world, "blue-box-a", "box", 0, 0, .{ -1.6, 0.0, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "gold-sphere", "uv_sphere", 16, 8, .{ 0.0, 0.0, 0.0 }, .{ 1.0, 0.56, 0.1 }, .{});
    try addBatchTestRenderable(&scene_world, "blue-box-b", "box", 0, 0, .{ 1.6, 0.0, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "blue-box-receiver", "box", 0, 0, .{ 0.0, -1.2, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .receives_shadow = true });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractScene(.{ .world = &scene_world });

    var world_plan = try BatchPlan.build(std.testing.allocator, &scene_world);
    defer world_plan.deinit();
    var extracted_plan = try BatchPlan.buildFromRenderables(std.testing.allocator, state.extractedRenderableMeshes());
    defer extracted_plan.deinit();

    try std.testing.expectEqual(world_plan.renderables.len, extracted_plan.renderables.len);
    try std.testing.expectEqual(world_plan.batches.len, extracted_plan.batches.len);
    for (world_plan.batches, extracted_plan.batches) |world_batch, extracted_batch| {
        try std.testing.expect(world_batch.geometry_key.eql(extracted_batch.geometry_key));
        try std.testing.expect(world_batch.shadow_key.eql(extracted_batch.shadow_key));
        try std.testing.expectEqualSlices(usize, world_batch.render_indices, extracted_batch.render_indices);
    }
}

test "render ECS repeated extraction replaces render world without accumulating entities" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    try addBatchTestRenderable(&scene_world, "blue-box", "box", 0, 0, .{ -1.0, 0.0, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{});

    const panel = try scene_world.createEntity("panel", "Panel");
    try scene_world.setUiRect(panel, .{
        .position = .{ 24.0, 24.0, 0.0 },
        .size = .{ 120.0, 40.0, 0.0 },
        .color = .{ 0.02, 0.08, 0.16 },
    });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractScene(.{ .world = &scene_world });
    try std.testing.expectEqual(@as(usize, 1), state.world.renderableMeshCount());
    try std.testing.expectEqual(@as(usize, 1), state.extractedRenderableMeshes().len);
    try std.testing.expectEqual(@as(usize, 1), state.world.uiRectCount());
    const first_entity_count = state.world.entityCount();

    try state.extractScene(.{ .world = &scene_world });
    try std.testing.expectEqual(first_entity_count, state.world.entityCount());
    try std.testing.expectEqual(@as(usize, 1), state.world.renderableMeshCount());
    try std.testing.expectEqual(@as(usize, 1), state.extractedRenderableMeshes().len);
    try std.testing.expectEqual(@as(usize, 1), state.world.uiRectCount());
}

test "render ECS failed renderable snapshot preserves previous render world and snapshot" {
    var valid_world = runtime.World.init(std.testing.allocator);
    defer valid_world.deinit();
    try addBatchTestRenderable(&valid_world, "blue-box", "box", 0, 0, .{ -1.0, 0.0, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{});

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractScene(.{ .world = &valid_world });
    try std.testing.expectEqual(@as(usize, 1), state.world.renderableMeshCount());
    try std.testing.expectEqual(@as(usize, 1), state.extractedRenderableMeshes().len);

    const original_allocator = state.allocator;
    state.allocator = std.testing.failing_allocator;
    defer state.allocator = original_allocator;
    try std.testing.expectError(RenderError.OutOfMemory, state.extractScene(.{ .world = &valid_world }));

    try std.testing.expectEqual(@as(usize, 1), state.world.renderableMeshCount());
    try std.testing.expectEqual(@as(usize, 1), state.extractedRenderableMeshes().len);
    try std.testing.expect(state.world.findEntityById("scrapbot.input.frame") == null);
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

test "UI vertex builder emits one quad per visible glyph" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const label = try world.createEntity("label", "Label");
    try world.setUiText(label, .{
        .position = .{ 42.0, 36.0, 0.0 },
        .size = 1.0,
        .color = .{ 1.0, 0.8, 0.2 },
        .value = "A ",
    });

    var vertices = try buildUiVertices(std.testing.allocator, &world, 640, 480);
    defer vertices.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 6), vertices.items.len);
    try std.testing.expectEqual(@as(f32, -1.0), vertices.items[0].rect_size_radius[3]);
    try std.testing.expect(vertices.items[0].glyph_rows1[2] > 0.0);
}

test "UI vertex builder scales editor logical pixels to physical pixels" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try writeFrameInput(&world, .{
        .viewport_width = 640.0,
        .viewport_height = 360.0,
        .pixel_scale = 2.0,
        .debug_overlay_visible = true,
    });

    const input = try world.createEntity("scrapbot.editor.test.input", "Editor Test Input");
    try world.setUiRect(input, .{
        .position = .{ 10.0, 12.0, 0.0 },
        .size = .{ 32.0, 16.0, 0.0 },
        .color = .{ 0.2, 0.3, 0.4 },
        .corner_radius = 8.0,
    });

    var vertices = try buildUiVertices(std.testing.allocator, &world, 1280, 720);
    defer vertices.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 6), vertices.items.len);
    try std.testing.expectApproxEqAbs(screenToClipX(20.0, 1280), vertices.items[0].position[0], 0.001);
    try std.testing.expectApproxEqAbs(screenToClipY(24.0, 720), vertices.items[0].position[1], 0.001);
    try std.testing.expectApproxEqAbs(screenToClipX(84.0, 1280), vertices.items[1].position[0], 0.001);
    try std.testing.expectApproxEqAbs(screenToClipY(56.0, 720), vertices.items[2].position[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 64.0), vertices.items[0].rect_size_radius[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), vertices.items[0].rect_size_radius[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), vertices.items[0].rect_size_radius[2], 0.001);
}

test "UI hit testing uses half-open screen rects" {
    const position = [3]f32{ 32.0, 24.0, 0.0 };
    const size = [3]f32{ 120.0, 48.0, 0.0 };

    try std.testing.expect(runtime.pointInsideUiRect(.{ 32.0, 24.0 }, position, size));
    try std.testing.expect(runtime.pointInsideUiRect(.{ 151.99, 71.99 }, position, size));
    try std.testing.expect(!runtime.pointInsideUiRect(.{ 152.0, 72.0 }, position, size));
    try std.testing.expect(!runtime.pointInsideUiRect(.{ 31.99, 24.0 }, position, size));
}

test "UI layout resolves scroll views and vgroup rows" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const scroll = try world.createEntity("scroll", "Scroll View");
    try world.setUiScrollView(scroll, .{
        .position = .{ 40.0, 50.0, 0.0 },
        .size = .{ 100.0, 60.0, 0.0 },
        .content_offset = .{ 0.0, 20.0, 0.0 },
    });

    const stack = try world.createEntity("stack", "Stack");
    try world.setUiVGroup(stack, .{
        .position = .{ 8.0, 10.0, 0.0 },
        .size = .{ 100.0, 96.0, 0.0 },
        .spacing = 4.0,
        .padding = .{ 0.0, 0.0, 0.0 },
    });
    try world.setUiLayoutItem(stack, .{ .parent = "scroll", .order = 0 });

    const first = try world.createEntity("first", "First");
    try world.setUiText(first, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = 1.0,
        .value = "FIRST",
    });
    try world.setUiLayoutItem(first, .{ .parent = "stack", .order = 0 });

    const second = try world.createEntity("second", "Second");
    try world.setUiText(second, .{
        .position = .{ 2.0, 3.0, 0.0 },
        .size = 1.0,
        .value = "SECOND",
    });
    try world.setUiLayoutItem(second, .{ .parent = "stack", .order = 1 });

    const first_layout = try resolveUiLayout(&world, first, .{ 0.0, 0.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), first_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), first_layout.position[1], 0.001);

    const second_layout = try resolveUiLayout(&world, second, .{ 2.0, 3.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), second_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 79.0), second_layout.position[1], 0.001);
    const clip = second_layout.clip orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), clip.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), clip.position[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), clip.size[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 60.0), clip.size[1], 0.001);
}

test "UI stack layout resolves horizontal rows and text block centering" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const stack = try world.createEntity("stack", "Stack");
    try world.setUiStack(stack, .{
        .position = .{ 20.0, 30.0, 0.0 },
        .spacing = 3.0,
        .direction = "horizontal",
        .padding = .{ 5.0, 6.0, 0.0 },
    });

    const first = try world.createEntity("first", "First");
    try world.setUiRect(first, .{
        .position = .{ 1.0, 2.0, 0.0 },
        .size = .{ 20.0, 10.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
    });
    try world.setUiLayoutItem(first, .{ .parent = "stack", .order = 0 });

    const second = try world.createEntity("second", "Second");
    try world.setUiRect(second, .{
        .position = .{ 2.0, 4.0, 0.0 },
        .size = .{ 12.0, 10.0, 0.0 },
        .color = .{ 0.2, 0.3, 0.4 },
    });
    try world.setUiLayoutItem(second, .{ .parent = "stack", .order = 1 });

    const first_layout = try resolveUiLayout(&world, first, .{ 1.0, 2.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 26.0), first_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 38.0), first_layout.position[1], 0.001);

    const second_layout = try resolveUiLayout(&world, second, .{ 2.0, 4.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), second_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), second_layout.position[1], 0.001);

    const bad_stack = try world.createEntity("bad-stack", "Bad Stack");
    try world.setUiStack(bad_stack, .{ .direction = "diagonal" });
    const bad_child = try world.createEntity("bad-child", "Bad Child");
    try world.setUiRect(bad_child, .{});
    try world.setUiLayoutItem(bad_child, .{ .parent = "bad-stack" });
    try std.testing.expectError(RenderError.InvalidScene, resolveUiLayout(&world, bad_child, .{ 0.0, 0.0, 0.0 }));

    const label = try world.createEntity("label", "Label");
    try world.setUiText(label, .{
        .position = .{ 10.0, 20.0, 0.0 },
        .size = 1.0,
        .value = "OK",
    });
    try world.setUiTextBlock(label, .{
        .size = .{ 100.0, 48.0, 0.0 },
        .horizontal_align = "center",
        .vertical_align = "center",
    });
    const label_position = try resolveUiTextPosition(&world, label, world.uiTextAt(0) orelse return error.TestExpectedEqual, .{ 10.0, 20.0, 0.0 });
    const label_size = textPixelSize("OK", 1.0);
    try std.testing.expectApproxEqAbs(10.0 + (100.0 - label_size[0]) * 0.5, label_position[0], 0.001);
    try std.testing.expectApproxEqAbs(20.0 + (48.0 - label_size[1]) * 0.5, label_position[1], 0.001);
}

test "UI layout item can inherit a rect parent's layout chain" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const stack = try world.createEntity("stack", "Stack");
    try world.setUiStack(stack, .{
        .position = .{ 80.0, 40.0, 0.0 },
        .spacing = 12.0,
        .direction = "horizontal",
        .padding = .{ 8.0, 6.0, 0.0 },
    });

    const button = try world.createEntity("button", "Button");
    try world.setUiRect(button, .{
        .position = .{ 2.0, 3.0, 0.0 },
        .size = .{ 120.0, 48.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
    });
    try world.setUiLayoutItem(button, .{ .parent = "stack", .order = 0 });

    const label = try world.createEntity("button-label", "Button Label");
    try world.setUiText(label, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = 1.0,
        .value = "ACTION",
    });
    try world.setUiTextBlock(label, .{
        .size = .{ 120.0, 48.0, 0.0 },
        .horizontal_align = "center",
        .vertical_align = "center",
    });
    try world.setUiLayoutItem(label, .{ .parent = "button", .order = 0 });

    const label_layout = try resolveUiLayout(&world, label, .{ 0.0, 0.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 90.0), label_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 49.0), label_layout.position[1], 0.001);

    const text = world.uiTextAt(0) orelse return error.TestExpectedEqual;
    const centered = try resolveUiTextPosition(&world, label, text, label_layout.position);
    const label_size = textPixelSize("ACTION", 1.0);
    try std.testing.expectApproxEqAbs(90.0 + (120.0 - label_size[0]) * 0.5, centered[0], 0.001);
    try std.testing.expectApproxEqAbs(49.0 + (48.0 - label_size[1]) * 0.5, centered[1], 0.001);
}

test "UI layout item margins participate in stack placement" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const stack = try world.createEntity("stack", "Stack");
    try world.setUiStack(stack, .{
        .position = .{ 20.0, 30.0, 0.0 },
        .spacing = 4.0,
        .direction = "horizontal",
    });

    const first = try world.createEntity("first", "First");
    try world.setUiRect(first, .{ .size = .{ 20.0, 10.0, 0.0 } });
    try world.setUiLayoutItem(first, .{ .parent = "stack", .order = 0, .margin = .{ 3.0, 5.0, 0.0 } });

    const second = try world.createEntity("second", "Second");
    try world.setUiRect(second, .{ .size = .{ 12.0, 10.0, 0.0 } });
    try world.setUiLayoutItem(second, .{ .parent = "stack", .order = 1, .margin = .{ 2.0, 1.0, 0.0 } });

    const first_layout = try resolveUiLayout(&world, first, .{ 0.0, 0.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 23.0), first_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 35.0), first_layout.position[1], 0.001);

    const second_layout = try resolveUiLayout(&world, second, .{ 0.0, 0.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 52.0), second_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 31.0), second_layout.position[1], 0.001);
}

test "UI canvas fit scaling transforms scene UI vertices" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try writeFrameInput(&world, .{
        .viewport_width = 200.0,
        .viewport_height = 100.0,
        .ui_visible = true,
    });

    const canvas = try world.createEntity("canvas", "Canvas");
    try world.setUiCanvas(canvas, .{
        .design_size = .{ 100.0, 100.0, 0.0 },
        .scale_mode = "fit",
    });

    const panel = try world.createEntity("panel", "Panel");
    try world.setUiRect(panel, .{
        .position = .{ 10.0, 10.0, 0.0 },
        .size = .{ 20.0, 10.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
    });
    try world.setUiBorder(panel, .{
        .color = .{ 0.5, 0.6, 0.7 },
        .thickness = 2.0,
    });

    var vertices = try buildUiVertices(std.testing.allocator, &world, 200, 100);
    defer vertices.deinit(std.testing.allocator);

    try std.testing.expect(vertices.items.len >= 12);
    try std.testing.expectApproxEqAbs(@as(f32, -0.4), vertices.items[0].position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), vertices.items[0].position[1], 0.001);
}

test "UI canvas fit scaling targets editor game viewport when editor is visible" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try writeFrameInput(&world, .{
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .ui_visible = true,
        .debug_overlay_visible = true,
    });

    const canvas = try world.createEntity("canvas", "Canvas");
    try world.setUiCanvas(canvas, .{
        .design_size = .{ 100.0, 100.0, 0.0 },
        .scale_mode = "fit",
    });

    const panel = try world.createEntity("panel", "Panel");
    try world.setUiRect(panel, .{
        .position = .{ 10.0, 10.0, 0.0 },
        .size = .{ 20.0, 10.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
    });

    var vertices = try buildUiVertices(std.testing.allocator, &world, 1280, 720);
    defer vertices.deinit(std.testing.allocator);

    const viewport = editorGameViewport(.{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pixel_scale = 2.0,
    });
    const scale = @min(viewport.width / 100.0, viewport.height / 100.0);
    const expected_x = viewport.x + (viewport.width - 100.0 * scale) * 0.5 + 10.0 * scale;
    const expected_y = viewport.y + (viewport.height - 100.0 * scale) * 0.5 + 10.0 * scale;

    try std.testing.expectApproxEqAbs(screenToClipX(expected_x, 1280), vertices.items[0].position[0], 0.001);
    try std.testing.expectApproxEqAbs(screenToClipY(expected_y, 720), vertices.items[0].position[1], 0.001);
}

test "UI vertex builder renders progress fills and separators" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const progress = try world.createEntity("progress", "Progress");
    try world.setUiRect(progress, .{
        .position = .{ 10.0, 20.0, 0.0 },
        .size = .{ 100.0, 16.0, 0.0 },
        .color = .{ 0.1, 0.1, 0.1 },
        .corner_radius = 4.0,
    });
    try world.setUiProgressBar(progress, .{
        .value = 0.25,
        .max = 1.0,
        .fill_color = .{ 0.2, 0.7, 0.8 },
    });

    const separator = try world.createEntity("separator", "Separator");
    try world.setUiSeparator(separator, .{
        .position = .{ 10.0, 44.0, 0.0 },
        .size = .{ 100.0, 2.0, 0.0 },
        .color = .{ 0.5, 0.6, 0.7 },
    });

    var vertices = try buildUiVertices(std.testing.allocator, &world, 200, 100);
    defer vertices.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 18), vertices.items.len);
    try std.testing.expectApproxEqAbs(screenToClipX(35.0, 200), vertices.items[7].position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), vertices.items[6].color[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), vertices.items[6].rect_size_radius[2], 0.001);
    try std.testing.expectApproxEqAbs(screenToClipY(44.0, 100), vertices.items[12].position[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), vertices.items[12].color[0], 0.001);
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
    const held_state = (try renderUiButtonState(state.world, extracted_button.entity)) orelse return error.TestExpectedEqual;
    try std.testing.expect(held_state.hovered);
    try std.testing.expect(held_state.held);
    try std.testing.expect(!held_state.pressed);

    const extracted_panel = state.world.uiRectAt(1) orelse return error.TestExpectedEqual;
    try std.testing.expect((try renderUiButtonState(state.world, extracted_panel.entity)) == null);

    try state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .pointer = .{
            .position = .{ 48.0, 36.0 },
            .has_position = true,
            .primary_released = true,
        },
    });
    try state.updateUiInteractions();

    const pressed_button = state.world.uiRectAt(0) orelse return error.TestExpectedEqual;
    const pressed_state = (try renderUiButtonState(state.world, pressed_button.entity)) orelse return error.TestExpectedEqual;
    try std.testing.expect(pressed_state.hovered);
    try std.testing.expect(!pressed_state.held);
    try std.testing.expect(pressed_state.pressed);
}

test "render ECS hit tests buttons through UI layout clips" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const scroll = try scene_world.createEntity("scroll", "Scroll View");
    try scene_world.setUiScrollView(scroll, .{
        .position = .{ 40.0, 50.0, 0.0 },
        .size = .{ 60.0, 40.0, 0.0 },
        .content_offset = .{ 0.0, 0.0, 0.0 },
    });

    const button = try scene_world.createEntity("button", "Button");
    try scene_world.setUiRect(button, .{
        .position = .{ 8.0, 8.0, 0.0 },
        .size = .{ 30.0, 24.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
    });
    try scene_world.setUiButton(button);
    try scene_world.setUiLayoutItem(button, .{ .parent = "scroll", .order = 0 });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();

    try state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .pointer = .{
            .position = .{ 50.0, 60.0 },
            .has_position = true,
            .primary_down = true,
        },
    });
    try state.updateUiInteractions();

    const extracted_button = state.world.findEntityById("button") orelse return error.TestExpectedEqual;
    const held_state = (try renderUiButtonState(state.world, extracted_button)) orelse return error.TestExpectedEqual;
    try std.testing.expect(held_state.hovered);
    try std.testing.expect(held_state.held);

    try state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .pointer = .{
            .position = .{ 104.0, 60.0 },
            .has_position = true,
            .primary_down = true,
        },
    });
    try state.updateUiInteractions();

    const clipped_button = state.world.findEntityById("button") orelse return error.TestExpectedEqual;
    const clipped_state = (try renderUiButtonState(state.world, clipped_button)) orelse return error.TestExpectedEqual;
    try std.testing.expect(!clipped_state.hovered);
    try std.testing.expect(!clipped_state.held);
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

    try std.testing.expectEqual(@as(usize, 1), state.world.uiRectCount());
    try std.testing.expectEqual(@as(usize, 1), state.world.uiTextCount());
    try std.testing.expectEqual(@as(usize, 0), state.world.componentInstanceCountFor(render_ui_button_state_component_id));
    try state.queueUiDraw();
    try std.testing.expectEqual(@as(usize, 0), state.uiDrawCommandCount());

    const input = try renderFrameInput(state.world);
    try std.testing.expect(!input.ui_visible);
    try std.testing.expect(!input.debug_overlay_visible);
}

test "frame input round trips through ECS input components" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try writeFrameInput(&world, .{
        .pointer = .{
            .position = .{ 44.0, 55.0 },
            .delta = .{ 2.0, -1.0 },
            .has_position = true,
            .primary_down = true,
            .secondary_down = true,
            .secondary_pressed = true,
            .wheel_delta = .{ 0.0, -3.0 },
        },
        .keyboard = .{
            .ctrl_down = true,
            .move_forward = true,
            .move_down = true,
            .editor_toggle_pressed = true,
        },
        .ui_visible = false,
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pixel_scale = 2.0,
    });

    const input = try renderFrameInput(&world);
    try std.testing.expect(input.pointer.has_position);
    try std.testing.expectEqual(@as(f32, 44.0), input.pointer.position[0]);
    try std.testing.expectEqual(@as(f32, 2.0), input.pointer.delta[0]);
    try std.testing.expect(input.pointer.secondary_down);
    try std.testing.expect(input.pointer.secondary_pressed);
    try std.testing.expectEqual(@as(f32, -3.0), input.pointer.wheel_delta[1]);
    try std.testing.expect(input.keyboard.ctrl_down);
    try std.testing.expect(input.keyboard.move_forward);
    try std.testing.expect(input.keyboard.move_down);
    try std.testing.expect(input.keyboard.editor_toggle_pressed);
    try std.testing.expect(!input.ui_visible);
    try std.testing.expect(input.debug_overlay_visible);
    try std.testing.expectEqual(@as(f32, 1280.0), input.viewport_width);
    try std.testing.expectEqual(@as(f32, 2.0), input.pixel_scale);
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

    try std.testing.expect(isEditorToggleShortcut(sdl.SCRAPBOT_SDL_KEY_TAB, true));
    try std.testing.expect(!isEditorToggleShortcut(sdl.SCRAPBOT_SDL_KEY_TAB, false));
    try std.testing.expect(!isEditorToggleShortcut(sdl.SCRAPBOT_SDL_KEY_F1, true));
}

test "live run delta conversion uses measured elapsed seconds" {
    const delta = liveRunDeltaSecondsFromElapsedNs(16_666_667);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0 / 60.0), delta, 0.000001);
}

test "live run delta conversion falls back for non-advancing ticks" {
    const delta = liveRunDeltaSecondsFromElapsedNs(0);
    try std.testing.expectApproxEqAbs(live_run_default_delta_seconds, delta, 0.000001);
}
