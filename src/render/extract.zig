const std = @import("std");
const runtime = @import("../runtime.zig");

pub const Error = error{
    OutOfMemory,
    InvalidScene,
};

pub fn extractMeshInto(
    world: *runtime.World,
    render_index: usize,
    mesh: runtime.RenderableMesh,
) Error!runtime.RenderableMesh {
    var entity_id_buffer: [64]u8 = undefined;
    const entity_id = std.fmt.bufPrint(&entity_id_buffer, "scrapbot.render.extract.mesh.{d}", .{render_index}) catch return Error.InvalidScene;
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

    const stored = world.entity(entity) catch return Error.InvalidScene;
    return .{
        .entity = entity,
        .id = stored.id,
        .name = stored.name,
        .position = mesh.position,
        .rotation = mesh.rotation,
        .scale = mesh.scale,
        .primitive = mesh.primitive,
        .segments = mesh.segments,
        .rings = mesh.rings,
        .base_color = mesh.base_color,
        .spin = mesh.spin,
        .casts_shadow = mesh.casts_shadow,
        .receives_shadow = mesh.receives_shadow,
    };
}

pub fn extractSceneUiInto(render_world: *runtime.World, scene_world: *const runtime.World) Error!void {
    for (0..scene_world.entityCount()) |index| {
        const source = runtime.EntityHandle{ .index = @intCast(index) };
        const stored = scene_world.entity(source) catch return Error.InvalidScene;
        if (!hasExtractableUiComponent(scene_world, source)) {
            continue;
        }

        const target = render_world.findEntityById(stored.id) orelse
            (render_world.createEntity(stored.id, stored.name) catch |err| return mapWorldError(err));
        try copyComponent(scene_world, render_world, source, target, runtime.ui_canvas_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_rect_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_border_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_text_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_button_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_hit_area_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_command_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_scroll_view_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_vgroup_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_hgroup_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_table_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_stack_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_layout_item_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_spacer_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_text_block_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_toggle_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_progress_bar_component_id);
        try copyComponent(scene_world, render_world, source, target, runtime.ui_separator_component_id);
    }
}

pub fn extractRendererInto(render_world: *runtime.World, scene_world: *const runtime.World) Error!void {
    var cursor: usize = 0;
    const query = [_][]const u8{runtime.renderer_component_id};
    const source = scene_world.queryNext(&query, &cursor) orelse return;
    if (scene_world.queryNext(&query, &cursor) != null) {
        return Error.InvalidScene;
    }
    const stored = scene_world.entity(source) catch return Error.InvalidScene;
    const target = render_world.findEntityById(stored.id) orelse
        (render_world.createEntity(stored.id, stored.name) catch |err| return mapWorldError(err));
    try copyComponent(scene_world, render_world, source, target, runtime.renderer_component_id);
}

fn hasExtractableUiComponent(world: *const runtime.World, entity: runtime.EntityHandle) bool {
    return (world.hasComponent(entity, runtime.ui_canvas_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_rect_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_border_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_text_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_button_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_hit_area_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_command_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_scroll_view_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_vgroup_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_hgroup_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_table_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_stack_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_layout_item_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_spacer_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_text_block_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_toggle_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_progress_bar_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_separator_component_id) catch false);
}

fn copyComponent(
    source_world: *const runtime.World,
    target_world: *runtime.World,
    source: runtime.EntityHandle,
    target: runtime.EntityHandle,
    component_id: []const u8,
) Error!void {
    if (!(source_world.hasComponent(source, component_id) catch |err| return mapWorldError(err))) {
        return;
    }

    var fields: std.ArrayList(runtime.ComponentFieldValue) = .empty;
    const allocator = target_world.allocator;
    defer fields.deinit(allocator);

    const field_count = source_world.componentFieldCount(component_id);
    fields.ensureTotalCapacity(allocator, field_count) catch return Error.OutOfMemory;
    for (0..field_count) |field_index| {
        const field_name = source_world.componentFieldNameAt(component_id, field_index) orelse return Error.InvalidScene;
        const value = source_world.getComponentFieldValue(source, component_id, field_name) catch |err| return mapWorldError(err);
        fields.appendAssumeCapacity(.{
            .name = field_name,
            .value = value,
        });
    }

    target_world.setComponent(target, component_id, fields.items) catch |err| return mapWorldError(err);
}

fn mapWorldError(err: anyerror) Error {
    return switch (err) {
        error.OutOfMemory => Error.OutOfMemory,
        else => Error.InvalidScene,
    };
}
