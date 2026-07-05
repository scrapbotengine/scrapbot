const std = @import("std");
const runtime = @import("../runtime.zig");
const platform = @import("platform.zig");
const wgpu = @import("wgpu");
const sdl = platform.sdl;

pub const output_width = 640;
pub const output_height = 480;
pub const output_extent = wgpu.Extent3D{
    .width = output_width,
    .height = output_height,
    .depth_or_array_layers = 1,
};
pub const output_bytes_per_row = 4 * output_width;
pub const output_size = output_bytes_per_row * output_height;
pub const depth_format = wgpu.TextureFormat.depth24_plus;
pub const shadow_depth_format = wgpu.TextureFormat.depth32_float;
pub const shadow_map_size = 1024;
pub const render_ui_button_state_component_id = "scrapbot.render.internal.ui.button_state";
pub const render_ui_clip_component_id = "scrapbot.render.internal.ui.clip";
pub const render_draw_batch_component_id = "scrapbot.render.internal.draw.batch";
pub const render_draw_ui_component_id = "scrapbot.render.internal.draw.ui";
pub const render_extract_system_id = "scrapbot.render.extract";
pub const render_prepare_meshes_system_id = "scrapbot.render.prepare_meshes";
pub const render_queue_meshes_system_id = "scrapbot.render.queue_meshes";
pub const render_interact_ui_system_id = "scrapbot.render.interact_ui";
pub const render_prepare_ui_system_id = "scrapbot.render.prepare_ui";
pub const render_queue_ui_system_id = "scrapbot.render.queue_ui";
pub const render_draw_meshes_system_id = "scrapbot.render.draw_meshes";
pub const default_window_width = 1280;
pub const default_window_height = 720;
pub const editor_top_bar_height: f32 = 56.0;
pub const editor_bottom_bar_height: f32 = 60.0;
pub const editor_left_sidebar_target_width: f32 = 420.0;
pub const editor_left_sidebar_min_width: f32 = 260.0;
pub const editor_right_sidebar_target_width: f32 = 460.0;
pub const editor_right_sidebar_min_width: f32 = 300.0;
pub const editor_min_game_viewport_width: f32 = 320.0;
pub const editor_splitter_width: f32 = 2.0;
pub const editor_splitter_hit_width: f32 = 12.0;
pub const editor_performance_display_interval_ns: u64 = 333_000_000;
pub const live_run_default_delta_seconds: f32 = 1.0 / 60.0;
pub const live_run_max_delta_seconds: f32 = 0.1;
pub const editor_system_text_size: f32 = 1.0;
pub const editor_panel_padding_x: f32 = 16.0;
pub const editor_panel_padding_y: f32 = 22.0;
pub const editor_panel_section_gap: f32 = 18.0;
pub const editor_panel_label_gap: f32 = 10.0;
pub const editor_panel_bottom_padding: f32 = 18.0;
pub const editor_system_row_stride: f32 = 40.0;
pub const editor_system_row_label_padding_x: f32 = 16.0;
pub const editor_system_row_duration_padding_x: f32 = 16.0;
pub const editor_system_field_column_gap: f32 = 4.0;
pub const editor_system_card_padding_y: f32 = 16.0;
pub const editor_system_scroll_pixels_per_wheel: f32 = 18.0;
pub const editor_system_scroll_smoothing: f32 = 22.0;
pub const editor_scrollbar_width: f32 = 6.0;
pub const editor_scrollbar_gap: f32 = 10.0;
pub const render_system_profile_window_frames: usize = 120;
pub const editor_control_button_width: f32 = 104.0;
pub const editor_control_button_height: f32 = 36.0;
pub const editor_control_button_gap: f32 = 14.0;
pub const editor_panel_corner_radius: f32 = 16.0;
pub const editor_sidebar_panel_margin: f32 = 6.0;
pub const editor_button_corner_radius: f32 = 6.0;
pub const editor_command_play_toggle = "scrapbot.editor.play_toggle";
pub const editor_command_step = "scrapbot.editor.step";
pub const editor_command_splitter_left = "scrapbot.editor.splitter.left";
pub const editor_command_splitter_right = "scrapbot.editor.splitter.right";
pub const fly_camera_move_speed: f32 = 6.0;
pub const fly_camera_look_sensitivity: f32 = 0.0035;
pub const fly_camera_max_pitch: f32 = std.math.degreesToRadians(89.0);
pub const editor_inspector_text_size: f32 = 1.0;
pub const editor_inspector_line_stride: f32 = 32.0;
pub const editor_inspector_field_row_margin_y: f32 = 2.0;
pub const editor_inspector_card_gap: f32 = 4.0;
pub const editor_inspector_separator_height: f32 = 1.0;
pub const editor_inspector_card_padding_x: f32 = 20.0;
pub const editor_inspector_card_padding_y: f32 = 20.0;
pub const editor_inspector_field_value_column_x: f32 = 204.0;
pub const editor_inspector_field_column_gap: f32 = 12.0;
pub const editor_inspector_input_padding_x: f32 = 2.0;
pub const editor_inspector_input_padding_y: f32 = 2.0;
pub const editor_inspector_input_gap: f32 = 8.0;
pub const editor_inspector_input_border_thickness: f32 = 1.0;
pub const editor_inspector_input_text_offset_x: f32 = editor_inspector_input_border_thickness + editor_inspector_input_padding_x;
pub const editor_inspector_input_text_offset_y: f32 = editor_inspector_input_border_thickness + editor_inspector_input_padding_y;
pub const editor_inspector_input_height: f32 = 38.0;
pub const editor_inspector_input_cell_padding: f32 = 2.0;
pub const editor_inspector_field_row_height: f32 = editor_inspector_input_height + editor_inspector_input_cell_padding * 2.0;
pub const editor_inspector_field_row_stride: f32 = editor_inspector_field_row_height + editor_inspector_field_row_margin_y;
pub const editor_inspector_input_corner_radius: f32 = 8.0;
pub const editor_inspector_caret_width: f32 = 2.0;
pub const editor_inspector_field_control_offset_y: f32 = -4.0;
pub const editor_inspector_field_text_offset_y: f32 = -editor_inspector_field_control_offset_y + editor_inspector_input_cell_padding;
pub const editor_inspector_selection_padding_y: f32 = 4.0;
pub const editor_component_id_buffer_len = 128;
pub const editor_field_name_buffer_len = 64;
pub const editor_input_text_buffer_len = 128;
pub const editor_undo_capacity = 64;
pub const editor_gizmo_axis_length: f32 = 1.25;
pub const editor_gizmo_axis_thickness: f32 = 0.035;
pub const editor_gizmo_pick_radius_px: f32 = 18.0;

pub const editor_palette = struct {
    pub const shell = [3]f32{ 0.008, 0.012, 0.024 };
    pub const panel = [3]f32{ 0.031, 0.041, 0.063 };
    pub const panel_muted = [3]f32{ 0.094, 0.116, 0.151 };
    pub const input = [3]f32{ 0.016, 0.023, 0.039 };
    pub const input_selection = [3]f32{ 0.063, 0.255, 0.337 };
    pub const accent = [3]f32{ 0.031, 0.431, 0.533 };
    pub const accent_soft = [3]f32{ 0.22, 0.714, 0.82 };
    pub const text = [3]f32{ 0.886, 0.91, 0.941 };
    pub const text_muted = [3]f32{ 0.58, 0.639, 0.722 };
    pub const text_dim = [3]f32{ 0.392, 0.455, 0.545 };
    pub const danger = [3]f32{ 0.82, 0.282, 0.282 };
    const info = [3]f32{ 0.49, 0.745, 0.933 };
    pub const primary = [3]f32{ 0.028, 0.324, 0.49 };
    pub const success = [3]f32{ 0.023, 0.471, 0.314 };
    pub const warning = [3]f32{ 0.714, 0.333, 0.031 };
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
    hidden: bool = false,
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

    pub fn beginFrame(self: *PointerInput) void {
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

    pub fn beginFrame(self: *KeyboardInput) void {
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

pub const EditorFieldSelection = struct {
    active: bool = false,
    entity: runtime.EntityHandle = .{ .index = 0, .generation = 0 },
    component_id: [editor_component_id_buffer_len]u8 = [_]u8{0} ** editor_component_id_buffer_len,
    component_id_len: usize = 0,
    field_name: [editor_field_name_buffer_len]u8 = [_]u8{0} ** editor_field_name_buffer_len,
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
        buffer: [editor_input_text_buffer_len]u8 = [_]u8{0} ** editor_input_text_buffer_len,
        len: usize = 0,
    },

    pub fn from(value: runtime.ComponentValue) ?EditorStoredValue {
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

    pub fn componentValue(self: *const EditorStoredValue) runtime.ComponentValue {
        return switch (self.*) {
            .boolean => |payload| .{ .boolean = payload },
            .int => |payload| .{ .int = payload },
            .float => |payload| .{ .float = payload },
            .vec3 => |payload| .{ .vec3 = payload },
            .string => |payload| .{ .string = payload.buffer[0..payload.len] },
        };
    }
};

pub const EditorFieldEditCommand = struct {
    active: bool = false,
    entity: runtime.EntityHandle = .{ .index = 0, .generation = 0 },
    component_id: [editor_component_id_buffer_len]u8 = [_]u8{0} ** editor_component_id_buffer_len,
    component_id_len: usize = 0,
    field_name: [editor_field_name_buffer_len]u8 = [_]u8{0} ** editor_field_name_buffer_len,
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
    buffer: [editor_input_text_buffer_len]u8 = [_]u8{0} ** editor_input_text_buffer_len,
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
    buffer: [editor_input_text_buffer_len]u8 = [_]u8{0} ** editor_input_text_buffer_len,
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

pub const EditorCursorKind = enum {
    default,
    resize_ew,
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

    pub fn beginFrame(self: *FrameInput) void {
        self.pointer.beginFrame();
        self.keyboard.beginFrame();
        self.system_profile_count_hint = 0;
        self.text_input_len = 0;
        @memset(self.text_input[0..], 0);
    }

    pub fn appendTextInput(self: *FrameInput, value: []const u8) void {
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

    pub fn textInput(self: *const FrameInput) []const u8 {
        return self.text_input[0..self.text_input_len];
    }
};

pub const FrameUniforms = extern struct {
    light_dir: [4]f32,
    light_color: [4]f32,
    lighting: [4]f32,
};

pub const InstanceAttributes = extern struct {
    mvp: [16]f32,
    model: [16]f32,
    object_color: [4]f32,
    shadow_mvp: [16]f32,
    shadow_flags: [4]f32,
};

pub const UiVertex = extern struct {
    position: [2]f32,
    color: [4]f32,
    local_position: [2]f32,
    rect_size_radius: [4]f32,
};

pub const InstanceConfig = struct {
    width: f32,
    height: f32,
    mesh: *const runtime.RenderableMesh,
    camera: CameraState,
    light_view_projection: [16]f32,
};

pub const CameraState = struct {
    transform: runtime.Transform = .{ .position = .{ 0.0, 0.0, 4.8 } },
    fov_y_degrees: f32 = 48.0,
    near: f32 = 0.1,
    far: f32 = 100.0,
};

pub const DirectionalLightState = struct {
    direction: [3]f32 = .{ 0.35, 0.68, 0.64 },
    color: [3]f32 = .{ 1.0, 1.0, 1.0 },
    intensity: f32 = 0.78,
    ambient: f32 = 0.18,
};

const ui_layout = @import("../ui_layout.zig");
pub const UiButtonState = struct {
    hovered: bool = false,
    held: bool = false,
    pressed: bool = false,
};

pub const UiClipRect = ui_layout.ClipRect;

pub const UiCanvasTransform = ui_layout.CanvasTransform;

pub const UiBorder = struct {
    color: [3]f32,
    thickness: f32,
};

pub const UiProgressBar = struct {
    value: f32,
    max: f32,
    fill_color: [3]f32,
};
