package script

import ecs "../ecs"
import shared "../shared"
import base_runtime "base:runtime"
import c "core:c"

ui_component_name_is_mutable :: proc "contextless" (name: string) -> bool {
	return ecs.ui_component_name_is_mutable(name)
}

read_ui_component_command_from_luau :: proc "c" (
	L: Lua_State,
	world: ^shared.World,
	entity_index: int,
	name: string,
	payload_index: c.int,
	command: ^ecs.UI_Component_Command,
	base: ^ecs.UI_Component_Command = nil,
) -> string {
	context = base_runtime.default_context()
	if command == nil {
		return "UI component command is not available"
	}
	command^ = {}
	switch name {
		case "scrapbot.ui_layout":
			value := current_ui_layout(world, entity_index, base)
			if err := read_ui_uuid_field(L, payload_index, "parent", &value.parent);
			   err != "" { return err }
			if err := read_ui_vec2_field(L, payload_index, "position", &value.position);
			   err != "" { return err }
			if err := read_ui_vec2_field(L, payload_index, "size", &value.size);
			   err != "" { return err }
			if err := read_ui_vec2_field(L, payload_index, "min_size", &value.min_size);
			   err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "margin", &value.margin);
			   err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "padding", &value.padding);
			   err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "background", &value.background);
			   err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "border_color", &value.border_color);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "border_width", &value.border_width);
			   err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"corner_radius",
				&value.corner_radius,
			); err != "" { return err }
			if err := read_ui_bool_field(L, payload_index, "hidden", &value.hidden);
			   err != "" { return err }
			if err := read_ui_bool_field(L, payload_index, "fill_width", &value.fill_width);
			   err != "" { return err }
			if err := read_ui_bool_field(L, payload_index, "fill_height", &value.fill_height);
			   err != "" { return err }
			if err := read_ui_bool_field(
				L,
				payload_index,
				"fit_content_width",
				&value.fit_content_width,
			); err != "" { return err }
			if err := read_ui_bool_field(L, payload_index, "fixed_in_fill", &value.fixed_in_fill);
			   err != "" { return err }
			if err := read_ui_bool_field(
				L,
				payload_index,
				"fit_content_height",
				&value.fit_content_height,
			); err != "" { return err }
			if !shared.ui_layout_is_valid(
				value,
			) { return "ui_layout requires positive size and non-negative box metrics" }
			command.layout = value
			return ecs.init_ui_component_command(command, .Layout)
		case "scrapbot.ui_hstack", "scrapbot.ui_vstack":
			value := current_ui_stack(world, entity_index, name, base)
			if err := read_ui_number_field(L, payload_index, "gap", &value.gap);
			   err != "" { return err }
			if err := read_ui_bool_field(L, payload_index, "fill", &value.fill);
			   err != "" { return err }
			if err := read_ui_bool_field(L, payload_index, "draggable", &value.draggable);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "min_size", &value.min_size);
			   err != "" { return err }
			if !shared.ui_stack_is_valid(
				value,
			) { return "UI stack requires non-negative gap/min_size and draggable requires fill" }
			command.stack = value
			kind := ecs.UI_Component_Command_Kind.HStack
			if name == "scrapbot.ui_vstack" { kind = .VStack }
			return ecs.init_ui_component_command(command, kind)
		case "scrapbot.ui_scroll_area":
			value := current_ui_scroll_area(world, entity_index, base)
			if err := read_ui_number_field(L, payload_index, "scroll_speed", &value.scroll_speed);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "smoothness", &value.smoothness);
			   err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"scrollbar_width",
				&value.scrollbar_width,
			); err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"scrollbar_right",
				&value.scrollbar_right,
			); err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"scrollbar_vertical_inset",
				&value.scrollbar_vertical_inset,
			); err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"minimum_thumb_size",
				&value.minimum_thumb_size,
			); err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"scrollbar_corner_radius",
				&value.scrollbar_corner_radius,
			); err != "" { return err }
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"scrollbar_track_color",
				&value.scrollbar_track_color,
			); err != "" { return err }
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"scrollbar_thumb_color",
				&value.scrollbar_thumb_color,
			); err != "" { return err }
			if !shared.ui_scroll_area_is_valid(
				value,
			) { return "ui_scroll_area requires positive scroll_speed and smoothness" }
			command.scroll_area = value
			return ecs.init_ui_component_command(command, .Scroll_Area)
		case "scrapbot.ui_panel":
			value := current_ui_panel(world, entity_index, base)
			if err := read_ui_string_field(L, payload_index, "title", &value.title);
			   err != "" { return err }
			if err := read_ui_string_field(L, payload_index, "font", &value.font);
			   err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "title_color", &value.title_color);
			   err != "" { return err }
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"title_background",
				&value.title_background,
			); err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "title_size", &value.title_size);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "title_height", &value.title_height);
			   err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"disclosure_size",
				&value.disclosure_size,
			); err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"disclosure_margin",
				&value.disclosure_margin,
			); err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"disclosure_gap",
				&value.disclosure_gap,
			); err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"disclosure_corner_radius",
				&value.disclosure_corner_radius,
			); err != "" { return err }
			if err := read_ui_bool_field(L, payload_index, "collapsible", &value.collapsible);
			   err != "" { return err }
			if err := read_ui_bool_field(L, payload_index, "collapsed", &value.collapsed);
			   err != "" { return err }
			if !shared.ui_panel_is_valid(
				value,
			) { return "ui_panel title and collapse settings are invalid" }
			command.panel = value
			command.panel.title = ""
			command.panel.font = ""
			return ecs.init_ui_component_command(command, .Panel, value.title, value.font)
		case "scrapbot.ui_table":
			value := current_ui_table(world, entity_index, base)
			columns := f32(value.columns)
			if err := read_ui_number_field(L, payload_index, "columns", &columns);
			   err != "" { return err }
			value.columns = int(columns)
			if err := read_ui_number_field(L, payload_index, "column_gap", &value.column_gap);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "row_gap", &value.row_gap);
			   err != "" { return err }
			if err := read_ui_bool_field(
				L,
				payload_index,
				"proportional_columns",
				&value.proportional_columns,
			); err != "" { return err }
			if err := read_ui_bool_field(
				L,
				payload_index,
				"resizable_columns",
				&value.resizable_columns,
			); err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"min_column_width",
				&value.min_column_width,
			); err != "" { return err }
			if !shared.ui_table_is_valid(
				value,
			) { return "ui_table requires valid columns, gaps, proportions, and minimum width" }
			command.table = value
			return ecs.init_ui_component_command(command, .Table)
		case "scrapbot.ui_list":
			value := current_ui_list(world, entity_index, base)
			if err := read_ui_uuid_field(L, payload_index, "selected", &value.selected);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "gap", &value.gap);
			   err != "" { return err }
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"selection_background",
				&value.selection_background,
			); err != "" { return err }
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"hover_background",
				&value.hover_background,
			); err != "" { return err }
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"active_background",
				&value.active_background,
			); err != "" { return err }
			if !shared.ui_list_is_valid(value) { return "ui_list requires a non-negative gap" }
			command.list = value
			return ecs.init_ui_component_command(command, .List)
		case "scrapbot.ui_progress":
			value := current_ui_progress(world, entity_index, base)
			if err := read_ui_number_field(L, payload_index, "value", &value.value);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "maximum", &value.maximum);
			   err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "fill_color", &value.fill_color);
			   err != "" { return err }
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"background_color",
				&value.background_color,
			); err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "inset", &value.inset);
			   err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"corner_radius",
				&value.corner_radius,
			); err != "" { return err }
			if err := read_ui_bool_field(L, payload_index, "right_to_left", &value.right_to_left);
			   err != "" { return err }
			if !shared.ui_progress_is_valid(value) {
				return(
					"ui_progress requires a positive maximum and non-negative inset/corner radius" \
				)
			}
			command.progress = value
			return ecs.init_ui_component_command(command, .Progress)
		case "scrapbot.ui_text":
			value := current_ui_text(world, entity_index, base)
			if err := read_ui_string_field(L, payload_index, "text", &value.text);
			   err != "" { return err }
			if err := read_ui_string_field(L, payload_index, "font", &value.font);
			   err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "color", &value.color);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "size", &value.size);
			   err != "" { return err }
			alignment := ui_text_alignment_name(value.alignment)
			if err := read_ui_string_field(L, payload_index, "alignment", &alignment);
			   err != "" { return err }
			switch alignment {
				case "", "left":
					value.alignment = .Left
				case "center":
					value.alignment = .Center
				case "right":
					value.alignment = .Right
				case:
					return "ui_text.alignment must be left, center, or right"
			}
			if !shared.ui_text_is_valid(
				value,
			) { return "ui_text requires text and a positive size" }
			command.text = value
			command.text.text = ""
			command.text.font = ""
			return ecs.init_ui_component_command(command, .Text, value.text, value.font)
		case "scrapbot.ui_button":
			value := current_ui_button(world, entity_index, base)
			if err := read_ui_string_field(L, payload_index, "text", &value.text);
			   err != "" { return err }
			if err := read_ui_string_field(L, payload_index, "font", &value.font);
			   err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "color", &value.color);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "size", &value.size);
			   err != "" { return err }
			alignment := ui_text_alignment_name(value.alignment)
			if err := read_ui_string_field(L, payload_index, "alignment", &alignment);
			   err != "" { return err }
			switch alignment {
				case "", "left":
					value.alignment = .Left
				case "center":
					value.alignment = .Center
				case "right":
					value.alignment = .Right
				case:
					return "ui_button.alignment must be left, center, or right"
			}
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"hover_background",
				&value.hover_background,
			); err != "" { return err }
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"active_background",
				&value.active_background,
			); err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "hover_color", &value.hover_color);
			   err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "active_color", &value.active_color);
			   err != "" { return err }
			icon := ui_icon_name(value.icon)
			if err := read_ui_string_field(L, payload_index, "icon", &icon); err != "" {
				return err
			}
			switch icon {
				case "", "none":
					value.icon = .None
				case "close":
					value.icon = .Close
				case "plus":
					value.icon = .Plus
				case:
					return "ui_button.icon must be none, close, or plus"
			}
			if err := read_ui_number_field(L, payload_index, "icon_inset", &value.icon_inset);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "icon_stroke", &value.icon_stroke);
			   err != "" { return err }
			if err := read_ui_bool_field(L, payload_index, "panel_action", &value.panel_action);
			   err != "" { return err }
			if !shared.ui_button_is_valid(
				value,
			) { return "ui_button requires text and a positive size" }
			command.button = value
			command.button.text = ""
			command.button.font = ""
			return ecs.init_ui_component_command(command, .Button, value.text, value.font)
		case "scrapbot.ui_input":
			value := current_ui_input(world, entity_index, base)
			if err := read_ui_string_field(L, payload_index, "text", &value.text);
			   err != "" { return err }
			if err := read_ui_string_field(L, payload_index, "font", &value.font);
			   err != "" { return err }
			if err := read_ui_string_field(L, payload_index, "prefix", &value.prefix);
			   err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "color", &value.color);
			   err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "prefix_color", &value.prefix_color);
			   err != "" { return err }
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"prefix_background",
				&value.prefix_background,
			); err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "size", &value.size);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "prefix_width", &value.prefix_width);
			   err != "" { return err }
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"selection_background",
				&value.selection_background,
			); err != "" { return err }
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"focus_border_color",
				&value.focus_border_color,
			); err != "" { return err }
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"invalid_border_color",
				&value.invalid_border_color,
			); err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "caret_color", &value.caret_color);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "number", &value.number);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "step", &value.step);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "minimum", &value.minimum);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "maximum", &value.maximum);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "prefix_gap", &value.prefix_gap);
			   err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"prefix_corner_radius",
				&value.prefix_corner_radius,
			); err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"prefix_text_padding",
				&value.prefix_text_padding,
			); err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"selection_corner_radius",
				&value.selection_corner_radius,
			); err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"focus_border_width",
				&value.focus_border_width,
			); err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"invalid_border_width",
				&value.invalid_border_width,
			); err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "caret_width", &value.caret_width);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "caret_inset", &value.caret_inset);
			   err != "" { return err }
			if err := read_ui_bool_field(L, payload_index, "read_only", &value.read_only);
			   err != "" { return err }
			if err := read_ui_bool_field(L, payload_index, "numeric", &value.numeric);
			   err != "" { return err }
			if err := read_ui_bool_field(L, payload_index, "has_minimum", &value.has_minimum);
			   err != "" { return err }
			if err := read_ui_bool_field(L, payload_index, "has_maximum", &value.has_maximum);
			   err != "" { return err }
			if !shared.ui_input_is_valid(value) { return "ui_input payload is invalid" }
			command.input = value
			command.input.text = ""
			command.input.font = ""
			command.input.prefix = ""
			return ecs.init_ui_component_command(
				command,
				.Input,
				value.text,
				value.font,
				value.prefix,
			)
		case "scrapbot.ui_checkbox":
			value := current_ui_checkbox(world, entity_index, base)
			if err := read_ui_bool_field(L, payload_index, "checked", &value.checked);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "box_size", &value.box_size);
			   err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "background", &value.background);
			   err != "" { return err }
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"checked_background",
				&value.checked_background,
			); err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"corner_radius",
				&value.corner_radius,
			); err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "border_width", &value.border_width);
			   err != "" { return err }
			if err := read_ui_number_field(L, payload_index, "check_inset", &value.check_inset);
			   err != "" { return err }
			if err := read_ui_number_field(
				L,
				payload_index,
				"check_corner_radius",
				&value.check_corner_radius,
			); err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "border_color", &value.border_color);
			   err != "" { return err }
			if err := read_ui_vec4_field(L, payload_index, "check_color", &value.check_color);
			   err != "" { return err }
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"hover_background",
				&value.hover_background,
			); err != "" { return err }
			if err := read_ui_vec4_field(
				L,
				payload_index,
				"active_background",
				&value.active_background,
			); err != "" { return err }
			if err := read_ui_bool_field(L, payload_index, "read_only", &value.read_only);
			   err != "" { return err }
			if !shared.ui_checkbox_is_valid(
				value,
			) { return "ui_checkbox requires a positive box_size" }
			command.checkbox = value
			return ecs.init_ui_component_command(command, .Checkbox)
		case:
			return "unsupported UI component"
	}
	return "unsupported UI component"
}

current_ui_layout :: proc(
	world: ^shared.World,
	entity_index: int,
	base: ^ecs.UI_Component_Command,
) -> shared.UI_Layout_Component {
	if base != nil && base.kind == .Layout { return base.layout }
	if world != nil && entity_index >= 0 && entity_index < len(world.entities) {
		index := world.entities[entity_index].ui_layout_index
		if index >= 0 && index < len(world.ui_layouts) { return world.ui_layouts[index] }
	}
	return shared.ui_layout_default()
}

current_ui_stack :: proc(
	world: ^shared.World,
	entity_index: int,
	name: string,
	base: ^ecs.UI_Component_Command,
) -> shared.UI_Stack_Component {
	if base != nil && (base.kind == .HStack || base.kind == .VStack) { return base.stack }
	if world != nil && entity_index >= 0 && entity_index < len(world.entities) {
		entity := world.entities[entity_index]
		index := entity.ui_hstack_index
		storage := world.ui_hstacks[:]
		if name == "scrapbot.ui_vstack" {
			index = entity.ui_vstack_index
			storage = world.ui_vstacks[:]
		}
		if index >= 0 && index < len(storage) { return storage[index] }
	}
	return shared.ui_stack_default()
}

current_ui_scroll_area :: proc(
	world: ^shared.World,
	entity_index: int,
	base: ^ecs.UI_Component_Command,
) -> shared.UI_Scroll_Area_Component {
	if base != nil && base.kind == .Scroll_Area { return base.scroll_area }
	if world != nil && entity_index >= 0 && entity_index < len(world.entities) {
		index := world.entities[entity_index].ui_scroll_area_index
		if index >= 0 && index < len(world.ui_scroll_areas) { return world.ui_scroll_areas[index] }
	}
	return shared.ui_scroll_area_default()
}

current_ui_panel :: proc(
	world: ^shared.World,
	entity_index: int,
	base: ^ecs.UI_Component_Command,
) -> shared.UI_Panel_Component {
	if base != nil && base.kind == .Panel {
		value := base.panel
		value.title = ecs.ui_component_command_text(base)
		value.font = ecs.ui_component_command_font(base)
		return value
	}
	if world != nil && entity_index >= 0 && entity_index < len(world.entities) {
		index := world.entities[entity_index].ui_panel_index
		if index >= 0 && index < len(world.ui_panels) { return world.ui_panels[index] }
	}
	return shared.ui_panel_default()
}

current_ui_table :: proc(
	world: ^shared.World,
	entity_index: int,
	base: ^ecs.UI_Component_Command,
) -> shared.UI_Table_Component {
	if base != nil && base.kind == .Table { return base.table }
	if world != nil && entity_index >= 0 && entity_index < len(world.entities) {
		index := world.entities[entity_index].ui_table_index
		if index >= 0 && index < len(world.ui_tables) { return world.ui_tables[index] }
	}
	return shared.ui_table_default()
}

current_ui_list :: proc(
	world: ^shared.World,
	entity_index: int,
	base: ^ecs.UI_Component_Command,
) -> shared.UI_List_Component {
	if base != nil && base.kind == .List { return base.list }
	if world != nil && entity_index >= 0 && entity_index < len(world.entities) {
		index := world.entities[entity_index].ui_list_index
		if index >= 0 && index < len(world.ui_lists) { return world.ui_lists[index] }
	}
	return shared.ui_list_default()
}

current_ui_text :: proc(
	world: ^shared.World,
	entity_index: int,
	base: ^ecs.UI_Component_Command,
) -> shared.UI_Text_Component {
	if base != nil && base.kind == .Text {
		value := base.text
		value.text = ecs.ui_component_command_text(base)
		value.font = ecs.ui_component_command_font(base)
		return value
	}
	if world != nil && entity_index >= 0 && entity_index < len(world.entities) {
		index := world.entities[entity_index].ui_text_index
		if index >= 0 && index < len(world.ui_texts) { return world.ui_texts[index] }
	}
	return shared.ui_text_default()
}

current_ui_button :: proc(
	world: ^shared.World,
	entity_index: int,
	base: ^ecs.UI_Component_Command,
) -> shared.UI_Button_Component {
	if base != nil && base.kind == .Button {
		value := base.button
		value.text = ecs.ui_component_command_text(base)
		value.font = ecs.ui_component_command_font(base)
		return value
	}
	if world != nil && entity_index >= 0 && entity_index < len(world.entities) {
		index := world.entities[entity_index].ui_button_index
		if index >= 0 && index < len(world.ui_buttons) { return world.ui_buttons[index] }
	}
	return shared.ui_button_default()
}

current_ui_progress :: proc(
	world: ^shared.World,
	entity_index: int,
	base: ^ecs.UI_Component_Command,
) -> shared.UI_Progress_Component {
	if base != nil && base.kind == .Progress { return base.progress }
	if world != nil && entity_index >= 0 && entity_index < len(world.entities) {
		index := world.entities[entity_index].ui_progress_index
		if index >= 0 && index < len(world.ui_progresses) { return world.ui_progresses[index] }
	}
	return shared.ui_progress_default()
}

current_ui_input :: proc(
	world: ^shared.World,
	entity_index: int,
	base: ^ecs.UI_Component_Command,
) -> shared.UI_Input_Component {
	if base != nil && base.kind == .Input {
		value := base.input
		value.text = ecs.ui_component_command_text(base)
		value.font = ecs.ui_component_command_font(base)
		return value
	}
	if world != nil && entity_index >= 0 && entity_index < len(world.entities) {
		index := world.entities[entity_index].ui_input_index
		if index >= 0 && index < len(world.ui_inputs) { return world.ui_inputs[index] }
	}
	return shared.ui_input_default()
}

current_ui_checkbox :: proc(
	world: ^shared.World,
	entity_index: int,
	base: ^ecs.UI_Component_Command,
) -> shared.UI_Checkbox_Component {
	if base != nil && base.kind == .Checkbox { return base.checkbox }
	if world != nil && entity_index >= 0 && entity_index < len(world.entities) {
		index := world.entities[entity_index].ui_checkbox_index
		if index >= 0 && index < len(world.ui_checkboxes) { return world.ui_checkboxes[index] }
	}
	return shared.ui_checkbox_default()
}

ui_text_alignment_name :: proc "contextless" (alignment: shared.UI_Text_Alignment) -> string {
	switch alignment {
		case .Center:
			return "center"
		case .Right:
			return "right"
		case .Left:
			return "left"
	}
	return "left"
}

ui_icon_name :: proc "contextless" (icon: shared.UI_Icon) -> string {
	switch icon {
		case .Close:
			return "close"
		case .Plus:
			return "plus"
		case .None:
			return "none"
	}
	return "none"
}

read_ui_bool_field :: proc "c" (L: Lua_State, index: c.int, name: cstring, out: ^bool) -> string {
	lua_getfield(L, index, name)
	defer lua_settop(L, -2)
	if lua_type(L, -1) == LUA_TNIL { return "" }
	if lua_type(L, -1) != LUA_TBOOLEAN { return "UI boolean field must be a boolean" }
	out^ = lua_toboolean(L, -1) != 0
	return ""
}

read_ui_number_field :: proc "c" (L: Lua_State, index: c.int, name: cstring, out: ^f32) -> string {
	lua_getfield(L, index, name)
	defer lua_settop(L, -2)
	if lua_type(L, -1) == LUA_TNIL { return "" }
	is_number: c.int
	value := lua_tonumberx(L, -1, &is_number)
	if is_number == 0 { return "UI number field must be a number" }
	out^ = f32(value)
	return ""
}

read_ui_string_field :: proc "c" (
	L: Lua_State,
	index: c.int,
	name: cstring,
	out: ^string,
) -> string {
	lua_getfield(L, index, name)
	defer lua_settop(L, -2)
	if lua_type(L, -1) == LUA_TNIL { return "" }
	value, ok := luau_required_string(L, -1)
	if !ok { return "UI string field must be a string" }
	out^ = value
	return ""
}

read_ui_uuid_field :: proc "c" (
	L: Lua_State,
	index: c.int,
	name: cstring,
	out: ^shared.Entity_UUID,
) -> string {
	context = base_runtime.default_context()
	text := ""
	if err := read_ui_string_field(L, index, name, &text); err != "" { return err }
	if text == "" { return "" }
	value, ok := shared.entity_uuid_parse(text)
	if !ok { return "UI entity reference must be a UUID string" }
	out^ = value
	return ""
}

read_ui_vec2_field :: proc "c" (
	L: Lua_State,
	index: c.int,
	name: cstring,
	out: ^shared.Vec2,
) -> string {
	lua_getfield(L, index, name)
	defer lua_settop(L, -2)
	if lua_type(L, -1) == LUA_TNIL { return "" }
	if lua_type(L, -1) != LUA_TTABLE { return "UI vec2 field must be a table" }
	values := [2]^f32{&out.x, &out.y}
	names := [2]cstring{"x", "y"}
	for field_name, i in names {
		if err := read_ui_number_field(L, -1, field_name, values[i]); err != "" { return err }
	}
	return ""
}

read_ui_vec4_field :: proc "c" (
	L: Lua_State,
	index: c.int,
	name: cstring,
	out: ^shared.Vec4,
) -> string {
	lua_getfield(L, index, name)
	defer lua_settop(L, -2)
	if lua_type(L, -1) == LUA_TNIL { return "" }
	if lua_type(L, -1) != LUA_TTABLE { return "UI vec4 field must be a table" }
	values := [4]^f32{&out.x, &out.y, &out.z, &out.w}
	names := [4]cstring{"x", "y", "z", "w"}
	for field_name, i in names {
		if err := read_ui_number_field(L, -1, field_name, values[i]); err != "" { return err }
	}
	return ""
}
