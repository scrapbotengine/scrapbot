const std = @import("std");

const runtime = @import("../runtime.zig");
const layout = @import("layout.zig");

const PointerCapture = layout.PointerCapture;
const LayoutCache = layout.LayoutCache;
const applyScrollWheelAt = layout.applyScrollWheelAt;
const commandAt = layout.commandAt;
const resolve = layout.resolve;
const resolveWithCache = layout.resolveWithCache;
const resolvedItemRect = layout.resolvedItemRect;
const resolvedItemSize = layout.resolvedItemSize;
const resolvedItemSizeWithCache = layout.resolvedItemSizeWithCache;
const routePointer = layout.routePointer;
const routeScrollWheelAt = layout.routeScrollWheelAt;

test "scroll wheel routing targets the scroll view under the pointer" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const scroll = try world.createEntity("scroll", "Scroll");
    try world.setUiScrollView(scroll, .{
        .position = .{ 10.0, 20.0, 0.0 },
        .size = .{ 120.0, 40.0, 0.0 },
        .content_offset = .{ 0.0, 0.0, 0.0 },
    });

    const content = try world.createEntity("content", "Content");
    try world.setUiSpacer(content, .{ .size = .{ 120.0, 100.0, 0.0 } });
    try world.setUiLayoutItem(content, .{ .parent = "scroll", .order = 0 });

    const missed = try routeScrollWheelAt(&world, .{ 200.0, 200.0 }, -1.0, 24.0);
    try std.testing.expect(missed == null);

    const static_scroll = try world.createEntity("static-scroll", "Static Scroll");
    try world.setUiScrollView(static_scroll, .{
        .position = .{ 200.0, 20.0, 0.0 },
        .size = .{ 120.0, 100.0, 0.0 },
        .content_offset = .{ 0.0, 0.0, 0.0 },
    });
    const static_content = try world.createEntity("static-content", "Static Content");
    try world.setUiSpacer(static_content, .{ .size = .{ 120.0, 60.0, 0.0 } });
    try world.setUiLayoutItem(static_content, .{ .parent = "static-scroll", .order = 0 });
    const no_overflow = try routeScrollWheelAt(&world, .{ 210.0, 30.0 }, -1.0, 24.0);
    try std.testing.expect(no_overflow == null);

    const route = (try applyScrollWheelAt(&world, .{ 20.0, 30.0 }, -2.0, 24.0)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(scroll.index, route.entity.index);
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), route.next_offset[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 60.0), route.max_offset_y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), (try world.getVec3(scroll, runtime.ui_scroll_view_component_id, "content_offset"))[1], 0.001);
}

test "command routing targets the topmost command button under the pointer" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const toolbar = try world.createEntity("toolbar", "Toolbar");
    try world.setUiStack(toolbar, .{
        .position = .{ 100.0, 20.0, 0.0 },
        .spacing = 0.0,
        .direction = "horizontal",
        .padding = .{ 0.0, 0.0, 0.0 },
    });

    const first = try world.createEntity("first", "First");
    try world.setUiRect(first, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = .{ 80.0, 40.0, 0.0 },
        .color = .{ 0.0, 0.0, 0.0 },
    });
    try world.setUiButton(first);
    try world.setUiCommand(first, .{ .command = "first_command" });
    try world.setUiLayoutItem(first, .{ .parent = "toolbar", .order = 0 });

    const second = try world.createEntity("second", "Second");
    try world.setUiRect(second, .{
        .position = .{ -80.0, 0.0, 0.0 },
        .size = .{ 80.0, 40.0, 0.0 },
        .color = .{ 0.0, 0.0, 0.0 },
    });
    try world.setUiButton(second);
    try world.setUiCommand(second, .{ .command = "second_command" });
    try world.setUiLayoutItem(second, .{ .parent = "toolbar", .order = 1 });

    try std.testing.expect((try commandAt(&world, .{ 12.0, 12.0 })) == null);

    const hit = (try commandAt(&world, .{ 120.0, 30.0 })) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(second.index, hit.entity.index);
    try std.testing.expectEqualStrings("second", hit.source);
    try std.testing.expectEqualStrings("second_command", hit.command);
}

test "command routing can use non-rendering hit areas" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const visual = try world.createEntity("thin-control", "Thin Control");
    try world.setUiRect(visual, .{
        .position = .{ 100.0, 20.0, 0.0 },
        .size = .{ 2.0, 80.0, 0.0 },
        .color = .{ 0.0, 0.0, 0.0 },
    });
    try world.setUiHitArea(visual, .{
        .position = .{ 95.0, 20.0, 0.0 },
        .size = .{ 12.0, 80.0, 0.0 },
    });
    try world.setUiButton(visual);
    try world.setUiCommand(visual, .{ .command = "drag.thin-control" });

    try std.testing.expect((try commandAt(&world, .{ 94.0, 30.0 })) == null);
    const hit = (try commandAt(&world, .{ 105.0, 30.0 })) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(visual.index, hit.entity.index);
    try std.testing.expectEqualStrings("thin-control", hit.source);
    try std.testing.expectEqualStrings("drag.thin-control", hit.command);
    try std.testing.expectApproxEqAbs(@as(f32, 95.0), hit.rect.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), hit.rect.size[0], 0.001);
}

test "command routing preserves order across rects and hit areas" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const hit_target = try world.createEntity("wide-hit", "Wide Hit");
    try world.setUiHitArea(hit_target, .{
        .position = .{ 10.0, 10.0, 0.0 },
        .size = .{ 100.0, 40.0, 0.0 },
    });
    try world.setUiButton(hit_target);
    try world.setUiCommand(hit_target, .{ .command = "wide_hit" });

    const visual_button = try world.createEntity("visual", "Visual");
    try world.setUiRect(visual_button, .{
        .position = .{ 10.0, 10.0, 0.0 },
        .size = .{ 100.0, 40.0, 0.0 },
        .color = .{ 0.0, 0.0, 0.0 },
    });
    try world.setUiButton(visual_button);
    try world.setUiCommand(visual_button, .{ .command = "visual_button" });

    const hit = (try commandAt(&world, .{ 20.0, 20.0 })) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(visual_button.index, hit.entity.index);
    try std.testing.expectEqualStrings("visual_button", hit.command);
}

test "pointer routing reports command capture" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const button = try world.createEntity("button", "Button");
    try world.setUiRect(button, .{
        .position = .{ 10.0, 10.0, 0.0 },
        .size = .{ 100.0, 40.0, 0.0 },
        .color = .{ 0.0, 0.0, 0.0 },
    });
    try world.setUiButton(button);
    try world.setUiCommand(button, .{ .command = "button.press" });

    const route = try routePointer(&world, .{
        .position = .{ 20.0, 20.0 },
        .primary_pressed = true,
    });
    try std.testing.expect(route.command != null);
    try std.testing.expect(route.scroll == null);
    try std.testing.expectEqual(PointerCapture.command, route.capture);
    try std.testing.expectEqualStrings("button.press", route.command.?.command);
}

test "pointer routing gives scroll wheel capture precedence" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const scroll = try world.createEntity("scroll", "Scroll");
    try world.setUiScrollView(scroll, .{
        .position = .{ 10.0, 10.0, 0.0 },
        .size = .{ 100.0, 40.0, 0.0 },
        .content_offset = .{ 0.0, 0.0, 0.0 },
    });
    const content = try world.createEntity("content", "Content");
    try world.setUiSpacer(content, .{ .size = .{ 100.0, 120.0, 0.0 } });
    try world.setUiLayoutItem(content, .{ .parent = "scroll", .order = 0 });

    const button = try world.createEntity("button", "Button");
    try world.setUiRect(button, .{
        .position = .{ 10.0, 10.0, 0.0 },
        .size = .{ 100.0, 40.0, 0.0 },
        .color = .{ 0.0, 0.0, 0.0 },
    });
    try world.setUiButton(button);
    try world.setUiCommand(button, .{ .command = "button.press" });

    const route = try routePointer(&world, .{
        .position = .{ 20.0, 20.0 },
        .wheel_delta_y = -1.0,
        .pixels_per_wheel = 24.0,
        .primary_pressed = true,
    });
    try std.testing.expect(route.command != null);
    try std.testing.expect(route.scroll != null);
    try std.testing.expectEqual(PointerCapture.scroll, route.capture);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), route.scroll.?.next_offset[1], 0.001);
}

test "hgroup distributes grow space across horizontal children" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const group = try world.createEntity("body", "Body HGroup");
    try world.setUiHGroup(group, .{
        .position = .{ 10.0, 20.0, 0.0 },
        .size = .{ 500.0, 100.0, 0.0 },
        .spacing = 2.0,
        .padding = .{ 4.0, 6.0, 0.0 },
    });

    const left = try world.createEntity("left", "Left");
    try world.setUiSpacer(left, .{ .size = .{ 120.0, 20.0, 0.0 } });
    try world.setUiLayoutItem(left, .{ .parent = "body", .order = 0, .@"align" = "fill" });

    const center = try world.createEntity("center", "Center");
    try world.setUiSpacer(center, .{ .size = .{ 0.0, 0.0, 0.0 } });
    try world.setUiLayoutItem(center, .{
        .parent = "body",
        .order = 1,
        .min_size = .{ 100.0, 10.0, 0.0 },
        .grow = 1.0,
        .@"align" = "fill",
    });

    const right = try world.createEntity("right", "Right");
    try world.setUiSpacer(right, .{ .size = .{ 80.0, 30.0, 0.0 } });
    try world.setUiLayoutItem(right, .{ .parent = "body", .order = 2, .@"align" = "center" });

    const left_rect = try resolvedItemRect(&world, left);
    try std.testing.expectApproxEqAbs(@as(f32, 14.0), left_rect.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 26.0), left_rect.position[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 120.0), left_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 88.0), left_rect.size[1], 0.001);

    const center_rect = try resolvedItemRect(&world, center);
    try std.testing.expectApproxEqAbs(@as(f32, 136.0), center_rect.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 288.0), center_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 88.0), center_rect.size[1], 0.001);

    const right_rect = try resolvedItemRect(&world, right);
    try std.testing.expectApproxEqAbs(@as(f32, 426.0), right_rect.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 55.0), right_rect.position[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 80.0), right_rect.size[0], 0.001);
}

test "hgroup honors preferred max grow and shrink sizing" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const group = try world.createEntity("row", "Row");
    try world.setUiHGroup(group, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = .{ 968.0, 28.0, 0.0 },
        .spacing = 8.0,
    });

    const label = try world.createEntity("label", "Label");
    try world.setUiSpacer(label, .{ .size = .{ 0.0, 28.0, 0.0 } });
    try world.setUiLayoutItem(label, .{
        .parent = "row",
        .order = 0,
        .min_size = .{ 180.0, 28.0, 0.0 },
        .preferred_size = .{ 180.0, 28.0, 0.0 },
        .max_size = .{ 360.0, 0.0, 0.0 },
        .grow = 1.0,
        .@"align" = "fill",
    });

    const value = try world.createEntity("value", "Value");
    try world.setUiSpacer(value, .{ .size = .{ 0.0, 28.0, 0.0 } });
    try world.setUiLayoutItem(value, .{
        .parent = "row",
        .order = 1,
        .min_size = .{ 140.0, 28.0, 0.0 },
        .preferred_size = .{ 340.0, 28.0, 0.0 },
        .grow = 1.0,
        .shrink = 1.0,
        .@"align" = "fill",
    });

    const label_rect = try resolvedItemRect(&world, label);
    const value_rect = try resolvedItemRect(&world, value);
    try std.testing.expectApproxEqAbs(@as(f32, 360.0), label_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 600.0), value_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 368.0), value_rect.position[0], 0.001);

    try world.setVec3(group, runtime.ui_hgroup_component_id, "size", .{ 328.0, 28.0, 0.0 });
    const narrow_label_rect = try resolvedItemRect(&world, label);
    const narrow_value_rect = try resolvedItemRect(&world, value);
    try std.testing.expectApproxEqAbs(@as(f32, 180.0), narrow_label_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 140.0), narrow_value_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 188.0), narrow_value_rect.position[0], 0.001);
}

test "vgroup distributes vertical grow space and cross-axis fill" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const group = try world.createEntity("column", "Column");
    try world.setUiVGroup(group, .{
        .position = .{ 10.0, 20.0, 0.0 },
        .size = .{ 120.0, 300.0, 0.0 },
        .spacing = 2.0,
        .padding = .{ 6.0, 8.0, 0.0 },
    });

    const top = try world.createEntity("top", "Top");
    try world.setUiSpacer(top, .{ .size = .{ 30.0, 40.0, 0.0 } });
    try world.setUiLayoutItem(top, .{ .parent = "column", .order = 0, .@"align" = "fill" });

    const middle = try world.createEntity("middle", "Middle");
    try world.setUiSpacer(middle, .{ .size = .{ 20.0, 0.0, 0.0 } });
    try world.setUiLayoutItem(middle, .{
        .parent = "column",
        .order = 1,
        .min_size = .{ 20.0, 50.0, 0.0 },
        .preferred_size = .{ 20.0, 120.0, 0.0 },
        .max_size = .{ 0.0, 150.0, 0.0 },
        .grow = 1.0,
        .shrink = 1.0,
        .@"align" = "fill",
    });

    const bottom = try world.createEntity("bottom", "Bottom");
    try world.setUiSpacer(bottom, .{ .size = .{ 60.0, 30.0, 0.0 } });
    try world.setUiLayoutItem(bottom, .{ .parent = "column", .order = 2, .@"align" = "center" });

    const top_rect = try resolvedItemRect(&world, top);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), top_rect.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 28.0), top_rect.position[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 108.0), top_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), top_rect.size[1], 0.001);

    const middle_rect = try resolvedItemRect(&world, middle);
    try std.testing.expectApproxEqAbs(@as(f32, 70.0), middle_rect.position[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 108.0), middle_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 150.0), middle_rect.size[1], 0.001);

    const bottom_rect = try resolvedItemRect(&world, bottom);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), bottom_rect.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 222.0), bottom_rect.position[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 60.0), bottom_rect.size[0], 0.001);

    try world.setVec3(group, runtime.ui_vgroup_component_id, "size", .{ 120.0, 116.0, 0.0 });
    const narrow_middle_rect = try resolvedItemRect(&world, middle);
    const narrow_bottom_rect = try resolvedItemRect(&world, bottom);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), narrow_middle_rect.size[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 122.0), narrow_bottom_rect.position[1], 0.001);
}

test "vgroup rejects invalid fixed layout values" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const group = try world.createEntity("column", "Column");
    try world.setUiVGroup(group, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = .{ 100.0, -1.0, 0.0 },
        .spacing = 2.0,
    });

    const child = try world.createEntity("child", "Child");
    try world.setUiSpacer(child, .{ .size = .{ 10.0, 10.0, 0.0 } });
    try world.setUiLayoutItem(child, .{ .parent = "column", .order = 0 });

    try std.testing.expectError(error.InvalidLayout, resolvedItemRect(&world, child));
}

test "cached layout resolution matches direct layout resolution" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const panel = try world.createEntity("panel", "Panel");
    try world.setUiRect(panel, .{
        .position = .{ 12.0, 18.0, 0.0 },
        .size = .{ 240.0, 180.0, 0.0 },
        .color = .{ 0.0, 0.0, 0.0 },
    });

    const scroll = try world.createEntity("scroll", "Scroll");
    try world.setUiScrollView(scroll, .{
        .position = .{ 8.0, 10.0, 0.0 },
        .size = .{ 180.0, 90.0, 0.0 },
        .content_offset = .{ 0.0, 15.0, 0.0 },
    });
    try world.setUiLayoutItem(scroll, .{ .parent = "panel", .order = 0 });

    const column = try world.createEntity("column", "Column");
    try world.setUiVGroup(column, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = .{ 180.0, 160.0, 0.0 },
        .spacing = 4.0,
        .padding = .{ 6.0, 5.0, 0.0 },
    });
    try world.setUiLayoutItem(column, .{ .parent = "scroll", .order = 0 });

    const first = try world.createEntity("first", "First");
    try world.setUiSpacer(first, .{ .size = .{ 30.0, 20.0, 0.0 } });
    try world.setUiLayoutItem(first, .{ .parent = "column", .order = 0, .@"align" = "fill" });

    const second = try world.createEntity("second", "Second");
    try world.setUiSpacer(second, .{ .size = .{ 40.0, 30.0, 0.0 } });
    try world.setUiLayoutItem(second, .{ .parent = "column", .order = 1, .@"align" = "center" });

    var cache = LayoutCache.init(std.testing.allocator);
    defer cache.deinit();
    try cache.reset(&world);

    const direct_layout = try resolve(&world, second, .{ 3.0, 7.0, 0.0 });
    const cached_layout = try resolveWithCache(&cache, &world, second, .{ 3.0, 7.0, 0.0 });
    try std.testing.expectApproxEqAbs(direct_layout.position[0], cached_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(direct_layout.position[1], cached_layout.position[1], 0.001);
    try std.testing.expectApproxEqAbs(direct_layout.position[2], cached_layout.position[2], 0.001);
    try std.testing.expect(direct_layout.clip != null);
    try std.testing.expect(cached_layout.clip != null);
    try std.testing.expectApproxEqAbs(direct_layout.clip.?.position[0], cached_layout.clip.?.position[0], 0.001);
    try std.testing.expectApproxEqAbs(direct_layout.clip.?.position[1], cached_layout.clip.?.position[1], 0.001);
    try std.testing.expectApproxEqAbs(direct_layout.clip.?.size[0], cached_layout.clip.?.size[0], 0.001);
    try std.testing.expectApproxEqAbs(direct_layout.clip.?.size[1], cached_layout.clip.?.size[1], 0.001);

    const direct_size = try resolvedItemSize(&world, second);
    const cached_size = try resolvedItemSizeWithCache(&cache, &world, second);
    try std.testing.expectApproxEqAbs(direct_size[0], cached_size[0], 0.001);
    try std.testing.expectApproxEqAbs(direct_size[1], cached_size[1], 0.001);
}

test "table lays out children in row-major cells with controlled column split" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const table_entity = try world.createEntity("properties", "Property Table");
    try world.setUiTable(table_entity, .{
        .position = .{ 10.0, 20.0, 0.0 },
        .size = .{ 400.0, 80.0, 0.0 },
        .columns = 2,
        .row_height = 24.0,
        .column_gap = 8.0,
        .row_gap = 4.0,
        .padding = .{ 12.0, 6.0, 0.0 },
        .first_column_ratio = 0.5,
    });

    const label = try world.createEntity("label", "Label");
    try world.setUiSpacer(label, .{ .size = .{ 1.0, 1.0, 0.0 } });
    try world.setUiLayoutItem(label, .{ .parent = "properties", .order = 0, .@"align" = "fill" });

    const value = try world.createEntity("value", "Value");
    try world.setUiSpacer(value, .{ .size = .{ 1.0, 1.0, 0.0 } });
    try world.setUiLayoutItem(value, .{ .parent = "properties", .order = 1, .@"align" = "fill" });

    const next_label = try world.createEntity("next-label", "Next Label");
    try world.setUiSpacer(next_label, .{ .size = .{ 1.0, 1.0, 0.0 } });
    try world.setUiLayoutItem(next_label, .{ .parent = "properties", .order = 2, .@"align" = "fill" });

    const label_rect = try resolvedItemRect(&world, label);
    const value_rect = try resolvedItemRect(&world, value);
    const next_label_rect = try resolvedItemRect(&world, next_label);

    try std.testing.expectApproxEqAbs(@as(f32, 22.0), label_rect.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 26.0), label_rect.position[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 184.0), label_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), label_rect.size[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 214.0), value_rect.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 184.0), value_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 22.0), next_label_rect.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 54.0), next_label_rect.position[1], 0.001);
}
