const std = @import("std");
const state = @import("state.zig");

pub const top_bar_height: f32 = 60.0;
pub const bottom_bar_height: f32 = 64.0;
pub const left_sidebar_target_width: f32 = 456.0;
pub const left_sidebar_min_width: f32 = 280.0;
pub const right_sidebar_target_width: f32 = 560.0;
pub const right_sidebar_min_width: f32 = 360.0;
pub const min_game_viewport_width: f32 = 320.0;
pub const splitter_width: f32 = 2.0;
pub const splitter_hit_width: f32 = 12.0;
pub const panel_padding_x: f32 = 20.0;
pub const control_button_width: f32 = 104.0;
pub const control_button_height: f32 = 36.0;
pub const control_button_gap: f32 = 16.0;

const default_output_width: f32 = 640.0;
const default_output_height: f32 = 480.0;

pub const ScreenRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn position(self: ScreenRect) [3]f32 {
        return .{ self.x, self.y, 0.0 };
    }

    pub fn size3(self: ScreenRect) [3]f32 {
        return .{ self.width, self.height, 0.0 };
    }

    pub fn contains(self: ScreenRect, point: [2]f32) bool {
        return pointInsideScreenRect(point, .{ self.x, self.y }, .{ self.width, self.height });
    }
};

pub fn scaleScreenRect(rect: ScreenRect, scale: f32) ScreenRect {
    return .{
        .x = rect.x * scale,
        .y = rect.y * scale,
        .width = rect.width * scale,
        .height = rect.height * scale,
    };
}

pub fn pointInsideScreenRect(position: [2]f32, origin: [2]f32, size: [2]f32) bool {
    return position[0] >= origin[0] and position[1] >= origin[1] and position[0] <= origin[0] + size[0] and position[1] <= origin[1] + size[1];
}

pub fn viewportWidth(input: anytype) f32 {
    return if (input.viewport_width > 0.0) input.viewport_width else default_output_width;
}

pub fn viewportHeight(input: anytype) f32 {
    return if (input.viewport_height > 0.0) input.viewport_height else default_output_height;
}

pub const SideWidths = struct {
    left: f32,
    right: f32,
};

pub const BodyLayout = struct {
    body: ScreenRect,
    left: ScreenRect,
    left_splitter: ScreenRect,
    game: ScreenRect,
    right_splitter: ScreenRect,
    right: ScreenRect,
};

pub fn defaultSideWidths(window_width: f32) SideWidths {
    if (window_width <= 0.0) {
        return .{ .left = left_sidebar_target_width, .right = right_sidebar_target_width };
    }
    var left = std.math.clamp(window_width * 0.25, left_sidebar_min_width, left_sidebar_target_width);
    var right = std.math.clamp(window_width * 0.32, right_sidebar_min_width, right_sidebar_target_width);
    const max_side_total = @max(window_width - min_game_viewport_width, 1.0);
    if (left + right > max_side_total) {
        const scale = max_side_total / (left + right);
        left = @max(left * scale, 1.0);
        right = @max(right * scale, 1.0);
    }
    return .{ .left = left, .right = right };
}

pub fn sideWidths(input: anytype) SideWidths {
    const window_width = viewportWidth(input);
    var widths = defaultSideWidths(window_width);
    if (@hasField(@TypeOf(input), "editor")) {
        if (input.editor.left_sidebar_width > 0.0) {
            widths.left = input.editor.left_sidebar_width;
        }
        if (input.editor.right_sidebar_width > 0.0) {
            widths.right = input.editor.right_sidebar_width;
        }
    }
    return clampSideWidths(widths, window_width);
}

pub fn clampSideWidths(widths: SideWidths, window_width: f32) SideWidths {
    const max_side_total = @max(window_width - min_game_viewport_width - splitter_width * 2.0, 1.0);
    var left = std.math.clamp(widths.left, @min(left_sidebar_min_width, max_side_total), max_side_total);
    var right = std.math.clamp(widths.right, @min(right_sidebar_min_width, max_side_total), max_side_total);
    if (left + right > max_side_total) {
        const scale = max_side_total / (left + right);
        left = @max(left * scale, 1.0);
        right = @max(right * scale, 1.0);
    }
    return .{ .left = left, .right = right };
}

pub fn topBarRect(input: anytype) ScreenRect {
    const window_width = viewportWidth(input);
    return .{
        .x = 0.0,
        .y = 0.0,
        .width = @max(window_width, 1.0),
        .height = top_bar_height,
    };
}

pub fn bottomBarRect(input: anytype) ScreenRect {
    const window_width = viewportWidth(input);
    const window_height = viewportHeight(input);
    return .{
        .x = 0.0,
        .y = @max(window_height - bottom_bar_height, top_bar_height),
        .width = @max(window_width, 1.0),
        .height = bottom_bar_height,
    };
}

pub fn bodyRect(input: anytype) ScreenRect {
    const window_width = viewportWidth(input);
    const window_height = viewportHeight(input);
    return .{
        .x = 0.0,
        .y = top_bar_height,
        .width = @max(window_width, 1.0),
        .height = @max(window_height - top_bar_height - bottom_bar_height, 1.0),
    };
}

pub fn bodyLayout(input: anytype) BodyLayout {
    const body = bodyRect(input);
    const widths = sideWidths(input);
    const left = ScreenRect{
        .x = body.x,
        .y = body.y,
        .width = widths.left,
        .height = body.height,
    };
    const left_splitter = ScreenRect{
        .x = left.x + left.width,
        .y = body.y,
        .width = splitter_width,
        .height = body.height,
    };
    const right = ScreenRect{
        .x = body.x + body.width - widths.right,
        .y = body.y,
        .width = widths.right,
        .height = body.height,
    };
    const right_splitter = ScreenRect{
        .x = right.x - splitter_width,
        .y = body.y,
        .width = splitter_width,
        .height = body.height,
    };
    const game = ScreenRect{
        .x = left_splitter.x + left_splitter.width,
        .y = body.y,
        .width = @max(right_splitter.x - (left_splitter.x + left_splitter.width), 1.0),
        .height = body.height,
    };
    return .{
        .body = body,
        .left = left,
        .left_splitter = left_splitter,
        .game = game,
        .right_splitter = right_splitter,
        .right = right,
    };
}

pub fn leftSidebarRect(input: anytype) ScreenRect {
    return bodyLayout(input).left;
}

pub fn rightSidebarRect(input: anytype) ScreenRect {
    return bodyLayout(input).right;
}

pub fn splitterRect(input: anytype, splitter: state.EditorSplitter) ?ScreenRect {
    const layout = bodyLayout(input);
    return switch (splitter) {
        .none => null,
        .left => layout.left_splitter,
        .right => layout.right_splitter,
    };
}

pub fn splitterHitRect(input: anytype, splitter: state.EditorSplitter) ?ScreenRect {
    const visual = splitterRect(input, splitter) orelse return null;
    const extra_width = @max(splitter_hit_width - visual.width, 0.0);
    return .{
        .x = visual.x - extra_width * 0.5,
        .y = visual.y,
        .width = visual.width + extra_width,
        .height = visual.height,
    };
}

pub fn gameViewport(input: anytype) ScreenRect {
    const window_width = viewportWidth(input);
    const window_height = viewportHeight(input);
    if (!input.debug_overlay_visible) {
        return .{
            .x = 0.0,
            .y = 0.0,
            .width = @max(window_width, 1.0),
            .height = @max(window_height, 1.0),
        };
    }

    return bodyLayout(input).game;
}

pub fn gameViewportBounds(input: anytype) state.EditorViewportBounds {
    const viewport = gameViewport(input);
    return .{
        .x = viewport.x,
        .y = viewport.y,
        .width = viewport.width,
        .height = viewport.height,
    };
}

pub fn playButtonRect(input: anytype) ScreenRect {
    const top = topBarRect(input);
    return .{
        .x = @max(top.width - panel_padding_x - control_button_width * 2.0 - control_button_gap, panel_padding_x),
        .y = top.y + (top.height - control_button_height) * 0.5,
        .width = control_button_width,
        .height = control_button_height,
    };
}

pub fn stepButtonRect(input: anytype) ScreenRect {
    const play = playButtonRect(input);
    return .{
        .x = play.x + play.width + control_button_gap,
        .y = play.y,
        .width = control_button_width,
        .height = control_button_height,
    };
}
