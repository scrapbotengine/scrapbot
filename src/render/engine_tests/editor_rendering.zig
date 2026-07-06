const std = @import("std");
const runtime = @import("../../runtime.zig");
const render = @import("../engine.zig");
const render_ui = @import("../ui.zig");
const ui_layout = @import("../../ui_layout.zig");

const editor_layout = @import("../../editor/layout.zig");
const FrameInput = render.FrameInput;
const EditorCursorKind = render.EditorCursorKind;
const EditorSplitter = render.EditorSplitter;
const EditorState = render.EditorState;
const RenderEcsState = render.RenderEcsState;
const applyEditorTypedControlClick = render.applyEditorTypedControlClick;
const editor_command_play_toggle = render.editor_command_play_toggle;
const editor_command_splitter_left = render.editor_command_splitter_left;
const editor_control_button_height = render.editor_control_button_height;
const editor_control_button_width = render.editor_control_button_width;
const editor_entity_row_label_padding_x = render.editor_entity_row_label_padding_x;
const editor_entity_card_padding_y = render.editor_entity_card_padding_y;
const editor_entity_row_stride = render.editor_entity_row_stride;
const editor_button_corner_radius = render.editor_button_corner_radius;
const editor_bar_text_offset_y = render.editor_bar_text_offset_y;
const editor_inspector_card_padding_y = render.editor_inspector_card_padding_y;
const editor_inspector_card_gap = render.editor_inspector_card_gap;
const editor_inspector_card_padding_x = render.editor_inspector_card_padding_x;
const editor_inspector_field_row_stride = render.editor_inspector_field_row_stride;
const editor_inspector_field_control_offset_y = render.editor_inspector_field_control_offset_y;
const editor_inspector_field_row_height = render.editor_inspector_field_row_height;
const editor_inspector_field_row_margin_y = render.editor_inspector_field_row_margin_y;
const editor_inspector_input_cell_padding = render.editor_inspector_input_cell_padding;
const editor_inspector_input_border_thickness = render.editor_inspector_input_border_thickness;
const editor_inspector_input_corner_radius = render.editor_inspector_input_corner_radius;
const editor_inspector_input_padding_x = render.editor_inspector_input_padding_x;
const editor_inspector_input_padding_y = render.editor_inspector_input_padding_y;
const editor_inspector_input_text_offset_x = render.editor_inspector_input_text_offset_x;
const editor_inspector_input_text_offset_y = render.editor_inspector_input_text_offset_y;
const editor_inspector_separator_height = render.editor_inspector_separator_height;
const editor_inspector_text_size = render.editor_inspector_text_size;
const editor_left_panel_gap = render.editor_left_panel_gap;
const editor_left_sidebar_target_width = render.editor_left_sidebar_target_width;
const editor_palette = render.editor_palette;
const editor_panel_label_gap = render.editor_panel_label_gap;
const editor_panel_corner_radius = render.editor_panel_corner_radius;
const editor_system_row_stride = render.editor_system_row_stride;
const editor_system_scroll_pixels_per_wheel = render.editor_system_scroll_pixels_per_wheel;
const editor_system_text_size = render.editor_system_text_size;
const editorBottomBarRect = editor_layout.bottomBarRect;
const editorCursorKind = render.editorCursorKind;
const editorEntityHandlesEqual = render.editorEntityHandlesEqual;
const editorEntityListClipRect = render.editorEntityListClipRect;
const editorFrameState = render.editorFrameState;
const editorGameViewport = editor_layout.gameViewport;
const editorInspectorFieldLayout = render.editorInspectorFieldLayout;
const editorInspectorScrollClipRect = render.editorInspectorScrollClipRect;
const editorLeftSidebarRect = editor_layout.leftSidebarRect;
const editorRightSidebarRect = editor_layout.rightSidebarRect;
const editorSidebarPanelRect = render.editorSidebarPanelRect;
const editorSplitterRect = editor_layout.splitterRect;
const editorSystemListClipRect = render.editorSystemListClipRect;
const editorSystemTableContentHeight = render.editorSystemTableContentHeight;
const editorTextHeight = render.editorTextHeight;
const editorTextWidth = render.editorTextWidth;
const focusEditorTextInput = render.focusEditorTextInput;
const liveRunDeltaSecondsFromElapsedNs = render.liveRunDeltaSecondsFromElapsedNs;
const makeEditorFieldSelection = render.makeEditorFieldSelection;
const mapWorldError = render.mapWorldError;
const renderFrameInput = render_ui.renderFrameInput;
const resolveUiLayout = render_ui.resolveUiLayout;
const resolveUiTextPosition = render_ui.resolveUiTextPosition;
const routeEditorSplitterAt = render.routeEditorSplitterAt;
const setRenderUiButtonState = render_ui.setRenderUiButtonState;
const buildUiVertices = render_ui.buildUiVertices;
const setRenderUiClip = render_ui.setRenderUiClip;
const screenToClipY = render_ui.screenToClipY;
const uiLayoutItemSize = render_ui.uiLayoutItemSize;
const updateEditorState = render.updateEditorState;
const layoutItem = ui_layout.layoutItem;
const resolvedItemRect = ui_layout.resolvedItemRect;
const editor_performance_display_interval_ns = render.editor_performance_display_interval_ns;
const live_run_max_delta_seconds = render.live_run_max_delta_seconds;
const render_extract_system_id = render.render_extract_system_id;
const render_system_profile_window_frames = render.render_system_profile_window_frames;

test "live run delta conversion clamps large spikes" {
    const delta = liveRunDeltaSecondsFromElapsedNs(2 * std.time.ns_per_s);
    try std.testing.expectApproxEqAbs(live_run_max_delta_seconds, delta, 0.000001);
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
    try std.testing.expect(state.world.uiTextCount() >= 8);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.debug.accent") == null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.inspector.accent") == null);

    const label = state.world.findEntityById("scrapbot.editor.debug.fps") orelse return error.TestExpectedEqual;
    const fps_value = try state.world.getString(label, runtime.ui_text_component_id, "value");
    const fps_position = try state.world.getVec3(label, runtime.ui_text_component_id, "position");
    const fps_size = try state.world.getFloat(label, runtime.ui_text_component_id, "size");
    try std.testing.expectEqualStrings("FPS 60", fps_value);
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_text_size), fps_size, 0.001);

    const play_button = state.world.findEntityById("scrapbot.editor.controls.play") orelse return error.TestExpectedEqual;
    const play_position = try state.world.getVec3(play_button, runtime.ui_rect_component_id, "position");
    try std.testing.expect(play_position[0] > fps_position[0] + editorTextWidth(fps_value, fps_size));
    try std.testing.expectEqual(@as(f32, editor_button_corner_radius), try state.world.getFloat(play_button, runtime.ui_rect_component_id, "corner_radius"));
    try std.testing.expect(try state.world.hasComponent(play_button, runtime.ui_button_component_id));
    try std.testing.expectEqualStrings(editor_command_play_toggle, try state.world.getString(play_button, runtime.ui_command_component_id, "command"));

    const play_label = state.world.findEntityById("scrapbot.editor.controls.play.label") orelse return error.TestExpectedEqual;
    const play_label_position = try state.world.getVec3(play_label, runtime.ui_text_component_id, "position");
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), play_label_position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), play_label_position[1], 0.001);
    const play_label_item = (try ui_layout.layoutItem(state.world, play_label)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("scrapbot.editor.controls.play", play_label_item.parent);
    const resolved_play_label = try resolveUiLayout(state.world, play_label, play_label_position);
    const play_label_text = runtime.UiText{
        .entity = play_label,
        .id = "scrapbot.editor.controls.play.label",
        .name = "Editor Play Label",
        .position = play_label_position,
        .size = try state.world.getFloat(play_label, runtime.ui_text_component_id, "size"),
        .color = try state.world.getVec3(play_label, runtime.ui_text_component_id, "color"),
        .value = try state.world.getString(play_label, runtime.ui_text_component_id, "value"),
    };
    const centered_play_label = try resolveUiTextPosition(state.world, play_label, play_label_text, resolved_play_label.position);
    const expected_play_label_x = play_position[0] + (editor_control_button_width - editorTextWidth("PAUSE", 1.0)) * 0.5;
    const expected_play_label_y = play_position[1] + (editor_control_button_height - editorTextHeight(1.0)) * 0.5;
    try std.testing.expectApproxEqAbs(expected_play_label_x, centered_play_label[0], 0.001);
    try std.testing.expectApproxEqAbs(expected_play_label_y, centered_play_label[1], 0.001);

    const input = try renderFrameInput(state.world);
    var texts = state.world.uiTexts();
    while (texts.next()) |text| {
        try std.testing.expect(std.mem.indexOf(u8, text.value, "IN W") == null);
    }

    try std.testing.expect(!input.ui_visible);
    try std.testing.expect(input.debug_overlay_visible);
    const left_sidebar = editorLeftSidebarRect(input);
    const expected_left_panel = editorSidebarPanelRect(left_sidebar);
    const debug_panel = state.world.findEntityById("scrapbot.editor.debug.panel") orelse return error.TestExpectedEqual;
    const debug_panel_x = state.world.getVec3(debug_panel, runtime.ui_rect_component_id, "position") catch |err| return mapWorldError(err);
    const debug_panel_radius = try state.world.getFloat(debug_panel, runtime.ui_rect_component_id, "corner_radius");
    try std.testing.expectApproxEqAbs(expected_left_panel.x, debug_panel_x[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), debug_panel_radius, 0.001);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.shell.top_bar") != null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.shell.bottom_bar") != null);
    const left_sidebar_entity = state.world.findEntityById("scrapbot.editor.shell.left_sidebar") orelse return error.TestExpectedEqual;
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.shell.right_sidebar") != null);
    const left_sidebar_color = try state.world.getVec3(left_sidebar_entity, runtime.ui_rect_component_id, "color");
    const debug_panel_color = try state.world.getVec3(debug_panel, runtime.ui_rect_component_id, "color");
    for (0..3) |channel| {
        try std.testing.expectApproxEqAbs(editor_palette.panel[channel], left_sidebar_color[channel], 0.001);
        try std.testing.expectApproxEqAbs(editor_palette.panel[channel], debug_panel_color[channel], 0.001);
    }
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.shell.viewport.frame") == null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.shell.viewport.border.top") == null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.shell.viewport.border.left") == null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.shell.viewport.border.right") == null);
    const bottom = editorBottomBarRect(input);
    const status = state.world.findEntityById("scrapbot.editor.bottom.status") orelse return error.TestExpectedEqual;
    const status_position = try state.world.getVec3(status, runtime.ui_text_component_id, "position");
    const status_size = try state.world.getFloat(status, runtime.ui_text_component_id, "size");
    try std.testing.expectApproxEqAbs(bottom.y + editor_bar_text_offset_y, status_position[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_text_size), status_size, 0.001);
    try std.testing.expect(status_position[1] + editorTextHeight(status_size) <= bottom.y + bottom.height);

    try state.queueUiDraw();
    try std.testing.expectEqual(@as(usize, 1), state.uiDrawCommandCount());
}

test "editor shell body uses hgroup slot for the game viewport" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    const input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{
            .left_sidebar_width = 360.0,
            .right_sidebar_width = 420.0,
        },
    };
    try state.extractSceneWithInput(.{ .world = &scene_world }, input);

    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.ui_hgroup_component_id));
    const game_slot = state.world.findEntityById("scrapbot.editor.shell.game_viewport") orelse return error.TestExpectedEqual;
    const slot_rect = try ui_layout.resolvedItemRect(state.world, game_slot);
    const left_splitter = editorSplitterRect(input, .left) orelse return error.TestExpectedEqual;
    const viewport = editorGameViewport(input);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), left_splitter.width, 0.001);
    try std.testing.expectApproxEqAbs(viewport.x, slot_rect.position[0], 0.001);
    try std.testing.expectApproxEqAbs(viewport.y, slot_rect.position[1], 0.001);
    try std.testing.expectApproxEqAbs(viewport.width, slot_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(viewport.height, slot_rect.size[1], 0.001);
    const inactive_splitter = state.world.findEntityById("scrapbot.editor.shell.splitter.left") orelse return error.TestExpectedEqual;
    try std.testing.expect(try state.world.hasComponent(inactive_splitter, runtime.ui_spacer_component_id));
    try std.testing.expect(!(try state.world.hasComponent(inactive_splitter, runtime.ui_separator_component_id)));
    const splitter_hit_area = state.world.findEntityById("scrapbot.editor.shell.splitter.left.hit_area") orelse return error.TestExpectedEqual;
    try std.testing.expect(try state.world.hasComponent(splitter_hit_area, runtime.ui_hit_area_component_id));
    try std.testing.expect(try state.world.hasComponent(splitter_hit_area, runtime.ui_button_component_id));
    try std.testing.expect(try state.world.hasComponent(splitter_hit_area, runtime.ui_command_component_id));
    try std.testing.expect(!(try state.world.hasComponent(splitter_hit_area, runtime.ui_rect_component_id)));
    const hit_area_size = try state.world.getVec3(splitter_hit_area, runtime.ui_hit_area_component_id, "size");
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), hit_area_size[0], 0.001);

    var hover_state = try RenderEcsState.init(std.testing.allocator);
    defer hover_state.deinit();
    const hover_point = [2]f32{ left_splitter.x + left_splitter.width + 3.0, left_splitter.y + 40.0 };
    try std.testing.expect(!left_splitter.contains(hover_point));
    try hover_state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = input.editor,
        .pointer = .{
            .position = hover_point,
            .has_position = true,
        },
    });
    const hit = (try ui_layout.commandAt(hover_state.world, hover_point)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings(editor_command_splitter_left, hit.command);
    const hover_splitter = hover_state.world.findEntityById("scrapbot.editor.shell.splitter.left") orelse return error.TestExpectedEqual;
    const hover_color = try hover_state.world.getVec3(hover_splitter, runtime.ui_separator_component_id, "color");
    for (0..3) |channel| {
        try std.testing.expectApproxEqAbs(editor_palette.text_dim[channel], hover_color[channel], 0.001);
    }
}

test "editor splitters resize sidebars through editor state" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    var editor_state = EditorState{};
    const initial_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    const left_splitter = editorSplitterRect(initial_input, .left) orelse return error.TestExpectedEqual;
    const press_point = [2]f32{ left_splitter.x + left_splitter.width + 3.0, left_splitter.y + 40.0 };
    try std.testing.expect(!left_splitter.contains(press_point));
    try std.testing.expectEqual(EditorSplitter.left, (try routeEditorSplitterAt(std.testing.allocator, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{ .position = press_point, .has_position = true },
    })).?);

    const press = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{
            .position = press_point,
            .has_position = true,
            .primary_pressed = true,
            .primary_down = true,
        },
    });
    try std.testing.expect(press.consumed_pointer);
    try std.testing.expectEqual(EditorSplitter.left, editor_state.dragging_splitter);
    const before_width = editor_state.left_sidebar_width;

    const drag = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = editorFrameState(&world, editor_state),
        .pointer = .{
            .position = .{ press_point[0] + 200.0, press_point[1] },
            .has_position = true,
            .primary_down = true,
        },
    });
    try std.testing.expect(drag.consumed_pointer);
    try std.testing.expect(editor_state.left_sidebar_width > before_width);
    try std.testing.expect(editor_state.left_sidebar_width > editor_left_sidebar_target_width);

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = editorFrameState(&world, editor_state),
        .pointer = .{
            .position = .{ press_point[0] + 200.0, press_point[1] },
            .has_position = true,
            .primary_released = true,
        },
    });
    try std.testing.expectEqual(EditorSplitter.none, editor_state.dragging_splitter);
}

test "editor cursor changes over and during splitter drag" {
    const input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    const left_splitter = editorSplitterRect(input, .left) orelse return error.TestExpectedEqual;
    const hover_point = [2]f32{ left_splitter.x + left_splitter.width + 3.0, left_splitter.y + 40.0 };

    try std.testing.expectEqual(EditorCursorKind.default, try editorCursorKind(std.testing.allocator, input));
    try std.testing.expectEqual(EditorCursorKind.resize_ew, try editorCursorKind(std.testing.allocator, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{
            .position = hover_point,
            .has_position = true,
        },
    }));
    try std.testing.expectEqual(EditorCursorKind.resize_ew, try editorCursorKind(std.testing.allocator, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{ .dragging_splitter = .left },
        .pointer = .{
            .position = .{ 900.0, 200.0 },
            .has_position = true,
        },
    }));
    try std.testing.expectEqual(EditorCursorKind.default, try editorCursorKind(std.testing.allocator, .{
        .debug_overlay_visible = false,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{ .dragging_splitter = .left },
        .pointer = .{
            .position = hover_point,
            .has_position = true,
        },
    }));
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
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .fps = 60.0,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .system_profiles = &profiles,
    };
    try state.extractSceneWithInput(.{ .world = &scene_world }, frame_input);

    try std.testing.expect(state.world.uiTextCount() >= 11);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.debug.panel") != null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.debug.accent") == null);

    var saw_header = false;
    var saw_pause = false;
    var saw_no_selection = false;
    var texts = state.world.uiTexts();
    while (texts.next()) |text| {
        try std.testing.expect(std.mem.indexOf(u8, text.value, "IN W") == null);
        try std.testing.expect(std.mem.indexOf(u8, text.value, "ROWS ") == null);
        try std.testing.expect(text.size >= 1.0);
        if (std.mem.indexOf(u8, text.value, "SYS 2 AVG 120F SNAP 3HZ") != null) {
            saw_header = true;
        }
        if (std.mem.indexOf(u8, text.value, "PAUSE") != null) {
            saw_pause = true;
        }
        if (std.mem.indexOf(u8, text.value, "NO ENTITY SELECTED") != null) {
            saw_no_selection = true;
        }
    }

    try std.testing.expect(saw_header);
    try std.testing.expect(saw_pause);
    try std.testing.expect(saw_no_selection);

    const table = state.world.findEntityById("scrapbot.editor.debug.systems.table") orelse return error.TestExpectedEqual;
    const row0_label = state.world.findEntityById("scrapbot.editor.debug.systems.row.0.label") orelse return error.TestExpectedEqual;
    const row0_duration = state.world.findEntityById("scrapbot.editor.debug.systems.row.0.duration") orelse return error.TestExpectedEqual;
    const row1_label = state.world.findEntityById("scrapbot.editor.debug.systems.row.1.label") orelse return error.TestExpectedEqual;
    const row1_duration = state.world.findEntityById("scrapbot.editor.debug.systems.row.1.duration") orelse return error.TestExpectedEqual;
    const list_clip = editorSystemListClipRect(frame_input);
    const table_size = try state.world.getVec3(table, runtime.ui_rect_component_id, "size");
    try std.testing.expectApproxEqAbs(list_clip.size[0], table_size[0], 0.001);
    try std.testing.expectApproxEqAbs(editorSystemTableContentHeight(2), table_size[1], 0.001);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.debug.systems.row.0") == null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.debug.systems.row.1") == null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.debug.systems.separator.1") == null);
    try std.testing.expectEqualStrings("spawn_initial", try state.world.getString(row0_label, runtime.ui_text_component_id, "value"));
    try std.testing.expectEqualStrings("--", try state.world.getString(row0_duration, runtime.ui_text_component_id, "value"));
    try std.testing.expectEqualStrings("rotate_cubes", try state.world.getString(row1_label, runtime.ui_text_component_id, "value"));
    try std.testing.expectEqualStrings("57us", try state.world.getString(row1_duration, runtime.ui_text_component_id, "value"));
}

test "debug overlay extracts entity list below system list" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const player = try scene_world.createAuthoredEntity("player", "Player");
    try scene_world.setTransform(player, .{});
    const crate = try scene_world.createEntity("crate", "Crate");
    try scene_world.setTransform(crate, .{});
    const camera = try scene_world.createAuthoredEntity("camera", "Camera");
    try scene_world.setTransform(camera, .{});

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{ .id = "tick", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
    };

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .system_profiles = &profiles,
        .editor = .{ .selected_entity = camera },
    };
    try state.extractSceneWithInput(.{ .world = &scene_world }, frame_input);

    const system_panel = state.world.findEntityById("scrapbot.editor.debug.panel") orelse return error.TestExpectedEqual;
    const entity_panel = state.world.findEntityById("scrapbot.editor.entities.panel") orelse return error.TestExpectedEqual;
    const entity_header = state.world.findEntityById("scrapbot.editor.entities.header") orelse return error.TestExpectedEqual;
    const row0_label = state.world.findEntityById("scrapbot.editor.entities.row.0.label") orelse return error.TestExpectedEqual;
    const row1_label = state.world.findEntityById("scrapbot.editor.entities.row.1.label") orelse return error.TestExpectedEqual;
    const row1_components = state.world.findEntityById("scrapbot.editor.entities.row.1.components") orelse return error.TestExpectedEqual;
    const row2_label = state.world.findEntityById("scrapbot.editor.entities.row.2.label") orelse return error.TestExpectedEqual;
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.entities.row.2.highlight") != null);

    const system_position = try state.world.getVec3(system_panel, runtime.ui_rect_component_id, "position");
    const system_size = try state.world.getVec3(system_panel, runtime.ui_rect_component_id, "size");
    const entity_position = try state.world.getVec3(entity_panel, runtime.ui_rect_component_id, "position");
    const row0_color = try state.world.getVec3(row0_label, runtime.ui_text_component_id, "color");
    const row1_color = try state.world.getVec3(row1_label, runtime.ui_text_component_id, "color");
    const row2_color = try state.world.getVec3(row2_label, runtime.ui_text_component_id, "color");
    try std.testing.expect(entity_position[1] >= system_position[1] + system_size[1] + editor_left_panel_gap - 0.001);
    try std.testing.expectEqualStrings("ENTITIES 3", try state.world.getString(entity_header, runtime.ui_text_component_id, "value"));
    try std.testing.expectEqualStrings("Player", try state.world.getString(row0_label, runtime.ui_text_component_id, "value"));
    try std.testing.expectEqualStrings("Crate", try state.world.getString(row1_label, runtime.ui_text_component_id, "value"));
    try std.testing.expectEqualStrings("Camera", try state.world.getString(row2_label, runtime.ui_text_component_id, "value"));
    try std.testing.expectEqualStrings("1C", try state.world.getString(row1_components, runtime.ui_text_component_id, "value"));
    try std.testing.expectEqual(editor_palette.text, row0_color);
    try std.testing.expectEqual(editor_palette.text_dim, row1_color);
    try std.testing.expectEqual(editor_palette.accent_soft, row2_color);
}

test "editor entity list scroll state responds to wheel input" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    for (0..12) |index| {
        const id = try std.fmt.allocPrint(std.testing.allocator, "entity-{d}", .{index});
        defer std.testing.allocator.free(id);
        const name = try std.fmt.allocPrint(std.testing.allocator, "Entity {d}", .{index});
        defer std.testing.allocator.free(name);
        _ = try world.createEntity(id, name);
    }

    var editor_state = EditorState{};
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    const list_clip = editorEntityListClipRect(&world, frame_input);
    const update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .delta_seconds = 1.0,
        .pointer = .{
            .position = .{ list_clip.position[0] + 4.0, list_clip.position[1] + 4.0 },
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });

    try std.testing.expect(update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel), editor_state.entity_scroll_target_y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), editor_state.system_scroll_target_y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), editor_state.inspector_scroll_target_y, 0.001);
}

test "editor entity list row click selects entity" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    _ = try world.createEntity("first", "First");
    const second = try world.createEntity("second", "Second");
    _ = try world.createEntity("third", "Third");

    var editor_state = EditorState{};
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    const list_clip = editorEntityListClipRect(&world, frame_input);
    const press = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{
            .position = .{
                list_clip.position[0] + editor_entity_row_label_padding_x,
                list_clip.position[1] + editor_entity_card_padding_y + editor_entity_row_stride + 2.0,
            },
            .has_position = true,
            .primary_pressed = true,
        },
    });

    try std.testing.expect(press.consumed_pointer);
    try std.testing.expect(editorEntityHandlesEqual(editor_state.selected_entity, second));
    try std.testing.expect(editorEntityHandlesEqual(editorFrameState(&world, editor_state).selected_entity, second));
}

test "editor renders inspector for non-renderable entity list selection" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    _ = try world.createEntity("visible", "Visible");
    const resource = try world.createEntity("resource", "Resource");

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractSceneWithInput(.{ .world = &world }, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{ .selected_entity = resource },
    });

    const entity_label = state.world.findEntityById("scrapbot.editor.inspector.entity") orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("Resource  resource", try state.world.getString(entity_label, runtime.ui_text_component_id, "value"));
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.gizmo.x") == null);
}

test "editor render skips stale selected entity handles" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractSceneWithInput(.{ .world = &world }, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{ .selected_entity = .{ .index = 99, .generation = 99 } },
    });

    try std.testing.expect(state.world.findEntityById("scrapbot.editor.gizmo.x") == null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.inspector.unavailable") != null);
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
        .editor = .{ .system_scroll_y = editor_system_row_stride * 2.0 },
    });

    var texts = state.world.uiTexts();
    while (texts.next()) |text| {
        try std.testing.expect(std.mem.indexOf(u8, text.value, "ROWS ") == null);
    }

    try std.testing.expect(state.world.findEntityById("scrapbot.editor.debug.systems.row.0.label") != null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.debug.systems.row.2.label") != null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.debug.systems.row.8.label") != null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.debug.systems.table") != null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.debug.systems.row.0") == null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.debug.systems.separator.1") == null);
    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.ui_scroll_view_component_id));
    try std.testing.expectEqual(@as(usize, 0), state.world.componentInstanceCountFor(runtime.ui_vgroup_component_id));
    try std.testing.expect(state.world.componentInstanceCountFor(runtime.ui_layout_item_component_id) >= profiles.len * 2 + 1);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.debug.systems.scrollbar.track") != null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.debug.systems.scrollbar.thumb") != null);
}

test "editor overlay extracts selected entity inspector and translate gizmo" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const entity = try scene_world.createEntity("selected", "Selected Box");
    try scene_world.setTransform(entity, .{ .position = .{ 0.25, 0.5, 0.0 } });
    try scene_world.setGeometryPrimitive(entity, .{
        .primitive = "uv_sphere",
        .segments = 16,
        .rings = 8,
    });
    try scene_world.setSurfaceMaterial(entity, .{ .base_color = .{ 0.8, 0.4, 0.2 } });
    try scene_world.setUiToggle(entity, .{ .checked = true });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1920.0,
        .viewport_height = 1080.0,
        .editor = .{
            .selected_entity = entity,
            .entity_count = scene_world.entityCount(),
            .component_instance_count = scene_world.componentInstanceCount(),
            .renderable_count = scene_world.renderableMeshCount(),
        },
    };
    try state.extractSceneWithInput(.{ .world = &scene_world }, frame_input);

    try std.testing.expectEqual(@as(usize, 4), state.world.renderableMeshCount());
    try std.testing.expectEqual(@as(usize, 4), state.extractedRenderableMeshes().len);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.inspector.panel") != null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.inspector.accent") == null);

    var saw_entity_header = false;
    var texts = state.world.uiTexts();
    while (texts.next()) |text| {
        if (std.mem.indexOf(u8, text.value, "Selected Box") != null) {
            saw_entity_header = true;
        }
    }
    try std.testing.expect(saw_entity_header);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.inspector.components") != null);
    try std.testing.expect(try state.world.hasComponent(
        state.world.findEntityById("scrapbot.editor.inspector.components") orelse return error.TestExpectedEqual,
        runtime.ui_vgroup_component_id,
    ));
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.inspector.component.0") != null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.inspector.component.1") != null);
    try std.testing.expect(state.world.findEntityById("scrapbot.editor.inspector.component.separator.1") != null);

    const geometry_card = state.world.findEntityById("scrapbot.editor.inspector.component.1") orelse return error.TestExpectedEqual;
    const geometry_title = state.world.findEntityById("scrapbot.editor.inspector.component.1.title") orelse return error.TestExpectedEqual;
    const transform_position_label = state.world.findEntityById("scrapbot.editor.inspector.component.0.field.0.label") orelse return error.TestExpectedEqual;
    const transform_x_label = state.world.findEntityById("scrapbot.editor.inspector.component.0.field.0.lane_label.0") orelse return error.TestExpectedEqual;
    const transform_position_row = state.world.findEntityById("scrapbot.editor.inspector.component.0.field.0.row") orelse return error.TestExpectedEqual;
    const transform_position_input_0 = state.world.findEntityById("scrapbot.editor.inspector.component.0.field.0.input.0") orelse return error.TestExpectedEqual;
    const transform_position_value_0 = state.world.findEntityById("scrapbot.editor.inspector.component.0.field.0.value.0") orelse return error.TestExpectedEqual;
    const transform_rotation_row = state.world.findEntityById("scrapbot.editor.inspector.component.0.field.1.row") orelse return error.TestExpectedEqual;
    const geometry_field_row = state.world.findEntityById("scrapbot.editor.inspector.component.1.field.0.row") orelse return error.TestExpectedEqual;
    const geometry_field_label = state.world.findEntityById("scrapbot.editor.inspector.component.1.field.0.label") orelse return error.TestExpectedEqual;
    const geometry_field_label_cell = state.world.findEntityById("scrapbot.editor.inspector.component.1.field.0.label_cell") orelse return error.TestExpectedEqual;
    const geometry_field_value_cell = state.world.findEntityById("scrapbot.editor.inspector.component.1.field.0.value_cell") orelse return error.TestExpectedEqual;
    const geometry_field_input = state.world.findEntityById("scrapbot.editor.inspector.component.1.field.0.select") orelse return error.TestExpectedEqual;
    const geometry_field_value = state.world.findEntityById("scrapbot.editor.inspector.component.1.field.0.select.value") orelse return error.TestExpectedEqual;
    const geometry_next_row = state.world.findEntityById("scrapbot.editor.inspector.component.1.field.1.row") orelse return error.TestExpectedEqual;
    const material_swatch = state.world.findEntityById("scrapbot.editor.inspector.component.2.field.0.swatch") orelse return error.TestExpectedEqual;
    const material_red = state.world.findEntityById("scrapbot.editor.inspector.component.2.field.0.lane_label.0") orelse return error.TestExpectedEqual;
    const material_green = state.world.findEntityById("scrapbot.editor.inspector.component.2.field.0.lane_label.1") orelse return error.TestExpectedEqual;
    const material_blue = state.world.findEntityById("scrapbot.editor.inspector.component.2.field.0.lane_label.2") orelse return error.TestExpectedEqual;
    const toggle_input = state.world.findEntityById("scrapbot.editor.inspector.component.3.field.0.toggle") orelse return error.TestExpectedEqual;
    const toggle_value = state.world.findEntityById("scrapbot.editor.inspector.component.3.field.0.toggle.label") orelse return error.TestExpectedEqual;
    const separator = state.world.findEntityById("scrapbot.editor.inspector.component.separator.1") orelse return error.TestExpectedEqual;
    const card_position = try state.world.getVec3(geometry_card, runtime.ui_rect_component_id, "position");
    const card_size = try state.world.getVec3(geometry_card, runtime.ui_rect_component_id, "size");
    const title_position = try state.world.getVec3(geometry_title, runtime.ui_text_component_id, "position");
    const title_size = try state.world.getFloat(geometry_title, runtime.ui_text_component_id, "size");
    const title_value = try state.world.getString(geometry_title, runtime.ui_text_component_id, "value");
    const label_position = try state.world.getVec3(geometry_field_label, runtime.ui_text_component_id, "position");
    const input_position = try state.world.getVec3(geometry_field_input, runtime.ui_rect_component_id, "position");
    const value_position = try state.world.getVec3(geometry_field_value, runtime.ui_text_component_id, "position");
    const transform_lane_value_position = try state.world.getVec3(transform_position_value_0, runtime.ui_text_component_id, "position");
    const label_value = try state.world.getString(geometry_field_label, runtime.ui_text_component_id, "value");
    const field_value = try state.world.getString(geometry_field_value, runtime.ui_text_component_id, "value");
    try std.testing.expectEqualStrings("position", try state.world.getString(transform_position_label, runtime.ui_text_component_id, "value"));
    try std.testing.expectEqualStrings("X", try state.world.getString(transform_x_label, runtime.ui_text_component_id, "value"));
    try std.testing.expect(try state.world.hasComponent(transform_position_input_0, runtime.ui_rect_component_id));
    try std.testing.expect((try state.world.getString(transform_position_value_0, runtime.ui_text_component_id, "value")).len > 0);
    try std.testing.expect(try state.world.hasComponent(material_swatch, runtime.ui_rect_component_id));
    const red_color = try state.world.getVec3(material_red, runtime.ui_text_component_id, "color");
    const green_color = try state.world.getVec3(material_green, runtime.ui_text_component_id, "color");
    const blue_color = try state.world.getVec3(material_blue, runtime.ui_text_component_id, "color");
    try std.testing.expect(red_color[0] > red_color[1]);
    try std.testing.expect(green_color[1] > green_color[0]);
    try std.testing.expect(blue_color[2] > blue_color[0]);
    try std.testing.expect(try state.world.hasComponent(toggle_input, runtime.ui_rect_component_id));
    try std.testing.expectEqualStrings("ON", try state.world.getString(toggle_value, runtime.ui_text_component_id, "value"));
    const separator_size = try state.world.getVec3(separator, runtime.ui_separator_component_id, "size");
    const sidebar = editorSidebarPanelRect(editorRightSidebarRect(frame_input));
    const resolved_card_layout = try resolveUiLayout(state.world, geometry_card, card_position);
    const resolved_separator_layout = try resolveUiLayout(state.world, separator, try state.world.getVec3(separator, runtime.ui_separator_component_id, "position"));
    const transform_card = state.world.findEntityById("scrapbot.editor.inspector.component.0") orelse return error.TestExpectedEqual;
    const transform_card_size = try state.world.getVec3(transform_card, runtime.ui_rect_component_id, "size");
    const resolved_transform_card_layout = try resolveUiLayout(state.world, transform_card, try state.world.getVec3(transform_card, runtime.ui_rect_component_id, "position"));

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), card_position[0], 0.001);
    try std.testing.expectApproxEqAbs(sidebar.width, card_size[0], 0.001);
    try std.testing.expectApproxEqAbs(sidebar.x, resolved_card_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(editor_panel_corner_radius, try state.world.getFloat(geometry_card, runtime.ui_rect_component_id, "corner_radius"), 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_separator_height, separator_size[1], 0.001);
    try std.testing.expectApproxEqAbs(sidebar.width, separator_size[0], 0.001);
    try std.testing.expectApproxEqAbs(resolved_transform_card_layout.position[1] + transform_card_size[1] + editor_inspector_card_gap, resolved_separator_layout.position[1], 0.001);
    try std.testing.expect(title_position[1] >= card_position[1] + editor_inspector_card_padding_y);
    try std.testing.expect(title_position[1] + editorTextHeight(title_size) <= card_position[1] + card_size[1] - editor_inspector_card_padding_y);
    try std.testing.expect(editorTextWidth(title_value, title_size) <= card_size[0] - editor_inspector_card_padding_x * 2.0);
    const field_layout = editorInspectorFieldLayout(card_size[0]);
    const row_position = try state.world.getVec3(geometry_field_row, runtime.ui_table_component_id, "position");
    const row_layout = try resolveUiLayout(state.world, geometry_field_row, row_position);
    const row_size = try uiLayoutItemSize(state.world, geometry_field_row);
    const next_row_position = try state.world.getVec3(geometry_next_row, runtime.ui_table_component_id, "position");
    const next_row_layout = try resolveUiLayout(state.world, geometry_next_row, next_row_position);
    const transform_position_row_position = try state.world.getVec3(transform_position_row, runtime.ui_table_component_id, "position");
    const transform_position_row_layout = try resolveUiLayout(state.world, transform_position_row, transform_position_row_position);
    const transform_position_row_size = try uiLayoutItemSize(state.world, transform_position_row);
    const transform_rotation_row_position = try state.world.getVec3(transform_rotation_row, runtime.ui_table_component_id, "position");
    const transform_rotation_row_layout = try resolveUiLayout(state.world, transform_rotation_row, transform_rotation_row_position);
    const label_cell_rect = try ui_layout.resolvedItemRect(state.world, geometry_field_label_cell);
    const value_cell_rect = try ui_layout.resolvedItemRect(state.world, geometry_field_value_cell);
    const input_layout = try resolveUiLayout(state.world, geometry_field_input, input_position);
    const input_size = try uiLayoutItemSize(state.world, geometry_field_input);
    const value_text_layout = try resolveUiLayout(state.world, geometry_field_value, value_position);
    const transform_position_input_position = try state.world.getVec3(transform_position_input_0, runtime.ui_rect_component_id, "position");
    const transform_position_lane_layout = try resolveUiLayout(state.world, transform_position_input_0, transform_position_input_position);
    const transform_lane_text_layout = try resolveUiLayout(state.world, transform_position_value_0, transform_lane_value_position);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), label_position[0], 0.001);
    try std.testing.expectApproxEqAbs(resolved_card_layout.position[0] + field_layout.label_x, label_cell_rect.position[0], 0.001);
    try std.testing.expectApproxEqAbs(field_layout.label_width, label_cell_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(resolved_card_layout.position[0] + field_layout.value_x, value_cell_rect.position[0], 0.001);
    try std.testing.expectApproxEqAbs(field_layout.value_width, value_cell_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(value_cell_rect.position[0] + editor_inspector_input_cell_padding, input_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_cell_padding, input_position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), editor_inspector_input_padding_x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), editor_inspector_input_padding_y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), editor_inspector_input_cell_padding, 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_border_thickness + editor_inspector_input_padding_x, editor_inspector_input_text_offset_x, 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_border_thickness + editor_inspector_input_padding_y, editor_inspector_input_text_offset_y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), editor_inspector_field_row_margin_y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 8.0), editor_inspector_input_corner_radius, 0.001);
    try std.testing.expect(input_size[1] >= editorTextHeight(editor_inspector_text_size) + editor_inspector_input_text_offset_y * 2.0);
    try std.testing.expectApproxEqAbs(editor_inspector_field_row_height, row_size[1], 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_cell_padding, input_layout.position[0] - value_cell_rect.position[0], 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_cell_padding, (value_cell_rect.position[0] + value_cell_rect.size[0]) - (input_layout.position[0] + input_size[0]), 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_cell_padding, input_layout.position[1] - row_layout.position[1], 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_cell_padding, (row_layout.position[1] + row_size[1]) - (input_layout.position[1] + input_size[1]), 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_field_row_margin_y, next_row_layout.position[1] - (row_layout.position[1] + row_size[1]), 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_cell_padding, transform_position_lane_layout.position[1] - transform_position_row_layout.position[1], 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_field_row_margin_y, transform_rotation_row_layout.position[1] - (transform_position_row_layout.position[1] + transform_position_row_size[1]), 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_text_offset_x, value_position[0], 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_text_offset_y, value_position[1], 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_text_offset_x, transform_lane_value_position[0], 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_text_offset_y, transform_lane_value_position[1], 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_text_offset_x, value_text_layout.position[0] - input_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_text_offset_y, value_text_layout.position[1] - input_layout.position[1], 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_text_offset_x, transform_lane_text_layout.position[0] - transform_position_lane_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_text_offset_y, transform_lane_text_layout.position[1] - transform_position_lane_layout.position[1], 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_corner_radius, try state.world.getFloat(geometry_field_input, runtime.ui_rect_component_id, "corner_radius"), 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_corner_radius, try state.world.getFloat(transform_position_input_0, runtime.ui_rect_component_id, "corner_radius"), 0.001);
    try std.testing.expectEqualStrings("primitive", label_value);
    try std.testing.expectEqualStrings("uv_sphere >", field_value);
}

test "editor inspector component stack resolves inside scroll view clip" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const entity = try scene_world.createEntity("selected", "Selected Box");
    try scene_world.setTransform(entity, .{ .position = .{ 0.25, 0.5, 0.0 } });
    try scene_world.setGeometryPrimitive(entity, .{
        .primitive = "uv_sphere",
        .segments = 16,
        .rings = 8,
    });
    try scene_world.setSurfaceMaterial(entity, .{ .base_color = .{ 0.8, 0.4, 0.2 } });
    try scene_world.setShadowCaster(entity);
    try scene_world.setShadowReceiver(entity);

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{
            .selected_entity = entity,
            .inspector_scroll_y = 80.0,
        },
    };
    try state.extractSceneWithInput(.{ .world = &scene_world }, frame_input);

    const scroll = state.world.findEntityById("scrapbot.editor.inspector.scroll") orelse return error.TestExpectedEqual;
    const stack = state.world.findEntityById("scrapbot.editor.inspector.components") orelse return error.TestExpectedEqual;
    const first_card = state.world.findEntityById("scrapbot.editor.inspector.component.0") orelse return error.TestExpectedEqual;
    try std.testing.expect(try state.world.hasComponent(scroll, runtime.ui_scroll_view_component_id));
    try std.testing.expectEqualStrings("scrapbot.editor.inspector.scroll", try state.world.getString(stack, runtime.ui_layout_item_component_id, "parent"));

    const clip = editorInspectorScrollClipRect(frame_input);
    const card_position = try state.world.getVec3(first_card, runtime.ui_rect_component_id, "position");
    const resolved = try resolveUiLayout(state.world, first_card, card_position);
    const resolved_clip = resolved.clip orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(clip.position[0], resolved_clip.position[0], 0.001);
    try std.testing.expectApproxEqAbs(clip.position[1], resolved_clip.position[1], 0.001);
    try std.testing.expectApproxEqAbs(clip.size[0], resolved_clip.size[0], 0.001);
    try std.testing.expectApproxEqAbs(clip.size[1], resolved_clip.size[1], 0.001);
    try std.testing.expectApproxEqAbs(clip.position[1] - 80.0, resolved.position[1], 0.001);
}

test "editor inspector field rows split labels and editors evenly" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const entity = try scene_world.createEntity("renderer", "Renderer Settings");
    try scene_world.setRendererSettings(entity, .{
        .entity = entity,
        .id = "renderer",
        .name = "Renderer Settings",
        .hdr = true,
        .tone_mapping = "aces",
        .exposure = -0.45,
        .postprocess_enabled = true,
        .antialiasing = "fxaa",
        .bloom_enabled = true,
        .bloom_threshold = 1.25,
        .bloom_intensity = 0.56,
        .bloom_radius = 0.92,
        .vignette_enabled = true,
        .vignette_strength = 0.38,
        .vignette_radius = 0.84,
        .chromatic_aberration_enabled = true,
        .chromatic_aberration_strength = 0.004,
    });

    var default_state = try RenderEcsState.init(std.testing.allocator);
    defer default_state.deinit();
    const default_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{ .selected_entity = entity },
    };
    try default_state.extractSceneWithInput(.{ .world = &scene_world }, default_input);
    const default_label = default_state.world.findEntityById("scrapbot.editor.inspector.component.0.field.13.label") orelse return error.TestExpectedEqual;
    const default_label_text = try default_state.world.getString(default_label, runtime.ui_text_component_id, "value");
    try std.testing.expect(std.mem.indexOf(u8, default_label_text, "...") != null);

    var wide_state = try RenderEcsState.init(std.testing.allocator);
    defer wide_state.deinit();
    const wide_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 2400.0,
        .viewport_height = 720.0,
        .editor = .{
            .selected_entity = entity,
            .right_sidebar_width = 1400.0,
        },
    };
    try wide_state.extractSceneWithInput(.{ .world = &scene_world }, wide_input);
    const wide_label = wide_state.world.findEntityById("scrapbot.editor.inspector.component.0.field.13.label") orelse return error.TestExpectedEqual;
    const wide_label_cell = wide_state.world.findEntityById("scrapbot.editor.inspector.component.0.field.13.label_cell") orelse return error.TestExpectedEqual;
    const wide_value_cell = wide_state.world.findEntityById("scrapbot.editor.inspector.component.0.field.13.value_cell") orelse return error.TestExpectedEqual;
    const wide_input_box = wide_state.world.findEntityById("scrapbot.editor.inspector.component.0.field.13.input") orelse return error.TestExpectedEqual;
    const wide_label_text = try wide_state.world.getString(wide_label, runtime.ui_text_component_id, "value");
    try std.testing.expectEqualStrings("chromatic_aberration_strength", wide_label_text);

    const wide_label_cell_rect = try ui_layout.resolvedItemRect(wide_state.world, wide_label_cell);
    const wide_value_cell_rect = try ui_layout.resolvedItemRect(wide_state.world, wide_value_cell);
    const wide_input_rect = try ui_layout.resolvedItemRect(wide_state.world, wide_input_box);
    try std.testing.expectApproxEqAbs(wide_label_cell_rect.size[0], wide_value_cell_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(editorInspectorFieldLayout(editorInspectorScrollClipRect(wide_input).size[0]).label_width, wide_label_cell_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(wide_value_cell_rect.position[0], wide_input_rect.position[0], 0.001);

    const inspector_scroll_y = 220.0;
    var editor_state = EditorState{
        .selected_entity = entity,
        .right_sidebar_width = wide_input.editor.right_sidebar_width,
        .inspector_scroll_y = inspector_scroll_y,
        .inspector_scroll_target_y = inspector_scroll_y,
    };
    const clip = editorInspectorScrollClipRect(wide_input);
    const field_layout = editorInspectorFieldLayout(clip.size[0]);
    const field_y = clip.position[1] +
        -inspector_scroll_y +
        editor_inspector_card_padding_y +
        editorTextHeight(editor_inspector_text_size) +
        editor_panel_label_gap +
        13.0 * editor_inspector_field_row_stride;
    const row_y = field_y + editor_inspector_field_control_offset_y - editor_inspector_input_cell_padding;
    const update = try updateEditorState(std.testing.allocator, &scene_world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = wide_input.viewport_width,
        .viewport_height = wide_input.viewport_height,
        .editor = wide_input.editor,
        .pointer = .{
            .position = .{
                clip.position[0] + field_layout.value_x + editor_inspector_input_cell_padding + editor_inspector_input_text_offset_x,
                row_y + editor_inspector_field_row_height * 0.5,
            },
            .has_position = true,
            .primary_pressed = true,
            .primary_down = true,
        },
    });
    try std.testing.expect(update.consumed_pointer);
    try std.testing.expect(editor_state.selected_property.matches(entity, runtime.renderer_component_id, "chromatic_aberration_strength"));
}

test "editor inspector scroll state responds to wheel input" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("selected", "Selected Box");
    try world.setTransform(entity, .{ .position = .{ 0.25, 0.5, 0.0 } });
    try world.setGeometryPrimitive(entity, .{
        .primitive = "uv_sphere",
        .segments = 16,
        .rings = 8,
    });
    try world.setSurfaceMaterial(entity, .{ .base_color = .{ 0.8, 0.4, 0.2 } });
    try world.setShadowCaster(entity);
    try world.setShadowReceiver(entity);

    var editor_state = EditorState{ .selected_entity = entity };
    const clip = editorInspectorScrollClipRect(.{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{ .selected_entity = entity },
    });
    const update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{
            .position = .{ clip.position[0] + 8.0, clip.position[1] + 8.0 },
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });

    try std.testing.expect(update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel), editor_state.inspector_scroll_target_y, 0.001);
    try std.testing.expect(editor_state.inspector_scroll_y > 0.0);
    try std.testing.expect(editor_state.inspector_scroll_y < editor_state.inspector_scroll_target_y);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), editor_state.system_scroll_target_y, 0.001);
}

test "editor inspector property inputs edit text and commit with undo" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("selected", "Selected Box");
    try world.setTransform(entity, .{ .position = .{ 0.25, 0.5, 0.0 } });
    try world.setGeometryPrimitive(entity, .{
        .primitive = "uv_sphere",
        .segments = 16,
        .rings = 8,
    });
    try world.setUiToggle(entity, .{ .checked = false });

    var editor_state = EditorState{ .selected_entity = entity };
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{ .selected_entity = entity },
    };
    const clip = editorInspectorScrollClipRect(frame_input);
    const value_x = editorInspectorFieldLayout(clip.size[0]).value_x;
    const first_field_y = clip.position[1] +
        editor_inspector_card_padding_y +
        editorTextHeight(editor_inspector_text_size) +
        editor_panel_label_gap;

    const focus_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{
            .position = .{ clip.position[0] + value_x + 4.0, first_field_y + 2.0 },
            .has_position = true,
            .primary_pressed = true,
            .primary_down = true,
        },
    });
    try std.testing.expect(focus_update.consumed_pointer);
    try std.testing.expect(editor_state.selected_property.matches(entity, runtime.transform_component_id, "position"));
    try std.testing.expectEqual(@as(u2, 0), editor_state.selected_property.vec3_lane);
    try std.testing.expect(editor_state.text_input.active);
    try std.testing.expectEqualStrings("0.250", editor_state.text_input.text());
    try std.testing.expectEqual(editor_state.text_input.len, editor_state.text_input.cursor);
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.selection_anchor);
    try std.testing.expect(editor_state.text_input.hasSelection());

    var render_state = try RenderEcsState.init(std.testing.allocator);
    defer render_state.deinit();
    var selected_frame = frame_input;
    selected_frame.editor = editorFrameState(&world, editor_state);
    try render_state.extractSceneWithInput(.{ .world = &world }, selected_frame);
    try std.testing.expect(render_state.world.findEntityById("scrapbot.editor.inspector.component.0.field.0.selected") == null);
    const focused_input = render_state.world.findEntityById("scrapbot.editor.inspector.component.0.field.0.input.0") orelse return error.TestExpectedEqual;
    try std.testing.expect(try render_state.world.hasComponent(focused_input, runtime.ui_border_component_id));
    const selection_rect = render_state.world.findEntityById("scrapbot.editor.inspector.component.0.field.0.selection.0") orelse return error.TestExpectedEqual;
    try std.testing.expect(try render_state.world.hasComponent(selection_rect, runtime.ui_rect_component_id));
    try std.testing.expect((try render_state.world.getVec3(selection_rect, runtime.ui_rect_component_id, "size"))[0] > 1.0);
    try std.testing.expect(render_state.world.findEntityById("scrapbot.editor.inspector.component.0.field.0.caret.0") != null);
    var focused_vertices = try buildUiVertices(std.testing.allocator, render_state.world, 1280, 720);
    focused_vertices.deinit(std.testing.allocator);

    var replace_selected = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    replace_selected.appendTextInput("1.250");
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, replace_selected);
    try std.testing.expectEqualStrings("1.250", editor_state.text_input.text());
    try std.testing.expectEqual(editor_state.text_input.len, editor_state.text_input.cursor);
    try std.testing.expectEqual(editor_state.text_input.cursor, editor_state.text_input.selection_anchor);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), (try world.getVec3(entity, runtime.transform_component_id, "position"))[0], 0.001);

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .shift_down = true, .editor_left_pressed = true },
    });
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .shift_down = true, .editor_left_pressed = true },
    });
    try std.testing.expectEqual(@as(usize, 3), editor_state.text_input.cursor);
    try std.testing.expectEqual(@as(usize, 5), editor_state.text_input.selection_anchor);
    try std.testing.expect(editor_state.text_input.hasSelection());

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_delete_pressed = true },
    });
    try std.testing.expectEqualStrings("1.2", editor_state.text_input.text());
    try std.testing.expectEqual(@as(usize, 3), editor_state.text_input.cursor);
    try std.testing.expectEqual(editor_state.text_input.cursor, editor_state.text_input.selection_anchor);

    var insert_tail = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    insert_tail.appendTextInput("50");
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, insert_tail);
    try std.testing.expectEqualStrings("1.250", editor_state.text_input.text());

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .shift_down = true, .editor_home_pressed = true },
    });
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.cursor);
    try std.testing.expectEqual(@as(usize, 5), editor_state.text_input.selection_anchor);

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_left_pressed = true },
    });
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.cursor);
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.selection_anchor);

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_select_all_pressed = true },
    });
    try std.testing.expectEqual(editor_state.text_input.len, editor_state.text_input.cursor);
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.selection_anchor);

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_backspace_pressed = true },
    });
    try std.testing.expectEqualStrings("", editor_state.text_input.text());
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.cursor);
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.selection_anchor);

    var restore_value = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    restore_value.appendTextInput("0.750");
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, restore_value);
    try std.testing.expectEqualStrings("0.750", editor_state.text_input.text());

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_select_all_pressed = true },
    });
    try std.testing.expect(editor_state.text_input.hasSelection());
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.selectionStart());
    try std.testing.expectEqual(editor_state.text_input.len, editor_state.text_input.selectionEnd());

    var overwrite_selected = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    overwrite_selected.appendTextInput("1.250");
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, overwrite_selected);
    try std.testing.expectEqualStrings("1.250", editor_state.text_input.text());
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), (try world.getVec3(entity, runtime.transform_component_id, "position"))[0], 0.001);

    const enter_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_enter_pressed = true },
    });
    try std.testing.expect(enter_update.consumed_pointer);
    try std.testing.expect(!editor_state.text_input.active);
    try std.testing.expectApproxEqAbs(@as(f32, 1.25), (try world.getVec3(entity, runtime.transform_component_id, "position"))[0], 0.001);
    try std.testing.expectEqual(@as(usize, 1), editor_state.undo_len);
    try std.testing.expectEqual(@as(usize, 0), editor_state.redo_len);

    const undo_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_undo_pressed = true },
    });
    try std.testing.expect(undo_update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), (try world.getVec3(entity, runtime.transform_component_id, "position"))[0], 0.001);
    try std.testing.expectEqual(@as(usize, 0), editor_state.undo_len);
    try std.testing.expectEqual(@as(usize, 1), editor_state.redo_len);

    const redo_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_redo_pressed = true },
    });
    try std.testing.expect(redo_update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, 1.25), (try world.getVec3(entity, runtime.transform_component_id, "position"))[0], 0.001);
    try std.testing.expectEqual(@as(usize, 1), editor_state.undo_len);
    try std.testing.expectEqual(@as(usize, 0), editor_state.redo_len);

    try focusEditorTextInput(&world, &editor_state, try makeEditorFieldSelection(entity, runtime.transform_component_id, "position", 1), .{ .select_all_on_focus = true });
    try std.testing.expect(editor_state.text_input.hasSelection());
    var edit_y = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    edit_y.appendTextInput("2.500");
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, edit_y);
    const blur_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{
            .position = .{ 8.0, 8.0 },
            .has_position = true,
            .primary_pressed = true,
            .primary_down = true,
        },
    });
    try std.testing.expect(blur_update.consumed_pointer);
    try std.testing.expect(!editor_state.text_input.active);
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), (try world.getVec3(entity, runtime.transform_component_id, "position"))[1], 0.001);

    const primitive_selection = try makeEditorFieldSelection(entity, runtime.geometry_primitive_component_id, "primitive", 0);
    try std.testing.expect(try applyEditorTypedControlClick(&world, &editor_state, primitive_selection));
    try std.testing.expect(!editor_state.text_input.active);
    try std.testing.expectEqualStrings("ico_sphere", try world.getString(entity, runtime.geometry_primitive_component_id, "primitive"));

    const primitive_undo_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_undo_pressed = true },
    });
    try std.testing.expect(primitive_undo_update.consumed_pointer);
    try std.testing.expectEqualStrings("uv_sphere", try world.getString(entity, runtime.geometry_primitive_component_id, "primitive"));

    const primitive_redo_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_redo_pressed = true },
    });
    try std.testing.expect(primitive_redo_update.consumed_pointer);
    try std.testing.expectEqualStrings("ico_sphere", try world.getString(entity, runtime.geometry_primitive_component_id, "primitive"));

    const toggle_selection = try makeEditorFieldSelection(entity, runtime.ui_toggle_component_id, "checked", 0);
    try std.testing.expect(try applyEditorTypedControlClick(&world, &editor_state, toggle_selection));
    try std.testing.expect(try world.getBoolean(entity, runtime.ui_toggle_component_id, "checked"));

    const toggle_undo_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_undo_pressed = true },
    });
    try std.testing.expect(toggle_undo_update.consumed_pointer);
    try std.testing.expect(!try world.getBoolean(entity, runtime.ui_toggle_component_id, "checked"));

    try focusEditorTextInput(&world, &editor_state, try makeEditorFieldSelection(entity, runtime.geometry_primitive_component_id, "primitive", 0), .{ .select_all_on_focus = false });
    try std.testing.expect(editor_state.text_input.active);
    try std.testing.expect(!editor_state.text_input.hasSelection());
    try std.testing.expectEqual(editor_state.text_input.len, editor_state.text_input.cursor);

    try focusEditorTextInput(&world, &editor_state, try makeEditorFieldSelection(entity, runtime.geometry_primitive_component_id, "segments", 0), .{ .select_all_on_focus = true });
    try std.testing.expect(editor_state.text_input.active);
    try std.testing.expectEqualStrings("16", editor_state.text_input.text());
    try std.testing.expectEqual(editor_state.text_input.len, editor_state.text_input.cursor);
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.selection_anchor);
    try std.testing.expect(editor_state.text_input.hasSelection());

    var scalar_render_state = try RenderEcsState.init(std.testing.allocator);
    defer scalar_render_state.deinit();
    var scalar_frame = frame_input;
    scalar_frame.editor = editorFrameState(&world, editor_state);
    try scalar_render_state.extractSceneWithInput(.{ .world = &world }, scalar_frame);
    const scalar_input = scalar_render_state.world.findEntityById("scrapbot.editor.inspector.component.1.field.1.input") orelse return error.TestExpectedEqual;
    try std.testing.expect(try scalar_render_state.world.hasComponent(scalar_input, runtime.ui_border_component_id));
    const scalar_selection = scalar_render_state.world.findEntityById("scrapbot.editor.inspector.component.1.field.1.selection") orelse return error.TestExpectedEqual;
    try std.testing.expect(try scalar_render_state.world.hasComponent(scalar_selection, runtime.ui_rect_component_id));
    var scalar_vertices = try buildUiVertices(std.testing.allocator, scalar_render_state.world, 1280, 720);
    scalar_vertices.deinit(std.testing.allocator);
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
        .corner_radius = 6.0,
    });
    try world.setUiButton(button);
    try setRenderUiButtonState(&world, button, .{ .hovered = true });

    var hovered_vertices = try buildUiVertices(std.testing.allocator, &world, 640, 480);
    defer hovered_vertices.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 6), hovered_vertices.items.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.106), hovered_vertices.items[0].color[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), hovered_vertices.items[0].rect_size_radius[2], 0.001);

    try setRenderUiButtonState(&world, button, .{ .held = true });
    var held_vertices = try buildUiVertices(std.testing.allocator, &world, 640, 480);
    defer held_vertices.deinit(std.testing.allocator);
    try std.testing.expectApproxEqAbs(@as(f32, 0.086), held_vertices.items[0].color[0], 0.001);
}

test "UI vertex builder clips text to render clip rect" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const text = try world.createEntity("text", "Text");
    try world.setUiText(text, .{
        .position = .{ 10.0, 8.0, 0.0 },
        .size = 1.0,
        .color = .{ 1.0, 1.0, 1.0 },
        .value = "CLIP",
    });
    try setRenderUiClip(&world, text, .{
        .position = .{ 10.0, 16.0, 0.0 },
        .size = .{ 120.0, 18.0, 0.0 },
    });

    var vertices = try buildUiVertices(std.testing.allocator, &world, 640, 480);
    defer vertices.deinit(std.testing.allocator);
    try std.testing.expect(vertices.items.len > 0);

    const clip_top = screenToClipY(16.0, 480);
    const clip_bottom = screenToClipY(34.0, 480);
    for (vertices.items) |vertex| {
        try std.testing.expect(vertex.position[1] <= clip_top + 0.0001);
        try std.testing.expect(vertex.position[1] >= clip_bottom - 0.0001);
    }
}
