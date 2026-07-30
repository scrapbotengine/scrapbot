package render

import ecs "../ecs"
import platform "../platform"
import resources "../resources"
import shared "../shared"
import ui "../ui"
import base_runtime "base:runtime"
import "core:fmt"
import "core:math"
import "core:path/filepath"
import "core:time"
import "vendor:wgpu"

Vec2 :: shared.Vec2
Vec3 :: shared.Vec3
Render_Instance :: shared.Render_Instance
Camera_Instance :: shared.Camera_Instance
Render_List :: shared.Render_List

Mat4 :: [16]f32

WGPU_MAX_INSTANCES :: 64
WGPU_VIEWPORT_TARGET_MIN_SIZE :: u32(64)
WGPU_VIEWPORT_TARGET_MAX_SIZE :: u32(1024)
WGPU_VIEWPORT_TARGET_GRANULARITY :: u32(32)
WGPU_MAX_GPU_INSTANCES :: 131_072
WGPU_INITIAL_DRAW_CAPACITY :: 64
WGPU_VISIBLE_ALIGNMENT :: 64
WGPU_BLOOM_LEVELS :: 5
WGPU_GPU_TIMESTAMP_FRAMES :: 4
WGPU_MAX_HIZ_LEVELS :: 16
WGPU_HIZ_MIN_INSTANCES :: 256
WGPU_LEGACY_MAX_POINT_LIGHTS :: 16
WGPU_SHADOW_CASCADE_COUNT :: 4
WGPU_SHADOW_MAX_DISTANCE :: f32(80)
WGPU_SHADOW_SPLIT_LAMBDA :: f32(0.65)
WGPU_CLUSTER_COUNT_X :: 16
WGPU_CLUSTER_COUNT_Y :: 9
WGPU_CLUSTER_COUNT_Z :: 24
WGPU_CLUSTER_COUNT :: WGPU_CLUSTER_COUNT_X * WGPU_CLUSTER_COUNT_Y * WGPU_CLUSTER_COUNT_Z
WGPU_CLUSTER_INITIAL_LIGHT_CAPACITY :: 256

WGPU_GPU_Timestamp_Phase :: enum u32 {
	Instance_Expansion,
	Clustered_Lighting,
	Cull,
	Shadow,
	Depth,
	World,
	HiZ,
	Temporal_AA,
	Ambient_Occlusion,
	Screen_Space_Reflections,
	Volumetric_Fog,
	Bloom,
	Automatic_Exposure,
	Composite,
	UI,
}

WGPU_GPU_TIMESTAMP_PHASE_COUNT :: int(WGPU_GPU_Timestamp_Phase.UI) + 1
WGPU_GPU_HIZ_EXTRA_QUERY_BASE :: WGPU_GPU_TIMESTAMP_PHASE_COUNT * 2
WGPU_GPU_SHADOW_EXTRA_QUERY_BASE :: WGPU_GPU_HIZ_EXTRA_QUERY_BASE + (WGPU_MAX_HIZ_LEVELS - 1) * 2
WGPU_GPU_TIMESTAMP_QUERY_COUNT ::
	WGPU_GPU_SHADOW_EXTRA_QUERY_BASE + (WGPU_SHADOW_CASCADE_COUNT - 1) * 2
WGPU_GPU_TIMESTAMP_RESOLVE_ALIGNMENT :: u64(256)
WGPU_GPU_TIMESTAMP_RESOLVE_RANGE_COUNT :: WGPU_GPU_TIMESTAMP_PHASE_COUNT + 2
#assert((WGPU_MAX_HIZ_LEVELS - 1) * 2 * size_of(u64) <= WGPU_GPU_TIMESTAMP_RESOLVE_ALIGNMENT)

WGPU_GPU_Timestamp_Resolve_Range :: struct {
	first: u32,
	count: u32,
}

WGPU_GPU_Timestamp_Readback :: struct {
	buffer: wgpu.Buffer,
	map_state: WGPU_Buffer_Map_State,
	pending: bool,
	frame_index: u64,
	dynamic_resolution_generation: u64,
	hiz_mip_count: int,
	phase_mask: u32,
}

WGPU_Dynamic_Resolution_Sample :: struct {
	generation: u64,
	serial: u64,
	frame_index: u64,
	gpu_ms: f64,
}

WGPU_GPU_Visibility_Counters :: struct {
	visible_instances: u32,
	shadow_visible_instances: u32,
	frustum_candidates: u32,
	frustum_culled_instances: u32,
	occlusion_culled_instances: u32,
	lod_visible_instances: [shared.MAX_GEOMETRY_LODS]u32,
	visible_meshlets: u32,
	shadow_visible_meshlets: u32,
	frustum_culled_meshlets: u32,
	cone_culled_meshlets: u32,
	occlusion_culled_meshlets: u32,
	meshlet_debug_records: u32,
	visible_batches: u32,
	visible_meshlet_draws: u32,
}
WGPU_GPU_VISIBLE_BATCH_WORD_COUNT :: (WGPU_MAX_GPU_INSTANCES * shared.MAX_GEOMETRY_LODS + 31) / 32
#assert(WGPU_GPU_VISIBLE_BATCH_WORD_COUNT == 16_384)
WGPU_GPU_VISIBILITY_COUNTER_BUFFER_SIZE ::
	u64(size_of(WGPU_GPU_Visibility_Counters)) +
	u64(WGPU_GPU_VISIBLE_BATCH_WORD_COUNT * size_of(u32))

WGPU_GPU_Visibility_Readback :: struct {
	buffer: wgpu.Buffer,
	map_state: WGPU_Buffer_Map_State,
	pending: bool,
}

WGPU_Render_Uniform :: struct {
	mvp: [WGPU_MAX_INSTANCES]Mat4,
	model: [WGPU_MAX_INSTANCES]Mat4,
	normal_model: [WGPU_MAX_INSTANCES]Mat4,
	shadow_mvp: [WGPU_MAX_INSTANCES]Mat4,
	color: [WGPU_MAX_INSTANCES][4]f32,
	emissive: [WGPU_MAX_INSTANCES][4]f32,
	shadow_flags: [WGPU_MAX_INSTANCES][4]f32,
	ambient: [4]f32,
	directional_direction_intensity: [shared.MAX_DIRECTIONAL_LIGHTS][4]f32,
	directional_color: [shared.MAX_DIRECTIONAL_LIGHTS][4]f32,
	point_position_range: [WGPU_LEGACY_MAX_POINT_LIGHTS][4]f32,
	point_color_intensity: [WGPU_LEGACY_MAX_POINT_LIGHTS][4]f32,
	light_counts: [4]u32,
	camera_position: [4]f32,
}

WGPU_GPU_Render_Uniform :: struct {
	view_projection: Mat4,
	view: Mat4,
	shadow_view_projections: [WGPU_SHADOW_CASCADE_COUNT]Mat4,
	ambient: [4]f32,
	directional_direction_intensity: [shared.MAX_DIRECTIONAL_LIGHTS][4]f32,
	directional_color: [shared.MAX_DIRECTIONAL_LIGHTS][4]f32,
	light_counts: [4]u32,
	camera_position: [4]f32,
	shadow_cascade_splits: [4]f32,
	shadow_cascade_texel_sizes: [4]f32,
	debug: [4]u32,
	camera_clip: [4]f32,
}
#assert(size_of(WGPU_GPU_Render_Uniform) == 624)

WGPU_GPU_Point_Light :: struct {
	position_range: [4]f32,
	color_intensity: [4]f32,
}
#assert(size_of(WGPU_GPU_Point_Light) == 32)

WGPU_Cluster_Uniform :: struct {
	view: Mat4,
	projection: Mat4,
	viewport: [4]f32,
	z_parameters: [4]f32,
	counts: [4]u32,
}
#assert(size_of(WGPU_Cluster_Uniform) == 176)

WGPU_Shadow_Cascade_Uniform :: struct {
	index: u32,
	_padding: [3]u32,
}
#assert(size_of(WGPU_Shadow_Cascade_Uniform) == 16)

WGPU_Material_Uniform :: struct {
	pbr_factors: [4]f32,
	flags: [4]f32,
	alpha: [4]f32,
}
#assert(size_of(WGPU_Material_Uniform) == 48)

WGPU_Environment_Uniform :: struct {
	intensity: f32,
	rotation: f32,
	exposure: f32,
	enabled: f32,
	max_specular_lod: f32,
	background_intensity: f32,
	background_rotation: f32,
	background_exposure: f32,
	background_blur: f32,
	background_enabled: f32,
	background_max_specular_lod: f32,
	reflection_intensity: f32,
	sun_direction_intensity: [4]f32,
	sun_color: [4]f32,
	atmosphere_sky_tint: [4]f32,
	atmosphere_ground_color: [4]f32,
	atmosphere_parameters: [4]f32,
	atmosphere_sun: [4]f32,
}
#assert(size_of(WGPU_Environment_Uniform) == 144)

WGPU_Sky_Uniform :: struct {
	right: [4]f32,
	up: [4]f32,
	forward: [4]f32,
	projection: [4]f32,
}
#assert(size_of(WGPU_Sky_Uniform) == 64)

WGPU_Ambient_Occlusion_Uniform :: struct {
	projection: [4]f32,
	viewport: [4]f32,
	dimensions: [4]f32,
	parameters: [4]f32,
	visibility_parameters: [4]f32,
}
#assert(size_of(WGPU_Ambient_Occlusion_Uniform) == 80)

WGPU_VISIBILITY_AO_RADIUS :: f32(1.0)
WGPU_VISIBILITY_AO_POWER :: f32(1.0)
WGPU_VISIBILITY_AO_STRENGTH :: f32(0.45)
WGPU_VISIBILITY_AO_THICKNESS :: f32(0.15)

WGPU_Screen_Space_Reflections_Uniform :: struct {
	projection: [4]f32,
	viewport: [4]f32,
	parameters: [4]f32,
	_padding: [4]f32,
}
#assert(size_of(WGPU_Screen_Space_Reflections_Uniform) == 64)

WGPU_Temporal_AA_Uniform :: struct {
	previous_view_projection: Mat4,
	inverse_view: Mat4,
	projection: [4]f32,
	previous_projection: [4]f32,
	viewport: [4]f32,
	parameters: [4]f32,
	features: [4]f32,
	reflections: [4]f32,
	fog_color_density: [4]f32,
	fog_height_distance: [4]f32,
	fog_lighting: [4]f32,
}
#assert(size_of(WGPU_Temporal_AA_Uniform) == 272)

WGPU_Temporal_Camera :: struct {
	position: Vec3,
	forward: Vec3,
	fov: f32,
	has_camera: bool,
	temporal_antialiasing: bool,
}

WGPU_Automatic_Exposure_Settings :: struct {
	viewport: [4]f32,
	parameters: [4]f32,
	control: [4]f32,
}
#assert(size_of(WGPU_Automatic_Exposure_Settings) == 48)

WGPU_Automatic_Exposure_State :: struct {
	values: [4]f32,
}
#assert(size_of(WGPU_Automatic_Exposure_State) == 16)

WGPU_Draw_Batch :: struct {
	geometry: shared.Geometry_Handle,
	material: shared.Material_Handle,
	first_instance: u32,
	instance_count: u32,
	visible_offset: u32,
	visible_capacity: u32,
	meshlet_draw_offset: u32,
	meshlet_draw_count: u32,
	meshlet_visible_offset: u32,
	meshlet_visible_capacity: u32,
	world_bind_group: wgpu.BindGroup,
	shadow_bind_groups: [WGPU_SHADOW_CASCADE_COUNT]wgpu.BindGroup,
	meshlet_world_bind_group: wgpu.BindGroup,
	meshlet_shadow_bind_groups: [WGPU_SHADOW_CASCADE_COUNT]wgpu.BindGroup,
}

WGPU_Draw_Batch_Cache :: struct {
	world_uuid: shared.Entity_UUID,
	topology_revision: u64,
	geometry_topology_revision: u64,
	valid: bool,
	batches: [dynamic]WGPU_Draw_Batch,
	batch_count: int,
	source_indices: [dynamic]int,
	instance_count: int,
	rebuild_count: u64,
}

WGPU_GPU_Instance :: struct {
	model: Mat4,
	normal_model: Mat4,
	color: [4]f32,
	emissive: [4]f32,
	shadow_flags: [4]f32,
	bounds: [4]f32,
	batch_indices: [shared.MAX_GEOMETRY_LODS]u32,
	lod_screen_radii: [shared.MAX_GEOMETRY_LODS]f32,
	lod_count: u32,
	active: u32,
	_padding: [2]u32,
}
#assert(size_of(WGPU_GPU_Instance) == 240)

WGPU_GPU_Instance_Transform :: struct {
	position: [4]f32,
	rotation: [4]f32,
	scale: [4]f32,
	local_bounds: [4]f32,
}
#assert(size_of(WGPU_GPU_Instance_Transform) == 64)

WGPU_GPU_Cull_Uniform :: struct {
	camera_planes: [6][4]f32,
	shadow_planes: [WGPU_SHADOW_CASCADE_COUNT][6][4]f32,
	view_projection: Mat4,
	hiz_view_projection: Mat4,
	viewport: [4]f32,
	camera_position: [4]f32,
	slot_count: u32,
	batch_count: u32,
	hiz_mip_count: u32,
	hiz_enabled: u32,
	shadow_visible_stride: u32,
	meshlet_enabled: u32,
	meshlet_shadow_visible_stride: u32,
	meshlet_debug_record_offset: u32,
	debug_view: u32,
	_padding: [3]u32,
}
#assert(size_of(WGPU_GPU_Cull_Uniform) == 688)

WGPU_Draw_Indexed_Indirect :: struct {
	index_count: u32,
	instance_count: u32,
	first_index: u32,
	base_vertex: i32,
	first_instance: u32,
}
#assert(size_of(WGPU_Draw_Indexed_Indirect) == 20)

WGPU_Draw_Indirect :: struct {
	vertex_count: u32,
	instance_count: u32,
	first_vertex: u32,
	first_instance: u32,
}
#assert(size_of(WGPU_Draw_Indirect) == 16)

WGPU_GPU_Meshlet_Debug_Record :: struct {
	bounds: [4]f32,
	query_rect: [4]f32,
	query_depths: [4]f32,
	classification: u32,
	lod_level: u32,
	meshlet_identity: u32,
	_padding: u32,
}
#assert(size_of(WGPU_GPU_Meshlet_Debug_Record) == 64)

WGPU_GPU_Batch_Info :: struct {
	visible_offset: u32,
	visible_capacity: u32,
	meshlet_offset: u32,
	meshlet_count: u32,
}

WGPU_GPU_Meshlet_Info :: struct {
	bounds: [4]f32,
	cone_axis_cutoff: [4]f32,
	visible_offset: u32,
	visible_capacity: u32,
	flags: u32,
	_padding: u32,
}
#assert(size_of(WGPU_GPU_Meshlet_Info) == 48)

WGPU_Instance_Source_State :: struct {
	geometry: shared.Geometry_Handle,
	material: shared.Material_Handle,
	geometry_version: u32,
	material_version: u32,
	shadow_caster: bool,
	shadow_receiver: bool,
	batch_indices: [shared.MAX_GEOMETRY_LODS]u32,
	lod_screen_radii: [shared.MAX_GEOMETRY_LODS]f32,
	lod_count: u32,
}

WGPU_Geometry_Cache :: struct {
	handle: shared.Geometry_Handle,
	version: u32,
	vertex_buffer: wgpu.Buffer,
	index_buffer: wgpu.Buffer,
	meshlet_index_buffer: wgpu.Buffer,
	index_count: u32,
	valid: bool,
}

WGPU_Material_Cache :: struct {
	handle: shared.Material_Handle,
	version: u32,
	texture_handle: shared.Texture_Handle,
	texture_version: u32,
	textures: [5]wgpu.Texture,
	views: [5]wgpu.TextureView,
	samplers: [5]wgpu.Sampler,
	bind_group: wgpu.BindGroup,
	uniform_buffer: wgpu.Buffer,
	owns_texture: [5]bool,
	double_sided: bool,
	valid: bool,
}

WGPU_Texture_Cache :: struct {
	handle: shared.Texture_Handle,
	version: u32,
	texture: wgpu.Texture,
	view: wgpu.TextureView,
	valid: bool,
}
WGPU_UI_Vertex :: struct {
	position: [2]f32,
	uv: [2]f32,
	color: [4]f32,
	kind: f32,
	size_radius: [3]f32,
	clip: [4]f32,
	border_color: [4]f32,
	border_width: f32,
	font_layer: f32,
}
#assert(size_of(WGPU_UI_Vertex) == 88)

WGPU_Request_Adapter_State :: struct {
	completed: bool,
	status: wgpu.RequestAdapterStatus,
	adapter: wgpu.Adapter,
	message: [512]u8,
	message_length: int,
}

wgpu_material_cache_slot :: proc(
	cache: []WGPU_Material_Cache,
	handle: shared.Material_Handle,
) -> int {
	for cached, index in cache {
		if cached.handle.index == handle.index {
			return index
		}
	}
	return -1
}

wgpu_texture_cache_slot :: proc(
	cache: []WGPU_Texture_Cache,
	handle: shared.Texture_Handle,
) -> int {
	for cached, index in cache {
		if cached.handle.index == handle.index {
			return index
		}
	}
	return -1
}

wgpu_geometry_cache_slot :: proc(
	cache: []WGPU_Geometry_Cache,
	handle: shared.Geometry_Handle,
) -> int {
	for cached, index in cache {
		if cached.handle.index == handle.index {
			return index
		}
	}
	return -1
}

WGPU_Request_Device_State :: struct {
	completed: bool,
	status: wgpu.RequestDeviceStatus,
	device: wgpu.Device,
	message: [512]u8,
	message_length: int,
}

WGPU_Buffer_Map_State :: struct {
	completed: bool,
	status: wgpu.MapAsyncStatus,
	message: [512]u8,
	message_length: int,
}

WGPU_Renderer :: struct {
	instance: wgpu.Instance,
	surface: wgpu.Surface,
	adapter: wgpu.Adapter,
	device: wgpu.Device,
	queue: wgpu.Queue,
	pipeline_layout: wgpu.PipelineLayout,
	bind_group_layout: wgpu.BindGroupLayout,
	bind_group: wgpu.BindGroup,
	material_bind_group_layout: wgpu.BindGroupLayout,
	material_sampler: wgpu.Sampler,
	material_fallback_textures: [5]wgpu.Texture,
	material_fallback_views: [5]wgpu.TextureView,
	environment_bind_group_layout: wgpu.BindGroupLayout,
	environment_bind_group: wgpu.BindGroup,
	environment_sampler: wgpu.Sampler,
	environment_uniform_buffer: wgpu.Buffer,
	environment_sky_texture: wgpu.Texture,
	environment_sky_view: wgpu.TextureView,
	environment_irradiance_texture: wgpu.Texture,
	environment_irradiance_view: wgpu.TextureView,
	environment_specular_texture: wgpu.Texture,
	environment_specular_view: wgpu.TextureView,
	environment_background_specular_texture: wgpu.Texture,
	environment_background_specular_view: wgpu.TextureView,
	environment_cached_handle: shared.Environment_Handle,
	environment_cached_version: u32,
	environment_cached_background_handle: shared.Environment_Handle,
	environment_cached_background_version: u32,
	environment_cached_revision: u64,
	environment_cached_camera_exposure: f32,
	environment_cache_valid: bool,
	sky_bind_group_layout: wgpu.BindGroupLayout,
	sky_bind_group: wgpu.BindGroup,
	sky_pipeline_layout: wgpu.PipelineLayout,
	sky_shader: wgpu.ShaderModule,
	sky_pipeline: wgpu.RenderPipeline,
	sky_uniform_buffer: wgpu.Buffer,
	sky_cached_uniform: WGPU_Sky_Uniform,
	sky_uniform_cache_valid: bool,
	ui_bind_group_layout: wgpu.BindGroupLayout,
	ui_bind_group: wgpu.BindGroup,
	ui_pipeline_layout: wgpu.PipelineLayout,
	ui_shader: wgpu.ShaderModule,
	ui_pipeline: wgpu.RenderPipeline,
	ui_viewport_pipeline: wgpu.RenderPipeline,
	ui_viewport_texture_pipeline: wgpu.RenderPipeline,
	ui_viewport_texture_pipeline_layout: wgpu.PipelineLayout,
	ui_viewport_texture_bind_group_layout: wgpu.BindGroupLayout,
	ui_font_texture: wgpu.Texture,
	ui_font_view: wgpu.TextureView,
	ui_font_sampler: wgpu.Sampler,
	ui_viewport_textures: [ui.MAX_EMBEDDED_VIEWPORTS]wgpu.Texture,
	ui_viewport_layer_views: [ui.MAX_EMBEDDED_VIEWPORTS]wgpu.TextureView,
	ui_viewport_depth_textures: [ui.MAX_EMBEDDED_VIEWPORTS]wgpu.Texture,
	ui_viewport_depth_views: [ui.MAX_EMBEDDED_VIEWPORTS]wgpu.TextureView,
	ui_viewport_widths: [ui.MAX_EMBEDDED_VIEWPORTS]u32,
	ui_viewport_heights: [ui.MAX_EMBEDDED_VIEWPORTS]u32,
	ui_viewport_uniform_buffers: [ui.MAX_EMBEDDED_VIEWPORTS]wgpu.Buffer,
	ui_viewport_bind_groups: [ui.MAX_EMBEDDED_VIEWPORTS]wgpu.BindGroup,
	ui_viewport_cached_components: [ui.MAX_EMBEDDED_VIEWPORTS]shared.UI_Viewport_Component,
	ui_viewport_cached_resource_versions: [ui.MAX_EMBEDDED_VIEWPORTS]u32,
	ui_viewport_cached_aspects: [ui.MAX_EMBEDDED_VIEWPORTS]f32,
	ui_viewport_cached_geometry_revisions: [ui.MAX_EMBEDDED_VIEWPORTS]u64,
	ui_viewport_cached_texture_revisions: [ui.MAX_EMBEDDED_VIEWPORTS]u64,
	ui_viewport_cached_material_revisions: [ui.MAX_EMBEDDED_VIEWPORTS]u64,
	ui_viewport_cache_valid: [ui.MAX_EMBEDDED_VIEWPORTS]bool,
	ui_viewport_cache_warmup_frames: [ui.MAX_EMBEDDED_VIEWPORTS]u8,
	ui_viewport_preview_vertex_buffer: wgpu.Buffer,
	ui_viewport_preview_index_buffer: wgpu.Buffer,
	ui_viewport_preview_index_count: u32,
	ui_viewport_active_targets: int,
	ui_viewport_target_pixels: u64,
	ui_viewport_target_resize_count: u64,
	ui_viewport_redraw_count: u64,
	ui_viewport_cache_hit_count: u64,
	ui_font_versions: [shared.MAX_PROJECT_FONTS]u32,
	ui_icon_set_versions: [shared.MAX_ICON_SETS]u32,
	ui_project_vertices: [dynamic]WGPU_UI_Vertex,
	ui_project_vertex_buffer: wgpu.Buffer,
	ui_project_vertex_capacity: int,
	ui_project_stream_key: WGPU_UI_Stream_Key,
	ui_project_stream_key_valid: bool,
	ui_editor_vertices: [dynamic]WGPU_UI_Vertex,
	ui_editor_vertex_buffer: wgpu.Buffer,
	ui_editor_vertex_capacity: int,
	ui_editor_stream_key: WGPU_UI_Stream_Key,
	ui_editor_stream_key_valid: bool,
	ui_overlay_vertices: [dynamic]WGPU_UI_Vertex,
	ui_overlay_vertex_buffer: wgpu.Buffer,
	ui_overlay_vertex_capacity: int,
	ui_overlay_stream_key: WGPU_UI_Stream_Key,
	ui_overlay_stream_key_valid: bool,
	ui_vertex_rebuild_count: u64,
	ui_project_vertex_rebuild_count: u64,
	ui_editor_vertex_rebuild_count: u64,
	ui_overlay_vertex_rebuild_count: u64,
	ui_vertex_upload_count: u64,
	ui_vertex_upload_bytes: u64,
	render_list: Render_List,
	draw_batch_cache: WGPU_Draw_Batch_Cache,
	gpu_driven_shader: wgpu.ShaderModule,
	gpu_driven_pipeline: wgpu.RenderPipeline,
	gpu_driven_double_sided_pipeline: wgpu.RenderPipeline,
	gpu_driven_depth_pipeline: wgpu.RenderPipeline,
	gpu_driven_depth_double_sided_pipeline: wgpu.RenderPipeline,
	gpu_driven_depth_mask_pipeline: wgpu.RenderPipeline,
	gpu_driven_depth_mask_double_sided_pipeline: wgpu.RenderPipeline,
	gpu_driven_depth_pipeline_layout: wgpu.PipelineLayout,
	gpu_driven_depth_mask_pipeline_layout: wgpu.PipelineLayout,
	gpu_driven_shadow_pipeline: wgpu.RenderPipeline,
	gpu_driven_shadow_double_sided_pipeline: wgpu.RenderPipeline,
	gpu_driven_shadow_mask_pipeline: wgpu.RenderPipeline,
	gpu_driven_shadow_mask_double_sided_pipeline: wgpu.RenderPipeline,
	gpu_driven_pipeline_layout: wgpu.PipelineLayout,
	gpu_driven_shadow_pipeline_layout: wgpu.PipelineLayout,
	gpu_driven_shadow_mask_pipeline_layout: wgpu.PipelineLayout,
	gpu_driven_world_bind_group_layout: wgpu.BindGroupLayout,
	gpu_driven_shadow_bind_group_layout: wgpu.BindGroupLayout,
	gpu_cull_shader: wgpu.ShaderModule,
	gpu_cull_pipeline: wgpu.ComputePipeline,
	gpu_cull_pipeline_layout: wgpu.PipelineLayout,
	gpu_cull_bind_group_layout: wgpu.BindGroupLayout,
	gpu_cull_bind_group: wgpu.BindGroup,
	gpu_meshlet_cull_bind_group: wgpu.BindGroup,
	gpu_meshlet_debug_shader: wgpu.ShaderModule,
	gpu_meshlet_debug_pipeline: wgpu.RenderPipeline,
	gpu_meshlet_debug_pipeline_layout: wgpu.PipelineLayout,
	gpu_meshlet_debug_bind_group_layout: wgpu.BindGroupLayout,
	gpu_meshlet_debug_bind_group: wgpu.BindGroup,
	gpu_transform_shader: wgpu.ShaderModule,
	gpu_transform_pipeline: wgpu.ComputePipeline,
	gpu_transform_pipeline_layout: wgpu.PipelineLayout,
	gpu_transform_bind_group_layout: wgpu.BindGroupLayout,
	gpu_transform_bind_group: wgpu.BindGroup,
	gpu_hiz_shader: wgpu.ShaderModule,
	gpu_hiz_downsample_shader: wgpu.ShaderModule,
	gpu_hiz_debug_shader: wgpu.ShaderModule,
	gpu_hiz_first_pipeline: wgpu.ComputePipeline,
	gpu_hiz_downsample_pipeline: wgpu.ComputePipeline,
	gpu_hiz_debug_pipeline: wgpu.RenderPipeline,
	gpu_hiz_first_bind_group_layout: wgpu.BindGroupLayout,
	gpu_hiz_downsample_bind_group_layout: wgpu.BindGroupLayout,
	gpu_hiz_debug_bind_group_layout: wgpu.BindGroupLayout,
	gpu_hiz_first_pipeline_layout: wgpu.PipelineLayout,
	gpu_hiz_downsample_pipeline_layout: wgpu.PipelineLayout,
	gpu_hiz_debug_pipeline_layout: wgpu.PipelineLayout,
	gpu_hiz_texture: wgpu.Texture,
	gpu_hiz_view: wgpu.TextureView,
	gpu_hiz_mip_views: [WGPU_MAX_HIZ_LEVELS]wgpu.TextureView,
	gpu_hiz_first_bind_group: wgpu.BindGroup,
	gpu_hiz_downsample_bind_groups: [WGPU_MAX_HIZ_LEVELS]wgpu.BindGroup,
	gpu_hiz_debug_bind_group: wgpu.BindGroup,
	gpu_hiz_width: u32,
	gpu_hiz_height: u32,
	gpu_hiz_mip_count: int,
	gpu_hiz_valid: bool,
	gpu_hiz_occlusion_enabled: bool,
	gpu_hiz_occlusion_status: shared.HiZ_Occlusion_Status,
	gpu_hiz_requested: bool,
	gpu_previous_view_projection: Mat4,
	gpu_current_view_projection: Mat4,
	gpu_previous_depth_view_projection: Mat4,
	gpu_instance_buffer: wgpu.Buffer,
	gpu_transform_update_buffer: wgpu.Buffer,
	gpu_batch_info_buffer: wgpu.Buffer,
	gpu_visible_buffer: wgpu.Buffer,
	gpu_shadow_visible_buffer: wgpu.Buffer,
	gpu_indirect_template_buffer: wgpu.Buffer,
	gpu_indirect_buffer: wgpu.Buffer,
	gpu_shadow_indirect_buffer: wgpu.Buffer,
	gpu_meshlet_info_buffer: wgpu.Buffer,
	gpu_meshlet_visible_buffer: wgpu.Buffer,
	gpu_meshlet_identity_buffer: wgpu.Buffer,
	gpu_meshlet_debug_indirect_buffer: wgpu.Buffer,
	gpu_occlusion_debug_evidence_valid: bool,
	gpu_occlusion_debug_record_count: u32,
	gpu_meshlet_shadow_visible_buffer: wgpu.Buffer,
	gpu_meshlet_indirect_template_buffer: wgpu.Buffer,
	gpu_meshlet_indirect_buffer: wgpu.Buffer,
	gpu_meshlet_shadow_indirect_buffer: wgpu.Buffer,
	gpu_cull_uniform_buffer: wgpu.Buffer,
	gpu_render_uniform_buffer: wgpu.Buffer,
	gpu_point_light_buffer: wgpu.Buffer,
	gpu_cluster_count_buffer: wgpu.Buffer,
	gpu_cluster_index_buffer: wgpu.Buffer,
	gpu_cluster_uniform_buffer: wgpu.Buffer,
	gpu_cluster_shader: wgpu.ShaderModule,
	gpu_cluster_pipeline: wgpu.ComputePipeline,
	gpu_cluster_pipeline_layout: wgpu.PipelineLayout,
	gpu_cluster_bind_group_layout: wgpu.BindGroupLayout,
	gpu_cluster_bind_group: wgpu.BindGroup,
	gpu_cluster_dispatch_count: u64,
	gpu_clustered_light_count: int,
	gpu_point_light_capacity: int,
	gpu_cluster_light_capacity: int,
	gpu_point_lights: [dynamic]WGPU_GPU_Point_Light,
	gpu_point_lights_valid: bool,
	gpu_cluster_uniform: WGPU_Cluster_Uniform,
	gpu_cluster_uniform_valid: bool,
	gpu_cluster_dirty: bool,
	gpu_shadow_cascade_uniform_buffers: [WGPU_SHADOW_CASCADE_COUNT]wgpu.Buffer,
	gpu_visibility_counter_buffer: wgpu.Buffer,
	gpu_visibility_readbacks: [WGPU_GPU_TIMESTAMP_FRAMES]WGPU_GPU_Visibility_Readback,
	gpu_visibility_next_slot: int,
	gpu_visibility_active_slot: int,
	gpu_visibility_counters: WGPU_GPU_Visibility_Counters,
	gpu_instance_records: [dynamic]WGPU_GPU_Instance,
	gpu_instance_transform_records: [dynamic]WGPU_GPU_Instance_Transform,
	gpu_instance_sources: [dynamic]WGPU_Instance_Source_State,
	gpu_instance_source_transforms: [dynamic]shared.Transform_Component,
	gpu_active_slots: [dynamic]bool,
	gpu_dirty_indices: [dynamic]int,
	gpu_transform_updates: [dynamic]WGPU_GPU_Instance_Transform,
	gpu_live_slots: [dynamic]int,
	gpu_batch_indices_by_slot: [dynamic][shared.MAX_GEOMETRY_LODS]u32,
	gpu_cpu_visible: [dynamic]u32,
	gpu_cpu_shadow_visible: [dynamic]u32,
	gpu_indirect_templates: [dynamic]WGPU_Draw_Indexed_Indirect,
	gpu_meshlet_infos: [dynamic]WGPU_GPU_Meshlet_Info,
	gpu_meshlet_indirect_templates: [dynamic]WGPU_Draw_Indexed_Indirect,
	gpu_draw_capacity: int,
	gpu_visible_buffer_capacity: int,
	gpu_meshlet_draw_capacity: int,
	gpu_meshlet_visible_buffer_capacity: int,
	gpu_meshlet_draw_count: int,
	gpu_meshlet_visible_capacity: int,
	gpu_meshlet_supported: bool,
	gpu_meshlet_native_multi_draw: bool,
	gpu_meshlet_layout_valid: bool,
	gpu_meshlet_submission_active: bool,
	gpu_draw_database_rebuild_count: u64,
	gpu_slot_count: int,
	gpu_visible_capacity: int,
	gpu_topology_revision: u64,
	gpu_material_revision: u64,
	gpu_world_uuid: shared.Entity_UUID,
	gpu_topology_valid: bool,
	gpu_instance_upload_count: u64,
	gpu_instance_upload_bytes: u64,
	gpu_instance_transform_upload_count: u64,
	gpu_instance_transform_upload_bytes: u64,
	gpu_instance_expand_dispatch_count: u64,
	gpu_instance_expanded_slot_count: u64,
	gpu_render_uniform: WGPU_GPU_Render_Uniform,
	gpu_render_uniform_valid: bool,
	gpu_cull_uniform: WGPU_GPU_Cull_Uniform,
	gpu_cull_uniform_valid: bool,
	gpu_timestamp_query_set: wgpu.QuerySet,
	gpu_timestamp_resolve_buffer: wgpu.Buffer,
	gpu_timestamp_readbacks: [WGPU_GPU_TIMESTAMP_FRAMES]WGPU_GPU_Timestamp_Readback,
	gpu_timestamp_period_ns: f64,
	gpu_timestamp_next_slot: int,
	gpu_timestamp_active_slot: int,
	gpu_timestamp_supported: bool,
	gpu_timestamp_valid: bool,
	gpu_timestamp_sample_serial: u64,
	gpu_timestamp_resolution_samples: [WGPU_GPU_TIMESTAMP_FRAMES]WGPU_Dynamic_Resolution_Sample,
	gpu_timestamp_resolution_sample_count: int,
	gpu_timestamp_phase_ms: [WGPU_GPU_TIMESTAMP_PHASE_COUNT]f64,
	gpu_timestamp_frame_ms: f64,
	dynamic_resolution: Dynamic_Resolution_State,
	profile: ^Profile_Collector,
	profile_frame_index: u64,
	shadow_bind_group_layout: wgpu.BindGroupLayout,
	shadow_bind_group: wgpu.BindGroup,
	shadow_pipeline_layout: wgpu.PipelineLayout,
	shader: wgpu.ShaderModule,
	pipeline: wgpu.RenderPipeline,
	shadow_pipeline: wgpu.RenderPipeline,
	post_shader: wgpu.ShaderModule,
	automatic_exposure_shader: wgpu.ShaderModule,
	temporal_aa_shader: wgpu.ShaderModule,
	ambient_occlusion_shader: wgpu.ShaderModule,
	composite_shader: wgpu.ShaderModule,
	temporal_aa_bind_group_layout: wgpu.BindGroupLayout,
	temporal_aa_pipeline_layout: wgpu.PipelineLayout,
	temporal_aa_pipeline: wgpu.ComputePipeline,
	volumetric_fog_pipeline: wgpu.ComputePipeline,
	temporal_aa_uniform_buffer: wgpu.Buffer,
	temporal_aa_bind_groups: [2]wgpu.BindGroup,
	volumetric_fog_bind_group: wgpu.BindGroup,
	volumetric_fog_texture: wgpu.Texture,
	volumetric_fog_view: wgpu.TextureView,
	volumetric_fog_dummy_texture: wgpu.Texture,
	volumetric_fog_dummy_view: wgpu.TextureView,
	temporal_color_textures: [2]wgpu.Texture,
	temporal_color_views: [2]wgpu.TextureView,
	temporal_depth_textures: [2]wgpu.Texture,
	temporal_depth_views: [2]wgpu.TextureView,
	temporal_output_index: int,
	temporal_previous_view_projection: Mat4,
	temporal_current_view_projection: Mat4,
	temporal_previous_projection: [4]f32,
	temporal_current_projection: [4]f32,
	temporal_inverse_view: Mat4,
	temporal_camera: WGPU_Temporal_Camera,
	temporal_sample_index: u64,
	temporal_history_valid: bool,
	temporal_camera_valid: bool,
	automatic_exposure_bind_group_layout: wgpu.BindGroupLayout,
	automatic_exposure_pipeline_layout: wgpu.PipelineLayout,
	automatic_exposure_pipeline: wgpu.ComputePipeline,
	automatic_exposure_settings_buffer: wgpu.Buffer,
	automatic_exposure_state_buffer: wgpu.Buffer,
	automatic_exposure_bind_groups: [2]wgpu.BindGroup,
	automatic_exposure_valid: bool,
	automatic_exposure_enabled: bool,
	automatic_exposure_debug_view: bool,
	ambient_occlusion_bind_group_layout: wgpu.BindGroupLayout,
	ambient_occlusion_pipeline_layout: wgpu.PipelineLayout,
	ambient_occlusion_pipeline: wgpu.ComputePipeline,
	ambient_occlusion_blur_horizontal_pipeline: wgpu.ComputePipeline,
	ambient_occlusion_blur_vertical_pipeline: wgpu.ComputePipeline,
	ambient_occlusion_uniform_buffer: wgpu.Buffer,
	ambient_occlusion_textures: [3]wgpu.Texture,
	ambient_occlusion_views: [3]wgpu.TextureView,
	ambient_occlusion_bind_groups: [3]wgpu.BindGroup,
	screen_space_reflections_shader: wgpu.ShaderModule,
	screen_space_reflections_bind_group_layout: wgpu.BindGroupLayout,
	screen_space_reflections_pipeline_layout: wgpu.PipelineLayout,
	screen_space_reflections_pipeline: wgpu.ComputePipeline,
	screen_space_reflections_uniform_buffer: wgpu.Buffer,
	screen_space_reflections_texture: wgpu.Texture,
	screen_space_reflections_view: wgpu.TextureView,
	screen_space_reflections_bind_group: wgpu.BindGroup,
	bloom_compute_bind_group_layout: wgpu.BindGroupLayout,
	bloom_compute_pipeline_layout: wgpu.PipelineLayout,
	bloom_bright_pipeline: wgpu.ComputePipeline,
	bloom_downsample_pipeline: wgpu.ComputePipeline,
	composite_bind_group_layout: wgpu.BindGroupLayout,
	composite_pipeline_layout: wgpu.PipelineLayout,
	composite_pipeline: wgpu.RenderPipeline,
	post_sampler: wgpu.Sampler,
	hdr_texture: wgpu.Texture,
	hdr_view: wgpu.TextureView,
	surface_texture: wgpu.Texture,
	surface_view: wgpu.TextureView,
	indirect_diffuse_texture: wgpu.Texture,
	indirect_diffuse_view: wgpu.TextureView,
	bloom_textures: [WGPU_BLOOM_LEVELS]wgpu.Texture,
	bloom_views: [WGPU_BLOOM_LEVELS]wgpu.TextureView,
	bloom_compute_bind_groups: [2][WGPU_BLOOM_LEVELS]wgpu.BindGroup,
	composite_bind_groups: [2]wgpu.BindGroup,
	post_depth_view: wgpu.TextureView,
	post_width: u32,
	post_height: u32,
	render_depth_texture: wgpu.Texture,
	render_depth_view: wgpu.TextureView,
	render_depth_width: u32,
	render_depth_height: u32,
	geometry_cache: [dynamic]WGPU_Geometry_Cache,
	texture_cache: [dynamic]WGPU_Texture_Cache,
	material_cache: [dynamic]WGPU_Material_Cache,
	uniform_buffer: wgpu.Buffer,
	depth_texture: wgpu.Texture,
	depth_view: wgpu.TextureView,
	shadow_texture: wgpu.Texture,
	shadow_view: wgpu.TextureView,
	shadow_array_view: wgpu.TextureView,
	shadow_layer_views: [WGPU_SHADOW_CASCADE_COUNT]wgpu.TextureView,
	shadow_sampler: wgpu.Sampler,
	format: wgpu.TextureFormat,
	present_mode: wgpu.PresentMode,
	alpha_mode: wgpu.CompositeAlphaMode,
	width: u32,
	height: u32,
	configured: bool,
}

WGPU_Live_Resize_State :: struct {
	renderer: ^WGPU_Renderer,
	world: ^World,
	config: ^Run_Config,
	previous_tick: ^time.Tick,
	frame_count: ^u32,
	drawing: bool,
	should_quit: bool,
	err: string,
}

WGPU_UI_Stream_Key :: struct {
	revision: u64,
	target_width: u32,
	target_height: u32,
	viewport: ui.Rect,
}

WGPU_Render_Target_Layout :: struct {
	output_width: u32,
	output_height: u32,
	render_width: u32,
	render_height: u32,
	output_viewport: ui.Rect,
	render_viewport: ui.Rect,
	resolution_scale: f32,
}

wgpu_apply_render_debug_override :: proc(render_list: ^Render_List, ui_state: ^ui.State) {
	if render_list == nil || !render_list.has_camera {
		return
	}
	render_list.camera.camera.debug_view = ui.effective_render_debug_view(
		ui_state,
		render_list.camera.camera,
	)
	render_list.camera.camera.debug_hiz_mip = f32(
		ui.effective_render_debug_hiz_mip(ui_state, render_list.camera.camera),
	)
	render_list.camera.camera.debug_occlusion_freeze = ui.effective_render_debug_occlusion_freeze(
		ui_state,
		render_list.camera.camera,
	)
}

wgpu_dynamic_resolution_scale :: proc(
	renderer: ^WGPU_Renderer,
	camera: shared.Camera_Component,
	policy_owner: shared.Entity_UUID,
) -> f32 {
	if renderer == nil {
		return shared.camera_resolution_scale(camera)
	}
	scale := dynamic_resolution_scale(
		&renderer.dynamic_resolution,
		camera,
		renderer.gpu_timestamp_supported,
		renderer.dynamic_resolution.last_sample_serial,
		0,
		0,
		policy_owner,
	)
	samples := renderer.gpu_timestamp_resolution_samples[:renderer.gpu_timestamp_resolution_sample_count]
	for index in 1 ..< len(samples) {
		sample := samples[index]
		cursor := index
		for cursor > 0 && samples[cursor - 1].frame_index > sample.frame_index {
			samples[cursor] = samples[cursor - 1]
			cursor -= 1
		}
		samples[cursor] = sample
	}
	for sample in samples {
		if sample.generation != renderer.dynamic_resolution.generation {
			continue
		}
		generation := renderer.dynamic_resolution.generation
		scale = dynamic_resolution_scale(
			&renderer.dynamic_resolution,
			camera,
			renderer.gpu_timestamp_supported,
			sample.serial,
			sample.gpu_ms,
			0,
			policy_owner,
		)
		if renderer.dynamic_resolution.generation != generation {
			break
		}
	}
	renderer.gpu_timestamp_resolution_sample_count = 0
	if wgpu_gpu_timing_active(renderer) {
		readback := &renderer.gpu_timestamp_readbacks[renderer.gpu_timestamp_active_slot]
		readback.dynamic_resolution_generation = renderer.dynamic_resolution.generation
	}
	return scale
}

wgpu_dynamic_resolution_accumulate_sample :: proc(
	renderer: ^WGPU_Renderer,
	generation: u64,
	frame_index: u64,
	frame_ms, ui_ms: f64,
) {
	if renderer == nil ||
	   !renderer.dynamic_resolution.initialized ||
	   generation != renderer.dynamic_resolution.generation ||
	   renderer.gpu_timestamp_resolution_sample_count >=
		   len(renderer.gpu_timestamp_resolution_samples) {
		return
	}
	renderer.gpu_timestamp_sample_serial += 1
	index := renderer.gpu_timestamp_resolution_sample_count
	renderer.gpu_timestamp_resolution_samples[index] = {
		generation = generation,
		serial = renderer.gpu_timestamp_sample_serial,
		frame_index = frame_index,
		gpu_ms = max(frame_ms - ui_ms, 0),
	}
	renderer.gpu_timestamp_resolution_sample_count += 1
}

wgpu_render_target_layout :: proc(
	output_width, output_height: u32,
	output_viewport: ui.Rect,
	camera: shared.Camera_Component,
) -> WGPU_Render_Target_Layout {
	scale := shared.camera_resolution_scale(camera)
	render_width := max(u32(1), u32(math.round(f32(output_width) * scale)))
	render_height := max(u32(1), u32(math.round(f32(output_height) * scale)))
	if render_width == output_width && render_height == output_height {
		return {
			output_width = output_width,
			output_height = output_height,
			render_width = render_width,
			render_height = render_height,
			output_viewport = output_viewport,
			render_viewport = output_viewport,
			resolution_scale = scale,
		}
	}
	scale_x := f32(render_width) / f32(max(output_width, u32(1)))
	scale_y := f32(render_height) / f32(max(output_height, u32(1)))
	x0 := clamp(math.floor(output_viewport.x * scale_x), 0, f32(render_width - 1))
	y0 := clamp(math.floor(output_viewport.y * scale_y), 0, f32(render_height - 1))
	x1 := clamp(
		math.ceil((output_viewport.x + output_viewport.width) * scale_x),
		x0 + 1,
		f32(render_width),
	)
	y1 := clamp(
		math.ceil((output_viewport.y + output_viewport.height) * scale_y),
		y0 + 1,
		f32(render_height),
	)
	return {
		output_width = output_width,
		output_height = output_height,
		render_width = render_width,
		render_height = render_height,
		output_viewport = output_viewport,
		render_viewport = {x = x0, y = y0, width = x1 - x0, height = y1 - y0},
		resolution_scale = scale,
	}
}

wgpu_release_render_depth :: proc(renderer: ^WGPU_Renderer) {
	if renderer.render_depth_view != nil {
		wgpu.TextureViewRelease(renderer.render_depth_view)
		renderer.render_depth_view = nil
	}
	if renderer.render_depth_texture != nil {
		wgpu.TextureRelease(renderer.render_depth_texture)
		renderer.render_depth_texture = nil
	}
	renderer.render_depth_width = 0
	renderer.render_depth_height = 0
}

wgpu_render_depth_view :: proc(
	renderer: ^WGPU_Renderer,
	output_depth_view: wgpu.TextureView,
	output_width, output_height: u32,
	render_width, render_height: u32,
) -> (
	wgpu.TextureView,
	string,
) {
	if render_width == output_width && render_height == output_height {
		if renderer.render_depth_view != nil {
			wgpu_release_post_targets(renderer)
			wgpu_release_render_depth(renderer)
		}
		return output_depth_view, ""
	}
	if renderer.render_depth_view != nil &&
	   renderer.render_depth_width == render_width &&
	   renderer.render_depth_height == render_height {
		return renderer.render_depth_view, ""
	}
	wgpu_release_post_targets(renderer)
	wgpu_release_render_depth(renderer)
	texture, view, err := wgpu_create_depth_texture(renderer, render_width, render_height)
	if err != "" {
		return nil, err
	}
	renderer.render_depth_texture = texture
	renderer.render_depth_view = view
	renderer.render_depth_width = render_width
	renderer.render_depth_height = render_height
	return view, ""
}

wgpu_profile_compute_workload :: proc(
	enabled: bool,
	width, height, passes, samples_per_pixel: u32,
) -> Profile_Pass_Workload {
	if !enabled || width == 0 || height == 0 || passes == 0 {
		return {}
	}
	workgroups_per_pass := u64((width + 7) / 8) * u64((height + 7) / 8)
	return {
		enabled = true,
		width = width,
		height = height,
		passes = passes,
		workgroups = workgroups_per_pass * u64(passes),
		invocations = workgroups_per_pass * u64(passes) * 64,
		samples_per_pixel = samples_per_pixel,
	}
}

wgpu_profile_workload :: proc(
	renderer: ^WGPU_Renderer,
	world: ^World,
	viewport: ui.Rect,
	width, height: u32,
	output_width, output_height: u32,
	cluster_dispatched: bool,
	stats: ^Render_Stats,
	render_feature_overrides: Render_Feature_Overrides,
) -> Profile_Workload {
	if renderer == nil {
		return {}
	}
	camera := shared.camera_defaults()
	if renderer.render_list.has_camera {
		camera = renderer.render_list.camera.camera
	}
	camera = apply_render_feature_overrides(camera, render_feature_overrides)
	viewport_width := u32(max(viewport.width, 0))
	viewport_height := u32(max(viewport.height, 0))
	batches := u64(0)
	geometry_draws := u64(0)
	visible_instances := u64(0)
	shadow_instances := u64(0)
	if stats != nil {
		batches = u64(max(stats.draw_batches, 0))
		geometry_draws = batches
		if stats.meshlet_culling {
			geometry_draws = u64(max(stats.meshlet_draws, 0))
		}
		visible_instances = u64(stats.visible_instances)
		shadow_instances = u64(stats.shadow_visible_instances)
	}
	instance_expansion := Profile_Pass_Workload{}
	if len(renderer.gpu_transform_updates) > 1 {
		update_count := u64(len(renderer.gpu_transform_updates) - 1)
		instance_expansion = {
			enabled = true,
			passes = 1,
			workgroups = (update_count + 63) / 64,
			invocations = ((update_count + 63) / 64) * 64,
			instances = update_count,
		}
	}
	cull := Profile_Pass_Workload{}
	if stats != nil && stats.compute_culling && renderer.gpu_slot_count > 0 {
		cull = {
			enabled = true,
			passes = 1,
			workgroups = u64((renderer.gpu_slot_count + 63) / 64) * u64(WGPU_SHADOW_CASCADE_COUNT),
			invocations = u64(
				(renderer.gpu_slot_count + 63) / 64,
			) * u64(WGPU_SHADOW_CASCADE_COUNT) * 64,
			instances = u64(renderer.gpu_slot_count),
		}
	}
	clustered := Profile_Pass_Workload{}
	if cluster_dispatched {
		clustered = {
			enabled = true,
			passes = 1,
			workgroups = u64((WGPU_CLUSTER_COUNT + 63) / 64),
			invocations = u64((WGPU_CLUSTER_COUNT + 63) / 64) * 64,
			instances = u64(renderer.gpu_clustered_light_count),
		}
	}
	shadow := Profile_Pass_Workload{}
	shadow_cascades := u32(0)
	if renderer.render_list.directional_light_count > 0 {
		shadow_cascades = WGPU_SHADOW_CASCADE_COUNT
		shadow = {
			enabled = true,
			width = WGPU_SHADOW_MAP_SIZE,
			height = WGPU_SHADOW_MAP_SIZE,
			passes = shadow_cascades,
			draws = geometry_draws * u64(shadow_cascades),
			instances = shadow_instances,
		}
	}
	hiz_workgroups: u64
	hiz_invocations: u64
	hiz_width, hiz_height := viewport_width, viewport_height
	for _ in 0 ..< max(renderer.gpu_hiz_mip_count, 0) {
		groups := u64((max(hiz_width, u32(1)) + 7) / 8) * u64((max(hiz_height, u32(1)) + 7) / 8)
		hiz_workgroups += groups
		hiz_invocations += groups * 64
		hiz_width = max(hiz_width / 2, 1)
		hiz_height = max(hiz_height / 2, 1)
	}
	hiz := Profile_Pass_Workload{}
	if renderer.gpu_hiz_mip_count > 0 {
		hiz = {
			enabled = true,
			width = viewport_width,
			height = viewport_height,
			passes = u32(renderer.gpu_hiz_mip_count),
			workgroups = hiz_workgroups,
			invocations = hiz_invocations,
		}
	}
	fog := wgpu_volumetric_fog_settings(world)
	if render_feature_overrides.disable_volumetric_fog {
		fog.density = 0
	}
	ao_width := max(u32(1), (width + 1) / 2)
	ao_height := max(u32(1), (height + 1) / 2)
	fog_width := max(u32(1), (width + 1) / 2)
	fog_height := max(u32(1), (height + 1) / 2)
	bloom_workgroups: u64
	bloom_invocations: u64
	for index in 0 ..< WGPU_BLOOM_LEVELS {
		level_width := max(u32(1), width >> u32(index + 1))
		level_height := max(u32(1), height >> u32(index + 1))
		groups := u64((level_width + 7) / 8) * u64((level_height + 7) / 8)
		bloom_workgroups += groups
		bloom_invocations += groups * 64
	}
	bloom := Profile_Pass_Workload{}
	if camera.bloom {
		bloom = {
			enabled = true,
			width = max(width / 2, 1),
			height = max(height / 2, 1),
			passes = WGPU_BLOOM_LEVELS,
			workgroups = bloom_workgroups,
			invocations = bloom_invocations,
		}
	}
	ui_draws := u64(0)
	if len(renderer.ui_project_vertices) > 0 {
		ui_draws += 1
	}
	if len(renderer.ui_editor_vertices) > 0 {
		ui_draws += 1
	}
	if len(renderer.ui_overlay_vertices) > 0 {
		ui_draws += 1
	}
	return {
		instance_expansion = instance_expansion,
		cull = cull,
		clustered_lighting = clustered,
		shadow = shadow,
		depth = {
			enabled = batches > 0,
			width = viewport_width,
			height = viewport_height,
			passes = 1,
			draws = geometry_draws,
			instances = visible_instances,
		},
		world = {
			enabled = batches > 0,
			width = viewport_width,
			height = viewport_height,
			passes = 1,
			draws = geometry_draws,
			instances = visible_instances,
		},
		hiz = hiz,
		ambient_occlusion = wgpu_profile_compute_workload(
			camera.ambient_occlusion,
			ao_width,
			ao_height,
			3,
			shared.camera_ambient_occlusion_sample_count(camera),
		),
		screen_space_reflections = wgpu_profile_compute_workload(
			camera.screen_space_reflections,
			width,
			height,
			1,
			shared.camera_screen_space_reflections_sample_count(camera),
		),
		volumetric_fog = wgpu_profile_compute_workload(
			fog.density > 0,
			fog_width,
			fog_height,
			1,
			16,
		),
		temporal_aa = wgpu_profile_compute_workload(
			true,
			width,
			height,
			1,
			9 if camera.temporal_antialiasing else 1,
		),
		bloom = bloom,
		automatic_exposure = {
			enabled = camera.automatic_exposure,
			width = width,
			height = height,
			passes = 1,
			workgroups = 1 if camera.automatic_exposure else 0,
			invocations = 256 if camera.automatic_exposure else 0,
		},
		composite = {
			enabled = true,
			width = output_width,
			height = output_height,
			passes = 1,
			draws = 1,
		},
		ui = {
			enabled = ui_draws > 0,
			width = output_width,
			height = output_height,
			passes = 1,
			draws = ui_draws,
		},
	}
}

wgpu_ui_stream_key :: proc(
	revision: u64,
	target_width, target_height: u32,
	viewport: ui.Rect = {},
) -> WGPU_UI_Stream_Key {
	return {
		revision = revision,
		target_width = target_width,
		target_height = target_height,
		viewport = viewport,
	}
}

wgpu_append_ui_vertices :: proc(
	vertices: ^[dynamic]WGPU_UI_Vertex,
	commands: []ui.Paint_Command,
	editor_paint_start: int,
	ui_state: ^ui.State,
	viewport: ui.Rect,
	drawable_width, drawable_height: f32,
) {
	project_transform := ui.project_canvas_transform_in_host(ui_state, viewport)
	for command, command_index in commands {
		rect := command.rect
		radius := command.corner_radius
		clip := [4]f32{0, 0, drawable_width, drawable_height}
		project_command := command_index < editor_paint_start
		if project_command {
			rect = {
				project_transform.viewport.x + rect.x * project_transform.scale.x,
				project_transform.viewport.y + rect.y * project_transform.scale.y,
				rect.width * project_transform.scale.x,
				rect.height * project_transform.scale.y,
			}
			radius *= min(project_transform.scale.x, project_transform.scale.y)
			clip = {
				project_transform.clip.x,
				project_transform.clip.y,
				project_transform.clip.x + project_transform.clip.width,
				project_transform.clip.y + project_transform.clip.height,
			}
			if command.has_clip {
				command_clip := ui.Rect {
					project_transform.viewport.x + command.clip.x * project_transform.scale.x,
					project_transform.viewport.y + command.clip.y * project_transform.scale.y,
					command.clip.width * project_transform.scale.x,
					command.clip.height * project_transform.scale.y,
				}
				command_clip = ui.rect_intersection(command_clip, project_transform.clip)
				clip = {
					command_clip.x,
					command_clip.y,
					command_clip.x + command_clip.width,
					command_clip.y + command_clip.height,
				}
			}
		} else if command.has_clip {
			clip = {
				command.clip.x,
				command.clip.y,
				command.clip.x + command.clip.width,
				command.clip.y + command.clip.height,
			}
		}
		positions: [4][2]f32
		shape_width, shape_height := rect.width, rect.height
		if command.kind == .Line {
			line_start, line_end := command.line_start, command.line_end
			line_thickness := command.line_thickness
			if project_command {
				line_start = {
					project_transform.viewport.x + line_start.x * project_transform.scale.x,
					project_transform.viewport.y + line_start.y * project_transform.scale.y,
				}
				line_end = {
					project_transform.viewport.x + line_end.x * project_transform.scale.x,
					project_transform.viewport.y + line_end.y * project_transform.scale.y,
				}
				line_thickness *= min(project_transform.scale.x, project_transform.scale.y)
			}
			dx := line_end.x - line_start.x
			dy := line_end.y - line_start.y
			line_length := math.sqrt(dx * dx + dy * dy)
			if line_length <= 0.0001 {
				line_length = 0.0001
			}
			half := line_thickness * 0.5
			px := -dy / line_length * half
			py := dx / line_length * half
			points := [4]shared.Vec2 {
				{line_start.x - px, line_start.y - py},
				{line_end.x - px, line_end.y - py},
				{line_end.x + px, line_end.y + py},
				{line_start.x + px, line_start.y + py},
			}
			for point, index in points {
				positions[index] = {
					point.x / drawable_width * 2 - 1,
					1 - point.y / drawable_height * 2,
				}
			}
			shape_width = line_length
			shape_height = line_thickness
		} else if command.kind == .Triangle {
			for point, index in command.triangle {
				positions[index] = {
					point.x / drawable_width * 2 - 1,
					1 - point.y / drawable_height * 2,
				}
			}
			positions[3] = positions[2]
			shape_width = 1
			shape_height = 1
		} else if command.kind == .Ring {
			center, axis_x, axis_y := command.ring_center, command.ring_axis_x, command.ring_axis_y
			extent := f32(1.0 / 0.92)
			axis_x.x *= extent
			axis_x.y *= extent
			axis_y.x *= extent
			axis_y.y *= extent
			points := [4]shared.Vec2 {
				{center.x - axis_x.x - axis_y.x, center.y - axis_x.y - axis_y.y},
				{center.x + axis_x.x - axis_y.x, center.y + axis_x.y - axis_y.y},
				{center.x + axis_x.x + axis_y.x, center.y + axis_x.y + axis_y.y},
				{center.x - axis_x.x + axis_y.x, center.y - axis_x.y + axis_y.y},
			}
			for point, index in points {
				positions[index] = {
					point.x / drawable_width * 2 - 1,
					1 - point.y / drawable_height * 2,
				}
			}
			shape_width = math.sqrt(axis_x.x * axis_x.x + axis_x.y * axis_x.y) * 2
			shape_height = math.sqrt(axis_y.x * axis_y.x + axis_y.y * axis_y.y) * 2
			radius = command.ring_thickness
		} else {
			x0 := rect.x / drawable_width * 2 - 1
			x1 := (rect.x + rect.width) / drawable_width * 2 - 1
			y0 := 1 - rect.y / drawable_height * 2
			y1 := 1 - (rect.y + rect.height) / drawable_height * 2
			positions = {{x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}}
		}
		u0, v0, u1, v1 := command.uv.x, command.uv.y, command.uv.z, command.uv.w
		kind := f32(0)
		if command.kind == .Glyph || command.kind == .Icon {
			kind = 1
		} else if command.kind == .Triangle {
			kind = 2
		} else if command.kind == .Ring {
			kind = 3
		} else if command.kind == .Disclosure {
			kind = 4
			if command.disclosure_expanded {
				radius = -radius
			}
		} else if command.kind == .Checkmark {
			kind = 5
		} else if command.kind == .Viewport {
			kind = 6
		}
		if command.kind == .Panel ||
		   command.kind == .Line ||
		   command.kind == .Triangle ||
		   command.kind == .Ring ||
		   command.kind == .Disclosure ||
		   command.kind == .Checkmark {
			u0 = 0
			v0 = 0
			u1 = 1
			v1 = 1
		}
		colors := [4][4]f32 {
			{command.color.x, command.color.y, command.color.z, command.color.w},
			{command.color.x, command.color.y, command.color.z, command.color.w},
			{command.color.x, command.color.y, command.color.z, command.color.w},
			{command.color.x, command.color.y, command.color.z, command.color.w},
		}
		if command.gradient {
			for corner, index in command.corner_colors {
				colors[index] = {corner.x, corner.y, corner.z, corner.w}
			}
		}
		border_color := [4]f32 {
			command.border_color.x,
			command.border_color.y,
			command.border_color.z,
			command.border_color.w,
		}
		border_width := command.border_width
		if project_command {
			border_width *= min(project_transform.scale.x, project_transform.scale.y)
		}
		params := [3]f32{shape_width, shape_height, radius}
		append(
			vertices,
			WGPU_UI_Vertex {
				position = positions[0],
				uv = {u0, v0},
				color = colors[0],
				kind = kind,
				size_radius = params,
				clip = clip,
				border_color = border_color,
				border_width = border_width,
				font_layer = command.font_layer,
			},
			WGPU_UI_Vertex {
				position = positions[1],
				uv = {u1, v0},
				color = colors[1],
				kind = kind,
				size_radius = params,
				clip = clip,
				border_color = border_color,
				border_width = border_width,
				font_layer = command.font_layer,
			},
			WGPU_UI_Vertex {
				position = positions[2],
				uv = {u1, v1},
				color = colors[2],
				kind = kind,
				size_radius = params,
				clip = clip,
				border_color = border_color,
				border_width = border_width,
				font_layer = command.font_layer,
			},
			WGPU_UI_Vertex {
				position = positions[0],
				uv = {u0, v0},
				color = colors[0],
				kind = kind,
				size_radius = params,
				clip = clip,
				border_color = border_color,
				border_width = border_width,
				font_layer = command.font_layer,
			},
			WGPU_UI_Vertex {
				position = positions[2],
				uv = {u1, v1},
				color = colors[2],
				kind = kind,
				size_radius = params,
				clip = clip,
				border_color = border_color,
				border_width = border_width,
				font_layer = command.font_layer,
			},
			WGPU_UI_Vertex {
				position = positions[3],
				uv = {u0, v1},
				color = colors[3],
				kind = kind,
				size_radius = params,
				clip = clip,
				border_color = border_color,
				border_width = border_width,
				font_layer = command.font_layer,
			},
		)
	}
}

wgpu_upload_ui_vertices :: proc(
	renderer: ^WGPU_Renderer,
	vertices: []WGPU_UI_Vertex,
	vertex_buffer: ^wgpu.Buffer,
	vertex_capacity: ^int,
	label: string,
) -> bool {
	// Empty retained UI is a valid transition (for example when editor chrome
	// closes while the previous frame still has dynamic world overlays). There
	// is nothing to upload, and callers already skip the zero-vertex draw.
	if len(vertices) == 0 {
		return true
	}
	if renderer == nil || vertex_buffer == nil || vertex_capacity == nil {
		return false
	}
	if vertex_buffer^ == nil || vertex_capacity^ < len(vertices) {
		if vertex_buffer^ != nil {
			wgpu.BufferRelease(vertex_buffer^)
		}
		vertex_capacity^ = max(len(vertices), max(vertex_capacity^ * 2, 256))
		vertex_buffer^ = wgpu.DeviceCreateBuffer(
			renderer.device,
			&wgpu.BufferDescriptor {
				label = label,
				usage = {.Vertex, .CopyDst},
				size = u64(vertex_capacity^ * size_of(WGPU_UI_Vertex)),
			},
		)
		if vertex_buffer^ == nil {
			vertex_capacity^ = 0
			return false
		}
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		vertex_buffer^,
		0,
		raw_data(vertices),
		uint(len(vertices) * size_of(WGPU_UI_Vertex)),
	)
	renderer.ui_vertex_upload_count += 1
	renderer.ui_vertex_upload_bytes += u64(len(vertices) * size_of(WGPU_UI_Vertex))
	return true
}

wgpu_rebuild_ui_vertex_stream :: proc(
	renderer: ^WGPU_Renderer,
	vertices: ^[dynamic]WGPU_UI_Vertex,
	commands: []ui.Paint_Command,
	project: bool,
	ui_state: ^ui.State,
	viewport: ui.Rect,
	drawable_width, drawable_height: f32,
	vertex_buffer: ^wgpu.Buffer,
	vertex_capacity: ^int,
	label: string,
) -> bool {
	clear(vertices)
	project_command_count := 0
	if project {
		project_command_count = len(commands)
	}
	wgpu_append_ui_vertices(
		vertices,
		commands,
		project_command_count,
		ui_state,
		viewport,
		drawable_width,
		drawable_height,
	)
	return wgpu_upload_ui_vertices(renderer, vertices^[:], vertex_buffer, vertex_capacity, label)
}

wgpu_next_frame_delta :: proc(previous_tick: ^time.Tick, has_previous_frame: bool) -> f32 {
	now := time.tick_now()
	delta_time := f32(1.0 / 60.0)
	if has_previous_frame {
		duration := time.tick_diff(previous_tick^, now)
		delta_time = f32(f64(duration) / 1_000_000_000.0)
		if delta_time <= 0 { delta_time = 1.0 / 60.0 }
	}
	previous_tick^ = now
	return min(delta_time, ecs.MAX_DELTA_TIME)
}

wgpu_live_resize_redraw :: proc "c" (userdata: rawptr) {
	context = base_runtime.default_context()
	state := cast(^WGPU_Live_Resize_State)userdata
	if state == nil || state.drawing || state.should_quit || state.err != "" { return }
	if state.config.max_frames != 0 && state.frame_count^ >= state.config.max_frames { return }

	state.drawing = true
	defer state.drawing = false
	delta_time := wgpu_next_frame_delta(state.previous_tick, state.frame_count^ > 0)
	_, state.should_quit, state.err = wgpu_draw_frame(
		state.renderer,
		state.world,
		state.config,
		delta_time,
		false,
	)
	if state.err == "" && !state.should_quit {
		state.frame_count^ += 1
	}
}

wgpu_material_cache :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
	handle: shared.Material_Handle,
) -> (
	^WGPU_Material_Cache,
	string,
) {
	material, ok := resources.get_material(registry, handle)
	if !ok { return nil, "render material handle is stale" }
	texture_version: u32
	if material.desc.texture != (shared.Texture_Handle{}) {
		texture_resource, texture_ok := resources.get_texture(registry, material.desc.texture)
		if !texture_ok {
			return nil, "render material texture handle is stale"
		}
		texture_version = texture_resource.version
	}
	cache_index := wgpu_material_cache_slot(renderer.material_cache[:], handle)
	if cache_index < 0 {
		cache_index = len(renderer.material_cache)
		append(&renderer.material_cache, WGPU_Material_Cache{})
	}
	cached := &renderer.material_cache[cache_index]
	if cached.valid &&
	   cached.handle == handle &&
	   cached.version == material.version &&
	   cached.texture_handle == material.desc.texture &&
	   cached.texture_version == texture_version {
		return cached, ""
	}
	wgpu_release_material_cache_entry(cached)
	cached^ = {
		handle = handle,
		version = material.version,
		texture_handle = material.desc.texture,
		texture_version = texture_version,
		double_sided = material.desc.double_sided,
	}
	if material.desc.texture != (shared.Texture_Handle{}) {
		texture_cached, texture_err := wgpu_texture_cache(
			renderer,
			registry,
			material.desc.texture,
		)
		if texture_err != "" {
			return nil, texture_err
		}
		cached.textures[0] = texture_cached.texture
		cached.views[0] = texture_cached.view
	} else if len(material.desc.texture_pixels) > 0 {
		base_image := resources.Material_Image {
			pixels = material.desc.texture_pixels,
			width = material.desc.texture_width,
			height = material.desc.texture_height,
			mip_count = material.desc.texture_mip_count,
			color_space = .SRGB,
		}
		texture, view, texture_err := wgpu_create_material_image(
			renderer,
			base_image,
			{255, 255, 255, 255},
			"Scrapbot Base Color Texture",
		)
		if texture_err != "" {
			return nil, texture_err
		}
		cached.textures[0] = texture
		cached.views[0] = view
		cached.owns_texture[0] = true
	} else {
		cached.textures[0] = renderer.material_fallback_textures[0]
		cached.views[0] = renderer.material_fallback_views[0]
	}
	images := [?]resources.Material_Image {
		material.desc.metallic_roughness_image,
		material.desc.normal_image,
		material.desc.occlusion_image,
		material.desc.emissive_image,
	}
	samplers := [?]shared.Texture_Sampler {
		material.desc.texture_sampler,
		material.desc.metallic_roughness_image.sampler,
		material.desc.normal_image.sampler,
		material.desc.occlusion_image.sampler,
		material.desc.emissive_image.sampler,
	}
	for sampler, sampler_index in samplers {
		cached.samplers[sampler_index] = wgpu_create_material_sampler(renderer, sampler)
		if cached.samplers[sampler_index] == nil {
			wgpu_release_material_cache_entry(cached)
			return nil, "failed to create material texture sampler"
		}
	}
	fallbacks := [?][4]u8 {
		{255, 255, 255, 255},
		{128, 128, 255, 255},
		{255, 255, 255, 255},
		{0, 0, 0, 255},
	}
	labels := [?]string {
		"Scrapbot Metallic Roughness Texture",
		"Scrapbot Normal Texture",
		"Scrapbot Occlusion Texture",
		"Scrapbot Emissive Texture",
	}
	for image, image_index in images {
		cache_index := image_index + 1
		if len(image.pixels) == 0 {
			cached.textures[cache_index] = renderer.material_fallback_textures[cache_index]
			cached.views[cache_index] = renderer.material_fallback_views[cache_index]
			continue
		}
		texture, view, image_err := wgpu_create_material_image(
			renderer,
			image,
			fallbacks[image_index],
			labels[image_index],
		)
		if image_err != "" {
			wgpu_release_material_cache_entry(cached)
			return nil, image_err
		}
		cached.textures[cache_index] = texture
		cached.views[cache_index] = view
		cached.owns_texture[cache_index] = true
	}
	material_uniform := WGPU_Material_Uniform {
		pbr_factors = {
			material.desc.metallic_factor,
			material.desc.roughness_factor,
			material.desc.normal_scale,
			material.desc.occlusion_strength,
		},
		flags = {
			1 if len(material.desc.emissive_image.pixels) > 0 else 0,
			1 if material.desc.pbr else 0,
			1 if material.desc.alpha_mode == .Mask else 0,
			1 if material.desc.double_sided else 0,
		},
		alpha = {
			material.desc.alpha_cutoff,
			1 if len(material.desc.normal_image.pixels) > 0 else 0,
			0,
			0,
		},
	}
	cached.uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Material Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Material_Uniform)),
		},
	)
	if cached.uniform_buffer == nil {
		wgpu_release_material_cache_entry(cached)
		return nil, "failed to create material uniform buffer"
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		cached.uniform_buffer,
		0,
		&material_uniform,
		uint(size_of(WGPU_Material_Uniform)),
	)
	entries := [?]wgpu.BindGroupEntry {
		{binding = 0, textureView = cached.views[0]},
		{binding = 1, sampler = cached.samplers[0]},
		{binding = 2, textureView = cached.views[1]},
		{binding = 3, textureView = cached.views[2]},
		{binding = 4, textureView = cached.views[3]},
		{binding = 5, textureView = cached.views[4]},
		{binding = 6, buffer = cached.uniform_buffer, size = u64(size_of(WGPU_Material_Uniform))},
		{binding = 7, sampler = cached.samplers[1]},
		{binding = 8, sampler = cached.samplers[2]},
		{binding = 9, sampler = cached.samplers[3]},
		{binding = 10, sampler = cached.samplers[4]},
	}
	cached.bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Material Bind Group",
			layout = renderer.material_bind_group_layout,
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
	if cached.bind_group == nil {
		wgpu_release_material_cache_entry(cached)
		return nil, "failed to create material bind group"
	}
	cached.valid = true
	return cached, ""
}

wgpu_release_material_cache_entry :: proc(cached: ^WGPU_Material_Cache) {
	if cached == nil {
		return
	}
	if cached.bind_group != nil {
		wgpu.BindGroupRelease(cached.bind_group)
	}
	if cached.uniform_buffer != nil {
		wgpu.BufferRelease(cached.uniform_buffer)
	}
	for sampler in cached.samplers {
		if sampler != nil {
			wgpu.SamplerRelease(sampler)
		}
	}
	for owns, index in cached.owns_texture {
		if !owns {
			continue
		}
		if cached.views[index] != nil {
			wgpu.TextureViewRelease(cached.views[index])
		}
		if cached.textures[index] != nil {
			wgpu.TextureRelease(cached.textures[index])
		}
	}
	cached.bind_group = nil
	cached.uniform_buffer = nil
	cached.textures = {}
	cached.views = {}
	cached.samplers = {}
	cached.owns_texture = {}
}

wgpu_create_material_sampler :: proc(
	renderer: ^WGPU_Renderer,
	desc: shared.Texture_Sampler,
) -> wgpu.Sampler {
	mag_filter: wgpu.FilterMode = .Linear
	if desc.mag_filter == .Nearest {
		mag_filter = .Nearest
	}
	min_filter: wgpu.FilterMode = .Linear
	if desc.min_filter == .Nearest {
		min_filter = .Nearest
	}
	mipmap_filter: wgpu.MipmapFilterMode = .Linear
	if desc.mipmap_filter == .Nearest || desc.mipmap_filter == .Base_Only {
		mipmap_filter = .Nearest
	}
	address_u: wgpu.AddressMode = .Repeat
	#partial switch desc.address_u {
		case .Clamp_To_Edge:
			address_u = .ClampToEdge
		case .Mirrored_Repeat:
			address_u = .MirrorRepeat
		case .Default, .Repeat:
			address_u = .Repeat
	}
	address_v: wgpu.AddressMode = .Repeat
	#partial switch desc.address_v {
		case .Clamp_To_Edge:
			address_v = .ClampToEdge
		case .Mirrored_Repeat:
			address_v = .MirrorRepeat
		case .Default, .Repeat:
			address_v = .Repeat
	}
	max_lod := f32(32)
	if desc.mipmap_filter == .Base_Only {
		max_lod = 0
	}
	max_anisotropy := wgpu_material_sampler_anisotropy(desc)
	return wgpu.DeviceCreateSampler(
		renderer.device,
		&wgpu.SamplerDescriptor {
			label = "Scrapbot Material Texture Sampler",
			addressModeU = address_u,
			addressModeV = address_v,
			addressModeW = .Repeat,
			magFilter = mag_filter,
			minFilter = min_filter,
			mipmapFilter = mipmap_filter,
			lodMaxClamp = max_lod,
			maxAnisotropy = max_anisotropy,
		},
	)
}

wgpu_material_sampler_anisotropy :: proc(desc: shared.Texture_Sampler) -> u16 {
	if desc.mag_filter == .Nearest ||
	   desc.min_filter == .Nearest ||
	   desc.mipmap_filter == .Nearest ||
	   desc.mipmap_filter == .Base_Only {
		return 1
	}
	return 8
}

wgpu_create_material_image :: proc(
	renderer: ^WGPU_Renderer,
	image: resources.Material_Image,
	fallback: [4]u8,
	label: string,
) -> (
	texture: wgpu.Texture,
	view: wgpu.TextureView,
	err: string,
) {
	width, height, mip_count := image.width, image.height, image.mip_count
	pixels := image.pixels
	fallback_pixels := fallback
	if len(pixels) == 0 {
		width, height, mip_count = 1, 1, 1
		pixels = fallback_pixels[:]
	}
	format: wgpu.TextureFormat = .RGBA8UnormSrgb
	if image.color_space == .Linear {
		format = .RGBA8Unorm
	}
	texture = wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label = label,
			usage = {.TextureBinding, .CopyDst},
			dimension = ._2D,
			size = {width = width, height = height, depthOrArrayLayers = 1},
			format = format,
			mipLevelCount = mip_count,
			sampleCount = 1,
		},
	)
	if texture == nil {
		return nil, nil, fmt.tprintf("failed to create %s", label)
	}
	offset := 0
	mip_width, mip_height := width, height
	for level in 0 ..< mip_count {
		byte_count := int(mip_width * mip_height * 4)
		level_pixels := pixels[offset:offset + byte_count]
		wgpu.QueueWriteTexture(
			renderer.queue,
			&wgpu.TexelCopyTextureInfo{texture = texture, mipLevel = level, aspect = .All},
			raw_data(level_pixels),
			uint(len(level_pixels)),
			&wgpu.TexelCopyBufferLayout{bytesPerRow = mip_width * 4, rowsPerImage = mip_height},
			&wgpu.Extent3D{width = mip_width, height = mip_height, depthOrArrayLayers = 1},
		)
		offset += byte_count
		mip_width = max(mip_width / 2, 1)
		mip_height = max(mip_height / 2, 1)
	}
	view = wgpu.TextureCreateView(texture)
	if view == nil {
		wgpu.TextureRelease(texture)
		return nil, nil, fmt.tprintf("failed to create %s view", label)
	}
	return texture, view, ""
}

wgpu_texture_cache :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
	handle: shared.Texture_Handle,
) -> (
	^WGPU_Texture_Cache,
	string,
) {
	texture_resource, ok := resources.get_texture(registry, handle)
	if !ok {
		return nil, "render texture handle is stale"
	}
	cache_index := wgpu_texture_cache_slot(renderer.texture_cache[:], handle)
	if cache_index < 0 {
		cache_index = len(renderer.texture_cache)
		append(&renderer.texture_cache, WGPU_Texture_Cache{})
	}
	cached := &renderer.texture_cache[cache_index]
	if cached.valid && cached.handle == handle && cached.version == texture_resource.version {
		return cached, ""
	}
	if cached.view != nil {
		wgpu.TextureViewRelease(cached.view)
	}
	if cached.texture != nil {
		wgpu.TextureRelease(cached.texture)
	}
	cached^ = {
		handle = handle,
		version = texture_resource.version,
	}
	format: wgpu.TextureFormat = .RGBA8UnormSrgb
	if texture_resource.desc.color_space == .Linear {
		format = .RGBA8Unorm
	}
	cached.texture = wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label = "Scrapbot Texture Resource",
			usage = {.TextureBinding, .CopyDst},
			dimension = ._2D,
			size = {
				width = texture_resource.desc.width,
				height = texture_resource.desc.height,
				depthOrArrayLayers = 1,
			},
			format = format,
			mipLevelCount = texture_resource.desc.mip_count,
			sampleCount = 1,
		},
	)
	if cached.texture == nil {
		return nil, "failed to create texture resource"
	}
	offset := 0
	width, height := texture_resource.desc.width, texture_resource.desc.height
	for level in 0 ..< texture_resource.desc.mip_count {
		byte_count := int(width * height * 4)
		level_pixels := texture_resource.desc.pixels[offset:offset + byte_count]
		wgpu.QueueWriteTexture(
			renderer.queue,
			&wgpu.TexelCopyTextureInfo{texture = cached.texture, mipLevel = level, aspect = .All},
			raw_data(level_pixels),
			uint(len(level_pixels)),
			&wgpu.TexelCopyBufferLayout{bytesPerRow = width * 4, rowsPerImage = height},
			&wgpu.Extent3D{width = width, height = height, depthOrArrayLayers = 1},
		)
		offset += byte_count
		width = max(width / 2, 1)
		height = max(height / 2, 1)
	}
	cached.view = wgpu.TextureCreateView(cached.texture)
	if cached.view == nil {
		return nil, "failed to create texture resource view"
	}
	cached.valid = true
	return cached, ""
}

WGPU_OFFSCREEN_WIDTH :: u32(1280)
WGPU_OFFSCREEN_HEIGHT :: u32(720)
WGPU_SHADOW_MAP_SIZE :: u32(2048)

wgpu_rebuild_draw_batch_cache :: proc(
	cache: ^WGPU_Draw_Batch_Cache,
	render_list: ^Render_List,
	registry: ^resources.Registry = nil,
) {
	if cache == nil || render_list == nil {
		return
	}
	wgpu_release_batch_bind_groups(cache)
	rebuild_count := cache.rebuild_count + 1
	source_indices := cache.source_indices
	batches := cache.batches
	clear(&source_indices)
	clear(&batches)
	cache^ = {
		world_uuid = render_list.world_uuid,
		topology_revision = render_list.topology_revision,
		geometry_topology_revision = registry.geometry_topology_revision if registry != nil else 0,
		valid = true,
		rebuild_count = rebuild_count,
		source_indices = source_indices,
		batches = batches,
	}
	for candidate in render_list.instances {
		handles: [shared.MAX_GEOMETRY_LODS]shared.Geometry_Handle
		handles[0] = candidate.geometry.handle
		handle_count := 1
		if geometry, alive := resources.get_geometry(registry, candidate.geometry.handle); alive {
			for handle in geometry.lod_handles[:geometry.lod_count] {
				handles[handle_count] = handle
				handle_count += 1
			}
		}
		for handle in handles[:handle_count] {
			found := false
			for batch_index in 0 ..< cache.batch_count {
				batch := cache.batches[batch_index]
				if batch.geometry == handle && batch.material == candidate.material.handle {
					found = true
					break
				}
			}
			if found {
				continue
			}
			append(
				&cache.batches,
				WGPU_Draw_Batch{geometry = handle, material = candidate.material.handle},
			)
			cache.batch_count += 1
		}
	}
	for batch_index in 0 ..< cache.batch_count {
		batch := &cache.batches[batch_index]
		batch.first_instance = u32(cache.instance_count)
		for candidate, source_index in render_list.instances {
			if candidate.material.handle != batch.material {
				continue
			}
			matches := candidate.geometry.handle == batch.geometry
			if !matches {
				if geometry, alive := resources.get_geometry(registry, candidate.geometry.handle);
				   alive {
					for handle in geometry.lod_handles[:geometry.lod_count] {
						if handle == batch.geometry {
							matches = true
							break
						}
					}
				}
			}
			if !matches {
				continue
			}
			append(&cache.source_indices, source_index)
			cache.instance_count += 1
			batch.instance_count += 1
		}
	}
}

wgpu_ensure_draw_batch_cache :: proc(
	renderer: ^WGPU_Renderer,
	render_list: ^Render_List,
	registry: ^resources.Registry = nil,
) -> ^WGPU_Draw_Batch_Cache {
	if renderer == nil || render_list == nil {
		return nil
	}
	cache := &renderer.draw_batch_cache
	if !cache.valid ||
	   cache.world_uuid != render_list.world_uuid ||
	   cache.topology_revision != render_list.topology_revision ||
	   (registry != nil &&
			   cache.geometry_topology_revision != registry.geometry_topology_revision) {
		wgpu_rebuild_draw_batch_cache(cache, render_list, registry)
	}
	return cache
}

wgpu_geometry_cache :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
	handle: shared.Geometry_Handle,
) -> (
	^WGPU_Geometry_Cache,
	string,
) {
	geometry, ok := resources.get_geometry(registry, handle)
	if !ok { return nil, "render geometry handle is stale" }
	cache_index := wgpu_geometry_cache_slot(renderer.geometry_cache[:], handle)
	if cache_index < 0 {
		cache_index = len(renderer.geometry_cache)
		append(&renderer.geometry_cache, WGPU_Geometry_Cache{})
	}
	cached := &renderer.geometry_cache[cache_index]
	if cached.valid && cached.handle == handle && cached.version == geometry.version {
		return cached, ""
	}
	if cached.vertex_buffer != nil { wgpu.BufferRelease(cached.vertex_buffer) }
	if cached.index_buffer != nil { wgpu.BufferRelease(cached.index_buffer) }
	if cached.meshlet_index_buffer != nil { wgpu.BufferRelease(cached.meshlet_index_buffer) }
	cached^ = {
		handle = handle,
		version = geometry.version,
		index_count = u32(len(geometry.indices)),
	}
	cached.vertex_buffer = wgpu.DeviceCreateBufferWithData(
		renderer.device,
		&wgpu.BufferWithDataDescriptor{label = "Scrapbot Geometry Vertices", usage = {.Vertex}},
		geometry.vertices,
	)
	cached.index_buffer = wgpu.DeviceCreateBufferWithData(
		renderer.device,
		&wgpu.BufferWithDataDescriptor{label = "Scrapbot Geometry Indices", usage = {.Index}},
		geometry.indices,
	)
	if renderer.gpu_meshlet_supported {
		meshlet_indices, meshlet_err := wgpu_expand_meshlet_indices(geometry)
		if meshlet_err != "" {
			return nil, meshlet_err
		}
		cached.meshlet_index_buffer = wgpu.DeviceCreateBufferWithData(
			renderer.device,
			&wgpu.BufferWithDataDescriptor {
				label = "Scrapbot Geometry Meshlet Indices",
				usage = {.Index},
			},
			meshlet_indices,
		)
	}
	if cached.vertex_buffer == nil ||
	   cached.index_buffer == nil ||
	   (renderer.gpu_meshlet_supported && cached.meshlet_index_buffer == nil) {
		return nil, "failed to upload geometry buffers"
	}
	cached.valid = true
	return cached, ""
}

wgpu_encode_render_pass :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	color_view: wgpu.TextureView,
	output_depth_view: wgpu.TextureView,
	render_depth_view: wgpu.TextureView,
	batches: []WGPU_Draw_Batch,
	registry: ^resources.Registry,
	world: ^World,
	ui_state: ^ui.State,
	config: ^Run_Config,
	label: string,
	layout: WGPU_Render_Target_Layout,
	delta_time: f32,
) -> string {
	world_start := time.tick_now()
	if err := wgpu_sync_ui_fonts(renderer, registry); err != "" { return err }
	if err := wgpu_sync_environment(renderer, registry, &renderer.render_list); err != "" {
		return err
	}
	if err := wgpu_ensure_post_targets(
		renderer,
		layout.render_width,
		layout.render_height,
		render_depth_view,
	); err != "" {
		return err
	}
	if err := wgpu_encode_sky_pass(renderer, encoder, layout.render_viewport); err != "" {
		return err
	}
	color_attachments := [3]wgpu.RenderPassColorAttachment {
		{
			view = renderer.hdr_view,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			loadOp = .Load,
			storeOp = .Store,
		},
		{
			view = renderer.surface_view,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			loadOp = .Clear,
			storeOp = .Store,
			clearValue = {},
		},
		{
			view = renderer.indirect_diffuse_view,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			loadOp = .Clear,
			storeOp = .Store,
			clearValue = {},
		},
	}
	depth_attachment := wgpu.RenderPassDepthStencilAttachment {
		view = render_depth_view,
		depthLoadOp = .Load,
		depthStoreOp = .Store,
		depthClearValue = 1.0,
		stencilLoadOp = .Undefined,
		stencilStoreOp = .Undefined,
	}
	world_timestamps, world_timestamps_enabled := wgpu_gpu_pass_timestamps(renderer, .World)
	world_timestamps_ptr: ^wgpu.PassTimestampWrites
	if world_timestamps_enabled {
		world_timestamps_ptr = &world_timestamps
	}
	render_pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = label,
			colorAttachmentCount = len(color_attachments),
			colorAttachments = raw_data(color_attachments[:]),
			depthStencilAttachment = &depth_attachment,
			timestampWrites = world_timestamps_ptr,
		},
	)
	if render_pass == nil {
		return "failed to begin wgpu render pass"
	}
	defer wgpu.RenderPassEncoderRelease(render_pass)

	viewport := layout.render_viewport
	wgpu.RenderPassEncoderSetViewport(
		render_pass,
		viewport.x,
		viewport.y,
		viewport.width,
		viewport.height,
		0,
		1,
	)
	wgpu.RenderPassEncoderSetScissorRect(
		render_pass,
		u32(viewport.x),
		u32(viewport.y),
		u32(viewport.width),
		u32(viewport.height),
	)
	if len(batches) > 0 {
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 2, renderer.environment_bind_group)
		for batch, batch_index in batches {
			cached, cache_err := wgpu_geometry_cache(renderer, registry, batch.geometry)
			if cache_err != "" { return cache_err }
			material_cached, material_err := wgpu_material_cache(
				renderer,
				registry,
				batch.material,
			)
			if material_err != "" { return material_err }
			pipeline := renderer.gpu_driven_pipeline
			if material_cached.double_sided {
				pipeline = renderer.gpu_driven_double_sided_pipeline
			}
			wgpu.RenderPassEncoderSetPipeline(render_pass, pipeline)
			world_bind_group := batch.world_bind_group
			index_buffer := cached.index_buffer
			if renderer.gpu_meshlet_submission_active {
				world_bind_group = batch.meshlet_world_bind_group
				index_buffer = cached.meshlet_index_buffer
			}
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, world_bind_group)
			wgpu.RenderPassEncoderSetBindGroup(render_pass, 1, material_cached.bind_group)
			wgpu.RenderPassEncoderSetVertexBuffer(
				render_pass,
				0,
				cached.vertex_buffer,
				0,
				wgpu.WHOLE_SIZE,
			)
			wgpu.RenderPassEncoderSetIndexBuffer(
				render_pass,
				index_buffer,
				.Uint32,
				0,
				wgpu.WHOLE_SIZE,
			)
			if renderer.gpu_meshlet_submission_active {
				wgpu.RenderPassEncoderMultiDrawIndexedIndirect(
					render_pass,
					renderer.gpu_meshlet_indirect_buffer,
					u64(batch.meshlet_draw_offset) * u64(size_of(WGPU_Draw_Indexed_Indirect)),
					batch.meshlet_draw_count,
				)
			} else {
				wgpu.RenderPassEncoderDrawIndexedIndirect(
					render_pass,
					renderer.gpu_indirect_buffer,
					u64(batch_index * size_of(WGPU_Draw_Indexed_Indirect)),
				)
			}
		}
	}
	wgpu.RenderPassEncoderEnd(render_pass)
	record_system_profile_phase(config, .Render_World, world_start)
	if renderer.gpu_hiz_requested {
		if err := wgpu_encode_hiz_pyramid(renderer, encoder, render_depth_view); err != "" {
			return err
		}
	} else {
		renderer.gpu_hiz_valid = false
		renderer.gpu_hiz_occlusion_enabled = false
	}
	if err := wgpu_encode_hiz_debug_view(renderer, encoder, layout.render_viewport); err != "" {
		return err
	}
	if err := wgpu_encode_meshlet_debug_overlay(renderer, encoder, layout.render_viewport);
	   err != "" {
		return err
	}
	if err := wgpu_encode_embedded_viewports(
		renderer,
		encoder,
		ui_state,
		registry,
		world,
		&renderer.render_list,
	); err != "" {
		return err
	}
	post_start := time.tick_now()
	if err := wgpu_encode_bloom_and_composite(
		renderer,
		encoder,
		color_view,
		render_depth_view,
		layout.render_width,
		layout.render_height,
		layout.output_width,
		layout.output_height,
		renderer.render_list.camera.camera,
		renderer.render_list.has_camera,
		world,
		delta_time,
		config.render_feature_overrides,
	); err != "" {
		return err
	}
	record_system_profile_phase(config, .Render_Post, post_start)
	ui_start := time.tick_now()
	if ui_state != nil && (ui_state.paint_count > 0 || ui_state.editor_overlay_paint_count > 0) {
		ui_color_attachment := wgpu.RenderPassColorAttachment {
			view = color_view,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			loadOp = .Load,
			storeOp = .Store,
		}
		ui_depth_attachment := wgpu.RenderPassDepthStencilAttachment {
			view = output_depth_view,
			depthLoadOp = .Load,
			depthStoreOp = .Store,
			stencilLoadOp = .Undefined,
			stencilStoreOp = .Undefined,
		}
		ui_timestamps, ui_timestamps_enabled := wgpu_gpu_pass_timestamps(renderer, .UI)
		ui_timestamps_ptr: ^wgpu.PassTimestampWrites
		if ui_timestamps_enabled {
			ui_timestamps_ptr = &ui_timestamps
		}
		ui_pass := wgpu.CommandEncoderBeginRenderPass(
			encoder,
			&wgpu.RenderPassDescriptor {
				label = "Scrapbot UI Overlay Pass",
				colorAttachmentCount = 1,
				colorAttachments = &ui_color_attachment,
				depthStencilAttachment = &ui_depth_attachment,
				timestampWrites = ui_timestamps_ptr,
			},
		)
		if ui_pass == nil { return "failed to begin UI overlay render pass" }
		defer wgpu.RenderPassEncoderRelease(ui_pass)
		drawable_width := f32(layout.output_width)
		drawable_height := f32(layout.output_height)
		viewport := layout.output_viewport
		project_command_count := clamp(ui_state.editor_paint_start, 0, ui_state.paint_count)
		editor_command_end := clamp(
			ui_state.editor_paint_end,
			project_command_count,
			ui_state.paint_count,
		)
		project_key := wgpu_ui_stream_key(
			ui_state.project_paint_output_revision,
			layout.output_width,
			layout.output_height,
			viewport,
		)
		if !renderer.ui_project_stream_key_valid || renderer.ui_project_stream_key != project_key {
			stream_changed := project_command_count > 0 || len(renderer.ui_project_vertices) > 0
			if !wgpu_rebuild_ui_vertex_stream(
				renderer,
				&renderer.ui_project_vertices,
				ui_state.paint[:project_command_count],
				true,
				ui_state,
				viewport,
				drawable_width,
				drawable_height,
				&renderer.ui_project_vertex_buffer,
				&renderer.ui_project_vertex_capacity,
				"Scrapbot Project UI Vertex Buffer",
			) {
				return "failed to upload project UI vertices"
			}
			renderer.ui_project_stream_key = project_key
			renderer.ui_project_stream_key_valid = true
			if stream_changed {
				renderer.ui_vertex_rebuild_count += 1
				renderer.ui_project_vertex_rebuild_count += 1
			}
		}
		editor_key := wgpu_ui_stream_key(
			ui_state.editor_paint_output_revision,
			layout.output_width,
			layout.output_height,
		)
		if !renderer.ui_editor_stream_key_valid || renderer.ui_editor_stream_key != editor_key {
			stream_changed :=
				editor_command_end > project_command_count || len(renderer.ui_editor_vertices) > 0
			if !wgpu_rebuild_ui_vertex_stream(
				renderer,
				&renderer.ui_editor_vertices,
				ui_state.paint[project_command_count:editor_command_end],
				false,
				ui_state,
				viewport,
				drawable_width,
				drawable_height,
				&renderer.ui_editor_vertex_buffer,
				&renderer.ui_editor_vertex_capacity,
				"Scrapbot Editor UI Vertex Buffer",
			) {
				return "failed to upload editor UI vertices"
			}
			renderer.ui_editor_stream_key = editor_key
			renderer.ui_editor_stream_key_valid = true
			if stream_changed {
				renderer.ui_vertex_rebuild_count += 1
				renderer.ui_editor_vertex_rebuild_count += 1
			}
		}
		overlay_key := wgpu_ui_stream_key(
			ui_state.editor_overlay_paint_output_revision,
			layout.output_width,
			layout.output_height,
		)
		if !renderer.ui_overlay_stream_key_valid || renderer.ui_overlay_stream_key != overlay_key {
			stream_changed :=
				ui_state.editor_overlay_paint_count > 0 || len(renderer.ui_overlay_vertices) > 0
			if !wgpu_rebuild_ui_vertex_stream(
				renderer,
				&renderer.ui_overlay_vertices,
				ui_state.editor_overlay_paint[:ui_state.editor_overlay_paint_count],
				false,
				ui_state,
				viewport,
				drawable_width,
				drawable_height,
				&renderer.ui_overlay_vertex_buffer,
				&renderer.ui_overlay_vertex_capacity,
				"Scrapbot Editor Overlay Vertex Buffer",
			) {
				return "failed to upload editor overlay vertices"
			}
			renderer.ui_overlay_stream_key = overlay_key
			renderer.ui_overlay_stream_key_valid = true
			if stream_changed {
				renderer.ui_vertex_rebuild_count += 1
				renderer.ui_overlay_vertex_rebuild_count += 1
			}
		}
		wgpu.RenderPassEncoderSetViewport(ui_pass, 0, 0, drawable_width, drawable_height, 0, 1)
		wgpu.RenderPassEncoderSetScissorRect(
			ui_pass,
			0,
			0,
			layout.output_width,
			layout.output_height,
		)
		wgpu.RenderPassEncoderSetPipeline(ui_pass, renderer.ui_pipeline)
		wgpu.RenderPassEncoderSetBindGroup(ui_pass, 0, renderer.ui_bind_group)
		project_vertex_count := u32(len(renderer.ui_project_vertices))
		if project_vertex_count > 0 {
			wgpu.RenderPassEncoderSetVertexBuffer(
				ui_pass,
				0,
				renderer.ui_project_vertex_buffer,
				0,
				wgpu.WHOLE_SIZE,
			)
			wgpu.RenderPassEncoderSetScissorRect(
				ui_pass,
				u32(viewport.x),
				u32(viewport.y),
				u32(viewport.width),
				u32(viewport.height),
			)
			wgpu.RenderPassEncoderDraw(ui_pass, project_vertex_count, 1, 0, 0)
		}
		if ui_state.editor_visible {
			if len(renderer.ui_overlay_vertices) > 0 {
				wgpu.RenderPassEncoderSetScissorRect(
					ui_pass,
					u32(viewport.x),
					u32(viewport.y),
					u32(viewport.width),
					u32(viewport.height),
				)
				wgpu.RenderPassEncoderSetVertexBuffer(
					ui_pass,
					0,
					renderer.ui_overlay_vertex_buffer,
					0,
					wgpu.WHOLE_SIZE,
				)
				wgpu.RenderPassEncoderDraw(
					ui_pass,
					u32(len(renderer.ui_overlay_vertices)),
					1,
					0,
					0,
				)
			}
		}
		editor_vertex_count := u32(len(renderer.ui_editor_vertices))
		if ui_state.editor_visible && editor_vertex_count > 0 {
			wgpu.RenderPassEncoderSetScissorRect(
				ui_pass,
				0,
				0,
				layout.output_width,
				layout.output_height,
			)
			wgpu.RenderPassEncoderSetVertexBuffer(
				ui_pass,
				0,
				renderer.ui_editor_vertex_buffer,
				0,
				wgpu.WHOLE_SIZE,
			)
			wgpu.RenderPassEncoderDraw(ui_pass, editor_vertex_count, 1, 0, 0)
		}
		wgpu.RenderPassEncoderEnd(ui_pass)
	}
	record_system_profile_phase(config, .Render_UI, ui_start)
	return ""
}

wgpu_encode_depth_prepass :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	depth_view: wgpu.TextureView,
	batches: []WGPU_Draw_Batch,
	registry: ^resources.Registry,
	viewport: ui.Rect,
) -> string {
	depth_attachment := wgpu.RenderPassDepthStencilAttachment {
		view = depth_view,
		depthLoadOp = .Clear,
		depthStoreOp = .Store,
		depthClearValue = 1,
		stencilLoadOp = .Undefined,
		stencilStoreOp = .Undefined,
	}
	timestamps, timestamps_enabled := wgpu_gpu_pass_timestamps(renderer, .Depth)
	timestamps_ptr: ^wgpu.PassTimestampWrites
	if timestamps_enabled {
		timestamps_ptr = &timestamps
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = "Scrapbot Depth Prepass",
			depthStencilAttachment = &depth_attachment,
			timestampWrites = timestamps_ptr,
		},
	)
	if pass == nil {
		return "failed to begin depth prepass"
	}
	defer wgpu.RenderPassEncoderRelease(pass)
	wgpu.RenderPassEncoderSetViewport(
		pass,
		viewport.x,
		viewport.y,
		viewport.width,
		viewport.height,
		0,
		1,
	)
	wgpu.RenderPassEncoderSetScissorRect(
		pass,
		u32(viewport.x),
		u32(viewport.y),
		u32(viewport.width),
		u32(viewport.height),
	)
	for batch, batch_index in batches {
		cached, err := wgpu_geometry_cache(renderer, registry, batch.geometry)
		if err != "" {
			return err
		}
		material, material_alive := resources.get_material(registry, batch.material)
		if !material_alive {
			return "render material handle is stale during depth prepass"
		}
		masked := material.desc.alpha_mode == .Mask
		pipeline := renderer.gpu_driven_depth_pipeline
		if masked {
			pipeline = renderer.gpu_driven_depth_mask_pipeline
		}
		if material.desc.double_sided {
			pipeline = renderer.gpu_driven_depth_double_sided_pipeline
			if masked {
				pipeline = renderer.gpu_driven_depth_mask_double_sided_pipeline
			}
		}
		wgpu.RenderPassEncoderSetPipeline(pass, pipeline)
		world_bind_group := batch.world_bind_group
		index_buffer := cached.index_buffer
		if renderer.gpu_meshlet_submission_active {
			world_bind_group = batch.meshlet_world_bind_group
			index_buffer = cached.meshlet_index_buffer
		}
		wgpu.RenderPassEncoderSetBindGroup(pass, 0, world_bind_group)
		if masked {
			material_cached, material_err := wgpu_material_cache(
				renderer,
				registry,
				batch.material,
			)
			if material_err != "" {
				return material_err
			}
			wgpu.RenderPassEncoderSetBindGroup(pass, 1, material_cached.bind_group)
		}
		wgpu.RenderPassEncoderSetVertexBuffer(pass, 0, cached.vertex_buffer, 0, wgpu.WHOLE_SIZE)
		wgpu.RenderPassEncoderSetIndexBuffer(pass, index_buffer, .Uint32, 0, wgpu.WHOLE_SIZE)
		if renderer.gpu_meshlet_submission_active {
			wgpu.RenderPassEncoderMultiDrawIndexedIndirect(
				pass,
				renderer.gpu_meshlet_indirect_buffer,
				u64(batch.meshlet_draw_offset) * u64(size_of(WGPU_Draw_Indexed_Indirect)),
				batch.meshlet_draw_count,
			)
		} else {
			wgpu.RenderPassEncoderDrawIndexedIndirect(
				pass,
				renderer.gpu_indirect_buffer,
				u64(batch_index * size_of(WGPU_Draw_Indexed_Indirect)),
			)
		}
	}
	wgpu.RenderPassEncoderEnd(pass)
	return ""
}

wgpu_sync_ui_fonts :: proc(renderer: ^WGPU_Renderer, registry: ^resources.Registry) -> string {
	if renderer == nil || registry == nil { return "" }
	font_count := min(len(registry.fonts), shared.MAX_PROJECT_FONTS)
	for index in 0 ..< font_count {
		font := &registry.fonts[index]
		if !font.alive || renderer.ui_font_versions[index] == font.version { continue }
		if font.desc.width != ui.FONT_ATLAS_SIZE ||
		   font.desc.height != ui.FONT_ATLAS_SIZE ||
		   len(font.desc.pixels) != ui.FONT_ATLAS_SIZE * ui.FONT_ATLAS_SIZE * 4 {
			return fmt.tprintf("font %q has an invalid UI atlas", font.name)
		}
		wgpu.QueueWriteTexture(
			renderer.queue,
			&wgpu.TexelCopyTextureInfo {
				texture = renderer.ui_font_texture,
				origin = {z = u32(index + 1)},
				aspect = .All,
			},
			raw_data(font.desc.pixels),
			uint(len(font.desc.pixels)),
			&wgpu.TexelCopyBufferLayout {
				bytesPerRow = ui.FONT_ATLAS_SIZE * 4,
				rowsPerImage = ui.FONT_ATLAS_SIZE,
			},
			&wgpu.Extent3D {
				width = ui.FONT_ATLAS_SIZE,
				height = ui.FONT_ATLAS_SIZE,
				depthOrArrayLayers = 1,
			},
		)
		renderer.ui_font_versions[index] = font.version
	}
	icon_set_count := min(len(registry.icon_sets), shared.MAX_ICON_SETS)
	for index in 0 ..< icon_set_count {
		icon_set := &registry.icon_sets[index]
		if !icon_set.alive || renderer.ui_icon_set_versions[index] == icon_set.version {
			continue
		}
		if icon_set.desc.width != ui.FONT_ATLAS_SIZE ||
		   icon_set.desc.height != ui.FONT_ATLAS_SIZE ||
		   len(icon_set.desc.pixels) != ui.FONT_ATLAS_SIZE * ui.FONT_ATLAS_SIZE * 4 {
			return fmt.tprintf("icon set %q has an invalid UI atlas", icon_set.name)
		}
		wgpu.QueueWriteTexture(
			renderer.queue,
			&wgpu.TexelCopyTextureInfo {
				texture = renderer.ui_font_texture,
				origin = {z = u32(shared.MAX_PROJECT_FONTS + 1 + index)},
				aspect = .All,
			},
			raw_data(icon_set.desc.pixels),
			uint(len(icon_set.desc.pixels)),
			&wgpu.TexelCopyBufferLayout {
				bytesPerRow = ui.FONT_ATLAS_SIZE * 4,
				rowsPerImage = ui.FONT_ATLAS_SIZE,
			},
			&wgpu.Extent3D {
				width = ui.FONT_ATLAS_SIZE,
				height = ui.FONT_ATLAS_SIZE,
				depthOrArrayLayers = 1,
			},
		)
		renderer.ui_icon_set_versions[index] = icon_set.version
	}
	return ""
}

wgpu_encode_shadow_pass :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	batches: []WGPU_Draw_Batch,
	registry: ^resources.Registry,
) -> string {
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		if err := wgpu_encode_shadow_cascade_pass(
			renderer,
			encoder,
			batches,
			registry,
			cascade_index,
		); err != "" {
			return err
		}
	}
	return ""
}

wgpu_encode_shadow_cascade_pass :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	batches: []WGPU_Draw_Batch,
	registry: ^resources.Registry,
	cascade_index: int,
) -> string {
	depth_attachment := wgpu.RenderPassDepthStencilAttachment {
		view = renderer.shadow_layer_views[cascade_index],
		depthLoadOp = .Clear,
		depthStoreOp = .Store,
		depthClearValue = 1,
		stencilLoadOp = .Undefined,
		stencilStoreOp = .Undefined,
	}
	shadow_timestamps, shadow_timestamps_enabled := wgpu_gpu_shadow_pass_timestamps(
		renderer,
		cascade_index,
	)
	shadow_timestamps_ptr: ^wgpu.PassTimestampWrites
	if shadow_timestamps_enabled {
		shadow_timestamps_ptr = &shadow_timestamps
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = "Scrapbot Shadow Pass",
			depthStencilAttachment = &depth_attachment,
			timestampWrites = shadow_timestamps_ptr,
		},
	)
	if pass == nil { return "failed to begin wgpu shadow pass" }
	defer wgpu.RenderPassEncoderRelease(pass)
	if len(batches) > 0 {
		for batch, batch_index in batches {
			cached, err := wgpu_geometry_cache(renderer, registry, batch.geometry)
			if err != "" { return err }
			material, material_alive := resources.get_material(registry, batch.material)
			if !material_alive {
				return "render material handle is stale during shadow pass"
			}
			masked := material.desc.alpha_mode == .Mask
			pipeline := renderer.gpu_driven_shadow_pipeline
			if masked {
				pipeline = renderer.gpu_driven_shadow_mask_pipeline
			}
			if material.desc.double_sided {
				pipeline = renderer.gpu_driven_shadow_double_sided_pipeline
				if masked {
					pipeline = renderer.gpu_driven_shadow_mask_double_sided_pipeline
				}
			}
			wgpu.RenderPassEncoderSetPipeline(pass, pipeline)
			shadow_bind_group := batch.shadow_bind_groups[cascade_index]
			index_buffer := cached.index_buffer
			if renderer.gpu_meshlet_submission_active {
				shadow_bind_group = batch.meshlet_shadow_bind_groups[cascade_index]
				index_buffer = cached.meshlet_index_buffer
			}
			wgpu.RenderPassEncoderSetBindGroup(pass, 0, shadow_bind_group)
			if masked {
				material_cached, material_err := wgpu_material_cache(
					renderer,
					registry,
					batch.material,
				)
				if material_err != "" {
					return material_err
				}
				wgpu.RenderPassEncoderSetBindGroup(pass, 1, material_cached.bind_group)
			}
			wgpu.RenderPassEncoderSetVertexBuffer(
				pass,
				0,
				cached.vertex_buffer,
				0,
				wgpu.WHOLE_SIZE,
			)
			wgpu.RenderPassEncoderSetIndexBuffer(pass, index_buffer, .Uint32, 0, wgpu.WHOLE_SIZE)
			if renderer.gpu_meshlet_submission_active {
				wgpu.RenderPassEncoderMultiDrawIndexedIndirect(
					pass,
					renderer.gpu_meshlet_shadow_indirect_buffer,
					u64(
						cascade_index * renderer.gpu_meshlet_draw_capacity +
						int(batch.meshlet_draw_offset),
					) *
					u64(size_of(WGPU_Draw_Indexed_Indirect)),
					batch.meshlet_draw_count,
				)
			} else {
				wgpu.RenderPassEncoderDrawIndexedIndirect(
					pass,
					renderer.gpu_shadow_indirect_buffer,
					u64(
						(cascade_index * renderer.draw_batch_cache.batch_count + batch_index) *
						size_of(WGPU_Draw_Indexed_Indirect),
					),
				)
			}
		}
	}
	wgpu.RenderPassEncoderEnd(pass)
	return ""
}

wgpu_draw_frame :: proc(
	renderer: ^WGPU_Renderer,
	world: ^World,
	config: ^Run_Config,
	delta_time: f32,
	pump_events_on_acquire := true,
) -> (
	presented, should_quit: bool,
	err: string,
) {
	drawable, configure_err := wgpu_configure_surface(renderer)
	if configure_err != "" || !drawable {
		return false, false, configure_err
	}

	surface_texture, acquired_texture, acquire_should_quit := wgpu_acquire_surface_texture(
		renderer,
		pump_events_on_acquire,
	)
	if acquire_should_quit {
		return false, true, ""
	}
	if !acquired_texture {
		switch surface_texture.status {
			case .Occluded, .Timeout:
				return false, false, ""
			case .Outdated, .Lost:
				renderer.configured = false
				return false, false, ""
			case .Error:
				return false, false, "failed to acquire wgpu surface texture: Error"
			case .SuccessOptimal, .SuccessSuboptimal:
		}
		return false, false, fmt.tprintf(
			"failed to acquire wgpu surface texture: %v",
			surface_texture.status,
		)
	}
	texture := surface_texture.texture
	if texture == nil {
		return false, false, "wgpu surface returned no texture"
	}
	active_frame_start := time.tick_now()

	view := wgpu.TextureCreateView(texture)
	if view == nil {
		wgpu.TextureRelease(texture)
		return false, false, "failed to create wgpu texture view"
	}
	defer wgpu.TextureViewRelease(view)
	defer wgpu.TextureRelease(texture)

	begin_system_profile_frame(config)
	frame_start := begin_runtime_frame(config)
	if err = run_frame_system(
		config,
		world,
		delta_time,
		f32(renderer.width),
		f32(renderer.height),
	); err != "" {
		return false, false, err
	}
	render_prepare_start := time.tick_now()
	ecs.populate_resource_render_list(
		world,
		config.resource_registry,
		&renderer.render_list,
		config.ui_state != nil && config.ui_state.editor_visible,
	)
	wgpu_apply_render_debug_override(&renderer.render_list, config.ui_state)
	profile_frame_index := renderer.profile_frame_index
	wgpu_gpu_timing_begin_frame(renderer, profile_frame_index)
	viewport := ui.editor_viewport(config.ui_state, f32(renderer.width), f32(renderer.height))
	camera := shared.camera_defaults()
	policy_owner: shared.Entity_UUID
	if renderer.render_list.has_camera {
		camera = renderer.render_list.camera.camera
		policy_owner = renderer.render_list.camera.policy_owner
	}
	camera.resolution_scale = wgpu_dynamic_resolution_scale(renderer, camera, policy_owner)
	layout := wgpu_render_target_layout(renderer.width, renderer.height, viewport, camera)
	render_depth_view, render_depth_err := wgpu_render_depth_view(
		renderer,
		renderer.depth_view,
		renderer.width,
		renderer.height,
		layout.render_width,
		layout.render_height,
	)
	if render_depth_err != "" {
		return false, false, render_depth_err
	}
	batches, batch_count, prepare_err := wgpu_prepare_gpu_draw_batches(
		renderer,
		&renderer.render_list,
		config.resource_registry,
		layout.render_viewport,
		layout.render_width,
		layout.render_height,
		config.cpu_culling,
	)
	if prepare_err != "" {
		return false, false, prepare_err
	}
	if config.cpu_culling {
		renderer.gpu_hiz_occlusion_enabled = false
		renderer.gpu_hiz_occlusion_status = .Unavailable
		renderer.gpu_hiz_requested = false
		wgpu_prepare_cpu_culling(
			renderer,
			&renderer.render_list,
			u32(layout.render_viewport.width),
			u32(layout.render_viewport.height),
		)
	}
	if config.stats != nil {
		config.stats.draw_batches = batch_count
		config.stats.draw_capacity = renderer.gpu_draw_capacity
		config.stats.draw_database_rebuilds = renderer.gpu_draw_database_rebuild_count
		config.stats.gpu_driven = true
		config.stats.render_scale = layout.resolution_scale
		config.stats.dynamic_resolution = renderer.dynamic_resolution.enabled
		config.stats.dynamic_resolution_filtered_gpu_ms =
			renderer.dynamic_resolution.filtered_gpu_ms
		config.stats.compute_culling = !config.cpu_culling
		config.stats.meshlet_culling = renderer.gpu_meshlet_submission_active
		config.stats.meshlet_supported = renderer.gpu_meshlet_supported
		config.stats.meshlet_native_multi_draw =
			renderer.gpu_meshlet_submission_active && renderer.gpu_meshlet_native_multi_draw
		config.stats.meshlet_draws = renderer.gpu_meshlet_draw_count
		config.stats.meshlet_visible_capacity = renderer.gpu_meshlet_visible_capacity
		config.stats.clustered_lighting = true
		config.stats.shadow_cascades =
			WGPU_SHADOW_CASCADE_COUNT if renderer.render_list.directional_light_count > 0 else 0
		config.stats.cluster_count = WGPU_CLUSTER_COUNT
		config.stats.cluster_max_lights = renderer.gpu_cluster_light_capacity
		config.stats.clustered_point_lights = renderer.gpu_clustered_light_count
		config.stats.cluster_dispatches = renderer.gpu_cluster_dispatch_count
		config.stats.instance_capacity = WGPU_MAX_GPU_INSTANCES
		config.stats.instance_slots = renderer.gpu_slot_count
		config.stats.visible_capacity = renderer.gpu_visible_capacity
		config.stats.visible_buffer_capacity = renderer.gpu_visible_buffer_capacity
		config.stats.instance_uploads = renderer.gpu_instance_upload_count
		config.stats.instance_upload_bytes = renderer.gpu_instance_upload_bytes
		config.stats.instance_transform_uploads = renderer.gpu_instance_transform_upload_count
		config.stats.instance_transform_upload_bytes = renderer.gpu_instance_transform_upload_bytes
		config.stats.instance_expand_dispatches = renderer.gpu_instance_expand_dispatch_count
		config.stats.instance_expanded_slots = renderer.gpu_instance_expanded_slot_count
	}
	record_system_profile_phase(config, .Render_Prepare, render_prepare_start)
	finish_runtime_frame(config, world, frame_start)

	cull_start := time.tick_now()
	encoder := wgpu.DeviceCreateCommandEncoder(
		renderer.device,
		&wgpu.CommandEncoderDescriptor{label = "Scrapbot Render Encoder"},
	)
	if encoder == nil {
		return false, false, "failed to create wgpu command encoder"
	}
	defer wgpu.CommandEncoderRelease(encoder)
	if !config.cpu_culling {
		wgpu_visibility_begin_frame(renderer)
	}
	if err = wgpu_encode_gpu_instance_expansion(renderer, encoder); err != "" {
		return false, false, err
	}
	if !config.cpu_culling {
		if err = wgpu_encode_gpu_culling(renderer, encoder, batch_count); err != "" {
			return false, false, err
		}
	}
	cluster_dispatches_before := renderer.gpu_cluster_dispatch_count
	if err = wgpu_encode_clustered_lighting(renderer, encoder); err != "" {
		return false, false, err
	}
	record_system_profile_phase(config, .Render_Cull, cull_start)
	shadow_start := time.tick_now()
	if err = wgpu_encode_shadow_pass(
		renderer,
		encoder,
		batches[:batch_count],
		config.resource_registry,
	); err != "" { return false, false, err }
	record_system_profile_phase(config, .Render_Shadow, shadow_start)
	if err = wgpu_encode_depth_prepass(
		renderer,
		encoder,
		render_depth_view,
		batches[:batch_count],
		config.resource_registry,
		layout.render_viewport,
	); err != "" {
		return false, false, err
	}
	if err = wgpu_encode_render_pass(
		renderer,
		encoder,
		view,
		renderer.depth_view,
		render_depth_view,
		batches[:batch_count],
		config.resource_registry,
		world,
		config.ui_state,
		config,
		"Scrapbot Geometry Pass",
		layout,
		delta_time,
	); err != "" {
		return false, false, err
	}
	if !config.cpu_culling {
		wgpu_visibility_resolve(renderer, encoder)
	}
	wgpu_gpu_timing_resolve(renderer, encoder)
	finish_start := time.tick_now()
	command_buffer := wgpu.CommandEncoderFinish(
		encoder,
		&wgpu.CommandBufferDescriptor{label = "Scrapbot Render Commands"},
	)
	if command_buffer == nil {
		return false, false, "failed to finish wgpu command encoder"
	}
	defer wgpu.CommandBufferRelease(command_buffer)
	record_system_profile_phase(config, .Render_Finish, finish_start)

	submit_start := time.tick_now()
	wgpu.QueueSubmit(renderer.queue, []wgpu.CommandBuffer{command_buffer})
	wgpu_gpu_timing_after_submit(renderer)
	if !config.cpu_culling {
		wgpu_visibility_after_submit(renderer)
	}
	record_system_profile_phase(config, .Render_Submit, submit_start)
	present_start := time.tick_now()
	if wgpu.SurfacePresent(renderer.surface) != .Success {
		return false, false, "failed to present wgpu surface"
	}
	record_system_profile_phase(config, .Render_Present, present_start)
	profile_active_frame_seconds := frame_active_seconds(active_frame_start)
	if config.profile != nil && (profile_frame_index + 1) % u64(WGPU_GPU_TIMESTAMP_FRAMES) == 0 {
		wgpu_gpu_timing_drain(renderer)
	}
	if config.stats != nil {
		wgpu_publish_gpu_timing(renderer, config.stats)
		wgpu_publish_visibility(renderer, config.stats)
		config.stats.ui_vertex_rebuilds = renderer.ui_vertex_rebuild_count
		config.stats.ui_project_vertex_rebuilds = renderer.ui_project_vertex_rebuild_count
		config.stats.ui_editor_vertex_rebuilds = renderer.ui_editor_vertex_rebuild_count
		config.stats.ui_overlay_vertex_rebuilds = renderer.ui_overlay_vertex_rebuild_count
		config.stats.ui_vertex_uploads = renderer.ui_vertex_upload_count
		config.stats.ui_vertex_upload_bytes = renderer.ui_vertex_upload_bytes
		config.stats.ui_viewport_active_targets = renderer.ui_viewport_active_targets
		config.stats.ui_viewport_target_pixels = renderer.ui_viewport_target_pixels
		config.stats.ui_viewport_target_resizes = renderer.ui_viewport_target_resize_count
		config.stats.ui_viewport_redraws = renderer.ui_viewport_redraw_count
		config.stats.ui_viewport_cache_hits = renderer.ui_viewport_cache_hit_count
	}
	active_frame_seconds :=
		profile_active_frame_seconds if config.profile != nil else frame_active_seconds(active_frame_start)
	performance_diagnostics_commit_frame(
		config.performance_diagnostics,
		config.stats,
		world,
		delta_time,
		active_frame_seconds,
	)
	profile_record_frame(
		config.profile,
		profile_frame_index,
		active_frame_seconds,
		delta_time,
		renderer.width,
		renderer.height,
		platform.runtime_window_pixel_density(),
		viewport,
		config.stats,
		wgpu_profile_workload(
			renderer,
			world,
			layout.render_viewport,
			layout.render_width,
			layout.render_height,
			layout.output_width,
			layout.output_height,
			renderer.gpu_cluster_dispatch_count > cluster_dispatches_before,
			config.stats,
			config.render_feature_overrides,
		),
	)
	renderer.profile_frame_index += 1
	commit_system_profile_frame(config)

	return true, false, ""
}

wgpu_render_offscreen_frame :: proc(
	renderer: ^WGPU_Renderer,
	world: ^World,
	texture: wgpu.Texture,
	view: wgpu.TextureView,
	depth_view: wgpu.TextureView,
	readback: wgpu.Buffer = nil,
	row_stride: u32 = 0,
	width: u32 = 0,
	height: u32 = 0,
	config: ^Run_Config = nil,
) -> string {
	active_frame_start := time.tick_now()
	begin_system_profile_frame(config)
	frame_start := begin_runtime_frame(config)
	if config != nil {
		if err := run_frame_system(config, world, 1.0 / 60.0); err != "" {
			return err
		}
	}
	render_prepare_start := time.tick_now()
	ecs.populate_resource_render_list(
		world,
		config.resource_registry,
		&renderer.render_list,
		config.ui_state != nil && config.ui_state.editor_visible,
	)
	wgpu_apply_render_debug_override(&renderer.render_list, config.ui_state)
	profile_frame_index := renderer.profile_frame_index
	wgpu_gpu_timing_begin_frame(renderer, profile_frame_index)
	viewport := ui.editor_viewport(config.ui_state, f32(width), f32(height))
	camera := shared.camera_defaults()
	policy_owner: shared.Entity_UUID
	if renderer.render_list.has_camera {
		camera = renderer.render_list.camera.camera
		policy_owner = renderer.render_list.camera.policy_owner
	}
	camera.resolution_scale = wgpu_dynamic_resolution_scale(renderer, camera, policy_owner)
	layout := wgpu_render_target_layout(width, height, viewport, camera)
	render_depth_view, render_depth_err := wgpu_render_depth_view(
		renderer,
		depth_view,
		width,
		height,
		layout.render_width,
		layout.render_height,
	)
	if render_depth_err != "" {
		return render_depth_err
	}
	batches, batch_count, prepare_err := wgpu_prepare_gpu_draw_batches(
		renderer,
		&renderer.render_list,
		config.resource_registry,
		layout.render_viewport,
		layout.render_width,
		layout.render_height,
		config.cpu_culling,
	)
	if prepare_err != "" {
		return prepare_err
	}
	if config.cpu_culling {
		renderer.gpu_hiz_occlusion_enabled = false
		renderer.gpu_hiz_occlusion_status = .Unavailable
		renderer.gpu_hiz_requested = false
		wgpu_prepare_cpu_culling(
			renderer,
			&renderer.render_list,
			u32(layout.render_viewport.width),
			u32(layout.render_viewport.height),
		)
	}
	if config != nil && config.stats != nil {
		config.stats.draw_batches = batch_count
		config.stats.draw_capacity = renderer.gpu_draw_capacity
		config.stats.draw_database_rebuilds = renderer.gpu_draw_database_rebuild_count
		config.stats.gpu_driven = true
		config.stats.render_scale = layout.resolution_scale
		config.stats.dynamic_resolution = renderer.dynamic_resolution.enabled
		config.stats.dynamic_resolution_filtered_gpu_ms =
			renderer.dynamic_resolution.filtered_gpu_ms
		config.stats.compute_culling = !config.cpu_culling
		config.stats.meshlet_culling = renderer.gpu_meshlet_submission_active
		config.stats.meshlet_supported = renderer.gpu_meshlet_supported
		config.stats.meshlet_native_multi_draw =
			renderer.gpu_meshlet_submission_active && renderer.gpu_meshlet_native_multi_draw
		config.stats.meshlet_draws = renderer.gpu_meshlet_draw_count
		config.stats.meshlet_visible_capacity = renderer.gpu_meshlet_visible_capacity
		config.stats.clustered_lighting = true
		config.stats.shadow_cascades =
			WGPU_SHADOW_CASCADE_COUNT if renderer.render_list.directional_light_count > 0 else 0
		config.stats.cluster_count = WGPU_CLUSTER_COUNT
		config.stats.cluster_max_lights = renderer.gpu_cluster_light_capacity
		config.stats.clustered_point_lights = renderer.gpu_clustered_light_count
		config.stats.cluster_dispatches = renderer.gpu_cluster_dispatch_count
		config.stats.instance_capacity = WGPU_MAX_GPU_INSTANCES
		config.stats.instance_slots = renderer.gpu_slot_count
		config.stats.visible_capacity = renderer.gpu_visible_capacity
		config.stats.visible_buffer_capacity = renderer.gpu_visible_buffer_capacity
		config.stats.instance_uploads = renderer.gpu_instance_upload_count
		config.stats.instance_upload_bytes = renderer.gpu_instance_upload_bytes
		config.stats.instance_transform_uploads = renderer.gpu_instance_transform_upload_count
		config.stats.instance_transform_upload_bytes = renderer.gpu_instance_transform_upload_bytes
		config.stats.instance_expand_dispatches = renderer.gpu_instance_expand_dispatch_count
		config.stats.instance_expanded_slots = renderer.gpu_instance_expanded_slot_count
	}
	record_system_profile_phase(config, .Render_Prepare, render_prepare_start)
	finish_runtime_frame(config, world, frame_start)

	cull_start := time.tick_now()
	encoder := wgpu.DeviceCreateCommandEncoder(
		renderer.device,
		&wgpu.CommandEncoderDescriptor{label = "Scrapbot Headless Render Encoder"},
	)
	if encoder == nil {
		return "failed to create wgpu command encoder"
	}
	defer wgpu.CommandEncoderRelease(encoder)
	if !config.cpu_culling {
		wgpu_visibility_begin_frame(renderer)
	}
	if err := wgpu_encode_gpu_instance_expansion(renderer, encoder); err != "" {
		return err
	}
	if !config.cpu_culling {
		if err := wgpu_encode_gpu_culling(renderer, encoder, batch_count); err != "" {
			return err
		}
	}
	cluster_dispatches_before := renderer.gpu_cluster_dispatch_count
	if err := wgpu_encode_clustered_lighting(renderer, encoder); err != "" {
		return err
	}
	record_system_profile_phase(config, .Render_Cull, cull_start)
	shadow_start := time.tick_now()
	if err := wgpu_encode_shadow_pass(
		renderer,
		encoder,
		batches[:batch_count],
		config.resource_registry,
	); err != "" { return err }
	record_system_profile_phase(config, .Render_Shadow, shadow_start)
	if err := wgpu_encode_depth_prepass(
		renderer,
		encoder,
		render_depth_view,
		batches[:batch_count],
		config.resource_registry,
		layout.render_viewport,
	); err != "" {
		return err
	}
	if err := wgpu_encode_render_pass(
		renderer,
		encoder,
		view,
		depth_view,
		render_depth_view,
		batches[:batch_count],
		config.resource_registry,
		world,
		config.ui_state,
		config,
		"Scrapbot Headless Geometry Pass",
		layout,
		1.0 / 60.0,
	); err != "" {
		return err
	}
	if !config.cpu_culling {
		wgpu_visibility_resolve(renderer, encoder)
	}

	if readback != nil {
		required_readback_size := u64(row_stride) * u64(height)
		if wgpu.BufferGetSize(readback) < required_readback_size {
			return fmt.tprintf(
				"wgpu headless readback buffer is %d bytes; expected at least %d",
				wgpu.BufferGetSize(readback),
				required_readback_size,
			)
		}
		wgpu.CommandEncoderCopyTextureToBuffer(
			encoder,
			&wgpu.TexelCopyTextureInfo{texture = texture, aspect = .All},
			&wgpu.TexelCopyBufferInfo {
				buffer = readback,
				layout = wgpu.TexelCopyBufferLayout {
					bytesPerRow = row_stride,
					rowsPerImage = height,
				},
			},
			&wgpu.Extent3D{width = width, height = height, depthOrArrayLayers = 1},
		)
	}
	wgpu_gpu_timing_resolve(renderer, encoder)
	finish_start := time.tick_now()
	command_buffer := wgpu.CommandEncoderFinish(
		encoder,
		&wgpu.CommandBufferDescriptor{label = "Scrapbot Headless Render Commands"},
	)
	if command_buffer == nil {
		return "failed to finish wgpu command encoder"
	}
	defer wgpu.CommandBufferRelease(command_buffer)
	record_system_profile_phase(config, .Render_Finish, finish_start)

	submit_start := time.tick_now()
	wgpu.QueueSubmit(renderer.queue, []wgpu.CommandBuffer{command_buffer})
	wgpu_gpu_timing_after_submit(renderer)
	if !config.cpu_culling {
		wgpu_visibility_after_submit(renderer)
	}
	record_system_profile_phase(config, .Render_Submit, submit_start)
	profile_active_frame_seconds := frame_active_seconds(active_frame_start)
	if config.profile != nil && (profile_frame_index + 1) % u64(WGPU_GPU_TIMESTAMP_FRAMES) == 0 {
		wgpu_gpu_timing_drain(renderer)
	}
	if config.stats != nil {
		wgpu_publish_gpu_timing(renderer, config.stats)
		wgpu_publish_visibility(renderer, config.stats)
		config.stats.ui_vertex_rebuilds = renderer.ui_vertex_rebuild_count
		config.stats.ui_project_vertex_rebuilds = renderer.ui_project_vertex_rebuild_count
		config.stats.ui_editor_vertex_rebuilds = renderer.ui_editor_vertex_rebuild_count
		config.stats.ui_overlay_vertex_rebuilds = renderer.ui_overlay_vertex_rebuild_count
		config.stats.ui_vertex_uploads = renderer.ui_vertex_upload_count
		config.stats.ui_vertex_upload_bytes = renderer.ui_vertex_upload_bytes
		config.stats.ui_viewport_active_targets = renderer.ui_viewport_active_targets
		config.stats.ui_viewport_target_pixels = renderer.ui_viewport_target_pixels
		config.stats.ui_viewport_target_resizes = renderer.ui_viewport_target_resize_count
		config.stats.ui_viewport_redraws = renderer.ui_viewport_redraw_count
		config.stats.ui_viewport_cache_hits = renderer.ui_viewport_cache_hit_count
	}
	active_frame_seconds :=
		profile_active_frame_seconds if config.profile != nil else frame_active_seconds(active_frame_start)
	performance_diagnostics_commit_frame(
		config.performance_diagnostics,
		config.stats,
		world,
		1.0 / 60.0,
		active_frame_seconds,
	)
	profile_record_frame(
		config.profile,
		profile_frame_index,
		active_frame_seconds,
		1.0 / 60.0,
		width,
		height,
		1,
		viewport,
		config.stats,
		wgpu_profile_workload(
			renderer,
			world,
			layout.render_viewport,
			layout.render_width,
			layout.render_height,
			layout.output_width,
			layout.output_height,
			renderer.gpu_cluster_dispatch_count > cluster_dispatches_before,
			config.stats,
			config.render_feature_overrides,
		),
	)
	renderer.profile_frame_index += 1
	commit_system_profile_frame(config)
	return ""
}

wgpu_write_framegrab_readback :: proc(
	renderer: ^WGPU_Renderer,
	readback: wgpu.Buffer,
	readback_size: u64,
	row_stride, frame_width, frame_height: u32,
	capture_x, capture_y, capture_width, capture_height: u32,
	path: string,
) -> string {
	map_state: WGPU_Buffer_Map_State
	wgpu.BufferMapAsync(
		readback,
		{.Read},
		0,
		uint(readback_size),
		wgpu.BufferMapCallbackInfo {
			mode = .AllowSpontaneos,
			callback = wgpu_buffer_map_callback,
			userdata1 = &map_state,
		},
	)
	if !wgpu_wait_for_buffer_map(renderer.instance, &map_state) {
		message := string(map_state.message[:map_state.message_length])
		if message == "" {
			message = "request timed out"
		}
		return fmt.tprintf("failed to map wgpu readback buffer: %s", message)
	}
	defer wgpu.BufferUnmap(readback)
	mapped := wgpu.BufferGetMappedRange(readback, 0, uint(readback_size))
	capture_row_bytes := capture_width * 4
	pixels := make([]u8, int(capture_row_bytes * capture_height))
	defer delete(pixels)
	for y in 0 ..< int(capture_height) {
		dst := y * int(capture_row_bytes)
		src := (y + int(capture_y)) * int(row_stride) + int(capture_x * 4)
		copy_framegrab_row(
			pixels[dst:dst + int(capture_row_bytes)],
			mapped[src:src + int(capture_row_bytes)],
			renderer.format,
		)
	}
	return write_png_rgba8(path, pixels, capture_width, capture_height)
}

wgpu_offscreen_capture_requested :: proc(config: ^Run_Config) -> bool {
	if config == nil {
		return false
	}
	return config.framegrab_path != "" || config.framegrab_sequence_directory != ""
}

wgpu_run_headless :: proc(world: ^World, config: ^Run_Config) -> string {
	renderer, init_err := wgpu_init_renderer(false, config.ui_state)
	defer wgpu_destroy_renderer(&renderer)
	if init_err != "" {
		return init_err
	}
	wgpu_configure_profile(&renderer, config.profile)

	width := u32(WGPU_OFFSCREEN_WIDTH)
	height := u32(WGPU_OFFSCREEN_HEIGHT)
	profile_dimensions := config.profile != nil || config.framegrab_sequence_directory != ""
	if profile_dimensions {
		width = u32(max(config.window_width, 1))
		height = u32(max(config.window_height, 1))
	}
	capture_x, capture_y, capture_width, capture_height := u32(0), u32(0), width, height
	if config.framegrab_region.width > 0 {
		region := config.framegrab_region
		if region.x >= width ||
		   region.y >= height ||
		   region.width > width - region.x ||
		   region.height > height - region.y {
			return fmt.tprintf("framegrab region must fit within the %dx%d frame", width, height)
		}
		capture_x, capture_y, capture_width, capture_height =
			region.x, region.y, region.width, region.height
	}
	row_bytes := width * 4
	row_stride := align_to(row_bytes, 256)
	readback_size := u64(row_stride * height)

	texture := wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label = "Scrapbot Headless Frame Texture",
			usage = {.RenderAttachment, .CopySrc},
			dimension = ._2D,
			size = wgpu.Extent3D{width = width, height = height, depthOrArrayLayers = 1},
			format = renderer.format,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	if texture == nil {
		return "failed to create wgpu headless texture"
	}
	defer wgpu.TextureRelease(texture)

	view := wgpu.TextureCreateView(texture)
	if view == nil {
		return "failed to create wgpu headless texture view"
	}
	defer wgpu.TextureViewRelease(view)

	depth_texture, depth_view, depth_err := wgpu_create_depth_texture(&renderer, width, height)
	if depth_err != "" {
		return depth_err
	}
	defer wgpu.TextureViewRelease(depth_view)
	defer wgpu.TextureRelease(depth_texture)

	readback: wgpu.Buffer
	defer if readback != nil {
		wgpu.BufferRelease(readback)
	}
	if wgpu_offscreen_capture_requested(config) {
		readback = wgpu.DeviceCreateBuffer(
			renderer.device,
			&wgpu.BufferDescriptor {
				label = "Scrapbot Headless Readback Buffer",
				usage = {.CopyDst, .MapRead},
				size = readback_size,
			},
		)
		if readback == nil {
			return "failed to create wgpu headless readback buffer"
		}
		if wgpu.BufferGetSize(readback) < readback_size {
			return fmt.tprintf(
				"wgpu created a %d-byte headless readback buffer; requested %d bytes",
				wgpu.BufferGetSize(readback),
				readback_size,
			)
		}
	}

	frame_count := config.max_frames
	if frame_count == 0 {
		frame_count = 1
	}
	diagnostic_err := ""
	for index in 0 ..< frame_count {
		sequence_capture :=
			config.framegrab_sequence_directory != "" &&
			index >= config.framegrab_sequence_start &&
			index <= config.framegrab_sequence_end
		final_capture := config.framegrab_path != "" && index == frame_count - 1
		diagnostic_capture := config.ui_driver != nil && config.framegrab_path != ""
		capture := diagnostic_capture || sequence_capture || final_capture
		if capture && wgpu.BufferGetSize(readback) < readback_size {
			return fmt.tprintf(
				"wgpu headless readback buffer changed to %d bytes before frame %d; expected %d",
				wgpu.BufferGetSize(readback),
				index,
				readback_size,
			)
		}
		err := wgpu_render_offscreen_frame(
			&renderer,
			world,
			texture,
			view,
			depth_view,
			readback if capture else nil,
			row_stride if capture else 0,
			width,
			height,
			config,
		)
		if err != "" {
			if config.ui_driver == nil {
				return err
			}
			diagnostic_err = err
			break
		}
		if config.ui_driver != nil &&
		   ui.diagnostic_driver_is_complete(config.ui_driver) &&
		   config.profile == nil &&
		   config.framegrab_sequence_directory == "" {
			break
		}
		if sequence_capture {
			sequence_index := index - config.framegrab_sequence_index_base
			file_name := fmt.aprintf("frame-%06d.png", sequence_index)
			path, path_err := filepath.join({config.framegrab_sequence_directory, file_name})
			delete(file_name)
			if path_err != nil {
				return "failed to allocate profile frame path"
			}
			write_err := wgpu_write_framegrab_readback(
				&renderer,
				readback,
				readback_size,
				row_stride,
				width,
				height,
				capture_x,
				capture_y,
				capture_width,
				capture_height,
				path,
			)
			delete(path)
			if write_err != "" {
				return write_err
			}
		}
	}
	if config.ui_driver != nil && !ui.diagnostic_driver_is_complete(config.ui_driver) {
		if diagnostic_err == "" {
			diagnostic_err = fmt.tprintf(
				"UI diagnostic script did not complete within %d frames",
				frame_count,
			)
		}
	}
	if config.framegrab_region.width == 0 && config.ui_driver != nil {
		if target_rect, found := ui.diagnostic_driver_capture_rect(
			config.ui_driver,
			config.ui_state,
			world,
			f32(width),
			f32(height),
		); found {
			x0 := u32(math.floor(clamp(target_rect.x, 0, f32(width - 1))))
			y0 := u32(math.floor(clamp(target_rect.y, 0, f32(height - 1))))
			x1 := u32(math.ceil(clamp(target_rect.x + target_rect.width, f32(x0 + 1), f32(width))))
			y1 := u32(
				math.ceil(clamp(target_rect.y + target_rect.height, f32(y0 + 1), f32(height))),
			)
			capture_x = x0
			capture_y = y0
			capture_width = x1 - x0
			capture_height = y1 - y0
		}
	}

	wgpu_gpu_timing_drain(&renderer)
	if !config.cpu_culling {
		wgpu_visibility_consume_readbacks(&renderer)
	}
	if config.stats != nil {
		wgpu_publish_gpu_timing(&renderer, config.stats)
		wgpu_publish_visibility(&renderer, config.stats)
	}
	if config.framegrab_path != "" {
		if write_err := wgpu_write_framegrab_readback(
			&renderer,
			readback,
			readback_size,
			row_stride,
			width,
			height,
			capture_x,
			capture_y,
			capture_width,
			capture_height,
			config.framegrab_path,
		); write_err != "" {
			return write_err
		}
	}
	return diagnostic_err
}

copy_framegrab_row :: proc(dst, src: []u8, format: wgpu.TextureFormat) {
	#partial switch format {
		case .BGRA8Unorm, .BGRA8UnormSrgb:
			for i := 0; i < len(dst); i += 4 {
				dst[i + 0] = src[i + 2]
				dst[i + 1] = src[i + 1]
				dst[i + 2] = src[i + 0]
				dst[i + 3] = src[i + 3]
			}
		case:
			copy(dst, src)
	}
}

align_to :: proc(value, alignment: u32) -> u32 {
	return ((value + alignment - 1) / alignment) * alignment
}

wgpu_run_window :: proc(world: ^World, config: ^Run_Config) -> string {
	renderer, init_err := wgpu_init_renderer(true, config.ui_state)
	defer wgpu_destroy_renderer(&renderer)
	if init_err != "" {
		return init_err
	}
	wgpu_configure_profile(&renderer, config.profile)
	defer wgpu_gpu_timing_drain(&renderer)

	frame_count: u32
	previous_tick := time.tick_now()
	live_resize_state := WGPU_Live_Resize_State {
		renderer = &renderer,
		world = world,
		config = config,
		previous_tick = &previous_tick,
		frame_count = &frame_count,
	}
	live_resize_watch: platform.Live_Resize_Watch
	if watch_err := platform.watch_runtime_live_resize(
		&live_resize_watch,
		wgpu_live_resize_redraw,
		&live_resize_state,
	); watch_err != "" {
		return watch_err
	}
	defer platform.unwatch_runtime_live_resize(&live_resize_watch)

	for config.max_frames == 0 || frame_count < config.max_frames {
		if platform.pump_runtime_window_events() {
			break
		}
		if live_resize_state.err != "" { return live_resize_state.err }
		if live_resize_state.should_quit { break }
		if config.max_frames != 0 && frame_count >= config.max_frames { break }
		delta_time := wgpu_next_frame_delta(&previous_tick, frame_count > 0)
		_, should_quit, draw_err := wgpu_draw_frame(&renderer, world, config, delta_time)
		if draw_err != "" {
			return draw_err
		}
		if should_quit {
			break
		}

		frame_count += 1
		if config.ui_driver != nil && ui.diagnostic_driver_is_complete(config.ui_driver) {
			break
		}
	}
	if config.ui_driver != nil && !ui.diagnostic_driver_is_complete(config.ui_driver) {
		return fmt.tprintf(
			"UI diagnostic script did not complete within %d frames",
			config.max_frames,
		)
	}

	return ""
}
