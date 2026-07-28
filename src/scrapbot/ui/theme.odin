package ui

import shared "../shared"

Theme_Surface :: shared.UI_Theme_Surface
Theme_Text_Role :: shared.UI_Theme_Text_Role
Theme_Button_Role :: shared.UI_Theme_Button_Role
Theme_Palette :: shared.UI_Theme_Palette
Theme_Metrics :: shared.UI_Theme_Metrics
Theme :: shared.UI_Theme

reduced_dark_theme :: proc "contextless" () -> Theme {
	return shared.ui_theme_reduced_dark()
}

theme_surface_color :: proc "contextless" (theme: Theme, role: Theme_Surface) -> shared.Vec4 {
	return shared.ui_theme_surface_color(theme, role)
}

theme_apply_surface :: proc "contextless" (
	value: ^shared.UI_Layout_Component,
	theme: Theme,
	role: Theme_Surface,
	bordered := false,
) {
	shared.ui_theme_apply_surface(value, theme, role, bordered)
}

theme_text_color :: proc "contextless" (theme: Theme, role: Theme_Text_Role) -> shared.Vec4 {
	return shared.ui_theme_text_color(theme, role)
}

theme_text :: proc "contextless" (
	theme: Theme,
	text: string,
	role := Theme_Text_Role.Primary,
	size: f32 = 0,
) -> shared.UI_Text_Component {
	return shared.ui_theme_text(theme, text, role, size)
}

theme_button :: proc "contextless" (
	theme: Theme,
	role := Theme_Button_Role.Standard,
) -> (
	layout: shared.UI_Layout_Component,
	button: shared.UI_Button_Component,
) {
	return shared.ui_theme_button(theme, role)
}

theme_input :: proc "contextless" (
	theme: Theme,
) -> (
	layout: shared.UI_Layout_Component,
	input: shared.UI_Input_Component,
) {
	return shared.ui_theme_input(theme)
}

theme_panel :: proc "contextless" (
	theme: Theme,
) -> (
	layout: shared.UI_Layout_Component,
	panel: shared.UI_Panel_Component,
) {
	return shared.ui_theme_panel(theme)
}

theme_list :: proc "contextless" (theme: Theme) -> shared.UI_List_Component {
	return shared.ui_theme_list(theme)
}

theme_scroll_area :: proc "contextless" (theme: Theme) -> shared.UI_Scroll_Area_Component {
	return shared.ui_theme_scroll_area(theme)
}

theme_checkbox :: proc "contextless" (theme: Theme) -> shared.UI_Checkbox_Component {
	return shared.ui_theme_checkbox(theme)
}

theme_color_picker :: proc "contextless" (theme: Theme) -> shared.UI_Color_Picker_Component {
	return shared.ui_theme_color_picker(theme)
}
