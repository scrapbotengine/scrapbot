package ecs

import shared "../shared"

ui_component_name_is_mutable :: proc "contextless" (name: string) -> bool {
	return ui_component_command_kind(name) != .None
}

ui_component_name_is_public :: proc "contextless" (name: string) -> bool {
	return ui_component_name_is_mutable(name) || name == "scrapbot.ui_state"
}

ui_entity_is_mutable :: proc(world: ^World, entity_index: int) -> bool {
	return(
		world != nil &&
		entity_index >= 0 &&
		entity_index < len(world.entities) &&
		world.entities[entity_index].alive \
	)
}

ensure_ui_state :: proc(world: ^World, entity_index: int) -> ^UI_State_Component {
	if !ui_entity_is_mutable(world, entity_index) {
		return nil
	}
	entity := &world.entities[entity_index]
	if entity.ui_state_index < 0 || entity.ui_state_index >= len(world.ui_states) {
		if index, found := take_free_slot(&world.free_ui_state_indices); found {
			entity.ui_state_index = index
			world.ui_states[index] = {
				valid = true,
			}
		} else {
			entity.ui_state_index = len(world.ui_states)
			append(&world.ui_states, UI_State_Component{valid = true})
		}
		bump_component_revision(world, entity_index)
	}
	return &world.ui_states[entity.ui_state_index]
}

mark_ui_submitted :: proc(world: ^World, entity_index: int) -> bool {
	state := ensure_ui_state(world, entity_index)
	if state == nil {
		return false
	}
	state.submitted = true
	state.submit_revision += 1
	return true
}

mark_ui_cancelled :: proc(world: ^World, entity_index: int) -> bool {
	state := ensure_ui_state(world, entity_index)
	if state == nil {
		return false
	}
	state.cancelled = true
	state.cancel_revision += 1
	return true
}

mark_ui_activated :: proc(world: ^World, entity_index: int) -> bool {
	state := ensure_ui_state(world, entity_index)
	if state == nil {
		return false
	}
	state.activated = true
	state.activation_revision += 1
	return true
}

mark_ui_changed :: proc(world: ^World, entity_index: int) -> bool {
	state := ensure_ui_state(world, entity_index)
	if state == nil {
		return false
	}
	state.changed = true
	state.change_revision += 1
	return true
}

remove_ui_component :: proc(world: ^World, entity_index: int, name: string) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	entity := &world.entities[entity_index]
	switch name {
		case "scrapbot.ui_layout":
			if entity.ui_layout_index < 0 { return false }
			mark_ui_subtree_dirty(world, entity_index)
			world.ui_layouts[entity.ui_layout_index] = {}
			append(&world.free_ui_layout_indices, entity.ui_layout_index)
			entity.ui_layout_index = INVALID_COMPONENT_INDEX
		case "scrapbot.ui_hstack":
			if entity.ui_hstack_index < 0 { return false }
			world.ui_hstacks[entity.ui_hstack_index] = {}
			append(&world.free_ui_hstack_indices, entity.ui_hstack_index)
			entity.ui_hstack_index = INVALID_COMPONENT_INDEX
		case "scrapbot.ui_vstack":
			if entity.ui_vstack_index < 0 { return false }
			world.ui_vstacks[entity.ui_vstack_index] = {}
			append(&world.free_ui_vstack_indices, entity.ui_vstack_index)
			entity.ui_vstack_index = INVALID_COMPONENT_INDEX
		case "scrapbot.ui_scroll_area":
			if entity.ui_scroll_area_index < 0 { return false }
			world.ui_scroll_areas[entity.ui_scroll_area_index] = {}
			append(&world.free_ui_scroll_area_indices, entity.ui_scroll_area_index)
			entity.ui_scroll_area_index = INVALID_COMPONENT_INDEX
		case "scrapbot.ui_panel":
			if entity.ui_panel_index < 0 { return false }
			panel := &world.ui_panels[entity.ui_panel_index]
			delete_world_string(world, panel.title)
			delete_world_string(world, panel.font)
			panel^ = {}
			append(&world.free_ui_panel_indices, entity.ui_panel_index)
			entity.ui_panel_index = INVALID_COMPONENT_INDEX
		case "scrapbot.ui_table":
			if entity.ui_table_index < 0 { return false }
			world.ui_tables[entity.ui_table_index] = {}
			append(&world.free_ui_table_indices, entity.ui_table_index)
			entity.ui_table_index = INVALID_COMPONENT_INDEX
		case "scrapbot.ui_list":
			if entity.ui_list_index < 0 { return false }
			world.ui_lists[entity.ui_list_index] = {}
			append(&world.free_ui_list_indices, entity.ui_list_index)
			entity.ui_list_index = INVALID_COMPONENT_INDEX
		case "scrapbot.ui_progress":
			if entity.ui_progress_index < 0 { return false }
			world.ui_progresses[entity.ui_progress_index] = {}
			append(&world.free_ui_progress_indices, entity.ui_progress_index)
			entity.ui_progress_index = INVALID_COMPONENT_INDEX
		case "scrapbot.ui_text":
			if entity.ui_text_index < 0 { return false }
			text := &world.ui_texts[entity.ui_text_index]
			delete_world_string(world, text.text)
			delete_world_string(world, text.font)
			text^ = {}
			append(&world.free_ui_text_indices, entity.ui_text_index)
			entity.ui_text_index = INVALID_COMPONENT_INDEX
		case "scrapbot.ui_button":
			if entity.ui_button_index < 0 { return false }
			button := &world.ui_buttons[entity.ui_button_index]
			delete_world_string(world, button.text)
			delete_world_string(world, button.font)
			button^ = {}
			append(&world.free_ui_button_indices, entity.ui_button_index)
			entity.ui_button_index = INVALID_COMPONENT_INDEX
		case "scrapbot.ui_input":
			if entity.ui_input_index < 0 { return false }
			input := &world.ui_inputs[entity.ui_input_index]
			delete_world_string(world, input.text)
			delete_world_string(world, input.font)
			delete_world_string(world, input.prefix)
			input^ = {}
			append(&world.free_ui_input_indices, entity.ui_input_index)
			entity.ui_input_index = INVALID_COMPONENT_INDEX
		case "scrapbot.ui_checkbox":
			if entity.ui_checkbox_index < 0 { return false }
			world.ui_checkboxes[entity.ui_checkbox_index] = {}
			append(&world.free_ui_checkbox_indices, entity.ui_checkbox_index)
			entity.ui_checkbox_index = INVALID_COMPONENT_INDEX
		case:
			return false
	}
	if name != "scrapbot.ui_layout" {
		mark_ui_entity_dirty(world, entity_index)
	}
	bump_component_revision(world, entity_index)
	return true
}

release_ui_state :: proc(world: ^World, entity_index: int) {
	if !ui_entity_is_mutable(world, entity_index) {
		return
	}
	entity := &world.entities[entity_index]
	if entity.ui_state_index < 0 || entity.ui_state_index >= len(world.ui_states) {
		return
	}
	world.ui_states[entity.ui_state_index] = {}
	append(&world.free_ui_state_indices, entity.ui_state_index)
	entity.ui_state_index = INVALID_COMPONENT_INDEX
}

set_ui_layout :: proc(world: ^World, entity_index: int, value: UI_Layout_Component) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	entity := &world.entities[entity_index]
	if entity.ui_layout_index >= 0 && entity.ui_layout_index < len(world.ui_layouts) {
		current := &world.ui_layouts[entity.ui_layout_index]
		hierarchy_changed := current.parent != value.parent || current.hidden != value.hidden
		layout_changed := current^ != value
		current^ = value
		if hierarchy_changed {
			mark_ui_subtree_dirty(world, entity_index)
		} else if layout_changed {
			mark_ui_layout_changed(world, entity_index)
		}
		return true
	}
	if index, found := take_free_slot(&world.free_ui_layout_indices); found {
		entity.ui_layout_index = index
		world.ui_layouts[index] = value
	} else {
		entity.ui_layout_index = len(world.ui_layouts)
		append(&world.ui_layouts, value)
	}
	mark_ui_entity_dirty(world, entity_index)
	return true
}

set_ui_hstack :: proc(world: ^World, entity_index: int, value: UI_Stack_Component) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	entity := &world.entities[entity_index]
	if entity.ui_hstack_index >= 0 && entity.ui_hstack_index < len(world.ui_hstacks) {
		if world.ui_hstacks[entity.ui_hstack_index] != value {
			mark_ui_layout_changed(world, entity_index)
		}
		world.ui_hstacks[entity.ui_hstack_index] = value
		return true
	}
	if index, found := take_free_slot(&world.free_ui_hstack_indices); found {
		entity.ui_hstack_index = index
		world.ui_hstacks[index] = value
	} else {
		entity.ui_hstack_index = len(world.ui_hstacks)
		append(&world.ui_hstacks, value)
	}
	mark_ui_entity_dirty(world, entity_index)
	return true
}

set_ui_vstack :: proc(world: ^World, entity_index: int, value: UI_Stack_Component) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	entity := &world.entities[entity_index]
	if entity.ui_vstack_index >= 0 && entity.ui_vstack_index < len(world.ui_vstacks) {
		if world.ui_vstacks[entity.ui_vstack_index] != value {
			mark_ui_layout_changed(world, entity_index)
		}
		world.ui_vstacks[entity.ui_vstack_index] = value
		return true
	}
	if index, found := take_free_slot(&world.free_ui_vstack_indices); found {
		entity.ui_vstack_index = index
		world.ui_vstacks[index] = value
	} else {
		entity.ui_vstack_index = len(world.ui_vstacks)
		append(&world.ui_vstacks, value)
	}
	mark_ui_entity_dirty(world, entity_index)
	return true
}

set_ui_scroll_area :: proc(
	world: ^World,
	entity_index: int,
	value: UI_Scroll_Area_Component,
) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	entity := &world.entities[entity_index]
	if entity.ui_scroll_area_index >= 0 &&
	   entity.ui_scroll_area_index < len(world.ui_scroll_areas) {
		world.ui_scroll_areas[entity.ui_scroll_area_index] = value
		return true
	}
	if index, found := take_free_slot(&world.free_ui_scroll_area_indices); found {
		entity.ui_scroll_area_index = index
		world.ui_scroll_areas[index] = value
	} else {
		entity.ui_scroll_area_index = len(world.ui_scroll_areas)
		append(&world.ui_scroll_areas, value)
	}
	mark_ui_entity_dirty(world, entity_index)
	return true
}

set_ui_panel :: proc(world: ^World, entity_index: int, value: UI_Panel_Component) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	panel := value
	panel.title = clone_world_string(world, value.title)
	panel.font = clone_world_string(world, value.font)
	entity := &world.entities[entity_index]
	if entity.ui_panel_index >= 0 && entity.ui_panel_index < len(world.ui_panels) {
		current := &world.ui_panels[entity.ui_panel_index]
		layout_changed :=
			current.title != value.title ||
			current.font != value.font ||
			current.title_size != value.title_size ||
			current.title_height != value.title_height ||
			current.disclosure_size != value.disclosure_size ||
			current.disclosure_margin != value.disclosure_margin ||
			current.disclosure_gap != value.disclosure_gap ||
			current.collapsible != value.collapsible ||
			current.collapsed != value.collapsed
		delete_world_string(world, current.title)
		delete_world_string(world, current.font)
		current^ = panel
		if layout_changed {
			mark_ui_layout_changed(world, entity_index)
		}
		return true
	}
	if index, found := take_free_slot(&world.free_ui_panel_indices); found {
		entity.ui_panel_index = index
		world.ui_panels[index] = panel
	} else {
		entity.ui_panel_index = len(world.ui_panels)
		append(&world.ui_panels, panel)
	}
	mark_ui_entity_dirty(world, entity_index)
	return true
}

set_ui_table :: proc(world: ^World, entity_index: int, value: UI_Table_Component) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	entity := &world.entities[entity_index]
	if entity.ui_table_index >= 0 && entity.ui_table_index < len(world.ui_tables) {
		if world.ui_tables[entity.ui_table_index] != value {
			mark_ui_layout_changed(world, entity_index)
		}
		world.ui_tables[entity.ui_table_index] = value
		return true
	}
	if index, found := take_free_slot(&world.free_ui_table_indices); found {
		entity.ui_table_index = index
		world.ui_tables[index] = value
	} else {
		entity.ui_table_index = len(world.ui_tables)
		append(&world.ui_tables, value)
	}
	mark_ui_entity_dirty(world, entity_index)
	return true
}

set_ui_list :: proc(world: ^World, entity_index: int, value: UI_List_Component) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	entity := &world.entities[entity_index]
	if entity.ui_list_index >= 0 && entity.ui_list_index < len(world.ui_lists) {
		if world.ui_lists[entity.ui_list_index].gap != value.gap {
			mark_ui_layout_changed(world, entity_index)
		}
		world.ui_lists[entity.ui_list_index] = value
		return true
	}
	if index, found := take_free_slot(&world.free_ui_list_indices); found {
		entity.ui_list_index = index
		world.ui_lists[index] = value
	} else {
		entity.ui_list_index = len(world.ui_lists)
		append(&world.ui_lists, value)
	}
	mark_ui_entity_dirty(world, entity_index)
	return true
}

set_ui_progress :: proc(world: ^World, entity_index: int, value: UI_Progress_Component) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	entity := &world.entities[entity_index]
	if entity.ui_progress_index >= 0 && entity.ui_progress_index < len(world.ui_progresses) {
		world.ui_progresses[entity.ui_progress_index] = value
		return true
	}
	if index, found := take_free_slot(&world.free_ui_progress_indices); found {
		entity.ui_progress_index = index
		world.ui_progresses[index] = value
	} else {
		entity.ui_progress_index = len(world.ui_progresses)
		append(&world.ui_progresses, value)
	}
	mark_ui_entity_dirty(world, entity_index)
	return true
}

set_ui_text :: proc(world: ^World, entity_index: int, value: UI_Text_Component) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	text := value
	text.text = clone_world_string(world, value.text)
	text.font = clone_world_string(world, value.font)
	entity := &world.entities[entity_index]
	if entity.ui_text_index >= 0 && entity.ui_text_index < len(world.ui_texts) {
		current := &world.ui_texts[entity.ui_text_index]
		intrinsic_changed :=
			current.text != value.text ||
			current.font != value.font ||
			current.size != value.size ||
			current.alignment != value.alignment
		delete_world_string(world, current.text)
		delete_world_string(world, current.font)
		current^ = text
		if intrinsic_changed {
			mark_ui_intrinsic_layout_changed(world, entity_index)
		}
		return true
	}
	if index, found := take_free_slot(&world.free_ui_text_indices); found {
		entity.ui_text_index = index
		world.ui_texts[index] = text
	} else {
		entity.ui_text_index = len(world.ui_texts)
		append(&world.ui_texts, text)
	}
	mark_ui_entity_dirty(world, entity_index)
	return true
}

set_ui_button :: proc(world: ^World, entity_index: int, value: UI_Button_Component) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	button := value
	button.text = clone_world_string(world, value.text)
	button.font = clone_world_string(world, value.font)
	entity := &world.entities[entity_index]
	if entity.ui_button_index >= 0 && entity.ui_button_index < len(world.ui_buttons) {
		current := &world.ui_buttons[entity.ui_button_index]
		intrinsic_changed :=
			current.text != value.text ||
			current.font != value.font ||
			current.size != value.size ||
			current.alignment != value.alignment ||
			current.icon != value.icon ||
			current.icon_inset != value.icon_inset
		delete_world_string(world, current.text)
		delete_world_string(world, current.font)
		current^ = button
		if intrinsic_changed {
			mark_ui_intrinsic_layout_changed(world, entity_index)
		}
		return true
	}
	if index, found := take_free_slot(&world.free_ui_button_indices); found {
		entity.ui_button_index = index
		world.ui_buttons[index] = button
	} else {
		entity.ui_button_index = len(world.ui_buttons)
		append(&world.ui_buttons, button)
	}
	mark_ui_entity_dirty(world, entity_index)
	return true
}

set_ui_input :: proc(world: ^World, entity_index: int, value: UI_Input_Component) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	input := value
	input.text = clone_world_string(world, value.text)
	input.font = clone_world_string(world, value.font)
	input.prefix = clone_world_string(world, value.prefix)
	entity := &world.entities[entity_index]
	if entity.ui_input_index >= 0 && entity.ui_input_index < len(world.ui_inputs) {
		current := &world.ui_inputs[entity.ui_input_index]
		intrinsic_changed :=
			current.text != value.text ||
			current.font != value.font ||
			current.prefix != value.prefix ||
			current.size != value.size ||
			current.prefix_width != value.prefix_width ||
			current.prefix_gap != value.prefix_gap
		delete_world_string(world, current.text)
		delete_world_string(world, current.font)
		delete_world_string(world, current.prefix)
		current^ = input
		if intrinsic_changed {
			mark_ui_intrinsic_layout_changed(world, entity_index)
		}
		return true
	}
	if index, found := take_free_slot(&world.free_ui_input_indices); found {
		entity.ui_input_index = index
		world.ui_inputs[index] = input
	} else {
		entity.ui_input_index = len(world.ui_inputs)
		append(&world.ui_inputs, input)
	}
	mark_ui_entity_dirty(world, entity_index)
	return true
}

set_ui_checkbox :: proc(world: ^World, entity_index: int, value: UI_Checkbox_Component) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	entity := &world.entities[entity_index]
	if entity.ui_checkbox_index >= 0 && entity.ui_checkbox_index < len(world.ui_checkboxes) {
		if world.ui_checkboxes[entity.ui_checkbox_index].box_size != value.box_size {
			mark_ui_intrinsic_layout_changed(world, entity_index)
		}
		world.ui_checkboxes[entity.ui_checkbox_index] = value
		return true
	}
	if index, found := take_free_slot(&world.free_ui_checkbox_indices); found {
		entity.ui_checkbox_index = index
		world.ui_checkboxes[index] = value
	} else {
		entity.ui_checkbox_index = len(world.ui_checkboxes)
		append(&world.ui_checkboxes, value)
	}
	mark_ui_entity_dirty(world, entity_index)
	return true
}

set_ui_parent :: proc(world: ^World, entity_index: int, parent: shared.Entity_UUID) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	entity := world.entities[entity_index]
	if entity.ui_layout_index < 0 || entity.ui_layout_index >= len(world.ui_layouts) {
		return false
	}
	if world.ui_layouts[entity.ui_layout_index].parent == parent {
		return false
	}
	world.ui_layouts[entity.ui_layout_index].parent = parent
	mark_ui_subtree_dirty(world, entity_index)
	return true
}

set_ui_hidden :: proc(world: ^World, entity_index: int, hidden: bool) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	entity := world.entities[entity_index]
	if entity.ui_layout_index < 0 || entity.ui_layout_index >= len(world.ui_layouts) {
		return false
	}
	if world.ui_layouts[entity.ui_layout_index].hidden == hidden {
		return false
	}
	world.ui_layouts[entity.ui_layout_index].hidden = hidden
	mark_ui_subtree_dirty(world, entity_index)
	return true
}

set_ui_text_value :: proc(world: ^World, entity_index: int, value: string) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	entity := world.entities[entity_index]
	if entity.ui_text_index < 0 || entity.ui_text_index >= len(world.ui_texts) {
		return false
	}
	text := &world.ui_texts[entity.ui_text_index]
	if text.text == value {
		return false
	}
	delete_world_string(world, text.text)
	text.text = clone_world_string(world, value)
	mark_ui_intrinsic_layout_changed(world, entity_index)
	return true
}

set_ui_input_value :: proc(world: ^World, entity_index: int, value: string) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	entity := world.entities[entity_index]
	if entity.ui_input_index < 0 || entity.ui_input_index >= len(world.ui_inputs) {
		return false
	}
	input := &world.ui_inputs[entity.ui_input_index]
	if input.text == value {
		return false
	}
	delete_world_string(world, input.text)
	input.text = clone_world_string(world, value)
	mark_ui_intrinsic_layout_changed(world, entity_index)
	return true
}

set_ui_input_prefix :: proc(world: ^World, entity_index: int, value: string) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	entity := &world.entities[entity_index]
	if entity.ui_input_index < 0 || entity.ui_input_index >= len(world.ui_inputs) {
		return false
	}
	input := &world.ui_inputs[entity.ui_input_index]
	if input.prefix == value {
		return true
	}
	next := clone_world_string(world, value)
	delete_world_string(world, input.prefix)
	input.prefix = next
	mark_ui_intrinsic_layout_changed(world, entity_index)
	return true
}

set_ui_panel_title :: proc(world: ^World, entity_index: int, value: string) -> bool {
	if !ui_entity_is_mutable(world, entity_index) {
		return false
	}
	entity := world.entities[entity_index]
	if entity.ui_panel_index < 0 || entity.ui_panel_index >= len(world.ui_panels) {
		return false
	}
	panel := &world.ui_panels[entity.ui_panel_index]
	if panel.title == value {
		return false
	}
	delete_world_string(world, panel.title)
	panel.title = clone_world_string(world, value)
	mark_ui_layout_changed(world, entity_index)
	return true
}
