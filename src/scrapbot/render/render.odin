package render

import ecs "../ecs"
import platform "../platform"
import resources "../resources"
import shared "../shared"
import ui "../ui"
import "core:fmt"
import "core:math"
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
	Environment,
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
Runtime_Reimport_Proc :: #type proc(
	data: rawptr,
	world: ^World,
	id: shared.Resource_UUID,
	all: bool,
) -> string
Render_Stats :: struct {
	draw_batches: int,
	draw_submissions: int,
	visible_batches: u32,
	draw_capacity: int,
	draw_database_rebuilds: u64,
	gpu_driven: bool,
	compute_culling: bool,
	meshlet_culling: bool,
	meshlet_supported: bool,
	meshlet_native_multi_draw: bool,
	meshlet_draws: int,
	visible_meshlet_draws: u32,
	virtual_geometry: bool,
	virtual_geometry_compacted: bool,
	virtual_cluster_draws: int,
	visible_virtual_clusters: u32,
	virtual_rejected_clusters: u32,
	virtual_geometry_page_budget_bytes: u64,
	virtual_geometry_page_resident_bytes: u64,
	virtual_geometry_error_pixels: f32,
	virtual_geometry_pages: int,
	virtual_geometry_resident_pages: int,
	virtual_geometry_pinned_pages: int,
	virtual_geometry_prefetched_pages: int,
	virtual_geometry_page_requests: u32,
	virtual_geometry_page_prefetches: u32,
	virtual_geometry_page_request_overflow: u32,
	virtual_geometry_page_uploads: u64,
	virtual_geometry_page_upload_bytes: u64,
	virtual_geometry_page_reads: u64,
	virtual_geometry_page_read_bytes: u64,
	virtual_geometry_page_read_failures: u64,
	virtual_geometry_page_evictions: u64,
	virtual_geometry_page_feedback: u32,
	virtual_geometry_group_uploads: u64,
	virtual_geometry_group_activations: u64,
	virtual_geometry_prefetch_group_uploads: u64,
	virtual_geometry_prefetch_hits: u64,
	virtual_geometry_prefetch_evictions: u64,
	virtual_geometry_group_evictions: u64,
	virtual_geometry_deferred_groups: u64,
	meshlet_visible_capacity: int,
	clustered_lighting: bool,
	shadow_cascades: int,
	shadow_resolution: u32,
	cluster_count: int,
	cluster_max_lights: int,
	clustered_point_lights: int,
	cluster_dispatches: u64,
	gpu_timestamps_supported: bool,
	gpu_timestamps_valid: bool,
	gpu_frame_ms: f64,
	gpu_scene_ms: f64,
	render_scale: f32,
	dynamic_resolution: bool,
	dynamic_resolution_filtered_gpu_ms: f64,
	adaptive_post_quality: f32,
	gpu_instance_expansion_ms: f64,
	gpu_clustered_lighting_ms: f64,
	gpu_cull_ms: f64,
	gpu_shadow_ms: f64,
	gpu_world_ms: f64,
	gpu_post_ms: f64,
	gpu_temporal_aa_ms: f64,
	gpu_ambient_occlusion_ms: f64,
	gpu_screen_space_reflections_ms: f64,
	gpu_volumetric_fog_ms: f64,
	gpu_bloom_ms: f64,
	gpu_composite_ms: f64,
	gpu_automatic_exposure_ms: f64,
	gpu_ui_ms: f64,
	gpu_depth_ms: f64,
	gpu_hiz_ms: f64,
	hiz_occlusion: bool,
	hiz_occlusion_status: shared.HiZ_Occlusion_Status,
	hiz_instance_threshold: int,
	hiz_valid: bool,
	hiz_mip_count: int,
	visible_instances: u32,
	shadow_visible_instances: u32,
	frustum_candidates: u32,
	frustum_culled_instances: u32,
	occlusion_culled_instances: u32,
	visible_meshlets: u32,
	shadow_visible_meshlets: u32,
	frustum_culled_meshlets: u32,
	cone_culled_meshlets: u32,
	occlusion_culled_meshlets: u32,
	meshlet_debug_records: u32,
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
	instance_transform_uploads: u64,
	instance_transform_upload_bytes: u64,
	instance_expand_dispatches: u64,
	instance_expanded_slots: u64,
	geometry_vertex_arena_capacity_bytes: u64,
	geometry_vertex_arena_resident_bytes: u64,
	geometry_index_arena_capacity_bytes: u64,
	geometry_index_arena_resident_bytes: u64,
	geometry_arena_uploads: u64,
	geometry_arena_upload_bytes: u64,
	geometry_arena_growths: u64,
	ui_vertex_rebuilds: u64,
	ui_project_vertex_rebuilds: u64,
	ui_editor_vertex_rebuilds: u64,
	ui_overlay_vertex_rebuilds: u64,
	ui_vertex_uploads: u64,
	ui_vertex_upload_bytes: u64,
	ui_viewport_active_targets: int,
	ui_viewport_target_pixels: u64,
	ui_viewport_target_resizes: u64,
	ui_viewport_redraws: u64,
	ui_viewport_cache_hits: u64,
}

Frame_Budget_State :: struct {
	initialized: bool,
	enabled: bool,
	generation: u64,
	policy_owner: shared.Entity_UUID,
	maximum_scale: f32,
	minimum_scale: f32,
	target_ms: f32,
	minimum_quality: f32,
	effective_scale: f32,
	effective_shadow_resolution: u32,
	effective_post_quality: f32,
	filtered_gpu_ms: f64,
	has_filtered_sample: bool,
	last_sample_serial: u64,
	over_budget_samples: int,
	under_budget_samples: int,
	cooldown_samples: int,
}

DYNAMIC_RESOLUTION_SCALE_STEP :: f32(0.05)
DYNAMIC_RESOLUTION_OVER_BUDGET_RATIO :: f64(1.08)
DYNAMIC_RESOLUTION_UNDER_BUDGET_RATIO :: f64(0.72)
DYNAMIC_RESOLUTION_OVER_BUDGET_SAMPLES :: 3
DYNAMIC_RESOLUTION_UNDER_BUDGET_SAMPLES :: 30
DYNAMIC_RESOLUTION_CHANGE_COOLDOWN_SAMPLES :: 8
DYNAMIC_RESOLUTION_FILTER_ALPHA :: f64(0.2)

FRAME_BUDGET_SHADOW_MAXIMUM :: u32(2048)
FRAME_BUDGET_SHADOW_MIDDLE :: u32(1024)
FRAME_BUDGET_SHADOW_MINIMUM :: u32(512)
FRAME_BUDGET_FIRST_SCALE_RATIO :: f32(0.8)
FRAME_BUDGET_QUALITY_STEP :: f32(0.25)

dynamic_resolution_quantize :: proc "contextless" (scale, minimum, maximum: f32) -> f32 {
	steps := math.round(scale / DYNAMIC_RESOLUTION_SCALE_STEP)
	return clamp(steps * DYNAMIC_RESOLUTION_SCALE_STEP, minimum, maximum)
}

frame_budget_minimum_shadow_resolution :: proc "contextless" (minimum_quality: f32) -> u32 {
	if minimum_quality >= 0.75 {
		return FRAME_BUDGET_SHADOW_MAXIMUM
	}
	if minimum_quality >= 0.5 {
		return FRAME_BUDGET_SHADOW_MIDDLE
	}
	return FRAME_BUDGET_SHADOW_MINIMUM
}

camera_apply_adaptive_post_quality :: proc "contextless" (
	camera: shared.Camera_Component,
	quality: f32,
) -> shared.Camera_Component {
	resolved := camera
	factor := clamp(quality, 0.25, 1)
	resolved.ambient_occlusion_quality = max(
		f32(0.25),
		shared.camera_ambient_occlusion_quality(camera) * factor,
	)
	resolved.screen_space_reflections_quality = max(
		f32(0.25),
		shared.camera_screen_space_reflections_quality(camera) * factor,
	)
	return resolved
}

frame_budget_change :: proc "contextless" (state: ^Frame_Budget_State, degrade: bool) -> bool {
	if state == nil {
		return false
	}
	first_scale := dynamic_resolution_quantize(
		max(state.minimum_scale, state.maximum_scale * FRAME_BUDGET_FIRST_SCALE_RATIO),
		state.minimum_scale,
		state.maximum_scale,
	)
	minimum_shadow := frame_budget_minimum_shadow_resolution(state.minimum_quality)
	if degrade {
		if state.effective_scale > first_scale {
			state.effective_scale = dynamic_resolution_quantize(
				state.effective_scale - DYNAMIC_RESOLUTION_SCALE_STEP,
				state.minimum_scale,
				state.maximum_scale,
			)
			return true
		}
		if state.effective_shadow_resolution > max(minimum_shadow, FRAME_BUDGET_SHADOW_MIDDLE) {
			state.effective_shadow_resolution = max(
				state.effective_shadow_resolution / 2,
				max(minimum_shadow, FRAME_BUDGET_SHADOW_MIDDLE),
			)
			return true
		}
		if state.effective_scale > state.minimum_scale {
			state.effective_scale = dynamic_resolution_quantize(
				state.effective_scale - DYNAMIC_RESOLUTION_SCALE_STEP,
				state.minimum_scale,
				state.maximum_scale,
			)
			return true
		}
		if state.effective_post_quality > max(state.minimum_quality, f32(0.75)) {
			state.effective_post_quality = max(
				state.effective_post_quality - FRAME_BUDGET_QUALITY_STEP,
				max(state.minimum_quality, f32(0.75)),
			)
			return true
		}
		if state.effective_shadow_resolution > minimum_shadow {
			state.effective_shadow_resolution = max(
				state.effective_shadow_resolution / 2,
				minimum_shadow,
			)
			return true
		}
		if state.effective_post_quality > state.minimum_quality {
			state.effective_post_quality = max(
				state.effective_post_quality - FRAME_BUDGET_QUALITY_STEP,
				state.minimum_quality,
			)
			return true
		}
		return false
	}
	if state.effective_post_quality < 0.75 {
		state.effective_post_quality = min(
			state.effective_post_quality + FRAME_BUDGET_QUALITY_STEP,
			f32(0.75),
		)
		return true
	}
	if state.effective_shadow_resolution < FRAME_BUDGET_SHADOW_MIDDLE {
		state.effective_shadow_resolution = min(
			state.effective_shadow_resolution * 2,
			FRAME_BUDGET_SHADOW_MIDDLE,
		)
		return true
	}
	if state.effective_post_quality < 1 {
		state.effective_post_quality = min(
			state.effective_post_quality + FRAME_BUDGET_QUALITY_STEP,
			f32(1),
		)
		return true
	}
	if state.effective_scale < first_scale {
		state.effective_scale = dynamic_resolution_quantize(
			state.effective_scale + DYNAMIC_RESOLUTION_SCALE_STEP,
			state.minimum_scale,
			first_scale,
		)
		return true
	}
	if state.effective_shadow_resolution < FRAME_BUDGET_SHADOW_MAXIMUM {
		state.effective_shadow_resolution = min(
			state.effective_shadow_resolution * 2,
			FRAME_BUDGET_SHADOW_MAXIMUM,
		)
		return true
	}
	if state.effective_scale < state.maximum_scale {
		state.effective_scale = dynamic_resolution_quantize(
			state.effective_scale + DYNAMIC_RESOLUTION_SCALE_STEP,
			state.minimum_scale,
			state.maximum_scale,
		)
		return true
	}
	return false
}

dynamic_resolution_scale :: proc "contextless" (
	state: ^Frame_Budget_State,
	camera: shared.Camera_Component,
	timestamps_supported: bool,
	sample_serial: u64,
	gpu_scene_ms: f64,
	policy_owner: shared.Entity_UUID = {},
) -> f32 {
	maximum := shared.camera_resolution_scale(camera)
	minimum := shared.camera_dynamic_resolution_min_scale(camera)
	target := shared.camera_dynamic_resolution_target_ms(camera)
	minimum_quality := shared.camera_adaptive_quality_minimum(camera)
	enabled := camera.dynamic_resolution && timestamps_supported
	if state == nil {
		return maximum
	}
	policy_changed :=
		!state.initialized ||
		state.enabled != enabled ||
		state.policy_owner != policy_owner ||
		state.maximum_scale != maximum ||
		state.minimum_scale != minimum ||
		state.target_ms != target ||
		state.minimum_quality != minimum_quality
	if policy_changed {
		was_enabled := state.initialized && state.enabled
		owner_changed := state.initialized && state.policy_owner != policy_owner
		if !was_enabled || !enabled || owner_changed {
			state.effective_scale = maximum
			state.effective_shadow_resolution = FRAME_BUDGET_SHADOW_MAXIMUM
			state.effective_post_quality = 1
		} else {
			state.effective_scale = dynamic_resolution_quantize(
				state.effective_scale,
				minimum,
				maximum,
			)
		}
		state.initialized = true
		state.enabled = enabled
		state.generation += 1
		state.policy_owner = policy_owner
		state.maximum_scale = maximum
		state.minimum_scale = minimum
		state.target_ms = target
		state.minimum_quality = minimum_quality
		state.effective_shadow_resolution = clamp(
			state.effective_shadow_resolution,
			frame_budget_minimum_shadow_resolution(minimum_quality),
			FRAME_BUDGET_SHADOW_MAXIMUM,
		)
		state.effective_post_quality = clamp(state.effective_post_quality, minimum_quality, 1)
		state.filtered_gpu_ms = 0
		state.has_filtered_sample = false
		state.over_budget_samples = 0
		state.under_budget_samples = 0
		state.cooldown_samples = 0
	}
	if !enabled || sample_serial == 0 || sample_serial == state.last_sample_serial {
		return state.effective_scale
	}
	state.last_sample_serial = sample_serial
	if !state.has_filtered_sample {
		state.filtered_gpu_ms = max(gpu_scene_ms, 0)
		state.has_filtered_sample = true
	} else {
		state.filtered_gpu_ms +=
			(max(gpu_scene_ms, 0) - state.filtered_gpu_ms) * DYNAMIC_RESOLUTION_FILTER_ALPHA
	}
	if state.cooldown_samples > 0 {
		state.cooldown_samples -= 1
		return state.effective_scale
	}
	over_budget := state.filtered_gpu_ms > f64(target) * DYNAMIC_RESOLUTION_OVER_BUDGET_RATIO
	under_budget := state.filtered_gpu_ms < f64(target) * DYNAMIC_RESOLUTION_UNDER_BUDGET_RATIO
	if over_budget {
		state.over_budget_samples += 1
		state.under_budget_samples = 0
	} else if under_budget {
		state.under_budget_samples += 1
		state.over_budget_samples = 0
	} else {
		state.over_budget_samples = 0
		state.under_budget_samples = 0
	}
	adjustment_due := false
	if state.over_budget_samples >= DYNAMIC_RESOLUTION_OVER_BUDGET_SAMPLES {
		adjustment_due = frame_budget_change(state, true)
	} else if state.under_budget_samples >= DYNAMIC_RESOLUTION_UNDER_BUDGET_SAMPLES {
		adjustment_due = frame_budget_change(state, false)
	}
	if !adjustment_due {
		return state.effective_scale
	}
	state.generation += 1
	state.filtered_gpu_ms = 0
	state.has_filtered_sample = false
	state.cooldown_samples = DYNAMIC_RESOLUTION_CHANGE_COOLDOWN_SAMPLES
	state.over_budget_samples = 0
	state.under_budget_samples = 0
	return state.effective_scale
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
	native_queries: shared.Native_Query_Stats,
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

Render_Feature_Overrides :: struct {
	disable_automatic_exposure: bool,
	disable_temporal_antialiasing: bool,
	disable_fast_antialiasing: bool,
	disable_ambient_occlusion: bool,
	disable_screen_space_reflections: bool,
	disable_bloom: bool,
	disable_volumetric_fog: bool,
}

apply_render_feature_overrides :: proc "contextless" (
	camera: shared.Camera_Component,
	overrides: Render_Feature_Overrides,
) -> shared.Camera_Component {
	resolved := camera
	if overrides.disable_automatic_exposure {
		resolved.automatic_exposure = false
	}
	if overrides.disable_temporal_antialiasing {
		resolved.temporal_antialiasing = false
	}
	if overrides.disable_fast_antialiasing {
		resolved.fast_antialiasing = false
	}
	if overrides.disable_ambient_occlusion {
		resolved.ambient_occlusion = false
	}
	if overrides.disable_screen_space_reflections {
		resolved.screen_space_reflections = false
	}
	if overrides.disable_bloom {
		resolved.bloom = false
	}
	return resolved
}

Run_Config :: struct {
	backend: Renderer_Backend,
	virtual_geometry_budget_bytes: u64,
	virtual_geometry_prefetch: bool,
	cpu_culling: bool,
	render_feature_overrides: Render_Feature_Overrides,
	window: bool,
	window_width, window_height: int,
	override_window_size: bool,
	hot_reload: bool,
	editor: bool,
	max_frames: u32,
	framegrab_path: string,
	framegrab_region: Framegrab_Region,
	framegrab_sequence_directory: string,
	framegrab_sequence_start: u32,
	framegrab_sequence_end: u32,
	framegrab_sequence_index_base: u32,
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
	runtime_reconcile: Runtime_World_Proc,
	runtime_reconcile_data: rawptr,
	runtime_environment: Runtime_World_Proc,
	runtime_environment_data: rawptr,
	runtime_reimport: Runtime_Reimport_Proc,
	runtime_reimport_data: rawptr,
	resource_registry: ^resources.Registry,
	stats: ^Render_Stats,
	profile: ^Profile_Collector,
	performance_diagnostics: ^Performance_Diagnostics_Accumulator,
	collect_runtime_stats: bool,
	runtime_stats: ^Runtime_Stats,
	runtime_stats_collector: ^Runtime_Stats_Collector,
	allocator_current_bytes: ^i64,
	allocator_peak_bytes: ^i64,
	log_enabled: bool,
	ui_state: ^ui.State,
	ui_driver: ^ui.Diagnostic_Driver,
	input_override: ^shared.Input_Frame,
	last_drawable_width: f32,
	last_drawable_height: f32,
}

Renderer_Output_Mode :: enum {
	Surface,
	Offscreen,
}

renderer_output_mode :: proc(config: ^Run_Config) -> Renderer_Output_Mode {
	if config != nil && config.backend == .WGPU && config.window {
		return .Surface
	}
	return .Offscreen
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
	snapshot.gpu_scene_ms = stats.gpu_scene_ms
	snapshot.render_scale = stats.render_scale
	snapshot.shadow_resolution = stats.shadow_resolution
	snapshot.adaptive_post_quality = stats.adaptive_post_quality
	snapshot.gpu_timestamps_valid = stats.gpu_timestamps_valid
	snapshot.entity_count = world.scene_entity_count + world.runtime_entity_count
	snapshot.retained_batches = stats.draw_batches
	snapshot.visible_batches = stats.visible_batches
	snapshot.visible_meshlet_draws = stats.visible_meshlet_draws
	snapshot.instance_count = stats.instance_slots
	snapshot.frustum_candidates = stats.frustum_candidates
	snapshot.frustum_culled_instances = stats.frustum_culled_instances
	snapshot.visible_instances = stats.visible_instances
	snapshot.occlusion_culled_instances = stats.occlusion_culled_instances
	snapshot.occlusion_culled_meshlets = stats.occlusion_culled_meshlets
	snapshot.hiz_occlusion_status = stats.hiz_occlusion_status
	snapshot.hiz_instance_threshold = stats.hiz_instance_threshold
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
			if renderer_output_mode(&run_config) == .Surface {
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
			err = wgpu_run_headless(world, &run_config)
			frame = ecs.render_frame_from_world(world)
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
	input_frame := platform.runtime_input_frame()
	if config.input_override != nil {
		input_frame = config.input_override^
	}
	if !ecs.update_input(world, input_frame) {
		return "runtime input singleton is unavailable"
	}
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
		if id, all, requested := ui.consume_resource_reimport_request(config.ui_state); requested {
			reimport_err := "editor reimport requires a runtime import callback"
			if config.runtime_reimport != nil {
				reimport_err = config.runtime_reimport(
					config.runtime_reimport_data,
					world,
					id,
					all,
				)
			}
			ui.complete_resource_reimport(config.ui_state, reimport_err)
			if reimport_err != "" {
				fmt.eprintf("[editor] failed to reimport resource: %s\n", reimport_err)
			}
		}
		if config.runtime_reconcile != nil {
			if err := config.runtime_reconcile(config.runtime_reconcile_data, world); err != "" {
				return err
			}
		}
		environment_system_start := time.tick_now()
		if config.runtime_environment != nil {
			if err := config.runtime_environment(config.runtime_environment_data, world);
			   err != "" {
				return err
			}
		}
		record_system_profile_phase(config, .Environment, environment_system_start)
		record_system_profile_phase(config, .UI, ui_system_start)
		cursor: platform.Runtime_Pointer_Cursor
		switch ui.current_pointer_cursor(config.ui_state) {
			case .Default:
			case .Pointer:
				cursor = .Pointer
			case .Text_Edit:
				cursor = .Text_Edit
			case .Horizontal_Resize:
				cursor = .Horizontal_Resize
			case .Vertical_Resize:
				cursor = .Vertical_Resize
			case .Move:
				cursor = .Move
			case .Not_Allowed:
				cursor = .Not_Allowed
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
