package render

import ecs "../ecs"
import platform "../platform"
import shared "../shared"

Renderer_Backend :: shared.Renderer_Backend
Run_Config :: struct {
	backend:    Renderer_Backend,
	window:     bool,
	max_frames: u32,
}
World :: shared.World
Render_Frame :: shared.Render_Frame

parse_renderer_backend :: proc(value: string) -> (backend: Renderer_Backend, ok: bool) {
	switch value {
	case "", "null", "Null":
		return .Null, true
	case "wgpu", "WGPU", "wgpu-native", "WGPU-Native":
		return .WGPU, true
	}
	return .Null, false
}

renderer_backend_name :: proc(backend: Renderer_Backend) -> string {
	switch backend {
	case .Null:
		return "null"
	case .WGPU:
		return "wgpu"
	}
	return "unknown"
}

run_renderer :: proc(config: Run_Config, world: ^World) -> (frame: Render_Frame, err: string) {
	switch config.backend {
	case .Null:
		if config.window {
			window_err := platform.open_runtime_window("Scrapbot", 1280, 720)
			if window_err != "" {
				return frame, window_err
			}
			defer platform.close_runtime_window()
			platform.pump_runtime_window_events()
		}

		renderer: Null_Renderer
		return renderer_submit(&renderer, world), ""
	case .WGPU:
		if !config.window {
			return frame, "wgpu renderer backend currently requires --window"
		}
		window_err := platform.open_runtime_window("Scrapbot WGPU", 1280, 720)
		if window_err != "" {
			return frame, window_err
		}
		defer platform.close_runtime_window()
		platform.pump_runtime_window_events()

		frame = ecs.render_frame_from_world(world)
		err = wgpu_run_window(frame, config.max_frames)
		return
	}

	return frame, "unknown renderer backend"
}
