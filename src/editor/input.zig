const std = @import("std");
const runtime = @import("../runtime.zig");
const ui_layout = @import("../ui_layout.zig");
const editor_state_types = @import("state.zig");
const editor_layout = @import("layout.zig");
const editor_theme = @import("theme.zig");
const render_input = @import("../render/input.zig");
const editor_metrics = @import("metrics.zig");

const FrameInput = render_input.FrameInput;
const editor_input_text_buffer_len = editor_state_types.input_text_buffer_len;
const editor_undo_capacity = editor_state_types.undo_capacity;
const EditorFieldEditCommand = editor_state_types.EditorFieldEditCommand;
const EditorTextInputState = editor_state_types.EditorTextInputState;
const EditorTextInputFrame = editor_state_types.EditorTextInputFrame;
const EditorTextInputFocusOptions = editor_state_types.EditorTextInputFocusOptions;
const EditorFrameState = editor_state_types.EditorFrameState;
pub const EditorState = editor_state_types.EditorState;
const EditorScrollBoundary = editor_state_types.EditorScrollBoundary;
const EditorUpdate = editor_state_types.EditorUpdate;
pub const EditorFieldSelection = editor_state_types.EditorFieldSelection;
const EditorStoredValue = editor_state_types.EditorStoredValue;
const EditorError = editor_state_types.EditorError;
const EditorSideWidths = editor_layout.SideWidths;
const editorViewportWidth = editor_layout.viewportWidth;
const editorDefaultSideWidths = editor_layout.defaultSideWidths;
const clampEditorSideWidths = editor_layout.clampSideWidths;
const editorSystemMaxScrollY = editor_metrics.editorSystemMaxScrollY;
const editorInspectorMaxScrollY = editor_metrics.editorInspectorMaxScrollY;
const editorEntityMaxScrollY = editor_metrics.editorEntityMaxScrollY;
const editor_system_scroll_smoothing = editor_theme.system_scroll_smoothing;
const editor_geometry_primitives = editor_theme.geometry_primitives;
const editor_color_channels = editor_theme.color_channels;
const editor_vec3_lane_labels = editor_theme.vec3_lane_labels;

pub fn validatedEditorSelection(world: *const runtime.World, selected: ?runtime.EntityHandle) ?runtime.EntityHandle {
    const entity = selected orelse return null;
    _ = world.entity(entity) catch return null;
    return entity;
}

pub fn validatedEditorFieldSelection(world: *const runtime.World, selected: ?runtime.EntityHandle, field: EditorFieldSelection) EditorFieldSelection {
    if (!field.active) {
        return .{};
    }
    const entity = selected orelse return .{};
    if (entity.index != field.entity.index or entity.generation != field.entity.generation) {
        return .{};
    }
    _ = world.entity(entity) catch return .{};
    if (!(world.hasComponent(entity, field.componentId()) catch false)) {
        return .{};
    }
    _ = world.getComponentFieldValue(entity, field.componentId(), field.fieldName()) catch return .{};
    return field;
}

pub fn validatedEditorTextInput(world: *const runtime.World, selected: ?runtime.EntityHandle, input: EditorTextInputState) EditorTextInputState {
    if (!input.active) {
        return .{};
    }
    const selection = validatedEditorFieldSelection(world, selected, input.selection);
    if (!selection.active or !selection.sameInput(input.selection)) {
        return .{};
    }
    var validated = input;
    validated.selection = selection;
    validated.cursor = @min(validated.cursor, validated.len);
    validated.selection_anchor = @min(validated.selection_anchor, validated.len);
    return validated;
}

pub fn editorFrameState(world: *const runtime.World, state: EditorState) EditorFrameState {
    const selected_entity = validatedEditorSelection(world, state.selected_entity);
    return .{
        .paused = state.paused,
        .selected_entity = selected_entity,
        .selected_property = validatedEditorFieldSelection(world, selected_entity, state.selected_property),
        .text_input = editorTextInputFrame(world, selected_entity, state.text_input),
        .dragging_axis = state.dragging_axis,
        .dragging_splitter = state.dragging_splitter,
        .system_scroll_y = state.system_scroll_y,
        .entity_scroll_y = state.entity_scroll_y,
        .inspector_scroll_y = state.inspector_scroll_y,
        .left_sidebar_width = state.left_sidebar_width,
        .right_sidebar_width = state.right_sidebar_width,
        .entity_count = world.entityCount(),
        .component_instance_count = world.componentInstanceCount(),
        .renderable_count = world.renderableMeshCount(),
    };
}

pub fn editorTextInputFrame(world: *const runtime.World, selected: ?runtime.EntityHandle, state: EditorTextInputState) EditorTextInputFrame {
    const validated = validatedEditorTextInput(world, selected, state);
    if (!validated.active) {
        return .{};
    }
    var frame = EditorTextInputFrame{
        .active = true,
        .selection = validated.selection,
        .len = validated.len,
        .cursor = validated.cursor,
        .selection_anchor = validated.selection_anchor,
    };
    @memcpy(frame.buffer[0..validated.len], validated.buffer[0..validated.len]);
    return frame;
}

pub fn clampEditorSystemScroll(state: *EditorState, input: FrameInput, profile_count: usize) void {
    const max_scroll_y = editorSystemMaxScrollY(input, profile_count);
    state.system_scroll_target_y = std.math.clamp(state.system_scroll_target_y, 0.0, max_scroll_y);
    state.system_scroll_y = std.math.clamp(state.system_scroll_y, 0.0, max_scroll_y);
}

pub fn clampEditorInspectorScroll(state: *EditorState, world: *const runtime.World, input: FrameInput) void {
    const max_scroll_y = editorInspectorMaxScrollY(world, input);
    state.inspector_scroll_target_y = std.math.clamp(state.inspector_scroll_target_y, 0.0, max_scroll_y);
    state.inspector_scroll_y = std.math.clamp(state.inspector_scroll_y, 0.0, max_scroll_y);
}

pub fn clampEditorEntityScroll(state: *EditorState, world: *const runtime.World, input: FrameInput) void {
    const max_scroll_y = editorEntityMaxScrollY(world, input);
    state.entity_scroll_target_y = std.math.clamp(state.entity_scroll_target_y, 0.0, max_scroll_y);
    state.entity_scroll_y = std.math.clamp(state.entity_scroll_y, 0.0, max_scroll_y);
}

pub fn applyEditorScrollRoute(
    scroll_y: *f32,
    scroll_target_y: *f32,
    scroll_boundary: *EditorScrollBoundary,
    route: ui_layout.ScrollWheelRoute,
    wheel_delta_y: f32,
) void {
    if (route.max_offset_y == 0.0) {
        scroll_y.* = 0.0;
        scroll_target_y.* = 0.0;
        return;
    }

    if (scroll_boundary.* == .top and wheel_delta_y > 0.0) {
        return;
    }
    if (scroll_boundary.* == .bottom and wheel_delta_y < 0.0) {
        return;
    }
    scroll_boundary.* = .none;

    scroll_target_y.* = route.next_offset[1];
    if (route.next_offset[1] <= 0.0 and wheel_delta_y > 0.0) {
        scroll_boundary.* = .top;
        return;
    }
    if (route.next_offset[1] >= route.max_offset_y and wheel_delta_y < 0.0) {
        scroll_boundary.* = .bottom;
        return;
    }
}

pub fn animateEditorScroll(scroll_y: *f32, scroll_target_y: *f32, delta_seconds: f32) void {
    if (!std.math.isFinite(scroll_y.*) or !std.math.isFinite(scroll_target_y.*)) {
        scroll_y.* = 0.0;
        scroll_target_y.* = 0.0;
        return;
    }

    const remaining = scroll_target_y.* - scroll_y.*;
    if (@abs(remaining) < 0.01) {
        scroll_y.* = scroll_target_y.*;
        return;
    }

    if (!std.math.isFinite(delta_seconds) or delta_seconds <= 0.0) {
        return;
    }

    const clamped_delta = @min(delta_seconds, 0.1);
    const alpha = 1.0 - @exp(-editor_system_scroll_smoothing * clamped_delta);
    scroll_y.* += remaining * alpha;
}

pub fn ensureEditorSidebarWidths(state: *EditorState, input: FrameInput) void {
    var widths = EditorSideWidths{
        .left = state.left_sidebar_width,
        .right = state.right_sidebar_width,
    };
    if (widths.left <= 0.0 or widths.right <= 0.0) {
        const defaults = editorDefaultSideWidths(editorViewportWidth(input));
        if (widths.left <= 0.0) {
            widths.left = defaults.left;
        }
        if (widths.right <= 0.0) {
            widths.right = defaults.right;
        }
    }
    widths = clampEditorSideWidths(widths, editorViewportWidth(input));
    state.left_sidebar_width = widths.left;
    state.right_sidebar_width = widths.right;
}

pub fn dragEditorSplitter(state: *EditorState, input: FrameInput) void {
    if (!state.has_last_pointer) {
        state.last_pointer = input.pointer.position;
        state.has_last_pointer = true;
        return;
    }
    const delta_x = input.pointer.position[0] - state.last_pointer[0];
    state.last_pointer = input.pointer.position;
    if (delta_x == 0.0) {
        return;
    }
    var widths = EditorSideWidths{
        .left = state.left_sidebar_width,
        .right = state.right_sidebar_width,
    };
    switch (state.dragging_splitter) {
        .none => return,
        .left => widths.left += delta_x,
        .right => widths.right -= delta_x,
    }
    widths = clampEditorSideWidths(widths, editorViewportWidth(input));
    state.left_sidebar_width = widths.left;
    state.right_sidebar_width = widths.right;
}

pub fn applyEditorKeyboardEdits(world: *runtime.World, state: *EditorState, input: FrameInput) EditorError!bool {
    if (state.text_input.active and try applyEditorTextInputEdits(world, state, input)) {
        return true;
    }
    if (input.keyboard.editor_undo_pressed) {
        return try undoEditorFieldEdit(world, state);
    }
    if (input.keyboard.editor_redo_pressed) {
        return try redoEditorFieldEdit(world, state);
    }
    return false;
}

pub fn applyEditorTextInputEdits(world: *runtime.World, state: *EditorState, input: FrameInput) EditorError!bool {
    state.text_input = validatedEditorTextInput(world, state.selected_entity, state.text_input);
    if (!state.text_input.active) {
        return false;
    }

    var consumed = false;
    if (input.keyboard.editor_select_all_pressed) {
        selectAllEditorTextInput(&state.text_input);
        consumed = true;
    }
    if (input.keyboard.editor_home_pressed) {
        moveEditorTextInputCursor(&state.text_input, 0, input.keyboard.shift_down);
        consumed = true;
    }
    if (input.keyboard.editor_end_pressed) {
        moveEditorTextInputCursor(&state.text_input, state.text_input.len, input.keyboard.shift_down);
        consumed = true;
    }
    if (input.keyboard.editor_left_pressed) {
        const next_cursor = if (!input.keyboard.shift_down and state.text_input.hasSelection())
            state.text_input.selectionStart()
        else
            previousEditorTextCursor(state.text_input.text(), state.text_input.cursor);
        moveEditorTextInputCursor(&state.text_input, next_cursor, input.keyboard.shift_down);
        consumed = true;
    }
    if (input.keyboard.editor_right_pressed) {
        const next_cursor = if (!input.keyboard.shift_down and state.text_input.hasSelection())
            state.text_input.selectionEnd()
        else
            nextEditorTextCursor(state.text_input.text(), state.text_input.cursor);
        moveEditorTextInputCursor(&state.text_input, next_cursor, input.keyboard.shift_down);
        consumed = true;
    }
    if (input.keyboard.editor_backspace_pressed) {
        editorTextInputBackspace(&state.text_input);
        consumed = true;
    }
    if (input.keyboard.editor_delete_pressed) {
        editorTextInputDelete(&state.text_input);
        consumed = true;
    }
    if (input.text_input_len > 0) {
        editorTextInputInsert(&state.text_input, input.textInput());
        consumed = true;
    }
    if (input.keyboard.editor_enter_pressed) {
        try commitEditorTextInput(world, state);
        return true;
    }
    return consumed;
}

pub fn focusEditorTextInput(world: *const runtime.World, state: *EditorState, selection: EditorFieldSelection, options: EditorTextInputFocusOptions) EditorError!void {
    const value = world.getComponentFieldValue(selection.entity, selection.componentId(), selection.fieldName()) catch return;
    const original = EditorStoredValue.from(value) orelse {
        std.log.err("editor text input focus skipped for {s}.{s}: value cannot be stored", .{ selection.componentId(), selection.fieldName() });
        return;
    };
    var text_input = EditorTextInputState{
        .active = true,
        .selection = selection,
        .original_value = original,
    };
    const text = formatEditorInputValue(&text_input.buffer, value, selection.vec3_lane) orelse {
        std.log.err("editor text input focus skipped for {s}.{s}: value cannot be formatted", .{ selection.componentId(), selection.fieldName() });
        return;
    };
    text_input.len = text.len;
    text_input.cursor = text.len;
    text_input.selection_anchor = if (options.select_all_on_focus) 0 else text.len;
    state.text_input = text_input;
    state.selected_property = selection;
}

pub fn editorTextInputFocusOptionsForProperty(world: *const runtime.World, selection: EditorFieldSelection) EditorTextInputFocusOptions {
    const value = world.getComponentFieldValue(selection.entity, selection.componentId(), selection.fieldName()) catch return .{};
    return .{ .select_all_on_focus = editorComponentValueSelectsAllOnFocus(value) };
}

pub fn editorComponentValueSelectsAllOnFocus(value: runtime.ComponentValue) bool {
    return switch (value) {
        .int, .float, .vec3 => true,
        .boolean, .string => false,
    };
}

pub fn applyEditorTypedControlClick(world: *runtime.World, state: *EditorState, selection: EditorFieldSelection) EditorError!bool {
    const old_value = world.getComponentFieldValue(selection.entity, selection.componentId(), selection.fieldName()) catch return false;
    const new_value = nextEditorTypedControlValue(selection, old_value) orelse return false;
    state.text_input = .{};
    try applyEditorFieldValue(world, state, selection, old_value, new_value);
    state.selected_property = selection;
    return true;
}

pub fn nextEditorTypedControlValue(selection: EditorFieldSelection, value: runtime.ComponentValue) ?runtime.ComponentValue {
    return switch (value) {
        .boolean => |payload| .{ .boolean = !payload },
        .string => |payload| if (editorPrimitiveSelectorNextValue(selection, payload)) |next|
            .{ .string = next }
        else
            null,
        else => null,
    };
}

pub fn editorPrimitiveSelectorNextValue(selection: EditorFieldSelection, value: []const u8) ?[]const u8 {
    if (!editorFieldIsPrimitiveSelector(selection.componentId(), selection.fieldName())) {
        return null;
    }
    for (editor_geometry_primitives, 0..) |primitive, index| {
        if (std.mem.eql(u8, primitive, value)) {
            return editor_geometry_primitives[(index + 1) % editor_geometry_primitives.len];
        }
    }
    return null;
}

pub fn editorFieldIsPrimitiveSelector(component_id: []const u8, field_name: []const u8) bool {
    return std.mem.eql(u8, component_id, runtime.geometry_primitive_component_id) and
        std.mem.eql(u8, field_name, "primitive");
}

pub fn editorFieldLooksLikeColor(field_name: []const u8) bool {
    return std.mem.indexOf(u8, field_name, "color") != null or
        std.mem.indexOf(u8, field_name, "colour") != null;
}

pub fn editorVec3LaneColor(lane: u2) [3]f32 {
    return editor_color_channels[@as(usize, lane)];
}

pub fn editorVec3LaneLabel(lane: u2) []const u8 {
    return editor_vec3_lane_labels[@as(usize, lane)];
}

pub fn commitEditorTextInput(world: *runtime.World, state: *EditorState) EditorError!void {
    state.text_input = validatedEditorTextInput(world, state.selected_entity, state.text_input);
    if (!state.text_input.active) {
        return;
    }
    const selection = state.text_input.selection;
    const current_value = world.getComponentFieldValue(selection.entity, selection.componentId(), selection.fieldName()) catch {
        state.text_input = .{};
        return;
    };
    const new_value = parseEditorInputValue(current_value, selection.vec3_lane, state.text_input.text()) catch {
        state.text_input = .{};
        return;
    };
    try applyEditorFieldValue(world, state, selection, state.text_input.original_value.componentValue(), new_value);
    state.selected_property = selection;
    state.text_input = .{};
}

pub fn blurEditorTextInput(world: *runtime.World, state: *EditorState) EditorError!void {
    if (state.text_input.active) {
        try commitEditorTextInput(world, state);
    }
}

pub fn formatEditorInputValue(buffer: *[editor_input_text_buffer_len]u8, value: runtime.ComponentValue, vec3_lane: u2) ?[]const u8 {
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

pub fn parseEditorInputValue(current_value: runtime.ComponentValue, vec3_lane: u2, text: []const u8) !runtime.ComponentValue {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    return switch (current_value) {
        .boolean => .{ .boolean = try parseEditorBool(trimmed) },
        .int => .{ .int = try std.fmt.parseInt(i32, trimmed, 10) },
        .float => .{ .float = try std.fmt.parseFloat(f32, trimmed) },
        .vec3 => |payload| blk: {
            var next = payload;
            next[vec3_lane] = try std.fmt.parseFloat(f32, trimmed);
            break :blk .{ .vec3 = next };
        },
        .string => .{ .string = text },
    };
}

pub fn parseEditorBool(text: []const u8) !bool {
    if (std.ascii.eqlIgnoreCase(text, "true") or std.mem.eql(u8, text, "1")) {
        return true;
    }
    if (std.ascii.eqlIgnoreCase(text, "false") or std.mem.eql(u8, text, "0")) {
        return false;
    }
    return error.InvalidCharacter;
}

pub fn editorTextInputInsert(input: *EditorTextInputState, value: []const u8) void {
    editorTextInputDeleteSelection(input);
    for (value) |byte| {
        if (input.len >= input.buffer.len) {
            break;
        }
        std.mem.copyBackwards(u8, input.buffer[input.cursor + 1 .. input.len + 1], input.buffer[input.cursor..input.len]);
        input.buffer[input.cursor] = byte;
        input.len += 1;
        input.cursor += 1;
        input.selection_anchor = input.cursor;
    }
    @memset(input.buffer[input.len..], 0);
}

pub fn editorTextInputBackspace(input: *EditorTextInputState) void {
    if (input.hasSelection()) {
        editorTextInputDeleteSelection(input);
        return;
    }
    if (input.cursor == 0) {
        return;
    }
    const previous = previousEditorTextCursor(input.text(), input.cursor);
    std.mem.copyForwards(u8, input.buffer[previous .. input.len - (input.cursor - previous)], input.buffer[input.cursor..input.len]);
    input.len -= input.cursor - previous;
    input.cursor = previous;
    input.selection_anchor = input.cursor;
    @memset(input.buffer[input.len..], 0);
}

pub fn editorTextInputDelete(input: *EditorTextInputState) void {
    if (input.hasSelection()) {
        editorTextInputDeleteSelection(input);
        return;
    }
    if (input.cursor >= input.len) {
        return;
    }
    const next = nextEditorTextCursor(input.text(), input.cursor);
    std.mem.copyForwards(u8, input.buffer[input.cursor .. input.len - (next - input.cursor)], input.buffer[next..input.len]);
    input.len -= next - input.cursor;
    input.selection_anchor = input.cursor;
    @memset(input.buffer[input.len..], 0);
}

pub fn editorTextInputDeleteSelection(input: *EditorTextInputState) void {
    if (!input.hasSelection()) {
        return;
    }
    const start = input.selectionStart();
    const end = input.selectionEnd();
    std.mem.copyForwards(u8, input.buffer[start .. input.len - (end - start)], input.buffer[end..input.len]);
    input.len -= end - start;
    input.cursor = start;
    input.selection_anchor = start;
    @memset(input.buffer[input.len..], 0);
}

pub fn moveEditorTextInputCursor(input: *EditorTextInputState, next_cursor: usize, extend_selection: bool) void {
    const clamped = @min(next_cursor, input.len);
    input.cursor = clamped;
    if (!extend_selection) {
        input.selection_anchor = clamped;
    }
}

pub fn selectAllEditorTextInput(input: *EditorTextInputState) void {
    input.selection_anchor = 0;
    input.cursor = input.len;
}

pub fn previousEditorTextCursor(text: []const u8, cursor: usize) usize {
    if (cursor == 0) {
        return 0;
    }
    var next = cursor - 1;
    while (next > 0 and (text[next] & 0b1100_0000) == 0b1000_0000) {
        next -= 1;
    }
    return next;
}

pub fn nextEditorTextCursor(text: []const u8, cursor: usize) usize {
    if (cursor >= text.len) {
        return text.len;
    }
    var next = cursor + 1;
    while (next < text.len and (text[next] & 0b1100_0000) == 0b1000_0000) {
        next += 1;
    }
    return next;
}

pub fn applyEditorFieldValue(
    world: *runtime.World,
    state: *EditorState,
    selected_property: EditorFieldSelection,
    old_value: runtime.ComponentValue,
    new_value: runtime.ComponentValue,
) EditorError!void {
    if (componentValuesEqual(old_value, new_value)) {
        return;
    }
    const old_stored = EditorStoredValue.from(old_value) orelse return error.InvalidScene;
    const new_stored = EditorStoredValue.from(new_value) orelse return error.InvalidScene;
    try world.setComponentFieldValue(selected_property.entity, selected_property.componentId(), selected_property.fieldName(), new_stored.componentValue());
    var command = EditorFieldEditCommand{
        .active = true,
        .entity = selected_property.entity,
        .old_value = old_stored,
        .new_value = new_stored,
    };
    if (!copyEditorBytes(&command.component_id, selected_property.componentId())) {
        return error.InvalidScene;
    }
    command.component_id_len = selected_property.component_id_len;
    if (!copyEditorBytes(&command.field_name, selected_property.fieldName())) {
        return error.InvalidScene;
    }
    command.field_name_len = selected_property.field_name_len;
    pushEditorUndo(state, command);
}

pub fn undoEditorFieldEdit(world: *runtime.World, state: *EditorState) EditorError!bool {
    if (state.undo_len == 0) {
        return false;
    }
    state.undo_len -= 1;
    const command = state.undo_stack[state.undo_len];
    if (!command.active) {
        return false;
    }
    world.setComponentFieldValue(command.entity, command.componentId(), command.fieldName(), command.old_value.componentValue()) catch return false;
    pushEditorRedo(state, command);
    state.selected_property = editorSelectionFromCommand(command);
    return true;
}

pub fn redoEditorFieldEdit(world: *runtime.World, state: *EditorState) EditorError!bool {
    if (state.redo_len == 0) {
        return false;
    }
    state.redo_len -= 1;
    const command = state.redo_stack[state.redo_len];
    if (!command.active) {
        return false;
    }
    world.setComponentFieldValue(command.entity, command.componentId(), command.fieldName(), command.new_value.componentValue()) catch return false;
    pushEditorUndoPreservingRedo(state, command);
    state.selected_property = editorSelectionFromCommand(command);
    return true;
}

pub fn pushEditorUndo(state: *EditorState, command: EditorFieldEditCommand) void {
    pushEditorUndoPreservingRedo(state, command);
    state.redo_len = 0;
}

pub fn pushEditorUndoPreservingRedo(state: *EditorState, command: EditorFieldEditCommand) void {
    pushEditorCommand(&state.undo_stack, &state.undo_len, command);
}

pub fn pushEditorRedo(state: *EditorState, command: EditorFieldEditCommand) void {
    pushEditorCommand(&state.redo_stack, &state.redo_len, command);
}

pub fn pushEditorCommand(stack: *[editor_undo_capacity]EditorFieldEditCommand, len: *usize, command: EditorFieldEditCommand) void {
    if (len.* == editor_undo_capacity) {
        std.mem.copyForwards(EditorFieldEditCommand, stack[0 .. editor_undo_capacity - 1], stack[1..editor_undo_capacity]);
        len.* -= 1;
    }
    stack[len.*] = command;
    len.* += 1;
}

pub fn editorSelectionFromCommand(command: EditorFieldEditCommand) EditorFieldSelection {
    var selection = EditorFieldSelection{
        .active = true,
        .entity = command.entity,
        .component_id_len = command.component_id_len,
        .field_name_len = command.field_name_len,
    };
    @memcpy(selection.component_id[0..command.component_id_len], command.componentId());
    @memcpy(selection.field_name[0..command.field_name_len], command.fieldName());
    return selection;
}

pub fn copyEditorBytes(target: anytype, value: []const u8) bool {
    const target_info = @typeInfo(@TypeOf(target)).pointer;
    const target_len = @typeInfo(target_info.child).array.len;
    if (value.len > target_len) {
        return false;
    }
    @memset(target[0..], 0);
    @memcpy(target[0..value.len], value);
    return true;
}

pub fn componentValuesEqual(a: runtime.ComponentValue, b: runtime.ComponentValue) bool {
    return switch (a) {
        .boolean => |payload| switch (b) {
            .boolean => |other| payload == other,
            else => false,
        },
        .int => |payload| switch (b) {
            .int => |other| payload == other,
            else => false,
        },
        .float => |payload| switch (b) {
            .float => |other| payload == other,
            else => false,
        },
        .vec3 => |payload| switch (b) {
            .vec3 => |other| payload[0] == other[0] and payload[1] == other[1] and payload[2] == other[2],
            else => false,
        },
        .string => |payload| switch (b) {
            .string => |other| std.mem.eql(u8, payload, other),
            else => false,
        },
    };
}

pub fn makeEditorFieldSelection(entity: runtime.EntityHandle, component_id: []const u8, field_name: []const u8, vec3_lane: u2) EditorError!EditorFieldSelection {
    var selection = EditorFieldSelection{
        .active = true,
        .entity = entity,
        .component_id_len = component_id.len,
        .field_name_len = field_name.len,
        .vec3_lane = vec3_lane,
    };
    if (!copyEditorBytes(&selection.component_id, component_id)) {
        return error.InvalidScene;
    }
    if (!copyEditorBytes(&selection.field_name, field_name)) {
        return error.InvalidScene;
    }
    return selection;
}
