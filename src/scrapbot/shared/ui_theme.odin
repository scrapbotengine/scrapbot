package shared

UI_Theme_Name :: enum {
	Reduced_Dark,
}

UI_Theme_Surface :: enum {
	Canvas,
	Region,
	Panel,
	Raised,
	Control,
	Overlay,
}

UI_Theme_Text_Role :: enum {
	Primary,
	Secondary,
	Muted,
	Accent,
	Warning,
	Danger,
}

UI_Theme_Button_Role :: enum {
	Quiet,
	Standard,
	Primary,
	Destructive,
}

UI_Theme_Recipe :: enum {
	Canvas,
	Region,
	Panel_Surface,
	Raised,
	Control,
	Overlay,
	Primary_Text,
	Secondary_Text,
	Muted_Text,
	Accent_Text,
	Warning_Text,
	Danger_Text,
	Quiet_Button,
	Standard_Button,
	Primary_Button,
	Destructive_Button,
	Input,
	Panel,
	List,
	Scroll_Area,
	Checkbox,
	Color_Picker,
}

UI_THEME_RECIPE_CAPACITY :: 16

UI_Theme_Palette :: struct {
	canvas: Vec4,
	region: Vec4,
	panel: Vec4,
	raised: Vec4,
	control: Vec4,
	overlay: Vec4,
	border: Vec4,
	border_strong: Vec4,
	text: Vec4,
	text_secondary: Vec4,
	text_muted: Vec4,
	accent: Vec4,
	accent_text: Vec4,
	accent_soft: Vec4,
	hover: Vec4,
	active: Vec4,
	selection: Vec4,
	focus: Vec4,
	warning: Vec4,
	warning_soft: Vec4,
	danger: Vec4,
	danger_soft: Vec4,
}

UI_Theme_Metrics :: struct {
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
	padding_small: Vec4,
	padding_control: Vec4,
	padding_panel: Vec4,
}

UI_Theme :: struct {
	palette: UI_Theme_Palette,
	metrics: UI_Theme_Metrics,
}

UI_Theme_Resolved :: struct {
	has_layout: bool,
	layout: UI_Layout_Component,
	has_scroll_area: bool,
	scroll_area: UI_Scroll_Area_Component,
	has_panel: bool,
	panel: UI_Panel_Component,
	has_list: bool,
	list: UI_List_Component,
	has_text: bool,
	text: UI_Text_Component,
	has_button: bool,
	button: UI_Button_Component,
	has_input: bool,
	input: UI_Input_Component,
	has_checkbox: bool,
	checkbox: UI_Checkbox_Component,
	has_color_picker: bool,
	color_picker: UI_Color_Picker_Component,
}

ui_theme_name :: proc "contextless" (value: UI_Theme_Name) -> string {
	switch value {
		case .Reduced_Dark:
			return "reduced_dark"
	}
	return ""
}

ui_theme_name_parse :: proc "contextless" (value: string) -> (UI_Theme_Name, bool) {
	if value == "reduced_dark" {
		return .Reduced_Dark, true
	}
	return {}, false
}

ui_theme_recipe_name :: proc "contextless" (value: UI_Theme_Recipe) -> string {
	switch value {
		case .Canvas:
			return "canvas"
		case .Region:
			return "region"
		case .Panel_Surface:
			return "panel_surface"
		case .Raised:
			return "raised"
		case .Control:
			return "control"
		case .Overlay:
			return "overlay"
		case .Primary_Text:
			return "primary_text"
		case .Secondary_Text:
			return "secondary_text"
		case .Muted_Text:
			return "muted_text"
		case .Accent_Text:
			return "accent_text"
		case .Warning_Text:
			return "warning_text"
		case .Danger_Text:
			return "danger_text"
		case .Quiet_Button:
			return "quiet_button"
		case .Standard_Button:
			return "standard_button"
		case .Primary_Button:
			return "primary_button"
		case .Destructive_Button:
			return "destructive_button"
		case .Input:
			return "input"
		case .Panel:
			return "panel"
		case .List:
			return "list"
		case .Scroll_Area:
			return "scroll_area"
		case .Checkbox:
			return "checkbox"
		case .Color_Picker:
			return "color_picker"
	}
	return ""
}

ui_theme_recipe_parse :: proc "contextless" (value: string) -> (UI_Theme_Recipe, bool) {
	for recipe in UI_Theme_Recipe {
		if ui_theme_recipe_name(recipe) == value {
			return recipe, true
		}
	}
	return {}, false
}

ui_theme_builtin :: proc "contextless" (name: UI_Theme_Name) -> UI_Theme {
	switch name {
		case .Reduced_Dark:
			return ui_theme_reduced_dark()
	}
	return {}
}

ui_theme_reduced_dark :: proc "contextless" () -> UI_Theme {
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

ui_theme_surface_color :: proc "contextless" (theme: UI_Theme, role: UI_Theme_Surface) -> Vec4 {
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

ui_theme_apply_surface :: proc "contextless" (
	value: ^UI_Layout_Component,
	theme: UI_Theme,
	role: UI_Theme_Surface,
	bordered := false,
) {
	if value == nil {
		return
	}
	value.background = ui_theme_surface_color(theme, role)
	value.border_color = theme.palette.border
	value.border_width = 0
	value.corner_radius = theme.metrics.radius
	if bordered {
		value.border_width = theme.metrics.border_width
	}
}

ui_theme_text_color :: proc "contextless" (theme: UI_Theme, role: UI_Theme_Text_Role) -> Vec4 {
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

ui_theme_text :: proc "contextless" (
	theme: UI_Theme,
	text: string,
	role := UI_Theme_Text_Role.Primary,
	size: f32 = 0,
) -> UI_Text_Component {
	result := ui_text_default()
	result.text = text
	result.color = ui_theme_text_color(theme, role)
	result.size = size
	if result.size <= 0 {
		result.size = theme.metrics.text_size
	}
	return result
}

ui_theme_button :: proc "contextless" (
	theme: UI_Theme,
	role := UI_Theme_Button_Role.Standard,
) -> (
	layout: UI_Layout_Component,
	button: UI_Button_Component,
) {
	layout = ui_layout_default()
	layout.size = {80, theme.metrics.control_height}
	layout.padding = theme.metrics.padding_control
	layout.corner_radius = theme.metrics.radius
	layout.border_color = theme.palette.border
	layout.border_width = theme.metrics.border_width
	button = ui_button_default()
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

ui_theme_input :: proc "contextless" (
	theme: UI_Theme,
) -> (
	layout: UI_Layout_Component,
	input: UI_Input_Component,
) {
	layout = ui_layout_default()
	layout.size = {160, theme.metrics.control_height}
	layout.padding = theme.metrics.padding_control
	layout.background = theme.palette.control
	layout.border_color = theme.palette.border
	layout.border_width = theme.metrics.border_width
	layout.corner_radius = theme.metrics.radius_small
	input = ui_input_default()
	input.color = theme.palette.text
	input.prefix_color = theme.palette.text_muted
	input.prefix_background = theme.palette.raised
	input.size = theme.metrics.text_size
	input.selection_background = theme.palette.selection
	input.focus_border_color = theme.palette.focus
	input.invalid_border_color = theme.palette.danger
	return
}

ui_theme_panel :: proc "contextless" (
	theme: UI_Theme,
) -> (
	layout: UI_Layout_Component,
	panel: UI_Panel_Component,
) {
	layout = ui_layout_default()
	layout.size = {320, 160}
	layout.padding = theme.metrics.padding_panel
	layout.background = theme.palette.panel
	layout.border_color = theme.palette.border
	layout.corner_radius = theme.metrics.radius
	panel = ui_panel_default()
	panel.title_color = theme.palette.text
	panel.title_background = theme.palette.raised
	panel.title_size = theme.metrics.text_size
	panel.title_height = theme.metrics.title_height
	panel.disclosure_corner_radius = theme.metrics.radius_small
	return
}

ui_theme_list :: proc "contextless" (theme: UI_Theme) -> UI_List_Component {
	result := ui_list_default()
	result.gap = 1
	result.selection_background = theme.palette.selection
	result.hover_background = theme.palette.hover
	result.active_background = theme.palette.active
	result.drop_target_background = theme.palette.accent_soft
	result.drop_indicator_color = theme.palette.accent
	return result
}

ui_theme_scroll_area :: proc "contextless" (theme: UI_Theme) -> UI_Scroll_Area_Component {
	result := ui_scroll_area_default()
	result.scrollbar_track_color = {0, 0, 0, 0}
	result.scrollbar_thumb_color = theme.palette.border_strong
	result.scrollbar_corner_radius = theme.metrics.radius_small
	return result
}

ui_theme_checkbox :: proc "contextless" (theme: UI_Theme) -> UI_Checkbox_Component {
	result := ui_checkbox_default()
	result.background = theme.palette.control
	result.checked_background = theme.palette.accent_soft
	result.border_color = theme.palette.border_strong
	result.check_color = theme.palette.accent_text
	result.hover_background = {0.045, 0.155, 0.133, 1}
	result.active_background = {0.025, 0.085, 0.074, 1}
	result.corner_radius = theme.metrics.radius_small
	return result
}

ui_theme_color_picker :: proc "contextless" (theme: UI_Theme) -> UI_Color_Picker_Component {
	result := ui_color_picker_default()
	result.thumb_border_color = theme.palette.canvas
	result.thumb_border_width = 2
	return result
}

ui_theme_apply_recipe :: proc "contextless" (
	resolved: ^UI_Theme_Resolved,
	theme: UI_Theme,
	recipe: UI_Theme_Recipe,
) {
	if resolved == nil {
		return
	}
	switch recipe {
		case .Canvas:
			resolved.has_layout = true
			ui_theme_apply_surface(&resolved.layout, theme, .Canvas)
		case .Region:
			resolved.has_layout = true
			ui_theme_apply_surface(&resolved.layout, theme, .Region)
		case .Panel_Surface:
			resolved.has_layout = true
			ui_theme_apply_surface(&resolved.layout, theme, .Panel)
		case .Raised:
			resolved.has_layout = true
			ui_theme_apply_surface(&resolved.layout, theme, .Raised)
		case .Control:
			resolved.has_layout = true
			ui_theme_apply_surface(&resolved.layout, theme, .Control)
		case .Overlay:
			resolved.has_layout = true
			ui_theme_apply_surface(&resolved.layout, theme, .Overlay)
		case .Primary_Text:
			resolved.has_text = true
			resolved.text = ui_theme_text(theme, "", .Primary)
		case .Secondary_Text:
			resolved.has_text = true
			resolved.text = ui_theme_text(theme, "", .Secondary)
		case .Muted_Text:
			resolved.has_text = true
			resolved.text = ui_theme_text(theme, "", .Muted)
		case .Accent_Text:
			resolved.has_text = true
			resolved.text = ui_theme_text(theme, "", .Accent)
		case .Warning_Text:
			resolved.has_text = true
			resolved.text = ui_theme_text(theme, "", .Warning)
		case .Danger_Text:
			resolved.has_text = true
			resolved.text = ui_theme_text(theme, "", .Danger)
		case .Quiet_Button, .Standard_Button, .Primary_Button, .Destructive_Button:
			role := UI_Theme_Button_Role.Standard
			#partial switch recipe {
				case .Quiet_Button:
					role = .Quiet
				case .Primary_Button:
					role = .Primary
				case .Destructive_Button:
					role = .Destructive
			}
			resolved.layout, resolved.button = ui_theme_button(theme, role)
			resolved.has_layout = true
			resolved.has_button = true
		case .Input:
			resolved.layout, resolved.input = ui_theme_input(theme)
			resolved.has_layout = true
			resolved.has_input = true
		case .Panel:
			resolved.layout, resolved.panel = ui_theme_panel(theme)
			resolved.has_layout = true
			resolved.has_panel = true
		case .List:
			resolved.list = ui_theme_list(theme)
			resolved.has_list = true
		case .Scroll_Area:
			resolved.scroll_area = ui_theme_scroll_area(theme)
			resolved.has_scroll_area = true
		case .Checkbox:
			resolved.checkbox = ui_theme_checkbox(theme)
			resolved.has_checkbox = true
		case .Color_Picker:
			resolved.color_picker = ui_theme_color_picker(theme)
			resolved.has_color_picker = true
	}
}

ui_theme_resolve :: proc "contextless" (
	name: UI_Theme_Name,
	recipes: []UI_Theme_Recipe,
) -> UI_Theme_Resolved {
	resolved: UI_Theme_Resolved
	theme := ui_theme_builtin(name)
	for recipe in recipes {
		ui_theme_apply_recipe(&resolved, theme, recipe)
	}
	return resolved
}
