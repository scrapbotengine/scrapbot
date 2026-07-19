package render

import ecs "../ecs"
import resources "../resources"
import shared "../shared"
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

Test_System_Profile_Events :: struct {
	begin_count: int,
	commit_count: int,
	phase_counts: [Engine_System_Profile_Phase.Count]int,
}

@(test)
test_null_renderer_profiles_every_engine_frame_system :: proc(t: ^testing.T) {
	world: World
	defer ecs.destroy_world(&world)
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	events: Test_System_Profile_Events

	_, err := run_renderer(
		Run_Config {
			backend = .Null,
			max_frames = 2,
			ui_state = state,
			system_profile_begin = test_system_profile_begin,
			system_profile_record = test_system_profile_record,
			system_profile_commit = test_system_profile_commit,
			system_profile_data = &events,
		},
		&world,
	)

	testing.expectf(t, err == "", "run_renderer failed: %s", err)
	testing.expect(t, events.begin_count == 2)
	testing.expect(t, events.commit_count == 2)
	for phase in Engine_System_Profile_Phase {
		if phase == .Count {
			continue
		}
		testing.expect(t, events.phase_counts[phase] == 2)
	}
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
test_editor_stop_restores_authoring_world_once_at_the_frame_boundary :: proc(t: ^testing.T) {
	world: World
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	frame_count := 0
	restore_count := 0
	config := Run_Config {
		frame_system = test_count_frame_system,
		frame_system_data = &frame_count,
		runtime_playback_stop = test_count_runtime_world_action,
		runtime_playback_stop_data = &restore_count,
		ui_state = state,
	}
	ui.editor_stop(state)
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, restore_count == 1)
	testing.expect(t, frame_count == 0)
	testing.expect(t, state.editor_simulation_stopped)
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, restore_count == 1)
	ui.editor_stop(state)
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, restore_count == 1)
}

@(test)
test_editor_play_snapshots_authoring_world_before_simulation :: proc(t: ^testing.T) {
	world: World
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	begin_count := 0
	frame_count := 0
	config := Run_Config {
		frame_system = test_count_frame_system,
		frame_system_data = &frame_count,
		runtime_playback_begin = test_count_runtime_world_action,
		runtime_playback_begin_data = &begin_count,
		ui_state = state,
	}
	ui.editor_play(state)
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, begin_count == 1)
	testing.expect(t, frame_count == 1)
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, begin_count == 1)
	testing.expect(t, frame_count == 2)
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
		runtime_save = test_count_runtime_save,
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
test_editor_revert_runs_once_and_clears_history_only_after_success :: proc(t: ^testing.T) {
	world: World
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	state.editor_scene_dirty = true
	state.editor_history_count = 1
	state.editor_history_cursor = 1
	revert_count := 0
	config := Run_Config {
		runtime_revert = test_count_runtime_world_action,
		runtime_revert_data = &revert_count,
		ui_state = state,
	}
	ui.editor_revert(state)
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, revert_count == 1)
	testing.expect(t, !state.editor_scene_dirty)
	testing.expect(t, !state.editor_scene_revert_failed)
	testing.expect(t, state.editor_history_count == 0)
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, revert_count == 1)
}

@(test)
test_editor_revert_failure_preserves_dirty_world_and_history :: proc(t: ^testing.T) {
	world: World
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	state.editor_scene_dirty = true
	state.editor_history_count = 1
	state.editor_history_cursor = 1
	config := Run_Config {
		runtime_revert = test_fail_runtime_world_action,
		ui_state = state,
	}
	ui.editor_revert(state)
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 0.1) == "")
	testing.expect(t, state.editor_scene_dirty)
	testing.expect(t, state.editor_scene_revert_failed)
	testing.expect(t, state.editor_history_count == 1)
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

@(test)
test_wgpu_draw_batch_topology_is_retained_across_transform_only_frames :: proc(t: ^testing.T) {
	renderer: WGPU_Renderer
	defer delete(renderer.draw_batch_cache.source_indices)
	list: Render_List = {
		world_uuid = shared.entity_uuid_from_engine_name("batch-cache-test"),
		topology_revision = 1,
	}
	defer ecs.destroy_render_list(&list)
	geometry_a := shared.Geometry_Handle {
		index = 1,
		generation = 1,
	}
	geometry_b := shared.Geometry_Handle {
		index = 2,
		generation = 1,
	}
	material := shared.Material_Handle {
		index = 1,
		generation = 1,
	}
	append(
		&list.instances,
		shared.Render_Instance{geometry = {handle = geometry_a}, material = {handle = material}},
		shared.Render_Instance{geometry = {handle = geometry_b}, material = {handle = material}},
		shared.Render_Instance{geometry = {handle = geometry_a}, material = {handle = material}},
	)
	cache := wgpu_ensure_draw_batch_cache(&renderer, &list)
	testing.expect(t, cache != nil)
	testing.expect(t, cache.batch_count == 2)
	testing.expect(t, cache.batches[0].instance_count == 2)
	testing.expect(t, cache.batches[1].instance_count == 1)
	testing.expect(t, cache.rebuild_count == 1)
	list.instances[0].transform.position.x = 42
	cache = wgpu_ensure_draw_batch_cache(&renderer, &list)
	testing.expect(t, cache.rebuild_count == 1)
	list.topology_revision += 1
	cache = wgpu_ensure_draw_batch_cache(&renderer, &list)
	testing.expect(t, cache.rebuild_count == 2)
}

@(test)
test_wgpu_draw_batches_scale_beyond_legacy_uniform_limit :: proc(t: ^testing.T) {
	renderer: WGPU_Renderer
	defer delete(renderer.draw_batch_cache.source_indices)
	list: Render_List = {
		world_uuid = shared.entity_uuid_from_engine_name("large-batch-cache-test"),
		topology_revision = 1,
	}
	defer ecs.destroy_render_list(&list)
	geometry := shared.Geometry_Handle {
		index = 1,
		generation = 1,
	}
	material := shared.Material_Handle {
		index = 1,
		generation = 1,
	}
	for slot in 0 ..< 100_000 {
		append(
			&list.instances,
			shared.Render_Instance {
				slot = slot,
				geometry = {handle = geometry},
				material = {handle = material},
			},
		)
	}
	cache := wgpu_ensure_draw_batch_cache(&renderer, &list)
	testing.expect(t, cache != nil)
	testing.expect(t, cache.batch_count == 1)
	testing.expect(t, cache.batches[0].instance_count == 100_000)
	testing.expect(t, len(cache.source_indices) == 100_000)
}

@(test)
test_wgpu_frustum_planes_and_cpu_culling_reference :: proc(t: ^testing.T) {
	planes := wgpu_extract_frustum_planes(mat4_identity())
	testing.expect(t, wgpu_sphere_visible({0, 0, 0.5, 0.1}, planes))
	testing.expect(t, wgpu_sphere_visible({1.05, 0, 0.5, 0.1}, planes))
	testing.expect(t, !wgpu_sphere_visible({2, 0, 0.5, 0.1}, planes))
	testing.expect(t, !wgpu_sphere_visible({0, 0, -1, 0.1}, planes))

	instances := []WGPU_GPU_Instance {
		{bounds = {0, 0, 0.5, 0.1}, batch_index = 0, active = 1},
		{bounds = {2, 0, 0.5, 0.1}, batch_index = 0, active = 1},
		{bounds = {0, 0, 0.5, 0.1}, batch_index = 1, active = 1, shadow_flags = {1, 0, 0, 0}},
		{bounds = {0, 0, 0.5, 0.1}, batch_index = 1, active = 0},
	}
	camera_counts := wgpu_cpu_cull_counts(instances, planes, 2)
	shadow_counts := wgpu_cpu_cull_counts(instances, planes, 2, true)
	testing.expect(t, camera_counts[0] == 1)
	testing.expect(t, camera_counts[1] == 1)
	testing.expect(t, shadow_counts[0] == 0)
	testing.expect(t, shadow_counts[1] == 1)
}

@(test)
test_wgpu_visible_batch_slices_are_storage_aligned :: proc(t: ^testing.T) {
	testing.expect(t, wgpu_align_visible_capacity(0) == WGPU_VISIBLE_ALIGNMENT)
	testing.expect(t, wgpu_align_visible_capacity(1) == WGPU_VISIBLE_ALIGNMENT)
	testing.expect(t, wgpu_align_visible_capacity(64) == WGPU_VISIBLE_ALIGNMENT)
	testing.expect(t, wgpu_align_visible_capacity(65) == WGPU_VISIBLE_ALIGNMENT * 2)
	testing.expect(t, (wgpu_align_visible_capacity(65) * size_of(u32)) % 256 == 0)
}

@(test)
test_wgpu_ui_paint_signature_tracks_only_rendered_output :: proc(t: ^testing.T) {
	state := new(ui.State)
	defer free(state)
	state.paint_count = 1
	state.paint[0] = {
		kind = .Panel,
		rect = {x = 10, y = 20, width = 100, height = 40},
		color = {0.2, 0.3, 0.4, 1},
	}
	first := wgpu_ui_paint_signature(state, 1280, 720)
	testing.expect(t, first != 0)
	testing.expect(t, wgpu_ui_paint_signature(state, 1280, 720) == first)

	state.paint[0].color.x = 0.5
	changed_paint := wgpu_ui_paint_signature(state, 1280, 720)
	testing.expect(t, changed_paint != first)
	testing.expect(t, wgpu_ui_paint_signature(state, 1920, 1080) != changed_paint)

	state.paint_count = 0
	testing.expect(t, wgpu_ui_paint_signature(state, 1280, 720) == 0)
}

@(test)
test_wgpu_indirect_template_tracks_in_place_geometry_replacement :: proc(t: ^testing.T) {
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	cube, cube_err := resources.cube()
	defer delete(cube.vertices)
	defer delete(cube.indices)
	testing.expect(t, cube_err == "")
	handle, register_err := resources.register_geometry(&registry, "mutable", cube)
	testing.expect(t, register_err == "")
	cache := WGPU_Draw_Batch_Cache {
		batch_count = 1,
	}
	cache.batches[0].geometry = handle
	before, before_err := wgpu_build_indirect_templates(&cache, &registry)
	testing.expect(t, before_err == "")
	testing.expect(t, before[0].index_count == u32(len(cube.indices)))

	plane, plane_err := resources.plane()
	defer delete(plane.vertices)
	defer delete(plane.indices)
	testing.expect(t, plane_err == "")
	updated, update_err := resources.register_geometry(&registry, "mutable", plane)
	testing.expect(t, update_err == "")
	testing.expect(t, updated == handle)
	after, after_err := wgpu_build_indirect_templates(&cache, &registry)
	testing.expect(t, after_err == "")
	testing.expect(t, after[0].index_count == u32(len(plane.indices)))
	testing.expect(t, after[0].index_count != before[0].index_count)
}

test_count_frame_system :: proc(data: rawptr, world: ^World, delta_seconds: f32) -> string {
	ecs.advance_time(&world.time, delta_seconds)
	count := cast(^int)data
	count^ += 1
	return ""
}

test_count_runtime_world_action :: proc(data: rawptr, world: ^World) -> string {
	count := cast(^int)data
	count^ += 1
	world.time = {}
	return ""
}

test_fail_runtime_world_action :: proc(_: rawptr, _: ^World) -> string {
	return "expected test failure"
}

test_count_runtime_save :: proc(
	data: rawptr,
	_: ^World,
	_: []shared.Entity_UUID,
	_: []shared.Resource_UUID,
) -> string {
	count := cast(^int)data
	count^ += 1
	return ""
}

test_system_profile_begin :: proc(data: rawptr) {
	events := cast(^Test_System_Profile_Events)data
	events.begin_count += 1
}

test_system_profile_record :: proc(data: rawptr, phase: Engine_System_Profile_Phase, _: i64) {
	events := cast(^Test_System_Profile_Events)data
	events.phase_counts[phase] += 1
}

test_system_profile_commit :: proc(data: rawptr) {
	events := cast(^Test_System_Profile_Events)data
	events.commit_count += 1
}
