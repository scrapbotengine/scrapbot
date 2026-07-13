package platform

import "core:c"
import "core:fmt"
import "core:strings"
import shared "../shared"
import sdl "vendor:sdl3"

runtime_window: ^sdl.Window
runtime_window_ready: bool
runtime_window_hidden: bool
runtime_editor_toggle_requested: bool
runtime_wheel_y: f32
runtime_scene_camera_look_active: bool

Pointer_State :: struct {
	x, y: f32,
	wheel_y: f32,
	primary_down: bool,
	secondary_down: bool,
	available: bool,
}

Scene_Camera_Key_State :: struct {
	forward, backward: bool,
	left, right:       bool,
	up, down:          bool,
}

runtime_window_flags :: proc(hidden: bool) -> sdl.WindowFlags {
	flags := sdl.WindowFlags{.RESIZABLE}
	when ODIN_OS == .Darwin {
		flags += sdl.WINDOW_METAL
	}
	if hidden {
		flags += sdl.WINDOW_HIDDEN
	}
	return flags
}

open_runtime_window :: proc(title: string, width, height: int) -> string {
	return open_runtime_window_with_visibility(title, width, height, false)
}

open_hidden_runtime_window :: proc(title: string, width, height: int) -> string {
	return open_runtime_window_with_visibility(title, width, height, true)
}

open_runtime_window_with_visibility :: proc(title: string, width, height: int, hidden: bool) -> string {
	if runtime_window_ready {
		return ""
	}

	if !sdl.Init(sdl.INIT_VIDEO) {
		return fmt.tprintf("failed to initialize SDL3 video: %s", sdl.GetError())
	}

	title_c := strings.clone_to_cstring(title)
	defer delete(title_c)

	runtime_window = sdl.CreateWindow(title_c, c.int(width), c.int(height), runtime_window_flags(hidden))
	if runtime_window == nil {
		err := fmt.tprintf("failed to create SDL3 window: %s", sdl.GetError())
		sdl.Quit()
		return err
	}

	runtime_window_ready = true
	runtime_window_hidden = hidden
	return ""
}

close_runtime_window :: proc() {
	if runtime_window != nil && runtime_scene_camera_look_active {
		_ = sdl.SetWindowRelativeMouseMode(runtime_window, false)
	}
	if runtime_window != nil {
		sdl.DestroyWindow(runtime_window)
		runtime_window = nil
	}
	if runtime_window_ready {
		sdl.Quit()
		runtime_window_ready = false
	}
	runtime_window_hidden = false
	runtime_editor_toggle_requested = false
	runtime_scene_camera_look_active = false
}

runtime_pointer_state :: proc() -> Pointer_State {
	if runtime_window == nil || runtime_window_hidden {
		return {}
	}
	x, y: f32
	buttons := sdl.GetMouseState(&x, &y)
	return {x=x, y=y, wheel_y=runtime_wheel_y, primary_down=.LEFT in buttons, secondary_down=.RIGHT in buttons, available=true}
}

runtime_pointer_state_in_pixels :: proc() -> Pointer_State {
	pointer := runtime_pointer_state()
	if !pointer.available || runtime_window == nil {return pointer}
	window_width, window_height: c.int
	pixel_width, pixel_height: c.int
	if !sdl.GetWindowSize(runtime_window, &window_width, &window_height) ||
	   !sdl.GetWindowSizeInPixels(runtime_window, &pixel_width, &pixel_height) ||
	   window_width <= 0 || window_height <= 0 {return pointer}
	pointer.x *= f32(pixel_width) / f32(window_width)
	pointer.y *= f32(pixel_height) / f32(window_height)
	return pointer
}

consume_editor_toggle :: proc() -> bool {
	requested:=runtime_editor_toggle_requested
	runtime_editor_toggle_requested=false
	return requested
}

editor_toggle_shortcut :: proc(scancode:sdl.Scancode,modifiers:sdl.Keymod,repeat:bool)->bool {
	return !repeat&&scancode==.ESCAPE&&(.LCTRL in modifiers||.RCTRL in modifiers)
}

scene_camera_input_from_state :: proc(keys: Scene_Camera_Key_State, look_delta: shared.Vec2, look_active: bool) -> shared.Editor_Fly_Camera_Input {
	if !look_active {
		return {}
	}
	movement := shared.Vec3{}
	if keys.right {movement.x += 1}
	if keys.left {movement.x -= 1}
	if keys.up {movement.y += 1}
	if keys.down {movement.y -= 1}
	if keys.forward {movement.z += 1}
	if keys.backward {movement.z -= 1}
	return {movement = movement, look_delta = look_delta, look_active = true}
}

keyboard_state_has :: proc(keyboard: [^]bool, key_count: int, scancode: sdl.Scancode) -> bool {
	index := int(scancode)
	return keyboard != nil && index >= 0 && index < key_count && keyboard[index]
}

runtime_scene_camera_input :: proc(enabled: bool, viewport_x, viewport_y, viewport_width, viewport_height: f32) -> shared.Editor_Fly_Camera_Input {
	if runtime_window == nil || runtime_window_hidden || !enabled {
		if runtime_window != nil && runtime_scene_camera_look_active {
			_ = sdl.SetWindowRelativeMouseMode(runtime_window, false)
		}
		runtime_scene_camera_look_active = false
		return {}
	}

	pointer := runtime_pointer_state_in_pixels()
	inside_viewport := pointer.available && pointer.x >= viewport_x && pointer.y >= viewport_y &&
		pointer.x < viewport_x + viewport_width && pointer.y < viewport_y + viewport_height
	if !runtime_scene_camera_look_active {
		if !pointer.secondary_down || !inside_viewport {
			return {}
		}
		if !sdl.SetWindowRelativeMouseMode(runtime_window, true) {
			return {}
		}
		runtime_scene_camera_look_active = true
	}

	delta_x, delta_y: f32
	buttons := sdl.GetRelativeMouseState(&delta_x, &delta_y)
	if .RIGHT not_in buttons {
		_ = sdl.SetWindowRelativeMouseMode(runtime_window, false)
		runtime_scene_camera_look_active = false
		return {}
	}

	key_count: c.int
	keyboard := sdl.GetKeyboardState(&key_count)
	keys := Scene_Camera_Key_State {
		forward  = keyboard_state_has(keyboard, int(key_count), .W),
		backward = keyboard_state_has(keyboard, int(key_count), .S),
		left     = keyboard_state_has(keyboard, int(key_count), .A),
		right    = keyboard_state_has(keyboard, int(key_count), .D),
		up       = keyboard_state_has(keyboard, int(key_count), .SPACE),
		down     = keyboard_state_has(keyboard, int(key_count), .LCTRL) || keyboard_state_has(keyboard, int(key_count), .RCTRL),
	}
	return scene_camera_input_from_state(keys, {delta_x, delta_y}, true)
}

runtime_window_pixel_size :: proc() -> (width, height: int, ok: bool) {
	if runtime_window == nil {
		return 0, 0, false
	}

	w, h: c.int
	if !sdl.GetWindowSizeInPixels(runtime_window, &w, &h) {
		return 0, 0, false
	}
	return int(w), int(h), true
}

pump_runtime_window_events :: proc() -> bool {
	should_quit := false
	runtime_wheel_y = 0
	event: sdl.Event
	for sdl.PollEvent(&event) {
		if event.type == .QUIT || event.type == .WINDOW_CLOSE_REQUESTED {
			should_quit = true
		}
		if event.type==.KEY_DOWN && editor_toggle_shortcut(event.key.scancode,event.key.mod,event.key.repeat) {
			runtime_editor_toggle_requested=true
		}
		if event.type==.MOUSE_WHEEL {runtime_wheel_y += event.wheel.y}
	}
	return should_quit
}
