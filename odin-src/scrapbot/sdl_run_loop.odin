package main

import sdl3 "vendor:sdl3"

Sdl_Run_Loop_Result :: struct {
	completed_frames: int,
	window_opened:    bool,
	window_width:     int,
	window_height:    int,
	pixel_width:      int,
	pixel_height:     int,
	quit_requested:   bool,
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

sdl_run_live_project_frames :: proc(
	project: ^Live_Project,
	frames: int,
	delta_seconds: f32,
	hidden: bool,
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
	for completed_frames < frames {
		if sdl_run_loop_pump_events() {
			result.quit_requested = true
			break
		}
		frame := live_project_run_frame_with_report(project, delta_seconds, completed_frames, report)
		if !frame.ok {
			result.completed_frames = frame.completed_frames
			return result, frame, "", true
		}
		completed_frames = frame.completed_frames
	}
	result.completed_frames = completed_frames
	return result, Simulation_Run_Result{ok = true, completed_frames = completed_frames}, "", true
}
