package render

import ecs "../ecs"
import platform "../platform"
import shared "../shared"

Renderer_Backend :: shared.Renderer_Backend
Frame_System_Proc :: #type proc(data: rawptr, world: ^World, delta_seconds: f32) -> string
Run_Config :: struct {
	backend:           Renderer_Backend,
	window:            bool,
	hot_reload:        bool,
	max_frames:        u32,
	framegrab_path:    string,
	frame_system:      Frame_System_Proc,
	frame_system_data: rawptr,
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
	run_config := config
	switch run_config.backend {
	case .Null:
		if err = run_frame_system(&run_config, world, 1.0 / 60.0); err != "" {
			return
		}
		if run_config.window {
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
		frame = ecs.render_frame_from_world(world)
		if run_config.window {
			window_err := platform.open_runtime_window("Scrapbot WGPU", 1280, 720)
			if window_err != "" {
				return frame, window_err
			}
			defer platform.close_runtime_window()
			platform.pump_runtime_window_events()

			err = wgpu_run_window(world, &run_config)
			frame = ecs.render_frame_from_world(world)
			return
		}
		if run_config.framegrab_path != "" {
			window_err := platform.open_hidden_runtime_window("Scrapbot WGPU Headless", 1280, 720)
			if window_err != "" {
				return frame, window_err
			}
			defer platform.close_runtime_window()
			platform.pump_runtime_window_events()

			err = wgpu_run_headless(world, &run_config)
			frame = ecs.render_frame_from_world(world)
			return
		}
		err = "wgpu renderer backend currently requires --window or --framegrab"
		return
	}

	return frame, "unknown renderer backend"
}

run_frame_system :: proc(config: ^Run_Config, world: ^World, delta_seconds: f32) -> string {
	if config.frame_system == nil {
		return ""
	}
	return config.frame_system(config.frame_system_data, world, delta_seconds)
}
