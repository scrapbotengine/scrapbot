package render

import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import ui "../ui"

import "core:math"
import "core:testing"

@(test)
test_sky_uniform_uses_active_camera_basis_projection_and_aspect :: proc(t: ^testing.T) {
	list := shared.Render_List {
		has_camera = true,
		camera = {transform = {rotation = {0, math.PI / 2, 0}}, camera = {fov = 90}},
	}
	uniform := wgpu_build_sky_uniform(&list, 1920, 1080)
	testing.expect(t, math.abs(uniform.right[0]) < 0.00001)
	testing.expect(t, math.abs(uniform.right[2] - 1) < 0.00001)
	testing.expect(t, math.abs(uniform.up[1] - 1) < 0.00001)
	testing.expect(t, math.abs(uniform.forward[0] - 1) < 0.00001)
	testing.expect(t, math.abs(uniform.forward[2]) < 0.00001)
	testing.expect(t, math.abs(uniform.projection[0] - f32(16.0 / 9.0)) < 0.00001)
	testing.expect(t, math.abs(uniform.projection[1] - 1) < 0.00001)
}

@(test)
test_sky_uniform_upload_state_changes_only_with_camera_or_viewport :: proc(t: ^testing.T) {
	renderer: WGPU_Renderer
	first := wgpu_build_sky_uniform(nil, 1280, 720)
	testing.expect(t, wgpu_retain_sky_uniform(&renderer, first))
	testing.expect(t, !wgpu_retain_sky_uniform(&renderer, first))
	resized := wgpu_build_sky_uniform(nil, 720, 720)
	testing.expect(t, wgpu_retain_sky_uniform(&renderer, resized))
	list := shared.Render_List {
		has_camera = true,
		camera = {transform = {rotation = {0.1, 0.2, 0}}, camera = {fov = 60}},
	}
	rotated := wgpu_build_sky_uniform(&list, 720, 720)
	testing.expect(t, wgpu_retain_sky_uniform(&renderer, rotated))
	testing.expect(t, !wgpu_retain_sky_uniform(&renderer, rotated))
}

@(test)
test_gpu_normal_model_can_reuse_the_model_matrix :: proc(t: ^testing.T) {
	transform := shared.Transform_Component {
		position = {3, -2, 7},
		rotation = {0.31, -0.72, 1.08},
		scale = {-2, 0.5, 3},
	}
	model := wgpu_build_model(transform)
	actual := wgpu_build_normal_model_from_model(model, transform.scale)
	expected := mat4_mul(
		mat4_rotate_z(transform.rotation.z),
		mat4_mul(
			mat4_rotate_y(transform.rotation.y),
			mat4_mul(mat4_rotate_x(transform.rotation.x), mat4_scale({-0.5, 2, 1.0 / 3.0})),
		),
	)
	for value, index in actual {
		testing.expect(t, math.abs(value - expected[index]) < 0.00001)
	}
}

@(test)
test_gpu_instance_transform_stream_is_compact_and_preserves_source :: proc(t: ^testing.T) {
	transform := shared.Transform_Component {
		position = {-4, 8, 11},
		rotation = {0.2, -0.4, 0.7},
		scale = {2, 0.5, 3},
	}
	geometry := resources.Geometry {
		bounds = {min = {-2, -1, -3}, max = {4, 5, 7}},
	}
	record := wgpu_build_gpu_instance_transform(
		shared.Render_Instance{transform = transform},
		&geometry,
	)
	testing.expect_value(t, size_of(WGPU_GPU_Instance_Transform), 64)
	testing.expect(t, size_of(WGPU_GPU_Instance_Transform) < size_of(WGPU_GPU_Instance))
	testing.expect_value(t, record.position, [4]f32{-4, 8, 11, 0})
	testing.expect_value(t, record.rotation, [4]f32{0.2, -0.4, 0.7, 0})
	testing.expect_value(t, record.scale, [4]f32{2, 0.5, 3, 0})
	testing.expect_value(t, record.local_bounds, [4]f32{1, 2, 2, math.sqrt(f32(43))})

	updated := record
	next_transform := transform
	next_transform.position.x += 5
	wgpu_update_gpu_instance_transform(&updated, next_transform)
	testing.expect_value(t, updated.position, [4]f32{1, 8, 11, 0})
	testing.expect_value(t, updated.local_bounds, record.local_bounds)
}

@(test)
test_gpu_transform_updates_are_dense_and_encode_the_destination_slot :: proc(t: ^testing.T) {
	renderer: WGPU_Renderer
	defer delete(renderer.gpu_instance_transform_records)
	defer delete(renderer.gpu_transform_updates)
	resize(&renderer.gpu_instance_transform_records, 8)
	append(&renderer.gpu_transform_updates, WGPU_GPU_Instance_Transform{})
	renderer.gpu_instance_transform_records[5] = {
		position = {1, 2, 3, 0},
		rotation = {0.1, 0.2, 0.3, 0},
		scale = {2, 3, 4, 0},
		local_bounds = {0, 1, 2, 7},
	}

	wgpu_append_transform_update(&renderer, 5)
	testing.expect_value(t, len(renderer.gpu_transform_updates), 2)
	update := renderer.gpu_transform_updates[1]
	testing.expect_value(t, update.position, [4]f32{1, 2, 3, 5})
	testing.expect_value(t, update.rotation, [4]f32{0.1, 0.2, 0.3, 0})
	testing.expect_value(t, update.scale, [4]f32{2, 3, 4, 0})
	testing.expect_value(t, update.local_bounds, [4]f32{0, 1, 2, 7})
}

@(test)
test_gpu_instance_update_work_separates_static_and_transform_uploads :: proc(t: ^testing.T) {
	previous := WGPU_Instance_Source_State {
		geometry = {1, 1},
		material = {2, 1},
		geometry_version = 4,
		material_version = 5,
	}
	transform := shared.Transform_Component {
		position = {1, 2, 3},
		scale = {1, 1, 1},
	}
	static_changed, transform_changed, expand := wgpu_instance_update_work(
		false,
		{},
		previous,
		{},
		transform,
	)
	testing.expect(t, static_changed && transform_changed && !expand)

	current := previous
	next_transform := transform
	next_transform.rotation.y = 0.5
	testing.expect(
		t,
		wgpu_instance_source_changed(true, previous, current, transform, next_transform),
	)
	static_changed, transform_changed, expand = wgpu_instance_update_work(
		true,
		previous,
		current,
		transform,
		next_transform,
	)
	testing.expect(t, !static_changed && transform_changed && expand)

	current = previous
	current.material_version += 1
	testing.expect(t, wgpu_instance_source_changed(true, previous, current, transform, transform))
	static_changed, transform_changed, expand = wgpu_instance_update_work(
		true,
		previous,
		current,
		transform,
		transform,
	)
	testing.expect(t, static_changed && !transform_changed && !expand)

	current = previous
	current.geometry_version += 1
	static_changed, transform_changed, expand = wgpu_instance_update_work(
		true,
		previous,
		current,
		transform,
		transform,
	)
	testing.expect(t, static_changed && transform_changed && !expand)
	testing.expect(
		t,
		!wgpu_instance_source_changed(true, previous, previous, transform, transform),
	)
}

@(test)
test_gpu_dirty_instance_sync_reactivates_an_authoritative_render_slot :: proc(t: ^testing.T) {
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	description, description_err := resources.cube()
	defer delete(description.vertices)
	defer delete(description.indices)
	testing.expect(t, description_err == "")
	geometry, geometry_err := resources.register_geometry(&registry, "projectile", description)
	material, material_err := resources.register_material(
		&registry,
		"projectile",
		{base_color = {0.2, 0.8, 1, 1}},
	)
	testing.expect(t, geometry_err == "" && material_err == "")

	render_list: Render_List
	defer ecs.destroy_render_list(&render_list)
	append(
		&render_list.instances,
		Render_Instance {
			slot = 0,
			transform = {position = {2, 3, 0}, scale = {1, 1, 1}},
			geometry = {handle = geometry},
			material = {handle = material},
		},
	)
	append(&render_list.instance_index_by_slot, 0)
	render_list.instance_slot_count = 1

	cache: WGPU_Draw_Batch_Cache
	defer delete(cache.batches)
	append(
		&cache.batches,
		WGPU_Draw_Batch{geometry = geometry, material = material, visible_capacity = 64},
	)
	cache.batch_count = 1

	renderer: WGPU_Renderer
	defer delete(renderer.gpu_instance_records)
	defer delete(renderer.gpu_instance_transform_records)
	defer delete(renderer.gpu_instance_sources)
	defer delete(renderer.gpu_instance_source_transforms)
	defer delete(renderer.gpu_active_slots)
	defer delete(renderer.gpu_dirty_indices)
	defer delete(renderer.gpu_transform_updates)
	resize(&renderer.gpu_instance_records, 1)
	resize(&renderer.gpu_instance_transform_records, 1)
	resize(&renderer.gpu_instance_sources, 1)
	resize(&renderer.gpu_instance_source_transforms, 1)
	resize(&renderer.gpu_active_slots, 1)

	capacity_grew, err := wgpu_sync_dirty_instance_slot(
		&renderer,
		&cache,
		&render_list,
		&registry,
		0,
		false,
	)
	testing.expect(t, err == "")
	testing.expect(t, !capacity_grew)
	testing.expect(t, renderer.gpu_active_slots[0])
	testing.expect(t, renderer.gpu_instance_records[0].active == 1)
	testing.expect_value(t, renderer.gpu_instance_source_transforms[0].position, Vec3{2, 3, 0})
	testing.expect_value(t, cache.instance_count, 1)
	testing.expect_value(t, cache.batches[0].instance_count, u32(1))
	testing.expect_value(t, len(renderer.gpu_dirty_indices), 1)
	testing.expect_value(t, renderer.gpu_dirty_indices[0], 0)
}

@(test)
test_gpu_instance_reset_clears_retained_slots_beyond_a_smaller_world :: proc(t: ^testing.T) {
	renderer: WGPU_Renderer
	defer delete(renderer.gpu_instance_records)
	defer delete(renderer.gpu_instance_transform_records)
	defer delete(renderer.gpu_instance_sources)
	defer delete(renderer.gpu_instance_source_transforms)
	defer delete(renderer.gpu_active_slots)
	defer delete(renderer.gpu_dirty_indices)
	defer delete(renderer.gpu_live_slots)
	resize(&renderer.gpu_instance_records, 4)
	resize(&renderer.gpu_instance_transform_records, 4)
	resize(&renderer.gpu_instance_sources, 4)
	resize(&renderer.gpu_instance_source_transforms, 4)
	resize(&renderer.gpu_active_slots, 4)
	for slot in 0 ..< 4 {
		renderer.gpu_active_slots[slot] = true
		renderer.gpu_instance_sources[slot].material = {u32(slot), 7}
		append(&renderer.gpu_live_slots, slot)
	}

	wgpu_reset_gpu_instance_slots(&renderer)
	testing.expect_value(t, len(renderer.gpu_dirty_indices), 4)
	testing.expect_value(t, len(renderer.gpu_live_slots), 0)
	for slot in 0 ..< 4 {
		testing.expect(t, !renderer.gpu_active_slots[slot])
		testing.expect_value(t, renderer.gpu_instance_sources[slot], WGPU_Instance_Source_State{})
	}
}

@(test)
test_material_revision_marks_only_dependent_active_gpu_slots_for_sync :: proc(t: ^testing.T) {
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	material, material_err := resources.register_material(
		&registry,
		"editable",
		{base_color = {1, 1, 1, 1}},
	)
	testing.expect(t, material_err == "")
	material_data, alive := resources.get_material(&registry, material)
	testing.expect(t, alive)

	renderer: WGPU_Renderer
	defer delete(renderer.gpu_active_slots)
	defer delete(renderer.gpu_instance_sources)
	resize(&renderer.gpu_active_slots, 2)
	resize(&renderer.gpu_instance_sources, 2)
	renderer.gpu_active_slots[0] = true
	renderer.gpu_instance_sources[0].material = material
	renderer.gpu_instance_sources[0].material_version = material_data.version
	instance := Render_Instance {
		slot = 0,
		material = {handle = material},
	}
	testing.expect(t, !wgpu_material_instance_needs_sync(&renderer, &registry, instance))

	testing.expect(t, resources.touch_material(&registry, material))
	testing.expect(t, wgpu_material_instance_needs_sync(&renderer, &registry, instance))
	instance.slot = 1
	testing.expect(t, !wgpu_material_instance_needs_sync(&renderer, &registry, instance))
}

@(test)
test_gpu_resource_cache_reuses_slots_across_handle_generations :: proc(t: ^testing.T) {
	materials := [?]WGPU_Material_Cache {
		{handle = {index = 2, generation = 1}},
		{handle = {index = 7, generation = 4}},
	}
	geometries := [?]WGPU_Geometry_Cache {
		{handle = {index = 3, generation = 2}},
		{handle = {index = 9, generation = 5}},
	}
	testing.expect_value(
		t,
		wgpu_material_cache_slot(materials[:], {index = 7, generation = 99}),
		1,
	)
	testing.expect_value(
		t,
		wgpu_geometry_cache_slot(geometries[:], {index = 3, generation = 88}),
		0,
	)
}

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
test_performance_diagnostics_publish_retained_rolling_snapshot :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	_, scene_ok := ecs.create_world_entity(&world, "Scene", {}, .Scene)
	runtime_index, runtime_ok := ecs.create_world_entity(&world, "Runtime", {}, .Runtime)
	_, editor_ok := ecs.create_world_entity(&world, "Editor", {}, .Editor)
	testing.expect(t, scene_ok && runtime_ok && editor_ok)
	testing.expect(t, world.scene_entity_count == 1)
	testing.expect(t, world.runtime_entity_count == 1)
	testing.expect(t, world.editor_entity_count == 1)
	testing.expect(t, ecs.set_entity_origin(&world, runtime_index, .Scene))
	testing.expect(t, world.scene_entity_count == 2)
	testing.expect(t, world.runtime_entity_count == 0)
	stats := Render_Stats {
		draw_batches = 7,
		gpu_timestamps_valid = true,
		gpu_frame_ms = 2.25,
		instance_slots = 12,
		frustum_candidates = 11,
		frustum_culled_instances = 4,
		visible_instances = 8,
		occlusion_culled_instances = 3,
	}
	accumulator: Performance_Diagnostics_Accumulator
	for index in 0 ..< PERFORMANCE_DIAGNOSTICS_PUBLISH_INTERVAL_FRAMES {
		performance_diagnostics_commit_frame(&accumulator, &stats, &world, 0.02, 0.006)
		if index < PERFORMANCE_DIAGNOSTICS_PUBLISH_INTERVAL_FRAMES - 1 {
			testing.expect(t, accumulator.snapshot.revision == 0)
		}
	}
	snapshot := accumulator.snapshot
	testing.expect(t, snapshot.revision == 1)
	testing.expect(t, snapshot.sample_frames == PERFORMANCE_DIAGNOSTICS_PUBLISH_INTERVAL_FRAMES)
	testing.expect(t, math.abs(snapshot.fps - 50) < 0.001)
	testing.expect(t, math.abs(snapshot.frame_ms - 6) < 0.001)
	testing.expect(t, snapshot.gpu_frame_ms == 2.25)
	testing.expect(t, snapshot.gpu_timestamps_valid)
	testing.expect(t, snapshot.entity_count == 2)
	testing.expect(t, snapshot.draw_batches == 7)
	testing.expect(t, snapshot.instance_count == 12)
	testing.expect(t, snapshot.frustum_candidates == 11)
	testing.expect(t, snapshot.frustum_culled_instances == 4)
	testing.expect(t, snapshot.visible_instances == 8)
	testing.expect(t, snapshot.occlusion_culled_instances == 3)
	ecs.despawn_entity(&world, runtime_index, world.entities[runtime_index].id.generation)
	for _ in 0 ..< PERFORMANCE_DIAGNOSTICS_PUBLISH_INTERVAL_FRAMES {
		performance_diagnostics_commit_frame(&accumulator, &stats, &world, 0.02, 0.006)
	}
	testing.expect(t, accumulator.snapshot.entity_count == 1)
	testing.expect(t, accumulator.snapshot.revision == 2)
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
test_runtime_commits_injected_input_before_project_systems :: proc(t: ^testing.T) {
	world: World
	input: shared.Input_Frame
	input.keyboard.available = true
	shared.input_button_set(&input.keyboard.buttons.pressed, int(shared.Input_Key.Space))
	observed := false
	config := Run_Config {
		input_override = &input,
		frame_system = test_observe_input_frame_system,
		frame_system_data = &observed,
	}
	testing.expect(t, run_frame_system_unmeasured(&config, &world, 1.0 / 60.0) == "")
	testing.expect(t, observed)
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
test_wgpu_hiz_build_waits_for_stable_instance_data :: proc(t: ^testing.T) {
	testing.expect(t, !wgpu_hiz_build_requested(WGPU_HIZ_MIN_INSTANCES - 1, false))
	testing.expect(t, wgpu_hiz_build_requested(WGPU_HIZ_MIN_INSTANCES, false))
	testing.expect(t, !wgpu_hiz_build_requested(WGPU_HIZ_MIN_INSTANCES, true))
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
test_wgpu_ui_stream_keys_track_revision_target_and_project_viewport :: proc(t: ^testing.T) {
	viewport := ui.Rect{10, 20, 800, 600}
	first := wgpu_ui_stream_key(7, 1280, 720, viewport)
	testing.expect_value(t, wgpu_ui_stream_key(7, 1280, 720, viewport), first)
	testing.expect(t, wgpu_ui_stream_key(8, 1280, 720, viewport) != first)
	testing.expect(t, wgpu_ui_stream_key(7, 1920, 1080, viewport) != first)
	testing.expect(t, wgpu_ui_stream_key(7, 1280, 720, {11, 20, 800, 600}) != first)
}

@(test)
test_project_ui_vertices_preserve_pixel_aspect_inside_editor_viewport :: proc(t: ^testing.T) {
	vertices: [dynamic]WGPU_UI_Vertex
	defer delete(vertices)
	viewport := ui.Rect{250, 50, 628, 638}
	command := ui.Paint_Command {
		kind = .Panel,
		rect = {20, 20, 430, 90},
		corner_radius = 12,
		border_width = 2,
	}
	wgpu_append_ui_vertices(&vertices, []ui.Paint_Command{command}, 1, viewport, 1280, 720)
	testing.expect_value(t, len(vertices), 6)
	testing.expect(t, math.abs(vertices[0].size_radius[0] - 430) < 0.001)
	testing.expect(t, math.abs(vertices[0].size_radius[1] - 90) < 0.001)
	testing.expect(t, math.abs(vertices[0].size_radius[2] - 12) < 0.001)
	testing.expect(t, math.abs(vertices[0].border_width - 2) < 0.001)
	expected_x := (viewport.x + 20) / 1280 * 2 - 1
	expected_y := 1 - (viewport.y + 20) / 720 * 2
	testing.expect(t, math.abs(vertices[0].position[0] - expected_x) < 0.001)
	testing.expect(t, math.abs(vertices[0].position[1] - expected_y) < 0.001)
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
test_wgpu_existing_batch_membership_grows_without_rebuilding_draw_database :: proc(t: ^testing.T) {
	cache: WGPU_Draw_Batch_Cache
	defer delete(cache.batches)
	append(
		&cache.batches,
		WGPU_Draw_Batch{instance_count = 1, visible_capacity = WGPU_VISIBLE_ALIGNMENT},
	)
	cache.batch_count = 1
	cache.instance_count = 1
	indices: [shared.MAX_GEOMETRY_LODS]u32
	capacity_grew := wgpu_adjust_batch_membership(&cache, indices, 0, 1)
	testing.expect(t, !capacity_grew)
	testing.expect_value(t, cache.batches[0].instance_count, u32(2))
	testing.expect_value(t, cache.instance_count, 2)
	_ = wgpu_adjust_batch_membership(&cache, indices, 0, -1)
	testing.expect_value(t, cache.batches[0].instance_count, u32(1))
	testing.expect_value(t, cache.instance_count, 1)

	cache.batches[0].instance_count = WGPU_VISIBLE_ALIGNMENT
	capacity_grew = wgpu_adjust_batch_membership(&cache, indices, 0, 1)
	testing.expect(t, capacity_grew)
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

test_observe_input_frame_system :: proc(data: rawptr, world: ^World, _: f32) -> string {
	input, ok := ecs.keyboard_input(world)
	_, pressed, _ := shared.input_key_state(input, .Space)
	observed := cast(^bool)data
	observed^ = ok && pressed
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

@(test)
test_embedded_viewport_target_dimensions_are_bounded_and_quantized :: proc(t: ^testing.T) {
	testing.expect_value(t, wgpu_viewport_target_dimension(1), u32(64))
	testing.expect_value(t, wgpu_viewport_target_dimension(64), u32(64))
	testing.expect_value(t, wgpu_viewport_target_dimension(65), u32(96))
	testing.expect_value(t, wgpu_viewport_target_dimension(511.2), u32(512))
	testing.expect_value(t, wgpu_viewport_target_dimension(2048), u32(1024))
	width, height := wgpu_viewport_target_size(ui.Rect{width = 351, height = 219})
	testing.expect_value(t, width, u32(352))
	testing.expect_value(t, height, u32(224))
}

@(test)
test_embedded_viewport_cache_tracks_all_resource_families :: proc(t: ^testing.T) {
	renderer: WGPU_Renderer
	component := shared.ui_viewport_default()
	component.resource, _ = shared.resource_uuid_parse("a7000000-0000-4000-8000-000000000001")
	wgpu_store_viewport_cache(&renderer, 0, component, 1.5, 7, 11, 13, 17)
	testing.expect(t, wgpu_viewport_cache_matches(&renderer, 0, component, 1.5, 7, 11, 13, 17))
	testing.expect(t, !wgpu_viewport_cache_matches(&renderer, 0, component, 1.5, 7, 11, 14, 17))
	wgpu_invalidate_viewport_cache(&renderer, 0)
	testing.expect(t, !renderer.ui_viewport_cache_valid[0])
}
