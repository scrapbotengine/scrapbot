package render

import ui "../ui"
import "core:math"
import "vendor:wgpu"

wgpu_create_clustered_lighting :: proc(renderer: ^WGPU_Renderer) -> string {
	source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_CLUSTERED_LIGHTING_SHADER,
	}
	renderer.gpu_cluster_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &source,
			label = "Scrapbot Clustered Lighting Shader",
		},
	)
	if renderer.gpu_cluster_shader == nil {
		return "failed to create clustered lighting shader"
	}
	entries := [?]wgpu.BindGroupLayoutEntry {
		{binding = 0, visibility = {.Compute}, buffer = {type = .ReadOnlyStorage}},
		{binding = 1, visibility = {.Compute}, buffer = {type = .Storage}},
		{binding = 2, visibility = {.Compute}, buffer = {type = .Storage}},
		{
			binding = 3,
			visibility = {.Compute},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_Cluster_Uniform))},
		},
	}
	renderer.gpu_cluster_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Clustered Lighting Bind Group Layout",
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
	if renderer.gpu_cluster_bind_group_layout == nil {
		return "failed to create clustered lighting bind group layout"
	}
	renderer.gpu_cluster_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Clustered Lighting Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.gpu_cluster_bind_group_layout,
		},
	)
	if renderer.gpu_cluster_pipeline_layout == nil {
		return "failed to create clustered lighting pipeline layout"
	}
	renderer.gpu_cluster_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Clustered Lighting Pipeline",
			layout = renderer.gpu_cluster_pipeline_layout,
			compute = {module = renderer.gpu_cluster_shader, entryPoint = "assign_lights"},
		},
	)
	if renderer.gpu_cluster_pipeline == nil {
		return "failed to create clustered lighting pipeline"
	}
	renderer.gpu_point_light_capacity = WGPU_CLUSTER_INITIAL_LIGHT_CAPACITY
	renderer.gpu_cluster_light_capacity = WGPU_CLUSTER_INITIAL_LIGHT_CAPACITY
	renderer.gpu_point_light_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot Point Light Table",
		{.Storage, .CopyDst},
		u64(renderer.gpu_point_light_capacity) * u64(size_of(WGPU_GPU_Point_Light)),
	)
	renderer.gpu_cluster_count_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot Cluster Light Counts",
		{.Storage, .CopyDst},
		u64(WGPU_CLUSTER_COUNT) * u64(size_of(u32)),
	)
	renderer.gpu_cluster_index_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot Cluster Light Indices",
		{.Storage},
		u64(WGPU_CLUSTER_COUNT * renderer.gpu_cluster_light_capacity) * u64(size_of(u32)),
	)
	renderer.gpu_cluster_uniform_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot Cluster Uniform",
		{.Uniform, .CopyDst},
		u64(size_of(WGPU_Cluster_Uniform)),
	)
	if renderer.gpu_point_light_buffer == nil ||
	   renderer.gpu_cluster_count_buffer == nil ||
	   renderer.gpu_cluster_index_buffer == nil ||
	   renderer.gpu_cluster_uniform_buffer == nil {
		return "failed to allocate clustered lighting buffers"
	}
	renderer.gpu_cluster_bind_group = wgpu_make_cluster_bind_group(
		renderer,
		renderer.gpu_point_light_buffer,
		renderer.gpu_cluster_index_buffer,
		renderer.gpu_point_light_capacity,
		renderer.gpu_cluster_light_capacity,
	)
	if renderer.gpu_cluster_bind_group == nil {
		return "failed to create clustered lighting bind group"
	}
	renderer.gpu_cluster_dirty = true
	return ""
}

wgpu_make_cluster_bind_group :: proc(
	renderer: ^WGPU_Renderer,
	point_light_buffer, cluster_index_buffer: wgpu.Buffer,
	point_light_capacity, cluster_light_capacity: int,
) -> wgpu.BindGroup {
	bind_entries := [?]wgpu.BindGroupEntry {
		{
			binding = 0,
			buffer = point_light_buffer,
			size = u64(point_light_capacity) * u64(size_of(WGPU_GPU_Point_Light)),
		},
		{
			binding = 1,
			buffer = renderer.gpu_cluster_count_buffer,
			size = u64(WGPU_CLUSTER_COUNT) * u64(size_of(u32)),
		},
		{
			binding = 2,
			buffer = cluster_index_buffer,
			size = u64(WGPU_CLUSTER_COUNT * cluster_light_capacity) * u64(size_of(u32)),
		},
		{
			binding = 3,
			buffer = renderer.gpu_cluster_uniform_buffer,
			size = u64(size_of(WGPU_Cluster_Uniform)),
		},
	}
	return wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Clustered Lighting Bind Group",
			layout = renderer.gpu_cluster_bind_group_layout,
			entryCount = uint(len(bind_entries)),
			entries = raw_data(bind_entries[:]),
		},
	)
}

wgpu_ensure_clustered_light_capacity :: proc(
	renderer: ^WGPU_Renderer,
	required: int,
) -> (
	old_point_light_buffer, old_cluster_index_buffer: wgpu.Buffer,
	grew: bool,
	err: string,
) {
	if required <= renderer.gpu_point_light_capacity &&
	   required <= renderer.gpu_cluster_light_capacity {
		return
	}
	capacity := wgpu_grow_capacity(renderer.gpu_point_light_capacity, max(required, 1))
	point_light_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot Point Light Table",
		{.Storage, .CopyDst},
		u64(capacity) * u64(size_of(WGPU_GPU_Point_Light)),
	)
	cluster_index_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot Cluster Light Indices",
		{.Storage},
		u64(WGPU_CLUSTER_COUNT * capacity) * u64(size_of(u32)),
	)
	if point_light_buffer == nil || cluster_index_buffer == nil {
		if point_light_buffer != nil {
			wgpu.BufferRelease(point_light_buffer)
		}
		if cluster_index_buffer != nil {
			wgpu.BufferRelease(cluster_index_buffer)
		}
		err = "failed to grow clustered lighting buffers"
		return
	}
	cluster_bind_group := wgpu_make_cluster_bind_group(
		renderer,
		point_light_buffer,
		cluster_index_buffer,
		capacity,
		capacity,
	)
	if cluster_bind_group == nil {
		wgpu.BufferRelease(point_light_buffer)
		wgpu.BufferRelease(cluster_index_buffer)
		err = "failed to grow clustered lighting bind group"
		return
	}
	old_point_light_buffer = renderer.gpu_point_light_buffer
	old_cluster_index_buffer = renderer.gpu_cluster_index_buffer
	if renderer.gpu_cluster_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_cluster_bind_group)
	}
	renderer.gpu_point_light_buffer = point_light_buffer
	renderer.gpu_cluster_index_buffer = cluster_index_buffer
	renderer.gpu_cluster_bind_group = cluster_bind_group
	renderer.gpu_point_light_capacity = capacity
	renderer.gpu_cluster_light_capacity = capacity
	renderer.gpu_point_lights_valid = false
	renderer.gpu_cluster_dirty = true
	grew = true
	return
}

wgpu_prepare_clustered_lighting :: proc(
	renderer: ^WGPU_Renderer,
	render_list: ^Render_List,
	view, projection: Mat4,
	viewport: ui.Rect,
) {
	point_lights_changed :=
		!renderer.gpu_point_lights_valid ||
		len(renderer.gpu_point_lights) != render_list.point_light_count
	if len(renderer.gpu_point_lights) != render_list.point_light_count {
		resize(&renderer.gpu_point_lights, render_list.point_light_count)
	}
	for light, index in render_list.point_lights[:render_list.point_light_count] {
		point_light := WGPU_GPU_Point_Light {
			position_range = {
				light.position.x,
				light.position.y,
				light.position.z,
				light.light.range,
			},
			color_intensity = {
				light.light.color.x,
				light.light.color.y,
				light.light.color.z,
				light.light.intensity,
			},
		}
		if renderer.gpu_point_lights[index] != point_light {
			renderer.gpu_point_lights[index] = point_light
			point_lights_changed = true
		}
	}
	if point_lights_changed {
		renderer.gpu_point_lights_valid = true
		renderer.gpu_cluster_dirty = true
		if render_list.point_light_count > 0 {
			wgpu.QueueWriteBuffer(
				renderer.queue,
				renderer.gpu_point_light_buffer,
				0,
				raw_data(renderer.gpu_point_lights[:render_list.point_light_count]),
				uint(render_list.point_light_count * size_of(WGPU_GPU_Point_Light)),
			)
		}
	}
	near_plane := f32(0.1)
	far_plane := f32(100)
	if render_list.has_camera {
		if render_list.camera.camera.near > 0 {
			near_plane = render_list.camera.camera.near
		}
		if render_list.camera.camera.far > near_plane {
			far_plane = render_list.camera.camera.far
		}
	}
	uniform := WGPU_Cluster_Uniform {
		view = view,
		projection = projection,
		viewport = wgpu_cluster_viewport_uniform(viewport),
		z_parameters = {
			near_plane,
			far_plane,
			math.log2(far_plane / near_plane),
			f32(renderer.gpu_cluster_light_capacity),
		},
		counts = {
			WGPU_CLUSTER_COUNT_X,
			WGPU_CLUSTER_COUNT_Y,
			WGPU_CLUSTER_COUNT_Z,
			u32(render_list.point_light_count),
		},
	}
	if !renderer.gpu_cluster_uniform_valid || renderer.gpu_cluster_uniform != uniform {
		renderer.gpu_cluster_uniform = uniform
		renderer.gpu_cluster_uniform_valid = true
		renderer.gpu_cluster_dirty = true
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_cluster_uniform_buffer,
			0,
			&uniform,
			uint(size_of(uniform)),
		)
	}
	renderer.gpu_clustered_light_count = render_list.point_light_count
}

wgpu_cluster_viewport_uniform :: proc(viewport: ui.Rect) -> [4]f32 {
	return {viewport.x, viewport.y, viewport.width, viewport.height}
}

wgpu_encode_clustered_lighting :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
) -> string {
	if !renderer.gpu_cluster_dirty {
		return ""
	}
	timestamps, timestamps_enabled := wgpu_gpu_pass_timestamps(renderer, .Clustered_Lighting)
	timestamps_ptr: ^wgpu.PassTimestampWrites
	if timestamps_enabled {
		timestamps_ptr = &timestamps
	}
	pass := wgpu.CommandEncoderBeginComputePass(
		encoder,
		&wgpu.ComputePassDescriptor {
			label = "Scrapbot Clustered Lighting Pass",
			timestampWrites = timestamps_ptr,
		},
	)
	if pass == nil {
		return "failed to begin clustered lighting pass"
	}
	wgpu.ComputePassEncoderSetPipeline(pass, renderer.gpu_cluster_pipeline)
	wgpu.ComputePassEncoderSetBindGroup(pass, 0, renderer.gpu_cluster_bind_group)
	workgroups := u32((WGPU_CLUSTER_COUNT + 63) / 64)
	wgpu.ComputePassEncoderDispatchWorkgroups(pass, workgroups, 1, 1)
	wgpu.ComputePassEncoderEnd(pass)
	wgpu.ComputePassEncoderRelease(pass)
	renderer.gpu_cluster_dirty = false
	renderer.gpu_cluster_dispatch_count += 1
	return ""
}
