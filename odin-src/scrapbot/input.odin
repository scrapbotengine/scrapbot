package main

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

EDITOR_TEST_TEXT_INPUT_BUFFER_LEN :: 128
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
	editor_backspace_pressed: bool,
	editor_delete_pressed: bool,
	editor_select_all_pressed: bool,
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
	text_input:                string,
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
	left_sidebar_width:          f32,
	right_sidebar_width:         f32,
	last_pointer:                [2]f32,
	has_last_pointer:            bool,
	text_input_active:           bool,
	text_input_component:        string,
	text_input_field:            string,
	text_input_lane:             int,
	text_input_buffer:           [EDITOR_TEST_TEXT_INPUT_BUFFER_LEN]u8,
	text_input_len:              int,
	text_input_cursor:           int,
	text_input_selection_anchor: int,
}

frame_input_default :: proc() -> Frame_Input {
	return Frame_Input{
		ui_visible = true,
		pixel_scale = 1.0,
	}
}

route_editor_test_input :: proc(state: ^Editor_Test_Input_State, world: ^Runtime_World, input: ^Frame_Input) {
	state.step_once = false
	if !input.debug_overlay_visible {
		state.captured_pointer = false
		return
	}
	consumed := false
	if apply_editor_test_keyboard_edits(state, world, input^) {
		consumed = true
	}
	if input.pointer.has_position {
		inside_game := editor_pointer_in_game_viewport(input^)
		ensure_editor_sidebar_widths(state, input^)
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
				state.captured_pointer = true
				consumed = true
			} else if component_id, field_name, lane, property_ok := editor_inspector_property_at_pointer(world^, state^, input^); property_ok {
				if state.text_input_active &&
				   (state.text_input_component != component_id || state.text_input_field != field_name || state.text_input_lane != lane) {
					commit_editor_test_text_input(world, state)
				}
				state.selected_property_component = component_id
				state.selected_property_field = field_name
				state.selected_property_lane = lane
				state.has_selected_property = true
				focus_editor_test_text_input(world^, state, component_id, field_name, lane)
				state.captured_pointer = true
				consumed = true
			} else if !inside_game {
				commit_editor_test_text_input(world, state)
				state.captured_pointer = true
				consumed = true
			} else if axis, axis_ok := editor_gizmo_axis_at_pointer(world^, state^, input^); axis_ok {
				commit_editor_test_text_input(world, state)
				state.dragging_axis = axis
				state.captured_pointer = true
				state.last_pointer = input.pointer.position
				state.has_last_pointer = true
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
			state.captured_pointer = false
			state.dragging_splitter = .None
			state.dragging_axis = .None
			state.has_last_pointer = false
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
		state.has_last_pointer = false
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

apply_editor_test_keyboard_edits :: proc(state: ^Editor_Test_Input_State, world: ^Runtime_World, input: Frame_Input) -> bool {
	if !state.text_input_active {
		return false
	}
	consumed := false
	if input.keyboard.editor_select_all_pressed {
		select_all_editor_test_text_input(state)
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
	return true
}

commit_editor_test_text_input :: proc(world: ^Runtime_World, state: ^Editor_Test_Input_State) -> bool {
	if !state.text_input_active || !state.has_selected_entity {
		return false
	}
	current, current_err := runtime_world_get_component_field_value(world^, state.selected_entity, state.text_input_component, state.text_input_field)
	if current_err != .None {
		clear_editor_test_text_input(state)
		return false
	}
	text := string(state.text_input_buffer[:state.text_input_len])
	next, parse_ok := editor_test_parse_input_value(current, text, state.text_input_lane)
	if !parse_ok {
		clear_editor_test_text_input(state)
		return false
	}
	set_err := runtime_world_set_component_field_value(world, state.selected_entity, state.text_input_component, state.text_input_field, next)
	clear_editor_test_text_input(state)
	return set_err == .None
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
	camera, camera_ok := editor_test_camera_state(world^)
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
	camera, camera_ok := editor_test_camera_state(world)
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
	next := current_y + -wheel_delta_y * UI_EDITOR_SCROLL_PIXELS_PER_WHEEL
	return clamp_f32(next, 0, editor_inspector_max_scroll_y(world, state, input))
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
