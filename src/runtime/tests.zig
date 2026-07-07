const std = @import("std");

const runtime = @import("main.zig");

const ComponentFieldDefinition = runtime.ComponentFieldDefinition;
const ComponentRegistry = runtime.ComponentRegistry;
const EntityProvenance = runtime.EntityProvenance;
const FieldType = runtime.FieldType;
const RegistryError = runtime.RegistryError;
const ResolvedComponentRow = runtime.ResolvedComponentRow;
const ScheduleError = runtime.ScheduleError;
const TypeIdError = runtime.TypeIdError;
const World = runtime.World;
const WorldError = runtime.WorldError;
const camera_component_id = runtime.camera_component_id;
const cube_renderer_component_id = runtime.cube_renderer_component_id;
const directional_light_component_id = runtime.directional_light_component_id;
const findColumn = runtime.findColumn;
const geometry_primitive_component_id = runtime.geometry_primitive_component_id;
const input_entity_id = runtime.input_entity_id;
const input_frame_component_id = runtime.input_frame_component_id;
const input_keyboard_component_id = runtime.input_keyboard_component_id;
const input_pointer_component_id = runtime.input_pointer_component_id;
const registerEngineComponents = runtime.registerEngineComponents;
const renderer_component_id = runtime.renderer_component_id;
const shadow_caster_component_id = runtime.shadow_caster_component_id;
const shadow_receiver_component_id = runtime.shadow_receiver_component_id;
const spin_component_id = runtime.spin_component_id;
const surface_material_component_id = runtime.surface_material_component_id;
const transform_component_id = runtime.transform_component_id;
const ui_canvas_component_id = runtime.ui_canvas_component_id;
const ui_border_component_id = runtime.ui_border_component_id;
const ui_button_component_id = runtime.ui_button_component_id;
const ui_command_component_id = runtime.ui_command_component_id;
const ui_command_event_component_id = runtime.ui_command_event_component_id;
const ui_hgroup_component_id = runtime.ui_hgroup_component_id;
const ui_hit_area_component_id = runtime.ui_hit_area_component_id;
const ui_layout_item_component_id = runtime.ui_layout_item_component_id;
const ui_progress_bar_component_id = runtime.ui_progress_bar_component_id;
const ui_rect_component_id = runtime.ui_rect_component_id;
const ui_scroll_view_component_id = runtime.ui_scroll_view_component_id;
const ui_separator_component_id = runtime.ui_separator_component_id;
const ui_spacer_component_id = runtime.ui_spacer_component_id;
const ui_stack_component_id = runtime.ui_stack_component_id;
const ui_table_component_id = runtime.ui_table_component_id;
const ui_text_block_component_id = runtime.ui_text_block_component_id;
const ui_text_component_id = runtime.ui_text_component_id;
const ui_toggle_component_id = runtime.ui_toggle_component_id;
const ui_vgroup_component_id = runtime.ui_vgroup_component_id;
const validateEngineTypeId = runtime.validateEngineTypeId;
const validatePackageTypeId = runtime.validatePackageTypeId;
const validateProjectTypeId = runtime.validateProjectTypeId;

test "world stores stable entity ids and components" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("entity-1", "Player");
    try world.setTransform(entity, .{ .position = .{ 1.0, 2.0, 3.0 } });
    try world.setCubeRenderer(entity, .{ .color = .{ 1.0, 0.0, 0.0 } });

    try std.testing.expectEqual(@as(usize, 1), world.entityCount());
    try std.testing.expectEqual(@as(usize, 1), world.renderableCubeCount());
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(cube_renderer_component_id));
    try std.testing.expectEqual(@as(usize, 0), world.componentInstanceCountFor(camera_component_id));

    const found = world.findEntityById("entity-1") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(entity.index, found.index);

    const cube = world.renderableCubeAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("entity-1", cube.id);
    try std.testing.expectEqual(@as(f32, 2.0), cube.position[1]);
    try std.testing.expectEqual(@as(f32, 1.0), cube.color[0]);

    const mesh = world.renderableMeshAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("box", mesh.primitive);
    try std.testing.expectEqual(@as(f32, 1.0), mesh.base_color[0]);
    try std.testing.expectEqual(entity.generation, mesh.entity.generation);
}

test "world tracks entity provenance" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const spawned = try world.createEntity("spawned", "Spawned");
    const authored = try world.createAuthoredEntity("authored", "Authored");
    const transient = try world.createEngineTransientEntity("transient", "Transient");

    try std.testing.expectEqual(EntityProvenance.spawned, (try world.entity(spawned)).provenance);
    try std.testing.expectEqual(EntityProvenance.authored, (try world.entity(authored)).provenance);
    try std.testing.expectEqual(EntityProvenance.engine_transient, (try world.entity(transient)).provenance);
}

test "world clears engine transient entities without removing scene entities" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const authored = try world.createAuthoredEntity("authored", "Authored");
    const spawned = try world.createEntity("spawned", "Spawned");
    const transient = try world.createEngineTransientEntity("transient", "Transient");
    try world.setTransform(authored, .{ .position = .{ 1.0, 0.0, 0.0 } });
    try world.setTransform(spawned, .{ .position = .{ 2.0, 0.0, 0.0 } });
    try world.setTransform(transient, .{ .position = .{ 3.0, 0.0, 0.0 } });

    try std.testing.expectEqual(@as(usize, 3), world.entityCount());
    try std.testing.expectEqual(@as(usize, 3), world.componentInstanceCountFor(transform_component_id));

    try world.clearEngineTransientEntities();

    try std.testing.expectEqual(@as(usize, 2), world.entityCount());
    try std.testing.expect(world.findEntityById("authored") != null);
    try std.testing.expect(world.findEntityById("spawned") != null);
    try std.testing.expect(world.findEntityById("transient") == null);
    try std.testing.expectEqual(@as(usize, 2), world.componentInstanceCountFor(transform_component_id));
    try std.testing.expectError(WorldError.InvalidEntity, world.entity(transient));
}

test "world bulk clears interleaved engine transient components" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const first = try world.createEntity("first", "First");
    const transient_a = try world.createEngineTransientEntity("transient-a", "Transient A");
    const middle = try world.createEntity("middle", "Middle");
    const transient_b = try world.createEngineTransientEntity("transient-b", "Transient B");
    const last = try world.createEntity("last", "Last");

    try world.setTransform(first, .{ .position = .{ 1.0, 0.0, 0.0 } });
    try world.setTransform(transient_a, .{ .position = .{ 2.0, 0.0, 0.0 } });
    try world.setTransform(middle, .{ .position = .{ 3.0, 0.0, 0.0 } });
    try world.setTransform(transient_b, .{ .position = .{ 4.0, 0.0, 0.0 } });
    try world.setTransform(last, .{ .position = .{ 5.0, 0.0, 0.0 } });
    try world.setUiText(transient_a, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = 1.0,
        .color = .{ 1.0, 1.0, 1.0 },
        .value = "transient text",
    });
    try world.setSurfaceMaterial(last, .{ .base_color = .{ 0.1, 0.2, 0.3 } });

    try world.clearEngineTransientEntities();

    try std.testing.expectEqual(@as(usize, 3), world.entityCount());
    try std.testing.expect(world.findEntityById("transient-a") == null);
    try std.testing.expect(world.findEntityById("transient-b") == null);
    try std.testing.expectEqual(@as(usize, 3), world.componentInstanceCountFor(transform_component_id));
    try std.testing.expectEqual(@as(usize, 0), world.componentInstanceCountFor(ui_text_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(surface_material_component_id));

    const moved_middle = world.findEntityById("middle") orelse return error.TestExpectedEqual;
    const moved_last = world.findEntityById("last") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u32, 1), moved_middle.index);
    try std.testing.expectEqual(@as(u32, 2), moved_last.index);
    try std.testing.expectError(WorldError.InvalidEntity, world.entity(middle));
    try std.testing.expectError(WorldError.InvalidEntity, world.entity(last));
    try std.testing.expectError(WorldError.InvalidEntity, world.entity(transient_a));
    try std.testing.expectEqual(@as(f32, 3.0), (try world.getTransform(moved_middle)).?.position[0]);
    try std.testing.expect(try world.hasComponent(moved_last, surface_material_component_id));
}

test "engine transient mutations do not write structural events" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const scene_entity = try world.createEntity("scene", "Scene");
    try world.setTransform(scene_entity, .{ .position = .{ 1.0, 0.0, 0.0 } });
    try std.testing.expectEqual(@as(usize, 2), world.structuralEvents().len);
    world.clearStructuralEventsRetainingCapacity();

    const transient = try world.createEngineTransientEntity("transient", "Transient");
    try world.setTransform(transient, .{ .position = .{ 2.0, 0.0, 0.0 } });
    try world.setComponentSilently(scene_entity, ui_command_event_component_id, &.{
        .{ .name = "command", .value = .{ .string = "internal" } },
        .{ .name = "source", .value = .{ .string = "transient" } },
    });
    try std.testing.expectEqual(@as(usize, 0), world.structuralEvents().len);

    try world.clearEngineTransientEntities();
    try world.removeAllComponentsSilently(ui_command_event_component_id);
    try std.testing.expectEqual(@as(usize, 0), world.structuralEvents().len);
    try std.testing.expectError(WorldError.InvalidEntity, world.entity(transient));
}

test "world exposes component field names for inspection" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("entity-1", "Player");
    try world.setTransform(entity, .{ .position = .{ 1.0, 2.0, 3.0 } });

    try std.testing.expectEqual(@as(usize, 3), world.componentFieldCount(transform_component_id));
    try std.testing.expectEqualStrings("position", world.componentFieldNameAt(transform_component_id, 0) orelse return error.TestExpectedEqual);
    try std.testing.expectEqualStrings("rotation", world.componentFieldNameAt(transform_component_id, 1) orelse return error.TestExpectedEqual);
    try std.testing.expectEqualStrings("scale", world.componentFieldNameAt(transform_component_id, 2) orelse return error.TestExpectedEqual);
    try std.testing.expect(world.componentFieldNameAt(transform_component_id, 3) == null);
    try std.testing.expectEqual(@as(usize, 0), world.componentFieldCount("missing.component"));

    const value = try world.getComponentFieldValue(entity, transform_component_id, "position");
    switch (value) {
        .vec3 => |payload| try std.testing.expectEqual(@as(f32, 2.0), payload[1]),
        else => return error.TestExpectedEqual,
    }
}

test "component mutation generation tracks table row and field changes" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    try std.testing.expectEqual(@as(u64, 0), world.componentMutationGeneration(ui_rect_component_id));

    const panel = try world.createEntity("panel", "Panel");
    try world.setUiRect(panel, .{ .position = .{ 1.0, 0.0, 0.0 } });
    const after_add = world.componentMutationGeneration(ui_rect_component_id);
    try std.testing.expect(after_add != 0);

    const input = try world.createEngineTransientEntity(input_entity_id, "Input Frame");
    try world.setInputFrame(input, .{ .viewport = .{ 640.0, 480.0, 0.0 } });
    try std.testing.expectEqual(after_add, world.componentMutationGeneration(ui_rect_component_id));
    try world.clearEngineTransientEntities();
    try std.testing.expectEqual(after_add, world.componentMutationGeneration(ui_rect_component_id));

    try world.setUiRect(panel, .{ .position = .{ 2.0, 0.0, 0.0 } });
    const after_row_update = world.componentMutationGeneration(ui_rect_component_id);
    try std.testing.expect(after_row_update != after_add);

    try world.setVec3(panel, ui_rect_component_id, "color", .{ 0.2, 0.3, 0.4 });
    const after_field_update = world.componentMutationGeneration(ui_rect_component_id);
    try std.testing.expect(after_field_update != after_row_update);

    try std.testing.expect(try world.removeComponent(panel, ui_rect_component_id));
    try std.testing.expect(world.componentMutationGeneration(ui_rect_component_id) != after_field_update);
}

test "world clears entities and components while retaining reusable schemas" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const first = try world.createEntity("first", "First");
    try world.setTransform(first, .{ .position = .{ 1.0, 2.0, 3.0 } });
    try world.setUiText(first, .{
        .position = .{ 4.0, 5.0, 0.0 },
        .size = 2.0,
        .color = .{ 1.0, 1.0, 1.0 },
        .value = "before",
    });

    try std.testing.expectEqual(@as(usize, 1), world.entityCount());
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(transform_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_text_component_id));

    const before_generation = world.queryPlanGeneration();
    const before_revision = world.worldRevision();
    world.clearRetainingCapacity();

    try std.testing.expectEqual(@as(usize, 0), world.entityCount());
    try std.testing.expectEqual(@as(usize, 0), world.componentInstanceCountFor(transform_component_id));
    try std.testing.expectEqual(@as(usize, 0), world.componentInstanceCountFor(ui_text_component_id));
    try std.testing.expectEqual(@as(usize, 3), world.componentFieldCount(transform_component_id));
    try std.testing.expect(world.queryPlanGeneration() != before_generation);
    try std.testing.expect(world.worldRevision() != before_revision);
    try std.testing.expect(world.findEntityById("first") == null);
    try std.testing.expectError(WorldError.InvalidEntity, world.entity(first));

    const second = try world.createEntity("second", "Second");
    try std.testing.expectEqual(@as(u32, 0), second.index);
    try std.testing.expect(second.generation != first.generation);
    try std.testing.expectError(WorldError.InvalidEntity, world.entity(first));
    try world.setTransform(second, .{ .position = .{ 7.0, 8.0, 9.0 } });
    const transform = (try world.getTransform(second)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(f32, 8.0), transform.position[1]);
}

test "world stores frame input components on a shared input entity" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const input = try world.createEntity(input_entity_id, "Input Frame");
    try world.setInputPointer(input, .{
        .position = .{ 12.0, 34.0, 0.0 },
        .delta = .{ 3.0, -4.0, 0.0 },
        .has_position = true,
        .primary_down = true,
        .secondary_down = true,
        .wheel_delta = .{ 0.0, -2.0, 0.0 },
    });
    try world.setInputKeyboard(input, .{
        .ctrl_down = true,
        .move_forward = true,
        .move_down = true,
        .editor_toggle_pressed = true,
    });
    try world.setInputFrame(input, .{
        .ui_visible = true,
        .debug_overlay_visible = true,
        .viewport = .{ 1280.0, 720.0, 0.0 },
        .pixel_scale = 2.0,
    });

    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(input_pointer_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(input_keyboard_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(input_frame_component_id));
    try std.testing.expectEqual(@as(f32, 3.0), (try world.getVec3(input, input_pointer_component_id, "delta"))[0]);
    try std.testing.expect(try world.getBoolean(input, input_pointer_component_id, "secondary_down"));
    try std.testing.expectEqual(@as(f32, -2.0), (try world.getVec3(input, input_pointer_component_id, "wheel_delta"))[1]);
    try std.testing.expect(try world.getBoolean(input, input_keyboard_component_id, "move_forward"));
    try std.testing.expect(try world.getBoolean(input, input_keyboard_component_id, "move_down"));
    try std.testing.expect(try world.getBoolean(input, input_keyboard_component_id, "editor_toggle_pressed"));
    try std.testing.expectEqual(@as(f32, 1280.0), (try world.getVec3(input, input_frame_component_id, "viewport"))[0]);
    try std.testing.expectEqual(@as(f32, 2.0), try world.getFloat(input, input_frame_component_id, "pixel_scale"));
}

test "world removes component rows without moving entity handles" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const first = try world.createEntity("first", "First");
    const second = try world.createEntity("second", "Second");
    try world.setUiCommandEvent(first, .{ .command = "one", .source = "first" });
    try world.setUiCommandEvent(second, .{ .command = "two", .source = "second" });

    try std.testing.expect(try world.removeComponent(first, ui_command_event_component_id));
    try std.testing.expect(!try world.hasComponent(first, ui_command_event_component_id));
    try std.testing.expect(try world.hasComponent(second, ui_command_event_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_command_event_component_id));

    const event = world.uiCommandEvent() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(second.index, event.entity.index);
    try std.testing.expectEqualStrings("two", event.command);
    try std.testing.expectEqualStrings("second", event.source);
    try std.testing.expect(!try world.removeComponent(first, ui_command_event_component_id));
}

test "world records structural events for entities and components" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("entity", "Entity");
    try world.setTransform(entity, .{ .position = .{ 1.0, 2.0, 3.0 } });
    try world.setTransform(entity, .{ .position = .{ 4.0, 5.0, 6.0 } });
    try world.setCubeRenderer(entity, .{ .color = .{ 0.2, 0.4, 0.6 } });

    const initial_events = world.structuralEvents();
    try std.testing.expectEqual(@as(usize, 3), initial_events.len);
    try std.testing.expectEqual(runtime.StructuralEventKind.entity_created, initial_events[0].kind);
    try std.testing.expectEqual(entity, initial_events[0].entity);
    try std.testing.expect(initial_events[0].component_id == null);
    try std.testing.expectEqual(runtime.StructuralEventKind.component_added, initial_events[1].kind);
    try std.testing.expectEqual(entity, initial_events[1].entity);
    try std.testing.expectEqualStrings(transform_component_id, initial_events[1].component_id orelse return error.TestExpectedEqual);
    try std.testing.expectEqual(runtime.StructuralEventKind.component_added, initial_events[2].kind);
    try std.testing.expectEqualStrings(cube_renderer_component_id, initial_events[2].component_id orelse return error.TestExpectedEqual);

    var transform_events = world.componentStructuralEvents(transform_component_id);
    const transform_added = transform_events.next() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(runtime.StructuralEventKind.component_added, transform_added.kind);
    try std.testing.expect(transform_events.next() == null);

    try std.testing.expect(try world.removeComponent(entity, transform_component_id));
    try std.testing.expect(try world.removeEntity(entity));

    const all_events = world.structuralEvents();
    try std.testing.expectEqual(@as(usize, 6), all_events.len);
    try std.testing.expectEqual(runtime.StructuralEventKind.component_removed, all_events[3].kind);
    try std.testing.expectEqualStrings(transform_component_id, all_events[3].component_id orelse return error.TestExpectedEqual);
    try std.testing.expectEqual(runtime.StructuralEventKind.component_removed, all_events[4].kind);
    try std.testing.expectEqualStrings(cube_renderer_component_id, all_events[4].component_id orelse return error.TestExpectedEqual);
    try std.testing.expectEqual(runtime.StructuralEventKind.entity_removed, all_events[5].kind);
    try std.testing.expectEqual(entity, all_events[5].entity);

    var cube_events = world.componentStructuralEvents(cube_renderer_component_id);
    try std.testing.expectEqual(runtime.StructuralEventKind.component_added, (cube_events.next() orelse return error.TestExpectedEqual).kind);
    try std.testing.expectEqual(runtime.StructuralEventKind.component_removed, (cube_events.next() orelse return error.TestExpectedEqual).kind);
    try std.testing.expect(cube_events.next() == null);

    world.clearStructuralEventsRetainingCapacity();
    try std.testing.expectEqual(@as(usize, 0), world.structuralEvents().len);
}

test "query observer reports matching entities once" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const visible = try world.createEntity("visible", "Visible");
    try world.setTransform(visible, .{ .position = .{ 1.0, 0.0, 0.0 } });
    try world.setSurfaceMaterial(visible, .{ .base_color = .{ 0.2, 0.3, 0.4 } });
    const transform_only = try world.createEntity("transform-only", "Transform Only");
    try world.setTransform(transform_only, .{ .position = .{ 2.0, 0.0, 0.0 } });

    var observer = try runtime.QueryObserver.init(std.testing.allocator, &.{
        transform_component_id,
        surface_material_component_id,
    });
    defer observer.deinit();

    try observer.refresh(world);
    try std.testing.expectEqual(@as(usize, 1), observer.existing().len);
    try std.testing.expectEqual(@as(usize, 1), observer.appeared().len);
    try std.testing.expectEqual(@as(usize, 0), observer.disappeared().len);
    try std.testing.expectEqualStrings("visible", observer.appeared()[0].id);
    try std.testing.expectEqual(visible.index, observer.appeared()[0].entity.index);

    try observer.refresh(world);
    try std.testing.expectEqual(@as(usize, 1), observer.existing().len);
    try std.testing.expectEqual(@as(usize, 0), observer.appeared().len);
    try std.testing.expectEqual(@as(usize, 0), observer.disappeared().len);
}

test "query observer tracks component-set membership changes" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("dynamic", "Dynamic");
    try world.setTransform(entity, .{ .position = .{ 1.0, 0.0, 0.0 } });

    var observer = try runtime.QueryObserver.init(std.testing.allocator, &.{
        transform_component_id,
        surface_material_component_id,
    });
    defer observer.deinit();
    try observer.reset(world);
    try std.testing.expectEqual(@as(usize, 0), observer.existing().len);

    try world.setSurfaceMaterial(entity, .{ .base_color = .{ 0.5, 0.6, 0.7 } });
    try observer.refresh(world);
    try std.testing.expectEqual(@as(usize, 1), observer.existing().len);
    try std.testing.expectEqual(@as(usize, 1), observer.appeared().len);
    try std.testing.expectEqualStrings("dynamic", observer.appeared()[0].id);

    try std.testing.expect(try world.removeComponent(entity, transform_component_id));
    try observer.refresh(world);
    try std.testing.expectEqual(@as(usize, 0), observer.existing().len);
    try std.testing.expectEqual(@as(usize, 0), observer.appeared().len);
    try std.testing.expectEqual(@as(usize, 1), observer.disappeared().len);
    try std.testing.expectEqualStrings("dynamic", observer.disappeared()[0].id);

    try world.setTransform(entity, .{ .position = .{ 2.0, 0.0, 0.0 } });
    try observer.refresh(world);
    try std.testing.expectEqual(@as(usize, 1), observer.existing().len);
    try std.testing.expectEqual(@as(usize, 1), observer.appeared().len);
    try std.testing.expectEqualStrings("dynamic", observer.appeared()[0].id);
}

test "query observer reset seeds membership without deltas" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("seeded", "Seeded");
    try world.setTransform(entity, .{ .position = .{ 1.0, 0.0, 0.0 } });
    try world.setSurfaceMaterial(entity, .{ .base_color = .{ 0.1, 0.2, 0.3 } });

    var observer = try runtime.QueryObserver.init(std.testing.allocator, &.{
        transform_component_id,
        surface_material_component_id,
    });
    defer observer.deinit();

    try observer.reset(world);
    try std.testing.expectEqual(@as(usize, 1), observer.existing().len);
    try std.testing.expectEqual(@as(usize, 0), observer.appeared().len);
    try std.testing.expectEqual(@as(usize, 0), observer.disappeared().len);
    try std.testing.expectEqualStrings("seeded", observer.existing()[0].id);
}

test "query observer empty component set tracks all entities" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    var observer = try runtime.QueryObserver.init(std.testing.allocator, &.{});
    defer observer.deinit();
    try observer.reset(world);

    const first = try world.createEntity("first", "First");
    try observer.refresh(world);
    try std.testing.expectEqual(@as(usize, 1), observer.existing().len);
    try std.testing.expectEqual(@as(usize, 1), observer.appeared().len);
    try std.testing.expectEqualStrings("first", observer.appeared()[0].id);

    try std.testing.expect(try world.removeEntity(first));
    try observer.refresh(world);
    try std.testing.expectEqual(@as(usize, 0), observer.existing().len);
    try std.testing.expectEqual(@as(usize, 1), observer.disappeared().len);
    try std.testing.expectEqualStrings("first", observer.disappeared()[0].id);
}

test "query observer repairs handles after silent transient compaction" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const first = try world.createEntity("first", "First");
    try world.setTransform(first, .{ .position = .{ 1.0, 0.0, 0.0 } });
    try world.setSurfaceMaterial(first, .{ .base_color = .{ 0.2, 0.2, 0.2 } });
    const transient = try world.createEngineTransientEntity("transient", "Transient");
    try world.setTransform(transient, .{ .position = .{ 99.0, 0.0, 0.0 } });
    const second = try world.createEntity("second", "Second");
    try world.setTransform(second, .{ .position = .{ 2.0, 0.0, 0.0 } });
    try world.setSurfaceMaterial(second, .{ .base_color = .{ 0.3, 0.3, 0.3 } });

    var observer = try runtime.QueryObserver.init(std.testing.allocator, &.{
        transform_component_id,
        surface_material_component_id,
    });
    defer observer.deinit();
    try observer.reset(world);
    try std.testing.expectEqual(@as(usize, 2), observer.existing().len);

    try world.clearEngineTransientEntities();
    try observer.refresh(world);
    try std.testing.expectEqual(@as(usize, 2), observer.existing().len);
    try std.testing.expectEqual(@as(usize, 0), observer.appeared().len);
    try std.testing.expectEqual(@as(usize, 0), observer.disappeared().len);
    const moved_second = world.findEntityById("second") orelse return error.TestExpectedEqual;
    try std.testing.expect(observer.existing()[0].entity.index == moved_second.index or observer.existing()[1].entity.index == moved_second.index);
    try std.testing.expectError(WorldError.InvalidEntity, world.entity(second));
}

test "query observer survives entity removal compaction and cleared event journals" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const unrelated = try world.createEntity("unrelated", "Unrelated");
    try world.setTransform(unrelated, .{ .position = .{ 0.0, 0.0, 0.0 } });
    const first = try world.createEntity("first", "First");
    try world.setTransform(first, .{ .position = .{ 1.0, 0.0, 0.0 } });
    try world.setSurfaceMaterial(first, .{ .base_color = .{ 0.2, 0.2, 0.2 } });
    const second = try world.createEntity("second", "Second");
    try world.setTransform(second, .{ .position = .{ 2.0, 0.0, 0.0 } });
    try world.setSurfaceMaterial(second, .{ .base_color = .{ 0.3, 0.3, 0.3 } });

    var observer = try runtime.QueryObserver.init(std.testing.allocator, &.{
        transform_component_id,
        surface_material_component_id,
    });
    defer observer.deinit();
    try observer.reset(world);
    try std.testing.expectEqual(@as(usize, 2), observer.existing().len);

    try std.testing.expect(try world.removeEntity(unrelated));
    try observer.refresh(world);
    try std.testing.expectEqual(@as(usize, 2), observer.existing().len);
    try std.testing.expectEqual(@as(usize, 0), observer.appeared().len);
    try std.testing.expectEqual(@as(usize, 0), observer.disappeared().len);
    const moved_first = world.findEntityById("first") orelse return error.TestExpectedEqual;
    const moved_second = world.findEntityById("second") orelse return error.TestExpectedEqual;
    try std.testing.expect(observer.existing()[0].entity.index == moved_first.index or observer.existing()[1].entity.index == moved_first.index);
    try std.testing.expect(observer.existing()[0].entity.index == moved_second.index or observer.existing()[1].entity.index == moved_second.index);

    try std.testing.expect(try world.removeEntity(moved_first));
    try observer.refresh(world);
    try std.testing.expectEqual(@as(usize, 1), observer.existing().len);
    try std.testing.expectEqual(@as(usize, 0), observer.appeared().len);
    try std.testing.expectEqual(@as(usize, 1), observer.disappeared().len);
    try std.testing.expectEqualStrings("first", observer.disappeared()[0].id);

    world.clearStructuralEventsRetainingCapacity();
    const third = try world.createEntity("third", "Third");
    try world.setTransform(third, .{ .position = .{ 3.0, 0.0, 0.0 } });
    try world.setSurfaceMaterial(third, .{ .base_color = .{ 0.4, 0.4, 0.4 } });
    try observer.refresh(world);
    try std.testing.expectEqual(@as(usize, 2), observer.existing().len);
    try std.testing.expectEqual(@as(usize, 1), observer.appeared().len);
    try std.testing.expectEqualStrings("third", observer.appeared()[0].id);
    try std.testing.expectEqual(@as(usize, 0), observer.disappeared().len);
}

test "world removes entities and repairs component table handles" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const first = try world.createEntity("first", "First");
    const middle = try world.createEntity("middle", "Middle");
    const last = try world.createEntity("last", "Last");
    try world.setTransform(first, .{ .position = .{ -1.0, 0.0, 0.0 } });
    try world.setTransform(middle, .{ .position = .{ 0.0, 0.0, 0.0 } });
    try world.setTransform(last, .{ .position = .{ 1.0, 0.0, 0.0 } });
    try world.setSurfaceMaterial(last, .{ .base_color = .{ 0.1, 0.2, 0.3 } });

    try std.testing.expect(try world.removeEntity(middle));
    try std.testing.expectEqual(@as(usize, 2), world.entityCount());
    try std.testing.expect(world.findEntityById("middle") == null);
    try std.testing.expectError(WorldError.InvalidEntity, world.entity(middle));
    try std.testing.expectError(WorldError.InvalidEntity, world.getTransform(middle));

    const moved_last = world.findEntityById("last") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u32, 1), moved_last.index);
    try std.testing.expectEqual(last.generation, moved_last.generation);
    try std.testing.expectError(WorldError.InvalidEntity, world.entity(last));
    const moved_transform = (try world.getTransform(moved_last)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(f32, 1.0), moved_transform.position[0]);
    try std.testing.expect(try world.hasComponent(moved_last, surface_material_component_id));

    var cursor: usize = 0;
    const query = [_][]const u8{transform_component_id};
    try std.testing.expectEqual(first.index, (world.queryNext(&query, &cursor) orelse return error.TestExpectedEqual).index);
    try std.testing.expectEqual(moved_last.index, (world.queryNext(&query, &cursor) orelse return error.TestExpectedEqual).index);
    try std.testing.expect(world.queryNext(&query, &cursor) == null);
}

test "world resolves explicit primitive geometry and surface material renderables" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("sphere", "Sphere");
    try world.setTransform(entity, .{ .position = .{ 0.0, 1.0, 0.0 } });
    try world.setGeometryPrimitive(entity, .{
        .primitive = "uv_sphere",
        .segments = 32,
        .rings = 16,
    });
    try world.setSurfaceMaterial(entity, .{
        .base_color = .{ 0.2, 0.8, 1.0 },
    });
    try world.setShadowCaster(entity);
    try world.setShadowReceiver(entity);

    try std.testing.expectEqual(@as(usize, 1), world.renderableMeshCount());
    try std.testing.expectEqual(@as(usize, 1), world.renderableCubeCount());
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(shadow_caster_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(shadow_receiver_component_id));

    const mesh = world.renderableMeshAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(entity.index, mesh.entity.index);
    try std.testing.expectEqualStrings("uv_sphere", mesh.primitive);
    try std.testing.expectEqual(@as(i32, 32), mesh.segments);
    try std.testing.expectEqual(@as(i32, 16), mesh.rings);
    try std.testing.expectEqual(@as(f32, 0.8), mesh.base_color[1]);
    try std.testing.expect(mesh.casts_shadow);
    try std.testing.expect(mesh.receives_shadow);
}

test "world resolves render camera and directional light components" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const camera_entity = try world.createEntity("camera", "Camera");
    try world.setTransform(camera_entity, .{ .position = .{ 0.0, 1.5, 6.0 } });
    try world.setCamera(camera_entity, .{
        .fov_y_degrees = 55.0,
        .near = 0.2,
        .far = 250.0,
    });

    const light_entity = try world.createEntity("key-light", "Key Light");
    try world.setDirectionalLight(light_entity, .{
        .direction = .{ -0.25, 0.75, 0.5 },
        .color = .{ 0.9, 0.95, 1.0 },
        .intensity = 1.2,
        .ambient = 0.12,
    });

    const camera = world.renderCamera() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(camera_entity.index, camera.entity.index);
    try std.testing.expectEqual(@as(f32, 6.0), camera.transform.position[2]);
    try std.testing.expectEqual(@as(f32, 55.0), camera.fov_y_degrees);

    const light = world.renderDirectionalLight() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(light_entity.index, light.entity.index);
    try std.testing.expectEqual(@as(f32, 0.75), light.direction[1]);
    try std.testing.expectEqual(@as(f32, 1.2), light.intensity);
}

test "world resolves UI rect and text components" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const canvas = try world.createEntity("hud-canvas", "HUD Canvas");
    try world.setUiCanvas(canvas, .{});

    const panel = try world.createEntity("hud-panel", "HUD Panel");
    try world.setUiRect(panel, .{
        .position = .{ 24.0, 24.0, 0.0 },
        .size = .{ 220.0, 72.0, 0.0 },
        .color = .{ 0.02, 0.08, 0.14 },
    });

    const button = try world.createEntity("hud-button", "HUD Button");
    try world.setUiRect(button, .{
        .position = .{ 32.0, 104.0, 0.0 },
        .size = .{ 140.0, 34.0, 0.0 },
        .color = .{ 0.0, 0.48, 0.86 },
        .corner_radius = 6.0,
    });
    try world.setUiButton(button);

    const label = try world.createEntity("hud-label", "HUD Label");
    try world.setUiText(label, .{
        .position = .{ 40.0, 42.0, 0.0 },
        .size = 2.0,
        .color = .{ 0.82, 0.94, 1.0 },
        .value = "BATCHES 4",
    });

    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_canvas_component_id));
    try std.testing.expectEqual(@as(usize, 2), world.uiRectCount());
    try std.testing.expectEqual(@as(usize, 1), world.uiTextCount());

    const resolved_panel = world.uiRectAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(panel.index, resolved_panel.entity.index);
    try std.testing.expectEqual(@as(f32, 220.0), resolved_panel.size[0]);
    try std.testing.expect(!resolved_panel.is_button);

    const resolved_button = world.uiRectAt(1) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(button.index, resolved_button.entity.index);
    try std.testing.expect(resolved_button.is_button);
    try std.testing.expectEqual(@as(f32, 6.0), resolved_button.corner_radius);

    const resolved_label = world.uiTextAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(label.index, resolved_label.entity.index);
    try std.testing.expectEqual(@as(f32, 2.0), resolved_label.size);
    try std.testing.expectEqualStrings("BATCHES 4", resolved_label.value);
}

test "UI iterators preserve entity order after component swap removal" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const first = try world.createEntity("first", "First");
    try world.setUiRect(first, .{ .position = .{ 1.0, 0.0, 0.0 } });

    const second = try world.createEntity("second", "Second");
    try world.setUiRect(second, .{ .position = .{ 2.0, 0.0, 0.0 } });
    try world.setUiButton(second);

    const third = try world.createEntity("third", "Third");
    try world.setUiRect(third, .{ .position = .{ 3.0, 0.0, 0.0 } });

    try std.testing.expect(try world.removeComponent(first, ui_rect_component_id));

    var rects = world.uiRects();
    const resolved_second = rects.next() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(second.index, resolved_second.entity.index);
    try std.testing.expect(resolved_second.is_button);
    try std.testing.expectEqual(@as(f32, 2.0), resolved_second.position[0]);

    const resolved_third = rects.next() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(third.index, resolved_third.entity.index);
    try std.testing.expect(!resolved_third.is_button);
    try std.testing.expectEqual(@as(f32, 3.0), resolved_third.position[0]);

    try std.testing.expect(rects.next() == null);
}

test "UI rect iterators detect buttons added through wildcard handles" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("button", "Button");
    try world.setUiRect(.{ .index = entity.index }, .{});
    try world.setUiButton(entity);

    var rects = world.uiRects();
    const rect = rects.next() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(entity.index, rect.entity.index);
    try std.testing.expect(rect.is_button);
}

test "world stores expanded UI semantic components" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const stack = try world.createEntity("toolbar", "Toolbar");
    try world.setUiStack(stack, .{
        .position = .{ 10.0, 12.0, 0.0 },
        .spacing = 6.0,
        .direction = "horizontal",
        .padding = .{ 8.0, 4.0, 0.0 },
    });

    const hgroup = try world.createEntity("hgroup", "HGroup");
    try world.setUiHGroup(hgroup, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = .{ 200.0, 40.0, 0.0 },
        .spacing = 4.0,
        .padding = .{ 2.0, 2.0, 0.0 },
    });

    const vgroup = try world.createEntity("vgroup", "VGroup");
    try world.setUiVGroup(vgroup, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = .{ 120.0, 160.0, 0.0 },
        .spacing = 6.0,
        .padding = .{ 3.0, 4.0, 0.0 },
    });

    const slot = try world.createEntity("slot", "Slot");
    try world.setUiLayoutItem(slot, .{
        .parent = "toolbar",
        .order = 2,
        .min_size = .{ 64.0, 32.0, 0.0 },
        .grow = 1.0,
        .@"align" = "center",
    });
    try world.setUiSpacer(slot, .{ .size = .{ 24.0, 16.0, 0.0 } });

    const progress = try world.createEntity("progress", "Progress");
    try world.setUiProgressBar(progress, .{
        .value = 3.0,
        .max = 5.0,
        .fill_color = .{ 0.1, 0.7, 0.3 },
    });
    try world.setUiToggle(progress, .{ .checked = true });

    const label = try world.createEntity("label", "Label");
    try world.setUiText(label, .{ .value = "CENTER" });
    try world.setUiTextBlock(label, .{
        .size = .{ 120.0, 48.0, 0.0 },
        .horizontal_align = "center",
        .vertical_align = "center",
    });

    const separator = try world.createEntity("separator", "Separator");
    try world.setUiSeparator(separator, .{
        .position = .{ 0.0, 44.0, 0.0 },
        .size = .{ 120.0, 2.0, 0.0 },
        .color = .{ 0.5, 0.6, 0.7 },
    });

    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_stack_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_hgroup_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_vgroup_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_spacer_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_text_block_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_toggle_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(ui_progress_bar_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.uiSeparatorCount());

    const resolved_separator = world.uiSeparatorAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(separator.index, resolved_separator.entity.index);
    try std.testing.expectEqual(@as(f32, 2.0), resolved_separator.size[1]);
}

test "world rejects duplicate entity ids" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    _ = try world.createEntity("entity-1", "One");
    try std.testing.expectError(WorldError.DuplicateEntityId, world.createEntity("entity-1", "Two"));
}

test "world queries and mutates component field storage" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("spinner", "Spinner");
    try world.setTransform(entity, .{ .rotation = .{ 0.1, 0.2, 0.3 } });
    try world.setSpin(entity, .{ .angular_velocity = .{ 1.0, 2.0, -4.0 } });

    var cursor: usize = 0;
    const query = [_][]const u8{ transform_component_id, spin_component_id };
    const queried = world.queryNext(&query, &cursor) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(entity.index, queried.index);
    try std.testing.expect(world.queryNext(&query, &cursor) == null);

    const rotation = try world.getVec3(entity, transform_component_id, "rotation");
    const angular_velocity = try world.getVec3(entity, spin_component_id, "angular_velocity");
    try world.setVec3(entity, transform_component_id, "rotation", .{
        rotation[0] + angular_velocity[0] * 0.5,
        rotation[1] + angular_velocity[1] * 0.5,
        rotation[2] + angular_velocity[2] * 0.5,
    });

    const transform_after = (try world.getTransform(entity)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(f32, 0.6), transform_after.rotation[0]);
    try std.testing.expectEqual(@as(f32, 1.2), transform_after.rotation[1]);
    try std.testing.expectEqual(@as(f32, -1.7), transform_after.rotation[2]);
    try std.testing.expectError(WorldError.UnknownComponent, world.getVec3(entity, "stamina", "value"));
    try std.testing.expectError(WorldError.InvalidFieldType, world.setVec3(entity, transform_component_id, "rotation", .{ std.math.inf(f32), 0.0, 0.0 }));
}

test "world stores component fields in sparse SoA tables" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const untagged = try world.createEntity("untagged", "Untagged");
    const plain = try world.createEntity("plain", "Plain");
    const spinner = try world.createEntity("spinner", "Spinner");
    try world.setTransform(plain, .{ .position = .{ -1.0, 0.0, 0.0 } });
    try world.setTransform(spinner, .{
        .position = .{ 1.0, 2.0, 3.0 },
        .rotation = .{ 0.1, 0.2, 0.3 },
        .scale = .{ 2.0, 2.0, 2.0 },
    });
    try world.setSpin(spinner, .{ .angular_velocity = .{ 0.0, 1.0, 0.0 } });

    const transform_table = world.findComponentTable(transform_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 2), transform_table.entities.items.len);
    try std.testing.expectEqual(plain.index, transform_table.entities.items[0].index);
    try std.testing.expectEqual(spinner.index, transform_table.entities.items[1].index);
    try std.testing.expectEqual(@as(usize, 3), transform_table.rows_by_entity.items.len);
    try std.testing.expect(transform_table.rows_by_entity.items[untagged.index] == null);
    try std.testing.expectEqual(@as(usize, 1), transform_table.rows_by_entity.items[spinner.index] orelse return error.TestExpectedEqual);

    const rotation_column = findColumn(transform_table.*, "rotation") orelse return error.TestExpectedEqual;
    const rotation_values = switch (rotation_column.values) {
        .vec3 => |values| values,
        else => return error.TestExpectedEqual,
    };
    try std.testing.expectEqual(@as(usize, 2), rotation_values.items.len);
    try std.testing.expectEqual(@as(f32, 0.2), rotation_values.items[1][1]);

    var cursor: usize = 0;
    const query = [_][]const u8{ transform_component_id, spin_component_id };
    try std.testing.expectEqual(spinner.index, (world.queryNext(&query, &cursor) orelse return error.TestExpectedEqual).index);
    try std.testing.expectEqual(@as(usize, 1), cursor);

    try world.setVec3(spinner, transform_component_id, "rotation", .{ 0.5, 0.6, 0.7 });
    const updated_table = world.findComponentTable(transform_component_id) orelse return error.TestExpectedEqual;
    const updated_rotation_column = findColumn(updated_table.*, "rotation") orelse return error.TestExpectedEqual;
    const updated_rotation_values = switch (updated_rotation_column.values) {
        .vec3 => |values| values,
        else => return error.TestExpectedEqual,
    };
    try std.testing.expectEqual(@as(usize, 2), updated_table.entities.items.len);
    try std.testing.expectEqual(@as(f32, 0.6), updated_rotation_values.items[1][1]);
}

test "world resolved queries return reusable component rows" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const first = try world.createEntity("first", "First");
    const second = try world.createEntity("second", "Second");
    try world.setTransform(first, .{
        .position = .{ 1.0, 0.0, 0.0 },
        .rotation = .{ 0.1, 0.2, 0.3 },
    });
    try world.setTransform(second, .{
        .position = .{ 2.0, 0.0, 0.0 },
        .rotation = .{ 1.1, 1.2, 1.3 },
    });
    try world.setSpin(second, .{ .angular_velocity = .{ 0.0, 2.0, 0.0 } });

    const transform_table = world.resolveComponentTableIndex(transform_component_id) orelse return error.TestExpectedEqual;
    const spin_table = world.resolveComponentTableIndex(spin_component_id) orelse return error.TestExpectedEqual;
    const query_tables = [_]u32{ transform_table, spin_table };
    const driver = (try world.queryDriverTableIndex(&query_tables)) orelse return error.TestExpectedEqual;

    var cursor: usize = 0;
    var rows: [2]u32 = undefined;
    const queried = (try world.queryNextResolved(&query_tables, driver, &cursor, &rows)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(second.index, queried.index);
    try std.testing.expectEqual(spin_table, query_tables[1]);

    const rotation = try world.getComponentFieldValueResolved(queried, .{
        .table_index = transform_table,
        .row_index = rows[0],
    }, "rotation");
    try std.testing.expectEqual(@as(f32, 1.2), rotation.vec3[1]);

    try world.setComponentFieldValueResolved(queried, .{
        .table_index = transform_table,
        .row_index = rows[0],
    }, "rotation", .{ .vec3 = .{ 3.0, 4.0, 5.0 } });
    try std.testing.expectEqual(@as(f32, 4.0), (try world.getVec3(second, transform_component_id, "rotation"))[1]);
    try std.testing.expect((try world.queryNextResolved(&query_tables, driver, &cursor, &rows)) == null);
}

test "world resolved field access repairs stale moved rows" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const first = try world.createEntity("first", "First");
    const second = try world.createEntity("second", "Second");
    try world.setTransform(first, .{ .position = .{ 1.0, 0.0, 0.0 } });
    try world.setTransform(second, .{ .position = .{ 2.0, 0.0, 0.0 } });

    const transform_table = world.resolveComponentTableIndex(transform_component_id) orelse return error.TestExpectedEqual;
    const stale_second_row = ResolvedComponentRow{
        .table_index = transform_table,
        .row_index = 1,
    };

    try std.testing.expect(try world.removeComponent(first, transform_component_id));
    try world.setComponentFieldValueResolved(second, stale_second_row, "position", .{ .vec3 = .{ 9.0, 8.0, 7.0 } });
    try std.testing.expectEqual(@as(f32, 9.0), (try world.getVec3(second, transform_component_id, "position"))[0]);
    try std.testing.expectError(WorldError.UnknownComponent, world.getComponentFieldValueResolved(first, stale_second_row, "position"));
}

test "type ids distinguish project-local, package, and engine namespaces" {
    try validateProjectTypeId("stamina");
    try validateProjectTypeId("inventory_item");
    try validateProjectTypeId("com.acme.stamina");
    try validateProjectTypeId("game.stamina");
    try validatePackageTypeId("com.acme.stamina");
    try validateEngineTypeId("scrapbot.transform");

    try std.testing.expectError(TypeIdError.InvalidTypeId, validateProjectTypeId("Com.Acme.Stamina"));
    try std.testing.expectError(TypeIdError.InvalidTypeId, validateProjectTypeId("com.acme-stamina"));
    try std.testing.expectError(TypeIdError.InvalidTypeId, validateProjectTypeId("com..stamina"));
    try std.testing.expectError(TypeIdError.InvalidTypeId, validatePackageTypeId("stamina"));
    try std.testing.expectError(TypeIdError.ReservedTypeId, validateProjectTypeId("scrapbot.transform"));
    try std.testing.expectError(TypeIdError.ReservedTypeId, validatePackageTypeId("scrapbot.transform"));
    try std.testing.expectError(TypeIdError.ReservedTypeId, validateEngineTypeId("stamina"));
    try std.testing.expectError(TypeIdError.ReservedTypeId, validateEngineTypeId("com.acme.stamina"));
}

test "component registry allows reload-identical components and rejects incompatible duplicates" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const fields = [_]ComponentFieldDefinition{
        .{ .name = "current", .value_type = .float },
        .{ .name = "max", .value_type = .float },
    };
    try registry.registerProjectComponent(.{
        .id = "stamina",
        .version = 1,
        .fields = &fields,
    });
    try registry.registerProjectComponent(.{
        .id = "stamina",
        .version = 1,
        .fields = &fields,
    });

    try std.testing.expectEqual(@as(usize, 1), registry.componentCount());

    const incompatible_fields = [_]ComponentFieldDefinition{
        .{ .name = "current", .value_type = .int },
        .{ .name = "max", .value_type = .float },
    };
    try std.testing.expectError(RegistryError.DuplicateComponentType, registry.registerProjectComponent(.{
        .id = "stamina",
        .version = 1,
        .fields = &incompatible_fields,
    }));
}

test "component registry rejects duplicate field names" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const fields = [_]ComponentFieldDefinition{
        .{ .name = "current", .value_type = .float },
        .{ .name = "current", .value_type = .int },
    };
    try std.testing.expectError(RegistryError.DuplicateComponentField, registry.registerProjectComponent(.{
        .id = "com.acme.stamina",
        .version = 1,
        .fields = &fields,
    }));
}

test "component registry separates project, package, and engine registrations" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.registerProjectComponent(.{
        .id = "stamina",
        .version = 1,
    });
    try std.testing.expectError(RegistryError.InvalidTypeId, registry.registerPackageComponent(.{
        .id = "mana",
        .version = 1,
    }));
    try registry.registerPackageComponent(.{
        .id = "com.acme.mana",
        .version = 1,
    });
    try std.testing.expectError(RegistryError.ReservedTypeId, registry.registerProjectComponent(.{
        .id = "scrapbot.transform",
        .version = 1,
    }));

    try registry.registerEngineComponent(.{
        .id = "scrapbot.transform",
        .version = 1,
    });
    try std.testing.expectEqual(@as(usize, 3), registry.componentCount());
}

test "engine component schemas are registered from runtime" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registerEngineComponents(&registry);

    try std.testing.expect(registry.findComponent(transform_component_id) != null);
    try std.testing.expect(registry.findComponent(cube_renderer_component_id) != null);
    try std.testing.expect(registry.findComponent(geometry_primitive_component_id) != null);
    try std.testing.expect(registry.findComponent(surface_material_component_id) != null);
    try std.testing.expect(registry.findComponent(camera_component_id) != null);
    try std.testing.expect(registry.findComponent(directional_light_component_id) != null);
    try std.testing.expect(registry.findComponent(shadow_caster_component_id) != null);
    try std.testing.expect(registry.findComponent(shadow_receiver_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_canvas_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_rect_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_border_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_text_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_button_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_hit_area_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_command_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_command_event_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_scroll_view_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_vgroup_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_hgroup_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_table_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_stack_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_layout_item_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_spacer_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_text_block_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_toggle_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_progress_bar_component_id) != null);
    try std.testing.expect(registry.findComponent(ui_separator_component_id) != null);
    try std.testing.expect(registry.findComponent(input_pointer_component_id) != null);
    try std.testing.expect(registry.findComponent(input_keyboard_component_id) != null);
    try std.testing.expect(registry.findComponent(input_frame_component_id) != null);
    try std.testing.expect(registry.findComponent(renderer_component_id) != null);
    try std.testing.expectEqual(@as(usize, 31), registry.componentCount());

    const transform = registry.findComponent(transform_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 3), transform.fields.len);
    try std.testing.expectEqual(FieldType.vec3, transform.fields[0].value_type);

    const ui_canvas = registry.findComponent(ui_canvas_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 2), ui_canvas.fields.len);
    try std.testing.expectEqual(FieldType.vec3, ui_canvas.fields[0].value_type);
    try std.testing.expectEqual(FieldType.string, ui_canvas.fields[1].value_type);

    const ui_text = registry.findComponent(ui_text_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 4), ui_text.fields.len);
    try std.testing.expectEqual(FieldType.string, ui_text.fields[3].value_type);

    const ui_rect = registry.findComponent(ui_rect_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 4), ui_rect.fields.len);
    try std.testing.expectEqual(FieldType.float, ui_rect.fields[3].value_type);

    const ui_border = registry.findComponent(ui_border_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 2), ui_border.fields.len);
    try std.testing.expectEqual(FieldType.vec3, ui_border.fields[0].value_type);
    try std.testing.expectEqual(FieldType.float, ui_border.fields[1].value_type);

    const ui_stack = registry.findComponent(ui_stack_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 4), ui_stack.fields.len);
    try std.testing.expectEqual(FieldType.string, ui_stack.fields[2].value_type);

    const ui_hgroup = registry.findComponent(ui_hgroup_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 4), ui_hgroup.fields.len);
    try std.testing.expectEqual(FieldType.vec3, ui_hgroup.fields[1].value_type);
    try std.testing.expectEqual(FieldType.float, ui_hgroup.fields[2].value_type);

    const ui_vgroup = registry.findComponent(ui_vgroup_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 4), ui_vgroup.fields.len);
    try std.testing.expectEqual(FieldType.vec3, ui_vgroup.fields[1].value_type);
    try std.testing.expectEqual(FieldType.float, ui_vgroup.fields[2].value_type);

    const ui_layout_item = registry.findComponent(ui_layout_item_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 9), ui_layout_item.fields.len);
    try std.testing.expectEqual(FieldType.vec3, ui_layout_item.fields[2].value_type);
    try std.testing.expectEqual(FieldType.vec3, ui_layout_item.fields[3].value_type);
    try std.testing.expectEqual(FieldType.vec3, ui_layout_item.fields[4].value_type);
    try std.testing.expectEqual(FieldType.float, ui_layout_item.fields[5].value_type);
    try std.testing.expectEqual(FieldType.float, ui_layout_item.fields[6].value_type);
    try std.testing.expectEqual(FieldType.string, ui_layout_item.fields[7].value_type);
    try std.testing.expectEqual(FieldType.vec3, ui_layout_item.fields[8].value_type);

    const ui_table = registry.findComponent(ui_table_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 8), ui_table.fields.len);
    try std.testing.expectEqual(FieldType.int, ui_table.fields[2].value_type);
    try std.testing.expectEqual(FieldType.float, ui_table.fields[3].value_type);
    try std.testing.expectEqual(FieldType.float, ui_table.fields[7].value_type);

    const ui_progress_bar = registry.findComponent(ui_progress_bar_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 3), ui_progress_bar.fields.len);
    try std.testing.expectEqual(FieldType.vec3, ui_progress_bar.fields[2].value_type);

    const ui_separator = registry.findComponent(ui_separator_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 3), ui_separator.fields.len);
    try std.testing.expectEqual(FieldType.vec3, ui_separator.fields[2].value_type);

    const ui_command_event = registry.findComponent(ui_command_event_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 2), ui_command_event.fields.len);
    try std.testing.expectEqual(FieldType.string, ui_command_event.fields[0].value_type);

    const input_pointer = registry.findComponent(input_pointer_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 10), input_pointer.fields.len);
    try std.testing.expectEqual(FieldType.vec3, input_pointer.fields[1].value_type);
    try std.testing.expectEqual(FieldType.boolean, input_pointer.fields[6].value_type);
    try std.testing.expectEqual(FieldType.vec3, input_pointer.fields[9].value_type);

    const input_keyboard = registry.findComponent(input_keyboard_component_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 11), input_keyboard.fields.len);
    try std.testing.expectEqual(FieldType.boolean, input_keyboard.fields[4].value_type);
    try std.testing.expectEqual(FieldType.boolean, input_keyboard.fields[9].value_type);
}

test "system registry validates component access and reload-compatible definitions" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.registerProjectComponent(.{ .id = "stamina", .version = 1 });
    try registry.registerPackageComponent(.{ .id = "com.acme.mana", .version = 1 });
    try registry.registerEngineComponent(.{ .id = "scrapbot.transform", .version = 1 });

    const reads = [_][]const u8{ "scrapbot.transform", "stamina" };
    const writes = [_][]const u8{"stamina"};
    const after = [_][]const u8{"input"};
    try registry.registerProjectSystem(.{
        .id = "stamina_regen",
        .reads = &reads,
        .writes = &.{},
        .after = &after,
    });
    try registry.registerProjectSystem(.{
        .id = "stamina_regen",
        .reads = &reads,
        .writes = &.{},
        .after = &after,
    });
    try std.testing.expectEqual(@as(usize, 1), registry.systemCount());

    const package_reads = [_][]const u8{"com.acme.mana"};
    try registry.registerPackageSystem(.{
        .id = "com.acme.mana_regen",
        .reads = &package_reads,
    });
    try std.testing.expectEqual(@as(usize, 2), registry.systemCount());

    try std.testing.expectError(RegistryError.UnknownComponentType, registry.registerProjectSystem(.{
        .id = "com.acme.missing_reader",
        .reads = &.{"com.acme.missing"},
    }));
    try std.testing.expectError(RegistryError.InvalidTypeId, registry.registerPackageSystem(.{
        .id = "com.acme.bad_local_access",
        .reads = &.{"stamina"},
    }));
    try std.testing.expectError(RegistryError.DuplicateSystemAccess, registry.registerProjectSystem(.{
        .id = "com.acme.bad_access",
        .reads = &reads,
        .writes = &writes,
    }));
    try std.testing.expectError(RegistryError.ReservedTypeId, registry.registerProjectSystem(.{
        .id = "scrapbot.script_system",
    }));
}

test "system schedule batches compatible systems and detects order cycles" {
    var registry = ComponentRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.registerProjectComponent(.{ .id = "stamina" });
    try registry.registerProjectComponent(.{ .id = "focus" });

    try registry.registerProjectSystem(.{
        .id = "observe_stamina",
        .reads = &.{"stamina"},
    });
    try registry.registerProjectSystem(.{
        .id = "observe_focus",
        .reads = &.{"focus"},
    });
    try registry.registerProjectSystem(.{
        .id = "regen_stamina",
        .writes = &.{"stamina"},
        .after = &.{"observe_stamina"},
    });

    var schedule = try registry.buildSchedule(std.testing.allocator, .update);
    defer schedule.deinit();

    try std.testing.expectEqual(@as(usize, 2), schedule.batchCount());
    try std.testing.expectEqual(@as(usize, 3), schedule.systemCount());
    try std.testing.expectEqualStrings("observe_stamina", schedule.batches[0].systems[0].id);
    try std.testing.expectEqualStrings("observe_focus", schedule.batches[0].systems[1].id);
    try std.testing.expectEqualStrings("regen_stamina", schedule.batches[1].systems[0].id);

    var cyclic = ComponentRegistry.init(std.testing.allocator);
    defer cyclic.deinit();
    try cyclic.registerProjectSystem(.{
        .id = "first",
        .after = &.{"second"},
    });
    try cyclic.registerProjectSystem(.{
        .id = "second",
        .after = &.{"first"},
    });

    try std.testing.expectError(ScheduleError.CyclicSystemOrder, cyclic.buildSchedule(std.testing.allocator, .update));
}
