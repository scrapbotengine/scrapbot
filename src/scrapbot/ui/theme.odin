package ui

import shared "../shared"

Theme_Surface :: enum {
	Canvas,
	Region,
	Panel,
	Raised,
	Control,
	Overlay,
}

Theme_Text_Role :: enum {
	Primary,
	Secondary,
	Muted,
	Accent,
	Warning,
	Danger,
}

Theme_Button_Role :: enum {
	Quiet,
	Standard,
	Primary,
	Destructive,
}

Theme_Palette :: struct {
	canvas: shared.Vec4,
	region: shared.Vec4,
	panel: shared.Vec4,
	raised: shared.Vec4,
	control: shared.Vec4,
	overlay: shared.Vec4,
	border: shared.Vec4,
	border_strong: shared.Vec4,
	text: shared.Vec4,
	text_secondary: shared.Vec4,
	text_muted: shared.Vec4,
	accent: shared.Vec4,
	accent_text: shared.Vec4,
	accent_soft: shared.Vec4,
	hover: shared.Vec4,
	active: shared.Vec4,
	selection: shared.Vec4,
	focus: shared.Vec4,
	warning: shared.Vec4,
	warning_soft: shared.Vec4,
	danger: shared.Vec4,
	danger_soft: shared.Vec4,
}

Theme_Metrics :: struct {
	text_size: f32,
	small_text_size: f32,
	control_height: f32,
	row_height: f32,
	title_height: f32,
	radius_small: f32,
	radius: f32,
	radius_large: f32,
	border_width: f32,
	gap_small: f32,
	gap: f32,
	gap_large: f32,
	padding_small: shared.Vec4,
	padding_control: shared.Vec4,
	padding_panel: shared.Vec4,
}

Theme :: struct {
	palette: Theme_Palette,
	metrics: Theme_Metrics,
}

reduced_dark_theme :: proc "contextless" () -> Theme {
	return {
		palette = {
			canvas = {0.005, 0.007, 0.010, 1},
			region = {0.009, 0.012, 0.017, 1},
			panel = {0.015, 0.019, 0.026, 1},
			raised = {0.022, 0.028, 0.037, 1},
			control = {0.018, 0.023, 0.031, 1},
			overlay = {0.006, 0.009, 0.013, 0.94},
			border = {0.050, 0.060, 0.076, 1},
			border_strong = {0.085, 0.100, 0.126, 1},
			text = {0.86, 0.88, 0.92, 1},
			text_secondary = {0.64, 0.67, 0.73, 1},
			text_muted = {0.40, 0.43, 0.49, 1},
			accent = {0.30, 0.88, 0.75, 1},
			accent_text = {0.82, 1.00, 0.95, 1},
			accent_soft = {0.030, 0.105, 0.092, 1},
			hover = {0.028, 0.036, 0.048, 1},
			active = {0.042, 0.053, 0.070, 1},
			selection = {0.040, 0.105, 0.098, 1},
			focus = {0.20, 0.82, 0.70, 1},
			warning = {0.94, 0.58, 0.22, 1},
			warning_soft = {0.090, 0.050, 0.018, 1},
			danger = {0.94, 0.29, 0.34, 1},
			danger_soft = {0.120, 0.030, 0.040, 1},
		},
		metrics = {
			text_size = 13,
			small_text_size = 11,
			control_height = 30,
			row_height = 32,
			title_height = 32,
			radius_small = 3,
			radius = 5,
			radius_large = 8,
			border_width = 1,
			gap_small = 4,
			gap = 8,
			gap_large = 12,
			padding_small = {4, 6, 4, 6},
			padding_control = {7, 9, 6, 9},
			padding_panel = {10, 12, 12, 12},
		},
	}
}

theme_surface_color :: proc "contextless" (theme: Theme, role: Theme_Surface) -> shared.Vec4 {
	switch role {
		case .Canvas:
			return theme.palette.canvas
		case .Region:
			return theme.palette.region
		case .Panel:
			return theme.palette.panel
		case .Raised:
			return theme.palette.raised
		case .Control:
			return theme.palette.control
		case .Overlay:
			return theme.palette.overlay
	}
	return theme.palette.canvas
}

theme_apply_surface :: proc "contextless" (
	value: ^shared.UI_Layout_Component,
	theme: Theme,
	role: Theme_Surface,
	bordered := false,
) {
	if value == nil {
		return
	}
	value.background = theme_surface_color(theme, role)
	value.border_color = theme.palette.border
	value.border_width = 0
	value.corner_radius = theme.metrics.radius
	if bordered {
		value.border_width = theme.metrics.border_width
	}
}

theme_text_color :: proc "contextless" (theme: Theme, role: Theme_Text_Role) -> shared.Vec4 {
	switch role {
		case .Primary:
			return theme.palette.text
		case .Secondary:
			return theme.palette.text_secondary
		case .Muted:
			return theme.palette.text_muted
		case .Accent:
			return theme.palette.accent
		case .Warning:
			return theme.palette.warning
		case .Danger:
			return theme.palette.danger
	}
	return theme.palette.text
}

theme_text :: proc "contextless" (
	theme: Theme,
	text: string,
	role := Theme_Text_Role.Primary,
	size: f32 = 0,
) -> shared.UI_Text_Component {
	result := shared.ui_text_default()
	result.text = text
	result.color = theme_text_color(theme, role)
	result.size = size
	if result.size <= 0 {
		result.size = theme.metrics.text_size
	}
	return result
}

theme_button :: proc "contextless" (
	theme: Theme,
	role := Theme_Button_Role.Standard,
) -> (
	layout: shared.UI_Layout_Component,
	button: shared.UI_Button_Component,
) {
	layout = shared.ui_layout_default()
	layout.size = {80, theme.metrics.control_height}
	layout.padding = theme.metrics.padding_control
	layout.corner_radius = theme.metrics.radius
	layout.border_color = theme.palette.border
	layout.border_width = theme.metrics.border_width
	button = shared.ui_button_default()
	button.size = theme.metrics.text_size
	button.color = theme.palette.text_secondary
	button.hover_background = theme.palette.hover
	button.active_background = theme.palette.active
	switch role {
		case .Quiet:
			layout.background = {0, 0, 0, 0}
			layout.border_width = 0
		case .Standard:
			layout.background = theme.palette.control
		case .Primary:
			layout.background = theme.palette.accent_soft
			layout.border_color = theme.palette.accent
			button.color = theme.palette.accent_text
			button.hover_background = {0.045, 0.155, 0.133, 1}
			button.active_background = {0.025, 0.085, 0.074, 1}
		case .Destructive:
			layout.background = theme.palette.danger_soft
			layout.border_color = theme.palette.danger
			button.color = {1.00, 0.78, 0.80, 1}
			button.hover_background = {0.20, 0.045, 0.060, 1}
			button.active_background = {0.10, 0.020, 0.030, 1}
	}
	return
}

theme_input :: proc "contextless" (
	theme: Theme,
) -> (
	layout: shared.UI_Layout_Component,
	input: shared.UI_Input_Component,
) {
	layout = shared.ui_layout_default()
	layout.size = {160, theme.metrics.control_height}
	layout.padding = theme.metrics.padding_control
	layout.background = theme.palette.control
	layout.border_color = theme.palette.border
	layout.border_width = theme.metrics.border_width
	layout.corner_radius = theme.metrics.radius_small
	input = shared.ui_input_default()
	input.color = theme.palette.text
	input.prefix_color = theme.palette.text_muted
	input.prefix_background = theme.palette.raised
	input.size = theme.metrics.text_size
	input.selection_background = theme.palette.selection
	input.focus_border_color = theme.palette.focus
	input.invalid_border_color = theme.palette.danger
	return
}

theme_panel :: proc "contextless" (
	theme: Theme,
) -> (
	layout: shared.UI_Layout_Component,
	panel: shared.UI_Panel_Component,
) {
	layout = shared.ui_layout_default()
	layout.size = {320, 160}
	layout.padding = theme.metrics.padding_panel
	layout.background = theme.palette.panel
	layout.border_color = theme.palette.border
	layout.corner_radius = theme.metrics.radius
	panel = shared.ui_panel_default()
	panel.title_color = theme.palette.text
	panel.title_background = theme.palette.raised
	panel.title_size = theme.metrics.text_size
	panel.title_height = theme.metrics.title_height
	panel.disclosure_corner_radius = theme.metrics.radius_small
	return
}

theme_list :: proc "contextless" (theme: Theme) -> shared.UI_List_Component {
	result := shared.ui_list_default()
	result.gap = 1
	result.selection_background = theme.palette.selection
	result.hover_background = theme.palette.hover
	result.active_background = theme.palette.active
	result.drop_target_background = theme.palette.accent_soft
	result.drop_indicator_color = theme.palette.accent
	return result
}

theme_scroll_area :: proc "contextless" (theme: Theme) -> shared.UI_Scroll_Area_Component {
	result := shared.ui_scroll_area_default()
	result.scrollbar_track_color = {0, 0, 0, 0}
	result.scrollbar_thumb_color = theme.palette.border_strong
	result.scrollbar_corner_radius = theme.metrics.radius_small
	return result
}

theme_checkbox :: proc "contextless" (theme: Theme) -> shared.UI_Checkbox_Component {
	result := shared.ui_checkbox_default()
	result.background = theme.palette.control
	result.checked_background = theme.palette.accent_soft
	result.border_color = theme.palette.border_strong
	result.check_color = theme.palette.accent_text
	result.hover_background = {0.045, 0.155, 0.133, 1}
	result.active_background = {0.025, 0.085, 0.074, 1}
	result.corner_radius = theme.metrics.radius_small
	return result
}

theme_color_picker :: proc "contextless" (theme: Theme) -> shared.UI_Color_Picker_Component {
	result := shared.ui_color_picker_default()
	result.thumb_border_color = theme.palette.canvas
	result.thumb_border_width = 2
	return result
}
