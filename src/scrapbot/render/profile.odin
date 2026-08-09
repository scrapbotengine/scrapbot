package render

import ui "../ui"
import "core:math"
import "core:strings"

PROFILE_SCHEMA_VERSION :: 2

Profile_Distribution :: struct {
	samples: int,
	median_ms: f64,
	p95_ms: f64,
	max_ms: f64,
}

Profile_Viewport :: struct {
	x, y, width, height: f32,
}

Profile_Pass_Workload :: struct {
	enabled: bool,
	width, height: u32,
	passes: u32,
	workgroups: u64,
	invocations: u64,
	draws: u64,
	instances: u64,
	samples_per_pixel: u32,
}

Profile_Workload :: struct {
	instance_expansion: Profile_Pass_Workload,
	cull: Profile_Pass_Workload,
	clustered_lighting: Profile_Pass_Workload,
	spectral_surface: Profile_Pass_Workload,
	shadow: Profile_Pass_Workload,
	shadow_cascade_0: Profile_Pass_Workload,
	shadow_cascade_1: Profile_Pass_Workload,
	shadow_cascade_2: Profile_Pass_Workload,
	shadow_cascade_3: Profile_Pass_Workload,
	depth: Profile_Pass_Workload,
	world: Profile_Pass_Workload,
	hiz: Profile_Pass_Workload,
	ambient_occlusion: Profile_Pass_Workload,
	screen_space_reflections: Profile_Pass_Workload,
	volumetric_fog: Profile_Pass_Workload,
	temporal_aa: Profile_Pass_Workload,
	bloom: Profile_Pass_Workload,
	automatic_exposure: Profile_Pass_Workload,
	composite: Profile_Pass_Workload,
	ui: Profile_Pass_Workload,
}

Profile_Counter_Deltas :: struct {
	draw_database_rebuilds: u64,
	geometry_arena_uploads: u64,
	geometry_arena_upload_bytes: u64,
	geometry_arena_growths: u64,
	virtual_geometry_page_uploads: u64,
	virtual_geometry_page_upload_bytes: u64,
	virtual_geometry_page_reads: u64,
	virtual_geometry_page_read_bytes: u64,
	virtual_geometry_page_read_failures: u64,
	virtual_geometry_page_evictions: u64,
	virtual_geometry_group_uploads: u64,
	virtual_geometry_metadata_uploads: u64,
	virtual_geometry_metadata_upload_bytes: u64,
	virtual_geometry_group_activations: u64,
	virtual_geometry_prefetch_group_uploads: u64,
	virtual_geometry_prefetch_hits: u64,
	virtual_geometry_prefetch_evictions: u64,
	virtual_geometry_group_evictions: u64,
	virtual_geometry_deferred_groups: u64,
	cluster_dispatches: u64,
	spectral_surface_dispatches: u64,
	instance_uploads: u64,
	instance_upload_bytes: u64,
	instance_transform_uploads: u64,
	instance_transform_upload_bytes: u64,
	instance_expand_dispatches: u64,
	instance_expanded_slots: u64,
	world_distance_field_rebuilds: u64,
	world_distance_field_scrolls: u64,
	world_distance_field_scroll_voxels: u64,
	world_distance_field_dispatches: u64,
	world_distance_field_upload_bytes: u64,
	ui_vertex_rebuilds: u64,
	ui_project_vertex_rebuilds: u64,
	ui_editor_vertex_rebuilds: u64,
	ui_overlay_vertex_rebuilds: u64,
	ui_vertex_uploads: u64,
	ui_vertex_upload_bytes: u64,
	ui_viewport_target_resizes: u64,
	ui_viewport_redraws: u64,
	ui_viewport_cache_hits: u64,
}

Profile_Frame :: struct {
	index: u32,
	cpu_active_ms: f64,
	simulation_delta_ms: f64,
	logical_width, logical_height: u32,
	physical_width, physical_height: u32,
	pixel_density: f32,
	shaded_pixels: u64,
	viewport: Profile_Viewport,
	gpu_timing_valid: bool,
	render: Render_Stats,
	counter_deltas: Profile_Counter_Deltas,
	workload: Profile_Workload,
}

Profile_Summary :: struct {
	cpu_active: Profile_Distribution,
	gpu_frame: Profile_Distribution,
	gpu_scene: Profile_Distribution,
	gpu_instance_expansion: Profile_Distribution,
	gpu_clustered_lighting: Profile_Distribution,
	gpu_cull: Profile_Distribution,
	gpu_shadow: Profile_Distribution,
	gpu_shadow_cascade_0: Profile_Distribution,
	gpu_shadow_cascade_1: Profile_Distribution,
	gpu_shadow_cascade_2: Profile_Distribution,
	gpu_shadow_cascade_3: Profile_Distribution,
	gpu_depth: Profile_Distribution,
	gpu_world: Profile_Distribution,
	gpu_hiz: Profile_Distribution,
	gpu_temporal_aa: Profile_Distribution,
	gpu_ambient_occlusion: Profile_Distribution,
	gpu_screen_space_reflections: Profile_Distribution,
	gpu_volumetric_fog: Profile_Distribution,
	gpu_bloom: Profile_Distribution,
	gpu_automatic_exposure: Profile_Distribution,
	gpu_composite: Profile_Distribution,
	gpu_ui: Profile_Distribution,
}

Profile_Metadata :: struct {
	engine_version: string,
	host: string,
	backend: string,
	adapter_vendor: string,
	adapter_device: string,
	adapter_description: string,
	adapter_architecture: string,
	adapter_backend: string,
	adapter_type: string,
	disabled_render_features: string,
	timestamp_queries: bool,
}

Profile_Report :: struct {
	schema_version: int,
	warmup_frames: u32,
	requested_frames: u32,
	recorded_frames: int,
	gpu_timed_frames: int,
	metadata: Profile_Metadata,
	summary: Profile_Summary,
	frames: []Profile_Frame,
}

Profile_Collector :: struct {
	report: Profile_Report,
	frames: [dynamic]Profile_Frame,
	warmup_frames: u32,
	requested_frames: u32,
	recorded_frames: int,
	previous_stats: Render_Stats,
	previous_stats_valid: bool,
}

init_profile_collector :: proc(
	collector: ^Profile_Collector,
	warmup_frames, requested_frames: u32,
	engine_version, host, backend: string,
) {
	if collector == nil {
		return
	}
	collector^ = {
		warmup_frames = warmup_frames,
		requested_frames = requested_frames,
		report = {
			schema_version = PROFILE_SCHEMA_VERSION,
			warmup_frames = warmup_frames,
			requested_frames = requested_frames,
			metadata = {
				engine_version = strings.clone(engine_version),
				host = strings.clone(host),
				backend = strings.clone(backend),
			},
		},
	}
	collector.frames = make([dynamic]Profile_Frame, int(requested_frames))
	for index in 0 ..< len(collector.frames) {
		collector.frames[index].index = u32(index)
	}
}

destroy_profile_collector :: proc(collector: ^Profile_Collector) {
	if collector == nil {
		return
	}
	delete(collector.frames)
	metadata := &collector.report.metadata
	delete(metadata.engine_version)
	delete(metadata.host)
	delete(metadata.backend)
	delete(metadata.adapter_vendor)
	delete(metadata.adapter_device)
	delete(metadata.adapter_description)
	delete(metadata.adapter_architecture)
	delete(metadata.adapter_backend)
	delete(metadata.adapter_type)
	delete(metadata.disabled_render_features)
	collector^ = {}
}

profile_set_disabled_render_features :: proc(collector: ^Profile_Collector, features: string) {
	if collector == nil {
		return
	}
	delete(collector.report.metadata.disabled_render_features)
	collector.report.metadata.disabled_render_features = strings.clone(features)
}

profile_set_adapter :: proc(
	collector: ^Profile_Collector,
	vendor, device, description, architecture, backend, adapter_type: string,
	timestamp_queries: bool,
) {
	if collector == nil {
		return
	}
	metadata := &collector.report.metadata
	delete(metadata.adapter_vendor)
	delete(metadata.adapter_device)
	delete(metadata.adapter_description)
	delete(metadata.adapter_architecture)
	delete(metadata.adapter_backend)
	delete(metadata.adapter_type)
	metadata.adapter_vendor = strings.clone(vendor)
	metadata.adapter_device = strings.clone(device)
	metadata.adapter_description = strings.clone(description)
	metadata.adapter_architecture = strings.clone(architecture)
	metadata.adapter_backend = strings.clone(backend)
	metadata.adapter_type = strings.clone(adapter_type)
	metadata.timestamp_queries = timestamp_queries
}

profile_frame_slot :: proc(collector: ^Profile_Collector, renderer_frame_index: u64) -> int {
	if collector == nil ||
	   renderer_frame_index < u64(collector.warmup_frames) ||
	   renderer_frame_index >= u64(collector.warmup_frames + collector.requested_frames) {
		return -1
	}
	return int(renderer_frame_index - u64(collector.warmup_frames))
}

profile_record_frame :: proc(
	collector: ^Profile_Collector,
	renderer_frame_index: u64,
	cpu_active_seconds, simulation_delta_seconds: f32,
	physical_width, physical_height: u32,
	pixel_density: f32,
	viewport: ui.Rect,
	stats: ^Render_Stats,
	workload: Profile_Workload = {},
) {
	if collector == nil {
		return
	}
	counter_deltas: Profile_Counter_Deltas
	if stats != nil {
		if collector.previous_stats_valid {
			counter_deltas = profile_counter_deltas(stats^, collector.previous_stats)
		} else {
			counter_deltas = profile_counter_deltas(stats^, {})
		}
		collector.previous_stats = stats^
		collector.previous_stats_valid = true
	}
	slot := profile_frame_slot(collector, renderer_frame_index)
	if slot < 0 {
		return
	}
	density := max(pixel_density, 1)
	frame := &collector.frames[slot]
	collector.recorded_frames += 1
	frame.cpu_active_ms = f64(max(cpu_active_seconds, 0)) * 1000
	frame.simulation_delta_ms = f64(max(simulation_delta_seconds, 0)) * 1000
	frame.physical_width = physical_width
	frame.physical_height = physical_height
	frame.logical_width = u32(math.round(f32(physical_width) / density))
	frame.logical_height = u32(math.round(f32(physical_height) / density))
	frame.pixel_density = density
	frame.viewport = {
		x = viewport.x,
		y = viewport.y,
		width = viewport.width,
		height = viewport.height,
	}
	frame.shaded_pixels = u64(max(viewport.width, 0) * max(viewport.height, 0))
	frame.counter_deltas = counter_deltas
	frame.workload = workload
	if stats != nil {
		gpu_valid := frame.gpu_timing_valid
		gpu := profile_gpu_stats(frame.render)
		frame.render = stats^
		if gpu_valid {
			profile_apply_gpu_stats(&frame.render, gpu)
			frame.gpu_timing_valid = true
		}
	}
}

profile_counter_delta :: proc(current, previous: u64) -> u64 {
	if current < previous {
		return current
	}
	return current - previous
}

profile_counter_deltas :: proc(current, previous: Render_Stats) -> Profile_Counter_Deltas {
	return {
		draw_database_rebuilds = profile_counter_delta(
			current.draw_database_rebuilds,
			previous.draw_database_rebuilds,
		),
		geometry_arena_uploads = profile_counter_delta(
			current.geometry_arena_uploads,
			previous.geometry_arena_uploads,
		),
		geometry_arena_upload_bytes = profile_counter_delta(
			current.geometry_arena_upload_bytes,
			previous.geometry_arena_upload_bytes,
		),
		geometry_arena_growths = profile_counter_delta(
			current.geometry_arena_growths,
			previous.geometry_arena_growths,
		),
		virtual_geometry_page_uploads = profile_counter_delta(
			current.virtual_geometry_page_uploads,
			previous.virtual_geometry_page_uploads,
		),
		virtual_geometry_page_upload_bytes = profile_counter_delta(
			current.virtual_geometry_page_upload_bytes,
			previous.virtual_geometry_page_upload_bytes,
		),
		virtual_geometry_page_reads = profile_counter_delta(
			current.virtual_geometry_page_reads,
			previous.virtual_geometry_page_reads,
		),
		virtual_geometry_page_read_bytes = profile_counter_delta(
			current.virtual_geometry_page_read_bytes,
			previous.virtual_geometry_page_read_bytes,
		),
		virtual_geometry_page_read_failures = profile_counter_delta(
			current.virtual_geometry_page_read_failures,
			previous.virtual_geometry_page_read_failures,
		),
		virtual_geometry_page_evictions = profile_counter_delta(
			current.virtual_geometry_page_evictions,
			previous.virtual_geometry_page_evictions,
		),
		virtual_geometry_group_uploads = profile_counter_delta(
			current.virtual_geometry_group_uploads,
			previous.virtual_geometry_group_uploads,
		),
		virtual_geometry_metadata_uploads = profile_counter_delta(
			current.virtual_geometry_metadata_uploads,
			previous.virtual_geometry_metadata_uploads,
		),
		virtual_geometry_metadata_upload_bytes = profile_counter_delta(
			current.virtual_geometry_metadata_upload_bytes,
			previous.virtual_geometry_metadata_upload_bytes,
		),
		virtual_geometry_group_activations = profile_counter_delta(
			current.virtual_geometry_group_activations,
			previous.virtual_geometry_group_activations,
		),
		virtual_geometry_prefetch_group_uploads = profile_counter_delta(
			current.virtual_geometry_prefetch_group_uploads,
			previous.virtual_geometry_prefetch_group_uploads,
		),
		virtual_geometry_prefetch_hits = profile_counter_delta(
			current.virtual_geometry_prefetch_hits,
			previous.virtual_geometry_prefetch_hits,
		),
		virtual_geometry_prefetch_evictions = profile_counter_delta(
			current.virtual_geometry_prefetch_evictions,
			previous.virtual_geometry_prefetch_evictions,
		),
		virtual_geometry_group_evictions = profile_counter_delta(
			current.virtual_geometry_group_evictions,
			previous.virtual_geometry_group_evictions,
		),
		virtual_geometry_deferred_groups = profile_counter_delta(
			current.virtual_geometry_deferred_groups,
			previous.virtual_geometry_deferred_groups,
		),
		cluster_dispatches = profile_counter_delta(
			current.cluster_dispatches,
			previous.cluster_dispatches,
		),
		spectral_surface_dispatches = profile_counter_delta(
			current.spectral_surface_dispatches,
			previous.spectral_surface_dispatches,
		),
		instance_uploads = profile_counter_delta(
			current.instance_uploads,
			previous.instance_uploads,
		),
		instance_upload_bytes = profile_counter_delta(
			current.instance_upload_bytes,
			previous.instance_upload_bytes,
		),
		instance_transform_uploads = profile_counter_delta(
			current.instance_transform_uploads,
			previous.instance_transform_uploads,
		),
		instance_transform_upload_bytes = profile_counter_delta(
			current.instance_transform_upload_bytes,
			previous.instance_transform_upload_bytes,
		),
		instance_expand_dispatches = profile_counter_delta(
			current.instance_expand_dispatches,
			previous.instance_expand_dispatches,
		),
		instance_expanded_slots = profile_counter_delta(
			current.instance_expanded_slots,
			previous.instance_expanded_slots,
		),
		world_distance_field_rebuilds = profile_counter_delta(
			current.world_distance_field_rebuilds,
			previous.world_distance_field_rebuilds,
		),
		world_distance_field_scrolls = profile_counter_delta(
			current.world_distance_field_scrolls,
			previous.world_distance_field_scrolls,
		),
		world_distance_field_scroll_voxels = profile_counter_delta(
			current.world_distance_field_scroll_voxels,
			previous.world_distance_field_scroll_voxels,
		),
		world_distance_field_dispatches = profile_counter_delta(
			current.world_distance_field_dispatches,
			previous.world_distance_field_dispatches,
		),
		world_distance_field_upload_bytes = profile_counter_delta(
			current.world_distance_field_upload_bytes,
			previous.world_distance_field_upload_bytes,
		),
		ui_vertex_rebuilds = profile_counter_delta(
			current.ui_vertex_rebuilds,
			previous.ui_vertex_rebuilds,
		),
		ui_project_vertex_rebuilds = profile_counter_delta(
			current.ui_project_vertex_rebuilds,
			previous.ui_project_vertex_rebuilds,
		),
		ui_editor_vertex_rebuilds = profile_counter_delta(
			current.ui_editor_vertex_rebuilds,
			previous.ui_editor_vertex_rebuilds,
		),
		ui_overlay_vertex_rebuilds = profile_counter_delta(
			current.ui_overlay_vertex_rebuilds,
			previous.ui_overlay_vertex_rebuilds,
		),
		ui_vertex_uploads = profile_counter_delta(
			current.ui_vertex_uploads,
			previous.ui_vertex_uploads,
		),
		ui_vertex_upload_bytes = profile_counter_delta(
			current.ui_vertex_upload_bytes,
			previous.ui_vertex_upload_bytes,
		),
		ui_viewport_target_resizes = profile_counter_delta(
			current.ui_viewport_target_resizes,
			previous.ui_viewport_target_resizes,
		),
		ui_viewport_redraws = profile_counter_delta(
			current.ui_viewport_redraws,
			previous.ui_viewport_redraws,
		),
		ui_viewport_cache_hits = profile_counter_delta(
			current.ui_viewport_cache_hits,
			previous.ui_viewport_cache_hits,
		),
	}
}

Profile_GPU_Stats :: struct {
	frame, scene, instance_expansion, clustered_lighting, cull, shadow, depth, world, hiz: f64,
	shadow_cascades: [WGPU_SHADOW_CASCADE_COUNT]f64,
	temporal_aa, ambient_occlusion, screen_space_reflections: f64,
	volumetric_fog, bloom, automatic_exposure, composite, ui: f64,
}

profile_gpu_stats :: proc(stats: Render_Stats) -> Profile_GPU_Stats {
	return {
		frame = stats.gpu_frame_ms,
		scene = stats.gpu_scene_ms,
		instance_expansion = stats.gpu_instance_expansion_ms,
		clustered_lighting = stats.gpu_clustered_lighting_ms,
		cull = stats.gpu_cull_ms,
		shadow = stats.gpu_shadow_ms,
		shadow_cascades = stats.gpu_shadow_cascade_ms,
		depth = stats.gpu_depth_ms,
		world = stats.gpu_world_ms,
		hiz = stats.gpu_hiz_ms,
		temporal_aa = stats.gpu_temporal_aa_ms,
		ambient_occlusion = stats.gpu_ambient_occlusion_ms,
		screen_space_reflections = stats.gpu_screen_space_reflections_ms,
		volumetric_fog = stats.gpu_volumetric_fog_ms,
		bloom = stats.gpu_bloom_ms,
		automatic_exposure = stats.gpu_automatic_exposure_ms,
		composite = stats.gpu_composite_ms,
		ui = stats.gpu_ui_ms,
	}
}

profile_apply_gpu_stats :: proc(stats: ^Render_Stats, gpu: Profile_GPU_Stats) {
	stats.gpu_timestamps_valid = true
	stats.gpu_frame_ms = gpu.frame
	stats.gpu_scene_ms = gpu.scene
	stats.gpu_instance_expansion_ms = gpu.instance_expansion
	stats.gpu_clustered_lighting_ms = gpu.clustered_lighting
	stats.gpu_cull_ms = gpu.cull
	stats.gpu_shadow_ms = gpu.shadow
	stats.gpu_shadow_cascade_ms = gpu.shadow_cascades
	stats.gpu_depth_ms = gpu.depth
	stats.gpu_world_ms = gpu.world
	stats.gpu_hiz_ms = gpu.hiz
	stats.gpu_temporal_aa_ms = gpu.temporal_aa
	stats.gpu_ambient_occlusion_ms = gpu.ambient_occlusion
	stats.gpu_screen_space_reflections_ms = gpu.screen_space_reflections
	stats.gpu_volumetric_fog_ms = gpu.volumetric_fog
	stats.gpu_bloom_ms = gpu.bloom
	stats.gpu_automatic_exposure_ms = gpu.automatic_exposure
	stats.gpu_composite_ms = gpu.composite
	stats.gpu_ui_ms = gpu.ui
	stats.gpu_post_ms =
		gpu.temporal_aa +
		gpu.ambient_occlusion +
		gpu.screen_space_reflections +
		gpu.volumetric_fog +
		gpu.bloom +
		gpu.automatic_exposure +
		gpu.composite
}

profile_record_gpu_frame :: proc(
	collector: ^Profile_Collector,
	renderer_frame_index: u64,
	gpu: Profile_GPU_Stats,
) {
	slot := profile_frame_slot(collector, renderer_frame_index)
	if slot < 0 || slot >= len(collector.frames) {
		return
	}
	frame := &collector.frames[slot]
	frame.gpu_timing_valid = true
	profile_apply_gpu_stats(&frame.render, gpu)
}

profile_distribution :: proc(values: []f64) -> Profile_Distribution {
	if len(values) == 0 {
		return {}
	}
	sorted := make([]f64, len(values))
	defer delete(sorted)
	copy(sorted, values)
	for index in 1 ..< len(sorted) {
		value := sorted[index]
		cursor := index
		for cursor > 0 && sorted[cursor - 1] > value {
			sorted[cursor] = sorted[cursor - 1]
			cursor -= 1
		}
		sorted[cursor] = value
	}
	median := sorted[len(sorted) / 2]
	if len(sorted) % 2 == 0 {
		median = (sorted[len(sorted) / 2 - 1] + median) * 0.5
	}
	p95_index := int(math.ceil(f64(len(sorted)) * 0.95)) - 1
	p95_index = clamp(p95_index, 0, len(sorted) - 1)
	return {
		samples = len(sorted),
		median_ms = median,
		p95_ms = sorted[p95_index],
		max_ms = sorted[len(sorted) - 1],
	}
}

finish_profile_collector :: proc(collector: ^Profile_Collector) {
	if collector == nil {
		return
	}
	cpu := make([dynamic]f64, 0, len(collector.frames))
	gpu_frame := make([dynamic]f64, 0, len(collector.frames))
	gpu_scene := make([dynamic]f64, 0, len(collector.frames))
	gpu_instance_expansion := make([dynamic]f64, 0, len(collector.frames))
	gpu_clustered_lighting := make([dynamic]f64, 0, len(collector.frames))
	gpu_cull := make([dynamic]f64, 0, len(collector.frames))
	gpu_shadow := make([dynamic]f64, 0, len(collector.frames))
	gpu_shadow_cascade_0 := make([dynamic]f64, 0, len(collector.frames))
	gpu_shadow_cascade_1 := make([dynamic]f64, 0, len(collector.frames))
	gpu_shadow_cascade_2 := make([dynamic]f64, 0, len(collector.frames))
	gpu_shadow_cascade_3 := make([dynamic]f64, 0, len(collector.frames))
	gpu_depth := make([dynamic]f64, 0, len(collector.frames))
	gpu_world := make([dynamic]f64, 0, len(collector.frames))
	gpu_hiz := make([dynamic]f64, 0, len(collector.frames))
	gpu_taa := make([dynamic]f64, 0, len(collector.frames))
	gpu_ao := make([dynamic]f64, 0, len(collector.frames))
	gpu_ssr := make([dynamic]f64, 0, len(collector.frames))
	gpu_fog := make([dynamic]f64, 0, len(collector.frames))
	gpu_bloom := make([dynamic]f64, 0, len(collector.frames))
	gpu_automatic_exposure := make([dynamic]f64, 0, len(collector.frames))
	gpu_composite := make([dynamic]f64, 0, len(collector.frames))
	gpu_ui := make([dynamic]f64, 0, len(collector.frames))
	defer {
		delete(cpu)
		delete(gpu_frame)
		delete(gpu_scene)
		delete(gpu_instance_expansion)
		delete(gpu_clustered_lighting)
		delete(gpu_cull)
		delete(gpu_shadow)
		delete(gpu_shadow_cascade_0)
		delete(gpu_shadow_cascade_1)
		delete(gpu_shadow_cascade_2)
		delete(gpu_shadow_cascade_3)
		delete(gpu_depth)
		delete(gpu_world)
		delete(gpu_hiz)
		delete(gpu_taa)
		delete(gpu_ao)
		delete(gpu_ssr)
		delete(gpu_fog)
		delete(gpu_bloom)
		delete(gpu_automatic_exposure)
		delete(gpu_composite)
		delete(gpu_ui)
	}
	for frame in collector.frames[:collector.recorded_frames] {
		append(&cpu, frame.cpu_active_ms)
		if !frame.gpu_timing_valid {
			continue
		}
		stats := frame.render
		append(&gpu_frame, stats.gpu_frame_ms)
		append(&gpu_scene, stats.gpu_scene_ms)
		append(&gpu_instance_expansion, stats.gpu_instance_expansion_ms)
		append(&gpu_clustered_lighting, stats.gpu_clustered_lighting_ms)
		append(&gpu_cull, stats.gpu_cull_ms)
		append(&gpu_shadow, stats.gpu_shadow_ms)
		append(&gpu_shadow_cascade_0, stats.gpu_shadow_cascade_ms[0])
		append(&gpu_shadow_cascade_1, stats.gpu_shadow_cascade_ms[1])
		append(&gpu_shadow_cascade_2, stats.gpu_shadow_cascade_ms[2])
		append(&gpu_shadow_cascade_3, stats.gpu_shadow_cascade_ms[3])
		append(&gpu_depth, stats.gpu_depth_ms)
		append(&gpu_world, stats.gpu_world_ms)
		append(&gpu_hiz, stats.gpu_hiz_ms)
		append(&gpu_taa, stats.gpu_temporal_aa_ms)
		append(&gpu_ao, stats.gpu_ambient_occlusion_ms)
		append(&gpu_ssr, stats.gpu_screen_space_reflections_ms)
		append(&gpu_fog, stats.gpu_volumetric_fog_ms)
		append(&gpu_bloom, stats.gpu_bloom_ms)
		append(&gpu_automatic_exposure, stats.gpu_automatic_exposure_ms)
		append(&gpu_composite, stats.gpu_composite_ms)
		append(&gpu_ui, stats.gpu_ui_ms)
	}
	collector.report.frames = collector.frames[:collector.recorded_frames]
	collector.report.recorded_frames = collector.recorded_frames
	collector.report.gpu_timed_frames = len(gpu_frame)
	collector.report.summary = {
		cpu_active = profile_distribution(cpu[:]),
		gpu_frame = profile_distribution(gpu_frame[:]),
		gpu_scene = profile_distribution(gpu_scene[:]),
		gpu_instance_expansion = profile_distribution(gpu_instance_expansion[:]),
		gpu_clustered_lighting = profile_distribution(gpu_clustered_lighting[:]),
		gpu_cull = profile_distribution(gpu_cull[:]),
		gpu_shadow = profile_distribution(gpu_shadow[:]),
		gpu_shadow_cascade_0 = profile_distribution(gpu_shadow_cascade_0[:]),
		gpu_shadow_cascade_1 = profile_distribution(gpu_shadow_cascade_1[:]),
		gpu_shadow_cascade_2 = profile_distribution(gpu_shadow_cascade_2[:]),
		gpu_shadow_cascade_3 = profile_distribution(gpu_shadow_cascade_3[:]),
		gpu_depth = profile_distribution(gpu_depth[:]),
		gpu_world = profile_distribution(gpu_world[:]),
		gpu_hiz = profile_distribution(gpu_hiz[:]),
		gpu_temporal_aa = profile_distribution(gpu_taa[:]),
		gpu_ambient_occlusion = profile_distribution(gpu_ao[:]),
		gpu_screen_space_reflections = profile_distribution(gpu_ssr[:]),
		gpu_volumetric_fog = profile_distribution(gpu_fog[:]),
		gpu_bloom = profile_distribution(gpu_bloom[:]),
		gpu_automatic_exposure = profile_distribution(gpu_automatic_exposure[:]),
		gpu_composite = profile_distribution(gpu_composite[:]),
		gpu_ui = profile_distribution(gpu_ui[:]),
	}
}
