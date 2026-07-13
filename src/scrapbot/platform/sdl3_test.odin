package platform

import "core:testing"
import shared "../shared"
import sdl "vendor:sdl3"

@(test)
test_editor_toggle_shortcut_requires_ctrl_escape_press :: proc(t:^testing.T) {
	testing.expect(t,editor_toggle_shortcut(.ESCAPE,sdl.Keymod{.LCTRL},false))
	testing.expect(t,editor_toggle_shortcut(.ESCAPE,sdl.Keymod{.RCTRL},false))
	testing.expect(t,!editor_toggle_shortcut(.ESCAPE,sdl.Keymod{},false))
	testing.expect(t,!editor_toggle_shortcut(.ESCAPE,sdl.Keymod{.LCTRL},true))
	other:=sdl.Scancode(4)
	testing.expect(t,!editor_toggle_shortcut(other,sdl.Keymod{.LCTRL},false))
}

@(test)
test_scene_camera_input_maps_navigation_only_while_looking :: proc(t: ^testing.T) {
	keys := Scene_Camera_Key_State{forward = true, left = true, up = true}
	inactive := scene_camera_input_from_state(keys, {4, -2}, false)
	testing.expect(t, !inactive.look_active)
	testing.expect(t, inactive.movement == shared.Vec3{})

	active := scene_camera_input_from_state(keys, {4, -2}, true)
	testing.expect(t, active.look_active)
	testing.expect(t, active.movement == shared.Vec3{-1, 1, 1})
	testing.expect(t, active.look_delta == shared.Vec2{4, -2})
}

@(test)
test_scene_camera_capture_discards_initial_relative_mouse_delta :: proc(t: ^testing.T) {
	delta := shared.Vec2{380, -240}
	testing.expect(t, scene_camera_capture_delta(delta, true) == shared.Vec2{})
	testing.expect(t, scene_camera_capture_delta(delta, false) == delta)
}
