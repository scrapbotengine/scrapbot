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
Runtime_World_Proc :: #type proc(data: rawptr, world: ^World) -> string
Engine_System_Profile_Phase :: enum {
	Editor_Camera,
	Editor_Gizmo,
	UI,
	Picking,
	Render_Prepare,
	Render_Cull,
	Render_Shadow,
	Render_World,
	Render_Post,
	Render_UI,
	Render_Finish,
	Render_Submit,
	Render_Present,
	Count,
}
System_Profile_Begin_Proc :: #type proc(data: rawptr)
System_Profile_Record_Proc :: #type proc(
	data: rawptr,
	phase: Engine_System_Profile_Phase,
	duration_nanoseconds: i64,
)
System_Profile_Commit_Proc :: #type proc(data: rawptr)
Runtime_Save_Proc :: #type proc(
	data: rawptr,
	world: ^World,
	dirty_entities: []shared.Entity_UUID,
	dirty_resources: []shared.Resource_UUID,
) -> string
Render_Stats :: struct {
	draw_batches: int,
	draw_capacity: int,
	draw_database_rebuilds: u64,
	gpu_driven: bool,
	compute_culling: bool,
	gpu_timestamps_supported: bool,
	gpu_timestamps_valid: bool,
	gpu_frame_ms: f64,
	gpu_cull_ms: f64,
	gpu_shadow_ms: f64,
	gpu_world_ms: f64,
	gpu_post_ms: f64,
	gpu_bloom_ms: f64,
	gpu_composite_ms: f64,
	gpu_ui_ms: f64,
	gpu_depth_ms: f64,
	gpu_hiz_ms: f64,
	hiz_occlusion: bool,
	hiz_valid: bool,
	hiz_mip_count: int,
	visible_instances: u32,
	shadow_visible_instances: u32,
	frustum_candidates: u32,
	occlusion_culled_instances: u32,
	lod0_visible_instances: u32,
	lod1_visible_instances: u32,
	lod2_visible_instances: u32,
	lod3_visible_instances: u32,
	instance_capacity: int,
	instance_slots: int,
	visible_capacity: int,
	visible_buffer_capacity: int,
	instance_uploads: u64,
	instance_upload_bytes: u64,
	ui_vertex_rebuilds: u64,
	ui_project_vertex_rebuilds: u64,
	ui_editor_vertex_rebuilds: u64,
	ui_overlay_vertex_rebuilds: u64,
	ui_vertex_uploads: u64,
	ui_vertex_upload_bytes: u64,
}

PERFORMANCE_DIAGNOSTICS_PUBLISH_INTERVAL_FRAMES :: 5
PERFORMANCE_DIAGNOSTICS_ROLLING_WINDOW_FRAMES :: 50

Performance_Diagnostics_Accumulator :: struct {
	snapshot: shared.Performance_Diagnostics,
	active_frame_ms_samples: [PERFORMANCE_DIAGNOSTICS_ROLLING_WINDOW_FRAMES]f64,
	active_frame_ms_total: f64,
	frame_interval_ms_samples: [PERFORMANCE_DIAGNOSTICS_ROLLING_WINDOW_FRAMES]f64,
	frame_interval_ms_total: f64,
	sample_cursor: int,
	sample_count: int,
	frames_since_publish: int,
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
	cpu_culling: bool,
	window: bool,
	window_width, window_height: int,
	hot_reload: bool,
	editor: bool,
	max_frames: u32,
	framegrab_path: string,
	framegrab_region: Framegrab_Region,
	ui_script_path: string,
	ui_dump_path: string,
	frame_system: Frame_System_Proc,
	frame_system_data: rawptr,
	system_profile_begin: System_Profile_Begin_Proc,
	system_profile_record: System_Profile_Record_Proc,
	system_profile_commit: System_Profile_Commit_Proc,
	system_profile_data: rawptr,
	runtime_playback_begin: Runtime_World_Proc,
	runtime_playback_begin_data: rawptr,
	runtime_playback_stop: Runtime_World_Proc,
	runtime_playback_stop_data: rawptr,
	runtime_save: Runtime_Save_Proc,
	runtime_save_data: rawptr,
	runtime_revert: Runtime_World_Proc,
	runtime_revert_data: rawptr,
	resource_registry: ^resources.Registry,
	stats: ^Render_Stats,
	performance_diagnostics: ^Performance_Diagnostics_Accumulator,
	collect_runtime_stats: bool,
	runtime_stats: ^Runtime_Stats,
	runtime_stats_collector: ^Runtime_Stats_Collector,
	allocator_current_bytes: ^i64,
	allocator_peak_bytes: ^i64,
	log_enabled: bool,
	ui_state: ^ui.State,
	ui_driver: ^ui.Diagnostic_Driver,
	last_drawable_width: f32,
	last_drawable_height: f32,
}

performance_diagnostics_commit_frame :: proc(
	accumulator: ^Performance_Diagnostics_Accumulator,
	stats: ^Render_Stats,
	world: ^World,
	frame_interval_seconds: f32,
	active_frame_seconds: f32,
) {
	if accumulator == nil || stats == nil || world == nil {
		return
	}
	active_frame_ms := f64(max(active_frame_seconds, 0)) * 1000
	frame_interval_ms := f64(max(frame_interval_seconds, 0)) * 1000
	previous_active_frame_ms := f64(0)
	previous_frame_interval_ms := f64(0)
	if accumulator.sample_count == PERFORMANCE_DIAGNOSTICS_ROLLING_WINDOW_FRAMES {
		previous_active_frame_ms = accumulator.active_frame_ms_samples[accumulator.sample_cursor]
		previous_frame_interval_ms =
			accumulator.frame_interval_ms_samples[accumulator.sample_cursor]
	}
	accumulator.active_frame_ms_samples[accumulator.sample_cursor] = active_frame_ms
	accumulator.active_frame_ms_total += active_frame_ms - previous_active_frame_ms
	accumulator.frame_interval_ms_samples[accumulator.sample_cursor] = frame_interval_ms
	accumulator.frame_interval_ms_total += frame_interval_ms - previous_frame_interval_ms
	accumulator.sample_cursor =
		(accumulator.sample_cursor + 1) % PERFORMANCE_DIAGNOSTICS_ROLLING_WINDOW_FRAMES
	accumulator.sample_count = min(
		accumulator.sample_count + 1,
		PERFORMANCE_DIAGNOSTICS_ROLLING_WINDOW_FRAMES,
	)
	accumulator.frames_since_publish += 1
	if accumulator.frames_since_publish < PERFORMANCE_DIAGNOSTICS_PUBLISH_INTERVAL_FRAMES {
		return
	}
	average_active_frame_ms := accumulator.active_frame_ms_total / f64(accumulator.sample_count)
	average_frame_interval_ms :=
		accumulator.frame_interval_ms_total / f64(accumulator.sample_count)
	snapshot := &accumulator.snapshot
	snapshot.frame_ms = average_active_frame_ms
	if average_frame_interval_ms > 0 {
		snapshot.fps = 1000 / average_frame_interval_ms
	}
	snapshot.gpu_frame_ms = stats.gpu_frame_ms
	snapshot.gpu_timestamps_valid = stats.gpu_timestamps_valid
	snapshot.entity_count = world.scene_entity_count + world.runtime_entity_count
	snapshot.draw_batches = stats.draw_batches
	snapshot.instance_count = stats.instance_slots
	snapshot.frustum_candidates = stats.frustum_candidates
	snapshot.visible_instances = stats.visible_instances
	snapshot.occlusion_culled_instances = stats.occlusion_culled_instances
	snapshot.sample_frames = accumulator.sample_count
	snapshot.revision += 1
	accumulator.frames_since_publish = 0
}

renderer_window_size :: proc(config: Run_Config) -> (int, int) {
	width := config.window_width
	height := config.window_height
	if width <= 0 {
		width = shared.DEFAULT_WINDOW_WIDTH
	}
	if height <= 0 {
		height = shared.DEFAULT_WINDOW_HEIGHT
	}
	return width, height
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
	diagnostic_driver: ui.Diagnostic_Driver
	diagnostic_driver_loaded := false
	if run_config.ui_script_path != "" {
		if run_config.ui_state == nil {
			return frame, "UI diagnostic scripts require an active UI state"
		}
		if load_err := ui.diagnostic_driver_load(&diagnostic_driver, run_config.ui_script_path);
		   load_err != "" {
			return frame, load_err
		}
		diagnostic_driver_loaded = true
		run_config.ui_driver = &diagnostic_driver
		if run_config.max_frames == 0 {
			run_config.max_frames = 240
		}
	}
	defer {
		if run_config.ui_dump_path != "" {
			dump_width := run_config.last_drawable_width
			dump_height := run_config.last_drawable_height
			if dump_width <= 0 {
				dump_width = 1280
			}
			if dump_height <= 0 {
				dump_height = 720
			}
			if dump_err := ui.diagnostic_driver_write_dump(
				run_config.ui_dump_path,
				run_config.ui_state,
				world,
				dump_width,
				dump_height,
				run_config.ui_driver,
			); dump_err != "" && err == "" {
				err = dump_err
			}
		}
		if diagnostic_driver_loaded {
			ui.diagnostic_driver_destroy(&diagnostic_driver)
		}
	}
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
			render_list: shared.Render_List
			defer ecs.destroy_render_list(&render_list)
			frame_count := run_config.max_frames
			if frame_count == 0 {
				frame_count = 1
			}
			for i in 0 ..< frame_count {
				active_frame_start := time.tick_now()
				begin_system_profile_frame(&run_config)
				frame_start := begin_runtime_frame(&run_config)
				if err = run_frame_system(&run_config, world, 1.0 / 60.0); err != "" {
					return
				}
				render_prepare_start := time.tick_now()
				if run_config.runtime_stats_collector != nil ||
				   run_config.system_profile_record != nil {
					ecs.populate_resource_render_list(
						world,
						run_config.resource_registry,
						&render_list,
						run_config.ui_state != nil && run_config.ui_state.editor_visible,
					)
					if run_config.stats != nil {
						run_config.stats.draw_batches = ecs.render_batch_count(&render_list)
					}
				}
				record_system_profile_phase(&run_config, .Render_Prepare, render_prepare_start)
				finish_runtime_frame(&run_config, world, frame_start)
				performance_diagnostics_commit_frame(
					run_config.performance_diagnostics,
					run_config.stats,
					world,
					1.0 / 60.0,
					frame_active_seconds(active_frame_start),
				)
				render_phases := [8]Engine_System_Profile_Phase {
					Engine_System_Profile_Phase.Render_Cull,
					Engine_System_Profile_Phase.Render_Shadow,
					Engine_System_Profile_Phase.Render_World,
					Engine_System_Profile_Phase.Render_Post,
					Engine_System_Profile_Phase.Render_UI,
					Engine_System_Profile_Phase.Render_Finish,
					Engine_System_Profile_Phase.Render_Submit,
					Engine_System_Profile_Phase.Render_Present,
				}
				for phase in render_phases {
					record_system_profile_phase(&run_config, phase, time.tick_now())
				}
				commit_system_profile_frame(&run_config)
				if run_config.ui_driver != nil &&
				   ui.diagnostic_driver_is_complete(run_config.ui_driver) {
					break
				}
			}
			if run_config.ui_driver != nil &&
			   !ui.diagnostic_driver_is_complete(run_config.ui_driver) {
				return frame, fmt.tprintf(
					"UI diagnostic script did not complete within %d frames",
					frame_count,
				)
			}
			if run_config.window {
				window_width, window_height := renderer_window_size(run_config)
				window_err := platform.open_runtime_window("Scrapbot", window_width, window_height)
				if window_err != "" {
					return frame, window_err
				}
				defer platform.close_runtime_window()
				platform.pump_runtime_window_events()
			}
			ecs.reconcile_render_instances(world, run_config.resource_registry)
			if run_config.stats != nil {
				ecs.populate_resource_render_list(
					world,
					run_config.resource_registry,
					&render_list,
					run_config.ui_state != nil && run_config.ui_state.editor_visible,
				)
				run_config.stats.draw_batches = ecs.render_batch_count(&render_list)
			}

			renderer: Null_Renderer
			return renderer_submit(&renderer, world), ""
		case .WGPU:
			frame = ecs.render_frame_from_world(world)
			if run_config.window {
				window_width, window_height := renderer_window_size(run_config)
				window_err := platform.open_runtime_window(
					"Scrapbot WGPU",
					window_width,
					window_height,
				)
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

begin_system_profile_frame :: proc(config: ^Run_Config) {
	if config != nil && config.system_profile_begin != nil {
		config.system_profile_begin(config.system_profile_data)
	}
}

record_system_profile_phase :: proc(
	config: ^Run_Config,
	phase: Engine_System_Profile_Phase,
	start: time.Tick,
) {
	if config == nil || config.system_profile_record == nil {
		return
	}
	finish := time.tick_now()
	config.system_profile_record(
		config.system_profile_data,
		phase,
		time.duration_nanoseconds(time.tick_diff(start, finish)),
	)
}

commit_system_profile_frame :: proc(config: ^Run_Config) {
	if config != nil && config.system_profile_commit != nil {
		config.system_profile_commit(config.system_profile_data)
	}
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

frame_active_seconds :: proc(start: time.Tick) -> f32 {
	finish := time.tick_now()
	return f32(f64(time.tick_diff(start, finish)) / 1_000_000_000.0)
}

run_frame_system_unmeasured :: proc(
	config: ^Run_Config,
	world: ^World,
	delta_seconds: f32,
	drawable_width: f32 = 1280,
	drawable_height: f32 = 720,
) -> string {
	if ui.consume_playback_begin_request(config.ui_state) {
		if config.runtime_playback_begin == nil {
			return "editor playback requires an authoring snapshot callback"
		}
		if err := config.runtime_playback_begin(config.runtime_playback_begin_data, world);
		   err != "" {
			return err
		}
	}
	if ui.consume_playback_stop_request(config.ui_state) {
		selected_uuid, had_selection := ui.editor_selected_uuid(config.ui_state, world)
		if config.runtime_playback_stop == nil {
			return "editor stop requires an authoring restore callback"
		}
		if err := config.runtime_playback_stop(config.runtime_playback_stop_data, world);
		   err != "" {
			return err
		}
		ui.editor_world_restored(config.ui_state, world, selected_uuid, had_selection)
	}
	if ui.consume_scene_save_request(config.ui_state) {
		save_err := "editor save requires a runtime save callback"
		if config.runtime_save != nil {
			save_err = config.runtime_save(
				config.runtime_save_data,
				world,
				config.ui_state.editor_dirty_entities[:],
				config.ui_state.editor_dirty_resources[:],
			)
		}
		ui.complete_scene_save(config.ui_state, save_err == "")
		if save_err != "" {
			fmt.eprintf("[editor] failed to save scene: %s\n", save_err)
		}
	}
	if ui.consume_scene_revert_request(config.ui_state) {
		selected_uuid, had_selection := ui.editor_selected_uuid(config.ui_state, world)
		revert_err := "editor revert requires a runtime revert callback"
		if config.runtime_revert != nil {
			revert_err = config.runtime_revert(config.runtime_revert_data, world)
		}
		ui.complete_scene_revert(config.ui_state, revert_err == "")
		if revert_err == "" {
			ui.editor_world_restored(config.ui_state, world, selected_uuid, had_selection)
		} else {
			fmt.eprintf("[editor] failed to revert scene: %s\n", revert_err)
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
		config.last_drawable_width = drawable_width
		config.last_drawable_height = drawable_height
		config.ui_state.editor_pixel_density = platform.runtime_window_pixel_density()
		viewport := ui.editor_viewport(config.ui_state, drawable_width, drawable_height)
		camera_input := platform.runtime_scene_camera_input(
			config.ui_state.editor_visible,
			viewport.x,
			viewport.y,
			viewport.width,
			viewport.height,
		)
		if config.ui_driver != nil {
			camera_input = {}
		}
		config.ui_state.editor_scene_camera_captures_input = camera_input.look_active
		if mode, requested := platform.consume_editor_gizmo_mode();
		   requested &&
		   config.ui_state.editor_visible &&
		   !camera_input.look_active &&
		   !ui.has_text_focus(config.ui_state) { ui.editor_set_gizmo_mode(config.ui_state, mode) }
		camera_system_start := time.tick_now()
		ecs.editor_scene_camera_system(
			world,
			camera_input,
			delta_seconds,
			config.ui_state.editor_visible,
		)
		record_system_profile_phase(config, .Editor_Camera, camera_system_start)
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
			editor_toggle = platform_keyboard.editor_toggle,
			run_stop = platform_keyboard.run_stop,
			pause_step = platform_keyboard.pause_step,
		}
		if config.ui_driver != nil {
			driver_pointer, driver_keyboard, driver_err := ui.diagnostic_driver_input(
				config.ui_driver,
				config.ui_state,
				world,
				drawable_width,
				drawable_height,
			)
			if driver_err != "" {
				return driver_err
			}
			pointer = driver_pointer
			keyboard = driver_keyboard
		}
		camera, has_camera := ecs.active_camera_instance(world, config.ui_state.editor_visible)
		gizmo_system_start := time.tick_now()
		gizmo_pointer := pointer
		if ui.editor_pointer_over_gizmo_toolbar(config.ui_state, pointer) {
			gizmo_pointer = {}
		}
		editor_camera_mesh_system(
			config.ui_state,
			world,
			viewport,
			camera,
			has_camera,
			config.ui_state.editor_visible,
		)
		editor_transform_gizmo_system(
			config.ui_state,
			world,
			gizmo_pointer,
			viewport,
			camera,
			has_camera,
		)
		if err := ui.rebuild_editor_world_overlay(config.ui_state); err != "" {
			return err
		}
		record_system_profile_phase(config, .Editor_Gizmo, gizmo_system_start)
		ui_system_start := time.tick_now()
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
		record_system_profile_phase(config, .UI, ui_system_start)
		cursor: platform.Runtime_Pointer_Cursor
		switch ui.current_pointer_cursor(config.ui_state) {
			case .Default:
			case .Horizontal_Resize:
				cursor = .Horizontal_Resize
			case .Vertical_Resize:
				cursor = .Vertical_Resize
		}
		platform.set_runtime_pointer_cursor(cursor)
		picking_system_start := time.tick_now()
		if config.ui_state.editor_pick_requested {
			config.ui_state.editor_pick_requested = false
			picked, found := editor_pick_camera_mesh(
				config.ui_state,
				config.ui_state.editor_pick_position,
			)
			if !found && config.resource_registry != nil {
				list := ecs.build_resource_render_list(
					world,
					config.resource_registry,
					config.ui_state.editor_visible,
				); defer ecs.destroy_render_list(&list)
				picked, found = editor_pick_entity(
					&list,
					config.resource_registry,
					config.ui_state.editor_pick_position,
					viewport,
				)
			}
			if found {
				ui.editor_select_entity(
					config.ui_state,
					world,
					picked,
					drawable_height / max(config.ui_state.editor_pixel_density, 1),
				)
			} else {
				ui.editor_clear_selection(config.ui_state)
			}
		}
		record_system_profile_phase(config, .Picking, picking_system_start)
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
