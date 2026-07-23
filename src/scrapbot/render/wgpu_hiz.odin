package render

import "vendor:wgpu"

wgpu_hiz_mip_count :: proc(width, height: u32) -> int {
	count := 1
	size := max(width, height)
	for size > 1 && count < WGPU_MAX_HIZ_LEVELS {
		size = max(size / 2, 1)
		count += 1
	}
	return count
}

wgpu_create_hiz_pipelines :: proc(renderer: ^WGPU_Renderer) -> string {
	chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_HIZ_COPY_SHADER,
	}
	renderer.gpu_hiz_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor{nextInChain = &chain, label = "Scrapbot Hi-Z Shader"},
	)
	if renderer.gpu_hiz_shader == nil {
		return "failed to create Hi-Z shader"
	}
	downsample_chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_HIZ_DOWNSAMPLE_SHADER,
	}
	renderer.gpu_hiz_downsample_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &downsample_chain,
			label = "Scrapbot Hi-Z Downsample Shader",
		},
	)
	if renderer.gpu_hiz_downsample_shader == nil {
		return "failed to create Hi-Z downsample shader"
	}
	first_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			texture = {sampleType = .Depth, viewDimension = ._2D},
		},
		{
			binding = 1,
			visibility = {.Compute},
			storageTexture = {access = .WriteOnly, format = .R32Float, viewDimension = ._2D},
		},
	}
	downsample_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			texture = {sampleType = .UnfilterableFloat, viewDimension = ._2D},
		},
		{
			binding = 1,
			visibility = {.Compute},
			storageTexture = {access = .WriteOnly, format = .R32Float, viewDimension = ._2D},
		},
	}
	renderer.gpu_hiz_first_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Hi-Z Copy Layout",
			entryCount = uint(len(first_entries)),
			entries = raw_data(first_entries[:]),
		},
	)
	renderer.gpu_hiz_downsample_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Hi-Z Downsample Layout",
			entryCount = uint(len(downsample_entries)),
			entries = raw_data(downsample_entries[:]),
		},
	)
	if renderer.gpu_hiz_first_bind_group_layout == nil ||
	   renderer.gpu_hiz_downsample_bind_group_layout == nil {
		return "failed to create Hi-Z bind group layouts"
	}
	renderer.gpu_hiz_first_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Hi-Z Copy Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.gpu_hiz_first_bind_group_layout,
		},
	)
	renderer.gpu_hiz_downsample_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Hi-Z Downsample Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.gpu_hiz_downsample_bind_group_layout,
		},
	)
	if renderer.gpu_hiz_first_pipeline_layout == nil ||
	   renderer.gpu_hiz_downsample_pipeline_layout == nil {
		return "failed to create Hi-Z pipeline layouts"
	}
	renderer.gpu_hiz_first_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Hi-Z Depth Copy Pipeline",
			layout = renderer.gpu_hiz_first_pipeline_layout,
			compute = {module = renderer.gpu_hiz_shader, entryPoint = "copy_depth"},
		},
	)
	renderer.gpu_hiz_downsample_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Hi-Z Downsample Pipeline",
			layout = renderer.gpu_hiz_downsample_pipeline_layout,
			compute = {
				module = renderer.gpu_hiz_downsample_shader,
				entryPoint = "downsample_depth",
			},
		},
	)
	if renderer.gpu_hiz_first_pipeline == nil || renderer.gpu_hiz_downsample_pipeline == nil {
		return "failed to create Hi-Z compute pipelines"
	}
	return ""
}

wgpu_release_hiz_targets :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil {
		return
	}
	if renderer.gpu_hiz_first_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_hiz_first_bind_group)
		renderer.gpu_hiz_first_bind_group = nil
	}
	for index in 0 ..< WGPU_MAX_HIZ_LEVELS {
		if renderer.gpu_hiz_downsample_bind_groups[index] != nil {
			wgpu.BindGroupRelease(renderer.gpu_hiz_downsample_bind_groups[index])
			renderer.gpu_hiz_downsample_bind_groups[index] = nil
		}
		if renderer.gpu_hiz_mip_views[index] != nil {
			wgpu.TextureViewRelease(renderer.gpu_hiz_mip_views[index])
			renderer.gpu_hiz_mip_views[index] = nil
		}
	}
	if renderer.gpu_hiz_view != nil {
		wgpu.TextureViewRelease(renderer.gpu_hiz_view)
		renderer.gpu_hiz_view = nil
	}
	if renderer.gpu_hiz_texture != nil {
		wgpu.TextureRelease(renderer.gpu_hiz_texture)
		renderer.gpu_hiz_texture = nil
	}
	renderer.gpu_hiz_width = 0
	renderer.gpu_hiz_height = 0
	renderer.gpu_hiz_mip_count = 0
	renderer.gpu_hiz_valid = false
	renderer.gpu_hiz_occlusion_enabled = false
}

wgpu_release_hiz :: proc(renderer: ^WGPU_Renderer) {
	wgpu_release_hiz_targets(renderer)
	if renderer.gpu_hiz_first_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.gpu_hiz_first_pipeline)
	}
	if renderer.gpu_hiz_downsample_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.gpu_hiz_downsample_pipeline)
	}
	if renderer.gpu_hiz_first_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.gpu_hiz_first_pipeline_layout)
	}
	if renderer.gpu_hiz_downsample_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.gpu_hiz_downsample_pipeline_layout)
	}
	if renderer.gpu_hiz_first_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.gpu_hiz_first_bind_group_layout)
	}
	if renderer.gpu_hiz_downsample_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.gpu_hiz_downsample_bind_group_layout)
	}
	if renderer.gpu_hiz_shader != nil {
		wgpu.ShaderModuleRelease(renderer.gpu_hiz_shader)
	}
	if renderer.gpu_hiz_downsample_shader != nil {
		wgpu.ShaderModuleRelease(renderer.gpu_hiz_downsample_shader)
	}
}

wgpu_ensure_hiz_targets :: proc(renderer: ^WGPU_Renderer, width, height: u32) -> string {
	width := max(width, 1)
	height := max(height, 1)
	if renderer.gpu_hiz_texture != nil &&
	   renderer.gpu_hiz_width == width &&
	   renderer.gpu_hiz_height == height {
		return ""
	}
	wgpu_release_hiz_targets(renderer)
	mip_count := wgpu_hiz_mip_count(width, height)
	renderer.gpu_hiz_texture = wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label = "Scrapbot Hi-Z Pyramid",
			usage = {.TextureBinding, .StorageBinding},
			dimension = ._2D,
			size = {width = width, height = height, depthOrArrayLayers = 1},
			format = .R32Float,
			mipLevelCount = u32(mip_count),
			sampleCount = 1,
		},
	)
	if renderer.gpu_hiz_texture == nil {
		return "failed to create Hi-Z texture"
	}
	renderer.gpu_hiz_view = wgpu.TextureCreateView(renderer.gpu_hiz_texture)
	if renderer.gpu_hiz_view == nil {
		return "failed to create Hi-Z texture view"
	}
	for index in 0 ..< mip_count {
		renderer.gpu_hiz_mip_views[index] = wgpu.TextureCreateView(
			renderer.gpu_hiz_texture,
			&wgpu.TextureViewDescriptor {
				format = .R32Float,
				dimension = ._2D,
				baseMipLevel = u32(index),
				mipLevelCount = 1,
				baseArrayLayer = 0,
				arrayLayerCount = 1,
				aspect = .All,
			},
		)
		if renderer.gpu_hiz_mip_views[index] == nil {
			return "failed to create Hi-Z mip view"
		}
	}
	renderer.gpu_hiz_width = width
	renderer.gpu_hiz_height = height
	renderer.gpu_hiz_mip_count = mip_count
	if cull_err := wgpu_rebuild_cull_bind_group(renderer); cull_err != "" {
		return cull_err
	}
	return ""
}

wgpu_prepare_hiz_bind_groups :: proc(
	renderer: ^WGPU_Renderer,
	depth_view: wgpu.TextureView,
) -> string {
	if renderer.gpu_hiz_first_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_hiz_first_bind_group)
	}
	first_entries := [?]wgpu.BindGroupEntry {
		{binding = 0, textureView = depth_view},
		{binding = 1, textureView = renderer.gpu_hiz_mip_views[0]},
	}
	renderer.gpu_hiz_first_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Hi-Z Copy Bind Group",
			layout = renderer.gpu_hiz_first_bind_group_layout,
			entryCount = uint(len(first_entries)),
			entries = raw_data(first_entries[:]),
		},
	)
	if renderer.gpu_hiz_first_bind_group == nil {
		return "failed to create Hi-Z copy bind group"
	}
	for index in 1 ..< renderer.gpu_hiz_mip_count {
		if renderer.gpu_hiz_downsample_bind_groups[index] != nil {
			continue
		}
		entries := [?]wgpu.BindGroupEntry {
			{binding = 0, textureView = renderer.gpu_hiz_mip_views[index - 1]},
			{binding = 1, textureView = renderer.gpu_hiz_mip_views[index]},
		}
		renderer.gpu_hiz_downsample_bind_groups[index] = wgpu.DeviceCreateBindGroup(
			renderer.device,
			&wgpu.BindGroupDescriptor {
				label = "Scrapbot Hi-Z Downsample Bind Group",
				layout = renderer.gpu_hiz_downsample_bind_group_layout,
				entryCount = uint(len(entries)),
				entries = raw_data(entries[:]),
			},
		)
		if renderer.gpu_hiz_downsample_bind_groups[index] == nil {
			return "failed to create Hi-Z downsample bind group"
		}
	}
	return ""
}

wgpu_encode_hiz_pyramid :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	depth_view: wgpu.TextureView,
) -> string {
	if err := wgpu_prepare_hiz_bind_groups(renderer, depth_view); err != "" {
		return err
	}
	timestamps, timestamps_enabled := wgpu_gpu_hiz_pass_timestamps(renderer, 0)
	timestamps_ptr: ^wgpu.PassTimestampWrites
	if timestamps_enabled {
		timestamps_ptr = &timestamps
	}
	copy_pass := wgpu.CommandEncoderBeginComputePass(
		encoder,
		&wgpu.ComputePassDescriptor {
			label = "Scrapbot Hi-Z Pyramid Pass",
			timestampWrites = timestamps_ptr,
		},
	)
	if copy_pass == nil {
		return "failed to begin Hi-Z compute pass"
	}
	wgpu.ComputePassEncoderSetPipeline(copy_pass, renderer.gpu_hiz_first_pipeline)
	wgpu.ComputePassEncoderSetBindGroup(copy_pass, 0, renderer.gpu_hiz_first_bind_group)
	wgpu.ComputePassEncoderDispatchWorkgroups(
		copy_pass,
		(renderer.gpu_hiz_width + 7) / 8,
		(renderer.gpu_hiz_height + 7) / 8,
		1,
	)
	wgpu.ComputePassEncoderEnd(copy_pass)
	wgpu.ComputePassEncoderRelease(copy_pass)
	width := renderer.gpu_hiz_width
	height := renderer.gpu_hiz_height
	for index in 1 ..< renderer.gpu_hiz_mip_count {
		width = max(width / 2, 1)
		height = max(height / 2, 1)
		mip_timestamps, mip_timestamps_enabled := wgpu_gpu_hiz_pass_timestamps(renderer, index)
		mip_timestamps_ptr: ^wgpu.PassTimestampWrites
		if mip_timestamps_enabled {
			mip_timestamps_ptr = &mip_timestamps
		}
		pass := wgpu.CommandEncoderBeginComputePass(
			encoder,
			&wgpu.ComputePassDescriptor {
				label = "Scrapbot Hi-Z Downsample Pass",
				timestampWrites = mip_timestamps_ptr,
			},
		)
		if pass == nil {
			return "failed to begin Hi-Z downsample pass"
		}
		wgpu.ComputePassEncoderSetPipeline(pass, renderer.gpu_hiz_downsample_pipeline)
		wgpu.ComputePassEncoderSetBindGroup(
			pass,
			0,
			renderer.gpu_hiz_downsample_bind_groups[index],
		)
		wgpu.ComputePassEncoderDispatchWorkgroups(pass, (width + 7) / 8, (height + 7) / 8, 1)
		wgpu.ComputePassEncoderEnd(pass)
		wgpu.ComputePassEncoderRelease(pass)
	}
	renderer.gpu_previous_view_projection = renderer.gpu_current_view_projection
	renderer.gpu_previous_depth_view_projection = renderer.temporal_current_view_projection
	renderer.gpu_hiz_valid = true
	return ""
}
