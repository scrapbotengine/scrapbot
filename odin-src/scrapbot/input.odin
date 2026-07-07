package main

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

EDITOR_TEST_TEXT_INPUT_BUFFER_LEN :: 128
EDITOR_TEST_DIAGNOSTIC_BUFFER_LEN :: 160
EDITOR_TEST_UNDO_CAPACITY :: 64
EDITOR_TEST_GIZMO_AXIS_LENGTH :: f32(1.35)
EDITOR_TEST_GIZMO_PICK_RADIUS_PX :: f32(12.0)
EDITOR_TEST_DEFAULT_CAMERA_POSITION :: [3]f32{0.0, 0.0, 4.8}
EDITOR_TEST_DEFAULT_CAMERA_FOV_Y_DEGREES :: f32(48.0)
EDITOR_TEST_DEFAULT_CAMERA_NEAR :: f32(0.1)
EDITOR_TEST_DEFAULT_CAMERA_FAR :: f32(100.0)

Frame_Input_Pointer :: struct {
	position:           [2]f32,
	delta:              [2]f32,
	has_position:       bool,
	primary_down:       bool,
	primary_pressed:    bool,
	primary_released:   bool,
	secondary_down:     bool,
	secondary_pressed:  bool,
	secondary_released: bool,
	wheel_delta:        [2]f32,
}

Frame_Input_Keyboard :: struct {
	ctrl_down:             bool,
	shift_down:            bool,
	alt_down:              bool,
	super_down:            bool,
	move_forward:          bool,
	move_back:             bool,
	move_left:             bool,
	move_right:            bool,
	move_up:               bool,
	move_down:             bool,
	editor_toggle_pressed: bool,
	editor_enter_pressed:  bool,
	editor_undo_pressed:   bool,
	editor_redo_pressed:   bool,
	editor_left_pressed:   bool,
	editor_right_pressed:  bool,
	editor_home_pressed:   bool,
	editor_end_pressed:    bool,
	editor_backspace_pressed: bool,
	editor_delete_pressed: bool,
	editor_select_all_pressed: bool,
	editor_copy_pressed:       bool,
	editor_paste_pressed:      bool,
	editor_spawn_pressed:      bool,
	editor_despawn_pressed:    bool,
}

Frame_Input :: struct {
	pointer:                   Frame_Input_Pointer,
	keyboard:                  Frame_Input_Keyboard,
	ui_visible:                bool,
	debug_overlay_visible:     bool,
	viewport_width:            f32,
	viewport_height:           f32,
	pixel_scale:               f32,
	camera_override_enabled:   bool,
	camera_override:           Editor_Test_Camera_State,
	system_profile_count_hint: int,
	text_input:                string,
	clipboard_text:            string,
	editor_add_component_id:   string,
	editor_remove_component_id: string,
}

Step_Input_Frame :: struct {
	frame: int,
	input: Frame_Input,
}

Editor_Test_Splitter :: enum {
	None,
	Left,
	Right,
}

Editor_Test_Axis :: enum {
	None,
	X,
	Y,
	Z,
}

Editor_Test_Field_Edit_Command :: struct {
	entity:    Entity_Handle,
	component: string,
	field:     string,
	lane:      int,
	old_value: Runtime_Component_Value,
	new_value: Runtime_Component_Value,
}

Editor_Test_Input_State :: struct {
	captured_pointer:    bool,
	paused:              bool,
	step_once:           bool,
	selected_entity:     Entity_Handle,
	has_selected_entity: bool,
	system_scroll_y:     f32,
	entity_scroll_y:     f32,
	inspector_scroll_y:  f32,
	selected_property_component: string,
	selected_property_field:     string,
	selected_property_lane:      int,
	has_selected_property:       bool,
	dragging_splitter:           Editor_Test_Splitter,
	dragging_axis:               Editor_Test_Axis,
	hovered_axis:                Editor_Test_Axis,
	left_sidebar_width:          f32,
	right_sidebar_width:         f32,
	last_pointer:                [2]f32,
	has_last_pointer:            bool,
	gizmo_drag_start_position:   [3]f32,
	has_gizmo_drag_start_position: bool,
	text_input_active:           bool,
	text_input_component:        string,
	text_input_field:            string,
	text_input_lane:             int,
	text_input_buffer:           [EDITOR_TEST_TEXT_INPUT_BUFFER_LEN]u8,
	text_input_len:              int,
	text_input_cursor:           int,
	text_input_selection_anchor: int,
	has_diagnostic:              bool,
	diagnostic_buffer:           [EDITOR_TEST_DIAGNOSTIC_BUFFER_LEN]u8,
	diagnostic_len:              int,
	clipboard_buffer:            [EDITOR_TEST_TEXT_INPUT_BUFFER_LEN]u8,
	clipboard_len:               int,
	clipboard_changed:           bool,
	editor_spawn_index:          int,
	undo_stack:                  [EDITOR_TEST_UNDO_CAPACITY]Editor_Test_Field_Edit_Command,
	undo_len:                    int,
	redo_stack:                  [EDITOR_TEST_UNDO_CAPACITY]Editor_Test_Field_Edit_Command,
	redo_len:                    int,
	pending_scene_edit:          Editor_Test_Field_Edit_Command,
	has_pending_scene_edit:      bool,
}

frame_input_default :: proc() -> Frame_Input {
	return Frame_Input{
		ui_visible = true,
		pixel_scale = 1.0,
	}
}

route_editor_test_input :: proc(state: ^Editor_Test_Input_State, registry: Runtime_Component_Registry, world: ^Runtime_World, input: ^Frame_Input) {
	state.step_once = false
	if !input.debug_overlay_visible {
		state.captured_pointer = false
		state.dragging_splitter = .None
		state.dragging_axis = .None
		state.hovered_axis = .None
		state.has_last_pointer = false
		clear_editor_gizmo_drag(state)
		return
	}
	consumed := false
	if apply_editor_test_keyboard_edits(state, registry, world, input^) {
		consumed = true
	}
	if input.pointer.has_position {
		inside_game := editor_pointer_in_game_viewport(input^)
		ensure_editor_sidebar_widths(state, input^)
		update_editor_gizmo_hover(state, world^, input^)
		if state.dragging_splitter != .None && input.pointer.primary_down {
			drag_editor_splitter(state, input^)
			consumed = true
		}
		if state.dragging_axis != .None && input.pointer.primary_down {
			drag_editor_gizmo_axis(state, world, input^)
			consumed = true
		}
		if input.pointer.primary_pressed {
			if editor_pointer_in_play_button(input^) {
				state.paused = !state.paused
				state.captured_pointer = true
				consumed = true
			} else if editor_pointer_in_step_button(input^) {
				state.paused = true
				state.step_once = true
				state.captured_pointer = true
				consumed = true
			} else if editor_pointer_in_spawn_entity_button(input^) {
				commit_editor_test_text_input(world, state)
				spawn_editor_test_entity(world, state)
				state.captured_pointer = true
				consumed = true
			} else if editor_pointer_in_despawn_entity_button(input^) {
				commit_editor_test_text_input(world, state)
				despawn_editor_test_selected_entity(world, state)
				state.captured_pointer = true
				consumed = true
			} else if editor_pointer_in_add_component_button(input^) {
				commit_editor_test_text_input(world, state)
				add_editor_test_first_missing_component(registry, world, state)
				state.captured_pointer = true
				consumed = true
			} else if editor_pointer_in_remove_component_button(input^) {
				commit_editor_test_text_input(world, state)
				remove_editor_test_visible_component(world, state)
				state.captured_pointer = true
				consumed = true
			} else if editor_pointer_in_selected_entity_header(state^, input^) {
				commit_editor_test_text_input(world, state)
				_ = copy_editor_test_selected_entity_id(world^, state)
				state.captured_pointer = true
				consumed = true
			} else if splitter, splitter_ok := editor_splitter_at_pointer(state^, input^); splitter_ok {
				state.dragging_splitter = splitter
				state.captured_pointer = true
				state.last_pointer = input.pointer.position
				state.has_last_pointer = true
				consumed = true
			} else if selected, selected_ok := editor_entity_at_pointer(world^, state^, input^); selected_ok {
				commit_editor_test_text_input(world, state)
				state.selected_entity = selected
				state.has_selected_entity = true
				state.has_selected_property = false
				state.selected_property_component = ""
				state.selected_property_field = ""
				state.selected_property_lane = 0
				clear_editor_test_text_input(state)
				clear_editor_test_diagnostic(state)
				state.captured_pointer = true
				consumed = true
			} else if component_id, field_name, lane, property_ok := editor_inspector_property_at_pointer(world^, state^, input^); property_ok {
				if state.text_input_active &&
				   (state.text_input_component != component_id || state.text_input_field != field_name || state.text_input_lane != lane) {
					commit_editor_test_text_input(world, state)
				}
				if !apply_editor_test_typed_control_click(world, state, component_id, field_name, lane) {
					state.selected_property_component = component_id
					state.selected_property_field = field_name
					state.selected_property_lane = lane
					state.has_selected_property = true
					focus_editor_test_text_input(world^, state, component_id, field_name, lane)
				}
				state.captured_pointer = true
				consumed = true
			} else if !inside_game {
				commit_editor_test_text_input(world, state)
				state.captured_pointer = true
				consumed = true
			} else if state.hovered_axis != .None {
				commit_editor_test_text_input(world, state)
				state.dragging_axis = state.hovered_axis
				state.captured_pointer = true
				state.last_pointer = input.pointer.position
				state.has_last_pointer = true
				begin_editor_gizmo_drag(state, world^)
				consumed = true
			} else if state.text_input_active {
				commit_editor_test_text_input(world, state)
			}
		}
		if input.pointer.primary_down && state.captured_pointer {
			consumed = true
		}
		if input.pointer.primary_released {
			if state.captured_pointer || !inside_game {
				consumed = true
			}
			if state.dragging_axis != .None {
				finish_editor_gizmo_drag(state, world)
			}
			state.captured_pointer = false
			state.dragging_splitter = .None
			state.dragging_axis = .None
			state.has_last_pointer = false
			clear_editor_gizmo_drag(state)
			update_editor_gizmo_hover(state, world^, input^)
		}
		if input.pointer.secondary_pressed || input.pointer.secondary_down || input.pointer.secondary_released {
			if !inside_game {
				consumed = true
			}
		}
		if (input.pointer.wheel_delta[0] != 0 || input.pointer.wheel_delta[1] != 0) && !inside_game {
			if editor_pointer_in_system_list(input^) {
				state.system_scroll_y = editor_system_scroll_next(input^, state.system_scroll_y, input.pointer.wheel_delta[1])
			} else if editor_pointer_in_entity_list(world^, input^) {
				state.entity_scroll_y = editor_entity_scroll_next(world^, input^, state.entity_scroll_y, input.pointer.wheel_delta[1])
			} else if editor_pointer_in_inspector(world^, state^, input^) {
				state.inspector_scroll_y = editor_inspector_scroll_next(world^, state^, input^, state.inspector_scroll_y, input.pointer.wheel_delta[1])
			}
			consumed = true
		}
	} else if input.pointer.primary_released {
		state.captured_pointer = false
		state.dragging_splitter = .None
		state.dragging_axis = .None
		state.hovered_axis = .None
		state.has_last_pointer = false
		clear_editor_gizmo_drag(state)
	}
	if consumed {
		clear_frame_pointer_actions(input)
	}
}

update_editor_gizmo_hover :: proc(state: ^Editor_Test_Input_State, world: Runtime_World, input: Frame_Input) {
	if state.dragging_axis != .None {
		state.hovered_axis = state.dragging_axis
		return
	}
	if axis, axis_ok := editor_gizmo_axis_at_pointer(world, state^, input); axis_ok {
		state.hovered_axis = axis
	} else {
		state.hovered_axis = .None
	}
}

editor_gizmo_highlight_axis :: proc(state: Editor_Test_Input_State) -> Editor_Test_Axis {
	if state.dragging_axis != .None {
		return state.dragging_axis
	}
	return state.hovered_axis
}

editor_test_should_run_update :: proc(state: Editor_Test_Input_State) -> bool {
	return !state.paused || state.step_once
}

editor_test_selected_entity_id :: proc(state: Editor_Test_Input_State, world: Runtime_World) -> (string, bool) {
	if !state.has_selected_entity {
		return "", false
	}
	entity, err := runtime_world_entity(world, state.selected_entity)
	if err != .None {
		return "", false
	}
	return entity.id, true
}

editor_test_input_state_free :: proc(state: ^Editor_Test_Input_State) {
	clear_editor_test_field_command_stack(&state.undo_stack, &state.undo_len)
	clear_editor_test_field_command_stack(&state.redo_stack, &state.redo_len)
	clear_editor_test_pending_scene_edit(state)
}

apply_editor_test_keyboard_edits :: proc(state: ^Editor_Test_Input_State, registry: Runtime_Component_Registry, world: ^Runtime_World, input: Frame_Input) -> bool {
	consumed := false
	if state.text_input_active {
		if input.keyboard.editor_copy_pressed {
			if copy_editor_test_text_input_selection(state) {
				consumed = true
			}
		}
		if input.keyboard.editor_paste_pressed && input.clipboard_text != "" {
			editor_test_text_input_insert(state, input.clipboard_text)
			consumed = true
		}
		if input.keyboard.editor_select_all_pressed {
			select_all_editor_test_text_input(state)
			consumed = true
		}
		if input.keyboard.editor_home_pressed {
			editor_test_text_input_move_cursor(state, 0, input.keyboard.shift_down)
			consumed = true
		}
		if input.keyboard.editor_end_pressed {
			editor_test_text_input_move_cursor(state, state.text_input_len, input.keyboard.shift_down)
			consumed = true
		}
		if input.keyboard.editor_left_pressed {
			next_cursor := state.text_input_cursor
			if !input.keyboard.shift_down && editor_test_text_input_has_selection(state^) {
				next_cursor = min_int(state.text_input_cursor, state.text_input_selection_anchor)
			} else {
				next_cursor = max_int(state.text_input_cursor - 1, 0)
			}
			editor_test_text_input_move_cursor(state, next_cursor, input.keyboard.shift_down)
			consumed = true
		}
		if input.keyboard.editor_right_pressed {
			next_cursor := state.text_input_cursor
			if !input.keyboard.shift_down && editor_test_text_input_has_selection(state^) {
				next_cursor = max_int(state.text_input_cursor, state.text_input_selection_anchor)
			} else {
				next_cursor = min_int(state.text_input_cursor + 1, state.text_input_len)
			}
			editor_test_text_input_move_cursor(state, next_cursor, input.keyboard.shift_down)
			consumed = true
		}
		if input.keyboard.editor_backspace_pressed {
			editor_test_text_input_backspace(state)
			consumed = true
		}
		if input.keyboard.editor_delete_pressed {
			editor_test_text_input_delete(state)
			consumed = true
		}
		if input.text_input != "" {
			editor_test_text_input_insert(state, input.text_input)
			consumed = true
		}
		if input.keyboard.editor_enter_pressed {
			commit_editor_test_text_input(world, state)
			return true
		}
		return consumed
	}
	if input.keyboard.editor_undo_pressed {
		return undo_editor_test_field_edit(world, state)
	}
	if input.keyboard.editor_redo_pressed {
		return redo_editor_test_field_edit(world, state)
	}
	if input.keyboard.editor_copy_pressed {
		return copy_editor_test_selected_entity_id(world^, state)
	}
	if input.keyboard.editor_spawn_pressed {
		return spawn_editor_test_entity(world, state)
	}
	if input.keyboard.editor_despawn_pressed {
		return despawn_editor_test_selected_entity(world, state)
	}
	if input.editor_add_component_id != "" {
		return add_editor_test_component(registry, world, state, input.editor_add_component_id)
	}
	if input.editor_remove_component_id != "" {
		return remove_editor_test_component(world, state, input.editor_remove_component_id)
	}
	return false
}

apply_editor_test_typed_control_click :: proc(
	world: ^Runtime_World,
	state: ^Editor_Test_Input_State,
	component_id, field_name: string,
	lane: int,
) -> bool {
	if !state.has_selected_entity {
		return false
	}
	old_value, old_err := runtime_world_get_component_field_value(world^, state.selected_entity, component_id, field_name)
	if old_err != .None {
		return false
	}
	new_value, typed_ok := next_editor_test_typed_control_value(component_id, field_name, old_value)
	if !typed_ok {
		return false
	}
	if !apply_editor_test_field_value(world, state, state.selected_entity, component_id, field_name, lane, new_value, true) {
		return false
	}
	clear_editor_test_text_input(state)
	state.selected_property_component = component_id
	state.selected_property_field = field_name
	state.selected_property_lane = clamp_int(lane, 0, 2)
	state.has_selected_property = true
	return true
}

next_editor_test_typed_control_value :: proc(component_id, field_name: string, value: Runtime_Component_Value) -> (Runtime_Component_Value, bool) {
	switch value.value_type {
	case .Boolean:
		return runtime_component_value_boolean(!value.boolean), true
	case .String:
		if next, ok := editor_test_known_selector_next_value(component_id, field_name, value.string_value); ok {
			return runtime_component_value_string(next), true
		}
	case .Int, .Float, .Vec3:
	}
	return Runtime_Component_Value{}, false
}

editor_test_known_selector_next_value :: proc(component_id, field_name, value: string) -> (string, bool) {
	switch component_id {
	case GEOMETRY_PRIMITIVE_COMPONENT_ID:
		if field_name == "primitive" {
			return editor_test_next_string_option(value, []string{"box", "plane", "sphere", "uv_sphere", "ico_sphere"})
		}
	case RENDERER_COMPONENT_ID:
		switch field_name {
		case "tone_mapping":
			return editor_test_next_string_option(value, []string{"none", "reinhard", "aces"})
		case "antialiasing":
			return editor_test_next_string_option(value, []string{"none", "fxaa"})
		}
	case UI_CANVAS_COMPONENT_ID:
		if field_name == "scale_mode" {
			return editor_test_next_string_option(value, []string{"none", "fit", "fill"})
		}
	case UI_LAYOUT_ITEM_COMPONENT_ID:
		if field_name == "align" {
			return editor_test_next_string_option(value, []string{"start", "center", "end"})
		}
	case UI_TEXT_BLOCK_COMPONENT_ID:
		switch field_name {
		case "horizontal_align", "vertical_align":
			return editor_test_next_string_option(value, []string{"start", "center", "end"})
		}
	}
	return "", false
}

editor_test_next_string_option :: proc(value: string, options: []string) -> (string, bool) {
	for option, index in options {
		if value == option {
			return options[(index + 1) % len(options)], true
		}
	}
	return "", false
}

focus_editor_test_text_input :: proc(world: Runtime_World, state: ^Editor_Test_Input_State, component_id, field_name: string, lane: int) -> bool {
	if !state.has_selected_entity {
		clear_editor_test_text_input(state)
		return false
	}
	value, value_err := runtime_world_get_component_field_value(world, state.selected_entity, component_id, field_name)
	if value_err != .None {
		clear_editor_test_text_input(state)
		return false
	}
	formatted, ok := editor_test_format_input_value(&state.text_input_buffer, value, lane)
	if !ok {
		clear_editor_test_text_input(state)
		return false
	}
	state.text_input_active = true
	state.text_input_component = component_id
	state.text_input_field = field_name
	state.text_input_lane = clamp_int(lane, 0, 2)
	state.text_input_len = len(formatted)
	state.text_input_cursor = state.text_input_len
	if editor_test_component_value_selects_all_on_focus(value) {
		state.text_input_selection_anchor = 0
	} else {
		state.text_input_selection_anchor = state.text_input_len
	}
	clear_editor_test_diagnostic(state)
	return true
}

commit_editor_test_text_input :: proc(world: ^Runtime_World, state: ^Editor_Test_Input_State) -> bool {
	if !state.text_input_active || !state.has_selected_entity {
		return false
	}
	current, current_err := runtime_world_get_component_field_value(world^, state.selected_entity, state.text_input_component, state.text_input_field)
	if current_err != .None {
		set_editor_test_diagnostic(state, "invalid editor target: %s.%s", state.text_input_component, state.text_input_field)
		clear_editor_test_text_input(state)
		return false
	}
	text := string(state.text_input_buffer[:state.text_input_len])
	next, parse_ok := editor_test_parse_input_value(current, text, state.text_input_lane)
	if !parse_ok {
		set_editor_test_diagnostic(state, "invalid value for %s.%s", state.text_input_component, state.text_input_field)
		return false
	}
	set_ok := apply_editor_test_field_value(
		world,
		state,
		state.selected_entity,
		state.text_input_component,
		state.text_input_field,
		state.text_input_lane,
		next,
		true,
	)
	if !set_ok {
		set_editor_test_diagnostic(state, "failed to edit %s.%s", state.text_input_component, state.text_input_field)
		return false
	}
	clear_editor_test_diagnostic(state)
	clear_editor_test_text_input(state)
	return true
}

apply_editor_test_field_value :: proc(
	world: ^Runtime_World,
	state: ^Editor_Test_Input_State,
	entity: Entity_Handle,
	component_id, field_name: string,
	lane: int,
	new_value: Runtime_Component_Value,
	push_undo: bool,
) -> bool {
	old_value, old_err := runtime_world_get_component_field_value(world^, entity, component_id, field_name)
	if old_err != .None {
		return false
	}
	if editor_test_component_values_equal(old_value, new_value) {
		return true
	}
	set_err := runtime_world_set_component_field_value(world, entity, component_id, field_name, new_value)
	if set_err != .None {
		return false
	}
	if push_undo {
		push_editor_test_field_command(&state.undo_stack, &state.undo_len, entity, component_id, field_name, lane, old_value, new_value)
		clear_editor_test_field_command_stack(&state.redo_stack, &state.redo_len)
		set_editor_test_pending_scene_edit(state, entity, component_id, field_name, lane, old_value, new_value)
	}
	clear_editor_test_diagnostic(state)
	return true
}

undo_editor_test_field_edit :: proc(world: ^Runtime_World, state: ^Editor_Test_Input_State) -> bool {
	command, ok := pop_editor_test_field_command(&state.undo_stack, &state.undo_len)
	if !ok {
		return false
	}
	component_id := editor_test_field_command_component(&command)
	field_name := editor_test_field_command_field(&command)
	set_err := runtime_world_set_component_field_value(world, command.entity, component_id, field_name, command.old_value)
	if set_err != .None {
		editor_test_field_command_free(&command)
		return false
	}
	set_editor_test_pending_scene_edit(state, command.entity, component_id, field_name, command.lane, command.new_value, command.old_value)
	push_editor_test_field_command(&state.redo_stack, &state.redo_len, command.entity, component_id, field_name, command.lane, command.old_value, command.new_value)
	select_editor_test_field_edit_command(world^, state, &command)
	clear_editor_test_diagnostic(state)
	editor_test_field_command_free(&command)
	return true
}

redo_editor_test_field_edit :: proc(world: ^Runtime_World, state: ^Editor_Test_Input_State) -> bool {
	command, ok := pop_editor_test_field_command(&state.redo_stack, &state.redo_len)
	if !ok {
		return false
	}
	component_id := editor_test_field_command_component(&command)
	field_name := editor_test_field_command_field(&command)
	set_err := runtime_world_set_component_field_value(world, command.entity, component_id, field_name, command.new_value)
	if set_err != .None {
		editor_test_field_command_free(&command)
		return false
	}
	set_editor_test_pending_scene_edit(state, command.entity, component_id, field_name, command.lane, command.old_value, command.new_value)
	push_editor_test_field_command(&state.undo_stack, &state.undo_len, command.entity, component_id, field_name, command.lane, command.old_value, command.new_value)
	select_editor_test_field_edit_command(world^, state, &command)
	clear_editor_test_diagnostic(state)
	editor_test_field_command_free(&command)
	return true
}

select_editor_test_field_edit_command :: proc(world: Runtime_World, state: ^Editor_Test_Input_State, command: ^Editor_Test_Field_Edit_Command) {
	component_id := editor_test_field_command_component(command)
	field_name := editor_test_field_command_field(command)
	table, table_ok := runtime_world_find_component_table(world, component_id)
	if !table_ok {
		return
	}
	field_index, field_ok := runtime_component_table_field_index(table^, field_name)
	if !field_ok {
		return
	}
	state.selected_entity = command.entity
	state.has_selected_entity = true
	state.selected_property_component = table.id
	state.selected_property_field = table.columns[field_index].name
	state.selected_property_lane = command.lane
	state.has_selected_property = true
	clear_editor_test_text_input(state)
}

push_editor_test_field_command :: proc(
	stack: ^[EDITOR_TEST_UNDO_CAPACITY]Editor_Test_Field_Edit_Command,
	stack_len: ^int,
	entity: Entity_Handle,
	component_id, field_name: string,
	lane: int,
	old_value, new_value: Runtime_Component_Value,
) -> bool {
	if stack_len^ >= EDITOR_TEST_UNDO_CAPACITY {
		editor_test_field_command_free(&stack[0])
		for index := 1; index < EDITOR_TEST_UNDO_CAPACITY; index += 1 {
			stack[index - 1] = stack[index]
		}
		stack[EDITOR_TEST_UNDO_CAPACITY - 1] = Editor_Test_Field_Edit_Command{}
		stack_len^ = EDITOR_TEST_UNDO_CAPACITY - 1
	}
	slot := &stack[stack_len^]
	if !editor_test_field_command_init(slot, entity, component_id, field_name, lane, old_value, new_value) {
		slot^ = Editor_Test_Field_Edit_Command{}
		return false
	}
	stack_len^ += 1
	return true
}

pop_editor_test_field_command :: proc(
	stack: ^[EDITOR_TEST_UNDO_CAPACITY]Editor_Test_Field_Edit_Command,
	stack_len: ^int,
) -> (Editor_Test_Field_Edit_Command, bool) {
	if stack_len^ <= 0 {
		return Editor_Test_Field_Edit_Command{}, false
	}
	stack_len^ -= 1
	command := stack[stack_len^]
	stack[stack_len^] = Editor_Test_Field_Edit_Command{}
	return command, true
}

clear_editor_test_field_command_stack :: proc(
	stack: ^[EDITOR_TEST_UNDO_CAPACITY]Editor_Test_Field_Edit_Command,
	stack_len: ^int,
) {
	for index := 0; index < stack_len^; index += 1 {
		editor_test_field_command_free(&stack[index])
	}
	stack_len^ = 0
}

editor_test_field_command_init :: proc(
	command: ^Editor_Test_Field_Edit_Command,
	entity: Entity_Handle,
	component_id, field_name: string,
	lane: int,
	old_value, new_value: Runtime_Component_Value,
) -> bool {
	command^ = Editor_Test_Field_Edit_Command{}
	owned_component, component_err := strings.clone(component_id)
	if component_err != nil {
		return false
	}
	owned_field, field_err := strings.clone(field_name)
	if field_err != nil {
		delete(owned_component)
		return false
	}
	owned_old, old_err := runtime_component_value_clone(old_value)
	if old_err != .None {
		delete(owned_component)
		delete(owned_field)
		return false
	}
	owned_new, new_err := runtime_component_value_clone(new_value)
	if new_err != .None {
		delete(owned_component)
		delete(owned_field)
		runtime_component_value_free(owned_old)
		return false
	}
	command.entity = entity
	command.component = owned_component
	command.field = owned_field
	command.lane = clamp_int(lane, 0, 2)
	command.old_value = owned_old
	command.new_value = owned_new
	return true
}

editor_test_field_command_free :: proc(command: ^Editor_Test_Field_Edit_Command) {
	if command.component != "" {
		delete(command.component)
	}
	if command.field != "" {
		delete(command.field)
	}
	runtime_component_value_free(command.old_value)
	runtime_component_value_free(command.new_value)
	command^ = Editor_Test_Field_Edit_Command{}
}

editor_test_field_command_component :: proc(command: ^Editor_Test_Field_Edit_Command) -> string {
	return command.component
}

editor_test_field_command_field :: proc(command: ^Editor_Test_Field_Edit_Command) -> string {
	return command.field
}

set_editor_test_pending_scene_edit :: proc(
	state: ^Editor_Test_Input_State,
	entity: Entity_Handle,
	component_id, field_name: string,
	lane: int,
	old_value, new_value: Runtime_Component_Value,
) -> bool {
	clear_editor_test_pending_scene_edit(state)
	if !editor_test_field_command_init(&state.pending_scene_edit, entity, component_id, field_name, lane, old_value, new_value) {
		return false
	}
	state.has_pending_scene_edit = true
	return true
}

take_editor_test_pending_scene_edit :: proc(state: ^Editor_Test_Input_State) -> (Editor_Test_Field_Edit_Command, bool) {
	if !state.has_pending_scene_edit {
		return Editor_Test_Field_Edit_Command{}, false
	}
	command := state.pending_scene_edit
	state.pending_scene_edit = Editor_Test_Field_Edit_Command{}
	state.has_pending_scene_edit = false
	return command, true
}

clear_editor_test_pending_scene_edit :: proc(state: ^Editor_Test_Input_State) {
	if state.has_pending_scene_edit {
		editor_test_field_command_free(&state.pending_scene_edit)
		state.has_pending_scene_edit = false
	}
}

editor_test_component_values_equal :: proc(left, right: Runtime_Component_Value) -> bool {
	if left.value_type != right.value_type {
		return false
	}
	switch left.value_type {
	case .Boolean:
		return left.boolean == right.boolean
	case .Int:
		return left.int_value == right.int_value
	case .Float:
		return left.float == right.float
	case .Vec3:
		return left.vec3 == right.vec3
	case .String:
		return left.string_value == right.string_value
	}
	return false
}

clear_editor_test_text_input :: proc(state: ^Editor_Test_Input_State) {
	state.text_input_active = false
	state.text_input_component = ""
	state.text_input_field = ""
	state.text_input_lane = 0
	state.text_input_buffer = {}
	state.text_input_len = 0
	state.text_input_cursor = 0
	state.text_input_selection_anchor = 0
}

set_editor_test_diagnostic :: proc(state: ^Editor_Test_Input_State, format: string, args: ..any) {
	state.diagnostic_buffer = {}
	text := fmt.bprintf(state.diagnostic_buffer[:], format, ..args)
	state.diagnostic_len = len(text)
	state.has_diagnostic = state.diagnostic_len > 0
}

clear_editor_test_diagnostic :: proc(state: ^Editor_Test_Input_State) {
	state.has_diagnostic = false
	state.diagnostic_buffer = {}
	state.diagnostic_len = 0
}

editor_test_diagnostic_text :: proc(state: ^Editor_Test_Input_State) -> string {
	if !state.has_diagnostic {
		return ""
	}
	return string(state.diagnostic_buffer[:state.diagnostic_len])
}

editor_test_component_value_selects_all_on_focus :: proc(value: Runtime_Component_Value) -> bool {
	switch value.value_type {
	case .Int, .Float, .Vec3:
		return true
	case .Boolean, .String:
		return false
	}
	return false
}

editor_test_format_input_value :: proc(buffer: ^[EDITOR_TEST_TEXT_INPUT_BUFFER_LEN]u8, value: Runtime_Component_Value, lane: int = 0) -> (string, bool) {
	buffer^ = {}
	switch value.value_type {
	case .Boolean:
		if value.boolean {
			copy(buffer[:], "true")
			return string(buffer[:4]), true
		}
		copy(buffer[:], "false")
		return string(buffer[:5]), true
	case .Int:
		text := fmt.bprintf(buffer[:], "%d", value.int_value)
		return text, true
	case .Float:
		text := fmt.bprintf(buffer[:], "%g", value.float)
		return text, true
	case .Vec3:
		text := fmt.bprintf(buffer[:], "%g", value.vec3[clamp_int(lane, 0, 2)])
		return text, true
	case .String:
		if len(value.string_value) > len(buffer) {
			return "", false
		}
		copy(buffer[:], value.string_value)
		return string(buffer[:len(value.string_value)]), true
	}
	return "", false
}

editor_test_parse_input_value :: proc(current: Runtime_Component_Value, text: string, lane: int = 0) -> (Runtime_Component_Value, bool) {
	trimmed := strings.trim_space(text)
	switch current.value_type {
	case .Boolean:
		if trimmed == "true" || trimmed == "1" {
			return runtime_component_value_boolean(true), true
		}
		if trimmed == "false" || trimmed == "0" {
			return runtime_component_value_boolean(false), true
		}
	case .Int:
		parsed, ok := strconv.parse_int(trimmed, 10)
		if ok {
			return runtime_component_value_int(parsed), true
		}
	case .Float:
		parsed, ok := strconv.parse_f32(trimmed)
		if ok {
			return runtime_component_value_float(parsed), true
		}
	case .Vec3:
		parsed, ok := strconv.parse_f32(trimmed)
		if ok {
			next := current.vec3
			next[clamp_int(lane, 0, 2)] = parsed
			return runtime_component_value_vec3(next), true
		}
	case .String:
		return runtime_component_value_string(text), true
	}
	return Runtime_Component_Value{}, false
}

select_all_editor_test_text_input :: proc(state: ^Editor_Test_Input_State) {
	state.text_input_selection_anchor = 0
	state.text_input_cursor = state.text_input_len
}

copy_editor_test_text_input_selection :: proc(state: ^Editor_Test_Input_State) -> bool {
	if !state.text_input_active || !editor_test_text_input_has_selection(state^) {
		return false
	}
	start := min_int(state.text_input_cursor, state.text_input_selection_anchor)
	end := max_int(state.text_input_cursor, state.text_input_selection_anchor)
	return set_editor_test_clipboard(state, string(state.text_input_buffer[start:end]))
}

copy_editor_test_selected_entity_id :: proc(world: Runtime_World, state: ^Editor_Test_Input_State) -> bool {
	entity_id, selected_ok := editor_test_selected_entity_id(state^, world)
	if !selected_ok {
		return false
	}
	return set_editor_test_clipboard(state, entity_id)
}

spawn_editor_test_entity :: proc(world: ^Runtime_World, state: ^Editor_Test_Input_State) -> bool {
	id_buffer: [64]u8
	name_buffer: [64]u8
	for attempt := 0; attempt < 1000; attempt += 1 {
		state.editor_spawn_index += 1
		id := fmt.bprintf(id_buffer[:], "editor-spawn-%d", state.editor_spawn_index)
		name := fmt.bprintf(name_buffer[:], "Editor Spawn %d", state.editor_spawn_index)
		entity, err := runtime_world_create_entity(world, id, name)
		if err == .None {
			state.selected_entity = entity
			state.has_selected_entity = true
			state.has_selected_property = false
			state.selected_property_component = ""
			state.selected_property_field = ""
			state.selected_property_lane = 0
			clear_editor_test_text_input(state)
			clear_editor_test_diagnostic(state)
			return true
		}
		if err != .Duplicate_Entity_ID {
			set_editor_test_diagnostic(state, "Could not spawn entity: %s", runtime_error_label(err))
			return true
		}
	}
	set_editor_test_diagnostic(state, "Could not spawn entity: Duplicate_Entity_ID")
	return true
}

despawn_editor_test_selected_entity :: proc(world: ^Runtime_World, state: ^Editor_Test_Input_State) -> bool {
	if !state.has_selected_entity {
		return false
	}
	err := runtime_world_remove_entity(world, state.selected_entity)
	clear_editor_test_selection(state)
	if err != .None {
		set_editor_test_diagnostic(state, "Could not despawn entity: %s", runtime_error_label(err))
	}
	return true
}

add_editor_test_component :: proc(registry: Runtime_Component_Registry, world: ^Runtime_World, state: ^Editor_Test_Input_State, component_id: string) -> bool {
	if !state.has_selected_entity {
		return false
	}
	definition, found := runtime_find_component(registry, component_id)
	if !found {
		set_editor_test_diagnostic(state, "Unknown component: %s", component_id)
		return true
	}
	if _, entity_err := runtime_world_entity(world^, state.selected_entity); entity_err != .None {
		set_editor_test_diagnostic(state, "Could not add component: %s", runtime_error_label(entity_err))
		return true
	}
	has_component, has_err := runtime_world_has_component(world^, state.selected_entity, component_id)
	if has_err != .None {
		set_editor_test_diagnostic(state, "Could not add component: %s", runtime_error_label(has_err))
		return true
	}
	if has_component {
		set_editor_test_diagnostic(state, "Component already present: %s", component_id)
		return true
	}

	fields := make([]Runtime_Component_Field_Value, len(definition.fields))
	if fields == nil && len(definition.fields) > 0 {
		set_editor_test_diagnostic(state, "Could not add component: Out_Of_Memory")
		return true
	}
	defer delete(fields)
	for field, index in definition.fields {
		fields[index] = Runtime_Component_Field_Value{
			name = field.name,
			value = editor_test_default_component_value(component_id, field),
		}
	}
	set_err := runtime_world_set_component(world, state.selected_entity, component_id, fields)
	if set_err != .None {
		set_editor_test_diagnostic(state, "Could not add component: %s", runtime_error_label(set_err))
		return true
	}

	clear_editor_test_field_command_stack(&state.undo_stack, &state.undo_len)
	clear_editor_test_field_command_stack(&state.redo_stack, &state.redo_len)
	clear_editor_test_text_input(state)
	clear_editor_test_diagnostic(state)
	if len(definition.fields) > 0 {
		state.selected_property_component = component_id
		state.selected_property_field = definition.fields[0].name
		state.selected_property_lane = 0
		state.has_selected_property = true
	} else {
		state.has_selected_property = false
		state.selected_property_component = ""
		state.selected_property_field = ""
		state.selected_property_lane = 0
	}
	return true
}

remove_editor_test_component :: proc(world: ^Runtime_World, state: ^Editor_Test_Input_State, component_id: string) -> bool {
	if !state.has_selected_entity {
		return false
	}
	has_component, has_err := runtime_world_has_component(world^, state.selected_entity, component_id)
	if has_err != .None {
		set_editor_test_diagnostic(state, "Could not remove component: %s", runtime_error_label(has_err))
		return true
	}
	if !has_component {
		set_editor_test_diagnostic(state, "Component not present: %s", component_id)
		return true
	}
	_, remove_err := runtime_world_remove_component(world, state.selected_entity, component_id)
	if remove_err != .None {
		set_editor_test_diagnostic(state, "Could not remove component: %s", runtime_error_label(remove_err))
		return true
	}

	clear_editor_test_field_command_stack(&state.undo_stack, &state.undo_len)
	clear_editor_test_field_command_stack(&state.redo_stack, &state.redo_len)
	if state.has_selected_property && state.selected_property_component == component_id {
		state.has_selected_property = false
		state.selected_property_component = ""
		state.selected_property_field = ""
		state.selected_property_lane = 0
		clear_editor_test_text_input(state)
	}
	clear_editor_test_diagnostic(state)
	return true
}

add_editor_test_first_missing_component :: proc(registry: Runtime_Component_Registry, world: ^Runtime_World, state: ^Editor_Test_Input_State) -> bool {
	if !state.has_selected_entity {
		return false
	}
	for component in registry.components {
		if !editor_test_component_addable_from_visible_chrome(component.id) {
			continue
		}
		has_component, has_err := runtime_world_has_component(world^, state.selected_entity, component.id)
		if has_err != .None {
			set_editor_test_diagnostic(state, "Could not add component: %s", runtime_error_label(has_err))
			return true
		}
		if !has_component {
			return add_editor_test_component(registry, world, state, component.id)
		}
	}
	set_editor_test_diagnostic(state, "No addable component available")
	return true
}

remove_editor_test_visible_component :: proc(world: ^Runtime_World, state: ^Editor_Test_Input_State) -> bool {
	if !state.has_selected_entity {
		return false
	}
	if state.has_selected_property && state.selected_property_component != "" {
		return remove_editor_test_component(world, state, state.selected_property_component)
	}
	selected_index, selected_err := runtime_world_entity_index(world^, state.selected_entity)
	if selected_err != .None {
		set_editor_test_diagnostic(state, "Could not remove component: %s", runtime_error_label(selected_err))
		return true
	}
	for table in world.component_tables {
		if selected_index < len(table.rows_by_entity) && table.rows_by_entity[selected_index] >= 0 {
			return remove_editor_test_component(world, state, table.id)
		}
	}
	set_editor_test_diagnostic(state, "No component selected")
	return true
}

editor_test_component_addable_from_visible_chrome :: proc(component_id: string) -> bool {
	return component_id != "" && !strings.has_prefix(component_id, "scrapbot.")
}

editor_test_default_component_value :: proc(component_id: string, field: Runtime_Component_Field_Definition) -> Runtime_Component_Value {
	switch field.value_type {
	case .Boolean:
		switch component_id {
		case RENDERER_COMPONENT_ID:
			switch field.name {
			case "hdr", "postprocess_enabled", "bloom_enabled", "vignette_enabled", "chromatic_aberration_enabled":
				return runtime_component_value_boolean(true)
			}
		}
		return runtime_component_value_boolean(false)
	case .Int:
		if component_id == GEOMETRY_PRIMITIVE_COMPONENT_ID {
			switch field.name {
			case "segments":
				return runtime_component_value_int(16)
			case "rings":
				return runtime_component_value_int(8)
			}
		}
		return runtime_component_value_int(0)
	case .Float:
		if component_id == RENDERER_COMPONENT_ID {
			switch field.name {
			case "bloom_threshold":
				return runtime_component_value_float(0.85)
			case "bloom_intensity":
				return runtime_component_value_float(0.12)
			case "bloom_radius":
				return runtime_component_value_float(1.0)
			case "vignette_strength":
				return runtime_component_value_float(0.24)
			case "vignette_radius":
				return runtime_component_value_float(0.82)
			case "chromatic_aberration_strength":
				return runtime_component_value_float(0.0025)
			}
		}
		return runtime_component_value_float(0.0)
	case .Vec3:
		switch component_id {
		case TRANSFORM_COMPONENT_ID:
			if field.name == "scale" {
				return runtime_component_value_vec3({1.0, 1.0, 1.0})
			}
		case CUBE_RENDERER_COMPONENT_ID:
			if field.name == "color" {
				return runtime_component_value_vec3({1.0, 1.0, 1.0})
			}
		case SURFACE_MATERIAL_COMPONENT_ID:
			if field.name == "base_color" {
				return runtime_component_value_vec3({1.0, 1.0, 1.0})
			}
		}
		return runtime_component_value_vec3({0.0, 0.0, 0.0})
	case .String:
		switch component_id {
		case GEOMETRY_PRIMITIVE_COMPONENT_ID:
			if field.name == "primitive" {
				return runtime_component_value_string("box")
			}
		case RENDERER_COMPONENT_ID:
			switch field.name {
			case "tone_mapping":
				return runtime_component_value_string("aces")
			case "antialiasing":
				return runtime_component_value_string("fxaa")
			}
		case "scrapbot.ui.canvas":
			if field.name == "scale_mode" {
				return runtime_component_value_string("none")
			}
		case "scrapbot.ui.layout.item":
			if field.name == "align" {
				return runtime_component_value_string("start")
			}
		}
		return runtime_component_value_string("")
	}
	return Runtime_Component_Value{}
}

clear_editor_test_selection :: proc(state: ^Editor_Test_Input_State) {
	state.selected_entity = {}
	state.has_selected_entity = false
	state.has_selected_property = false
	state.selected_property_component = ""
	state.selected_property_field = ""
	state.selected_property_lane = 0
	clear_editor_test_text_input(state)
	clear_editor_test_diagnostic(state)
}

set_editor_test_clipboard :: proc(state: ^Editor_Test_Input_State, text: string) -> bool {
	state.clipboard_buffer = {}
	count := min_int(len(text), len(state.clipboard_buffer) - 1)
	for index := 0; index < count; index += 1 {
		state.clipboard_buffer[index] = text[index]
	}
	state.clipboard_len = count
	state.clipboard_changed = true
	return true
}

editor_test_clipboard_text :: proc(state: ^Editor_Test_Input_State) -> string {
	return string(state.clipboard_buffer[:state.clipboard_len])
}

editor_test_text_input_move_cursor :: proc(state: ^Editor_Test_Input_State, cursor: int, select_range: bool) {
	next := clamp_int(cursor, 0, state.text_input_len)
	state.text_input_cursor = next
	if !select_range {
		state.text_input_selection_anchor = next
	}
}

editor_test_text_input_backspace :: proc(state: ^Editor_Test_Input_State) {
	if editor_test_text_input_has_selection(state^) {
		editor_test_text_input_delete_selection(state)
		return
	}
	if state.text_input_cursor <= 0 {
		return
	}
	start := state.text_input_cursor - 1
	copy(state.text_input_buffer[start:], state.text_input_buffer[state.text_input_cursor:state.text_input_len])
	state.text_input_len -= 1
	state.text_input_cursor = start
	state.text_input_selection_anchor = start
	clear_editor_test_text_input_tail(state)
}

editor_test_text_input_delete :: proc(state: ^Editor_Test_Input_State) {
	if editor_test_text_input_has_selection(state^) {
		editor_test_text_input_delete_selection(state)
		return
	}
	if state.text_input_cursor >= state.text_input_len {
		return
	}
	copy(state.text_input_buffer[state.text_input_cursor:], state.text_input_buffer[state.text_input_cursor + 1:state.text_input_len])
	state.text_input_len -= 1
	state.text_input_selection_anchor = state.text_input_cursor
	clear_editor_test_text_input_tail(state)
}

editor_test_text_input_insert :: proc(state: ^Editor_Test_Input_State, value: string) {
	editor_test_text_input_delete_selection(state)
	for index := 0; index < len(value); index += 1 {
		if state.text_input_len >= len(state.text_input_buffer) {
			break
		}
		for index := state.text_input_len; index > state.text_input_cursor; index -= 1 {
			state.text_input_buffer[index] = state.text_input_buffer[index - 1]
		}
		state.text_input_buffer[state.text_input_cursor] = value[index]
		state.text_input_len += 1
		state.text_input_cursor += 1
		state.text_input_selection_anchor = state.text_input_cursor
	}
}

editor_test_text_input_delete_selection :: proc(state: ^Editor_Test_Input_State) {
	if !editor_test_text_input_has_selection(state^) {
		return
	}
	start := min_int(state.text_input_cursor, state.text_input_selection_anchor)
	end := max_int(state.text_input_cursor, state.text_input_selection_anchor)
	copy(state.text_input_buffer[start:], state.text_input_buffer[end:state.text_input_len])
	state.text_input_len -= end - start
	state.text_input_cursor = start
	state.text_input_selection_anchor = start
	clear_editor_test_text_input_tail(state)
}

editor_test_text_input_has_selection :: proc(state: Editor_Test_Input_State) -> bool {
	return state.text_input_cursor != state.text_input_selection_anchor
}

clear_editor_test_text_input_tail :: proc(state: ^Editor_Test_Input_State) {
	for index := state.text_input_len; index < len(state.text_input_buffer); index += 1 {
		state.text_input_buffer[index] = 0
	}
}

ensure_editor_sidebar_widths :: proc(state: ^Editor_Test_Input_State, input: Frame_Input) {
	left := state.left_sidebar_width
	right := state.right_sidebar_width
	default_left, default_right := editor_side_widths(input.viewport_width)
	if left <= 0 {
		left = default_left
	}
	if right <= 0 {
		right = default_right
	}
	state.left_sidebar_width, state.right_sidebar_width = editor_clamped_side_widths(input.viewport_width, left, right)
}

drag_editor_splitter :: proc(state: ^Editor_Test_Input_State, input: Frame_Input) {
	if !state.has_last_pointer {
		state.last_pointer = input.pointer.position
		state.has_last_pointer = true
		return
	}
	delta_x := input.pointer.position[0] - state.last_pointer[0]
	state.last_pointer = input.pointer.position
	if delta_x == 0 {
		return
	}
	left := state.left_sidebar_width
	right := state.right_sidebar_width
	switch state.dragging_splitter {
	case .Left:
		left += delta_x
	case .Right:
		right -= delta_x
	case .None:
		return
	}
	state.left_sidebar_width, state.right_sidebar_width = editor_clamped_side_widths(input.viewport_width, left, right)
}

drag_editor_gizmo_axis :: proc(state: ^Editor_Test_Input_State, world: ^Runtime_World, input: Frame_Input) -> bool {
	if !state.has_selected_entity {
		return false
	}
	axis, axis_ok := editor_test_axis_vector(state.dragging_axis)
	if !axis_ok {
		return false
	}
	position, position_ok := editor_test_transform_position(world^, state.selected_entity)
	if !position_ok {
		return false
	}
	if !state.has_last_pointer {
		state.last_pointer = input.pointer.position
		state.has_last_pointer = true
		return true
	}
	camera, camera_ok := editor_test_input_camera_state(world^, input)
	if !camera_ok {
		state.last_pointer = input.pointer.position
		return false
	}
	origin_screen, origin_ok := editor_test_project_world_to_screen(position, camera, input)
	end_screen, end_ok := editor_test_project_world_to_screen(editor_test_add_vec3(position, editor_test_scale_vec3(axis, EDITOR_TEST_GIZMO_AXIS_LENGTH)), camera, input)
	if !origin_ok || !end_ok {
		state.last_pointer = input.pointer.position
		return false
	}
	axis_screen_delta := [2]f32{end_screen[0] - origin_screen[0], end_screen[1] - origin_screen[1]}
	axis_screen_length := editor_test_vec2_length(axis_screen_delta)
	if axis_screen_length < 0.001 {
		state.last_pointer = input.pointer.position
		return false
	}
	axis_screen := [2]f32{axis_screen_delta[0] / axis_screen_length, axis_screen_delta[1] / axis_screen_length}
	pointer_delta := [2]f32{input.pointer.position[0] - state.last_pointer[0], input.pointer.position[1] - state.last_pointer[1]}
	projected_pixels := pointer_delta[0] * axis_screen[0] + pointer_delta[1] * axis_screen[1]
	camera_distance := editor_test_vec3_length(editor_test_subtract_vec3(position, camera.position))
	units_per_pixel := max_f32(camera_distance, 1.0) * 0.0025
	world_delta := projected_pixels * units_per_pixel
	next_position := editor_test_add_vec3(position, editor_test_scale_vec3(axis, world_delta))
	set_err := runtime_world_set_component_field_value(world, state.selected_entity, TRANSFORM_COMPONENT_ID, "position", runtime_component_value_vec3(next_position))
	state.last_pointer = input.pointer.position
	return set_err == .None
}

begin_editor_gizmo_drag :: proc(state: ^Editor_Test_Input_State, world: Runtime_World) {
	clear_editor_gizmo_drag(state)
	if !state.has_selected_entity {
		return
	}
	position, position_ok := editor_test_transform_position(world, state.selected_entity)
	if !position_ok {
		return
	}
	state.gizmo_drag_start_position = position
	state.has_gizmo_drag_start_position = true
}

finish_editor_gizmo_drag :: proc(state: ^Editor_Test_Input_State, world: ^Runtime_World) -> bool {
	if !state.has_selected_entity || !state.has_gizmo_drag_start_position {
		return false
	}
	next_position, next_ok := editor_test_transform_position(world^, state.selected_entity)
	if !next_ok {
		return false
	}
	old_value := runtime_component_value_vec3(state.gizmo_drag_start_position)
	new_value := runtime_component_value_vec3(next_position)
	if editor_test_component_values_equal(old_value, new_value) {
		return true
	}
	lane := editor_test_axis_lane(state.dragging_axis)
	if !push_editor_test_field_command(&state.undo_stack, &state.undo_len, state.selected_entity, TRANSFORM_COMPONENT_ID, "position", lane, old_value, new_value) {
		return false
	}
	clear_editor_test_field_command_stack(&state.redo_stack, &state.redo_len)
	set_editor_test_pending_scene_edit(state, state.selected_entity, TRANSFORM_COMPONENT_ID, "position", lane, old_value, new_value)
	state.selected_property_component = TRANSFORM_COMPONENT_ID
	state.selected_property_field = "position"
	state.selected_property_lane = lane
	state.has_selected_property = true
	clear_editor_test_text_input(state)
	clear_editor_test_diagnostic(state)
	return true
}

clear_editor_gizmo_drag :: proc(state: ^Editor_Test_Input_State) {
	state.gizmo_drag_start_position = {}
	state.has_gizmo_drag_start_position = false
}

Editor_Test_Camera_State :: struct {
	position:      [3]f32,
	rotation:      [3]f32,
	fov_y_degrees: f32,
	near:          f32,
	far:           f32,
}

editor_gizmo_axis_at_pointer :: proc(world: Runtime_World, state: Editor_Test_Input_State, input: Frame_Input) -> (Editor_Test_Axis, bool) {
	if !input.pointer.has_position || !state.has_selected_entity || !editor_pointer_in_game_viewport(input) {
		return .None, false
	}
	position, position_ok := editor_test_transform_position(world, state.selected_entity)
	if !position_ok {
		return .None, false
	}
	camera, camera_ok := editor_test_input_camera_state(world, input)
	if !camera_ok {
		return .None, false
	}
	origin_screen, origin_ok := editor_test_project_world_to_screen(position, camera, input)
	if !origin_ok {
		return .None, false
	}
	best_axis := Editor_Test_Axis.None
	best_distance_sq := EDITOR_TEST_GIZMO_PICK_RADIUS_PX * EDITOR_TEST_GIZMO_PICK_RADIUS_PX
	axes := [?]Editor_Test_Axis{.X, .Y, .Z}
	for axis in axes {
		vector, vector_ok := editor_test_axis_vector(axis)
		if !vector_ok {
			continue
		}
		end_screen, end_ok := editor_test_project_world_to_screen(editor_test_add_vec3(position, editor_test_scale_vec3(vector, EDITOR_TEST_GIZMO_AXIS_LENGTH)), camera, input)
		if !end_ok {
			continue
		}
		distance_sq := editor_test_distance_point_to_segment_sq(input.pointer.position, origin_screen, end_screen)
		if distance_sq < best_distance_sq {
			best_distance_sq = distance_sq
			best_axis = axis
		}
	}
	if best_axis == .None {
		return .None, false
	}
	return best_axis, true
}

editor_test_transform_position :: proc(world: Runtime_World, entity: Entity_Handle) -> ([3]f32, bool) {
	value, err := runtime_world_get_component_field_value(world, entity, TRANSFORM_COMPONENT_ID, "position")
	if err != .None || value.value_type != .Vec3 {
		return {}, false
	}
	return value.vec3, true
}

editor_test_camera_state :: proc(world: Runtime_World) -> (Editor_Test_Camera_State, bool) {
	query := [?]string{TRANSFORM_COMPONENT_ID, CAMERA_COMPONENT_ID}
	cursor := 0
	entity, found := runtime_world_query_next(world, query[:], &cursor)
	if !found {
		return Editor_Test_Camera_State{
			position = EDITOR_TEST_DEFAULT_CAMERA_POSITION,
			rotation = {},
			fov_y_degrees = EDITOR_TEST_DEFAULT_CAMERA_FOV_Y_DEGREES,
			near = EDITOR_TEST_DEFAULT_CAMERA_NEAR,
			far = EDITOR_TEST_DEFAULT_CAMERA_FAR,
		}, true
	}
	position, position_ok := editor_test_transform_position(world, entity)
	if !position_ok {
		return {}, false
	}
	rotation, rotation_ok := editor_test_transform_vec3_field(world, entity, "rotation")
	fov, fov_ok := editor_test_float_field(world, entity, CAMERA_COMPONENT_ID, "fov_y_degrees")
	near, near_ok := editor_test_float_field(world, entity, CAMERA_COMPONENT_ID, "near")
	far, far_ok := editor_test_float_field(world, entity, CAMERA_COMPONENT_ID, "far")
	if !rotation_ok || !fov_ok || !near_ok || !far_ok || fov <= 0 || near <= 0 || far <= near {
		return {}, false
	}
	return Editor_Test_Camera_State{position = position, rotation = rotation, fov_y_degrees = fov, near = near, far = far}, true
}

editor_test_input_camera_state :: proc(world: Runtime_World, input: Frame_Input) -> (Editor_Test_Camera_State, bool) {
	if input.camera_override_enabled {
		camera := input.camera_override
		if camera.fov_y_degrees > 0 && camera.near > 0 && camera.far > camera.near {
			return camera, true
		}
		return {}, false
	}
	return editor_test_camera_state(world)
}

editor_test_transform_vec3_field :: proc(world: Runtime_World, entity: Entity_Handle, field_name: string) -> ([3]f32, bool) {
	value, err := runtime_world_get_component_field_value(world, entity, TRANSFORM_COMPONENT_ID, field_name)
	if err != .None || value.value_type != .Vec3 {
		return {}, false
	}
	return value.vec3, true
}

editor_test_float_field :: proc(world: Runtime_World, entity: Entity_Handle, component_id, field_name: string) -> (f32, bool) {
	value, err := runtime_world_get_component_field_value(world, entity, component_id, field_name)
	if err != .None || value.value_type != .Float {
		return 0, false
	}
	return value.float, true
}

editor_test_project_world_to_screen :: proc(position: [3]f32, camera: Editor_Test_Camera_State, input: Frame_Input) -> ([2]f32, bool) {
	viewport_x, viewport_y, viewport_width, viewport_height := editor_game_viewport(input.viewport_width, input.viewport_height)
	if viewport_width <= 0 || viewport_height <= 0 {
		return {}, false
	}
	view := editor_test_camera_view_matrix(camera)
	projection := editor_test_perspective_matrix(camera.fov_y_degrees * math.PI / 180.0, viewport_width / viewport_height, camera.near, camera.far)
	clip := editor_test_transform_point(editor_test_mat_mul(projection, view), {position[0], position[1], position[2], 1.0})
	if clip[3] > -0.00001 && clip[3] < 0.00001 {
		return {}, false
	}
	ndc_x := clip[0] / clip[3]
	ndc_y := clip[1] / clip[3]
	return {
		viewport_x + (ndc_x + 1.0) * 0.5 * viewport_width,
		viewport_y + (1.0 - ndc_y) * 0.5 * viewport_height,
	}, true
}

editor_test_axis_vector :: proc(axis: Editor_Test_Axis) -> ([3]f32, bool) {
	switch axis {
	case .X:
		return {1.0, 0.0, 0.0}, true
	case .Y:
		return {0.0, 1.0, 0.0}, true
	case .Z:
		return {0.0, 0.0, 1.0}, true
	case .None:
		return {}, false
	}
	return {}, false
}

editor_test_axis_lane :: proc(axis: Editor_Test_Axis) -> int {
	switch axis {
	case .X:
		return 0
	case .Y:
		return 1
	case .Z:
		return 2
	case .None:
		return 0
	}
	return 0
}

editor_test_add_vec3 :: proc(left, right: [3]f32) -> [3]f32 {
	return {left[0] + right[0], left[1] + right[1], left[2] + right[2]}
}

editor_test_subtract_vec3 :: proc(left, right: [3]f32) -> [3]f32 {
	return {left[0] - right[0], left[1] - right[1], left[2] - right[2]}
}

editor_test_scale_vec3 :: proc(value: [3]f32, scale: f32) -> [3]f32 {
	return {value[0] * scale, value[1] * scale, value[2] * scale}
}

editor_test_vec3_length :: proc(value: [3]f32) -> f32 {
	return f32(math.sqrt(f64(value[0] * value[0] + value[1] * value[1] + value[2] * value[2])))
}

editor_test_vec2_length :: proc(value: [2]f32) -> f32 {
	return f32(math.sqrt(f64(value[0] * value[0] + value[1] * value[1])))
}

editor_test_distance_point_to_segment_sq :: proc(point, start, end: [2]f32) -> f32 {
	segment := [2]f32{end[0] - start[0], end[1] - start[1]}
	length_sq := segment[0] * segment[0] + segment[1] * segment[1]
	if length_sq <= 0.00001 {
		return editor_test_distance_sq(point, start)
	}
	point_delta := [2]f32{point[0] - start[0], point[1] - start[1]}
	t := (point_delta[0] * segment[0] + point_delta[1] * segment[1]) / length_sq
	t = clamp_f32(t, 0, 1)
	closest := [2]f32{start[0] + segment[0] * t, start[1] + segment[1] * t}
	return editor_test_distance_sq(point, closest)
}

editor_test_distance_sq :: proc(left, right: [2]f32) -> f32 {
	dx := left[0] - right[0]
	dy := left[1] - right[1]
	return dx * dx + dy * dy
}

editor_test_camera_view_matrix :: proc(camera: Editor_Test_Camera_State) -> [16]f32 {
	inverse_translation := editor_test_translation_matrix(-camera.position[0], -camera.position[1], -camera.position[2])
	return editor_test_mat_mul(
		editor_test_rotation_x_matrix(-camera.rotation[0]),
		editor_test_mat_mul(
			editor_test_rotation_y_matrix(-camera.rotation[1]),
			editor_test_mat_mul(editor_test_rotation_z_matrix(-camera.rotation[2]), inverse_translation),
		),
	)
}

editor_test_perspective_matrix :: proc(fovy_radians, aspect, near, far: f32) -> [16]f32 {
	f := 1.0 / f32(math.tan(f64(fovy_radians * 0.5)))
	return {
		f / aspect, 0.0, 0.0,                       0.0,
		0.0,        f,   0.0,                       0.0,
		0.0,        0.0, far / (near - far),        -1.0,
		0.0,        0.0, (far * near) / (near - far), 0.0,
	}
}

editor_test_translation_matrix :: proc(x, y, z: f32) -> [16]f32 {
	return {
		1.0, 0.0, 0.0, 0.0,
		0.0, 1.0, 0.0, 0.0,
		0.0, 0.0, 1.0, 0.0,
		x,   y,   z,   1.0,
	}
}

editor_test_rotation_x_matrix :: proc(angle: f32) -> [16]f32 {
	c := f32(math.cos(f64(angle)))
	s := f32(math.sin(f64(angle)))
	return {
		1.0, 0.0, 0.0, 0.0,
		0.0, c,   s,   0.0,
		0.0, -s,  c,   0.0,
		0.0, 0.0, 0.0, 1.0,
	}
}

editor_test_rotation_y_matrix :: proc(angle: f32) -> [16]f32 {
	c := f32(math.cos(f64(angle)))
	s := f32(math.sin(f64(angle)))
	return {
		c,   0.0, -s,  0.0,
		0.0, 1.0, 0.0, 0.0,
		s,   0.0, c,   0.0,
		0.0, 0.0, 0.0, 1.0,
	}
}

editor_test_rotation_z_matrix :: proc(angle: f32) -> [16]f32 {
	c := f32(math.cos(f64(angle)))
	s := f32(math.sin(f64(angle)))
	return {
		c,   s,   0.0, 0.0,
		-s,  c,   0.0, 0.0,
		0.0, 0.0, 1.0, 0.0,
		0.0, 0.0, 0.0, 1.0,
	}
}

editor_test_transform_point :: proc(m: [16]f32, point: [4]f32) -> [4]f32 {
	return {
		m[0] * point[0] + m[4] * point[1] + m[8] * point[2] + m[12] * point[3],
		m[1] * point[0] + m[5] * point[1] + m[9] * point[2] + m[13] * point[3],
		m[2] * point[0] + m[6] * point[1] + m[10] * point[2] + m[14] * point[3],
		m[3] * point[0] + m[7] * point[1] + m[11] * point[2] + m[15] * point[3],
	}
}

editor_test_mat_mul :: proc(a, b: [16]f32) -> [16]f32 {
	out: [16]f32
	for column := 0; column < 4; column += 1 {
		for row := 0; row < 4; row += 1 {
			sum := f32(0)
			for k := 0; k < 4; k += 1 {
				sum += a[k * 4 + row] * b[column * 4 + k]
			}
			out[column * 4 + row] = sum
		}
	}
	return out
}

editor_pointer_in_game_viewport :: proc(input: Frame_Input) -> bool {
	x, y, width, height := editor_game_viewport(input.viewport_width, input.viewport_height)
	return input.pointer.position[0] >= x &&
	       input.pointer.position[1] >= y &&
	       input.pointer.position[0] < x + width &&
	       input.pointer.position[1] < y + height
}

editor_pointer_in_play_button :: proc(input: Frame_Input) -> bool {
	x, y, width, height := editor_play_button_rect(input.viewport_width)
	return editor_pointer_in_rect(input, x, y, width, height)
}

editor_pointer_in_step_button :: proc(input: Frame_Input) -> bool {
	play_x, play_y, play_width, play_height := editor_play_button_rect(input.viewport_width)
	return editor_pointer_in_rect(input, play_x + play_width + UI_EDITOR_CONTROL_BUTTON_GAP, play_y, play_width, play_height)
}

editor_pointer_in_spawn_entity_button :: proc(input: Frame_Input) -> bool {
	x, y, width, height := editor_entity_spawn_button_rect(input.viewport_width, input.viewport_height)
	return editor_pointer_in_rect(input, x, y, width, height)
}

editor_pointer_in_despawn_entity_button :: proc(input: Frame_Input) -> bool {
	x, y, width, height := editor_entity_despawn_button_rect(input.viewport_width, input.viewport_height)
	return editor_pointer_in_rect(input, x, y, width, height)
}

editor_pointer_in_add_component_button :: proc(input: Frame_Input) -> bool {
	x, y, width, height := editor_component_add_button_rect(input.viewport_width, input.viewport_height)
	return editor_pointer_in_rect(input, x, y, width, height)
}

editor_pointer_in_remove_component_button :: proc(input: Frame_Input) -> bool {
	x, y, width, height := editor_component_remove_button_rect(input.viewport_width, input.viewport_height)
	return editor_pointer_in_rect(input, x, y, width, height)
}

editor_pointer_in_selected_entity_header :: proc(state: Editor_Test_Input_State, input: Frame_Input) -> bool {
	if !input.pointer.has_position || !state.has_selected_entity {
		return false
	}
	x, y, width, height := editor_selected_entity_header_rect(input.viewport_width, input.viewport_height)
	return editor_pointer_in_rect(input, x, y, width, height)
}

editor_play_button_rect :: proc(window_width: f32) -> (x, y, width, height: f32) {
	body_width := max_f32(window_width, 1)
	return max_f32(body_width - UI_EDITOR_PANEL_PADDING_X - UI_EDITOR_CONTROL_BUTTON_WIDTH * 2 - UI_EDITOR_CONTROL_BUTTON_GAP, UI_EDITOR_PANEL_PADDING_X),
	       (UI_EDITOR_TOP_BAR_HEIGHT - UI_EDITOR_CONTROL_BUTTON_HEIGHT) * 0.5,
	       UI_EDITOR_CONTROL_BUTTON_WIDTH,
	       UI_EDITOR_CONTROL_BUTTON_HEIGHT
}

editor_entity_spawn_button_rect :: proc(window_width, window_height: f32) -> (x, y, width, height: f32) {
	panel_x, panel_y, panel_width, _ := editor_entity_panel_rect(window_width, window_height)
	width = 44.0
	height = 28.0
	x = panel_x + max_f32(panel_width - UI_EDITOR_PANEL_PADDING_X - width * 2.0 - 8.0, UI_EDITOR_PANEL_PADDING_X)
	y = panel_y + max_f32((editor_system_rows_y_offset() - height) * 0.5, 4.0)
	return
}

editor_entity_despawn_button_rect :: proc(window_width, window_height: f32) -> (x, y, width, height: f32) {
	spawn_x, spawn_y, spawn_width, spawn_height := editor_entity_spawn_button_rect(window_width, window_height)
	return spawn_x + spawn_width + 8.0, spawn_y, spawn_width, spawn_height
}

editor_component_add_button_rect :: proc(window_width, window_height: f32) -> (x, y, width, height: f32) {
	panel_x, panel_y, panel_width, _ := editor_right_sidebar_panel_rect(window_width, window_height)
	width = 44.0
	height = 28.0
	x = panel_x + max_f32(panel_width - UI_EDITOR_PANEL_PADDING_X - width * 2.0 - 8.0, UI_EDITOR_PANEL_PADDING_X)
	y = panel_y + max_f32((editor_system_rows_y_offset() - height) * 0.5, 4.0)
	return
}

editor_component_remove_button_rect :: proc(window_width, window_height: f32) -> (x, y, width, height: f32) {
	add_x, add_y, add_width, add_height := editor_component_add_button_rect(window_width, window_height)
	return add_x + add_width + 8.0, add_y, add_width, add_height
}

editor_selected_entity_header_rect :: proc(window_width, window_height: f32) -> (x, y, width, height: f32) {
	panel_x, panel_y, _, _ := editor_right_sidebar_panel_rect(window_width, window_height)
	button_x, _, _, _ := editor_component_add_button_rect(window_width, window_height)
	x = panel_x + UI_EDITOR_PANEL_PADDING_X
	y = panel_y + UI_EDITOR_PANEL_PADDING_Y
	width = max_f32(button_x - x - 8.0, 1.0)
	height = UI_EDITOR_TEXT_HEIGHT
	return
}

editor_entity_at_pointer :: proc(world: Runtime_World, state: Editor_Test_Input_State, input: Frame_Input) -> (Entity_Handle, bool) {
	if !input.pointer.has_position || runtime_world_entity_count(world) == 0 {
		return Entity_Handle{}, false
	}
	clip_x, clip_y, clip_width, clip_height := editor_entity_list_clip_rect(world, input)
	if !editor_pointer_in_rect(input, clip_x, clip_y, clip_width, clip_height) {
		return Entity_Handle{}, false
	}
	row_index := int((input.pointer.position[1] - clip_y - UI_EDITOR_ENTITY_CARD_PADDING_Y + 8.0 + state_entity_scroll_y(state)) / UI_EDITOR_ENTITY_ROW_STRIDE)
	if row_index < 0 || row_index >= runtime_world_entity_count(world) {
		return Entity_Handle{}, false
	}
	entity, err := runtime_world_entity(world, Entity_Handle{index = u32(row_index)})
	if err != .None {
		return Entity_Handle{}, false
	}
	return Entity_Handle{index = u32(row_index), generation = entity.generation}, true
}

editor_splitter_at_pointer :: proc(state: Editor_Test_Input_State, input: Frame_Input) -> (Editor_Test_Splitter, bool) {
	if !input.pointer.has_position {
		return .None, false
	}
	x, y, width, height := editor_left_splitter_hit_rect(state, input)
	if editor_pointer_in_rect(input, x, y, width, height) {
		return .Left, true
	}
	x, y, width, height = editor_right_splitter_hit_rect(state, input)
	if editor_pointer_in_rect(input, x, y, width, height) {
		return .Right, true
	}
	return .None, false
}

editor_inspector_property_at_pointer :: proc(world: Runtime_World, state: Editor_Test_Input_State, input: Frame_Input) -> (component_id, field_name: string, lane: int, ok: bool) {
	if !input.pointer.has_position || !state.has_selected_entity {
		return "", "", 0, false
	}
	selected_index, selected_err := runtime_world_entity_index(world, state.selected_entity)
	if selected_err != .None {
		return "", "", 0, false
	}
	clip_x, clip_y, clip_width, clip_height := editor_inspector_scroll_clip_rect(input)
	if !editor_pointer_in_rect(input, clip_x, clip_y, clip_width, clip_height) {
		return "", "", 0, false
	}
	content_y := -state.inspector_scroll_y
	component_index := 0
	for table in world.component_tables {
		if selected_index >= len(table.rows_by_entity) || table.rows_by_entity[selected_index] < 0 {
			continue
		}
		if component_index > 0 {
			content_y += UI_EDITOR_INSPECTOR_CARD_GAP * 2 + UI_EDITOR_INSPECTOR_SEPARATOR_HEIGHT
		}
		field_start_y := UI_EDITOR_INSPECTOR_CARD_PADDING_Y + UI_EDITOR_TEXT_HEIGHT + UI_EDITOR_PANEL_LABEL_GAP
		for column, field_index in table.columns {
			field_y := clip_y + content_y + field_start_y + f32(field_index) * UI_EDITOR_INSPECTOR_FIELD_ROW_STRIDE
			row_y := field_y + UI_EDITOR_INSPECTOR_FIELD_CONTROL_OFFSET_Y - UI_EDITOR_INSPECTOR_INPUT_CELL_PADDING
			if editor_pointer_in_rect(input, clip_x, row_y, clip_width, UI_EDITOR_INSPECTOR_FIELD_ROW_HEIGHT) {
				value, value_err := runtime_world_get_component_field_value(world, state.selected_entity, table.id, column.name)
				if value_err != .None {
					return "", "", 0, false
				}
				value_x, value_width := editor_inspector_value_rect(clip_width)
				lane := editor_inspector_vec3_lane_at_pointer(value, column.name, input.pointer.position[0], clip_x + value_x + UI_EDITOR_INSPECTOR_INPUT_CELL_PADDING, max_f32(value_width - UI_EDITOR_INSPECTOR_INPUT_CELL_PADDING * 2.0, 1.0))
				return table.id, column.name, lane, true
			}
		}
		content_y += editor_inspector_component_card_height(len(table.columns))
		component_index += 1
	}
	return "", "", 0, false
}

editor_inspector_value_rect :: proc(card_width: f32) -> (x, width: f32) {
	row_width := max_f32(card_width - UI_EDITOR_INSPECTOR_CARD_PADDING_X * 2.0, 1.0)
	available := max_f32(row_width - UI_EDITOR_INSPECTOR_FIELD_COLUMN_GAP, 0.0)
	column_width := max_f32(available * 0.5, UI_EDITOR_INSPECTOR_COLUMN_MIN_WIDTH)
	return UI_EDITOR_INSPECTOR_CARD_PADDING_X + column_width + UI_EDITOR_INSPECTOR_FIELD_COLUMN_GAP, column_width
}

editor_inspector_vec3_lane_at_pointer :: proc(value: Runtime_Component_Value, field_name: string, pointer_x, value_screen_x, value_width: f32) -> int {
	if value.value_type != .Vec3 {
		return 0
	}
	is_color := editor_test_field_looks_like_color(field_name)
	child_count := f32(6.0)
	if is_color {
		child_count = 7.0
	}
	spacing_total := max_f32(child_count - 1.0, 0.0) * UI_EDITOR_INSPECTOR_INPUT_GAP
	swatch_total_width := f32(0)
	if is_color {
		swatch_total_width = UI_EDITOR_INSPECTOR_SWATCH_SIZE
	}
	lane_width := max_f32((value_width - swatch_total_width - UI_EDITOR_INSPECTOR_LANE_LABEL_WIDTH * 3.0 - spacing_total) / 3.0, 1.0)
	x := value_screen_x
	if is_color {
		if pointer_x < x + UI_EDITOR_INSPECTOR_SWATCH_SIZE + UI_EDITOR_INSPECTOR_INPUT_GAP {
			return 0
		}
		x += UI_EDITOR_INSPECTOR_SWATCH_SIZE + UI_EDITOR_INSPECTOR_INPUT_GAP
	}
	for lane := 0; lane < 3; lane += 1 {
		slot_end := x + UI_EDITOR_INSPECTOR_LANE_LABEL_WIDTH + UI_EDITOR_INSPECTOR_INPUT_GAP + lane_width
		if pointer_x < slot_end || lane == 2 {
			return lane
		}
		x = slot_end + UI_EDITOR_INSPECTOR_INPUT_GAP
	}
	return 2
}

editor_test_field_looks_like_color :: proc(field_name: string) -> bool {
	return strings.contains(field_name, "color") || strings.contains(field_name, "colour")
}

editor_left_splitter_hit_rect :: proc(state: Editor_Test_Input_State, input: Frame_Input) -> (x, y, width, height: f32) {
	body_y := UI_EDITOR_TOP_BAR_HEIGHT
	body_height := max_f32(input.viewport_height - UI_EDITOR_TOP_BAR_HEIGHT - UI_EDITOR_BOTTOM_BAR_HEIGHT, 1)
	visual_x := state.left_sidebar_width
	extra_width := max_f32(UI_EDITOR_SPLITTER_HIT_WIDTH - UI_EDITOR_SPLITTER_WIDTH, 0)
	return visual_x - extra_width * 0.5,
	       body_y,
	       UI_EDITOR_SPLITTER_WIDTH + extra_width,
	       body_height
}

editor_right_splitter_hit_rect :: proc(state: Editor_Test_Input_State, input: Frame_Input) -> (x, y, width, height: f32) {
	body_width := max_f32(input.viewport_width, 1)
	body_y := UI_EDITOR_TOP_BAR_HEIGHT
	body_height := max_f32(input.viewport_height - UI_EDITOR_TOP_BAR_HEIGHT - UI_EDITOR_BOTTOM_BAR_HEIGHT, 1)
	visual_x := body_width - state.right_sidebar_width - UI_EDITOR_SPLITTER_WIDTH
	extra_width := max_f32(UI_EDITOR_SPLITTER_HIT_WIDTH - UI_EDITOR_SPLITTER_WIDTH, 0)
	return visual_x - extra_width * 0.5,
	       body_y,
	       UI_EDITOR_SPLITTER_WIDTH + extra_width,
	       body_height
}

editor_pointer_in_system_list :: proc(input: Frame_Input) -> bool {
	if !input.pointer.has_position || editor_system_profile_scroll_count(input) == 0 {
		return false
	}
	clip_x, clip_y, clip_width, clip_height := editor_system_list_clip_rect(input)
	return editor_pointer_in_rect(input, clip_x, clip_y, clip_width, clip_height)
}

editor_system_scroll_next :: proc(input: Frame_Input, current_y, wheel_delta_y: f32) -> f32 {
	next := current_y + -wheel_delta_y * UI_EDITOR_SCROLL_PIXELS_PER_WHEEL
	return clamp_f32(next, 0, editor_system_max_scroll_y(input))
}

editor_pointer_in_inspector :: proc(world: Runtime_World, state: Editor_Test_Input_State, input: Frame_Input) -> bool {
	if !input.pointer.has_position || !state.has_selected_entity {
		return false
	}
	if editor_inspector_max_scroll_y(world, state, input) <= 0 {
		return false
	}
	clip_x, clip_y, clip_width, clip_height := editor_inspector_scroll_clip_rect(input)
	return editor_pointer_in_rect(input, clip_x, clip_y, clip_width, clip_height)
}

editor_inspector_scroll_next :: proc(world: Runtime_World, state: Editor_Test_Input_State, input: Frame_Input, current_y, wheel_delta_y: f32) -> f32 {
	if next, ok := editor_inspector_retained_scroll_next(world, state, input, current_y, wheel_delta_y); ok {
		return next
	}
	next := current_y + -wheel_delta_y * UI_EDITOR_SCROLL_PIXELS_PER_WHEEL
	return clamp_f32(next, 0, editor_inspector_max_scroll_y(world, state, input))
}

editor_inspector_retained_scroll_next :: proc(world: Runtime_World, state: Editor_Test_Input_State, input: Frame_Input, current_y, wheel_delta_y: f32) -> (f32, bool) {
	if wheel_delta_y == 0 {
		return current_y, true
	}
	routing_world, routing_ok := editor_inspector_routing_world(world, state, input, current_y)
	if !routing_ok {
		return current_y, false
	}
	defer runtime_world_free(&routing_world)
	clip_x, clip_y, clip_width, clip_height := editor_inspector_scroll_clip_rect(input)
	point := [2]f32{
		clamp_f32(input.pointer.position[0], clip_x, clip_x + max_f32(clip_width - 1.0, 0.0)),
		clamp_f32(input.pointer.position[1], clip_y, clip_y + max_f32(clip_height - 1.0, 0.0)),
	}
	consumed, scroll_err := apply_scroll_wheel_at(&routing_world, point, wheel_delta_y, UI_EDITOR_SCROLL_PIXELS_PER_WHEEL)
	if scroll_err != .None || !consumed {
		return current_y, false
	}
	scroll, scroll_found := runtime_world_find_entity_by_id(routing_world, "scrapbot.editor.inspector.scroll")
	if !scroll_found {
		return current_y, false
	}
	content_offset, offset_err := runtime_world_get_vec3(routing_world, scroll, UI_SCROLL_VIEW_COMPONENT_ID, "content_offset")
	if offset_err != .None {
		return current_y, false
	}
	return content_offset[1], true
}

editor_inspector_routing_world :: proc(world: Runtime_World, state: Editor_Test_Input_State, input: Frame_Input, scroll_y: f32) -> (Runtime_World, bool) {
	routing_world := runtime_world_init()
	clip_x, clip_y, clip_width, clip_height := editor_inspector_scroll_clip_rect(input)
	scroll, scroll_err := runtime_world_create_entity(&routing_world, "scrapbot.editor.inspector.scroll", "Editor Inspector Scroll View")
	if scroll_err != .None {
		runtime_world_free(&routing_world)
		return Runtime_World{}, false
	}
	scroll_fields := [?]Runtime_Component_Field_Value{
		{name = "position", value = runtime_component_value_vec3({clip_x, clip_y, 0.0})},
		{name = "size", value = runtime_component_value_vec3({clip_width, clip_height, 0.0})},
		{name = "content_offset", value = runtime_component_value_vec3({0.0, scroll_y, 0.0})},
	}
	if runtime_world_set_component(&routing_world, scroll, UI_SCROLL_VIEW_COMPONENT_ID, scroll_fields[:]) != .None {
		runtime_world_free(&routing_world)
		return Runtime_World{}, false
	}

	content_height := editor_inspector_component_content_height(world, state)
	stack, stack_err := runtime_world_create_entity(&routing_world, "scrapbot.editor.inspector.components", "Editor Component Stack")
	if stack_err != .None {
		runtime_world_free(&routing_world)
		return Runtime_World{}, false
	}
	stack_fields := [?]Runtime_Component_Field_Value{
		{name = "position", value = runtime_component_value_vec3({0.0, 0.0, 0.0})},
		{name = "size", value = runtime_component_value_vec3({max_f32(clip_width, 1.0), content_height, 0.0})},
		{name = "spacing", value = runtime_component_value_float(UI_EDITOR_INSPECTOR_CARD_GAP)},
		{name = "padding", value = runtime_component_value_vec3({0.0, 0.0, 0.0})},
	}
	if runtime_world_set_component(&routing_world, stack, UI_VGROUP_COMPONENT_ID, stack_fields[:]) != .None {
		runtime_world_free(&routing_world)
		return Runtime_World{}, false
	}
	layout_fields := [?]Runtime_Component_Field_Value{
		{name = "parent", value = runtime_component_value_string("scrapbot.editor.inspector.scroll")},
		{name = "order", value = runtime_component_value_int(0)},
		{name = "min_size", value = runtime_component_value_vec3({0.0, 0.0, 0.0})},
		{name = "preferred_size", value = runtime_component_value_vec3({0.0, 0.0, 0.0})},
		{name = "max_size", value = runtime_component_value_vec3({0.0, 0.0, 0.0})},
		{name = "grow", value = runtime_component_value_float(0.0)},
		{name = "shrink", value = runtime_component_value_float(0.0)},
		{name = "align", value = runtime_component_value_string("")},
		{name = "margin", value = runtime_component_value_vec3({0.0, 0.0, 0.0})},
	}
	if runtime_world_set_component(&routing_world, stack, UI_LAYOUT_ITEM_COMPONENT_ID, layout_fields[:]) != .None {
		runtime_world_free(&routing_world)
		return Runtime_World{}, false
	}
	return routing_world, true
}

editor_pointer_in_entity_list :: proc(world: Runtime_World, input: Frame_Input) -> bool {
	if !input.pointer.has_position || runtime_world_entity_count(world) == 0 {
		return false
	}
	clip_x, clip_y, clip_width, clip_height := editor_entity_list_clip_rect(world, input)
	return editor_pointer_in_rect(input, clip_x, clip_y, clip_width, clip_height)
}

editor_entity_scroll_next :: proc(world: Runtime_World, input: Frame_Input, current_y, wheel_delta_y: f32) -> f32 {
	next := current_y + -wheel_delta_y * UI_EDITOR_SCROLL_PIXELS_PER_WHEEL
	return clamp_f32(next, 0, editor_entity_max_scroll_y(world, input))
}

editor_system_profile_scroll_count :: proc(input: Frame_Input) -> int {
	return max_int(input.system_profile_count_hint, 0)
}

state_entity_scroll_y :: proc(state: Editor_Test_Input_State) -> f32 {
	return state.entity_scroll_y
}

editor_system_list_clip_rect :: proc(input: Frame_Input) -> (x, y, width, height: f32) {
	panel_x, panel_y, panel_width, panel_height := editor_system_panel_rect(input.viewport_width, input.viewport_height)
	visible_rows := editor_system_visible_rows(panel_y, panel_height)
	scrollbar_space := f32(0)
	if editor_system_profile_scroll_count(input) > visible_rows {
		scrollbar_space = UI_EDITOR_SCROLLBAR_WIDTH + UI_EDITOR_SCROLLBAR_GAP
	}
	return panel_x,
	       panel_y + editor_system_rows_y_offset(),
	       max_f32(panel_width - scrollbar_space, 1),
	       editor_system_table_content_height(visible_rows)
}

editor_system_panel_rect :: proc(window_width, window_height: f32) -> (x, y, width, height: f32) {
	panel_x, panel_y, panel_width, panel_height := editor_left_sidebar_panel_rect(window_width, window_height)
	entity_height := editor_entity_panel_height(panel_height)
	return panel_x,
	       panel_y,
	       panel_width,
	       max_f32(panel_height - UI_EDITOR_LEFT_PANEL_GAP - entity_height, 1)
}

editor_entity_list_clip_rect :: proc(world: Runtime_World, input: Frame_Input) -> (x, y, width, height: f32) {
	panel_x, panel_y, panel_width, panel_height := editor_entity_panel_rect(input.viewport_width, input.viewport_height)
	visible_rows := editor_entity_visible_rows(panel_y, panel_height)
	scrollbar_space := f32(0)
	if runtime_world_entity_count(world) > visible_rows {
		scrollbar_space = UI_EDITOR_SCROLLBAR_WIDTH + UI_EDITOR_SCROLLBAR_GAP
	}
	return panel_x,
	       panel_y + editor_system_rows_y_offset(),
	       max_f32(panel_width - scrollbar_space, 1),
	       editor_entity_table_content_height(visible_rows)
}

editor_entity_panel_rect :: proc(window_width, window_height: f32) -> (x, y, width, height: f32) {
	sidebar_x, sidebar_y, sidebar_width, sidebar_height := editor_left_sidebar_panel_rect(window_width, window_height)
	entity_height := editor_entity_panel_height(sidebar_height)
	return sidebar_x,
	       sidebar_y + max_f32(sidebar_height - entity_height, 0),
	       sidebar_width,
	       entity_height
}

editor_left_sidebar_panel_rect :: proc(window_width, window_height: f32) -> (x, y, width, height: f32) {
	body_y := UI_EDITOR_TOP_BAR_HEIGHT
	body_height := max_f32(window_height - UI_EDITOR_TOP_BAR_HEIGHT - UI_EDITOR_BOTTOM_BAR_HEIGHT, 1)
	left, _ := editor_side_widths(window_width)
	return UI_EDITOR_SIDEBAR_PANEL_MARGIN,
	       body_y + UI_EDITOR_SIDEBAR_PANEL_MARGIN,
	       max_f32(left - UI_EDITOR_SIDEBAR_PANEL_MARGIN * 2, 1),
	       max_f32(body_height - UI_EDITOR_SIDEBAR_PANEL_MARGIN * 2, 1)
}

editor_right_sidebar_panel_rect :: proc(window_width, window_height: f32) -> (x, y, width, height: f32) {
	body_width := max_f32(window_width, 1)
	body_y := UI_EDITOR_TOP_BAR_HEIGHT
	body_height := max_f32(window_height - UI_EDITOR_TOP_BAR_HEIGHT - UI_EDITOR_BOTTOM_BAR_HEIGHT, 1)
	_, right := editor_side_widths(window_width)
	return max_f32(body_width - right + UI_EDITOR_SIDEBAR_PANEL_MARGIN, UI_EDITOR_SIDEBAR_PANEL_MARGIN),
	       body_y + UI_EDITOR_SIDEBAR_PANEL_MARGIN,
	       max_f32(right - UI_EDITOR_SIDEBAR_PANEL_MARGIN * 2, 1),
	       max_f32(body_height - UI_EDITOR_SIDEBAR_PANEL_MARGIN * 2, 1)
}

editor_entity_panel_height :: proc(total_height: f32) -> f32 {
	if total_height <= UI_EDITOR_LEFT_PANEL_GAP + 2 {
		return max_f32(total_height * 0.5, 1)
	}
	max_entity_height := max_f32(total_height * 0.5, 1)
	min_entity_height := min_f32(UI_EDITOR_ENTITY_PANEL_MIN_HEIGHT, max_entity_height)
	entity_height := clamp_f32(total_height * 0.4, min_entity_height, max_entity_height)
	min_system := min_f32(UI_EDITOR_SYSTEM_PANEL_MIN_HEIGHT, max_f32(total_height - UI_EDITOR_LEFT_PANEL_GAP - 1, 1))
	if total_height - UI_EDITOR_LEFT_PANEL_GAP - entity_height < min_system {
		entity_height = max_f32(total_height - UI_EDITOR_LEFT_PANEL_GAP - min_system, 1)
	}
	return entity_height
}

editor_system_visible_rows :: proc(panel_y, panel_height: f32) -> int {
	rows_y := panel_y + editor_system_rows_y_offset()
	rows_height := max_f32(panel_y + panel_height - rows_y - UI_EDITOR_PANEL_BOTTOM_PADDING - UI_EDITOR_SYSTEM_CARD_PADDING_Y * 2, UI_EDITOR_SYSTEM_ROW_STRIDE)
	rows := int(rows_height / UI_EDITOR_SYSTEM_ROW_STRIDE)
	if rows < 1 {
		return 1
	}
	return rows
}

editor_entity_visible_rows :: proc(panel_y, panel_height: f32) -> int {
	rows_y := panel_y + editor_system_rows_y_offset()
	rows_height := max_f32(panel_y + panel_height - rows_y - UI_EDITOR_PANEL_BOTTOM_PADDING - UI_EDITOR_ENTITY_CARD_PADDING_Y * 2, UI_EDITOR_ENTITY_ROW_STRIDE)
	rows := int(rows_height / UI_EDITOR_ENTITY_ROW_STRIDE)
	if rows < 1 {
		return 1
	}
	return rows
}

editor_system_max_scroll_y :: proc(input: Frame_Input) -> f32 {
	visible_rows := editor_system_visible_rows_from_input(input)
	profile_count := editor_system_profile_scroll_count(input)
	if profile_count <= visible_rows {
		return 0
	}
	return f32(profile_count - visible_rows) * UI_EDITOR_SYSTEM_ROW_STRIDE
}

editor_inspector_max_scroll_y :: proc(world: Runtime_World, state: Editor_Test_Input_State, input: Frame_Input) -> f32 {
	_, _, _, clip_height := editor_inspector_scroll_clip_rect(input)
	content_height := editor_inspector_component_content_height(world, state)
	if content_height <= clip_height {
		return 0
	}
	return content_height - clip_height
}

editor_entity_max_scroll_y :: proc(world: Runtime_World, input: Frame_Input) -> f32 {
	visible_rows := editor_entity_visible_rows_from_input(input)
	entity_count := runtime_world_entity_count(world)
	if entity_count <= visible_rows {
		return 0
	}
	return f32(entity_count - visible_rows) * UI_EDITOR_ENTITY_ROW_STRIDE
}

editor_system_visible_rows_from_input :: proc(input: Frame_Input) -> int {
	_, panel_y, _, panel_height := editor_system_panel_rect(input.viewport_width, input.viewport_height)
	return editor_system_visible_rows(panel_y, panel_height)
}

editor_entity_visible_rows_from_input :: proc(input: Frame_Input) -> int {
	_, panel_y, _, panel_height := editor_entity_panel_rect(input.viewport_width, input.viewport_height)
	return editor_entity_visible_rows(panel_y, panel_height)
}

editor_system_table_content_height :: proc(row_count: int) -> f32 {
	return UI_EDITOR_SYSTEM_CARD_PADDING_Y * 2 + f32(row_count) * UI_EDITOR_SYSTEM_ROW_STRIDE
}

editor_inspector_scroll_clip_rect :: proc(input: Frame_Input) -> (x, y, width, height: f32) {
	sidebar_x, sidebar_y, sidebar_width, sidebar_height := editor_right_sidebar_panel_rect(input.viewport_width, input.viewport_height)
	clip_y := sidebar_y + UI_EDITOR_PANEL_PADDING_Y + UI_EDITOR_INSPECTOR_LINE_STRIDE * 2.5
	return sidebar_x,
	       clip_y,
	       max_f32(sidebar_width, 1),
	       max_f32(sidebar_y + sidebar_height - clip_y, 1)
}

editor_inspector_component_content_height :: proc(world: Runtime_World, state: Editor_Test_Input_State) -> f32 {
	if !state.has_selected_entity {
		return 0
	}
	selected_index, selected_err := runtime_world_entity_index(world, state.selected_entity)
	if selected_err != .None {
		return 0
	}
	height := f32(0)
	component_count := 0
	for table in world.component_tables {
		if selected_index < len(table.rows_by_entity) && table.rows_by_entity[selected_index] >= 0 {
			if component_count > 0 {
				height += UI_EDITOR_INSPECTOR_CARD_GAP * 2 + UI_EDITOR_INSPECTOR_SEPARATOR_HEIGHT
			}
			height += editor_inspector_component_card_height(len(table.columns))
			component_count += 1
		}
	}
	return height
}

editor_inspector_component_card_height :: proc(field_count: int) -> f32 {
	return UI_EDITOR_INSPECTOR_CARD_PADDING_Y * 2 +
	       UI_EDITOR_TEXT_HEIGHT +
	       UI_EDITOR_PANEL_LABEL_GAP +
	       f32(field_count) * UI_EDITOR_INSPECTOR_FIELD_ROW_STRIDE
}

editor_entity_table_content_height :: proc(row_count: int) -> f32 {
	return UI_EDITOR_ENTITY_CARD_PADDING_Y * 2 + f32(row_count) * UI_EDITOR_ENTITY_ROW_STRIDE
}

editor_system_rows_y_offset :: proc() -> f32 {
	return UI_EDITOR_PANEL_PADDING_Y + UI_EDITOR_TEXT_HEIGHT + UI_EDITOR_PANEL_LABEL_GAP
}

editor_pointer_in_rect :: proc(input: Frame_Input, x, y, width, height: f32) -> bool {
	return input.pointer.position[0] >= x &&
	       input.pointer.position[1] >= y &&
	       input.pointer.position[0] < x + width &&
	       input.pointer.position[1] < y + height
}

max_int :: proc(left, right: int) -> int {
	if left > right {
		return left
	}
	return right
}

min_int :: proc(left, right: int) -> int {
	if left < right {
		return left
	}
	return right
}

clamp_int :: proc(value, minimum, maximum: int) -> int {
	return max_int(min_int(value, maximum), minimum)
}

clear_frame_pointer_actions :: proc(input: ^Frame_Input) {
	input.pointer.delta = {}
	input.pointer.primary_down = false
	input.pointer.primary_pressed = false
	input.pointer.primary_released = false
	input.pointer.secondary_down = false
	input.pointer.secondary_pressed = false
	input.pointer.secondary_released = false
	input.pointer.wheel_delta = {}
}

write_frame_input :: proc(world: ^Runtime_World, input: Frame_Input) -> Runtime_Error {
	handle, found := runtime_world_find_entity_by_id(world^, INPUT_ENTITY_ID)
	if !found {
		create_err: Runtime_Error
		handle, create_err = runtime_world_create_entity(world, INPUT_ENTITY_ID, "Input")
		if create_err != .None {
			return create_err
		}
	}

	pointer_fields := [?]Runtime_Component_Field_Value{
		{name = "position", value = Runtime_Component_Value{value_type = .Vec3, vec3 = {input.pointer.position[0], input.pointer.position[1], 0}}},
		{name = "delta", value = Runtime_Component_Value{value_type = .Vec3, vec3 = {input.pointer.delta[0], input.pointer.delta[1], 0}}},
		{name = "has_position", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.pointer.has_position}},
		{name = "primary_down", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.pointer.primary_down}},
		{name = "primary_pressed", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.pointer.primary_pressed}},
		{name = "primary_released", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.pointer.primary_released}},
		{name = "secondary_down", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.pointer.secondary_down}},
		{name = "secondary_pressed", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.pointer.secondary_pressed}},
		{name = "secondary_released", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.pointer.secondary_released}},
		{name = "wheel_delta", value = Runtime_Component_Value{value_type = .Vec3, vec3 = {input.pointer.wheel_delta[0], input.pointer.wheel_delta[1], 0}}},
	}
	err := runtime_world_set_component(world, handle, INPUT_POINTER_COMPONENT_ID, pointer_fields[:])
	if err != .None {
		return err
	}

	keyboard_fields := [?]Runtime_Component_Field_Value{
		{name = "ctrl_down", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.keyboard.ctrl_down}},
		{name = "shift_down", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.keyboard.shift_down}},
		{name = "alt_down", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.keyboard.alt_down}},
		{name = "super_down", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.keyboard.super_down}},
		{name = "move_forward", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.keyboard.move_forward}},
		{name = "move_back", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.keyboard.move_back}},
		{name = "move_left", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.keyboard.move_left}},
		{name = "move_right", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.keyboard.move_right}},
		{name = "move_up", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.keyboard.move_up}},
		{name = "move_down", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.keyboard.move_down}},
		{name = "editor_toggle_pressed", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.keyboard.editor_toggle_pressed}},
	}
	err = runtime_world_set_component(world, handle, INPUT_KEYBOARD_COMPONENT_ID, keyboard_fields[:])
	if err != .None {
		return err
	}

	frame_fields := [?]Runtime_Component_Field_Value{
		{name = "ui_visible", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.ui_visible}},
		{name = "debug_overlay_visible", value = Runtime_Component_Value{value_type = .Boolean, boolean = input.debug_overlay_visible}},
		{name = "viewport", value = Runtime_Component_Value{value_type = .Vec3, vec3 = {input.viewport_width, input.viewport_height, 0}}},
		{name = "pixel_scale", value = Runtime_Component_Value{value_type = .Float, float = input.pixel_scale}},
	}
	return runtime_world_set_component(world, handle, INPUT_FRAME_COMPONENT_ID, frame_fields[:])
}

step_input_for_frame :: proc(input_frames: []Step_Input_Frame, frame: int) -> Frame_Input {
	for input_frame in input_frames {
		if input_frame.frame == frame {
			return input_frame.input
		}
	}
	return frame_input_default()
}
