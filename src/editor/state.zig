const std = @import("std");
const runtime = @import("../runtime.zig");

pub const component_id_buffer_len = 128;
pub const field_name_buffer_len = 64;
pub const input_text_buffer_len = 128;
pub const undo_capacity = 64;

pub const EditorAxis = enum {
    none,
    x,
    y,
    z,
};

pub const EditorFieldSelection = struct {
    active: bool = false,
    entity: runtime.EntityHandle = .{ .index = 0, .generation = 0 },
    component_id: [component_id_buffer_len]u8 = [_]u8{0} ** component_id_buffer_len,
    component_id_len: usize = 0,
    field_name: [field_name_buffer_len]u8 = [_]u8{0} ** field_name_buffer_len,
    field_name_len: usize = 0,
    vec3_lane: u2 = 0,

    pub fn componentId(self: *const EditorFieldSelection) []const u8 {
        return self.component_id[0..self.component_id_len];
    }

    pub fn fieldName(self: *const EditorFieldSelection) []const u8 {
        return self.field_name[0..self.field_name_len];
    }

    pub fn matches(self: *const EditorFieldSelection, entity: runtime.EntityHandle, component_id: []const u8, field_name: []const u8) bool {
        return self.active and
            self.entity.index == entity.index and
            self.entity.generation == entity.generation and
            std.mem.eql(u8, self.componentId(), component_id) and
            std.mem.eql(u8, self.fieldName(), field_name);
    }

    pub fn sameInput(self: *const EditorFieldSelection, other: EditorFieldSelection) bool {
        return self.active and
            other.active and
            self.entity.index == other.entity.index and
            self.entity.generation == other.entity.generation and
            self.vec3_lane == other.vec3_lane and
            std.mem.eql(u8, self.componentId(), other.componentId()) and
            std.mem.eql(u8, self.fieldName(), other.fieldName());
    }
};

pub const EditorStoredValue = union(runtime.FieldType) {
    boolean: bool,
    int: i32,
    float: f32,
    vec3: [3]f32,
    string: struct {
        buffer: [input_text_buffer_len]u8 = [_]u8{0} ** input_text_buffer_len,
        len: usize = 0,
    },

    pub fn from(value: runtime.ComponentValue) ?EditorStoredValue {
        return switch (value) {
            .boolean => |payload| .{ .boolean = payload },
            .int => |payload| .{ .int = payload },
            .float => |payload| .{ .float = payload },
            .vec3 => |payload| .{ .vec3 = payload },
            .string => |payload| blk: {
                if (payload.len > input_text_buffer_len) {
                    break :blk null;
                }
                var stored = EditorStoredValue{ .string = .{} };
                @memcpy(stored.string.buffer[0..payload.len], payload);
                stored.string.len = payload.len;
                break :blk stored;
            },
        };
    }

    pub fn componentValue(self: *const EditorStoredValue) runtime.ComponentValue {
        return switch (self.*) {
            .boolean => |payload| .{ .boolean = payload },
            .int => |payload| .{ .int = payload },
            .float => |payload| .{ .float = payload },
            .vec3 => |payload| .{ .vec3 = payload },
            .string => .{ .string = self.string.buffer[0..self.string.len] },
        };
    }
};

pub const EditorFieldEditCommand = struct {
    active: bool = false,
    entity: runtime.EntityHandle = .{ .index = 0, .generation = 0 },
    component_id: [component_id_buffer_len]u8 = [_]u8{0} ** component_id_buffer_len,
    component_id_len: usize = 0,
    field_name: [field_name_buffer_len]u8 = [_]u8{0} ** field_name_buffer_len,
    field_name_len: usize = 0,
    old_value: EditorStoredValue = .{ .boolean = false },
    new_value: EditorStoredValue = .{ .boolean = false },

    pub fn componentId(self: *const EditorFieldEditCommand) []const u8 {
        return self.component_id[0..self.component_id_len];
    }

    pub fn fieldName(self: *const EditorFieldEditCommand) []const u8 {
        return self.field_name[0..self.field_name_len];
    }
};

pub const EditorTextInputState = struct {
    active: bool = false,
    selection: EditorFieldSelection = .{},
    buffer: [input_text_buffer_len]u8 = [_]u8{0} ** input_text_buffer_len,
    len: usize = 0,
    cursor: usize = 0,
    selection_anchor: usize = 0,
    original_value: EditorStoredValue = .{ .boolean = false },

    pub fn text(self: *const EditorTextInputState) []const u8 {
        return self.buffer[0..self.len];
    }

    pub fn selectionStart(self: *const EditorTextInputState) usize {
        return @min(self.cursor, self.selection_anchor);
    }

    pub fn selectionEnd(self: *const EditorTextInputState) usize {
        return @max(self.cursor, self.selection_anchor);
    }

    pub fn hasSelection(self: *const EditorTextInputState) bool {
        return self.cursor != self.selection_anchor;
    }

    pub fn matches(self: *const EditorTextInputState, selection: EditorFieldSelection) bool {
        return self.active and self.selection.sameInput(selection);
    }
};

pub const EditorTextInputFrame = struct {
    active: bool = false,
    selection: EditorFieldSelection = .{},
    buffer: [input_text_buffer_len]u8 = [_]u8{0} ** input_text_buffer_len,
    len: usize = 0,
    cursor: usize = 0,
    selection_anchor: usize = 0,

    pub fn text(self: *const EditorTextInputFrame) []const u8 {
        return self.buffer[0..self.len];
    }

    pub fn selectionStart(self: *const EditorTextInputFrame) usize {
        return @min(self.cursor, self.selection_anchor);
    }

    pub fn selectionEnd(self: *const EditorTextInputFrame) usize {
        return @max(self.cursor, self.selection_anchor);
    }

    pub fn hasSelection(self: *const EditorTextInputFrame) bool {
        return self.cursor != self.selection_anchor;
    }

    pub fn matches(self: *const EditorTextInputFrame, selection: EditorFieldSelection) bool {
        return self.active and self.selection.sameInput(selection);
    }
};

pub const EditorTextInputFocusOptions = struct {
    select_all_on_focus: bool = false,
};

pub const EditorState = struct {
    paused: bool = false,
    selected_entity: ?runtime.EntityHandle = null,
    selected_property: EditorFieldSelection = .{},
    text_input: EditorTextInputState = .{},
    dragging_axis: EditorAxis = .none,
    dragging_splitter: EditorSplitter = .none,
    captured_pointer: bool = false,
    system_scroll_y: f32 = 0.0,
    system_scroll_target_y: f32 = 0.0,
    system_scroll_boundary: EditorScrollBoundary = .none,
    entity_scroll_y: f32 = 0.0,
    entity_scroll_target_y: f32 = 0.0,
    entity_scroll_boundary: EditorScrollBoundary = .none,
    inspector_scroll_y: f32 = 0.0,
    inspector_scroll_target_y: f32 = 0.0,
    inspector_scroll_boundary: EditorScrollBoundary = .none,
    left_sidebar_width: f32 = 0.0,
    right_sidebar_width: f32 = 0.0,
    last_pointer: [2]f32 = .{ 0.0, 0.0 },
    has_last_pointer: bool = false,
    undo_stack: [undo_capacity]EditorFieldEditCommand = [_]EditorFieldEditCommand{.{}} ** undo_capacity,
    undo_len: usize = 0,
    redo_stack: [undo_capacity]EditorFieldEditCommand = [_]EditorFieldEditCommand{.{}} ** undo_capacity,
    redo_len: usize = 0,
};

pub const EditorSplitter = enum {
    none,
    left,
    right,
};

pub const EditorScrollBoundary = enum {
    none,
    top,
    bottom,
};

pub const EditorFrameState = struct {
    paused: bool = false,
    selected_entity: ?runtime.EntityHandle = null,
    selected_property: EditorFieldSelection = .{},
    text_input: EditorTextInputFrame = .{},
    dragging_axis: EditorAxis = .none,
    dragging_splitter: EditorSplitter = .none,
    system_scroll_y: f32 = 0.0,
    entity_scroll_y: f32 = 0.0,
    inspector_scroll_y: f32 = 0.0,
    left_sidebar_width: f32 = 0.0,
    right_sidebar_width: f32 = 0.0,
    entity_count: usize = 0,
    component_instance_count: usize = 0,
    renderable_count: usize = 0,
};

pub const EditorUpdate = struct {
    consumed_pointer: bool = false,
    step_once: bool = false,
};

pub const EditorViewportBounds = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const EditorError = runtime.WorldError || error{InvalidScene};
