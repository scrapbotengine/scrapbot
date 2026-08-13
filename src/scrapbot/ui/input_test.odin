package ui

import shared "../shared"
import "core:testing"

test_keyboard_snapshot :: proc(
	down, pressed: []shared.Input_Key,
) -> shared.Keyboard_Input_Component {
	result := shared.Keyboard_Input_Component {
		available = true,
		focused = true,
	}
	for key in down {
		shared.input_button_set(&result.buttons.down, int(key))
	}
	for key in pressed {
		shared.input_button_set(&result.buttons.pressed, int(key))
	}
	return result
}

@(test)
test_editor_actions_resolve_from_one_physical_keyboard_snapshot :: proc(t: ^testing.T) {
	shortcut := keyboard_input_from_snapshot(test_keyboard_snapshot({.Left_Meta}, {.E, .D}))
	testing.expect(t, editor_action_requested(shortcut, .Toggle_Editor))
	testing.expect(t, editor_action_requested(shortcut, .Duplicate_Entity))
	testing.expect(t, !editor_action_requested(shortcut, .Gizmo_Rotate))

	run := keyboard_input_from_snapshot(test_keyboard_snapshot({.Left_Control}, {.R}))
	testing.expect(t, editor_action_requested(run, .Transport_Play))
	testing.expect(t, !editor_action_requested(run, .Transform_Rotate))

	pause := keyboard_input_from_snapshot(test_keyboard_snapshot({.Left_Control}, {.T}))
	testing.expect(t, editor_action_requested(pause, .Transport_Pause))
	testing.expect(t, !editor_action_requested(pause, .Transport_Step))

	step := keyboard_input_from_snapshot(
		test_keyboard_snapshot({.Left_Control, .Left_Shift}, {.T}),
	)
	testing.expect(t, editor_action_requested(step, .Transport_Step))
	testing.expect(t, !editor_action_requested(step, .Transport_Pause))

	stop := keyboard_input_from_snapshot(test_keyboard_snapshot({.Left_Meta}, {.Period}))
	testing.expect(t, editor_action_requested(stop, .Transport_Stop))
	shift_stop := keyboard_input_from_snapshot(
		test_keyboard_snapshot({.Left_Meta, .Left_Shift}, {.Period}),
	)
	testing.expect(t, editor_action_requested(shift_stop, .Transport_Stop))

	aliases := keyboard_input_from_snapshot(test_keyboard_snapshot({}, {.F5, .F6, .F7, .F8}))
	testing.expect(t, editor_action_requested(aliases, .Transport_Play))
	testing.expect(t, editor_action_requested(aliases, .Transport_Pause))
	testing.expect(t, editor_action_requested(aliases, .Transport_Step))
	testing.expect(t, editor_action_requested(aliases, .Transport_Stop))

	right_sidebar := keyboard_input_from_snapshot(
		test_keyboard_snapshot({.Left_Control, .Left_Alt}, {.B}),
	)
	testing.expect(t, editor_action_requested(right_sidebar, .Toggle_Right_Sidebar))
	testing.expect(t, !editor_action_requested(right_sidebar, .Toggle_Left_Sidebar))
}

@(test)
test_unmodified_editor_chords_and_axes_resolve_after_modifiers :: proc(t: ^testing.T) {
	rotate := keyboard_input_from_snapshot(test_keyboard_snapshot({}, {.R}))
	testing.expect(t, editor_action_requested(rotate, .Transform_Rotate))
	testing.expect(t, !editor_action_requested(rotate, .Transport_Play))

	complementary_axis := keyboard_input_from_snapshot(test_keyboard_snapshot({.Left_Shift}, {.X}))
	testing.expect(t, complementary_axis.shift)
	testing.expect(t, editor_action_requested(complementary_axis, .Transform_Axis_X))

	delete := keyboard_input_from_snapshot(test_keyboard_snapshot({}, {.Backspace}))
	testing.expect(t, editor_action_requested(delete, .Delete_Entity))
}

@(test)
test_ui_pointer_adapter_preserves_authoritative_button_edges :: proc(t: ^testing.T) {
	physical := shared.Pointer_Input_Component {
		available = true,
		position = {120, 80},
		wheel = {0, -2},
	}
	shared.input_button_set(&physical.buttons.down, int(shared.Input_Pointer_Button.Primary))
	shared.input_button_set(&physical.buttons.pressed, int(shared.Input_Pointer_Button.Primary))
	pointer := pointer_input_from_snapshot(physical)
	testing.expect(t, pointer.edges_authoritative)
	testing.expect(t, pointer.primary_down)
	testing.expect(t, pointer.primary_pressed)
	testing.expect(t, !pointer.primary_released)
	testing.expect_value(t, pointer.position, shared.Vec2{120, 80})
	testing.expect_value(t, pointer.wheel_y, f32(-2))
}

@(test)
test_authoritative_pointer_edges_do_not_rearm_from_held_state :: proc(t: ^testing.T) {
	pointer := Pointer_Input {
		primary_down = true,
		primary_pressed = false,
		edges_authoritative = true,
	}
	testing.expect(t, !pointer_press_started(pointer, false))
	testing.expect(t, !pointer_press_released(pointer, true))
}
