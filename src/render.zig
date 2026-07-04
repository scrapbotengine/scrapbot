const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const geometry = @import("geometry.zig");
const runtime = @import("runtime.zig");
const ui_layout = @import("ui_layout.zig");
const ui_font = @import("ui_font.zig");
const wgpu = @import("wgpu");

const is_supported_window_platform = builtin.os.tag == .macos or builtin.os.tag == .linux or builtin.os.tag == .windows;
const sdl = if (is_supported_window_platform) @cImport({
    @cInclude("sdl_bridge.h");
}) else struct {};

const output_width = 640;
const output_height = 480;
const output_extent = wgpu.Extent3D{
    .width = output_width,
    .height = output_height,
    .depth_or_array_layers = 1,
};
const output_bytes_per_row = 4 * output_width;
const output_size = output_bytes_per_row * output_height;
const depth_format = wgpu.TextureFormat.depth24_plus;
const shadow_depth_format = wgpu.TextureFormat.depth32_float;
const shadow_map_size = 1024;
const render_ui_button_state_component_id = "machina.render.internal.ui.button_state";
const render_ui_clip_component_id = "machina.render.internal.ui.clip";
const render_draw_batch_component_id = "machina.render.internal.draw.batch";
const render_draw_ui_component_id = "machina.render.internal.draw.ui";
const render_extract_system_id = "machina.render.extract";
const render_prepare_meshes_system_id = "machina.render.prepare_meshes";
const render_queue_meshes_system_id = "machina.render.queue_meshes";
const render_interact_ui_system_id = "machina.render.interact_ui";
const render_prepare_ui_system_id = "machina.render.prepare_ui";
const render_queue_ui_system_id = "machina.render.queue_ui";
const render_draw_meshes_system_id = "machina.render.draw_meshes";
const default_window_width = 1280;
const default_window_height = 720;
const editor_top_bar_height: f32 = 56.0;
const editor_bottom_bar_height: f32 = 60.0;
const editor_left_sidebar_target_width: f32 = 420.0;
const editor_left_sidebar_min_width: f32 = 260.0;
const editor_right_sidebar_target_width: f32 = 460.0;
const editor_right_sidebar_min_width: f32 = 300.0;
const editor_min_game_viewport_width: f32 = 320.0;
const editor_splitter_width: f32 = 2.0;
const editor_splitter_hit_width: f32 = 12.0;
const editor_performance_display_interval_ns: u64 = 333_000_000;
const live_run_default_delta_seconds: f32 = 1.0 / 60.0;
const live_run_max_delta_seconds: f32 = 0.1;
const editor_system_text_size: f32 = 1.0;
const editor_panel_padding_x: f32 = 16.0;
const editor_panel_padding_y: f32 = 22.0;
const editor_panel_section_gap: f32 = 18.0;
const editor_panel_label_gap: f32 = 10.0;
const editor_panel_bottom_padding: f32 = 18.0;
const editor_system_row_stride: f32 = 40.0;
const editor_system_row_label_padding_x: f32 = 16.0;
const editor_system_row_duration_padding_x: f32 = 16.0;
const editor_system_field_column_gap: f32 = 4.0;
const editor_system_card_padding_y: f32 = 16.0;
const editor_system_scroll_pixels_per_wheel: f32 = 18.0;
const editor_system_scroll_smoothing: f32 = 22.0;
const editor_entity_text_size: f32 = 1.0;
const editor_entity_row_stride: f32 = 34.0;
const editor_entity_row_label_padding_x: f32 = 16.0;
const editor_entity_row_component_padding_x: f32 = 16.0;
const editor_entity_field_column_gap: f32 = 4.0;
const editor_entity_card_padding_y: f32 = 14.0;
const editor_left_panel_gap: f32 = 8.0;
const editor_entity_panel_min_height: f32 = 160.0;
const editor_system_panel_min_height: f32 = 180.0;
const editor_scrollbar_width: f32 = 6.0;
const editor_scrollbar_gap: f32 = 10.0;
const render_system_profile_window_frames: usize = 120;
const editor_control_button_width: f32 = 104.0;
const editor_control_button_height: f32 = 36.0;
const editor_control_button_gap: f32 = 14.0;
const editor_panel_corner_radius: f32 = 16.0;
const editor_sidebar_panel_margin: f32 = 6.0;
const editor_button_corner_radius: f32 = 6.0;
const editor_command_play_toggle = "machina.editor.play_toggle";
const editor_command_step = "machina.editor.step";
const editor_command_splitter_left = "machina.editor.splitter.left";
const editor_command_splitter_right = "machina.editor.splitter.right";
const fly_camera_move_speed: f32 = 6.0;
const fly_camera_look_sensitivity: f32 = 0.0035;
const fly_camera_max_pitch: f32 = std.math.degreesToRadians(89.0);
const editor_inspector_text_size: f32 = 1.0;
const editor_inspector_line_stride: f32 = 28.0;
const editor_inspector_field_row_stride: f32 = 32.0;
const editor_inspector_card_gap: f32 = 0.0;
const editor_inspector_separator_height: f32 = 1.0;
const editor_inspector_card_padding_x: f32 = 16.0;
const editor_inspector_card_padding_y: f32 = 16.0;
const editor_inspector_field_value_column_x: f32 = 204.0;
const editor_inspector_field_column_gap: f32 = 8.0;
const editor_inspector_input_padding_x: f32 = 4.0;
const editor_inspector_input_gap: f32 = 6.0;
const editor_inspector_input_height: f32 = 28.0;
const editor_inspector_input_corner_radius: f32 = 5.0;
const editor_inspector_input_border_thickness: f32 = 1.0;
const editor_inspector_caret_width: f32 = 2.0;
const editor_inspector_selection_padding_y: f32 = 4.0;
const editor_component_id_buffer_len = 128;
const editor_field_name_buffer_len = 64;
const editor_input_text_buffer_len = 128;
const editor_undo_capacity = 64;
const editor_gizmo_axis_length: f32 = 1.25;
const editor_gizmo_axis_thickness: f32 = 0.035;
const editor_gizmo_pick_radius_px: f32 = 18.0;

const editor_palette = struct {
    const shell = [3]f32{ 0.008, 0.012, 0.024 };
    const panel = [3]f32{ 0.031, 0.041, 0.063 };
    const panel_muted = [3]f32{ 0.094, 0.116, 0.151 };
    const input = [3]f32{ 0.016, 0.023, 0.039 };
    const input_selection = [3]f32{ 0.063, 0.255, 0.337 };
    const accent = [3]f32{ 0.031, 0.431, 0.533 };
    const accent_soft = [3]f32{ 0.22, 0.714, 0.82 };
    const text = [3]f32{ 0.886, 0.91, 0.941 };
    const text_muted = [3]f32{ 0.58, 0.639, 0.722 };
    const text_dim = [3]f32{ 0.392, 0.455, 0.545 };
    const danger = [3]f32{ 0.82, 0.282, 0.282 };
    const info = [3]f32{ 0.49, 0.745, 0.933 };
    const primary = [3]f32{ 0.028, 0.324, 0.49 };
    const success = [3]f32{ 0.023, 0.471, 0.314 };
    const warning = [3]f32{ 0.714, 0.333, 0.031 };
};

pub const RenderError = error{
    NoAdapter,
    NoDevice,
    NoSurface,
    NoSurfaceFormat,
    SurfaceFailed,
    WindowingUnsupported,
    SdlInitFailed,
    WindowCreateFailed,
    MetalViewCreateFailed,
    MetalLayerMissing,
    NativeWindowHandleMissing,
    BufferMapFailed,
    OutOfMemory,
    InvalidScene,
};

pub const Stats = struct {
    renderables: usize,
    render_batches: usize,
    ui_rects: usize,
    ui_texts: usize,
};

pub const WindowOptions = struct {
    max_frames: ?u32 = null,
    editor: bool = false,
    scene_reload: ?SceneReloadHook = null,
    frame_update: ?FrameUpdateHook = null,
};

pub const Scene = struct {
    world: *const runtime.World,
};

pub const SceneReloadHook = struct {
    context: *anyopaque,
    poll: *const fn (context: *anyopaque) ?Scene,
};

pub const FrameUpdateHook = struct {
    context: *anyopaque,
    step: *const fn (context: *anyopaque, delta_seconds: f32, input: *FrameInput) void,
};

pub const PointerInput = struct {
    position: [2]f32 = .{ 0.0, 0.0 },
    delta: [2]f32 = .{ 0.0, 0.0 },
    has_position: bool = false,
    primary_down: bool = false,
    primary_pressed: bool = false,
    primary_released: bool = false,
    secondary_down: bool = false,
    secondary_pressed: bool = false,
    secondary_released: bool = false,
    wheel_delta: [2]f32 = .{ 0.0, 0.0 },

    fn beginFrame(self: *PointerInput) void {
        self.primary_pressed = false;
        self.primary_released = false;
        self.secondary_pressed = false;
        self.secondary_released = false;
        self.delta = .{ 0.0, 0.0 };
        self.wheel_delta = .{ 0.0, 0.0 };
    }
};

pub const KeyboardInput = struct {
    ctrl_down: bool = false,
    shift_down: bool = false,
    alt_down: bool = false,
    super_down: bool = false,
    move_forward: bool = false,
    move_back: bool = false,
    move_left: bool = false,
    move_right: bool = false,
    move_up: bool = false,
    move_down: bool = false,
    editor_toggle_pressed: bool = false,
    editor_undo_pressed: bool = false,
    editor_redo_pressed: bool = false,
    editor_left_pressed: bool = false,
    editor_right_pressed: bool = false,
    editor_home_pressed: bool = false,
    editor_end_pressed: bool = false,
    editor_backspace_pressed: bool = false,
    editor_delete_pressed: bool = false,
    editor_enter_pressed: bool = false,
    editor_select_all_pressed: bool = false,

    fn beginFrame(self: *KeyboardInput) void {
        self.editor_toggle_pressed = false;
        self.editor_undo_pressed = false;
        self.editor_redo_pressed = false;
        self.editor_left_pressed = false;
        self.editor_right_pressed = false;
        self.editor_home_pressed = false;
        self.editor_end_pressed = false;
        self.editor_backspace_pressed = false;
        self.editor_delete_pressed = false;
        self.editor_enter_pressed = false;
        self.editor_select_all_pressed = false;
    }
};

pub const EditorAxis = enum {
    none,
    x,
    y,
    z,
};

const EditorFieldSelection = struct {
    active: bool = false,
    entity: runtime.EntityHandle = .{ .index = 0, .generation = 0 },
    component_id: [editor_component_id_buffer_len]u8 = [_]u8{0} ** editor_component_id_buffer_len,
    component_id_len: usize = 0,
    field_name: [editor_field_name_buffer_len]u8 = [_]u8{0} ** editor_field_name_buffer_len,
    field_name_len: usize = 0,
    vec3_lane: u2 = 0,

    fn componentId(self: *const EditorFieldSelection) []const u8 {
        return self.component_id[0..self.component_id_len];
    }

    fn fieldName(self: *const EditorFieldSelection) []const u8 {
        return self.field_name[0..self.field_name_len];
    }

    fn matches(self: *const EditorFieldSelection, entity: runtime.EntityHandle, component_id: []const u8, field_name: []const u8) bool {
        return self.active and
            self.entity.index == entity.index and
            self.entity.generation == entity.generation and
            std.mem.eql(u8, self.componentId(), component_id) and
            std.mem.eql(u8, self.fieldName(), field_name);
    }

    fn sameInput(self: *const EditorFieldSelection, other: EditorFieldSelection) bool {
        return self.active and
            other.active and
            self.entity.index == other.entity.index and
            self.entity.generation == other.entity.generation and
            self.vec3_lane == other.vec3_lane and
            std.mem.eql(u8, self.componentId(), other.componentId()) and
            std.mem.eql(u8, self.fieldName(), other.fieldName());
    }
};

const EditorStoredValue = union(runtime.FieldType) {
    boolean: bool,
    int: i32,
    float: f32,
    vec3: [3]f32,
    string: struct {
        buffer: [editor_input_text_buffer_len]u8 = [_]u8{0} ** editor_input_text_buffer_len,
        len: usize = 0,
    },

    fn from(value: runtime.ComponentValue) ?EditorStoredValue {
        return switch (value) {
            .boolean => |payload| .{ .boolean = payload },
            .int => |payload| .{ .int = payload },
            .float => |payload| .{ .float = payload },
            .vec3 => |payload| .{ .vec3 = payload },
            .string => |payload| blk: {
                if (payload.len > editor_input_text_buffer_len) {
                    break :blk null;
                }
                var stored = EditorStoredValue{ .string = .{} };
                @memcpy(stored.string.buffer[0..payload.len], payload);
                stored.string.len = payload.len;
                break :blk stored;
            },
        };
    }

    fn componentValue(self: *const EditorStoredValue) runtime.ComponentValue {
        return switch (self.*) {
            .boolean => |payload| .{ .boolean = payload },
            .int => |payload| .{ .int = payload },
            .float => |payload| .{ .float = payload },
            .vec3 => |payload| .{ .vec3 = payload },
            .string => |payload| .{ .string = payload.buffer[0..payload.len] },
        };
    }
};

const EditorFieldEditCommand = struct {
    active: bool = false,
    entity: runtime.EntityHandle = .{ .index = 0, .generation = 0 },
    component_id: [editor_component_id_buffer_len]u8 = [_]u8{0} ** editor_component_id_buffer_len,
    component_id_len: usize = 0,
    field_name: [editor_field_name_buffer_len]u8 = [_]u8{0} ** editor_field_name_buffer_len,
    field_name_len: usize = 0,
    old_value: EditorStoredValue = .{ .boolean = false },
    new_value: EditorStoredValue = .{ .boolean = false },

    fn componentId(self: *const EditorFieldEditCommand) []const u8 {
        return self.component_id[0..self.component_id_len];
    }

    fn fieldName(self: *const EditorFieldEditCommand) []const u8 {
        return self.field_name[0..self.field_name_len];
    }
};

const EditorTextInputState = struct {
    active: bool = false,
    selection: EditorFieldSelection = .{},
    buffer: [editor_input_text_buffer_len]u8 = [_]u8{0} ** editor_input_text_buffer_len,
    len: usize = 0,
    cursor: usize = 0,
    selection_anchor: usize = 0,
    original_value: EditorStoredValue = .{ .boolean = false },

    fn text(self: *const EditorTextInputState) []const u8 {
        return self.buffer[0..self.len];
    }

    fn selectionStart(self: *const EditorTextInputState) usize {
        return @min(self.cursor, self.selection_anchor);
    }

    fn selectionEnd(self: *const EditorTextInputState) usize {
        return @max(self.cursor, self.selection_anchor);
    }

    fn hasSelection(self: *const EditorTextInputState) bool {
        return self.cursor != self.selection_anchor;
    }

    fn matches(self: *const EditorTextInputState, selection: EditorFieldSelection) bool {
        return self.active and self.selection.sameInput(selection);
    }
};

const EditorTextInputFrame = struct {
    active: bool = false,
    selection: EditorFieldSelection = .{},
    buffer: [editor_input_text_buffer_len]u8 = [_]u8{0} ** editor_input_text_buffer_len,
    len: usize = 0,
    cursor: usize = 0,
    selection_anchor: usize = 0,

    fn text(self: *const EditorTextInputFrame) []const u8 {
        return self.buffer[0..self.len];
    }

    fn selectionStart(self: *const EditorTextInputFrame) usize {
        return @min(self.cursor, self.selection_anchor);
    }

    fn selectionEnd(self: *const EditorTextInputFrame) usize {
        return @max(self.cursor, self.selection_anchor);
    }

    fn hasSelection(self: *const EditorTextInputFrame) bool {
        return self.cursor != self.selection_anchor;
    }

    fn matches(self: *const EditorTextInputFrame, selection: EditorFieldSelection) bool {
        return self.active and self.selection.sameInput(selection);
    }
};

const EditorTextInputFocusOptions = struct {
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
    undo_stack: [editor_undo_capacity]EditorFieldEditCommand = [_]EditorFieldEditCommand{.{}} ** editor_undo_capacity,
    undo_len: usize = 0,
    redo_stack: [editor_undo_capacity]EditorFieldEditCommand = [_]EditorFieldEditCommand{.{}} ** editor_undo_capacity,
    redo_len: usize = 0,
};

pub const EditorSplitter = enum {
    none,
    left,
    right,
};

const EditorCursorKind = enum {
    default,
    resize_ew,
};

const EditorScrollBoundary = enum {
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

pub const FrameInput = struct {
    pointer: PointerInput = .{},
    keyboard: KeyboardInput = .{},
    ui_visible: bool = true,
    debug_overlay_visible: bool = false,
    fps: f32 = 0.0,
    delta_seconds: f32 = 0.0,
    viewport_width: f32 = 0.0,
    viewport_height: f32 = 0.0,
    camera_override: ?runtime.Transform = null,
    editor: EditorFrameState = .{},
    system_profiles: []const runtime.SystemProfileSnapshot = &.{},
    system_profile_count_hint: usize = 0,
    text_input: [editor_input_text_buffer_len]u8 = [_]u8{0} ** editor_input_text_buffer_len,
    text_input_len: usize = 0,

    fn beginFrame(self: *FrameInput) void {
        self.pointer.beginFrame();
        self.keyboard.beginFrame();
        self.system_profile_count_hint = 0;
        self.text_input_len = 0;
        @memset(self.text_input[0..], 0);
    }

    fn appendTextInput(self: *FrameInput, value: []const u8) void {
        for (value) |byte| {
            if (self.text_input_len >= self.text_input.len) {
                break;
            }
            if (byte >= 32 and byte < 127) {
                self.text_input[self.text_input_len] = byte;
                self.text_input_len += 1;
            }
        }
    }

    fn textInput(self: *const FrameInput) []const u8 {
        return self.text_input[0..self.text_input_len];
    }
};

fn toggleDebugOverlay(input: *FrameInput) void {
    input.debug_overlay_visible = !input.debug_overlay_visible;
    input.keyboard.editor_toggle_pressed = true;
}

fn isEditorToggleShortcut(key: sdl.MachinaSdlKey, ctrl_down: bool) bool {
    return key == sdl.MACHINA_SDL_KEY_TAB and ctrl_down;
}

fn updateKeyboardModifiers(keyboard: *KeyboardInput, event: sdl.MachinaSdlEvent) void {
    keyboard.ctrl_down = event.ctrl_down != 0;
    keyboard.shift_down = event.shift_down != 0;
    keyboard.alt_down = event.alt_down != 0;
    keyboard.super_down = event.super_down != 0;
    keyboard.move_down = keyboard.ctrl_down;
}

fn updateKeyboardKeyState(keyboard: *KeyboardInput, key: sdl.MachinaSdlKey, down: bool) void {
    if (key == sdl.MACHINA_SDL_KEY_W) {
        keyboard.move_forward = down;
    } else if (key == sdl.MACHINA_SDL_KEY_S) {
        keyboard.move_back = down;
    } else if (key == sdl.MACHINA_SDL_KEY_A) {
        keyboard.move_left = down;
    } else if (key == sdl.MACHINA_SDL_KEY_D) {
        keyboard.move_right = down;
    } else if (key == sdl.MACHINA_SDL_KEY_SPACE) {
        keyboard.move_up = down;
    } else if (key == sdl.MACHINA_SDL_KEY_LCTRL or key == sdl.MACHINA_SDL_KEY_RCTRL) {
        keyboard.move_down = down;
    }
}

fn updateEditorKeyboardActions(keyboard: *KeyboardInput, event: sdl.MachinaSdlEvent) void {
    if (event.kind != sdl.MACHINA_SDL_EVENT_KEY_DOWN) {
        return;
    }
    if (event.key == sdl.MACHINA_SDL_KEY_LEFT) {
        keyboard.editor_left_pressed = true;
    } else if (event.key == sdl.MACHINA_SDL_KEY_RIGHT) {
        keyboard.editor_right_pressed = true;
    } else if (event.key == sdl.MACHINA_SDL_KEY_HOME) {
        keyboard.editor_home_pressed = true;
    } else if (event.key == sdl.MACHINA_SDL_KEY_END) {
        keyboard.editor_end_pressed = true;
    } else if (event.key == sdl.MACHINA_SDL_KEY_BACKSPACE) {
        keyboard.editor_backspace_pressed = true;
    } else if (event.key == sdl.MACHINA_SDL_KEY_DELETE) {
        keyboard.editor_delete_pressed = true;
    } else if (event.key == sdl.MACHINA_SDL_KEY_RETURN and event.repeat == 0) {
        keyboard.editor_enter_pressed = true;
    } else if (event.repeat == 0 and event.key == sdl.MACHINA_SDL_KEY_A and event.ctrl_down != 0) {
        keyboard.editor_select_all_pressed = true;
    } else if (event.repeat == 0 and event.key == sdl.MACHINA_SDL_KEY_Z and event.ctrl_down != 0 and event.shift_down == 0) {
        keyboard.editor_undo_pressed = true;
    } else if (event.repeat == 0 and event.key == sdl.MACHINA_SDL_KEY_Z and event.ctrl_down != 0 and event.shift_down != 0) {
        keyboard.editor_redo_pressed = true;
    } else if (event.repeat == 0 and event.key == sdl.MACHINA_SDL_KEY_Y and event.ctrl_down != 0) {
        keyboard.editor_redo_pressed = true;
    }
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

fn editorTextInputFrame(world: *const runtime.World, selected: ?runtime.EntityHandle, state: EditorTextInputState) EditorTextInputFrame {
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

fn clampEditorSystemScroll(state: *EditorState, input: FrameInput, profile_count: usize) void {
    const max_scroll_y = editorSystemMaxScrollY(input, profile_count);
    state.system_scroll_target_y = std.math.clamp(state.system_scroll_target_y, 0.0, max_scroll_y);
    state.system_scroll_y = std.math.clamp(state.system_scroll_y, 0.0, max_scroll_y);
}

fn clampEditorInspectorScroll(state: *EditorState, world: *const runtime.World, input: FrameInput) void {
    const max_scroll_y = editorInspectorMaxScrollY(world, input);
    state.inspector_scroll_target_y = std.math.clamp(state.inspector_scroll_target_y, 0.0, max_scroll_y);
    state.inspector_scroll_y = std.math.clamp(state.inspector_scroll_y, 0.0, max_scroll_y);
}

fn clampEditorEntityScroll(state: *EditorState, world: *const runtime.World, input: FrameInput) void {
    const max_scroll_y = editorEntityMaxScrollY(world, input);
    state.entity_scroll_target_y = std.math.clamp(state.entity_scroll_target_y, 0.0, max_scroll_y);
    state.entity_scroll_y = std.math.clamp(state.entity_scroll_y, 0.0, max_scroll_y);
}

fn applyEditorScrollRoute(
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

fn animateEditorScroll(scroll_y: *f32, scroll_target_y: *f32, delta_seconds: f32) void {
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

fn ensureEditorSidebarWidths(state: *EditorState, input: FrameInput) void {
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

fn dragEditorSplitter(state: *EditorState, input: FrameInput) void {
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

fn applyEditorKeyboardEdits(world: *runtime.World, state: *EditorState, input: FrameInput) EditorError!bool {
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

fn applyEditorTextInputEdits(world: *runtime.World, state: *EditorState, input: FrameInput) EditorError!bool {
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

fn focusEditorTextInput(world: *const runtime.World, state: *EditorState, selection: EditorFieldSelection, options: EditorTextInputFocusOptions) EditorError!void {
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

fn editorTextInputFocusOptionsForProperty(world: *const runtime.World, selection: EditorFieldSelection) EditorTextInputFocusOptions {
    const value = world.getComponentFieldValue(selection.entity, selection.componentId(), selection.fieldName()) catch return .{};
    return .{ .select_all_on_focus = editorComponentValueSelectsAllOnFocus(value) };
}

fn editorComponentValueSelectsAllOnFocus(value: runtime.ComponentValue) bool {
    return switch (value) {
        .int, .float, .vec3 => true,
        .boolean, .string => false,
    };
}

fn commitEditorTextInput(world: *runtime.World, state: *EditorState) EditorError!void {
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

fn blurEditorTextInput(world: *runtime.World, state: *EditorState) EditorError!void {
    if (state.text_input.active) {
        try commitEditorTextInput(world, state);
    }
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

fn parseEditorInputValue(current_value: runtime.ComponentValue, vec3_lane: u2, text: []const u8) !runtime.ComponentValue {
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

fn parseEditorBool(text: []const u8) !bool {
    if (std.ascii.eqlIgnoreCase(text, "true") or std.mem.eql(u8, text, "1")) {
        return true;
    }
    if (std.ascii.eqlIgnoreCase(text, "false") or std.mem.eql(u8, text, "0")) {
        return false;
    }
    return error.InvalidCharacter;
}

fn editorTextInputInsert(input: *EditorTextInputState, value: []const u8) void {
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

fn editorTextInputBackspace(input: *EditorTextInputState) void {
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

fn editorTextInputDelete(input: *EditorTextInputState) void {
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

fn editorTextInputDeleteSelection(input: *EditorTextInputState) void {
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

fn moveEditorTextInputCursor(input: *EditorTextInputState, next_cursor: usize, extend_selection: bool) void {
    const clamped = @min(next_cursor, input.len);
    input.cursor = clamped;
    if (!extend_selection) {
        input.selection_anchor = clamped;
    }
}

fn selectAllEditorTextInput(input: *EditorTextInputState) void {
    input.selection_anchor = 0;
    input.cursor = input.len;
}

fn previousEditorTextCursor(text: []const u8, cursor: usize) usize {
    if (cursor == 0) {
        return 0;
    }
    var next = cursor - 1;
    while (next > 0 and (text[next] & 0b1100_0000) == 0b1000_0000) {
        next -= 1;
    }
    return next;
}

fn nextEditorTextCursor(text: []const u8, cursor: usize) usize {
    if (cursor >= text.len) {
        return text.len;
    }
    var next = cursor + 1;
    while (next < text.len and (text[next] & 0b1100_0000) == 0b1000_0000) {
        next += 1;
    }
    return next;
}

fn applyEditorFieldValue(
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

fn undoEditorFieldEdit(world: *runtime.World, state: *EditorState) EditorError!bool {
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

fn redoEditorFieldEdit(world: *runtime.World, state: *EditorState) EditorError!bool {
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

fn pushEditorUndo(state: *EditorState, command: EditorFieldEditCommand) void {
    pushEditorUndoPreservingRedo(state, command);
    state.redo_len = 0;
}

fn pushEditorUndoPreservingRedo(state: *EditorState, command: EditorFieldEditCommand) void {
    pushEditorCommand(&state.undo_stack, &state.undo_len, command);
}

fn pushEditorRedo(state: *EditorState, command: EditorFieldEditCommand) void {
    pushEditorCommand(&state.redo_stack, &state.redo_len, command);
}

fn pushEditorCommand(stack: *[editor_undo_capacity]EditorFieldEditCommand, len: *usize, command: EditorFieldEditCommand) void {
    if (len.* == editor_undo_capacity) {
        std.mem.copyForwards(EditorFieldEditCommand, stack[0 .. editor_undo_capacity - 1], stack[1..editor_undo_capacity]);
        len.* -= 1;
    }
    stack[len.*] = command;
    len.* += 1;
}

fn editorSelectionFromCommand(command: EditorFieldEditCommand) EditorFieldSelection {
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

fn copyEditorBytes(target: anytype, value: []const u8) bool {
    const target_info = @typeInfo(@TypeOf(target)).pointer;
    const target_len = @typeInfo(target_info.child).array.len;
    if (value.len > target_len) {
        return false;
    }
    @memset(target[0..], 0);
    @memcpy(target[0..value.len], value);
    return true;
}

fn componentValuesEqual(a: runtime.ComponentValue, b: runtime.ComponentValue) bool {
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

pub fn updateEditorState(allocator: std.mem.Allocator, world: *runtime.World, state: *EditorState, input: FrameInput) EditorError!EditorUpdate {
    state.selected_entity = validatedEditorSelection(world, state.selected_entity);
    state.selected_property = validatedEditorFieldSelection(world, state.selected_entity, state.selected_property);
    state.text_input = validatedEditorTextInput(world, state.selected_entity, state.text_input);
    if (!input.debug_overlay_visible) {
        try blurEditorTextInput(world, state);
        state.dragging_axis = .none;
        state.dragging_splitter = .none;
        state.captured_pointer = false;
        state.has_last_pointer = false;
        return .{};
    }
    ensureEditorSidebarWidths(state, input);
    var effective_input = input;
    effective_input.editor.selected_entity = state.selected_entity;
    effective_input.editor.left_sidebar_width = state.left_sidebar_width;
    effective_input.editor.right_sidebar_width = state.right_sidebar_width;
    effective_input.editor.system_scroll_y = state.system_scroll_y;
    effective_input.editor.entity_scroll_y = state.entity_scroll_y;
    effective_input.editor.inspector_scroll_y = state.inspector_scroll_y;
    effective_input.editor.text_input = editorTextInputFrame(world, state.selected_entity, state.text_input);

    const profile_count = editorSystemProfileScrollCount(input);
    clampEditorSystemScroll(state, effective_input, profile_count);
    clampEditorEntityScroll(state, world, effective_input);
    clampEditorInspectorScroll(state, world, effective_input);

    const wheel_y = input.pointer.wheel_delta[1];
    const scroll_route = if (wheel_y != 0.0 and
        input.pointer.has_position and
        !std.math.isNan(input.pointer.position[0]) and
        !std.math.isNan(input.pointer.position[1]))
        try routeEditorScrollWheel(allocator, world, state, effective_input, profile_count, wheel_y)
    else
        null;

    if (wheel_y == 0.0 or scroll_route == null) {
        state.system_scroll_boundary = .none;
        state.entity_scroll_boundary = .none;
        state.inspector_scroll_boundary = .none;
    }

    if (scroll_route) |route| {
        switch (route) {
            .system_scroll => |scroll| {
                applyEditorScrollRoute(&state.system_scroll_y, &state.system_scroll_target_y, &state.system_scroll_boundary, scroll, wheel_y);
                animateEditorScroll(&state.system_scroll_y, &state.system_scroll_target_y, input.delta_seconds);
                animateEditorScroll(&state.entity_scroll_y, &state.entity_scroll_target_y, input.delta_seconds);
                animateEditorScroll(&state.inspector_scroll_y, &state.inspector_scroll_target_y, input.delta_seconds);
                return .{ .consumed_pointer = true };
            },
            .entity_scroll => |scroll| {
                applyEditorScrollRoute(&state.entity_scroll_y, &state.entity_scroll_target_y, &state.entity_scroll_boundary, scroll, wheel_y);
                animateEditorScroll(&state.system_scroll_y, &state.system_scroll_target_y, input.delta_seconds);
                animateEditorScroll(&state.entity_scroll_y, &state.entity_scroll_target_y, input.delta_seconds);
                animateEditorScroll(&state.inspector_scroll_y, &state.inspector_scroll_target_y, input.delta_seconds);
                return .{ .consumed_pointer = true };
            },
            .inspector_scroll => |scroll| {
                applyEditorScrollRoute(&state.inspector_scroll_y, &state.inspector_scroll_target_y, &state.inspector_scroll_boundary, scroll, wheel_y);
                animateEditorScroll(&state.system_scroll_y, &state.system_scroll_target_y, input.delta_seconds);
                animateEditorScroll(&state.entity_scroll_y, &state.entity_scroll_target_y, input.delta_seconds);
                animateEditorScroll(&state.inspector_scroll_y, &state.inspector_scroll_target_y, input.delta_seconds);
                return .{ .consumed_pointer = true };
            },
            else => {},
        }
    }

    animateEditorScroll(&state.system_scroll_y, &state.system_scroll_target_y, input.delta_seconds);
    animateEditorScroll(&state.entity_scroll_y, &state.entity_scroll_target_y, input.delta_seconds);
    animateEditorScroll(&state.inspector_scroll_y, &state.inspector_scroll_target_y, input.delta_seconds);

    if (try applyEditorKeyboardEdits(world, state, input)) {
        return .{ .consumed_pointer = true };
    }

    if (!input.pointer.has_position) {
        state.dragging_axis = .none;
        state.dragging_splitter = .none;
        state.has_last_pointer = false;
        return .{};
    }

    const release_consumes = input.pointer.primary_released and
        (state.captured_pointer or state.dragging_axis != .none or state.dragging_splitter != .none or hitEditorChrome(input));
    if (input.pointer.primary_released) {
        state.dragging_axis = .none;
        state.dragging_splitter = .none;
        state.captured_pointer = false;
        state.has_last_pointer = false;
    }

    if (state.dragging_splitter != .none and input.pointer.primary_down) {
        dragEditorSplitter(state, input);
        return .{ .consumed_pointer = true };
    }

    if (input.pointer.primary_pressed) {
        const picked_property = try pickEditorInspectorProperty(world, effective_input);
        if (state.text_input.active and (picked_property == null or !state.text_input.selection.sameInput(picked_property.?))) {
            try commitEditorTextInput(world, state);
            effective_input.editor.text_input = editorTextInputFrame(world, state.selected_entity, state.text_input);
        }
        if (try routeEditorUi(allocator, world, state.system_scroll_target_y, state.entity_scroll_target_y, state.inspector_scroll_target_y, effective_input, profile_count)) |route| {
            switch (route) {
                .splitter => |splitter| {
                    state.dragging_splitter = splitter;
                    state.captured_pointer = true;
                    state.last_pointer = input.pointer.position;
                    state.has_last_pointer = true;
                    return .{ .consumed_pointer = true };
                },
                .command => |command| {
                    state.captured_pointer = true;
                    return switch (command) {
                        .play_toggle => blk: {
                            state.paused = !state.paused;
                            break :blk .{ .consumed_pointer = true };
                        },
                        .step => blk: {
                            state.paused = true;
                            break :blk .{ .consumed_pointer = true, .step_once = true };
                        },
                    };
                },
                .entity_select => |entity| {
                    _ = world.entity(entity) catch {
                        state.captured_pointer = true;
                        return .{ .consumed_pointer = true };
                    };
                    state.selected_entity = entity;
                    state.selected_property = .{};
                    state.text_input = .{};
                    state.captured_pointer = true;
                    return .{ .consumed_pointer = true };
                },
                .system_scroll => {},
                .entity_scroll => {},
                .inspector_scroll => {},
            }
        }
        if (picked_property) |property| {
            try focusEditorTextInput(world, state, property, editorTextInputFocusOptionsForProperty(world, property));
            state.captured_pointer = true;
            return .{ .consumed_pointer = true };
        }
        if (hitEditorChrome(input)) {
            state.captured_pointer = true;
            return .{ .consumed_pointer = true };
        }

        if (state.selected_entity) |selected| {
            const axis = try pickEditorGizmoAxis(world, selected, input);
            if (axis != .none) {
                state.dragging_axis = axis;
                state.captured_pointer = true;
                state.last_pointer = input.pointer.position;
                state.has_last_pointer = true;
                return .{ .consumed_pointer = true };
            }
        }

        const previous_selection = state.selected_entity;
        state.selected_entity = try pickRenderableEntity(world, input);
        if (previous_selection == null or state.selected_entity == null or previous_selection.?.index != state.selected_entity.?.index or previous_selection.?.generation != state.selected_entity.?.generation) {
            state.selected_property = .{};
            state.text_input = .{};
        }
        state.captured_pointer = state.selected_entity != null;
        return .{ .consumed_pointer = state.selected_entity != null };
    }

    if (input.pointer.primary_down and state.dragging_axis != .none) {
        try dragSelectedEntity(world, state, input);
        return .{ .consumed_pointer = true };
    }

    if (release_consumes) {
        return .{ .consumed_pointer = true };
    }

    state.has_last_pointer = false;
    return .{};
}

pub fn stats(allocator: std.mem.Allocator, scene: Scene) RenderError!Stats {
    var state = try RenderEcsState.init(allocator);
    defer state.deinit();

    try state.extractScene(scene);
    var plan = try BatchPlan.build(allocator, &state.world);
    defer plan.deinit();

    return .{
        .renderables = state.world.renderableMeshCount(),
        .render_batches = plan.batches.len,
        .ui_rects = state.world.uiRectCount(),
        .ui_texts = state.world.uiTextCount(),
    };
}

const UiButtonState = struct {
    hovered: bool = false,
    held: bool = false,
    pressed: bool = false,
};

const UiClipRect = ui_layout.ClipRect;

const ScreenRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    fn position(self: ScreenRect) [3]f32 {
        return .{ self.x, self.y, 0.0 };
    }

    fn size3(self: ScreenRect) [3]f32 {
        return .{ self.width, self.height, 0.0 };
    }

    fn contains(self: ScreenRect, point: [2]f32) bool {
        return pointInsideScreenRect(point, .{ self.x, self.y }, .{ self.width, self.height });
    }
};

const UiCanvasTransform = ui_layout.CanvasTransform;

const UiBorder = struct {
    color: [3]f32,
    thickness: f32,
};

const UiProgressBar = struct {
    value: f32,
    max: f32,
    fill_color: [3]f32,
};

pub fn renderDemoBmp(io: Io, allocator: std.mem.Allocator, output_path: []const u8, scene: Scene) !void {
    try renderDemoBmpWithInput(io, allocator, output_path, scene, .{});
}

pub fn renderDemoBmpWithInput(io: Io, allocator: std.mem.Allocator, output_path: []const u8, scene: Scene, frame_input: FrameInput) !void {
    const instance = wgpu.Instance.create(null) orelse return RenderError.NoAdapter;
    defer instance.release();

    var gpu = try openGpu(instance, null);
    defer gpu.deinit();

    const texture_format = wgpu.TextureFormat.bgra8_unorm_srgb;
    const target_texture = gpu.device.createTexture(&wgpu.TextureDescriptor{
        .label = wgpu.StringView.fromSlice("Machina mesh target"),
        .size = output_extent,
        .format = texture_format,
        .usage = wgpu.TextureUsages.render_attachment | wgpu.TextureUsages.copy_src,
    }) orelse return RenderError.NoDevice;
    defer target_texture.release();

    const target_view = target_texture.createView(&wgpu.TextureViewDescriptor{
        .label = wgpu.StringView.fromSlice("Machina mesh target view"),
        .mip_level_count = 1,
        .array_layer_count = 1,
    }) orelse return RenderError.NoDevice;
    defer target_view.release();

    var demo = try MeshDemo.create(allocator, gpu.device, gpu.queue, texture_format, scene);
    defer demo.deinit();

    var depth = try DepthTarget.create(gpu.device, output_width, output_height);
    defer depth.deinit();

    const staging_buffer = gpu.device.createBuffer(&wgpu.BufferDescriptor{
        .label = wgpu.StringView.fromSlice("Machina mesh staging buffer"),
        .usage = wgpu.BufferUsages.map_read | wgpu.BufferUsages.copy_dst,
        .size = output_size,
        .mapped_at_creation = @as(u32, @intFromBool(false)),
    }) orelse return RenderError.NoDevice;
    defer staging_buffer.release();

    var input = frame_input;
    input.viewport_width = @floatFromInt(output_width);
    input.viewport_height = @floatFromInt(output_height);

    try demo.draw(gpu.device, gpu.queue, target_view, depth.view orelse return RenderError.NoDevice, .{
        .width = output_width,
        .height = output_height,
        .scene = scene,
        .input = input,
    });

    const encoder = gpu.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
        .label = wgpu.StringView.fromSlice("Machina mesh copy encoder"),
    }) orelse return RenderError.NoDevice;
    defer encoder.release();

    encoder.copyTextureToBuffer(
        &wgpu.TexelCopyTextureInfo{
            .origin = .{},
            .texture = target_texture,
        },
        &wgpu.TexelCopyBufferInfo{
            .layout = .{
                .bytes_per_row = output_bytes_per_row,
                .rows_per_image = output_height,
            },
            .buffer = staging_buffer,
        },
        &output_extent,
    );

    const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor{
        .label = wgpu.StringView.fromSlice("Machina mesh copy command buffer"),
    }) orelse return RenderError.NoDevice;
    defer command_buffer.release();

    const command_buffers = [_]*const wgpu.CommandBuffer{command_buffer};
    gpu.queue.submit(&command_buffers);

    var map_complete = false;
    var map_status: wgpu.MapAsyncStatus = .unknown;
    _ = staging_buffer.mapAsync(wgpu.MapModes.read, 0, output_size, .{
        .callback = handleBufferMap,
        .userdata1 = @ptrCast(&map_complete),
        .userdata2 = @ptrCast(&map_status),
    });

    instance.processEvents();
    while (!map_complete) {
        instance.processEvents();
    }

    if (map_status != .success) {
        return RenderError.BufferMapFailed;
    }

    const mapped: [*]u8 = @ptrCast(@alignCast(staging_buffer.getMappedRange(0, output_size) orelse return RenderError.BufferMapFailed));
    defer staging_buffer.unmap();

    try write24BitBmp(io, allocator, output_path, mapped[0..output_size]);
}

const WindowSurface = switch (builtin.os.tag) {
    .macos => MacWindowSurface,
    .linux => LinuxWindowSurface,
    .windows => WindowsWindowSurface,
    else => UnsupportedWindowSurface,
};

const UnsupportedWindowSurface = struct {
    surface: *wgpu.Surface,

    fn create(_: *wgpu.Instance, _: *anyopaque) RenderError!UnsupportedWindowSurface {
        return RenderError.WindowingUnsupported;
    }

    fn deinit(_: *UnsupportedWindowSurface) void {}
};

const MacWindowSurface = struct {
    surface: *wgpu.Surface,
    metal_view: *anyopaque,

    fn create(instance: *wgpu.Instance, window: *anyopaque) RenderError!MacWindowSurface {
        const metal_view = sdl.machina_sdl_create_metal_view(window) orelse return RenderError.MetalViewCreateFailed;
        errdefer sdl.machina_sdl_destroy_metal_view(metal_view);

        const metal_layer = sdl.machina_sdl_get_metal_layer(metal_view) orelse return RenderError.MetalLayerMissing;
        var surface_descriptor = wgpu.surfaceDescriptorFromMetalLayer(.{
            .label = "Machina window surface",
            .layer = metal_layer,
        });
        const surface = instance.createSurface(&surface_descriptor) orelse return RenderError.NoSurface;
        return .{
            .surface = surface,
            .metal_view = metal_view,
        };
    }

    fn deinit(self: *MacWindowSurface) void {
        self.surface.unconfigure();
        self.surface.release();
        sdl.machina_sdl_destroy_metal_view(self.metal_view);
        self.* = undefined;
    }
};

const LinuxWindowSurface = struct {
    surface: *wgpu.Surface,

    fn create(instance: *wgpu.Instance, window: *anyopaque) RenderError!LinuxWindowSurface {
        var wayland_display: ?*anyopaque = null;
        var wayland_surface: ?*anyopaque = null;
        if (sdl.machina_sdl_get_wayland_handles(window, &wayland_display, &wayland_surface) != 0) {
            var surface_descriptor = wgpu.surfaceDescriptorFromWaylandSurface(.{
                .label = "Machina window surface",
                .display = wayland_display orelse return RenderError.NativeWindowHandleMissing,
                .surface = wayland_surface orelse return RenderError.NativeWindowHandleMissing,
            });
            const surface = instance.createSurface(&surface_descriptor) orelse return RenderError.NoSurface;
            return .{ .surface = surface };
        }

        var x11_display: ?*anyopaque = null;
        var x11_window: u64 = 0;
        if (sdl.machina_sdl_get_x11_handles(window, &x11_display, &x11_window) != 0) {
            var surface_descriptor = wgpu.surfaceDescriptorFromXlibWindow(.{
                .label = "Machina window surface",
                .display = x11_display orelse return RenderError.NativeWindowHandleMissing,
                .window = x11_window,
            });
            const surface = instance.createSurface(&surface_descriptor) orelse return RenderError.NoSurface;
            return .{ .surface = surface };
        }

        return RenderError.NativeWindowHandleMissing;
    }

    fn deinit(self: *LinuxWindowSurface) void {
        self.surface.unconfigure();
        self.surface.release();
        self.* = undefined;
    }
};

const WindowsWindowSurface = struct {
    surface: *wgpu.Surface,

    fn create(instance: *wgpu.Instance, window: *anyopaque) RenderError!WindowsWindowSurface {
        var hinstance: ?*anyopaque = null;
        var hwnd: ?*anyopaque = null;
        if (sdl.machina_sdl_get_win32_handles(window, &hinstance, &hwnd) == 0) {
            return RenderError.NativeWindowHandleMissing;
        }
        var surface_descriptor = wgpu.surfaceDescriptorFromWindowsHWND(.{
            .label = "Machina window surface",
            .hinstance = hinstance orelse return RenderError.NativeWindowHandleMissing,
            .hwnd = hwnd orelse return RenderError.NativeWindowHandleMissing,
        });
        const surface = instance.createSurface(&surface_descriptor) orelse return RenderError.NoSurface;
        return .{ .surface = surface };
    }

    fn deinit(self: *WindowsWindowSurface) void {
        self.surface.unconfigure();
        self.surface.release();
        self.* = undefined;
    }
};

pub fn runDemoWindow(allocator: std.mem.Allocator, title: []const u8, options: WindowOptions, initial_scene: Scene) !void {
    if (!is_supported_window_platform) {
        return RenderError.WindowingUnsupported;
    }

    const title_z = try allocator.dupeZ(u8, title);
    defer allocator.free(title_z);

    if (sdl.machina_sdl_init_video() == 0) {
        return RenderError.SdlInitFailed;
    }
    defer sdl.machina_sdl_quit();

    const window = sdl.machina_sdl_create_window(title_z.ptr, default_window_width, default_window_height) orelse return RenderError.WindowCreateFailed;
    defer sdl.machina_sdl_destroy_window(window);
    _ = sdl.machina_sdl_start_text_input(window);

    const instance = wgpu.Instance.create(null) orelse return RenderError.NoAdapter;
    defer instance.release();

    var window_surface = try WindowSurface.create(instance, window);
    defer window_surface.deinit();
    const surface = window_surface.surface;

    var gpu = try openGpu(instance, surface);
    defer gpu.deinit();

    var capabilities: wgpu.SurfaceCapabilities = undefined;
    if (surface.getCapabilities(gpu.adapter, &capabilities) != .success) {
        return RenderError.SurfaceFailed;
    }
    defer capabilities.freeMembers();

    const surface_format = chooseSurfaceFormat(capabilities) orelse return RenderError.NoSurfaceFormat;
    var scene = initial_scene;
    var demo = try MeshDemo.create(allocator, gpu.device, gpu.queue, surface_format, scene);
    defer demo.deinit();
    var fly_camera = FlyCameraState{};

    var depth = DepthTarget{};
    defer depth.deinit();

    var width: u32 = 0;
    var height: u32 = 0;
    try configureSurfaceFromWindow(surface, gpu.device, window, surface_format, &width, &height);
    try depth.ensure(gpu.device, width, height);

    var running = true;
    var frame_count: u32 = 0;
    var input: FrameInput = .{ .debug_overlay_visible = options.editor };
    var relative_mouse_enabled = false;
    const resize_ew_cursor: ?*anyopaque = sdl.machina_sdl_create_resize_ew_cursor();
    defer if (resize_ew_cursor) |cursor| sdl.machina_sdl_destroy_cursor(cursor);
    var active_cursor_kind: EditorCursorKind = .default;
    var last_frame_ticks = sdl.machina_sdl_get_ticks_ns();
    var last_performance_display_ticks: u64 = 0;
    var smoothed_fps: f32 = 0.0;
    var displayed_fps: f32 = 0.0;
    while (running) {
        input.beginFrame();

        var event: sdl.MachinaSdlEvent = undefined;
        while (sdl.machina_sdl_poll_event(&event) != 0) {
            switch (event.kind) {
                sdl.MACHINA_SDL_EVENT_QUIT => running = false,
                sdl.MACHINA_SDL_EVENT_KEY_DOWN => {
                    updateKeyboardKeyState(&input.keyboard, event.key, true);
                    updateKeyboardModifiers(&input.keyboard, event);
                    updateEditorKeyboardActions(&input.keyboard, event);
                    if (event.repeat == 0 and isEditorToggleShortcut(event.key, event.ctrl_down != 0)) {
                        toggleDebugOverlay(&input);
                    }
                },
                sdl.MACHINA_SDL_EVENT_KEY_UP => {
                    updateKeyboardKeyState(&input.keyboard, event.key, false);
                    updateKeyboardModifiers(&input.keyboard, event);
                },
                sdl.MACHINA_SDL_EVENT_MOUSE_MOTION => {
                    updatePointerFromWindow(&input.pointer, window, event.x, event.y);
                    input.pointer.delta[0] += event.xrel;
                    input.pointer.delta[1] += event.yrel;
                },
                sdl.MACHINA_SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    updatePointerFromWindow(&input.pointer, window, event.x, event.y);
                    if (event.button == sdl.machina_sdl_button_left()) {
                        input.pointer.primary_down = true;
                        input.pointer.primary_pressed = true;
                    } else if (event.button == sdl.machina_sdl_button_right()) {
                        input.pointer.secondary_down = true;
                        input.pointer.secondary_pressed = true;
                    }
                },
                sdl.MACHINA_SDL_EVENT_MOUSE_BUTTON_UP => {
                    updatePointerFromWindow(&input.pointer, window, event.x, event.y);
                    if (event.button == sdl.machina_sdl_button_left()) {
                        input.pointer.primary_down = false;
                        input.pointer.primary_released = true;
                    } else if (event.button == sdl.machina_sdl_button_right()) {
                        input.pointer.secondary_down = false;
                        input.pointer.secondary_released = true;
                    }
                },
                sdl.MACHINA_SDL_EVENT_MOUSE_WHEEL => {
                    input.pointer.wheel_delta[0] += event.wheel_x;
                    input.pointer.wheel_delta[1] += event.wheel_y;
                },
                sdl.MACHINA_SDL_EVENT_TEXT_INPUT => {
                    input.appendTextInput(std.mem.sliceTo(event.text[0..], 0));
                },
                sdl.MACHINA_SDL_EVENT_WINDOW_RESIZED => {
                    try configureSurfaceFromWindow(surface, gpu.device, window, surface_format, &width, &height);
                    try depth.ensure(gpu.device, width, height);
                },
                else => {},
            }
        }

        if (!running) {
            break;
        }

        const frame_ticks = sdl.machina_sdl_get_ticks_ns();
        const elapsed_ns = if (frame_ticks > last_frame_ticks) frame_ticks - last_frame_ticks else 0;
        if (frame_ticks > last_frame_ticks) {
            last_frame_ticks = frame_ticks;
            const instant_fps = 1_000_000_000.0 / @as(f32, @floatFromInt(elapsed_ns));
            smoothed_fps = if (smoothed_fps == 0.0) instant_fps else smoothed_fps * 0.9 + instant_fps * 0.1;
            if (displayed_fps == 0.0 or frame_ticks - last_performance_display_ticks >= editor_performance_display_interval_ns) {
                displayed_fps = smoothed_fps;
                last_performance_display_ticks = frame_ticks;
            }
            input.fps = displayed_fps;
        }

        if (options.scene_reload) |reload| {
            if (reload.poll(reload.context)) |reloaded_scene| {
                const reloaded_demo = try MeshDemo.create(allocator, gpu.device, gpu.queue, surface_format, reloaded_scene);
                demo.deinit();
                demo = reloaded_demo;
                scene = reloaded_scene;
                fly_camera.reset();
            }
        }

        const delta_seconds = liveRunDeltaSecondsFromElapsedNs(elapsed_ns);
        input.delta_seconds = delta_seconds;
        input.viewport_width = @floatFromInt(width);
        input.viewport_height = @floatFromInt(height);
        input.system_profile_count_hint = demo.renderSystemProfileCount();
        const should_enable_relative_mouse = flyCameraInputActive(input);
        if (should_enable_relative_mouse != relative_mouse_enabled) {
            _ = sdl.machina_sdl_set_window_relative_mouse_mode(window, @intFromBool(should_enable_relative_mouse));
            relative_mouse_enabled = should_enable_relative_mouse;
        }
        input.camera_override = updateFlyCamera(&fly_camera, scene.world, input, delta_seconds) catch null;
        if (options.frame_update) |frame_update| {
            frame_update.step(frame_update.context, delta_seconds, &input);
        }
        const desired_cursor = if (relative_mouse_enabled) EditorCursorKind.default else editorCursorKind(allocator, input) catch .default;
        if (desired_cursor != active_cursor_kind) {
            setEditorCursor(desired_cursor, resize_ew_cursor);
            active_cursor_kind = desired_cursor;
        }

        try configureSurfaceFromWindow(surface, gpu.device, window, surface_format, &width, &height);
        try depth.ensure(gpu.device, width, height);
        try drawMeshToSurface(surface, gpu.device, gpu.queue, &demo, depth.view orelse return RenderError.NoDevice, .{
            .width = width,
            .height = height,
            .scene = scene,
            .input = input,
        });
        instance.processEvents();

        frame_count += 1;
        if (options.max_frames) |max_frames| {
            if (frame_count >= max_frames) {
                break;
            }
        }

        sdl.machina_sdl_delay_ms(1);
    }
    if (relative_mouse_enabled) {
        _ = sdl.machina_sdl_set_window_relative_mouse_mode(window, 0);
    }
}

const FrameConfig = struct {
    width: u32,
    height: u32,
    scene: Scene,
    input: FrameInput = .{},

    fn gameViewport(self: FrameConfig) ScreenRect {
        var input = self.input;
        input.viewport_width = @floatFromInt(self.width);
        input.viewport_height = @floatFromInt(self.height);
        return editorGameViewport(input);
    }
};

const InstanceConfig = struct {
    width: f32,
    height: f32,
    mesh: *const runtime.RenderableMesh,
    camera: CameraState,
    light_view_projection: [16]f32,
};

const CameraState = struct {
    transform: runtime.Transform = .{ .position = .{ 0.0, 0.0, 4.8 } },
    fov_y_degrees: f32 = 48.0,
    near: f32 = 0.1,
    far: f32 = 100.0,
};

const FlyCameraState = struct {
    initialized: bool = false,
    transform: runtime.Transform = .{},

    fn reset(self: *FlyCameraState) void {
        self.* = .{};
    }
};

const DirectionalLightState = struct {
    direction: [3]f32 = .{ 0.35, 0.68, 0.64 },
    color: [3]f32 = .{ 1.0, 1.0, 1.0 },
    intensity: f32 = 0.78,
    ambient: f32 = 0.18,
};

const RenderSystemContext = struct {
    device: *wgpu.Device,
    queue: *wgpu.Queue,
    target_view: *wgpu.TextureView,
    depth_view: *wgpu.TextureView,
    frame: FrameConfig,
};

const RenderSystemProfileState = struct {
    id: []const u8,
    phase: runtime.SystemPhase,
    samples_ns: [render_system_profile_window_frames]u64 = [_]u64{0} ** render_system_profile_window_frames,
    sample_count: usize = 0,
    next_sample: usize = 0,
    total_ns: u64 = 0,
    last_ns: u64 = 0,

    fn deinit(self: *RenderSystemProfileState, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        self.* = undefined;
    }

    fn record(self: *RenderSystemProfileState, duration_ns: u64) void {
        if (self.sample_count < render_system_profile_window_frames) {
            self.samples_ns[self.next_sample] = duration_ns;
            self.sample_count += 1;
            self.total_ns += duration_ns;
        } else {
            self.total_ns -= self.samples_ns[self.next_sample];
            self.samples_ns[self.next_sample] = duration_ns;
            self.total_ns += duration_ns;
        }

        self.next_sample = (self.next_sample + 1) % render_system_profile_window_frames;
        self.last_ns = duration_ns;
    }

    fn snapshot(self: RenderSystemProfileState) runtime.SystemProfileSnapshot {
        const average_ns = if (self.sample_count == 0) 0 else self.total_ns / self.sample_count;
        return .{
            .id = self.id,
            .phase = self.phase,
            .sample_count = @intCast(self.sample_count),
            .window_size = @intCast(render_system_profile_window_frames),
            .last_ns = self.last_ns,
            .rolling_average_ns = average_ns,
        };
    }
};

const RenderEcsState = struct {
    allocator: std.mem.Allocator,
    registry: runtime.ComponentRegistry,
    schedule: runtime.SystemSchedule,
    world: runtime.World,
    system_profiles: std.ArrayList(RenderSystemProfileState) = .empty,
    system_profile_snapshots: std.ArrayList(runtime.SystemProfileSnapshot) = .empty,
    combined_system_profile_snapshots: std.ArrayList(runtime.SystemProfileSnapshot) = .empty,
    display_system_profile_snapshots: std.ArrayList(runtime.SystemProfileSnapshot) = .empty,
    display_system_profile_ids: std.ArrayList([]u8) = .empty,
    last_display_system_profile_update_ns: i128 = 0,

    fn init(allocator: std.mem.Allocator) RenderError!RenderEcsState {
        var registry = runtime.ComponentRegistry.init(allocator);
        errdefer registry.deinit();

        registerRenderEcsTypes(&registry) catch |err| return mapEngineSetupError(err);

        var schedule = registry.buildSchedule(allocator, .render) catch |err| return mapEngineSetupError(err);
        errdefer schedule.deinit();

        var state = RenderEcsState{
            .allocator = allocator,
            .registry = registry,
            .schedule = schedule,
            .world = runtime.World.init(allocator),
        };
        errdefer state.deinit();
        try state.initializeSystemProfiles();
        return state;
    }

    fn deinit(self: *RenderEcsState) void {
        self.clearDisplaySystemProfileSnapshots();
        self.display_system_profile_ids.deinit(self.allocator);
        self.display_system_profile_snapshots.deinit(self.allocator);
        self.combined_system_profile_snapshots.deinit(self.allocator);
        self.system_profile_snapshots.deinit(self.allocator);
        self.clearSystemProfiles();
        self.system_profiles.deinit(self.allocator);
        self.world.deinit();
        self.schedule.deinit();
        self.registry.deinit();
        self.* = undefined;
    }

    fn systemProfileSnapshots(self: *RenderEcsState) []const runtime.SystemProfileSnapshot {
        self.system_profile_snapshots.clearRetainingCapacity();
        for (self.system_profiles.items) |profile| {
            self.system_profile_snapshots.appendAssumeCapacity(profile.snapshot());
        }
        return self.system_profile_snapshots.items;
    }

    fn combineSystemProfileSnapshots(
        self: *RenderEcsState,
        project_profiles: []const runtime.SystemProfileSnapshot,
    ) RenderError![]const runtime.SystemProfileSnapshot {
        const now_ns = monotonicTimestampNs();
        if (self.display_system_profile_snapshots.items.len > 0 and
            now_ns - self.last_display_system_profile_update_ns < @as(i128, editor_performance_display_interval_ns))
        {
            return self.display_system_profile_snapshots.items;
        }

        const render_profiles = self.systemProfileSnapshots();
        try self.refreshDisplaySystemProfileSnapshots(project_profiles, render_profiles);
        self.last_display_system_profile_update_ns = now_ns;
        return self.display_system_profile_snapshots.items;
    }

    fn refreshDisplaySystemProfileSnapshots(
        self: *RenderEcsState,
        project_profiles: []const runtime.SystemProfileSnapshot,
        render_profiles: []const runtime.SystemProfileSnapshot,
    ) RenderError!void {
        self.clearDisplaySystemProfileSnapshots();
        self.display_system_profile_snapshots.ensureTotalCapacity(self.allocator, project_profiles.len + render_profiles.len) catch return RenderError.OutOfMemory;
        self.display_system_profile_ids.ensureTotalCapacity(self.allocator, project_profiles.len + render_profiles.len) catch return RenderError.OutOfMemory;
        self.combined_system_profile_snapshots.clearRetainingCapacity();
        self.combined_system_profile_snapshots.ensureTotalCapacity(self.allocator, project_profiles.len + render_profiles.len) catch return RenderError.OutOfMemory;

        for (project_profiles) |profile| {
            try self.appendDisplaySystemProfileSnapshot(profile);
        }
        for (render_profiles) |profile| {
            try self.appendDisplaySystemProfileSnapshot(profile);
        }
    }

    fn appendDisplaySystemProfileSnapshot(self: *RenderEcsState, profile: runtime.SystemProfileSnapshot) RenderError!void {
        const owned_id = self.allocator.dupe(u8, profile.id) catch return RenderError.OutOfMemory;
        errdefer self.allocator.free(owned_id);
        self.display_system_profile_ids.appendAssumeCapacity(owned_id);
        const copied = runtime.SystemProfileSnapshot{
            .id = owned_id,
            .phase = profile.phase,
            .sample_count = profile.sample_count,
            .window_size = profile.window_size,
            .last_ns = profile.last_ns,
            .rolling_average_ns = profile.rolling_average_ns,
        };
        self.display_system_profile_snapshots.appendAssumeCapacity(copied);
        self.combined_system_profile_snapshots.appendAssumeCapacity(copied);
    }

    fn clearDisplaySystemProfileSnapshots(self: *RenderEcsState) void {
        for (self.display_system_profile_ids.items) |id| {
            self.allocator.free(id);
        }
        self.display_system_profile_ids.clearRetainingCapacity();
        self.display_system_profile_snapshots.clearRetainingCapacity();
        self.combined_system_profile_snapshots.clearRetainingCapacity();
    }

    fn initializeSystemProfiles(self: *RenderEcsState) RenderError!void {
        self.clearSystemProfiles();
        self.system_profile_snapshots.clearRetainingCapacity();
        self.combined_system_profile_snapshots.clearRetainingCapacity();
        self.clearDisplaySystemProfileSnapshots();
        self.last_display_system_profile_update_ns = 0;

        const system_count = self.schedule.systemCount();
        self.system_profiles.ensureTotalCapacity(self.allocator, system_count) catch return RenderError.OutOfMemory;
        self.system_profile_snapshots.ensureTotalCapacity(self.allocator, system_count) catch return RenderError.OutOfMemory;

        for (self.schedule.batches) |batch| {
            for (batch.systems) |system| {
                const owned_id = self.allocator.dupe(u8, system.id) catch return RenderError.OutOfMemory;
                self.system_profiles.appendAssumeCapacity(.{
                    .id = owned_id,
                    .phase = batch.phase,
                });
            }
        }
    }

    fn clearSystemProfiles(self: *RenderEcsState) void {
        for (self.system_profiles.items) |*profile| {
            profile.deinit(self.allocator);
        }
        self.system_profiles.clearRetainingCapacity();
    }

    fn recordSystemDuration(self: *RenderEcsState, system: runtime.ScheduledSystem, phase: runtime.SystemPhase, duration_ns: u64) void {
        for (self.system_profiles.items) |*profile| {
            if (profile.phase == phase and std.mem.eql(u8, profile.id, system.id)) {
                profile.record(duration_ns);
                return;
            }
        }
    }

    fn extractScene(self: *RenderEcsState, scene: Scene) RenderError!void {
        try self.extractSceneWithInput(scene, .{});
    }

    fn extractSceneWithInput(self: *RenderEcsState, scene: Scene, input: FrameInput) RenderError!void {
        var next_world = runtime.World.init(self.allocator);
        errdefer next_world.deinit();

        setRenderFrameInput(&next_world, input) catch |err| {
            std.log.err("render extract failed while setting frame input: {s}", .{@errorName(err)});
            return err;
        };

        var mesh_index: usize = 0;
        var meshes = scene.world.renderableMeshes();
        while (meshes.next()) |mesh| {
            extractMeshInto(self.allocator, &next_world, mesh_index, mesh) catch |err| {
                std.log.err("render extract failed while extracting mesh {d}: {s}", .{ mesh_index, @errorName(err) });
                return err;
            };
            mesh_index += 1;
        }

        if (input.debug_overlay_visible) {
            extractEditorGizmoInto(self.allocator, &next_world, scene.world, input) catch |err| {
                std.log.err("render extract failed while extracting editor gizmo: {s}", .{@errorName(err)});
                return err;
            };
        }

        if (input.ui_visible) {
            extractSceneUiInto(self.allocator, &next_world, scene.world) catch |err| {
                std.log.err("render extract failed while extracting scene UI: {s}", .{@errorName(err)});
                return err;
            };
        }

        if (input.debug_overlay_visible) {
            extractDebugOverlayInto(self.allocator, &next_world, input, scene.world) catch |err| {
                std.log.err("render extract failed while extracting editor overlay: {s}", .{@errorName(err)});
                return err;
            };
        }

        var render_camera = cameraState(scene.world) catch |err| {
            std.log.err("render extract failed while resolving camera: {s}", .{@errorName(err)});
            return err;
        };
        if (input.camera_override) |camera_transform| {
            render_camera.transform = camera_transform;
        }
        extractCameraInto(&next_world, render_camera) catch |err| {
            std.log.err("render extract failed while extracting camera: {s}", .{@errorName(err)});
            return err;
        };
        const light = directionalLightState(scene.world) catch |err| {
            std.log.err("render extract failed while resolving directional light: {s}", .{@errorName(err)});
            return err;
        };
        extractDirectionalLightInto(&next_world, light) catch |err| {
            std.log.err("render extract failed while extracting directional light: {s}", .{@errorName(err)});
            return err;
        };

        self.world.deinit();
        self.world = next_world;
    }

    fn updateUiInteractions(self: *RenderEcsState) RenderError!void {
        const input = try renderFrameInput(&self.world);
        if (!input.ui_visible) {
            return;
        }

        var cursor: usize = 0;
        const button_query = [_][]const u8{
            runtime.ui_rect_component_id,
            runtime.ui_button_component_id,
        };
        while (self.world.queryNext(&button_query, &cursor)) |entity| {
            const stored_entity = self.world.entity(entity) catch |err| return mapWorldError(err);
            const position = self.world.getVec3(entity, runtime.ui_rect_component_id, "position") catch |err| return mapWorldError(err);
            const size = self.world.getVec3(entity, runtime.ui_rect_component_id, "size") catch |err| return mapWorldError(err);
            const layout = try resolveUiLayout(&self.world, entity, position);
            const canvas_transform = if (input.viewport_width > 0.0 and input.viewport_height > 0.0)
                try sceneUiCanvasTransform(&self.world, input, input.viewport_width, input.viewport_height)
            else
                UiCanvasTransform{};
            const canvas_layout = applyUiCanvasLayout(canvas_transform, stored_entity.id, layout);
            const screen_size = if (isEditorUiEntityId(stored_entity.id)) size else scaleUiSize(canvas_transform, size);
            const screen_layout = try resolveUiScreenLayout(input, stored_entity.id, canvas_layout, screen_size);
            var interaction_position = screen_layout.position;
            var interaction_size = screen_size;
            var interaction_clip = screen_layout.clip;
            if (self.world.hasComponent(entity, runtime.ui_hit_area_component_id) catch |err| return mapWorldError(err)) {
                const hit_position = self.world.getVec3(entity, runtime.ui_hit_area_component_id, "position") catch |err| return mapWorldError(err);
                const hit_size = self.world.getVec3(entity, runtime.ui_hit_area_component_id, "size") catch |err| return mapWorldError(err);
                const hit_layout = try resolveUiLayout(&self.world, entity, hit_position);
                const hit_canvas_layout = applyUiCanvasLayout(canvas_transform, stored_entity.id, hit_layout);
                const hit_screen_size = if (isEditorUiEntityId(stored_entity.id)) hit_size else scaleUiSize(canvas_transform, hit_size);
                const hit_screen_layout = try resolveUiScreenLayout(input, stored_entity.id, hit_canvas_layout, hit_screen_size);
                interaction_position = hit_screen_layout.position;
                interaction_size = hit_screen_size;
                interaction_clip = hit_screen_layout.clip;
            }
            const state = evaluateUiButtonState(input, interaction_position, interaction_size, interaction_clip);
            try setRenderUiButtonState(&self.world, entity, state);
        }
    }

    fn queueBatchDraws(self: *RenderEcsState, batch_count: usize) RenderError!void {
        for (0..batch_count) |batch_index| {
            if (batch_index > std.math.maxInt(i32)) {
                return RenderError.InvalidScene;
            }
            const entity_id = std.fmt.allocPrint(self.allocator, "machina.render.draw.batch.{d}", .{batch_index}) catch return RenderError.OutOfMemory;
            defer self.allocator.free(entity_id);

            const entity = self.world.createEntity(entity_id, "Batch Draw") catch |err| return mapWorldError(err);
            const fields = [_]runtime.ComponentFieldValue{
                .{ .name = "batch_index", .value = .{ .int = @intCast(batch_index) } },
            };
            self.world.setComponent(entity, render_draw_batch_component_id, &fields) catch |err| return mapWorldError(err);
        }
    }

    fn queueUiDraw(self: *RenderEcsState) RenderError!void {
        if (self.world.uiRectCount() == 0 and self.world.uiTextCount() == 0) {
            return;
        }
        const entity = self.world.createEntity("machina.render.draw.ui", "UI Draw") catch |err| return mapWorldError(err);
        self.world.setComponent(entity, render_draw_ui_component_id, &.{}) catch |err| return mapWorldError(err);
    }

    fn drawCommandCount(self: RenderEcsState) usize {
        return self.world.componentInstanceCountFor(render_draw_batch_component_id);
    }

    fn uiDrawCommandCount(self: RenderEcsState) usize {
        return self.world.componentInstanceCountFor(render_draw_ui_component_id);
    }

    fn drawCommandBatchIndex(self: RenderEcsState, entity: runtime.EntityHandle) RenderError!usize {
        return batchIndexFromDrawEntity(&self.world, entity);
    }
};

const GpuContext = struct {
    adapter: *wgpu.Adapter,
    device: *wgpu.Device,
    queue: *wgpu.Queue,

    fn deinit(self: *GpuContext) void {
        self.queue.release();
        self.device.release();
        self.adapter.release();
    }
};

const DepthTarget = struct {
    texture: ?*wgpu.Texture = null,
    view: ?*wgpu.TextureView = null,
    width: u32 = 0,
    height: u32 = 0,

    fn create(device: *wgpu.Device, width: u32, height: u32) RenderError!DepthTarget {
        var target = DepthTarget{};
        try target.ensure(device, width, height);
        return target;
    }

    fn ensure(self: *DepthTarget, device: *wgpu.Device, width: u32, height: u32) RenderError!void {
        if (self.view != null and self.width == width and self.height == height) {
            return;
        }

        self.deinit();

        const texture = device.createTexture(&wgpu.TextureDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh depth texture"),
            .size = .{
                .width = width,
                .height = height,
                .depth_or_array_layers = 1,
            },
            .format = depth_format,
            .usage = wgpu.TextureUsages.render_attachment,
        }) orelse return RenderError.NoDevice;
        errdefer texture.release();

        const view = texture.createView(&wgpu.TextureViewDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh depth view"),
            .mip_level_count = 1,
            .array_layer_count = 1,
        }) orelse return RenderError.NoDevice;

        self.texture = texture;
        self.view = view;
        self.width = width;
        self.height = height;
    }

    fn deinit(self: *DepthTarget) void {
        if (self.view) |view| {
            view.release();
        }
        if (self.texture) |texture| {
            texture.release();
        }
        self.* = .{};
    }
};

const ShadowTarget = struct {
    texture: ?*wgpu.Texture = null,
    view: ?*wgpu.TextureView = null,

    fn create(device: *wgpu.Device) RenderError!ShadowTarget {
        const texture = device.createTexture(&wgpu.TextureDescriptor{
            .label = wgpu.StringView.fromSlice("Machina shadow map texture"),
            .size = .{
                .width = shadow_map_size,
                .height = shadow_map_size,
                .depth_or_array_layers = 1,
            },
            .format = shadow_depth_format,
            .usage = wgpu.TextureUsages.render_attachment | wgpu.TextureUsages.texture_binding,
        }) orelse return RenderError.NoDevice;
        errdefer texture.release();

        const view = texture.createView(&wgpu.TextureViewDescriptor{
            .label = wgpu.StringView.fromSlice("Machina shadow map view"),
            .mip_level_count = 1,
            .array_layer_count = 1,
            .aspect = .depth_only,
        }) orelse return RenderError.NoDevice;

        return .{
            .texture = texture,
            .view = view,
        };
    }

    fn deinit(self: *ShadowTarget) void {
        if (self.view) |view| {
            view.release();
        }
        if (self.texture) |texture| {
            texture.release();
        }
        self.* = .{};
    }
};

fn registerRenderEcsTypes(registry: *runtime.ComponentRegistry) !void {
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
        runtime.ui_vbox_component_id,
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
        runtime.ui_vbox_component_id,
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
        runtime.ui_vbox_component_id,
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
        runtime.ui_vbox_component_id,
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

fn extractMeshInto(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    render_index: usize,
    mesh: runtime.RenderableMesh,
) RenderError!void {
    const entity_id = std.fmt.allocPrint(allocator, "machina.render.extract.mesh.{d}", .{render_index}) catch return RenderError.OutOfMemory;
    defer allocator.free(entity_id);

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
}

fn extractEditorGizmoInto(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    scene_world: *const runtime.World,
    input: FrameInput,
) RenderError!void {
    const selected = input.editor.selected_entity orelse return;
    _ = scene_world.entity(selected) catch return;
    const selected_transform = (scene_world.getTransform(selected) catch return) orelse return;
    const axes = [_]struct {
        id: []const u8,
        axis: EditorAxis,
        position_offset: [3]f32,
        scale: [3]f32,
        color: [3]f32,
        active_color: [3]f32,
    }{
        .{
            .id = "x",
            .axis = .x,
            .position_offset = .{ editor_gizmo_axis_length * 0.5, 0.0, 0.0 },
            .scale = .{ editor_gizmo_axis_length, editor_gizmo_axis_thickness, editor_gizmo_axis_thickness },
            .color = editor_palette.danger,
            .active_color = .{ 0.94, 0.42, 0.42 },
        },
        .{
            .id = "y",
            .axis = .y,
            .position_offset = .{ 0.0, editor_gizmo_axis_length * 0.5, 0.0 },
            .scale = .{ editor_gizmo_axis_thickness, editor_gizmo_axis_length, editor_gizmo_axis_thickness },
            .color = editor_palette.success,
            .active_color = .{ 0.176, 0.667, 0.443 },
        },
        .{
            .id = "z",
            .axis = .z,
            .position_offset = .{ 0.0, 0.0, editor_gizmo_axis_length * 0.5 },
            .scale = .{ editor_gizmo_axis_thickness, editor_gizmo_axis_thickness, editor_gizmo_axis_length },
            .color = editor_palette.primary,
            .active_color = editor_palette.accent_soft,
        },
    };

    for (axes) |entry| {
        const entity_id = std.fmt.allocPrint(allocator, "machina.editor.gizmo.{s}", .{entry.id}) catch return RenderError.OutOfMemory;
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
            .base_color = if (input.editor.dragging_axis == entry.axis) entry.active_color else entry.color,
        }) catch |err| return mapWorldError(err);
    }
}

fn extractSceneUiInto(allocator: std.mem.Allocator, render_world: *runtime.World, scene_world: *const runtime.World) RenderError!void {
    for (0..scene_world.entityCount()) |index| {
        const source = runtime.EntityHandle{ .index = @intCast(index) };
        const stored = scene_world.entity(source) catch return RenderError.InvalidScene;
        if (!hasExtractableUiComponent(scene_world, source)) {
            continue;
        }

        const target = render_world.createEntity(stored.id, stored.name) catch |err| return mapWorldError(err);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_canvas_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_rect_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_border_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_text_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_button_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_hit_area_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_command_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_scroll_view_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_vbox_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_hgroup_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_stack_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_layout_item_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_spacer_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_text_block_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_toggle_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_progress_bar_component_id);
        try copyUiComponent(allocator, scene_world, render_world, source, target, runtime.ui_separator_component_id);
    }
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
        (world.hasComponent(entity, runtime.ui_vbox_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_hgroup_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_stack_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_layout_item_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_spacer_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_text_block_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_toggle_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_progress_bar_component_id) catch false) or
        (world.hasComponent(entity, runtime.ui_separator_component_id) catch false);
}

fn copyUiComponent(
    allocator: std.mem.Allocator,
    source_world: *const runtime.World,
    target_world: *runtime.World,
    source: runtime.EntityHandle,
    target: runtime.EntityHandle,
    component_id: []const u8,
) RenderError!void {
    if (!(source_world.hasComponent(source, component_id) catch |err| return mapWorldError(err))) {
        return;
    }

    var fields: std.ArrayList(runtime.ComponentFieldValue) = .empty;
    defer fields.deinit(allocator);

    const field_count = source_world.componentFieldCount(component_id);
    fields.ensureTotalCapacity(allocator, field_count) catch return RenderError.OutOfMemory;
    for (0..field_count) |field_index| {
        const field_name = source_world.componentFieldNameAt(component_id, field_index) orelse return RenderError.InvalidScene;
        const value = source_world.getComponentFieldValue(source, component_id, field_name) catch |err| return mapWorldError(err);
        fields.appendAssumeCapacity(.{
            .name = field_name,
            .value = value,
        });
    }

    target_world.setComponent(target, component_id, fields.items) catch |err| return mapWorldError(err);
}

const EditorVBox = struct {
    allocator: std.mem.Allocator,
    world: *runtime.World,
    id_prefix: []const u8,
    x: f32,
    y: f32,
    row_stride: f32,
    layout_parent: ?[]const u8 = null,
    row: usize = 0,

    fn init(
        allocator: std.mem.Allocator,
        world: *runtime.World,
        id_prefix: []const u8,
        x: f32,
        y: f32,
        row_stride: f32,
    ) EditorVBox {
        return .{
            .allocator = allocator,
            .world = world,
            .id_prefix = id_prefix,
            .x = x,
            .y = y,
            .row_stride = row_stride,
        };
    }

    fn withLayoutParent(self: EditorVBox, parent: []const u8) EditorVBox {
        var copy = self;
        copy.layout_parent = parent;
        return copy;
    }

    fn text(self: *EditorVBox, name: []const u8, value: []const u8, size: f32, color: [3]f32) RenderError!void {
        const entity_id = std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ self.id_prefix, self.row }) catch return RenderError.OutOfMemory;
        defer self.allocator.free(entity_id);
        const entity = self.world.createEntity(entity_id, name) catch |err| return mapWorldError(err);
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

fn extractEditorShellInto(allocator: std.mem.Allocator, world: *runtime.World, input: FrameInput) RenderError!void {
    const top = editorTopBarRect(input);
    const bottom = editorBottomBarRect(input);
    const body = editorBodyRect(input);
    const layout = editorBodyLayout(input);
    const game_viewport = editorGameViewport(input);
    const hovered_splitter = routeEditorSplitterAt(allocator, input) catch null;

    try extractEditorShellRect(world, "machina.editor.shell.top_bar", top, editor_palette.shell);
    try extractEditorShellRect(world, "machina.editor.shell.bottom_bar", bottom, editor_palette.shell);

    const body_group = world.createEntity("machina.editor.shell.body", "Editor Body HGroup") catch |err| return mapWorldError(err);
    world.setUiHGroup(body_group, .{
        .position = body.position(),
        .size = body.size3(),
        .spacing = 0.0,
        .padding = .{ 0.0, 0.0, 0.0 },
    }) catch |err| return mapWorldError(err);

    try extractEditorShellLayoutRect(world, "machina.editor.shell.left_sidebar", "Editor Left Sidebar", layout.left.size3(), 0, editor_palette.panel);
    try extractEditorShellLayoutSplitter(world, input, "machina.editor.shell.splitter.left", "Editor Left Splitter", layout.left_splitter.size3(), 1, .left, hovered_splitter);
    try extractEditorSplitterHitTarget(world, input, .left);
    try extractEditorShellLayoutSpacer(world, "machina.editor.shell.game_viewport", "Editor Game Viewport Slot", .{ editor_min_game_viewport_width, body.height, 0.0 }, 2, 1.0);
    try extractEditorShellLayoutSplitter(world, input, "machina.editor.shell.splitter.right", "Editor Right Splitter", layout.right_splitter.size3(), 3, .right, hovered_splitter);
    try extractEditorSplitterHitTarget(world, input, .right);
    try extractEditorShellLayoutRect(world, "machina.editor.shell.right_sidebar", "Editor Right Sidebar", layout.right.size3(), 4, editor_palette.panel);

    const frame_color = editor_palette.panel_muted;
    try extractEditorShellRect(world, "machina.editor.shell.viewport.border.bottom", .{
        .x = game_viewport.x,
        .y = game_viewport.y + game_viewport.height - 2.0,
        .width = game_viewport.width,
        .height = 2.0,
    }, frame_color);
}

fn extractEditorSplitterHitTarget(world: *runtime.World, input: FrameInput, splitter: EditorSplitter) RenderError!void {
    const visual = editorSplitterRect(input, splitter) orelse return;
    const hit_rect = editorSplitterHitRect(input, splitter) orelse return;
    const id = switch (splitter) {
        .none => return,
        .left => "machina.editor.shell.splitter.left.hit_area",
        .right => "machina.editor.shell.splitter.right.hit_area",
    };
    const name = switch (splitter) {
        .none => return,
        .left => "Editor Left Splitter Hit Area",
        .right => "Editor Right Splitter Hit Area",
    };
    const parent = switch (splitter) {
        .none => return,
        .left => "machina.editor.shell.splitter.left",
        .right => "machina.editor.shell.splitter.right",
    };
    const command = switch (splitter) {
        .none => return,
        .left => editor_command_splitter_left,
        .right => editor_command_splitter_right,
    };
    const entity = world.createEntity(id, name) catch |err| return mapWorldError(err);
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
    const entity = world.createEntity(id, "Editor Shell Rect") catch |err| return mapWorldError(err);
    world.setUiRect(entity, .{
        .position = rect.position(),
        .size = rect.size3(),
        .color = color,
        .corner_radius = 0.0,
    }) catch |err| return mapWorldError(err);
}

fn extractEditorShellLayoutRect(world: *runtime.World, id: []const u8, name: []const u8, size: [3]f32, order: i32, color: [3]f32) RenderError!void {
    const entity = world.createEntity(id, name) catch |err| return mapWorldError(err);
    world.setUiRect(entity, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = size,
        .color = color,
        .corner_radius = 0.0,
    }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(entity, .{
        .parent = "machina.editor.shell.body",
        .order = order,
        .@"align" = "fill",
    }) catch |err| return mapWorldError(err);
}

fn extractEditorShellLayoutSeparator(world: *runtime.World, id: []const u8, name: []const u8, size: [3]f32, order: i32, color: [3]f32) RenderError!void {
    const entity = world.createEntity(id, name) catch |err| return mapWorldError(err);
    world.setUiSeparator(entity, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = size,
        .color = color,
    }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(entity, .{
        .parent = "machina.editor.shell.body",
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

fn extractEditorShellLayoutSpacer(world: *runtime.World, id: []const u8, name: []const u8, min_size: [3]f32, order: i32, grow: f32) RenderError!void {
    const entity = world.createEntity(id, name) catch |err| return mapWorldError(err);
    world.setUiSpacer(entity, .{ .size = .{ 0.0, 0.0, 0.0 } }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(entity, .{
        .parent = "machina.editor.shell.body",
        .order = order,
        .min_size = min_size,
        .grow = grow,
        .@"align" = "fill",
    }) catch |err| return mapWorldError(err);
}

fn extractDebugOverlayInto(
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

    const canvas = world.createEntity("machina.editor.debug.canvas", "Editor Debug Canvas") catch |err| return mapWorldError(err);
    world.setUiCanvas(canvas, .{}) catch |err| return mapWorldError(err);

    _ = try extractEditorPanel(world, "machina.editor.debug.panel", "Editor Debug Panel", .{
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
    const header = world.createEntity("machina.editor.debug.systems.header", "Editor Debug Systems Header") catch |err| return mapWorldError(err);
    world.setUiText(header, .{
        .position = editorPanelTextPosition(panel, editorSystemHeaderY(input) - panel.y),
        .size = editor_system_text_size,
        .color = editor_palette.text_muted,
        .value = header_text,
    }) catch |err| return mapWorldError(err);

    const list_clip = editorSystemListClipRect(input);
    const system_scroll = world.createEntity("machina.editor.debug.systems.scroll", "Editor Debug Systems Scroll View") catch |err| return mapWorldError(err);
    world.setUiScrollView(system_scroll, .{
        .position = list_clip.position,
        .size = list_clip.size,
        .content_offset = .{ 0.0, input.editor.system_scroll_y, 0.0 },
    }) catch |err| return mapWorldError(err);

    const row_width = list_clip.size[0];
    const table_height = editorSystemTableContentHeight(input.system_profiles.len);
    const system_table = world.createEntity("machina.editor.debug.systems.table", "Editor Debug Systems Table") catch |err| return mapWorldError(err);
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
        .parent = "machina.editor.debug.systems.scroll",
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

        const label_id = std.fmt.allocPrint(allocator, "machina.editor.debug.systems.row.{d}.label", .{profile_index}) catch return RenderError.OutOfMemory;
        defer allocator.free(label_id);
        _ = try extractEditorChildText(world, label_id, "Editor System Row Label", "machina.editor.debug.systems.table", .{
            editor_system_row_label_padding_x,
            row_y,
            0.0,
        }, label_text, editor_system_text_size, editor_palette.text);

        const duration_id = std.fmt.allocPrint(allocator, "machina.editor.debug.systems.row.{d}.duration", .{profile_index}) catch return RenderError.OutOfMemory;
        defer allocator.free(duration_id);
        _ = try extractEditorChildText(world, duration_id, "Editor System Row Duration", "machina.editor.debug.systems.table", .{
            duration_x,
            row_y,
            0.0,
        }, duration_text, editor_system_text_size, editor_palette.text_muted);
    }

    try extractEditorSystemScrollbarInto(world, input, list_clip);
    try extractEditorEntityListInto(allocator, world, scene_world, input);
    try extractEditorComponentInspectorInto(allocator, world, scene_world, input);
}

fn extractEditorTopBarInto(allocator: std.mem.Allocator, world: *runtime.World, input: FrameInput) RenderError!void {
    const top = editorTopBarRect(input);
    const title = world.createEntity("machina.editor.top.title", "Editor Top Title") catch |err| return mapWorldError(err);
    world.setUiText(title, .{
        .position = .{ editor_panel_padding_x, top.y + 14.0, 0.0 },
        .size = 1.0,
        .color = editor_palette.text_muted,
        .value = "MACHINA",
    }) catch |err| return mapWorldError(err);

    const fps_text = formatFpsLabel(allocator, input.fps) catch return RenderError.OutOfMemory;
    defer allocator.free(fps_text);
    const fps = world.createEntity("machina.editor.debug.fps", "Editor Debug FPS") catch |err| return mapWorldError(err);
    world.setUiText(fps, .{
        .position = .{ 150.0, top.y + 14.0, 0.0 },
        .size = editor_system_text_size,
        .color = editor_palette.text,
        .value = fps_text,
    }) catch |err| return mapWorldError(err);

    try extractEditorPlaybackControlsInto(world, input);
}

fn extractEditorBottomBarInto(allocator: std.mem.Allocator, world: *runtime.World, input: FrameInput) RenderError!void {
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
    const status_text = world.createEntity("machina.editor.bottom.status", "Editor Bottom Status") catch |err| return mapWorldError(err);
    world.setUiText(status_text, .{
        .position = .{ editor_panel_padding_x, bottom.y + 14.0, 0.0 },
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

fn extractEditorButtonInto(
    world: *runtime.World,
    spec: EditorButtonSpec,
    label: []const u8,
    color: [3]f32,
) RenderError!void {
    const button = world.createEntity(spec.id, spec.name) catch |err| return mapWorldError(err);
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
    const text = world.createEntity(label_id, label_name) catch |err| return mapWorldError(err);
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
    const track = world.createEntity("machina.editor.debug.systems.scrollbar.track", "Editor System Scrollbar Track") catch |err| return mapWorldError(err);
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

    const thumb = world.createEntity("machina.editor.debug.systems.scrollbar.thumb", "Editor System Scrollbar Thumb") catch |err| return mapWorldError(err);
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
    _ = try extractEditorPanel(world, "machina.editor.entities.panel", "Editor Entities Panel", panel, editor_palette.panel, 0.0);

    const header_text = std.fmt.allocPrint(allocator, "ENTITIES {d}", .{scene_world.entityCount()}) catch return RenderError.OutOfMemory;
    defer allocator.free(header_text);
    try extractEditorText(world, "machina.editor.entities.header", "Editor Entities Header", editorPanelTextPosition(panel, editorSystemHeaderYOffset()), header_text, editor_entity_text_size, editor_palette.text_muted);

    if (scene_world.entityCount() == 0) {
        try extractEditorText(world, "machina.editor.entities.empty", "Editor Entities Empty", editorPanelTextPosition(panel, editorSystemRowsYOffset()), "NO ENTITIES", editor_entity_text_size, editor_palette.text_dim);
        return;
    }

    const list_clip = editorEntityListClipRect(scene_world, input);
    const entity_scroll = world.createEntity("machina.editor.entities.scroll", "Editor Entities Scroll View") catch |err| return mapWorldError(err);
    world.setUiScrollView(entity_scroll, .{
        .position = list_clip.position,
        .size = list_clip.size,
        .content_offset = .{ 0.0, input.editor.entity_scroll_y, 0.0 },
    }) catch |err| return mapWorldError(err);

    const row_width = list_clip.size[0];
    const table_height = editorEntityTableContentHeight(scene_world.entityCount());
    const entity_table = world.createEntity("machina.editor.entities.table", "Editor Entities Table") catch |err| return mapWorldError(err);
    world.setUiRect(entity_table, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = .{ row_width, table_height, 0.0 },
        .color = editor_palette.shell,
        .corner_radius = editor_panel_corner_radius,
    }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(entity_table, .{
        .parent = "machina.editor.entities.scroll",
        .order = 0,
    }) catch |err| return mapWorldError(err);

    const range = editorEntityVisibleRange(scene_world, input);
    for (range.start..range.end) |entity_index| {
        const handle = editorEntityHandleAt(scene_world, entity_index) orelse continue;
        const entity = scene_world.entity(handle) catch continue;
        const row_y = editor_entity_card_padding_y + @as(f32, @floatFromInt(entity_index)) * editor_entity_row_stride;
        const is_selected = editorEntityHandlesEqual(input.editor.selected_entity, handle);
        if (is_selected) {
            const highlight_id = std.fmt.allocPrint(allocator, "machina.editor.entities.row.{d}.highlight", .{entity_index}) catch return RenderError.OutOfMemory;
            defer allocator.free(highlight_id);
            const highlight = try extractEditorPanel(world, highlight_id, "Editor Entity Row Highlight", .{
                .x = 0.0,
                .y = row_y - 8.0,
                .width = row_width,
                .height = editor_entity_row_stride,
            }, editor_palette.panel_muted, editor_button_corner_radius);
            world.setUiLayoutItem(highlight, .{
                .parent = "machina.editor.entities.table",
                .order = @intCast(entity_index),
            }) catch |err| return mapWorldError(err);
        }

        const component_count = editorEntityComponentCount(scene_world, handle);
        const component_text = std.fmt.allocPrint(allocator, "{d}C", .{component_count}) catch return RenderError.OutOfMemory;
        defer allocator.free(component_text);
        const component_width = editorTextWidth(component_text, editor_entity_text_size);
        const component_x = @max(row_width - editor_entity_row_component_padding_x - component_width, editor_entity_row_label_padding_x);
        const label_max_width = @max(component_x - editor_entity_row_label_padding_x - editor_entity_field_column_gap, 1.0);
        const raw_label = if (entity.name.len > 0) entity.name else entity.id;
        const label_text = fitEditorTextToWidth(allocator, raw_label, editor_entity_text_size, label_max_width) catch return RenderError.OutOfMemory;
        defer allocator.free(label_text);

        const label_id = std.fmt.allocPrint(allocator, "machina.editor.entities.row.{d}.label", .{entity_index}) catch return RenderError.OutOfMemory;
        defer allocator.free(label_id);
        _ = try extractEditorChildText(world, label_id, "Editor Entity Row Label", "machina.editor.entities.table", .{
            editor_entity_row_label_padding_x,
            row_y,
            0.0,
        }, label_text, editor_entity_text_size, if (is_selected) editor_palette.accent_soft else editor_palette.text);

        const component_id = std.fmt.allocPrint(allocator, "machina.editor.entities.row.{d}.components", .{entity_index}) catch return RenderError.OutOfMemory;
        defer allocator.free(component_id);
        _ = try extractEditorChildText(world, component_id, "Editor Entity Row Component Count", "machina.editor.entities.table", .{
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
    const track = world.createEntity("machina.editor.entities.scrollbar.track", "Editor Entities Scrollbar Track") catch |err| return mapWorldError(err);
    world.setUiRect(track, .{
        .position = .{ track_x, list_clip.position[1], 0.0 },
        .size = .{ editor_scrollbar_width, track_height, 0.0 },
        .color = editor_palette.panel_muted,
        .corner_radius = editor_scrollbar_width * 0.5,
    }) catch |err| return mapWorldError(err);

    const visible_rows = @as(f32, @floatFromInt(editorEntityVisibleRows(input)));
    const total_rows = @as(f32, @floatFromInt(scene_world.entityCount()));
    const thumb_height = @max(track_height * visible_rows / @max(total_rows, visible_rows), editor_scrollbar_width * 2.0);
    const max_scroll = editorEntityMaxScrollY(scene_world, input);
    const scroll_t = if (max_scroll > 0.0) std.math.clamp(input.editor.entity_scroll_y / max_scroll, 0.0, 1.0) else 0.0;
    const thumb_y = list_clip.position[1] + (track_height - thumb_height) * scroll_t;

    const thumb = world.createEntity("machina.editor.entities.scrollbar.thumb", "Editor Entities Scrollbar Thumb") catch |err| return mapWorldError(err);
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

    _ = try extractEditorPanel(world, "machina.editor.inspector.panel", "Editor Inspector Panel", .{
        .x = panel_x,
        .y = panel_y,
        .width = panel_width,
        .height = panel_height,
    }, editor_palette.panel, 0.0);

    try extractEditorText(world, "machina.editor.inspector.title", "Editor Inspector Title", .{
        panel_x + editor_panel_padding_x,
        panel_y + editor_panel_padding_y,
        0.0,
    }, "COMPONENTS", editor_inspector_text_size, editor_palette.text);

    const selected = input.editor.selected_entity orelse {
        try extractEditorText(world, "machina.editor.inspector.empty", "Editor Inspector Empty", .{
            panel_x + editor_panel_padding_x,
            panel_y + editor_panel_padding_y + editor_inspector_line_stride * 2.0,
            0.0,
        }, "NO ENTITY SELECTED", editor_inspector_text_size, editor_palette.text);
        try extractEditorText(world, "machina.editor.inspector.empty.hint", "Editor Inspector Empty Hint", .{
            panel_x + editor_panel_padding_x,
            panel_y + editor_panel_padding_y + editor_inspector_line_stride * 3.0,
            0.0,
        }, "CLICK A MESH", editor_inspector_text_size, editor_palette.text_dim);
        return;
    };

    const entity = scene_world.entity(selected) catch {
        try extractEditorText(world, "machina.editor.inspector.unavailable", "Editor Inspector Unavailable", .{
            panel_x + editor_panel_padding_x,
            panel_y + editor_panel_padding_y + editor_inspector_line_stride * 2.0,
            0.0,
        }, "SELECTION UNAVAILABLE", editor_inspector_text_size, editor_palette.danger);
        return;
    };

    const entity_header = std.fmt.allocPrint(allocator, "{s}  {s}", .{ entity.name, entity.id }) catch return RenderError.OutOfMemory;
    defer allocator.free(entity_header);
    try extractEditorText(world, "machina.editor.inspector.entity", "Editor Inspector Entity", .{
        panel_x + editor_panel_padding_x,
        panel_y + editor_panel_padding_y + editor_inspector_line_stride,
        0.0,
    }, entity_header, editor_inspector_text_size, editor_palette.text_muted);

    const scroll_clip = editorInspectorScrollClipRect(input);
    const scroll = world.createEntity("machina.editor.inspector.scroll", "Editor Inspector Scroll View") catch |err| return mapWorldError(err);
    world.setUiScrollView(scroll, .{
        .position = scroll_clip.position,
        .size = scroll_clip.size,
        .content_offset = .{ 0.0, input.editor.inspector_scroll_y, 0.0 },
    }) catch |err| return mapWorldError(err);

    const stack_id = "machina.editor.inspector.components";
    const stack = world.createEntity(stack_id, "Editor Component Stack") catch |err| return mapWorldError(err);
    world.setUiVBox(stack, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .spacing = editor_inspector_card_gap,
    }) catch |err| return mapWorldError(err);
    world.setUiLayoutItem(stack, .{
        .parent = "machina.editor.inspector.scroll",
        .order = 0,
    }) catch |err| return mapWorldError(err);

    const card_width = @max(scroll_clip.size[0], 1.0);
    const field_stride = editor_inspector_field_row_stride;
    var component_index: usize = 0;
    var stack_order: i32 = 0;
    var components = scene_world.entityComponents(selected) catch {
        return;
    };
    while (components.next()) |component_id| {
        if (component_index > 0) {
            const separator_id = std.fmt.allocPrint(allocator, "machina.editor.inspector.component.separator.{d}", .{component_index}) catch return RenderError.OutOfMemory;
            defer allocator.free(separator_id);
            const separator = world.createEntity(separator_id, "Editor Component Separator") catch |err| return mapWorldError(err);
            world.setUiSeparator(separator, .{
                .position = .{ 0.0, 0.0, 0.0 },
                .size = .{ card_width, editor_inspector_separator_height, 0.0 },
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
        const card_id = std.fmt.allocPrint(allocator, "machina.editor.inspector.component.{d}", .{component_index}) catch return RenderError.OutOfMemory;
        defer allocator.free(card_id);
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

        const title_id = std.fmt.allocPrint(allocator, "machina.editor.inspector.component.{d}.title", .{component_index}) catch return RenderError.OutOfMemory;
        defer allocator.free(title_id);
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
            const field_y = editor_inspector_card_padding_y + editorTextHeight(editor_inspector_text_size) + editor_panel_label_gap + @as(f32, @floatFromInt(field_index)) * field_stride;
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
    const entity = world.createEntity(id, name) catch |err| return mapWorldError(err);
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
    const panel = world.createEntity(id, name) catch |err| return mapWorldError(err);
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
    const label_id = std.fmt.allocPrint(allocator, "machina.editor.inspector.component.{d}.field.{d}.label", .{ spec.component_index, spec.field_index }) catch return RenderError.OutOfMemory;
    defer allocator.free(label_id);

    const value_x = editorInspectorFieldValueX(spec.card_width);
    const label_max_width = @max(value_x - editor_inspector_card_padding_x - editor_inspector_field_column_gap, 1.0);
    const label_text = fitEditorTextToWidth(allocator, spec.field_name, editor_inspector_text_size, label_max_width) catch return RenderError.OutOfMemory;
    defer allocator.free(label_text);

    _ = try extractEditorChildText(world, label_id, "Editor Component Field Label", spec.parent_id, .{
        editor_inspector_card_padding_x,
        spec.field_y,
        0.0,
    }, label_text, editor_inspector_text_size, editor_palette.text_muted);

    switch (spec.value) {
        .vec3 => |payload| {
            const total_width = @max(spec.card_width - value_x - editor_inspector_card_padding_x, 1.0);
            const lane_width = @max((total_width - editor_inspector_input_gap * 2.0) / 3.0, 1.0);
            for (0..3) |lane_index| {
                var lane_buffer: [editor_input_text_buffer_len]u8 = [_]u8{0} ** editor_input_text_buffer_len;
                const lane: u2 = @intCast(lane_index);
                const is_focused = editorTextInputFocuses(spec.text_input, spec.component_id, spec.field_name, lane);
                const value_text = if (is_focused)
                    spec.text_input.text()
                else
                    std.fmt.bufPrint(&lane_buffer, "{d:.2}", .{payload[lane]}) catch "";
                try extractEditorPropertyInputBox(allocator, world, spec, .{
                    .lane = lane,
                    .x = value_x + @as(f32, @floatFromInt(lane_index)) * (lane_width + editor_inspector_input_gap),
                    .width = lane_width,
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
            try extractEditorPropertyInputBox(allocator, world, spec, .{
                .lane = null,
                .x = value_x,
                .width = @max(spec.card_width - value_x - editor_inspector_card_padding_x, 1.0),
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
    x: f32,
    width: f32,
    text: []const u8,
    focused: bool,
    cursor: usize,
    selection_anchor: usize,
};

fn extractEditorPropertyInputBox(
    allocator: std.mem.Allocator,
    world: *runtime.World,
    row: EditorPropertyRowSpec,
    input: EditorPropertyInputBoxSpec,
) RenderError!void {
    const input_id = if (input.lane) |lane|
        std.fmt.allocPrint(allocator, "machina.editor.inspector.component.{d}.field.{d}.input.{d}", .{ row.component_index, row.field_index, lane }) catch return RenderError.OutOfMemory
    else
        std.fmt.allocPrint(allocator, "machina.editor.inspector.component.{d}.field.{d}.input", .{ row.component_index, row.field_index }) catch return RenderError.OutOfMemory;
    defer allocator.free(input_id);
    const value_id = if (input.lane) |lane|
        std.fmt.allocPrint(allocator, "machina.editor.inspector.component.{d}.field.{d}.value.{d}", .{ row.component_index, row.field_index, lane }) catch return RenderError.OutOfMemory
    else
        std.fmt.allocPrint(allocator, "machina.editor.inspector.component.{d}.field.{d}.value", .{ row.component_index, row.field_index }) catch return RenderError.OutOfMemory;
    defer allocator.free(value_id);

    const box = try extractEditorPanel(world, input_id, "Editor Property Text Input", .{
        .x = input.x,
        .y = row.field_y - 4.0,
        .width = input.width,
        .height = editor_inspector_input_height,
    }, editor_palette.input, editor_inspector_input_corner_radius);
    world.setUiLayoutItem(box, .{
        .parent = row.parent_id,
        .order = 0,
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
        const selection_id = if (input.lane) |lane|
            std.fmt.allocPrint(allocator, "machina.editor.inspector.component.{d}.field.{d}.selection.{d}", .{ row.component_index, row.field_index, lane }) catch return RenderError.OutOfMemory
        else
            std.fmt.allocPrint(allocator, "machina.editor.inspector.component.{d}.field.{d}.selection", .{ row.component_index, row.field_index }) catch return RenderError.OutOfMemory;
        defer allocator.free(selection_id);
        const start_x = std.math.clamp(
            editor_inspector_input_padding_x + editorTextWidth(input.text[0..@min(selection_start, input.text.len)], editor_inspector_text_size),
            editor_inspector_input_padding_x,
            @max(input.width - editor_inspector_input_padding_x, editor_inspector_input_padding_x),
        );
        const end_x = std.math.clamp(
            editor_inspector_input_padding_x + editorTextWidth(input.text[0..@min(selection_end, input.text.len)], editor_inspector_text_size),
            editor_inspector_input_padding_x,
            @max(input.width - editor_inspector_input_padding_x, editor_inspector_input_padding_x),
        );
        const selection = try extractEditorPanel(world, selection_id, "Editor Property Text Selection", .{
            .x = start_x,
            .y = editor_inspector_selection_padding_y,
            .width = @max(end_x - start_x, 1.0),
            .height = editorTextHeight(editor_inspector_text_size) - editor_inspector_selection_padding_y * 0.5,
        }, editor_palette.input_selection, 2.0);
        world.setUiLayoutItem(selection, .{
            .parent = input_id,
            .order = 0,
        }) catch |err| return mapWorldError(err);
    }

    const text_max_width = @max(input.width - editor_inspector_input_padding_x * 2.0, 1.0);
    const fitted_text = fitEditorTextToWidth(allocator, input.text, editor_inspector_text_size, text_max_width) catch return RenderError.OutOfMemory;
    defer allocator.free(fitted_text);
    const text_entity = try extractEditorChildText(world, value_id, "Editor Property Text Input Value", input_id, .{
        editor_inspector_input_padding_x,
        2.0,
        0.0,
    }, fitted_text, editor_inspector_text_size, if (input.focused) editor_palette.text else editor_palette.text_muted);
    world.setUiLayoutItem(text_entity, .{
        .parent = input_id,
        .order = 1,
    }) catch |err| return mapWorldError(err);

    if (input.focused) {
        const cursor_x = std.math.clamp(
            editor_inspector_input_padding_x + editorTextWidth(input.text[0..@min(input.cursor, input.text.len)], editor_inspector_text_size),
            editor_inspector_input_padding_x,
            @max(input.width - editor_inspector_input_padding_x, editor_inspector_input_padding_x),
        );
        const caret_id = if (input.lane) |lane|
            std.fmt.allocPrint(allocator, "machina.editor.inspector.component.{d}.field.{d}.caret.{d}", .{ row.component_index, row.field_index, lane }) catch return RenderError.OutOfMemory
        else
            std.fmt.allocPrint(allocator, "machina.editor.inspector.component.{d}.field.{d}.caret", .{ row.component_index, row.field_index }) catch return RenderError.OutOfMemory;
        defer allocator.free(caret_id);
        const caret = try extractEditorPanel(world, caret_id, "Editor Property Text Input Caret", .{
            .x = cursor_x,
            .y = 4.0,
            .width = editor_inspector_caret_width,
            .height = editorTextHeight(editor_inspector_text_size) - 4.0,
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

fn editorTextHeight(size: f32) f32 {
    return @as(f32, @floatFromInt(ui_font.height)) * size;
}

fn editorTextWidth(value: []const u8, size: f32) f32 {
    return @as(f32, @floatFromInt(value.len * ui_font.advance)) * size;
}

fn editorInspectorFieldValueX(card_width: f32) f32 {
    const preferred = editor_inspector_field_value_column_x;
    const max_start = @max(card_width - editor_inspector_card_padding_x - @as(f32, @floatFromInt(ui_font.advance)) * 3.0, editor_inspector_card_padding_x);
    return std.math.clamp(preferred, editor_inspector_card_padding_x, max_start);
}

fn fitEditorTextToWidth(allocator: std.mem.Allocator, value: []const u8, size: f32, max_width: f32) error{OutOfMemory}![]u8 {
    if (editorTextWidth(value, size) <= max_width) {
        return allocator.dupe(u8, value);
    }

    const suffix = "...";
    const glyph_width = @as(f32, @floatFromInt(ui_font.advance)) * size;
    const suffix_width = editorTextWidth(suffix, size);
    if (max_width <= 0.0 or glyph_width <= 0.0) {
        return allocator.dupe(u8, "");
    }
    if (max_width < suffix_width) {
        const glyph_count = @min(suffix.len, @as(usize, @intFromFloat(@floor(max_width / glyph_width))));
        return allocator.dupe(u8, suffix[0..glyph_count]);
    }
    if (max_width == suffix_width) {
        return allocator.dupe(u8, suffix);
    }

    const available_prefix_width = max_width - suffix_width;
    const prefix_len = @min(value.len, @as(usize, @intFromFloat(@floor(available_prefix_width / glyph_width))));
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ value[0..prefix_len], suffix });
}

fn editorPanelTextPosition(panel: ScreenRect, local_y: f32) [3]f32 {
    return .{ panel.x + editor_panel_padding_x, panel.y + local_y, 0.0 };
}

fn editorSystemHeaderYOffset() f32 {
    return editor_panel_padding_y;
}

fn editorSystemRowsYOffset() f32 {
    return editorSystemHeaderYOffset() + editorTextHeight(editor_system_text_size) + editor_panel_label_gap;
}

fn editorDebugPanelSize(input: FrameInput) [2]f32 {
    const panel = editorSystemPanelRect(input);
    return .{ panel.width, panel.height };
}

fn editorSystemPanelRect(input: FrameInput) ScreenRect {
    const panel = editorLeftSidebarPanelRect(input);
    const entity_height = editorEntityPanelHeight(panel.height);
    return .{
        .x = panel.x,
        .y = panel.y,
        .width = panel.width,
        .height = @max(panel.height - editor_left_panel_gap - entity_height, 1.0),
    };
}

fn editorEntityPanelRect(input: FrameInput) ScreenRect {
    const panel = editorLeftSidebarPanelRect(input);
    const entity_height = editorEntityPanelHeight(panel.height);
    return .{
        .x = panel.x,
        .y = panel.y + @max(panel.height - entity_height, 0.0),
        .width = panel.width,
        .height = entity_height,
    };
}

fn editorLeftSidebarPanelRect(input: FrameInput) ScreenRect {
    return editorSidebarPanelRect(editorLeftSidebarRect(input));
}

fn editorEntityPanelHeight(total_height: f32) f32 {
    if (total_height <= editor_left_panel_gap + 2.0) {
        return @max(total_height * 0.5, 1.0);
    }
    const max_entity_height = @max(total_height * 0.5, 1.0);
    const min_entity_height = @min(editor_entity_panel_min_height, max_entity_height);
    var entity_height = std.math.clamp(total_height * 0.38, min_entity_height, max_entity_height);
    const min_system = @min(editor_system_panel_min_height, @max(total_height - editor_left_panel_gap - 1.0, 1.0));
    if (total_height - editor_left_panel_gap - entity_height < min_system) {
        entity_height = @max(total_height - editor_left_panel_gap - min_system, 1.0);
    }
    return entity_height;
}

fn editorSidebarPanelRect(sidebar: ScreenRect) ScreenRect {
    return insetScreenRect(sidebar, editor_sidebar_panel_margin);
}

fn insetScreenRect(rect: ScreenRect, inset: f32) ScreenRect {
    const clamped = @max(inset, 0.0);
    return .{
        .x = rect.x + clamped,
        .y = rect.y + clamped,
        .width = @max(rect.width - clamped * 2.0, 1.0),
        .height = @max(rect.height - clamped * 2.0, 1.0),
    };
}

fn editorSystemHeaderY(input: FrameInput) f32 {
    return editorSystemPanelRect(input).y + editorSystemHeaderYOffset();
}

fn editorSystemRowsY(input: FrameInput) f32 {
    return editorSystemPanelRect(input).y + editorSystemRowsYOffset();
}

const EditorSystemVisibleRange = struct {
    start: usize,
    end: usize,
    offset_y: f32,
};

fn editorSystemVisibleRange(input: FrameInput) EditorSystemVisibleRange {
    const profile_count = input.system_profiles.len;
    if (profile_count == 0) {
        return .{ .start = 0, .end = 0, .offset_y = 0.0 };
    }

    const scroll_y = std.math.clamp(input.editor.system_scroll_y, 0.0, editorSystemMaxScrollY(input, profile_count));
    const row_offset = scroll_y / editor_system_row_stride;
    const start_float = @floor(row_offset);
    const start: usize = @intFromFloat(start_float);
    const offset_y = scroll_y - start_float * editor_system_row_stride;
    const visible_rows = editorSystemVisibleRows(input);
    const visible_count = @min(
        profile_count - start,
        visible_rows + if (offset_y > 0.0) @as(usize, 1) else @as(usize, 0),
    );
    return .{
        .start = start,
        .end = start + visible_count,
        .offset_y = offset_y,
    };
}

fn editorSystemListClipRect(input: FrameInput) UiClipRect {
    const panel = editorSystemPanelRect(input);
    const scrollbar_space = if (editorSystemNeedsScrollForInput(input, editorSystemProfileScrollCount(input)))
        editor_scrollbar_width + editor_scrollbar_gap
    else
        0.0;
    return .{
        .position = .{ panel.x, editorSystemRowsY(input), 0.0 },
        .size = .{
            @max(panel.width - scrollbar_space, 1.0),
            editorSystemTableContentHeight(editorSystemVisibleRows(input)),
            0.0,
        },
    };
}

const EditorEntityVisibleRange = struct {
    start: usize,
    end: usize,
    offset_y: f32,
};

fn editorEntityVisibleRange(scene_world: *const runtime.World, input: FrameInput) EditorEntityVisibleRange {
    const entity_count = scene_world.entityCount();
    if (entity_count == 0) {
        return .{ .start = 0, .end = 0, .offset_y = 0.0 };
    }

    const scroll_y = std.math.clamp(input.editor.entity_scroll_y, 0.0, editorEntityMaxScrollY(scene_world, input));
    const row_offset = scroll_y / editor_entity_row_stride;
    const start_float = @floor(row_offset);
    const start: usize = @intFromFloat(start_float);
    const offset_y = scroll_y - start_float * editor_entity_row_stride;
    const visible_rows = editorEntityVisibleRows(input);
    const visible_count = @min(
        entity_count - start,
        visible_rows + if (offset_y > 0.0) @as(usize, 1) else @as(usize, 0),
    );
    return .{
        .start = start,
        .end = start + visible_count,
        .offset_y = offset_y,
    };
}

fn editorEntityListClipRect(scene_world: *const runtime.World, input: FrameInput) UiClipRect {
    const panel = editorEntityPanelRect(input);
    const scrollbar_space = if (editorEntityNeedsScroll(scene_world, input))
        editor_scrollbar_width + editor_scrollbar_gap
    else
        0.0;
    return .{
        .position = .{ panel.x, panel.y + editorSystemRowsYOffset(), 0.0 },
        .size = .{
            @max(panel.width - scrollbar_space, 1.0),
            editorEntityTableContentHeight(editorEntityVisibleRows(input)),
            0.0,
        },
    };
}

fn editorSystemProfileScrollCount(input: FrameInput) usize {
    return @max(input.system_profiles.len, input.system_profile_count_hint);
}

fn editorSystemVisibleRows(input: FrameInput) usize {
    const panel = editorSystemPanelRect(input);
    const rows_height = @max(panel.y + panel.height - editorSystemRowsY(input) - editor_panel_bottom_padding - editor_system_card_padding_y * 2.0, editor_system_row_stride);
    return @max(@as(usize, @intFromFloat(@floor(rows_height / editor_system_row_stride))), 1);
}

fn editorSystemTableContentHeight(row_count: usize) f32 {
    return editor_system_card_padding_y * 2.0 + @as(f32, @floatFromInt(row_count)) * editor_system_row_stride;
}

fn editorEntityVisibleRows(input: FrameInput) usize {
    const panel = editorEntityPanelRect(input);
    const rows_y = panel.y + editorSystemRowsYOffset();
    const rows_height = @max(panel.y + panel.height - rows_y - editor_panel_bottom_padding - editor_entity_card_padding_y * 2.0, editor_entity_row_stride);
    return @max(@as(usize, @intFromFloat(@floor(rows_height / editor_entity_row_stride))), 1);
}

fn editorEntityTableContentHeight(row_count: usize) f32 {
    return editor_entity_card_padding_y * 2.0 + @as(f32, @floatFromInt(row_count)) * editor_entity_row_stride;
}

fn editorEntityNeedsScroll(scene_world: *const runtime.World, input: FrameInput) bool {
    return scene_world.entityCount() > editorEntityVisibleRows(input);
}

fn editorEntityMaxScroll(scene_world: *const runtime.World, input: FrameInput) usize {
    const visible_rows = editorEntityVisibleRows(input);
    const entity_count = scene_world.entityCount();
    return if (entity_count > visible_rows)
        entity_count - visible_rows
    else
        0;
}

fn editorEntityMaxScrollY(scene_world: *const runtime.World, input: FrameInput) f32 {
    return @as(f32, @floatFromInt(editorEntityMaxScroll(scene_world, input))) * editor_entity_row_stride;
}

fn editorEntityHandleAt(scene_world: *const runtime.World, entity_index: usize) ?runtime.EntityHandle {
    if (entity_index >= scene_world.entityCount()) {
        return null;
    }
    const index: u32 = @intCast(entity_index);
    const entity = scene_world.entity(.{ .index = index }) catch return null;
    return .{ .index = index, .generation = entity.generation };
}

fn editorEntityComponentCount(scene_world: *const runtime.World, handle: runtime.EntityHandle) usize {
    var components = scene_world.entityComponents(handle) catch return 0;
    var count: usize = 0;
    while (components.next()) |_| {
        count += 1;
    }
    return count;
}

fn editorEntityHandlesEqual(selected: ?runtime.EntityHandle, handle: runtime.EntityHandle) bool {
    const candidate = selected orelse return false;
    return candidate.index == handle.index and candidate.generation == handle.generation;
}

fn editorInspectorScrollClipRect(input: FrameInput) UiClipRect {
    const sidebar = editorSidebarPanelRect(editorRightSidebarRect(input));
    const y = sidebar.y + editor_panel_padding_y + editor_inspector_line_stride * 2.5;
    const bottom = sidebar.y + sidebar.height;
    return .{
        .position = .{ sidebar.x, y, 0.0 },
        .size = .{
            @max(sidebar.width, 1.0),
            @max(bottom - y, 1.0),
            0.0,
        },
    };
}

fn editorInspectorComponentContentHeight(scene_world: *const runtime.World, selected: ?runtime.EntityHandle) f32 {
    const selected_entity = selected orelse return 0.0;
    var components = scene_world.entityComponents(selected_entity) catch return 0.0;
    var height: f32 = 0.0;
    var component_index: usize = 0;
    while (components.next()) |component_id| {
        if (component_index > 0) {
            height += editor_inspector_separator_height;
        }
        height += editorInspectorComponentCardHeight(scene_world, component_id);
        component_index += 1;
    }
    return height;
}

fn editorInspectorComponentCardHeight(scene_world: *const runtime.World, component_id: []const u8) f32 {
    const field_count = scene_world.componentFieldCount(component_id);
    return editor_inspector_card_padding_y * 2.0 +
        editorTextHeight(editor_inspector_text_size) +
        editor_panel_label_gap +
        @as(f32, @floatFromInt(field_count)) * editor_inspector_field_row_stride;
}

fn editorInspectorNeedsScroll(scene_world: *const runtime.World, input: FrameInput) bool {
    return editorInspectorMaxScrollY(scene_world, input) > 0.0;
}

fn editorInspectorMaxScrollY(scene_world: *const runtime.World, input: FrameInput) f32 {
    const clip = editorInspectorScrollClipRect(input);
    return @max(editorInspectorComponentContentHeight(scene_world, input.editor.selected_entity) - clip.size[1], 0.0);
}

fn editorSystemNeedsScrollForInput(input: FrameInput, profile_count: usize) bool {
    return profile_count > editorSystemVisibleRows(input);
}

fn editorSystemMaxScroll(input: FrameInput, profile_count: usize) usize {
    const visible_rows = editorSystemVisibleRows(input);
    return if (profile_count > visible_rows)
        profile_count - visible_rows
    else
        0;
}

fn editorSystemMaxScrollY(input: FrameInput, profile_count: usize) f32 {
    return @as(f32, @floatFromInt(editorSystemMaxScroll(input, profile_count))) * editor_system_row_stride;
}

fn formatFpsLabel(allocator: std.mem.Allocator, fps: f32) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(allocator, "FPS {d}", .{roundedFps(fps)});
}

fn formatSystemProfileHeader(allocator: std.mem.Allocator, profiles: []const runtime.SystemProfileSnapshot) error{OutOfMemory}![]const u8 {
    const window_size = if (profiles.len == 0) 0 else profiles[0].window_size;
    return std.fmt.allocPrint(allocator, "SYS {d} AVG {d}F SNAP 3HZ", .{ profiles.len, window_size });
}

fn formatSystemProfileDuration(allocator: std.mem.Allocator, profile: runtime.SystemProfileSnapshot) error{OutOfMemory}![]const u8 {
    if (profile.sample_count == 0) {
        return allocator.dupe(u8, "--");
    }

    var average_buffer: [16]u8 = undefined;
    const average = formatDurationShort(&average_buffer, profile.rolling_average_ns);
    return allocator.dupe(u8, average);
}

fn formatDurationShort(buffer: *[16]u8, ns: u64) []const u8 {
    const micros = nsToMicrosRounded(ns);
    if (micros < 10_000) {
        return std.fmt.bufPrint(buffer, "{d}us", .{micros}) catch "----";
    }
    return std.fmt.bufPrint(buffer, "{d}ms", .{(micros + 500) / 1000}) catch "----";
}

fn nsToMicrosRounded(ns: u64) u64 {
    return (ns + 500) / 1000;
}

fn elapsedNanosecondsSince(started_ns: i128) u64 {
    const elapsed_ns = monotonicTimestampNs() - started_ns;
    if (elapsed_ns <= 0) {
        return 0;
    }
    return @intCast(@min(elapsed_ns, std.math.maxInt(u64)));
}

fn monotonicTimestampNs() i128 {
    const io = Io.Threaded.global_single_threaded.io();
    return Io.Timestamp.now(io, .awake).nanoseconds;
}

fn roundedFps(fps: f32) i32 {
    if (!std.math.isFinite(fps) or fps <= 0.0) {
        return 0;
    }
    const clamped = @min(fps, 9999.0);
    return @intFromFloat(@round(clamped));
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

fn setRenderFrameInput(world: *runtime.World, input: FrameInput) RenderError!void {
    writeFrameInput(world, input) catch |err| return mapWorldError(err);
}

fn renderFrameInput(world: *const runtime.World) RenderError!FrameInput {
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

fn setRenderUiButtonState(world: *runtime.World, entity: runtime.EntityHandle, state: UiButtonState) RenderError!void {
    const fields = [_]runtime.ComponentFieldValue{
        .{ .name = "hovered", .value = .{ .boolean = state.hovered } },
        .{ .name = "held", .value = .{ .boolean = state.held } },
        .{ .name = "pressed", .value = .{ .boolean = state.pressed } },
    };
    world.setComponent(entity, render_ui_button_state_component_id, &fields) catch |err| return mapWorldError(err);
}

fn setRenderUiClip(world: *runtime.World, entity: runtime.EntityHandle, clip: UiClipRect) RenderError!void {
    const fields = [_]runtime.ComponentFieldValue{
        .{ .name = "position", .value = .{ .vec3 = clip.position } },
        .{ .name = "size", .value = .{ .vec3 = clip.size } },
    };
    world.setComponent(entity, render_ui_clip_component_id, &fields) catch |err| return mapWorldError(err);
}

fn renderUiButtonState(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?UiButtonState {
    if (!(world.hasComponent(entity, render_ui_button_state_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return .{
        .hovered = world.getBoolean(entity, render_ui_button_state_component_id, "hovered") catch |err| return mapWorldError(err),
        .held = world.getBoolean(entity, render_ui_button_state_component_id, "held") catch |err| return mapWorldError(err),
        .pressed = world.getBoolean(entity, render_ui_button_state_component_id, "pressed") catch |err| return mapWorldError(err),
    };
}

fn renderUiClip(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?UiClipRect {
    if (!(world.hasComponent(entity, render_ui_clip_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return .{
        .position = world.getVec3(entity, render_ui_clip_component_id, "position") catch |err| return mapWorldError(err),
        .size = world.getVec3(entity, render_ui_clip_component_id, "size") catch |err| return mapWorldError(err),
    };
}

fn uiBorder(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?UiBorder {
    if (!(world.hasComponent(entity, runtime.ui_border_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return .{
        .color = world.getVec3(entity, runtime.ui_border_component_id, "color") catch |err| return mapWorldError(err),
        .thickness = world.getFloat(entity, runtime.ui_border_component_id, "thickness") catch |err| return mapWorldError(err),
    };
}

fn uiProgressBar(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?UiProgressBar {
    if (!(world.hasComponent(entity, runtime.ui_progress_bar_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return .{
        .value = world.getFloat(entity, runtime.ui_progress_bar_component_id, "value") catch |err| return mapWorldError(err),
        .max = world.getFloat(entity, runtime.ui_progress_bar_component_id, "max") catch |err| return mapWorldError(err),
        .fill_color = world.getVec3(entity, runtime.ui_progress_bar_component_id, "fill_color") catch |err| return mapWorldError(err),
    };
}

fn uiToggleChecked(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!?bool {
    if (!(world.hasComponent(entity, runtime.ui_toggle_component_id) catch |err| return mapWorldError(err))) {
        return null;
    }
    return world.getBoolean(entity, runtime.ui_toggle_component_id, "checked") catch |err| return mapWorldError(err);
}

fn resolveUiLayout(world: *const runtime.World, entity: runtime.EntityHandle, local_position: [3]f32) RenderError!ui_layout.ResolvedLayout {
    return ui_layout.resolve(world, entity, local_position) catch |err| return mapLayoutError(err);
}

fn combineUiClip(a: ?UiClipRect, b: ?UiClipRect) RenderError!?UiClipRect {
    return ui_layout.combineClip(a, b) catch |err| return mapLayoutError(err);
}

fn resolveUiScreenLayout(input: FrameInput, entity_id: []const u8, layout: ui_layout.ResolvedLayout, item_size: [3]f32) RenderError!ui_layout.ResolvedLayout {
    if (!input.debug_overlay_visible or isEditorUiEntityId(entity_id)) {
        return layout;
    }
    return ui_layout.clipToTarget(layout, sceneUiTarget(input, 0.0, 0.0), item_size) catch |err| return mapLayoutError(err);
}

fn sceneUiCanvasTransform(world: *const runtime.World, input: FrameInput, width: f32, height: f32) RenderError!UiCanvasTransform {
    return ui_layout.canvasTransform(world, sceneUiTarget(input, width, height)) catch |err| return mapLayoutError(err);
}

fn sceneUiTarget(input: FrameInput, width: f32, height: f32) ui_layout.Target {
    if (input.debug_overlay_visible) {
        const viewport = editorGameViewport(input);
        return .{ .x = viewport.x, .y = viewport.y, .width = viewport.width, .height = viewport.height };
    }
    return .{ .width = width, .height = height };
}

fn isEditorUiEntityId(entity_id: []const u8) bool {
    return std.mem.startsWith(u8, entity_id, "machina.editor.");
}

fn applyUiCanvasLayout(transform: UiCanvasTransform, entity_id: []const u8, layout: ui_layout.ResolvedLayout) ui_layout.ResolvedLayout {
    if (isEditorUiEntityId(entity_id)) {
        return layout;
    }
    return ui_layout.applyCanvasTransform(transform, layout);
}

fn scaleUiVec3(transform: UiCanvasTransform, value: [3]f32) [3]f32 {
    return ui_layout.scaleVec3(transform, value);
}

fn scaleUiSize(transform: UiCanvasTransform, value: [3]f32) [3]f32 {
    return ui_layout.scaleSize(transform, value);
}

fn uiLayoutItemSize(world: *const runtime.World, entity: runtime.EntityHandle) RenderError![3]f32 {
    return ui_layout.itemSize(world, entity) catch |err| return mapLayoutError(err);
}

fn hitTestUiRect(point: [2]f32, position: [3]f32, size: [3]f32, clip: ?UiClipRect) bool {
    return ui_layout.pointInsideRect(point, position, size, clip);
}

fn textPixelSize(value: []const u8, size: f32) [3]f32 {
    return ui_layout.textPixelSize(value, size);
}

fn resolveUiTextPosition(world: *const runtime.World, entity: runtime.EntityHandle, text: runtime.UiText, position: [3]f32) RenderError![3]f32 {
    return ui_layout.resolveTextPosition(world, entity, text, position) catch |err| return mapLayoutError(err);
}

fn evaluateUiButtonState(input: FrameInput, position: [3]f32, size: [3]f32, clip: ?UiClipRect) UiButtonState {
    const hovered = input.pointer.has_position and hitTestUiRect(input.pointer.position, position, size, clip);
    return .{
        .hovered = hovered,
        .held = hovered and input.pointer.primary_down,
        .pressed = hovered and input.pointer.primary_released,
    };
}

fn extractCameraInto(world: *runtime.World, camera: CameraState) RenderError!void {
    const entity = world.createEntity("machina.render.extract.camera", "Render Camera") catch |err| return mapWorldError(err);
    world.setTransform(entity, camera.transform) catch |err| return mapWorldError(err);
    world.setCamera(entity, .{
        .fov_y_degrees = camera.fov_y_degrees,
        .near = camera.near,
        .far = camera.far,
    }) catch |err| return mapWorldError(err);
}

fn extractDirectionalLightInto(world: *runtime.World, light: DirectionalLightState) RenderError!void {
    const entity = world.createEntity("machina.render.extract.directional_light", "Render Directional Light") catch |err| return mapWorldError(err);
    world.setDirectionalLight(entity, .{
        .direction = light.direction,
        .color = light.color,
        .intensity = light.intensity,
        .ambient = light.ambient,
    }) catch |err| return mapWorldError(err);
}

fn batchIndexFromDrawEntity(world: *const runtime.World, entity: runtime.EntityHandle) RenderError!usize {
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

fn mapEngineSetupError(err: anyerror) RenderError {
    return switch (err) {
        error.OutOfMemory => RenderError.OutOfMemory,
        else => RenderError.InvalidScene,
    };
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

fn mapGeometryError(err: anyerror) RenderError {
    return switch (err) {
        error.OutOfMemory => RenderError.OutOfMemory,
        else => RenderError.InvalidScene,
    };
}

const BatchPlan = struct {
    allocator: std.mem.Allocator,
    renderables: []runtime.RenderableMesh,
    batches: []BatchPlanEntry,

    fn build(allocator: std.mem.Allocator, world: *const runtime.World) RenderError!BatchPlan {
        var renderables: std.ArrayList(runtime.RenderableMesh) = .empty;
        errdefer renderables.deinit(allocator);

        var builds: std.ArrayList(BatchBuild) = .empty;
        errdefer {
            for (builds.items) |*pending_batch| {
                pending_batch.deinit(allocator);
            }
            builds.deinit(allocator);
        }

        var meshes = world.renderableMeshes();
        while (meshes.next()) |renderable| {
            const render_index = renderables.items.len;
            renderables.append(allocator, renderable) catch return RenderError.OutOfMemory;
            const geometry_key = GeometryKey.fromRenderable(renderable) orelse return RenderError.InvalidScene;
            const shadow_key = ShadowKey.fromRenderable(renderable);

            var batch_index: ?usize = null;
            for (builds.items, 0..) |pending_batch, index| {
                if (pending_batch.geometry_key.eql(geometry_key) and
                    pending_batch.shadow_key.eql(shadow_key))
                {
                    batch_index = index;
                    break;
                }
            }

            const index = batch_index orelse blk: {
                try builds.append(allocator, .{
                    .geometry_key = geometry_key,
                    .shadow_key = shadow_key,
                });
                break :blk builds.items.len - 1;
            };
            builds.items[index].render_indices.append(allocator, render_index) catch return RenderError.OutOfMemory;
        }

        const renderable_slice = renderables.toOwnedSlice(allocator) catch return RenderError.OutOfMemory;
        errdefer allocator.free(renderable_slice);

        const batches = allocator.alloc(BatchPlanEntry, builds.items.len) catch return RenderError.OutOfMemory;
        var copied: usize = 0;
        errdefer {
            for (batches[0..copied]) |entry| {
                allocator.free(entry.render_indices);
            }
            allocator.free(batches);
        }

        for (builds.items, 0..) |*pending_batch, index| {
            batches[index] = .{
                .geometry_key = pending_batch.geometry_key,
                .shadow_key = pending_batch.shadow_key,
                .render_indices = pending_batch.render_indices.toOwnedSlice(allocator) catch return RenderError.OutOfMemory,
            };
            copied += 1;
        }

        builds.deinit(allocator);
        return .{
            .allocator = allocator,
            .renderables = renderable_slice,
            .batches = batches,
        };
    }

    fn deinit(self: *BatchPlan) void {
        const allocator = self.allocator;
        for (self.batches) |entry| {
            allocator.free(entry.render_indices);
        }
        allocator.free(self.batches);
        allocator.free(self.renderables);
        self.* = .{
            .allocator = allocator,
            .renderables = &.{},
            .batches = &.{},
        };
    }
};

const BatchBuild = struct {
    geometry_key: GeometryKey,
    shadow_key: ShadowKey,
    render_indices: std.ArrayList(usize) = .empty,

    fn deinit(self: *BatchBuild, allocator: std.mem.Allocator) void {
        self.render_indices.deinit(allocator);
    }
};

const BatchPlanEntry = struct {
    geometry_key: GeometryKey,
    shadow_key: ShadowKey,
    render_indices: []usize,
};

const UiDrawResources = struct {
    vertex_buffer: ?*wgpu.Buffer = null,
    vertex_buffer_size: u64 = 0,
    vertex_count: u32 = 0,

    fn update(
        self: *UiDrawResources,
        device: *wgpu.Device,
        queue: *wgpu.Queue,
        vertices: []const UiVertex,
    ) RenderError!void {
        if (vertices.len > std.math.maxInt(u32)) {
            return RenderError.InvalidScene;
        }

        self.vertex_count = @intCast(vertices.len);
        if (vertices.len == 0) {
            return;
        }

        const bytes = std.mem.sliceAsBytes(vertices);
        if (self.vertex_buffer == null or self.vertex_buffer_size < bytes.len) {
            const buffer = device.createBuffer(&wgpu.BufferDescriptor{
                .label = wgpu.StringView.fromSlice("Machina UI vertex buffer"),
                .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
                .size = @intCast(bytes.len),
                .mapped_at_creation = @as(u32, @intFromBool(false)),
            }) orelse return RenderError.NoDevice;
            if (self.vertex_buffer) |old_buffer| {
                old_buffer.release();
            }
            self.vertex_buffer = buffer;
            self.vertex_buffer_size = @intCast(bytes.len);
        }

        queue.writeBuffer(self.vertex_buffer orelse return RenderError.NoDevice, 0, bytes.ptr, bytes.len);
    }

    fn deinit(self: *UiDrawResources) void {
        if (self.vertex_buffer) |buffer| {
            buffer.release();
        }
        self.* = .{};
    }
};

const MeshDemo = struct {
    allocator: std.mem.Allocator,
    pipeline: *wgpu.RenderPipeline,
    shadow_pipeline: *wgpu.RenderPipeline,
    ui_pipeline: *wgpu.RenderPipeline,
    bind_group_layout: *wgpu.BindGroupLayout,
    pipeline_layout: *wgpu.PipelineLayout,
    shadow_pipeline_layout: *wgpu.PipelineLayout,
    ui_pipeline_layout: *wgpu.PipelineLayout,
    frame_uniform_buffer: *wgpu.Buffer,
    bind_group: *wgpu.BindGroup,
    shadow_target: ShadowTarget,
    shadow_sampler: *wgpu.Sampler,
    render_state: RenderEcsState,
    batches: []BatchResources,
    ui_draw: UiDrawResources = .{},

    fn create(
        allocator: std.mem.Allocator,
        device: *wgpu.Device,
        queue: *wgpu.Queue,
        texture_format: wgpu.TextureFormat,
        scene: Scene,
    ) RenderError!MeshDemo {
        const bind_group_layout_entries = [_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = wgpu.ShaderStages.vertex | wgpu.ShaderStages.fragment,
                .buffer = .{
                    .type = .uniform,
                    .min_binding_size = @sizeOf(FrameUniforms),
                },
            },
            .{
                .binding = 1,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = .{
                    .sample_type = .depth,
                    .view_dimension = .@"2d",
                },
            },
            .{
                .binding = 2,
                .visibility = wgpu.ShaderStages.fragment,
                .sampler = .{
                    .type = .comparison,
                },
            },
        };
        const bind_group_layout = device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh bind group layout"),
            .entry_count = bind_group_layout_entries.len,
            .entries = &bind_group_layout_entries,
        }) orelse return RenderError.NoDevice;
        errdefer bind_group_layout.release();

        const frame_uniform_buffer = device.createBuffer(&wgpu.BufferDescriptor{
            .label = wgpu.StringView.fromSlice("Machina frame uniforms"),
            .usage = wgpu.BufferUsages.uniform | wgpu.BufferUsages.copy_dst,
            .size = @sizeOf(FrameUniforms),
            .mapped_at_creation = @as(u32, @intFromBool(false)),
        }) orelse return RenderError.NoDevice;
        errdefer frame_uniform_buffer.release();

        var initial_uniforms = try frameUniforms(.{});
        writeUniforms(queue, frame_uniform_buffer, &initial_uniforms);

        var shadow_target = try ShadowTarget.create(device);
        errdefer shadow_target.deinit();

        const shadow_sampler = device.createSampler(&wgpu.SamplerDescriptor{
            .label = wgpu.StringView.fromSlice("Machina shadow comparison sampler"),
            .address_mode_u = .clamp_to_edge,
            .address_mode_v = .clamp_to_edge,
            .address_mode_w = .clamp_to_edge,
            .mag_filter = .linear,
            .min_filter = .linear,
            .mipmap_filter = .nearest,
            .compare = .less_equal,
        }) orelse return RenderError.NoDevice;
        errdefer shadow_sampler.release();

        const bind_group_entries = [_]wgpu.BindGroupEntry{
            .{
                .binding = 0,
                .buffer = frame_uniform_buffer,
                .size = @sizeOf(FrameUniforms),
            },
            .{
                .binding = 1,
                .texture_view = shadow_target.view orelse return RenderError.NoDevice,
            },
            .{
                .binding = 2,
                .sampler = shadow_sampler,
            },
        };
        const bind_group = device.createBindGroup(&wgpu.BindGroupDescriptor{
            .label = wgpu.StringView.fromSlice("Machina frame bind group"),
            .layout = bind_group_layout,
            .entry_count = bind_group_entries.len,
            .entries = &bind_group_entries,
        }) orelse return RenderError.NoDevice;
        errdefer bind_group.release();

        var render_state = try RenderEcsState.init(allocator);
        errdefer render_state.deinit();
        try render_state.extractScene(scene);

        const batches = allocator.alloc(BatchResources, 0) catch return RenderError.OutOfMemory;
        errdefer allocator.free(batches);

        const bind_group_layouts = [_]*wgpu.BindGroupLayout{bind_group_layout};
        const pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh pipeline layout"),
            .bind_group_layout_count = bind_group_layouts.len,
            .bind_group_layouts = &bind_group_layouts,
        }) orelse return RenderError.NoDevice;
        errdefer pipeline_layout.release();

        const pipeline = try createMeshPipeline(device, texture_format, pipeline_layout);
        errdefer pipeline.release();

        const empty_bind_group_layouts = [_]*wgpu.BindGroupLayout{};
        const shadow_pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Machina shadow pipeline layout"),
            .bind_group_layout_count = empty_bind_group_layouts.len,
            .bind_group_layouts = &empty_bind_group_layouts,
        }) orelse return RenderError.NoDevice;
        errdefer shadow_pipeline_layout.release();

        const shadow_pipeline = try createShadowPipeline(device, shadow_pipeline_layout);
        errdefer shadow_pipeline.release();

        const ui_pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("Machina UI pipeline layout"),
            .bind_group_layout_count = empty_bind_group_layouts.len,
            .bind_group_layouts = &empty_bind_group_layouts,
        }) orelse return RenderError.NoDevice;
        errdefer ui_pipeline_layout.release();

        const ui_pipeline = try createUiPipeline(device, texture_format, ui_pipeline_layout);
        errdefer ui_pipeline.release();

        return .{
            .allocator = allocator,
            .pipeline = pipeline,
            .shadow_pipeline = shadow_pipeline,
            .ui_pipeline = ui_pipeline,
            .bind_group_layout = bind_group_layout,
            .pipeline_layout = pipeline_layout,
            .shadow_pipeline_layout = shadow_pipeline_layout,
            .ui_pipeline_layout = ui_pipeline_layout,
            .frame_uniform_buffer = frame_uniform_buffer,
            .bind_group = bind_group,
            .shadow_target = shadow_target,
            .shadow_sampler = shadow_sampler,
            .render_state = render_state,
            .batches = batches,
        };
    }

    fn deinit(self: *MeshDemo) void {
        self.render_state.deinit();
        for (self.batches) |*batch| {
            batch.deinit();
        }
        self.allocator.free(self.batches);
        self.bind_group.release();
        self.frame_uniform_buffer.release();
        self.shadow_sampler.release();
        self.shadow_target.deinit();
        self.pipeline.release();
        self.shadow_pipeline.release();
        self.ui_pipeline.release();
        self.pipeline_layout.release();
        self.shadow_pipeline_layout.release();
        self.ui_pipeline_layout.release();
        self.bind_group_layout.release();
        self.ui_draw.deinit();
    }

    fn draw(
        self: *MeshDemo,
        device: *wgpu.Device,
        queue: *wgpu.Queue,
        target_view: *wgpu.TextureView,
        depth_view: *wgpu.TextureView,
        config: FrameConfig,
    ) RenderError!void {
        try self.runRenderSchedule(.{
            .device = device,
            .queue = queue,
            .target_view = target_view,
            .depth_view = depth_view,
            .frame = config,
        });
    }

    fn renderSystemProfileCount(self: *const MeshDemo) usize {
        return self.render_state.system_profiles.items.len;
    }

    fn runRenderSchedule(self: *MeshDemo, context: RenderSystemContext) RenderError!void {
        var maybe_plan: ?BatchPlan = null;
        defer if (maybe_plan) |*plan| {
            plan.deinit();
        };

        var profiled_context = context;
        profiled_context.frame.input.system_profiles = try self.render_state.combineSystemProfileSnapshots(context.frame.input.system_profiles);

        for (self.render_state.schedule.batches) |batch| {
            for (batch.systems) |system| {
                const started_ns = monotonicTimestampNs();
                const result = self.runRenderSystem(system, profiled_context, &maybe_plan);
                self.render_state.recordSystemDuration(system, batch.phase, elapsedNanosecondsSince(started_ns));
                try result;
            }
        }
    }

    fn runRenderSystem(
        self: *MeshDemo,
        system: runtime.ScheduledSystem,
        context: RenderSystemContext,
        maybe_plan: *?BatchPlan,
    ) RenderError!void {
        const result: RenderError!void = if (std.mem.eql(u8, system.id, render_extract_system_id)) blk: {
            break :blk self.render_state.extractSceneWithInput(context.frame.scene, context.frame.input);
        } else if (std.mem.eql(u8, system.id, render_prepare_meshes_system_id)) blk: {
            var plan = try BatchPlan.build(self.allocator, &self.render_state.world);
            var plan_transferred = false;
            errdefer if (!plan_transferred) {
                plan.deinit();
            };
            try self.prepareBatchResources(context.device, plan);
            try self.updateBatchInstances(context.queue, plan, context.frame);
            maybe_plan.* = plan;
            plan_transferred = true;
            break :blk {};
        } else if (std.mem.eql(u8, system.id, render_queue_meshes_system_id)) blk: {
            const plan = maybe_plan.* orelse return RenderError.InvalidScene;
            break :blk self.render_state.queueBatchDraws(plan.batches.len);
        } else if (std.mem.eql(u8, system.id, render_interact_ui_system_id)) blk: {
            break :blk self.render_state.updateUiInteractions();
        } else if (std.mem.eql(u8, system.id, render_prepare_ui_system_id)) blk: {
            break :blk self.prepareUiDrawResources(context.device, context.queue, context.frame);
        } else if (std.mem.eql(u8, system.id, render_queue_ui_system_id)) blk: {
            break :blk self.render_state.queueUiDraw();
        } else if (std.mem.eql(u8, system.id, render_draw_meshes_system_id)) blk: {
            break :blk self.drawQueuedBatches(context);
        } else {
            return RenderError.InvalidScene;
        };
        result catch |err| {
            std.log.err("render system '{s}' failed: {s}", .{ system.id, @errorName(err) });
            return err;
        };
    }

    fn prepareUiDrawResources(self: *MeshDemo, device: *wgpu.Device, queue: *wgpu.Queue, config: FrameConfig) RenderError!void {
        var vertices = try buildUiVertices(self.allocator, &self.render_state.world, config.width, config.height);
        defer vertices.deinit(self.allocator);
        try self.ui_draw.update(device, queue, vertices.items);
    }

    fn prepareBatchResources(self: *MeshDemo, device: *wgpu.Device, plan: BatchPlan) RenderError!void {
        if (self.batchResourcesMatchPlan(plan)) {
            return;
        }

        const new_batches = self.allocator.alloc(BatchResources, plan.batches.len) catch return RenderError.OutOfMemory;
        var batch_count: usize = 0;
        errdefer {
            for (new_batches[0..batch_count]) |*batch| {
                batch.deinit();
            }
            self.allocator.free(new_batches);
        }

        for (plan.batches, 0..) |entry, index| {
            new_batches[index] = try BatchResources.create(self.allocator, device, entry);
            batch_count += 1;
        }

        for (self.batches) |*batch| {
            batch.deinit();
        }
        self.allocator.free(self.batches);
        self.batches = new_batches;
    }

    fn batchResourcesMatchPlan(self: MeshDemo, plan: BatchPlan) bool {
        if (self.batches.len != plan.batches.len) {
            return false;
        }
        for (plan.batches, self.batches) |entry, batch| {
            if (!batch.matches(entry)) {
                return false;
            }
        }
        return true;
    }

    fn updateBatchInstances(self: *MeshDemo, queue: *wgpu.Queue, plan: BatchPlan, config: FrameConfig) RenderError!void {
        const camera = try cameraState(&self.render_state.world);
        const light = try directionalLightState(&self.render_state.world);
        const light_view_projection = try shadowLightViewProjection(light);
        const game_viewport = config.gameViewport();
        for (plan.batches, 0..) |entry, batch_index| {
            if (batch_index >= self.batches.len) {
                return RenderError.InvalidScene;
            }

            const instances = self.allocator.alloc(InstanceAttributes, entry.render_indices.len) catch return RenderError.OutOfMemory;
            defer self.allocator.free(instances);

            for (entry.render_indices, 0..) |render_index, instance_index| {
                if (render_index >= plan.renderables.len) {
                    return RenderError.InvalidScene;
                }
                const mesh = plan.renderables[render_index];
                instances[instance_index] = try instanceAttributes(.{
                    .width = game_viewport.width,
                    .height = game_viewport.height,
                    .mesh = &mesh,
                    .camera = camera,
                    .light_view_projection = light_view_projection,
                });
            }

            const bytes = std.mem.sliceAsBytes(instances);
            queue.writeBuffer(self.batches[batch_index].instance_buffer, 0, bytes.ptr, bytes.len);
        }
    }

    fn drawQueuedBatches(self: *MeshDemo, context: RenderSystemContext) RenderError!void {
        const light = try directionalLightState(&self.render_state.world);
        var frame_uniforms = try frameUniforms(light);
        writeUniforms(context.queue, self.frame_uniform_buffer, &frame_uniforms);

        var draw_batch_indices: std.ArrayList(usize) = .empty;
        defer draw_batch_indices.deinit(self.allocator);

        var draw_cursor: usize = 0;
        const draw_query = [_][]const u8{render_draw_batch_component_id};
        while (self.render_state.world.queryNext(&draw_query, &draw_cursor)) |draw_entity| {
            const batch_index = try self.render_state.drawCommandBatchIndex(draw_entity);
            if (batch_index >= self.batches.len) {
                return RenderError.InvalidScene;
            }
            draw_batch_indices.append(self.allocator, batch_index) catch return RenderError.OutOfMemory;
        }

        const should_draw_ui = self.render_state.uiDrawCommandCount() > 0 and self.ui_draw.vertex_count > 0;

        const encoder = context.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh command encoder"),
        }) orelse return RenderError.NoDevice;
        defer encoder.release();

        try self.drawShadowPass(encoder, draw_batch_indices.items);

        const color_attachments = [_]wgpu.ColorAttachment{
            .{
                .view = context.target_view,
                .clear_value = .{
                    .r = 0.0006,
                    .g = 0.0018,
                    .b = 0.0086,
                    .a = 1.0,
                },
            },
        };
        const depth_attachment = wgpu.DepthStencilAttachment{
            .view = context.depth_view,
            .depth_load_op = .clear,
            .depth_store_op = .store,
            .depth_clear_value = 1.0,
        };

        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .color_attachment_count = color_attachments.len,
            .color_attachments = &color_attachments,
            .depth_stencil_attachment = &depth_attachment,
        }) orelse return RenderError.NoDevice;
        defer render_pass.release();
        const game_viewport = context.frame.gameViewport();
        render_pass.setViewport(game_viewport.x, game_viewport.y, game_viewport.width, game_viewport.height, 0.0, 1.0);
        render_pass.setScissorRect(
            @intFromFloat(@max(@floor(game_viewport.x), 0.0)),
            @intFromFloat(@max(@floor(game_viewport.y), 0.0)),
            @intFromFloat(@max(@ceil(game_viewport.width), 1.0)),
            @intFromFloat(@max(@ceil(game_viewport.height), 1.0)),
        );
        render_pass.setPipeline(self.pipeline);
        render_pass.setBindGroup(0, self.bind_group, 0, null);
        for (draw_batch_indices.items) |batch_index| {
            const batch = self.batches[batch_index];
            render_pass.setVertexBuffer(0, batch.vertex_buffer, 0, batch.vertex_buffer_size);
            render_pass.setVertexBuffer(1, batch.instance_buffer, 0, batch.instance_buffer_size);
            render_pass.setIndexBuffer(batch.index_buffer, .uint16, 0, batch.index_buffer_size);
            render_pass.drawIndexed(batch.index_count, batch.instance_count, 0, 0, 0);
        }
        render_pass.end();

        if (should_draw_ui) {
            try self.drawUiPass(encoder, context.target_view);
        }

        const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh command buffer"),
        }) orelse return RenderError.NoDevice;
        defer command_buffer.release();

        const command_buffers = [_]*const wgpu.CommandBuffer{command_buffer};
        context.queue.submit(&command_buffers);
    }

    fn drawShadowPass(self: *MeshDemo, encoder: *wgpu.CommandEncoder, draw_batch_indices: []const usize) RenderError!void {
        const shadow_view = self.shadow_target.view orelse return RenderError.NoDevice;
        const depth_attachment = wgpu.DepthStencilAttachment{
            .view = shadow_view,
            .depth_load_op = .clear,
            .depth_store_op = .store,
            .depth_clear_value = 1.0,
        };
        const color_attachments = [_]wgpu.ColorAttachment{};
        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .label = wgpu.StringView.fromSlice("Machina shadow pass"),
            .color_attachment_count = color_attachments.len,
            .color_attachments = &color_attachments,
            .depth_stencil_attachment = &depth_attachment,
        }) orelse return RenderError.NoDevice;
        defer render_pass.release();

        render_pass.setPipeline(self.shadow_pipeline);
        for (draw_batch_indices) |batch_index| {
            const batch = self.batches[batch_index];
            if (!batch.shadow_key.casts_shadow) {
                continue;
            }
            render_pass.setVertexBuffer(0, batch.vertex_buffer, 0, batch.vertex_buffer_size);
            render_pass.setVertexBuffer(1, batch.instance_buffer, 0, batch.instance_buffer_size);
            render_pass.setIndexBuffer(batch.index_buffer, .uint16, 0, batch.index_buffer_size);
            render_pass.drawIndexed(batch.index_count, batch.instance_count, 0, 0, 0);
        }
        render_pass.end();
    }

    fn drawUiPass(self: *MeshDemo, encoder: *wgpu.CommandEncoder, target_view: *wgpu.TextureView) RenderError!void {
        const color_attachments = [_]wgpu.ColorAttachment{
            .{
                .view = target_view,
                .load_op = .load,
                .store_op = .store,
            },
        };
        const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .label = wgpu.StringView.fromSlice("Machina UI pass"),
            .color_attachment_count = color_attachments.len,
            .color_attachments = &color_attachments,
        }) orelse return RenderError.NoDevice;
        defer render_pass.release();

        render_pass.setPipeline(self.ui_pipeline);
        const vertex_buffer = self.ui_draw.vertex_buffer orelse return RenderError.NoDevice;
        render_pass.setVertexBuffer(0, vertex_buffer, 0, self.ui_draw.vertex_buffer_size);
        render_pass.draw(self.ui_draw.vertex_count, 1, 0, 0);
        render_pass.end();
    }
};

const BatchResources = struct {
    geometry_key: GeometryKey,
    shadow_key: ShadowKey,
    vertex_buffer: *wgpu.Buffer,
    index_buffer: *wgpu.Buffer,
    instance_buffer: *wgpu.Buffer,
    vertex_buffer_size: u64,
    index_buffer_size: u64,
    instance_buffer_size: u64,
    index_count: u32,
    instance_count: u32,

    fn create(
        allocator: std.mem.Allocator,
        device: *wgpu.Device,
        entry: BatchPlanEntry,
    ) RenderError!BatchResources {
        var mesh = geometry.generatePrimitive(
            allocator,
            entry.geometry_key.primitive,
            entry.geometry_key.segments,
            entry.geometry_key.rings,
        ) catch |err| return mapGeometryError(err);
        defer mesh.deinit(allocator);

        const vertex_bytes = std.mem.sliceAsBytes(mesh.vertices);
        const index_bytes = std.mem.sliceAsBytes(mesh.indices);
        const vertex_buffer = try createStaticBuffer(device, "Machina mesh vertex buffer", wgpu.BufferUsages.vertex, vertex_bytes);
        errdefer vertex_buffer.release();

        const index_buffer = try createStaticBuffer(device, "Machina mesh index buffer", wgpu.BufferUsages.index, index_bytes);
        errdefer index_buffer.release();

        if (entry.render_indices.len > std.math.maxInt(u32)) {
            return RenderError.InvalidScene;
        }
        const instance_buffer_size = @sizeOf(InstanceAttributes) * entry.render_indices.len;
        const instance_buffer = device.createBuffer(&wgpu.BufferDescriptor{
            .label = wgpu.StringView.fromSlice("Machina mesh instance buffer"),
            .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
            .size = @intCast(instance_buffer_size),
            .mapped_at_creation = @as(u32, @intFromBool(false)),
        }) orelse return RenderError.NoDevice;
        errdefer instance_buffer.release();

        return .{
            .geometry_key = entry.geometry_key,
            .shadow_key = entry.shadow_key,
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .instance_buffer = instance_buffer,
            .vertex_buffer_size = @intCast(vertex_bytes.len),
            .index_buffer_size = @intCast(index_bytes.len),
            .instance_buffer_size = @intCast(instance_buffer_size),
            .index_count = @intCast(mesh.indices.len),
            .instance_count = @intCast(entry.render_indices.len),
        };
    }

    fn matches(self: BatchResources, entry: BatchPlanEntry) bool {
        if (entry.render_indices.len > std.math.maxInt(u32)) {
            return false;
        }
        return self.geometry_key.eql(entry.geometry_key) and
            self.shadow_key.eql(entry.shadow_key) and
            self.instance_count == @as(u32, @intCast(entry.render_indices.len));
    }

    fn deinit(self: *BatchResources) void {
        self.instance_buffer.release();
        self.index_buffer.release();
        self.vertex_buffer.release();
    }
};

const GeometryKey = struct {
    primitive: geometry.Primitive,
    segments: i32,
    rings: i32,

    fn fromRenderable(renderable: runtime.RenderableMesh) ?GeometryKey {
        return .{
            .primitive = geometry.parsePrimitive(renderable.primitive) orelse return null,
            .segments = renderable.segments,
            .rings = renderable.rings,
        };
    }

    fn eql(self: GeometryKey, other: GeometryKey) bool {
        return self.primitive == other.primitive and self.segments == other.segments and self.rings == other.rings;
    }
};

const ShadowKey = struct {
    casts_shadow: bool,
    receives_shadow: bool,

    fn fromRenderable(renderable: runtime.RenderableMesh) ShadowKey {
        return .{
            .casts_shadow = renderable.casts_shadow,
            .receives_shadow = renderable.receives_shadow,
        };
    }

    fn eql(self: ShadowKey, other: ShadowKey) bool {
        return self.casts_shadow == other.casts_shadow and self.receives_shadow == other.receives_shadow;
    }
};

fn openGpu(instance: *wgpu.Instance, compatible_surface: ?*wgpu.Surface) RenderError!GpuContext {
    const adapter_response = instance.requestAdapterSync(&wgpu.RequestAdapterOptions{
        .compatible_surface = compatible_surface,
    }, 200_000_000);
    const adapter = switch (adapter_response.status) {
        .success => adapter_response.adapter orelse return RenderError.NoAdapter,
        else => return RenderError.NoAdapter,
    };
    errdefer adapter.release();

    const device_response = adapter.requestDeviceSync(instance, &wgpu.DeviceDescriptor{
        .required_limits = null,
    }, 200_000_000);
    const device = switch (device_response.status) {
        .success => device_response.device orelse return RenderError.NoDevice,
        else => return RenderError.NoDevice,
    };
    errdefer device.release();

    const queue = device.getQueue() orelse return RenderError.NoDevice;
    errdefer queue.release();

    return .{
        .adapter = adapter,
        .device = device,
        .queue = queue,
    };
}

fn chooseSurfaceFormat(capabilities: wgpu.SurfaceCapabilities) ?wgpu.TextureFormat {
    for (capabilities.formats[0..capabilities.format_count]) |format| {
        if (format == .bgra8_unorm_srgb) {
            return format;
        }
    }

    if (capabilities.format_count == 0) {
        return null;
    }
    return capabilities.formats[0];
}

fn updatePointerFromWindow(pointer: *PointerInput, window: *anyopaque, x: f32, y: f32) void {
    var window_width: c_int = 0;
    var window_height: c_int = 0;
    var pixel_width: c_int = 0;
    var pixel_height: c_int = 0;

    const has_window_size = sdl.machina_sdl_get_window_size(window, &window_width, &window_height);
    const has_pixel_size = sdl.machina_sdl_get_window_size_in_pixels(window, &pixel_width, &pixel_height);
    if (has_window_size == 0 or has_pixel_size == 0 or window_width <= 0 or window_height <= 0) {
        pointer.position = .{ x, y };
        pointer.has_position = true;
        return;
    }

    const scale_x = @as(f32, @floatFromInt(@max(pixel_width, 1))) / @as(f32, @floatFromInt(window_width));
    const scale_y = @as(f32, @floatFromInt(@max(pixel_height, 1))) / @as(f32, @floatFromInt(window_height));
    pointer.position = .{ x * scale_x, y * scale_y };
    pointer.has_position = true;
}

fn configureSurfaceFromWindow(
    surface: *wgpu.Surface,
    device: *wgpu.Device,
    window: *anyopaque,
    format: wgpu.TextureFormat,
    current_width: *u32,
    current_height: *u32,
) !void {
    var pixel_width: c_int = 0;
    var pixel_height: c_int = 0;
    if (sdl.machina_sdl_get_window_size_in_pixels(window, &pixel_width, &pixel_height) == 0) {
        return RenderError.SurfaceFailed;
    }

    const width: u32 = @intCast(@max(pixel_width, 1));
    const height: u32 = @intCast(@max(pixel_height, 1));
    if (width == current_width.* and height == current_height.*) {
        return;
    }

    surface.configure(&wgpu.SurfaceConfiguration{
        .device = device,
        .format = format,
        .width = width,
        .height = height,
        .present_mode = .fifo,
    });
    current_width.* = width;
    current_height.* = height;
}

fn drawMeshToSurface(
    surface: *wgpu.Surface,
    device: *wgpu.Device,
    queue: *wgpu.Queue,
    demo: *MeshDemo,
    depth_view: *wgpu.TextureView,
    config: FrameConfig,
) !void {
    var surface_texture = wgpu.SurfaceTexture{
        .next_in_chain = null,
        .texture = null,
        .status = .@"error",
    };
    surface.getCurrentTexture(&surface_texture);
    switch (surface_texture.status) {
        .success_optimal, .success_suboptimal => {},
        else => return RenderError.SurfaceFailed,
    }

    const texture = surface_texture.texture orelse return RenderError.SurfaceFailed;
    defer texture.release();

    const view = texture.createView(&wgpu.TextureViewDescriptor{
        .label = wgpu.StringView.fromSlice("Machina surface texture view"),
        .mip_level_count = 1,
        .array_layer_count = 1,
    }) orelse return RenderError.NoDevice;
    defer view.release();

    try demo.draw(device, queue, view, depth_view, config);
    if (surface.present() != .success) {
        return RenderError.SurfaceFailed;
    }
}

fn createMeshPipeline(device: *wgpu.Device, texture_format: wgpu.TextureFormat, pipeline_layout: *wgpu.PipelineLayout) RenderError!*wgpu.RenderPipeline {
    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("shaders/demo.wgsl"),
    })) orelse return RenderError.NoDevice;
    defer shader_module.release();

    const vertex_attributes = [_]wgpu.VertexAttribute{
        .{
            .format = .float32x3,
            .offset = @offsetOf(geometry.Vertex, "position"),
            .shader_location = 0,
        },
        .{
            .format = .float32x3,
            .offset = @offsetOf(geometry.Vertex, "normal"),
            .shader_location = 1,
        },
    };
    const vec4_size = @sizeOf([4]f32);
    const instance_attributes = [_]wgpu.VertexAttribute{
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "mvp") + vec4_size * 0,
            .shader_location = 2,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "mvp") + vec4_size * 1,
            .shader_location = 3,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "mvp") + vec4_size * 2,
            .shader_location = 4,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "mvp") + vec4_size * 3,
            .shader_location = 5,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "model") + vec4_size * 0,
            .shader_location = 6,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "model") + vec4_size * 1,
            .shader_location = 7,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "model") + vec4_size * 2,
            .shader_location = 8,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "model") + vec4_size * 3,
            .shader_location = 9,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "object_color"),
            .shader_location = 10,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 0,
            .shader_location = 11,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 1,
            .shader_location = 12,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 2,
            .shader_location = 13,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 3,
            .shader_location = 14,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_flags"),
            .shader_location = 15,
        },
    };
    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .step_mode = .vertex,
            .array_stride = @sizeOf(geometry.Vertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        },
        .{
            .step_mode = .instance,
            .array_stride = @sizeOf(InstanceAttributes),
            .attribute_count = instance_attributes.len,
            .attributes = &instance_attributes,
        },
    };

    const color_targets = [_]wgpu.ColorTargetState{
        .{
            .format = texture_format,
        },
    };
    const depth_stencil = wgpu.DepthStencilState{
        .format = depth_format,
        .depth_write_enabled = .true,
        .depth_compare = .less,
        .stencil_front = .{},
        .stencil_back = .{},
    };

    return device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .label = wgpu.StringView.fromSlice("Machina mesh pipeline"),
        .layout = pipeline_layout,
        .vertex = .{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
            .buffer_count = vertex_buffers.len,
            .buffers = &vertex_buffers,
        },
        .primitive = .{
            .cull_mode = .none,
        },
        .depth_stencil = &depth_stencil,
        .fragment = &wgpu.FragmentState{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("fs_main"),
            .target_count = color_targets.len,
            .targets = &color_targets,
        },
        .multisample = .{},
    }) orelse return RenderError.NoDevice;
}

fn createShadowPipeline(device: *wgpu.Device, pipeline_layout: *wgpu.PipelineLayout) RenderError!*wgpu.RenderPipeline {
    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("shaders/shadow.wgsl"),
    })) orelse return RenderError.NoDevice;
    defer shader_module.release();

    const vertex_attributes = [_]wgpu.VertexAttribute{
        .{
            .format = .float32x3,
            .offset = @offsetOf(geometry.Vertex, "position"),
            .shader_location = 0,
        },
    };
    const vec4_size = @sizeOf([4]f32);
    const instance_attributes = [_]wgpu.VertexAttribute{
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 0,
            .shader_location = 2,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 1,
            .shader_location = 3,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 2,
            .shader_location = 4,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(InstanceAttributes, "shadow_mvp") + vec4_size * 3,
            .shader_location = 5,
        },
    };
    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .step_mode = .vertex,
            .array_stride = @sizeOf(geometry.Vertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        },
        .{
            .step_mode = .instance,
            .array_stride = @sizeOf(InstanceAttributes),
            .attribute_count = instance_attributes.len,
            .attributes = &instance_attributes,
        },
    };

    const depth_stencil = wgpu.DepthStencilState{
        .format = shadow_depth_format,
        .depth_write_enabled = .true,
        .depth_compare = .less,
        .stencil_front = .{},
        .stencil_back = .{},
        .depth_bias = 2,
        .depth_bias_slope_scale = 2.0,
    };

    return device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .label = wgpu.StringView.fromSlice("Machina shadow pipeline"),
        .layout = pipeline_layout,
        .vertex = .{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
            .buffer_count = vertex_buffers.len,
            .buffers = &vertex_buffers,
        },
        .primitive = .{
            .cull_mode = .back,
        },
        .depth_stencil = &depth_stencil,
        .multisample = .{},
    }) orelse return RenderError.NoDevice;
}

fn createUiPipeline(device: *wgpu.Device, texture_format: wgpu.TextureFormat, pipeline_layout: *wgpu.PipelineLayout) RenderError!*wgpu.RenderPipeline {
    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("shaders/ui.wgsl"),
    })) orelse return RenderError.NoDevice;
    defer shader_module.release();

    const vertex_attributes = [_]wgpu.VertexAttribute{
        .{
            .format = .float32x2,
            .offset = @offsetOf(UiVertex, "position"),
            .shader_location = 0,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(UiVertex, "color"),
            .shader_location = 1,
        },
        .{
            .format = .float32x2,
            .offset = @offsetOf(UiVertex, "local_position"),
            .shader_location = 2,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(UiVertex, "rect_size_radius"),
            .shader_location = 3,
        },
    };
    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .step_mode = .vertex,
            .array_stride = @sizeOf(UiVertex),
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        },
    };
    const color_targets = [_]wgpu.ColorTargetState{
        .{
            .format = texture_format,
            .blend = &wgpu.BlendState.alpha_blending,
        },
    };

    return device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .label = wgpu.StringView.fromSlice("Machina UI pipeline"),
        .layout = pipeline_layout,
        .vertex = .{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
            .buffer_count = vertex_buffers.len,
            .buffers = &vertex_buffers,
        },
        .primitive = .{},
        .fragment = &wgpu.FragmentState{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("fs_main"),
            .target_count = color_targets.len,
            .targets = &color_targets,
        },
        .multisample = .{},
    }) orelse return RenderError.NoDevice;
}

fn createStaticBuffer(device: *wgpu.Device, label: []const u8, usage: wgpu.BufferUsage, data: []const u8) RenderError!*wgpu.Buffer {
    const buffer = device.createBuffer(&wgpu.BufferDescriptor{
        .label = wgpu.StringView.fromSlice(label),
        .usage = usage,
        .size = data.len,
        .mapped_at_creation = @as(u32, @intFromBool(true)),
    }) orelse return RenderError.NoDevice;
    errdefer buffer.release();

    const mapped: [*]u8 = @ptrCast(@alignCast(buffer.getMappedRange(0, data.len) orelse return RenderError.NoDevice));
    @memcpy(mapped[0..data.len], data);
    buffer.unmap();
    return buffer;
}

fn writeUniforms(queue: *wgpu.Queue, buffer: *wgpu.Buffer, uniforms: *const FrameUniforms) void {
    const bytes = std.mem.asBytes(uniforms);
    queue.writeBuffer(buffer, 0, bytes.ptr, bytes.len);
}

fn frameUniforms(light_value: DirectionalLightState) RenderError!FrameUniforms {
    const light = try validateDirectionalLight(light_value);
    const normalized_light = normalizeVec3(light.direction);

    return .{
        .light_dir = .{ normalized_light[0], normalized_light[1], normalized_light[2], 0.0 },
        .light_color = .{ light.color[0], light.color[1], light.color[2], 1.0 },
        .lighting = .{ light.ambient, light.intensity, 0.0, 0.0 },
    };
}

fn instanceAttributes(config: InstanceConfig) RenderError!InstanceAttributes {
    const aspect = config.width / config.height;
    const mesh = config.mesh;
    const rotation = matMul(
        rotationZ(mesh.rotation[2]),
        matMul(
            rotationY(mesh.rotation[1]),
            rotationX(mesh.rotation[0]),
        ),
    );
    const model = matMul(
        translation(mesh.position[0], mesh.position[1], mesh.position[2]),
        matMul(rotation, scaling(mesh.scale[0], mesh.scale[1], mesh.scale[2])),
    );
    const camera = try validateCamera(config.camera);
    const view = cameraViewMatrix(camera.transform);
    const projection = perspective(std.math.degreesToRadians(camera.fov_y_degrees), aspect, camera.near, camera.far);
    const mvp = matMul(projection, matMul(view, model));
    const shadow_mvp = matMul(config.light_view_projection, model);

    return .{
        .mvp = mvp,
        .model = model,
        .object_color = .{ mesh.base_color[0], mesh.base_color[1], mesh.base_color[2], 1.0 },
        .shadow_mvp = shadow_mvp,
        .shadow_flags = .{
            @floatFromInt(@as(u32, @intFromBool(mesh.receives_shadow))),
            @floatFromInt(@as(u32, @intFromBool(mesh.casts_shadow))),
            0.0,
            0.0,
        },
    };
}

fn shadowLightViewProjection(light_value: DirectionalLightState) RenderError![16]f32 {
    const light = try validateDirectionalLight(light_value);
    const light_direction = normalizeVec3(light.direction);
    const eye = scaleVec3(light_direction, 7.5);
    const target = [3]f32{ 0.0, 0.0, 0.0 };
    const preferred_up = [3]f32{ 0.0, 1.0, 0.0 };
    const up = if (@abs(dotVec3(light_direction, preferred_up)) > 0.95)
        [3]f32{ 0.0, 0.0, 1.0 }
    else
        preferred_up;
    const view = lookAt(eye, target, up);
    const projection = orthographic(-5.2, 5.2, -3.9, 3.9, 0.1, 18.0);
    return matMul(projection, view);
}

fn cameraState(world: *const runtime.World) RenderError!CameraState {
    if (world.renderCamera()) |camera| {
        return validateCamera(.{
            .transform = camera.transform,
            .fov_y_degrees = camera.fov_y_degrees,
            .near = camera.near,
            .far = camera.far,
        });
    }
    if (world.componentInstanceCountFor(runtime.camera_component_id) != 0) {
        return RenderError.InvalidScene;
    }
    return .{};
}

fn cameraStateForInput(world: *const runtime.World, input: FrameInput) RenderError!CameraState {
    var camera = try cameraState(world);
    if (input.camera_override) |camera_transform| {
        camera.transform = camera_transform;
    }
    return validateCamera(camera);
}

fn liveRunDeltaSecondsFromElapsedNs(elapsed_ns: u64) f32 {
    if (elapsed_ns == 0) {
        return live_run_default_delta_seconds;
    }

    const elapsed_seconds = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(std.time.ns_per_s));
    if (!std.math.isFinite(elapsed_seconds) or elapsed_seconds <= 0.0) {
        return live_run_default_delta_seconds;
    }

    return @floatCast(@min(elapsed_seconds, @as(f64, live_run_max_delta_seconds)));
}

fn updateFlyCamera(state: *FlyCameraState, world: *const runtime.World, input: FrameInput, delta_seconds: f32) RenderError!?runtime.Transform {
    const active = flyCameraInputActive(input);
    if (!state.initialized and !active) {
        return null;
    }
    if (!state.initialized) {
        state.transform = (try cameraState(world)).transform;
        state.initialized = true;
    }
    if (!active) {
        return state.transform;
    }

    const dt = if (std.math.isFinite(delta_seconds) and delta_seconds > 0.0)
        @min(delta_seconds, 0.1)
    else
        0.0;

    if (std.math.isFinite(input.pointer.delta[0]) and std.math.isFinite(input.pointer.delta[1])) {
        state.transform.rotation[1] -= input.pointer.delta[0] * fly_camera_look_sensitivity;
        state.transform.rotation[0] = std.math.clamp(
            state.transform.rotation[0] - input.pointer.delta[1] * fly_camera_look_sensitivity,
            -fly_camera_max_pitch,
            fly_camera_max_pitch,
        );
        state.transform.rotation[2] = 0.0;
    }

    var movement = [3]f32{ 0.0, 0.0, 0.0 };
    const forward = rotateDirection(state.transform.rotation, .{ 0.0, 0.0, -1.0 });
    const right = rotateDirection(state.transform.rotation, .{ 1.0, 0.0, 0.0 });
    if (input.keyboard.move_forward) {
        movement = addVec3(movement, forward);
    }
    if (input.keyboard.move_back) {
        movement = subtractVec3(movement, forward);
    }
    if (input.keyboard.move_right) {
        movement = addVec3(movement, right);
    }
    if (input.keyboard.move_left) {
        movement = subtractVec3(movement, right);
    }
    if (input.keyboard.move_up) {
        movement[1] += 1.0;
    }
    if (input.keyboard.move_down) {
        movement[1] -= 1.0;
    }

    if (vec3Length(movement) > 0.0001 and dt > 0.0) {
        state.transform.position = addVec3(
            state.transform.position,
            scaleVec3(normalizeVec3(movement), fly_camera_move_speed * dt),
        );
    }

    return state.transform;
}

fn flyCameraInputActive(input: FrameInput) bool {
    if (!input.pointer.secondary_down) {
        return false;
    }
    if (!input.debug_overlay_visible) {
        return true;
    }
    return input.pointer.has_position and editorGameViewport(input).contains(input.pointer.position);
}

fn directionalLightState(world: *const runtime.World) RenderError!DirectionalLightState {
    if (world.renderDirectionalLight()) |light| {
        return validateDirectionalLight(.{
            .direction = light.direction,
            .color = light.color,
            .intensity = light.intensity,
            .ambient = light.ambient,
        });
    }
    return .{};
}

fn validateCamera(camera: CameraState) RenderError!CameraState {
    if (!isFiniteVec3(camera.transform.position) or
        !isFiniteVec3(camera.transform.rotation) or
        !isFiniteVec3(camera.transform.scale) or
        !std.math.isFinite(camera.fov_y_degrees) or
        !std.math.isFinite(camera.near) or
        !std.math.isFinite(camera.far) or
        camera.fov_y_degrees <= 0.0 or
        camera.fov_y_degrees >= 179.0 or
        camera.near <= 0.0 or
        camera.far <= camera.near)
    {
        return RenderError.InvalidScene;
    }
    return camera;
}

fn validateDirectionalLight(light: DirectionalLightState) RenderError!DirectionalLightState {
    if (!isFiniteVec3(light.direction) or
        !isFiniteVec3(light.color) or
        !std.math.isFinite(light.intensity) or
        !std.math.isFinite(light.ambient) or
        vec3Length(light.direction) == 0.0 or
        light.intensity < 0.0 or
        light.ambient < 0.0)
    {
        return RenderError.InvalidScene;
    }
    return light;
}

const EditorRay = struct {
    origin: [3]f32,
    direction: [3]f32,
};

fn validatedEditorSelection(world: *const runtime.World, selected: ?runtime.EntityHandle) ?runtime.EntityHandle {
    const entity = selected orelse return null;
    _ = world.entity(entity) catch return null;
    return entity;
}

fn validatedEditorFieldSelection(world: *const runtime.World, selected: ?runtime.EntityHandle, field: EditorFieldSelection) EditorFieldSelection {
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

fn validatedEditorTextInput(world: *const runtime.World, selected: ?runtime.EntityHandle, input: EditorTextInputState) EditorTextInputState {
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

fn pickRenderableEntity(world: *const runtime.World, input: FrameInput) EditorError!?runtime.EntityHandle {
    if (!editorGameViewport(input).contains(input.pointer.position)) {
        return null;
    }
    const ray = try editorRayFromInput(world, input);
    var best_entity: ?runtime.EntityHandle = null;
    var best_t = std.math.inf(f32);

    var meshes = world.renderableMeshes();
    while (meshes.next()) |mesh| {
        const radius = editorPickRadiusForMesh(mesh);
        const hit_t = intersectRaySphere(ray, mesh.position, radius) orelse continue;
        if (hit_t >= 0.0 and hit_t < best_t) {
            best_t = hit_t;
            best_entity = mesh.entity;
        }
    }

    return best_entity;
}

fn pickEditorGizmoAxis(world: *const runtime.World, selected: runtime.EntityHandle, input: FrameInput) EditorError!EditorAxis {
    const transform_value = (try world.getTransform(selected)) orelse return .none;
    const camera = cameraStateForInput(world, input) catch return error.InvalidScene;
    const origin_screen = projectWorldToScreen(transform_value.position, camera, input) orelse return .none;
    const axes = [_]struct {
        axis: EditorAxis,
        vector: [3]f32,
    }{
        .{ .axis = .x, .vector = .{ 1.0, 0.0, 0.0 } },
        .{ .axis = .y, .vector = .{ 0.0, 1.0, 0.0 } },
        .{ .axis = .z, .vector = .{ 0.0, 0.0, 1.0 } },
    };

    var best_axis = EditorAxis.none;
    var best_distance = editor_gizmo_pick_radius_px;
    for (axes) |entry| {
        const end_screen = projectWorldToScreen(addVec3(transform_value.position, scaleVec3(entry.vector, editor_gizmo_axis_length)), camera, input) orelse continue;
        const distance = distancePointToScreenSegment(input.pointer.position, origin_screen, end_screen);
        if (distance < best_distance) {
            best_distance = distance;
            best_axis = entry.axis;
        }
    }
    return best_axis;
}

fn dragSelectedEntity(world: *runtime.World, state: *EditorState, input: FrameInput) EditorError!void {
    const selected = state.selected_entity orelse return;
    const transform_value = (try world.getTransform(selected)) orelse return;
    if (!state.has_last_pointer) {
        state.last_pointer = input.pointer.position;
        state.has_last_pointer = true;
        return;
    }

    const axis = editorAxisVector(state.dragging_axis) orelse return;
    const camera = cameraStateForInput(world, input) catch return error.InvalidScene;
    const origin_screen = projectWorldToScreen(transform_value.position, camera, input) orelse return;
    const axis_screen_end = projectWorldToScreen(addVec3(transform_value.position, scaleVec3(axis, editor_gizmo_axis_length)), camera, input) orelse return;
    const axis_screen_delta = subtractVec2(axis_screen_end, origin_screen);
    const axis_screen_length = vec2Length(axis_screen_delta);
    if (axis_screen_length < 0.001) {
        state.last_pointer = input.pointer.position;
        return;
    }

    const axis_screen = scaleVec2(axis_screen_delta, 1.0 / axis_screen_length);
    const pointer_delta = subtractVec2(input.pointer.position, state.last_pointer);
    const projected_pixels = dotVec2(pointer_delta, axis_screen);
    const camera_distance = vec3Length(subtractVec3(transform_value.position, camera.transform.position));
    const units_per_pixel = @max(camera_distance, 1.0) * 0.0025;
    const world_delta = projected_pixels * units_per_pixel;
    const next_position = addVec3(transform_value.position, scaleVec3(axis, world_delta));

    try world.setVec3(selected, runtime.transform_component_id, "position", next_position);
    state.last_pointer = input.pointer.position;
}

fn editorRayFromInput(world: *const runtime.World, input: FrameInput) EditorError!EditorRay {
    const viewport = editorGameViewport(input);
    const width = viewport.width;
    const height = viewport.height;
    if (width <= 0.0 or height <= 0.0) {
        return error.InvalidScene;
    }
    if (!viewport.contains(input.pointer.position)) {
        return error.InvalidScene;
    }
    const camera = cameraStateForInput(world, input) catch return error.InvalidScene;
    const aspect = width / height;
    const tan_half_fov = @tan(std.math.degreesToRadians(camera.fov_y_degrees) * 0.5);
    const local_pointer = subtractVec2(input.pointer.position, .{ viewport.x, viewport.y });
    const ndc_x = (local_pointer[0] / width) * 2.0 - 1.0;
    const ndc_y = 1.0 - (local_pointer[1] / height) * 2.0;
    const local_direction = normalizeVec3(.{
        ndc_x * tan_half_fov * aspect,
        ndc_y * tan_half_fov,
        -1.0,
    });
    return .{
        .origin = camera.transform.position,
        .direction = rotateDirection(camera.transform.rotation, local_direction),
    };
}

fn projectWorldToScreen(position: [3]f32, camera_value: CameraState, input: FrameInput) ?[2]f32 {
    const viewport = editorGameViewport(input);
    const width = viewport.width;
    const height = viewport.height;
    if (width <= 0.0 or height <= 0.0) {
        return null;
    }
    const camera = validateCamera(camera_value) catch return null;
    const view = cameraViewMatrix(camera.transform);
    const projection = perspective(std.math.degreesToRadians(camera.fov_y_degrees), width / height, camera.near, camera.far);
    const clip = transformPoint(matMul(projection, view), .{ position[0], position[1], position[2], 1.0 });
    if (@abs(clip[3]) < 0.00001) {
        return null;
    }
    const ndc_x = clip[0] / clip[3];
    const ndc_y = clip[1] / clip[3];
    if (!std.math.isFinite(ndc_x) or !std.math.isFinite(ndc_y)) {
        return null;
    }
    return .{
        viewport.x + (ndc_x + 1.0) * 0.5 * width,
        viewport.y + (1.0 - ndc_y) * 0.5 * height,
    };
}

fn intersectRaySphere(ray: EditorRay, center: [3]f32, radius: f32) ?f32 {
    const oc = subtractVec3(ray.origin, center);
    const a = dotVec3(ray.direction, ray.direction);
    const b = 2.0 * dotVec3(oc, ray.direction);
    const c = dotVec3(oc, oc) - radius * radius;
    const discriminant = b * b - 4.0 * a * c;
    if (discriminant < 0.0) {
        return null;
    }
    const root = @sqrt(discriminant);
    const near_t = (-b - root) / (2.0 * a);
    if (near_t >= 0.0) {
        return near_t;
    }
    const far_t = (-b + root) / (2.0 * a);
    return if (far_t >= 0.0) far_t else null;
}

fn editorPickRadiusForMesh(mesh: runtime.RenderableMesh) f32 {
    return @max(@max(@abs(mesh.scale[0]), @abs(mesh.scale[1])), @abs(mesh.scale[2])) * 1.25;
}

fn editorAxisVector(axis: EditorAxis) ?[3]f32 {
    return switch (axis) {
        .none => null,
        .x => .{ 1.0, 0.0, 0.0 },
        .y => .{ 0.0, 1.0, 0.0 },
        .z => .{ 0.0, 0.0, 1.0 },
    };
}

fn editorPlayButtonRect(input: FrameInput) ScreenRect {
    const top = editorTopBarRect(input);
    return .{
        .x = @max(top.width - editor_panel_padding_x - editor_control_button_width * 2.0 - editor_control_button_gap, editor_panel_padding_x),
        .y = top.y + (top.height - editor_control_button_height) * 0.5,
        .width = editor_control_button_width,
        .height = editor_control_button_height,
    };
}

fn editorStepButtonRect(input: FrameInput) ScreenRect {
    const play = editorPlayButtonRect(input);
    return .{
        .x = play.x + play.width + editor_control_button_gap,
        .y = play.y,
        .width = editor_control_button_width,
        .height = editor_control_button_height,
    };
}

const EditorCommand = enum {
    play_toggle,
    step,
};

const EditorUiRoute = union(enum) {
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
            .id = "machina.editor.controls.play",
            .name = "Editor Play",
            .rect = editorPlayButtonRect(input),
            .command = editor_command_play_toggle,
        },
        .{
            .id = "machina.editor.controls.step",
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

const editor_entity_select_command_prefix = "machina.editor.entity.select.";

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

fn routeEditorUi(
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
        if (std.mem.eql(u8, scroll_entity.id, "machina.editor.debug.systems.scroll")) {
            return .{ .system_scroll = scroll_route };
        }
        if (std.mem.eql(u8, scroll_entity.id, "machina.editor.entities.scroll")) {
            return .{ .entity_scroll = scroll_route };
        }
        if (std.mem.eql(u8, scroll_entity.id, "machina.editor.inspector.scroll")) {
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

fn routeEditorSplitterAt(allocator: std.mem.Allocator, input: FrameInput) EditorError!?EditorSplitter {
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
        .left => "machina.editor.shell.splitter.left.hit_area",
        .right => "machina.editor.shell.splitter.right.hit_area",
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
    const scroll = try world.createEntity("machina.editor.debug.systems.scroll", "Editor Debug Systems Scroll View");
    try world.setUiScrollView(scroll, .{
        .position = list_clip.position,
        .size = .{ hit_width, list_clip.size[1], 0.0 },
        .content_offset = .{ 0.0, system_scroll_target_y, 0.0 },
    });

    const content = try world.createEntity("machina.editor.debug.systems.scroll.content", "Editor Debug Systems Scroll Content");
    try world.setUiSpacer(content, .{
        .size = .{
            list_clip.size[0],
            editorSystemTableContentHeight(profile_count),
            0.0,
        },
    });
    try world.setUiLayoutItem(content, .{
        .parent = "machina.editor.debug.systems.scroll",
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
    const scroll = try world.createEntity("machina.editor.entities.scroll", "Editor Entities Scroll View");
    try world.setUiScrollView(scroll, .{
        .position = list_clip.position,
        .size = .{ hit_width, list_clip.size[1], 0.0 },
        .content_offset = .{ 0.0, entity_scroll_target_y, 0.0 },
    });

    const content = try world.createEntity("machina.editor.entities.scroll.content", "Editor Entities Scroll Content");
    try world.setUiSpacer(content, .{
        .size = .{
            list_clip.size[0],
            editorEntityTableContentHeight(scene_world.entityCount()),
            0.0,
        },
    });
    try world.setUiLayoutItem(content, .{
        .parent = "machina.editor.entities.scroll",
        .order = 0,
    });

    var route_input = input;
    route_input.editor.entity_scroll_y = entity_scroll_target_y;
    const range = editorEntityVisibleRange(scene_world, route_input);
    for (range.start..range.end) |entity_index| {
        const handle = editorEntityHandleAt(scene_world, entity_index) orelse continue;
        const id = std.fmt.allocPrint(world.allocator, "machina.editor.entities.row.{d}.hit", .{entity_index}) catch return error.OutOfMemory;
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
            .parent = "machina.editor.entities.scroll",
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
    const scroll = try world.createEntity("machina.editor.inspector.scroll", "Editor Inspector Scroll View");
    try world.setUiScrollView(scroll, .{
        .position = clip.position,
        .size = clip.size,
        .content_offset = .{ 0.0, inspector_scroll_target_y, 0.0 },
    });

    const content = try world.createEntity("machina.editor.inspector.scroll.content", "Editor Inspector Scroll Content");
    try world.setUiSpacer(content, .{
        .size = .{
            clip.size[0],
            editorInspectorComponentContentHeight(scene_world, input.editor.selected_entity),
            0.0,
        },
    });
    try world.setUiLayoutItem(content, .{
        .parent = "machina.editor.inspector.scroll",
        .order = 0,
    });
}

fn pickEditorInspectorProperty(world: *const runtime.World, input: FrameInput) EditorError!?EditorFieldSelection {
    const selected = input.editor.selected_entity orelse return null;
    _ = world.entity(selected) catch return null;
    const clip = editorInspectorScrollClipRect(input);
    if (!pointInsideScreenRect(input.pointer.position, .{ clip.position[0], clip.position[1] }, .{ clip.size[0], clip.size[1] })) {
        return null;
    }

    const card_width = @max(clip.size[0], 1.0);
    const value_x = editorInspectorFieldValueX(card_width);
    var content_y: f32 = -input.editor.inspector_scroll_y;
    var component_index: usize = 0;
    var components = world.entityComponents(selected) catch return null;
    while (components.next()) |component_id| {
        if (component_index > 0) {
            content_y += editor_inspector_separator_height;
        }
        const card_y = content_y;
        const field_count = world.componentFieldCount(component_id);
        const field_start_y = editor_inspector_card_padding_y + editorTextHeight(editor_inspector_text_size) + editor_panel_label_gap;
        for (0..field_count) |field_index| {
            const field_name = world.componentFieldNameAt(component_id, field_index) orelse continue;
            const field_y = clip.position[1] + card_y + field_start_y + @as(f32, @floatFromInt(field_index)) * editor_inspector_field_row_stride;
            const row_rect = ScreenRect{
                .x = clip.position[0],
                .y = field_y - 4.0,
                .width = card_width,
                .height = editorTextHeight(editor_inspector_text_size) + 8.0,
            };
            if (row_rect.contains(input.pointer.position)) {
                const value = world.getComponentFieldValue(selected, component_id, field_name) catch return null;
                return try makeEditorFieldSelection(selected, component_id, field_name, pickEditorPropertyVec3Lane(value, input.pointer.position[0], clip.position[0] + value_x, card_width));
            }
        }
        content_y += editorInspectorComponentCardHeight(world, component_id);
        component_index += 1;
    }

    return null;
}

fn pickEditorPropertyVec3Lane(value: runtime.ComponentValue, pointer_x: f32, value_screen_x: f32, card_width: f32) u2 {
    return switch (value) {
        .vec3 => blk: {
            const value_width = @max(card_width - editorInspectorFieldValueX(card_width) - editor_inspector_card_padding_x, 1.0);
            const lane_width = @max(value_width / 3.0, 1.0);
            const local_x = std.math.clamp(pointer_x - value_screen_x, 0.0, value_width - 0.001);
            break :blk @intCast(@min(@as(i32, @intFromFloat(@floor(local_x / lane_width))), 2));
        },
        else => 0,
    };
}

fn makeEditorFieldSelection(entity: runtime.EntityHandle, component_id: []const u8, field_name: []const u8, vec3_lane: u2) EditorError!EditorFieldSelection {
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

fn hitEditorChrome(input: FrameInput) bool {
    if (!input.debug_overlay_visible) {
        return false;
    }
    return !editorGameViewport(input).contains(input.pointer.position);
}

fn routeEditorScrollWheel(
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

fn pointInsideScreenRect(position: [2]f32, origin: [2]f32, size: [2]f32) bool {
    return position[0] >= origin[0] and position[1] >= origin[1] and position[0] <= origin[0] + size[0] and position[1] <= origin[1] + size[1];
}

fn editorViewportWidth(input: FrameInput) f32 {
    return if (input.viewport_width > 0.0) input.viewport_width else @as(f32, @floatFromInt(output_width));
}

fn editorViewportHeight(input: FrameInput) f32 {
    return if (input.viewport_height > 0.0) input.viewport_height else @as(f32, @floatFromInt(output_height));
}

const EditorSideWidths = struct {
    left: f32,
    right: f32,
};

const EditorBodyLayout = struct {
    body: ScreenRect,
    left: ScreenRect,
    left_splitter: ScreenRect,
    game: ScreenRect,
    right_splitter: ScreenRect,
    right: ScreenRect,
};

fn editorDefaultSideWidths(window_width: f32) EditorSideWidths {
    if (window_width <= 0.0) {
        return .{ .left = editor_left_sidebar_target_width, .right = editor_right_sidebar_target_width };
    }
    var left = std.math.clamp(window_width * 0.24, editor_left_sidebar_min_width, editor_left_sidebar_target_width);
    var right = std.math.clamp(window_width * 0.26, editor_right_sidebar_min_width, editor_right_sidebar_target_width);
    const max_side_total = @max(window_width - editor_min_game_viewport_width, 1.0);
    if (left + right > max_side_total) {
        const scale = max_side_total / (left + right);
        left = @max(left * scale, 1.0);
        right = @max(right * scale, 1.0);
    }
    return .{ .left = left, .right = right };
}

fn editorSideWidths(input: FrameInput) EditorSideWidths {
    const window_width = editorViewportWidth(input);
    var widths = editorDefaultSideWidths(window_width);
    if (input.editor.left_sidebar_width > 0.0) {
        widths.left = input.editor.left_sidebar_width;
    }
    if (input.editor.right_sidebar_width > 0.0) {
        widths.right = input.editor.right_sidebar_width;
    }
    return clampEditorSideWidths(widths, window_width);
}

fn clampEditorSideWidths(widths: EditorSideWidths, window_width: f32) EditorSideWidths {
    const max_side_total = @max(window_width - editor_min_game_viewport_width - editor_splitter_width * 2.0, 1.0);
    var left = std.math.clamp(widths.left, @min(editor_left_sidebar_min_width, max_side_total), max_side_total);
    var right = std.math.clamp(widths.right, @min(editor_right_sidebar_min_width, max_side_total), max_side_total);
    if (left + right > max_side_total) {
        const scale = max_side_total / (left + right);
        left = @max(left * scale, 1.0);
        right = @max(right * scale, 1.0);
    }
    return .{ .left = left, .right = right };
}

fn editorTopBarRect(input: FrameInput) ScreenRect {
    const window_width = editorViewportWidth(input);
    return .{
        .x = 0.0,
        .y = 0.0,
        .width = @max(window_width, 1.0),
        .height = editor_top_bar_height,
    };
}

fn editorBottomBarRect(input: FrameInput) ScreenRect {
    const window_width = editorViewportWidth(input);
    const window_height = editorViewportHeight(input);
    return .{
        .x = 0.0,
        .y = @max(window_height - editor_bottom_bar_height, editor_top_bar_height),
        .width = @max(window_width, 1.0),
        .height = editor_bottom_bar_height,
    };
}

fn editorBodyRect(input: FrameInput) ScreenRect {
    const window_width = editorViewportWidth(input);
    const window_height = editorViewportHeight(input);
    return .{
        .x = 0.0,
        .y = editor_top_bar_height,
        .width = @max(window_width, 1.0),
        .height = @max(window_height - editor_top_bar_height - editor_bottom_bar_height, 1.0),
    };
}

fn editorBodyLayout(input: FrameInput) EditorBodyLayout {
    const body = editorBodyRect(input);
    const widths = editorSideWidths(input);
    const left = ScreenRect{
        .x = body.x,
        .y = body.y,
        .width = widths.left,
        .height = body.height,
    };
    const left_splitter = ScreenRect{
        .x = left.x + left.width,
        .y = body.y,
        .width = editor_splitter_width,
        .height = body.height,
    };
    const right = ScreenRect{
        .x = body.x + body.width - widths.right,
        .y = body.y,
        .width = widths.right,
        .height = body.height,
    };
    const right_splitter = ScreenRect{
        .x = right.x - editor_splitter_width,
        .y = body.y,
        .width = editor_splitter_width,
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

fn editorLeftSidebarRect(input: FrameInput) ScreenRect {
    return editorBodyLayout(input).left;
}

fn editorRightSidebarRect(input: FrameInput) ScreenRect {
    return editorBodyLayout(input).right;
}

fn editorSplitterRect(input: FrameInput, splitter: EditorSplitter) ?ScreenRect {
    const layout = editorBodyLayout(input);
    return switch (splitter) {
        .none => null,
        .left => layout.left_splitter,
        .right => layout.right_splitter,
    };
}

fn editorSplitterHitRect(input: FrameInput, splitter: EditorSplitter) ?ScreenRect {
    const visual = editorSplitterRect(input, splitter) orelse return null;
    const extra_width = @max(editor_splitter_hit_width - visual.width, 0.0);
    return .{
        .x = visual.x - extra_width * 0.5,
        .y = visual.y,
        .width = visual.width + extra_width,
        .height = visual.height,
    };
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

fn editorCursorKind(allocator: std.mem.Allocator, input: FrameInput) EditorError!EditorCursorKind {
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

fn setEditorCursor(kind: EditorCursorKind, resize_ew_cursor: ?*anyopaque) void {
    switch (kind) {
        .default => sdl.machina_sdl_set_default_cursor(),
        .resize_ew => {
            if (resize_ew_cursor) |cursor| {
                sdl.machina_sdl_set_cursor(cursor);
            } else {
                sdl.machina_sdl_set_default_cursor();
            }
        },
    }
}

fn editorGameViewport(input: FrameInput) ScreenRect {
    const window_width = editorViewportWidth(input);
    const window_height = editorViewportHeight(input);
    if (!input.debug_overlay_visible) {
        return .{
            .x = 0.0,
            .y = 0.0,
            .width = @max(window_width, 1.0),
            .height = @max(window_height, 1.0),
        };
    }

    return editorBodyLayout(input).game;
}

pub fn editorGameViewportBounds(input: FrameInput) EditorViewportBounds {
    const viewport = editorGameViewport(input);
    return .{
        .x = viewport.x,
        .y = viewport.y,
        .width = viewport.width,
        .height = viewport.height,
    };
}

fn cameraViewMatrix(transform_value: runtime.Transform) [16]f32 {
    const inverse_translation = translation(
        -transform_value.position[0],
        -transform_value.position[1],
        -transform_value.position[2],
    );
    return matMul(
        rotationX(-transform_value.rotation[0]),
        matMul(
            rotationY(-transform_value.rotation[1]),
            matMul(rotationZ(-transform_value.rotation[2]), inverse_translation),
        ),
    );
}

fn lookAt(eye: [3]f32, target: [3]f32, up: [3]f32) [16]f32 {
    const z = normalizeVec3(subtractVec3(eye, target));
    const x = normalizeVec3(crossVec3(up, z));
    const y = crossVec3(z, x);

    return .{
        x[0],             y[0],             z[0],             0.0,
        x[1],             y[1],             z[1],             0.0,
        x[2],             y[2],             z[2],             0.0,
        -dotVec3(x, eye), -dotVec3(y, eye), -dotVec3(z, eye), 1.0,
    };
}

fn isFiniteVec3(value: [3]f32) bool {
    return std.math.isFinite(value[0]) and std.math.isFinite(value[1]) and std.math.isFinite(value[2]);
}

fn addVec3(left: [3]f32, right: [3]f32) [3]f32 {
    return .{ left[0] + right[0], left[1] + right[1], left[2] + right[2] };
}

fn subtractVec3(left: [3]f32, right: [3]f32) [3]f32 {
    return .{ left[0] - right[0], left[1] - right[1], left[2] - right[2] };
}

fn scaleVec3(value: [3]f32, scalar: f32) [3]f32 {
    return .{ value[0] * scalar, value[1] * scalar, value[2] * scalar };
}

fn dotVec3(left: [3]f32, right: [3]f32) f32 {
    return left[0] * right[0] + left[1] * right[1] + left[2] * right[2];
}

fn crossVec3(left: [3]f32, right: [3]f32) [3]f32 {
    return .{
        left[1] * right[2] - left[2] * right[1],
        left[2] * right[0] - left[0] * right[2],
        left[0] * right[1] - left[1] * right[0],
    };
}

fn normalizeVec3(value: [3]f32) [3]f32 {
    const length = vec3Length(value);
    if (length == 0.0) {
        return .{ 0.0, 0.0, 1.0 };
    }
    return .{ value[0] / length, value[1] / length, value[2] / length };
}

fn vec3Length(value: [3]f32) f32 {
    return @sqrt(value[0] * value[0] + value[1] * value[1] + value[2] * value[2]);
}

fn addVec2(left: [2]f32, right: [2]f32) [2]f32 {
    return .{ left[0] + right[0], left[1] + right[1] };
}

fn subtractVec2(left: [2]f32, right: [2]f32) [2]f32 {
    return .{ left[0] - right[0], left[1] - right[1] };
}

fn scaleVec2(value: [2]f32, scalar: f32) [2]f32 {
    return .{ value[0] * scalar, value[1] * scalar };
}

fn dotVec2(left: [2]f32, right: [2]f32) f32 {
    return left[0] * right[0] + left[1] * right[1];
}

fn vec2Length(value: [2]f32) f32 {
    return @sqrt(value[0] * value[0] + value[1] * value[1]);
}

fn distancePointToScreenSegment(point: [2]f32, start: [2]f32, end: [2]f32) f32 {
    const segment = subtractVec2(end, start);
    const segment_len_sq = dotVec2(segment, segment);
    if (segment_len_sq <= 0.00001) {
        return vec2Length(subtractVec2(point, start));
    }
    const raw_t = dotVec2(subtractVec2(point, start), segment) / segment_len_sq;
    const t = @max(0.0, @min(1.0, raw_t));
    const closest = addVec2(start, scaleVec2(segment, t));
    return vec2Length(subtractVec2(point, closest));
}

fn rotateDirection(rotation: [3]f32, direction: [3]f32) [3]f32 {
    const matrix = matMul(
        rotationZ(rotation[2]),
        matMul(
            rotationY(rotation[1]),
            rotationX(rotation[0]),
        ),
    );
    const rotated = transformPoint(matrix, .{ direction[0], direction[1], direction[2], 0.0 });
    return normalizeVec3(.{ rotated[0], rotated[1], rotated[2] });
}

fn transformPoint(matrix: [16]f32, point: [4]f32) [4]f32 {
    return .{
        matrix[0] * point[0] + matrix[4] * point[1] + matrix[8] * point[2] + matrix[12] * point[3],
        matrix[1] * point[0] + matrix[5] * point[1] + matrix[9] * point[2] + matrix[13] * point[3],
        matrix[2] * point[0] + matrix[6] * point[1] + matrix[10] * point[2] + matrix[14] * point[3],
        matrix[3] * point[0] + matrix[7] * point[1] + matrix[11] * point[2] + matrix[15] * point[3],
    };
}

test "camera state falls back only when no camera component exists" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const fallback = try cameraState(&world);
    try std.testing.expectEqual(@as(f32, 4.8), fallback.transform.position[2]);

    const camera_entity = try world.createEntity("camera", "Camera");
    try world.setCamera(camera_entity, .{});
    try std.testing.expectError(RenderError.InvalidScene, cameraState(&world));

    try world.setTransform(camera_entity, .{ .position = .{ 0.0, 0.0, 6.0 } });
    const resolved = try cameraState(&world);
    try std.testing.expectEqual(@as(f32, 6.0), resolved.transform.position[2]);
}

test "fly camera initializes from scene camera and moves while secondary mouse is held" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const camera_entity = try world.createEntity("camera", "Camera");
    try world.setTransform(camera_entity, .{ .position = .{ 0.0, 1.0, 6.0 } });
    try world.setCamera(camera_entity, .{});

    var state = FlyCameraState{};
    try std.testing.expect(try updateFlyCamera(&state, &world, .{}, 0.016) == null);

    const moved = (try updateFlyCamera(&state, &world, .{
        .pointer = .{
            .secondary_down = true,
            .delta = .{ 10.0, -5.0 },
        },
        .keyboard = .{
            .move_forward = true,
            .move_up = true,
        },
    }, 0.05)) orelse return error.TestExpectedEqual;

    try std.testing.expect(state.initialized);
    try std.testing.expect(moved.position[2] < 6.0);
    try std.testing.expect(moved.position[1] > 1.0);
    try std.testing.expect(moved.rotation[1] < 0.0);
    try std.testing.expect(moved.rotation[0] > 0.0);

    const persisted = (try updateFlyCamera(&state, &world, .{}, 0.016)) orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(moved.position[2], persisted.position[2], 0.0001);
}

test "fly camera ignores right mouse held over editor sidebar" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    var state = FlyCameraState{};
    const ignored = try updateFlyCamera(&state, &world, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{
            .position = .{ 1240.0, 80.0 },
            .has_position = true,
            .secondary_down = true,
            .delta = .{ 100.0, 0.0 },
        },
        .keyboard = .{ .move_forward = true },
    }, 0.05);

    try std.testing.expect(ignored == null);
    try std.testing.expect(!state.initialized);
}

test "editor raycast selects nearest renderable mesh" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const far = try world.createEntity("far", "Far");
    try world.setTransform(far, .{ .position = .{ 0.0, 0.0, -2.0 } });
    try world.setCubeRenderer(far, .{ .color = .{ 0.2, 0.4, 0.8 } });

    const near = try world.createEntity("near", "Near");
    try world.setTransform(near, .{ .position = .{ 0.0, 0.0, 0.0 } });
    try world.setCubeRenderer(near, .{ .color = .{ 0.8, 0.4, 0.2 } });

    var editor_state = EditorState{};
    const input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    const game_viewport = editorGameViewport(input);
    const update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = input.debug_overlay_visible,
        .viewport_width = input.viewport_width,
        .viewport_height = input.viewport_height,
        .pointer = .{
            .position = .{ game_viewport.x + game_viewport.width * 0.5, game_viewport.y + game_viewport.height * 0.5 },
            .has_position = true,
            .primary_pressed = true,
            .primary_down = true,
        },
    });

    try std.testing.expect(update.consumed_pointer);
    try std.testing.expect(editor_state.selected_entity != null);
    try std.testing.expectEqual(near.index, editor_state.selected_entity.?.index);
    try std.testing.expectEqual(near.generation, editor_state.selected_entity.?.generation);
}

test "editor gizmo drag mutates selected transform position" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("selected", "Selected");
    try world.setTransform(entity, .{ .position = .{ 0.0, 0.0, 0.0 } });
    try world.setCubeRenderer(entity, .{ .color = .{ 0.8, 0.4, 0.2 } });

    var editor_state = EditorState{
        .selected_entity = entity,
        .dragging_axis = .x,
        .has_last_pointer = true,
    };
    const input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    const game_viewport = editorGameViewport(input);
    editor_state.last_pointer = .{ game_viewport.x + game_viewport.width * 0.5, game_viewport.y + game_viewport.height * 0.5 };
    const update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = input.debug_overlay_visible,
        .viewport_width = input.viewport_width,
        .viewport_height = input.viewport_height,
        .pointer = .{
            .position = .{ editor_state.last_pointer[0] + 40.0, editor_state.last_pointer[1] },
            .has_position = true,
            .primary_down = true,
        },
    });

    const transform_value = (try world.getTransform(entity)) orelse return error.TestExpectedEqual;
    try std.testing.expect(update.consumed_pointer);
    try std.testing.expect(transform_value.position[0] > 0.0);
    try std.testing.expectEqual(@as(f32, 0.0), transform_value.position[1]);
    try std.testing.expectEqual(@as(f32, 0.0), transform_value.position[2]);
}

test "editor playback controls toggle pause and request single step" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    var editor_state = EditorState{};
    const frame_input = FrameInput{ .debug_overlay_visible = true };
    const play_rect = editorPlayButtonRect(frame_input);
    const pause_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .pointer = .{
            .position = .{ play_rect.x + 4.0, play_rect.y + 4.0 },
            .has_position = true,
            .primary_pressed = true,
            .primary_down = true,
        },
    });
    try std.testing.expect(pause_update.consumed_pointer);
    try std.testing.expect(editor_state.paused);

    const release_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .pointer = .{
            .position = .{ play_rect.x + 4.0, play_rect.y + 4.0 },
            .has_position = true,
            .primary_released = true,
        },
    });
    try std.testing.expect(release_update.consumed_pointer);
    try std.testing.expect(!editor_state.captured_pointer);

    const step_rect = editorStepButtonRect(frame_input);
    const step_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .pointer = .{
            .position = .{ step_rect.x + 4.0, step_rect.y + 4.0 },
            .has_position = true,
            .primary_pressed = true,
            .primary_down = true,
        },
    });
    try std.testing.expect(step_update.consumed_pointer);
    try std.testing.expect(step_update.step_once);
    try std.testing.expect(editor_state.paused);
}

test "editor chrome routes pointer through one retained ui route" {
    const profiles = [_]runtime.SystemProfileSnapshot{
        .{ .id = "system.0", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.1", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.2", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.3", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.4", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.5", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.6", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.7", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.8", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
    };
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .system_profiles = &profiles,
        .system_profile_count_hint = 20,
    };
    const play_rect = editorPlayButtonRect(frame_input);
    const command_route = (try routeEditorUi(std.testing.allocator, null, 0.0, 0.0, 0.0, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = .{ play_rect.x + 4.0, play_rect.y + 4.0 },
            .has_position = true,
            .primary_pressed = true,
        },
    }, profiles.len)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(EditorCommand.play_toggle, command_route.command);

    const left_splitter = editorSplitterRect(frame_input, .left) orelse return error.TestExpectedEqual;
    const splitter_route = (try routeEditorUi(std.testing.allocator, null, 0.0, 0.0, 0.0, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = .{ left_splitter.x + left_splitter.width + 3.0, left_splitter.y + 40.0 },
            .has_position = true,
            .primary_pressed = true,
        },
    }, profiles.len)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(EditorSplitter.left, splitter_route.splitter);

    const scroll_point = editorSystemListHitTestPoint(&profiles, 20);
    const scroll_route = (try routeEditorUi(std.testing.allocator, null, 0.0, 0.0, 0.0, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .system_profiles = &profiles,
        .system_profile_count_hint = 20,
        .pointer = .{
            .position = scroll_point,
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    }, 20)) orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel), scroll_route.system_scroll.next_offset[1], 0.001);
}

pub fn editorSystemListHitTestPoint(profiles: []const runtime.SystemProfileSnapshot, profile_count_hint: usize) [2]f32 {
    const list_clip = editorSystemListClipRect(.{
        .debug_overlay_visible = true,
        .system_profiles = profiles,
        .system_profile_count_hint = profile_count_hint,
    });
    return .{ list_clip.position[0] + 4.0, list_clip.position[1] + 4.0 };
}

test "editor system list scroll state responds to wheel input" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{ .id = "system.0", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.1", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.2", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.3", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.4", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.5", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.6", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.7", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.8", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
    };

    var editor_state = EditorState{};
    const pointer = editorSystemListHitTestPoint(&profiles, 0);
    const down_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = pointer,
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });
    try std.testing.expect(down_update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel), editor_state.system_scroll_target_y, 0.001);
    try std.testing.expect(editor_state.system_scroll_y > 0.0);
    try std.testing.expect(editor_state.system_scroll_y < editor_state.system_scroll_target_y);

    const up_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = pointer,
            .has_position = true,
            .wheel_delta = .{ 0.0, 1.0 },
        },
    });
    try std.testing.expect(up_update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), editor_state.system_scroll_target_y, 0.001);
}

test "editor system list wheel scroll ignores pointer outside list" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{ .id = "system.0", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.1", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.2", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.3", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.4", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.5", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.6", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.7", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.8", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
    };

    var editor_state = EditorState{ .system_scroll_boundary = .bottom };
    const update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = .{ 1200.0, 680.0 },
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });

    try std.testing.expect(!update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), editor_state.system_scroll_target_y, 0.001);
    try std.testing.expectEqual(EditorScrollBoundary.none, editor_state.system_scroll_boundary);
}

test "editor system list uses profile count hint for render-added rows" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{ .id = "project.0", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "project.1", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
    };

    var editor_state = EditorState{};
    const update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
        .system_profile_count_hint = 9,
        .pointer = .{
            .position = editorSystemListHitTestPoint(&profiles, 9),
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });

    try std.testing.expect(update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel), editor_state.system_scroll_target_y, 0.001);
}

test "editor system list uses fixed wheel direction" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{ .id = "system.0", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.1", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.2", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.3", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.4", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.5", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.6", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.7", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.8", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
    };

    var editor_state = EditorState{};
    const pointer = editorSystemListHitTestPoint(&profiles, 0);
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = pointer,
            .has_position = true,
            .wheel_delta = .{ 0.0, 1.0 },
        },
    });
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), editor_state.system_scroll_target_y, 0.001);

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
    });

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = pointer,
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel), editor_state.system_scroll_target_y, 0.001);

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
    });

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = pointer,
            .has_position = true,
            .wheel_delta = .{ 0.0, 1.0 },
        },
    });
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), editor_state.system_scroll_target_y, 0.001);
}

test "editor system list supports fractional pixel scroll" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{ .id = "system.0", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.1", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.2", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.3", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.4", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.5", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.6", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.7", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.8", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
    };

    var editor_state = EditorState{};
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .viewport_height = 440.0,
        .system_profiles = &profiles,
        .pointer = .{
            .position = editorSystemListHitTestPoint(&profiles, 0),
            .has_position = true,
            .wheel_delta = .{ 0.0, -0.5 },
        },
    });
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel / 2.0), editor_state.system_scroll_target_y, 0.001);
    editor_state.system_scroll_y = editor_state.system_scroll_target_y;

    const range_input = FrameInput{
        .viewport_height = 440.0,
        .system_profiles = &profiles,
        .editor = editorFrameState(&world, editor_state),
    };
    const range = editorSystemVisibleRange(range_input);
    try std.testing.expectEqual(@as(usize, 0), range.start);
    try std.testing.expectEqual(editorSystemVisibleRows(range_input) + 1, range.end);
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel / 2.0), range.offset_y, 0.001);
}

test "editor system list animates toward scroll target" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{ .id = "system.0", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.1", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.2", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.3", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.4", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.5", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.6", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.7", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.8", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
    };

    var editor_state = EditorState{};
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 0.016,
        .system_profiles = &profiles,
        .pointer = .{
            .position = editorSystemListHitTestPoint(&profiles, 0),
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });

    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel), editor_state.system_scroll_target_y, 0.001);
    try std.testing.expect(editor_state.system_scroll_y > 0.0);
    try std.testing.expect(editor_state.system_scroll_y < editor_state.system_scroll_target_y);

    const previous_scroll_y = editor_state.system_scroll_y;
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .system_profiles = &profiles,
    });
    try std.testing.expect(editor_state.system_scroll_y > previous_scroll_y);
    try std.testing.expect(editor_state.system_scroll_y < editor_state.system_scroll_target_y);
}

fn replayEditorScrollFrames(
    world: *runtime.World,
    editor_state: *EditorState,
    profiles: []const runtime.SystemProfileSnapshot,
    wheel_deltas: []const f32,
) !void {
    const pointer = editorSystemListHitTestPoint(profiles, 0);
    for (wheel_deltas) |delta| {
        _ = try updateEditorState(std.testing.allocator, world, editor_state, .{
            .debug_overlay_visible = true,
            .delta_seconds = 1.0,
            .viewport_height = 440.0,
            .system_profiles = profiles,
            .pointer = .{
                .position = pointer,
                .has_position = true,
                .wheel_delta = .{ 0.0, delta },
            },
        });
    }
}

test "editor system list replay applies fractional scroll away from the bottom" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{ .id = "system.0", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.1", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.2", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.3", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.4", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.5", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.6", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.7", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.8", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
    };

    var editor_state = EditorState{
        .system_scroll_y = editor_system_row_stride * 2.0,
        .system_scroll_target_y = editor_system_row_stride * 2.0,
    };

    const bounce_frames = [_]f32{
        0.18, 0.0, 0.24, 0.0, 0.12, 0.0, 0.2,
    };
    try replayEditorScrollFrames(&world, &editor_state, &profiles, &bounce_frames);
    const bounced_target = editor_system_row_stride * 2.0 - editor_system_scroll_pixels_per_wheel * 0.74;
    try std.testing.expectApproxEqAbs(bounced_target, editor_state.system_scroll_target_y, 0.001);

    const deliberate_reverse_frames = [_]f32{1.0};
    try replayEditorScrollFrames(&world, &editor_state, &profiles, &deliberate_reverse_frames);
    try std.testing.expectApproxEqAbs(bounced_target - editor_system_scroll_pixels_per_wheel, editor_state.system_scroll_target_y, 0.001);
}

test "editor system list replay handles mixed wheel directions without sticky boundary" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{ .id = "system.0", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.1", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.2", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.3", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.4", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.5", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.6", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.7", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
        .{ .id = "system.8", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
    };

    var editor_state = EditorState{};
    const frames = [_]f32{
        -1.0, -1.0, -1.0, -1.0, 1.0, 1.0, -0.75, 2.0, -1.0,
    };
    try replayEditorScrollFrames(&world, &editor_state, &profiles, &frames);
    try std.testing.expectApproxEqAbs(@as(f32, 31.5), editor_state.system_scroll_target_y, 0.001);

    const deliberate_reverse_after_idle = [_]f32{ 0.0, 1.0 };
    try replayEditorScrollFrames(&world, &editor_state, &profiles, &deliberate_reverse_after_idle);
    try std.testing.expectApproxEqAbs(@as(f32, 13.5), editor_state.system_scroll_target_y, 0.001);
}

test "render ECS schedule orders extract prepare queue and draw systems" {
    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();

    try std.testing.expectEqual(@as(usize, 7), state.schedule.systemCount());
    try std.testing.expectEqual(@as(usize, 6), state.schedule.batchCount());

    const expected = [_][]const u8{
        render_extract_system_id,
        render_prepare_meshes_system_id,
        render_interact_ui_system_id,
        render_queue_meshes_system_id,
        render_prepare_ui_system_id,
        render_queue_ui_system_id,
        render_draw_meshes_system_id,
    };
    var expected_index: usize = 0;
    for (state.schedule.batches) |batch| {
        try std.testing.expectEqual(runtime.SystemPhase.render, batch.phase);
        for (batch.systems) |system| {
            try std.testing.expect(expected_index < expected.len);
            try std.testing.expectEqualStrings(expected[expected_index], system.id);
            expected_index += 1;
        }
    }
    try std.testing.expectEqual(expected.len, expected_index);
}

test "render ECS extracts scene data and queues mesh draw commands" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const cool_box = try scene_world.createEntity("cool-box", "Cool Box");
    try scene_world.setTransform(cool_box, .{
        .position = .{ -1.0, 0.0, 0.0 },
        .rotation = .{ 0.1, 0.2, 0.3 },
    });
    try scene_world.setCubeRenderer(cool_box, .{
        .color = .{ 0.1, 0.5, 1.0 },
    });
    try scene_world.setShadowCaster(cool_box);

    const warm_sphere = try scene_world.createEntity("warm-sphere", "Warm Sphere");
    try scene_world.setTransform(warm_sphere, .{
        .position = .{ 1.0, 0.0, 0.0 },
        .scale = .{ 0.8, 0.8, 0.8 },
    });
    try scene_world.setGeometryPrimitive(warm_sphere, .{
        .primitive = "uv_sphere",
        .segments = 16,
        .rings = 8,
    });
    try scene_world.setSurfaceMaterial(warm_sphere, .{
        .base_color = .{ 1.0, 0.35, 0.12 },
    });
    try scene_world.setShadowReceiver(warm_sphere);

    const camera = try scene_world.createEntity("camera", "Camera");
    try scene_world.setTransform(camera, .{ .position = .{ 0.0, 1.0, 7.0 } });
    try scene_world.setCamera(camera, .{ .fov_y_degrees = 52.0 });

    const light = try scene_world.createEntity("key-light", "Key Light");
    try scene_world.setDirectionalLight(light, .{ .intensity = 1.25 });

    const canvas = try scene_world.createEntity("debug-canvas", "Debug Canvas");
    try scene_world.setUiCanvas(canvas, .{});

    const panel = try scene_world.createEntity("debug-panel", "Debug Panel");
    try scene_world.setUiRect(panel, .{
        .position = .{ 24.0, 24.0, 0.0 },
        .size = .{ 180.0, 58.0, 0.0 },
        .color = .{ 0.02, 0.08, 0.16 },
    });
    try scene_world.setUiButton(panel);

    const label = try scene_world.createEntity("debug-label", "Debug Label");
    try scene_world.setUiText(label, .{
        .position = .{ 38.0, 42.0, 0.0 },
        .size = 2.0,
        .color = .{ 1.0, 0.68, 0.16 },
        .value = "UI READY",
    });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractScene(.{ .world = &scene_world });

    try std.testing.expectEqual(@as(usize, 8), state.world.entityCount());
    try std.testing.expectEqual(@as(usize, 2), state.world.renderableMeshCount());
    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.ui_canvas_component_id));
    try std.testing.expectEqual(@as(usize, 1), state.world.uiRectCount());
    try std.testing.expectEqual(@as(usize, 1), state.world.uiTextCount());
    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.input_pointer_component_id));
    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.input_keyboard_component_id));
    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.input_frame_component_id));
    try std.testing.expectEqual(@as(f32, 52.0), (state.world.renderCamera() orelse return error.TestExpectedEqual).fov_y_degrees);
    try std.testing.expectEqual(@as(f32, 1.25), (state.world.renderDirectionalLight() orelse return error.TestExpectedEqual).intensity);
    const extracted_sphere = state.world.renderableMeshAt(1) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("uv_sphere", extracted_sphere.primitive);
    try std.testing.expectEqual(@as(f32, 0.35), extracted_sphere.base_color[1]);
    const extracted_box = state.world.renderableMeshAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expect(extracted_box.casts_shadow);
    try std.testing.expect(!extracted_box.receives_shadow);
    try std.testing.expect(!extracted_sphere.casts_shadow);
    try std.testing.expect(extracted_sphere.receives_shadow);

    var plan = try BatchPlan.build(std.testing.allocator, &state.world);
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 2), plan.batches.len);

    try state.queueBatchDraws(plan.batches.len);
    try std.testing.expectEqual(@as(usize, 2), state.drawCommandCount());

    var cursor: usize = 0;
    const draw_query = [_][]const u8{render_draw_batch_component_id};
    const first_draw = state.world.queryNext(&draw_query, &cursor) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 0), try state.drawCommandBatchIndex(first_draw));
    const second_draw = state.world.queryNext(&draw_query, &cursor) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), try state.drawCommandBatchIndex(second_draw));
    try std.testing.expect(state.world.queryNext(&draw_query, &cursor) == null);

    const extracted_panel = state.world.uiRectAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expect(extracted_panel.is_button);
    const extracted_label = state.world.uiTextAt(0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("UI READY", extracted_label.value);
    try state.queueUiDraw();
    try std.testing.expectEqual(@as(usize, 1), state.uiDrawCommandCount());
}

test "batch plan groups matching geometry and shadow state with per-instance color" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    try addBatchTestRenderable(&scene_world, "blue-box-a", "box", 0, 0, .{ -1.6, 0.0, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "gold-sphere", "uv_sphere", 16, 8, .{ 0.0, 0.0, 0.0 }, .{ 1.0, 0.56, 0.1 }, .{});
    try addBatchTestRenderable(&scene_world, "blue-box-b", "box", 0, 0, .{ 1.6, 0.0, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "red-box", "box", 0, 0, .{ 0.0, 1.2, 0.0 }, .{ 0.95, 0.12, 0.18 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "blue-box-receiver", "box", 0, 0, .{ 0.0, -1.2, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .receives_shadow = true });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractScene(.{ .world = &scene_world });

    var plan = try BatchPlan.build(std.testing.allocator, &state.world);
    defer plan.deinit();

    try std.testing.expectEqual(@as(usize, 3), plan.batches.len);
    try std.testing.expectEqual(geometry.Primitive.box, plan.batches[0].geometry_key.primitive);
    try std.testing.expect(plan.batches[0].shadow_key.casts_shadow);
    try std.testing.expect(!plan.batches[0].shadow_key.receives_shadow);
    try std.testing.expectEqual(@as(usize, 3), plan.batches[0].render_indices.len);
    try std.testing.expectEqual(@as(usize, 0), plan.batches[0].render_indices[0]);
    try std.testing.expectEqual(@as(usize, 2), plan.batches[0].render_indices[1]);
    try std.testing.expectEqual(@as(usize, 3), plan.batches[0].render_indices[2]);

    try std.testing.expectEqual(geometry.Primitive.uv_sphere, plan.batches[1].geometry_key.primitive);
    try std.testing.expectEqual(@as(usize, 1), plan.batches[1].render_indices.len);
    try std.testing.expectEqual(@as(usize, 1), plan.batches[1].render_indices[0]);

    try std.testing.expectEqual(geometry.Primitive.box, plan.batches[2].geometry_key.primitive);
    try std.testing.expect(!plan.batches[2].shadow_key.casts_shadow);
    try std.testing.expect(plan.batches[2].shadow_key.receives_shadow);
    try std.testing.expectEqual(@as(usize, 1), plan.batches[2].render_indices.len);
    try std.testing.expectEqual(@as(usize, 4), plan.batches[2].render_indices[0]);

    try state.queueBatchDraws(plan.batches.len);
    try std.testing.expectEqual(@as(usize, 3), state.drawCommandCount());
}

test "render stats reports mesh renderables and planned batches" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    try addBatchTestRenderable(&scene_world, "blue-box-a", "box", 0, 0, .{ -1.6, 0.0, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "gold-sphere", "uv_sphere", 16, 8, .{ 0.0, 0.0, 0.0 }, .{ 1.0, 0.56, 0.1 }, .{});
    try addBatchTestRenderable(&scene_world, "blue-box-b", "box", 0, 0, .{ 1.6, 0.0, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "red-box", "box", 0, 0, .{ 0.0, 1.2, 0.0 }, .{ 0.95, 0.12, 0.18 }, .{ .casts_shadow = true });
    try addBatchTestRenderable(&scene_world, "blue-box-receiver", "box", 0, 0, .{ 0.0, -1.2, 0.0 }, .{ 0.08, 0.42, 1.0 }, .{ .receives_shadow = true });

    const result = try stats(std.testing.allocator, .{ .world = &scene_world });

    try std.testing.expectEqual(@as(usize, 5), result.renderables);
    try std.testing.expectEqual(@as(usize, 3), result.render_batches);
    try std.testing.expectEqual(@as(usize, 0), result.ui_rects);
    try std.testing.expectEqual(@as(usize, 0), result.ui_texts);
}

test "UI vertex builder expands rects and fixed pixel text" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const panel = try world.createEntity("panel", "Panel");
    try world.setUiRect(panel, .{
        .position = .{ 32.0, 24.0, 0.0 },
        .size = .{ 120.0, 48.0, 0.0 },
        .color = .{ 0.0, 0.2, 0.4 },
    });

    const label = try world.createEntity("label", "Label");
    try world.setUiText(label, .{
        .position = .{ 42.0, 36.0, 0.0 },
        .size = 2.0,
        .color = .{ 1.0, 0.8, 0.2 },
        .value = "UI 1",
    });

    var vertices = try buildUiVertices(std.testing.allocator, &world, 640, 480);
    defer vertices.deinit(std.testing.allocator);

    try std.testing.expect(vertices.items.len > 6);
    try std.testing.expectEqual(@as(f32, -0.9), vertices.items[0].position[0]);
    try std.testing.expect(vertices.items[0].position[1] > 0.8);
}

test "UI hit testing uses half-open screen rects" {
    const position = [3]f32{ 32.0, 24.0, 0.0 };
    const size = [3]f32{ 120.0, 48.0, 0.0 };

    try std.testing.expect(runtime.pointInsideUiRect(.{ 32.0, 24.0 }, position, size));
    try std.testing.expect(runtime.pointInsideUiRect(.{ 151.99, 71.99 }, position, size));
    try std.testing.expect(!runtime.pointInsideUiRect(.{ 152.0, 72.0 }, position, size));
    try std.testing.expect(!runtime.pointInsideUiRect(.{ 31.99, 24.0 }, position, size));
}

test "UI layout resolves scroll views and vbox rows" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const scroll = try world.createEntity("scroll", "Scroll View");
    try world.setUiScrollView(scroll, .{
        .position = .{ 40.0, 50.0, 0.0 },
        .size = .{ 100.0, 60.0, 0.0 },
        .content_offset = .{ 0.0, 20.0, 0.0 },
    });

    const stack = try world.createEntity("stack", "Stack");
    try world.setUiVBox(stack, .{
        .position = .{ 8.0, 10.0, 0.0 },
        .spacing = 4.0,
    });
    try world.setUiLayoutItem(stack, .{ .parent = "scroll", .order = 0 });

    const first = try world.createEntity("first", "First");
    try world.setUiText(first, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = 1.0,
        .value = "FIRST",
    });
    try world.setUiLayoutItem(first, .{ .parent = "stack", .order = 0 });

    const second = try world.createEntity("second", "Second");
    try world.setUiText(second, .{
        .position = .{ 2.0, 3.0, 0.0 },
        .size = 1.0,
        .value = "SECOND",
    });
    try world.setUiLayoutItem(second, .{ .parent = "stack", .order = 1 });

    const first_layout = try resolveUiLayout(&world, first, .{ 0.0, 0.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), first_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), first_layout.position[1], 0.001);

    const second_layout = try resolveUiLayout(&world, second, .{ 2.0, 3.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), second_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 79.0), second_layout.position[1], 0.001);
    const clip = second_layout.clip orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), clip.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), clip.position[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), clip.size[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 60.0), clip.size[1], 0.001);
}

test "UI stack layout resolves horizontal rows and text block centering" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const stack = try world.createEntity("stack", "Stack");
    try world.setUiStack(stack, .{
        .position = .{ 20.0, 30.0, 0.0 },
        .spacing = 3.0,
        .direction = "horizontal",
        .padding = .{ 5.0, 6.0, 0.0 },
    });

    const first = try world.createEntity("first", "First");
    try world.setUiRect(first, .{
        .position = .{ 1.0, 2.0, 0.0 },
        .size = .{ 20.0, 10.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
    });
    try world.setUiLayoutItem(first, .{ .parent = "stack", .order = 0 });

    const second = try world.createEntity("second", "Second");
    try world.setUiRect(second, .{
        .position = .{ 2.0, 4.0, 0.0 },
        .size = .{ 12.0, 10.0, 0.0 },
        .color = .{ 0.2, 0.3, 0.4 },
    });
    try world.setUiLayoutItem(second, .{ .parent = "stack", .order = 1 });

    const first_layout = try resolveUiLayout(&world, first, .{ 1.0, 2.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 26.0), first_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 38.0), first_layout.position[1], 0.001);

    const second_layout = try resolveUiLayout(&world, second, .{ 2.0, 4.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), second_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), second_layout.position[1], 0.001);

    const bad_stack = try world.createEntity("bad-stack", "Bad Stack");
    try world.setUiStack(bad_stack, .{ .direction = "diagonal" });
    const bad_child = try world.createEntity("bad-child", "Bad Child");
    try world.setUiRect(bad_child, .{});
    try world.setUiLayoutItem(bad_child, .{ .parent = "bad-stack" });
    try std.testing.expectError(RenderError.InvalidScene, resolveUiLayout(&world, bad_child, .{ 0.0, 0.0, 0.0 }));

    const label = try world.createEntity("label", "Label");
    try world.setUiText(label, .{
        .position = .{ 10.0, 20.0, 0.0 },
        .size = 1.0,
        .value = "OK",
    });
    try world.setUiTextBlock(label, .{
        .size = .{ 100.0, 48.0, 0.0 },
        .horizontal_align = "center",
        .vertical_align = "center",
    });
    const label_position = try resolveUiTextPosition(&world, label, world.uiTextAt(0) orelse return error.TestExpectedEqual, .{ 10.0, 20.0, 0.0 });
    const label_size = textPixelSize("OK", 1.0);
    try std.testing.expectApproxEqAbs(10.0 + (100.0 - label_size[0]) * 0.5, label_position[0], 0.001);
    try std.testing.expectApproxEqAbs(20.0 + (48.0 - label_size[1]) * 0.5, label_position[1], 0.001);
}

test "UI layout item can inherit a rect parent's layout chain" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const stack = try world.createEntity("stack", "Stack");
    try world.setUiStack(stack, .{
        .position = .{ 80.0, 40.0, 0.0 },
        .spacing = 12.0,
        .direction = "horizontal",
        .padding = .{ 8.0, 6.0, 0.0 },
    });

    const button = try world.createEntity("button", "Button");
    try world.setUiRect(button, .{
        .position = .{ 2.0, 3.0, 0.0 },
        .size = .{ 120.0, 48.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
    });
    try world.setUiLayoutItem(button, .{ .parent = "stack", .order = 0 });

    const label = try world.createEntity("button-label", "Button Label");
    try world.setUiText(label, .{
        .position = .{ 0.0, 0.0, 0.0 },
        .size = 1.0,
        .value = "ACTION",
    });
    try world.setUiTextBlock(label, .{
        .size = .{ 120.0, 48.0, 0.0 },
        .horizontal_align = "center",
        .vertical_align = "center",
    });
    try world.setUiLayoutItem(label, .{ .parent = "button", .order = 0 });

    const label_layout = try resolveUiLayout(&world, label, .{ 0.0, 0.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 90.0), label_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 49.0), label_layout.position[1], 0.001);

    const text = world.uiTextAt(0) orelse return error.TestExpectedEqual;
    const centered = try resolveUiTextPosition(&world, label, text, label_layout.position);
    const label_size = textPixelSize("ACTION", 1.0);
    try std.testing.expectApproxEqAbs(90.0 + (120.0 - label_size[0]) * 0.5, centered[0], 0.001);
    try std.testing.expectApproxEqAbs(49.0 + (48.0 - label_size[1]) * 0.5, centered[1], 0.001);
}

test "UI layout item margins participate in stack placement" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const stack = try world.createEntity("stack", "Stack");
    try world.setUiStack(stack, .{
        .position = .{ 20.0, 30.0, 0.0 },
        .spacing = 4.0,
        .direction = "horizontal",
    });

    const first = try world.createEntity("first", "First");
    try world.setUiRect(first, .{ .size = .{ 20.0, 10.0, 0.0 } });
    try world.setUiLayoutItem(first, .{ .parent = "stack", .order = 0, .margin = .{ 3.0, 5.0, 0.0 } });

    const second = try world.createEntity("second", "Second");
    try world.setUiRect(second, .{ .size = .{ 12.0, 10.0, 0.0 } });
    try world.setUiLayoutItem(second, .{ .parent = "stack", .order = 1, .margin = .{ 2.0, 1.0, 0.0 } });

    const first_layout = try resolveUiLayout(&world, first, .{ 0.0, 0.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 23.0), first_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 35.0), first_layout.position[1], 0.001);

    const second_layout = try resolveUiLayout(&world, second, .{ 0.0, 0.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 52.0), second_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 31.0), second_layout.position[1], 0.001);
}

test "UI canvas fit scaling transforms scene UI vertices" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try writeFrameInput(&world, .{
        .viewport_width = 200.0,
        .viewport_height = 100.0,
        .ui_visible = true,
    });

    const canvas = try world.createEntity("canvas", "Canvas");
    try world.setUiCanvas(canvas, .{
        .design_size = .{ 100.0, 100.0, 0.0 },
        .scale_mode = "fit",
    });

    const panel = try world.createEntity("panel", "Panel");
    try world.setUiRect(panel, .{
        .position = .{ 10.0, 10.0, 0.0 },
        .size = .{ 20.0, 10.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
    });
    try world.setUiBorder(panel, .{
        .color = .{ 0.5, 0.6, 0.7 },
        .thickness = 2.0,
    });

    var vertices = try buildUiVertices(std.testing.allocator, &world, 200, 100);
    defer vertices.deinit(std.testing.allocator);

    try std.testing.expect(vertices.items.len >= 12);
    try std.testing.expectApproxEqAbs(@as(f32, -0.4), vertices.items[0].position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), vertices.items[0].position[1], 0.001);
}

test "UI canvas fit scaling targets editor game viewport when editor is visible" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try writeFrameInput(&world, .{
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .ui_visible = true,
        .debug_overlay_visible = true,
    });

    const canvas = try world.createEntity("canvas", "Canvas");
    try world.setUiCanvas(canvas, .{
        .design_size = .{ 100.0, 100.0, 0.0 },
        .scale_mode = "fit",
    });

    const panel = try world.createEntity("panel", "Panel");
    try world.setUiRect(panel, .{
        .position = .{ 10.0, 10.0, 0.0 },
        .size = .{ 20.0, 10.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
    });

    var vertices = try buildUiVertices(std.testing.allocator, &world, 1280, 720);
    defer vertices.deinit(std.testing.allocator);

    const viewport = editorGameViewport(.{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    });
    const scale = @min(viewport.width / 100.0, viewport.height / 100.0);
    const expected_x = viewport.x + (viewport.width - 100.0 * scale) * 0.5 + 10.0 * scale;
    const expected_y = viewport.y + (viewport.height - 100.0 * scale) * 0.5 + 10.0 * scale;

    try std.testing.expectApproxEqAbs(screenToClipX(expected_x, 1280), vertices.items[0].position[0], 0.001);
    try std.testing.expectApproxEqAbs(screenToClipY(expected_y, 720), vertices.items[0].position[1], 0.001);
}

test "UI vertex builder renders progress fills and separators" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const progress = try world.createEntity("progress", "Progress");
    try world.setUiRect(progress, .{
        .position = .{ 10.0, 20.0, 0.0 },
        .size = .{ 100.0, 16.0, 0.0 },
        .color = .{ 0.1, 0.1, 0.1 },
        .corner_radius = 4.0,
    });
    try world.setUiProgressBar(progress, .{
        .value = 0.25,
        .max = 1.0,
        .fill_color = .{ 0.2, 0.7, 0.8 },
    });

    const separator = try world.createEntity("separator", "Separator");
    try world.setUiSeparator(separator, .{
        .position = .{ 10.0, 44.0, 0.0 },
        .size = .{ 100.0, 2.0, 0.0 },
        .color = .{ 0.5, 0.6, 0.7 },
    });

    var vertices = try buildUiVertices(std.testing.allocator, &world, 200, 100);
    defer vertices.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 18), vertices.items.len);
    try std.testing.expectApproxEqAbs(screenToClipX(35.0, 200), vertices.items[7].position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), vertices.items[6].color[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), vertices.items[6].rect_size_radius[2], 0.001);
    try std.testing.expectApproxEqAbs(screenToClipY(44.0, 100), vertices.items[12].position[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), vertices.items[12].color[0], 0.001);
}

test "render ECS derives UI button interaction state from frame input" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const button = try scene_world.createEntity("button", "Button");
    try scene_world.setUiRect(button, .{
        .position = .{ 32.0, 24.0, 0.0 },
        .size = .{ 120.0, 48.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
    });
    try scene_world.setUiButton(button);

    const panel = try scene_world.createEntity("panel", "Panel");
    try scene_world.setUiRect(panel, .{
        .position = .{ 180.0, 24.0, 0.0 },
        .size = .{ 80.0, 48.0, 0.0 },
        .color = .{ 0.2, 0.2, 0.2 },
    });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();

    try state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .pointer = .{
            .position = .{ 48.0, 36.0 },
            .has_position = true,
            .primary_down = true,
        },
    });
    try state.updateUiInteractions();

    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(render_ui_button_state_component_id));
    const extracted_button = state.world.uiRectAt(0) orelse return error.TestExpectedEqual;
    const held_state = (try renderUiButtonState(&state.world, extracted_button.entity)) orelse return error.TestExpectedEqual;
    try std.testing.expect(held_state.hovered);
    try std.testing.expect(held_state.held);
    try std.testing.expect(!held_state.pressed);

    const extracted_panel = state.world.uiRectAt(1) orelse return error.TestExpectedEqual;
    try std.testing.expect((try renderUiButtonState(&state.world, extracted_panel.entity)) == null);

    try state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .pointer = .{
            .position = .{ 48.0, 36.0 },
            .has_position = true,
            .primary_released = true,
        },
    });
    try state.updateUiInteractions();

    const pressed_button = state.world.uiRectAt(0) orelse return error.TestExpectedEqual;
    const pressed_state = (try renderUiButtonState(&state.world, pressed_button.entity)) orelse return error.TestExpectedEqual;
    try std.testing.expect(pressed_state.hovered);
    try std.testing.expect(!pressed_state.held);
    try std.testing.expect(pressed_state.pressed);
}

test "render ECS hit tests buttons through UI layout clips" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const scroll = try scene_world.createEntity("scroll", "Scroll View");
    try scene_world.setUiScrollView(scroll, .{
        .position = .{ 40.0, 50.0, 0.0 },
        .size = .{ 60.0, 40.0, 0.0 },
        .content_offset = .{ 0.0, 0.0, 0.0 },
    });

    const button = try scene_world.createEntity("button", "Button");
    try scene_world.setUiRect(button, .{
        .position = .{ 8.0, 8.0, 0.0 },
        .size = .{ 30.0, 24.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
    });
    try scene_world.setUiButton(button);
    try scene_world.setUiLayoutItem(button, .{ .parent = "scroll", .order = 0 });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();

    try state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .pointer = .{
            .position = .{ 50.0, 60.0 },
            .has_position = true,
            .primary_down = true,
        },
    });
    try state.updateUiInteractions();

    const extracted_button = state.world.findEntityById("button") orelse return error.TestExpectedEqual;
    const held_state = (try renderUiButtonState(&state.world, extracted_button)) orelse return error.TestExpectedEqual;
    try std.testing.expect(held_state.hovered);
    try std.testing.expect(held_state.held);

    try state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .pointer = .{
            .position = .{ 104.0, 60.0 },
            .has_position = true,
            .primary_down = true,
        },
    });
    try state.updateUiInteractions();

    const clipped_button = state.world.findEntityById("button") orelse return error.TestExpectedEqual;
    const clipped_state = (try renderUiButtonState(&state.world, clipped_button)) orelse return error.TestExpectedEqual;
    try std.testing.expect(!clipped_state.hovered);
    try std.testing.expect(!clipped_state.held);
}

test "hidden UI overlay skips UI extraction but keeps frame input" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const button = try scene_world.createEntity("button", "Button");
    try scene_world.setUiRect(button, .{
        .position = .{ 32.0, 24.0, 0.0 },
        .size = .{ 120.0, 48.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
    });
    try scene_world.setUiButton(button);

    const label = try scene_world.createEntity("label", "Label");
    try scene_world.setUiText(label, .{
        .position = .{ 42.0, 36.0, 0.0 },
        .size = 2.0,
        .color = .{ 1.0, 0.8, 0.2 },
        .value = "HIDDEN",
    });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractSceneWithInput(.{ .world = &scene_world }, .{ .ui_visible = false });
    try state.updateUiInteractions();

    try std.testing.expectEqual(@as(usize, 0), state.world.uiRectCount());
    try std.testing.expectEqual(@as(usize, 0), state.world.uiTextCount());
    try std.testing.expectEqual(@as(usize, 0), state.world.componentInstanceCountFor(render_ui_button_state_component_id));

    const input = try renderFrameInput(&state.world);
    try std.testing.expect(!input.ui_visible);
    try std.testing.expect(!input.debug_overlay_visible);
}

test "frame input round trips through ECS input components" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    try writeFrameInput(&world, .{
        .pointer = .{
            .position = .{ 44.0, 55.0 },
            .delta = .{ 2.0, -1.0 },
            .has_position = true,
            .primary_down = true,
            .secondary_down = true,
            .secondary_pressed = true,
            .wheel_delta = .{ 0.0, -3.0 },
        },
        .keyboard = .{
            .ctrl_down = true,
            .move_forward = true,
            .move_down = true,
            .editor_toggle_pressed = true,
        },
        .ui_visible = false,
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    });

    const input = try renderFrameInput(&world);
    try std.testing.expect(input.pointer.has_position);
    try std.testing.expectEqual(@as(f32, 44.0), input.pointer.position[0]);
    try std.testing.expectEqual(@as(f32, 2.0), input.pointer.delta[0]);
    try std.testing.expect(input.pointer.secondary_down);
    try std.testing.expect(input.pointer.secondary_pressed);
    try std.testing.expectEqual(@as(f32, -3.0), input.pointer.wheel_delta[1]);
    try std.testing.expect(input.keyboard.ctrl_down);
    try std.testing.expect(input.keyboard.move_forward);
    try std.testing.expect(input.keyboard.move_down);
    try std.testing.expect(input.keyboard.editor_toggle_pressed);
    try std.testing.expect(!input.ui_visible);
    try std.testing.expect(input.debug_overlay_visible);
    try std.testing.expectEqual(@as(f32, 1280.0), input.viewport_width);
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(runtime.input_pointer_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(runtime.input_keyboard_component_id));
    try std.testing.expectEqual(@as(usize, 1), world.componentInstanceCountFor(runtime.input_frame_component_id));
}

test "ctrl-tab debug overlay toggle updates editor visibility only" {
    var input = FrameInput{ .debug_overlay_visible = true };

    toggleDebugOverlay(&input);
    try std.testing.expect(!input.debug_overlay_visible);
    try std.testing.expect(input.ui_visible);
    try std.testing.expect(input.keyboard.editor_toggle_pressed);

    input.beginFrame();
    try std.testing.expect(!input.keyboard.editor_toggle_pressed);

    toggleDebugOverlay(&input);
    try std.testing.expect(input.debug_overlay_visible);
    try std.testing.expect(input.ui_visible);
    try std.testing.expect(input.keyboard.editor_toggle_pressed);

    try std.testing.expect(isEditorToggleShortcut(sdl.MACHINA_SDL_KEY_TAB, true));
    try std.testing.expect(!isEditorToggleShortcut(sdl.MACHINA_SDL_KEY_TAB, false));
    try std.testing.expect(!isEditorToggleShortcut(sdl.MACHINA_SDL_KEY_F1, true));
}

test "live run delta conversion uses measured elapsed seconds" {
    const delta = liveRunDeltaSecondsFromElapsedNs(16_666_667);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0 / 60.0), delta, 0.000001);
}

test "live run delta conversion falls back for non-advancing ticks" {
    const delta = liveRunDeltaSecondsFromElapsedNs(0);
    try std.testing.expectApproxEqAbs(live_run_default_delta_seconds, delta, 0.000001);
}

test "live run delta conversion clamps large spikes" {
    const delta = liveRunDeltaSecondsFromElapsedNs(2 * std.time.ns_per_s);
    try std.testing.expectApproxEqAbs(live_run_max_delta_seconds, delta, 0.000001);
}

test "debug overlay extracts FPS label when visible" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .ui_visible = false,
        .debug_overlay_visible = true,
        .fps = 59.6,
    });

    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.ui_canvas_component_id));
    try std.testing.expect(state.world.uiTextCount() >= 8);
    try std.testing.expect(state.world.findEntityById("machina.editor.debug.accent") == null);
    try std.testing.expect(state.world.findEntityById("machina.editor.inspector.accent") == null);

    const label = state.world.findEntityById("machina.editor.debug.fps") orelse return error.TestExpectedEqual;
    const fps_value = try state.world.getString(label, runtime.ui_text_component_id, "value");
    const fps_position = try state.world.getVec3(label, runtime.ui_text_component_id, "position");
    const fps_size = try state.world.getFloat(label, runtime.ui_text_component_id, "size");
    try std.testing.expectEqualStrings("FPS 60", fps_value);
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_text_size), fps_size, 0.001);

    const play_button = state.world.findEntityById("machina.editor.controls.play") orelse return error.TestExpectedEqual;
    const play_position = try state.world.getVec3(play_button, runtime.ui_rect_component_id, "position");
    try std.testing.expect(play_position[0] > fps_position[0] + editorTextWidth(fps_value, fps_size));
    try std.testing.expectEqual(@as(f32, editor_button_corner_radius), try state.world.getFloat(play_button, runtime.ui_rect_component_id, "corner_radius"));
    try std.testing.expect(try state.world.hasComponent(play_button, runtime.ui_button_component_id));
    try std.testing.expectEqualStrings(editor_command_play_toggle, try state.world.getString(play_button, runtime.ui_command_component_id, "command"));

    const play_label = state.world.findEntityById("machina.editor.controls.play.label") orelse return error.TestExpectedEqual;
    const play_label_position = try state.world.getVec3(play_label, runtime.ui_text_component_id, "position");
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), play_label_position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), play_label_position[1], 0.001);
    const play_label_item = (try ui_layout.layoutItem(&state.world, play_label)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("machina.editor.controls.play", play_label_item.parent);
    const resolved_play_label = try resolveUiLayout(&state.world, play_label, play_label_position);
    const play_label_text = runtime.UiText{
        .entity = play_label,
        .id = "machina.editor.controls.play.label",
        .name = "Editor Play Label",
        .position = play_label_position,
        .size = try state.world.getFloat(play_label, runtime.ui_text_component_id, "size"),
        .color = try state.world.getVec3(play_label, runtime.ui_text_component_id, "color"),
        .value = try state.world.getString(play_label, runtime.ui_text_component_id, "value"),
    };
    const centered_play_label = try resolveUiTextPosition(&state.world, play_label, play_label_text, resolved_play_label.position);
    const expected_play_label_x = play_position[0] + (editor_control_button_width - editorTextWidth("PAUSE", 1.0)) * 0.5;
    const expected_play_label_y = play_position[1] + (editor_control_button_height - editorTextHeight(1.0)) * 0.5;
    try std.testing.expectApproxEqAbs(expected_play_label_x, centered_play_label[0], 0.001);
    try std.testing.expectApproxEqAbs(expected_play_label_y, centered_play_label[1], 0.001);

    const input = try renderFrameInput(&state.world);
    var texts = state.world.uiTexts();
    while (texts.next()) |text| {
        try std.testing.expect(std.mem.indexOf(u8, text.value, "IN W") == null);
    }

    try std.testing.expect(!input.ui_visible);
    try std.testing.expect(input.debug_overlay_visible);
    const left_sidebar = editorLeftSidebarRect(input);
    const expected_left_panel = editorSidebarPanelRect(left_sidebar);
    const debug_panel = state.world.findEntityById("machina.editor.debug.panel") orelse return error.TestExpectedEqual;
    const debug_panel_x = state.world.getVec3(debug_panel, runtime.ui_rect_component_id, "position") catch |err| return mapWorldError(err);
    const debug_panel_radius = try state.world.getFloat(debug_panel, runtime.ui_rect_component_id, "corner_radius");
    try std.testing.expectApproxEqAbs(expected_left_panel.x, debug_panel_x[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), debug_panel_radius, 0.001);
    try std.testing.expect(state.world.findEntityById("machina.editor.shell.top_bar") != null);
    try std.testing.expect(state.world.findEntityById("machina.editor.shell.bottom_bar") != null);
    const left_sidebar_entity = state.world.findEntityById("machina.editor.shell.left_sidebar") orelse return error.TestExpectedEqual;
    try std.testing.expect(state.world.findEntityById("machina.editor.shell.right_sidebar") != null);
    const left_sidebar_color = try state.world.getVec3(left_sidebar_entity, runtime.ui_rect_component_id, "color");
    const debug_panel_color = try state.world.getVec3(debug_panel, runtime.ui_rect_component_id, "color");
    for (0..3) |channel| {
        try std.testing.expectApproxEqAbs(editor_palette.panel[channel], left_sidebar_color[channel], 0.001);
        try std.testing.expectApproxEqAbs(editor_palette.panel[channel], debug_panel_color[channel], 0.001);
    }
    try std.testing.expect(state.world.findEntityById("machina.editor.shell.viewport.frame") == null);
    try std.testing.expect(state.world.findEntityById("machina.editor.shell.viewport.border.top") == null);
    try std.testing.expect(state.world.findEntityById("machina.editor.shell.viewport.border.left") == null);
    try std.testing.expect(state.world.findEntityById("machina.editor.shell.viewport.border.right") == null);
    const bottom = editorBottomBarRect(input);
    const status = state.world.findEntityById("machina.editor.bottom.status") orelse return error.TestExpectedEqual;
    const status_position = try state.world.getVec3(status, runtime.ui_text_component_id, "position");
    const status_size = try state.world.getFloat(status, runtime.ui_text_component_id, "size");
    try std.testing.expectApproxEqAbs(bottom.y + 14.0, status_position[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_text_size), status_size, 0.001);
    try std.testing.expect(status_position[1] + editorTextHeight(status_size) <= bottom.y + bottom.height);

    try state.queueUiDraw();
    try std.testing.expectEqual(@as(usize, 1), state.uiDrawCommandCount());
}

test "editor shell body uses hgroup slot for the game viewport" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    const input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{
            .left_sidebar_width = 360.0,
            .right_sidebar_width = 420.0,
        },
    };
    try state.extractSceneWithInput(.{ .world = &scene_world }, input);

    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.ui_hgroup_component_id));
    const game_slot = state.world.findEntityById("machina.editor.shell.game_viewport") orelse return error.TestExpectedEqual;
    const slot_rect = try ui_layout.resolvedItemRect(&state.world, game_slot);
    const left_splitter = editorSplitterRect(input, .left) orelse return error.TestExpectedEqual;
    const viewport = editorGameViewport(input);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), left_splitter.width, 0.001);
    try std.testing.expectApproxEqAbs(viewport.x, slot_rect.position[0], 0.001);
    try std.testing.expectApproxEqAbs(viewport.y, slot_rect.position[1], 0.001);
    try std.testing.expectApproxEqAbs(viewport.width, slot_rect.size[0], 0.001);
    try std.testing.expectApproxEqAbs(viewport.height, slot_rect.size[1], 0.001);
    const inactive_splitter = state.world.findEntityById("machina.editor.shell.splitter.left") orelse return error.TestExpectedEqual;
    try std.testing.expect(try state.world.hasComponent(inactive_splitter, runtime.ui_spacer_component_id));
    try std.testing.expect(!(try state.world.hasComponent(inactive_splitter, runtime.ui_separator_component_id)));
    const splitter_hit_area = state.world.findEntityById("machina.editor.shell.splitter.left.hit_area") orelse return error.TestExpectedEqual;
    try std.testing.expect(try state.world.hasComponent(splitter_hit_area, runtime.ui_hit_area_component_id));
    try std.testing.expect(try state.world.hasComponent(splitter_hit_area, runtime.ui_button_component_id));
    try std.testing.expect(try state.world.hasComponent(splitter_hit_area, runtime.ui_command_component_id));
    try std.testing.expect(!(try state.world.hasComponent(splitter_hit_area, runtime.ui_rect_component_id)));
    const hit_area_size = try state.world.getVec3(splitter_hit_area, runtime.ui_hit_area_component_id, "size");
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), hit_area_size[0], 0.001);

    var hover_state = try RenderEcsState.init(std.testing.allocator);
    defer hover_state.deinit();
    const hover_point = [2]f32{ left_splitter.x + left_splitter.width + 3.0, left_splitter.y + 40.0 };
    try std.testing.expect(!left_splitter.contains(hover_point));
    try hover_state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = input.editor,
        .pointer = .{
            .position = hover_point,
            .has_position = true,
        },
    });
    const hit = (try ui_layout.commandAt(&hover_state.world, hover_point)) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings(editor_command_splitter_left, hit.command);
    const hover_splitter = hover_state.world.findEntityById("machina.editor.shell.splitter.left") orelse return error.TestExpectedEqual;
    const hover_color = try hover_state.world.getVec3(hover_splitter, runtime.ui_separator_component_id, "color");
    for (0..3) |channel| {
        try std.testing.expectApproxEqAbs(editor_palette.text_dim[channel], hover_color[channel], 0.001);
    }
}

test "editor splitters resize sidebars through editor state" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    var editor_state = EditorState{};
    const initial_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    const left_splitter = editorSplitterRect(initial_input, .left) orelse return error.TestExpectedEqual;
    const press_point = [2]f32{ left_splitter.x + left_splitter.width + 3.0, left_splitter.y + 40.0 };
    try std.testing.expect(!left_splitter.contains(press_point));
    try std.testing.expectEqual(EditorSplitter.left, (try routeEditorSplitterAt(std.testing.allocator, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{ .position = press_point, .has_position = true },
    })).?);

    const press = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{
            .position = press_point,
            .has_position = true,
            .primary_pressed = true,
            .primary_down = true,
        },
    });
    try std.testing.expect(press.consumed_pointer);
    try std.testing.expectEqual(EditorSplitter.left, editor_state.dragging_splitter);
    const before_width = editor_state.left_sidebar_width;

    const drag = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = editorFrameState(&world, editor_state),
        .pointer = .{
            .position = .{ press_point[0] + 200.0, press_point[1] },
            .has_position = true,
            .primary_down = true,
        },
    });
    try std.testing.expect(drag.consumed_pointer);
    try std.testing.expect(editor_state.left_sidebar_width > before_width);
    try std.testing.expect(editor_state.left_sidebar_width > editor_left_sidebar_target_width);

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = editorFrameState(&world, editor_state),
        .pointer = .{
            .position = .{ press_point[0] + 200.0, press_point[1] },
            .has_position = true,
            .primary_released = true,
        },
    });
    try std.testing.expectEqual(EditorSplitter.none, editor_state.dragging_splitter);
}

test "editor cursor changes over and during splitter drag" {
    const input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    const left_splitter = editorSplitterRect(input, .left) orelse return error.TestExpectedEqual;
    const hover_point = [2]f32{ left_splitter.x + left_splitter.width + 3.0, left_splitter.y + 40.0 };

    try std.testing.expectEqual(EditorCursorKind.default, try editorCursorKind(std.testing.allocator, input));
    try std.testing.expectEqual(EditorCursorKind.resize_ew, try editorCursorKind(std.testing.allocator, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{
            .position = hover_point,
            .has_position = true,
        },
    }));
    try std.testing.expectEqual(EditorCursorKind.resize_ew, try editorCursorKind(std.testing.allocator, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{ .dragging_splitter = .left },
        .pointer = .{
            .position = .{ 900.0, 200.0 },
            .has_position = true,
        },
    }));
    try std.testing.expectEqual(EditorCursorKind.default, try editorCursorKind(std.testing.allocator, .{
        .debug_overlay_visible = false,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{ .dragging_splitter = .left },
        .pointer = .{
            .position = hover_point,
            .has_position = true,
        },
    }));
}

test "debug overlay extracts system profile rows when available" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{
            .id = "spawn_initial",
            .phase = .startup,
            .sample_count = 0,
            .window_size = 120,
            .last_ns = 0,
            .rolling_average_ns = 0,
        },
        .{
            .id = "rotate_cubes",
            .phase = .update,
            .sample_count = 3,
            .window_size = 120,
            .last_ns = 123_400,
            .rolling_average_ns = 56_700,
        },
    };

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .fps = 60.0,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .system_profiles = &profiles,
    };
    try state.extractSceneWithInput(.{ .world = &scene_world }, frame_input);

    try std.testing.expect(state.world.uiTextCount() >= 11);
    try std.testing.expect(state.world.findEntityById("machina.editor.debug.panel") != null);
    try std.testing.expect(state.world.findEntityById("machina.editor.debug.accent") == null);

    var saw_header = false;
    var saw_pause = false;
    var saw_no_selection = false;
    var texts = state.world.uiTexts();
    while (texts.next()) |text| {
        try std.testing.expect(std.mem.indexOf(u8, text.value, "IN W") == null);
        try std.testing.expect(std.mem.indexOf(u8, text.value, "ROWS ") == null);
        try std.testing.expect(text.size >= 1.0);
        if (std.mem.indexOf(u8, text.value, "SYS 2 AVG 120F SNAP 3HZ") != null) {
            saw_header = true;
        }
        if (std.mem.indexOf(u8, text.value, "PAUSE") != null) {
            saw_pause = true;
        }
        if (std.mem.indexOf(u8, text.value, "NO ENTITY SELECTED") != null) {
            saw_no_selection = true;
        }
    }

    try std.testing.expect(saw_header);
    try std.testing.expect(saw_pause);
    try std.testing.expect(saw_no_selection);

    const table = state.world.findEntityById("machina.editor.debug.systems.table") orelse return error.TestExpectedEqual;
    const row0_label = state.world.findEntityById("machina.editor.debug.systems.row.0.label") orelse return error.TestExpectedEqual;
    const row0_duration = state.world.findEntityById("machina.editor.debug.systems.row.0.duration") orelse return error.TestExpectedEqual;
    const row1_label = state.world.findEntityById("machina.editor.debug.systems.row.1.label") orelse return error.TestExpectedEqual;
    const row1_duration = state.world.findEntityById("machina.editor.debug.systems.row.1.duration") orelse return error.TestExpectedEqual;
    const list_clip = editorSystemListClipRect(frame_input);
    const table_size = try state.world.getVec3(table, runtime.ui_rect_component_id, "size");
    try std.testing.expectApproxEqAbs(list_clip.size[0], table_size[0], 0.001);
    try std.testing.expectApproxEqAbs(editorSystemTableContentHeight(2), table_size[1], 0.001);
    try std.testing.expect(state.world.findEntityById("machina.editor.debug.systems.row.0") == null);
    try std.testing.expect(state.world.findEntityById("machina.editor.debug.systems.row.1") == null);
    try std.testing.expect(state.world.findEntityById("machina.editor.debug.systems.separator.1") == null);
    try std.testing.expectEqualStrings("spawn_initial", try state.world.getString(row0_label, runtime.ui_text_component_id, "value"));
    try std.testing.expectEqualStrings("--", try state.world.getString(row0_duration, runtime.ui_text_component_id, "value"));
    try std.testing.expectEqualStrings("rotate_cubes", try state.world.getString(row1_label, runtime.ui_text_component_id, "value"));
    try std.testing.expectEqualStrings("57us", try state.world.getString(row1_duration, runtime.ui_text_component_id, "value"));
}

test "debug overlay extracts entity list below system list" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const player = try scene_world.createEntity("player", "Player");
    try scene_world.setTransform(player, .{});
    const crate = try scene_world.createEntity("crate", "Crate");
    try scene_world.setTransform(crate, .{});

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{ .id = "tick", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1, .rolling_average_ns = 1 },
    };

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .system_profiles = &profiles,
        .editor = .{ .selected_entity = crate },
    };
    try state.extractSceneWithInput(.{ .world = &scene_world }, frame_input);

    const system_panel = state.world.findEntityById("machina.editor.debug.panel") orelse return error.TestExpectedEqual;
    const entity_panel = state.world.findEntityById("machina.editor.entities.panel") orelse return error.TestExpectedEqual;
    const entity_header = state.world.findEntityById("machina.editor.entities.header") orelse return error.TestExpectedEqual;
    const row0_label = state.world.findEntityById("machina.editor.entities.row.0.label") orelse return error.TestExpectedEqual;
    const row1_label = state.world.findEntityById("machina.editor.entities.row.1.label") orelse return error.TestExpectedEqual;
    const row1_components = state.world.findEntityById("machina.editor.entities.row.1.components") orelse return error.TestExpectedEqual;
    try std.testing.expect(state.world.findEntityById("machina.editor.entities.row.1.highlight") != null);

    const system_position = try state.world.getVec3(system_panel, runtime.ui_rect_component_id, "position");
    const system_size = try state.world.getVec3(system_panel, runtime.ui_rect_component_id, "size");
    const entity_position = try state.world.getVec3(entity_panel, runtime.ui_rect_component_id, "position");
    try std.testing.expect(entity_position[1] >= system_position[1] + system_size[1] + editor_left_panel_gap - 0.001);
    try std.testing.expectEqualStrings("ENTITIES 2", try state.world.getString(entity_header, runtime.ui_text_component_id, "value"));
    try std.testing.expectEqualStrings("Player", try state.world.getString(row0_label, runtime.ui_text_component_id, "value"));
    try std.testing.expectEqualStrings("Crate", try state.world.getString(row1_label, runtime.ui_text_component_id, "value"));
    try std.testing.expectEqualStrings("1C", try state.world.getString(row1_components, runtime.ui_text_component_id, "value"));
}

test "editor entity list scroll state responds to wheel input" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    for (0..12) |index| {
        const id = try std.fmt.allocPrint(std.testing.allocator, "entity-{d}", .{index});
        defer std.testing.allocator.free(id);
        const name = try std.fmt.allocPrint(std.testing.allocator, "Entity {d}", .{index});
        defer std.testing.allocator.free(name);
        _ = try world.createEntity(id, name);
    }

    var editor_state = EditorState{};
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    const list_clip = editorEntityListClipRect(&world, frame_input);
    const update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .delta_seconds = 1.0,
        .pointer = .{
            .position = .{ list_clip.position[0] + 4.0, list_clip.position[1] + 4.0 },
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });

    try std.testing.expect(update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel), editor_state.entity_scroll_target_y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), editor_state.system_scroll_target_y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), editor_state.inspector_scroll_target_y, 0.001);
}

test "editor entity list row click selects entity" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    _ = try world.createEntity("first", "First");
    const second = try world.createEntity("second", "Second");
    _ = try world.createEntity("third", "Third");

    var editor_state = EditorState{};
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    const list_clip = editorEntityListClipRect(&world, frame_input);
    const press = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{
            .position = .{
                list_clip.position[0] + editor_entity_row_label_padding_x,
                list_clip.position[1] + editor_entity_card_padding_y + editor_entity_row_stride + 2.0,
            },
            .has_position = true,
            .primary_pressed = true,
        },
    });

    try std.testing.expect(press.consumed_pointer);
    try std.testing.expect(editorEntityHandlesEqual(editor_state.selected_entity, second));
    try std.testing.expect(editorEntityHandlesEqual(editorFrameState(&world, editor_state).selected_entity, second));
}

test "editor renders inspector for non-renderable entity list selection" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    _ = try world.createEntity("visible", "Visible");
    const resource = try world.createEntity("resource", "Resource");

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractSceneWithInput(.{ .world = &world }, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{ .selected_entity = resource },
    });

    const entity_label = state.world.findEntityById("machina.editor.inspector.entity") orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("Resource  resource", try state.world.getString(entity_label, runtime.ui_text_component_id, "value"));
    try std.testing.expect(state.world.findEntityById("machina.editor.gizmo.x") == null);
}

test "editor render skips stale selected entity handles" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractSceneWithInput(.{ .world = &world }, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{ .selected_entity = .{ .index = 99, .generation = 99 } },
    });

    try std.testing.expect(state.world.findEntityById("machina.editor.gizmo.x") == null);
    try std.testing.expect(state.world.findEntityById("machina.editor.inspector.unavailable") != null);
}

test "debug overlay renders a scrolled system profile window" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const profiles = [_]runtime.SystemProfileSnapshot{
        .{ .id = "system.zero", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 1_000, .rolling_average_ns = 1_000 },
        .{ .id = "system.one", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 2_000, .rolling_average_ns = 2_000 },
        .{ .id = "system.two", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 3_000, .rolling_average_ns = 3_000 },
        .{ .id = "system.three", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 4_000, .rolling_average_ns = 4_000 },
        .{ .id = "system.four", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 5_000, .rolling_average_ns = 5_000 },
        .{ .id = "system.five", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 6_000, .rolling_average_ns = 6_000 },
        .{ .id = "system.six", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 7_000, .rolling_average_ns = 7_000 },
        .{ .id = "system.seven", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 8_000, .rolling_average_ns = 8_000 },
        .{ .id = "system.eight", .phase = .update, .sample_count = 1, .window_size = 120, .last_ns = 9_000, .rolling_average_ns = 9_000 },
    };

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    try state.extractSceneWithInput(.{ .world = &scene_world }, .{
        .debug_overlay_visible = true,
        .fps = 60.0,
        .system_profiles = &profiles,
        .editor = .{ .system_scroll_y = editor_system_row_stride * 2.0 },
    });

    var texts = state.world.uiTexts();
    while (texts.next()) |text| {
        try std.testing.expect(std.mem.indexOf(u8, text.value, "ROWS ") == null);
    }

    try std.testing.expect(state.world.findEntityById("machina.editor.debug.systems.row.0.label") != null);
    try std.testing.expect(state.world.findEntityById("machina.editor.debug.systems.row.2.label") != null);
    try std.testing.expect(state.world.findEntityById("machina.editor.debug.systems.row.8.label") != null);
    try std.testing.expect(state.world.findEntityById("machina.editor.debug.systems.table") != null);
    try std.testing.expect(state.world.findEntityById("machina.editor.debug.systems.row.0") == null);
    try std.testing.expect(state.world.findEntityById("machina.editor.debug.systems.separator.1") == null);
    try std.testing.expectEqual(@as(usize, 1), state.world.componentInstanceCountFor(runtime.ui_scroll_view_component_id));
    try std.testing.expectEqual(@as(usize, 0), state.world.componentInstanceCountFor(runtime.ui_vbox_component_id));
    try std.testing.expect(state.world.componentInstanceCountFor(runtime.ui_layout_item_component_id) >= profiles.len * 2 + 1);
    try std.testing.expect(state.world.findEntityById("machina.editor.debug.systems.scrollbar.track") != null);
    try std.testing.expect(state.world.findEntityById("machina.editor.debug.systems.scrollbar.thumb") != null);
}

test "editor overlay extracts selected entity inspector and translate gizmo" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const entity = try scene_world.createEntity("selected", "Selected Box");
    try scene_world.setTransform(entity, .{ .position = .{ 0.25, 0.5, 0.0 } });
    try scene_world.setGeometryPrimitive(entity, .{
        .primitive = "uv_sphere",
        .segments = 16,
        .rings = 8,
    });
    try scene_world.setSurfaceMaterial(entity, .{ .base_color = .{ 0.8, 0.4, 0.2 } });

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1920.0,
        .viewport_height = 1080.0,
        .editor = .{
            .selected_entity = entity,
            .entity_count = scene_world.entityCount(),
            .component_instance_count = scene_world.componentInstanceCount(),
            .renderable_count = scene_world.renderableMeshCount(),
        },
    };
    try state.extractSceneWithInput(.{ .world = &scene_world }, frame_input);

    try std.testing.expectEqual(@as(usize, 4), state.world.renderableMeshCount());
    try std.testing.expect(state.world.findEntityById("machina.editor.inspector.panel") != null);
    try std.testing.expect(state.world.findEntityById("machina.editor.inspector.accent") == null);

    var saw_entity_header = false;
    var texts = state.world.uiTexts();
    while (texts.next()) |text| {
        if (std.mem.indexOf(u8, text.value, "Selected Box") != null) {
            saw_entity_header = true;
        }
    }
    try std.testing.expect(saw_entity_header);
    try std.testing.expect(state.world.findEntityById("machina.editor.inspector.components") != null);
    try std.testing.expect(try state.world.hasComponent(
        state.world.findEntityById("machina.editor.inspector.components") orelse return error.TestExpectedEqual,
        runtime.ui_vbox_component_id,
    ));
    try std.testing.expect(state.world.findEntityById("machina.editor.inspector.component.0") != null);
    try std.testing.expect(state.world.findEntityById("machina.editor.inspector.component.1") != null);
    try std.testing.expect(state.world.findEntityById("machina.editor.inspector.component.separator.1") != null);

    const geometry_card = state.world.findEntityById("machina.editor.inspector.component.1") orelse return error.TestExpectedEqual;
    const geometry_title = state.world.findEntityById("machina.editor.inspector.component.1.title") orelse return error.TestExpectedEqual;
    const transform_position_label = state.world.findEntityById("machina.editor.inspector.component.0.field.0.label") orelse return error.TestExpectedEqual;
    const transform_position_input_0 = state.world.findEntityById("machina.editor.inspector.component.0.field.0.input.0") orelse return error.TestExpectedEqual;
    const transform_position_value_0 = state.world.findEntityById("machina.editor.inspector.component.0.field.0.value.0") orelse return error.TestExpectedEqual;
    const geometry_field_label = state.world.findEntityById("machina.editor.inspector.component.1.field.0.label") orelse return error.TestExpectedEqual;
    const geometry_field_input = state.world.findEntityById("machina.editor.inspector.component.1.field.0.input") orelse return error.TestExpectedEqual;
    const geometry_field_value = state.world.findEntityById("machina.editor.inspector.component.1.field.0.value") orelse return error.TestExpectedEqual;
    const separator = state.world.findEntityById("machina.editor.inspector.component.separator.1") orelse return error.TestExpectedEqual;
    const card_position = try state.world.getVec3(geometry_card, runtime.ui_rect_component_id, "position");
    const card_size = try state.world.getVec3(geometry_card, runtime.ui_rect_component_id, "size");
    const title_position = try state.world.getVec3(geometry_title, runtime.ui_text_component_id, "position");
    const title_size = try state.world.getFloat(geometry_title, runtime.ui_text_component_id, "size");
    const title_value = try state.world.getString(geometry_title, runtime.ui_text_component_id, "value");
    const label_position = try state.world.getVec3(geometry_field_label, runtime.ui_text_component_id, "position");
    const input_position = try state.world.getVec3(geometry_field_input, runtime.ui_rect_component_id, "position");
    const value_position = try state.world.getVec3(geometry_field_value, runtime.ui_text_component_id, "position");
    const label_value = try state.world.getString(geometry_field_label, runtime.ui_text_component_id, "value");
    const field_value = try state.world.getString(geometry_field_value, runtime.ui_text_component_id, "value");
    try std.testing.expectEqualStrings("position", try state.world.getString(transform_position_label, runtime.ui_text_component_id, "value"));
    try std.testing.expect(try state.world.hasComponent(transform_position_input_0, runtime.ui_rect_component_id));
    try std.testing.expectEqualStrings("0.25", try state.world.getString(transform_position_value_0, runtime.ui_text_component_id, "value"));
    const separator_size = try state.world.getVec3(separator, runtime.ui_separator_component_id, "size");
    const sidebar = editorSidebarPanelRect(editorRightSidebarRect(frame_input));
    const resolved_card_layout = try resolveUiLayout(&state.world, geometry_card, card_position);
    const resolved_separator_layout = try resolveUiLayout(&state.world, separator, try state.world.getVec3(separator, runtime.ui_separator_component_id, "position"));
    const transform_card = state.world.findEntityById("machina.editor.inspector.component.0") orelse return error.TestExpectedEqual;
    const transform_card_size = try state.world.getVec3(transform_card, runtime.ui_rect_component_id, "size");
    const resolved_transform_card_layout = try resolveUiLayout(&state.world, transform_card, try state.world.getVec3(transform_card, runtime.ui_rect_component_id, "position"));

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), card_position[0], 0.001);
    try std.testing.expectApproxEqAbs(sidebar.width, card_size[0], 0.001);
    try std.testing.expectApproxEqAbs(sidebar.x, resolved_card_layout.position[0], 0.001);
    try std.testing.expectApproxEqAbs(editor_panel_corner_radius, try state.world.getFloat(geometry_card, runtime.ui_rect_component_id, "corner_radius"), 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_separator_height, separator_size[1], 0.001);
    try std.testing.expectApproxEqAbs(sidebar.width, separator_size[0], 0.001);
    try std.testing.expectApproxEqAbs(resolved_transform_card_layout.position[1] + transform_card_size[1], resolved_separator_layout.position[1], 0.001);
    try std.testing.expect(title_position[1] >= card_position[1] + editor_inspector_card_padding_y);
    try std.testing.expect(title_position[1] + editorTextHeight(title_size) <= card_position[1] + card_size[1] - editor_inspector_card_padding_y);
    try std.testing.expect(editorTextWidth(title_value, title_size) <= card_size[0] - editor_inspector_card_padding_x * 2.0);
    try std.testing.expectApproxEqAbs(editor_inspector_card_padding_x, label_position[0], 0.001);
    try std.testing.expectApproxEqAbs(editorInspectorFieldValueX(card_size[0]), input_position[0], 0.001);
    try std.testing.expectApproxEqAbs(editor_inspector_input_padding_x, value_position[0], 0.001);
    try std.testing.expectEqualStrings("primitive", label_value);
    try std.testing.expectEqualStrings("uv_sphere", field_value);
}

test "editor inspector component stack resolves inside scroll view clip" {
    var scene_world = runtime.World.init(std.testing.allocator);
    defer scene_world.deinit();

    const entity = try scene_world.createEntity("selected", "Selected Box");
    try scene_world.setTransform(entity, .{ .position = .{ 0.25, 0.5, 0.0 } });
    try scene_world.setGeometryPrimitive(entity, .{
        .primitive = "uv_sphere",
        .segments = 16,
        .rings = 8,
    });
    try scene_world.setSurfaceMaterial(entity, .{ .base_color = .{ 0.8, 0.4, 0.2 } });
    try scene_world.setShadowCaster(entity);
    try scene_world.setShadowReceiver(entity);

    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{
            .selected_entity = entity,
            .inspector_scroll_y = 80.0,
        },
    };
    try state.extractSceneWithInput(.{ .world = &scene_world }, frame_input);

    const scroll = state.world.findEntityById("machina.editor.inspector.scroll") orelse return error.TestExpectedEqual;
    const stack = state.world.findEntityById("machina.editor.inspector.components") orelse return error.TestExpectedEqual;
    const first_card = state.world.findEntityById("machina.editor.inspector.component.0") orelse return error.TestExpectedEqual;
    try std.testing.expect(try state.world.hasComponent(scroll, runtime.ui_scroll_view_component_id));
    try std.testing.expectEqualStrings("machina.editor.inspector.scroll", try state.world.getString(stack, runtime.ui_layout_item_component_id, "parent"));

    const clip = editorInspectorScrollClipRect(frame_input);
    const card_position = try state.world.getVec3(first_card, runtime.ui_rect_component_id, "position");
    const resolved = try resolveUiLayout(&state.world, first_card, card_position);
    const resolved_clip = resolved.clip orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(clip.position[0], resolved_clip.position[0], 0.001);
    try std.testing.expectApproxEqAbs(clip.position[1], resolved_clip.position[1], 0.001);
    try std.testing.expectApproxEqAbs(clip.size[0], resolved_clip.size[0], 0.001);
    try std.testing.expectApproxEqAbs(clip.size[1], resolved_clip.size[1], 0.001);
    try std.testing.expectApproxEqAbs(clip.position[1] - 80.0, resolved.position[1], 0.001);
}

test "editor inspector scroll state responds to wheel input" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("selected", "Selected Box");
    try world.setTransform(entity, .{ .position = .{ 0.25, 0.5, 0.0 } });
    try world.setGeometryPrimitive(entity, .{
        .primitive = "uv_sphere",
        .segments = 16,
        .rings = 8,
    });
    try world.setSurfaceMaterial(entity, .{ .base_color = .{ 0.8, 0.4, 0.2 } });
    try world.setShadowCaster(entity);
    try world.setShadowReceiver(entity);

    var editor_state = EditorState{ .selected_entity = entity };
    const clip = editorInspectorScrollClipRect(.{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{ .selected_entity = entity },
    });
    const update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .delta_seconds = 1.0,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{
            .position = .{ clip.position[0] + 8.0, clip.position[1] + 8.0 },
            .has_position = true,
            .wheel_delta = .{ 0.0, -1.0 },
        },
    });

    try std.testing.expect(update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, editor_system_scroll_pixels_per_wheel), editor_state.inspector_scroll_target_y, 0.001);
    try std.testing.expect(editor_state.inspector_scroll_y > 0.0);
    try std.testing.expect(editor_state.inspector_scroll_y < editor_state.inspector_scroll_target_y);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), editor_state.system_scroll_target_y, 0.001);
}

test "editor inspector property inputs edit text and commit with undo" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const entity = try world.createEntity("selected", "Selected Box");
    try world.setTransform(entity, .{ .position = .{ 0.25, 0.5, 0.0 } });
    try world.setGeometryPrimitive(entity, .{
        .primitive = "uv_sphere",
        .segments = 16,
        .rings = 8,
    });

    var editor_state = EditorState{ .selected_entity = entity };
    const frame_input = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .editor = .{ .selected_entity = entity },
    };
    const clip = editorInspectorScrollClipRect(frame_input);
    const value_x = editorInspectorFieldValueX(clip.size[0]);
    const first_field_y = clip.position[1] +
        editor_inspector_card_padding_y +
        editorTextHeight(editor_inspector_text_size) +
        editor_panel_label_gap;

    const focus_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{
            .position = .{ clip.position[0] + value_x + 4.0, first_field_y + 2.0 },
            .has_position = true,
            .primary_pressed = true,
            .primary_down = true,
        },
    });
    try std.testing.expect(focus_update.consumed_pointer);
    try std.testing.expect(editor_state.selected_property.matches(entity, runtime.transform_component_id, "position"));
    try std.testing.expectEqual(@as(u2, 0), editor_state.selected_property.vec3_lane);
    try std.testing.expect(editor_state.text_input.active);
    try std.testing.expectEqualStrings("0.250", editor_state.text_input.text());
    try std.testing.expectEqual(editor_state.text_input.len, editor_state.text_input.cursor);
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.selection_anchor);
    try std.testing.expect(editor_state.text_input.hasSelection());

    var render_state = try RenderEcsState.init(std.testing.allocator);
    defer render_state.deinit();
    var selected_frame = frame_input;
    selected_frame.editor = editorFrameState(&world, editor_state);
    try render_state.extractSceneWithInput(.{ .world = &world }, selected_frame);
    try std.testing.expect(render_state.world.findEntityById("machina.editor.inspector.component.0.field.0.selected") == null);
    const focused_input = render_state.world.findEntityById("machina.editor.inspector.component.0.field.0.input.0") orelse return error.TestExpectedEqual;
    try std.testing.expect(try render_state.world.hasComponent(focused_input, runtime.ui_border_component_id));
    const selection_rect = render_state.world.findEntityById("machina.editor.inspector.component.0.field.0.selection.0") orelse return error.TestExpectedEqual;
    try std.testing.expect(try render_state.world.hasComponent(selection_rect, runtime.ui_rect_component_id));
    try std.testing.expect((try render_state.world.getVec3(selection_rect, runtime.ui_rect_component_id, "size"))[0] > 1.0);
    try std.testing.expect(render_state.world.findEntityById("machina.editor.inspector.component.0.field.0.caret.0") != null);
    var focused_vertices = try buildUiVertices(std.testing.allocator, &render_state.world, 1280, 720);
    focused_vertices.deinit(std.testing.allocator);

    var replace_selected = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    replace_selected.appendTextInput("1.250");
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, replace_selected);
    try std.testing.expectEqualStrings("1.250", editor_state.text_input.text());
    try std.testing.expectEqual(editor_state.text_input.len, editor_state.text_input.cursor);
    try std.testing.expectEqual(editor_state.text_input.cursor, editor_state.text_input.selection_anchor);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), (try world.getVec3(entity, runtime.transform_component_id, "position"))[0], 0.001);

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .shift_down = true, .editor_left_pressed = true },
    });
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .shift_down = true, .editor_left_pressed = true },
    });
    try std.testing.expectEqual(@as(usize, 3), editor_state.text_input.cursor);
    try std.testing.expectEqual(@as(usize, 5), editor_state.text_input.selection_anchor);
    try std.testing.expect(editor_state.text_input.hasSelection());

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_delete_pressed = true },
    });
    try std.testing.expectEqualStrings("1.2", editor_state.text_input.text());
    try std.testing.expectEqual(@as(usize, 3), editor_state.text_input.cursor);
    try std.testing.expectEqual(editor_state.text_input.cursor, editor_state.text_input.selection_anchor);

    var insert_tail = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    insert_tail.appendTextInput("50");
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, insert_tail);
    try std.testing.expectEqualStrings("1.250", editor_state.text_input.text());

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .shift_down = true, .editor_home_pressed = true },
    });
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.cursor);
    try std.testing.expectEqual(@as(usize, 5), editor_state.text_input.selection_anchor);

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_left_pressed = true },
    });
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.cursor);
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.selection_anchor);

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_select_all_pressed = true },
    });
    try std.testing.expectEqual(editor_state.text_input.len, editor_state.text_input.cursor);
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.selection_anchor);

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_backspace_pressed = true },
    });
    try std.testing.expectEqualStrings("", editor_state.text_input.text());
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.cursor);
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.selection_anchor);

    var restore_value = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    restore_value.appendTextInput("0.750");
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, restore_value);
    try std.testing.expectEqualStrings("0.750", editor_state.text_input.text());

    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_select_all_pressed = true },
    });
    try std.testing.expect(editor_state.text_input.hasSelection());
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.selectionStart());
    try std.testing.expectEqual(editor_state.text_input.len, editor_state.text_input.selectionEnd());

    var overwrite_selected = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    overwrite_selected.appendTextInput("1.250");
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, overwrite_selected);
    try std.testing.expectEqualStrings("1.250", editor_state.text_input.text());
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), (try world.getVec3(entity, runtime.transform_component_id, "position"))[0], 0.001);

    const enter_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_enter_pressed = true },
    });
    try std.testing.expect(enter_update.consumed_pointer);
    try std.testing.expect(!editor_state.text_input.active);
    try std.testing.expectApproxEqAbs(@as(f32, 1.25), (try world.getVec3(entity, runtime.transform_component_id, "position"))[0], 0.001);
    try std.testing.expectEqual(@as(usize, 1), editor_state.undo_len);
    try std.testing.expectEqual(@as(usize, 0), editor_state.redo_len);

    const undo_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_undo_pressed = true },
    });
    try std.testing.expect(undo_update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), (try world.getVec3(entity, runtime.transform_component_id, "position"))[0], 0.001);
    try std.testing.expectEqual(@as(usize, 0), editor_state.undo_len);
    try std.testing.expectEqual(@as(usize, 1), editor_state.redo_len);

    const redo_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .keyboard = .{ .editor_redo_pressed = true },
    });
    try std.testing.expect(redo_update.consumed_pointer);
    try std.testing.expectApproxEqAbs(@as(f32, 1.25), (try world.getVec3(entity, runtime.transform_component_id, "position"))[0], 0.001);
    try std.testing.expectEqual(@as(usize, 1), editor_state.undo_len);
    try std.testing.expectEqual(@as(usize, 0), editor_state.redo_len);

    try focusEditorTextInput(&world, &editor_state, try makeEditorFieldSelection(entity, runtime.transform_component_id, "position", 1), .{ .select_all_on_focus = true });
    try std.testing.expect(editor_state.text_input.hasSelection());
    var edit_y = FrameInput{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
    };
    edit_y.appendTextInput("2.500");
    _ = try updateEditorState(std.testing.allocator, &world, &editor_state, edit_y);
    const blur_update = try updateEditorState(std.testing.allocator, &world, &editor_state, .{
        .debug_overlay_visible = true,
        .viewport_width = 1280.0,
        .viewport_height = 720.0,
        .pointer = .{
            .position = .{ 8.0, 8.0 },
            .has_position = true,
            .primary_pressed = true,
            .primary_down = true,
        },
    });
    try std.testing.expect(blur_update.consumed_pointer);
    try std.testing.expect(!editor_state.text_input.active);
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), (try world.getVec3(entity, runtime.transform_component_id, "position"))[1], 0.001);

    try focusEditorTextInput(&world, &editor_state, try makeEditorFieldSelection(entity, runtime.geometry_primitive_component_id, "primitive", 0), .{ .select_all_on_focus = false });
    try std.testing.expect(editor_state.text_input.active);
    try std.testing.expect(!editor_state.text_input.hasSelection());
    try std.testing.expectEqual(editor_state.text_input.len, editor_state.text_input.cursor);

    try focusEditorTextInput(&world, &editor_state, try makeEditorFieldSelection(entity, runtime.geometry_primitive_component_id, "segments", 0), .{ .select_all_on_focus = true });
    try std.testing.expect(editor_state.text_input.active);
    try std.testing.expectEqualStrings("16", editor_state.text_input.text());
    try std.testing.expectEqual(editor_state.text_input.len, editor_state.text_input.cursor);
    try std.testing.expectEqual(@as(usize, 0), editor_state.text_input.selection_anchor);
    try std.testing.expect(editor_state.text_input.hasSelection());

    var scalar_render_state = try RenderEcsState.init(std.testing.allocator);
    defer scalar_render_state.deinit();
    var scalar_frame = frame_input;
    scalar_frame.editor = editorFrameState(&world, editor_state);
    try scalar_render_state.extractSceneWithInput(.{ .world = &world }, scalar_frame);
    const scalar_input = scalar_render_state.world.findEntityById("machina.editor.inspector.component.1.field.1.input") orelse return error.TestExpectedEqual;
    try std.testing.expect(try scalar_render_state.world.hasComponent(scalar_input, runtime.ui_border_component_id));
    const scalar_selection = scalar_render_state.world.findEntityById("machina.editor.inspector.component.1.field.1.selection") orelse return error.TestExpectedEqual;
    try std.testing.expect(try scalar_render_state.world.hasComponent(scalar_selection, runtime.ui_rect_component_id));
    var scalar_vertices = try buildUiVertices(std.testing.allocator, &scalar_render_state.world, 1280, 720);
    scalar_vertices.deinit(std.testing.allocator);
}

test "render ECS profiles internal systems for editor overlay" {
    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();

    const initial_profiles = state.systemProfileSnapshots();
    try std.testing.expectEqual(@as(usize, 7), initial_profiles.len);
    try std.testing.expectEqualStrings(render_extract_system_id, initial_profiles[0].id);
    try std.testing.expectEqual(runtime.SystemPhase.render, initial_profiles[0].phase);
    try std.testing.expectEqual(@as(u32, 0), initial_profiles[0].sample_count);
    try std.testing.expectEqual(@as(u32, render_system_profile_window_frames), initial_profiles[0].window_size);

    const first_batch = state.schedule.batches[0];
    state.recordSystemDuration(first_batch.systems[0], first_batch.phase, 12_300);

    const recorded_profiles = state.systemProfileSnapshots();
    try std.testing.expectEqual(@as(u32, 1), recorded_profiles[0].sample_count);
    try std.testing.expectEqual(@as(u64, 12_300), recorded_profiles[0].last_ns);
    try std.testing.expectEqual(@as(u64, 12_300), recorded_profiles[0].rolling_average_ns);
}

test "editor profile input combines project and engine system rows" {
    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();

    const project_profiles = [_]runtime.SystemProfileSnapshot{
        .{
            .id = "game.update",
            .phase = .update,
            .sample_count = 2,
            .window_size = 120,
            .last_ns = 1_000,
            .rolling_average_ns = 900,
        },
    };

    const combined = try state.combineSystemProfileSnapshots(project_profiles[0..]);
    try std.testing.expectEqual(project_profiles.len + state.system_profiles.items.len, combined.len);
    try std.testing.expectEqualStrings("game.update", combined[0].id);
    try std.testing.expectEqualStrings(render_extract_system_id, combined[1].id);
    try std.testing.expectEqual(runtime.SystemPhase.render, combined[1].phase);
}

test "editor profile display snapshots are copied and throttled" {
    var state = try RenderEcsState.init(std.testing.allocator);
    defer state.deinit();

    const first_project_profiles = [_]runtime.SystemProfileSnapshot{
        .{
            .id = "game.fast",
            .phase = .update,
            .sample_count = 1,
            .window_size = 120,
            .last_ns = 1_000,
            .rolling_average_ns = 1_000,
        },
    };
    const first = try state.combineSystemProfileSnapshots(first_project_profiles[0..]);
    try std.testing.expectEqualStrings("game.fast", first[0].id);
    try std.testing.expect(first[0].id.ptr != first_project_profiles[0].id.ptr);
    try std.testing.expectEqual(@as(u64, 1_000), first[0].last_ns);

    const second_project_profiles = [_]runtime.SystemProfileSnapshot{
        .{
            .id = "game.slow",
            .phase = .update,
            .sample_count = 1,
            .window_size = 120,
            .last_ns = 9_000,
            .rolling_average_ns = 9_000,
        },
    };
    const throttled = try state.combineSystemProfileSnapshots(second_project_profiles[0..]);
    try std.testing.expectEqualStrings("game.fast", throttled[0].id);
    try std.testing.expectEqual(@as(u64, 1_000), throttled[0].last_ns);

    state.last_display_system_profile_update_ns -= @as(i128, editor_performance_display_interval_ns);
    const refreshed = try state.combineSystemProfileSnapshots(second_project_profiles[0..]);
    try std.testing.expectEqualStrings("game.slow", refreshed[0].id);
    try std.testing.expectEqual(@as(u64, 9_000), refreshed[0].last_ns);
}

test "UI vertex builder reflects button interaction state" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const button = try world.createEntity("button", "Button");
    try world.setUiRect(button, .{
        .position = .{ 32.0, 24.0, 0.0 },
        .size = .{ 120.0, 48.0, 0.0 },
        .color = .{ 0.1, 0.2, 0.3 },
        .corner_radius = 6.0,
    });
    try world.setUiButton(button);
    try setRenderUiButtonState(&world, button, .{ .hovered = true });

    var hovered_vertices = try buildUiVertices(std.testing.allocator, &world, 640, 480);
    defer hovered_vertices.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 6), hovered_vertices.items.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.106), hovered_vertices.items[0].color[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), hovered_vertices.items[0].rect_size_radius[2], 0.001);

    try setRenderUiButtonState(&world, button, .{ .held = true });
    var held_vertices = try buildUiVertices(std.testing.allocator, &world, 640, 480);
    defer held_vertices.deinit(std.testing.allocator);
    try std.testing.expectApproxEqAbs(@as(f32, 0.086), held_vertices.items[0].color[0], 0.001);
}

test "UI vertex builder clips text to render clip rect" {
    var world = runtime.World.init(std.testing.allocator);
    defer world.deinit();

    const text = try world.createEntity("text", "Text");
    try world.setUiText(text, .{
        .position = .{ 10.0, 8.0, 0.0 },
        .size = 1.0,
        .color = .{ 1.0, 1.0, 1.0 },
        .value = "CLIP",
    });
    try setRenderUiClip(&world, text, .{
        .position = .{ 10.0, 16.0, 0.0 },
        .size = .{ 120.0, 18.0, 0.0 },
    });

    var vertices = try buildUiVertices(std.testing.allocator, &world, 640, 480);
    defer vertices.deinit(std.testing.allocator);
    try std.testing.expect(vertices.items.len > 0);

    const clip_top = screenToClipY(16.0, 480);
    const clip_bottom = screenToClipY(34.0, 480);
    for (vertices.items) |vertex| {
        try std.testing.expect(vertex.position[1] <= clip_top + 0.0001);
        try std.testing.expect(vertex.position[1] >= clip_bottom - 0.0001);
    }
}

const BatchTestShadowFlags = struct {
    casts_shadow: bool = false,
    receives_shadow: bool = false,
};

fn addBatchTestRenderable(
    world: *runtime.World,
    id: []const u8,
    primitive: []const u8,
    segments: i32,
    rings: i32,
    position: [3]f32,
    base_color: [3]f32,
    shadow_flags: BatchTestShadowFlags,
) !void {
    const entity = try world.createEntity(id, id);
    try world.setTransform(entity, .{ .position = position });
    try world.setGeometryPrimitive(entity, .{
        .primitive = primitive,
        .segments = segments,
        .rings = rings,
    });
    try world.setSurfaceMaterial(entity, .{ .base_color = base_color });
    if (shadow_flags.casts_shadow) {
        try world.setShadowCaster(entity);
    }
    if (shadow_flags.receives_shadow) {
        try world.setShadowReceiver(entity);
    }
}

fn perspective(fovy_radians: f32, aspect: f32, near: f32, far: f32) [16]f32 {
    const f = 1.0 / @tan(fovy_radians * 0.5);
    return .{
        f / aspect, 0.0, 0.0,                         0.0,
        0.0,        f,   0.0,                         0.0,
        0.0,        0.0, far / (near - far),          -1.0,
        0.0,        0.0, (far * near) / (near - far), 0.0,
    };
}

fn orthographic(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) [16]f32 {
    return .{
        2.0 / (right - left),             0.0,                              0.0,                 0.0,
        0.0,                              2.0 / (top - bottom),             0.0,                 0.0,
        0.0,                              0.0,                              1.0 / (near - far),  0.0,
        -(right + left) / (right - left), -(top + bottom) / (top - bottom), near / (near - far), 1.0,
    };
}

fn translation(x: f32, y: f32, z: f32) [16]f32 {
    return .{
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        x,   y,   z,   1.0,
    };
}

fn scaling(x: f32, y: f32, z: f32) [16]f32 {
    return .{
        x,   0.0, 0.0, 0.0,
        0.0, y,   0.0, 0.0,
        0.0, 0.0, z,   0.0,
        0.0, 0.0, 0.0, 1.0,
    };
}

fn rotationX(angle: f32) [16]f32 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{
        1.0, 0.0, 0.0, 0.0,
        0.0, c,   s,   0.0,
        0.0, -s,  c,   0.0,
        0.0, 0.0, 0.0, 1.0,
    };
}

fn rotationY(angle: f32) [16]f32 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{
        c,   0.0, -s,  0.0,
        0.0, 1.0, 0.0, 0.0,
        s,   0.0, c,   0.0,
        0.0, 0.0, 0.0, 1.0,
    };
}

fn rotationZ(angle: f32) [16]f32 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{
        c,   s,   0.0, 0.0,
        -s,  c,   0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    };
}

fn matMul(a: [16]f32, b: [16]f32) [16]f32 {
    var out: [16]f32 = undefined;
    for (0..4) |column| {
        for (0..4) |row| {
            var sum: f32 = 0.0;
            for (0..4) |k| {
                sum += a[k * 4 + row] * b[column * 4 + k];
            }
            out[column * 4 + row] = sum;
        }
    }
    return out;
}

fn buildUiVertices(allocator: std.mem.Allocator, world: *const runtime.World, width: u32, height: u32) RenderError!std.ArrayList(UiVertex) {
    if (width == 0 or height == 0) {
        return RenderError.InvalidScene;
    }

    const input = renderFrameInput(world) catch FrameInput{};
    const canvas_transform = try sceneUiCanvasTransform(world, input, @floatFromInt(width), @floatFromInt(height));
    var vertices: std.ArrayList(UiVertex) = .empty;
    errdefer vertices.deinit(allocator);

    var rects = world.uiRects();
    while (rects.next()) |rect| {
        const maybe_button_state = if (rect.is_button) try renderUiButtonState(world, rect.entity) else null;
        const layout = try resolveUiLayout(world, rect.entity, rect.position);
        const canvas_layout = applyUiCanvasLayout(canvas_transform, rect.id, layout);
        const screen_size = if (isEditorUiEntityId(rect.id)) rect.size else scaleUiSize(canvas_transform, rect.size);
        const screen_layout = try resolveUiScreenLayout(input, rect.id, canvas_layout, screen_size);
        const style_scale: f32 = if (isEditorUiEntityId(rect.id)) 1.0 else canvas_transform.scale;
        const screen_radius = rect.corner_radius * style_scale;
        const maybe_clip = try combineUiClip(screen_layout.clip, try renderUiClip(world, rect.entity));
        var rect_color = rect.color;
        if (maybe_button_state) |state| {
            if (state.held) {
                rect_color = scaleColor(rect.color, 0.86);
            } else if (state.pressed) {
                rect_color = scaleColor(rect.color, 1.1);
            } else if (state.hovered) {
                rect_color = scaleColor(rect.color, 1.06);
            }
        }
        if ((try uiToggleChecked(world, rect.entity)) orelse false) {
            rect_color = scaleColor(rect_color, 1.18);
        }

        try appendStyledUiRect(&vertices, allocator, world, width, height, rect.entity, screen_layout.position, screen_size, rect_color, screen_radius, style_scale, maybe_clip);
        if (try uiProgressBar(world, rect.entity)) |progress| {
            const ratio = try uiProgressRatio(progress);
            if (ratio > 0.0) {
                const fill_size = [3]f32{ screen_size[0] * ratio, screen_size[1], screen_size[2] };
                try appendUiRectClipped(&vertices, allocator, width, height, screen_layout.position, fill_size, progress.fill_color, screen_radius, maybe_clip);
            }
        }
    }

    var separators = world.uiSeparators();
    while (separators.next()) |separator| {
        const layout = try resolveUiLayout(world, separator.entity, separator.position);
        const canvas_layout = applyUiCanvasLayout(canvas_transform, separator.id, layout);
        const screen_size = if (isEditorUiEntityId(separator.id)) separator.size else scaleUiSize(canvas_transform, separator.size);
        const screen_layout = try resolveUiScreenLayout(input, separator.id, canvas_layout, screen_size);
        const maybe_clip = try combineUiClip(screen_layout.clip, try renderUiClip(world, separator.entity));
        try appendUiRectClipped(&vertices, allocator, width, height, screen_layout.position, screen_size, separator.color, 0.0, maybe_clip);
    }

    var texts = world.uiTexts();
    while (texts.next()) |text| {
        const item_size = try uiLayoutItemSize(world, text.entity);
        const layout = try resolveUiLayout(world, text.entity, text.position);
        const canvas_layout = applyUiCanvasLayout(canvas_transform, text.id, layout);
        const screen_item_size = if (isEditorUiEntityId(text.id)) item_size else scaleUiSize(canvas_transform, item_size);
        const screen_layout = try resolveUiScreenLayout(input, text.id, canvas_layout, screen_item_size);
        const maybe_clip = try combineUiClip(screen_layout.clip, try renderUiClip(world, text.entity));
        var resolved_text = text;
        if (isEditorUiEntityId(text.id)) {
            resolved_text.position = try resolveUiTextPosition(world, text.entity, text, screen_layout.position);
        } else {
            const design_position = try resolveUiTextPosition(world, text.entity, text, layout.position);
            resolved_text.position = scaleUiVec3(canvas_transform, design_position);
            resolved_text.size *= canvas_transform.scale;
        }
        try appendUiText(&vertices, allocator, width, height, resolved_text, maybe_clip);
    }

    return vertices;
}

fn uiProgressRatio(progress: UiProgressBar) RenderError!f32 {
    if (!std.math.isFinite(progress.value) or !std.math.isFinite(progress.max) or !isFiniteVec3(progress.fill_color) or progress.max <= 0.0) {
        return RenderError.InvalidScene;
    }
    return clamp01(progress.value / progress.max);
}

fn appendStyledUiRect(
    vertices: *std.ArrayList(UiVertex),
    allocator: std.mem.Allocator,
    world: *const runtime.World,
    width: u32,
    height: u32,
    entity: runtime.EntityHandle,
    position: [3]f32,
    size: [3]f32,
    color: [3]f32,
    corner_radius: f32,
    style_scale: f32,
    clip: ?UiClipRect,
) RenderError!void {
    const border = (try uiBorder(world, entity)) orelse {
        try appendUiRectClipped(vertices, allocator, width, height, position, size, color, corner_radius, clip);
        return;
    };
    if (!isFiniteVec3(border.color) or !std.math.isFinite(border.thickness) or border.thickness < 0.0) {
        return RenderError.InvalidScene;
    }
    if (border.thickness == 0.0) {
        try appendUiRectClipped(vertices, allocator, width, height, position, size, color, corner_radius, clip);
        return;
    }

    const thickness = @min(border.thickness * style_scale, @min(size[0], size[1]) * 0.5);
    try appendUiRectClipped(vertices, allocator, width, height, position, size, border.color, corner_radius, clip);
    const inner_size = [3]f32{
        @max(size[0] - thickness * 2.0, 0.0),
        @max(size[1] - thickness * 2.0, 0.0),
        size[2],
    };
    if (inner_size[0] <= 0.0 or inner_size[1] <= 0.0) {
        return;
    }
    try appendUiRectClipped(
        vertices,
        allocator,
        width,
        height,
        .{ position[0] + thickness, position[1] + thickness, position[2] },
        inner_size,
        color,
        @max(corner_radius - thickness, 0.0),
        clip,
    );
}

fn appendUiText(
    vertices: *std.ArrayList(UiVertex),
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    text: runtime.UiText,
    clip: ?UiClipRect,
) RenderError!void {
    if (!isFiniteVec3(text.position) or
        !std.math.isFinite(text.size) or
        text.size <= 0.0 or
        !isFiniteVec3(text.color))
    {
        return RenderError.InvalidScene;
    }

    const origin_x = text.position[0];
    var cursor_x = origin_x;
    var cursor_y = text.position[1];
    for (text.value) |byte| {
        if (byte == '\n') {
            cursor_x = origin_x;
            cursor_y += text.size * @as(f32, @floatFromInt(ui_font.height));
            continue;
        }
        try appendGlyph(vertices, allocator, width, height, cursor_x, cursor_y, text.size, text.color, byte, clip);
        cursor_x += text.size * @as(f32, @floatFromInt(ui_font.advance));
    }
}

fn appendGlyph(
    vertices: *std.ArrayList(UiVertex),
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    x: f32,
    y: f32,
    size: f32,
    color: [3]f32,
    byte: u8,
    clip: ?UiClipRect,
) RenderError!void {
    const rows = ui_font.glyphRows(byte);
    for (rows, 0..) |row_bits, row| {
        for (0..ui_font.width) |column| {
            const bit: ui_font.BitShift = @intCast(ui_font.width - 1 - column);
            if ((row_bits & (@as(ui_font.Row, 1) << bit)) == 0) {
                continue;
            }
            try appendUiRectClipped(
                vertices,
                allocator,
                width,
                height,
                .{ x + @as(f32, @floatFromInt(column)) * size, y + @as(f32, @floatFromInt(row)) * size, 0.0 },
                .{ size, size, 0.0 },
                color,
                0.0,
                clip,
            );
        }
    }
}

fn appendUiRect(
    vertices: *std.ArrayList(UiVertex),
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    position: [3]f32,
    size: [3]f32,
    color: [3]f32,
) RenderError!void {
    try appendUiRectClipped(vertices, allocator, width, height, position, size, color, 0.0, null);
}

fn appendUiRectClipped(
    vertices: *std.ArrayList(UiVertex),
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    position: [3]f32,
    size: [3]f32,
    color: [3]f32,
    corner_radius: f32,
    clip: ?UiClipRect,
) RenderError!void {
    if (!isFiniteVec3(position) or
        !isFiniteVec3(size) or
        !isFiniteVec3(color) or
        !std.math.isFinite(corner_radius) or
        size[0] <= 0.0 or
        size[1] <= 0.0 or
        corner_radius < 0.0)
    {
        std.log.err(
            "invalid UI rect: position={d:.3},{d:.3},{d:.3} size={d:.3},{d:.3},{d:.3} color={d:.3},{d:.3},{d:.3} radius={d:.3}",
            .{
                position[0],
                position[1],
                position[2],
                size[0],
                size[1],
                size[2],
                color[0],
                color[1],
                color[2],
                corner_radius,
            },
        );
        return RenderError.InvalidScene;
    }

    var clipped_position = position;
    var clipped_size = size;
    if (clip) |clip_rect| {
        if (!isFiniteVec3(clip_rect.position) or !isFiniteVec3(clip_rect.size)) {
            return RenderError.InvalidScene;
        }
        if (clip_rect.size[0] <= 0.0 or clip_rect.size[1] <= 0.0) {
            return;
        }
        const left_px = @max(position[0], clip_rect.position[0]);
        const top_px = @max(position[1], clip_rect.position[1]);
        const right_px = @min(position[0] + size[0], clip_rect.position[0] + clip_rect.size[0]);
        const bottom_px = @min(position[1] + size[1], clip_rect.position[1] + clip_rect.size[1]);
        if (right_px <= left_px or bottom_px <= top_px) {
            return;
        }
        clipped_position = .{ left_px, top_px, position[2] };
        clipped_size = .{ right_px - left_px, bottom_px - top_px, size[2] };
    }

    const left = screenToClipX(clipped_position[0], width);
    const right = screenToClipX(clipped_position[0] + clipped_size[0], width);
    const top = screenToClipY(clipped_position[1], height);
    const bottom = screenToClipY(clipped_position[1] + clipped_size[1], height);
    const vertex_color = [4]f32{ clamp01(color[0]), clamp01(color[1]), clamp01(color[2]), 1.0 };
    const rect_size_radius = [4]f32{
        size[0],
        size[1],
        @min(corner_radius, @min(size[0], size[1]) * 0.5),
        if (corner_radius > 0.0) 1.0 else 0.0,
    };
    const local_left = clipped_position[0] - position[0];
    const local_top = clipped_position[1] - position[1];
    const local_right = local_left + clipped_size[0];
    const local_bottom = local_top + clipped_size[1];

    const quad = [_]UiVertex{
        .{ .position = .{ left, top }, .color = vertex_color, .local_position = .{ local_left, local_top }, .rect_size_radius = rect_size_radius },
        .{ .position = .{ right, top }, .color = vertex_color, .local_position = .{ local_right, local_top }, .rect_size_radius = rect_size_radius },
        .{ .position = .{ right, bottom }, .color = vertex_color, .local_position = .{ local_right, local_bottom }, .rect_size_radius = rect_size_radius },
        .{ .position = .{ left, top }, .color = vertex_color, .local_position = .{ local_left, local_top }, .rect_size_radius = rect_size_radius },
        .{ .position = .{ right, bottom }, .color = vertex_color, .local_position = .{ local_right, local_bottom }, .rect_size_radius = rect_size_radius },
        .{ .position = .{ left, bottom }, .color = vertex_color, .local_position = .{ local_left, local_bottom }, .rect_size_radius = rect_size_radius },
    };
    try vertices.appendSlice(allocator, &quad);
}

fn screenToClipX(value: f32, width: u32) f32 {
    return (value / @as(f32, @floatFromInt(width))) * 2.0 - 1.0;
}

fn screenToClipY(value: f32, height: u32) f32 {
    return 1.0 - (value / @as(f32, @floatFromInt(height))) * 2.0;
}

fn scaleColor(color: [3]f32, scale: f32) [3]f32 {
    return .{
        clamp01(color[0] * scale),
        clamp01(color[1] * scale),
        clamp01(color[2] * scale),
    };
}

fn clamp01(value: f32) f32 {
    return @min(@max(value, 0.0), 1.0);
}

const FrameUniforms = extern struct {
    light_dir: [4]f32,
    light_color: [4]f32,
    lighting: [4]f32,
};

const InstanceAttributes = extern struct {
    mvp: [16]f32,
    model: [16]f32,
    object_color: [4]f32,
    shadow_mvp: [16]f32,
    shadow_flags: [4]f32,
};

const UiVertex = extern struct {
    position: [2]f32,
    color: [4]f32,
    local_position: [2]f32,
    rect_size_radius: [4]f32,
};

fn handleBufferMap(status: wgpu.MapAsyncStatus, _: wgpu.StringView, userdata1: ?*anyopaque, userdata2: ?*anyopaque) callconv(.c) void {
    const complete: *bool = @ptrCast(@alignCast(userdata1));
    complete.* = true;

    const map_status: *wgpu.MapAsyncStatus = @ptrCast(@alignCast(userdata2));
    map_status.* = status;
}

fn write24BitBmp(io: Io, allocator: std.mem.Allocator, output_path: []const u8, bgra_data: []const u8) !void {
    const bytes = try allocator.alloc(u8, bmpFileSize());
    defer allocator.free(bytes);
    @memset(bytes, 0);

    var cursor: usize = 0;
    putBytes(bytes, &cursor, "BM");
    putInt(u32, bytes, &cursor, bmpFileSize());
    putInt(u32, bytes, &cursor, 0);
    putInt(u32, bytes, &cursor, 54);
    putInt(u32, bytes, &cursor, 40);
    putInt(u32, bytes, &cursor, output_width);
    putInt(u32, bytes, &cursor, output_height);
    putInt(u16, bytes, &cursor, 1);
    putInt(u16, bytes, &cursor, 24);
    cursor += 4 * 6;

    var line_buffer = [_]u8{0} ** bmp_bytes_per_line;
    const bgra_pixels_per_line = output_width * 4;
    for (0..output_height) |i_y| {
        const y = output_height - i_y - 1;
        const line_offset = y * bgra_pixels_per_line;
        for (0..output_width) |x| {
            const bgr_pixel_offset = x * 3;
            const bgra_pixel_offset = line_offset + (x * 4);
            line_buffer[bgr_pixel_offset] = bgra_data[bgra_pixel_offset];
            line_buffer[bgr_pixel_offset + 1] = bgra_data[bgra_pixel_offset + 1];
            line_buffer[bgr_pixel_offset + 2] = bgra_data[bgra_pixel_offset + 2];
        }
        putBytes(bytes, &cursor, &line_buffer);
    }

    try Io.Dir.cwd().writeFile(io, .{
        .sub_path = output_path,
        .data = bytes,
    });
}

fn putBytes(output: []u8, cursor: *usize, bytes: []const u8) void {
    @memcpy(output[cursor.*..][0..bytes.len], bytes);
    cursor.* += bytes.len;
}

fn putInt(comptime T: type, output: []u8, cursor: *usize, value: anytype) void {
    const size = @sizeOf(T);
    std.mem.writeInt(T, output[cursor.*..][0..size], @intCast(value), .little);
    cursor.* += size;
}

const bmp_colors_per_line = output_width * 3;
const bmp_bytes_per_line = if (bmp_colors_per_line & 0x00000003 == 0)
    bmp_colors_per_line
else
    (bmp_colors_per_line | 0x00000003) + 1;

fn bmpFileSize() usize {
    return 54 + (bmp_bytes_per_line * output_height);
}
