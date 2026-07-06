const std = @import("std");
const runtime = @import("../runtime.zig");
const ui_layout = @import("../ui_layout.zig");
const editor_state_types = @import("state.zig");
const editor_layout = @import("layout.zig");
const editor_render_chrome = @import("render_chrome.zig");
const editor_input_routing = @import("input_routing.zig");
const editor_theme = @import("theme.zig");
const render_input = @import("../render/input.zig");
const editor_input = @import("input.zig");
const editor_metrics = @import("metrics.zig");

const FrameInput = render_input.FrameInput;
const EditorError = editor_state_types.EditorError;
const EditorSplitter = editor_state_types.EditorSplitter;
const EditorState = editor_state_types.EditorState;
const EditorFieldSelection = editor_state_types.EditorFieldSelection;
pub const EditorCursorKind = editor_input_routing.CursorKind;
const ScreenRect = editor_layout.ScreenRect;
const pointInsideScreenRect = editor_layout.pointInsideScreenRect;
const editorGameViewport = editor_layout.gameViewport;
const editorPlayButtonRect = editor_layout.playButtonRect;
const editorStepButtonRect = editor_layout.stepButtonRect;
const editorSplitterHitRect = editor_layout.splitterHitRect;
const editorInspectorFieldLayout = editor_render_chrome.inspectorFieldLayout;
const editorTextHeight = editor_render_chrome.textHeight;
const editor_inspector_text_size = editor_render_chrome.inspector_text_size;
const editor_inspector_card_gap = editor_render_chrome.inspector_card_gap;
const editor_inspector_separator_height = editor_render_chrome.inspector_separator_height;
const editor_inspector_card_padding_y = editor_render_chrome.inspector_card_padding_y;
const editor_inspector_field_row_stride = editor_render_chrome.inspector_field_row_stride;
const editor_inspector_field_control_offset_y = editor_render_chrome.inspector_field_control_offset_y;
const editor_inspector_input_cell_padding = editor_render_chrome.inspector_input_cell_padding;
const editor_inspector_field_row_height = editor_render_chrome.inspector_field_row_height;
const editor_inspector_input_gap = editor_render_chrome.inspector_input_gap;
const editor_inspector_swatch_size = editor_render_chrome.inspector_swatch_size;
const editor_inspector_lane_label_width = editor_render_chrome.inspector_lane_label_width;
const editor_panel_label_gap = editor_theme.panel_label_gap;
const editor_button_corner_radius = editor_theme.button_corner_radius;
const editor_system_scroll_pixels_per_wheel = editor_theme.system_scroll_pixels_per_wheel;
const editor_scrollbar_width = editor_theme.scrollbar_width;
const editor_scrollbar_gap = editor_theme.scrollbar_gap;
const editor_entity_card_padding_y = editor_theme.entity_card_padding_y;
const editor_entity_row_stride = editor_theme.entity_row_stride;
const editor_command_play_toggle = editor_theme.command_play_toggle;
const editor_command_step = editor_theme.command_step;
const editor_command_splitter_left = editor_theme.command_splitter_left;
const editor_command_splitter_right = editor_theme.command_splitter_right;
const editorSystemProfileScrollCount = editor_metrics.editorSystemProfileScrollCount;
const editorSystemNeedsScrollForInput = editor_metrics.editorSystemNeedsScrollForInput;
const editorSystemListClipRect = editor_metrics.editorSystemListClipRect;
const editorSystemTableContentHeight = editor_metrics.editorSystemTableContentHeight;
const editorEntityListClipRect = editor_metrics.editorEntityListClipRect;
const editorEntityNeedsScroll = editor_metrics.editorEntityNeedsScroll;
const editorEntityTableContentHeight = editor_metrics.editorEntityTableContentHeight;
const editorEntityVisibleRange = editor_metrics.editorEntityVisibleRange;
const editorEntityHandleAt = editor_metrics.editorEntityHandleAt;
const editorInspectorNeedsScroll = editor_metrics.editorInspectorNeedsScroll;
const editorInspectorScrollClipRect = editor_metrics.editorInspectorScrollClipRect;
const editorInspectorComponentContentHeight = editor_metrics.editorInspectorComponentContentHeight;
const editorInspectorComponentCardHeight = editor_metrics.editorInspectorComponentCardHeight;
const makeEditorFieldSelection = editor_input.makeEditorFieldSelection;
const editorFieldLooksLikeColor = editor_input.editorFieldLooksLikeColor;

pub const EditorCommand = enum {
    play_toggle,
    step,
};

pub const EditorUiRoute = union(enum) {
    command: EditorCommand,
    splitter: EditorSplitter,
    system_scroll: ui_layout.ScrollWheelRoute,
    entity_scroll: ui_layout.ScrollWheelRoute,
    inspector_scroll: ui_layout.ScrollWheelRoute,
    entity_select: runtime.EntityHandle,
};

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

fn decodeEditorCommand(command: []const u8) ?EditorCommand {
    if (std.mem.eql(u8, command, editor_command_play_toggle)) {
        return .play_toggle;
    }
    if (std.mem.eql(u8, command, editor_command_step)) {
        return .step;
    }
    return null;
}

const editor_entity_select_command_prefix = "scrapbot.editor.entity.select.";

fn formatEditorEntitySelectCommand(buffer: []u8, handle: runtime.EntityHandle) ?[]const u8 {
    return std.fmt.bufPrint(buffer, "{s}{d}.{d}", .{ editor_entity_select_command_prefix, handle.index, handle.generation }) catch null;
}

fn decodeEditorEntitySelect(command: []const u8) ?runtime.EntityHandle {
    if (!std.mem.startsWith(u8, command, editor_entity_select_command_prefix)) {
        return null;
    }
    var parts = std.mem.splitScalar(u8, command[editor_entity_select_command_prefix.len..], '.');
    const index_text = parts.next() orelse return null;
    const generation_text = parts.next() orelse return null;
    if (parts.next() != null) {
        return null;
    }
    return .{
        .index = std.fmt.parseInt(u32, index_text, 10) catch return null,
        .generation = std.fmt.parseInt(u32, generation_text, 10) catch return null,
    };
}

fn decodeEditorSplitter(command: []const u8) ?EditorSplitter {
    if (std.mem.eql(u8, command, editor_command_splitter_left)) {
        return .left;
    }
    if (std.mem.eql(u8, command, editor_command_splitter_right)) {
        return .right;
    }
    return null;
}

pub fn routeEditorUi(
    allocator: std.mem.Allocator,
    scene_world: ?*const runtime.World,
    system_scroll_target_y: f32,
    entity_scroll_target_y: f32,
    inspector_scroll_target_y: f32,
    input: FrameInput,
    profile_count: usize,
) EditorError!?EditorUiRoute {
    if (!input.debug_overlay_visible or
        !input.pointer.has_position or
        std.math.isNan(input.pointer.position[0]) or
        std.math.isNan(input.pointer.position[1]))
    {
        return null;
    }

    var input_world = runtime.World.init(allocator);
    defer input_world.deinit();

    try addEditorChromeControlsForRouting(&input_world, scene_world, system_scroll_target_y, entity_scroll_target_y, inspector_scroll_target_y, input, profile_count);

    const route = ui_layout.routePointer(&input_world, .{
        .position = input.pointer.position,
        .wheel_delta_y = input.pointer.wheel_delta[1],
        .pixels_per_wheel = editor_system_scroll_pixels_per_wheel,
        .primary_pressed = input.pointer.primary_pressed,
        .primary_down = input.pointer.primary_down,
        .primary_released = input.pointer.primary_released,
    }) catch |err| return mapEditorLayoutError(err);

    if (route.scroll) |scroll_route| {
        const scroll_entity = input_world.entity(scroll_route.entity) catch return error.InvalidScene;
        if (std.mem.eql(u8, scroll_entity.id, "scrapbot.editor.debug.systems.scroll")) {
            return .{ .system_scroll = scroll_route };
        }
        if (std.mem.eql(u8, scroll_entity.id, "scrapbot.editor.entities.scroll")) {
            return .{ .entity_scroll = scroll_route };
        }
        if (std.mem.eql(u8, scroll_entity.id, "scrapbot.editor.inspector.scroll")) {
            return .{ .inspector_scroll = scroll_route };
        }
        return null;
    }
    if (route.command) |command_hit| {
        if (decodeEditorSplitter(command_hit.command)) |splitter| {
            return .{ .splitter = splitter };
        }
        if (decodeEditorCommand(command_hit.command)) |command| {
            return .{ .command = command };
        }
        if (decodeEditorEntitySelect(command_hit.command)) |entity| {
            return .{ .entity_select = entity };
        }
    }
    return null;
}

pub fn routeEditorSplitterAt(allocator: std.mem.Allocator, input: FrameInput) EditorError!?EditorSplitter {
    const route = (try routeEditorUi(allocator, null, input.editor.system_scroll_y, input.editor.entity_scroll_y, input.editor.inspector_scroll_y, input, editorSystemProfileScrollCount(input))) orelse return null;
    return switch (route) {
        .splitter => |splitter| splitter,
        else => null,
    };
}

fn routeEditorCommandAt(allocator: std.mem.Allocator, input: FrameInput) EditorError!?EditorCommand {
    const route = (try routeEditorUi(allocator, null, input.editor.system_scroll_y, input.editor.entity_scroll_y, input.editor.inspector_scroll_y, input, editorSystemProfileScrollCount(input))) orelse return null;
    return switch (route) {
        .command => |command| command,
        else => null,
    };
}

fn addEditorChromeControlsForRouting(
    world: *runtime.World,
    scene_world: ?*const runtime.World,
    system_scroll_target_y: f32,
    entity_scroll_target_y: f32,
    inspector_scroll_target_y: f32,
    input: FrameInput,
    profile_count: usize,
) EditorError!void {
    const buttons = editorPlaybackButtonSpecs(input);
    for (buttons) |button| {
        try addEditorCommandButtonForRouting(world, button);
    }
    try addEditorSplitterHitTargetForRouting(world, input, .left);
    try addEditorSplitterHitTargetForRouting(world, input, .right);
    try addEditorSystemScrollForRouting(world, system_scroll_target_y, input, profile_count);
    if (scene_world) |loaded_scene_world| {
        try addEditorEntityListForRouting(world, loaded_scene_world, entity_scroll_target_y, input);
        try addEditorInspectorScrollForRouting(world, loaded_scene_world, inspector_scroll_target_y, input);
    }
}

fn addEditorCommandButtonForRouting(
    world: *runtime.World,
    spec: EditorButtonSpec,
) EditorError!void {
    const button = try world.createEntity(spec.id, spec.name);
    try world.setUiRect(button, .{
        .position = spec.rect.position(),
        .size = spec.rect.size3(),
        .color = .{ 0.0, 0.0, 0.0 },
        .corner_radius = editor_button_corner_radius,
    });
    try world.setUiButton(button);
    try world.setUiCommand(button, .{ .command = spec.command });
}

fn addEditorSplitterHitTargetForRouting(
    world: *runtime.World,
    input: FrameInput,
    splitter: EditorSplitter,
) EditorError!void {
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
    const command = switch (splitter) {
        .none => return,
        .left => editor_command_splitter_left,
        .right => editor_command_splitter_right,
    };
    const hit_rect = editorSplitterHitRect(input, splitter) orelse return;
    const hit = try world.createEntity(id, name);
    try world.setUiHitArea(hit, .{
        .position = hit_rect.position(),
        .size = hit_rect.size3(),
    });
    try world.setUiButton(hit);
    try world.setUiCommand(hit, .{ .command = command });
}

fn addEditorSystemScrollForRouting(
    world: *runtime.World,
    system_scroll_target_y: f32,
    input: FrameInput,
    profile_count: usize,
) EditorError!void {
    if (!editorSystemNeedsScrollForInput(input, profile_count)) {
        return;
    }

    const list_clip = editorSystemListClipRect(input);
    const hit_width = list_clip.size[0] + editor_scrollbar_gap + editor_scrollbar_width;
    const scroll = try world.createEntity("scrapbot.editor.debug.systems.scroll", "Editor Debug Systems Scroll View");
    try world.setUiScrollView(scroll, .{
        .position = list_clip.position,
        .size = .{ hit_width, list_clip.size[1], 0.0 },
        .content_offset = .{ 0.0, system_scroll_target_y, 0.0 },
    });

    const content = try world.createEntity("scrapbot.editor.debug.systems.scroll.content", "Editor Debug Systems Scroll Content");
    try world.setUiSpacer(content, .{
        .size = .{
            list_clip.size[0],
            editorSystemTableContentHeight(profile_count),
            0.0,
        },
    });
    try world.setUiLayoutItem(content, .{
        .parent = "scrapbot.editor.debug.systems.scroll",
        .order = 0,
    });
}

fn addEditorEntityListForRouting(
    world: *runtime.World,
    scene_world: *const runtime.World,
    entity_scroll_target_y: f32,
    input: FrameInput,
) EditorError!void {
    if (scene_world.entityCount() == 0) {
        return;
    }

    const list_clip = editorEntityListClipRect(scene_world, input);
    const hit_width = list_clip.size[0] + if (editorEntityNeedsScroll(scene_world, input)) editor_scrollbar_gap + editor_scrollbar_width else 0.0;
    const scroll = try world.createEntity("scrapbot.editor.entities.scroll", "Editor Entities Scroll View");
    try world.setUiScrollView(scroll, .{
        .position = list_clip.position,
        .size = .{ hit_width, list_clip.size[1], 0.0 },
        .content_offset = .{ 0.0, entity_scroll_target_y, 0.0 },
    });

    const content = try world.createEntity("scrapbot.editor.entities.scroll.content", "Editor Entities Scroll Content");
    try world.setUiSpacer(content, .{
        .size = .{
            list_clip.size[0],
            editorEntityTableContentHeight(scene_world.entityCount()),
            0.0,
        },
    });
    try world.setUiLayoutItem(content, .{
        .parent = "scrapbot.editor.entities.scroll",
        .order = 0,
    });

    var route_input = input;
    route_input.editor.entity_scroll_y = entity_scroll_target_y;
    const range = editorEntityVisibleRange(scene_world, route_input);
    for (range.start..range.end) |entity_index| {
        const handle = editorEntityHandleAt(scene_world, entity_index) orelse continue;
        const id = std.fmt.allocPrint(world.allocator, "scrapbot.editor.entities.row.{d}.hit", .{entity_index}) catch return error.OutOfMemory;
        defer world.allocator.free(id);
        var command_buffer: [96]u8 = undefined;
        const command = formatEditorEntitySelectCommand(&command_buffer, handle) orelse return error.InvalidScene;
        const hit = try world.createEntity(id, "Editor Entity Row Hit Area");
        try world.setUiHitArea(hit, .{
            .position = .{
                0.0,
                editor_entity_card_padding_y + @as(f32, @floatFromInt(entity_index)) * editor_entity_row_stride - 8.0,
                0.0,
            },
            .size = .{ list_clip.size[0], editor_entity_row_stride, 0.0 },
        });
        try world.setUiButton(hit);
        try world.setUiCommand(hit, .{ .command = command });
        try world.setUiLayoutItem(hit, .{
            .parent = "scrapbot.editor.entities.scroll",
            .order = @intCast(entity_index + 1),
        });
    }
}

fn addEditorInspectorScrollForRouting(
    world: *runtime.World,
    scene_world: *const runtime.World,
    inspector_scroll_target_y: f32,
    input: FrameInput,
) EditorError!void {
    if (!editorInspectorNeedsScroll(scene_world, input)) {
        return;
    }

    const clip = editorInspectorScrollClipRect(input);
    const scroll = try world.createEntity("scrapbot.editor.inspector.scroll", "Editor Inspector Scroll View");
    try world.setUiScrollView(scroll, .{
        .position = clip.position,
        .size = clip.size,
        .content_offset = .{ 0.0, inspector_scroll_target_y, 0.0 },
    });

    const content = try world.createEntity("scrapbot.editor.inspector.scroll.content", "Editor Inspector Scroll Content");
    try world.setUiSpacer(content, .{
        .size = .{
            clip.size[0],
            editorInspectorComponentContentHeight(scene_world, input.editor.selected_entity),
            0.0,
        },
    });
    try world.setUiLayoutItem(content, .{
        .parent = "scrapbot.editor.inspector.scroll",
        .order = 0,
    });
}

pub fn pickEditorInspectorProperty(world: *const runtime.World, input: FrameInput) EditorError!?EditorFieldSelection {
    const selected = input.editor.selected_entity orelse return null;
    _ = world.entity(selected) catch return null;
    const clip = editorInspectorScrollClipRect(input);
    if (!pointInsideScreenRect(input.pointer.position, .{ clip.position[0], clip.position[1] }, .{ clip.size[0], clip.size[1] })) {
        return null;
    }

    const card_width = @max(clip.size[0], 1.0);
    const field_layout = editorInspectorFieldLayout(card_width);
    var content_y: f32 = -input.editor.inspector_scroll_y;
    var component_index: usize = 0;
    var components = world.entityComponents(selected) catch return null;
    while (components.next()) |component_id| {
        if (component_index > 0) {
            content_y += editor_inspector_card_gap;
            content_y += editor_inspector_separator_height;
            content_y += editor_inspector_card_gap;
        }
        const card_y = content_y;
        const field_count = world.componentFieldCount(component_id);
        const field_start_y = editor_inspector_card_padding_y + editorTextHeight(editor_inspector_text_size) + editor_panel_label_gap;
        for (0..field_count) |field_index| {
            const field_name = world.componentFieldNameAt(component_id, field_index) orelse continue;
            const field_y = clip.position[1] + card_y + field_start_y + @as(f32, @floatFromInt(field_index)) * editor_inspector_field_row_stride;
            const row_rect = ScreenRect{
                .x = clip.position[0],
                .y = field_y + editor_inspector_field_control_offset_y - editor_inspector_input_cell_padding,
                .width = card_width,
                .height = editor_inspector_field_row_height,
            };
            if (row_rect.contains(input.pointer.position)) {
                const value = world.getComponentFieldValue(selected, component_id, field_name) catch return null;
                return try makeEditorFieldSelection(
                    selected,
                    component_id,
                    field_name,
                    pickEditorPropertyVec3Lane(
                        value,
                        field_name,
                        input.pointer.position[0],
                        clip.position[0] + field_layout.value_x + editor_inspector_input_cell_padding,
                        @max(field_layout.value_width - editor_inspector_input_cell_padding * 2.0, 1.0),
                    ),
                );
            }
        }
        content_y += editorInspectorComponentCardHeight(world, component_id);
        component_index += 1;
    }

    return null;
}

fn pickEditorPropertyVec3Lane(value: runtime.ComponentValue, field_name: []const u8, pointer_x: f32, value_screen_x: f32, value_width: f32) u2 {
    return switch (value) {
        .vec3 => blk: {
            const is_color = editorFieldLooksLikeColor(field_name);
            const child_count: f32 = if (is_color) 7.0 else 6.0;
            const spacing_total = @max(child_count - 1.0, 0.0) * editor_inspector_input_gap;
            const swatch_total_width = if (is_color) editor_inspector_swatch_size else 0.0;
            const lane_width = @max((value_width - swatch_total_width - editor_inspector_lane_label_width * 3.0 - spacing_total) / 3.0, 1.0);
            var x = value_screen_x;
            if (is_color) {
                if (pointer_x < x + editor_inspector_swatch_size + editor_inspector_input_gap) {
                    break :blk 0;
                }
                x += editor_inspector_swatch_size + editor_inspector_input_gap;
            }
            for (0..3) |lane_index| {
                const slot_end = x + editor_inspector_lane_label_width + editor_inspector_input_gap + lane_width;
                if (pointer_x < slot_end or lane_index == 2) {
                    break :blk @intCast(lane_index);
                }
                x = slot_end + editor_inspector_input_gap;
            }
            break :blk 2;
        },
        else => 0,
    };
}

pub fn hitEditorChrome(input: FrameInput) bool {
    if (!input.debug_overlay_visible) {
        return false;
    }
    return !editorGameViewport(input).contains(input.pointer.position);
}

pub fn routeEditorScrollWheel(
    allocator: std.mem.Allocator,
    world: *const runtime.World,
    state: *const EditorState,
    input: FrameInput,
    profile_count: usize,
    wheel_delta_y: f32,
) EditorError!?EditorUiRoute {
    var route_input = input;
    route_input.pointer.wheel_delta[1] = wheel_delta_y;
    const route = (try routeEditorUi(allocator, world, state.system_scroll_target_y, state.entity_scroll_target_y, state.inspector_scroll_target_y, route_input, profile_count)) orelse return null;
    return switch (route) {
        .system_scroll, .entity_scroll, .inspector_scroll => route,
        else => null,
    };
}

fn mapEditorLayoutError(err: anyerror) EditorError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.DuplicateEntityId => error.DuplicateEntityId,
        error.InvalidEntity => error.InvalidEntity,
        error.UnknownComponent => error.UnknownComponent,
        error.UnknownField => error.UnknownField,
        error.InvalidFieldType => error.InvalidFieldType,
        else => error.InvalidScene,
    };
}

pub fn editorCursorKind(allocator: std.mem.Allocator, input: FrameInput) EditorError!EditorCursorKind {
    if (!input.debug_overlay_visible) {
        return .default;
    }
    if (input.editor.dragging_splitter != .none) {
        return .resize_ew;
    }
    if ((try routeEditorSplitterAt(allocator, input)) != null) {
        return .resize_ew;
    }
    return .default;
}
