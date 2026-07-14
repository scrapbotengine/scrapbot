package platform

import shared "../shared"
import base_runtime "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

runtime_window: ^sdl.Window
runtime_window_ready: bool
runtime_window_hidden: bool
runtime_editor_toggle_requested: bool
runtime_editor_gizmo_mode_requested: bool
runtime_editor_gizmo_mode: shared.Editor_Gizmo_Mode
runtime_wheel_y: f32
runtime_scene_camera_look_active: bool
runtime_text_bytes: [512]u8
runtime_text_length: int
runtime_text_navigation: Runtime_Text_Input

Pointer_State :: struct {
	x, y: f32,
	wheel_y: f32,
	primary_down: bool,
	secondary_down: bool,
	available: bool,
}

Scene_Camera_Key_State :: struct {
	forward, backward: bool,
	left, right: bool,
	up, down: bool,
}

Runtime_Text_Input :: struct {
	text: string,
	left, right, up, down, home, end: bool,
	backspace, delete_forward: bool,
	tab, shift, fine, enter, escape, select_all, undo, redo: bool,
}

Live_Resize_Redraw_Proc :: #type proc "c" (userdata: rawptr)

Live_Resize_Watch :: struct {
	window_id: sdl.WindowID,
	redraw: Live_Resize_Redraw_Proc,
	userdata: rawptr,
}

runtime_event_requests_live_resize_redraw :: proc(
	event: ^sdl.Event,
	window_id: sdl.WindowID,
) -> bool {
	return(
		event != nil &&
		event.type == .WINDOW_EXPOSED &&
		event.window.data1 == 1 &&
		event.window.windowID == window_id \
	)
}

runtime_live_resize_event_watch :: proc "c" (userdata: rawptr, event: ^sdl.Event) -> bool {
	context = base_runtime.default_context()
	watch := cast(^Live_Resize_Watch)userdata
	if watch != nil &&
	   watch.redraw != nil &&
	   runtime_event_requests_live_resize_redraw(event, watch.window_id) {
		watch.redraw(watch.userdata)
	}
	return true
}

watch_runtime_live_resize :: proc(
	watch: ^Live_Resize_Watch,
	redraw: Live_Resize_Redraw_Proc,
	userdata: rawptr,
) -> string {
	if watch == nil || redraw == nil || runtime_window == nil {
		return "cannot watch live resize without a runtime window and redraw callback"
	}
	watch^ = {
		window_id = sdl.GetWindowID(runtime_window),
		redraw = redraw,
		userdata = userdata,
	}
	if watch.window_id == 0 || !sdl.AddEventWatch(runtime_live_resize_event_watch, watch) {
		watch^ = {}
		return fmt.tprintf("failed to watch SDL3 live resize events: %s", sdl.GetError())
	}
	return ""
}

unwatch_runtime_live_resize :: proc(watch: ^Live_Resize_Watch) {
	if watch == nil || watch.redraw == nil { return }
	sdl.RemoveEventWatch(runtime_live_resize_event_watch, watch)
	watch^ = {}
}

runtime_window_flags :: proc(hidden: bool) -> sdl.WindowFlags {
	flags := sdl.WindowFlags{.RESIZABLE}
	if !hidden {
		flags += sdl.WINDOW_HIGH_PIXEL_DENSITY
	}
	when ODIN_OS == .Darwin {
		flags += sdl.WINDOW_METAL
	}
	if hidden {
		flags += sdl.WINDOW_HIDDEN
	}
	return flags
}

runtime_window_pixel_density :: proc() -> f32 {
	if runtime_window == nil || runtime_window_hidden { return 1 }
	density := sdl.GetWindowPixelDensity(runtime_window)
	if density <= 0 { return 1 }
	return density
}

open_runtime_window :: proc(title: string, width, height: int) -> string {
	return open_runtime_window_with_visibility(title, width, height, false)
}

open_hidden_runtime_window :: proc(title: string, width, height: int) -> string {
	return open_runtime_window_with_visibility(title, width, height, true)
}

open_runtime_window_with_visibility :: proc(
	title: string,
	width, height: int,
	hidden: bool,
) -> string {
	if runtime_window_ready {
		return ""
	}

	if !sdl.Init(sdl.INIT_VIDEO) {
		return fmt.tprintf("failed to initialize SDL3 video: %s", sdl.GetError())
	}

	title_c := strings.clone_to_cstring(title)
	defer delete(title_c)

	runtime_window = sdl.CreateWindow(
		title_c,
		c.int(width),
		c.int(height),
		runtime_window_flags(hidden),
	)
	if runtime_window == nil {
		err := fmt.tprintf("failed to create SDL3 window: %s", sdl.GetError())
		sdl.Quit()
		return err
	}

	runtime_window_ready = true
	runtime_window_hidden = hidden
	_ = sdl.StartTextInput(runtime_window)
	return ""
}

close_runtime_window :: proc() {
	if runtime_window != nil && runtime_scene_camera_look_active {
		_ = sdl.SetWindowRelativeMouseMode(runtime_window, false)
	}
	if runtime_window != nil {
		_ = sdl.StopTextInput(runtime_window)
		sdl.DestroyWindow(runtime_window)
		runtime_window = nil
	}
	if runtime_window_ready {
		sdl.Quit()
		runtime_window_ready = false
	}
	runtime_window_hidden = false
	runtime_editor_toggle_requested = false
	runtime_editor_gizmo_mode_requested = false
	runtime_scene_camera_look_active = false
	runtime_text_length = 0
	runtime_text_navigation = {}
}

runtime_pointer_state :: proc() -> Pointer_State {
	if runtime_window == nil || runtime_window_hidden {
		return {}
	}
	x, y: f32
	buttons := sdl.GetMouseState(&x, &y)
	return {
		x = x,
		y = y,
		wheel_y = runtime_wheel_y,
		primary_down = .LEFT in buttons,
		secondary_down = .RIGHT in buttons,
		available = true,
	}
}

runtime_pointer_state_in_pixels :: proc() -> Pointer_State {
	pointer := runtime_pointer_state()
	if !pointer.available || runtime_window == nil { return pointer }
	window_width, window_height: c.int
	pixel_width, pixel_height: c.int
	if !sdl.GetWindowSize(runtime_window, &window_width, &window_height) ||
	   !sdl.GetWindowSizeInPixels(runtime_window, &pixel_width, &pixel_height) ||
	   window_width <= 0 ||
	   window_height <= 0 { return pointer }
	pointer.x *= f32(pixel_width) / f32(window_width)
	pointer.y *= f32(pixel_height) / f32(window_height)
	return pointer
}

runtime_text_input :: proc() -> Runtime_Text_Input {
	result := runtime_text_navigation
	result.text = string(runtime_text_bytes[:runtime_text_length])
	return result
}

consume_editor_toggle :: proc() -> bool {
	requested := runtime_editor_toggle_requested
	runtime_editor_toggle_requested = false
	return requested
}

consume_editor_gizmo_mode :: proc() -> (shared.Editor_Gizmo_Mode, bool) {
	mode, requested := runtime_editor_gizmo_mode, runtime_editor_gizmo_mode_requested
	runtime_editor_gizmo_mode_requested = false
	return mode, requested
}

editor_toggle_shortcut :: proc(
	scancode: sdl.Scancode,
	modifiers: sdl.Keymod,
	repeat: bool,
) -> bool {
	return !repeat && scancode == .ESCAPE && (.LCTRL in modifiers || .RCTRL in modifiers)
}

editor_gizmo_mode_shortcut :: proc(
	scancode: sdl.Scancode,
	repeat: bool,
) -> (
	shared.Editor_Gizmo_Mode,
	bool,
) {
	if repeat { return .Translate, false }
	#partial switch scancode {
		case .W:
			return .Translate, true
		case .E:
			return .Rotate, true
		case .R:
			return .Scale, true
		case:
			return .Translate, false
	}
}

scene_camera_input_from_state :: proc(
	keys: Scene_Camera_Key_State,
	look_delta: shared.Vec2,
	look_active: bool,
) -> shared.Editor_Fly_Camera_Input {
	if !look_active {
		return {}
	}
	movement := shared.Vec3{}
	if keys.right { movement.x += 1 }
	if keys.left { movement.x -= 1 }
	if keys.up { movement.y += 1 }
	if keys.down { movement.y -= 1 }
	if keys.forward { movement.z += 1 }
	if keys.backward { movement.z -= 1 }
	return {movement = movement, look_delta = look_delta, look_active = true}
}

scene_camera_capture_delta :: proc(delta: shared.Vec2, capture_started: bool) -> shared.Vec2 {
	if capture_started {
		return {}
	}
	return delta
}

keyboard_state_has :: proc(keyboard: [^]bool, key_count: int, scancode: sdl.Scancode) -> bool {
	index := int(scancode)
	return keyboard != nil && index >= 0 && index < key_count && keyboard[index]
}

runtime_scene_camera_input :: proc(
	enabled: bool,
	viewport_x, viewport_y, viewport_width, viewport_height: f32,
) -> shared.Editor_Fly_Camera_Input {
	if runtime_window == nil || runtime_window_hidden || !enabled {
		if runtime_window != nil && runtime_scene_camera_look_active {
			_ = sdl.SetWindowRelativeMouseMode(runtime_window, false)
		}
		runtime_scene_camera_look_active = false
		return {}
	}

	pointer := runtime_pointer_state_in_pixels()
	inside_viewport :=
		pointer.available &&
		pointer.x >= viewport_x &&
		pointer.y >= viewport_y &&
		pointer.x < viewport_x + viewport_width &&
		pointer.y < viewport_y + viewport_height
	capture_started := false
	if !runtime_scene_camera_look_active {
		if !pointer.secondary_down || !inside_viewport {
			return {}
		}
		if !sdl.SetWindowRelativeMouseMode(runtime_window, true) {
			return {}
		}
		runtime_scene_camera_look_active = true
		capture_started = true
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
		forward = keyboard_state_has(keyboard, int(key_count), .W),
		backward = keyboard_state_has(keyboard, int(key_count), .S),
		left = keyboard_state_has(keyboard, int(key_count), .A),
		right = keyboard_state_has(keyboard, int(key_count), .D),
		up = keyboard_state_has(keyboard, int(key_count), .SPACE),
		down = keyboard_state_has(
			keyboard,
			int(key_count),
			.LCTRL,
		) || keyboard_state_has(keyboard, int(key_count), .RCTRL),
	}
	look_delta := scene_camera_capture_delta({delta_x, delta_y}, capture_started)
	return scene_camera_input_from_state(keys, look_delta, true)
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

runtime_text_key :: proc(
	input: ^Runtime_Text_Input,
	scancode: sdl.Scancode,
	modifiers: sdl.Keymod,
) {
	if input == nil { return }
	shortcut :=
		.LCTRL in modifiers || .RCTRL in modifiers || .LGUI in modifiers || .RGUI in modifiers
	input.shift = .LSHIFT in modifiers || .RSHIFT in modifiers
	input.fine =
		.LCTRL in modifiers || .RCTRL in modifiers || .LGUI in modifiers || .RGUI in modifiers
	#partial switch scancode {
		case .LEFT:
			input.left = true
		case .RIGHT:
			input.right = true
		case .UP:
			input.up = true
		case .DOWN:
			input.down = true
		case .HOME:
			input.home = true
		case .END:
			input.end = true
		case .BACKSPACE:
			input.backspace = true
		case .DELETE:
			input.delete_forward = true
		case .TAB:
			input.tab = true
		case .RETURN, .KP_ENTER:
			input.enter = true
		case .ESCAPE:
			if !shortcut { input.escape = true }
		case .A:
			if shortcut { input.select_all = true }
		case .Z:
			if shortcut && input.shift {
				input.redo = true
			} else if shortcut {
				input.undo = true
			}
	}
}

pump_runtime_window_events :: proc() -> bool {
	should_quit := false
	runtime_wheel_y = 0
	runtime_text_length = 0
	runtime_text_navigation = {}
	modifiers := sdl.GetModState()
	runtime_text_navigation.shift = .LSHIFT in modifiers || .RSHIFT in modifiers
	runtime_text_navigation.fine =
		.LCTRL in modifiers || .RCTRL in modifiers || .LGUI in modifiers || .RGUI in modifiers
	event: sdl.Event
	for sdl.PollEvent(&event) {
		if event.type == .QUIT || event.type == .WINDOW_CLOSE_REQUESTED {
			should_quit = true
		}
		if event.type == .KEY_DOWN &&
		   editor_toggle_shortcut(event.key.scancode, event.key.mod, event.key.repeat) {
			runtime_editor_toggle_requested = true
		}
		if event.type == .KEY_DOWN {
			if mode, requested := editor_gizmo_mode_shortcut(event.key.scancode, event.key.repeat);
			   requested { runtime_editor_gizmo_mode = mode; runtime_editor_gizmo_mode_requested = true }
		}
		if event.type == .KEY_DOWN {
			runtime_text_key(&runtime_text_navigation, event.key.scancode, event.key.mod)
		}
		if event.type == .TEXT_INPUT && event.text.text != nil {
			text, err := strings.clone_from_cstring(event.text.text)
			if err == nil {
				for byte in transmute([]u8)text {
					if runtime_text_length >= len(runtime_text_bytes) { break }
					runtime_text_bytes[runtime_text_length] = byte
					runtime_text_length += 1
				}
				delete(text)
			}
		}
		if event.type == .MOUSE_WHEEL { runtime_wheel_y += event.wheel.y }
	}
	return should_quit
}
