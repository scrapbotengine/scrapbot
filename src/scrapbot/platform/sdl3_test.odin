package platform

import "core:testing"
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
