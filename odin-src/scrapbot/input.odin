package main

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
}

Frame_Input :: struct {
	pointer:                   Frame_Input_Pointer,
	keyboard:                  Frame_Input_Keyboard,
	ui_visible:                bool,
	debug_overlay_visible:     bool,
	viewport_width:            f32,
	viewport_height:           f32,
	pixel_scale:               f32,
	system_profile_count_hint: int,
}

Step_Input_Frame :: struct {
	frame: int,
	input: Frame_Input,
}

Editor_Test_Input_State :: struct {
	captured_pointer:    bool,
	paused:              bool,
	step_once:           bool,
	selected_entity:     Entity_Handle,
	has_selected_entity: bool,
	system_scroll_y:     f32,
	entity_scroll_y:     f32,
}

frame_input_default :: proc() -> Frame_Input {
	return Frame_Input{
		ui_visible = true,
		pixel_scale = 1.0,
	}
}

route_editor_test_input :: proc(state: ^Editor_Test_Input_State, world: Runtime_World, input: ^Frame_Input) {
	state.step_once = false
	if !input.debug_overlay_visible {
		state.captured_pointer = false
		return
	}
	consumed := false
	if input.pointer.has_position {
		inside_game := editor_pointer_in_game_viewport(input^)
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
			} else if selected, selected_ok := editor_entity_at_pointer(world, state^, input^); selected_ok {
				state.selected_entity = selected
				state.has_selected_entity = true
				state.captured_pointer = true
				consumed = true
			} else if !inside_game {
				state.captured_pointer = true
				consumed = true
			}
		}
		if input.pointer.primary_down && state.captured_pointer {
			consumed = true
		}
		if input.pointer.primary_released {
			if state.captured_pointer || !inside_game {
				consumed = true
			}
			state.captured_pointer = false
		}
		if input.pointer.secondary_pressed || input.pointer.secondary_down || input.pointer.secondary_released {
			if !inside_game {
				consumed = true
			}
		}
		if (input.pointer.wheel_delta[0] != 0 || input.pointer.wheel_delta[1] != 0) && !inside_game {
			if editor_pointer_in_system_list(input^) {
				state.system_scroll_y = editor_system_scroll_next(input^, state.system_scroll_y, input.pointer.wheel_delta[1])
			} else if editor_pointer_in_entity_list(world, input^) {
				state.entity_scroll_y = editor_entity_scroll_next(world, input^, state.entity_scroll_y, input.pointer.wheel_delta[1])
			}
			consumed = true
		}
	} else if input.pointer.primary_released {
		state.captured_pointer = false
	}
	if consumed {
		clear_frame_pointer_actions(input)
	}
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

editor_play_button_rect :: proc(window_width: f32) -> (x, y, width, height: f32) {
	body_width := max_f32(window_width, 1)
	return max_f32(body_width - UI_EDITOR_PANEL_PADDING_X - UI_EDITOR_CONTROL_BUTTON_WIDTH * 2 - UI_EDITOR_CONTROL_BUTTON_GAP, UI_EDITOR_PANEL_PADDING_X),
	       (UI_EDITOR_TOP_BAR_HEIGHT - UI_EDITOR_CONTROL_BUTTON_HEIGHT) * 0.5,
	       UI_EDITOR_CONTROL_BUTTON_WIDTH,
	       UI_EDITOR_CONTROL_BUTTON_HEIGHT
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
