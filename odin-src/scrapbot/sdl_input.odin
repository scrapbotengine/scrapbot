package main

import sdl3 "vendor:sdl3"

Sdl_Input_State :: struct {
	pointer_position: [2]f32,
	has_pointer:      bool,
	primary_down:     bool,
	secondary_down:   bool,
	ctrl_down:        bool,
	shift_down:       bool,
	alt_down:         bool,
	super_down:       bool,
	move_forward:     bool,
	move_back:        bool,
	move_left:        bool,
	move_right:       bool,
	move_up:          bool,
	move_down:        bool,
	text_input_buffer: [EDITOR_TEST_TEXT_INPUT_BUFFER_LEN]u8,
	text_input_len:    int,
}

sdl_input_begin_frame :: proc(state: Sdl_Input_State, size: Sdl_Window_Size, editor_visible: bool) -> Frame_Input {
	input := frame_input_default()
	input.debug_overlay_visible = editor_visible
	input.viewport_width = f32(size.pixel_width)
	input.viewport_height = f32(size.pixel_height)
	if input.viewport_width <= 0 {
		input.viewport_width = f32(size.width)
	}
	if input.viewport_height <= 0 {
		input.viewport_height = f32(size.height)
	}
	input.pointer.position = state.pointer_position
	input.pointer.has_position = state.has_pointer
	input.pointer.primary_down = state.primary_down
	input.pointer.secondary_down = state.secondary_down
	input.keyboard.ctrl_down = state.ctrl_down
	input.keyboard.shift_down = state.shift_down
	input.keyboard.alt_down = state.alt_down
	input.keyboard.super_down = state.super_down
	input.keyboard.move_forward = state.move_forward
	input.keyboard.move_back = state.move_back
	input.keyboard.move_left = state.move_left
	input.keyboard.move_right = state.move_right
	input.keyboard.move_up = state.move_up
	input.keyboard.move_down = state.move_down
	return input
}

sdl_input_clear_text_input :: proc(state: ^Sdl_Input_State, input: ^Frame_Input) {
	state.text_input_buffer = {}
	state.text_input_len = 0
	input.text_input = ""
}

sdl_input_window_to_pixel_position :: proc(size: Sdl_Window_Size, x, y: f32) -> [2]f32 {
	scale_x := f32(1)
	scale_y := f32(1)
	if size.width > 0 && size.pixel_width > 0 {
		scale_x = f32(size.pixel_width) / f32(size.width)
	}
	if size.height > 0 && size.pixel_height > 0 {
		scale_y = f32(size.pixel_height) / f32(size.height)
	}
	return {x * scale_x, y * scale_y}
}

sdl_input_apply_mouse_motion :: proc(state: ^Sdl_Input_State, input: ^Frame_Input, size: Sdl_Window_Size, x, y, xrel, yrel: f32) {
	position := sdl_input_window_to_pixel_position(size, x, y)
	previous := state.pointer_position
	had_pointer := state.has_pointer
	state.pointer_position = position
	state.has_pointer = true
	input.pointer.position = position
	input.pointer.has_position = true
	if had_pointer {
		input.pointer.delta[0] += position[0] - previous[0]
		input.pointer.delta[1] += position[1] - previous[1]
	} else {
		relative := sdl_input_window_to_pixel_position(size, xrel, yrel)
		input.pointer.delta[0] += relative[0]
		input.pointer.delta[1] += relative[1]
	}
}

sdl_input_apply_mouse_button :: proc(state: ^Sdl_Input_State, input: ^Frame_Input, size: Sdl_Window_Size, button: sdl3.Uint8, down: bool, x, y: f32) {
	position := sdl_input_window_to_pixel_position(size, x, y)
	state.pointer_position = position
	state.has_pointer = true
	input.pointer.position = position
	input.pointer.has_position = true
	if button == sdl3.BUTTON_LEFT {
		state.primary_down = down
		input.pointer.primary_down = down
		if down {
			input.pointer.primary_pressed = true
		} else {
			input.pointer.primary_released = true
		}
	} else if button == sdl3.BUTTON_RIGHT {
		state.secondary_down = down
		input.pointer.secondary_down = down
		if down {
			input.pointer.secondary_pressed = true
		} else {
			input.pointer.secondary_released = true
		}
	}
}

sdl_input_apply_mouse_wheel :: proc(state: ^Sdl_Input_State, input: ^Frame_Input, size: Sdl_Window_Size, x, y, mouse_x, mouse_y: f32, direction: sdl3.MouseWheelDirection) {
	position := sdl_input_window_to_pixel_position(size, mouse_x, mouse_y)
	state.pointer_position = position
	state.has_pointer = true
	input.pointer.position = position
	input.pointer.has_position = true
	wheel_x := x
	wheel_y := y
	if direction == .FLIPPED {
		wheel_x = -wheel_x
		wheel_y = -wheel_y
	}
	input.pointer.wheel_delta[0] += wheel_x
	input.pointer.wheel_delta[1] += wheel_y
}

sdl_input_apply_text_input :: proc(state: ^Sdl_Input_State, input: ^Frame_Input, text: cstring) {
	if text == nil {
		return
	}
	bytes := cast([^]u8)text
	for index := 0; bytes[index] != 0; index += 1 {
		if state.text_input_len >= len(state.text_input_buffer) {
			break
		}
		state.text_input_buffer[state.text_input_len] = bytes[index]
		state.text_input_len += 1
	}
	if state.text_input_len > 0 {
		input.text_input = string(state.text_input_buffer[:state.text_input_len])
	}
}

sdl_input_apply_key :: proc(state: ^Sdl_Input_State, input: ^Frame_Input, scancode: sdl3.Scancode, down, repeat: bool) {
	if sdl_input_apply_modifier_key(state, scancode, down) {
		sdl_input_sync_keyboard_state(input, state^)
		return
	}
	#partial switch scancode {
	case .W:
		state.move_forward = down
	case .S:
		state.move_back = down
	case .A:
		state.move_left = down
	case .D:
		state.move_right = down
	case .E:
		state.move_up = down
	case .Q:
		state.move_down = down
	case .RETURN:
		input.keyboard.editor_enter_pressed = down && !repeat
	case .BACKSPACE:
		input.keyboard.editor_backspace_pressed = down && !repeat
	case .DELETE:
		input.keyboard.editor_delete_pressed = down && !repeat
	case .TAB:
		input.keyboard.editor_toggle_pressed = down && !repeat && state.ctrl_down
	case:
	}
	input.keyboard.editor_select_all_pressed = down && !repeat && scancode == .A && (state.ctrl_down || state.super_down)
	sdl_input_sync_keyboard_state(input, state^)
}

sdl_input_apply_modifier_key :: proc(state: ^Sdl_Input_State, scancode: sdl3.Scancode, down: bool) -> bool {
	#partial switch scancode {
	case .LCTRL, .RCTRL:
		state.ctrl_down = down
	case .LSHIFT, .RSHIFT:
		state.shift_down = down
	case .LALT, .RALT:
		state.alt_down = down
	case .LGUI, .RGUI:
		state.super_down = down
	case:
		return false
	}
	return true
}

sdl_input_sync_keyboard_state :: proc(input: ^Frame_Input, state: Sdl_Input_State) {
	input.keyboard.ctrl_down = state.ctrl_down
	input.keyboard.shift_down = state.shift_down
	input.keyboard.alt_down = state.alt_down
	input.keyboard.super_down = state.super_down
	input.keyboard.move_forward = state.move_forward
	input.keyboard.move_back = state.move_back
	input.keyboard.move_left = state.move_left
	input.keyboard.move_right = state.move_right
	input.keyboard.move_up = state.move_up
	input.keyboard.move_down = state.move_down
}
