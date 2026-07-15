package render

import ecs "../ecs"
import ui "../ui"
import "core:testing"

@(test)
test_renderer_backend_names_parse :: proc(t: ^testing.T) {
	backend, ok := parse_renderer_backend("null")
	testing.expect(t, ok)
	testing.expect(t, backend == .Null)

	backend, ok = parse_renderer_backend("wgpu-native")
	testing.expect(t, ok)
	testing.expect(t, backend == .WGPU)

	_, ok = parse_renderer_backend("potato")
	testing.expect(t, !ok)
}

@(test)
test_framegrab_region_parses_explicit_pixel_crop :: proc(t: ^testing.T) {
	region, ok := parse_framegrab_region("240, 52, 600, 320")
	testing.expect(t, ok)
	testing.expect(t, region == Framegrab_Region{x = 240, y = 52, width = 600, height = 320})
	_, ok = parse_framegrab_region("240,52,0,320"); testing.expect(t, !ok)
	_, ok = parse_framegrab_region("240,52,600"); testing.expect(t, !ok)
}

@(test)
test_null_renderer_steps_frame_system_for_max_frames :: proc(t: ^testing.T) {
	world: World
	frame_count := 0

	_, err := run_renderer(
		Run_Config {
			backend = .Null,
			max_frames = 5,
			frame_system = test_count_frame_system,
			frame_system_data = &frame_count,
		},
		&world,
	)

	testing.expectf(t, err == "", "run_renderer failed: %s", err)
	testing.expect(t, frame_count == 5)
	testing.expect(t, world.time.frame_index == 5)
	testing.expect(t, world.time.delta_time == f32(1.0 / 60.0))
}

@(test)
test_stopped_editor_simulation_only_runs_requested_step :: proc(t: ^testing.T) {
	world: World
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	frame_count := 0
	config := Run_Config {
		frame_system = test_count_frame_system,
		frame_system_data = &frame_count,
		ui_state = state,
	}
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, frame_count == 1 && world.time.frame_index == 1)
	ui.editor_pause(state)
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, frame_count == 1 && world.time.frame_index == 1)
	ui.editor_step(state)
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, frame_count == 2 && world.time.frame_index == 2)
	testing.expect(t, world.time.delta_time == f32(1.0 / 60.0))
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, frame_count == 2 && world.time.frame_index == 2)
}

@(test)
test_editor_stop_resets_runtime_once_at_the_frame_boundary :: proc(t: ^testing.T) {
	world: World
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	frame_count := 0
	reset_count := 0
	config := Run_Config {
		frame_system = test_count_frame_system,
		frame_system_data = &frame_count,
		runtime_reset = test_count_runtime_reset,
		runtime_reset_data = &reset_count,
		ui_state = state,
	}
	ui.editor_stop(state)
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, reset_count == 1)
	testing.expect(t, frame_count == 0)
	testing.expect(t, state.editor_simulation_stopped)
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, reset_count == 1)
}

@(test)
test_editor_save_runs_once_and_clears_dirty_only_after_success :: proc(t: ^testing.T) {
	world: World
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	state.editor_scene_dirty = true
	save_count := 0
	config := Run_Config {
		runtime_save = test_count_runtime_reset,
		runtime_save_data = &save_count,
		ui_state = state,
	}
	ui.editor_save(state)
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, save_count == 1)
	testing.expect(t, !state.editor_scene_dirty)
	testing.expect(t, !state.editor_scene_save_failed)
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, save_count == 1)
}

@(test)
test_null_renderer_reports_runtime_growth_windows :: proc(t: ^testing.T) {
	world: World
	defer ecs.destroy_world(&world)
	append(&world.entities, ecs.World_Entity{id = {index = 0, generation = 1}, alive = true})
	stats: Runtime_Stats
	allocator_current := i64(1234)
	allocator_peak := i64(5678)

	_, err := run_renderer(
		Run_Config {
			backend = .Null,
			max_frames = 20,
			runtime_stats = &stats,
			allocator_current_bytes = &allocator_current,
			allocator_peak_bytes = &allocator_peak,
		},
		&world,
	)

	testing.expectf(t, err == "", "run_renderer failed: %s", err)
	testing.expect(t, stats.enabled)
	testing.expect(t, stats.frames == 20)
	testing.expect(t, stats.warmup_frames == 2)
	testing.expect(t, stats.sample_frames == 2)
	testing.expect(t, stats.early_update_ns_per_frame > 0)
	testing.expect(t, stats.late_update_ns_per_frame > 0)
	testing.expect(t, stats.cpu_growth_ratio > 0)
	testing.expect(t, stats.allocator_early_bytes == allocator_current)
	testing.expect(t, stats.allocator_late_bytes == allocator_current)
	testing.expect(t, stats.allocator_peak_bytes == allocator_peak)
	testing.expect(t, stats.allocator_final_bytes == allocator_current)
	testing.expect(t, stats.early_storage.entity_slots == 1)
	testing.expect(t, stats.late_storage == stats.early_storage)
	testing.expect(t, stats.final_storage == stats.early_storage)
}

@(test)
test_runtime_stats_reject_unbounded_window_runs :: proc(t: ^testing.T) {
	world: World
	stats: Runtime_Stats
	_, err := run_renderer(
		Run_Config{backend = .WGPU, window = true, max_frames = 0, runtime_stats = &stats},
		&world,
	)
	testing.expect(t, err != "")
	testing.expect(t, !stats.enabled)
}

@(test)
test_directional_shadow_matrix_is_finite_and_non_identity :: proc(t: ^testing.T) {
	light_matrix := wgpu_build_directional_light_view_projection({-0.5, -1, -0.25})
	testing.expect(t, light_matrix != mat4_identity())
	for value in light_matrix {
		testing.expect(t, value == value)
	}
}

test_count_frame_system :: proc(data: rawptr, world: ^World, delta_seconds: f32) -> string {
	ecs.advance_time(&world.time, delta_seconds)
	count := cast(^int)data
	count^ += 1
	return ""
}

test_count_runtime_reset :: proc(data: rawptr, world: ^World) -> string {
	count := cast(^int)data
	count^ += 1
	world.time = {}
	return ""
}
