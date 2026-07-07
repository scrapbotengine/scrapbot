package main

import "core:c"
import "core:math"
import sdl3 "vendor:sdl3"

SDL_RUN_LOOP_FIXED_DELTA_SECONDS :: f32(1.0 / 60.0)
SDL_RUN_LOOP_MAX_DELTA_SECONDS :: f32(0.1)
SDL_RUN_LOOP_IDLE_DELAY_MS :: sdl3.Uint32(1)
SDL_SOFTWARE_RENDERER_CREATE_ERROR :: "SDL renderer creation failed"
SDL_SOFTWARE_TEXTURE_CREATE_ERROR :: "SDL texture creation failed"
SDL_SOFTWARE_TEXTURE_UPDATE_ERROR :: "SDL texture update failed"
SDL_SOFTWARE_RENDER_CLEAR_ERROR :: "SDL render clear failed"
SDL_SOFTWARE_RENDER_TEXTURE_ERROR :: "SDL render texture failed"
SDL_SOFTWARE_RENDER_PRESENT_ERROR :: "SDL render present failed"
SDL_SOFTWARE_INVALID_SIZE_ERROR :: "SDL window has invalid pixel size"
SDL_FLY_CAMERA_LOOK_SENSITIVITY :: f32(0.003)
SDL_FLY_CAMERA_MOVE_SPEED :: f32(5.0)
SDL_FLY_CAMERA_MAX_PITCH :: f32(1.5)

Sdl_Run_Loop_Result :: struct {
	completed_frames:          int,
	window_opened:             bool,
	window_width:              int,
	window_height:             int,
	pixel_width:               int,
	pixel_height:              int,
	quit_requested:            bool,
	live_reload_events_printed: int,
	presented:                 bool,
	surface_width:             int,
	surface_height:            int,
	renderable_count:          int,
	editor_input_routed:       bool,
	editor_visible:            bool,
	editor_paused:             bool,
	editor_selected_entity_id: string,
	fly_camera_active:         bool,
	fly_camera_position:       [3]f32,
	fly_camera_rotation:       [3]f32,
}

Sdl_Software_Presenter :: struct {
	renderer: ^sdl3.Renderer,
	texture: ^sdl3.Texture,
	width:    int,
	height:   int,
}

Sdl_Fly_Camera_State :: struct {
	initialized:   bool,
	active:        bool,
	position:      [3]f32,
	rotation:      [3]f32,
	fov_y_degrees: f32,
	near:          f32,
	far:           f32,
}

sdl_run_loop_event_requests_quit :: proc(event: sdl3.Event) -> bool {
	return event.type == .QUIT || event.type == .WINDOW_CLOSE_REQUESTED
}

sdl_run_loop_pump_events :: proc() -> bool {
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		if sdl_run_loop_event_requests_quit(event) {
			return true
		}
	}
	return false
}

sdl_run_loop_pump_input_events :: proc(input_state: ^Sdl_Input_State, input: ^Frame_Input, size: Sdl_Window_Size) -> bool {
	sdl_input_clear_text_input(input_state, input)
	event: sdl3.Event
	for sdl3.PollEvent(&event) {
		if sdl_run_loop_event_requests_quit(event) {
			return true
		}
		#partial switch event.type {
		case .MOUSE_MOTION:
			sdl_input_apply_mouse_motion(input_state, input, size, event.motion.x, event.motion.y, event.motion.xrel, event.motion.yrel)
		case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
			sdl_input_apply_mouse_button(input_state, input, size, event.button.button, event.button.down, event.button.x, event.button.y)
		case .MOUSE_WHEEL:
			sdl_input_apply_mouse_wheel(input_state, input, size, event.wheel.x, event.wheel.y, event.wheel.mouse_x, event.wheel.mouse_y, event.wheel.direction)
		case .KEY_DOWN, .KEY_UP:
			sdl_input_apply_key(input_state, input, event.key.scancode, event.key.down, event.key.repeat)
		case .TEXT_INPUT:
			sdl_input_apply_text_input(input_state, input, event.text.text)
		}
	}
	return false
}

sdl_run_loop_apply_editor_toggle :: proc(editor_visible: ^bool, input: ^Frame_Input) {
	if input.keyboard.editor_toggle_pressed {
		editor_visible^ = !editor_visible^
	}
	input.debug_overlay_visible = editor_visible^
}

sdl_run_loop_sync_text_input :: proc(window: ^sdl3.Window, editor_visible: bool, text_input_active: ^bool) {
	if editor_visible && !text_input_active^ {
		text_input_active^ = sdl3.StartTextInput(window)
		return
	}
	if !editor_visible && text_input_active^ {
		_ = sdl3.StopTextInput(window)
		text_input_active^ = false
	}
}

sdl_run_loop_sync_relative_mouse :: proc(window: ^sdl3.Window, fly_camera_active: bool, relative_mouse_active: ^bool) {
	if fly_camera_active == relative_mouse_active^ {
		return
	}
	if sdl3.SetWindowRelativeMouseMode(window, fly_camera_active) {
		relative_mouse_active^ = fly_camera_active
	}
}

sdl_run_loop_tick_live_project :: proc(
	project: ^Live_Project,
	report: ^Live_Project_Run_Report,
	editor_state: ^Editor_Test_Input_State,
	fly_camera: ^Sdl_Fly_Camera_State,
	frame_input: Frame_Input,
	editor_visible: bool,
	delta_seconds: f32,
	completed_frames: int,
) -> Simulation_Run_Result {
	input := frame_input
	sdl_fly_camera_update(fly_camera, project.check.scene.world, input, editor_visible, delta_seconds)
	sdl_fly_camera_apply_to_frame_input(&input, fly_camera^)
	scene_stamp_before_frame := project.scene_stamp
	frame := live_project_run_frame_with_input(project, delta_seconds, completed_frames, report, editor_state, input)
	sdl_fly_camera_reset_after_scene_reload(fly_camera, scene_stamp_before_frame, project.scene_stamp)
	if !source_file_stamp_equal(scene_stamp_before_frame, project.scene_stamp) {
		sdl_fly_camera_update(fly_camera, project.check.scene.world, input, editor_visible, delta_seconds)
	}
	return frame
}

sdl_fly_camera_init_from_world :: proc(world: Runtime_World) -> Sdl_Fly_Camera_State {
	camera, ok := editor_test_camera_state(world)
	if !ok {
		camera = Editor_Test_Camera_State{
			position = EDITOR_TEST_DEFAULT_CAMERA_POSITION,
			rotation = {},
			fov_y_degrees = EDITOR_TEST_DEFAULT_CAMERA_FOV_Y_DEGREES,
			near = EDITOR_TEST_DEFAULT_CAMERA_NEAR,
			far = EDITOR_TEST_DEFAULT_CAMERA_FAR,
		}
	}
	return Sdl_Fly_Camera_State{
		initialized = true,
		position = camera.position,
		rotation = camera.rotation,
		fov_y_degrees = camera.fov_y_degrees,
		near = camera.near,
		far = camera.far,
	}
}

sdl_fly_camera_can_capture :: proc(input: Frame_Input, editor_visible: bool) -> bool {
	if !input.pointer.secondary_down {
		return false
	}
	if editor_visible {
		return input.pointer.has_position && editor_pointer_in_game_viewport(input)
	}
	return true
}

sdl_fly_camera_update :: proc(state: ^Sdl_Fly_Camera_State, world: Runtime_World, input: Frame_Input, editor_visible: bool, delta_seconds: f32) {
	if !state.initialized {
		state^ = sdl_fly_camera_init_from_world(world)
	}
	state.active = sdl_fly_camera_can_capture(input, editor_visible)
	if !state.active {
		return
	}

	state.rotation[1] += input.pointer.delta[0] * SDL_FLY_CAMERA_LOOK_SENSITIVITY
	state.rotation[0] = clamp_f32(state.rotation[0] - input.pointer.delta[1] * SDL_FLY_CAMERA_LOOK_SENSITIVITY, -SDL_FLY_CAMERA_MAX_PITCH, SDL_FLY_CAMERA_MAX_PITCH)

	movement := sdl_fly_camera_movement_vector(input, state.rotation)
	length := editor_test_vec3_length(movement)
	if length <= 0.00001 {
		return
	}
	step := SDL_FLY_CAMERA_MOVE_SPEED * max_f32(delta_seconds, 0.0) / length
	state.position[0] += movement[0] * step
	state.position[1] += movement[1] * step
	state.position[2] += movement[2] * step
}

sdl_fly_camera_movement_vector :: proc(input: Frame_Input, rotation: [3]f32) -> [3]f32 {
	yaw := rotation[1]
	pitch := rotation[0]
	cos_pitch := f32(math.cos(f64(pitch)))
	forward := [3]f32{
		f32(math.sin(f64(yaw))) * cos_pitch,
		-f32(math.sin(f64(pitch))),
		-f32(math.cos(f64(yaw))) * cos_pitch,
	}
	right := [3]f32{f32(math.cos(f64(yaw))), 0.0, f32(math.sin(f64(yaw)))}
	movement := [3]f32{}
	if input.keyboard.move_forward {
		movement = editor_test_add_vec3(movement, forward)
	}
	if input.keyboard.move_back {
		movement = editor_test_subtract_vec3(movement, forward)
	}
	if input.keyboard.move_right {
		movement = editor_test_add_vec3(movement, right)
	}
	if input.keyboard.move_left {
		movement = editor_test_subtract_vec3(movement, right)
	}
	if input.keyboard.move_up {
		movement[1] += 1.0
	}
	if input.keyboard.move_down || input.keyboard.ctrl_down {
		movement[1] -= 1.0
	}
	return movement
}

sdl_run_loop_frame_limit_reached :: proc(completed_frames, max_frames: int) -> bool {
	return max_frames > 0 && completed_frames >= max_frames
}

sdl_run_loop_delta_seconds :: proc(previous_ticks_ns, current_ticks_ns: sdl3.Uint64) -> f32 {
	if current_ticks_ns <= previous_ticks_ns {
		return SDL_RUN_LOOP_FIXED_DELTA_SECONDS
	}
	delta := f32(f64(current_ticks_ns - previous_ticks_ns) / f64(sdl3.NS_PER_SECOND))
	if delta > SDL_RUN_LOOP_MAX_DELTA_SECONDS {
		return SDL_RUN_LOOP_MAX_DELTA_SECONDS
	}
	if delta <= 0 {
		return SDL_RUN_LOOP_FIXED_DELTA_SECONDS
	}
	return delta
}

sdl_software_presenter_init :: proc(window: ^sdl3.Window) -> (Sdl_Software_Presenter, string, bool) {
	renderer := sdl3.CreateRenderer(window, cstring(nil))
	if renderer == nil {
		return Sdl_Software_Presenter{}, SDL_SOFTWARE_RENDERER_CREATE_ERROR, false
	}
	return Sdl_Software_Presenter{renderer = renderer}, "", true
}

sdl_software_presenter_deinit :: proc(presenter: ^Sdl_Software_Presenter) {
	if presenter.texture != nil {
		sdl3.DestroyTexture(presenter.texture)
	}
	if presenter.renderer != nil {
		sdl3.DestroyRenderer(presenter.renderer)
	}
	presenter^ = Sdl_Software_Presenter{}
}

sdl_software_presenter_ensure_texture :: proc(presenter: ^Sdl_Software_Presenter, width, height: int) -> (string, bool) {
	if presenter.texture != nil && presenter.width == width && presenter.height == height {
		return "", true
	}
	if presenter.texture != nil {
		sdl3.DestroyTexture(presenter.texture)
		presenter.texture = nil
	}
	texture := sdl3.CreateTexture(
		presenter.renderer,
		.RGB24,
		.STREAMING,
		c.int(width),
		c.int(height),
	)
	if texture == nil {
		presenter.width = 0
		presenter.height = 0
		return SDL_SOFTWARE_TEXTURE_CREATE_ERROR, false
	}
	presenter.texture = texture
	presenter.width = width
	presenter.height = height
	return "", true
}

sdl_software_present_image :: proc(presenter: ^Sdl_Software_Presenter, image: Render_Image) -> (string, bool) {
	if image.width <= 0 || image.height <= 0 || len(image.rgb) < image.width * image.height * 3 {
		return SDL_SOFTWARE_TEXTURE_UPDATE_ERROR, false
	}
	texture_error, texture_ok := sdl_software_presenter_ensure_texture(presenter, image.width, image.height)
	if !texture_ok {
		return texture_error, false
	}
	if !sdl3.UpdateTexture(presenter.texture, nil, raw_data(image.rgb), c.int(image.width * 3)) {
		return SDL_SOFTWARE_TEXTURE_UPDATE_ERROR, false
	}
	if !sdl3.RenderClear(presenter.renderer) {
		return SDL_SOFTWARE_RENDER_CLEAR_ERROR, false
	}
	if !sdl3.RenderTexture(presenter.renderer, presenter.texture, nil, nil) {
		return SDL_SOFTWARE_RENDER_TEXTURE_ERROR, false
	}
	if !sdl3.RenderPresent(presenter.renderer) {
		return SDL_SOFTWARE_RENDER_PRESENT_ERROR, false
	}
	return "", true
}

sdl_run_live_project_loop :: proc(
	project: ^Live_Project,
	max_frames: int,
	hidden: bool,
	editor: bool,
	emit_live_reload_output: bool,
	report: ^Live_Project_Run_Report,
) -> (Sdl_Run_Loop_Result, Simulation_Run_Result, string, bool) {
	init_err := sdl_video_init()
	if init_err != .None {
		return Sdl_Run_Loop_Result{}, Simulation_Run_Result{}, sdl_window_error_message(init_err), false
	}
	defer sdl_video_quit()

	window, window_err := sdl_window_create(sdl_window_default_options(hidden))
	if window_err != .None {
		return Sdl_Run_Loop_Result{}, Simulation_Run_Result{}, sdl_window_error_message(window_err), false
	}
	defer sdl_window_destroy(&window)

	size, size_err := sdl_window_get_size(window.window)
	if size_err != .None {
		return Sdl_Run_Loop_Result{}, Simulation_Run_Result{}, sdl_window_error_message(size_err), false
	}

	presenter, presenter_error, presenter_ok := sdl_software_presenter_init(window.window)
	if !presenter_ok {
		return Sdl_Run_Loop_Result{}, Simulation_Run_Result{}, presenter_error, false
	}
	defer sdl_software_presenter_deinit(&presenter)
	editor_visible := editor
	text_input_started := false
	sdl_run_loop_sync_text_input(window.window, editor_visible, &text_input_started)
	defer if text_input_started do _ = sdl3.StopTextInput(window.window)

	result := Sdl_Run_Loop_Result{
		window_opened = true,
		window_width = size.width,
		window_height = size.height,
		pixel_width = size.pixel_width,
		pixel_height = size.pixel_height,
		editor_visible = editor_visible,
	}

	completed_frames := 0
	previous_ticks_ns := sdl3.GetTicksNS()
	input_state := Sdl_Input_State{}
	editor_state := Editor_Test_Input_State{}
	fly_camera := Sdl_Fly_Camera_State{}
	relative_mouse_active := false
	defer editor_test_input_state_free(&editor_state)
	defer if relative_mouse_active do _ = sdl3.SetWindowRelativeMouseMode(window.window, false)
	for !sdl_run_loop_frame_limit_reached(completed_frames, max_frames) {
		frame_input := sdl_input_begin_frame(input_state, size, editor_visible)
		if sdl_run_loop_pump_input_events(&input_state, &frame_input, size) {
			result.quit_requested = true
			break
		}
		sdl_run_loop_apply_editor_toggle(&editor_visible, &frame_input)
		sdl_run_loop_sync_text_input(window.window, editor_visible, &text_input_started)
		current_ticks_ns := sdl3.GetTicksNS()
		delta_seconds := sdl_run_loop_delta_seconds(previous_ticks_ns, current_ticks_ns)
		previous_ticks_ns = current_ticks_ns
		frame := sdl_run_loop_tick_live_project(project, report, &editor_state, &fly_camera, frame_input, editor_visible, delta_seconds, completed_frames)
		sdl_run_loop_sync_relative_mouse(window.window, fly_camera.active, &relative_mouse_active)
		sdl_run_loop_flush_editor_clipboard(&editor_state)
		if !frame.ok {
			result.completed_frames = frame.completed_frames
			return result, frame, "", true
		}
		completed_frames = frame.completed_frames
		if emit_live_reload_output && report != nil {
			result.live_reload_events_printed = print_run_reload_events_since(report^, result.live_reload_events_printed)
		}

		size, size_err = sdl_window_get_size(window.window)
		if size_err != .None {
			result.completed_frames = completed_frames
			return result, Simulation_Run_Result{}, sdl_window_error_message(size_err), false
		}
		result.window_width = size.width
		result.window_height = size.height
		result.pixel_width = size.pixel_width
		result.pixel_height = size.pixel_height
		if size.pixel_width <= 0 || size.pixel_height <= 0 {
			result.completed_frames = completed_frames
			return result, Simulation_Run_Result{}, SDL_SOFTWARE_INVALID_SIZE_ERROR, false
		}

		selected_entity_id := ""
		if selected_id, selected_ok := editor_test_selected_entity_id(editor_state, project.check.scene.world); selected_ok {
			selected_entity_id = selected_id
		}
		image, image_ok := render_image_from_scene(project.check.scene.world, Render_Options{
			target_path = project.check.project.default_scene,
			width = size.pixel_width,
			height = size.pixel_height,
			pixel_scale = DEFAULT_RENDER_PIXEL_SCALE,
			editor = editor_visible,
			selected_entity_id = selected_entity_id,
			inspector_scroll_y = editor_state.inspector_scroll_y,
			gizmo_axis = editor_state.dragging_axis,
			gizmo_hover_axis = editor_state.hovered_axis,
			gizmo_local_space = editor_state.gizmo_local_space,
			camera_override_enabled = fly_camera.initialized,
			camera_override = sdl_fly_camera_render_camera(fly_camera),
			backend = .Software,
		})
		if !image_ok {
			result.completed_frames = completed_frames
			return result, Simulation_Run_Result{}, render_image_error_message(.Out_Of_Memory), false
		}
		present_error, present_ok := sdl_software_present_image(&presenter, image)
		render_image_free(&image)
		if !present_ok {
			result.completed_frames = completed_frames
			return result, Simulation_Run_Result{}, present_error, false
		}
		result.presented = true
		result.surface_width = size.pixel_width
		result.surface_height = size.pixel_height
		extract, extract_err := render_extract_scene(project.check.scene.world)
		if extract_err == .None {
			result.renderable_count = extract.renderables + extract.ui_rects + extract.ui_texts
		}
		result.editor_input_routed = editor_visible
		result.editor_visible = editor_visible
		result.editor_paused = editor_state.paused
		if selected_id, selected_ok := editor_test_selected_entity_id(editor_state, project.check.scene.world); selected_ok {
			result.editor_selected_entity_id = selected_id
		} else {
			result.editor_selected_entity_id = ""
		}
		result.fly_camera_active = fly_camera.active
		result.fly_camera_position = fly_camera.position
		result.fly_camera_rotation = fly_camera.rotation

		if max_frames == 0 {
			sdl3.Delay(SDL_RUN_LOOP_IDLE_DELAY_MS)
		}
	}
	result.completed_frames = completed_frames
	return result, Simulation_Run_Result{ok = true, completed_frames = completed_frames}, "", true
}

sdl_run_live_project_wgpu_loop :: proc(
	project: ^Live_Project,
	target_path: string,
	max_frames: int,
	hidden: bool,
	editor: bool,
	emit_live_reload_output: bool,
	report: ^Live_Project_Run_Report,
) -> (Sdl_Run_Loop_Result, Simulation_Run_Result, string, bool) {
	path, found := wgpu_find_default_offscreen_library(target_path)
	if !found && target_path != "." {
		path, found = wgpu_find_default_offscreen_library(".")
	}
	if !found {
		return Sdl_Run_Loop_Result{}, Simulation_Run_Result{}, WGPU_OFFSCREEN_LIBRARY_NOT_FOUND, false
	}
	defer delete(path)

	loaded, missing, loaded_ok := wgpu_load_offscreen_library(path)
	defer wgpu_unload_offscreen_library(&loaded)
	if !loaded_ok {
		if missing == "" {
			missing = WGPU_OFFSCREEN_LIBRARY_LOAD_ERROR
		}
		return Sdl_Run_Loop_Result{}, Simulation_Run_Result{}, missing, false
	}

	init_err := sdl_video_init()
	if init_err != .None {
		return Sdl_Run_Loop_Result{}, Simulation_Run_Result{}, sdl_window_error_message(init_err), false
	}
	defer sdl_video_quit()

	window, window_err := sdl_window_create(sdl_window_default_options(hidden))
	if window_err != .None {
		return Sdl_Run_Loop_Result{}, Simulation_Run_Result{}, sdl_window_error_message(window_err), false
	}
	defer sdl_window_destroy(&window)

	size, size_err := sdl_window_get_size(window.window)
	if size_err != .None {
		return Sdl_Run_Loop_Result{}, Simulation_Run_Result{}, sdl_window_error_message(size_err), false
	}
	if size.pixel_width <= 0 || size.pixel_height <= 0 {
		return Sdl_Run_Loop_Result{}, Simulation_Run_Result{}, WGPU_OFFSCREEN_INVALID_SIZE_ERROR, false
	}

	surface_descriptor := Sdl_WGPU_Surface_Descriptor{}
	surface_err := sdl_window_init_surface_descriptor(&surface_descriptor, window.window)
	defer sdl_wgpu_surface_descriptor_deinit(&surface_descriptor)
	if surface_err != .None {
		return Sdl_Run_Loop_Result{}, Simulation_Run_Result{}, sdl_window_error_message(surface_err), false
	}

	surface_context, surface_context_error, surface_context_ok := wgpu_surface_context_init(
		loaded.procs,
		&surface_descriptor.descriptor,
		u32(size.pixel_width),
		u32(size.pixel_height),
	)
	if !surface_context_ok {
		return Sdl_Run_Loop_Result{}, Simulation_Run_Result{}, surface_context_error, false
	}
	defer wgpu_surface_context_deinit(&surface_context)
	editor_visible := editor
	text_input_started := false
	sdl_run_loop_sync_text_input(window.window, editor_visible, &text_input_started)
	defer if text_input_started do _ = sdl3.StopTextInput(window.window)

	result := Sdl_Run_Loop_Result{
		window_opened = true,
		window_width = size.width,
		window_height = size.height,
		pixel_width = size.pixel_width,
		pixel_height = size.pixel_height,
		editor_visible = editor_visible,
	}

	completed_frames := 0
	previous_ticks_ns := sdl3.GetTicksNS()
	input_state := Sdl_Input_State{}
	editor_state := Editor_Test_Input_State{}
	fly_camera := Sdl_Fly_Camera_State{}
	relative_mouse_active := false
	defer editor_test_input_state_free(&editor_state)
	defer if relative_mouse_active do _ = sdl3.SetWindowRelativeMouseMode(window.window, false)
	for !sdl_run_loop_frame_limit_reached(completed_frames, max_frames) {
		frame_input := sdl_input_begin_frame(input_state, size, editor_visible)
		if sdl_run_loop_pump_input_events(&input_state, &frame_input, size) {
			result.quit_requested = true
			break
		}
		sdl_run_loop_apply_editor_toggle(&editor_visible, &frame_input)
		sdl_run_loop_sync_text_input(window.window, editor_visible, &text_input_started)
		current_ticks_ns := sdl3.GetTicksNS()
		delta_seconds := sdl_run_loop_delta_seconds(previous_ticks_ns, current_ticks_ns)
		previous_ticks_ns = current_ticks_ns
		frame := sdl_run_loop_tick_live_project(project, report, &editor_state, &fly_camera, frame_input, editor_visible, delta_seconds, completed_frames)
		sdl_run_loop_sync_relative_mouse(window.window, fly_camera.active, &relative_mouse_active)
		sdl_run_loop_flush_editor_clipboard(&editor_state)
		if !frame.ok {
			result.completed_frames = frame.completed_frames
			return result, frame, "", true
		}
		completed_frames = frame.completed_frames
		if emit_live_reload_output && report != nil {
			result.live_reload_events_printed = print_run_reload_events_since(report^, result.live_reload_events_printed)
		}

		size, size_err = sdl_window_get_size(window.window)
		if size_err != .None {
			result.completed_frames = completed_frames
			return result, Simulation_Run_Result{}, sdl_window_error_message(size_err), false
		}
		if size.pixel_width <= 0 || size.pixel_height <= 0 {
			result.completed_frames = completed_frames
			return result, Simulation_Run_Result{}, WGPU_OFFSCREEN_INVALID_SIZE_ERROR, false
		}
		result.window_width = size.width
		result.window_height = size.height
		result.pixel_width = size.pixel_width
		result.pixel_height = size.pixel_height

		selected_entity_id := ""
		if selected_id, selected_ok := editor_test_selected_entity_id(editor_state, project.check.scene.world); selected_ok {
			selected_entity_id = selected_id
		}
		presentation, present_error, present_ok := wgpu_surface_context_present_scene_frame(
			&surface_context,
			project.check.scene.world,
			u32(size.pixel_width),
			u32(size.pixel_height),
			editor_visible,
			selected_entity_id,
			editor_state.inspector_scroll_y,
			fly_camera.initialized,
			sdl_fly_camera_render_camera(fly_camera),
			editor_state.dragging_axis,
			editor_state.hovered_axis,
			editor_state.gizmo_local_space,
		)
		if !present_ok {
			result.completed_frames = completed_frames
			return result, Simulation_Run_Result{}, present_error, false
		}
		result.presented = true
		result.surface_width = int(presentation.width)
		result.surface_height = int(presentation.height)
		result.renderable_count = presentation.renderable_count + presentation.overlay_count
		result.editor_input_routed = editor_visible
		result.editor_visible = editor_visible
		result.editor_paused = editor_state.paused
		result.editor_selected_entity_id = selected_entity_id
		result.fly_camera_active = fly_camera.active
		result.fly_camera_position = fly_camera.position
		result.fly_camera_rotation = fly_camera.rotation

		if max_frames == 0 {
			sdl3.Delay(SDL_RUN_LOOP_IDLE_DELAY_MS)
		}
	}
	result.completed_frames = completed_frames
	return result, Simulation_Run_Result{ok = true, completed_frames = completed_frames}, "", true
}

sdl_run_loop_flush_editor_clipboard :: proc(editor_state: ^Editor_Test_Input_State) {
	if !editor_state.clipboard_changed {
		return
	}
	_ = sdl3.SetClipboardText(cstring(raw_data(editor_state.clipboard_buffer[:])))
	editor_state.clipboard_changed = false
}

sdl_fly_camera_render_camera :: proc(state: Sdl_Fly_Camera_State) -> Editor_Test_Camera_State {
	return Editor_Test_Camera_State{
		position = state.position,
		rotation = state.rotation,
		fov_y_degrees = state.fov_y_degrees,
		near = state.near,
		far = state.far,
	}
}

sdl_fly_camera_apply_to_frame_input :: proc(input: ^Frame_Input, state: Sdl_Fly_Camera_State) {
	if !state.initialized {
		return
	}
	input.camera_override_enabled = true
	input.camera_override = sdl_fly_camera_render_camera(state)
}

sdl_fly_camera_reset_after_scene_reload :: proc(state: ^Sdl_Fly_Camera_State, before, after: Source_File_Stamp) {
	if !source_file_stamp_equal(before, after) {
		state.initialized = false
		state.active = false
	}
}
