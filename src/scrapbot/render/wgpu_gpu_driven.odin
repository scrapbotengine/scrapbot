package render

import diagnostic "../diagnostic"
import resources "../resources"
import shared "../shared"
import ui "../ui"
import "core:fmt"
import "core:math"
import "core:slice"
import "vendor:wgpu"

WGPU_INSTANCE_UPLOAD_MERGE_GAP :: 8
WGPU_OBJECT_DEBUG_RECORD_CAPACITY :: 65_536
WGPU_OCCLUSION_DEBUG_RECT_VERTEX_COUNT :: u32(8)
WGPU_OBJECT_DEBUG_VERTEX_COUNT :: WGPU_OCCLUSION_DEBUG_RECT_VERTEX_COUNT
WGPU_SHADOW_CASCADE_UPDATE_CADENCE :: [WGPU_SHADOW_CASCADE_COUNT]u64{1, 2, 4, 8}
WGPU_SHADOW_CASCADE_UPDATE_OFFSET :: [WGPU_SHADOW_CASCADE_COUNT]u64{0, 0, 3, 5}

wgpu_shadow_cascade_update_mask :: proc "contextless" (frame_index: u64, force: bool) -> u32 {
	if force {
		return (u32(1) << WGPU_SHADOW_CASCADE_COUNT) - 1
	}
	mask: u32
	cadences := WGPU_SHADOW_CASCADE_UPDATE_CADENCE
	offsets := WGPU_SHADOW_CASCADE_UPDATE_OFFSET
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		cadence := cadences[cascade_index]
		if (frame_index + offsets[cascade_index]) % cadence == 0 {
			mask |= u32(1) << u32(cascade_index)
		}
	}
	return mask
}

wgpu_retain_shadow_cascades :: proc(
	renderer: ^WGPU_Renderer,
	desired: WGPU_Shadow_Cascades,
	active: bool,
	force: bool,
) -> WGPU_Shadow_Cascades {
	if renderer == nil || !active {
		if renderer != nil {
			renderer.shadow_cascades_valid = false
			renderer.shadow_cascade_render_mask = 0
		}
		return desired
	}
	force_refresh :=
		force ||
		!renderer.shadow_cascades_valid ||
		renderer.shadow_cascade_resolution != renderer.shadow_map_resolution
	mask := wgpu_shadow_cascade_update_mask(renderer.profile_frame_index, force_refresh)
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		if mask & (u32(1) << u32(cascade_index)) == 0 {
			continue
		}
		renderer.shadow_cascades.matrices[cascade_index] = desired.matrices[cascade_index]
		renderer.shadow_cascades.splits[cascade_index] = desired.splits[cascade_index]
		renderer.shadow_cascades.texel_sizes[cascade_index] = desired.texel_sizes[cascade_index]
	}
	renderer.shadow_cascades_valid = true
	renderer.shadow_cascade_resolution = renderer.shadow_map_resolution
	renderer.shadow_cascade_render_mask = mask
	return renderer.shadow_cascades
}

WGPU_Draw_Submission_Span :: struct {
	next_batch: int,
	first_indirect: u32,
	indirect_count: u32,
}

wgpu_geometry_draw_lod_count :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	geometry: ^resources.Geometry,
) -> int {
	if geometry == nil {
		return 0
	}
	return geometry.lod_count
}

wgpu_object_debug_buffer_bytes :: proc "contextless" (capacity: int) -> u64 {
	return u64(capacity) * u64(size_of(WGPU_GPU_Object_Debug_Record))
}

wgpu_align_visible_capacity :: proc(count: u32) -> u32 {
	return(
		((max(count, 1) + WGPU_VISIBLE_ALIGNMENT - 1) / WGPU_VISIBLE_ALIGNMENT) *
		WGPU_VISIBLE_ALIGNMENT \
	)
}

wgpu_create_gpu_world_pipeline :: proc(
	renderer: ^WGPU_Renderer,
	vertex_layout: ^wgpu.VertexBufferLayout,
	cull_mode: wgpu.CullMode,
	label: string,
	vertex_entry: string = "vs_main",
) -> wgpu.RenderPipeline {
	targets := [3]wgpu.ColorTargetState {
		{format = .RGBA16Float, writeMask = wgpu.ColorWriteMaskFlags_All},
		{format = .RGBA16Float, writeMask = wgpu.ColorWriteMaskFlags_All},
		{format = .RGBA16Float, writeMask = wgpu.ColorWriteMaskFlags_All},
	}
	fragment := wgpu.FragmentState {
		module = renderer.gpu_driven_shader,
		entryPoint = "fs_main",
		targetCount = len(targets),
		targets = raw_data(targets[:]),
	}
	return wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = label,
			layout = renderer.gpu_driven_pipeline_layout,
			vertex = {
				module = renderer.gpu_driven_shader,
				entryPoint = vertex_entry,
				bufferCount = 1,
				buffers = vertex_layout,
			},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = cull_mode},
			depthStencil = &wgpu.DepthStencilState {
				format = .Depth24Plus,
				depthWriteEnabled = .False,
				depthCompare = .LessEqual,
			},
			multisample = {count = 1, mask = 0xFFFF_FFFF},
			fragment = &fragment,
		},
	)
}

wgpu_create_gpu_selection_pipeline :: proc(
	renderer: ^WGPU_Renderer,
	vertex_layout: ^wgpu.VertexBufferLayout,
	cull_mode: wgpu.CullMode,
	label: string,
	vertex_entry: string = "vs_main",
) -> wgpu.RenderPipeline {
	target := wgpu.ColorTargetState {
		format = .R32Uint,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment := wgpu.FragmentState {
		module = renderer.gpu_driven_shader,
		entryPoint = "fs_selection",
		targetCount = 1,
		targets = &target,
	}
	return wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = label,
			layout = renderer.gpu_driven_pipeline_layout,
			vertex = {
				module = renderer.gpu_driven_shader,
				entryPoint = vertex_entry,
				bufferCount = 1,
				buffers = vertex_layout,
			},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = cull_mode},
			depthStencil = &wgpu.DepthStencilState {
				format = .Depth24Plus,
				depthWriteEnabled = .True,
				depthCompare = .LessEqual,
			},
			multisample = {count = 1, mask = 0xFFFF_FFFF},
			fragment = &fragment,
		},
	)
}

wgpu_create_object_debug_pipeline :: proc(renderer: ^WGPU_Renderer) -> string {
	source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_OBJECT_DEBUG_SHADER,
	}
	renderer.gpu_object_debug_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &source,
			label = "Scrapbot Object Visibility Debug Shader",
		},
	)
	if renderer.gpu_object_debug_shader == nil {
		return "failed to create object visibility debug shader"
	}
	entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Vertex},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_GPU_Render_Uniform))},
		},
		{
			binding = 1,
			visibility = {.Vertex},
			buffer = {
				type = .ReadOnlyStorage,
				minBindingSize = u64(size_of(WGPU_GPU_Object_Debug_Record)),
			},
		},
	}
	renderer.gpu_object_debug_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Object Visibility Debug Bind Group Layout",
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
	if renderer.gpu_object_debug_bind_group_layout == nil {
		return "failed to create object visibility debug bind group layout"
	}
	renderer.gpu_object_debug_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Object Visibility Debug Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.gpu_object_debug_bind_group_layout,
		},
	)
	if renderer.gpu_object_debug_pipeline_layout == nil {
		return "failed to create object visibility debug pipeline layout"
	}
	target := wgpu.ColorTargetState {
		format = .RGBA16Float,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment := wgpu.FragmentState {
		module = renderer.gpu_object_debug_shader,
		entryPoint = "debug_fs",
		targetCount = 1,
		targets = &target,
	}
	renderer.gpu_object_debug_pipeline = wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = "Scrapbot Object Visibility Debug Pipeline",
			layout = renderer.gpu_object_debug_pipeline_layout,
			vertex = {module = renderer.gpu_object_debug_shader, entryPoint = "debug_vs"},
			primitive = {topology = .LineList, frontFace = .CCW, cullMode = .None},
			multisample = {count = 1, mask = 0xFFFF_FFFF},
			fragment = &fragment,
		},
	)
	if renderer.gpu_object_debug_pipeline == nil {
		return "failed to create object visibility debug pipeline"
	}
	return ""
}

wgpu_create_gpu_depth_pipeline :: proc(
	renderer: ^WGPU_Renderer,
	vertex_layout: ^wgpu.VertexBufferLayout,
	cull_mode: wgpu.CullMode,
	masked: bool,
	label: string,
	vertex_entry: string = "depth_vs",
) -> wgpu.RenderPipeline {
	desc := wgpu.RenderPipelineDescriptor {
		label = label,
		layout = renderer.gpu_driven_depth_pipeline_layout,
		vertex = {
			module = renderer.gpu_driven_shader,
			entryPoint = vertex_entry,
			bufferCount = 1,
			buffers = vertex_layout,
		},
		primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = cull_mode},
		depthStencil = &wgpu.DepthStencilState {
			format = .Depth24Plus,
			depthWriteEnabled = .True,
			depthCompare = .Less,
		},
		multisample = {count = 1, mask = 0xFFFF_FFFF},
	}
	fragment: wgpu.FragmentState
	if masked {
		desc.layout = renderer.gpu_driven_depth_mask_pipeline_layout
		fragment = {
			module = renderer.gpu_driven_shader,
			entryPoint = "mask_fs",
		}
		desc.fragment = &fragment
	}
	return wgpu.DeviceCreateRenderPipeline(renderer.device, &desc)
}

wgpu_create_gpu_shadow_pipeline :: proc(
	renderer: ^WGPU_Renderer,
	vertex_layout: ^wgpu.VertexBufferLayout,
	cull_mode: wgpu.CullMode,
	masked: bool,
	label: string,
	vertex_entry: string = "shadow_vs",
) -> wgpu.RenderPipeline {
	desc := wgpu.RenderPipelineDescriptor {
		label = label,
		layout = renderer.gpu_driven_shadow_pipeline_layout,
		vertex = {
			module = renderer.gpu_driven_shader,
			entryPoint = vertex_entry,
			bufferCount = 1,
			buffers = vertex_layout,
		},
		primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = cull_mode},
		depthStencil = &wgpu.DepthStencilState {
			format = .Depth32Float,
			depthWriteEnabled = .True,
			depthCompare = .Less,
			depthBias = 2,
			depthBiasSlopeScale = 2,
		},
		multisample = {count = 1, mask = 0xFFFF_FFFF},
	}
	fragment: wgpu.FragmentState
	if masked {
		desc.layout = renderer.gpu_driven_shadow_mask_pipeline_layout
		fragment = {
			module = renderer.gpu_driven_shader,
			entryPoint = "mask_fs",
		}
		desc.fragment = &fragment
	}
	return wgpu.DeviceCreateRenderPipeline(renderer.device, &desc)
}

wgpu_create_gpu_buffer :: proc(
	renderer: ^WGPU_Renderer,
	label: string,
	usage: wgpu.BufferUsageFlags,
	size: u64,
) -> wgpu.Buffer {
	return wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor{label = label, usage = usage, size = size},
	)
}

wgpu_make_cull_bind_group :: proc(
	renderer: ^WGPU_Renderer,
	batch_buffer: wgpu.Buffer,
	batch_capacity: int,
	visible_buffer, shadow_visible_buffer: wgpu.Buffer,
	visible_capacity: int,
	indirect_buffer, shadow_indirect_buffer: wgpu.Buffer,
	draw_capacity: int,
	label: string,
) -> wgpu.BindGroup {
	instance_bytes := u64(WGPU_MAX_GPU_INSTANCES) * u64(size_of(WGPU_GPU_Instance))
	batch_bytes := u64(batch_capacity) * u64(size_of(WGPU_GPU_Batch_Info))
	visible_bytes := u64(visible_capacity) * u64(size_of(u32))
	visible_binding_bytes := visible_bytes
	indirect_bytes := u64(draw_capacity) * u64(size_of(WGPU_Draw_Indexed_Indirect))
	entries := [?]wgpu.BindGroupEntry {
		{binding = 0, buffer = renderer.gpu_instance_buffer, size = instance_bytes},
		{binding = 1, buffer = batch_buffer, size = batch_bytes},
		{binding = 2, buffer = visible_buffer, size = visible_binding_bytes},
		{
			binding = 3,
			buffer = shadow_visible_buffer,
			size = visible_bytes * WGPU_SHADOW_CASCADE_COUNT,
		},
		{binding = 4, buffer = indirect_buffer, size = indirect_bytes},
		{
			binding = 5,
			buffer = shadow_indirect_buffer,
			size = indirect_bytes * WGPU_SHADOW_CASCADE_COUNT,
		},
		{
			binding = 6,
			buffer = renderer.gpu_cull_uniform_buffer,
			size = u64(size_of(WGPU_GPU_Cull_Uniform)),
		},
		{binding = 7, textureView = renderer.gpu_hiz_view},
		{
			binding = 8,
			buffer = renderer.gpu_visibility_counter_buffer,
			size = WGPU_GPU_VISIBILITY_COUNTER_BUFFER_SIZE,
		},
		{
			binding = 9,
			buffer = renderer.gpu_object_debug_record_buffer,
			size = wgpu_object_debug_buffer_bytes(WGPU_OBJECT_DEBUG_RECORD_CAPACITY),
		},
	}
	return wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = label,
			layout = renderer.gpu_cull_bind_group_layout,
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
}

WGPU_GPU_Cull_Phase :: enum u32 {
	Disabled,
	Enabled,
	Coarse_Occluder,
}

wgpu_hiz_refinement_needed :: proc "contextless" (requested, reusable: bool) -> bool {
	return requested && !reusable
}

wgpu_initial_cull_phase :: proc "contextless" (
	occlusion_enabled, refinement_requested: bool,
) -> WGPU_GPU_Cull_Phase {
	if refinement_requested {
		return .Coarse_Occluder
	}
	if occlusion_enabled {
		return .Enabled
	}
	return .Disabled
}

wgpu_cull_phase_uses_occlusion :: proc "contextless" (phase: WGPU_GPU_Cull_Phase) -> bool {
	return phase == .Enabled
}

wgpu_rebuild_object_debug_bind_group :: proc(renderer: ^WGPU_Renderer) -> string {
	if renderer.gpu_object_debug_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_object_debug_bind_group)
		renderer.gpu_object_debug_bind_group = nil
	}
	entries := [?]wgpu.BindGroupEntry {
		{
			binding = 0,
			buffer = renderer.gpu_render_uniform_buffer,
			size = u64(size_of(WGPU_GPU_Render_Uniform)),
		},
		{
			binding = 1,
			buffer = renderer.gpu_object_debug_record_buffer,
			size = wgpu_object_debug_buffer_bytes(WGPU_OBJECT_DEBUG_RECORD_CAPACITY),
		},
	}
	renderer.gpu_object_debug_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Object Visibility Debug Bind Group",
			layout = renderer.gpu_object_debug_bind_group_layout,
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
	if renderer.gpu_object_debug_bind_group == nil {
		return "failed to create object visibility debug bind group"
	}
	return ""
}

wgpu_create_gpu_driven_pipelines :: proc(renderer: ^WGPU_Renderer) -> string {
	render_source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_GPU_DRIVEN_SHADER,
	}
	renderer.gpu_driven_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &render_source,
			label = "Scrapbot GPU-Driven Render Shader",
		},
	)
	if renderer.gpu_driven_shader == nil {
		return "failed to create GPU-driven render shader"
	}
	if debug_err := wgpu_create_object_debug_pipeline(renderer); debug_err != "" {
		return debug_err
	}
	if cluster_err := wgpu_create_clustered_lighting(renderer); cluster_err != "" {
		return cluster_err
	}

	world_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Vertex, .Fragment, .Compute},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_GPU_Render_Uniform))},
		},
		{
			binding = 1,
			visibility = {.Fragment},
			texture = {sampleType = .Depth, viewDimension = ._2DArray},
		},
		{binding = 2, visibility = {.Fragment}, sampler = {type = .Comparison}},
		{
			binding = 3,
			visibility = {.Vertex, .Compute},
			buffer = {type = .ReadOnlyStorage, minBindingSize = u64(size_of(WGPU_GPU_Instance))},
		},
		{
			binding = 4,
			visibility = {.Vertex},
			buffer = {type = .ReadOnlyStorage, minBindingSize = 4},
		},
		{binding = 5, visibility = {.Fragment}, buffer = {type = .ReadOnlyStorage}},
		{binding = 6, visibility = {.Fragment}, buffer = {type = .ReadOnlyStorage}},
		{binding = 7, visibility = {.Fragment}, buffer = {type = .ReadOnlyStorage}},
		{
			binding = 8,
			visibility = {.Fragment},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_Cluster_Uniform))},
		},
	}
	renderer.gpu_driven_world_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot GPU-Driven World Bind Group Layout",
			entryCount = uint(len(world_entries)),
			entries = raw_data(world_entries[:]),
		},
	)
	if renderer.gpu_driven_world_bind_group_layout == nil {
		return "failed to create GPU-driven world bind group layout"
	}
	shadow_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Vertex},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_GPU_Render_Uniform))},
		},
		{
			binding = 3,
			visibility = {.Vertex},
			buffer = {type = .ReadOnlyStorage, minBindingSize = u64(size_of(WGPU_GPU_Instance))},
		},
		{
			binding = 4,
			visibility = {.Vertex},
			buffer = {type = .ReadOnlyStorage, minBindingSize = 4},
		},
		{
			binding = 9,
			visibility = {.Vertex},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_Shadow_Cascade_Uniform))},
		},
	}
	renderer.gpu_driven_shadow_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot GPU-Driven Shadow Bind Group Layout",
			entryCount = uint(len(shadow_entries)),
			entries = raw_data(shadow_entries[:]),
		},
	)
	if renderer.gpu_driven_shadow_bind_group_layout == nil {
		return "failed to create GPU-driven shadow bind group layout"
	}

	world_layouts := [?]wgpu.BindGroupLayout {
		renderer.gpu_driven_world_bind_group_layout,
		renderer.material_bind_group_layout,
		renderer.environment_bind_group_layout,
	}
	renderer.gpu_driven_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot GPU-Driven Pipeline Layout",
			bindGroupLayoutCount = uint(len(world_layouts)),
			bindGroupLayouts = raw_data(world_layouts[:]),
		},
	)
	if renderer.gpu_driven_pipeline_layout == nil {
		return "failed to create GPU-driven pipeline layout"
	}
	renderer.gpu_driven_shadow_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot GPU-Driven Shadow Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.gpu_driven_shadow_bind_group_layout,
		},
	)
	if renderer.gpu_driven_shadow_pipeline_layout == nil {
		return "failed to create GPU-driven shadow pipeline layout"
	}
	depth_mask_layouts := [?]wgpu.BindGroupLayout {
		renderer.gpu_driven_world_bind_group_layout,
		renderer.material_bind_group_layout,
	}
	renderer.gpu_driven_depth_mask_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot GPU-Driven Masked Depth Pipeline Layout",
			bindGroupLayoutCount = uint(len(depth_mask_layouts)),
			bindGroupLayouts = raw_data(depth_mask_layouts[:]),
		},
	)
	shadow_mask_layouts := [?]wgpu.BindGroupLayout {
		renderer.gpu_driven_shadow_bind_group_layout,
		renderer.material_bind_group_layout,
	}
	renderer.gpu_driven_shadow_mask_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot GPU-Driven Masked Shadow Pipeline Layout",
			bindGroupLayoutCount = uint(len(shadow_mask_layouts)),
			bindGroupLayouts = raw_data(shadow_mask_layouts[:]),
		},
	)
	if renderer.gpu_driven_depth_mask_pipeline_layout == nil ||
	   renderer.gpu_driven_shadow_mask_pipeline_layout == nil {
		return "failed to create GPU-driven masked material pipeline layouts"
	}

	vertex_attributes := [?]wgpu.VertexAttribute {
		{format = .Float32x3, offset = 0, shaderLocation = 0},
		{format = .Float32x3, offset = 12, shaderLocation = 1},
		{format = .Float32x2, offset = 24, shaderLocation = 2},
		{format = .Float32x4, offset = 32, shaderLocation = 3},
	}
	vertex_buffer_layout := wgpu.VertexBufferLayout {
		stepMode = .Vertex,
		arrayStride = u64(size_of(resources.Vertex)),
		attributeCount = uint(len(vertex_attributes)),
		attributes = raw_data(vertex_attributes[:]),
	}
	renderer.gpu_driven_pipeline = wgpu_create_gpu_world_pipeline(
		renderer,
		&vertex_buffer_layout,
		.Back,
		"Scrapbot GPU-Driven Render Pipeline",
	)
	renderer.gpu_driven_double_sided_pipeline = wgpu_create_gpu_world_pipeline(
		renderer,
		&vertex_buffer_layout,
		.None,
		"Scrapbot GPU-Driven Double-Sided Render Pipeline",
	)
	renderer.gpu_selection_pipeline = wgpu_create_gpu_selection_pipeline(
		renderer,
		&vertex_buffer_layout,
		.Back,
		"Scrapbot GPU Selection Pipeline",
	)
	renderer.gpu_selection_double_sided_pipeline = wgpu_create_gpu_selection_pipeline(
		renderer,
		&vertex_buffer_layout,
		.None,
		"Scrapbot GPU Double-Sided Selection Pipeline",
	)
	renderer.gpu_driven_depth_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot GPU-Driven Depth Prepass Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.gpu_driven_world_bind_group_layout,
		},
	)
	if renderer.gpu_driven_depth_pipeline_layout == nil {
		return "failed to create GPU-driven depth prepass pipeline layout"
	}
	renderer.gpu_driven_depth_pipeline = wgpu_create_gpu_depth_pipeline(
		renderer,
		&vertex_buffer_layout,
		.Back,
		false,
		"Scrapbot GPU-Driven Depth Prepass Pipeline",
	)
	renderer.gpu_driven_depth_double_sided_pipeline = wgpu_create_gpu_depth_pipeline(
		renderer,
		&vertex_buffer_layout,
		.None,
		false,
		"Scrapbot GPU-Driven Double-Sided Depth Pipeline",
	)
	renderer.gpu_driven_depth_mask_pipeline = wgpu_create_gpu_depth_pipeline(
		renderer,
		&vertex_buffer_layout,
		.Back,
		true,
		"Scrapbot GPU-Driven Masked Depth Pipeline",
	)
	renderer.gpu_driven_depth_mask_double_sided_pipeline = wgpu_create_gpu_depth_pipeline(
		renderer,
		&vertex_buffer_layout,
		.None,
		true,
		"Scrapbot GPU-Driven Masked Double-Sided Depth Pipeline",
	)
	renderer.gpu_driven_shadow_pipeline = wgpu_create_gpu_shadow_pipeline(
		renderer,
		&vertex_buffer_layout,
		.Back,
		false,
		"Scrapbot GPU-Driven Shadow Pipeline",
	)
	renderer.gpu_driven_shadow_double_sided_pipeline = wgpu_create_gpu_shadow_pipeline(
		renderer,
		&vertex_buffer_layout,
		.None,
		false,
		"Scrapbot GPU-Driven Double-Sided Shadow Pipeline",
	)
	renderer.gpu_driven_shadow_mask_pipeline = wgpu_create_gpu_shadow_pipeline(
		renderer,
		&vertex_buffer_layout,
		.Back,
		true,
		"Scrapbot GPU-Driven Masked Shadow Pipeline",
	)
	renderer.gpu_driven_shadow_mask_double_sided_pipeline = wgpu_create_gpu_shadow_pipeline(
		renderer,
		&vertex_buffer_layout,
		.None,
		true,
		"Scrapbot GPU-Driven Masked Double-Sided Shadow Pipeline",
	)
	if renderer.gpu_driven_pipeline == nil ||
	   renderer.gpu_driven_double_sided_pipeline == nil ||
	   renderer.gpu_selection_pipeline == nil ||
	   renderer.gpu_selection_double_sided_pipeline == nil ||
	   renderer.gpu_driven_depth_pipeline == nil ||
	   renderer.gpu_driven_depth_double_sided_pipeline == nil ||
	   renderer.gpu_driven_depth_mask_pipeline == nil ||
	   renderer.gpu_driven_depth_mask_double_sided_pipeline == nil ||
	   renderer.gpu_driven_shadow_pipeline == nil ||
	   renderer.gpu_driven_shadow_double_sided_pipeline == nil ||
	   renderer.gpu_driven_shadow_mask_pipeline == nil ||
	   renderer.gpu_driven_shadow_mask_double_sided_pipeline == nil {
		return "failed to create GPU-driven material render pipelines"
	}

	transform_source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_GPU_TRANSFORM_SHADER,
	}
	renderer.gpu_transform_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &transform_source,
			label = "Scrapbot GPU Transform Shader",
		},
	)
	if renderer.gpu_transform_shader == nil {
		return "failed to create GPU transform shader"
	}
	transform_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			buffer = {
				type = .ReadOnlyStorage,
				minBindingSize = u64(size_of(WGPU_GPU_Instance_Transform)),
			},
		},
		{
			binding = 1,
			visibility = {.Compute},
			buffer = {type = .Storage, minBindingSize = u64(size_of(WGPU_GPU_Instance))},
		},
	}
	renderer.gpu_transform_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot GPU Transform Bind Group Layout",
			entryCount = uint(len(transform_entries)),
			entries = raw_data(transform_entries[:]),
		},
	)
	if renderer.gpu_transform_bind_group_layout == nil {
		return "failed to create GPU transform bind group layout"
	}
	renderer.gpu_transform_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot GPU Transform Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.gpu_transform_bind_group_layout,
		},
	)
	if renderer.gpu_transform_pipeline_layout == nil {
		return "failed to create GPU transform pipeline layout"
	}
	renderer.gpu_transform_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot GPU Transform Pipeline",
			layout = renderer.gpu_transform_pipeline_layout,
			compute = {module = renderer.gpu_transform_shader, entryPoint = "expand_transforms"},
		},
	)
	if renderer.gpu_transform_pipeline == nil {
		return "failed to create GPU transform pipeline"
	}

	cull_source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_GPU_CULL_SHADER,
	}
	renderer.gpu_cull_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &cull_source,
			label = "Scrapbot GPU Culling Shader",
		},
	)
	if renderer.gpu_cull_shader == nil {
		return "failed to create GPU culling shader"
	}
	cull_entries := [?]wgpu.BindGroupLayoutEntry {
		{binding = 0, visibility = {.Compute}, buffer = {type = .ReadOnlyStorage}},
		{binding = 1, visibility = {.Compute}, buffer = {type = .ReadOnlyStorage}},
		{binding = 2, visibility = {.Compute}, buffer = {type = .Storage}},
		{binding = 3, visibility = {.Compute}, buffer = {type = .Storage}},
		{binding = 4, visibility = {.Compute}, buffer = {type = .Storage}},
		{binding = 5, visibility = {.Compute}, buffer = {type = .Storage}},
		{
			binding = 6,
			visibility = {.Compute},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_GPU_Cull_Uniform))},
		},
		{
			binding = 7,
			visibility = {.Compute},
			texture = {sampleType = .UnfilterableFloat, viewDimension = ._2D},
		},
		{binding = 8, visibility = {.Compute}, buffer = {type = .Storage}},
		{binding = 9, visibility = {.Compute}, buffer = {type = .Storage}},
	}
	renderer.gpu_cull_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot GPU Culling Bind Group Layout",
			entryCount = uint(len(cull_entries)),
			entries = raw_data(cull_entries[:]),
		},
	)
	if renderer.gpu_cull_bind_group_layout == nil {
		return "failed to create GPU culling bind group layout"
	}
	renderer.gpu_cull_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot GPU Culling Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.gpu_cull_bind_group_layout,
		},
	)
	if renderer.gpu_cull_pipeline_layout == nil {
		return "failed to create GPU culling pipeline layout"
	}
	renderer.gpu_cull_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot GPU Classic Culling Pipeline",
			layout = renderer.gpu_cull_pipeline_layout,
			compute = {module = renderer.gpu_cull_shader, entryPoint = "cull_classic_instances"},
		},
	)
	if renderer.gpu_cull_pipeline == nil {
		return "failed to create GPU culling pipelines"
	}
	renderer.gpu_object_debug_cull_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Object Visibility Evidence Pipeline",
			layout = renderer.gpu_cull_pipeline_layout,
			compute = {
				module = renderer.gpu_cull_shader,
				entryPoint = "capture_object_visibility",
			},
		},
	)
	if renderer.gpu_object_debug_cull_pipeline == nil {
		return "failed to create object visibility evidence pipeline"
	}
	if hiz_err := wgpu_create_hiz_pipelines(renderer); hiz_err != "" {
		return hiz_err
	}
	if distance_field_err := wgpu_create_distance_field_debug_pipeline(renderer);
	   distance_field_err != "" {
		return distance_field_err
	}
	if clipmap_err := wgpu_create_distance_field_clipmap_pipeline(renderer); clipmap_err != "" {
		return clipmap_err
	}
	if hiz_err := wgpu_ensure_hiz_targets(renderer, 1, 1); hiz_err != "" {
		return hiz_err
	}

	instance_bytes := u64(WGPU_MAX_GPU_INSTANCES) * u64(size_of(WGPU_GPU_Instance))
	transform_update_bytes :=
		u64(WGPU_MAX_GPU_INSTANCES + 1) * u64(size_of(WGPU_GPU_Instance_Transform))
	visible_entries := WGPU_MAX_GPU_INSTANCES + WGPU_INITIAL_DRAW_CAPACITY * WGPU_VISIBLE_ALIGNMENT
	visible_bytes := u64(visible_entries) * u64(size_of(u32))
	shadow_visible_bytes := visible_bytes * WGPU_SHADOW_CASCADE_COUNT
	batch_bytes := u64(WGPU_INITIAL_DRAW_CAPACITY) * u64(size_of(WGPU_GPU_Batch_Info))
	indirect_bytes := u64(WGPU_INITIAL_DRAW_CAPACITY) * u64(size_of(WGPU_Draw_Indexed_Indirect))
	renderer.gpu_instance_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Instance Table",
		{.Storage, .CopyDst},
		instance_bytes,
	)
	renderer.gpu_transform_update_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Transform Updates",
		{.Storage, .CopyDst},
		transform_update_bytes,
	)
	renderer.gpu_batch_info_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Batch Table",
		{.Storage, .CopyDst},
		batch_bytes,
	)
	renderer.gpu_visible_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Visible Instances",
		{.Storage, .CopyDst},
		visible_bytes,
	)
	renderer.gpu_shadow_visible_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Shadow Visible Instances",
		{.Storage, .CopyDst},
		shadow_visible_bytes,
	)
	renderer.gpu_indirect_template_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Indirect Template",
		{.CopySrc, .CopyDst},
		indirect_bytes,
	)
	renderer.gpu_shadow_indirect_template_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Shadow Indirect Template",
		{.CopySrc, .CopyDst},
		indirect_bytes,
	)
	renderer.gpu_indirect_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Indirect Draws",
		{.Storage, .Indirect, .CopyDst},
		indirect_bytes,
	)
	renderer.gpu_shadow_indirect_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Shadow Indirect Draws",
		{.Storage, .Indirect, .CopyDst},
		indirect_bytes * WGPU_SHADOW_CASCADE_COUNT,
	)
	renderer.gpu_object_debug_indirect_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Object Visibility Debug Indirect Draw",
		{.Storage, .Indirect, .CopyDst},
		u64(size_of(WGPU_Draw_Indirect)),
	)
	renderer.gpu_object_debug_record_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Object Visibility Debug Records",
		{.Storage, .CopySrc},
		wgpu_object_debug_buffer_bytes(WGPU_OBJECT_DEBUG_RECORD_CAPACITY),
	)
	renderer.gpu_cull_uniform_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Culling Uniform",
		{.Uniform, .CopyDst},
		u64(size_of(WGPU_GPU_Cull_Uniform)),
	)
	renderer.gpu_cull_initial_uniform_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Initial Culling Uniform",
		{.CopySrc, .CopyDst},
		u64(size_of(WGPU_GPU_Cull_Uniform)),
	)
	renderer.gpu_cull_refine_uniform_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Refined Culling Uniform",
		{.CopySrc, .CopyDst},
		u64(size_of(WGPU_GPU_Cull_Uniform)),
	)
	renderer.gpu_render_uniform_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Render Uniform",
		{.Uniform, .CopyDst},
		u64(size_of(WGPU_GPU_Render_Uniform)),
	)
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		renderer.gpu_shadow_cascade_uniform_buffers[cascade_index] = wgpu_create_gpu_buffer(
			renderer,
			"Scrapbot Shadow Cascade Uniform",
			{.Uniform, .CopyDst},
			u64(size_of(WGPU_Shadow_Cascade_Uniform)),
		)
		if renderer.gpu_shadow_cascade_uniform_buffers[cascade_index] == nil {
			return "failed to allocate shadow cascade uniform buffer"
		}
		cascade_uniform := WGPU_Shadow_Cascade_Uniform {
			index = u32(cascade_index),
		}
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_shadow_cascade_uniform_buffers[cascade_index],
			0,
			&cascade_uniform,
			uint(size_of(cascade_uniform)),
		)
	}
	renderer.gpu_visibility_counter_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Visibility Counters",
		{.Storage, .CopySrc, .CopyDst},
		WGPU_GPU_VISIBILITY_COUNTER_BUFFER_SIZE,
	)
	if renderer.gpu_instance_buffer == nil ||
	   renderer.gpu_transform_update_buffer == nil ||
	   renderer.gpu_batch_info_buffer == nil ||
	   renderer.gpu_visible_buffer == nil ||
	   renderer.gpu_shadow_visible_buffer == nil ||
	   renderer.gpu_indirect_template_buffer == nil ||
	   renderer.gpu_shadow_indirect_template_buffer == nil ||
	   renderer.gpu_indirect_buffer == nil ||
	   renderer.gpu_shadow_indirect_buffer == nil ||
	   renderer.gpu_object_debug_indirect_buffer == nil ||
	   renderer.gpu_object_debug_record_buffer == nil ||
	   renderer.gpu_cull_uniform_buffer == nil ||
	   renderer.gpu_cull_initial_uniform_buffer == nil ||
	   renderer.gpu_cull_refine_uniform_buffer == nil ||
	   renderer.gpu_render_uniform_buffer == nil ||
	   renderer.gpu_visibility_counter_buffer == nil {
		return "failed to allocate GPU-driven renderer buffers"
	}
	transform_bind_entries := [?]wgpu.BindGroupEntry {
		{
			binding = 0,
			buffer = renderer.gpu_transform_update_buffer,
			size = transform_update_bytes,
		},
		{binding = 1, buffer = renderer.gpu_instance_buffer, size = instance_bytes},
	}
	renderer.gpu_transform_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot GPU Transform Bind Group",
			layout = renderer.gpu_transform_bind_group_layout,
			entryCount = uint(len(transform_bind_entries)),
			entries = raw_data(transform_bind_entries[:]),
		},
	)
	if renderer.gpu_transform_bind_group == nil {
		return "failed to create GPU transform bind group"
	}

	renderer.gpu_draw_capacity = WGPU_INITIAL_DRAW_CAPACITY
	renderer.gpu_visible_buffer_capacity = visible_entries
	if debug_err := wgpu_rebuild_object_debug_bind_group(renderer); debug_err != "" {
		return debug_err
	}
	if debug_err := wgpu_rebuild_hiz_debug_bind_group(renderer); debug_err != "" {
		return debug_err
	}
	if err := wgpu_rebuild_cull_bind_group(renderer); err != "" {
		return err
	}
	if visibility_err := wgpu_create_visibility_readbacks(renderer); visibility_err != "" {
		return visibility_err
	}
	return ""
}

wgpu_grow_capacity :: proc "contextless" (current, required: int) -> int {
	capacity := max(current, 1)
	for capacity < required {
		capacity *= 2
	}
	return capacity
}

wgpu_rebuild_cull_bind_group :: proc(renderer: ^WGPU_Renderer) -> string {
	if renderer == nil ||
	   renderer.gpu_instance_buffer == nil ||
	   renderer.gpu_batch_info_buffer == nil ||
	   renderer.gpu_hiz_view == nil {
		return ""
	}
	bind_group := wgpu_make_cull_bind_group(
		renderer,
		renderer.gpu_batch_info_buffer,
		renderer.gpu_draw_capacity,
		renderer.gpu_visible_buffer,
		renderer.gpu_shadow_visible_buffer,
		renderer.gpu_visible_buffer_capacity,
		renderer.gpu_indirect_buffer,
		renderer.gpu_shadow_indirect_buffer,
		renderer.gpu_draw_capacity,
		"Scrapbot GPU Culling Bind Group",
	)
	if bind_group == nil {
		return "failed to rebuild GPU culling bind group"
	}
	if renderer.gpu_cull_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_cull_bind_group)
	}
	renderer.gpu_cull_bind_group = bind_group
	return ""
}

wgpu_ensure_gpu_draw_buffers :: proc(
	renderer: ^WGPU_Renderer,
	required_batches, required_visible: int,
) -> string {
	if required_batches <= renderer.gpu_draw_capacity &&
	   required_visible <= renderer.gpu_visible_buffer_capacity {
		return ""
	}
	draw_capacity := wgpu_grow_capacity(renderer.gpu_draw_capacity, required_batches)
	visible_capacity := wgpu_grow_capacity(renderer.gpu_visible_buffer_capacity, required_visible)
	batch_bytes := u64(draw_capacity) * u64(size_of(WGPU_GPU_Batch_Info))
	visible_bytes := u64(visible_capacity) * u64(size_of(u32))
	shadow_visible_bytes := visible_bytes * WGPU_SHADOW_CASCADE_COUNT
	indirect_bytes := u64(draw_capacity) * u64(size_of(WGPU_Draw_Indexed_Indirect))
	shadow_indirect_bytes := indirect_bytes * WGPU_SHADOW_CASCADE_COUNT
	batch_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Batch Table",
		{.Storage, .CopyDst},
		batch_bytes,
	)
	visible_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Visible Instances",
		{.Storage, .CopyDst},
		visible_bytes,
	)
	shadow_visible_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Shadow Visible Instances",
		{.Storage, .CopyDst},
		shadow_visible_bytes,
	)
	indirect_template_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Indirect Template",
		{.CopySrc, .CopyDst},
		indirect_bytes,
	)
	shadow_indirect_template_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Shadow Indirect Template",
		{.CopySrc, .CopyDst},
		indirect_bytes,
	)
	indirect_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Indirect Draws",
		{.Storage, .Indirect, .CopyDst},
		indirect_bytes,
	)
	shadow_indirect_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Shadow Indirect Draws",
		{.Storage, .Indirect, .CopyDst},
		shadow_indirect_bytes,
	)
	new_buffers := [?]wgpu.Buffer {
		batch_buffer,
		visible_buffer,
		shadow_visible_buffer,
		indirect_template_buffer,
		shadow_indirect_template_buffer,
		indirect_buffer,
		shadow_indirect_buffer,
	}
	for buffer in new_buffers {
		if buffer == nil {
			for cleanup in new_buffers {
				if cleanup != nil {
					wgpu.BufferRelease(cleanup)
				}
			}
			return "failed to grow GPU draw database buffers"
		}
	}
	cull_bind_group := wgpu_make_cull_bind_group(
		renderer,
		batch_buffer,
		draw_capacity,
		visible_buffer,
		shadow_visible_buffer,
		visible_capacity,
		indirect_buffer,
		shadow_indirect_buffer,
		draw_capacity,
		"Scrapbot GPU Culling Bind Group",
	)
	if cull_bind_group == nil {
		if cull_bind_group != nil {
			wgpu.BindGroupRelease(cull_bind_group)
		}
		for buffer in new_buffers {
			wgpu.BufferRelease(buffer)
		}
		return "failed to grow GPU culling bind groups"
	}
	if renderer.gpu_cull_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_cull_bind_group)
	}
	old_buffers := [?]wgpu.Buffer {
		renderer.gpu_batch_info_buffer,
		renderer.gpu_visible_buffer,
		renderer.gpu_shadow_visible_buffer,
		renderer.gpu_indirect_template_buffer,
		renderer.gpu_shadow_indirect_template_buffer,
		renderer.gpu_indirect_buffer,
		renderer.gpu_shadow_indirect_buffer,
	}
	for buffer in old_buffers {
		if buffer != nil {
			wgpu.BufferRelease(buffer)
		}
	}
	renderer.gpu_batch_info_buffer = batch_buffer
	renderer.gpu_visible_buffer = visible_buffer
	renderer.gpu_shadow_visible_buffer = shadow_visible_buffer
	renderer.gpu_indirect_template_buffer = indirect_template_buffer
	renderer.gpu_shadow_indirect_template_buffer = shadow_indirect_template_buffer
	renderer.gpu_indirect_buffer = indirect_buffer
	renderer.gpu_shadow_indirect_buffer = shadow_indirect_buffer
	renderer.gpu_cull_bind_group = cull_bind_group
	renderer.gpu_draw_capacity = draw_capacity
	renderer.gpu_visible_buffer_capacity = visible_capacity
	renderer.gpu_draw_database_rebuild_count += 1
	clear(&renderer.gpu_indirect_templates)
	clear(&renderer.gpu_shadow_indirect_templates)
	return wgpu_rebuild_cull_bind_group(renderer)
}

wgpu_release_batch_bind_groups :: proc(cache: ^WGPU_Draw_Batch_Cache) {
	if cache == nil {
		return
	}
	for batch_index in 0 ..< cache.batch_count {
		batch := &cache.batches[batch_index]
		if batch.world_bind_group != nil {
			wgpu.BindGroupRelease(batch.world_bind_group)
		}
		for shadow_bind_group in batch.shadow_bind_groups {
			if shadow_bind_group != nil {
				wgpu.BindGroupRelease(shadow_bind_group)
			}
		}
		batch.world_bind_group = nil
		batch.shadow_bind_groups = {}
	}
}

wgpu_make_batch_bind_group :: proc(
	renderer: ^WGPU_Renderer,
	visible_buffer: wgpu.Buffer,
	visible_offset, visible_capacity: u32,
	label: string,
	shadow: bool = false,
	shadow_cascade_index: int = 0,
	shadow_visible_stride: int = 0,
) -> wgpu.BindGroup {
	if shadow {
		visible_stride := shadow_visible_stride
		if visible_stride <= 0 {
			visible_stride = renderer.gpu_visible_buffer_capacity
		}
		entries := [?]wgpu.BindGroupEntry {
			{
				binding = 0,
				buffer = renderer.gpu_render_uniform_buffer,
				size = u64(size_of(WGPU_GPU_Render_Uniform)),
			},
			{
				binding = 3,
				buffer = renderer.gpu_instance_buffer,
				size = u64(WGPU_MAX_GPU_INSTANCES) * u64(size_of(WGPU_GPU_Instance)),
			},
			{
				binding = 4,
				buffer = visible_buffer,
				offset = u64(shadow_cascade_index * visible_stride + int(visible_offset)) *
				u64(size_of(u32)),
				size = u64(visible_capacity) * u64(size_of(u32)),
			},
			{
				binding = 9,
				buffer = renderer.gpu_shadow_cascade_uniform_buffers[shadow_cascade_index],
				size = u64(size_of(WGPU_Shadow_Cascade_Uniform)),
			},
		}
		return wgpu.DeviceCreateBindGroup(
			renderer.device,
			&wgpu.BindGroupDescriptor {
				label = label,
				layout = renderer.gpu_driven_shadow_bind_group_layout,
				entryCount = uint(len(entries)),
				entries = raw_data(entries[:]),
			},
		)
	}
	entries := [?]wgpu.BindGroupEntry {
		{
			binding = 0,
			buffer = renderer.gpu_render_uniform_buffer,
			size = u64(size_of(WGPU_GPU_Render_Uniform)),
		},
		{binding = 1, textureView = renderer.shadow_array_view},
		{binding = 2, sampler = renderer.shadow_sampler},
		{
			binding = 3,
			buffer = renderer.gpu_instance_buffer,
			size = u64(WGPU_MAX_GPU_INSTANCES) * u64(size_of(WGPU_GPU_Instance)),
		},
		{
			binding = 4,
			buffer = visible_buffer,
			offset = u64(visible_offset) * u64(size_of(u32)),
			size = u64(visible_capacity) * u64(size_of(u32)),
		},
		{
			binding = 5,
			buffer = renderer.gpu_point_light_buffer,
			size = u64(renderer.gpu_point_light_capacity) * u64(size_of(WGPU_GPU_Point_Light)),
		},
		{
			binding = 6,
			buffer = renderer.gpu_cluster_count_buffer,
			size = u64(WGPU_CLUSTER_COUNT) * u64(size_of(u32)),
		},
		{
			binding = 7,
			buffer = renderer.gpu_cluster_index_buffer,
			size = u64(WGPU_CLUSTER_COUNT * renderer.gpu_cluster_light_capacity) *
			u64(size_of(u32)),
		},
		{
			binding = 8,
			buffer = renderer.gpu_cluster_uniform_buffer,
			size = u64(size_of(WGPU_Cluster_Uniform)),
		},
	}
	return wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = label,
			layout = renderer.gpu_driven_world_bind_group_layout,
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
}

wgpu_sync_gpu_topology :: proc(
	renderer: ^WGPU_Renderer,
	render_list: ^Render_List,
	registry: ^resources.Registry,
) -> (
	^WGPU_Draw_Batch_Cache,
	string,
) {
	topology_changed :=
		!renderer.gpu_topology_valid ||
		!renderer.draw_batch_cache.valid ||
		renderer.gpu_world_uuid != render_list.world_uuid ||
		renderer.gpu_topology_revision != render_list.topology_revision ||
		renderer.draw_batch_cache.geometry_topology_revision != registry.geometry_topology_revision
	cache := wgpu_ensure_draw_batch_cache(renderer, render_list, registry)
	if cache == nil {
		return nil, "failed to build GPU draw batches"
	}
	if !topology_changed {
		return cache, ""
	}
	if err := wgpu_refresh_gpu_batch_layout(renderer, cache, registry); err != "" {
		return nil, err
	}
	renderer.gpu_topology_revision = render_list.topology_revision
	renderer.gpu_world_uuid = render_list.world_uuid
	renderer.gpu_topology_valid = true
	return cache, ""
}

wgpu_refresh_gpu_batch_layout :: proc(
	renderer: ^WGPU_Renderer,
	cache: ^WGPU_Draw_Batch_Cache,
	registry: ^resources.Registry,
) -> string {
	wgpu_release_batch_bind_groups(cache)
	visible_offset: u32
	instance_count := 0
	for &batch in cache.batches[:cache.batch_count] {
		batch.visible_offset = visible_offset
		batch.visible_capacity = wgpu_align_visible_capacity(batch.instance_count)
		visible_offset += batch.visible_capacity
		instance_count += int(batch.instance_count)
		material, ok := resources.get_material(registry, batch.material)
		if !ok {
			return "GPU draw batch references unavailable material"
		}
		batch.custom_shader = material.desc.shader != (shared.Shader_Handle{})
	}
	renderer.gpu_indirect_command_count = cache.batch_count
	if err := wgpu_ensure_gpu_draw_buffers(renderer, cache.batch_count, int(visible_offset));
	   err != "" {
		return err
	}
	batch_info := make([]WGPU_GPU_Batch_Info, cache.batch_count)
	defer delete(batch_info)
	for &batch, batch_index in cache.batches[:cache.batch_count] {
		if _, err := wgpu_geometry_cache(renderer, registry, batch.geometry); err != "" {
			return err
		}
		batch_info[batch_index] = {
			visible_offset = batch.visible_offset,
			visible_capacity = batch.visible_capacity,
		}
		batch.world_bind_group = wgpu_make_batch_bind_group(
			renderer,
			renderer.gpu_visible_buffer,
			batch.visible_offset,
			batch.visible_capacity,
			"Scrapbot GPU-Driven Batch Bind Group",
		)
		if batch.world_bind_group == nil {
			return "failed to create GPU-driven batch bind group"
		}
		for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
			batch.shadow_bind_groups[cascade_index] = wgpu_make_batch_bind_group(
				renderer,
				renderer.gpu_shadow_visible_buffer,
				batch.visible_offset,
				batch.visible_capacity,
				"Scrapbot GPU-Driven Shadow Batch Bind Group",
				true,
				cascade_index,
			)
			if batch.shadow_bind_groups[cascade_index] == nil {
				return "failed to create GPU-driven shadow batch bind group"
			}
		}
	}
	renderer.gpu_visible_capacity = int(visible_offset)
	renderer.gpu_classic_batch_count = cache.batch_count
	if len(batch_info) > 0 {
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_batch_info_buffer,
			0,
			raw_data(batch_info),
			uint(len(batch_info) * size_of(WGPU_GPU_Batch_Info)),
		)
	}
	return wgpu_rebuild_transparent_world_bind_group(renderer)
}

wgpu_update_indirect_template_cache :: proc(
	renderer: ^WGPU_Renderer,
	cache: ^WGPU_Draw_Batch_Cache,
	registry: ^resources.Registry,
) -> (
	changed: bool,
	err: string,
) {
	if renderer == nil || cache == nil {
		return false, "GPU draw-batch cache is not available"
	}
	command_count := max(renderer.gpu_indirect_command_count, cache.batch_count)
	if len(renderer.gpu_indirect_templates) != command_count {
		resize(&renderer.gpu_indirect_templates, command_count)
		changed = true
	}
	if len(renderer.gpu_shadow_indirect_templates) != command_count {
		resize(&renderer.gpu_shadow_indirect_templates, command_count)
		changed = true
	}
	for batch, batch_index in cache.batches[:cache.batch_count] {
		geometry, geometry_err := wgpu_geometry_cache(renderer, registry, batch.geometry)
		if geometry_err != "" {
			return false, geometry_err
		}
		template := wgpu_geometry_indirect_template(geometry)
		shadow_template := template
		if renderer.gpu_indirect_templates[batch_index] != template {
			renderer.gpu_indirect_templates[batch_index] = template
			changed = true
		}
		if renderer.gpu_shadow_indirect_templates[batch_index] != shadow_template {
			renderer.gpu_shadow_indirect_templates[batch_index] = shadow_template
			changed = true
		}
	}
	return
}

wgpu_geometry_indirect_template :: proc "contextless" (
	geometry: ^WGPU_Geometry_Cache,
) -> WGPU_Draw_Indexed_Indirect {
	if geometry == nil {
		return {}
	}
	return {
		index_count = geometry.index_count,
		first_index = u32(geometry.index_range.offset / u64(size_of(u32))),
		base_vertex = i32(geometry.vertex_range.offset / u64(size_of(resources.Vertex))),
		first_instance = 0,
	}
}

wgpu_refresh_indirect_templates :: proc(
	renderer: ^WGPU_Renderer,
	cache: ^WGPU_Draw_Batch_Cache,
	registry: ^resources.Registry,
) -> string {
	changed, err := wgpu_update_indirect_template_cache(renderer, cache, registry)
	if err != "" {
		return err
	}
	if !changed {
		return ""
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_indirect_template_buffer,
		0,
		raw_data(renderer.gpu_indirect_templates[:]),
		uint(len(renderer.gpu_indirect_templates) * size_of(WGPU_Draw_Indexed_Indirect)),
	)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_shadow_indirect_template_buffer,
		0,
		raw_data(renderer.gpu_shadow_indirect_templates[:]),
		uint(len(renderer.gpu_shadow_indirect_templates) * size_of(WGPU_Draw_Indexed_Indirect)),
	)
	return ""
}

wgpu_instance_local_bounds :: proc(geometry: ^resources.Geometry) -> [4]f32 {
	center := Vec3 {
		(geometry.bounds.min.x + geometry.bounds.max.x) * 0.5,
		(geometry.bounds.min.y + geometry.bounds.max.y) * 0.5,
		(geometry.bounds.min.z + geometry.bounds.max.z) * 0.5,
	}
	half_extent := Vec3 {
		(geometry.bounds.max.x - geometry.bounds.min.x) * 0.5,
		(geometry.bounds.max.y - geometry.bounds.min.y) * 0.5,
		(geometry.bounds.max.z - geometry.bounds.min.z) * 0.5,
	}
	local_radius := math.sqrt(
		half_extent.x * half_extent.x +
		half_extent.y * half_extent.y +
		half_extent.z * half_extent.z,
	)
	return {center.x, center.y, center.z, local_radius}
}

wgpu_instance_bounds :: proc(
	instance: Render_Instance,
	geometry: ^resources.Geometry,
	model: Mat4,
) -> [4]f32 {
	local_bounds := wgpu_instance_local_bounds(geometry)
	center := Vec3{local_bounds[0], local_bounds[1], local_bounds[2]}
	world_center := Vec3 {
		model[0] * center.x + model[4] * center.y + model[8] * center.z + model[12],
		model[1] * center.x + model[5] * center.y + model[9] * center.z + model[13],
		model[2] * center.x + model[6] * center.y + model[10] * center.z + model[14],
	}
	max_scale := max(
		math.abs(instance.transform.scale.x),
		math.abs(instance.transform.scale.y),
		math.abs(instance.transform.scale.z),
	)
	return {world_center.x, world_center.y, world_center.z, local_bounds[3] * max_scale}
}

wgpu_build_gpu_instance_transform :: proc(
	instance: Render_Instance,
	geometry: ^resources.Geometry,
) -> WGPU_GPU_Instance_Transform {
	transform := instance.transform
	return {
		position = {transform.position.x, transform.position.y, transform.position.z, 0},
		rotation = {transform.rotation.x, transform.rotation.y, transform.rotation.z, 0},
		scale = {transform.scale.x, transform.scale.y, transform.scale.z, 0},
		local_bounds = wgpu_instance_local_bounds(geometry),
	}
}

wgpu_update_gpu_instance_transform :: proc(
	record: ^WGPU_GPU_Instance_Transform,
	transform: shared.Transform_Component,
) {
	if record == nil {
		return
	}
	record.position = {transform.position.x, transform.position.y, transform.position.z, 0}
	record.rotation = {transform.rotation.x, transform.rotation.y, transform.rotation.z, 0}
	record.scale = {transform.scale.x, transform.scale.y, transform.scale.z, 0}
}

wgpu_update_gpu_instance_record_transform :: proc(
	record: ^WGPU_GPU_Instance,
	instance: Render_Instance,
	geometry: ^resources.Geometry,
) {
	if record == nil || geometry == nil {
		return
	}
	model := wgpu_build_model(instance.transform)
	record.model = model
	record.normal_model = wgpu_build_normal_model_from_model(model, instance.transform.scale)
	record.render_flags[2] = 0
	record.bounds = wgpu_instance_bounds(instance, geometry, model)
}

wgpu_update_gpu_instance_transform_state :: proc(
	record: ^WGPU_GPU_Instance,
	transform_record: ^WGPU_GPU_Instance_Transform,
	instance: Render_Instance,
	geometry: ^resources.Geometry,
) {
	wgpu_update_gpu_instance_record_transform(record, instance, geometry)
	wgpu_update_gpu_instance_transform(transform_record, instance.transform)
}

wgpu_build_gpu_instance :: proc(
	instance: Render_Instance,
	geometry: ^resources.Geometry,
	material: ^resources.Material,
	batch_indices: [shared.MAX_GEOMETRY_LODS]u32,
	lod_count: u32,
) -> WGPU_GPU_Instance {
	color := material.desc.base_color
	emissive := material.desc.emissive
	model := wgpu_build_model(instance.transform)
	return WGPU_GPU_Instance {
		model = model,
		normal_model = wgpu_build_normal_model_from_model(model, instance.transform.scale),
		color = {color.x, color.y, color.z, color.w},
		emissive = {emissive.x, emissive.y, emissive.z, 0},
		render_flags = {
			1 if instance.shadow_caster else 0,
			1 if instance.shadow_receiver else 0,
			0,
			0,
		},
		bounds = wgpu_instance_bounds(instance, geometry, model),
		batch_indices = batch_indices,
		lod_screen_radii = {
			geometry.lod_screen_radii[0],
			geometry.lod_screen_radii[1],
			geometry.lod_screen_radii[2],
			0,
		},
		lod_count = lod_count,
		active = 1,
	}
}

wgpu_find_draw_batch :: proc(
	cache: ^WGPU_Draw_Batch_Cache,
	geometry: shared.Geometry_Handle,
	material: shared.Material_Handle,
) -> int {
	if cache == nil {
		return -1
	}
	for batch, batch_index in cache.batches[:cache.batch_count] {
		if batch.geometry == geometry && batch.material == material {
			return batch_index
		}
	}
	return -1
}

wgpu_render_instance_by_slot :: proc(
	render_list: ^Render_List,
	slot: int,
) -> (
	Render_Instance,
	bool,
) {
	if render_list == nil || slot < 0 || slot >= len(render_list.instance_index_by_slot) {
		return {}, false
	}
	instance_index := render_list.instance_index_by_slot[slot]
	if instance_index < 0 || instance_index >= len(render_list.instances) {
		return {}, false
	}
	instance := render_list.instances[instance_index]
	return instance, instance.slot == slot
}

wgpu_render_instance_pointer_by_slot :: proc(
	render_list: ^Render_List,
	slot: int,
) -> ^Render_Instance {
	if render_list == nil || slot < 0 || slot >= len(render_list.instance_index_by_slot) {
		return nil
	}
	instance_index := render_list.instance_index_by_slot[slot]
	if instance_index < 0 || instance_index >= len(render_list.instances) {
		return nil
	}
	instance := &render_list.instances[instance_index]
	if instance.slot != slot {
		return nil
	}
	return instance
}

wgpu_batch_indices_for_instance :: proc(
	renderer: ^WGPU_Renderer,
	cache: ^WGPU_Draw_Batch_Cache,
	instance: Render_Instance,
	registry: ^resources.Registry,
) -> (
	indices: [shared.MAX_GEOMETRY_LODS]u32,
	ok: bool,
) {
	geometry, geometry_ok := resources.get_geometry(registry, instance.geometry.handle)
	if !geometry_ok {
		return {}, false
	}
	base_batch := wgpu_find_draw_batch(cache, instance.geometry.handle, instance.material.handle)
	if base_batch < 0 {
		return {}, false
	}
	indices[0] = u32(base_batch)
	lod_count := wgpu_geometry_draw_lod_count(renderer, geometry)
	for handle, lod_index in geometry.lod_handles[:lod_count] {
		lod_batch := wgpu_find_draw_batch(cache, handle, instance.material.handle)
		if lod_batch < 0 {
			return {}, false
		}
		indices[lod_index + 1] = u32(lod_batch)
	}
	return indices, true
}

wgpu_adjust_batch_membership :: proc(
	cache: ^WGPU_Draw_Batch_Cache,
	indices: [shared.MAX_GEOMETRY_LODS]u32,
	lod_count: u32,
	delta: int,
) -> (
	layout_changed: bool,
) {
	count := min(int(lod_count) + 1, shared.MAX_GEOMETRY_LODS)
	for ordinal in 0 ..< count {
		index := indices[ordinal]
		duplicate := false
		for previous_ordinal in 0 ..< ordinal {
			previous := indices[previous_ordinal]
			if previous == index {
				duplicate = true
				break
			}
		}
		if duplicate || int(index) >= cache.batch_count {
			continue
		}
		batch := &cache.batches[index]
		if delta > 0 {
			batch.instance_count += u32(delta)
			cache.instance_count += delta
			layout_changed = layout_changed || batch.instance_count > batch.visible_capacity
		} else if batch.instance_count > 0 {
			batch.instance_count -= u32(-delta)
			cache.instance_count = max(cache.instance_count + delta, 0)
			if batch.instance_count == 0 {
				cache.valid = false
			}
		}
	}
	return
}

wgpu_instance_membership_matches :: proc(
	previous: WGPU_Instance_Source_State,
	indices: [shared.MAX_GEOMETRY_LODS]u32,
	lod_count: u32,
) -> bool {
	return previous.lod_count == lod_count && previous.batch_indices == indices
}

wgpu_instance_batch_key_matches :: proc(
	previous: WGPU_Instance_Source_State,
	instance: Render_Instance,
) -> bool {
	return(
		previous.geometry == instance.geometry.handle &&
		previous.material == instance.material.handle \
	)
}

wgpu_instance_update_work :: proc(
	previous_active: bool,
	previous, current: WGPU_Instance_Source_State,
	previous_transform, current_transform: shared.Transform_Component,
) -> (
	static_changed, transform_input_changed, expand_transform: bool,
) {
	static_changed = !previous_active || previous != current
	transform_changed := !previous_active || previous_transform != current_transform
	bounds_source_changed :=
		!previous_active ||
		previous.geometry != current.geometry ||
		previous.geometry_version != current.geometry_version
	transform_input_changed = transform_changed || bounds_source_changed
	expand_transform = transform_changed && !static_changed
	return
}

wgpu_instance_source_changed :: proc(
	previous_active: bool,
	previous, current: WGPU_Instance_Source_State,
	previous_transform, current_transform: shared.Transform_Component,
) -> bool {
	return !previous_active || previous != current || previous_transform != current_transform
}

wgpu_sync_dirty_instance_slot :: proc(
	renderer: ^WGPU_Renderer,
	cache: ^WGPU_Draw_Batch_Cache,
	render_list: ^Render_List,
	registry: ^resources.Registry,
	slot: int,
	cpu_culling: bool,
) -> (
	batch_layout_changed: bool,
	err: string,
) {
	if slot < 0 || slot >= render_list.instance_slot_count {
		return
	}
	instance, active := wgpu_render_instance_by_slot(render_list, slot)
	previous_active := renderer.gpu_active_slots[slot]
	previous_source := renderer.gpu_instance_sources[slot]
	previous_transform := renderer.gpu_instance_source_transforms[slot]
	if !active {
		if previous_active {
			_ = wgpu_adjust_batch_membership(
				cache,
				previous_source.batch_indices,
				previous_source.lod_count,
				-1,
			)
			renderer.gpu_instance_records[slot] = {}
			renderer.gpu_instance_transform_records[slot] = {}
			renderer.gpu_instance_sources[slot] = {}
			renderer.gpu_instance_source_transforms[slot] = {}
			renderer.gpu_active_slots[slot] = false
			append(&renderer.gpu_dirty_indices, slot)
		}
		return
	}
	geometry, geometry_ok := resources.get_geometry(registry, instance.geometry.handle)
	material, material_ok := resources.get_material(registry, instance.material.handle)
	if !geometry_ok || !material_ok {
		return
	}
	batch_indices := previous_source.batch_indices
	if !previous_active || !wgpu_instance_batch_key_matches(previous_source, instance) {
		batches_ok: bool
		batch_indices, batches_ok = wgpu_batch_indices_for_instance(
			renderer,
			cache,
			instance,
			registry,
		)
		if !batches_ok {
			return false, "GPU instance is missing its draw batch"
		}
	}
	lod_count := u32(wgpu_geometry_draw_lod_count(renderer, geometry))
	source := WGPU_Instance_Source_State {
		geometry = instance.geometry.handle,
		material = instance.material.handle,
		geometry_version = geometry.version,
		material_version = material.version,
		shadow_caster = instance.shadow_caster,
		shadow_receiver = instance.shadow_receiver,
		batch_indices = batch_indices,
		lod_screen_radii = {
			geometry.lod_screen_radii[0],
			geometry.lod_screen_radii[1],
			geometry.lod_screen_radii[2],
			0,
		},
		lod_count = lod_count,
	}
	membership_changed :=
		!previous_active ||
		!wgpu_instance_membership_matches(previous_source, batch_indices, lod_count)
	if membership_changed && previous_active {
		_ = wgpu_adjust_batch_membership(
			cache,
			previous_source.batch_indices,
			previous_source.lod_count,
			-1,
		)
	}
	if membership_changed {
		batch_layout_changed = wgpu_adjust_batch_membership(cache, batch_indices, lod_count, 1)
	}
	if wgpu_instance_source_changed(
		previous_active,
		previous_source,
		source,
		previous_transform,
		instance.transform,
	) {
		static_changed, transform_input_changed, expand_transform := wgpu_instance_update_work(
			previous_active,
			previous_source,
			source,
			previous_transform,
			instance.transform,
		)
		if static_changed || cpu_culling {
			renderer.gpu_instance_records[slot] = wgpu_build_gpu_instance(
				instance,
				geometry,
				material,
				batch_indices,
				lod_count,
			)
		} else if transform_input_changed {
			wgpu_update_gpu_instance_transform_state(
				&renderer.gpu_instance_records[slot],
				&renderer.gpu_instance_transform_records[slot],
				instance,
				geometry,
			)
		}
		if static_changed {
			append(&renderer.gpu_dirty_indices, slot)
		}
		if transform_input_changed && (static_changed || cpu_culling) {
			renderer.gpu_instance_transform_records[slot] = wgpu_build_gpu_instance_transform(
				instance,
				geometry,
			)
		}
		if expand_transform {
			wgpu_append_transform_update(renderer, slot)
		}
		renderer.gpu_instance_sources[slot] = source
		renderer.gpu_instance_source_transforms[slot] = instance.transform
		renderer.gpu_active_slots[slot] = true
	}
	return
}

wgpu_reconcile_transform_dirty_slot :: proc(
	renderer: ^WGPU_Renderer,
	cache: ^WGPU_Draw_Batch_Cache,
	render_list: ^Render_List,
	registry: ^resources.Registry,
	slot: int,
	cpu_culling: bool,
) -> (
	instance: ^Render_Instance,
	batch_layout_changed: bool,
	err: string,
) {
	instance = wgpu_render_instance_pointer_by_slot(render_list, slot)
	gpu_active := renderer.gpu_active_slots[slot]
	if (instance == nil) == !gpu_active {
		return
	}

	batch_layout_changed, err = wgpu_sync_dirty_instance_slot(
		renderer,
		cache,
		render_list,
		registry,
		slot,
		cpu_culling,
	)
	if err != "" {
		return
	}
	instance = wgpu_render_instance_pointer_by_slot(render_list, slot)
	if instance == nil && !renderer.gpu_active_slots[slot] {
		return
	}
	if instance == nil || !renderer.gpu_active_slots[slot] {
		diagnostic.fatal_engine_error(
			fmt.tprintf(
				"transform-dirty GPU slot %d could not be reconciled (render list: %v, GPU: %v, static dirty: %v)",
				slot,
				instance != nil,
				renderer.gpu_active_slots[slot],
				slice.contains(render_list.dirty_instance_slots[:], slot),
			),
		)
		return
	}
	return
}

wgpu_rebuild_instance_batch_cache :: proc(
	renderer: ^WGPU_Renderer,
	cache: ^WGPU_Draw_Batch_Cache,
	render_list: ^Render_List,
	registry: ^resources.Registry,
	slot_count: int,
) -> string {
	resize(&renderer.gpu_batch_indices_by_slot, slot_count)
	for instance in render_list.instances {
		if instance.slot < 0 || instance.slot >= slot_count {
			continue
		}
		geometry, ok := resources.get_geometry(registry, instance.geometry.handle)
		if !ok {
			return "GPU instance references unavailable geometry"
		}
		batch_indices: [shared.MAX_GEOMETRY_LODS]u32
		base_batch := wgpu_find_draw_batch(
			cache,
			instance.geometry.handle,
			instance.material.handle,
		)
		if base_batch < 0 {
			return "GPU instance is missing its draw batch"
		}
		batch_indices[0] = u32(base_batch)
		lod_count := wgpu_geometry_draw_lod_count(renderer, geometry)
		for handle, lod_index in geometry.lod_handles[:lod_count] {
			lod_batch := wgpu_find_draw_batch(cache, handle, instance.material.handle)
			if lod_batch < 0 {
				return "GPU LOD geometry is missing its draw batch"
			}
			batch_indices[lod_index + 1] = u32(lod_batch)
		}
		renderer.gpu_batch_indices_by_slot[instance.slot] = batch_indices
	}
	return ""
}

wgpu_next_instance_upload_range :: proc(
	dirty_indices: []int,
	start: int,
) -> (
	first, last, next: int,
) {
	first = dirty_indices[start]
	last = first + 1
	next = start + 1
	for next < len(dirty_indices) {
		slot := dirty_indices[next]
		if slot < last {
			next += 1
			continue
		}
		if slot - last > WGPU_INSTANCE_UPLOAD_MERGE_GAP {
			break
		}
		last = slot + 1
		next += 1
	}
	return
}

wgpu_sort_dirty_indices_if_needed :: proc(dirty_indices: []int) {
	for index in 1 ..< len(dirty_indices) {
		if dirty_indices[index] < dirty_indices[index - 1] {
			slice.sort(dirty_indices)
			return
		}
	}
}

wgpu_upload_dirty_instance_ranges :: proc(renderer: ^WGPU_Renderer, dirty_indices: []int) {
	if len(dirty_indices) == 0 {
		return
	}
	wgpu_sort_dirty_indices_if_needed(dirty_indices)
	index := 0
	for index < len(dirty_indices) {
		first, last, next := wgpu_next_instance_upload_range(dirty_indices, index)
		index = next
		count := last - first
		byte_count := uint(count * size_of(WGPU_GPU_Instance))
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_instance_buffer,
			u64(first * size_of(WGPU_GPU_Instance)),
			raw_data(renderer.gpu_instance_records[first:last]),
			byte_count,
		)
		renderer.gpu_instance_upload_count += 1
		renderer.gpu_instance_upload_bytes += u64(byte_count)
	}
}

wgpu_append_transform_update :: proc(renderer: ^WGPU_Renderer, slot: int) {
	if renderer == nil || slot < 0 || slot >= len(renderer.gpu_instance_transform_records) {
		return
	}
	update := renderer.gpu_instance_transform_records[slot]
	update.position[3] = f32(slot)
	append(&renderer.gpu_transform_updates, update)
}

wgpu_upload_transform_updates :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil || len(renderer.gpu_transform_updates) <= 1 {
		return
	}
	update_count := len(renderer.gpu_transform_updates) - 1
	renderer.gpu_transform_updates[0].position[3] = f32(update_count)
	byte_count := uint(len(renderer.gpu_transform_updates) * size_of(WGPU_GPU_Instance_Transform))
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_transform_update_buffer,
		0,
		raw_data(renderer.gpu_transform_updates[:]),
		byte_count,
	)
	renderer.gpu_instance_upload_count += 1
	renderer.gpu_instance_upload_bytes += u64(byte_count)
	renderer.gpu_instance_transform_upload_count += 1
	renderer.gpu_instance_transform_upload_bytes += u64(byte_count)
}

wgpu_reject_temporal_history_for_instance_changes :: proc(
	renderer: ^WGPU_Renderer,
	instance_data_changed: bool,
) {
	if renderer == nil || !instance_data_changed {
		return
	}
	// Surface reprojection currently accounts for camera motion only. Reusing
	// history after an instance moves or changes would project the old surface
	// onto its new position; fog history would retain the matching stale depth
	// and shadowing. Reject both until the renderer emits object motion vectors.
	renderer.temporal_history_valid = false
	renderer.volumetric_fog_history_valid = false
}

wgpu_cpu_cull_counts :: proc(
	instances: []WGPU_GPU_Instance,
	planes: [6][4]f32,
	batch_count: int,
	shadow: bool = false,
	view_projection: Mat4 = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
) -> [dynamic]u32 {
	counts := make([dynamic]u32, batch_count)
	for instance in instances {
		lod_level := wgpu_cpu_instance_lod_level(instance, view_projection)
		batch_index := instance.batch_indices[lod_level]
		if instance.active == 0 || int(batch_index) >= batch_count {
			continue
		}
		if shadow && instance.render_flags[0] < 0.5 {
			continue
		}
		if wgpu_sphere_visible(instance.bounds, planes) {
			counts[batch_index] += 1
		}
	}
	return counts
}

wgpu_cpu_instance_lod_level :: proc(instance: WGPU_GPU_Instance, view_projection: Mat4) -> int {
	if instance.lod_count == 0 {
		return 0
	}
	clip_w :=
		view_projection[3] * instance.bounds[0] +
		view_projection[7] * instance.bounds[1] +
		view_projection[11] * instance.bounds[2] +
		view_projection[15]
	if clip_w <= 0.0001 {
		return 0
	}
	screen_radius := math.abs(instance.bounds[3] * view_projection[5] / clip_w) * 0.5
	level := 0
	radii := instance.lod_screen_radii
	for threshold, index in radii[:int(instance.lod_count)] {
		if screen_radius < threshold {
			level = index + 1
		}
	}
	return level
}

wgpu_hiz_reuse_allowed :: proc(
	requested, valid, instance_data_changed: bool,
	previous_view_projection, current_view_projection: Mat4,
) -> bool {
	return(
		requested &&
		valid &&
		!instance_data_changed &&
		previous_view_projection == current_view_projection \
	)
}

wgpu_hiz_build_requested :: proc(slot_count: int, instance_data_changed: bool) -> bool {
	return slot_count >= WGPU_HIZ_MIN_INSTANCES && !instance_data_changed
}

wgpu_hiz_occlusion_status :: proc(
	forced, valid, instance_data_changed: bool,
	slot_count: int,
	previous_view_projection, current_view_projection: Mat4,
) -> shared.HiZ_Occlusion_Status {
	if !forced && slot_count < WGPU_HIZ_MIN_INSTANCES {
		return .Below_Threshold
	}
	if instance_data_changed {
		return .Scene_Changed
	}
	if !valid {
		return .Warming_Up
	}
	if previous_view_projection != current_view_projection {
		return .Camera_Changed
	}
	return .Active
}

wgpu_hiz_sphere_projection_safe :: proc(bounds: [4]f32, camera_position: Vec3) -> bool {
	offset := Vec3 {
		bounds[0] - camera_position.x,
		bounds[1] - camera_position.y,
		bounds[2] - camera_position.z,
	}
	distance_squared := offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
	conservative_distance := bounds[3] * 4
	return distance_squared > conservative_distance * conservative_distance
}

wgpu_retain_render_uniform :: proc(
	renderer: ^WGPU_Renderer,
	uniform: WGPU_GPU_Render_Uniform,
) -> bool {
	if renderer.gpu_render_uniform_valid && renderer.gpu_render_uniform == uniform {
		return false
	}
	renderer.gpu_render_uniform = uniform
	renderer.gpu_render_uniform_valid = true
	return true
}

wgpu_retain_cull_uniform :: proc(
	renderer: ^WGPU_Renderer,
	uniform: WGPU_GPU_Cull_Uniform,
) -> bool {
	if renderer.gpu_cull_uniform_valid && renderer.gpu_cull_uniform == uniform {
		return false
	}
	renderer.gpu_cull_uniform = uniform
	renderer.gpu_cull_uniform_valid = true
	return true
}

wgpu_reset_gpu_instance_slots :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil {
		return
	}
	for slot in 0 ..< len(renderer.gpu_instance_records) {
		renderer.gpu_instance_records[slot] = {}
		renderer.gpu_instance_transform_records[slot] = {}
		renderer.gpu_instance_sources[slot] = {}
		renderer.gpu_instance_source_transforms[slot] = {}
		renderer.gpu_active_slots[slot] = false
		append(&renderer.gpu_dirty_indices, slot)
	}
	clear(&renderer.gpu_live_slots)
}

wgpu_material_instance_needs_sync :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
	instance: Render_Instance,
) -> bool {
	if renderer == nil || registry == nil {
		return false
	}
	slot := instance.slot
	if slot < 0 ||
	   slot >= len(renderer.gpu_active_slots) ||
	   slot >= len(renderer.gpu_instance_sources) ||
	   !renderer.gpu_active_slots[slot] {
		return false
	}
	material, alive := resources.get_material(registry, instance.material.handle)
	return alive && renderer.gpu_instance_sources[slot].material_version != material.version
}

wgpu_prepare_gpu_draw_batches :: proc(
	renderer: ^WGPU_Renderer,
	render_list: ^Render_List,
	registry: ^resources.Registry,
	viewport: ui.Rect,
	target_width, target_height: u32,
	cpu_culling: bool,
	editor_selected_uuids: []shared.Entity_UUID,
	editor_selection_revision: u64,
) -> (
	[]WGPU_Draw_Batch,
	int,
	string,
) {
	slot_count := render_list.instance_slot_count
	temporal_world_changed :=
		renderer.gpu_topology_valid && renderer.gpu_world_uuid != render_list.world_uuid
	if slot_count > WGPU_MAX_GPU_INSTANCES {
		return nil, 0, "GPU-driven renderer exceeded its instance-slot capacity"
	}
	if renderer.gpu_topology_valid &&
	   renderer.gpu_world_uuid == render_list.world_uuid &&
	   renderer.draw_batch_cache.geometry_topology_revision ==
		   registry.geometry_topology_revision {
		for slot in render_list.dirty_instance_slots {
			if instance, active := wgpu_render_instance_by_slot(render_list, slot); active {
				if slot >= 0 &&
				   slot < len(renderer.gpu_active_slots) &&
				   renderer.gpu_active_slots[slot] &&
				   wgpu_instance_batch_key_matches(renderer.gpu_instance_sources[slot], instance) {
					continue
				}
				if _, found := wgpu_batch_indices_for_instance(
					renderer,
					&renderer.draw_batch_cache,
					instance,
					registry,
				); !found {
					renderer.draw_batch_cache.valid = false
					break
				}
			}
		}
	}
	topology_changed :=
		!renderer.gpu_topology_valid ||
		!renderer.draw_batch_cache.valid ||
		renderer.gpu_world_uuid != render_list.world_uuid ||
		renderer.gpu_topology_revision != render_list.topology_revision ||
		renderer.draw_batch_cache.geometry_topology_revision != registry.geometry_topology_revision
	cache, topology_err := wgpu_sync_gpu_topology(renderer, render_list, registry)
	if topology_err != "" {
		return nil, 0, topology_err
	}
	debug_view := shared.Render_Debug_View.Lit
	if render_list.has_camera {
	}
	old_point_light_buffer, old_cluster_index_buffer, cluster_buffers_grew, cluster_err :=
		wgpu_ensure_clustered_light_capacity(renderer, render_list.point_light_count)
	if cluster_err != "" {
		return nil, 0, cluster_err
	}
	if cluster_buffers_grew {
		if batch_layout_err := wgpu_refresh_gpu_batch_layout(renderer, cache, registry);
		   batch_layout_err != "" {
			return nil, 0, batch_layout_err
		}
		wgpu.BufferRelease(old_point_light_buffer)
		wgpu.BufferRelease(old_cluster_index_buffer)
	}
	if topology_changed {
		if batch_cache_err := wgpu_rebuild_instance_batch_cache(
			renderer,
			cache,
			render_list,
			registry,
			slot_count,
		); batch_cache_err != "" {
			return nil, 0, batch_cache_err
		}
	}
	if indirect_err := wgpu_refresh_indirect_templates(renderer, cache, registry);
	   indirect_err != "" {
		return nil, 0, indirect_err
	}
	uniform: WGPU_GPU_Render_Uniform
	view, projection := wgpu_build_camera_matrices(
		render_list.camera,
		render_list.has_camera,
		u32(viewport.width),
		u32(viewport.height),
	)
	view_projection := mat4_mul(projection, view)
	temporal_camera := wgpu_temporal_camera_state(render_list.camera, render_list.has_camera)
	shadow_camera_discontinuous :=
		renderer.temporal_camera_valid &&
		!wgpu_temporal_camera_continuous(renderer.temporal_camera, temporal_camera)
	if temporal_world_changed || shadow_camera_discontinuous {
		renderer.temporal_history_valid = false
		renderer.temporal_sample_index = 0
	}
	renderer.temporal_camera = temporal_camera
	renderer.temporal_camera_valid = true
	jitter: Vec2
	if render_list.has_camera &&
	   render_list.camera.camera.debug_view == .Lit &&
	   render_list.camera.camera.temporal_antialiasing {
		jitter = wgpu_temporal_jitter(
			renderer.temporal_sample_index,
			u32(viewport.width),
			u32(viewport.height),
		)
	}
	jittered_projection := wgpu_jitter_projection(projection, jitter)
	jittered_view_projection := mat4_mul(jittered_projection, view)
	renderer.temporal_current_view_projection = wgpu_temporal_history_view_projection(
		projection,
		view,
	)
	renderer.temporal_current_projection = {
		jittered_projection[0],
		jittered_projection[5],
		jittered_projection[10],
		jittered_projection[14],
	}
	renderer.temporal_inverse_view = wgpu_inverse_rigid_view(view)
	if hiz_err := wgpu_ensure_hiz_targets(renderer, target_width, target_height); hiz_err != "" {
		return nil, 0, hiz_err
	}
	shadow_cascades: WGPU_Shadow_Cascades
	for &cascade_matrix in shadow_cascades.matrices {
		cascade_matrix = mat4_identity()
	}
	if render_list.directional_light_count > 0 {
		shadow_cascades = wgpu_build_directional_shadow_cascades(
			render_list.camera,
			render_list.has_camera,
			u32(viewport.width),
			u32(viewport.height),
			render_list.directional_lights[0].light.direction,
			max(renderer.shadow_map_resolution, WGPU_SHADOW_MAP_MIN_SIZE),
		)
	}
	shadow_cascades = wgpu_retain_shadow_cascades(
		renderer,
		shadow_cascades,
		render_list.directional_light_count > 0,
		temporal_world_changed ||
		topology_changed ||
		shadow_camera_discontinuous ||
		len(render_list.dirty_instance_slots) > 0,
	)
	uniform.view_projection = jittered_view_projection
	uniform.view = view
	uniform.shadow_view_projections = shadow_cascades.matrices
	uniform.shadow_cascade_splits = shadow_cascades.splits
	uniform.shadow_cascade_texel_sizes = shadow_cascades.texel_sizes
	shadow_resolution := max(renderer.shadow_map_resolution, WGPU_SHADOW_MAP_MIN_SIZE)
	uniform.shadow_map_parameters = {
		f32(shadow_resolution) / f32(WGPU_SHADOW_MAP_SIZE),
		1.0 / f32(WGPU_SHADOW_MAP_SIZE),
		f32(shadow_resolution),
		f32(WGPU_SHADOW_MAP_SIZE),
	}
	camera_position := Vec3{0, 2, 6}
	if render_list.has_camera {
		camera_position = render_list.camera.transform.position
	}
	uniform.camera_position = {camera_position.x, camera_position.y, camera_position.z, 1}
	camera := shared.camera_defaults()
	if render_list.has_camera {
		camera = render_list.camera.camera
	}
	if camera.debug_view != .Occlusion_Queries {
		renderer.gpu_occlusion_debug_evidence_valid = false
		renderer.gpu_occlusion_debug_record_count = 0
	}
	uniform.debug = {
		u32(camera.debug_view),
		1 if !cpu_culling else 0,
		min(shared.camera_debug_hiz_mip(camera), u32(max(renderer.gpu_hiz_mip_count - 1, 0))),
		1 if camera.debug_occlusion_freeze else 0,
	}
	uniform.camera_clip = {camera.near, camera.far, 0, 0}
	uniform.ambient = {render_list.ambient.x, render_list.ambient.y, render_list.ambient.z, 1}
	uniform.light_counts = {
		u32(render_list.directional_light_count),
		u32(render_list.point_light_count),
		0,
		0,
	}
	for light, index in render_list.directional_lights[:render_list.directional_light_count] {
		uniform.directional_direction_intensity[index] = {
			light.light.direction.x,
			light.light.direction.y,
			light.light.direction.z,
			light.light.intensity,
		}
		uniform.directional_color[index] = {
			light.light.color.x,
			light.light.color.y,
			light.light.color.z,
			1,
		}
	}
	wgpu_prepare_clustered_lighting(renderer, render_list, view, jittered_projection, viewport)
	if wgpu_retain_render_uniform(renderer, uniform) {
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_render_uniform_buffer,
			0,
			&uniform,
			uint(size_of(uniform)),
		)
	}

	previous_slot_count := len(renderer.gpu_instance_records)
	if slot_count > previous_slot_count {
		resize(&renderer.gpu_instance_records, slot_count)
		resize(&renderer.gpu_instance_transform_records, slot_count)
		resize(&renderer.gpu_instance_sources, slot_count)
		resize(&renderer.gpu_instance_source_transforms, slot_count)
		resize(&renderer.gpu_active_slots, slot_count)
	}
	clear(&renderer.gpu_dirty_indices)
	clear(&renderer.gpu_transform_updates)
	append(&renderer.gpu_transform_updates, WGPU_GPU_Instance_Transform{})
	reset_instances := render_list.full_instance_sync || topology_changed
	if reset_instances {
		wgpu_reset_gpu_instance_slots(renderer)
	}
	batch_layout_changed := false
	instances := render_list.instances[:]
	if !reset_instances {
		instances = nil
	}
	for instance in instances {
		if instance.slot < 0 || instance.slot >= slot_count {
			continue
		}
		geometry, geometry_ok := resources.get_geometry(registry, instance.geometry.handle)
		material, material_ok := resources.get_material(registry, instance.material.handle)
		if !geometry_ok || !material_ok {
			continue
		}
		slot := instance.slot
		batch_indices := renderer.gpu_batch_indices_by_slot[slot]
		lod_count := u32(wgpu_geometry_draw_lod_count(renderer, geometry))
		source := WGPU_Instance_Source_State {
			geometry = instance.geometry.handle,
			material = instance.material.handle,
			geometry_version = geometry.version,
			material_version = material.version,
			shadow_caster = instance.shadow_caster,
			shadow_receiver = instance.shadow_receiver,
			batch_indices = batch_indices,
			lod_screen_radii = {
				geometry.lod_screen_radii[0],
				geometry.lod_screen_radii[1],
				geometry.lod_screen_radii[2],
				0,
			},
			lod_count = lod_count,
		}
		if !renderer.gpu_active_slots[slot] || renderer.gpu_instance_sources[slot] != source {
			record := wgpu_build_gpu_instance(
				instance,
				geometry,
				material,
				batch_indices,
				lod_count,
			)
			renderer.gpu_instance_records[slot] = record
			renderer.gpu_instance_transform_records[slot] = wgpu_build_gpu_instance_transform(
				instance,
				geometry,
			)
			renderer.gpu_instance_sources[slot] = source
			renderer.gpu_instance_source_transforms[slot] = instance.transform
			renderer.gpu_active_slots[slot] = true
			append(&renderer.gpu_dirty_indices, slot)
		}
		if reset_instances {
			append(&renderer.gpu_live_slots, slot)
		}
	}
	if !reset_instances && renderer.gpu_material_revision != registry.material_revision {
		for instance in render_list.instances {
			slot := instance.slot
			if slot < 0 ||
			   slot >= slot_count ||
			   !wgpu_material_instance_needs_sync(renderer, registry, instance) {
				continue
			}
			layout_changed, sync_err := wgpu_sync_dirty_instance_slot(
				renderer,
				cache,
				render_list,
				registry,
				slot,
				cpu_culling,
			)
			if sync_err != "" {
				return nil, 0, sync_err
			}
			batch_layout_changed = batch_layout_changed || layout_changed
		}
	}
	renderer.gpu_material_revision = registry.material_revision
	if !reset_instances {
		for slot in render_list.dirty_instance_slots {
			layout_changed, sync_err := wgpu_sync_dirty_instance_slot(
				renderer,
				cache,
				render_list,
				registry,
				slot,
				cpu_culling,
			)
			if sync_err != "" {
				return nil, 0, sync_err
			}
			batch_layout_changed = batch_layout_changed || layout_changed
		}
		for slot in render_list.dirty_transform_slots {
			if slot < 0 || slot >= slot_count {
				continue
			}
			instance, layout_changed, sync_err := wgpu_reconcile_transform_dirty_slot(
				renderer,
				cache,
				render_list,
				registry,
				slot,
				cpu_culling,
			)
			if sync_err != "" {
				return nil, 0, sync_err
			}
			batch_layout_changed = batch_layout_changed || layout_changed
			if instance == nil {
				continue
			}
			previous := &renderer.gpu_instance_sources[slot]
			if !wgpu_instance_batch_key_matches(previous^, instance^) ||
			   previous.shadow_caster != instance.shadow_caster ||
			   previous.shadow_receiver != instance.shadow_receiver {
				return nil, 0, "transform-dirty GPU instance changed static render state"
			}
			previous_transform := &renderer.gpu_instance_source_transforms[slot]
			if previous_transform^ == instance.transform {
				continue
			}
			geometry, geometry_ok := resources.get_geometry(registry, instance.geometry.handle)
			if !geometry_ok {
				continue
			}
			previous_transform^ = instance.transform
			wgpu_update_gpu_instance_transform_state(
				&renderer.gpu_instance_records[slot],
				&renderer.gpu_instance_transform_records[slot],
				instance^,
				geometry,
			)
			if cpu_culling {
				material, material_ok := resources.get_material(registry, instance.material.handle)
				if !material_ok {
					continue
				}
				renderer.gpu_instance_records[slot] = wgpu_build_gpu_instance(
					instance^,
					geometry,
					material,
					previous.batch_indices,
					previous.lod_count,
				)
				append(&renderer.gpu_dirty_indices, slot)
			} else {
				wgpu_append_transform_update(renderer, slot)
			}
		}
	}
	if batch_layout_changed {
		if layout_err := wgpu_refresh_gpu_batch_layout(renderer, cache, registry);
		   layout_err != "" {
			return nil, 0, layout_err
		}
	}
	wgpu_apply_editor_selection(
		renderer,
		render_list,
		editor_selected_uuids,
		editor_selection_revision,
	)
	instance_data_changed :=
		len(renderer.gpu_dirty_indices) > 0 || len(renderer.gpu_transform_updates) > 1
	wgpu_reject_temporal_history_for_instance_changes(renderer, instance_data_changed)
	wgpu_upload_dirty_instance_ranges(renderer, renderer.gpu_dirty_indices[:])
	wgpu_upload_transform_updates(renderer)
	renderer.gpu_slot_count = slot_count
	hiz_forced := camera.debug_view == .HiZ || camera.debug_view == .Occlusion_Queries
	renderer.gpu_hiz_requested =
		hiz_forced || wgpu_hiz_build_requested(slot_count, instance_data_changed)
	renderer.gpu_hiz_occlusion_status = wgpu_hiz_occlusion_status(
		hiz_forced,
		renderer.gpu_hiz_valid,
		instance_data_changed,
		slot_count,
		renderer.gpu_previous_view_projection,
		view_projection,
	)
	hiz_reusable := wgpu_hiz_reuse_allowed(
		renderer.gpu_hiz_requested,
		renderer.gpu_hiz_valid,
		instance_data_changed,
		renderer.gpu_previous_view_projection,
		view_projection,
	)
	renderer.gpu_hiz_refinement_requested = wgpu_hiz_refinement_needed(
		renderer.gpu_hiz_requested,
		hiz_reusable,
	)
	renderer.gpu_current_view_projection = view_projection
	renderer.gpu_hiz_occlusion_enabled = hiz_reusable || renderer.gpu_hiz_refinement_requested
	cull_uniform := WGPU_GPU_Cull_Uniform {
		camera_planes = wgpu_extract_frustum_planes(view_projection),
		view_projection = view_projection,
		hiz_view_projection = view_projection if renderer.gpu_hiz_refinement_requested else renderer.gpu_previous_depth_view_projection,
		viewport = {viewport.x, viewport.y, viewport.width, viewport.height},
		camera_position = {camera_position.x, camera_position.y, camera_position.z, 1},
		slot_count = u32(slot_count),
		batch_count = u32(cache.batch_count),
		hiz_mip_count = u32(renderer.gpu_hiz_mip_count),
		hiz_enabled = 1 if renderer.gpu_hiz_occlusion_enabled else 0,
		shadow_visible_stride = u32(renderer.gpu_visible_buffer_capacity),
		indirect_command_stride = u32(renderer.gpu_indirect_command_count),
		occlusion_depth_scale = math.abs(projection[14]),
		occlusion_world_bias = WGPU_HIZ_OCCLUSION_WORLD_BIAS,
	}
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		cull_uniform.shadow_planes[cascade_index] = wgpu_extract_frustum_planes(
			shadow_cascades.matrices[cascade_index],
		)
	}
	initial_cull_phase := wgpu_initial_cull_phase(
		renderer.gpu_hiz_occlusion_enabled,
		renderer.gpu_hiz_refinement_requested,
	)
	// A coarse current-camera depth pass exists specifically because retained
	// Hi-Z history is not reusable. It must be frustum-only: sampling the old
	// pyramid with the new view projection can reject visible occluders and
	// poison the refinement pyramid built from this pass.
	cull_uniform.hiz_enabled = 1 if wgpu_cull_phase_uses_occlusion(initial_cull_phase) else 0
	if wgpu_retain_cull_uniform(renderer, cull_uniform) {
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_cull_initial_uniform_buffer,
			0,
			&cull_uniform,
			uint(size_of(cull_uniform)),
		)
		refine_uniform := cull_uniform
		refine_uniform.hiz_enabled = 1
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_cull_refine_uniform_buffer,
			0,
			&refine_uniform,
			uint(size_of(refine_uniform)),
		)
	}
	return cache.batches[:cache.batch_count], cache.batch_count, ""
}

wgpu_apply_editor_selection :: proc(
	renderer: ^WGPU_Renderer,
	render_list: ^Render_List,
	selected_uuids: []shared.Entity_UUID,
	selection_revision: u64,
) {
	if renderer == nil || render_list == nil {
		return
	}
	selection_changed := renderer.gpu_editor_selection_revision != selection_revision
	if !selection_changed && len(renderer.gpu_dirty_indices) == 0 {
		return
	}
	previous_slot_capacity := len(renderer.gpu_editor_selected_slot_indices)
	if len(renderer.gpu_editor_selected_slot_indices) < len(renderer.gpu_instance_records) {
		resize(&renderer.gpu_editor_selected_slot_indices, len(renderer.gpu_instance_records))
		for index in previous_slot_capacity ..< len(renderer.gpu_editor_selected_slot_indices) {
			renderer.gpu_editor_selected_slot_indices[index] = -1
		}
	}
	if selection_changed {
		clear(&renderer.gpu_editor_selected_slots)
		for &index in renderer.gpu_editor_selected_slot_indices {
			index = -1
		}
		for instance in render_list.instances {
			wgpu_apply_editor_selection_to_instance(renderer, instance, selected_uuids)
		}
	} else {
		dirty_count := len(renderer.gpu_dirty_indices)
		for slot in renderer.gpu_dirty_indices[:dirty_count] {
			if instance, found := wgpu_render_instance_by_slot(render_list, slot); found {
				wgpu_apply_editor_selection_to_instance(renderer, instance, selected_uuids)
			} else {
				wgpu_set_editor_selected_slot(renderer, slot, false)
			}
		}
	}
	renderer.gpu_editor_selection_revision = selection_revision
}

wgpu_set_editor_selected_slot :: proc(renderer: ^WGPU_Renderer, slot: int, selected: bool) {
	if renderer == nil || slot < 0 || slot >= len(renderer.gpu_editor_selected_slot_indices) {
		return
	}
	index := renderer.gpu_editor_selected_slot_indices[slot]
	if selected {
		if index >= 0 && index < len(renderer.gpu_editor_selected_slots) {
			return
		}
		renderer.gpu_editor_selected_slot_indices[slot] = len(renderer.gpu_editor_selected_slots)
		append(&renderer.gpu_editor_selected_slots, slot)
		return
	}
	if index < 0 || index >= len(renderer.gpu_editor_selected_slots) {
		return
	}
	last_index := len(renderer.gpu_editor_selected_slots) - 1
	if index != last_index {
		moved_slot := renderer.gpu_editor_selected_slots[last_index]
		renderer.gpu_editor_selected_slots[index] = moved_slot
		if moved_slot >= 0 && moved_slot < len(renderer.gpu_editor_selected_slot_indices) {
			renderer.gpu_editor_selected_slot_indices[moved_slot] = index
		}
	}
	pop(&renderer.gpu_editor_selected_slots)
	renderer.gpu_editor_selected_slot_indices[slot] = -1
}

wgpu_apply_editor_selection_to_instance :: proc(
	renderer: ^WGPU_Renderer,
	instance: Render_Instance,
	selected_uuids: []shared.Entity_UUID,
) {
	if renderer == nil ||
	   instance.slot < 0 ||
	   instance.slot >= len(renderer.gpu_instance_records) {
		return
	}
	selected := false
	for selected_uuid in selected_uuids {
		if instance.entity.uuid == selected_uuid || instance.entity.model_owner == selected_uuid {
			selected = true
			break
		}
	}
	value := f32(0)
	if selected {
		value = 1
	}
	wgpu_set_editor_selected_slot(renderer, instance.slot, selected)
	record := &renderer.gpu_instance_records[instance.slot]
	if record.render_flags[3] == value {
		return
	}
	record.render_flags[3] = value
	append(&renderer.gpu_dirty_indices, instance.slot)
}

wgpu_encode_gpu_instance_expansion :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
) -> string {
	if renderer == nil || len(renderer.gpu_transform_updates) <= 1 {
		return ""
	}
	timestamps, timestamps_enabled := wgpu_gpu_pass_timestamps(renderer, .Instance_Expansion)
	timestamps_ptr: ^wgpu.PassTimestampWrites
	if timestamps_enabled {
		timestamps_ptr = &timestamps
	}
	pass := wgpu.CommandEncoderBeginComputePass(
		encoder,
		&wgpu.ComputePassDescriptor {
			label = "Scrapbot GPU Transform Expansion Pass",
			timestampWrites = timestamps_ptr,
		},
	)
	if pass == nil {
		return "failed to begin GPU transform expansion pass"
	}
	defer wgpu.ComputePassEncoderRelease(pass)
	wgpu.ComputePassEncoderSetPipeline(pass, renderer.gpu_transform_pipeline)
	wgpu.ComputePassEncoderSetBindGroup(pass, 0, renderer.gpu_transform_bind_group)
	update_count := len(renderer.gpu_transform_updates) - 1
	workgroups := u32((update_count + 63) / 64)
	wgpu.ComputePassEncoderDispatchWorkgroups(pass, workgroups, 1, 1)
	wgpu.ComputePassEncoderEnd(pass)
	renderer.gpu_instance_expand_dispatch_count += 1
	renderer.gpu_instance_expanded_slot_count += u64(update_count)
	return ""
}

wgpu_capture_object_visibility :: proc "contextless" (
	live_capture, query_view, occlusion_enabled, frozen, evidence_valid: bool,
) -> bool {
	if live_capture {
		return true
	}
	return query_view && occlusion_enabled && (!frozen || !evidence_valid)
}

wgpu_encode_gpu_culling :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	batch_count: int,
	cull_phase: WGPU_GPU_Cull_Phase = .Enabled,
	timestamp_phase: WGPU_GPU_Timestamp_Phase = .Cull,
) -> string {
	if batch_count <= 0 || renderer.gpu_slot_count <= 0 {
		renderer.gpu_visibility_counters = {}
		return ""
	}
	uniform_buffer := renderer.gpu_cull_initial_uniform_buffer
	if cull_phase == .Enabled {
		uniform_buffer = renderer.gpu_cull_refine_uniform_buffer
	}
	wgpu.CommandEncoderCopyBufferToBuffer(
		encoder,
		uniform_buffer,
		0,
		renderer.gpu_cull_uniform_buffer,
		0,
		u64(size_of(WGPU_GPU_Cull_Uniform)),
	)
	renderer.gpu_cull_pass_count += 1
	debug_view := shared.Render_Debug_View(renderer.gpu_render_uniform.debug.x)
	capture_debug_evidence :=
		renderer.gpu_cull_bind_group != nil &&
		wgpu_capture_object_visibility(
			renderer.live_debug_visibility_capture,
			debug_view == .Occlusion_Queries,
			cull_phase == .Enabled,
			renderer.gpu_render_uniform.debug.w != 0,
			renderer.gpu_occlusion_debug_evidence_valid,
		)
	if capture_debug_evidence {
		debug_draw := WGPU_Draw_Indirect {
			vertex_count = WGPU_OBJECT_DEBUG_VERTEX_COUNT,
		}
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_object_debug_indirect_buffer,
			0,
			&debug_draw,
			uint(size_of(debug_draw)),
		)
	}
	wgpu_visibility_reset(renderer, encoder, batch_count)
	copy_size :=
		u64(renderer.gpu_indirect_command_count) * u64(size_of(WGPU_Draw_Indexed_Indirect))
	wgpu.CommandEncoderCopyBufferToBuffer(
		encoder,
		renderer.gpu_indirect_template_buffer,
		0,
		renderer.gpu_indirect_buffer,
		0,
		copy_size,
	)
	wgpu.CommandEncoderCopyBufferToBuffer(
		encoder,
		renderer.gpu_shadow_indirect_template_buffer,
		0,
		renderer.gpu_shadow_indirect_buffer,
		0,
		copy_size,
	)
	for cascade_index in 1 ..< WGPU_SHADOW_CASCADE_COUNT {
		wgpu.CommandEncoderCopyBufferToBuffer(
			encoder,
			renderer.gpu_shadow_indirect_template_buffer,
			0,
			renderer.gpu_shadow_indirect_buffer,
			u64(cascade_index) * copy_size,
			copy_size,
		)
	}

	cull_timestamps, cull_timestamps_enabled := wgpu_gpu_pass_timestamps(renderer, timestamp_phase)
	cull_timestamps_ptr: ^wgpu.PassTimestampWrites
	if cull_timestamps_enabled {
		cull_timestamps_ptr = &cull_timestamps
	}
	pass := wgpu.CommandEncoderBeginComputePass(
		encoder,
		&wgpu.ComputePassDescriptor {
			label = "Scrapbot GPU Visibility Pass",
			timestampWrites = cull_timestamps_ptr,
		},
	)
	if pass == nil {
		return "failed to begin GPU visibility pass"
	}
	defer wgpu.ComputePassEncoderRelease(pass)
	workgroups := u32((renderer.gpu_slot_count + 63) / 64)
	if renderer.draw_batch_cache.batch_count > 0 {
		wgpu.ComputePassEncoderSetPipeline(pass, renderer.gpu_cull_pipeline)
		wgpu.ComputePassEncoderSetBindGroup(pass, 0, renderer.gpu_cull_bind_group)
		wgpu.ComputePassEncoderDispatchWorkgroups(pass, workgroups, WGPU_SHADOW_CASCADE_COUNT, 1)
	}

	if capture_debug_evidence {
		wgpu.ComputePassEncoderSetPipeline(pass, renderer.gpu_object_debug_cull_pipeline)
		wgpu.ComputePassEncoderSetBindGroup(pass, 0, renderer.gpu_cull_bind_group)
		wgpu.ComputePassEncoderDispatchWorkgroups(pass, workgroups, 1, 1)
	}
	wgpu.ComputePassEncoderEnd(pass)
	if capture_debug_evidence {
		wgpu.CommandEncoderCopyBufferToBuffer(
			encoder,
			renderer.gpu_visibility_counter_buffer,
			u64(offset_of(WGPU_GPU_Visibility_Summary, object_debug_records)),
			renderer.gpu_object_debug_indirect_buffer,
			u64(offset_of(WGPU_Draw_Indirect, instance_count)),
			u64(size_of(u32)),
		)
		if debug_view == .Occlusion_Queries {
			renderer.gpu_occlusion_debug_evidence_valid = true
		}
	}
	return ""
}

wgpu_encode_object_debug_overlay :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	viewport: ui.Rect,
) -> string {
	if renderer == nil {
		return ""
	}
	debug_view := shared.Render_Debug_View(renderer.gpu_render_uniform.debug.x)
	if debug_view != .Occlusion_Queries {
		return ""
	}
	if debug_view == .Occlusion_Queries && !renderer.gpu_occlusion_debug_evidence_valid {
		return ""
	}
	attachment := wgpu.RenderPassColorAttachment {
		view = renderer.hdr_view,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp = .Load,
		storeOp = .Store,
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = "Scrapbot Object Visibility Debug Overlay Pass",
			colorAttachmentCount = 1,
			colorAttachments = &attachment,
		},
	)
	if pass == nil {
		return "failed to begin object visibility debug overlay pass"
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
	wgpu.RenderPassEncoderSetPipeline(pass, renderer.gpu_object_debug_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, renderer.gpu_object_debug_bind_group)
	wgpu.RenderPassEncoderDrawIndirect(pass, renderer.gpu_object_debug_indirect_buffer, 0)
	wgpu.RenderPassEncoderEnd(pass)
	return ""
}

wgpu_prepare_cpu_culling :: proc(
	renderer: ^WGPU_Renderer,
	render_list: ^Render_List,
	width, height: u32,
) {
	if renderer == nil || renderer.gpu_slot_count <= 0 {
		return
	}
	view_projection := wgpu_build_view_projection(
		render_list.camera,
		render_list.has_camera,
		width,
		height,
	)
	shadow_cascades: WGPU_Shadow_Cascades
	for &cascade_matrix in shadow_cascades.matrices {
		cascade_matrix = mat4_identity()
	}
	if render_list.directional_light_count > 0 {
		shadow_cascades = wgpu_build_directional_shadow_cascades(
			render_list.camera,
			render_list.has_camera,
			width,
			height,
			render_list.directional_lights[0].light.direction,
			max(renderer.shadow_map_resolution, WGPU_SHADOW_MAP_MIN_SIZE),
		)
	}
	camera_planes := wgpu_extract_frustum_planes(view_projection)
	if len(renderer.gpu_cpu_visible) < renderer.gpu_visible_capacity {
		resize(&renderer.gpu_cpu_visible, renderer.gpu_visible_capacity)
	}
	shadow_visible_capacity := renderer.gpu_visible_capacity * WGPU_SHADOW_CASCADE_COUNT
	if len(renderer.gpu_cpu_shadow_visible) < shadow_visible_capacity {
		resize(&renderer.gpu_cpu_shadow_visible, shadow_visible_capacity)
	}
	visible := renderer.gpu_cpu_visible[:renderer.gpu_visible_capacity]
	shadow_visible := renderer.gpu_cpu_shadow_visible[:shadow_visible_capacity]
	camera_counts := wgpu_cpu_cull_counts(
		renderer.gpu_instance_records[:renderer.gpu_slot_count],
		camera_planes,
		renderer.draw_batch_cache.batch_count,
		false,
		view_projection,
	)
	defer delete(camera_counts)
	shadow_counts: [WGPU_SHADOW_CASCADE_COUNT][dynamic]u32
	shadow_planes: [WGPU_SHADOW_CASCADE_COUNT][6][4]f32
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		shadow_planes[cascade_index] = wgpu_extract_frustum_planes(
			shadow_cascades.matrices[cascade_index],
		)
		shadow_counts[cascade_index] = wgpu_cpu_cull_counts(
			renderer.gpu_instance_records[:renderer.gpu_slot_count],
			shadow_planes[cascade_index],
			renderer.draw_batch_cache.batch_count,
			true,
			view_projection,
		)
	}
	defer {
		for counts in shadow_counts {
			delete(counts)
		}
	}
	renderer.gpu_visibility_counters = {}
	for count in camera_counts {
		renderer.gpu_visibility_counters.visible_instances += count
		if count > 0 {
			renderer.gpu_visibility_counters.visible_batches += 1
		}
	}
	for counts in shadow_counts {
		for count in counts {
			renderer.gpu_visibility_counters.shadow_visible_instances += count
		}
	}
	camera_cursors := make([]u32, renderer.draw_batch_cache.batch_count)
	defer delete(camera_cursors)
	shadow_cursors: [WGPU_SHADOW_CASCADE_COUNT][]u32
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		shadow_cursors[cascade_index] = make([]u32, renderer.draw_batch_cache.batch_count)
	}
	defer {
		for cursors in shadow_cursors {
			delete(cursors)
		}
	}
	for instance, slot in renderer.gpu_instance_records[:renderer.gpu_slot_count] {
		lod_level := wgpu_cpu_instance_lod_level(instance, view_projection)
		batch_index := instance.batch_indices[lod_level]
		if instance.active == 0 || int(batch_index) >= renderer.draw_batch_cache.batch_count {
			continue
		}
		batch := renderer.draw_batch_cache.batches[batch_index]
		if wgpu_sphere_visible(instance.bounds, camera_planes) {
			renderer.gpu_visibility_counters.frustum_candidates += 1
			visible[batch.visible_offset + camera_cursors[batch_index]] = u32(slot)
			camera_cursors[batch_index] += 1
			renderer.gpu_visibility_counters.lod_visible_instances[lod_level] += 1
		} else {
			renderer.gpu_visibility_counters.frustum_culled_instances += 1
		}
		for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
			if instance.render_flags[0] > 0.5 &&
			   wgpu_sphere_visible(instance.bounds, shadow_planes[cascade_index]) {
				shadow_visible_index :=
					cascade_index * renderer.gpu_visible_capacity +
					int(batch.visible_offset + shadow_cursors[cascade_index][batch_index])
				shadow_visible[shadow_visible_index] = u32(slot)
				shadow_cursors[cascade_index][batch_index] += 1
			}
		}
	}
	indirect := make([]WGPU_Draw_Indexed_Indirect, len(renderer.gpu_indirect_templates))
	defer delete(indirect)
	copy(indirect, renderer.gpu_indirect_templates[:])
	shadow_indirect := make(
		[]WGPU_Draw_Indexed_Indirect,
		len(renderer.gpu_indirect_templates) * WGPU_SHADOW_CASCADE_COUNT,
	)
	defer delete(shadow_indirect)
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		start := cascade_index * len(renderer.gpu_indirect_templates)
		copy(shadow_indirect[start:start + len(renderer.gpu_indirect_templates)], indirect)
	}
	for batch_index in 0 ..< renderer.draw_batch_cache.batch_count {
		indirect[batch_index].instance_count = camera_counts[batch_index]
		for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
			shadow_indirect_index :=
				cascade_index * renderer.gpu_indirect_command_count + batch_index
			shadow_indirect[shadow_indirect_index].instance_count =
				shadow_counts[cascade_index][batch_index]
		}
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_visible_buffer,
		0,
		raw_data(visible),
		uint(len(visible) * size_of(u32)),
	)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_shadow_visible_buffer,
		0,
		raw_data(shadow_visible),
		uint(len(shadow_visible) * size_of(u32)),
	)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_indirect_buffer,
		0,
		raw_data(indirect),
		uint(len(indirect) * size_of(WGPU_Draw_Indexed_Indirect)),
	)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_shadow_indirect_buffer,
		0,
		raw_data(shadow_indirect),
		uint(len(shadow_indirect) * size_of(WGPU_Draw_Indexed_Indirect)),
	)
}

wgpu_draw_submission_span :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	batches: []WGPU_Draw_Batch,
	start: int,
) -> WGPU_Draw_Submission_Span {
	if renderer == nil || start < 0 || start >= len(batches) {
		return {next_batch = start + 1}
	}
	return {next_batch = start + 1, first_indirect = u32(start), indirect_count = 1}
}

wgpu_draw_submission_count :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	batches: []WGPU_Draw_Batch,
) -> int {
	return len(batches)
}

wgpu_shadow_draw_submission_span :: wgpu_draw_submission_span
wgpu_shadow_draw_submission_count :: wgpu_draw_submission_count
