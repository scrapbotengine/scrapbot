package main

import "core:c"
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
	editor_paused:             bool,
	editor_selected_entity_id: string,
}

Sdl_Software_Presenter :: struct {
	renderer: ^sdl3.Renderer,
	texture: ^sdl3.Texture,
	width:    int,
	height:   int,
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
	text_input_started := editor && sdl3.StartTextInput(window.window)
	defer if text_input_started do _ = sdl3.StopTextInput(window.window)

	result := Sdl_Run_Loop_Result{
		window_opened = true,
		window_width = size.width,
		window_height = size.height,
		pixel_width = size.pixel_width,
		pixel_height = size.pixel_height,
	}

	completed_frames := 0
	previous_ticks_ns := sdl3.GetTicksNS()
	input_state := Sdl_Input_State{}
	editor_state := Editor_Test_Input_State{}
	defer editor_test_input_state_free(&editor_state)
	for !sdl_run_loop_frame_limit_reached(completed_frames, max_frames) {
		frame_input := sdl_input_begin_frame(input_state, size, editor)
		if sdl_run_loop_pump_input_events(&input_state, &frame_input, size) {
			result.quit_requested = true
			break
		}
		current_ticks_ns := sdl3.GetTicksNS()
		delta_seconds := sdl_run_loop_delta_seconds(previous_ticks_ns, current_ticks_ns)
		previous_ticks_ns = current_ticks_ns
		frame := live_project_run_frame_with_input(project, delta_seconds, completed_frames, report, &editor_state, frame_input)
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

		image, image_ok := render_image_from_scene(project.check.scene.world, Render_Options{
			target_path = project.check.project.default_scene,
			width = size.pixel_width,
			height = size.pixel_height,
			pixel_scale = DEFAULT_RENDER_PIXEL_SCALE,
			editor = editor,
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
		result.editor_input_routed = editor
		result.editor_paused = editor_state.paused
		if selected_id, selected_ok := editor_test_selected_entity_id(editor_state, project.check.scene.world); selected_ok {
			result.editor_selected_entity_id = selected_id
		} else {
			result.editor_selected_entity_id = ""
		}

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
	text_input_started := editor && sdl3.StartTextInput(window.window)
	defer if text_input_started do _ = sdl3.StopTextInput(window.window)

	result := Sdl_Run_Loop_Result{
		window_opened = true,
		window_width = size.width,
		window_height = size.height,
		pixel_width = size.pixel_width,
		pixel_height = size.pixel_height,
	}

	completed_frames := 0
	previous_ticks_ns := sdl3.GetTicksNS()
	input_state := Sdl_Input_State{}
	editor_state := Editor_Test_Input_State{}
	defer editor_test_input_state_free(&editor_state)
	for !sdl_run_loop_frame_limit_reached(completed_frames, max_frames) {
		frame_input := sdl_input_begin_frame(input_state, size, editor)
		if sdl_run_loop_pump_input_events(&input_state, &frame_input, size) {
			result.quit_requested = true
			break
		}
		current_ticks_ns := sdl3.GetTicksNS()
		delta_seconds := sdl_run_loop_delta_seconds(previous_ticks_ns, current_ticks_ns)
		previous_ticks_ns = current_ticks_ns
		frame := live_project_run_frame_with_input(project, delta_seconds, completed_frames, report, &editor_state, frame_input)
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

		presentation, present_error, present_ok := wgpu_surface_context_present_scene_frame(
			&surface_context,
			project.check.scene.world,
			u32(size.pixel_width),
			u32(size.pixel_height),
			editor,
		)
		if !present_ok {
			result.completed_frames = completed_frames
			return result, Simulation_Run_Result{}, present_error, false
		}
		result.presented = true
		result.surface_width = int(presentation.width)
		result.surface_height = int(presentation.height)
		result.renderable_count = presentation.renderable_count + presentation.overlay_count
		result.editor_input_routed = editor
		result.editor_paused = editor_state.paused
		if selected_id, selected_ok := editor_test_selected_entity_id(editor_state, project.check.scene.world); selected_ok {
			result.editor_selected_entity_id = selected_id
		} else {
			result.editor_selected_entity_id = ""
		}

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
