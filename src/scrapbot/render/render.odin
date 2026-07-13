package render

import ecs "../ecs"
import platform "../platform"
import shared "../shared"
import resources "../resources"
import ui "../ui"

Renderer_Backend :: shared.Renderer_Backend
Frame_System_Proc :: #type proc(data: rawptr, world: ^World, delta_seconds: f32) -> string
Render_Stats :: struct {draw_batches: int}
Run_Config :: struct {
	backend:           Renderer_Backend,
	window:            bool,
	hot_reload:        bool,
	editor:            bool,
	max_frames:        u32,
	framegrab_path:    string,
	frame_system:      Frame_System_Proc,
	frame_system_data: rawptr,
	resource_registry: ^resources.Registry,
	stats: ^Render_Stats,
	log_enabled: bool,
	ui_state: ^ui.State,
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
		frame_count := run_config.max_frames
		if frame_count == 0 {
			frame_count = 1
		}
		for i in 0..<frame_count {
			if err = run_frame_system(&run_config, world, 1.0 / 60.0); err != "" {
				return
			}
		}
		if run_config.window {
			window_err := platform.open_runtime_window("Scrapbot", 1280, 720)
			if window_err != "" {
				return frame, window_err
			}
			defer platform.close_runtime_window()
			platform.pump_runtime_window_events()
		}
		ecs.reconcile_render_instances(world, run_config.resource_registry)
		if run_config.stats != nil {
			list := ecs.build_resource_render_list(world, run_config.resource_registry)
			defer ecs.destroy_render_list(&list)
			run_config.stats.draw_batches = ecs.render_batch_count(&list)
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

run_frame_system :: proc(config: ^Run_Config, world: ^World, delta_seconds: f32, drawable_width:f32=1280, drawable_height:f32=720) -> string {
	if config.frame_system == nil {
		ecs.advance_time(&world.time, delta_seconds)
	} else if err:=config.frame_system(config.frame_system_data, world, delta_seconds);err!=""{return err}
	if config.ui_state!=nil {
		if platform.consume_editor_toggle(){config.ui_state.editor_visible=!config.ui_state.editor_visible}
		platform_pointer:=platform.runtime_pointer_state_in_pixels()
		pointer:=ui.Pointer_Input{position={platform_pointer.x,platform_pointer.y},wheel_y=platform_pointer.wheel_y,primary_down=platform_pointer.primary_down,available=platform_pointer.available}
		viewport:=ui.editor_viewport(config.ui_state,drawable_width,drawable_height);camera,has_camera:=ecs.first_camera_instance(world)
		editor_transform_gizmo_system(config.ui_state,world,pointer,viewport,camera,has_camera)
		if err:=ui.reconcile(config.ui_state,world,1280,720,pointer,drawable_width,drawable_height);err!=""{return err}
		if config.ui_state.editor_pick_requested {
			config.ui_state.editor_pick_requested=false
			if config.resource_registry!=nil {
				list:=ecs.build_resource_render_list(world,config.resource_registry);defer ecs.destroy_render_list(&list)
				if entity,found:=editor_pick_entity(&list,config.resource_registry,config.ui_state.editor_pick_position,viewport);found {ui.editor_select_entity(config.ui_state,world,entity,drawable_height)} else {ui.editor_clear_selection(config.ui_state)}
			}
		}
		return ""
	}
	return ""
}
