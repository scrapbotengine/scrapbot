package extension

import c "core:c"
import raw "scrapbot:extension_api"

UI_LAYOUT :: "scrapbot.ui_layout"
UI_HSTACK :: "scrapbot.ui_hstack"
UI_VSTACK :: "scrapbot.ui_vstack"
UI_SCROLL_AREA :: "scrapbot.ui_scroll_area"
UI_PANEL :: "scrapbot.ui_panel"
UI_TABLE :: "scrapbot.ui_table"
UI_LIST :: "scrapbot.ui_list"
UI_PROGRESS :: "scrapbot.ui_progress"
UI_STATE :: "scrapbot.ui_state"
UI_TEXT :: "scrapbot.ui_text"
UI_BUTTON :: "scrapbot.ui_button"
UI_INPUT :: "scrapbot.ui_input"
UI_CHECKBOX :: "scrapbot.ui_checkbox"

UUID :: raw.UUID
UI_Text_Alignment :: raw.UI_Text_Alignment
UI_Layout :: raw.UI_Layout_Payload
UI_Stack :: raw.UI_Stack_Payload
UI_Scroll_Area :: raw.UI_Scroll_Area_Payload
UI_Panel :: raw.UI_Panel_Payload
UI_Table :: raw.UI_Table_Payload
UI_List :: raw.UI_List_Payload
UI_Progress :: raw.UI_Progress_Payload
UI_Text :: raw.UI_Text_Payload
UI_Button :: raw.UI_Button_Payload
UI_Icon :: raw.UI_Icon
UI_Input :: raw.UI_Input_Payload
UI_Checkbox :: raw.UI_Checkbox_Payload
UI_State :: raw.UI_State_Payload
UI_Component_Payload :: raw.UI_Component_Payload

UI_Layout_Component :: Component {
	name = UI_LAYOUT,
}
UI_HStack_Component :: Component {
	name = UI_HSTACK,
}
UI_VStack_Component :: Component {
	name = UI_VSTACK,
}
UI_Scroll_Area_Component :: Component {
	name = UI_SCROLL_AREA,
}
UI_Panel_Component :: Component {
	name = UI_PANEL,
}
UI_Table_Component :: Component {
	name = UI_TABLE,
}
UI_List_Component :: Component {
	name = UI_LIST,
}
UI_Progress_Component :: Component {
	name = UI_PROGRESS,
}
UI_State_Component :: Component {
	name = UI_STATE,
}
UI_Text_Component :: Component {
	name = UI_TEXT,
}
UI_Button_Component :: Component {
	name = UI_BUTTON,
}
UI_Input_Component :: Component {
	name = UI_INPUT,
}
UI_Checkbox_Component :: Component {
	name = UI_CHECKBOX,
}

ui_layout_default :: proc "contextless" () -> UI_Layout {
	return {}
}

ui_stack_default :: proc "contextless" () -> UI_Stack {
	return {}
}

ui_scroll_area_default :: proc "contextless" () -> UI_Scroll_Area {
	return {
		scroll_speed = 48,
		smoothness = 14,
		scrollbar_width = 3,
		scrollbar_right = 4,
		scrollbar_vertical_inset = 5,
		minimum_thumb_size = 18,
		scrollbar_corner_radius = 1.5,
		scrollbar_track_color = {0.08, 0.09, 0.11, 0.78},
		scrollbar_thumb_color = {0.34, 0.37, 0.42, 0.92},
	}
}

ui_panel_default :: proc "contextless" () -> UI_Panel {
	return {
		title_color = {1, 1, 1, 1},
		title_size = 12,
		title_height = 32,
		disclosure_size = 10,
		disclosure_margin = 10,
		disclosure_gap = 8,
		disclosure_corner_radius = 1.35,
	}
}

ui_table_default :: proc "contextless" () -> UI_Table {
	return {columns = 1, min_column_width = 32}
}

ui_list_default :: proc "contextless" () -> UI_List {
	return {
		selection_background = {0.045, 0.095, 0.105, 1},
		hover_background = {0.028, 0.038, 0.050, 1},
		active_background = {0.040, 0.055, 0.072, 1},
		drag_threshold = 5,
		drop_edge_fraction = 0.25,
		drop_target_background = {0.055, 0.12, 0.13, 1},
		drop_indicator_color = {0.42, 0.92, 0.84, 1},
		drop_indicator_thickness = 2,
		drop_indicator_inset = 8,
		tree_indent = 14,
	}
}

ui_progress_default :: proc "contextless" () -> UI_Progress {
	return {maximum = 1, fill_color = {1, 1, 1, 1}}
}

ui_text_default :: proc "contextless" () -> UI_Text {
	return {color = {1, 1, 1, 1}, size = 16}
}

ui_button_default :: proc "contextless" () -> UI_Button {
	return {
		color = {1, 1, 1, 1},
		size = 16,
		alignment = .Center,
		icon_inset = 6,
		icon_stroke = 1.5,
	}
}

ui_input_default :: proc "contextless" () -> UI_Input {
	return {
		color = {1, 1, 1, 1},
		prefix_color = {1, 1, 1, 1},
		size = 16,
		step = 1,
		prefix_gap = 3,
		prefix_corner_radius = 2,
		prefix_text_padding = 3,
		selection_corner_radius = 2,
		focus_border_width = 1,
		invalid_border_width = 1.5,
		caret_width = 1,
		caret_inset = 2,
		selection_background = {0.15, 0.45, 0.40, 0.55},
		focus_border_color = {0.15, 0.85, 0.72, 1},
		invalid_border_color = {0.92, 0.24, 0.28, 1},
	}
}

ui_checkbox_default :: proc "contextless" () -> UI_Checkbox {
	return {
		box_size = 18,
		background = {0.025, 0.030, 0.040, 1},
		checked_background = {0.08, 0.55, 0.46, 1},
		border_color = {0.24, 0.27, 0.32, 1},
		check_color = {0.95, 0.97, 0.98, 1},
		hover_background = {0.12, 0.64, 0.54, 1},
		active_background = {0.06, 0.42, 0.36, 1},
		corner_radius = -1,
		border_width = 1,
		check_inset = -1,
		check_corner_radius = -1,
	}
}

ui_layout :: proc "contextless" (value: UI_Layout) -> UI_Component_Payload {
	return {component = UI_LAYOUT, layout = value}
}

ui_hstack :: proc "contextless" (value: UI_Stack) -> UI_Component_Payload {
	return {component = UI_HSTACK, stack = value}
}

ui_vstack :: proc "contextless" (value: UI_Stack) -> UI_Component_Payload {
	return {component = UI_VSTACK, stack = value}
}

ui_scroll_area :: proc "contextless" (value: UI_Scroll_Area) -> UI_Component_Payload {
	return {component = UI_SCROLL_AREA, scroll_area = value}
}

ui_panel :: proc "contextless" (
	value: UI_Panel,
	title: string = "",
	font: string = "",
) -> (
	UI_Component_Payload,
	bool,
) {
	payload := UI_Component_Payload {
		component = UI_PANEL,
		panel = value,
	}
	return payload, ui_payload_set_strings(&payload, title, font)
}

ui_table :: proc "contextless" (value: UI_Table) -> UI_Component_Payload {
	return {component = UI_TABLE, table = value}
}

ui_list :: proc "contextless" (value: UI_List) -> UI_Component_Payload {
	return {component = UI_LIST, list = value}
}

ui_progress :: proc "contextless" (value: UI_Progress) -> UI_Component_Payload {
	return {component = UI_PROGRESS, progress = value}
}

ui_text :: proc "contextless" (
	value: UI_Text,
	text: string,
	font: string = "",
) -> (
	UI_Component_Payload,
	bool,
) {
	payload := UI_Component_Payload {
		component = UI_TEXT,
		text = value,
	}
	return payload, ui_payload_set_strings(&payload, text, font)
}

ui_button :: proc "contextless" (
	value: UI_Button,
	text: string,
	font: string = "",
) -> (
	UI_Component_Payload,
	bool,
) {
	payload := UI_Component_Payload {
		component = UI_BUTTON,
		button = value,
	}
	return payload, ui_payload_set_strings(&payload, text, font)
}

ui_input :: proc "contextless" (
	value: UI_Input,
	text: string = "",
	font: string = "",
	prefix: string = "",
) -> (
	UI_Component_Payload,
	bool,
) {
	payload := UI_Component_Payload {
		component = UI_INPUT,
		input = value,
	}
	return payload, ui_payload_set_strings(&payload, text, font, prefix)
}

ui_checkbox :: proc "contextless" (value: UI_Checkbox) -> UI_Component_Payload {
	return {component = UI_CHECKBOX, checkbox = value}
}

ui_payload_set_strings :: proc "contextless" (
	payload: ^UI_Component_Payload,
	text: string,
	font: string,
	prefix: string = "",
) -> bool {
	if payload == nil ||
	   len(text) >= len(payload.text_bytes) ||
	   len(font) >= len(payload.font_bytes) ||
	   len(prefix) >= len(payload.prefix_bytes) {
		return false
	}
	payload.text_len = c.int(len(text))
	payload.font_len = c.int(len(font))
	payload.prefix_len = c.int(len(prefix))
	for byte, index in transmute([]u8)text {
		payload.text_bytes[index] = byte
	}
	for byte, index in transmute([]u8)font {
		payload.font_bytes[index] = byte
	}
	for byte, index in transmute([]u8)prefix {
		payload.prefix_bytes[index] = byte
	}
	return true
}

ui_payload_text :: proc "contextless" (payload: ^UI_Component_Payload) -> string {
	if payload == nil || payload.text_len < 0 || int(payload.text_len) > len(payload.text_bytes) {
		return ""
	}
	return string(payload.text_bytes[:int(payload.text_len)])
}

ui_payload_font :: proc "contextless" (payload: ^UI_Component_Payload) -> string {
	if payload == nil || payload.font_len < 0 || int(payload.font_len) > len(payload.font_bytes) {
		return ""
	}
	return string(payload.font_bytes[:int(payload.font_len)])
}

ui_payload_prefix :: proc "contextless" (payload: ^UI_Component_Payload) -> string {
	if payload == nil ||
	   payload.prefix_len < 0 ||
	   int(payload.prefix_len) > len(payload.prefix_bytes) {
		return ""
	}
	return string(payload.prefix_bytes[:int(payload.prefix_len)])
}

get_ui :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	component: Component,
) -> (
	UI_Component_Payload,
	bool,
) {
	if ctx == nil || ctx.get_ui_component == nil {
		return {}, false
	}
	payload := UI_Component_Payload {
		component = component.name,
	}
	ok := ctx.get_ui_component(ctx, entity, component.name, &payload) != 0
	return payload, ok
}

set_ui :: proc "contextless" (
	ctx: ^System_Context,
	entity: Entity,
	payload: ^UI_Component_Payload,
) -> cstring {
	if ctx == nil || ctx.set_ui_component == nil {
		return "Scrapbot UI component API is not available"
	}
	return ctx.set_ui_component(ctx, entity, payload)
}

spawn_options_with_ui :: proc "contextless" (
	name: cstring,
	ui_components: []UI_Component_Payload,
	transform: ^Transform = nil,
) -> Spawn_Options {
	return {
		name = name,
		transform = transform,
		ui_components = raw_data(ui_components),
		ui_component_count = c.int(len(ui_components)),
	}
}

spawn_with_uuid :: proc "contextless" (
	ctx: ^System_Context,
	options: ^Spawn_Options,
) -> (
	UUID,
	cstring,
) {
	if ctx == nil || ctx.spawn == nil || options == nil {
		return {}, "Scrapbot spawn API is not available"
	}
	uuid: UUID
	options.out_uuid = &uuid
	err := ctx.spawn(ctx, options)
	options.out_uuid = nil
	return uuid, err
}
