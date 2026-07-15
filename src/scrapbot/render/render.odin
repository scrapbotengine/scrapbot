package render

import ecs "../ecs"
import platform "../platform"
import resources "../resources"
import shared "../shared"
import ui "../ui"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"

Renderer_Backend :: shared.Renderer_Backend
Frame_System_Proc :: #type proc(data: rawptr, world: ^World, delta_seconds: f32) -> string
Runtime_Reset_Proc :: #type proc(data: rawptr, world: ^World) -> string
Runtime_Save_Proc :: #type proc(data: rawptr, world: ^World) -> string
Render_Stats :: struct {
	draw_batches: int,
}
Framegrab_Region :: struct {
	x, y, width, height: u32,
}
Runtime_Stats :: struct {
	enabled: bool,
	frames: u32,
	warmup_frames: u32,
	sample_frames: u32,
	early_update_ns_per_frame: i64,
	late_update_ns_per_frame: i64,
	cpu_growth_ratio: f64,
	allocator_peak_bytes: i64,
	allocator_early_bytes: i64,
	allocator_late_bytes: i64,
	allocator_final_bytes: i64,
	early_storage: ecs.World_Storage_Stats,
	late_storage: ecs.World_Storage_Stats,
	peak_storage: ecs.World_Storage_Stats,
	final_storage: ecs.World_Storage_Stats,
}
Runtime_Stats_Collector :: struct {
	report: ^Runtime_Stats,
	early_start: u32,
	late_start: u32,
	early_update_ns: i64,
	late_update_ns: i64,
	early_count: u32,
	late_count: u32,
	allocator_current_bytes: ^i64,
	allocator_peak_bytes: ^i64,
}
Run_Config :: struct {
	backend: Renderer_Backend,
	window: bool,
	hot_reload: bool,
	editor: bool,
	max_frames: u32,
	framegrab_path: string,
	framegrab_region: Framegrab_Region,
	frame_system: Frame_System_Proc,
	frame_system_data: rawptr,
	runtime_reset: Runtime_Reset_Proc,
	runtime_reset_data: rawptr,
	runtime_save: Runtime_Save_Proc,
	runtime_save_data: rawptr,
	resource_registry: ^resources.Registry,
	stats: ^Render_Stats,
	collect_runtime_stats: bool,
	runtime_stats: ^Runtime_Stats,
	runtime_stats_collector: ^Runtime_Stats_Collector,
	allocator_current_bytes: ^i64,
	allocator_peak_bytes: ^i64,
	log_enabled: bool,
	ui_state: ^ui.State,
}
World :: shared.World
Render_Frame :: shared.Render_Frame

parse_framegrab_region :: proc(value: string) -> (Framegrab_Region, bool) {
	if value == "" { return {}, true }
	parts := strings.split(value, ","); defer delete(parts)
	if len(parts) != 4 { return {}, false }
	values: [4]u32
	for part, index in parts {
		parsed, ok := strconv.parse_uint(strings.trim_space(part))
		if !ok || parsed > uint(0xFFFF_FFFF) { return {}, false }
		values[index] = u32(parsed)
	}
	if values[2] == 0 || values[3] == 0 { return {}, false }
	return {x = values[0], y = values[1], width = values[2], height = values[3]}, true
}

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
	if run_config.runtime_stats != nil && run_config.window && run_config.max_frames == 0 {
		return frame, "runtime statistics require a bounded windowed run; pass --frames"
	}
	collector: Runtime_Stats_Collector
	collect_runtime_stats := run_config.runtime_stats != nil
	if collect_runtime_stats {
		init_runtime_stats_collector(
			&collector,
			run_config.runtime_stats,
			run_config.max_frames,
			run_config.allocator_current_bytes,
			run_config.allocator_peak_bytes,
		)
		run_config.runtime_stats_collector = &collector
	}
	defer {
		if collect_runtime_stats {
			finish_runtime_stats_collector(&collector, world)
		}
	}
	switch run_config.backend {
		case .Null:
			frame_count := run_config.max_frames
			if frame_count == 0 {
				frame_count = 1
			}
			for i in 0 ..< frame_count {
				frame_start := begin_runtime_frame(&run_config)
				if err = run_frame_system(&run_config, world, 1.0 / 60.0); err != "" {
					return
				}
				if run_config.runtime_stats_collector != nil {
					list := ecs.build_resource_render_list(
						world,
						run_config.resource_registry,
						run_config.ui_state != nil && run_config.ui_state.editor_visible,
					)
					if run_config.stats != nil {
						run_config.stats.draw_batches = ecs.render_batch_count(&list)
					}
					ecs.destroy_render_list(&list)
				}
				finish_runtime_frame(&run_config, world, frame_start)
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
				list := ecs.build_resource_render_list(
					world,
					run_config.resource_registry,
					run_config.ui_state != nil && run_config.ui_state.editor_visible,
				)
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
				window_err := platform.open_hidden_runtime_window(
					"Scrapbot WGPU Headless",
					1280,
					720,
				)
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

run_frame_system :: proc(
	config: ^Run_Config,
	world: ^World,
	delta_seconds: f32,
	drawable_width: f32 = 1280,
	drawable_height: f32 = 720,
) -> string {
	return run_frame_system_unmeasured(
		config,
		world,
		delta_seconds,
		drawable_width,
		drawable_height,
	)
}

begin_runtime_frame :: proc(config: ^Run_Config) -> time.Tick {
	if config == nil || config.runtime_stats_collector == nil { return {} }
	return time.tick_now()
}

finish_runtime_frame :: proc(config: ^Run_Config, world: ^World, start: time.Tick) {
	if config == nil || config.runtime_stats_collector == nil { return }
	finish := time.tick_now()
	record_runtime_frame(
		config.runtime_stats_collector,
		world,
		time.duration_nanoseconds(time.tick_diff(start, finish)),
	)
}

run_frame_system_unmeasured :: proc(
	config: ^Run_Config,
	world: ^World,
	delta_seconds: f32,
	drawable_width: f32 = 1280,
	drawable_height: f32 = 720,
) -> string {
	if ui.consume_scene_reload_request(config.ui_state) {
		if config.runtime_reset == nil {
			return "editor stop requires a runtime reset callback"
		}
		if err := config.runtime_reset(config.runtime_reset_data, world); err != "" {
			return err
		}
	}
	if ui.consume_scene_save_request(config.ui_state) {
		save_err := "editor save requires a runtime save callback"
		if config.runtime_save != nil {
			save_err = config.runtime_save(config.runtime_save_data, world)
		}
		ui.complete_scene_save(config.ui_state, save_err == "")
		if save_err != "" {
			fmt.eprintf("[editor] failed to save scene: %s\n", save_err)
		}
	}
	simulation_delta, run_simulation := ui.consume_simulation_delta(config.ui_state, delta_seconds)
	if run_simulation {
		if config.frame_system == nil {
			ecs.advance_time(&world.time, simulation_delta)
		} else if err := config.frame_system(config.frame_system_data, world, simulation_delta);
		   err != "" { return err }
	}
	if config.ui_state != nil {
		config.ui_state.editor_pixel_density = platform.runtime_window_pixel_density()
		if platform.consume_editor_toggle() {
			config.ui_state.editor_visible = !config.ui_state.editor_visible
		}
		viewport := ui.editor_viewport(config.ui_state, drawable_width, drawable_height)
		camera_input := platform.runtime_scene_camera_input(
			config.ui_state.editor_visible,
			viewport.x,
			viewport.y,
			viewport.width,
			viewport.height,
		)
		config.ui_state.editor_scene_camera_captures_input = camera_input.look_active
		if mode, requested := platform.consume_editor_gizmo_mode();
		   requested &&
		   config.ui_state.editor_visible &&
		   !camera_input.look_active &&
		   !ui.has_text_focus(config.ui_state) { ui.editor_set_gizmo_mode(config.ui_state, mode) }
		ecs.editor_scene_camera_system(
			world,
			camera_input,
			delta_seconds,
			config.ui_state.editor_visible,
		)
		platform_pointer := platform.runtime_pointer_state_in_pixels()
		pointer := ui.Pointer_Input {
			position = {platform_pointer.x, platform_pointer.y},
			wheel_y = platform_pointer.wheel_y,
			primary_down = platform_pointer.primary_down,
			available = platform_pointer.available,
		}
		if config.ui_state.editor_scene_camera_captures_input { pointer = {} }
		platform_keyboard := platform.runtime_text_input()
		keyboard := ui.Keyboard_Input {
			text = platform_keyboard.text,
			left = platform_keyboard.left,
			right = platform_keyboard.right,
			up = platform_keyboard.up,
			down = platform_keyboard.down,
			home = platform_keyboard.home,
			end = platform_keyboard.end,
			backspace = platform_keyboard.backspace,
			delete_forward = platform_keyboard.delete_forward,
			tab = platform_keyboard.tab,
			shift = platform_keyboard.shift,
			fine = platform_keyboard.fine,
			enter = platform_keyboard.enter,
			escape = platform_keyboard.escape,
			select_all = platform_keyboard.select_all,
			save = platform_keyboard.save,
			undo = platform_keyboard.undo,
			redo = platform_keyboard.redo,
		}
		camera, has_camera := ecs.active_camera_instance(world, config.ui_state.editor_visible)
		editor_transform_gizmo_system(
			config.ui_state,
			world,
			pointer,
			viewport,
			camera,
			has_camera,
		)
		if err := ui.reconcile(
			config.ui_state,
			world,
			1280,
			720,
			pointer,
			drawable_width,
			drawable_height,
			delta_seconds,
			keyboard,
			config.resource_registry,
		); err != "" { return err }
		cursor: platform.Runtime_Pointer_Cursor
		switch ui.current_pointer_cursor(config.ui_state) {
			case .Default:
			case .Horizontal_Resize:
				cursor = .Horizontal_Resize
			case .Vertical_Resize:
				cursor = .Vertical_Resize
		}
		platform.set_runtime_pointer_cursor(cursor)
		if config.ui_state.editor_pick_requested {
			config.ui_state.editor_pick_requested = false
			if config.resource_registry != nil {
				list := ecs.build_resource_render_list(
					world,
					config.resource_registry,
					config.ui_state.editor_visible,
				); defer ecs.destroy_render_list(&list)
				if entity, found := editor_pick_entity(
					&list,
					config.resource_registry,
					config.ui_state.editor_pick_position,
					viewport,
				);
				found { ui.editor_select_entity(config.ui_state, world, entity, drawable_height / max(config.ui_state.editor_pixel_density, 1)) } else { ui.editor_clear_selection(config.ui_state) }
			}
		}
		return ""
	}
	return ""
}

init_runtime_stats_collector :: proc(
	collector: ^Runtime_Stats_Collector,
	report: ^Runtime_Stats,
	expected_frames: u32,
	allocator_current_bytes, allocator_peak_bytes: ^i64,
) {
	frame_count := expected_frames
	if frame_count == 0 {
		frame_count = 1
	}
	sample_frames := min(max(frame_count / 10, 1), 1000)
	warmup_frames := min(frame_count / 10, 600)
	if warmup_frames + sample_frames > frame_count {
		warmup_frames = 0
	}
	report^ = {
		enabled = true,
		warmup_frames = warmup_frames,
		sample_frames = sample_frames,
	}
	collector^ = {
		report = report,
		early_start = warmup_frames,
		late_start = frame_count - sample_frames,
		allocator_current_bytes = allocator_current_bytes,
		allocator_peak_bytes = allocator_peak_bytes,
	}
}

record_runtime_frame :: proc(collector: ^Runtime_Stats_Collector, world: ^World, update_ns: i64) {
	if collector == nil || collector.report == nil {
		return
	}
	frame_index := collector.report.frames
	storage := ecs.world_storage_stats(world)
	collector.report.peak_storage = ecs.world_storage_stats_max(
		collector.report.peak_storage,
		storage,
	)
	if frame_index >= collector.early_start &&
	   frame_index < collector.early_start + collector.report.sample_frames {
		collector.early_update_ns += update_ns
		collector.early_count += 1
		collector.report.early_storage = storage
		if collector.allocator_current_bytes != nil {
			collector.report.allocator_early_bytes = collector.allocator_current_bytes^
		}
	}
	if frame_index >= collector.late_start {
		collector.late_update_ns += update_ns
		collector.late_count += 1
		collector.report.late_storage = storage
		if collector.allocator_current_bytes != nil {
			collector.report.allocator_late_bytes = collector.allocator_current_bytes^
		}
	}
	collector.report.frames += 1
}

finish_runtime_stats_collector :: proc(collector: ^Runtime_Stats_Collector, world: ^World) {
	if collector == nil || collector.report == nil {
		return
	}
	if collector.early_count > 0 {
		collector.report.early_update_ns_per_frame =
			collector.early_update_ns / i64(collector.early_count)
	}
	if collector.late_count > 0 {
		collector.report.late_update_ns_per_frame =
			collector.late_update_ns / i64(collector.late_count)
	}
	if collector.report.early_update_ns_per_frame > 0 {
		collector.report.cpu_growth_ratio =
			f64(collector.report.late_update_ns_per_frame) /
			f64(collector.report.early_update_ns_per_frame)
	}
	collector.report.final_storage = ecs.world_storage_stats(world)
	collector.report.peak_storage = ecs.world_storage_stats_max(
		collector.report.peak_storage,
		collector.report.final_storage,
	)
	if collector.allocator_peak_bytes != nil {
		collector.report.allocator_peak_bytes = collector.allocator_peak_bytes^
	}
	if collector.allocator_current_bytes != nil {
		collector.report.allocator_final_bytes = collector.allocator_current_bytes^
	}
}
