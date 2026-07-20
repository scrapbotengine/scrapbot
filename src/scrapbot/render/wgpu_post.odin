package render

import "vendor:wgpu"

wgpu_create_post_process_pipelines :: proc(renderer: ^WGPU_Renderer) -> string {
	post_chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_POST_PROCESS_SHADER,
	}
	renderer.post_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor{nextInChain = &post_chain, label = "Scrapbot Bloom Shader"},
	)
	if renderer.post_shader == nil {
		return "failed to create bloom shader"
	}

	bloom_layout_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{binding = 1, visibility = {.Compute}, sampler = {type = .Filtering}},
		{
			binding = 2,
			visibility = {.Compute},
			storageTexture = {access = .WriteOnly, format = .RGBA16Float, viewDimension = ._2D},
		},
	}
	renderer.bloom_compute_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Bloom Compute Bind Group Layout",
			entryCount = uint(len(bloom_layout_entries)),
			entries = raw_data(bloom_layout_entries[:]),
		},
	)
	if renderer.bloom_compute_bind_group_layout == nil {
		return "failed to create bloom compute bind group layout"
	}
	renderer.bloom_compute_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Bloom Compute Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.bloom_compute_bind_group_layout,
		},
	)
	if renderer.bloom_compute_pipeline_layout == nil {
		return "failed to create bloom compute pipeline layout"
	}

	renderer.bloom_bright_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Bloom Extract Compute Pipeline",
			layout = renderer.bloom_compute_pipeline_layout,
			compute = {module = renderer.post_shader, entryPoint = "bright_cs"},
		},
	)
	renderer.bloom_downsample_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Bloom Downsample Compute Pipeline",
			layout = renderer.bloom_compute_pipeline_layout,
			compute = {module = renderer.post_shader, entryPoint = "downsample_cs"},
		},
	)
	if renderer.bloom_bright_pipeline == nil || renderer.bloom_downsample_pipeline == nil {
		return "failed to create bloom compute pipelines"
	}

	composite_chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_COMPOSITE_SHADER,
	}
	renderer.composite_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &composite_chain,
			label = "Scrapbot HDR Composite Shader",
		},
	)
	if renderer.composite_shader == nil {
		return "failed to create HDR composite shader"
	}
	composite_entries: [2 + WGPU_BLOOM_LEVELS]wgpu.BindGroupLayoutEntry
	composite_entries[0] = {
		binding = 0,
		visibility = {.Fragment},
		texture = {sampleType = .Float, viewDimension = ._2D},
	}
	composite_entries[1] = {
		binding = 1,
		visibility = {.Fragment},
		sampler = {type = .Filtering},
	}
	for index in 0 ..< WGPU_BLOOM_LEVELS {
		composite_entries[index + 2] = {
			binding = u32(index + 2),
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		}
	}
	renderer.composite_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot HDR Composite Bind Group Layout",
			entryCount = uint(len(composite_entries)),
			entries = raw_data(composite_entries[:]),
		},
	)
	if renderer.composite_bind_group_layout == nil {
		return "failed to create HDR composite bind group layout"
	}
	renderer.composite_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot HDR Composite Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.composite_bind_group_layout,
		},
	)
	if renderer.composite_pipeline_layout == nil {
		return "failed to create HDR composite pipeline layout"
	}
	renderer.composite_pipeline = wgpu_create_fullscreen_pipeline(
		renderer,
		renderer.composite_shader,
		renderer.composite_pipeline_layout,
		"composite_fs",
		renderer.format,
		"Scrapbot HDR Composite Pipeline",
	)
	if renderer.composite_pipeline == nil {
		return "failed to create HDR composite pipeline"
	}

	renderer.post_sampler = wgpu.DeviceCreateSampler(
		renderer.device,
		&wgpu.SamplerDescriptor {
			label = "Scrapbot Post Process Sampler",
			addressModeU = .ClampToEdge,
			addressModeV = .ClampToEdge,
			addressModeW = .ClampToEdge,
			magFilter = .Linear,
			minFilter = .Linear,
			mipmapFilter = .Linear,
			maxAnisotropy = 1,
		},
	)
	if renderer.post_sampler == nil {
		return "failed to create post-process sampler"
	}
	return ""
}

wgpu_create_fullscreen_pipeline :: proc(
	renderer: ^WGPU_Renderer,
	shader: wgpu.ShaderModule,
	layout: wgpu.PipelineLayout,
	fragment_entry: string,
	format: wgpu.TextureFormat,
	label: string,
) -> wgpu.RenderPipeline {
	target := wgpu.ColorTargetState {
		format = format,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment := wgpu.FragmentState {
		module = shader,
		entryPoint = fragment_entry,
		targetCount = 1,
		targets = &target,
	}
	return wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = label,
			layout = layout,
			vertex = {module = shader, entryPoint = "fullscreen_vs"},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = .None},
			multisample = {count = 1, mask = 0xFFFF_FFFF},
			fragment = &fragment,
		},
	)
}

wgpu_release_post_targets :: proc(renderer: ^WGPU_Renderer) {
	if renderer.composite_bind_group != nil {
		wgpu.BindGroupRelease(renderer.composite_bind_group)
		renderer.composite_bind_group = nil
	}
	for index in 0 ..< WGPU_BLOOM_LEVELS {
		if renderer.bloom_compute_bind_groups[index] != nil {
			wgpu.BindGroupRelease(renderer.bloom_compute_bind_groups[index])
			renderer.bloom_compute_bind_groups[index] = nil
		}
		if renderer.bloom_views[index] != nil {
			wgpu.TextureViewRelease(renderer.bloom_views[index])
			renderer.bloom_views[index] = nil
		}
		if renderer.bloom_textures[index] != nil {
			wgpu.TextureRelease(renderer.bloom_textures[index])
			renderer.bloom_textures[index] = nil
		}
	}
	if renderer.hdr_view != nil {
		wgpu.TextureViewRelease(renderer.hdr_view)
		renderer.hdr_view = nil
	}
	if renderer.hdr_texture != nil {
		wgpu.TextureRelease(renderer.hdr_texture)
		renderer.hdr_texture = nil
	}
	renderer.post_width = 0
	renderer.post_height = 0
}

wgpu_release_post_process :: proc(renderer: ^WGPU_Renderer) {
	wgpu_release_post_targets(renderer)
	if renderer.post_sampler != nil {
		wgpu.SamplerRelease(renderer.post_sampler)
	}
	if renderer.composite_pipeline != nil {
		wgpu.RenderPipelineRelease(renderer.composite_pipeline)
	}
	if renderer.composite_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.composite_pipeline_layout)
	}
	if renderer.composite_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.composite_bind_group_layout)
	}
	if renderer.composite_shader != nil {
		wgpu.ShaderModuleRelease(renderer.composite_shader)
	}
	if renderer.bloom_bright_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.bloom_bright_pipeline)
	}
	if renderer.bloom_downsample_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.bloom_downsample_pipeline)
	}
	if renderer.bloom_compute_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.bloom_compute_pipeline_layout)
	}
	if renderer.bloom_compute_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.bloom_compute_bind_group_layout)
	}
	if renderer.post_shader != nil {
		wgpu.ShaderModuleRelease(renderer.post_shader)
	}
}

wgpu_ensure_post_targets :: proc(renderer: ^WGPU_Renderer, width, height: u32) -> string {
	if renderer.post_width == width && renderer.post_height == height && renderer.hdr_view != nil {
		return ""
	}
	wgpu_release_post_targets(renderer)
	renderer.hdr_texture = wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label = "Scrapbot HDR Scene Texture",
			usage = {.RenderAttachment, .TextureBinding},
			dimension = ._2D,
			size = {width = width, height = height, depthOrArrayLayers = 1},
			format = .RGBA16Float,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	if renderer.hdr_texture == nil {
		return "failed to create HDR scene texture"
	}
	renderer.hdr_view = wgpu.TextureCreateView(renderer.hdr_texture)
	if renderer.hdr_view == nil {
		return "failed to create HDR scene texture view"
	}

	for index in 0 ..< WGPU_BLOOM_LEVELS {
		level_width := max(u32(1), width >> u32(index + 1))
		level_height := max(u32(1), height >> u32(index + 1))
		texture := wgpu.DeviceCreateTexture(
			renderer.device,
			&wgpu.TextureDescriptor {
				label = "Scrapbot Bloom Texture",
				usage = {.TextureBinding, .StorageBinding},
				dimension = ._2D,
				size = {width = level_width, height = level_height, depthOrArrayLayers = 1},
				format = .RGBA16Float,
				mipLevelCount = 1,
				sampleCount = 1,
			},
		)
		if texture == nil {
			return "failed to create bloom texture"
		}
		view := wgpu.TextureCreateView(texture)
		if view == nil {
			wgpu.TextureRelease(texture)
			return "failed to create bloom texture view"
		}
		renderer.bloom_textures[index] = texture
		renderer.bloom_views[index] = view
	}

	for index in 0 ..< WGPU_BLOOM_LEVELS {
		source := renderer.hdr_view if index == 0 else renderer.bloom_views[index - 1]
		entries := [?]wgpu.BindGroupEntry {
			{binding = 0, textureView = source},
			{binding = 1, sampler = renderer.post_sampler},
			{binding = 2, textureView = renderer.bloom_views[index]},
		}
		renderer.bloom_compute_bind_groups[index] = wgpu.DeviceCreateBindGroup(
			renderer.device,
			&wgpu.BindGroupDescriptor {
				label = "Scrapbot Bloom Compute Bind Group",
				layout = renderer.bloom_compute_bind_group_layout,
				entryCount = uint(len(entries)),
				entries = raw_data(entries[:]),
			},
		)
		if renderer.bloom_compute_bind_groups[index] == nil {
			return "failed to create bloom bind groups"
		}
	}
	composite_entries: [2 + WGPU_BLOOM_LEVELS]wgpu.BindGroupEntry
	composite_entries[0] = {
		binding = 0,
		textureView = renderer.hdr_view,
	}
	composite_entries[1] = {
		binding = 1,
		sampler = renderer.post_sampler,
	}
	for index in 0 ..< WGPU_BLOOM_LEVELS {
		composite_entries[index + 2] = {
			binding = u32(index + 2),
			textureView = renderer.bloom_views[index],
		}
	}
	renderer.composite_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot HDR Composite Bind Group",
			layout = renderer.composite_bind_group_layout,
			entryCount = uint(len(composite_entries)),
			entries = raw_data(composite_entries[:]),
		},
	)
	if renderer.composite_bind_group == nil {
		return "failed to create HDR composite bind group"
	}
	renderer.post_width = width
	renderer.post_height = height
	return ""
}

wgpu_encode_fullscreen_pass :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	view: wgpu.TextureView,
	pipeline: wgpu.RenderPipeline,
	bind_group: wgpu.BindGroup,
	label: string,
	timestamp_phase: WGPU_GPU_Timestamp_Phase,
) -> string {
	attachment := wgpu.RenderPassColorAttachment {
		view = view,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp = .Clear,
		storeOp = .Store,
		clearValue = {},
	}
	timestamps, timestamps_enabled := wgpu_gpu_pass_timestamps(renderer, timestamp_phase)
	timestamps_ptr: ^wgpu.PassTimestampWrites
	if timestamps_enabled {
		timestamps_ptr = &timestamps
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = label,
			colorAttachmentCount = 1,
			colorAttachments = &attachment,
			timestampWrites = timestamps_ptr,
		},
	)
	if pass == nil {
		return "failed to begin post-process pass"
	}
	wgpu.RenderPassEncoderSetPipeline(pass, pipeline)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, bind_group)
	wgpu.RenderPassEncoderDraw(pass, 3, 1, 0, 0)
	wgpu.RenderPassEncoderEnd(pass)
	wgpu.RenderPassEncoderRelease(pass)
	return ""
}

wgpu_encode_bloom_and_composite :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	output_view: wgpu.TextureView,
	width, height: u32,
) -> string {
	if err := wgpu_ensure_post_targets(renderer, width, height); err != "" {
		return err
	}
	bloom_timestamps, bloom_timestamps_enabled := wgpu_gpu_pass_timestamps(renderer, .Bloom)
	bloom_timestamps_ptr: ^wgpu.PassTimestampWrites
	if bloom_timestamps_enabled {
		bloom_timestamps_ptr = &bloom_timestamps
	}
	pass := wgpu.CommandEncoderBeginComputePass(
		encoder,
		&wgpu.ComputePassDescriptor {
			label = "Scrapbot Bloom Compute Pass",
			timestampWrites = bloom_timestamps_ptr,
		},
	)
	if pass == nil {
		return "failed to begin bloom compute pass"
	}
	for index in 0 ..< WGPU_BLOOM_LEVELS {
		pipeline := renderer.bloom_downsample_pipeline
		if index == 0 {
			pipeline = renderer.bloom_bright_pipeline
		}
		level_width := max(u32(1), width >> u32(index + 1))
		level_height := max(u32(1), height >> u32(index + 1))
		wgpu.ComputePassEncoderSetPipeline(pass, pipeline)
		wgpu.ComputePassEncoderSetBindGroup(pass, 0, renderer.bloom_compute_bind_groups[index])
		wgpu.ComputePassEncoderDispatchWorkgroups(
			pass,
			(level_width + 7) / 8,
			(level_height + 7) / 8,
			1,
		)
	}
	wgpu.ComputePassEncoderEnd(pass)
	wgpu.ComputePassEncoderRelease(pass)
	return wgpu_encode_fullscreen_pass(
		renderer,
		encoder,
		output_view,
		renderer.composite_pipeline,
		renderer.composite_bind_group,
		"Scrapbot HDR Composite Pass",
		.Composite,
	)
}
