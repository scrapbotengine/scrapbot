package main

import sdl3 "vendor:sdl3"

SDL_RUN_LOOP_FIXED_DELTA_SECONDS :: f32(1.0 / 60.0)
SDL_RUN_LOOP_MAX_DELTA_SECONDS :: f32(0.1)
SDL_RUN_LOOP_IDLE_DELAY_MS :: sdl3.Uint32(1)

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

sdl_run_live_project_loop :: proc(
	project: ^Live_Project,
	max_frames: int,
	hidden: bool,
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

	result := Sdl_Run_Loop_Result{
		window_opened = true,
		window_width = size.width,
		window_height = size.height,
		pixel_width = size.pixel_width,
		pixel_height = size.pixel_height,
	}

	completed_frames := 0
	previous_ticks_ns := sdl3.GetTicksNS()
	for !sdl_run_loop_frame_limit_reached(completed_frames, max_frames) {
		if sdl_run_loop_pump_events() {
			result.quit_requested = true
			break
		}
		current_ticks_ns := sdl3.GetTicksNS()
		delta_seconds := sdl_run_loop_delta_seconds(previous_ticks_ns, current_ticks_ns)
		previous_ticks_ns = current_ticks_ns
		frame := live_project_run_frame_with_report(project, delta_seconds, completed_frames, report)
		if !frame.ok {
			result.completed_frames = frame.completed_frames
			return result, frame, "", true
		}
		completed_frames = frame.completed_frames
		if emit_live_reload_output && report != nil {
			result.live_reload_events_printed = print_run_reload_events_since(report^, result.live_reload_events_printed)
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

	result := Sdl_Run_Loop_Result{
		window_opened = true,
		window_width = size.width,
		window_height = size.height,
		pixel_width = size.pixel_width,
		pixel_height = size.pixel_height,
	}

	completed_frames := 0
	previous_ticks_ns := sdl3.GetTicksNS()
	for !sdl_run_loop_frame_limit_reached(completed_frames, max_frames) {
		if sdl_run_loop_pump_events() {
			result.quit_requested = true
			break
		}
		current_ticks_ns := sdl3.GetTicksNS()
		delta_seconds := sdl_run_loop_delta_seconds(previous_ticks_ns, current_ticks_ns)
		previous_ticks_ns = current_ticks_ns
		frame := live_project_run_frame_with_report(project, delta_seconds, completed_frames, report)
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

		presentation, present_error, present_ok := wgpu_present_surface_scene(
			loaded.procs,
			&surface_descriptor.descriptor,
			project.check.scene.world,
			u32(size.pixel_width),
			u32(size.pixel_height),
		)
		if !present_ok {
			result.completed_frames = completed_frames
			return result, Simulation_Run_Result{}, present_error, false
		}
		result.presented = true
		result.surface_width = int(presentation.width)
		result.surface_height = int(presentation.height)
		result.renderable_count = presentation.renderable_count

		if max_frames == 0 {
			sdl3.Delay(SDL_RUN_LOOP_IDLE_DELAY_MS)
		}
	}
	result.completed_frames = completed_frames
	return result, Simulation_Run_Result{ok = true, completed_frames = completed_frames}, "", true
}
