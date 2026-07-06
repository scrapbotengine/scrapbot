const std = @import("std");
const runtime = @import("../runtime.zig");
const render_math = @import("../render/math.zig");
const editor_state = @import("state.zig");

const addVec3 = render_math.addVec3;

pub const axis_length: f32 = 1.25;
pub const axis_thickness: f32 = 0.035;
pub const pick_radius_px: f32 = 18.0;

pub const Error = error{
    OutOfMemory,
    InvalidScene,
};

pub const Palette = struct {
    danger: [3]f32,
    success: [3]f32,
    primary: [3]f32,
    accent_soft: [3]f32,
};

pub fn extractTranslateInto(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    scene_world: *const runtime.World,
    selected_entity: ?runtime.EntityHandle,
    dragging_axis: editor_state.EditorAxis,
    palette: Palette,
) Error!void {
    const selected = selected_entity orelse return;
    _ = scene_world.entity(selected) catch return;
    const selected_transform = (scene_world.getTransform(selected) catch return) orelse return;
    const axes = [_]struct {
        id: []const u8,
        axis: editor_state.EditorAxis,
        position_offset: [3]f32,
        scale: [3]f32,
        color: [3]f32,
        active_color: [3]f32,
    }{
        .{
            .id = "x",
            .axis = .x,
            .position_offset = .{ axis_length * 0.5, 0.0, 0.0 },
            .scale = .{ axis_length, axis_thickness, axis_thickness },
            .color = palette.danger,
            .active_color = .{ 0.94, 0.42, 0.42 },
        },
        .{
            .id = "y",
            .axis = .y,
            .position_offset = .{ 0.0, axis_length * 0.5, 0.0 },
            .scale = .{ axis_thickness, axis_length, axis_thickness },
            .color = palette.success,
            .active_color = .{ 0.176, 0.667, 0.443 },
        },
        .{
            .id = "z",
            .axis = .z,
            .position_offset = .{ 0.0, 0.0, axis_length * 0.5 },
            .scale = .{ axis_thickness, axis_thickness, axis_length },
            .color = palette.primary,
            .active_color = palette.accent_soft,
        },
    };

    for (axes) |entry| {
        const entity_id = std.fmt.allocPrint(allocator, "scrapbot.editor.gizmo.{s}", .{entry.id}) catch return Error.OutOfMemory;
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
            .base_color = if (dragging_axis == entry.axis) entry.active_color else entry.color,
        }) catch |err| return mapWorldError(err);
    }
}

fn mapWorldError(err: anyerror) Error {
    return switch (err) {
        error.OutOfMemory => Error.OutOfMemory,
        else => Error.InvalidScene,
    };
}
