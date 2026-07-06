const std = @import("std");
const Io = std.Io;
const runtime = @import("../runtime.zig");
const ui_layout = @import("../ui_layout.zig");
const editor_state_types = @import("state.zig");
const editor_layout = @import("layout.zig");
const editor_render_chrome = @import("render_chrome.zig");
const editor_theme = @import("theme.zig");
const render_input = @import("../render/input.zig");
const render_types = @import("../render/types.zig");
const render_ui = @import("../render/ui.zig");

const FrameInput = render_input.FrameInput;
const RenderError = render_types.RenderError;
const UiButtonState = render_ui.UiButtonState;
const UiClipRect = render_ui.UiClipRect;
const UiBorder = render_ui.UiBorder;
const UiProgressBar = render_ui.UiProgressBar;
const setRenderUiButtonState = render_ui.setRenderUiButtonState;
const setRenderUiClip = render_ui.setRenderUiClip;
const renderUiClip = render_ui.renderUiClip;
const resolveUiLayout = render_ui.resolveUiLayout;
const uiLayoutItemSize = render_ui.uiLayoutItemSize;
const hitTestUiRect = render_ui.hitTestUiRect;
const clamp01 = render_ui.clamp01;

const editor_component_id_buffer_len = editor_state_types.component_id_buffer_len;
const editor_field_name_buffer_len = editor_state_types.field_name_buffer_len;
const editor_input_text_buffer_len = editor_state_types.input_text_buffer_len;
const EditorAxis = editor_state_types.EditorAxis;
const EditorFieldSelection = editor_state_types.EditorFieldSelection;
const EditorTextInputFrame = editor_state_types.EditorTextInputFrame;
const EditorSplitter = editor_state_types.EditorSplitter;
const ScreenRect = editor_layout.ScreenRect;
const pointInsideScreenRect = editor_layout.pointInsideScreenRect;
const editorViewportWidth = editor_layout.viewportWidth;
const editorViewportHeight = editor_layout.viewportHeight;
const EditorBodyLayout = editor_layout.BodyLayout;
const editorSideWidths = editor_layout.sideWidths;
const editorTopBarRect = editor_layout.topBarRect;
const editorBottomBarRect = editor_layout.bottomBarRect;
const editorBodyRect = editor_layout.bodyRect;
const editorBodyLayout = editor_layout.bodyLayout;
const editorLeftSidebarRect = editor_layout.leftSidebarRect;
const editorRightSidebarRect = editor_layout.rightSidebarRect;
const editorSplitterRect = editor_layout.splitterRect;
const editorSplitterHitRect = editor_layout.splitterHitRect;
const editorGameViewport = editor_layout.gameViewport;
const editorPlayButtonRect = editor_layout.playButtonRect;
const editorStepButtonRect = editor_layout.stepButtonRect;

const editor_top_bar_height = editor_layout.top_bar_height;
const editor_bottom_bar_height = editor_layout.bottom_bar_height;
pub const editor_left_sidebar_target_width = editor_layout.left_sidebar_target_width;
const editor_left_sidebar_min_width = editor_layout.left_sidebar_min_width;
const editor_right_sidebar_target_width = editor_layout.right_sidebar_target_width;
const editor_right_sidebar_min_width = editor_layout.right_sidebar_min_width;
const editor_min_game_viewport_width = editor_layout.min_game_viewport_width;
const editor_splitter_width = editor_layout.splitter_width;
const editor_splitter_hit_width = editor_layout.splitter_hit_width;
pub const editor_performance_display_interval_ns: u64 = 333_000_000;
pub const live_run_default_delta_seconds: f32 = 1.0 / 60.0;
pub const live_run_max_delta_seconds: f32 = 0.1;
pub const editor_system_text_size = editor_theme.system_text_size;
const editor_panel_padding_x = editor_layout.panel_padding_x;
const editor_panel_padding_y = editor_theme.panel_padding_y;
const editor_panel_section_gap = editor_theme.panel_section_gap;
pub const editor_panel_label_gap = editor_theme.panel_label_gap;
const editor_panel_bottom_padding = editor_theme.panel_bottom_padding;
pub const editor_system_row_stride = editor_theme.system_row_stride;
const editor_system_row_label_padding_x = editor_theme.system_row_label_padding_x;
const editor_system_row_duration_padding_x = editor_theme.system_row_duration_padding_x;
const editor_system_field_column_gap = editor_theme.system_field_column_gap;
const editor_system_card_padding_y = editor_theme.system_card_padding_y;
pub const editor_system_scroll_pixels_per_wheel = editor_theme.system_scroll_pixels_per_wheel;
const editor_system_scroll_smoothing = editor_theme.system_scroll_smoothing;
const editor_entity_text_size = editor_theme.entity_text_size;
pub const editor_entity_row_stride = editor_theme.entity_row_stride;
pub const editor_entity_row_label_padding_x = editor_theme.entity_row_label_padding_x;
const editor_entity_row_component_padding_x = editor_theme.entity_row_component_padding_x;
const editor_entity_field_column_gap = editor_theme.entity_field_column_gap;
pub const editor_entity_card_padding_y = editor_theme.entity_card_padding_y;
pub const editor_left_panel_gap = editor_theme.left_panel_gap;
const editor_entity_panel_min_height = editor_theme.entity_panel_min_height;
const editor_system_panel_min_height = editor_theme.system_panel_min_height;
const editor_scrollbar_width = editor_theme.scrollbar_width;
const editor_scrollbar_gap = editor_theme.scrollbar_gap;
pub const render_system_profile_window_frames: usize = 120;
pub const editor_control_button_width = editor_layout.control_button_width;
pub const editor_control_button_height = editor_layout.control_button_height;
const editor_control_button_gap = editor_layout.control_button_gap;
pub const editor_bar_text_offset_y = editor_theme.bar_text_offset_y;
const editor_top_fps_x = editor_theme.top_fps_x;
pub const editor_panel_corner_radius = editor_theme.panel_corner_radius;
const editor_sidebar_panel_margin = editor_theme.sidebar_panel_margin;
pub const editor_button_corner_radius = editor_theme.button_corner_radius;
pub const editor_command_play_toggle = editor_theme.command_play_toggle;
const editor_command_step = editor_theme.command_step;
pub const editor_command_splitter_left = editor_theme.command_splitter_left;
const editor_command_splitter_right = editor_theme.command_splitter_right;
const fly_camera_move_speed: f32 = 6.0;
const fly_camera_look_sensitivity: f32 = 0.0035;
const fly_camera_max_pitch: f32 = std.math.degreesToRadians(89.0);
pub const editor_inspector_text_size = editor_render_chrome.inspector_text_size;
const editor_inspector_line_stride = editor_render_chrome.inspector_line_stride;
pub const editor_inspector_field_row_margin_y = editor_render_chrome.inspector_field_row_margin_y;
pub const editor_inspector_card_gap = editor_render_chrome.inspector_card_gap;
pub const editor_inspector_separator_height = editor_render_chrome.inspector_separator_height;
pub const editor_inspector_card_padding_x = editor_render_chrome.inspector_card_padding_x;
pub const editor_inspector_card_padding_y = editor_render_chrome.inspector_card_padding_y;
const editor_inspector_field_column_gap = editor_render_chrome.inspector_field_column_gap;
const editor_inspector_column_min_width = editor_render_chrome.inspector_column_min_width;
pub const editor_inspector_input_padding_x = editor_render_chrome.inspector_input_padding_x;
pub const editor_inspector_input_padding_y = editor_render_chrome.inspector_input_padding_y;
const editor_inspector_input_gap = editor_render_chrome.inspector_input_gap;
pub const editor_inspector_input_border_thickness = editor_render_chrome.inspector_input_border_thickness;
pub const editor_inspector_input_text_offset_x = editor_render_chrome.inspector_input_text_offset_x;
pub const editor_inspector_input_text_offset_y = editor_render_chrome.inspector_input_text_offset_y;
const editor_inspector_input_height = editor_render_chrome.inspector_input_height;
pub const editor_inspector_input_cell_padding = editor_render_chrome.inspector_input_cell_padding;
pub const editor_inspector_field_row_height = editor_render_chrome.inspector_field_row_height;
pub const editor_inspector_field_row_stride = editor_render_chrome.inspector_field_row_stride;
pub const editor_inspector_input_corner_radius = editor_render_chrome.inspector_input_corner_radius;
const editor_inspector_caret_width = editor_render_chrome.inspector_caret_width;
pub const editor_inspector_field_control_offset_y = editor_render_chrome.inspector_field_control_offset_y;
const editor_inspector_field_text_offset_y = editor_render_chrome.inspector_field_text_offset_y;
const editor_inspector_selection_padding_y = editor_render_chrome.inspector_selection_padding_y;
const editor_inspector_toggle_width = editor_render_chrome.inspector_toggle_width;
const editor_inspector_swatch_size = editor_render_chrome.inspector_swatch_size;
const editor_inspector_lane_label_width = editor_render_chrome.inspector_lane_label_width;
const editor_inspector_lane_label_gap = editor_render_chrome.inspector_lane_label_gap;
pub const editorTextHeight = editor_render_chrome.textHeight;
pub const editorTextWidth = editor_render_chrome.textWidth;
const EditorInspectorFieldLayout = editor_render_chrome.InspectorFieldLayout;
pub const editorInspectorFieldLayout = editor_render_chrome.inspectorFieldLayout;
const fitEditorTextToWidth = editor_render_chrome.fitTextToWidth;
const editorPanelTextPosition = editor_render_chrome.panelTextPosition;
const insetScreenRect = editor_render_chrome.insetScreenRect;
const editor_geometry_primitives = editor_theme.geometry_primitives;
const editor_color_channels = editor_theme.color_channels;
const editor_vec3_lane_labels = editor_theme.vec3_lane_labels;

pub fn editorSystemHeaderYOffset() f32 {
    return editor_panel_padding_y;
}

pub fn editorSystemRowsYOffset() f32 {
    return editorSystemHeaderYOffset() + editorTextHeight(editor_system_text_size) + editor_panel_label_gap;
}

pub fn editorDebugPanelSize(input: FrameInput) [2]f32 {
    const panel = editorSystemPanelRect(input);
    return .{ panel.width, panel.height };
}

pub fn editorSystemPanelRect(input: FrameInput) ScreenRect {
    const panel = editorLeftSidebarPanelRect(input);
    const entity_height = editorEntityPanelHeight(panel.height);
    return .{
        .x = panel.x,
        .y = panel.y,
        .width = panel.width,
        .height = @max(panel.height - editor_left_panel_gap - entity_height, 1.0),
    };
}

pub fn editorEntityPanelRect(input: FrameInput) ScreenRect {
    const panel = editorLeftSidebarPanelRect(input);
    const entity_height = editorEntityPanelHeight(panel.height);
    return .{
        .x = panel.x,
        .y = panel.y + @max(panel.height - entity_height, 0.0),
        .width = panel.width,
        .height = entity_height,
    };
}

pub fn editorLeftSidebarPanelRect(input: FrameInput) ScreenRect {
    return editorSidebarPanelRect(editorLeftSidebarRect(input));
}

pub fn editorEntityPanelHeight(total_height: f32) f32 {
    if (total_height <= editor_left_panel_gap + 2.0) {
        return @max(total_height * 0.5, 1.0);
    }
    const max_entity_height = @max(total_height * 0.5, 1.0);
    const min_entity_height = @min(editor_entity_panel_min_height, max_entity_height);
    var entity_height = std.math.clamp(total_height * 0.4, min_entity_height, max_entity_height);
    const min_system = @min(editor_system_panel_min_height, @max(total_height - editor_left_panel_gap - 1.0, 1.0));
    if (total_height - editor_left_panel_gap - entity_height < min_system) {
        entity_height = @max(total_height - editor_left_panel_gap - min_system, 1.0);
    }
    return entity_height;
}

pub fn editorSidebarPanelRect(sidebar: ScreenRect) ScreenRect {
    return insetScreenRect(sidebar, editor_sidebar_panel_margin);
}

pub fn editorSystemHeaderY(input: FrameInput) f32 {
    return editorSystemPanelRect(input).y + editorSystemHeaderYOffset();
}

pub fn editorSystemRowsY(input: FrameInput) f32 {
    return editorSystemPanelRect(input).y + editorSystemRowsYOffset();
}

pub const EditorSystemVisibleRange = struct {
    start: usize,
    end: usize,
    offset_y: f32,
};

pub fn editorSystemVisibleRange(input: FrameInput) EditorSystemVisibleRange {
    const profile_count = input.system_profiles.len;
    if (profile_count == 0) {
        return .{ .start = 0, .end = 0, .offset_y = 0.0 };
    }

    const scroll_y = std.math.clamp(input.editor.system_scroll_y, 0.0, editorSystemMaxScrollY(input, profile_count));
    const row_offset = scroll_y / editor_system_row_stride;
    const start_float = @floor(row_offset);
    const start: usize = @intFromFloat(start_float);
    const offset_y = scroll_y - start_float * editor_system_row_stride;
    const visible_rows = editorSystemVisibleRows(input);
    const visible_count = @min(
        profile_count - start,
        visible_rows + if (offset_y > 0.0) @as(usize, 1) else @as(usize, 0),
    );
    return .{
        .start = start,
        .end = start + visible_count,
        .offset_y = offset_y,
    };
}

pub fn editorSystemListClipRect(input: FrameInput) UiClipRect {
    const panel = editorSystemPanelRect(input);
    const scrollbar_space = if (editorSystemNeedsScrollForInput(input, editorSystemProfileScrollCount(input)))
        editor_scrollbar_width + editor_scrollbar_gap
    else
        0.0;
    return .{
        .position = .{ panel.x, editorSystemRowsY(input), 0.0 },
        .size = .{
            @max(panel.width - scrollbar_space, 1.0),
            editorSystemTableContentHeight(editorSystemVisibleRows(input)),
            0.0,
        },
    };
}

pub fn editorSystemListHitTestPoint(profiles: []const runtime.SystemProfileSnapshot, profile_count_hint: usize) [2]f32 {
    const list_clip = editorSystemListClipRect(.{
        .debug_overlay_visible = true,
        .system_profiles = profiles,
        .system_profile_count_hint = profile_count_hint,
    });
    return .{ list_clip.position[0] + 4.0, list_clip.position[1] + 4.0 };
}

pub const EditorEntityVisibleRange = struct {
    start: usize,
    end: usize,
    offset_y: f32,
};

pub fn editorEntityVisibleRange(scene_world: *const runtime.World, input: FrameInput) EditorEntityVisibleRange {
    const entity_count = editorInspectableEntityCount(scene_world);
    if (entity_count == 0) {
        return .{ .start = 0, .end = 0, .offset_y = 0.0 };
    }

    const scroll_y = std.math.clamp(input.editor.entity_scroll_y, 0.0, editorEntityMaxScrollY(scene_world, input));
    const row_offset = scroll_y / editor_entity_row_stride;
    const start_float = @floor(row_offset);
    const start: usize = @intFromFloat(start_float);
    const offset_y = scroll_y - start_float * editor_entity_row_stride;
    const visible_rows = editorEntityVisibleRows(input);
    const visible_count = @min(
        entity_count - start,
        visible_rows + if (offset_y > 0.0) @as(usize, 1) else @as(usize, 0),
    );
    return .{
        .start = start,
        .end = start + visible_count,
        .offset_y = offset_y,
    };
}

pub fn editorEntityListClipRect(scene_world: *const runtime.World, input: FrameInput) UiClipRect {
    const panel = editorEntityPanelRect(input);
    const scrollbar_space = if (editorEntityNeedsScroll(scene_world, input))
        editor_scrollbar_width + editor_scrollbar_gap
    else
        0.0;
    return .{
        .position = .{ panel.x, panel.y + editorSystemRowsYOffset(), 0.0 },
        .size = .{
            @max(panel.width - scrollbar_space, 1.0),
            editorEntityTableContentHeight(editorEntityVisibleRows(input)),
            0.0,
        },
    };
}

pub fn editorSystemProfileScrollCount(input: FrameInput) usize {
    return @max(input.system_profiles.len, input.system_profile_count_hint);
}

pub fn editorSystemVisibleRows(input: FrameInput) usize {
    const panel = editorSystemPanelRect(input);
    const rows_height = @max(panel.y + panel.height - editorSystemRowsY(input) - editor_panel_bottom_padding - editor_system_card_padding_y * 2.0, editor_system_row_stride);
    return @max(@as(usize, @intFromFloat(@floor(rows_height / editor_system_row_stride))), 1);
}

pub fn editorSystemTableContentHeight(row_count: usize) f32 {
    return editor_system_card_padding_y * 2.0 + @as(f32, @floatFromInt(row_count)) * editor_system_row_stride;
}

pub fn editorEntityVisibleRows(input: FrameInput) usize {
    const panel = editorEntityPanelRect(input);
    const rows_y = panel.y + editorSystemRowsYOffset();
    const rows_height = @max(panel.y + panel.height - rows_y - editor_panel_bottom_padding - editor_entity_card_padding_y * 2.0, editor_entity_row_stride);
    return @max(@as(usize, @intFromFloat(@floor(rows_height / editor_entity_row_stride))), 1);
}

pub fn editorEntityTableContentHeight(row_count: usize) f32 {
    return editor_entity_card_padding_y * 2.0 + @as(f32, @floatFromInt(row_count)) * editor_entity_row_stride;
}

pub fn editorEntityNeedsScroll(scene_world: *const runtime.World, input: FrameInput) bool {
    return editorInspectableEntityCount(scene_world) > editorEntityVisibleRows(input);
}

pub fn editorEntityMaxScroll(scene_world: *const runtime.World, input: FrameInput) usize {
    const visible_rows = editorEntityVisibleRows(input);
    const entity_count = editorInspectableEntityCount(scene_world);
    return if (entity_count > visible_rows)
        entity_count - visible_rows
    else
        0;
}

pub fn editorEntityMaxScrollY(scene_world: *const runtime.World, input: FrameInput) f32 {
    return @as(f32, @floatFromInt(editorEntityMaxScroll(scene_world, input))) * editor_entity_row_stride;
}

pub fn editorEntityHandleAt(scene_world: *const runtime.World, entity_index: usize) ?runtime.EntityHandle {
    var inspectable_index: usize = 0;
    for (0..scene_world.entityCount()) |dense_index| {
        const index: u32 = @intCast(dense_index);
        const entity = scene_world.entity(.{ .index = index }) catch continue;
        if (entity.provenance == .engine_transient) {
            continue;
        }
        if (inspectable_index == entity_index) {
            return .{ .index = index, .generation = entity.generation };
        }
        inspectable_index += 1;
    }
    return null;
}

pub fn editorInspectableEntityCount(scene_world: *const runtime.World) usize {
    var count: usize = 0;
    for (0..scene_world.entityCount()) |dense_index| {
        const index: u32 = @intCast(dense_index);
        const entity = scene_world.entity(.{ .index = index }) catch continue;
        if (entity.provenance != .engine_transient) {
            count += 1;
        }
    }
    return count;
}

pub fn editorEntityComponentCount(scene_world: *const runtime.World, handle: runtime.EntityHandle) usize {
    var components = scene_world.entityComponents(handle) catch return 0;
    var count: usize = 0;
    while (components.next()) |_| {
        count += 1;
    }
    return count;
}

pub fn editorEntityHandlesEqual(selected: ?runtime.EntityHandle, handle: runtime.EntityHandle) bool {
    const candidate = selected orelse return false;
    return candidate.index == handle.index and candidate.generation == handle.generation;
}

pub fn editorInspectorScrollClipRect(input: FrameInput) UiClipRect {
    const sidebar = editorSidebarPanelRect(editorRightSidebarRect(input));
    const y = sidebar.y + editor_panel_padding_y + editor_inspector_line_stride * 2.5;
    const bottom = sidebar.y + sidebar.height;
    return .{
        .position = .{ sidebar.x, y, 0.0 },
        .size = .{
            @max(sidebar.width, 1.0),
            @max(bottom - y, 1.0),
            0.0,
        },
    };
}

pub fn editorInspectorComponentContentHeight(scene_world: *const runtime.World, selected: ?runtime.EntityHandle) f32 {
    const selected_entity = selected orelse return 0.0;
    var components = scene_world.entityComponents(selected_entity) catch return 0.0;
    var height: f32 = 0.0;
    var component_index: usize = 0;
    while (components.next()) |component_id| {
        if (component_index > 0) {
            height += editor_inspector_card_gap * 2.0;
            height += editor_inspector_separator_height;
        }
        height += editorInspectorComponentCardHeight(scene_world, component_id);
        component_index += 1;
    }
    return height;
}

pub fn editorInspectorComponentCardHeight(scene_world: *const runtime.World, component_id: []const u8) f32 {
    const field_count = scene_world.componentFieldCount(component_id);
    return editor_inspector_card_padding_y * 2.0 +
        editorTextHeight(editor_inspector_text_size) +
        editor_panel_label_gap +
        @as(f32, @floatFromInt(field_count)) * editor_inspector_field_row_stride;
}

pub fn editorInspectorNeedsScroll(scene_world: *const runtime.World, input: FrameInput) bool {
    return editorInspectorMaxScrollY(scene_world, input) > 0.0;
}

pub fn editorInspectorMaxScrollY(scene_world: *const runtime.World, input: FrameInput) f32 {
    const clip = editorInspectorScrollClipRect(input);
    return @max(editorInspectorComponentContentHeight(scene_world, input.editor.selected_entity) - clip.size[1], 0.0);
}

pub fn editorSystemNeedsScrollForInput(input: FrameInput, profile_count: usize) bool {
    return profile_count > editorSystemVisibleRows(input);
}

pub fn editorSystemMaxScroll(input: FrameInput, profile_count: usize) usize {
    const visible_rows = editorSystemVisibleRows(input);
    return if (profile_count > visible_rows)
        profile_count - visible_rows
    else
        0;
}

pub fn editorSystemMaxScrollY(input: FrameInput, profile_count: usize) f32 {
    return @as(f32, @floatFromInt(editorSystemMaxScroll(input, profile_count))) * editor_system_row_stride;
}

pub fn formatFpsLabel(allocator: std.mem.Allocator, fps: f32) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(allocator, "FPS {d}", .{roundedFps(fps)});
}

pub fn formatSystemProfileHeader(allocator: std.mem.Allocator, profiles: []const runtime.SystemProfileSnapshot) error{OutOfMemory}![]const u8 {
    const window_size = if (profiles.len == 0) 0 else profiles[0].window_size;
    return std.fmt.allocPrint(allocator, "SYS {d} AVG {d}F SNAP 3HZ", .{ profiles.len, window_size });
}

pub fn formatSystemProfileDuration(allocator: std.mem.Allocator, profile: runtime.SystemProfileSnapshot) error{OutOfMemory}![]const u8 {
    if (profile.sample_count == 0) {
        return allocator.dupe(u8, "--");
    }

    var average_buffer: [16]u8 = undefined;
    const average = formatDurationShort(&average_buffer, profile.rolling_average_ns);
    return allocator.dupe(u8, average);
}

pub fn formatDurationShort(buffer: *[16]u8, ns: u64) []const u8 {
    const micros = nsToMicrosRounded(ns);
    if (micros < 10_000) {
        return std.fmt.bufPrint(buffer, "{d}us", .{micros}) catch "----";
    }
    return std.fmt.bufPrint(buffer, "{d}ms", .{(micros + 500) / 1000}) catch "----";
}

pub fn nsToMicrosRounded(ns: u64) u64 {
    return (ns + 500) / 1000;
}

pub fn elapsedNanosecondsSince(started_ns: i128) u64 {
    const elapsed_ns = monotonicTimestampNs() - started_ns;
    if (elapsed_ns <= 0) {
        return 0;
    }
    return @intCast(@min(elapsed_ns, std.math.maxInt(u64)));
}

pub fn monotonicTimestampNs() i128 {
    const io = Io.Threaded.global_single_threaded.io();
    return Io.Timestamp.now(io, .awake).nanoseconds;
}

pub fn roundedFps(fps: f32) i32 {
    if (!std.math.isFinite(fps) or fps <= 0.0) {
        return 0;
    }
    const clamped = @min(fps, 9999.0);
    return @intFromFloat(@round(clamped));
}
