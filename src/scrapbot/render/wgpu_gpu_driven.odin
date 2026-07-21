package render

import resources "../resources"
import shared "../shared"
import ui "../ui"
import "core:fmt"
import "core:math"
import "core:slice"
import "vendor:wgpu"

WGPU_INSTANCE_UPLOAD_MERGE_GAP :: 8

wgpu_align_visible_capacity :: proc(count: u32) -> u32 {
	return(
		((max(count, 1) + WGPU_VISIBLE_ALIGNMENT - 1) / WGPU_VISIBLE_ALIGNMENT) *
		WGPU_VISIBLE_ALIGNMENT \
	)
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

	world_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Vertex, .Fragment},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_GPU_Render_Uniform))},
		},
		{
			binding = 1,
			visibility = {.Fragment},
			texture = {sampleType = .Depth, viewDimension = ._2D},
		},
		{binding = 2, visibility = {.Fragment}, sampler = {type = .Comparison}},
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

	vertex_attributes := [?]wgpu.VertexAttribute {
		{format = .Float32x3, offset = 0, shaderLocation = 0},
		{format = .Float32x3, offset = 12, shaderLocation = 1},
		{format = .Float32x2, offset = 24, shaderLocation = 2},
	}
	vertex_buffer_layout := wgpu.VertexBufferLayout {
		stepMode = .Vertex,
		arrayStride = u64(size_of(resources.Vertex)),
		attributeCount = uint(len(vertex_attributes)),
		attributes = raw_data(vertex_attributes[:]),
	}
	color_target := wgpu.ColorTargetState {
		format = .RGBA16Float,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment_state := wgpu.FragmentState {
		module = renderer.gpu_driven_shader,
		entryPoint = "fs_main",
		targetCount = 1,
		targets = &color_target,
	}
	renderer.gpu_driven_pipeline = wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = "Scrapbot GPU-Driven Render Pipeline",
			layout = renderer.gpu_driven_pipeline_layout,
			vertex = {
				module = renderer.gpu_driven_shader,
				entryPoint = "vs_main",
				bufferCount = 1,
				buffers = &vertex_buffer_layout,
			},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = .None},
			depthStencil = &wgpu.DepthStencilState {
				format = .Depth24Plus,
				depthWriteEnabled = .False,
				depthCompare = .LessEqual,
			},
			multisample = {count = 1, mask = 0xFFFF_FFFF},
			fragment = &fragment_state,
		},
	)
	if renderer.gpu_driven_pipeline == nil {
		return "failed to create GPU-driven render pipeline"
	}
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
	renderer.gpu_driven_depth_pipeline = wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = "Scrapbot GPU-Driven Depth Prepass Pipeline",
			layout = renderer.gpu_driven_depth_pipeline_layout,
			vertex = {
				module = renderer.gpu_driven_shader,
				entryPoint = "depth_vs",
				bufferCount = 1,
				buffers = &vertex_buffer_layout,
			},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = .None},
			depthStencil = &wgpu.DepthStencilState {
				format = .Depth24Plus,
				depthWriteEnabled = .True,
				depthCompare = .Less,
			},
			multisample = {count = 1, mask = 0xFFFF_FFFF},
		},
	)
	if renderer.gpu_driven_depth_pipeline == nil {
		return "failed to create GPU-driven depth prepass pipeline"
	}
	renderer.gpu_driven_shadow_pipeline = wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = "Scrapbot GPU-Driven Shadow Pipeline",
			layout = renderer.gpu_driven_shadow_pipeline_layout,
			vertex = {
				module = renderer.gpu_driven_shader,
				entryPoint = "shadow_vs",
				bufferCount = 1,
				buffers = &vertex_buffer_layout,
			},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = .Back},
			depthStencil = &wgpu.DepthStencilState {
				format = .Depth32Float,
				depthWriteEnabled = .True,
				depthCompare = .Less,
			},
			multisample = {count = 1, mask = 0xFFFF_FFFF},
		},
	)
	if renderer.gpu_driven_shadow_pipeline == nil {
		return "failed to create GPU-driven shadow pipeline"
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
			label = "Scrapbot GPU Culling Pipeline",
			layout = renderer.gpu_cull_pipeline_layout,
			compute = {module = renderer.gpu_cull_shader, entryPoint = "cull_instances"},
		},
	)
	if renderer.gpu_cull_pipeline == nil {
		return "failed to create GPU culling pipeline"
	}
	if hiz_err := wgpu_create_hiz_pipelines(renderer); hiz_err != "" {
		return hiz_err
	}
	if hiz_err := wgpu_ensure_hiz_targets(renderer, 1, 1); hiz_err != "" {
		return hiz_err
	}

	instance_bytes := u64(WGPU_MAX_GPU_INSTANCES) * u64(size_of(WGPU_GPU_Instance))
	transform_update_bytes :=
		u64(WGPU_MAX_GPU_INSTANCES + 1) * u64(size_of(WGPU_GPU_Instance_Transform))
	visible_entries := WGPU_MAX_GPU_INSTANCES + WGPU_INITIAL_DRAW_CAPACITY * WGPU_VISIBLE_ALIGNMENT
	visible_bytes := u64(visible_entries) * u64(size_of(u32))
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
		visible_bytes,
	)
	renderer.gpu_indirect_template_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Indirect Template",
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
		indirect_bytes,
	)
	renderer.gpu_cull_uniform_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Culling Uniform",
		{.Uniform, .CopyDst},
		u64(size_of(WGPU_GPU_Cull_Uniform)),
	)
	renderer.gpu_render_uniform_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Render Uniform",
		{.Uniform, .CopyDst},
		u64(size_of(WGPU_GPU_Render_Uniform)),
	)
	renderer.gpu_visibility_counter_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Visibility Counters",
		{.Storage, .CopySrc, .CopyDst},
		u64(size_of(WGPU_GPU_Visibility_Counters)),
	)
	if renderer.gpu_instance_buffer == nil ||
	   renderer.gpu_transform_update_buffer == nil ||
	   renderer.gpu_batch_info_buffer == nil ||
	   renderer.gpu_visible_buffer == nil ||
	   renderer.gpu_shadow_visible_buffer == nil ||
	   renderer.gpu_indirect_template_buffer == nil ||
	   renderer.gpu_indirect_buffer == nil ||
	   renderer.gpu_shadow_indirect_buffer == nil ||
	   renderer.gpu_cull_uniform_buffer == nil ||
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

	cull_bind_entries := [?]wgpu.BindGroupEntry {
		{binding = 0, buffer = renderer.gpu_instance_buffer, size = instance_bytes},
		{binding = 1, buffer = renderer.gpu_batch_info_buffer, size = batch_bytes},
		{binding = 2, buffer = renderer.gpu_visible_buffer, size = visible_bytes},
		{binding = 3, buffer = renderer.gpu_shadow_visible_buffer, size = visible_bytes},
		{binding = 4, buffer = renderer.gpu_indirect_buffer, size = indirect_bytes},
		{binding = 5, buffer = renderer.gpu_shadow_indirect_buffer, size = indirect_bytes},
		{
			binding = 6,
			buffer = renderer.gpu_cull_uniform_buffer,
			size = u64(size_of(WGPU_GPU_Cull_Uniform)),
		},
		{binding = 7, textureView = renderer.gpu_hiz_view},
		{
			binding = 8,
			buffer = renderer.gpu_visibility_counter_buffer,
			size = u64(size_of(WGPU_GPU_Visibility_Counters)),
		},
	}
	renderer.gpu_cull_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot GPU Culling Bind Group",
			layout = renderer.gpu_cull_bind_group_layout,
			entryCount = uint(len(cull_bind_entries)),
			entries = raw_data(cull_bind_entries[:]),
		},
	)
	if renderer.gpu_cull_bind_group == nil {
		return "failed to create GPU culling bind group"
	}
	renderer.gpu_draw_capacity = WGPU_INITIAL_DRAW_CAPACITY
	renderer.gpu_visible_buffer_capacity = visible_entries
	if visibility_err := wgpu_create_visibility_readbacks(renderer); visibility_err != "" {
		return visibility_err
	}
	return ""
}

wgpu_grow_capacity :: proc(current, required: int) -> int {
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
	instance_bytes := u64(WGPU_MAX_GPU_INSTANCES) * u64(size_of(WGPU_GPU_Instance))
	batch_bytes := u64(renderer.gpu_draw_capacity) * u64(size_of(WGPU_GPU_Batch_Info))
	visible_bytes := u64(renderer.gpu_visible_buffer_capacity) * u64(size_of(u32))
	indirect_bytes := u64(renderer.gpu_draw_capacity) * u64(size_of(WGPU_Draw_Indexed_Indirect))
	entries := [?]wgpu.BindGroupEntry {
		{binding = 0, buffer = renderer.gpu_instance_buffer, size = instance_bytes},
		{binding = 1, buffer = renderer.gpu_batch_info_buffer, size = batch_bytes},
		{binding = 2, buffer = renderer.gpu_visible_buffer, size = visible_bytes},
		{binding = 3, buffer = renderer.gpu_shadow_visible_buffer, size = visible_bytes},
		{binding = 4, buffer = renderer.gpu_indirect_buffer, size = indirect_bytes},
		{binding = 5, buffer = renderer.gpu_shadow_indirect_buffer, size = indirect_bytes},
		{
			binding = 6,
			buffer = renderer.gpu_cull_uniform_buffer,
			size = u64(size_of(WGPU_GPU_Cull_Uniform)),
		},
		{binding = 7, textureView = renderer.gpu_hiz_view},
		{
			binding = 8,
			buffer = renderer.gpu_visibility_counter_buffer,
			size = u64(size_of(WGPU_GPU_Visibility_Counters)),
		},
	}
	bind_group := wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot GPU Culling Bind Group",
			layout = renderer.gpu_cull_bind_group_layout,
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
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
	indirect_bytes := u64(draw_capacity) * u64(size_of(WGPU_Draw_Indexed_Indirect))
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
		visible_bytes,
	)
	indirect_template_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Indirect Template",
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
		indirect_bytes,
	)
	new_buffers := [?]wgpu.Buffer {
		batch_buffer,
		visible_buffer,
		shadow_visible_buffer,
		indirect_template_buffer,
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
	instance_bytes := u64(WGPU_MAX_GPU_INSTANCES) * u64(size_of(WGPU_GPU_Instance))
	cull_bind_entries := [?]wgpu.BindGroupEntry {
		{binding = 0, buffer = renderer.gpu_instance_buffer, size = instance_bytes},
		{binding = 1, buffer = batch_buffer, size = batch_bytes},
		{binding = 2, buffer = visible_buffer, size = visible_bytes},
		{binding = 3, buffer = shadow_visible_buffer, size = visible_bytes},
		{binding = 4, buffer = indirect_buffer, size = indirect_bytes},
		{binding = 5, buffer = shadow_indirect_buffer, size = indirect_bytes},
		{
			binding = 6,
			buffer = renderer.gpu_cull_uniform_buffer,
			size = u64(size_of(WGPU_GPU_Cull_Uniform)),
		},
		{binding = 7, textureView = renderer.gpu_hiz_view},
		{
			binding = 8,
			buffer = renderer.gpu_visibility_counter_buffer,
			size = u64(size_of(WGPU_GPU_Visibility_Counters)),
		},
	}
	cull_bind_group := wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot GPU Culling Bind Group",
			layout = renderer.gpu_cull_bind_group_layout,
			entryCount = uint(len(cull_bind_entries)),
			entries = raw_data(cull_bind_entries[:]),
		},
	)
	if cull_bind_group == nil {
		for buffer in new_buffers {
			wgpu.BufferRelease(buffer)
		}
		return "failed to grow GPU culling bind group"
	}
	if renderer.gpu_cull_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_cull_bind_group)
	}
	old_buffers := [?]wgpu.Buffer {
		renderer.gpu_batch_info_buffer,
		renderer.gpu_visible_buffer,
		renderer.gpu_shadow_visible_buffer,
		renderer.gpu_indirect_template_buffer,
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
	renderer.gpu_indirect_buffer = indirect_buffer
	renderer.gpu_shadow_indirect_buffer = shadow_indirect_buffer
	renderer.gpu_cull_bind_group = cull_bind_group
	renderer.gpu_draw_capacity = draw_capacity
	renderer.gpu_visible_buffer_capacity = visible_capacity
	renderer.gpu_draw_database_rebuild_count += 1
	clear(&renderer.gpu_indirect_templates)
	return ""
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
		if batch.shadow_bind_group != nil {
			wgpu.BindGroupRelease(batch.shadow_bind_group)
		}
		batch.world_bind_group = nil
		batch.shadow_bind_group = nil
	}
}

wgpu_make_batch_bind_group :: proc(
	renderer: ^WGPU_Renderer,
	visible_buffer: wgpu.Buffer,
	visible_offset, visible_capacity: u32,
	label: string,
	shadow: bool = false,
) -> wgpu.BindGroup {
	if shadow {
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
				offset = u64(visible_offset) * u64(size_of(u32)),
				size = u64(visible_capacity) * u64(size_of(u32)),
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
		{binding = 1, textureView = renderer.shadow_view},
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
	for batch_index in 0 ..< cache.batch_count {
		batch := &cache.batches[batch_index]
		batch.visible_offset = visible_offset
		batch.visible_capacity = wgpu_align_visible_capacity(batch.instance_count)
		visible_offset += batch.visible_capacity
	}
	if buffer_err := wgpu_ensure_gpu_draw_buffers(
		renderer,
		cache.batch_count,
		int(visible_offset),
	); buffer_err != "" {
		return buffer_err
	}
	batch_info := make([]WGPU_GPU_Batch_Info, cache.batch_count)
	defer delete(batch_info)
	for batch_index in 0 ..< cache.batch_count {
		batch := &cache.batches[batch_index]
		geometry, geometry_err := wgpu_geometry_cache(renderer, registry, batch.geometry)
		if geometry_err != "" {
			return geometry_err
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
		batch.shadow_bind_group = wgpu_make_batch_bind_group(
			renderer,
			renderer.gpu_shadow_visible_buffer,
			batch.visible_offset,
			batch.visible_capacity,
			"Scrapbot GPU-Driven Shadow Batch Bind Group",
			true,
		)
		if batch.world_bind_group == nil || batch.shadow_bind_group == nil {
			return "failed to create GPU-driven batch bind groups"
		}
	}
	renderer.gpu_visible_capacity = int(visible_offset)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_batch_info_buffer,
		0,
		raw_data(batch_info),
		uint(len(batch_info) * size_of(WGPU_GPU_Batch_Info)),
	)
	return ""
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
	if len(renderer.gpu_indirect_templates) != cache.batch_count {
		resize(&renderer.gpu_indirect_templates, cache.batch_count)
		changed = true
	}
	for batch, batch_index in cache.batches[:cache.batch_count] {
		geometry, ok := resources.get_geometry(registry, batch.geometry)
		if !ok {
			return false, "GPU draw batch references unavailable geometry"
		}
		template := WGPU_Draw_Indexed_Indirect {
			index_count = u32(len(geometry.indices)),
			first_instance = 0,
		}
		if renderer.gpu_indirect_templates[batch_index] != template {
			renderer.gpu_indirect_templates[batch_index] = template
			changed = true
		}
	}
	return
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

wgpu_build_gpu_instance :: proc(
	instance: Render_Instance,
	geometry: ^resources.Geometry,
	material: ^resources.Material,
	batch_indices: [shared.MAX_GEOMETRY_LODS]u32,
) -> WGPU_GPU_Instance {
	color := material.desc.base_color
	emissive := material.desc.emissive
	model := wgpu_build_model(instance.transform)
	return WGPU_GPU_Instance {
		model = model,
		normal_model = wgpu_build_normal_model_from_model(model, instance.transform.scale),
		color = {color.x, color.y, color.z, color.w},
		emissive = {emissive.x, emissive.y, emissive.z, 0},
		shadow_flags = {
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
		lod_count = u32(geometry.lod_count),
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
	for handle, lod_index in geometry.lod_handles[:geometry.lod_count] {
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
	capacity_grew: bool,
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
			capacity_grew = capacity_grew || batch.instance_count > batch.visible_capacity
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
	capacity_grew: bool,
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
		batch_indices, batches_ok = wgpu_batch_indices_for_instance(cache, instance, registry)
		if !batches_ok {
			return false, "GPU instance is missing its draw batch"
		}
	}
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
		lod_count = u32(geometry.lod_count),
	}
	membership_changed :=
		!previous_active ||
		!wgpu_instance_membership_matches(previous_source, batch_indices, u32(geometry.lod_count))
	if membership_changed && previous_active {
		_ = wgpu_adjust_batch_membership(
			cache,
			previous_source.batch_indices,
			previous_source.lod_count,
			-1,
		)
	}
	if membership_changed {
		capacity_grew = wgpu_adjust_batch_membership(
			cache,
			batch_indices,
			u32(geometry.lod_count),
			1,
		)
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
			)
		}
		if static_changed {
			append(&renderer.gpu_dirty_indices, slot)
		}
		if transform_input_changed {
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
		for handle, lod_index in geometry.lod_handles[:geometry.lod_count] {
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
		if shadow && instance.shadow_flags[0] < 0.5 {
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
) -> (
	[]WGPU_Draw_Batch,
	int,
	string,
) {
	slot_count := render_list.instance_slot_count
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
	view_projection := wgpu_build_view_projection(
		render_list.camera,
		render_list.has_camera,
		u32(viewport.width),
		u32(viewport.height),
	)
	if hiz_err := wgpu_ensure_hiz_targets(renderer, target_width, target_height); hiz_err != "" {
		return nil, 0, hiz_err
	}
	light_view_projection := mat4_identity()
	if render_list.directional_light_count > 0 {
		light_view_projection = wgpu_build_directional_light_view_projection(
			render_list.directional_lights[0].light.direction,
		)
	}
	uniform.view_projection = view_projection
	uniform.shadow_view_projection = light_view_projection
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
	for light, index in render_list.point_lights[:render_list.point_light_count] {
		uniform.point_position_range[index] = {
			light.position.x,
			light.position.y,
			light.position.z,
			light.light.range,
		}
		uniform.point_color_intensity[index] = {
			light.light.color.x,
			light.light.color.y,
			light.light.color.z,
			light.light.intensity,
		}
	}
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
	capacity_grew := false
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
			lod_count = u32(geometry.lod_count),
		}
		if !renderer.gpu_active_slots[slot] || renderer.gpu_instance_sources[slot] != source {
			record := wgpu_build_gpu_instance(instance, geometry, material, batch_indices)
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
			grew, sync_err := wgpu_sync_dirty_instance_slot(
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
			capacity_grew = capacity_grew || grew
		}
	}
	renderer.gpu_material_revision = registry.material_revision
	if !reset_instances {
		for slot in render_list.dirty_instance_slots {
			grew, sync_err := wgpu_sync_dirty_instance_slot(
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
			capacity_grew = capacity_grew || grew
		}
		for slot in render_list.dirty_transform_slots {
			if slot < 0 || slot >= slot_count {
				continue
			}
			instance := wgpu_render_instance_pointer_by_slot(render_list, slot)
			if instance == nil && !renderer.gpu_active_slots[slot] {
				continue
			}
			if instance != nil && !renderer.gpu_active_slots[slot] {
				grew, sync_err := wgpu_sync_dirty_instance_slot(
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
				capacity_grew = capacity_grew || grew
			}
			if instance == nil || !renderer.gpu_active_slots[slot] {
				return nil, 0, fmt.tprintf(
					"transform-dirty GPU slot %d could not be reconciled (render list: %v, GPU: %v, static dirty: %v)",
					slot,
					instance != nil,
					renderer.gpu_active_slots[slot],
					slice.contains(render_list.dirty_instance_slots[:], slot),
				)
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
			previous_transform^ = instance.transform
			wgpu_update_gpu_instance_transform(
				&renderer.gpu_instance_transform_records[slot],
				instance.transform,
			)
			if cpu_culling {
				geometry, geometry_ok := resources.get_geometry(registry, instance.geometry.handle)
				material, material_ok := resources.get_material(registry, instance.material.handle)
				if !geometry_ok || !material_ok {
					continue
				}
				renderer.gpu_instance_records[slot] = wgpu_build_gpu_instance(
					instance^,
					geometry,
					material,
					previous.batch_indices,
				)
				append(&renderer.gpu_dirty_indices, slot)
			} else {
				wgpu_append_transform_update(renderer, slot)
			}
		}
	}
	if capacity_grew {
		if layout_err := wgpu_refresh_gpu_batch_layout(renderer, cache, registry);
		   layout_err != "" {
			return nil, 0, layout_err
		}
	}
	instance_data_changed :=
		len(renderer.gpu_dirty_indices) > 0 || len(renderer.gpu_transform_updates) > 1
	wgpu_upload_dirty_instance_ranges(renderer, renderer.gpu_dirty_indices[:])
	wgpu_upload_transform_updates(renderer)
	renderer.gpu_slot_count = slot_count
	renderer.gpu_hiz_requested = wgpu_hiz_build_requested(slot_count, instance_data_changed)
	hiz_reusable := wgpu_hiz_reuse_allowed(
		renderer.gpu_hiz_requested,
		renderer.gpu_hiz_valid,
		instance_data_changed,
		renderer.gpu_previous_view_projection,
		view_projection,
	)
	renderer.gpu_current_view_projection = view_projection
	renderer.gpu_hiz_occlusion_enabled = hiz_reusable
	camera_position := Vec3{0, 2, 6}
	if render_list.has_camera {
		camera_position = render_list.camera.transform.position
	}
	cull_uniform := WGPU_GPU_Cull_Uniform {
		camera_planes = wgpu_extract_frustum_planes(view_projection),
		shadow_planes = wgpu_extract_frustum_planes(light_view_projection),
		view_projection = view_projection,
		viewport = {viewport.x, viewport.y, viewport.width, viewport.height},
		camera_position = {camera_position.x, camera_position.y, camera_position.z, 1},
		slot_count = u32(slot_count),
		batch_count = u32(cache.batch_count),
		hiz_mip_count = u32(renderer.gpu_hiz_mip_count),
		hiz_enabled = 1 if hiz_reusable else 0,
	}
	if wgpu_retain_cull_uniform(renderer, cull_uniform) {
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_cull_uniform_buffer,
			0,
			&cull_uniform,
			uint(size_of(cull_uniform)),
		)
	}
	return cache.batches[:cache.batch_count], cache.batch_count, ""
}

wgpu_encode_gpu_instance_expansion :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
) -> string {
	if renderer == nil || len(renderer.gpu_transform_updates) <= 1 {
		return ""
	}
	pass := wgpu.CommandEncoderBeginComputePass(
		encoder,
		&wgpu.ComputePassDescriptor{label = "Scrapbot GPU Transform Expansion Pass"},
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

wgpu_encode_gpu_culling :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	batch_count: int,
) -> string {
	if batch_count <= 0 || renderer.gpu_slot_count <= 0 {
		renderer.gpu_visibility_counters = {}
		return ""
	}
	wgpu_visibility_reset(renderer)
	copy_size := u64(batch_count) * u64(size_of(WGPU_Draw_Indexed_Indirect))
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
		renderer.gpu_indirect_template_buffer,
		0,
		renderer.gpu_shadow_indirect_buffer,
		0,
		copy_size,
	)
	cull_timestamps, cull_timestamps_enabled := wgpu_gpu_pass_timestamps(renderer, .Cull)
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
	wgpu.ComputePassEncoderSetPipeline(pass, renderer.gpu_cull_pipeline)
	wgpu.ComputePassEncoderSetBindGroup(pass, 0, renderer.gpu_cull_bind_group)
	workgroups := u32((renderer.gpu_slot_count + 63) / 64)
	wgpu.ComputePassEncoderDispatchWorkgroups(pass, workgroups, 1, 1)
	wgpu.ComputePassEncoderEnd(pass)
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
	light_view_projection := mat4_identity()
	if render_list.directional_light_count > 0 {
		light_view_projection = wgpu_build_directional_light_view_projection(
			render_list.directional_lights[0].light.direction,
		)
	}
	camera_planes := wgpu_extract_frustum_planes(view_projection)
	shadow_planes := wgpu_extract_frustum_planes(light_view_projection)
	if len(renderer.gpu_cpu_visible) < renderer.gpu_visible_capacity {
		resize(&renderer.gpu_cpu_visible, renderer.gpu_visible_capacity)
		resize(&renderer.gpu_cpu_shadow_visible, renderer.gpu_visible_capacity)
	}
	visible := renderer.gpu_cpu_visible[:renderer.gpu_visible_capacity]
	shadow_visible := renderer.gpu_cpu_shadow_visible[:renderer.gpu_visible_capacity]
	camera_counts := wgpu_cpu_cull_counts(
		renderer.gpu_instance_records[:renderer.gpu_slot_count],
		camera_planes,
		renderer.draw_batch_cache.batch_count,
		false,
		view_projection,
	)
	defer delete(camera_counts)
	shadow_counts := wgpu_cpu_cull_counts(
		renderer.gpu_instance_records[:renderer.gpu_slot_count],
		shadow_planes,
		renderer.draw_batch_cache.batch_count,
		true,
		view_projection,
	)
	defer delete(shadow_counts)
	renderer.gpu_visibility_counters = {}
	for count in camera_counts {
		renderer.gpu_visibility_counters.visible_instances += count
	}
	for count in shadow_counts {
		renderer.gpu_visibility_counters.shadow_visible_instances += count
	}
	camera_cursors := make([]u32, renderer.draw_batch_cache.batch_count)
	defer delete(camera_cursors)
	shadow_cursors := make([]u32, renderer.draw_batch_cache.batch_count)
	defer delete(shadow_cursors)
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
		if instance.shadow_flags[0] > 0.5 && wgpu_sphere_visible(instance.bounds, shadow_planes) {
			shadow_visible[batch.visible_offset + shadow_cursors[batch_index]] = u32(slot)
			shadow_cursors[batch_index] += 1
		}
	}
	indirect := make([]WGPU_Draw_Indexed_Indirect, len(renderer.gpu_indirect_templates))
	defer delete(indirect)
	copy(indirect, renderer.gpu_indirect_templates[:])
	shadow_indirect := make([]WGPU_Draw_Indexed_Indirect, len(renderer.gpu_indirect_templates))
	defer delete(shadow_indirect)
	copy(shadow_indirect, renderer.gpu_indirect_templates[:])
	for batch_index in 0 ..< renderer.draw_batch_cache.batch_count {
		indirect[batch_index].instance_count = camera_counts[batch_index]
		shadow_indirect[batch_index].instance_count = shadow_counts[batch_index]
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
