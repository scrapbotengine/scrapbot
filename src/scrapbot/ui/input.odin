package ui

import shared "../shared"

input_key_state :: proc(
	input: shared.Keyboard_Input_Component,
	key: shared.Input_Key,
) -> (
	down, pressed, released: bool,
) {
	return shared.input_key_state(input, key)
}

input_key_down :: proc(input: shared.Keyboard_Input_Component, key: shared.Input_Key) -> bool {
	down, _, _ := input_key_state(input, key)
	return down
}

input_key_pressed :: proc(input: shared.Keyboard_Input_Component, key: shared.Input_Key) -> bool {
	_, pressed, _ := input_key_state(input, key)
	return pressed
}

input_any_down :: proc(input: shared.Keyboard_Input_Component, keys: ..shared.Input_Key) -> bool {
	for key in keys {
		if input_key_down(input, key) {
			return true
		}
	}
	return false
}

keyboard_input_from_snapshot :: proc(
	physical: shared.Keyboard_Input_Component,
	text: shared.Text_Input = {},
) -> Keyboard_Input {
	result := Keyboard_Input {
		text = text.text,
		left = text.left,
		right = text.right,
		up = text.up,
		down = text.down,
		home = text.home,
		end = text.end,
		backspace = text.backspace,
		delete_forward = text.delete_forward,
		tab = text.tab,
		enter = text.enter,
		escape = text.escape || input_key_pressed(physical, .Escape),
	}
	result.shift = input_any_down(physical, .Left_Shift, .Right_Shift)
	shortcut := input_any_down(physical, .Left_Control, .Right_Control, .Left_Meta, .Right_Meta)
	alt := input_any_down(physical, .Left_Alt, .Right_Alt)
	result.fine = shortcut
	result.select_all = shortcut && input_key_pressed(physical, .A)
	if input_key_pressed(physical, .F5) {
		result.actions += {.Transport_Play}
	}
	if input_key_pressed(physical, .F6) {
		result.actions += {.Transport_Pause}
	}
	if input_key_pressed(physical, .F7) {
		result.actions += {.Transport_Step}
	}
	if input_key_pressed(physical, .F8) {
		result.actions += {.Transport_Stop}
	}
	if shortcut {
		if input_key_pressed(physical, .E) {
			result.actions += {.Toggle_Editor}
		}
		if input_key_pressed(physical, .B) {
			if alt {
				result.actions += {.Toggle_Right_Sidebar}
			} else {
				result.actions += {.Toggle_Left_Sidebar}
			}
		}
		if input_key_pressed(physical, .R) {
			result.actions += {.Transport_Play}
		}
		if input_key_pressed(physical, .T) {
			if result.shift {
				result.actions += {.Transport_Step}
			} else {
				result.actions += {.Transport_Pause}
			}
		}
		if input_key_pressed(physical, .Period) {
			result.actions += {.Transport_Stop}
		}
		if input_key_pressed(physical, .S) {
			result.actions += {.Save}
		}
		if input_key_pressed(physical, .Z) {
			if result.shift {
				result.actions += {.Redo}
			} else {
				result.actions += {.Undo}
			}
		}
		if input_key_pressed(physical, .D) {
			result.actions += {.Duplicate_Entity}
		}
		if input_key_pressed(physical, .C) {
			result.actions += {.Copy_Entities}
		}
		if input_key_pressed(physical, .X) {
			result.actions += {.Cut_Entities}
		}
		if input_key_pressed(physical, .V) {
			result.actions += {.Paste_Entities}
		}
		return result
	}
	if alt {
		return result
	}
	if input_key_pressed(physical, .Backspace) || input_key_pressed(physical, .Delete) {
		result.actions += {.Delete_Entity}
	}
	if input_key_pressed(physical, .F) {
		result.actions += {.Focus_Selected}
	}
	if input_key_pressed(physical, .W) {
		result.actions += {.Gizmo_Translate}
	}
	if input_key_pressed(physical, .E) {
		result.actions += {.Gizmo_Rotate}
	}
	if input_key_pressed(physical, .G) {
		result.actions += {.Transform_Translate}
	}
	if input_key_pressed(physical, .R) {
		result.actions += {.Transform_Rotate}
	}
	if input_key_pressed(physical, .S) {
		result.actions += {.Transform_Scale}
	}
	if input_key_pressed(physical, .X) {
		result.actions += {.Transform_Axis_X}
	}
	if input_key_pressed(physical, .Y) {
		result.actions += {.Transform_Axis_Y}
	}
	if input_key_pressed(physical, .Z) {
		result.actions += {.Transform_Axis_Z}
	}
	return result
}

pointer_input_from_snapshot :: proc(physical: shared.Pointer_Input_Component) -> Pointer_Input {
	down, pressed, released := shared.input_pointer_button_state(physical, .Primary)
	return {
		position = physical.position,
		wheel_y = physical.wheel.y,
		primary_down = down,
		primary_pressed = pressed,
		primary_released = released,
		edges_authoritative = true,
		available = physical.available,
	}
}
