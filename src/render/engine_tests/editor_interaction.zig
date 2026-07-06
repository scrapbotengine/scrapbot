const std = @import("std");
const runtime = @import("../../runtime.zig");
const render = @import("../engine.zig");

const editor_layout = @import("../../editor/layout.zig");
const RenderError = render.RenderError;
const FrameInput = render.FrameInput;
const EditorState = render.EditorState;
const EditorSplitter = render.EditorSplitter;
const EditorScrollBoundary = render.EditorScrollBoundary;
const EditorCommand = render.EditorCommand;
const FlyCameraState = render.FlyCameraState;
const cameraState = render.cameraState;
const updateFlyCamera = render.updateFlyCamera;
const updateEditorState = render.updateEditorState;
const editorFrameState = render.editorFrameState;
const routeEditorUi = render.routeEditorUi;
const editorSystemListHitTestPoint = render.editorSystemListHitTestPoint;
const editorSystemVisibleRows = render.editorSystemVisibleRows;
const editorSystemVisibleRange = render.editorSystemVisibleRange;
const editorSystemListClipRect = render.editorSystemListClipRect;
const editor_system_scroll_pixels_per_wheel = render.editor_system_scroll_pixels_per_wheel;
const editor_system_row_stride = render.editor_system_row_stride;
const editorGameViewport = editor_layout.gameViewport;
const editorPlayButtonRect = editor_layout.playButtonRect;
const editorStepButtonRect = editor_layout.stepButtonRect;
const editorSplitterRect = editor_layout.splitterRect;

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

test "fly camera initializes from scene camera and moves while secondary mouse is held" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const camera_entity = try world.createEntity("camera", "Camera");
    try world.setTransform(camera_entity, .{ .position = .{ 0.0, 1.0, 6.0 } });
    try world.setCamera(camera_entity, .{});

    var state = FlyCameraState{};
    try std.testing.expect(try updateFlyCamera(&state, &world, .{}, 0.016) == null);

    const moved = (try updateFlyCamera(&state, &world, .{
        .pointer = .{
            .secondary_down = true,
            .secondary_pressed = true,
            .delta = .{ 10.0, -5.0 },
        },
        .keyboard = .{
            .move_forward = true,
            .move_up = true,
        },
    }, 0.05)) orelse return error.TestExpectedEqual;

    try std.testing.expect(state.initialized);
    try std.testing.expect(state.captured_look);
    try std.testing.expect(moved.position[2] < 6.0);
    try std.testing.expect(moved.position[1] > 1.0);
    try std.testing.expect(moved.rotation[1] < 0.0);
    try std.testing.expect(moved.rotation[0] > 0.0);

    const persisted = (try updateFlyCamera(&state, &world, .{}, 0.016)) orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(moved.position[2], persisted.position[2], 0.0001);
}

test "fly camera ignores right mouse held over editor sidebar" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    var state = FlyCameraState{};
    const ignored = try updateFlyCamera(&state, &world, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{
            .position = .{ 1240.0, 80.0 },
            .has_position = true,
            .secondary_down = true,
            .secondary_pressed = true,
            .delta = .{ 100.0, 0.0 },
        },
        .keyboard = .{ .move_forward = true },
    }, 0.05);

    try std.testing.expect(ignored == null);
    try std.testing.expect(!state.initialized);
    try std.testing.expect(!state.captured_look);
}

test "fly camera remains captured after starting in editor game viewport" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const camera_entity = try world.createEntity("camera", "Camera");
    try world.setTransform(camera_entity, .{ .position = .{ 0.0, 1.0, 6.0 } });
    try world.setCamera(camera_entity, .{});

    var state = FlyCameraState{};
    const base_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    const game_viewport = editorGameViewport(base_input);
    const started = (try updateFlyCamera(&state, &world, .{
        .debug_overlay_visible = true,
        .viewport_width = base_input.viewport_width,
        .viewport_height = base_input.viewport_height,
        .pointer = .{
            .position = .{ game_viewport.x + game_viewport.width * 0.5, game_viewport.y + game_viewport.height * 0.5 },
            .has_position = true,
            .secondary_down = true,
            .secondary_pressed = true,
            .delta = .{ 10.0, 0.0 },
        },
    }, 0.016)) orelse return error.TestExpectedEqual;

    try std.testing.expect(state.initialized);
    try std.testing.expect(state.captured_look);

    const continued = (try updateFlyCamera(&state, &world, .{
        .debug_overlay_visible = true,
        .viewport_width = base_input.viewport_width,
        .viewport_height = base_input.viewport_height,
        .pointer = .{
            .position = .{ 1240.0, 80.0 },
            .has_position = true,
            .secondary_down = true,
            .delta = .{ 30.0, 0.0 },
        },
    }, 0.016)) orelse return error.TestExpectedEqual;

    try std.testing.expect(state.captured_look);
    try std.testing.expect(continued.rotation[1] < started.rotation[1]);

    const released = (try updateFlyCamera(&state, &world, .{
        .debug_overlay_visible = true,
        .viewport_width = base_input.viewport_width,
        .viewport_height = base_input.viewport_height,
        .pointer = .{
            .position = .{ 1240.0, 80.0 },
            .has_position = true,
            .secondary_released = true,
            .delta = .{ 100.0, 0.0 },
        },
    }, 0.016)) orelse return error.TestExpectedEqual;

    try std.testing.expect(!state.captured_look);
    try std.testing.expectApproxEqAbs(continued.rotation[1], released.rotation[1], 0.0001);
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
    const input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    const game_viewport = editorGameViewport(input);
    const update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = input.debug_overlay_visible,
        .viewport_width = input.viewport_width,
        .viewport_height = input.viewport_height,
        .pointer = .{
            .position = .{ game_viewport.x + game_viewport.width * 0.5, game_viewport.y + game_viewport.height * 0.5 },
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
        .has_last_pointer = true,
    };
    const input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    const game_viewport = editorGameViewport(input);
    editor_state.last_pointer = .{ game_viewport.x + game_viewport.width * 0.5, game_viewport.y + game_viewport.height * 0.5 };
    const update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = input.debug_overlay_visible,
        .viewport_width = input.viewport_width,
        .viewport_height = input.viewport_height,
        .pointer = .{
            .position = .{ editor_state.last_pointer[0] + 40.0, editor_state.last_pointer[1] },
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
    const frame_input = FrameInput{ .debug_overlay_visible = true };
    const play_rect = editorPlayButtonRect(frame_input);
    const pause_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .pointer = .{
            .position = .{ play_rect.x + 4.0, play_rect.y + 4.0 },
            .has_position = true,
            .primary_pressed = true,
            .primary_down = true,
        },
    });
    try std.testing.expect(pause_update.consumed_pointer);
    try std.testing.expect(editor_state.paused);

    const release_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .pointer = .{
            .position = .{ play_rect.x + 4.0, play_rect.y + 4.0 },
            .has_position = true,
            .primary_released = true,
        },
    });
    try std.testing.expect(release_update.consumed_pointer);
    try std.testing.expect(!editor_state.captured_pointer);

    const step_rect = editorStepButtonRect(frame_input);
    const step_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .pointer = .{
            .position = .{ step_rect.x + 4.0, step_rect.y + 4.0 },
            .has_position = true,
            .primary_pressed = true,
            .primary_down = true,
        },
    });
    try std.testing.expect(step_update.consumed_pointer);
    try std.testing.expect(step_update.step_once);
    try std.testing.expect(editor_state.paused);
}

test "editor chrome routes pointer through one retained ui route" {
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
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .system_profiles = &profiles,
        .system_profile_count_hint = 20,
    };
    const play_rect = editorPlayButtonRect(frame_input);
    const command_route = (try routeEditorUi(std.testing.allocator, null, 0.0, 0.0, 0.0, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = .{ play_rect.x + 4.0, play_rect.y + 4.0 },
            .has_position = true,
            .primary_pressed = true,
        },
    }, profiles.len)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(EditorCommand.play_toggle, command_route.command);

    const left_splitter = editorSplitterRect(frame_input, .left) orelse return error.TestExpectedEqual;
    const splitter_route = (try routeEditorUi(std.testing.allocator, null, 0.0, 0.0, 0.0, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = .{ left_splitter.x + left_splitter.width + 3.0, left_splitter.y + 40.0 },
            .has_position = true,
            .primary_pressed = true,
        },
    }, profiles.len)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(EditorSplitter.left, splitter_route.splitter);

    const scroll_point = editorSystemListHitTestPoint(&profiles, 20);
    const scroll_route = (try routeEditorUi(std.testing.allocator, null, 0.0, 0.0, 0.0, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .system_profiles = &profiles,
        .system_profile_count_hint = 20,
        .pointer = .{
            .position = scroll_point,
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    }, 20)) orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel), scroll_route.system_scroll.next_offset[1], 0.001);
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
    const pointer = editorSystemListHitTestPoint(&profiles, 0);
    const down_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = pointer,
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });
    try std.testing.expect(down_update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel), editor_state.system_scroll_target_y, 0.001);
    try std.testing.expect(editor_state.system_scroll_y > 0.0);
    try std.testing.expect(editor_state.system_scroll_y < editor_state.system_scroll_target_y);

    const up_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = pointer,
            .has_position = true,
            .wheel_delta = .{ 0.0, 1.0 },
        },
    });
    try std.testing.expect(up_update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), editor_state.system_scroll_target_y, 0.001);
}

test "editor system list wheel scroll ignores pointer outside list" {
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

    var editor_state = EditorState{ .system_scroll_boundary = .bottom };
    const update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = .{ 1200.0, 680.0 },
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });

    try std.testing.expect(!update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), editor_state.system_scroll_target_y, 0.001);
    try std.testing.expectEqual(EditorScrollBoundary.none, editor_state.system_scroll_boundary);
}

test "editor system list uses profile count hint for render-added rows" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{ .id = "project.0", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "project.1", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
    };

    var editor_state = EditorState{};
    const update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
        .system_profile_count_hint = 9,
        .pointer = .{
            .position = editorSystemListHitTestPoint(&profiles, 9),
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });

    try std.testing.expect(update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel), editor_state.system_scroll_target_y, 0.001);
}

test "editor system list uses fixed wheel direction" {
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
    const pointer = editorSystemListHitTestPoint(&profiles, 0);
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = pointer,
            .has_position = true,
            .wheel_delta = .{ 0.0, 1.0 },
        },
    });
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), editor_state.system_scroll_target_y, 0.001);

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
    });

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = pointer,
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel), editor_state.system_scroll_target_y, 0.001);

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
    });

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = pointer,
            .has_position = true,
            .wheel_delta = .{ 0.0, 1.0 },
        },
    });
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), editor_state.system_scroll_target_y, 0.001);
}

test "editor system list supports fractional pixel scroll" {
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
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .viewport_height = 440.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = editorSystemListHitTestPoint(&profiles, 0),
            .has_position = true,
            .wheel_delta = .{ 0.0, -0.5 },
        },
    });
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel / 2.0), editor_state.system_scroll_target_y, 0.001);
    editor_state.system_scroll_y = editor_state.system_scroll_target_y;

    const range_input = FrameInput{
        .viewport_height = 440.0,
        .system_profiles = &profiles,
        .editor = editorFrameState(&world, editor_state),
    };
    const range = editorSystemVisibleRange(range_input);
    try std.testing.expectEqual(@as(usize, 0), range.start);
    try std.testing.expectEqual(editorSystemVisibleRows(range_input) + 1, range.end);
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel / 2.0), range.offset_y, 0.001);
}

test "editor system list animates toward scroll target" {
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
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 0.016,
        .system_profiles = &profiles,
        .pointer = .{
            .position = editorSystemListHitTestPoint(&profiles, 0),
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });

    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel), editor_state.system_scroll_target_y, 0.001);
    try std.testing.expect(editor_state.system_scroll_y > 0.0);
    try std.testing.expect(editor_state.system_scroll_y < editor_state.system_scroll_target_y);

    const previous_scroll_y = editor_state.system_scroll_y;
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
    });
    try std.testing.expect(editor_state.system_scroll_y > previous_scroll_y);
    try std.testing.expect(editor_state.system_scroll_y < editor_state.system_scroll_target_y);
}

fn replayEditorScrollFrames(
    world: *runtime.World,
    editor_state: *EditorState,
    profiles: []const runtime.SystemProfileSnapshot,
    wheel_deltas: []const f32,
) !void {
    const pointer = editorSystemListHitTestPoint(profiles, 0);
    for (wheel_deltas) |delta| {
        _ = try updateEditorState(std.testing.allocator, world, editor_state, .{
            .debug_overlay_visible = true,
            .delta_seconds = 1.0,
            .viewport_height = 440.0,
            .system_profiles = profiles,
            .pointer = .{
                .position = pointer,
                .has_position = true,
                .wheel_delta = .{ 0.0, delta },
            },
        });
    }
}

test "editor system list replay applies fractional scroll away from the bottom" {
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

    var editor_state = EditorState{
        .system_scroll_y = editor_system_row_stride * 2.0,
        .system_scroll_target_y = editor_system_row_stride * 2.0,
    };

    const bounce_frames = [_]f32{
        0.18, 0.0, 0.24, 0.0, 0.12, 0.0, 0.2,
    };
    try replayEditorScrollFrames(&world, &editor_state, &profiles, &bounce_frames);
    const bounced_target = editor_system_row_stride * 2.0 - editor_system_scroll_pixels_per_wheel * 0.74;
    try std.testing.expectApproxEqAbs(bounced_target, editor_state.system_scroll_target_y, 0.001);

    const deliberate_reverse_frames = [_]f32{1.0};
    try replayEditorScrollFrames(&world, &editor_state, &profiles, &deliberate_reverse_frames);
    try std.testing.expectApproxEqAbs(bounced_target - editor_system_scroll_pixels_per_wheel, editor_state.system_scroll_target_y, 0.001);
}

test "editor system list replay handles mixed wheel directions without sticky boundary" {
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
    const frames = [_]f32{
        -1.0, -1.0, -1.0, -1.0, 1.0, 1.0, -0.75, 2.0, -1.0,
    };
    try replayEditorScrollFrames(&world, &editor_state, &profiles, &frames);
    try std.testing.expectApproxEqAbs(@as(f32, 31.5), editor_state.system_scroll_target_y, 0.001);

    const deliberate_reverse_after_idle = [_]f32{ 0.0, 1.0 };
    try replayEditorScrollFrames(&world, &editor_state, &profiles, &deliberate_reverse_after_idle);
    try std.testing.expectApproxEqAbs(@as(f32, 13.5), editor_state.system_scroll_target_y, 0.001);
}
