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
test_renderer_window_size_uses_project_values_and_engine_defaults :: proc(t: ^testing.T) {
	width, height := renderer_window_size({window_width = 1920, window_height = 1080})
	testing.expect(t, width == 1920 && height == 1080)
	width, height = renderer_window_size({})
	testing.expect(t, width == shared.DEFAULT_WINDOW_WIDTH)
	testing.expect(t, height == shared.DEFAULT_WINDOW_HEIGHT)
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
	defer delete(renderer.draw_batch_cache.batches)
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
	defer delete(renderer.draw_batch_cache.batches)
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
test_wgpu_draw_database_has_no_legacy_64_batch_ceiling :: proc(t: ^testing.T) {
	renderer: WGPU_Renderer
	defer delete(renderer.draw_batch_cache.source_indices)
	defer delete(renderer.draw_batch_cache.batches)
	list: Render_List = {
		world_uuid = shared.entity_uuid_from_engine_name("many-draw-batches-test"),
		topology_revision = 1,
	}
	defer ecs.destroy_render_list(&list)
	for slot in 0 ..< 257 {
		append(
			&list.instances,
			shared.Render_Instance {
				slot = slot,
				geometry = {handle = {index = u32(slot), generation = 1}},
				material = {handle = {index = u32(slot), generation = 1}},
			},
		)
	}
	cache := wgpu_ensure_draw_batch_cache(&renderer, &list)
	testing.expect(t, cache != nil)
	testing.expect_value(t, cache.batch_count, 257)
	testing.expect_value(t, len(cache.batches), 257)
	testing.expect_value(t, len(cache.source_indices), 257)
}

@(test)
test_wgpu_draw_database_materializes_all_geometry_lod_batches :: proc(t: ^testing.T) {
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	desc, desc_err := resources.cube(1)
	testing.expect(t, desc_err == "")
	defer delete(desc.vertices)
	defer delete(desc.indices)
	base, base_err := resources.register_geometry(&registry, "lod-base", desc)
	lod1, lod1_err := resources.register_geometry(&registry, "lod-1", desc)
	lod2, lod2_err := resources.register_geometry(&registry, "lod-2", desc)
	testing.expect(t, base_err == "" && lod1_err == "" && lod2_err == "")
	testing.expect(
		t,
		resources.set_geometry_lods(
			&registry,
			base,
			[]shared.Geometry_Handle{lod1, lod2},
			[]f32{0.15, 0.04},
		) ==
		"",
	)
	material := shared.Material_Handle {
		index = 9,
		generation = 1,
	}
	list := Render_List {
		world_uuid = shared.entity_uuid_generate(),
		topology_revision = 1,
		instances = make([dynamic]Render_Instance),
	}
	defer delete(list.instances)
	append(
		&list.instances,
		Render_Instance{geometry = {handle = base}, material = {handle = material}},
	)
	renderer: WGPU_Renderer
	defer delete(renderer.draw_batch_cache.batches)
	defer delete(renderer.draw_batch_cache.source_indices)
	defer delete(renderer.gpu_batch_indices_by_slot)
	cache := wgpu_ensure_draw_batch_cache(&renderer, &list, &registry)
	testing.expect_value(t, cache.batch_count, 3)
	for batch in cache.batches[:cache.batch_count] {
		testing.expect_value(t, batch.instance_count, u32(1))
	}
	testing.expect(
		t,
		wgpu_rebuild_instance_batch_cache(&renderer, cache, &list, &registry, 1) == "",
	)
	testing.expect_value(t, renderer.gpu_batch_indices_by_slot[0], [4]u32{0, 1, 2, 0})
}

@(test)
test_wgpu_cpu_lod_selection_uses_screen_radius_thresholds :: proc(t: ^testing.T) {
	instance := WGPU_GPU_Instance {
		lod_screen_radii = {0.15, 0.04, 0, 0},
		lod_count = 2,
	}
	instance.bounds = {0, 0, 0, 0.4}
	testing.expect_value(t, wgpu_cpu_instance_lod_level(instance, mat4_identity()), 0)
	instance.bounds.w = 0.2
	testing.expect_value(t, wgpu_cpu_instance_lod_level(instance, mat4_identity()), 1)
	instance.bounds.w = 0.04
	testing.expect_value(t, wgpu_cpu_instance_lod_level(instance, mat4_identity()), 2)
}

@(test)
test_wgpu_hiz_reuse_requires_stable_camera_and_instance_data :: proc(t: ^testing.T) {
	view_projection := mat4_identity()
	testing.expect(t, wgpu_hiz_reuse_allowed(true, true, false, view_projection, view_projection))
	testing.expect(
		t,
		!wgpu_hiz_reuse_allowed(false, true, false, view_projection, view_projection),
	)
	testing.expect(
		t,
		!wgpu_hiz_reuse_allowed(true, false, false, view_projection, view_projection),
	)
	testing.expect(t, !wgpu_hiz_reuse_allowed(true, true, true, view_projection, view_projection))
	moved_camera := view_projection
	moved_camera[12] = 1
	testing.expect(t, !wgpu_hiz_reuse_allowed(true, true, false, view_projection, moved_camera))
}

@(test)
test_wgpu_frustum_planes_and_cpu_culling_reference :: proc(t: ^testing.T) {
	planes := wgpu_extract_frustum_planes(mat4_identity())
	testing.expect(t, wgpu_sphere_visible({0, 0, 0.5, 0.1}, planes))
	testing.expect(t, wgpu_sphere_visible({1.05, 0, 0.5, 0.1}, planes))
	testing.expect(t, !wgpu_sphere_visible({2, 0, 0.5, 0.1}, planes))
	testing.expect(t, !wgpu_sphere_visible({0, 0, -1, 0.1}, planes))

	instances := []WGPU_GPU_Instance {
		{bounds = {0, 0, 0.5, 0.1}, batch_indices = {0, 0, 0, 0}, active = 1},
		{bounds = {2, 0, 0.5, 0.1}, batch_indices = {0, 0, 0, 0}, active = 1},
		{
			bounds = {0, 0, 0.5, 0.1},
			batch_indices = {1, 0, 0, 0},
			active = 1,
			shadow_flags = {1, 0, 0, 0},
		},
		{bounds = {0, 0, 0.5, 0.1}, batch_indices = {1, 0, 0, 0}, active = 0},
	}
	camera_counts := wgpu_cpu_cull_counts(instances, planes, 2)
	defer delete(camera_counts)
	shadow_counts := wgpu_cpu_cull_counts(instances, planes, 2, true)
	defer delete(shadow_counts)
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
	state.editor_overlay_paint_count = 1
	state.editor_overlay_paint[0] = {
		kind = .Line,
		line_start = {10, 10},
		line_end = {20, 20},
		line_thickness = 2,
	}
	testing.expect(t, wgpu_ui_paint_signature(state, 1280, 720) == changed_paint)

	state.paint_count = 0
	testing.expect(t, wgpu_ui_paint_signature(state, 1280, 720) == 0)
}

@(test)
test_wgpu_empty_ui_vertex_upload_is_a_successful_no_op :: proc(t: ^testing.T) {
	testing.expect(t, wgpu_upload_ui_vertices(nil, nil, nil, nil, "empty UI"))
}

@(test)
test_wgpu_instance_upload_ranges_coalesce_nearby_dirty_slots :: proc(t: ^testing.T) {
	dirty := []int{2, 3, 7, 16, 30}
	first, last, next := wgpu_next_instance_upload_range(dirty, 0)
	testing.expect_value(t, first, 2)
	testing.expect_value(t, last, 17)
	testing.expect_value(t, next, 4)
	first, last, next = wgpu_next_instance_upload_range(dirty, next)
	testing.expect_value(t, first, 30)
	testing.expect_value(t, last, 31)
	testing.expect_value(t, next, len(dirty))
}

@(test)
test_wgpu_gpu_uniforms_upload_only_after_value_changes :: proc(t: ^testing.T) {
	renderer: WGPU_Renderer
	render_uniform: WGPU_GPU_Render_Uniform
	testing.expect(t, wgpu_retain_render_uniform(&renderer, render_uniform))
	testing.expect(t, !wgpu_retain_render_uniform(&renderer, render_uniform))
	render_uniform.ambient.x = 0.25
	testing.expect(t, wgpu_retain_render_uniform(&renderer, render_uniform))

	cull_uniform: WGPU_GPU_Cull_Uniform
	testing.expect(t, wgpu_retain_cull_uniform(&renderer, cull_uniform))
	testing.expect(t, !wgpu_retain_cull_uniform(&renderer, cull_uniform))
	cull_uniform.viewport.z = 1280
	testing.expect(t, wgpu_retain_cull_uniform(&renderer, cull_uniform))
}

@(test)
test_wgpu_gpu_timing_marks_only_encoded_passes_for_the_sample :: proc(t: ^testing.T) {
	renderer: WGPU_Renderer
	renderer.gpu_timestamp_active_slot = 2
	_, enabled := wgpu_gpu_pass_timestamps(&renderer, .World)
	testing.expect(t, enabled)
	readback := renderer.gpu_timestamp_readbacks[2]
	testing.expect(t, readback.phase_mask & (u32(1) << u32(WGPU_GPU_Timestamp_Phase.World)) != 0)
	testing.expect(t, readback.phase_mask & (u32(1) << u32(WGPU_GPU_Timestamp_Phase.UI)) == 0)
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
	defer delete(cache.batches)
	append(&cache.batches, WGPU_Draw_Batch{geometry = handle})
	renderer: WGPU_Renderer
	defer delete(renderer.gpu_indirect_templates)
	changed, before_err := wgpu_update_indirect_template_cache(&renderer, &cache, &registry)
	testing.expect(t, before_err == "")
	testing.expect(t, changed)
	before_index_count := renderer.gpu_indirect_templates[0].index_count
	testing.expect(t, before_index_count == u32(len(cube.indices)))
	stable_err: string
	changed, stable_err = wgpu_update_indirect_template_cache(&renderer, &cache, &registry)
	testing.expect(t, stable_err == "")
	testing.expect(t, !changed)

	plane, plane_err := resources.plane()
	defer delete(plane.vertices)
	defer delete(plane.indices)
	testing.expect(t, plane_err == "")
	updated, update_err := resources.register_geometry(&registry, "mutable", plane)
	testing.expect(t, update_err == "")
	testing.expect(t, updated == handle)
	after_err: string
	changed, after_err = wgpu_update_indirect_template_cache(&renderer, &cache, &registry)
	testing.expect(t, after_err == "")
	testing.expect(t, changed)
	testing.expect(t, renderer.gpu_indirect_templates[0].index_count == u32(len(plane.indices)))
	testing.expect(t, renderer.gpu_indirect_templates[0].index_count != before_index_count)
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
