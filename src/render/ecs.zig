const std = @import("std");
const runtime = @import("../runtime.zig");
const types = @import("types.zig");

const RenderError = types.RenderError;
const FrameInput = types.FrameInput;
const UiButtonState = types.UiButtonState;
const UiClipRect = types.UiClipRect;
const UiBorder = types.UiBorder;
const UiProgressBar = types.UiProgressBar;
const render_ui_button_state_component_id = types.render_ui_button_state_component_id;
const render_ui_clip_component_id = types.render_ui_clip_component_id;
const render_draw_batch_component_id = types.render_draw_batch_component_id;
const render_draw_ui_component_id = types.render_draw_ui_component_id;
const render_extract_system_id = types.render_extract_system_id;
const render_prepare_meshes_system_id = types.render_prepare_meshes_system_id;
const render_queue_meshes_system_id = types.render_queue_meshes_system_id;
const render_interact_ui_system_id = types.render_interact_ui_system_id;
const render_prepare_ui_system_id = types.render_prepare_ui_system_id;
const render_queue_ui_system_id = types.render_queue_ui_system_id;
const render_draw_meshes_system_id = types.render_draw_meshes_system_id;

pub fn registerRenderEcsTypes(registry: *runtime.ComponentRegistry) !void {
    try runtime.registerEngineComponents(registry);

    const ui_button_state_fields = [_]runtime.ComponentFieldDefinition{
        .{ .name = "hovered", .value_type = .boolean },
        .{ .name = "held", .value_type = .boolean },
        .{ .name = "pressed", .value_type = .boolean },
    };
    try registry.registerEngineComponent(.{
        .id = render_ui_button_state_component_id,
        .version = 1,
        .fields = &ui_button_state_fields,
    });
    const ui_clip_fields = [_]runtime.ComponentFieldDefinition{
        .{ .name = "position", .value_type = .vec3 },
        .{ .name = "size", .value_type = .vec3 },
    };
    try registry.registerEngineComponent(.{
        .id = render_ui_clip_component_id,
        .version = 1,
        .fields = &ui_clip_fields,
    });
    const draw_batch_fields = [_]runtime.ComponentFieldDefinition{
        .{ .name = "batch_index", .value_type = .int },
    };
    try registry.registerEngineComponent(.{
        .id = render_draw_batch_component_id,
        .version = 1,
        .fields = &draw_batch_fields,
    });
    try registry.registerEngineComponent(.{
        .id = render_draw_ui_component_id,
        .version = 1,
    });

    const extract_writes = [_][]const u8{
        runtime.transform_component_id,
        runtime.geometry_primitive_component_id,
        runtime.surface_material_component_id,
        runtime.camera_component_id,
        runtime.directional_light_component_id,
        runtime.shadow_caster_component_id,
        runtime.shadow_receiver_component_id,
        runtime.ui_canvas_component_id,
        runtime.ui_rect_component_id,
        runtime.ui_border_component_id,
        runtime.ui_text_component_id,
        runtime.ui_button_component_id,
        runtime.ui_command_component_id,
        runtime.ui_scroll_view_component_id,
        runtime.ui_vgroup_component_id,
        runtime.ui_hgroup_component_id,
        runtime.ui_stack_component_id,
        runtime.ui_layout_item_component_id,
        runtime.ui_spacer_component_id,
        runtime.ui_text_block_component_id,
        runtime.ui_toggle_component_id,
        runtime.ui_progress_bar_component_id,
        runtime.ui_separator_component_id,
        runtime.input_pointer_component_id,
        runtime.input_keyboard_component_id,
        runtime.input_frame_component_id,
    };
    try registry.registerEngineSystem(.{
        .id = render_extract_system_id,
        .phase = .render,
        .writes = &extract_writes,
    });

    const prepare_reads = [_][]const u8{
        runtime.transform_component_id,
        runtime.geometry_primitive_component_id,
        runtime.surface_material_component_id,
        runtime.shadow_caster_component_id,
        runtime.shadow_receiver_component_id,
    };
    const after_extract = [_][]const u8{render_extract_system_id};
    try registry.registerEngineSystem(.{
        .id = render_prepare_meshes_system_id,
        .phase = .render,
        .reads = &prepare_reads,
        .after = &after_extract,
    });

    const queue_reads = [_][]const u8{
        runtime.transform_component_id,
        runtime.geometry_primitive_component_id,
        runtime.surface_material_component_id,
        runtime.shadow_caster_component_id,
        runtime.shadow_receiver_component_id,
    };
    const queue_writes = [_][]const u8{render_draw_batch_component_id};
    const after_prepare = [_][]const u8{render_prepare_meshes_system_id};
    try registry.registerEngineSystem(.{
        .id = render_queue_meshes_system_id,
        .phase = .render,
        .reads = &queue_reads,
        .writes = &queue_writes,
        .after = &after_prepare,
    });

    const interact_ui_reads = [_][]const u8{
        runtime.input_pointer_component_id,
        runtime.input_frame_component_id,
        runtime.ui_rect_component_id,
        runtime.ui_button_component_id,
        runtime.ui_scroll_view_component_id,
        runtime.ui_vgroup_component_id,
        runtime.ui_hgroup_component_id,
        runtime.ui_stack_component_id,
        runtime.ui_layout_item_component_id,
    };
    const interact_ui_writes = [_][]const u8{render_ui_button_state_component_id};
    try registry.registerEngineSystem(.{
        .id = render_interact_ui_system_id,
        .phase = .render,
        .reads = &interact_ui_reads,
        .writes = &interact_ui_writes,
        .after = &after_extract,
    });

    const prepare_ui_reads = [_][]const u8{
        runtime.ui_rect_component_id,
        runtime.ui_border_component_id,
        runtime.ui_text_component_id,
        runtime.ui_button_component_id,
        runtime.ui_scroll_view_component_id,
        runtime.ui_vgroup_component_id,
        runtime.ui_hgroup_component_id,
        runtime.ui_stack_component_id,
        runtime.ui_layout_item_component_id,
        runtime.ui_spacer_component_id,
        runtime.ui_text_block_component_id,
        runtime.ui_toggle_component_id,
        runtime.ui_progress_bar_component_id,
        runtime.ui_separator_component_id,
        render_ui_button_state_component_id,
    };
    const after_queue_meshes = [_][]const u8{ render_queue_meshes_system_id, render_interact_ui_system_id };
    try registry.registerEngineSystem(.{
        .id = render_prepare_ui_system_id,
        .phase = .render,
        .reads = &prepare_ui_reads,
        .after = &after_queue_meshes,
    });

    const queue_ui_reads = [_][]const u8{
        runtime.ui_rect_component_id,
        runtime.ui_border_component_id,
        runtime.ui_text_component_id,
        runtime.ui_separator_component_id,
        runtime.ui_progress_bar_component_id,
    };
    const queue_ui_writes = [_][]const u8{render_draw_ui_component_id};
    const after_prepare_ui = [_][]const u8{render_prepare_ui_system_id};
    try registry.registerEngineSystem(.{
        .id = render_queue_ui_system_id,
        .phase = .render,
        .reads = &queue_ui_reads,
        .writes = &queue_ui_writes,
        .after = &after_prepare_ui,
    });

    const draw_reads = [_][]const u8{
        render_draw_batch_component_id,
        render_draw_ui_component_id,
        runtime.transform_component_id,
        runtime.geometry_primitive_component_id,
        runtime.surface_material_component_id,
        runtime.camera_component_id,
        runtime.directional_light_component_id,
        runtime.shadow_caster_component_id,
        runtime.shadow_receiver_component_id,
        runtime.ui_rect_component_id,
        runtime.ui_text_component_id,
        runtime.ui_button_component_id,
        runtime.ui_scroll_view_component_id,
        runtime.ui_vgroup_component_id,
        runtime.ui_hgroup_component_id,
        runtime.ui_stack_component_id,
        runtime.ui_layout_item_component_id,
        runtime.ui_spacer_component_id,
        runtime.ui_text_block_component_id,
        runtime.ui_toggle_component_id,
        runtime.ui_progress_bar_component_id,
        runtime.ui_separator_component_id,
        runtime.input_pointer_component_id,
        runtime.input_keyboard_component_id,
        runtime.input_frame_component_id,
        render_ui_button_state_component_id,
    };
    const after_queue = [_][]const u8{render_queue_ui_system_id};
    try registry.registerEngineSystem(.{
        .id = render_draw_meshes_system_id,
        .phase = .render,
        .reads = &draw_reads,
        .after = &after_queue,
    });
}

pub fn writeFrameInput(world: *runtime.World, input: FrameInput) runtime.WorldError!void {
    const entity = world.findEntityById(runtime.input_entity_id) orelse try world.createEntity(runtime.input_entity_id, "Input Frame");
    try world.setInputPointer(entity, .{
        .position = .{ input.pointer.position[0], input.pointer.position[1], 0.0 },
        .delta = .{ input.pointer.delta[0], input.pointer.delta[1], 0.0 },
        .has_position = input.pointer.has_position,
        .primary_down = input.pointer.primary_down,
        .primary_pressed = input.pointer.primary_pressed,
        .primary_released = input.pointer.primary_released,
        .secondary_down = input.pointer.secondary_down,
        .secondary_pressed = input.pointer.secondary_pressed,
        .secondary_released = input.pointer.secondary_released,
        .wheel_delta = .{ input.pointer.wheel_delta[0], input.pointer.wheel_delta[1], 0.0 },
    });
    try world.setInputKeyboard(entity, .{
        .ctrl_down = input.keyboard.ctrl_down,
        .shift_down = input.keyboard.shift_down,
        .alt_down = input.keyboard.alt_down,
        .super_down = input.keyboard.super_down,
        .move_forward = input.keyboard.move_forward,
        .move_back = input.keyboard.move_back,
        .move_left = input.keyboard.move_left,
        .move_right = input.keyboard.move_right,
        .move_up = input.keyboard.move_up,
        .move_down = input.keyboard.move_down,
        .editor_toggle_pressed = input.keyboard.editor_toggle_pressed,
    });
    try world.setInputFrame(entity, .{
        .ui_visible = input.ui_visible,
        .debug_overlay_visible = input.debug_overlay_visible,
        .viewport = .{ input.viewport_width, input.viewport_height, 0.0 },
    });
}

pub fn setRenderFrameInput(world: *runtime.World, input: FrameInput) RenderError!void {
    writeFrameInput(world, input) catch |err| return mapWorldError(err);
}

pub fn renderFrameInput(world: *const runtime.World) RenderError!FrameInput {
    const entity = world.findEntityById(runtime.input_entity_id) orelse return RenderError.InvalidScene;
    const position = world.getVec3(entity, runtime.input_pointer_component_id, "position") catch |err| return mapWorldError(err);
    const delta = world.getVec3(entity, runtime.input_pointer_component_id, "delta") catch |err| return mapWorldError(err);
    const wheel_delta = world.getVec3(entity, runtime.input_pointer_component_id, "wheel_delta") catch |err| return mapWorldError(err);
    const viewport = world.getVec3(entity, runtime.input_frame_component_id, "viewport") catch |err| return mapWorldError(err);
    return .{
        .pointer = .{
            .position = .{ position[0], position[1] },
            .delta = .{ delta[0], delta[1] },
            .has_position = world.getBoolean(entity, runtime.input_pointer_component_id, "has_position") catch |err| return mapWorldError(err),
            .primary_down = world.getBoolean(entity, runtime.input_pointer_component_id, "primary_down") catch |err| return mapWorldError(err),
            .primary_pressed = world.getBoolean(entity, runtime.input_pointer_component_id, "primary_pressed") catch |err| return mapWorldError(err),
            .primary_released = world.getBoolean(entity, runtime.input_pointer_component_id, "primary_released") catch |err| return mapWorldError(err),
            .secondary_down = world.getBoolean(entity, runtime.input_pointer_component_id, "secondary_down") catch |err| return mapWorldError(err),
            .secondary_pressed = world.getBoolean(entity, runtime.input_pointer_component_id, "secondary_pressed") catch |err| return mapWorldError(err),
            .secondary_released = world.getBoolean(entity, runtime.input_pointer_component_id, "secondary_released") catch |err| return mapWorldError(err),
            .wheel_delta = .{ wheel_delta[0], wheel_delta[1] },
        },
        .keyboard = .{
            .ctrl_down = world.getBoolean(entity, runtime.input_keyboard_component_id, "ctrl_down") catch |err| return mapWorldError(err),
            .shift_down = world.getBoolean(entity, runtime.input_keyboard_component_id, "shift_down") catch |err| return mapWorldError(err),
            .alt_down = world.getBoolean(entity, runtime.input_keyboard_component_id, "alt_down") catch |err| return mapWorldError(err),
            .super_down = world.getBoolean(entity, runtime.input_keyboard_component_id, "super_down") catch |err| return mapWorldError(err),
            .move_forward = world.getBoolean(entity, runtime.input_keyboard_component_id, "move_forward") catch |err| return mapWorldError(err),
            .move_back = world.getBoolean(entity, runtime.input_keyboard_component_id, "move_back") catch |err| return mapWorldError(err),
            .move_left = world.getBoolean(entity, runtime.input_keyboard_component_id, "move_left") catch |err| return mapWorldError(err),
            .move_right = world.getBoolean(entity, runtime.input_keyboard_component_id, "move_right") catch |err| return mapWorldError(err),
            .move_up = world.getBoolean(entity, runtime.input_keyboard_component_id, "move_up") catch |err| return mapWorldError(err),
            .move_down = world.getBoolean(entity, runtime.input_keyboard_component_id, "move_down") catch |err| return mapWorldError(err),
            .editor_toggle_pressed = world.getBoolean(entity, runtime.input_keyboard_component_id, "editor_toggle_pressed") catch |err| return mapWorldError(err),
        },
        .ui_visible = world.getBoolean(entity, runtime.input_frame_component_id, "ui_visible") catch |err| return mapWorldError(err),
        .debug_overlay_visible = world.getBoolean(entity, runtime.input_frame_component_id, "debug_overlay_visible") catch |err| return mapWorldError(err),
        .viewport_width = viewport[0],
        .viewport_height = viewport[1],
    };
}

pub fn setRenderUiButtonState(world: *runtime.World, entity: runtime.EntityHandle, state: UiButtonState) RenderError!void {
    const fields = [_]runtime.ComponentFieldValue{
        .{ .name = "hovered", .value = .{ .boolean = state.hovered } },
        .{ .name = "held", .value = .{ .boolean = state.held } },
        .{ .name = "pressed", .value = .{ .boolean = state.pressed } },
    };
    world.setComponent(entity, render_ui_button_state_component_id, &fields) catch |err| return mapWorldError(err);
}

pub fn setRenderUiClip(world: *runtime.World, entity: runtime.EntityHandle, clip: UiClipRect) RenderError!void {
    const fields = [_]runtime.ComponentFieldValue{
        .{ .name = "position", .value = .{ .vec3 = clip.position } },
        .{ .name = "size", .value = .{ .vec3 = clip.size } },
    };
    world.setComponent(entity, render_ui_clip_component_id, &fields) catch |err| return mapWorldError(err);
}

pub fn renderUiButtonState(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?UiButtonState {
    if (!(world.hasComponent(entity, render_ui_button_state_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return .{
        .hovered = world.getBoolean(entity, render_ui_button_state_component_id, "hovered") catch |err| return mapWorldError(err),
        .held = world.getBoolean(entity, render_ui_button_state_component_id, "held") catch |err| return mapWorldError(err),
        .pressed = world.getBoolean(entity, render_ui_button_state_component_id, "pressed") catch |err| return mapWorldError(err),
    };
}

pub fn renderUiClip(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?UiClipRect {
    if (!(world.hasComponent(entity, render_ui_clip_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return .{
        .position = world.getVec3(entity, render_ui_clip_component_id, "position") catch |err| return mapWorldError(err),
        .size = world.getVec3(entity, render_ui_clip_component_id, "size") catch |err| return mapWorldError(err),
    };
}

pub fn uiBorder(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?UiBorder {
    if (!(world.hasComponent(entity, runtime.ui_border_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return .{
        .color = world.getVec3(entity, runtime.ui_border_component_id, "color") catch |err| return mapWorldError(err),
        .thickness = world.getFloat(entity, runtime.ui_border_component_id, "thickness") catch |err| return mapWorldError(err),
    };
}

pub fn uiProgressBar(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?UiProgressBar {
    if (!(world.hasComponent(entity, runtime.ui_progress_bar_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return .{
        .value = world.getFloat(entity, runtime.ui_progress_bar_component_id, "value") catch |err| return mapWorldError(err),
        .max = world.getFloat(entity, runtime.ui_progress_bar_component_id, "max") catch |err| return mapWorldError(err),
        .fill_color = world.getVec3(entity, runtime.ui_progress_bar_component_id, "fill_color") catch |err| return mapWorldError(err),
    };
}

pub fn uiToggleChecked(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?bool {
    if (!(world.hasComponent(entity, runtime.ui_toggle_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return world.getBoolean(entity, runtime.ui_toggle_component_id, "checked") catch |err| return mapWorldError(err);
}

pub fn batchIndexFromDrawEntity(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!usize {
    const value = world.getComponentFieldValue(entity, render_draw_batch_component_id, "batch_index") catch |err| return mapWorldError(err);
    const batch_index = switch (value) {
        .int => |payload| payload,
        else => return RenderError.InvalidScene,
    };
    if (batch_index < 0) {
        return RenderError.InvalidScene;
    }
    return @intCast(batch_index);
}

fn mapWorldError(err: anyerror) RenderError {
    return switch (err) {
        error.OutOfMemory => RenderError.OutOfMemory,
        else => RenderError.InvalidScene,
    };
}
