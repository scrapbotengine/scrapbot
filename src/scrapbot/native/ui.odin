package native

import ecs "../ecs"
import api "../extension_api"
import shared "../shared"
import c "core:c"

system_get_ui_component :: proc "c" (
	ctx: ^api.System_Context,
	entity: api.Entity,
	component_name: cstring,
	payload: ^api.UI_Component_Payload,
) -> c.int {
	step, ok := system_step_context(ctx)
	if !ok || component_name == nil || payload == nil {
		return 0
	}
	name := string(component_name)
	if !ecs.ui_component_name_is_public(name) ||
	   !system_allows_component_access(step.system.declaration, name, .Read) {
		return 0
	}
	entity_index := int(entity.index)
	if !ecs.entity_is_current(step.world, entity_index, entity.generation) {
		return 0
	}
	world_entity := step.world.entities[entity_index]
	payload^ = {}
	payload.component = component_name
	switch name {
		case "scrapbot.ui_layout":
			if world_entity.ui_layout_index < 0 ||
			   world_entity.ui_layout_index >= len(step.world.ui_layouts) { return 0 }
			value := step.world.ui_layouts[world_entity.ui_layout_index]
			payload.layout = {
				parent = api_uuid_from_shared(value.parent),
				position = api_vec2_from_shared(value.position),
				size = api_vec2_from_shared(value.size),
				min_size = api_vec2_from_shared(value.min_size),
				margin = api_vec4_from_shared(value.margin),
				padding = api_vec4_from_shared(value.padding),
				background = api_vec4_from_shared(value.background),
				border_color = api_vec4_from_shared(value.border_color),
				border_width = value.border_width,
				corner_radius = value.corner_radius,
				hidden = bool_to_c_int(value.hidden),
				fill_width = bool_to_c_int(value.fill_width),
				fill_height = bool_to_c_int(value.fill_height),
				fit_content_width = bool_to_c_int(value.fit_content_width),
				fit_content_height = bool_to_c_int(value.fit_content_height),
				fixed_in_fill = bool_to_c_int(value.fixed_in_fill),
				tree_item = bool_to_c_int(value.tree_item),
				tree_parent = api_uuid_from_shared(value.tree_parent),
				tree_order = c.int(value.tree_order),
				tree_collapsed = bool_to_c_int(value.tree_collapsed),
			}
		case "scrapbot.ui_hstack":
			if world_entity.ui_hstack_index < 0 ||
			   world_entity.ui_hstack_index >= len(step.world.ui_hstacks) { return 0 }
			payload.stack = api_ui_stack_from_shared(
				step.world.ui_hstacks[world_entity.ui_hstack_index],
			)
		case "scrapbot.ui_vstack":
			if world_entity.ui_vstack_index < 0 ||
			   world_entity.ui_vstack_index >= len(step.world.ui_vstacks) { return 0 }
			payload.stack = api_ui_stack_from_shared(
				step.world.ui_vstacks[world_entity.ui_vstack_index],
			)
		case "scrapbot.ui_scroll_area":
			if world_entity.ui_scroll_area_index < 0 ||
			   world_entity.ui_scroll_area_index >= len(step.world.ui_scroll_areas) { return 0 }
			value := step.world.ui_scroll_areas[world_entity.ui_scroll_area_index]
			payload.scroll_area = {
				scroll_speed = value.scroll_speed,
				smoothness = value.smoothness,
				scrollbar_width = value.scrollbar_width,
				scrollbar_right = value.scrollbar_right,
				scrollbar_vertical_inset = value.scrollbar_vertical_inset,
				minimum_thumb_size = value.minimum_thumb_size,
				scrollbar_corner_radius = value.scrollbar_corner_radius,
				scrollbar_track_color = api_vec4_from_shared(value.scrollbar_track_color),
				scrollbar_thumb_color = api_vec4_from_shared(value.scrollbar_thumb_color),
			}
		case "scrapbot.ui_panel":
			if world_entity.ui_panel_index < 0 ||
			   world_entity.ui_panel_index >= len(step.world.ui_panels) { return 0 }
			value := step.world.ui_panels[world_entity.ui_panel_index]
			payload.panel = {
				title_color = api_vec4_from_shared(value.title_color),
				title_background = api_vec4_from_shared(value.title_background),
				title_size = value.title_size,
				title_height = value.title_height,
				disclosure_size = value.disclosure_size,
				disclosure_margin = value.disclosure_margin,
				disclosure_gap = value.disclosure_gap,
				disclosure_corner_radius = value.disclosure_corner_radius,
				collapsible = bool_to_c_int(value.collapsible),
				collapsed = bool_to_c_int(value.collapsed),
			}
			if !api_ui_payload_set_strings(payload, value.title, value.font) { return 0 }
		case "scrapbot.ui_table":
			if world_entity.ui_table_index < 0 ||
			   world_entity.ui_table_index >= len(step.world.ui_tables) { return 0 }
			value := step.world.ui_tables[world_entity.ui_table_index]
			payload.table = {
				columns = c.int(value.columns),
				column_gap = value.column_gap,
				row_gap = value.row_gap,
				proportional_columns = bool_to_c_int(value.proportional_columns),
				resizable_columns = bool_to_c_int(value.resizable_columns),
				min_column_width = value.min_column_width,
			}
		case "scrapbot.ui_list":
			if world_entity.ui_list_index < 0 ||
			   world_entity.ui_list_index >= len(step.world.ui_lists) { return 0 }
			value := step.world.ui_lists[world_entity.ui_list_index]
			payload.list = {
				selected = api_uuid_from_shared(value.selected),
				gap = value.gap,
				selection_background = api_vec4_from_shared(value.selection_background),
				hover_background = api_vec4_from_shared(value.hover_background),
				active_background = api_vec4_from_shared(value.active_background),
				draggable = bool_to_c_int(value.draggable),
				drag_threshold = value.drag_threshold,
				drop_edge_fraction = value.drop_edge_fraction,
				drop_target_background = api_vec4_from_shared(value.drop_target_background),
				drop_indicator_color = api_vec4_from_shared(value.drop_indicator_color),
				drop_indicator_thickness = value.drop_indicator_thickness,
				drop_indicator_inset = value.drop_indicator_inset,
				tree_enabled = bool_to_c_int(value.tree_enabled),
				tree_indent = value.tree_indent,
			}
		case "scrapbot.ui_progress":
			if world_entity.ui_progress_index < 0 ||
			   world_entity.ui_progress_index >= len(step.world.ui_progresses) { return 0 }
			value := step.world.ui_progresses[world_entity.ui_progress_index]
			payload.progress = {
				value = value.value,
				maximum = value.maximum,
				fill_color = api_vec4_from_shared(value.fill_color),
				background_color = api_vec4_from_shared(value.background_color),
				inset = api_vec4_from_shared(value.inset),
				corner_radius = value.corner_radius,
				right_to_left = bool_to_c_int(value.right_to_left),
			}
		case "scrapbot.ui_state":
			if world_entity.ui_state_index < 0 ||
			   world_entity.ui_state_index >= len(step.world.ui_states) { return 0 }
			value := step.world.ui_states[world_entity.ui_state_index]
			payload.state = {
				hovered = bool_to_c_int(value.hovered),
				active = bool_to_c_int(value.active),
				focused = bool_to_c_int(value.focused),
				activated = bool_to_c_int(value.activated),
				changed = bool_to_c_int(value.changed),
				valid = bool_to_c_int(value.valid),
				submitted = bool_to_c_int(value.submitted),
				cancelled = bool_to_c_int(value.cancelled),
				dragging = bool_to_c_int(value.dragging),
				drag_source = api_uuid_from_shared(value.drag_source),
				drop_target = api_uuid_from_shared(value.drop_target),
				drop_placement = api.UI_Drop_Placement(value.drop_placement),
				activation_revision = value.activation_revision,
				change_revision = value.change_revision,
				submit_revision = value.submit_revision,
				cancel_revision = value.cancel_revision,
				drop_revision = value.drop_revision,
			}
		case "scrapbot.ui_text":
			if world_entity.ui_text_index < 0 ||
			   world_entity.ui_text_index >= len(step.world.ui_texts) { return 0 }
			value := step.world.ui_texts[world_entity.ui_text_index]
			payload.text = {
				color = api_vec4_from_shared(value.color),
				size = value.size,
				alignment = api_text_alignment_from_shared(value.alignment),
			}
			if !api_ui_payload_set_strings(payload, value.text, value.font) { return 0 }
		case "scrapbot.ui_button":
			if world_entity.ui_button_index < 0 ||
			   world_entity.ui_button_index >= len(step.world.ui_buttons) { return 0 }
			value := step.world.ui_buttons[world_entity.ui_button_index]
			payload.button = {
				color = api_vec4_from_shared(value.color),
				size = value.size,
				alignment = api_text_alignment_from_shared(value.alignment),
				hover_background = api_vec4_from_shared(value.hover_background),
				active_background = api_vec4_from_shared(value.active_background),
				hover_color = api_vec4_from_shared(value.hover_color),
				active_color = api_vec4_from_shared(value.active_color),
				icon = api_icon_from_shared(value.icon),
				icon_inset = value.icon_inset,
				icon_stroke = value.icon_stroke,
				panel_action = bool_to_c_int(value.panel_action),
			}
			if !api_ui_payload_set_strings(payload, value.text, value.font) { return 0 }
		case "scrapbot.ui_input":
			if world_entity.ui_input_index < 0 ||
			   world_entity.ui_input_index >= len(step.world.ui_inputs) { return 0 }
			value := step.world.ui_inputs[world_entity.ui_input_index]
			payload.input = {
				color = api_vec4_from_shared(value.color),
				prefix_color = api_vec4_from_shared(value.prefix_color),
				prefix_background = api_vec4_from_shared(value.prefix_background),
				size = value.size,
				prefix_width = value.prefix_width,
				selection_background = api_vec4_from_shared(value.selection_background),
				focus_border_color = api_vec4_from_shared(value.focus_border_color),
				invalid_border_color = api_vec4_from_shared(value.invalid_border_color),
				caret_color = api_vec4_from_shared(value.caret_color),
				number = value.number,
				step = value.step,
				minimum = value.minimum,
				maximum = value.maximum,
				prefix_gap = value.prefix_gap,
				prefix_corner_radius = value.prefix_corner_radius,
				prefix_text_padding = value.prefix_text_padding,
				selection_corner_radius = value.selection_corner_radius,
				focus_border_width = value.focus_border_width,
				invalid_border_width = value.invalid_border_width,
				caret_width = value.caret_width,
				caret_inset = value.caret_inset,
				read_only = bool_to_c_int(value.read_only),
				numeric = bool_to_c_int(value.numeric),
				has_minimum = bool_to_c_int(value.has_minimum),
				has_maximum = bool_to_c_int(value.has_maximum),
			}
			if !api_ui_payload_set_strings(
				payload,
				value.text,
				value.font,
				value.prefix,
			) { return 0 }
		case "scrapbot.ui_checkbox":
			if world_entity.ui_checkbox_index < 0 ||
			   world_entity.ui_checkbox_index >= len(step.world.ui_checkboxes) { return 0 }
			value := step.world.ui_checkboxes[world_entity.ui_checkbox_index]
			payload.checkbox = {
				checked = bool_to_c_int(value.checked),
				box_size = value.box_size,
				background = api_vec4_from_shared(value.background),
				checked_background = api_vec4_from_shared(value.checked_background),
				border_color = api_vec4_from_shared(value.border_color),
				check_color = api_vec4_from_shared(value.check_color),
				hover_background = api_vec4_from_shared(value.hover_background),
				active_background = api_vec4_from_shared(value.active_background),
				corner_radius = value.corner_radius,
				border_width = value.border_width,
				check_inset = value.check_inset,
				check_corner_radius = value.check_corner_radius,
				read_only = bool_to_c_int(value.read_only),
			}
		case:
			return 0
	}
	return 1
}

system_set_ui_component :: proc "c" (
	ctx: ^api.System_Context,
	entity: api.Entity,
	payload: ^api.UI_Component_Payload,
) -> cstring {
	step, ok := system_step_context(ctx)
	if !ok || step.commands == nil {
		return "native command buffer is not available"
	}
	if payload == nil || payload.component == nil {
		return "native UI component payload is not available"
	}
	name := string(payload.component)
	if !ecs.ui_component_name_is_mutable(name) {
		return "native UI component is not mutable"
	}
	if !system_allows_component_access(step.system.declaration, name, .Write) {
		return "native system does not have write access to UI component"
	}
	entity_index := int(entity.index)
	if !ecs.entity_is_current(step.world, entity_index, entity.generation) {
		return "native UI component entity is stale"
	}
	command: ecs.UI_Component_Command
	if err := ui_command_from_api_payload(payload, &command); err != "" {
		return cstring(raw_data(err))
	}
	if err := ecs.queue_add_ui_component(step.commands, entity_index, entity.generation, command);
	   err != "" {
		return cstring(raw_data(err))
	}
	return nil
}

ui_command_from_api_payload :: proc "c" (
	payload: ^api.UI_Component_Payload,
	command: ^ecs.UI_Component_Command,
) -> string {
	if payload == nil || payload.component == nil || command == nil {
		return "native UI component payload is not available"
	}
	text, font, strings_ok := api_ui_payload_strings(payload)
	if !strings_ok {
		return "native UI component string length is invalid"
	}
	prefix, prefix_ok := api_ui_payload_prefix(payload)
	if !prefix_ok {
		return "native UI input prefix length is invalid"
	}
	name := string(payload.component)
	command^ = {}
	switch name {
		case "scrapbot.ui_layout":
			value := shared.UI_Layout_Component {
				parent = shared_uuid_from_api(payload.layout.parent),
				position = shared_vec2_from_api(payload.layout.position),
				size = shared_vec2_from_api(payload.layout.size),
				min_size = shared_vec2_from_api(payload.layout.min_size),
				margin = shared_vec4_from_api(payload.layout.margin),
				padding = shared_vec4_from_api(payload.layout.padding),
				background = shared_vec4_from_api(payload.layout.background),
				border_color = shared_vec4_from_api(payload.layout.border_color),
				border_width = payload.layout.border_width,
				corner_radius = payload.layout.corner_radius,
				hidden = payload.layout.hidden != 0,
				fill_width = payload.layout.fill_width != 0,
				fill_height = payload.layout.fill_height != 0,
				fit_content_width = payload.layout.fit_content_width != 0,
				fit_content_height = payload.layout.fit_content_height != 0,
				fixed_in_fill = payload.layout.fixed_in_fill != 0,
				tree_item = payload.layout.tree_item != 0,
				tree_parent = shared_uuid_from_api(payload.layout.tree_parent),
				tree_order = int(payload.layout.tree_order),
				tree_collapsed = payload.layout.tree_collapsed != 0,
			}
			if !shared.ui_layout_is_valid(value) {
				return "native ui_layout payload is invalid"
			}
			command.layout = value
			return ecs.init_ui_component_command(command, .Layout)
		case "scrapbot.ui_hstack", "scrapbot.ui_vstack":
			value := shared.UI_Stack_Component {
				gap = payload.stack.gap,
				fill = payload.stack.fill != 0,
				draggable = payload.stack.draggable != 0,
				min_size = payload.stack.min_size,
			}
			if !shared.ui_stack_is_valid(value) {
				return "native UI stack payload is invalid"
			}
			command.stack = value
			kind := ecs.UI_Component_Command_Kind.HStack
			if name == "scrapbot.ui_vstack" { kind = .VStack }
			return ecs.init_ui_component_command(command, kind)
		case "scrapbot.ui_scroll_area":
			value := shared.UI_Scroll_Area_Component {
				scroll_speed = payload.scroll_area.scroll_speed,
				smoothness = payload.scroll_area.smoothness,
				scrollbar_width = payload.scroll_area.scrollbar_width,
				scrollbar_right = payload.scroll_area.scrollbar_right,
				scrollbar_vertical_inset = payload.scroll_area.scrollbar_vertical_inset,
				minimum_thumb_size = payload.scroll_area.minimum_thumb_size,
				scrollbar_corner_radius = payload.scroll_area.scrollbar_corner_radius,
				scrollbar_track_color = shared_vec4_from_api(
					payload.scroll_area.scrollbar_track_color,
				),
				scrollbar_thumb_color = shared_vec4_from_api(
					payload.scroll_area.scrollbar_thumb_color,
				),
			}
			if !shared.ui_scroll_area_is_valid(value) {
				return "native ui_scroll_area payload is invalid"
			}
			command.scroll_area = value
			return ecs.init_ui_component_command(command, .Scroll_Area)
		case "scrapbot.ui_panel":
			value := shared.UI_Panel_Component {
				title = text,
				font = font,
				title_color = shared_vec4_from_api(payload.panel.title_color),
				title_background = shared_vec4_from_api(payload.panel.title_background),
				title_size = payload.panel.title_size,
				title_height = payload.panel.title_height,
				disclosure_size = payload.panel.disclosure_size,
				disclosure_margin = payload.panel.disclosure_margin,
				disclosure_gap = payload.panel.disclosure_gap,
				disclosure_corner_radius = payload.panel.disclosure_corner_radius,
				collapsible = payload.panel.collapsible != 0,
				collapsed = payload.panel.collapsed != 0,
			}
			if !shared.ui_panel_is_valid(value) {
				return "native ui_panel payload is invalid"
			}
			command.panel = value
			command.panel.title = ""
			command.panel.font = ""
			return ecs.init_ui_component_command(command, .Panel, text, font)
		case "scrapbot.ui_table":
			value := shared.UI_Table_Component {
				columns = int(payload.table.columns),
				column_gap = payload.table.column_gap,
				row_gap = payload.table.row_gap,
				proportional_columns = payload.table.proportional_columns != 0,
				resizable_columns = payload.table.resizable_columns != 0,
				min_column_width = payload.table.min_column_width,
			}
			if !shared.ui_table_is_valid(value) {
				return "native ui_table payload is invalid"
			}
			command.table = value
			return ecs.init_ui_component_command(command, .Table)
		case "scrapbot.ui_list":
			value := shared.UI_List_Component {
				selected = shared_uuid_from_api(payload.list.selected),
				gap = payload.list.gap,
				selection_background = shared_vec4_from_api(payload.list.selection_background),
				hover_background = shared_vec4_from_api(payload.list.hover_background),
				active_background = shared_vec4_from_api(payload.list.active_background),
				draggable = payload.list.draggable != 0,
				drag_threshold = payload.list.drag_threshold,
				drop_edge_fraction = payload.list.drop_edge_fraction,
				drop_target_background = shared_vec4_from_api(payload.list.drop_target_background),
				drop_indicator_color = shared_vec4_from_api(payload.list.drop_indicator_color),
				drop_indicator_thickness = payload.list.drop_indicator_thickness,
				drop_indicator_inset = payload.list.drop_indicator_inset,
				tree_enabled = payload.list.tree_enabled != 0,
				tree_indent = payload.list.tree_indent,
			}
			if !shared.ui_list_is_valid(value) {
				return "native ui_list payload is invalid"
			}
			command.list = value
			return ecs.init_ui_component_command(command, .List)
		case "scrapbot.ui_progress":
			value := shared.UI_Progress_Component {
				value = payload.progress.value,
				maximum = payload.progress.maximum,
				fill_color = shared_vec4_from_api(payload.progress.fill_color),
				background_color = shared_vec4_from_api(payload.progress.background_color),
				inset = shared_vec4_from_api(payload.progress.inset),
				corner_radius = payload.progress.corner_radius,
				right_to_left = payload.progress.right_to_left != 0,
			}
			if !shared.ui_progress_is_valid(value) {
				return "native ui_progress payload is invalid"
			}
			command.progress = value
			return ecs.init_ui_component_command(command, .Progress)
		case "scrapbot.ui_text":
			alignment, alignment_ok := shared_text_alignment_from_api(payload.text.alignment)
			if !alignment_ok { return "native ui_text alignment is invalid" }
			value := shared.UI_Text_Component {
				text = text,
				font = font,
				color = shared_vec4_from_api(payload.text.color),
				size = payload.text.size,
				alignment = alignment,
			}
			if !shared.ui_text_is_valid(value) { return "native ui_text payload is invalid" }
			command.text = value
			command.text.text = ""
			command.text.font = ""
			return ecs.init_ui_component_command(command, .Text, text, font)
		case "scrapbot.ui_button":
			alignment, alignment_ok := shared_text_alignment_from_api(payload.button.alignment)
			if !alignment_ok { return "native ui_button alignment is invalid" }
			value := shared.UI_Button_Component {
				text = text,
				font = font,
				color = shared_vec4_from_api(payload.button.color),
				size = payload.button.size,
				alignment = alignment,
				hover_background = shared_vec4_from_api(payload.button.hover_background),
				active_background = shared_vec4_from_api(payload.button.active_background),
				hover_color = shared_vec4_from_api(payload.button.hover_color),
				active_color = shared_vec4_from_api(payload.button.active_color),
				icon = shared_icon_from_api(payload.button.icon),
				icon_inset = payload.button.icon_inset,
				icon_stroke = payload.button.icon_stroke,
				panel_action = payload.button.panel_action != 0,
			}
			if !shared.ui_button_is_valid(value) { return "native ui_button payload is invalid" }
			command.button = value
			command.button.text = ""
			command.button.font = ""
			return ecs.init_ui_component_command(command, .Button, text, font)
		case "scrapbot.ui_input":
			value := shared.UI_Input_Component {
				text = text,
				font = font,
				prefix = prefix,
				color = shared_vec4_from_api(payload.input.color),
				prefix_color = shared_vec4_from_api(payload.input.prefix_color),
				prefix_background = shared_vec4_from_api(payload.input.prefix_background),
				size = payload.input.size,
				prefix_width = payload.input.prefix_width,
				selection_background = shared_vec4_from_api(payload.input.selection_background),
				focus_border_color = shared_vec4_from_api(payload.input.focus_border_color),
				invalid_border_color = shared_vec4_from_api(payload.input.invalid_border_color),
				caret_color = shared_vec4_from_api(payload.input.caret_color),
				number = payload.input.number,
				step = payload.input.step,
				minimum = payload.input.minimum,
				maximum = payload.input.maximum,
				prefix_gap = payload.input.prefix_gap,
				prefix_corner_radius = payload.input.prefix_corner_radius,
				prefix_text_padding = payload.input.prefix_text_padding,
				selection_corner_radius = payload.input.selection_corner_radius,
				focus_border_width = payload.input.focus_border_width,
				invalid_border_width = payload.input.invalid_border_width,
				caret_width = payload.input.caret_width,
				caret_inset = payload.input.caret_inset,
				read_only = payload.input.read_only != 0,
				numeric = payload.input.numeric != 0,
				has_minimum = payload.input.has_minimum != 0,
				has_maximum = payload.input.has_maximum != 0,
			}
			if !shared.ui_input_is_valid(value) { return "native ui_input payload is invalid" }
			command.input = value
			command.input.text = ""
			command.input.font = ""
			command.input.prefix = ""
			return ecs.init_ui_component_command(command, .Input, text, font, prefix)
		case "scrapbot.ui_checkbox":
			value := shared.UI_Checkbox_Component {
				checked = payload.checkbox.checked != 0,
				box_size = payload.checkbox.box_size,
				background = shared_vec4_from_api(payload.checkbox.background),
				checked_background = shared_vec4_from_api(payload.checkbox.checked_background),
				border_color = shared_vec4_from_api(payload.checkbox.border_color),
				check_color = shared_vec4_from_api(payload.checkbox.check_color),
				hover_background = shared_vec4_from_api(payload.checkbox.hover_background),
				active_background = shared_vec4_from_api(payload.checkbox.active_background),
				corner_radius = payload.checkbox.corner_radius,
				border_width = payload.checkbox.border_width,
				check_inset = payload.checkbox.check_inset,
				check_corner_radius = payload.checkbox.check_corner_radius,
				read_only = payload.checkbox.read_only != 0,
			}
			if !shared.ui_checkbox_is_valid(value) {
				return "native ui_checkbox payload is invalid"
			}
			command.checkbox = value
			return ecs.init_ui_component_command(command, .Checkbox)
	}
	return "native UI component is not supported"
}

api_ui_stack_from_shared :: proc "contextless" (
	value: shared.UI_Stack_Component,
) -> api.UI_Stack_Payload {
	return {
		gap = value.gap,
		fill = bool_to_c_int(value.fill),
		draggable = bool_to_c_int(value.draggable),
		min_size = value.min_size,
	}
}

api_ui_payload_set_strings :: proc "contextless" (
	payload: ^api.UI_Component_Payload,
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
	for byte, index in transmute([]u8)text { payload.text_bytes[index] = byte }
	for byte, index in transmute([]u8)font { payload.font_bytes[index] = byte }
	for byte, index in transmute([]u8)prefix { payload.prefix_bytes[index] = byte }
	return true
}

api_ui_payload_prefix :: proc "contextless" (
	payload: ^api.UI_Component_Payload,
) -> (
	prefix: string,
	ok: bool,
) {
	if payload == nil ||
	   payload.prefix_len < 0 ||
	   int(payload.prefix_len) >= len(payload.prefix_bytes) {
		return "", false
	}
	return string(payload.prefix_bytes[:int(payload.prefix_len)]), true
}

api_ui_payload_strings :: proc "contextless" (
	payload: ^api.UI_Component_Payload,
) -> (
	text, font: string,
	ok: bool,
) {
	if payload == nil ||
	   payload.text_len < 0 ||
	   int(payload.text_len) >= len(payload.text_bytes) ||
	   payload.font_len < 0 ||
	   int(payload.font_len) >= len(payload.font_bytes) {
		return "", "", false
	}
	return string(payload.text_bytes[:int(payload.text_len)]),
		string(payload.font_bytes[:int(payload.font_len)]),
		true
}

bool_to_c_int :: proc "contextless" (value: bool) -> c.int {
	return 1 if value else 0
}

api_vec2_from_shared :: proc "contextless" (value: shared.Vec2) -> api.Vec2 {
	return {value.x, value.y}
}

shared_vec2_from_api :: proc "contextless" (value: api.Vec2) -> shared.Vec2 {
	return {value.x, value.y}
}

api_vec4_from_shared :: proc "contextless" (value: shared.Vec4) -> api.Vec4 {
	return {value.x, value.y, value.z, value.w}
}

shared_vec4_from_api :: proc "contextless" (value: api.Vec4) -> shared.Vec4 {
	return {value.x, value.y, value.z, value.w}
}

api_uuid_from_shared :: proc "contextless" (value: shared.Entity_UUID) -> api.UUID {
	result: api.UUID
	for byte, index in value { result.bytes[index] = byte }
	return result
}

shared_uuid_from_api :: proc "contextless" (value: api.UUID) -> shared.Entity_UUID {
	result: shared.Entity_UUID
	for byte, index in value.bytes { result[index] = byte }
	return result
}

api_text_alignment_from_shared :: proc "contextless" (
	value: shared.UI_Text_Alignment,
) -> api.UI_Text_Alignment {
	switch value {
		case .Left:
			return .Left
		case .Center:
			return .Center
		case .Right:
			return .Right
	}
	return .Left
}

api_icon_from_shared :: proc "contextless" (value: shared.UI_Icon) -> api.UI_Icon {
	switch value {
		case .Close:
			return .Close
		case .Plus:
			return .Plus
		case .Chevron_Right:
			return .Chevron_Right
		case .Chevron_Down:
			return .Chevron_Down
		case .None:
			return .None
	}
	return .None
}

shared_icon_from_api :: proc "contextless" (value: api.UI_Icon) -> shared.UI_Icon {
	switch value {
		case .Close:
			return .Close
		case .Plus:
			return .Plus
		case .Chevron_Right:
			return .Chevron_Right
		case .Chevron_Down:
			return .Chevron_Down
		case .None:
			return .None
	}
	return .None
}

shared_text_alignment_from_api :: proc "contextless" (
	value: api.UI_Text_Alignment,
) -> (
	shared.UI_Text_Alignment,
	bool,
) {
	#partial switch value {
		case .Left:
			return .Left, true
		case .Center:
			return .Center, true
		case .Right:
			return .Right, true
	}
	return .Left, false
}
