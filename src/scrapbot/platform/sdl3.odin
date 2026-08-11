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
runtime_editor_gizmo_mode_requested: bool
runtime_editor_gizmo_mode: shared.Editor_Gizmo_Mode
runtime_wheel_y: f32
runtime_wheel_x: f32
runtime_pointer_delta: shared.Vec2
runtime_key_pressed: [2]u64
runtime_key_released: [2]u64
runtime_pointer_pressed: [2]u64
runtime_pointer_released: [2]u64
runtime_input_generation: u64
runtime_input_sampled_generation: u64
runtime_scene_camera_look_active: bool
runtime_scene_camera_capture_warmup: int
runtime_pointer_cursor: Runtime_Pointer_Cursor
runtime_pointer_hand_cursor: ^sdl.Cursor
runtime_text_edit_cursor: ^sdl.Cursor
runtime_horizontal_resize_cursor: ^sdl.Cursor
runtime_vertical_resize_cursor: ^sdl.Cursor
runtime_move_cursor: ^sdl.Cursor
runtime_not_allowed_cursor: ^sdl.Cursor
runtime_text_bytes: [512]u8
runtime_text_length: int
runtime_text_navigation: Runtime_Text_Input

RUNTIME_WINDOW_USABLE_FRACTION :: f32(0.9)

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
	fast: bool,
}

Runtime_Text_Input :: struct {
	text: string,
	left, right, up, down, home, end: bool,
	backspace, delete_forward: bool,
	tab, shift, fine, enter, escape, select_all, save, undo, redo: bool,
	editor_toggle, run_stop, pause_step: bool,
	toggle_left_sidebar, toggle_right_sidebar: bool,
	duplicate_entity, delete_entity: bool,
	transform_translate, transform_rotate, transform_scale: bool,
	transform_axis_x, transform_axis_y, transform_axis_z: bool,
}

Editor_Shortcut_Action :: enum {
	Toggle_Editor,
	Toggle_Left_Sidebar,
	Toggle_Right_Sidebar,
	Run_Stop,
	Pause_Step,
	Save,
	Undo,
	Redo,
	Duplicate_Entity,
	Delete_Entity,
}

Runtime_Pointer_Cursor :: enum {
	Default,
	Pointer,
	Text_Edit,
	Horizontal_Resize,
	Vertical_Resize,
	Move,
	Not_Allowed,
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

	window_width, window_height := width, height
	if !hidden {
		usable: sdl.Rect
		display := sdl.GetPrimaryDisplay()
		if display != sdl.DisplayID(0) && sdl.GetDisplayUsableBounds(display, &usable) {
			window_width, window_height = runtime_window_size_for_usable_bounds(
				width,
				height,
				int(usable.w),
				int(usable.h),
			)
		}
	}

	title_c := strings.clone_to_cstring(title)
	defer delete(title_c)

	runtime_window = sdl.CreateWindow(
		title_c,
		c.int(window_width),
		c.int(window_height),
		runtime_window_flags(hidden),
	)
	if runtime_window == nil {
		err := fmt.tprintf("failed to create SDL3 window: %s", sdl.GetError())
		sdl.Quit()
		return err
	}

	runtime_window_ready = true
	runtime_window_hidden = hidden
	runtime_pointer_cursor = .Default
	_ = sdl.StartTextInput(runtime_window)
	return ""
}

runtime_window_size_for_usable_bounds :: proc(
	requested_width, requested_height, usable_width, usable_height: int,
) -> (
	int,
	int,
) {
	if requested_width <= 0 || requested_height <= 0 || usable_width <= 0 || usable_height <= 0 {
		return requested_width, requested_height
	}
	maximum_width := max(int(f32(usable_width) * RUNTIME_WINDOW_USABLE_FRACTION), 1)
	maximum_height := max(int(f32(usable_height) * RUNTIME_WINDOW_USABLE_FRACTION), 1)
	scale := min(
		f32(1),
		min(
			f32(maximum_width) / f32(requested_width),
			f32(maximum_height) / f32(requested_height),
		),
	)
	return max(int(f32(requested_width) * scale), 1), max(int(f32(requested_height) * scale), 1)
}

close_runtime_window :: proc() {
	if runtime_window != nil && runtime_scene_camera_look_active {
		_ = sdl.SetWindowRelativeMouseMode(runtime_window, false)
	}
	if runtime_window != nil {
		if runtime_pointer_cursor != .Default {
			_ = sdl.SetCursor(sdl.GetDefaultCursor())
		}
		if runtime_pointer_hand_cursor != nil {
			sdl.DestroyCursor(runtime_pointer_hand_cursor)
			runtime_pointer_hand_cursor = nil
		}
		if runtime_text_edit_cursor != nil {
			sdl.DestroyCursor(runtime_text_edit_cursor)
			runtime_text_edit_cursor = nil
		}
		if runtime_horizontal_resize_cursor != nil {
			sdl.DestroyCursor(runtime_horizontal_resize_cursor)
			runtime_horizontal_resize_cursor = nil
		}
		if runtime_vertical_resize_cursor != nil {
			sdl.DestroyCursor(runtime_vertical_resize_cursor)
			runtime_vertical_resize_cursor = nil
		}
		if runtime_move_cursor != nil {
			sdl.DestroyCursor(runtime_move_cursor)
			runtime_move_cursor = nil
		}
		if runtime_not_allowed_cursor != nil {
			sdl.DestroyCursor(runtime_not_allowed_cursor)
			runtime_not_allowed_cursor = nil
		}
		_ = sdl.StopTextInput(runtime_window)
		sdl.DestroyWindow(runtime_window)
		runtime_window = nil
	}
	if runtime_window_ready {
		sdl.Quit()
		runtime_window_ready = false
	}
	runtime_window_hidden = false
	runtime_editor_gizmo_mode_requested = false
	runtime_scene_camera_look_active = false
	runtime_scene_camera_capture_warmup = 0
	runtime_pointer_cursor = .Default
	runtime_wheel_x = 0
	runtime_wheel_y = 0
	runtime_pointer_delta = {}
	runtime_key_pressed = {}
	runtime_key_released = {}
	runtime_pointer_pressed = {}
	runtime_pointer_released = {}
	runtime_input_generation = 0
	runtime_input_sampled_generation = 0
	runtime_text_length = 0
	runtime_text_navigation = {}
}

runtime_pointer_system_cursor :: proc(cursor: Runtime_Pointer_Cursor) -> sdl.SystemCursor {
	switch cursor {
		case .Default:
			return .DEFAULT
		case .Pointer:
			return .POINTER
		case .Text_Edit:
			return .TEXT
		case .Horizontal_Resize:
			return .EW_RESIZE
		case .Vertical_Resize:
			return .NS_RESIZE
		case .Move:
			return .MOVE
		case .Not_Allowed:
			return .NOT_ALLOWED
	}
	return .DEFAULT
}

set_runtime_pointer_cursor :: proc(cursor: Runtime_Pointer_Cursor) {
	if runtime_window == nil ||
	   runtime_window_hidden ||
	   cursor == runtime_pointer_cursor { return }
	system_cursor: ^sdl.Cursor
	switch cursor {
		case .Default:
			system_cursor = sdl.GetDefaultCursor()
		case .Pointer:
			if runtime_pointer_hand_cursor == nil {
				runtime_pointer_hand_cursor = sdl.CreateSystemCursor(
					runtime_pointer_system_cursor(cursor),
				)
			}
			system_cursor = runtime_pointer_hand_cursor
		case .Text_Edit:
			if runtime_text_edit_cursor == nil {
				runtime_text_edit_cursor = sdl.CreateSystemCursor(
					runtime_pointer_system_cursor(cursor),
				)
			}
			system_cursor = runtime_text_edit_cursor
		case .Horizontal_Resize:
			if runtime_horizontal_resize_cursor == nil {
				runtime_horizontal_resize_cursor = sdl.CreateSystemCursor(
					runtime_pointer_system_cursor(cursor),
				)
			}
			system_cursor = runtime_horizontal_resize_cursor
		case .Vertical_Resize:
			if runtime_vertical_resize_cursor == nil {
				runtime_vertical_resize_cursor = sdl.CreateSystemCursor(
					runtime_pointer_system_cursor(cursor),
				)
			}
			system_cursor = runtime_vertical_resize_cursor
		case .Move:
			if runtime_move_cursor == nil {
				runtime_move_cursor = sdl.CreateSystemCursor(runtime_pointer_system_cursor(cursor))
			}
			system_cursor = runtime_move_cursor
		case .Not_Allowed:
			if runtime_not_allowed_cursor == nil {
				runtime_not_allowed_cursor = sdl.CreateSystemCursor(
					runtime_pointer_system_cursor(cursor),
				)
			}
			system_cursor = runtime_not_allowed_cursor
	}
	if system_cursor != nil && sdl.SetCursor(system_cursor) {
		runtime_pointer_cursor = cursor
	}
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

input_key_from_scancode :: proc "contextless" (
	scancode: sdl.Scancode,
) -> (
	shared.Input_Key,
	bool,
) {
	#partial switch scancode {
		case .A:
			return .A, true
		case .B:
			return .B, true
		case .C:
			return .C, true
		case .D:
			return .D, true
		case .E:
			return .E, true
		case .F:
			return .F, true
		case .G:
			return .G, true
		case .H:
			return .H, true
		case .I:
			return .I, true
		case .J:
			return .J, true
		case .K:
			return .K, true
		case .L:
			return .L, true
		case .M:
			return .M, true
		case .N:
			return .N, true
		case .O:
			return .O, true
		case .P:
			return .P, true
		case .Q:
			return .Q, true
		case .R:
			return .R, true
		case .S:
			return .S, true
		case .T:
			return .T, true
		case .U:
			return .U, true
		case .V:
			return .V, true
		case .W:
			return .W, true
		case .X:
			return .X, true
		case .Y:
			return .Y, true
		case .Z:
			return .Z, true
		case ._0:
			return .Digit_0, true
		case ._1:
			return .Digit_1, true
		case ._2:
			return .Digit_2, true
		case ._3:
			return .Digit_3, true
		case ._4:
			return .Digit_4, true
		case ._5:
			return .Digit_5, true
		case ._6:
			return .Digit_6, true
		case ._7:
			return .Digit_7, true
		case ._8:
			return .Digit_8, true
		case ._9:
			return .Digit_9, true
		case .LEFT:
			return .Left, true
		case .RIGHT:
			return .Right, true
		case .UP:
			return .Up, true
		case .DOWN:
			return .Down, true
		case .SPACE:
			return .Space, true
		case .RETURN, .KP_ENTER:
			return .Enter, true
		case .ESCAPE:
			return .Escape, true
		case .TAB:
			return .Tab, true
		case .BACKSPACE:
			return .Backspace, true
		case .DELETE:
			return .Delete, true
		case .HOME:
			return .Home, true
		case .END:
			return .End, true
		case .PAGEUP:
			return .Page_Up, true
		case .PAGEDOWN:
			return .Page_Down, true
		case .LSHIFT:
			return .Left_Shift, true
		case .RSHIFT:
			return .Right_Shift, true
		case .LCTRL:
			return .Left_Control, true
		case .RCTRL:
			return .Right_Control, true
		case .LALT:
			return .Left_Alt, true
		case .RALT:
			return .Right_Alt, true
		case .LGUI:
			return .Left_Meta, true
		case .RGUI:
			return .Right_Meta, true
		case .F1:
			return .F1, true
		case .F2:
			return .F2, true
		case .F3:
			return .F3, true
		case .F4:
			return .F4, true
		case .F5:
			return .F5, true
		case .F6:
			return .F6, true
		case .F7:
			return .F7, true
		case .F8:
			return .F8, true
		case .F9:
			return .F9, true
		case .F10:
			return .F10, true
		case .F11:
			return .F11, true
		case .F12:
			return .F12, true
		case:
			return .Unknown, false
	}
}

input_pointer_button_from_sdl :: proc "contextless" (
	button: u8,
) -> (
	shared.Input_Pointer_Button,
	bool,
) {
	switch button {
		case sdl.BUTTON_LEFT:
			return .Primary, true
		case sdl.BUTTON_RIGHT:
			return .Secondary, true
		case sdl.BUTTON_MIDDLE:
			return .Middle, true
		case sdl.BUTTON_X1:
			return .Back, true
		case sdl.BUTTON_X2:
			return .Forward, true
	}
	return .Primary, false
}

runtime_input_frame :: proc() -> shared.Input_Frame {
	if runtime_window == nil || runtime_window_hidden {
		return {}
	}
	result: shared.Input_Frame
	result.keyboard.available = true
	result.keyboard.focused = .INPUT_FOCUS in sdl.GetWindowFlags(runtime_window)
	key_count: c.int
	keyboard := sdl.GetKeyboardState(&key_count)
	for scancode_index in 0 ..< int(key_count) {
		if !keyboard_state_has(keyboard, int(key_count), sdl.Scancode(scancode_index)) {
			continue
		}
		if key, ok := input_key_from_scancode(sdl.Scancode(scancode_index)); ok {
			shared.input_button_set(&result.keyboard.buttons.down, int(key))
		}
	}
	result.keyboard.buttons.pressed = runtime_key_pressed
	result.keyboard.buttons.released = runtime_key_released
	pointer := runtime_pointer_state_in_pixels()
	result.pointer.available = pointer.available
	result.pointer.captured = runtime_scene_camera_look_active
	result.pointer.position = {pointer.x, pointer.y}
	density := runtime_window_pixel_density()
	result.pointer.delta = {runtime_pointer_delta.x * density, runtime_pointer_delta.y * density}
	result.pointer.wheel = {runtime_wheel_x, runtime_wheel_y}
	buttons := sdl.GetMouseState(nil, nil)
	if .LEFT in
	   buttons { shared.input_button_set(&result.pointer.buttons.down, int(shared.Input_Pointer_Button.Primary)) }
	if .RIGHT in
	   buttons { shared.input_button_set(&result.pointer.buttons.down, int(shared.Input_Pointer_Button.Secondary)) }
	if .MIDDLE in
	   buttons { shared.input_button_set(&result.pointer.buttons.down, int(shared.Input_Pointer_Button.Middle)) }
	if .X1 in
	   buttons { shared.input_button_set(&result.pointer.buttons.down, int(shared.Input_Pointer_Button.Back)) }
	if .X2 in
	   buttons { shared.input_button_set(&result.pointer.buttons.down, int(shared.Input_Pointer_Button.Forward)) }
	result.pointer.buttons.pressed = runtime_pointer_pressed
	result.pointer.buttons.released = runtime_pointer_released
	if runtime_input_sampled_generation == runtime_input_generation {
		result.keyboard.buttons.pressed = {}
		result.keyboard.buttons.released = {}
		result.pointer.delta = {}
		result.pointer.wheel = {}
		result.pointer.buttons.pressed = {}
		result.pointer.buttons.released = {}
	} else {
		runtime_input_sampled_generation = runtime_input_generation
	}
	return result
}

runtime_text_input :: proc() -> Runtime_Text_Input {
	result := runtime_text_navigation
	result.text = string(runtime_text_bytes[:runtime_text_length])
	return result
}

consume_editor_gizmo_mode :: proc() -> (shared.Editor_Gizmo_Mode, bool) {
	mode, requested := runtime_editor_gizmo_mode, runtime_editor_gizmo_mode_requested
	runtime_editor_gizmo_mode_requested = false
	return mode, requested
}

editor_shortcut_action :: proc(
	scancode: sdl.Scancode,
	modifiers: sdl.Keymod,
	repeat: bool,
) -> (
	Editor_Shortcut_Action,
	bool,
) {
	shortcut :=
		.LCTRL in modifiers || .RCTRL in modifiers || .LGUI in modifiers || .RGUI in modifiers
	alt := .LALT in modifiers || .RALT in modifiers
	shift := .LSHIFT in modifiers || .RSHIFT in modifiers
	if repeat {
		return .Toggle_Editor, false
	}
	if !shortcut && !alt {
		#partial switch scancode {
			case .BACKSPACE, .DELETE:
				return .Delete_Entity, true
		}
		return .Toggle_Editor, false
	}
	if !shortcut {
		return .Toggle_Editor, false
	}
	#partial switch scancode {
		case .E:
			return .Toggle_Editor, true
		case .B:
			if alt {
				return .Toggle_Right_Sidebar, true
			}
			return .Toggle_Left_Sidebar, true
		case .R:
			return .Run_Stop, true
		case .T:
			return .Pause_Step, true
		case .S:
			return .Save, true
		case .Z:
			if shift {
				return .Redo, true
			}
			return .Undo, true
		case .D:
			return .Duplicate_Entity, true
	}
	return .Toggle_Editor, false
}

apply_editor_shortcut_action :: proc(input: ^Runtime_Text_Input, action: Editor_Shortcut_Action) {
	if input == nil { return }
	switch action {
		case .Toggle_Editor:
			input.editor_toggle = true
		case .Toggle_Left_Sidebar:
			input.toggle_left_sidebar = true
		case .Toggle_Right_Sidebar:
			input.toggle_right_sidebar = true
		case .Run_Stop:
			input.run_stop = true
		case .Pause_Step:
			input.pause_step = true
		case .Save:
			input.save = true
		case .Undo:
			input.undo = true
		case .Redo:
			input.redo = true
		case .Duplicate_Entity:
			input.duplicate_entity = true
		case .Delete_Entity:
			input.delete_entity = true
	}
}

editor_gizmo_mode_shortcut :: proc(
	scancode: sdl.Scancode,
	modifiers: sdl.Keymod,
	repeat: bool,
) -> (
	shared.Editor_Gizmo_Mode,
	bool,
) {
	shortcut :=
		.LCTRL in modifiers || .RCTRL in modifiers || .LGUI in modifiers || .RGUI in modifiers
	if repeat || shortcut { return .Translate, false }
	#partial switch scancode {
		case .W:
			return .Translate, true
		case .E:
			return .Rotate, true
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
	return {
		movement = movement,
		look_delta = look_delta,
		look_active = true,
		move_fast = keys.fast,
	}
}

SCENE_CAMERA_CAPTURE_WARMUP_SAMPLES :: 2

scene_camera_capture_delta :: proc(delta: shared.Vec2, warmup_samples: ^int) -> shared.Vec2 {
	if warmup_samples != nil && warmup_samples^ > 0 {
		warmup_samples^ -= 1
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
		runtime_scene_camera_capture_warmup = 0
		return {}
	}

	pointer := runtime_pointer_state_in_pixels()
	inside_viewport :=
		pointer.available &&
		pointer.x >= viewport_x &&
		pointer.y >= viewport_y &&
		pointer.x < viewport_x + viewport_width &&
		pointer.y < viewport_y + viewport_height
	if !runtime_scene_camera_look_active {
		if !pointer.secondary_down || !inside_viewport {
			return {}
		}
		if !sdl.SetWindowRelativeMouseMode(runtime_window, true) {
			return {}
		}
		runtime_scene_camera_look_active = true
		runtime_scene_camera_capture_warmup = SCENE_CAMERA_CAPTURE_WARMUP_SAMPLES
	}

	delta_x, delta_y: f32
	buttons := sdl.GetRelativeMouseState(&delta_x, &delta_y)
	if .RIGHT not_in buttons {
		_ = sdl.SetWindowRelativeMouseMode(runtime_window, false)
		runtime_scene_camera_look_active = false
		runtime_scene_camera_capture_warmup = 0
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
		fast = keyboard_state_has(
			keyboard,
			int(key_count),
			.LSHIFT,
		) || keyboard_state_has(keyboard, int(key_count), .RSHIFT),
	}
	look_delta := scene_camera_capture_delta(
		{delta_x, delta_y},
		&runtime_scene_camera_capture_warmup,
	)
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
	repeat: bool = false,
) {
	if input == nil { return }
	shortcut :=
		.LCTRL in modifiers || .RCTRL in modifiers || .LGUI in modifiers || .RGUI in modifiers
	input.shift = .LSHIFT in modifiers || .RSHIFT in modifiers
	input.fine =
		.LCTRL in modifiers || .RCTRL in modifiers || .LGUI in modifiers || .RGUI in modifiers
	if action, requested := editor_shortcut_action(scancode, modifiers, repeat); requested {
		apply_editor_shortcut_action(input, action)
	}
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
		case .G:
			if !shortcut && !repeat { input.transform_translate = true }
		case .R:
			if !shortcut && !repeat { input.transform_rotate = true }
		case .S:
			if !shortcut && !repeat { input.transform_scale = true }
		case .X:
			if !shortcut && !repeat { input.transform_axis_x = true }
		case .Y:
			if !shortcut && !repeat { input.transform_axis_y = true }
		case .Z:
			if !shortcut && !repeat { input.transform_axis_z = true }
	}
}

pump_runtime_window_events :: proc() -> bool {
	runtime_input_generation += 1
	if runtime_input_generation == 0 {
		runtime_input_generation = 1
	}
	should_quit := false
	runtime_wheel_y = 0
	runtime_wheel_x = 0
	runtime_pointer_delta = {}
	runtime_key_pressed = {}
	runtime_key_released = {}
	runtime_pointer_pressed = {}
	runtime_pointer_released = {}
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
		if event.type == .KEY_DOWN {
			if !event.key.repeat {
				if key, ok := input_key_from_scancode(event.key.scancode); ok {
					shared.input_button_set(&runtime_key_pressed, int(key))
				}
			}
			if mode, requested := editor_gizmo_mode_shortcut(
				event.key.scancode,
				event.key.mod,
				event.key.repeat,
			);
			requested { runtime_editor_gizmo_mode = mode; runtime_editor_gizmo_mode_requested = true }
		}
		if event.type == .KEY_UP {
			if key, ok := input_key_from_scancode(event.key.scancode); ok {
				shared.input_button_set(&runtime_key_released, int(key))
			}
		}
		if event.type == .KEY_DOWN {
			runtime_text_key(
				&runtime_text_navigation,
				event.key.scancode,
				event.key.mod,
				event.key.repeat,
			)
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
		if event.type == .MOUSE_MOTION {
			runtime_pointer_delta.x += event.motion.xrel
			runtime_pointer_delta.y += event.motion.yrel
		}
		if event.type == .MOUSE_BUTTON_DOWN || event.type == .MOUSE_BUTTON_UP {
			if button, ok := input_pointer_button_from_sdl(event.button.button); ok {
				if event.type == .MOUSE_BUTTON_DOWN {
					shared.input_button_set(&runtime_pointer_pressed, int(button))
				} else {
					shared.input_button_set(&runtime_pointer_released, int(button))
				}
			}
		}
		if event.type == .MOUSE_WHEEL {
			runtime_wheel_x += event.wheel.x
			runtime_wheel_y += event.wheel.y
		}
	}
	return should_quit
}
