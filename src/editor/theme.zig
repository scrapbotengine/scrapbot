pub const system_text_size: f32 = 1.0;
pub const panel_padding_y: f32 = 24.0;
pub const panel_section_gap: f32 = 20.0;
pub const panel_label_gap: f32 = 12.0;
pub const panel_bottom_padding: f32 = 20.0;
pub const panel_corner_radius: f32 = 16.0;
pub const sidebar_panel_margin: f32 = 8.0;
pub const button_corner_radius: f32 = 6.0;

pub const system_row_stride: f32 = 44.0;
pub const system_row_label_padding_x: f32 = 20.0;
pub const system_row_duration_padding_x: f32 = 20.0;
pub const system_field_column_gap: f32 = 4.0;
pub const system_card_padding_y: f32 = 20.0;
pub const system_scroll_pixels_per_wheel: f32 = 18.0;
pub const system_scroll_smoothing: f32 = 22.0;

pub const entity_text_size: f32 = 1.0;
pub const entity_row_stride: f32 = 36.0;
pub const entity_row_label_padding_x: f32 = 20.0;
pub const entity_row_component_padding_x: f32 = 20.0;
pub const entity_field_column_gap: f32 = 4.0;
pub const entity_card_padding_y: f32 = 16.0;
pub const left_panel_gap: f32 = 12.0;
pub const entity_panel_min_height: f32 = 160.0;
pub const system_panel_min_height: f32 = 180.0;

pub const scrollbar_width: f32 = 8.0;
pub const scrollbar_gap: f32 = 12.0;
pub const bar_text_offset_y: f32 = 16.0;
pub const top_fps_x: f32 = 152.0;

pub const command_play_toggle = "scrapbot.editor.play_toggle";
pub const command_step = "scrapbot.editor.step";
pub const command_splitter_left = "scrapbot.editor.splitter.left";
pub const command_splitter_right = "scrapbot.editor.splitter.right";

pub const geometry_primitives = [_][]const u8{ "box", "plane", "uv_sphere", "ico_sphere" };
pub const color_channels = [_][3]f32{
    .{ 0.941, 0.267, 0.267 },
    .{ 0.133, 0.773, 0.369 },
    .{ 0.231, 0.51, 0.965 },
};
pub const vec3_lane_labels = [_][]const u8{ "X", "Y", "Z" };

pub const palette = struct {
    pub const shell = [3]f32{ 0.008, 0.012, 0.024 };
    pub const panel = [3]f32{ 0.031, 0.041, 0.063 };
    pub const panel_muted = [3]f32{ 0.094, 0.116, 0.151 };
    pub const input = [3]f32{ 0.016, 0.023, 0.039 };
    pub const input_selection = [3]f32{ 0.063, 0.255, 0.337 };
    pub const input_active = [3]f32{ 0.047, 0.349, 0.263 };
    pub const accent = [3]f32{ 0.031, 0.431, 0.533 };
    pub const accent_soft = [3]f32{ 0.22, 0.714, 0.82 };
    pub const text = [3]f32{ 0.886, 0.91, 0.941 };
    pub const text_muted = [3]f32{ 0.58, 0.639, 0.722 };
    pub const text_dim = [3]f32{ 0.392, 0.455, 0.545 };
    pub const danger = [3]f32{ 0.82, 0.282, 0.282 };
    pub const info = [3]f32{ 0.49, 0.745, 0.933 };
    pub const primary = [3]f32{ 0.028, 0.324, 0.49 };
    pub const success = [3]f32{ 0.023, 0.471, 0.314 };
    pub const warning = [3]f32{ 0.714, 0.333, 0.031 };
};
