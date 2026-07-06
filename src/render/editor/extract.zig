const std = @import("std");
const Io = std.Io;
const runtime = @import("../../runtime.zig");
const ui_layout = @import("../../ui_layout.zig");
const editor_state_types = @import("../../editor/state.zig");
const editor_layout = @import("../../editor/layout.zig");
const editor_render_chrome = @import("../../editor/render_chrome.zig");
const editor_theme = @import("../../editor/theme.zig");
const render_input = @import("../input.zig");
const editor_metrics = @import("../../editor/metrics.zig");
const render_types = @import("../types.zig");
const render_ui = @import("../ui.zig");

const FrameInput = render_input.FrameInput;
const RenderError = render_types.RenderError;
const UiButtonState = render_ui.UiButtonState;
const UiClipRect = render_ui.UiClipRect;
const UiBorder = render_ui.UiBorder;
const clamp01 = render_ui.clamp01;

const editor_input_text_buffer_len = editor_state_types.input_text_buffer_len;
const EditorFieldSelection = editor_state_types.EditorFieldSelection;
const EditorTextInputFrame = editor_state_types.EditorTextInputFrame;
const EditorSplitter = editor_state_types.EditorSplitter;
const ScreenRect = editor_layout.ScreenRect;
const pointInsideScreenRect = editor_layout.pointInsideScreenRect;
const editorTopBarRect = editor_layout.topBarRect;
const editorBottomBarRect = editor_layout.bottomBarRect;
const editorBodyRect = editor_layout.bodyRect;
const editorBodyLayout = editor_layout.bodyLayout;
const editorRightSidebarRect = editor_layout.rightSidebarRect;
const editorSplitterRect = editor_layout.splitterRect;
const editorSplitterHitRect = editor_layout.splitterHitRect;
const editorGameViewport = editor_layout.gameViewport;
const editorPlayButtonRect = editor_layout.playButtonRect;
const editorStepButtonRect = editor_layout.stepButtonRect;

pub const editor_system_text_size = editor_theme.system_text_size;
const editor_panel_padding_x = editor_layout.panel_padding_x;
const editor_panel_padding_y = editor_theme.panel_padding_y;
pub const editor_system_row_stride = editor_theme.system_row_stride;
const editor_system_row_label_padding_x = editor_theme.system_row_label_padding_x;
const editor_system_row_duration_padding_x = editor_theme.system_row_duration_padding_x;
const editor_system_field_column_gap = editor_theme.system_field_column_gap;
const editor_system_card_padding_y = editor_theme.system_card_padding_y;
const editor_entity_text_size = editor_theme.entity_text_size;
pub const editor_entity_row_stride = editor_theme.entity_row_stride;
pub const editor_entity_row_label_padding_x = editor_theme.entity_row_label_padding_x;
const editor_entity_row_component_padding_x = editor_theme.entity_row_component_padding_x;
const editor_entity_field_column_gap = editor_theme.entity_field_column_gap;
const editor_scrollbar_width = editor_theme.scrollbar_width;
const editor_scrollbar_gap = editor_theme.scrollbar_gap;
pub const editor_bar_text_offset_y = editor_theme.bar_text_offset_y;
const editor_top_fps_x = editor_theme.top_fps_x;
pub const editor_panel_corner_radius = editor_theme.panel_corner_radius;
const editor_sidebar_panel_margin = editor_theme.sidebar_panel_margin;
pub const editor_button_corner_radius = editor_theme.button_corner_radius;
pub const editor_command_play_toggle = editor_theme.command_play_toggle;
const editor_command_step = editor_theme.command_step;
pub const editor_command_splitter_left = editor_theme.command_splitter_left;
const editor_command_splitter_right = editor_theme.command_splitter_right;
pub const editor_inspector_text_size = editor_render_chrome.inspector_text_size;
const editor_inspector_line_stride = editor_render_chrome.inspector_line_stride;
pub const editor_inspector_card_padding_x = editor_render_chrome.inspector_card_padding_x;
pub const editor_inspector_card_padding_y = editor_render_chrome.inspector_card_padding_y;
const editor_inspector_field_column_gap = editor_render_chrome.inspector_field_column_gap;
const editor_inspector_input_gap = editor_render_chrome.inspector_input_gap;
pub const editor_inspector_input_border_thickness = editor_render_chrome.inspector_input_border_thickness;
pub const editor_inspector_input_text_offset_x = editor_render_chrome.inspector_input_text_offset_x;
pub const editor_inspector_input_text_offset_y = editor_render_chrome.inspector_input_text_offset_y;
const editor_inspector_input_height = editor_render_chrome.inspector_input_height;
pub const editor_inspector_input_cell_padding = editor_render_chrome.inspector_input_cell_padding;
pub const editor_inspector_field_row_height = editor_render_chrome.inspector_field_row_height;
pub const editor_inspector_input_corner_radius = editor_render_chrome.inspector_input_corner_radius;
const editor_inspector_caret_width = editor_render_chrome.inspector_caret_width;
pub const editor_inspector_field_control_offset_y = editor_render_chrome.inspector_field_control_offset_y;
const editor_inspector_field_text_offset_y = editor_render_chrome.inspector_field_text_offset_y;
const editor_inspector_selection_padding_y = editor_render_chrome.inspector_selection_padding_y;
const editor_inspector_toggle_width = editor_render_chrome.inspector_toggle_width;
const editor_inspector_swatch_size = editor_render_chrome.inspector_swatch_size;
const editor_inspector_lane_label_width = editor_render_chrome.inspector_lane_label_width;
pub const editorTextHeight = editor_render_chrome.textHeight;
pub const editorTextWidth = editor_render_chrome.textWidth;
const fitEditorTextToWidth = editor_render_chrome.fitTextToWidth;
const editorPanelTextPosition = editor_render_chrome.panelTextPosition;
const editorSystemHeaderYOffset = editor_metrics.editorSystemHeaderYOffset;
const editorSystemRowsYOffset = editor_metrics.editorSystemRowsYOffset;
const editorDebugPanelSize = editor_metrics.editorDebugPanelSize;
const editorSystemPanelRect = editor_metrics.editorSystemPanelRect;
const editorEntityPanelRect = editor_metrics.editorEntityPanelRect;
const editorSystemHeaderY = editor_metrics.editorSystemHeaderY;
const editorSystemRowsY = editor_metrics.editorSystemRowsY;
pub const editorSystemVisibleRows = editor_metrics.editorSystemVisibleRows;
pub const editorSystemTableContentHeight = editor_metrics.editorSystemTableContentHeight;
const editorEntityVisibleRows = editor_metrics.editorEntityVisibleRows;
pub const editorEntityTableContentHeight = editor_metrics.editorEntityTableContentHeight;
const formatFpsLabel = editor_metrics.formatFpsLabel;
const formatSystemProfileHeader = editor_metrics.formatSystemProfileHeader;
const formatSystemProfileDuration = editor_metrics.formatSystemProfileDuration;
pub const EditorSystemVisibleRange = editor_metrics.EditorSystemVisibleRange;
pub const editorSystemVisibleRange = editor_metrics.editorSystemVisibleRange;
pub const editorSystemListClipRect = editor_metrics.editorSystemListClipRect;
pub const editorSystemListHitTestPoint = editor_metrics.editorSystemListHitTestPoint;
pub const EditorEntityVisibleRange = editor_metrics.EditorEntityVisibleRange;
pub const editorEntityVisibleRange = editor_metrics.editorEntityVisibleRange;
pub const editorEntityListClipRect = editor_metrics.editorEntityListClipRect;
pub const editorSystemProfileScrollCount = editor_metrics.editorSystemProfileScrollCount;
pub const editorSystemMaxScrollY = editor_metrics.editorSystemMaxScrollY;
pub const editorEntityNeedsScroll = editor_metrics.editorEntityNeedsScroll;
pub const editorEntityMaxScroll = editor_metrics.editorEntityMaxScroll;
pub const editorEntityMaxScrollY = editor_metrics.editorEntityMaxScrollY;
pub const editorEntityHandleAt = editor_metrics.editorEntityHandleAt;
const editorInspectableEntityCount = editor_metrics.editorInspectableEntityCount;
pub const editorEntityComponentCount = editor_metrics.editorEntityComponentCount;
pub const editorEntityHandlesEqual = editor_metrics.editorEntityHandlesEqual;
pub const editorSidebarPanelRect = editor_metrics.editorSidebarPanelRect;
pub const editorInspectorScrollClipRect = editor_metrics.editorInspectorScrollClipRect;
pub const editorInspectorComponentContentHeight = editor_metrics.editorInspectorComponentContentHeight;
pub const editorInspectorComponentCardHeight = editor_metrics.editorInspectorComponentCardHeight;
pub const editorInspectorNeedsScroll = editor_metrics.editorInspectorNeedsScroll;
pub const editorInspectorMaxScrollY = editor_metrics.editorInspectorMaxScrollY;
pub const editorSystemNeedsScrollForInput = editor_metrics.editorSystemNeedsScrollForInput;
pub const elapsedNanosecondsSince = editor_metrics.elapsedNanosecondsSince;
pub const monotonicTimestampNs = editor_metrics.monotonicTimestampNs;
const editor_color_channels = editor_theme.color_channels;
const editor_vec3_lane_labels = editor_theme.vec3_lane_labels;
pub const editor_palette = editor_theme.palette;

const EditorVGroup = struct {
    world: *runtime.World,
    id_prefix: []const u8,
    x: f32,
    y: f32,
    row_stride: f32,
    layout_parent: ?[]const u8 = null,
    row: usize = 0,

    fn init(
        world: *runtime.World,
        id_prefix: []const u8,
        x: f32,
        y: f32,
        row_stride: f32,
    ) EditorVGroup {
        return .{
            .world = world,
            .id_prefix = id_prefix,
            .x = x,
            .y = y,
            .row_stride = row_stride,
        };
    }

    fn withLayoutParent(self: EditorVGroup, parent: []const u8) EditorVGroup {
        var copy = self;
        copy.layout_parent = parent;
        return copy;
    }

    fn text(self: *EditorVGroup, name: []const u8, value: []const u8, size: f32, color: [3]f32) RenderError!void {
        var entity_id_buffer: [192]u8 = undefined;
        const entity_id = try formatEditorId(&entity_id_buffer, "{s}.{d}", .{ self.id_prefix, self.row });
        const entity = self.world.createEngineTransientEntity(entity_id, name) catch |err| return mapWorldError(err);
        const position = if (self.layout_parent != null)
            [3]f32{ 0.0, 0.0, 0.0 }
        else
            [3]f32{
                self.x,
                self.y + @as(f32, @floatFromInt(self.row)) * self.row_stride,
                0.0,
            };
        self.world.setUiText(entity, .{
            .position = position,
            .size = size,
            .color = color,
            .value = value,
        }) catch |err| return mapWorldError(err);
        if (self.layout_parent) |parent| {
            self.world.setUiLayoutItem(entity, .{
                .parent = parent,
                .order = @intCast(self.row),
            }) catch |err| return mapWorldError(err);
        }
        self.row += 1;
    }
};

fn formatEditorId(buffer: []u8, comptime fmt: []const u8, args: anytype) RenderError![]const u8 {
    return std.fmt.bufPrint(buffer, fmt, args) catch return RenderError.InvalidScene;
}

pub fn extractEditorShellInto(allocator: std.mem.Allocator, world: *runtime.World, input: FrameInput) RenderError!void {
    const top = editorTopBarRect(input);
    const bottom = editorBottomBarRect(input);
    const body = editorBodyRect(input);
    const layout = editorBodyLayout(input);
    const game_viewport = editorGameViewport(input);
    _ = allocator;
    const hovered_splitter = routeEditorSplitterAt(input);

    try extractEditorShellRect(world, "scrapbot.editor.shell.top_bar", top, editor_palette.shell);
    try extractEditorShellRect(world, "scrapbot.editor.shell.bottom_bar", bottom, editor_palette.shell);

    const body_group = world.createEngineTransientEntity("scrapbot.editor.shell.body", "Editor Body HGroup") catch |err| return mapWorldError(err);
    world.setUiHGroup(body_group, .{
        .position = body.position(),
        .size = body.size3(),
        .spacing = 0.0,
        .padding = .{ 0.0, 0.0, 0.0 },
    }) catch |err| return mapWorldError(err);

    try extractEditorShellLayoutRect(world, "scrapbot.editor.shell.left_sidebar", "Editor Left Sidebar", layout.left.size3(), 0, editor_palette.panel);
    try extractEditorShellLayoutSplitter(world, input, "scrapbot.editor.shell.splitter.left", "Editor Left Splitter", layout.left_splitter.size3(), 1, .left, hovered_splitter);
    try extractEditorSplitterHitTarget(world, input, .left);
    try extractEditorShellLayoutSpacer(world, "scrapbot.editor.shell.game_viewport", "Editor Game Viewport Slot", .{ editor_layout.min_game_viewport_width, body.height, 0.0 }, 2, 1.0);
    try extractEditorShellLayoutSplitter(world, input, "scrapbot.editor.shell.splitter.right", "Editor Right Splitter", layout.right_splitter.size3(), 3, .right, hovered_splitter);
    try extractEditorSplitterHitTarget(world, input, .right);
    try extractEditorShellLayoutRect(world, "scrapbot.editor.shell.right_sidebar", "Editor Right Sidebar", layout.right.size3(), 4, editor_palette.panel);

    const frame_color = editor_palette.panel_muted;
    try extractEditorShellRect(world, "scrapbot.editor.shell.viewport.border.bottom", .{
        .x = game_viewport.x,
        .y = game_viewport.y + game_viewport.height - 2.0,
        .width = game_viewport.width,
        .height = 2.0,
    }, frame_color);
}

fn routeEditorSplitterAt(input: FrameInput) ?EditorSplitter {
    if (!input.debug_overlay_visible or !input.pointer.has_position) {
        return null;
    }
    if (editorSplitterHitRect(input, .left)) |rect| {
        if (pointInsideScreenRect(input.pointer.position, .{ rect.x, rect.y }, .{ rect.width, rect.height })) {
            return .left;
        }
    }
    if (editorSplitterHitRect(input, .right)) |rect| {
        if (pointInsideScreenRect(input.pointer.position, .{ rect.x, rect.y }, .{ rect.width, rect.height })) {
            return .right;
        }
    }
    return null;
}

fn extractEditorSplitterHitTarget(world: *runtime.World, input: FrameInput, splitter: EditorSplitter) RenderError!void {
    const visual = editorSplitterRect(input, splitter) orelse return;
    const hit_rect = editorSplitterHitRect(input, splitter) orelse return;
    const id = switch (splitter) {
        .none => return,
        .left => "scrapbot.editor.shell.splitter.left.hit_area",
        .right => "scrapbot.editor.shell.splitter.right.hit_area",
    };
    const name = switch (splitter) {
        .none => return,
        .left => "Editor Left Splitter Hit Area",
        .right => "Editor Right Splitter Hit Area",
    };
    const parent = switch (splitter) {
        .none => return,
        .left => "scrapbot.editor.shell.splitter.left",
        .right => "scrapbot.editor.shell.splitter.right",
    };
    const command = switch (splitter) {
        .none => return,
        .left => editor_command_splitter_left,
        .right => editor_command_splitter_right,
    };
    const entity = world.createEngineTransientEntity(id, name) catch |err| return mapWorldError(err);
    world.setUiHitArea(entity, .{
        .position = .{ hit_rect.x - visual.x, 0.0, 0.0 },
        .size = hit_rect.size3(),
    }) catch |err| return mapWorldError(err);
    world.setUiButton(entity) catch |err| return mapWorldError(err);
    world.setUiCommand(entity, .{ .command = command }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(entity, .{
        .parent = parent,
        .order = 0,
    }) catch |err| return mapWorldError(err);
}

fn extractEditorShellRect(world: *runtime.World, id: []const u8, rect: ScreenRect, color: [3]f32) RenderError!void {
    const entity = world.createEngineTransientEntity(id, "Editor Shell Rect") catch |err| return mapWorldError(err);
    world.setUiRect(entity, .{
        .position = rect.position(),
        .size = rect.size3(),
        .color = color,
        .corner_radius = 0.0,
    }) catch |err| return mapWorldError(err);
}

fn extractEditorShellLayoutRect(world: *runtime.World, id: []const u8, name: []const u8, size: [3]f32, order: i32, color: [3]f32) RenderError!void {
    const entity = world.createEngineTransientEntity(id, name) catch |err| return mapWorldError(err);
    world.setUiRect(entity, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = size,
        .color = color,
        .corner_radius = 0.0,
    }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(entity, .{
        .parent = "scrapbot.editor.shell.body",
        .order = order,
        .@"align" = "fill",
    }) catch |err| return mapWorldError(err);
}

fn extractEditorShellLayoutSeparator(world: *runtime.World, id: []const u8, name: []const u8, size: [3]f32, order: i32, color: [3]f32) RenderError!void {
    const entity = world.createEngineTransientEntity(id, name) catch |err| return mapWorldError(err);
    world.setUiSeparator(entity, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = size,
        .color = color,
    }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(entity, .{
        .parent = "scrapbot.editor.shell.body",
        .order = order,
        .@"align" = "fill",
    }) catch |err| return mapWorldError(err);
}

fn extractEditorShellLayoutSplitter(
    world: *runtime.World,
    input: FrameInput,
    id: []const u8,
    name: []const u8,
    size: [3]f32,
    order: i32,
    splitter: EditorSplitter,
    hovered_splitter: ?EditorSplitter,
) RenderError!void {
    if (editorSplitterVisible(input, splitter, hovered_splitter)) {
        try extractEditorShellLayoutSeparator(world, id, name, size, order, editorSplitterColor(input, splitter, hovered_splitter));
        return;
    }

    try extractEditorShellLayoutSpacer(world, id, name, size, order, 0.0);
}

fn editorSplitterColor(input: FrameInput, splitter: EditorSplitter, hovered_splitter: ?EditorSplitter) [3]f32 {
    if (input.editor.dragging_splitter == splitter) {
        return editor_palette.text_muted;
    }
    if (hovered_splitter != null and hovered_splitter.? == splitter) {
        return editor_palette.text_dim;
    }
    return editor_palette.panel;
}

fn editorSplitterVisible(input: FrameInput, splitter: EditorSplitter, hovered_splitter: ?EditorSplitter) bool {
    return input.editor.dragging_splitter == splitter or (hovered_splitter != null and hovered_splitter.? == splitter);
}

fn extractEditorShellLayoutSpacer(world: *runtime.World, id: []const u8, name: []const u8, min_size: [3]f32, order: i32, grow: f32) RenderError!void {
    const entity = world.createEngineTransientEntity(id, name) catch |err| return mapWorldError(err);
    world.setUiSpacer(entity, .{ .size = .{ 0.0, 0.0, 0.0 } }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(entity, .{
        .parent = "scrapbot.editor.shell.body",
        .order = order,
        .min_size = min_size,
        .grow = grow,
        .@"align" = "fill",
    }) catch |err| return mapWorldError(err);
}

pub fn extractDebugOverlayInto(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    input: FrameInput,
    scene_world: *const runtime.World,
) RenderError!void {
    try extractEditorShellInto(allocator, world, input);
    try extractEditorTopBarInto(allocator, world, input);
    try extractEditorBottomBarInto(allocator, world, input);

    const has_profiles = input.system_profiles.len > 0;
    const panel_size = editorDebugPanelSize(input);
    const panel = editorSystemPanelRect(input);

    const canvas = world.createEngineTransientEntity("scrapbot.editor.debug.canvas", "Editor Debug Canvas") catch |err| return mapWorldError(err);
    world.setUiCanvas(canvas, .{}) catch |err| return mapWorldError(err);

    _ = try extractEditorPanel(world, "scrapbot.editor.debug.panel", "Editor Debug Panel", .{
        .x = panel.x,
        .y = panel.y,
        .width = panel_size[0],
        .height = panel_size[1],
    }, editor_palette.panel, 0.0);

    if (!has_profiles) {
        try extractEditorEntityListInto(allocator, world, scene_world, input);
        try extractEditorComponentInspectorInto(allocator, world, scene_world, input);
        return;
    }

    const header_text = formatSystemProfileHeader(allocator, input.system_profiles) catch return RenderError.OutOfMemory;
    defer allocator.free(header_text);
    const header = world.createEngineTransientEntity("scrapbot.editor.debug.systems.header", "Editor Debug Systems Header") catch |err| return mapWorldError(err);
    world.setUiText(header, .{
        .position = editorPanelTextPosition(panel, editorSystemHeaderY(input) - panel.y),
        .size = editor_system_text_size,
        .color = editor_palette.text_muted,
        .value = header_text,
    }) catch |err| return mapWorldError(err);

    const list_clip = editorSystemListClipRect(input);
    const system_scroll = world.createEngineTransientEntity("scrapbot.editor.debug.systems.scroll", "Editor Debug Systems Scroll View") catch |err| return mapWorldError(err);
    world.setUiScrollView(system_scroll, .{
        .position = list_clip.position,
        .size = list_clip.size,
        .content_offset = .{ 0.0, input.editor.system_scroll_y, 0.0 },
    }) catch |err| return mapWorldError(err);

    const row_width = list_clip.size[0];
    const table_height = editorSystemTableContentHeight(input.system_profiles.len);
    const system_table = world.createEngineTransientEntity("scrapbot.editor.debug.systems.table", "Editor Debug Systems Table") catch |err| return mapWorldError(err);
    world.setUiRect(system_table, .{
        .position = .{
            0.0,
            editorSystemRowsY(input) - list_clip.position[1],
            0.0,
        },
        .size = .{ row_width, table_height, 0.0 },
        .color = editor_palette.shell,
        .corner_radius = editor_panel_corner_radius,
    }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(system_table, .{
        .parent = "scrapbot.editor.debug.systems.scroll",
        .order = 0,
    }) catch |err| return mapWorldError(err);

    for (input.system_profiles, 0..) |profile, profile_index| {
        const row_y = editor_system_card_padding_y + @as(f32, @floatFromInt(profile_index)) * editor_system_row_stride;
        const duration_text = formatSystemProfileDuration(allocator, profile) catch return RenderError.OutOfMemory;
        defer allocator.free(duration_text);
        const duration_width = editorTextWidth(duration_text, editor_system_text_size);
        const duration_x = @max(row_width - editor_system_row_duration_padding_x - duration_width, editor_system_row_label_padding_x);
        const label_max_width = @max(duration_x - editor_system_row_label_padding_x - editor_system_field_column_gap, 1.0);
        const label_text = fitEditorTextToWidth(allocator, profile.id, editor_system_text_size, label_max_width) catch return RenderError.OutOfMemory;
        defer allocator.free(label_text);

        var label_id_buffer: [192]u8 = undefined;
        const label_id = try formatEditorId(&label_id_buffer, "scrapbot.editor.debug.systems.row.{d}.label", .{profile_index});
        _ = try extractEditorChildText(world, label_id, "Editor System Row Label", "scrapbot.editor.debug.systems.table", .{
            editor_system_row_label_padding_x,
            row_y,
            0.0,
        }, label_text, editor_system_text_size, editor_palette.text);

        var duration_id_buffer: [192]u8 = undefined;
        const duration_id = try formatEditorId(&duration_id_buffer, "scrapbot.editor.debug.systems.row.{d}.duration", .{profile_index});
        _ = try extractEditorChildText(world, duration_id, "Editor System Row Duration", "scrapbot.editor.debug.systems.table", .{
            duration_x,
            row_y,
            0.0,
        }, duration_text, editor_system_text_size, editor_palette.text_muted);
    }

    try extractEditorSystemScrollbarInto(world, input, list_clip);
    try extractEditorEntityListInto(allocator, world, scene_world, input);
    try extractEditorComponentInspectorInto(allocator, world, scene_world, input);
}

pub fn extractEditorTopBarInto(allocator: std.mem.Allocator, world: *runtime.World, input: FrameInput) RenderError!void {
    const top = editorTopBarRect(input);
    const title = world.createEngineTransientEntity("scrapbot.editor.top.title", "Editor Top Title") catch |err| return mapWorldError(err);
    world.setUiText(title, .{
        .position = .{ editor_panel_padding_x, top.y + editor_bar_text_offset_y, 0.0 },
        .size = 1.0,
        .color = editor_palette.text_muted,
        .value = "SCRAPBOT",
    }) catch |err| return mapWorldError(err);

    const fps_text = formatFpsLabel(allocator, input.fps) catch return RenderError.OutOfMemory;
    defer allocator.free(fps_text);
    const fps = world.createEngineTransientEntity("scrapbot.editor.debug.fps", "Editor Debug FPS") catch |err| return mapWorldError(err);
    world.setUiText(fps, .{
        .position = .{ editor_top_fps_x, top.y + editor_bar_text_offset_y, 0.0 },
        .size = editor_system_text_size,
        .color = editor_palette.text,
        .value = fps_text,
    }) catch |err| return mapWorldError(err);

    try extractEditorPlaybackControlsInto(world, input);
}

pub fn extractEditorBottomBarInto(allocator: std.mem.Allocator, world: *runtime.World, input: FrameInput) RenderError!void {
    const bottom = editorBottomBarRect(input);
    const viewport = editorGameViewport(input);
    const status = std.fmt.allocPrint(allocator, "ENTITIES {d}  COMPONENTS {d}  RENDERABLES {d}  VIEWPORT {d}x{d}", .{
        input.editor.entity_count,
        input.editor.component_instance_count,
        input.editor.renderable_count,
        @as(u32, @intFromFloat(@round(viewport.width))),
        @as(u32, @intFromFloat(@round(viewport.height))),
    }) catch return RenderError.OutOfMemory;
    defer allocator.free(status);
    const status_text = world.createEngineTransientEntity("scrapbot.editor.bottom.status", "Editor Bottom Status") catch |err| return mapWorldError(err);
    world.setUiText(status_text, .{
        .position = .{ editor_panel_padding_x, bottom.y + editor_bar_text_offset_y, 0.0 },
        .size = editor_system_text_size,
        .color = editor_palette.text_muted,
        .value = status,
    }) catch |err| return mapWorldError(err);
}

fn extractEditorPlaybackControlsInto(world: *runtime.World, input: FrameInput) RenderError!void {
    const play_label = if (input.editor.paused) "PLAY" else "PAUSE";
    const play_color: [3]f32 = if (input.editor.paused) editor_palette.success else editor_palette.warning;
    const buttons = editorPlaybackButtonSpecs(input);
    try extractEditorButtonInto(world, buttons[0], play_label, play_color);
    try extractEditorButtonInto(world, buttons[1], "STEP", editor_palette.panel_muted);
}

const EditorButtonSpec = struct {
    id: []const u8,
    name: []const u8,
    rect: ScreenRect,
    command: []const u8,
};

fn editorPlaybackButtonSpecs(input: FrameInput) [2]EditorButtonSpec {
    return .{
        .{
            .id = "scrapbot.editor.controls.play",
            .name = "Editor Play",
            .rect = editorPlayButtonRect(input),
            .command = editor_command_play_toggle,
        },
        .{
            .id = "scrapbot.editor.controls.step",
            .name = "Editor Step",
            .rect = editorStepButtonRect(input),
            .command = editor_command_step,
        },
    };
}

fn extractEditorButtonInto(
    world: *runtime.World,
    spec: EditorButtonSpec,
    label: []const u8,
    color: [3]f32,
) RenderError!void {
    const button = world.createEngineTransientEntity(spec.id, spec.name) catch |err| return mapWorldError(err);
    world.setUiRect(button, .{
        .position = spec.rect.position(),
        .size = spec.rect.size3(),
        .color = color,
        .corner_radius = editor_button_corner_radius,
    }) catch |err| return mapWorldError(err);
    world.setUiButton(button) catch |err| return mapWorldError(err);
    world.setUiCommand(button, .{ .command = spec.command }) catch |err| return mapWorldError(err);

    var label_id_buffer: [96]u8 = undefined;
    const label_id = std.fmt.bufPrint(&label_id_buffer, "{s}.label", .{spec.id}) catch return RenderError.InvalidScene;
    var label_name_buffer: [96]u8 = undefined;
    const label_name = std.fmt.bufPrint(&label_name_buffer, "{s} Label", .{spec.name}) catch return RenderError.InvalidScene;
    const text = world.createEngineTransientEntity(label_id, label_name) catch |err| return mapWorldError(err);
    world.setUiText(text, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = 1.0,
        .color = editor_palette.text,
        .value = label,
    }) catch |err| return mapWorldError(err);
    world.setUiTextBlock(text, .{
        .size = spec.rect.size3(),
        .horizontal_align = "center",
        .vertical_align = "center",
    }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(text, .{
        .parent = spec.id,
        .order = 0,
    }) catch |err| return mapWorldError(err);
}

fn extractEditorSystemScrollbarInto(world: *runtime.World, input: FrameInput, list_clip: UiClipRect) RenderError!void {
    const profile_count = editorSystemProfileScrollCount(input);
    if (!editorSystemNeedsScrollForInput(input, profile_count)) {
        return;
    }

    const track_height = list_clip.size[1];
    const track_x = list_clip.position[0] + list_clip.size[0] + editor_scrollbar_gap;
    const track = world.createEngineTransientEntity("scrapbot.editor.debug.systems.scrollbar.track", "Editor System Scrollbar Track") catch |err| return mapWorldError(err);
    world.setUiRect(track, .{
        .position = .{ track_x, list_clip.position[1], 0.0 },
        .size = .{ editor_scrollbar_width, track_height, 0.0 },
        .color = editor_palette.panel_muted,
        .corner_radius = editor_scrollbar_width * 0.5,
    }) catch |err| return mapWorldError(err);

    const visible_rows = @as(f32, @floatFromInt(editorSystemVisibleRows(input)));
    const total_rows = @as(f32, @floatFromInt(profile_count));
    const thumb_height = @max(track_height * visible_rows / @max(total_rows, visible_rows), editor_scrollbar_width * 2.0);
    const max_scroll = editorSystemMaxScrollY(input, profile_count);
    const scroll_t = if (max_scroll > 0.0) std.math.clamp(input.editor.system_scroll_y / max_scroll, 0.0, 1.0) else 0.0;
    const thumb_y = list_clip.position[1] + (track_height - thumb_height) * scroll_t;

    const thumb = world.createEngineTransientEntity("scrapbot.editor.debug.systems.scrollbar.thumb", "Editor System Scrollbar Thumb") catch |err| return mapWorldError(err);
    world.setUiRect(thumb, .{
        .position = .{ track_x, thumb_y, 0.0 },
        .size = .{ editor_scrollbar_width, thumb_height, 0.0 },
        .color = editor_palette.accent_soft,
        .corner_radius = editor_scrollbar_width * 0.5,
    }) catch |err| return mapWorldError(err);
}

fn extractEditorEntityListInto(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    scene_world: *const runtime.World,
    input: FrameInput,
) RenderError!void {
    const panel = editorEntityPanelRect(input);
    _ = try extractEditorPanel(world, "scrapbot.editor.entities.panel", "Editor Entities Panel", panel, editor_palette.panel, 0.0);

    const entity_count = editorInspectableEntityCount(scene_world);
    const header_text = std.fmt.allocPrint(allocator, "ENTITIES {d}", .{entity_count}) catch return RenderError.OutOfMemory;
    defer allocator.free(header_text);
    try extractEditorText(world, "scrapbot.editor.entities.header", "Editor Entities Header", editorPanelTextPosition(panel, editorSystemHeaderYOffset()), header_text, editor_entity_text_size, editor_palette.text_muted);

    if (entity_count == 0) {
        try extractEditorText(world, "scrapbot.editor.entities.empty", "Editor Entities Empty", editorPanelTextPosition(panel, editorSystemRowsYOffset()), "NO ENTITIES", editor_entity_text_size, editor_palette.text_dim);
        return;
    }

    const list_clip = editorEntityListClipRect(scene_world, input);
    const entity_scroll = world.createEngineTransientEntity("scrapbot.editor.entities.scroll", "Editor Entities Scroll View") catch |err| return mapWorldError(err);
    world.setUiScrollView(entity_scroll, .{
        .position = list_clip.position,
        .size = list_clip.size,
        .content_offset = .{ 0.0, input.editor.entity_scroll_y, 0.0 },
    }) catch |err| return mapWorldError(err);

    const row_width = list_clip.size[0];
    const table_height = editorEntityTableContentHeight(entity_count);
    const entity_table = world.createEngineTransientEntity("scrapbot.editor.entities.table", "Editor Entities Table") catch |err| return mapWorldError(err);
    world.setUiRect(entity_table, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = .{ row_width, table_height, 0.0 },
        .color = editor_palette.shell,
        .corner_radius = editor_panel_corner_radius,
    }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(entity_table, .{
        .parent = "scrapbot.editor.entities.scroll",
        .order = 0,
    }) catch |err| return mapWorldError(err);

    const range = editorEntityVisibleRange(scene_world, input);
    for (range.start..range.end) |entity_index| {
        const handle = editorEntityHandleAt(scene_world, entity_index) orelse continue;
        const entity = scene_world.entity(handle) catch continue;
        const row_y = 16.0 + @as(f32, @floatFromInt(entity_index)) * editor_entity_row_stride;
        const is_selected = editorEntityHandlesEqual(input.editor.selected_entity, handle);
        if (is_selected) {
            var highlight_id_buffer: [192]u8 = undefined;
            const highlight_id = try formatEditorId(&highlight_id_buffer, "scrapbot.editor.entities.row.{d}.highlight", .{entity_index});
            const highlight = try extractEditorPanel(world, highlight_id, "Editor Entity Row Highlight", .{
                .x = 0.0,
                .y = row_y - 8.0,
                .width = row_width,
                .height = editor_entity_row_stride,
            }, editor_palette.panel_muted, editor_button_corner_radius);
            world.setUiLayoutItem(highlight, .{
                .parent = "scrapbot.editor.entities.table",
                .order = @intCast(entity_index),
            }) catch |err| return mapWorldError(err);
        }

        const component_count = editorEntityComponentCount(scene_world, handle);
        var component_text_buffer: [24]u8 = undefined;
        const component_text = std.fmt.bufPrint(&component_text_buffer, "{d}C", .{component_count}) catch return RenderError.InvalidScene;
        const component_width = editorTextWidth(component_text, editor_entity_text_size);
        const component_x = @max(row_width - editor_entity_row_component_padding_x - component_width, editor_entity_row_label_padding_x);
        const label_max_width = @max(component_x - editor_entity_row_label_padding_x - editor_entity_field_column_gap, 1.0);
        const raw_label = if (entity.name.len > 0) entity.name else entity.id;
        const label_text = fitEditorTextToWidth(allocator, raw_label, editor_entity_text_size, label_max_width) catch return RenderError.OutOfMemory;
        defer allocator.free(label_text);

        var label_id_buffer: [192]u8 = undefined;
        const label_id = try formatEditorId(&label_id_buffer, "scrapbot.editor.entities.row.{d}.label", .{entity_index});
        const row_label_color = if (entity.provenance == .spawned)
            editor_palette.text_dim
        else if (is_selected)
            editor_palette.accent_soft
        else
            editor_palette.text;
        _ = try extractEditorChildText(world, label_id, "Editor Entity Row Label", "scrapbot.editor.entities.table", .{
            editor_entity_row_label_padding_x,
            row_y,
            0.0,
        }, label_text, editor_entity_text_size, row_label_color);

        var component_id_buffer: [192]u8 = undefined;
        const component_id = try formatEditorId(&component_id_buffer, "scrapbot.editor.entities.row.{d}.components", .{entity_index});
        _ = try extractEditorChildText(world, component_id, "Editor Entity Row Component Count", "scrapbot.editor.entities.table", .{
            component_x,
            row_y,
            0.0,
        }, component_text, editor_entity_text_size, editor_palette.text_muted);
    }

    try extractEditorEntityScrollbarInto(world, scene_world, input, list_clip);
}

fn extractEditorEntityScrollbarInto(world: *runtime.World, scene_world: *const runtime.World, input: FrameInput, list_clip: UiClipRect) RenderError!void {
    if (!editorEntityNeedsScroll(scene_world, input)) {
        return;
    }

    const track_height = list_clip.size[1];
    const track_x = list_clip.position[0] + list_clip.size[0] + editor_scrollbar_gap;
    const track = world.createEngineTransientEntity("scrapbot.editor.entities.scrollbar.track", "Editor Entities Scrollbar Track") catch |err| return mapWorldError(err);
    world.setUiRect(track, .{
        .position = .{ track_x, list_clip.position[1], 0.0 },
        .size = .{ editor_scrollbar_width, track_height, 0.0 },
        .color = editor_palette.panel_muted,
        .corner_radius = editor_scrollbar_width * 0.5,
    }) catch |err| return mapWorldError(err);

    const visible_rows = @as(f32, @floatFromInt(editorEntityVisibleRows(input)));
    const total_rows = @as(f32, @floatFromInt(editorInspectableEntityCount(scene_world)));
    const thumb_height = @max(track_height * visible_rows / @max(total_rows, visible_rows), editor_scrollbar_width * 2.0);
    const max_scroll = editorEntityMaxScrollY(scene_world, input);
    const scroll_t = if (max_scroll > 0.0) std.math.clamp(input.editor.entity_scroll_y / max_scroll, 0.0, 1.0) else 0.0;
    const thumb_y = list_clip.position[1] + (track_height - thumb_height) * scroll_t;

    const thumb = world.createEngineTransientEntity("scrapbot.editor.entities.scrollbar.thumb", "Editor Entities Scrollbar Thumb") catch |err| return mapWorldError(err);
    world.setUiRect(thumb, .{
        .position = .{ track_x, thumb_y, 0.0 },
        .size = .{ editor_scrollbar_width, thumb_height, 0.0 },
        .color = editor_palette.accent_soft,
        .corner_radius = editor_scrollbar_width * 0.5,
    }) catch |err| return mapWorldError(err);
}

fn extractEditorComponentInspectorInto(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    scene_world: *const runtime.World,
    input: FrameInput,
) RenderError!void {
    const sidebar = editorSidebarPanelRect(editorRightSidebarRect(input));
    const panel_x = sidebar.x;
    const panel_y = sidebar.y;
    const panel_width = sidebar.width;
    const panel_height = sidebar.height;

    _ = try extractEditorPanel(world, "scrapbot.editor.inspector.panel", "Editor Inspector Panel", .{
        .x = panel_x,
        .y = panel_y,
        .width = panel_width,
        .height = panel_height,
    }, editor_palette.panel, 0.0);

    try extractEditorText(world, "scrapbot.editor.inspector.title", "Editor Inspector Title", .{
        panel_x + editor_panel_padding_x,
        panel_y + editor_panel_padding_y,
        0.0,
    }, "COMPONENTS", editor_inspector_text_size, editor_palette.text);

    const selected = input.editor.selected_entity orelse {
        try extractEditorText(world, "scrapbot.editor.inspector.empty", "Editor Inspector Empty", .{
            panel_x + editor_panel_padding_x,
            panel_y + editor_panel_padding_y + editor_inspector_line_stride * 2.0,
            0.0,
        }, "NO ENTITY SELECTED", editor_inspector_text_size, editor_palette.text);
        try extractEditorText(world, "scrapbot.editor.inspector.empty.hint", "Editor Inspector Empty Hint", .{
            panel_x + editor_panel_padding_x,
            panel_y + editor_panel_padding_y + editor_inspector_line_stride * 3.0,
            0.0,
        }, "CLICK A MESH", editor_inspector_text_size, editor_palette.text_dim);
        return;
    };

    const entity = scene_world.entity(selected) catch {
        try extractEditorText(world, "scrapbot.editor.inspector.unavailable", "Editor Inspector Unavailable", .{
            panel_x + editor_panel_padding_x,
            panel_y + editor_panel_padding_y + editor_inspector_line_stride * 2.0,
            0.0,
        }, "SELECTION UNAVAILABLE", editor_inspector_text_size, editor_palette.danger);
        return;
    };

    const entity_header = std.fmt.allocPrint(allocator, "{s}  {s}", .{ entity.name, entity.id }) catch return RenderError.OutOfMemory;
    defer allocator.free(entity_header);
    try extractEditorText(world, "scrapbot.editor.inspector.entity", "Editor Inspector Entity", .{
        panel_x + editor_panel_padding_x,
        panel_y + editor_panel_padding_y + editor_inspector_line_stride,
        0.0,
    }, entity_header, editor_inspector_text_size, editor_palette.text_muted);

    const scroll_clip = editorInspectorScrollClipRect(input);
    const scroll = world.createEngineTransientEntity("scrapbot.editor.inspector.scroll", "Editor Inspector Scroll View") catch |err| return mapWorldError(err);
    world.setUiScrollView(scroll, .{
        .position = scroll_clip.position,
        .size = scroll_clip.size,
        .content_offset = .{ 0.0, input.editor.inspector_scroll_y, 0.0 },
    }) catch |err| return mapWorldError(err);

    const card_width = @max(scroll_clip.size[0], 1.0);
    const stack_id = "scrapbot.editor.inspector.components";
    const stack = world.createEngineTransientEntity(stack_id, "Editor Component Stack") catch |err| return mapWorldError(err);
    world.setUiVGroup(stack, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = .{
            card_width,
            editorInspectorComponentContentHeight(scene_world, input.editor.selected_entity),
            0.0,
        },
        .spacing = editor_render_chrome.inspector_card_gap,
        .padding = .{ 0.0, 0.0, 0.0 },
    }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(stack, .{
        .parent = "scrapbot.editor.inspector.scroll",
        .order = 0,
    }) catch |err| return mapWorldError(err);

    const field_stride = editor_render_chrome.inspector_field_row_stride;
    var component_index: usize = 0;
    var stack_order: i32 = 0;
    var components = scene_world.entityComponents(selected) catch {
        return;
    };
    while (components.next()) |component_id| {
        if (component_index > 0) {
            var separator_id_buffer: [192]u8 = undefined;
            const separator_id = try formatEditorId(&separator_id_buffer, "scrapbot.editor.inspector.component.separator.{d}", .{component_index});
            const separator = world.createEngineTransientEntity(separator_id, "Editor Component Separator") catch |err| return mapWorldError(err);
            world.setUiSeparator(separator, .{
                .position = .{ 0.0, 0.0, 0.0 },
                .size = .{ card_width, editor_render_chrome.inspector_separator_height, 0.0 },
                .color = editor_palette.panel_muted,
            }) catch |err| return mapWorldError(err);
            world.setUiLayoutItem(separator, .{
                .parent = stack_id,
                .order = stack_order,
            }) catch |err| return mapWorldError(err);
            stack_order += 1;
        }

        const field_count = scene_world.componentFieldCount(component_id);
        const card_height = editorInspectorComponentCardHeight(scene_world, component_id);
        var card_id_buffer: [192]u8 = undefined;
        const card_id = try formatEditorId(&card_id_buffer, "scrapbot.editor.inspector.component.{d}", .{component_index});
        const card = try extractEditorPanel(world, card_id, "Editor Component Card", .{
            .x = 0.0,
            .y = 0.0,
            .width = card_width,
            .height = card_height,
        }, editor_palette.shell, editor_panel_corner_radius);
        world.setUiLayoutItem(card, .{
            .parent = stack_id,
            .order = stack_order,
        }) catch |err| return mapWorldError(err);
        stack_order += 1;

        var title_id_buffer: [192]u8 = undefined;
        const title_id = try formatEditorId(&title_id_buffer, "scrapbot.editor.inspector.component.{d}.title", .{component_index});
        const title_max_width = @max(card_width - editor_inspector_card_padding_x * 2.0, 1.0);
        const title_value = fitEditorTextToWidth(allocator, component_id, editor_inspector_text_size, title_max_width) catch return RenderError.OutOfMemory;
        defer allocator.free(title_value);
        _ = try extractEditorChildText(world, title_id, "Editor Component Title", card_id, .{
            editor_inspector_card_padding_x,
            editor_inspector_card_padding_y,
            0.0,
        }, title_value, editor_inspector_text_size, editor_palette.accent_soft);

        for (0..field_count) |field_index| {
            const field_name = scene_world.componentFieldNameAt(component_id, field_index) orelse continue;
            const value = scene_world.getComponentFieldValue(selected, component_id, field_name) catch continue;
            const field_y = editor_inspector_card_padding_y + editorTextHeight(editor_inspector_text_size) + 12.0 + @as(f32, @floatFromInt(field_index)) * field_stride;
            try extractEditorPropertyRow(allocator, world, .{
                .parent_id = card_id,
                .component_index = component_index,
                .field_index = field_index,
                .component_id = component_id,
                .field_name = field_name,
                .value = value,
                .card_width = card_width,
                .field_y = field_y,
                .text_input = input.editor.text_input,
            });
        }

        component_index += 1;
    }
}

fn extractEditorText(
    world: *runtime.World,
    id: []const u8,
    name: []const u8,
    position: [3]f32,
    value: []const u8,
    size: f32,
    color: [3]f32,
) RenderError!void {
    const entity = world.createEngineTransientEntity(id, name) catch |err| return mapWorldError(err);
    world.setUiText(entity, .{
        .position = position,
        .size = size,
        .color = color,
        .value = value,
    }) catch |err| return mapWorldError(err);
}

fn extractEditorPanel(
    world: *runtime.World,
    id: []const u8,
    name: []const u8,
    rect: ScreenRect,
    color: [3]f32,
    corner_radius: f32,
) RenderError!runtime.EntityHandle {
    const panel = world.createEngineTransientEntity(id, name) catch |err| return mapWorldError(err);
    world.setUiRect(panel, .{
        .position = rect.position(),
        .size = rect.size3(),
        .color = color,
        .corner_radius = corner_radius,
    }) catch |err| return mapWorldError(err);
    return panel;
}

fn extractEditorChildText(
    world: *runtime.World,
    id: []const u8,
    name: []const u8,
    parent: []const u8,
    position: [3]f32,
    value: []const u8,
    size: f32,
    color: [3]f32,
) RenderError!runtime.EntityHandle {
    try extractEditorText(world, id, name, position, value, size, color);
    const entity = world.findEntityById(id) orelse return RenderError.InvalidScene;
    world.setUiLayoutItem(entity, .{ .parent = parent }) catch |err| return mapWorldError(err);
    return entity;
}

fn formatInspectorFieldValue(allocator: std.mem.Allocator, value: runtime.ComponentValue) error{OutOfMemory}![]const u8 {
    return switch (value) {
        .boolean => |payload| std.fmt.allocPrint(allocator, "{s}", .{if (payload) "TRUE" else "FALSE"}),
        .int => |payload| std.fmt.allocPrint(allocator, "{d}", .{payload}),
        .float => |payload| std.fmt.allocPrint(allocator, "{d:.3}", .{payload}),
        .vec3 => |payload| std.fmt.allocPrint(allocator, "{d:.2} {d:.2} {d:.2}", .{ payload[0], payload[1], payload[2] }),
        .string => |payload| blk: {
            const max_len: usize = 26;
            const visible = if (payload.len > max_len) payload[0..max_len] else payload;
            const suffix = if (payload.len > max_len) "..." else "";
            break :blk std.fmt.allocPrint(allocator, "{s}{s}", .{ visible, suffix });
        },
    };
}

fn formatEditorInputValue(buffer: *[editor_input_text_buffer_len]u8, value: runtime.ComponentValue, vec3_lane: u2) ?[]const u8 {
    const text = switch (value) {
        .boolean => |payload| std.fmt.bufPrint(buffer, "{s}", .{if (payload) "true" else "false"}) catch return null,
        .int => |payload| std.fmt.bufPrint(buffer, "{d}", .{payload}) catch return null,
        .float => |payload| std.fmt.bufPrint(buffer, "{d:.3}", .{payload}) catch return null,
        .vec3 => |payload| std.fmt.bufPrint(buffer, "{d:.3}", .{payload[vec3_lane]}) catch return null,
        .string => |payload| blk: {
            if (payload.len > buffer.len) {
                return null;
            }
            @memcpy(buffer[0..payload.len], payload);
            break :blk buffer[0..payload.len];
        },
    };
    if (text.len < buffer.len) {
        @memset(buffer[text.len..], 0);
    }
    return text;
}

fn editorFieldIsPrimitiveSelector(component_id: []const u8, field_name: []const u8) bool {
    return std.mem.eql(u8, component_id, runtime.geometry_primitive_component_id) and
        std.mem.eql(u8, field_name, "primitive");
}

fn editorFieldLooksLikeColor(field_name: []const u8) bool {
    return std.mem.indexOf(u8, field_name, "color") != null or
        std.mem.indexOf(u8, field_name, "colour") != null;
}

fn editorVec3LaneColor(lane: u2) [3]f32 {
    return editor_color_channels[@as(usize, lane)];
}

fn editorVec3LaneLabel(lane: u2) []const u8 {
    return editor_vec3_lane_labels[@as(usize, lane)];
}
const EditorPropertyRowSpec = struct {
    parent_id: []const u8,
    component_index: usize,
    field_index: usize,
    component_id: []const u8,
    field_name: []const u8,
    value: runtime.ComponentValue,
    card_width: f32,
    field_y: f32,
    text_input: EditorTextInputFrame = .{},
};

fn extractEditorPropertyRow(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    spec: EditorPropertyRowSpec,
) RenderError!void {
    var row_id_buffer: [192]u8 = undefined;
    const row_id = try formatEditorId(&row_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.row", .{ spec.component_index, spec.field_index });
    var label_cell_id_buffer: [192]u8 = undefined;
    const label_cell_id = try formatEditorId(&label_cell_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.label_cell", .{ spec.component_index, spec.field_index });
    var value_cell_id_buffer: [192]u8 = undefined;
    const value_cell_id = try formatEditorId(&value_cell_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.value_cell", .{ spec.component_index, spec.field_index });

    const row = world.createEngineTransientEntity(row_id, "Editor Component Field Table") catch |err| return mapWorldError(err);
    world.setUiTable(row, .{
        .position = .{ editor_inspector_card_padding_x, spec.field_y + editor_inspector_field_control_offset_y - editor_inspector_input_cell_padding, 0.0 },
        .size = .{ @max(spec.card_width - editor_inspector_card_padding_x * 2.0, 1.0), editor_inspector_field_row_height, 0.0 },
        .columns = 2,
        .row_height = editor_inspector_field_row_height,
        .column_gap = editor_inspector_field_column_gap,
        .row_gap = editor_render_chrome.inspector_field_row_margin_y,
        .first_column_ratio = 0.5,
    }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(row, .{
        .parent = spec.parent_id,
        .order = @intCast(spec.field_index),
    }) catch |err| return mapWorldError(err);

    const label_cell = world.createEngineTransientEntity(label_cell_id, "Editor Component Field Label Cell") catch |err| return mapWorldError(err);
    world.setUiSpacer(label_cell, .{ .size = .{ 0.0, editor_inspector_field_row_height, 0.0 } }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(label_cell, .{
        .parent = row_id,
        .order = 0,
        .@"align" = "fill",
    }) catch |err| return mapWorldError(err);

    const value_cell = world.createEngineTransientEntity(value_cell_id, "Editor Component Field Value Cell") catch |err| return mapWorldError(err);
    world.setUiSpacer(value_cell, .{ .size = .{ 0.0, editor_inspector_field_row_height, 0.0 } }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(value_cell, .{
        .parent = row_id,
        .order = 1,
        .@"align" = "fill",
    }) catch |err| return mapWorldError(err);

    var label_id_buffer: [192]u8 = undefined;
    const label_id = try formatEditorId(&label_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.label", .{ spec.component_index, spec.field_index });

    const label_rect = ui_layout.resolvedItemRect(world, label_cell) catch |err| return mapLayoutError(err);
    const value_rect = ui_layout.resolvedItemRect(world, value_cell) catch |err| return mapLayoutError(err);
    const label_max_width = @max(label_rect.size[0], 1.0);
    const label_text = fitEditorTextToWidth(allocator, spec.field_name, editor_inspector_text_size, label_max_width) catch return RenderError.OutOfMemory;
    defer allocator.free(label_text);

    _ = try extractEditorChildText(world, label_id, "Editor Component Field Label", label_cell_id, .{
        0.0,
        editor_inspector_field_text_offset_y,
        0.0,
    }, label_text, editor_inspector_text_size, editor_palette.text_muted);

    var value_spec = spec;
    value_spec.parent_id = value_cell_id;
    value_spec.card_width = value_rect.size[0];
    value_spec.field_y = -editor_inspector_field_control_offset_y + editor_inspector_input_cell_padding;

    switch (spec.value) {
        .vec3 => |payload| {
            var value_row_id_buffer: [192]u8 = undefined;
            const value_row_id = try formatEditorId(&value_row_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.value_row", .{ spec.component_index, spec.field_index });
            const padded_value_width = @max(value_rect.size[0] - editor_inspector_input_cell_padding * 2.0, 1.0);
            const value_row = world.createEngineTransientEntity(value_row_id, "Editor Property Vec3 Value Row") catch |err| return mapWorldError(err);
            world.setUiHGroup(value_row, .{
                .position = .{ editor_inspector_input_cell_padding, 0.0, 0.0 },
                .size = .{ padded_value_width, editor_inspector_field_row_height, 0.0 },
                .spacing = editor_inspector_input_gap,
            }) catch |err| return mapWorldError(err);
            world.setUiLayoutItem(value_row, .{
                .parent = value_cell_id,
                .order = 0,
            }) catch |err| return mapWorldError(err);

            value_spec.parent_id = value_row_id;
            const is_color = editorFieldLooksLikeColor(spec.field_name);
            const child_count: f32 = if (is_color) 7.0 else 6.0;
            const spacing_total = @max(child_count - 1.0, 0.0) * editor_inspector_input_gap;
            const swatch_total_width = if (is_color) editor_inspector_swatch_size else 0.0;
            const lane_width = @max((padded_value_width - swatch_total_width - editor_inspector_lane_label_width * 3.0 - spacing_total) / 3.0, 1.0);
            var order: i32 = 0;
            if (is_color) {
                try extractEditorColorSwatch(world, value_spec, .{
                    .order = order,
                    .x = 0.0,
                    .color = payload,
                });
                order += 1;
            }
            for (0..3) |lane_index| {
                var lane_buffer: [editor_input_text_buffer_len]u8 = [_]u8{0} ** editor_input_text_buffer_len;
                const lane: u2 = @intCast(lane_index);
                try extractEditorVec3LaneLabel(world, value_spec, .{
                    .lane = lane,
                    .order = order,
                    .x = 0.0,
                    .color = editorVec3LaneColor(lane),
                });
                order += 1;
                const is_focused = editorTextInputFocuses(spec.text_input, spec.component_id, spec.field_name, lane);
                const value_text = if (is_focused)
                    spec.text_input.text()
                else
                    std.fmt.bufPrint(&lane_buffer, "{d:.2}", .{payload[lane]}) catch "";
                try extractEditorPropertyInputBox(allocator, world, value_spec, .{
                    .lane = lane,
                    .order = order,
                    .x = 0.0,
                    .width = lane_width,
                    .text = value_text,
                    .focused = is_focused,
                    .cursor = if (is_focused) spec.text_input.cursor else value_text.len,
                    .selection_anchor = if (is_focused) spec.text_input.selection_anchor else value_text.len,
                });
                order += 1;
            }
        },
        .boolean => |payload| {
            try extractEditorBooleanToggle(world, value_spec, .{
                .x = editor_inspector_input_cell_padding,
                .width = @min(editor_inspector_toggle_width, @max(value_rect.size[0] - editor_inspector_input_cell_padding * 2.0, 1.0)),
                .value = payload,
            });
        },
        .string => |payload| {
            if (editorFieldIsPrimitiveSelector(spec.component_id, spec.field_name)) {
                try extractEditorPrimitiveSelector(allocator, world, value_spec, .{
                    .x = editor_inspector_input_cell_padding,
                    .width = @max(value_rect.size[0] - editor_inspector_input_cell_padding * 2.0, 1.0),
                    .value = payload,
                });
            } else {
                var value_buffer: [editor_input_text_buffer_len]u8 = [_]u8{0} ** editor_input_text_buffer_len;
                const is_focused = editorTextInputFocuses(spec.text_input, spec.component_id, spec.field_name, 0);
                const value_text = if (is_focused)
                    spec.text_input.text()
                else
                    formatEditorInputValue(&value_buffer, spec.value, 0) orelse "";
                try extractEditorPropertyInputBox(allocator, world, value_spec, .{
                    .lane = null,
                    .x = editor_inspector_input_cell_padding,
                    .width = @max(value_rect.size[0] - editor_inspector_input_cell_padding * 2.0, 1.0),
                    .text = value_text,
                    .focused = is_focused,
                    .cursor = if (is_focused) spec.text_input.cursor else value_text.len,
                    .selection_anchor = if (is_focused) spec.text_input.selection_anchor else value_text.len,
                });
            }
        },
        else => {
            var value_buffer: [editor_input_text_buffer_len]u8 = [_]u8{0} ** editor_input_text_buffer_len;
            const is_focused = editorTextInputFocuses(spec.text_input, spec.component_id, spec.field_name, 0);
            const value_text = if (is_focused)
                spec.text_input.text()
            else
                formatEditorInputValue(&value_buffer, spec.value, 0) orelse "";
            try extractEditorPropertyInputBox(allocator, world, value_spec, .{
                .lane = null,
                .x = editor_inspector_input_cell_padding,
                .width = @max(value_rect.size[0] - editor_inspector_input_cell_padding * 2.0, 1.0),
                .text = value_text,
                .focused = is_focused,
                .cursor = if (is_focused) spec.text_input.cursor else value_text.len,
                .selection_anchor = if (is_focused) spec.text_input.selection_anchor else value_text.len,
            });
        },
    }
}

const EditorPropertyInputBoxSpec = struct {
    lane: ?u2,
    order: i32 = 0,
    x: f32,
    width: f32,
    text: []const u8,
    focused: bool,
    cursor: usize,
    selection_anchor: usize,
};

const EditorVec3LaneLabelSpec = struct {
    lane: u2,
    order: i32 = 0,
    x: f32,
    color: [3]f32,
};

fn extractEditorVec3LaneLabel(
    world: *runtime.World,
    row: EditorPropertyRowSpec,
    label: EditorVec3LaneLabelSpec,
) RenderError!void {
    var label_id_buffer: [192]u8 = undefined;
    const label_id = try formatEditorId(&label_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.lane_label.{d}", .{ row.component_index, row.field_index, label.lane });
    const text = try extractEditorChildText(world, label_id, "Editor Property Vec3 Lane Label", row.parent_id, .{
        label.x,
        row.field_y,
        0.0,
    }, editorVec3LaneLabel(label.lane), editor_inspector_text_size, label.color);
    world.setUiLayoutItem(text, .{
        .parent = row.parent_id,
        .order = label.order,
        .min_size = .{ editor_inspector_lane_label_width, editor_inspector_input_height, 0.0 },
        .preferred_size = .{ editor_inspector_lane_label_width, editor_inspector_input_height, 0.0 },
        .@"align" = "start",
    }) catch |err| return mapWorldError(err);
}

const EditorBooleanToggleSpec = struct {
    order: i32 = 0,
    x: f32,
    width: f32,
    value: bool,
};

fn extractEditorBooleanToggle(
    world: *runtime.World,
    row: EditorPropertyRowSpec,
    toggle: EditorBooleanToggleSpec,
) RenderError!void {
    var toggle_id_buffer: [192]u8 = undefined;
    const toggle_id = try formatEditorId(&toggle_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.toggle", .{ row.component_index, row.field_index });
    var label_id_buffer: [192]u8 = undefined;
    const label_id = try formatEditorId(&label_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.toggle.label", .{ row.component_index, row.field_index });

    const color = if (toggle.value) editor_palette.input_active else editor_palette.input;
    const toggle_entity = try extractEditorPanel(world, toggle_id, "Editor Property Boolean Toggle", .{
        .x = toggle.x,
        .y = row.field_y + editor_inspector_field_control_offset_y,
        .width = toggle.width,
        .height = editor_inspector_input_height,
    }, color, editor_inspector_input_corner_radius);
    world.setUiLayoutItem(toggle_entity, .{
        .parent = row.parent_id,
        .order = toggle.order,
        .preferred_size = .{ toggle.width, editor_inspector_input_height, 0.0 },
        .@"align" = "start",
    }) catch |err| return mapWorldError(err);
    world.setUiBorder(toggle_entity, .{
        .color = if (toggle.value) editor_palette.accent_soft else editor_palette.text_dim,
        .thickness = editor_inspector_input_border_thickness,
    }) catch |err| return mapWorldError(err);

    const label = if (toggle.value) "ON" else "OFF";
    const label_width = editorTextWidth(label, editor_inspector_text_size);
    const label_x = @max((toggle.width - label_width) * 0.5, editor_inspector_input_text_offset_x);
    const text = try extractEditorChildText(world, label_id, "Editor Property Boolean Toggle Label", toggle_id, .{
        label_x,
        editor_inspector_input_text_offset_y,
        0.0,
    }, label, editor_inspector_text_size, editor_palette.text);
    world.setUiLayoutItem(text, .{
        .parent = toggle_id,
        .order = 1,
    }) catch |err| return mapWorldError(err);
}

const EditorPrimitiveSelectorSpec = struct {
    order: i32 = 0,
    x: f32,
    width: f32,
    value: []const u8,
};

fn extractEditorPrimitiveSelector(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    row: EditorPropertyRowSpec,
    selector: EditorPrimitiveSelectorSpec,
) RenderError!void {
    var selector_id_buffer: [192]u8 = undefined;
    const selector_id = try formatEditorId(&selector_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.select", .{ row.component_index, row.field_index });
    var value_id_buffer: [192]u8 = undefined;
    const value_id = try formatEditorId(&value_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.select.value", .{ row.component_index, row.field_index });

    const box = try extractEditorPanel(world, selector_id, "Editor Property Primitive Selector", .{
        .x = selector.x,
        .y = row.field_y + editor_inspector_field_control_offset_y,
        .width = selector.width,
        .height = editor_inspector_input_height,
    }, editor_palette.input, editor_inspector_input_corner_radius);
    world.setUiLayoutItem(box, .{
        .parent = row.parent_id,
        .order = selector.order,
        .preferred_size = .{ selector.width, editor_inspector_input_height, 0.0 },
        .grow = 1.0,
        .shrink = 1.0,
        .@"align" = "start",
    }) catch |err| return mapWorldError(err);
    world.setUiBorder(box, .{
        .color = editor_palette.text_dim,
        .thickness = editor_inspector_input_border_thickness,
    }) catch |err| return mapWorldError(err);

    const label = std.fmt.allocPrint(allocator, "{s} >", .{selector.value}) catch return RenderError.OutOfMemory;
    defer allocator.free(label);
    const fitted = fitEditorTextToWidth(allocator, label, editor_inspector_text_size, @max(selector.width - editor_inspector_input_text_offset_x * 2.0, 1.0)) catch return RenderError.OutOfMemory;
    defer allocator.free(fitted);
    const text = try extractEditorChildText(world, value_id, "Editor Property Primitive Selector Value", selector_id, .{
        editor_inspector_input_text_offset_x,
        editor_inspector_input_text_offset_y,
        0.0,
    }, fitted, editor_inspector_text_size, editor_palette.text);
    world.setUiLayoutItem(text, .{
        .parent = selector_id,
        .order = 1,
    }) catch |err| return mapWorldError(err);
}

const EditorColorSwatchSpec = struct {
    order: i32 = 0,
    x: f32,
    color: [3]f32,
};

fn extractEditorColorSwatch(
    world: *runtime.World,
    row: EditorPropertyRowSpec,
    swatch: EditorColorSwatchSpec,
) RenderError!void {
    var swatch_id_buffer: [192]u8 = undefined;
    const swatch_id = try formatEditorId(&swatch_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.swatch", .{ row.component_index, row.field_index });
    const safe_color = [3]f32{
        clamp01(swatch.color[0]),
        clamp01(swatch.color[1]),
        clamp01(swatch.color[2]),
    };
    const entity = try extractEditorPanel(world, swatch_id, "Editor Property Color Swatch", .{
        .x = swatch.x,
        .y = row.field_y + editor_inspector_field_control_offset_y,
        .width = editor_inspector_swatch_size,
        .height = editor_inspector_input_height,
    }, safe_color, editor_inspector_input_corner_radius);
    world.setUiLayoutItem(entity, .{
        .parent = row.parent_id,
        .order = swatch.order,
        .preferred_size = .{ editor_inspector_swatch_size, editor_inspector_input_height, 0.0 },
        .@"align" = "start",
    }) catch |err| return mapWorldError(err);
    world.setUiBorder(entity, .{
        .color = editor_palette.text_dim,
        .thickness = editor_inspector_input_border_thickness,
    }) catch |err| return mapWorldError(err);
}

fn extractEditorPropertyInputBox(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    row: EditorPropertyRowSpec,
    input: EditorPropertyInputBoxSpec,
) RenderError!void {
    var input_id_buffer: [192]u8 = undefined;
    const input_id = if (input.lane) |lane|
        try formatEditorId(&input_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.input.{d}", .{ row.component_index, row.field_index, lane })
    else
        try formatEditorId(&input_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.input", .{ row.component_index, row.field_index });
    var value_id_buffer: [192]u8 = undefined;
    const value_id = if (input.lane) |lane|
        try formatEditorId(&value_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.value.{d}", .{ row.component_index, row.field_index, lane })
    else
        try formatEditorId(&value_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.value", .{ row.component_index, row.field_index });

    const box = try extractEditorPanel(world, input_id, "Editor Property Text Input", .{
        .x = input.x,
        .y = row.field_y + editor_inspector_field_control_offset_y,
        .width = input.width,
        .height = editor_inspector_input_height,
    }, editor_palette.input, editor_inspector_input_corner_radius);
    world.setUiLayoutItem(box, .{
        .parent = row.parent_id,
        .order = input.order,
        .min_size = .{ 1.0, editor_inspector_input_height, 0.0 },
        .preferred_size = .{ input.width, editor_inspector_input_height, 0.0 },
        .grow = 1.0,
        .shrink = 1.0,
        .@"align" = "start",
    }) catch |err| return mapWorldError(err);
    if (input.focused) {
        world.setUiBorder(box, .{
            .color = editor_palette.accent_soft,
            .thickness = editor_inspector_input_border_thickness,
        }) catch |err| return mapWorldError(err);
    }

    const selection_start = @min(input.cursor, input.selection_anchor);
    const selection_end = @max(input.cursor, input.selection_anchor);
    if (input.focused and selection_start < selection_end) {
        var selection_id_buffer: [192]u8 = undefined;
        const selection_id = if (input.lane) |lane|
            try formatEditorId(&selection_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.selection.{d}", .{ row.component_index, row.field_index, lane })
        else
            try formatEditorId(&selection_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.selection", .{ row.component_index, row.field_index });
        const start_x = std.math.clamp(
            editor_inspector_input_text_offset_x + editorTextWidth(input.text[0..@min(selection_start, input.text.len)], editor_inspector_text_size),
            editor_inspector_input_text_offset_x,
            @max(input.width - editor_inspector_input_text_offset_x, editor_inspector_input_text_offset_x),
        );
        const end_x = std.math.clamp(
            editor_inspector_input_text_offset_x + editorTextWidth(input.text[0..@min(selection_end, input.text.len)], editor_inspector_text_size),
            editor_inspector_input_text_offset_x,
            @max(input.width - editor_inspector_input_text_offset_x, editor_inspector_input_text_offset_x),
        );
        const selection = try extractEditorPanel(world, selection_id, "Editor Property Text Selection", .{
            .x = start_x,
            .y = editor_inspector_input_text_offset_y,
            .width = @max(end_x - start_x, 1.0),
            .height = editorTextHeight(editor_inspector_text_size),
        }, editor_palette.input_selection, 2.0);
        world.setUiLayoutItem(selection, .{
            .parent = input_id,
            .order = 0,
        }) catch |err| return mapWorldError(err);
    }

    const text_max_width = @max(input.width - editor_inspector_input_text_offset_x * 2.0, 1.0);
    const fitted_text = fitEditorTextToWidth(allocator, input.text, editor_inspector_text_size, text_max_width) catch return RenderError.OutOfMemory;
    defer allocator.free(fitted_text);
    const text_entity = try extractEditorChildText(world, value_id, "Editor Property Text Input Value", input_id, .{
        editor_inspector_input_text_offset_x,
        editor_inspector_input_text_offset_y,
        0.0,
    }, fitted_text, editor_inspector_text_size, if (input.focused) editor_palette.text else editor_palette.text_muted);
    world.setUiLayoutItem(text_entity, .{
        .parent = input_id,
        .order = 1,
    }) catch |err| return mapWorldError(err);

    if (input.focused) {
        const cursor_x = std.math.clamp(
            editor_inspector_input_text_offset_x + editorTextWidth(input.text[0..@min(input.cursor, input.text.len)], editor_inspector_text_size),
            editor_inspector_input_text_offset_x,
            @max(input.width - editor_inspector_input_text_offset_x, editor_inspector_input_text_offset_x),
        );
        var caret_id_buffer: [192]u8 = undefined;
        const caret_id = if (input.lane) |lane|
            try formatEditorId(&caret_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.caret.{d}", .{ row.component_index, row.field_index, lane })
        else
            try formatEditorId(&caret_id_buffer, "scrapbot.editor.inspector.component.{d}.field.{d}.caret", .{ row.component_index, row.field_index });
        const caret = try extractEditorPanel(world, caret_id, "Editor Property Text Input Caret", .{
            .x = cursor_x,
            .y = editor_inspector_input_text_offset_y,
            .width = editor_inspector_caret_width,
            .height = editorTextHeight(editor_inspector_text_size),
        }, editor_palette.accent_soft, 0.0);
        world.setUiLayoutItem(caret, .{
            .parent = input_id,
            .order = 2,
        }) catch |err| return mapWorldError(err);
    }
}
fn editorTextInputFocuses(input: EditorTextInputFrame, component_id: []const u8, field_name: []const u8, lane: u2) bool {
    return input.active and
        input.selection.vec3_lane == lane and
        std.mem.eql(u8, input.selection.componentId(), component_id) and
        std.mem.eql(u8, input.selection.fieldName(), field_name);
}
fn mapWorldError(err: anyerror) RenderError {
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
