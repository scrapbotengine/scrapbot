package render

import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import ui "../ui"

import "core:math"
import "core:os"
import "core:strings"
import "core:testing"
import "core:thread"
import "vendor:wgpu"

@(test)
test_wgpu_headless_runs_use_offscreen_output_without_requiring_capture :: proc(t: ^testing.T) {
	config := Run_Config {
		backend = .WGPU,
		window = false,
	}
	testing.expect_value(t, renderer_output_mode(&config), Renderer_Output_Mode.Offscreen)
	testing.expect(t, !wgpu_offscreen_capture_requested(&config))

	config.framegrab_path = "/tmp/frame.png"
	testing.expect_value(t, renderer_output_mode(&config), Renderer_Output_Mode.Offscreen)
	testing.expect(t, wgpu_offscreen_capture_requested(&config))

	config.framegrab_path = ""
	config.framegrab_sequence_directory = "/tmp/frames"
	testing.expect(t, wgpu_offscreen_capture_requested(&config))
}

@(test)
test_wgpu_window_runs_are_the_only_surface_output_mode :: proc(t: ^testing.T) {
	config := Run_Config {
		backend = .WGPU,
		window = true,
	}
	testing.expect_value(t, renderer_output_mode(&config), Renderer_Output_Mode.Surface)

	config.backend = .Null
	testing.expect_value(t, renderer_output_mode(&config), Renderer_Output_Mode.Offscreen)
}

@(test)
test_world_shaders_light_procedural_skies_through_the_pbr_environment_path :: proc(t: ^testing.T) {
	shaders := [?]string{WGPU_GPU_DRIVEN_SHADER, WGPU_RENDER_SHADER}
	for shader in shaders {
		testing.expect(t, strings.contains(shader, "fn procedural_environment_radiance"))
		testing.expect(t, strings.contains(shader, "fn environment_specular_response"))
		testing.expect(
			t,
			strings.contains(shader, "multiple_scattering * multiple_scattering_energy"),
		)
		testing.expect(t, strings.contains(shader, "fn specular_ambient_occlusion"))
		testing.expect(t, strings.contains(shader, "fn environment_horizon_occlusion"))
		testing.expect(t, strings.contains(shader, "material.alpha.y > 0.5"))
		testing.expect(t, strings.contains(shader, "procedural_specular *"))
		testing.expect(t, strings.contains(shader, "environment.reflection_intensity"))
		testing.expect(t, !strings.contains(shader, "ambient_specular * occlusion"))
	}
}

@(test)
test_project_shader_scene_sampling_uses_target_coordinates_and_linear_depth :: proc(
	t: ^testing.T,
) {
	testing.expect(t, strings.contains(WGPU_CUSTOM_SHADER_PRELUDE, "scene_uv: vec2<f32>"))
	testing.expect(t, strings.contains(WGPU_CUSTOM_SHADER_PRELUDE, "fn scrapbot_scene_uv("))
	testing.expect(
		t,
		strings.contains(WGPU_CUSTOM_SHADER_PRELUDE, "scrapbot_custom.viewport.xy + local_uv"),
	)
	testing.expect(t, strings.contains(WGPU_CUSTOM_SHADER_PRELUDE, "fn scrapbot_scene_uv_valid("))
	testing.expect(
		t,
		strings.contains(WGPU_CUSTOM_SHADER_PRELUDE, "fn scrapbot_scene_view_depth("),
	)
	testing.expect(t, strings.contains(WGPU_CUSTOM_SHADER_PRELUDE, "near_plane * far_plane"))
	testing.expect(
		t,
		strings.contains(WGPU_CUSTOM_SHADER_FOOTER, "scrapbot_scene_depth(scene_uv)"),
	)
	testing.expect(
		t,
		!strings.contains(WGPU_CUSTOM_SHADER_FOOTER, "scrapbot_scene_depth(screen_uv)"),
	)
}

@(test)
test_project_shaders_receive_object_transforms_and_environment_reflections :: proc(t: ^testing.T) {
	testing.expect(t, strings.contains(WGPU_CUSTOM_SHADER_PRELUDE, "model: mat4x4<f32>"))
	testing.expect(t, strings.contains(WGPU_CUSTOM_SHADER_PRELUDE, "normal_model: mat4x4<f32>"))
	testing.expect(
		t,
		strings.contains(WGPU_CUSTOM_SHADER_PRELUDE, "fn scrapbot_environment_reflection("),
	)
	testing.expect(
		t,
		strings.contains(WGPU_CUSTOM_SHADER_PRELUDE, "scrapbot_environment.max_specular_lod"),
	)
	testing.expect(
		t,
		strings.contains(WGPU_CUSTOM_SHADER_FOOTER, "instance.model, instance.normal_model"),
	)
}

@(test)
test_composite_dithers_tone_mapped_output_in_fixed_display_space :: proc(t: ^testing.T) {
	testing.expect(t, strings.contains(WGPU_COMPOSITE_SHADER, "fn presentation_dither"))
	testing.expect(t, strings.contains(WGPU_COMPOSITE_SHADER, "fn linear_to_srgb"))
	testing.expect(t, strings.contains(WGPU_COMPOSITE_SHADER, "fn srgb_to_linear"))
	testing.expect(t, strings.contains(WGPU_COMPOSITE_SHADER, "noise / 255.0"))
	testing.expect(
		t,
		strings.contains(
			WGPU_COMPOSITE_SHADER,
			"presentation_dither(aces(hdr), input.position.xy)",
		),
	)
}

@(test)
test_automatic_exposure_is_gpu_resident_viewport_scoped_and_shared_by_bloom_and_composite :: proc(
	t: ^testing.T,
) {
	testing.expect(t, strings.contains(WGPU_AUTOMATIC_EXPOSURE_SHADER, "@workgroup_size(256)"))
	testing.expect(t, strings.contains(WGPU_AUTOMATIC_EXPOSURE_SHADER, "settings.viewport"))
	testing.expect(t, strings.contains(WGPU_AUTOMATIC_EXPOSURE_SHADER, "log2(luminance)"))
	testing.expect(
		t,
		strings.contains(WGPU_AUTOMATIC_EXPOSURE_SHADER, "exp2(log_luminance_samples[0]"),
	)
	testing.expect(
		t,
		strings.contains(
			WGPU_AUTOMATIC_EXPOSURE_SHADER,
			"settings.control.w * settings.control.y",
		),
	)
	testing.expect(t, strings.contains(WGPU_AUTOMATIC_EXPOSURE_SHADER, "1.0 - exp("))
	testing.expect(t, strings.contains(WGPU_POST_PROCESS_SHADER, "automatic_exposure.values.x"))
	testing.expect(t, strings.contains(WGPU_COMPOSITE_SHADER, "automatic_exposure.values.x"))
}

@(test)
test_world_shaders_filter_directional_shadows_with_a_wide_tent_kernel :: proc(t: ^testing.T) {
	shaders := [?]string{WGPU_GPU_DRIVEN_SHADER, WGPU_RENDER_SHADER}
	for shader in shaders {
		testing.expect(t, strings.contains(shader, "select(1.0, 2.0, x == 0)"))
		testing.expect(t, strings.contains(shader, "select(1.0, 2.0, y == 0)"))
		testing.expect(t, strings.contains(shader, "vec2<f32>(f32(x), f32(y)) * texel * 1.5"))
		testing.expect(t, strings.contains(shader, "16.0"))
	}
}

@(test)
test_world_shaders_prefer_authored_tangent_frames_with_a_derivative_fallback :: proc(
	t: ^testing.T,
) {
	shaders := [?]string{WGPU_GPU_DRIVEN_SHADER, WGPU_RENDER_SHADER}
	for shader in shaders {
		testing.expect(t, strings.contains(shader, "@location(3) tangent: vec4<f32>"))
		testing.expect(t, strings.contains(shader, "@location(7) world_tangent: vec4<f32>"))
		testing.expect(t, strings.contains(shader, "authored_tangent_length > 0.0001"))
		testing.expect(t, strings.contains(shader, "input.world_tangent.w"))
		testing.expect(t, strings.contains(shader, "let position_dx = dpdx(input.world_position)"))
	}
	testing.expect_value(t, size_of(resources.Vertex), 48)
}

@(test)
test_ambient_occlusion_tracks_thickness_with_visibility_sectors :: proc(t: ^testing.T) {
	testing.expect(
		t,
		strings.contains(WGPU_AMBIENT_OCCLUSION_SHADER, "const SECTOR_COUNT: u32 = 32u"),
	)
	testing.expect(t, strings.contains(WGPU_AMBIENT_OCCLUSION_SHADER, "fn sector_mask"))
	testing.expect(
		t,
		strings.contains(
			WGPU_AMBIENT_OCCLUSION_SHADER,
			"back_difference = difference - view_direction * thickness",
		),
	)
	testing.expect(
		t,
		strings.contains(WGPU_AMBIENT_OCCLUSION_SHADER, "countOneBits(occluded_sectors)"),
	)
	testing.expect(t, !strings.contains(WGPU_AMBIENT_OCCLUSION_SHADER, "negative_horizon_cosine"))
	testing.expect(t, strings.contains(WGPU_AMBIENT_OCCLUSION_SHADER, "fn fast_acos"))
	testing.expect(t, strings.contains(WGPU_AMBIENT_OCCLUSION_SHADER, "let quality = clamp"))
	testing.expect(t, WGPU_VISIBILITY_AO_THICKNESS > 0)
	testing.expect(t, WGPU_VISIBILITY_AO_THICKNESS < WGPU_VISIBILITY_AO_RADIUS)
}

@(test)
test_ambient_occlusion_quality_uses_bounded_sample_tiers :: proc(t: ^testing.T) {
	camera := shared.camera_defaults()
	testing.expect_value(t, shared.camera_ambient_occlusion_quality(camera), f32(0.5))
	testing.expect_value(t, shared.camera_ambient_occlusion_sample_count(camera), u32(16))
	camera.ambient_occlusion_quality = 0.25
	testing.expect_value(t, shared.camera_ambient_occlusion_sample_count(camera), u32(8))
	camera.ambient_occlusion_quality = 0.75
	testing.expect_value(t, shared.camera_ambient_occlusion_sample_count(camera), u32(24))
	camera.ambient_occlusion_quality = 1
	testing.expect_value(t, shared.camera_ambient_occlusion_sample_count(camera), u32(36))
}

@(test)
test_screen_space_reflections_quality_uses_bounded_sample_tiers :: proc(t: ^testing.T) {
	camera := shared.camera_defaults()
	testing.expect_value(t, shared.camera_screen_space_reflections_quality(camera), f32(0.5))
	testing.expect_value(t, shared.camera_screen_space_reflections_sample_count(camera), u32(32))
	testing.expect(t, shared.camera_screen_space_reflections_stride_scale(camera) > 2.6)
	testing.expect(t, shared.camera_screen_space_reflections_stride_scale(camera) < 2.7)
	camera.screen_space_reflections_quality = 0.25
	testing.expect_value(t, shared.camera_screen_space_reflections_sample_count(camera), u32(16))
	camera.screen_space_reflections_quality = 0.75
	testing.expect_value(t, shared.camera_screen_space_reflections_sample_count(camera), u32(48))
	camera.screen_space_reflections_quality = 1
	testing.expect_value(t, shared.camera_screen_space_reflections_sample_count(camera), u32(64))
	testing.expect_value(t, shared.camera_screen_space_reflections_stride_scale(camera), f32(1))
	testing.expect(
		t,
		strings.contains(WGPU_SCREEN_SPACE_REFLECTIONS_SHADER, "step >= maximum_steps"),
	)
}

@(test)
test_cluster_index_budget_starts_at_256_and_grows_geometrically :: proc(t: ^testing.T) {
	testing.expect_value(t, WGPU_CLUSTER_INITIAL_LIGHT_CAPACITY, 256)
	testing.expect_value(
		t,
		WGPU_CLUSTER_COUNT * WGPU_CLUSTER_INITIAL_LIGHT_CAPACITY * size_of(u32),
		3_538_944,
	)
	testing.expect_value(t, wgpu_grow_capacity(WGPU_CLUSTER_INITIAL_LIGHT_CAPACITY, 257), 512)
}

@(test)
test_storage_binding_growth_uses_legal_capacity_below_device_limit :: proc(t: ^testing.T) {
	capacity, ok := wgpu_grow_storage_binding_capacity(
		256,
		800_000,
		size_of(WGPU_GPU_Meshlet_Info),
		128 * 1024 * 1024,
	)
	testing.expect(t, ok)
	testing.expect_value(t, capacity, 838_860)
	capacity, ok = wgpu_grow_storage_binding_capacity(
		256,
		838_861,
		size_of(WGPU_GPU_Meshlet_Info),
		128 * 1024 * 1024,
	)
	testing.expect(t, !ok)
	testing.expect_value(t, capacity, 0)
}

@(test)
test_cluster_viewport_tracks_editor_origin_and_available_world_extent :: proc(t: ^testing.T) {
	viewport := ui.Rect{320, 96, 1280, 720}
	testing.expect_value(t, wgpu_cluster_viewport_uniform(viewport), [4]f32{320, 96, 1280, 720})
}

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
test_wgpu_temporal_jitter_stays_inside_quarter_pixel_and_cycles :: proc(t: ^testing.T) {
	first := wgpu_temporal_jitter(0, 1280, 720)
	repeated := wgpu_temporal_jitter(8, 1280, 720)
	testing.expect_value(t, first, repeated)
	for sample_index in 0 ..< 8 {
		jitter := wgpu_temporal_jitter(u64(sample_index), 1280, 720)
		screen_x := math.abs(jitter.x) * 1280 * 0.5
		screen_y := math.abs(jitter.y) * 720 * 0.5
		testing.expect(t, screen_x <= 0.25)
		testing.expect(t, screen_y <= 0.25)
	}
	projection := mat4_perspective(math.to_radians(f32(60)), 16.0 / 9.0, 0.1, 100)
	view := mat4_look_at({1, 2, 3}, {}, {0, 1, 0})
	history_view_projection := wgpu_temporal_history_view_projection(projection, view)
	testing.expect_value(t, history_view_projection, mat4_mul(projection, view))
	jittered_projection := wgpu_jitter_projection(projection, first)
	testing.expect(t, history_view_projection != mat4_mul(jittered_projection, view))
}

@(test)
test_material_sampler_uses_anisotropy_only_with_linear_filters :: proc(t: ^testing.T) {
	testing.expect_value(t, wgpu_material_sampler_anisotropy({}), u16(8))
	testing.expect_value(t, wgpu_material_sampler_anisotropy({min_filter = .Nearest}), u16(1))
	testing.expect_value(t, wgpu_material_sampler_anisotropy({mipmap_filter = .Nearest}), u16(1))
	testing.expect_value(t, wgpu_material_sampler_anisotropy({mipmap_filter = .Base_Only}), u16(1))
}

@(test)
test_wgpu_device_depth_reconstructs_view_distance :: proc(t: ^testing.T) {
	projection := mat4_perspective(math.to_radians(f32(60)), 16.0 / 9.0, 0.1, 1000)
	view_z: f32 = -10
	clip_z := projection[10] * view_z + projection[14]
	clip_w := -view_z
	depth := clip_z / clip_w
	distance := wgpu_device_depth_to_view_distance(depth, projection)
	testing.expect(t, math.abs(distance - 10) < 0.0001)
}

@(test)
test_wgpu_inverse_rigid_view_roundtrips_camera_matrix :: proc(t: ^testing.T) {
	view := mat4_look_at({3, 2, 5}, {-1, 0.5, 0}, {0, 1, 0})
	product := mat4_mul(view, wgpu_inverse_rigid_view(view))
	identity := mat4_identity()
	for value, index in product {
		testing.expect(t, math.abs(value - identity[index]) < 0.00001)
	}
}

@(test)
test_temporal_resolve_reuses_one_workgroup_tile_for_exact_neighborhood_clamping :: proc(
	t: ^testing.T,
) {
	testing.expect(
		t,
		strings.contains(
			WGPU_TEMPORAL_AA_SHADER,
			"var<workgroup> current_color_tile: array<vec4<f32>, TEMPORAL_TILE_SIZE>",
		),
	)
	testing.expect(
		t,
		strings.contains(WGPU_TEMPORAL_AA_SHADER, "tile_index += TEMPORAL_WORKGROUP_WIDTH"),
	)
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "workgroupBarrier()"))
	testing.expect(
		t,
		strings.contains(WGPU_TEMPORAL_AA_SHADER, "fn current_neighborhood_from_tile"),
	)
	testing.expect(
		t,
		!strings.contains(
			WGPU_TEMPORAL_AA_SHADER,
			"let color = rgb_to_ycocg(current_color_at(sample_pixel))",
		),
	)
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "virtual_transition_reactive"))
	testing.expect(
		t,
		strings.contains(WGPU_TEMPORAL_AA_SHADER, "VIRTUAL_TRANSITION_MARKER_WITH_BLOOM"),
	)
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "depth_tolerance_scale"))
	testing.expect(
		t,
		strings.contains(WGPU_TEMPORAL_AA_SHADER, "history_weight = max(history_weight, 0.9)"),
	)
	testing.expect(
		t,
		strings.contains(WGPU_TEMPORAL_AA_SHADER, "depth >= 0.999999") &&
		strings.contains(WGPU_TEMPORAL_AA_SHADER, "virtual_transition_reactive(history_sample.a)"),
	)
}

@(test)
test_wgpu_temporal_camera_continuity_rejects_cuts :: proc(t: ^testing.T) {
	camera := WGPU_Temporal_Camera {
		position = {0, 1, 2},
		forward = {0, 0, -1},
		fov = 60,
		has_camera = true,
	}
	moved := camera
	moved.position.x = 0.25
	testing.expect(t, wgpu_temporal_camera_continuous(camera, moved))
	cut := camera
	cut.position.x = 3
	testing.expect(t, !wgpu_temporal_camera_continuous(camera, cut))
	turned := camera
	turned.forward = {1, 0, 0}
	testing.expect(t, !wgpu_temporal_camera_continuous(camera, turned))
	disabled := camera
	disabled.temporal_antialiasing = !camera.temporal_antialiasing
	testing.expect(t, !wgpu_temporal_camera_continuous(camera, disabled))
}

@(test)
test_camera_render_feature_defaults_preserve_current_renderer_policy :: proc(t: ^testing.T) {
	camera := shared.camera_defaults()
	testing.expect(t, camera.debug_view == .Lit)
	for view in shared.Render_Debug_View {
		name := shared.render_debug_view_name(view)
		parsed, ok := shared.render_debug_view_from_name(name)
		testing.expect(t, ok && parsed == view)
	}
	_, invalid_debug_view := shared.render_debug_view_from_name("triangles")
	testing.expect(t, !invalid_debug_view)
	camera.debug_hiz_mip = 6.9
	testing.expect_value(t, shared.camera_debug_hiz_mip(camera), u32(6))
	testing.expect(t, !camera.automatic_exposure)
	testing.expect_value(t, camera.automatic_exposure_min, f32(0.125))
	testing.expect_value(t, camera.automatic_exposure_max, f32(8))
	testing.expect_value(t, camera.automatic_exposure_speed, f32(2))
	testing.expect(t, camera.temporal_antialiasing)
	testing.expect(t, !camera.fast_antialiasing)
	testing.expect(t, camera.ambient_occlusion)
	testing.expect(t, !camera.screen_space_reflections)
	testing.expect(t, camera.bloom)
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
test_wgpu_geometry_arena_reuses_aligned_ranges_and_coalesces_releases :: proc(t: ^testing.T) {
	allocator: WGPU_Arena_Allocator
	defer delete(allocator.free_ranges)
	first := wgpu_arena_allocate(&allocator, 60, 16)
	second := wgpu_arena_allocate(&allocator, 20, 16)
	testing.expect_value(t, first, WGPU_Arena_Range{offset = 0, size = 60})
	testing.expect_value(t, second, WGPU_Arena_Range{offset = 64, size = 20})
	testing.expect_value(t, allocator.high_water, u64(84))
	testing.expect_value(t, allocator.resident_bytes, u64(80))

	wgpu_arena_release(&allocator, first)
	wgpu_arena_release(&allocator, second)
	testing.expect_value(t, allocator.resident_bytes, u64(0))
	testing.expect_value(t, len(allocator.free_ranges), 1)
	testing.expect_value(t, allocator.free_ranges[0], WGPU_Arena_Range{offset = 0, size = 84})

	reused := wgpu_arena_allocate(&allocator, 80, 16)
	testing.expect_value(t, reused, WGPU_Arena_Range{offset = 0, size = 80})
	testing.expect_value(t, allocator.high_water, u64(84))
	testing.expect_value(t, allocator.resident_bytes, u64(80))
}

@(test)
test_wgpu_geometry_cache_release_returns_all_arena_ranges :: proc(t: ^testing.T) {
	renderer: WGPU_Renderer
	defer delete(renderer.geometry_vertex_arena.allocator.free_ranges)
	defer delete(renderer.geometry_index_arena.allocator.free_ranges)
	vertex_range := wgpu_arena_allocate(&renderer.geometry_vertex_arena.allocator, 96, 16)
	index_range := wgpu_arena_allocate(&renderer.geometry_index_arena.allocator, 48, 4)
	meshlet_range := wgpu_arena_allocate(&renderer.geometry_index_arena.allocator, 64, 4)
	cached := WGPU_Geometry_Cache {
		handle = {index = 3, generation = 2},
		vertex_range = vertex_range,
		index_range = index_range,
		meshlet_index_range = meshlet_range,
		valid = true,
	}

	wgpu_release_geometry_cache_ranges(&renderer, &cached)

	testing.expect(t, !cached.valid)
	testing.expect_value(t, renderer.geometry_vertex_arena.allocator.resident_bytes, u64(0))
	testing.expect_value(t, renderer.geometry_index_arena.allocator.resident_bytes, u64(0))
	testing.expect_value(t, len(renderer.geometry_vertex_arena.allocator.free_ranges), 1)
	testing.expect_value(t, len(renderer.geometry_index_arena.allocator.free_ranges), 1)
}

@(test)
test_wgpu_geometry_arena_submission_spans_merge_compatible_lod_batches :: proc(t: ^testing.T) {
	material := shared.Material_Handle {
		index = 4,
		generation = 2,
	}
	other_material := shared.Material_Handle {
		index = 5,
		generation = 1,
	}
	batches := [?]WGPU_Draw_Batch {
		{material = material, meshlet_draw_offset = 0, meshlet_draw_count = 2},
		{material = material, meshlet_draw_offset = 2, meshlet_draw_count = 3},
		{material = material, meshlet_draw_offset = 5, meshlet_draw_count = 4},
		{material = other_material, meshlet_draw_offset = 9, meshlet_draw_count = 1},
	}
	renderer := WGPU_Renderer {
		gpu_meshlet_supported = true,
	}
	span := wgpu_draw_submission_span(&renderer, batches[:], 0)
	testing.expect_value(t, span.next_batch, 3)
	testing.expect_value(t, span.first_indirect, u32(0))
	testing.expect_value(t, span.indirect_count, u32(3))
	testing.expect_value(t, span.mode, WGPU_Submission_Mode.Classic)
	testing.expect_value(t, wgpu_draw_submission_count(&renderer, batches[:]), 2)

	renderer.gpu_meshlet_submission_active = true
	for &batch in batches[:3] {
		batch.meshlet_submission = true
	}
	span = wgpu_draw_submission_span(&renderer, batches[:], 0)
	testing.expect_value(t, span.next_batch, 3)
	testing.expect_value(t, span.first_indirect, u32(0))
	testing.expect_value(t, span.indirect_count, u32(9))
	testing.expect_value(t, span.mode, WGPU_Submission_Mode.Meshlet)
	testing.expect_value(t, wgpu_draw_submission_count(&renderer, batches[:]), 2)

	batches[0].compact_submission = true
	span = wgpu_draw_submission_span(&renderer, batches[:], 0)
	testing.expect_value(t, span.next_batch, 1)
	testing.expect_value(t, span.first_indirect, u32(0))
	testing.expect_value(t, span.indirect_count, u32(1))
	testing.expect_value(t, span.mode, WGPU_Submission_Mode.Compact)
	for &batch in batches[:3] {
		batch.compact_submission = true
	}
	shadow_span := wgpu_shadow_draw_submission_span(&renderer, batches[:], 0)
	testing.expect_value(t, shadow_span.next_batch, 3)
	testing.expect_value(t, shadow_span.first_indirect, u32(0))
	testing.expect_value(t, shadow_span.indirect_count, u32(3))
	testing.expect_value(t, shadow_span.mode, WGPU_Submission_Mode.Classic)
	testing.expect_value(t, wgpu_shadow_draw_submission_count(&renderer, batches[:]), 2)
	renderer.gpu_meshlet_force_enabled = true
	span = wgpu_draw_submission_span(&renderer, batches[:], 0)
	testing.expect_value(t, span.mode, WGPU_Submission_Mode.Meshlet)
	renderer.gpu_meshlet_force_enabled = false

	renderer.gpu_meshlet_supported = false
	span = wgpu_draw_submission_span(&renderer, batches[:], 0)
	testing.expect_value(t, span.next_batch, 1)
	testing.expect_value(t, span.indirect_count, u32(1))
}

@(test)
test_wgpu_compact_submission_spans_share_one_bounded_record_range :: proc(t: ^testing.T) {
	material := shared.Material_Handle {
		index = 2,
		generation = 1,
	}
	other_material := shared.Material_Handle {
		index = 3,
		generation = 1,
	}
	batches := [?]WGPU_Draw_Batch {
		{
			material = material,
			compact_submission = true,
			meshlet_visible_offset = 0,
			meshlet_visible_capacity = 12,
		},
		{
			material = material,
			compact_submission = true,
			meshlet_visible_offset = 12,
			meshlet_visible_capacity = 20,
		},
		{
			material = other_material,
			compact_submission = true,
			meshlet_visible_offset = 32,
			meshlet_visible_capacity = 8,
		},
	}
	wgpu_assign_compact_submission_spans(batches[:])
	for index in 0 ..< 2 {
		testing.expect_value(t, batches[index].compact_command_index, u32(0))
		testing.expect_value(t, batches[index].compact_visible_offset, u32(0))
		testing.expect_value(t, batches[index].compact_visible_capacity, u32(32))
	}
	testing.expect_value(t, batches[2].compact_command_index, u32(2))
	testing.expect_value(t, batches[2].compact_visible_offset, u32(32))
	testing.expect_value(t, batches[2].compact_visible_capacity, u32(8))
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
		visible_batches = 3,
		visible_meshlet_draws = 6,
		gpu_timestamps_valid = true,
		gpu_frame_ms = 2.25,
		gpu_scene_ms = 1.75,
		render_scale = 0.75,
		shadow_resolution = 1024,
		instance_slots = 12,
		frustum_candidates = 11,
		frustum_culled_instances = 4,
		visible_instances = 8,
		occlusion_culled_instances = 3,
		occlusion_culled_meshlets = 5,
		hiz_occlusion_status = .Active,
		hiz_instance_threshold = WGPU_HIZ_MIN_INSTANCES,
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
	testing.expect(t, snapshot.gpu_scene_ms == 1.75)
	testing.expect_value(t, snapshot.render_scale, f32(0.75))
	testing.expect_value(t, snapshot.shadow_resolution, u32(1024))
	testing.expect(t, snapshot.gpu_timestamps_valid)
	testing.expect(t, snapshot.entity_count == 2)
	testing.expect(t, snapshot.retained_batches == 7)
	testing.expect(t, snapshot.visible_batches == 3)
	testing.expect(t, snapshot.visible_meshlet_draws == 6)
	testing.expect(t, snapshot.instance_count == 12)
	testing.expect(t, snapshot.frustum_candidates == 11)
	testing.expect(t, snapshot.frustum_culled_instances == 4)
	testing.expect(t, snapshot.visible_instances == 8)
	testing.expect(t, snapshot.occlusion_culled_instances == 3)
	testing.expect(t, snapshot.occlusion_culled_meshlets == 5)
	testing.expect(t, snapshot.hiz_occlusion_status == .Active)
	testing.expect(t, snapshot.hiz_instance_threshold == WGPU_HIZ_MIN_INSTANCES)
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
test_directional_shadow_cascades_cover_camera_depth_monotonically :: proc(t: ^testing.T) {
	camera := Camera_Instance {
		transform = {position = {0, 2, 8}},
		camera = {fov = 60, near = 0.1, far = 100},
	}
	cascades := wgpu_build_directional_shadow_cascades(camera, true, 1280, 720, {-0.5, -1, -0.25})
	previous := camera.camera.near
	for split, index in cascades.splits {
		testing.expect(t, split > previous)
		testing.expect(t, split <= WGPU_SHADOW_MAX_DISTANCE)
		testing.expect(t, cascades.texel_sizes[index] > 0)
		testing.expect(t, cascades.matrices[index] != mat4_identity())
		for value in cascades.matrices[index] {
			testing.expect(t, value == value)
		}
		previous = split
	}
	for index in 1 ..< WGPU_SHADOW_CASCADE_COUNT {
		testing.expect(t, cascades.texel_sizes[index] >= cascades.texel_sizes[index - 1])
	}
	testing.expect_value(
		t,
		cascades.splits[WGPU_SHADOW_CASCADE_COUNT - 1],
		WGPU_SHADOW_MAX_DISTANCE,
	)
}

@(test)
test_directional_shadow_cascade_splits_respect_short_camera_far_plane :: proc(t: ^testing.T) {
	camera := Camera_Instance {
		camera = {fov = 60, near = 0.5, far = 20},
	}
	cascades := wgpu_build_directional_shadow_cascades(camera, true, 800, 600, {0, -1, 0})
	testing.expect_value(t, cascades.splits[WGPU_SHADOW_CASCADE_COUNT - 1], f32(20))
}

@(test)
test_directional_shadow_shader_blends_adjacent_cascades :: proc(t: ^testing.T) {
	testing.expect(t, strings.contains(WGPU_GPU_DRIVEN_SHADER, "fn directional_shadow_cascade"))
	testing.expect(
		t,
		strings.contains(
			WGPU_GPU_DRIVEN_SHADER,
			"let transition_width = max((current_split - previous_split) * 0.1, 0.001)",
		),
	)
	testing.expect(
		t,
		strings.contains(WGPU_GPU_DRIVEN_SHADER, "next_visibility = directional_shadow_cascade"),
	)
	testing.expect(
		t,
		strings.contains(
			WGPU_GPU_DRIVEN_SHADER,
			"return mix(visibility, next_visibility, transition)",
		),
	)
	testing.expect(t, strings.contains(WGPU_COMPOSITE_SHADER, "step(0.5, resolved.a)"))
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
test_wgpu_visible_batch_bitset_is_bounded_and_word_aligned :: proc(t: ^testing.T) {
	testing.expect_value(t, wgpu_visible_batch_word_count(-1), 0)
	testing.expect_value(t, wgpu_visible_batch_word_count(0), 0)
	testing.expect_value(t, wgpu_visible_batch_word_count(1), 1)
	testing.expect_value(t, wgpu_visible_batch_word_count(32), 1)
	testing.expect_value(t, wgpu_visible_batch_word_count(33), 2)
	testing.expect_value(
		t,
		wgpu_visible_batch_word_count(WGPU_GPU_VISIBLE_BATCH_WORD_COUNT * 32 + 1),
		WGPU_GPU_VISIBLE_BATCH_WORD_COUNT,
	)
}

@(test)
test_wgpu_hiz_status_explains_every_reuse_gate :: proc(t: ^testing.T) {
	view_projection := mat4_identity()
	moved_camera := view_projection
	moved_camera[12] = 1
	testing.expect(
		t,
		wgpu_hiz_occlusion_status(
			false,
			true,
			false,
			WGPU_HIZ_MIN_INSTANCES - 1,
			view_projection,
			view_projection,
		) ==
		.Below_Threshold,
	)
	testing.expect(
		t,
		wgpu_hiz_occlusion_status(
			true,
			true,
			true,
			WGPU_HIZ_MIN_INSTANCES,
			view_projection,
			view_projection,
		) ==
		.Scene_Changed,
	)
	testing.expect(
		t,
		wgpu_hiz_occlusion_status(
			true,
			false,
			false,
			WGPU_HIZ_MIN_INSTANCES,
			view_projection,
			view_projection,
		) ==
		.Warming_Up,
	)
	testing.expect(
		t,
		wgpu_hiz_occlusion_status(
			true,
			true,
			false,
			WGPU_HIZ_MIN_INSTANCES,
			view_projection,
			moved_camera,
		) ==
		.Camera_Changed,
	)
	testing.expect(
		t,
		wgpu_hiz_occlusion_status(
			true,
			true,
			false,
			WGPU_HIZ_MIN_INSTANCES,
			view_projection,
			view_projection,
		) ==
		.Active,
	)
}

@(test)
test_wgpu_hiz_rejects_unsafe_large_sphere_projections :: proc(t: ^testing.T) {
	camera := Vec3{0, 3.9, 14}
	testing.expect(t, !wgpu_hiz_sphere_projection_safe({0, 8.35, -19, 23.38}, camera))
	testing.expect(t, wgpu_hiz_sphere_projection_safe({0, 3.9, -19, 1}, camera))
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
	wgpu_append_ui_vertices(&vertices, []ui.Paint_Command{command}, 1, nil, viewport, 1280, 720)
	testing.expect_value(t, len(vertices), 6)
	scale := min(viewport.width / 1280, viewport.height / 720)
	canvas_y := viewport.y
	testing.expect(t, math.abs(vertices[0].size_radius[0] - 430 * scale) < 0.001)
	testing.expect(t, math.abs(vertices[0].size_radius[1] - 90 * scale) < 0.001)
	testing.expect(t, math.abs(vertices[0].size_radius[2] - 12 * scale) < 0.001)
	testing.expect(t, math.abs(vertices[0].border_width - 2 * scale) < 0.001)
	expected_x := (viewport.x + 20 * scale) / 1280 * 2 - 1
	expected_y := 1 - (canvas_y + 20 * scale) / 720 * 2
	testing.expect(t, math.abs(vertices[0].position[0] - expected_x) < 0.001)
	testing.expect(t, math.abs(vertices[0].position[1] - expected_y) < 0.001)
}

@(test)
test_wgpu_ui_vertices_preserve_per_corner_gradient_colors :: proc(t: ^testing.T) {
	vertices: [dynamic]WGPU_UI_Vertex
	defer delete(vertices)
	command := ui.Paint_Command {
		kind = .Panel,
		rect = {0, 0, 100, 50},
		gradient = true,
		corner_colors = {{1, 0, 0, 1}, {0, 1, 0, 1}, {0, 0, 1, 1}, {1, 1, 1, 1}},
	}
	wgpu_append_ui_vertices(&vertices, []ui.Paint_Command{command}, 0, nil, {}, 100, 50)
	testing.expect_value(t, len(vertices), 6)
	testing.expect_value(t, vertices[0].color, [4]f32{1, 0, 0, 1})
	testing.expect_value(t, vertices[1].color, [4]f32{0, 1, 0, 1})
	testing.expect_value(t, vertices[2].color, [4]f32{0, 0, 1, 1})
	testing.expect_value(t, vertices[5].color, [4]f32{1, 1, 1, 1})
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
test_wgpu_batch_membership_invalidates_layout_only_for_policy_or_capacity_changes :: proc(
	t: ^testing.T,
) {
	cache: WGPU_Draw_Batch_Cache
	defer delete(cache.batches)
	append(
		&cache.batches,
		WGPU_Draw_Batch {
			instance_count = 1,
			visible_capacity = WGPU_VISIBLE_ALIGNMENT,
			meshlet_draw_count = 4,
		},
	)
	cache.batch_count = 1
	cache.instance_count = 1
	indices: [shared.MAX_GEOMETRY_LODS]u32
	layout_changed := wgpu_adjust_batch_membership(&cache, indices, 0, 1)
	testing.expect(t, layout_changed)
	testing.expect_value(t, cache.batches[0].instance_count, u32(2))
	testing.expect_value(t, cache.instance_count, 2)
	layout_changed = wgpu_adjust_batch_membership(&cache, indices, 0, -1)
	testing.expect(t, layout_changed)
	testing.expect_value(t, cache.batches[0].instance_count, u32(1))
	testing.expect_value(t, cache.instance_count, 1)

	cache.batches[0].instance_count = WGPU_VISIBLE_ALIGNMENT
	layout_changed = wgpu_adjust_batch_membership(&cache, indices, 0, 1)
	testing.expect(t, layout_changed)
}

@(test)
test_wgpu_meshlet_submission_policy_amortizes_indirect_commands :: proc(t: ^testing.T) {
	testing.expect(t, !wgpu_geometry_uses_virtual_clusters(nil))
	groups: [2]resources.Geometry_Cluster_Group
	one_group := resources.Geometry {
		cluster_groups = groups[:1],
	}
	testing.expect(t, !wgpu_geometry_uses_virtual_clusters(&one_group))
	one_group.cluster_max_depth = 1
	testing.expect(t, !wgpu_geometry_uses_virtual_clusters(&one_group))
	one_group.cluster_groups = groups[:]
	testing.expect(t, wgpu_geometry_uses_virtual_clusters(&one_group))
	testing.expect(t, !wgpu_virtual_geometry_submission(nil, &one_group))
	renderer := WGPU_Renderer {
		gpu_meshlet_supported = true,
	}
	testing.expect(t, wgpu_virtual_geometry_submission(&renderer, &one_group))
	testing.expect(t, wgpu_virtual_geometry_uses_compaction(&renderer, &one_group))
	renderer.gpu_meshlet_native_multi_draw = true
	testing.expect(t, wgpu_virtual_geometry_submission(&renderer, &one_group))
	testing.expect(t, !wgpu_virtual_geometry_uses_compaction(&renderer, &one_group))
	renderer.gpu_meshlet_supported = false
	testing.expect(t, !wgpu_virtual_geometry_submission(&renderer, &one_group))
	testing.expect(t, !wgpu_virtual_geometry_uses_compaction(&renderer, &one_group))

	testing.expect(t, !wgpu_meshlet_batch_submission(0, 8))
	testing.expect(t, !wgpu_meshlet_batch_submission(16, 1))
	testing.expect(t, wgpu_meshlet_batch_submission(16, 2))
	testing.expect_value(t, wgpu_virtual_shadow_error_pixels(1, 0), f32(8))
	testing.expect_value(t, wgpu_virtual_shadow_error_pixels(1, 1), f32(32))
	testing.expect_value(t, wgpu_virtual_shadow_error_pixels(1, 2), f32(128))
	testing.expect_value(t, wgpu_virtual_shadow_error_pixels(1, 3), f32(512))
	testing.expect_value(t, wgpu_virtual_shadow_error_pixels(1, 99), f32(512))

	testing.expect(t, !wgpu_meshlet_debug_forces_submission(.Lit))
	testing.expect(t, wgpu_meshlet_debug_forces_submission(.Meshlets))
	testing.expect(t, wgpu_meshlet_debug_forces_submission(.Meshlet_Visibility))
	testing.expect(t, wgpu_meshlet_debug_forces_submission(.Occlusion_Queries))

	renderer = WGPU_Renderer {
		gpu_meshlet_submission_active = true,
		gpu_meshlet_selected_draw_count = 12,
		gpu_meshlet_draw_count = 28,
		gpu_classic_batch_count = 5,
	}
	testing.expect_value(t, wgpu_active_meshlet_draw_count(&renderer), 12)
	testing.expect_value(t, wgpu_active_classic_batch_count(&renderer), 5)
	renderer.gpu_meshlet_force_enabled = true
	testing.expect_value(t, wgpu_active_meshlet_draw_count(&renderer), 28)
	testing.expect_value(t, wgpu_active_classic_batch_count(&renderer), 0)
}

@(test)
test_wgpu_gpu_uniforms_upload_only_after_value_changes :: proc(t: ^testing.T) {
	renderer: WGPU_Renderer
	render_uniform: WGPU_GPU_Render_Uniform
	testing.expect(t, wgpu_retain_render_uniform(&renderer, render_uniform))
	testing.expect(t, !wgpu_retain_render_uniform(&renderer, render_uniform))
	render_uniform.ambient.x = 0.25
	testing.expect(t, wgpu_retain_render_uniform(&renderer, render_uniform))
	render_uniform.debug.x = u32(shared.Render_Debug_View.Meshlets)
	testing.expect(t, wgpu_retain_render_uniform(&renderer, render_uniform))

	cull_uniform: WGPU_GPU_Cull_Uniform
	testing.expect(t, wgpu_retain_cull_uniform(&renderer, cull_uniform))
	testing.expect(t, !wgpu_retain_cull_uniform(&renderer, cull_uniform))
	cull_uniform.viewport.z = 1280
	testing.expect(t, wgpu_retain_cull_uniform(&renderer, cull_uniform))
	cull_uniform.hiz_view_projection[12] = 0.25
	testing.expect(t, wgpu_retain_cull_uniform(&renderer, cull_uniform))
}

@(test)
test_wgpu_gpu_timing_marks_only_encoded_passes_for_the_sample :: proc(t: ^testing.T) {
	renderer: WGPU_Renderer
	renderer.gpu_timestamp_supported = true
	renderer.gpu_timestamp_query_set = wgpu.QuerySet(rawptr(uintptr(1)))
	renderer.gpu_timestamp_active_slot = 2
	_, enabled := wgpu_gpu_pass_timestamps(&renderer, .World)
	testing.expect(t, enabled)
	readback := renderer.gpu_timestamp_readbacks[2]
	testing.expect(t, readback.phase_mask & (u32(1) << u32(WGPU_GPU_Timestamp_Phase.World)) != 0)
	testing.expect(t, readback.phase_mask & (u32(1) << u32(WGPU_GPU_Timestamp_Phase.UI)) == 0)
}

@(test)
test_wgpu_gpu_timing_never_encodes_from_zero_initialized_state :: proc(t: ^testing.T) {
	renderer: WGPU_Renderer
	_, enabled := wgpu_gpu_pass_timestamps(&renderer, .World)
	testing.expect(t, !enabled)
	wgpu_gpu_timing_begin_frame(&renderer)
	testing.expect_value(t, renderer.gpu_timestamp_active_slot, -1)
}

@(test)
test_wgpu_gpu_timing_requests_pass_timestamp_feature :: proc(t: ^testing.T) {
	features, count := wgpu_timestamp_required_features(true)
	testing.expect_value(t, count, 1)
	testing.expect_value(t, features[0], wgpu.FeatureName.TimestampQuery)

	_, unsupported_count := wgpu_timestamp_required_features(false)
	testing.expect_value(t, unsupported_count, 0)
}

@(test)
test_wgpu_renderer_requests_meshlet_first_instance_feature_when_available :: proc(t: ^testing.T) {
	features, count := wgpu_renderer_required_features(true, true, true)
	testing.expect_value(t, count, 3)
	testing.expect_value(t, features[0], wgpu.FeatureName.TimestampQuery)
	testing.expect_value(t, features[1], wgpu.FeatureName.IndirectFirstInstance)
	testing.expect_value(t, features[2], wgpu.FeatureName.MultiDrawIndirectCount)

	features, count = wgpu_renderer_required_features(false, true, false)
	testing.expect_value(t, count, 1)
	testing.expect_value(t, features[0], wgpu.FeatureName.IndirectFirstInstance)

	_, count = wgpu_renderer_required_features(false, false, false)
	testing.expect_value(t, count, 0)
}

@(test)
test_wgpu_expands_meshlet_local_indices_for_indexed_submission :: proc(t: ^testing.T) {
	geometry := resources.Geometry {
		meshlets = []resources.Meshlet {
			{vertex_offset = 0, triangle_offset = 0, vertex_count = 3, triangle_count = 1},
			{vertex_offset = 3, triangle_offset = 3, vertex_count = 3, triangle_count = 1},
		},
		meshlet_vertices = []u32{8, 3, 5, 1, 4, 7},
		meshlet_triangles = []u8{0, 2, 1, 2, 1, 0},
	}
	indices, err := wgpu_expand_meshlet_indices(&geometry)
	testing.expect_value(t, err, "")
	expected := [?]u32{8, 5, 3, 7, 4, 1}
	testing.expect_value(t, len(indices), len(expected))
	for value, index in expected {
		testing.expect_value(t, indices[index], value)
	}
}

@(test)
test_wgpu_expands_selected_cluster_pages_into_one_upload :: proc(t: ^testing.T) {
	geometry := resources.Geometry {
		cluster_groups = []resources.Geometry_Cluster_Group{{page_offset = 0, page_count = 2}},
		clusters = []resources.Geometry_Cluster {
			{vertex_offset = 0, triangle_offset = 0, triangle_count = 1},
			{vertex_offset = 3, triangle_offset = 3, triangle_count = 1},
		},
		cluster_pages = []resources.Geometry_Cluster_Page {
			{cluster_offset = 0, cluster_count = 1, index_count = 3},
			{cluster_offset = 1, cluster_count = 1, index_count = 3},
		},
		cluster_vertices = []u32{8, 3, 5, 1, 4, 7},
		cluster_triangles = []u8{0, 2, 1, 2, 1, 0},
	}
	indices, page_offsets, err := wgpu_expand_cluster_pages_indices(&geometry, []u32{0, 1})
	testing.expect_value(t, err, "")
	testing.expect_value(t, len(indices), 6)
	testing.expect_value(t, len(page_offsets), 3)
	testing.expect_value(t, page_offsets[0], u32(0))
	testing.expect_value(t, page_offsets[1], u32(3))
	testing.expect_value(t, page_offsets[2], u32(6))
	expected := [?]u32{8, 5, 3, 7, 4, 1}
	for value, index in expected {
		testing.expect_value(t, indices[index], value)
	}
}

@(test)
test_wgpu_meshlet_visibility_capacity_is_exact_and_bounded :: proc(t: ^testing.T) {
	testing.expect_value(t, wgpu_meshlet_visible_instance_capacity(0), u32(1))
	testing.expect_value(t, wgpu_meshlet_visible_instance_capacity(65), u32(65))
	capacity, ok := wgpu_meshlet_batch_visible_capacity(3, 65)
	testing.expect(t, ok)
	testing.expect_value(t, capacity, u32(195))
	zero_instance_capacity, zero_instance_ok := wgpu_meshlet_batch_visible_capacity(3, 0)
	testing.expect(t, zero_instance_ok)
	testing.expect_value(t, zero_instance_capacity, u32(3))
	testing.expect_value(
		t,
		wgpu_meshlet_visible_buffer_bytes(int(capacity)),
		u64(capacity) * (u64(size_of(u32)) + u64(size_of(WGPU_GPU_Meshlet_Debug_Record))),
	)

	_, ok = wgpu_meshlet_batch_visible_capacity(u32(WGPU_MAX_MESHLET_VISIBLE_ENTRIES), 2)
	testing.expect(t, !ok)

	camera := shared.camera_defaults()
	testing.expect_value(t, wgpu_meshlet_debug_record_offset(camera, true, 4096, false), u32(0))
	camera.debug_view = .Meshlet_Visibility
	testing.expect_value(t, wgpu_meshlet_debug_record_offset(camera, false, 4096, false), u32(0))
	testing.expect_value(t, wgpu_meshlet_debug_record_offset(camera, true, 4096, false), u32(4096))
	camera.debug_view = .Occlusion_Queries
	testing.expect_value(t, wgpu_meshlet_debug_record_offset(camera, true, 4096, false), u32(4096))
	camera.debug_occlusion_freeze = true
	testing.expect_value(t, wgpu_meshlet_debug_record_offset(camera, true, 4096, false), u32(4096))
	testing.expect_value(t, wgpu_meshlet_debug_record_offset(camera, true, 4096, true), u32(0))
}

@(test)
test_wgpu_culling_shader_stays_within_portable_storage_binding_floor :: proc(t: ^testing.T) {
	testing.expect_value(t, strings.count(WGPU_GPU_CULL_SHADER, "var<storage"), 8)
	testing.expect(t, !strings.contains(WGPU_GPU_CULL_SHADER, "@binding(10)"))
	testing.expect(t, strings.contains(WGPU_GPU_CULL_SHADER, "virtual_page_demand_feedback"))
	testing.expect(t, strings.contains(WGPU_GPU_CULL_SHADER, "virtual_page_touch_feedback"))
	testing.expect(t, strings.contains(WGPU_GPU_CULL_SHADER, "virtual_page_prefetch_feedback"))
	testing.expect(t, strings.contains(WGPU_GPU_CULL_SHADER, "append_virtual_page_feedback"))
	testing.expect(t, strings.contains(WGPU_GPU_CULL_SHADER, "prefetch_virtual_cluster"))
	testing.expect(t, strings.contains(WGPU_GPU_CULL_SHADER, "predictive_camera_planes"))
	testing.expect(t, strings.contains(WGPU_GPU_CULL_SHADER, "meshlet.refined_resident == 0u"))
	testing.expect(
		t,
		strings.contains(
			WGPU_GPU_DRIVEN_SHADER,
			"batch_index: u32,\n\ttransition_start: u32,\n\trefined_transition_start: u32",
		),
	)
	testing.expect(
		t,
		strings.contains(
			WGPU_GPU_CULL_SHADER,
			"batch_index: u32,\n\ttransition_start: u32,\n\trefined_transition_start: u32",
		),
	)
	testing.expect(t, strings.contains(WGPU_GPU_DRIVEN_SHADER, "apply_virtual_transition"))
	testing.expect(t, strings.contains(WGPU_GPU_DRIVEN_SHADER, "threshold < transition.x"))
	testing.expect(t, strings.contains(WGPU_GPU_DRIVEN_SHADER, "threshold >= transition.y"))
	testing.expect(t, strings.contains(WGPU_GPU_DRIVEN_SHADER, "virtual_lod_progress"))
	testing.expect(t, strings.contains(WGPU_GPU_DRIVEN_SHADER, "virtual_transition_marker"))
	testing.expect(t, strings.contains(WGPU_GPU_DRIVEN_SHADER, "0.61803398875"))
	testing.expect(
		t,
		strings.contains(
			WGPU_GPU_DRIVEN_SHADER,
			"meshlet.refined_resident != 0u || meshlet.refined_transition_start != 0u",
		),
	)
	testing.expect(t, strings.contains(WGPU_GPU_CULL_SHADER, "virtual_frontier_progress"))
	testing.expect(t, strings.contains(WGPU_GPU_CULL_SHADER, "refined_progress < 1.0"))
	testing.expect(t, strings.contains(WGPU_GPU_CULL_SHADER, "cull_compact_candidate"))
	testing.expect(t, strings.contains(WGPU_GPU_CULL_SHADER, "cull_compact_camera_clusters"))
	testing.expect(t, strings.contains(WGPU_GPU_CULL_SHADER, "cull_compact_shadow_clusters"))
	testing.expect_value(t, size_of(WGPU_GPU_Meshlet_Info) % 16, 0)
}

@(test)
test_wgpu_virtual_group_residency_requires_every_page :: proc(t: ^testing.T) {
	geometry := resources.Geometry {
		cluster_groups = []resources.Geometry_Cluster_Group{{page_offset = 0, page_count = 2}},
	}
	cache := WGPU_Geometry_Cache {
		cluster_pages = make([dynamic]WGPU_Cluster_Page_Cache, 2),
		cluster_groups = make([dynamic]WGPU_Cluster_Group_Cache, 1),
	}
	defer delete(cache.cluster_pages)
	defer delete(cache.cluster_groups)
	cache.cluster_groups[0].active = true
	resident, missing, has_missing := wgpu_cluster_group_residency(&geometry, &cache, 0)
	testing.expect(t, !resident)
	testing.expect(t, has_missing)
	testing.expect_value(t, missing, u32(0))
	cache.cluster_pages[0].resident = true
	resident, missing, has_missing = wgpu_cluster_group_residency(&geometry, &cache, 0)
	testing.expect(t, !resident)
	testing.expect(t, has_missing)
	testing.expect_value(t, missing, u32(0))
	cache.cluster_pages[1].resident = true
	resident, _, has_missing = wgpu_cluster_group_residency(&geometry, &cache, 0)
	testing.expect(t, !resident)
	testing.expect(t, has_missing)
	cache.cluster_groups[0].transition_complete = true
	resident, _, has_missing = wgpu_cluster_group_residency(&geometry, &cache, 0)
	testing.expect(t, resident)
	testing.expect(t, !has_missing)
}

@(test)
test_wgpu_virtual_camera_prediction_tracks_motion_and_rejects_discontinuities :: proc(
	t: ^testing.T,
) {
	initial := wgpu_predict_virtual_camera({0, 0, 0}, {0, 0, -1}, {}, {}, {}, 100, false)
	testing.expect(t, !initial.enabled)
	testing.expect_value(t, initial.position, Vec3{})

	moving := wgpu_predict_virtual_camera({2, 0, 0}, {0, 0, -1}, {}, {0, 0, -1}, {}, 100, true)
	testing.expect(t, moving.enabled)
	testing.expect(t, moving.position.x > 2)
	testing.expect(t, moving.position.x <= 22)

	steady := wgpu_predict_virtual_camera(
		{4, 0, 0},
		{0, 0, -1},
		{2, 0, 0},
		{0, 0, -1},
		moving.velocity,
		100,
		true,
	)
	testing.expect(t, steady.enabled)
	testing.expect(t, steady.position.x > moving.position.x)

	turning := wgpu_predict_virtual_camera(
		{4, 0, 0},
		{0.1, 0, -0.9949874},
		{4, 0, 0},
		{0, 0, -1},
		{},
		100,
		true,
	)
	testing.expect(t, turning.enabled)
	testing.expect(t, turning.forward.x > 0.1)

	teleport := wgpu_predict_virtual_camera(
		{80, 0, 0},
		{0, 0, -1},
		{4, 0, 0},
		{0, 0, -1},
		steady.velocity,
		100,
		true,
	)
	testing.expect(t, !teleport.enabled)
	testing.expect_value(t, teleport.position, Vec3{80, 0, 0})
}

@(test)
test_wgpu_virtual_geometry_touches_and_evicts_complete_groups :: proc(t: ^testing.T) {
	geometry := resources.Geometry {
		cluster_groups = []resources.Geometry_Cluster_Group {
			{page_offset = 0, page_count = 2},
			{page_offset = 2, page_count = 2},
		},
		cluster_pages = make([]resources.Geometry_Cluster_Page, 4),
	}
	defer delete(geometry.cluster_pages)
	cache := WGPU_Geometry_Cache {
		handle = {index = 4, generation = 2},
		cluster_pages = make([dynamic]WGPU_Cluster_Page_Cache, 4),
		cluster_groups = make([dynamic]WGPU_Cluster_Group_Cache, 2),
	}
	defer delete(cache.cluster_pages)
	defer delete(cache.cluster_groups)
	for index in 0 ..< 4 {
		cache.cluster_pages[index] = {
			range = {offset = u64(index * 4), size = 4},
			last_used_frame = 1 if index < 2 else 8,
			group_index = 0 if index < 2 else 1,
			resident = true,
		}
	}
	page_offset, page_count, range_ok := wgpu_virtual_group_page_range(&geometry, 1)
	testing.expect(t, range_ok)
	testing.expect_value(t, page_offset, u32(2))
	testing.expect_value(t, page_count, u32(2))
	cache.cluster_pages[2].prefetched = true
	cache.cluster_pages[3].prefetched = true
	cache.cluster_groups[0] = {
		last_used_frame = 1,
		resident = true,
	}
	cache.cluster_groups[1] = {
		last_used_frame = 8,
		resident = true,
		prefetched = true,
	}
	prefetch_hit, promoted_pages := wgpu_touch_virtual_group(&cache, &geometry, 1, 12, 3)
	testing.expect(t, prefetch_hit)
	testing.expect_value(t, promoted_pages, u32(2))
	testing.expect_value(t, cache.cluster_pages[2].last_used_frame, u64(12))
	testing.expect_value(t, cache.cluster_pages[3].last_used_frame, u64(12))
	testing.expect(t, !cache.cluster_pages[2].prefetched)
	testing.expect(t, !cache.cluster_pages[3].prefetched)

	renderer := WGPU_Renderer {
		geometry_cache = make([dynamic]WGPU_Geometry_Cache, 0, 1),
		virtual_geometry_resident_bytes = 16,
	}
	defer delete(renderer.geometry_cache)
	defer delete(renderer.geometry_index_arena.allocator.free_ranges)
	append(&renderer.geometry_cache, cache)
	handle, group_index, evicted := wgpu_evict_virtual_group(&renderer, 40, false)
	testing.expect(t, evicted)
	testing.expect_value(t, handle, cache.handle)
	testing.expect_value(t, group_index, u32(0))
	testing.expect(t, !renderer.geometry_cache[0].cluster_pages[0].resident)
	testing.expect(t, !renderer.geometry_cache[0].cluster_pages[1].resident)
	testing.expect(t, renderer.geometry_cache[0].cluster_pages[2].resident)
	testing.expect(t, renderer.geometry_cache[0].cluster_pages[3].resident)
	testing.expect_value(t, renderer.virtual_geometry_page_eviction_count, u64(2))
	testing.expect_value(t, renderer.virtual_geometry_group_eviction_count, u64(1))
}

@(test)
test_wgpu_virtual_geometry_demand_reclaims_prefetch_before_visible_residency :: proc(
	t: ^testing.T,
) {
	renderer := WGPU_Renderer {
		geometry_cache = make([dynamic]WGPU_Geometry_Cache, 1),
		virtual_geometry_resident_bytes = 8,
	}
	defer delete(renderer.geometry_cache)
	defer delete(renderer.geometry_index_arena.allocator.free_ranges)
	defer delete(renderer.geometry_vertex_arena.allocator.free_ranges)
	cache := &renderer.geometry_cache[0]
	cache.handle = {
		index = 7,
		generation = 3,
	}
	resize(&cache.cluster_pages, 2)
	defer delete(cache.cluster_pages)
	resize(&cache.cluster_groups, 2)
	defer delete(cache.cluster_groups)
	cache.cluster_pages[0] = {
		range = {offset = 0, size = 4},
		last_used_frame = 1,
		group_index = 0,
		resident = true,
	}
	cache.cluster_pages[1] = {
		range = {offset = 4, size = 4},
		last_used_frame = 39,
		group_index = 1,
		resident = true,
		prefetched = true,
	}
	cache.cluster_groups[0] = {
		last_used_frame = 1,
		resident = true,
	}
	cache.cluster_groups[1] = {
		last_used_frame = 39,
		resident = true,
		prefetched = true,
	}

	_, group_index, evicted := wgpu_evict_virtual_group(&renderer, 40, true)
	testing.expect(t, evicted)
	testing.expect_value(t, group_index, u32(1))
	testing.expect(t, cache.cluster_pages[0].resident)
	testing.expect(t, !cache.cluster_pages[1].resident)
	testing.expect_value(t, renderer.virtual_geometry_prefetch_eviction_count, u64(1))
}

@(test)
test_wgpu_virtual_geometry_prefetch_preserves_recent_residency :: proc(t: ^testing.T) {
	renderer := WGPU_Renderer {
		geometry_cache = make([dynamic]WGPU_Geometry_Cache, 1),
		virtual_geometry_resident_bytes = 4,
	}
	defer delete(renderer.geometry_cache)
	cache := &renderer.geometry_cache[0]
	resize(&cache.cluster_pages, 1)
	defer delete(cache.cluster_pages)
	resize(&cache.cluster_groups, 1)
	defer delete(cache.cluster_groups)
	cache.cluster_pages[0] = {
		range = {size = 4},
		last_used_frame = 39,
		group_index = 0,
		resident = true,
	}
	cache.cluster_groups[0] = {
		last_used_frame = 39,
		resident = true,
	}

	_, _, evicted := wgpu_evict_virtual_group(&renderer, 40, false)
	testing.expect(t, !evicted)
	testing.expect(t, cache.cluster_pages[0].resident)
}

@(test)
test_wgpu_virtual_geometry_admission_starts_its_grace_window_at_upload :: proc(t: ^testing.T) {
	testing.expect_value(t, wgpu_virtual_page_admission_frame(40, 36), u64(40))
	testing.expect_value(t, wgpu_virtual_page_admission_frame(40, 40), u64(40))
}

@(test)
test_wgpu_virtual_geometry_activates_only_after_a_stable_window :: proc(t: ^testing.T) {
	renderer := WGPU_Renderer {
		geometry_cache = make([dynamic]WGPU_Geometry_Cache, 1),
	}
	defer delete(renderer.geometry_cache)
	defer delete(renderer.virtual_geometry_pending_activations)
	defer delete(renderer.virtual_geometry_transitions)
	cache := &renderer.geometry_cache[0]
	cache.handle = {
		index = 7,
		generation = 2,
	}
	resize(&cache.cluster_groups, 2)
	defer delete(cache.cluster_groups)
	cache.cluster_groups[0] = {
		resident_since_frame = 10,
		last_demand_frame = 15,
		resident = true,
	}
	cache.cluster_groups[1] = {
		resident_since_frame = 10,
		last_demand_frame = 15,
		resident = true,
	}
	changes: [dynamic]WGPU_Virtual_Group_Change
	defer delete(changes)
	wgpu_append_virtual_group_change(
		&renderer.virtual_geometry_pending_activations,
		cache.handle,
		0,
	)
	wgpu_append_virtual_group_change(
		&renderer.virtual_geometry_pending_activations,
		cache.handle,
		1,
	)

	renderer.profile_frame_index = 22
	wgpu_activate_stable_virtual_groups(&renderer, &changes)
	testing.expect(t, !cache.cluster_groups[0].active)
	testing.expect_value(t, len(changes), 0)

	renderer.profile_frame_index = 23
	wgpu_activate_stable_virtual_groups(&renderer, &changes)
	testing.expect(t, cache.cluster_groups[0].active)
	testing.expect(t, cache.cluster_groups[1].active)
	testing.expect(t, !cache.cluster_groups[0].transition_complete)
	testing.expect(t, !cache.cluster_groups[1].transition_complete)
	testing.expect_value(t, len(renderer.virtual_geometry_transitions), 2)
	testing.expect_value(t, len(changes), 2)

	clear(&changes)
	renderer.profile_frame_index = 38
	wgpu_finish_virtual_group_transitions(&renderer, &changes)
	testing.expect_value(t, len(changes), 0)
	testing.expect_value(t, len(renderer.virtual_geometry_transitions), 2)
	renderer.profile_frame_index = 39
	wgpu_finish_virtual_group_transitions(&renderer, &changes)
	testing.expect(t, cache.cluster_groups[0].transition_complete)
	testing.expect(t, cache.cluster_groups[1].transition_complete)
	testing.expect_value(t, len(changes), 2)
	testing.expect_value(t, len(renderer.virtual_geometry_transitions), 0)

	cache.cluster_groups[0].active = false
	cache.cluster_groups[0].transition_complete = false
	cache.cluster_groups[0].last_demand_frame = 41
	clear(&changes)
	wgpu_append_virtual_group_change(
		&renderer.virtual_geometry_pending_activations,
		cache.handle,
		0,
	)
	renderer.profile_frame_index = 41
	wgpu_activate_stable_virtual_groups(&renderer, &changes)
	testing.expect(t, !cache.cluster_groups[0].active)
	renderer.profile_frame_index = 42
	wgpu_activate_stable_virtual_groups(&renderer, &changes)
	testing.expect(t, cache.cluster_groups[0].active)
	testing.expect(t, !cache.cluster_groups[0].transition_complete)
	// The maximum hold bounds how long continuously demanded resident data can
	// remain staged; it does not make admission depend on camera idleness.
	testing.expect_value(t, len(changes), 1)
}

@(test)
test_wgpu_virtual_geometry_serializes_nested_transitions :: proc(t: ^testing.T) {
	renderer := WGPU_Renderer {
		geometry_cache = make([dynamic]WGPU_Geometry_Cache, 1),
		profile_frame_index = 40,
	}
	defer delete(renderer.geometry_cache)
	defer delete(renderer.virtual_geometry_pending_activations)
	defer delete(renderer.virtual_geometry_transitions)
	cache := &renderer.geometry_cache[0]
	cache.handle = {
		index = 9,
		generation = 3,
	}
	cache.cluster_groups = make([dynamic]WGPU_Cluster_Group_Cache, 2)
	defer delete(cache.cluster_groups)
	cache.refined_group_parent_offsets = make([dynamic]u32, 3)
	defer delete(cache.refined_group_parent_offsets)
	cache.refined_group_parents = make([dynamic]u32, 1)
	defer delete(cache.refined_group_parents)
	cache.refined_group_parent_offsets[0] = 0
	cache.refined_group_parent_offsets[1] = 0
	cache.refined_group_parent_offsets[2] = 1
	cache.refined_group_parents[0] = 0
	cache.cluster_groups[0] = {
		resident = true,
		active = true,
		transition_start_frame = 36,
	}
	cache.cluster_groups[1] = {
		resident = true,
		resident_since_frame = 20,
		last_demand_frame = 20,
	}
	wgpu_append_virtual_group_change(
		&renderer.virtual_geometry_pending_activations,
		cache.handle,
		1,
	)
	changes: [dynamic]WGPU_Virtual_Group_Change
	defer delete(changes)
	wgpu_activate_stable_virtual_groups(&renderer, &changes)
	testing.expect(t, !cache.cluster_groups[1].active)

	cache.cluster_groups[0].transition_complete = true
	wgpu_activate_stable_virtual_groups(&renderer, &changes)
	testing.expect(t, cache.cluster_groups[1].active)
	testing.expect(t, !cache.cluster_groups[1].transition_complete)
}

@(test)
test_wgpu_virtual_geometry_pressure_selects_a_stable_fitting_error :: proc(t: ^testing.T) {
	renderer := WGPU_Renderer {
		virtual_geometry_budget_bytes = 100,
		virtual_geometry_resident_bytes = 98,
	}
	testing.expect(t, !wgpu_update_virtual_geometry_error(&renderer, 1_000, 0, 31))
	testing.expect_value(
		t,
		renderer.virtual_geometry_error_pixels,
		WGPU_VIRTUAL_GEOMETRY_MIN_ERROR_PIXELS,
	)
	testing.expect(t, wgpu_update_virtual_geometry_error(&renderer, 1_000, 0, 32))
	testing.expect_value(t, renderer.virtual_geometry_error_pixels, f32(2))
	testing.expect(t, !wgpu_update_virtual_geometry_error(&renderer, 1_000, 0, 63))
	testing.expect(t, wgpu_update_virtual_geometry_error(&renderer, 1_000, 0, 64))
	testing.expect_value(t, renderer.virtual_geometry_error_pixels, f32(4))

	renderer.virtual_geometry_resident_bytes = 97
	testing.expect(t, !wgpu_update_virtual_geometry_error(&renderer, 1_000, 0, 96))
	testing.expect_value(t, renderer.virtual_geometry_error_pixels, f32(4))
	renderer.virtual_geometry_resident_bytes = 98
	testing.expect(t, !wgpu_update_virtual_geometry_error(&renderer, 0, 0, 96))
	testing.expect(t, wgpu_update_virtual_geometry_error(&renderer, 0, 1, 96))
	testing.expect_value(t, renderer.virtual_geometry_error_pixels, f32(8))
}

@(test)
test_wgpu_virtual_geometry_indexes_only_direct_refinement_dependencies :: proc(t: ^testing.T) {
	geometry := resources.Geometry {
		cluster_groups = make([]resources.Geometry_Cluster_Group, 3),
		clusters = []resources.Geometry_Cluster {
			{group = 2, refined_group = 1},
			{group = 2, refined_group = 0},
			{group = 1, refined_group = 0},
			{group = 0, refined_group = -1},
		},
	}
	defer delete(geometry.cluster_groups)
	cluster_offsets, clusters, parent_offsets, parents := wgpu_build_refined_group_cluster_index(
		&geometry,
	)
	defer delete(cluster_offsets)
	defer delete(clusters)
	defer delete(parent_offsets)
	defer delete(parents)
	expected_cluster_offsets := [?]u32{0, 2, 3, 3}
	expected_clusters := [?]u32{1, 2, 0}
	expected_parent_offsets := [?]u32{0, 2, 3, 3}
	expected_parents := [?]u32{1, 2, 2}
	testing.expect_value(t, len(cluster_offsets), len(expected_cluster_offsets))
	testing.expect_value(t, len(clusters), len(expected_clusters))
	testing.expect_value(t, len(parent_offsets), len(expected_parent_offsets))
	testing.expect_value(t, len(parents), len(expected_parents))
	for value, index in expected_cluster_offsets {
		testing.expect_value(t, cluster_offsets[index], value)
	}
	for value, index in expected_clusters {
		testing.expect_value(t, clusters[index], value)
	}
	for value, index in expected_parent_offsets {
		testing.expect_value(t, parent_offsets[index], value)
	}
	for value, index in expected_parents {
		testing.expect_value(t, parents[index], value)
	}

	groups := make([]WGPU_Cluster_Group_Cache, 3)
	defer delete(groups)
	wgpu_adjust_virtual_fallback_protection(groups, parent_offsets[:], parents[:], 0, 1)
	testing.expect_value(t, groups[0].resident_refinement_count, u32(0))
	testing.expect_value(t, groups[1].resident_refinement_count, u32(1))
	testing.expect_value(t, groups[2].resident_refinement_count, u32(1))
	wgpu_adjust_virtual_fallback_protection(groups, parent_offsets[:], parents[:], 0, -1)
	testing.expect_value(t, groups[1].resident_refinement_count, u32(0))
	testing.expect_value(t, groups[2].resident_refinement_count, u32(0))
}

@(test)
test_wgpu_virtual_geometry_eviction_plan_protects_fallbacks_and_priority :: proc(t: ^testing.T) {
	renderer := WGPU_Renderer {
		geometry_cache = make([dynamic]WGPU_Geometry_Cache, 1),
	}
	defer delete(renderer.geometry_cache)
	cache := &renderer.geometry_cache[0]
	resize(&cache.cluster_groups, 3)
	defer delete(cache.cluster_groups)
	cache.cluster_groups[0] = {
		last_used_frame = 1,
		priority = 1,
		resident = true,
		resident_refinement_count = 1,
	}
	cache.cluster_groups[1] = {
		last_used_frame = 1,
		priority = 4,
		resident = true,
	}
	cache.cluster_groups[2] = {
		last_used_frame = 20,
		priority = 2,
		resident = true,
		prefetched = true,
	}
	candidates := wgpu_build_virtual_eviction_candidates(&renderer, 50)
	testing.expect_value(t, len(candidates), 2)
	testing.expect_value(t, candidates[0].group_index, u32(2))
	testing.expect_value(t, candidates[1].group_index, u32(1))
	cursor := 1
	_, _, evicted := wgpu_evict_virtual_candidate(&renderer, candidates[:], &cursor, 2)
	testing.expect(t, !evicted)
	testing.expect(t, cache.cluster_groups[0].resident)
	testing.expect(t, cache.cluster_groups[1].resident)
}

@(test)
test_wgpu_virtual_geometry_preloads_only_complete_resources_that_fit :: proc(t: ^testing.T) {
	geometry := resources.Geometry {
		vertices = []resources.Vertex{{}},
		indices = []u32{0},
		cluster_pages = []resources.Geometry_Cluster_Page{{index_count = 8}, {index_count = 16}},
	}
	required_bytes :=
		wgpu_align_arena_offset(u64(size_of(resources.Vertex)), u64(size_of(resources.Vertex))) +
		wgpu_align_arena_offset(u64(size_of(u32)), u64(size_of(u32))) +
		u64(24 * size_of(u32))
	renderer := WGPU_Renderer {
		virtual_geometry_budget_bytes = required_bytes + 32,
		virtual_geometry_resident_bytes = 32,
	}
	testing.expect(t, wgpu_virtual_geometry_should_preload_pages(&renderer, &geometry))
	renderer.virtual_geometry_resident_bytes = 33
	testing.expect(t, !wgpu_virtual_geometry_should_preload_pages(&renderer, &geometry))
	renderer.virtual_geometry_resident_bytes = required_bytes + 32
	testing.expect(t, !wgpu_virtual_geometry_should_preload_pages(&renderer, &geometry))
	testing.expect(
		t,
		wgpu_virtual_geometry_should_preload_pages(&renderer, &geometry, required_bytes),
	)
	renderer.virtual_geometry_resident_bytes = renderer.virtual_geometry_budget_bytes + 1
	testing.expect(t, !wgpu_virtual_geometry_should_preload_pages(&renderer, &geometry))
}

@(test)
test_wgpu_virtual_page_io_reads_bounded_product_ranges :: proc(t: ^testing.T) {
	root, root_err := os.make_directory_temp("", "scrapbot-page-io-*", context.allocator)
	testing.expect(t, root_err == nil)
	if root_err != nil {
		return
	}
	defer os.remove_all(root)
	defer delete(root)
	path := strings.concatenate({root, "/pages.bin"})
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, []u8{1, 2, 3, 4, 5, 6}) == nil)
	io: WGPU_Virtual_Page_IO
	defer wgpu_virtual_page_io_destroy(&io)
	handle := shared.Geometry_Handle {
		index = 7,
		generation = 3,
	}
	testing.expect(t, wgpu_virtual_page_io_schedule(&io, handle, 11, 2, path, 2, 3))
	job: ^WGPU_Virtual_Page_IO_Job
	for _ in 0 ..< 10000 {
		ok: bool
		job, ok = wgpu_virtual_page_io_pop(&io)
		if ok {
			break
		}
		thread.yield()
	}
	testing.expect(t, job != nil)
	if job != nil {
		testing.expect(t, !job.err)
		testing.expect_value(t, job.handle, handle)
		testing.expect_value(t, job.geometry_version, u32(11))
		testing.expect_value(t, job.page_index, u32(2))
		testing.expect_value(t, len(job.bytes), 3)
		if len(job.bytes) == 3 {
			testing.expect(t, job.bytes[0] == 3 && job.bytes[1] == 4 && job.bytes[2] == 5)
		}
		wgpu_virtual_page_io_destroy_job(job)
	}
}

@(test)
test_wgpu_gpu_timing_resolves_only_queries_written_by_the_frame :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		wgpu_gpu_timestamp_resolve_bytes(),
		u64(WGPU_GPU_TIMESTAMP_RESOLVE_RANGE_COUNT) * WGPU_GPU_TIMESTAMP_RESOLVE_ALIGNMENT,
	)
	phase_mask :=
		u32(1) << u32(WGPU_GPU_Timestamp_Phase.Shadow) |
		u32(1) << u32(WGPU_GPU_Timestamp_Phase.World)
	ranges, count := wgpu_gpu_timestamp_resolve_ranges(phase_mask, 3)
	testing.expect_value(t, count, 4)
	testing.expect_value(t, ranges[0].first, u32(WGPU_GPU_Timestamp_Phase.Shadow) * 2)
	testing.expect_value(t, ranges[0].count, 2)
	testing.expect_value(t, ranges[1].first, u32(WGPU_GPU_Timestamp_Phase.World) * 2)
	testing.expect_value(t, ranges[1].count, 2)
	testing.expect_value(t, ranges[2].first, u32(WGPU_GPU_HIZ_EXTRA_QUERY_BASE))
	testing.expect_value(t, ranges[2].count, 4)
	testing.expect_value(t, ranges[3].first, u32(WGPU_GPU_SHADOW_EXTRA_QUERY_BASE))
	testing.expect_value(t, ranges[3].count, u32((WGPU_SHADOW_CASCADE_COUNT - 1) * 2))
	_, empty_count := wgpu_gpu_timestamp_resolve_ranges(0, 0)
	testing.expect_value(t, empty_count, 0)
}

@(test)
test_wgpu_gpu_frame_timing_uses_ordered_pass_boundaries :: proc(t: ^testing.T) {
	span: WGPU_GPU_Timestamp_Span
	wgpu_gpu_timestamp_span_include(&span, 2_000, 4_000, true)
	wgpu_gpu_timestamp_span_include(&span, 1_000, 3_000, true)
	wgpu_gpu_timestamp_span_include(&span, 4_000, 5_500, false)
	testing.expect(t, span.has_frame && span.has_scene)
	frame_ms, scene_ms, valid := wgpu_gpu_span_ms(
		span.frame_begin,
		span.scene_end,
		span.frame_end,
		2_000,
	)
	testing.expect(t, valid)
	testing.expect_value(t, scene_ms, 6.0)
	testing.expect_value(t, frame_ms, 9.0)

	_, _, valid = wgpu_gpu_span_ms(1_000, 900, 5_500, 2_000)
	testing.expect(t, !valid)
	_, _, valid = wgpu_gpu_span_ms(1_000, 4_000, 3_999, 2_000)
	testing.expect(t, !valid)
}

@(test)
test_profile_distribution_reports_median_p95_and_max :: proc(t: ^testing.T) {
	values := []f64{4, 1, 3, 2, 100}
	distribution := profile_distribution(values)
	testing.expect_value(t, distribution.samples, 5)
	testing.expect_value(t, distribution.median_ms, 3.0)
	testing.expect_value(t, distribution.p95_ms, 100.0)
	testing.expect_value(t, distribution.max_ms, 100.0)

	even := profile_distribution([]f64{4, 1, 3, 2})
	testing.expect_value(t, even.median_ms, 2.5)
}

@(test)
test_profile_correlates_delayed_gpu_timing_with_originating_frame :: proc(t: ^testing.T) {
	collector: Profile_Collector
	init_profile_collector(&collector, 2, 3, "test", "test", "wgpu")
	defer destroy_profile_collector(&collector)

	stats := Render_Stats {
		draw_batches = 7,
	}
	profile_record_gpu_frame(
		&collector,
		3,
		{frame = 5.0, scene = 4.5, world = 3.0, composite = 2.0},
	)
	profile_record_frame(
		&collector,
		2,
		0.001,
		1.0 / 60.0,
		320,
		180,
		1,
		{width = 320, height = 180},
		&stats,
	)
	profile_record_frame(
		&collector,
		3,
		0.002,
		1.0 / 60.0,
		320,
		180,
		1,
		{width = 320, height = 180},
		&stats,
	)
	profile_record_gpu_frame(
		&collector,
		2,
		{frame = 4.0, scene = 3.5, world = 2.5, composite = 1.5},
	)
	finish_profile_collector(&collector)

	testing.expect_value(t, collector.report.recorded_frames, 2)
	testing.expect_value(t, collector.frames[0].render.draw_batches, 7)
	testing.expect_value(t, collector.frames[0].render.gpu_frame_ms, 4.0)
	testing.expect_value(t, collector.frames[0].render.gpu_scene_ms, 3.5)
	testing.expect_value(t, collector.frames[1].render.gpu_frame_ms, 5.0)
	testing.expect_value(t, collector.frames[1].render.gpu_scene_ms, 4.5)
	testing.expect_value(t, collector.report.summary.gpu_frame.samples, 2)
	testing.expect_value(t, collector.report.summary.gpu_frame.median_ms, 4.5)
	testing.expect_value(t, collector.report.summary.gpu_scene.median_ms, 4.0)
}

@(test)
test_profile_reports_per_frame_counter_deltas_after_warmup :: proc(t: ^testing.T) {
	collector: Profile_Collector
	init_profile_collector(&collector, 1, 2, "test", "test", "wgpu")
	defer destroy_profile_collector(&collector)

	stats := Render_Stats {
		draw_database_rebuilds = 3,
		cluster_dispatches = 7,
		instance_uploads = 11,
		instance_upload_bytes = 1024,
		geometry_arena_uploads = 101,
		geometry_arena_upload_bytes = 4096,
		geometry_arena_growths = 2,
		virtual_geometry_page_uploads = 5,
		virtual_geometry_page_upload_bytes = 2048,
		virtual_geometry_page_reads = 7,
		virtual_geometry_page_read_bytes = 3072,
		virtual_geometry_page_read_failures = 1,
		virtual_geometry_page_evictions = 1,
		virtual_geometry_group_uploads = 3,
		virtual_geometry_group_activations = 2,
		virtual_geometry_prefetch_group_uploads = 2,
		virtual_geometry_prefetch_hits = 4,
		virtual_geometry_prefetch_evictions = 1,
		virtual_geometry_group_evictions = 1,
		virtual_geometry_deferred_groups = 4,
		ui_vertex_rebuilds = 5,
		ui_vertex_upload_bytes = 2048,
	}
	profile_record_frame(&collector, 0, 0, 0, 100, 100, 1, {}, &stats)

	stats.cluster_dispatches += 1
	stats.instance_uploads += 2
	stats.instance_upload_bytes += 96
	stats.geometry_arena_uploads += 3
	stats.geometry_arena_upload_bytes += 768
	stats.geometry_arena_growths += 1
	stats.virtual_geometry_page_uploads += 2
	stats.virtual_geometry_page_upload_bytes += 512
	stats.virtual_geometry_page_reads += 3
	stats.virtual_geometry_page_read_bytes += 1024
	stats.virtual_geometry_page_read_failures += 2
	stats.virtual_geometry_page_evictions += 1
	stats.virtual_geometry_group_uploads += 1
	stats.virtual_geometry_group_activations += 1
	stats.virtual_geometry_prefetch_group_uploads += 1
	stats.virtual_geometry_prefetch_hits += 2
	stats.virtual_geometry_prefetch_evictions += 1
	stats.virtual_geometry_group_evictions += 1
	stats.virtual_geometry_deferred_groups += 2
	stats.ui_vertex_rebuilds += 1
	profile_record_frame(&collector, 1, 0, 0, 100, 100, 1, {}, &stats)

	first := collector.frames[0].counter_deltas
	testing.expect_value(t, first.draw_database_rebuilds, u64(0))
	testing.expect_value(t, first.cluster_dispatches, u64(1))
	testing.expect_value(t, first.instance_uploads, u64(2))
	testing.expect_value(t, first.instance_upload_bytes, u64(96))
	testing.expect_value(t, first.geometry_arena_uploads, u64(3))
	testing.expect_value(t, first.geometry_arena_upload_bytes, u64(768))
	testing.expect_value(t, first.geometry_arena_growths, u64(1))
	testing.expect_value(t, first.virtual_geometry_page_uploads, u64(2))
	testing.expect_value(t, first.virtual_geometry_page_upload_bytes, u64(512))
	testing.expect_value(t, first.virtual_geometry_page_reads, u64(3))
	testing.expect_value(t, first.virtual_geometry_page_read_bytes, u64(1024))
	testing.expect_value(t, first.virtual_geometry_page_read_failures, u64(2))
	testing.expect_value(t, first.virtual_geometry_page_evictions, u64(1))
	testing.expect_value(t, first.virtual_geometry_group_uploads, u64(1))
	testing.expect_value(t, first.virtual_geometry_group_activations, u64(1))
	testing.expect_value(t, first.virtual_geometry_prefetch_group_uploads, u64(1))
	testing.expect_value(t, first.virtual_geometry_prefetch_hits, u64(2))
	testing.expect_value(t, first.virtual_geometry_prefetch_evictions, u64(1))
	testing.expect_value(t, first.virtual_geometry_group_evictions, u64(1))
	testing.expect_value(t, first.virtual_geometry_deferred_groups, u64(2))
	testing.expect_value(t, first.ui_vertex_rebuilds, u64(1))
	testing.expect_value(t, first.ui_vertex_upload_bytes, u64(0))

	stats.draw_database_rebuilds = 1
	stats.ui_vertex_upload_bytes += 128
	profile_record_frame(&collector, 2, 0, 0, 100, 100, 1, {}, &stats)

	second := collector.frames[1].counter_deltas
	testing.expect_value(t, second.draw_database_rebuilds, u64(1))
	testing.expect_value(t, second.ui_vertex_upload_bytes, u64(128))
}

@(test)
test_wgpu_post_timing_includes_camera_post_effects :: proc(t: ^testing.T) {
	renderer: WGPU_Renderer
	renderer.gpu_timestamp_valid = true
	renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Instance_Expansion)] = 0.10
	renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Clustered_Lighting)] = 0.20
	renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Temporal_AA)] = 0.125
	renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Ambient_Occlusion)] = 0.25
	renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Screen_Space_Reflections)] = 0.375
	renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Volumetric_Fog)] = 0.625
	renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Bloom)] = 0.50
	renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Automatic_Exposure)] = 0.30
	renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Composite)] = 0.75
	stats: Render_Stats
	wgpu_publish_gpu_timing(&renderer, &stats)
	testing.expect_value(t, stats.gpu_instance_expansion_ms, 0.10)
	testing.expect_value(t, stats.gpu_clustered_lighting_ms, 0.20)
	testing.expect_value(t, stats.gpu_temporal_aa_ms, 0.125)
	testing.expect_value(t, stats.gpu_ambient_occlusion_ms, 0.25)
	testing.expect_value(t, stats.gpu_screen_space_reflections_ms, 0.375)
	testing.expect_value(t, stats.gpu_volumetric_fog_ms, 0.625)
	testing.expect_value(t, stats.gpu_bloom_ms, 0.50)
	testing.expect_value(t, stats.gpu_automatic_exposure_ms, 0.30)
	testing.expect_value(t, stats.gpu_composite_ms, 0.75)
	testing.expect_value(t, stats.gpu_post_ms, 2.925)
}

@(test)
test_wgpu_gpu_shadow_timing_uses_distinct_queries_for_every_cascade :: proc(t: ^testing.T) {
	renderer: WGPU_Renderer
	renderer.gpu_timestamp_supported = true
	renderer.gpu_timestamp_query_set = wgpu.QuerySet(rawptr(uintptr(1)))
	renderer.gpu_timestamp_active_slot = 1
	first, first_enabled := wgpu_gpu_shadow_pass_timestamps(&renderer, 0)
	second, second_enabled := wgpu_gpu_shadow_pass_timestamps(&renderer, 1)
	last, last_enabled := wgpu_gpu_shadow_pass_timestamps(&renderer, WGPU_SHADOW_CASCADE_COUNT - 1)
	testing.expect(t, first_enabled)
	testing.expect(t, second_enabled)
	testing.expect(t, last_enabled)
	testing.expect_value(
		t,
		first.beginningOfPassWriteIndex,
		u32(WGPU_GPU_Timestamp_Phase.Shadow) * 2,
	)
	testing.expect_value(
		t,
		second.beginningOfPassWriteIndex,
		u32(WGPU_GPU_SHADOW_EXTRA_QUERY_BASE),
	)
	testing.expect_value(t, last.endOfPassWriteIndex, u32(WGPU_GPU_TIMESTAMP_QUERY_COUNT - 1))
}

@(test)
test_wgpu_indirect_template_uses_shared_geometry_arena_offsets :: proc(t: ^testing.T) {
	geometry := WGPU_Geometry_Cache {
		vertex_range = {offset = u64(size_of(resources.Vertex)) * 17, size = 4096},
		index_range = {offset = u64(size_of(u32)) * 31, size = 2048},
		index_count = 123,
		valid = true,
	}
	template := wgpu_geometry_indirect_template(&geometry, 44, true)
	testing.expect_value(t, template.index_count, u32(123))
	testing.expect_value(t, template.first_index, u32(31))
	testing.expect_value(t, template.base_vertex, i32(17))
	testing.expect_value(t, template.first_instance, u32(44))

	template = wgpu_geometry_indirect_template(&geometry, 44, false)
	testing.expect_value(t, template.first_instance, u32(0))
}

@(test)
test_wgpu_compact_shadows_use_pages_only_for_streamed_geometry :: proc(t: ^testing.T) {
	renderer := WGPU_Renderer {
		gpu_meshlet_submission_active = true,
		geometry_cache = make([dynamic]WGPU_Geometry_Cache, 0, 1),
	}
	defer delete(renderer.geometry_cache)
	batch := WGPU_Draw_Batch {
		meshlet_submission = true,
		compact_submission = true,
	}

	testing.expect_value(
		t,
		wgpu_shadow_batch_submission_mode(&renderer, batch),
		WGPU_Submission_Mode.Classic,
	)
	append(&renderer.geometry_cache, WGPU_Geometry_Cache{valid = true, virtual_geometry = true})
	wgpu_recount_virtual_page_residency(&renderer)
	testing.expect(t, wgpu_compact_shadow_pages_active(&renderer))
	testing.expect_value(
		t,
		wgpu_shadow_batch_submission_mode(&renderer, batch),
		WGPU_Submission_Mode.Compact,
	)

	renderer.geometry_cache[0].vertex_range = {
		offset = 64,
		size = 1024,
	}
	wgpu_recount_virtual_page_residency(&renderer)
	testing.expect(t, !wgpu_compact_shadow_pages_active(&renderer))
	testing.expect_value(
		t,
		wgpu_shadow_batch_submission_mode(&renderer, batch),
		WGPU_Submission_Mode.Classic,
	)
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

@(test)
test_volumetric_fog_settings_read_the_lowest_ordered_live_component :: proc(t: ^testing.T) {
	world: World
	defer delete(world.entities)
	defer delete(world.custom_components)
	append(
		&world.entities,
		shared.World_Entity{alive = true, scene_order = 8},
		shared.World_Entity{alive = true, scene_order = 3},
	)
	first := shared.Custom_Component {
		entity_index = 0,
	}
	append(&first.number_fields, shared.Named_Number{name = "density", value = 0.02})
	append(&first.vec3_fields, shared.Named_Vec3{name = "color", value = {1, 0, 0}})
	defer delete(first.number_fields)
	defer delete(first.vec3_fields)
	selected := shared.Custom_Component {
		entity_index = 1,
	}
	append(&selected.number_fields, shared.Named_Number{name = "density", value = 0.035})
	append(
		&selected.number_fields,
		shared.Named_Number{name = "anisotropy", value = 4},
		shared.Named_Number{name = "max_distance", value = -10},
		shared.Named_Number{name = "point_light_intensity", value = 0.7},
	)
	append(&selected.vec3_fields, shared.Named_Vec3{name = "color", value = {0.2, 0.3, 0.4}})
	defer delete(selected.number_fields)
	defer delete(selected.vec3_fields)
	storage := shared.Custom_Component_Storage {
		name = "scrapbot.volumetric_fog",
	}
	append(&storage.components, first, selected)
	append(&storage.active_component_indices, 0, 1)
	defer delete(storage.components)
	defer delete(storage.active_component_indices)
	append(&world.custom_components, storage)

	settings := wgpu_volumetric_fog_settings(&world)
	testing.expect_value(t, settings.color, shared.Vec3{0.2, 0.3, 0.4})
	testing.expect_value(t, settings.density, f32(0.035))
	testing.expect_value(t, settings.anisotropy, f32(0.9))
	testing.expect_value(t, settings.max_distance, f32(0.1))
	testing.expect_value(t, settings.point_light_intensity, f32(0.7))
}

@(test)
test_volumetric_fog_shader_is_energy_normalized_shadowed_and_temporally_resolved :: proc(
	t: ^testing.T,
) {
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "fn apply_volumetric_fog"))
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "fn volumetric_fog_cs"))
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "fn volumetric_fog_at"))
	testing.expect(
		t,
		strings.contains(WGPU_TEMPORAL_AA_SHADER, "textureStore(\n\t\tvolumetric_fog_output"),
	)
	testing.expect(
		t,
		strings.contains(WGPU_TEMPORAL_AA_SHADER, "abs(center_depth - sample_depth)"),
	)
	testing.expect(
		t,
		strings.contains(WGPU_TEMPORAL_AA_SHADER, "FOG_PHASE_NORMALIZATION: f32 = 0.07957747155"),
	)
	testing.expect(
		t,
		strings.contains(WGPU_TEMPORAL_AA_SHADER, "FOG_PHASE_NORMALIZATION * (1.0 - g2)"),
	)
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "fog_shadow_visibility"))
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "fn fog_shadow_cascade"))
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "textureSampleCompareLevel"))
	testing.expect(
		t,
		strings.contains(WGPU_TEMPORAL_AA_SHADER, "let uv_scale = render.shadow_map_parameters.x"),
	)
	testing.expect(
		t,
		strings.contains(WGPU_TEMPORAL_AA_SHADER, "clamp(atlas_uv + offset, uv_min, uv_max)"),
	)
	testing.expect(
		t,
		!strings.contains(
			WGPU_TEMPORAL_AA_SHADER,
			"let texel = render.shadow_cascade_texel_sizes[cascade_index]",
		),
	)
	testing.expect(
		t,
		strings.contains(
			WGPU_TEMPORAL_AA_SHADER,
			"next_visibility = fog_shadow_cascade(world_position, cascade_index + 1u)",
		),
	)
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "fog_point_light_radiance"))
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "cluster_light_counts"))
	testing.expect(t, !strings.contains(WGPU_TEMPORAL_AA_SHADER, "FOG_MAX_POINT_LIGHTS_PER_STEP"))
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "let spatial_phase = fract"))
	testing.expect(
		t,
		strings.contains(WGPU_TEMPORAL_AA_SHADER, "temporal.reflections.w * 0.754877666"),
	)
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "f32(step) + temporal_phase"))
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "closest_depth_delta"))
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "fn rgb_to_ycocg"))
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "fn ycocg_to_rgb"))
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "deviation * 2.5"))
	testing.expect(
		t,
		strings.contains(WGPU_TEMPORAL_AA_SHADER, "source_bounds[0] + fog_offset_ycocg"),
	)
	testing.expect(
		t,
		strings.contains(WGPU_TEMPORAL_AA_SHADER, "source_bounds[1] + fog_offset_ycocg"),
	)
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "jitter_motion"))
	testing.expect(t, strings.contains(WGPU_TEMPORAL_AA_SHADER, "mix(fogged_color, history"))
	testing.expect(t, !strings.contains(WGPU_TEMPORAL_AA_SHADER, "43758.5453"))
}

@(test)
test_profile_compute_workload_reports_dispatch_upper_bounds :: proc(t: ^testing.T) {
	workload := wgpu_profile_compute_workload(true, 17, 9, 3, 16)
	testing.expect(t, workload.enabled)
	testing.expect_value(t, workload.width, u32(17))
	testing.expect_value(t, workload.height, u32(9))
	testing.expect_value(t, workload.passes, u32(3))
	testing.expect_value(t, workload.workgroups, u64(18))
	testing.expect_value(t, workload.invocations, u64(1_152))
	testing.expect_value(t, workload.samples_per_pixel, u32(16))
	testing.expect_value(
		t,
		wgpu_profile_compute_workload(false, 17, 9, 3, 16),
		Profile_Pass_Workload{},
	)
}

@(test)
test_render_target_layout_scales_world_grid_but_preserves_output_viewport :: proc(t: ^testing.T) {
	camera := shared.camera_defaults()
	camera.resolution_scale = 0.5
	output_viewport := ui.Rect {
		x = 300,
		y = 80,
		width = 1320,
		height = 940,
	}
	layout := wgpu_render_target_layout(1920, 1080, output_viewport, camera)
	testing.expect_value(t, layout.output_width, u32(1920))
	testing.expect_value(t, layout.output_height, u32(1080))
	testing.expect_value(t, layout.render_width, u32(960))
	testing.expect_value(t, layout.render_height, u32(540))
	testing.expect_value(t, layout.output_viewport, output_viewport)
	testing.expect_value(
		t,
		layout.render_viewport,
		ui.Rect{x = 150, y = 40, width = 660, height = 470},
	)
}

@(test)
test_render_target_layout_defaults_to_native_resolution :: proc(t: ^testing.T) {
	camera: shared.Camera_Component
	output_viewport := ui.Rect {
		x = 16.25,
		y = 24.5,
		width = 639.5,
		height = 359.25,
	}
	layout := wgpu_render_target_layout(800, 450, output_viewport, camera)
	testing.expect_value(t, layout.render_width, u32(800))
	testing.expect_value(t, layout.render_height, u32(450))
	testing.expect_value(t, layout.render_viewport, output_viewport)
	testing.expect_value(t, layout.resolution_scale, f32(1))
}

@(test)
test_dynamic_resolution_requires_sustained_unique_gpu_samples :: proc(t: ^testing.T) {
	camera := shared.camera_defaults()
	camera.dynamic_resolution = true
	camera.dynamic_resolution_min_scale = 0.5
	camera.dynamic_resolution_target_ms = 10
	state: Frame_Budget_State
	scale := dynamic_resolution_scale(&state, camera, true, 1, 20)
	testing.expect_value(t, scale, f32(1))
	scale = dynamic_resolution_scale(&state, camera, true, 1, 20)
	testing.expect_value(t, scale, f32(1))
	scale = dynamic_resolution_scale(&state, camera, true, 2, 20)
	testing.expect_value(t, scale, f32(1))
	scale = dynamic_resolution_scale(&state, camera, true, 3, 20)
	testing.expect_value(t, scale, f32(0.95))
	testing.expect_value(t, state.cooldown_samples, DYNAMIC_RESOLUTION_CHANGE_COOLDOWN_SAMPLES)
}

@(test)
test_dynamic_resolution_consumes_scene_span_and_respects_manual_bounds :: proc(t: ^testing.T) {
	camera := shared.camera_defaults()
	camera.resolution_scale = 0.8
	camera.dynamic_resolution = true
	camera.dynamic_resolution_min_scale = 0.7
	camera.dynamic_resolution_target_ms = 10
	state: Frame_Budget_State
	for serial in 1 ..= u64(DYNAMIC_RESOLUTION_OVER_BUDGET_SAMPLES) {
		scale := dynamic_resolution_scale(&state, camera, true, serial, 8)
		testing.expect_value(t, scale, f32(0.8))
	}
	for serial in u64(4) ..= u64(6) {
		_ = dynamic_resolution_scale(&state, camera, true, serial, 24)
	}
	testing.expect_value(t, state.effective_scale, f32(0.75))
	for serial in u64(7) ..= u64(64) {
		_ = dynamic_resolution_scale(&state, camera, true, serial, 24)
	}
	testing.expect_value(t, state.effective_scale, f32(0.7))
}

@(test)
test_dynamic_resolution_falls_back_to_manual_scale_without_timestamps :: proc(t: ^testing.T) {
	camera := shared.camera_defaults()
	camera.resolution_scale = 0.75
	camera.dynamic_resolution = true
	state: Frame_Budget_State
	scale := dynamic_resolution_scale(&state, camera, false, 0, 0)
	testing.expect_value(t, scale, f32(0.75))
	testing.expect(t, !state.enabled)
}

@(test)
test_dynamic_resolution_rejects_delayed_samples_from_previous_scale_generation :: proc(
	t: ^testing.T,
) {
	camera := shared.camera_defaults()
	camera.dynamic_resolution = true
	camera.dynamic_resolution_target_ms = 10
	renderer: WGPU_Renderer
	renderer.gpu_timestamp_supported = true
	_ = dynamic_resolution_scale(&renderer.dynamic_resolution, camera, true, 0, 0)
	initial_generation := renderer.dynamic_resolution.generation
	for serial in 1 ..= u64(DYNAMIC_RESOLUTION_OVER_BUDGET_SAMPLES) {
		_ = dynamic_resolution_scale(&renderer.dynamic_resolution, camera, true, serial, 20)
	}
	testing.expect(t, renderer.dynamic_resolution.generation != initial_generation)
	wgpu_dynamic_resolution_accumulate_sample(&renderer, initial_generation, 1, 20)
	testing.expect_value(t, renderer.gpu_timestamp_resolution_sample_count, 0)
	testing.expect_value(t, renderer.gpu_timestamp_sample_serial, u64(0))
	wgpu_dynamic_resolution_accumulate_sample(
		&renderer,
		renderer.dynamic_resolution.generation,
		2,
		6,
	)
	testing.expect_value(t, renderer.gpu_timestamp_resolution_sample_count, 1)
	testing.expect_value(t, renderer.gpu_timestamp_sample_serial, u64(1))
	testing.expect(t, math.abs(renderer.gpu_timestamp_resolution_samples[0].gpu_ms - 6) < 0.001)
}

@(test)
test_dynamic_resolution_batches_match_individual_sample_hysteresis :: proc(t: ^testing.T) {
	camera := shared.camera_defaults()
	camera.dynamic_resolution = true
	camera.dynamic_resolution_target_ms = 10
	renderer: WGPU_Renderer
	renderer.gpu_timestamp_supported = true
	_ = dynamic_resolution_scale(&renderer.dynamic_resolution, camera, true, 0, 0)
	generation := renderer.dynamic_resolution.generation
	for frame_index in 0 ..< DYNAMIC_RESOLUTION_OVER_BUDGET_SAMPLES {
		wgpu_dynamic_resolution_accumulate_sample(&renderer, generation, u64(frame_index), 20)
	}
	scale := wgpu_dynamic_resolution_scale(&renderer, camera, {})
	testing.expect_value(t, scale, f32(0.95))
}

@(test)
test_dynamic_resolution_processes_completed_samples_in_frame_order :: proc(t: ^testing.T) {
	camera := shared.camera_defaults()
	camera.dynamic_resolution = true
	camera.dynamic_resolution_target_ms = 10
	renderer: WGPU_Renderer
	renderer.gpu_timestamp_supported = true
	_ = dynamic_resolution_scale(&renderer.dynamic_resolution, camera, true, 0, 0)
	generation := renderer.dynamic_resolution.generation
	wgpu_dynamic_resolution_accumulate_sample(&renderer, generation, 4, 20)
	wgpu_dynamic_resolution_accumulate_sample(&renderer, generation, 1, 5)
	wgpu_dynamic_resolution_accumulate_sample(&renderer, generation, 2, 5)
	wgpu_dynamic_resolution_accumulate_sample(&renderer, generation, 3, 5)
	_ = wgpu_dynamic_resolution_scale(&renderer, camera, {})

	expected: Frame_Budget_State
	expected_samples := [4]f64{5, 5, 5, 20}
	for sample, serial in expected_samples {
		_ = dynamic_resolution_scale(&expected, camera, true, u64(serial + 1), sample)
	}
	testing.expect(
		t,
		math.abs(renderer.dynamic_resolution.filtered_gpu_ms - expected.filtered_gpu_ms) < 0.001,
	)
	testing.expect_value(
		t,
		renderer.dynamic_resolution.over_budget_samples,
		expected.over_budget_samples,
	)
	testing.expect_value(
		t,
		renderer.dynamic_resolution.under_budget_samples,
		expected.under_budget_samples,
	)
	testing.expect_value(t, renderer.dynamic_resolution.effective_scale, expected.effective_scale)
}

@(test)
test_dynamic_resolution_resets_when_policy_owner_camera_changes :: proc(t: ^testing.T) {
	camera := shared.camera_defaults()
	camera.dynamic_resolution = true
	camera.dynamic_resolution_target_ms = 10
	first_owner, first_owner_ok := shared.entity_uuid_parse("10000000-0000-4000-8000-000000000001")
	second_owner, second_owner_ok := shared.entity_uuid_parse(
		"10000000-0000-4000-8000-000000000002",
	)
	testing.expect(t, first_owner_ok)
	testing.expect(t, second_owner_ok)
	state: Frame_Budget_State
	for serial in 1 ..= u64(DYNAMIC_RESOLUTION_OVER_BUDGET_SAMPLES) {
		_ = dynamic_resolution_scale(&state, camera, true, serial, 20, first_owner)
	}
	testing.expect_value(t, state.effective_scale, f32(0.95))
	scale := dynamic_resolution_scale(
		&state,
		camera,
		true,
		state.last_sample_serial,
		0,
		second_owner,
	)
	testing.expect_value(t, scale, f32(1))
	testing.expect_value(t, state.policy_owner, second_owner)
	testing.expect(t, !state.has_filtered_sample)
}

@(test)
test_frame_budget_degrades_one_ordered_quality_axis_at_a_time :: proc(t: ^testing.T) {
	state := Frame_Budget_State {
		maximum_scale = 1,
		minimum_scale = 0.6,
		minimum_quality = 0.25,
		effective_scale = 1,
		effective_shadow_resolution = FRAME_BUDGET_SHADOW_MAXIMUM,
		effective_post_quality = 1,
	}
	for _ in 0 ..< 4 {
		testing.expect(t, frame_budget_change(&state, true))
	}
	testing.expect_value(t, state.effective_scale, f32(0.8))
	testing.expect(t, frame_budget_change(&state, true))
	testing.expect_value(t, state.effective_shadow_resolution, u32(1024))
	for _ in 0 ..< 4 {
		testing.expect(t, frame_budget_change(&state, true))
	}
	testing.expect_value(t, state.effective_scale, f32(0.6))
	testing.expect(t, frame_budget_change(&state, true))
	testing.expect_value(t, state.effective_post_quality, f32(0.75))
	testing.expect(t, frame_budget_change(&state, true))
	testing.expect_value(t, state.effective_shadow_resolution, u32(512))
	testing.expect(t, frame_budget_change(&state, true))
	testing.expect_value(t, state.effective_post_quality, f32(0.5))
}

@(test)
test_frame_budget_respects_authored_quality_floor_and_restores_in_reverse :: proc(t: ^testing.T) {
	state := Frame_Budget_State {
		maximum_scale = 1,
		minimum_scale = 0.6,
		minimum_quality = 0.5,
		effective_scale = 0.6,
		effective_shadow_resolution = 1024,
		effective_post_quality = 0.5,
	}
	testing.expect(t, frame_budget_change(&state, false))
	testing.expect_value(t, state.effective_post_quality, f32(0.75))
	testing.expect(t, frame_budget_change(&state, false))
	testing.expect_value(t, state.effective_post_quality, f32(1))
	for _ in 0 ..< 4 {
		testing.expect(t, frame_budget_change(&state, false))
	}
	testing.expect_value(t, state.effective_scale, f32(0.8))
	testing.expect(t, frame_budget_change(&state, false))
	testing.expect_value(t, state.effective_shadow_resolution, u32(2048))

	state.effective_scale = state.minimum_scale
	state.effective_shadow_resolution = 1024
	state.effective_post_quality = 0.5
	for frame_budget_change(&state, true) {  }
	testing.expect_value(t, state.effective_shadow_resolution, u32(1024))
	testing.expect_value(t, state.effective_post_quality, f32(0.5))
}

@(test)
test_adaptive_post_quality_scales_authored_ceilings_without_disabling_features :: proc(
	t: ^testing.T,
) {
	camera := shared.camera_defaults()
	camera.ambient_occlusion_quality = 1
	camera.screen_space_reflections = true
	camera.screen_space_reflections_quality = 0.75
	resolved := camera_apply_adaptive_post_quality(camera, 0.5)
	testing.expect(t, resolved.ambient_occlusion)
	testing.expect(t, resolved.screen_space_reflections)
	testing.expect_value(t, resolved.ambient_occlusion_quality, f32(0.5))
	testing.expect_value(t, resolved.screen_space_reflections_quality, f32(0.375))
	testing.expect_value(t, camera.ambient_occlusion_quality, f32(1))
}

@(test)
test_adaptive_quality_floor_bounds_shadow_tiers :: proc(t: ^testing.T) {
	testing.expect_value(t, frame_budget_minimum_shadow_resolution(0.25), u32(512))
	testing.expect_value(t, frame_budget_minimum_shadow_resolution(0.5), u32(1024))
	testing.expect_value(t, frame_budget_minimum_shadow_resolution(0.75), u32(2048))
	testing.expect_value(t, frame_budget_minimum_shadow_resolution(1), u32(2048))
}
