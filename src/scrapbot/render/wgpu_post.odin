package render

import shared "../shared"
import "core:math"
import "vendor:wgpu"

WGPU_Volumetric_Fog_Settings :: struct {
	color: shared.Vec3,
	density: f32,
	height: f32,
	height_falloff: f32,
	max_distance: f32,
	anisotropy: f32,
	ambient_intensity: f32,
	light_intensity: f32,
	point_light_intensity: f32,
}

wgpu_fog_number :: proc(component: ^shared.Custom_Component, name: string, fallback: f32) -> f32 {
	if component == nil {
		return fallback
	}
	for field in component.number_fields {
		if field.name == name {
			if math.is_nan(field.value) || math.is_inf(field.value) {
				return fallback
			}
			return field.value
		}
	}
	return fallback
}

wgpu_fog_vec3 :: proc(
	component: ^shared.Custom_Component,
	name: string,
	fallback: shared.Vec3,
) -> shared.Vec3 {
	if component == nil {
		return fallback
	}
	for field in component.vec3_fields {
		if field.name == name {
			value := field.value
			if math.is_nan(value.x) ||
			   math.is_inf(value.x) ||
			   math.is_nan(value.y) ||
			   math.is_inf(value.y) ||
			   math.is_nan(value.z) ||
			   math.is_inf(value.z) {
				return fallback
			}
			return value
		}
	}
	return fallback
}

wgpu_volumetric_fog_settings :: proc(world: ^shared.World) -> WGPU_Volumetric_Fog_Settings {
	settings := WGPU_Volumetric_Fog_Settings {
		color = {0.62, 0.72, 0.82},
		height_falloff = 0.2,
		max_distance = 100,
		anisotropy = 0.35,
		ambient_intensity = 0.15,
		light_intensity = 1,
	}
	if world == nil {
		return settings
	}
	component: ^shared.Custom_Component
	best_scene_order := 0
	for &storage in world.custom_components {
		if storage.name != "scrapbot.volumetric_fog" {
			continue
		}
		for component_index in storage.active_component_indices {
			if component_index < 0 || component_index >= len(storage.components) {
				continue
			}
			candidate := &storage.components[component_index]
			entity_index := candidate.entity_index
			if entity_index < 0 ||
			   entity_index >= len(world.entities) ||
			   !world.entities[entity_index].alive {
				continue
			}
			scene_order := world.entities[entity_index].scene_order
			if component == nil || scene_order < best_scene_order {
				component = candidate
				best_scene_order = scene_order
			}
		}
		break
	}
	if component == nil {
		return settings
	}
	settings.color = wgpu_fog_vec3(component, "color", settings.color)
	settings.color.x = max(settings.color.x, 0)
	settings.color.y = max(settings.color.y, 0)
	settings.color.z = max(settings.color.z, 0)
	settings.density = clamp(wgpu_fog_number(component, "density", 0), f32(0), f32(1))
	settings.height = wgpu_fog_number(component, "height", 0)
	settings.height_falloff = clamp(
		wgpu_fog_number(component, "height_falloff", settings.height_falloff),
		f32(0),
		f32(10),
	)
	settings.max_distance = clamp(
		wgpu_fog_number(component, "max_distance", settings.max_distance),
		f32(0.1),
		f32(10000),
	)
	settings.anisotropy = clamp(
		wgpu_fog_number(component, "anisotropy", settings.anisotropy),
		f32(-0.9),
		f32(0.9),
	)
	settings.ambient_intensity = clamp(
		wgpu_fog_number(component, "ambient_intensity", settings.ambient_intensity),
		f32(0),
		f32(10),
	)
	settings.light_intensity = clamp(
		wgpu_fog_number(component, "light_intensity", settings.light_intensity),
		f32(0),
		f32(10),
	)
	settings.point_light_intensity = clamp(
		wgpu_fog_number(component, "point_light_intensity", settings.point_light_intensity),
		f32(0),
		f32(10),
	)
	return settings
}

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

	temporal_aa_chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_TEMPORAL_AA_SHADER,
	}
	renderer.temporal_aa_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &temporal_aa_chain,
			label = "Scrapbot Temporal AA Shader",
		},
	)
	if renderer.temporal_aa_shader == nil {
		return "failed to create temporal AA shader"
	}
	temporal_aa_layout_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{binding = 1, visibility = {.Compute}, sampler = {type = .Filtering}},
		{
			binding = 2,
			visibility = {.Compute},
			texture = {sampleType = .Depth, viewDimension = ._2D},
		},
		{
			binding = 3,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 4,
			visibility = {.Compute},
			texture = {sampleType = .UnfilterableFloat, viewDimension = ._2D},
		},
		{
			binding = 5,
			visibility = {.Compute},
			storageTexture = {access = .WriteOnly, format = .RGBA16Float, viewDimension = ._2D},
		},
		{
			binding = 6,
			visibility = {.Compute},
			storageTexture = {access = .WriteOnly, format = .R32Float, viewDimension = ._2D},
		},
		{
			binding = 7,
			visibility = {.Compute},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_Temporal_AA_Uniform))},
		},
		{
			binding = 8,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 9,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 10,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 11,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 12,
			visibility = {.Compute},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_GPU_Render_Uniform))},
		},
		{
			binding = 13,
			visibility = {.Compute},
			texture = {sampleType = .Depth, viewDimension = ._2DArray},
		},
		{binding = 14, visibility = {.Compute}, sampler = {type = .Comparison}},
	}
	renderer.temporal_aa_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Temporal AA Bind Group Layout",
			entryCount = uint(len(temporal_aa_layout_entries)),
			entries = raw_data(temporal_aa_layout_entries[:]),
		},
	)
	if renderer.temporal_aa_bind_group_layout == nil {
		return "failed to create temporal AA bind group layout"
	}
	temporal_aa_bind_group_layouts := [?]wgpu.BindGroupLayout {
		renderer.temporal_aa_bind_group_layout,
		renderer.gpu_cluster_bind_group_layout,
	}
	renderer.temporal_aa_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Temporal AA Pipeline Layout",
			bindGroupLayoutCount = uint(len(temporal_aa_bind_group_layouts)),
			bindGroupLayouts = raw_data(temporal_aa_bind_group_layouts[:]),
		},
	)
	if renderer.temporal_aa_pipeline_layout == nil {
		return "failed to create temporal AA pipeline layout"
	}
	renderer.temporal_aa_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Temporal AA Pipeline",
			layout = renderer.temporal_aa_pipeline_layout,
			compute = {module = renderer.temporal_aa_shader, entryPoint = "temporal_aa_cs"},
		},
	)
	if renderer.temporal_aa_pipeline == nil {
		return "failed to create temporal AA compute pipeline"
	}
	renderer.temporal_aa_uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Temporal AA Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Temporal_AA_Uniform)),
		},
	)
	if renderer.temporal_aa_uniform_buffer == nil {
		return "failed to create temporal AA uniform buffer"
	}

	ambient_occlusion_chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_AMBIENT_OCCLUSION_SHADER,
	}
	renderer.ambient_occlusion_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &ambient_occlusion_chain,
			label = "Scrapbot Ambient Occlusion Shader",
		},
	)
	if renderer.ambient_occlusion_shader == nil {
		return "failed to create ambient occlusion shader"
	}
	ambient_occlusion_layout_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			texture = {sampleType = .Depth, viewDimension = ._2D},
		},
		{
			binding = 1,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 2,
			visibility = {.Compute},
			storageTexture = {access = .WriteOnly, format = .RGBA8Unorm, viewDimension = ._2D},
		},
		{
			binding = 3,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 4,
			visibility = {.Compute},
			buffer = {
				type = .Uniform,
				minBindingSize = u64(size_of(WGPU_Ambient_Occlusion_Uniform)),
			},
		},
	}
	renderer.ambient_occlusion_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Ambient Occlusion Bind Group Layout",
			entryCount = uint(len(ambient_occlusion_layout_entries)),
			entries = raw_data(ambient_occlusion_layout_entries[:]),
		},
	)
	if renderer.ambient_occlusion_bind_group_layout == nil {
		return "failed to create ambient occlusion bind group layout"
	}
	renderer.ambient_occlusion_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Ambient Occlusion Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.ambient_occlusion_bind_group_layout,
		},
	)
	if renderer.ambient_occlusion_pipeline_layout == nil {
		return "failed to create ambient occlusion pipeline layout"
	}
	renderer.ambient_occlusion_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Ambient Occlusion Pipeline",
			layout = renderer.ambient_occlusion_pipeline_layout,
			compute = {
				module = renderer.ambient_occlusion_shader,
				entryPoint = "ambient_occlusion_cs",
			},
		},
	)
	renderer.ambient_occlusion_blur_horizontal_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Ambient Occlusion Horizontal Blur Pipeline",
			layout = renderer.ambient_occlusion_pipeline_layout,
			compute = {
				module = renderer.ambient_occlusion_shader,
				entryPoint = "blur_horizontal_cs",
			},
		},
	)
	renderer.ambient_occlusion_blur_vertical_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Ambient Occlusion Vertical Blur Pipeline",
			layout = renderer.ambient_occlusion_pipeline_layout,
			compute = {
				module = renderer.ambient_occlusion_shader,
				entryPoint = "blur_vertical_cs",
			},
		},
	)
	if renderer.ambient_occlusion_pipeline == nil ||
	   renderer.ambient_occlusion_blur_horizontal_pipeline == nil ||
	   renderer.ambient_occlusion_blur_vertical_pipeline == nil {
		return "failed to create ambient occlusion compute pipelines"
	}
	renderer.ambient_occlusion_uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Ambient Occlusion Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Ambient_Occlusion_Uniform)),
		},
	)
	if renderer.ambient_occlusion_uniform_buffer == nil {
		return "failed to create ambient occlusion uniform buffer"
	}

	reflections_chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_SCREEN_SPACE_REFLECTIONS_SHADER,
	}
	renderer.screen_space_reflections_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &reflections_chain,
			label = "Scrapbot Screen-Space Reflections Shader",
		},
	)
	if renderer.screen_space_reflections_shader == nil {
		return "failed to create screen-space reflections shader"
	}
	reflections_layout_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{binding = 1, visibility = {.Compute}, sampler = {type = .Filtering}},
		{
			binding = 2,
			visibility = {.Compute},
			texture = {sampleType = .Depth, viewDimension = ._2D},
		},
		{
			binding = 3,
			visibility = {.Compute},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 4,
			visibility = {.Compute},
			storageTexture = {access = .WriteOnly, format = .RGBA16Float, viewDimension = ._2D},
		},
		{
			binding = 5,
			visibility = {.Compute},
			buffer = {
				type = .Uniform,
				minBindingSize = u64(size_of(WGPU_Screen_Space_Reflections_Uniform)),
			},
		},
	}
	renderer.screen_space_reflections_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Screen-Space Reflections Bind Group Layout",
			entryCount = uint(len(reflections_layout_entries)),
			entries = raw_data(reflections_layout_entries[:]),
		},
	)
	if renderer.screen_space_reflections_bind_group_layout == nil {
		return "failed to create screen-space reflections bind group layout"
	}
	renderer.screen_space_reflections_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Screen-Space Reflections Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.screen_space_reflections_bind_group_layout,
		},
	)
	if renderer.screen_space_reflections_pipeline_layout == nil {
		return "failed to create screen-space reflections pipeline layout"
	}
	renderer.screen_space_reflections_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Screen-Space Reflections Pipeline",
			layout = renderer.screen_space_reflections_pipeline_layout,
			compute = {
				module = renderer.screen_space_reflections_shader,
				entryPoint = "screen_space_reflections_cs",
			},
		},
	)
	if renderer.screen_space_reflections_pipeline == nil {
		return "failed to create screen-space reflections pipeline"
	}
	renderer.screen_space_reflections_uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Screen-Space Reflections Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Screen_Space_Reflections_Uniform)),
		},
	)
	if renderer.screen_space_reflections_uniform_buffer == nil {
		return "failed to create screen-space reflections uniform buffer"
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

wgpu_create_post_texture :: proc(
	renderer: ^WGPU_Renderer,
	label: string,
	width, height: u32,
	format: wgpu.TextureFormat,
	usage: wgpu.TextureUsageFlags,
) -> (
	texture: wgpu.Texture,
	view: wgpu.TextureView,
	err: string,
) {
	texture = wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label = label,
			usage = usage,
			dimension = ._2D,
			size = {width = width, height = height, depthOrArrayLayers = 1},
			format = format,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	if texture == nil {
		err = "failed to create retained post-process texture"
		return
	}
	view = wgpu.TextureCreateView(texture)
	if view == nil {
		wgpu.TextureRelease(texture)
		texture = nil
		err = "failed to create retained post-process texture view"
	}
	return
}

wgpu_release_post_targets :: proc(renderer: ^WGPU_Renderer) {
	if renderer.composite_bind_group != nil {
		wgpu.BindGroupRelease(renderer.composite_bind_group)
		renderer.composite_bind_group = nil
	}
	if renderer.temporal_aa_bind_group != nil {
		wgpu.BindGroupRelease(renderer.temporal_aa_bind_group)
		renderer.temporal_aa_bind_group = nil
	}
	if renderer.temporal_resolved_view != nil {
		wgpu.TextureViewRelease(renderer.temporal_resolved_view)
		renderer.temporal_resolved_view = nil
	}
	if renderer.temporal_resolved_texture != nil {
		wgpu.TextureRelease(renderer.temporal_resolved_texture)
		renderer.temporal_resolved_texture = nil
	}
	if renderer.temporal_history_view != nil {
		wgpu.TextureViewRelease(renderer.temporal_history_view)
		renderer.temporal_history_view = nil
	}
	if renderer.temporal_history_texture != nil {
		wgpu.TextureRelease(renderer.temporal_history_texture)
		renderer.temporal_history_texture = nil
	}
	if renderer.temporal_resolved_depth_view != nil {
		wgpu.TextureViewRelease(renderer.temporal_resolved_depth_view)
		renderer.temporal_resolved_depth_view = nil
	}
	if renderer.temporal_resolved_depth_texture != nil {
		wgpu.TextureRelease(renderer.temporal_resolved_depth_texture)
		renderer.temporal_resolved_depth_texture = nil
	}
	if renderer.temporal_history_depth_view != nil {
		wgpu.TextureViewRelease(renderer.temporal_history_depth_view)
		renderer.temporal_history_depth_view = nil
	}
	if renderer.temporal_history_depth_texture != nil {
		wgpu.TextureRelease(renderer.temporal_history_depth_texture)
		renderer.temporal_history_depth_texture = nil
	}
	for index in 0 ..< len(renderer.ambient_occlusion_bind_groups) {
		if renderer.ambient_occlusion_bind_groups[index] != nil {
			wgpu.BindGroupRelease(renderer.ambient_occlusion_bind_groups[index])
			renderer.ambient_occlusion_bind_groups[index] = nil
		}
		if renderer.ambient_occlusion_views[index] != nil {
			wgpu.TextureViewRelease(renderer.ambient_occlusion_views[index])
			renderer.ambient_occlusion_views[index] = nil
		}
		if renderer.ambient_occlusion_textures[index] != nil {
			wgpu.TextureRelease(renderer.ambient_occlusion_textures[index])
			renderer.ambient_occlusion_textures[index] = nil
		}
	}
	if renderer.screen_space_reflections_bind_group != nil {
		wgpu.BindGroupRelease(renderer.screen_space_reflections_bind_group)
		renderer.screen_space_reflections_bind_group = nil
	}
	if renderer.screen_space_reflections_view != nil {
		wgpu.TextureViewRelease(renderer.screen_space_reflections_view)
		renderer.screen_space_reflections_view = nil
	}
	if renderer.screen_space_reflections_texture != nil {
		wgpu.TextureRelease(renderer.screen_space_reflections_texture)
		renderer.screen_space_reflections_texture = nil
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
	if renderer.surface_view != nil {
		wgpu.TextureViewRelease(renderer.surface_view)
		renderer.surface_view = nil
	}
	if renderer.surface_texture != nil {
		wgpu.TextureRelease(renderer.surface_texture)
		renderer.surface_texture = nil
	}
	if renderer.indirect_diffuse_view != nil {
		wgpu.TextureViewRelease(renderer.indirect_diffuse_view)
		renderer.indirect_diffuse_view = nil
	}
	if renderer.indirect_diffuse_texture != nil {
		wgpu.TextureRelease(renderer.indirect_diffuse_texture)
		renderer.indirect_diffuse_texture = nil
	}
	renderer.post_width = 0
	renderer.post_height = 0
	renderer.post_depth_view = nil
	renderer.temporal_history_valid = false
}

wgpu_release_post_process :: proc(renderer: ^WGPU_Renderer) {
	wgpu_release_post_targets(renderer)
	if renderer.post_sampler != nil {
		wgpu.SamplerRelease(renderer.post_sampler)
	}
	if renderer.temporal_aa_uniform_buffer != nil {
		wgpu.BufferRelease(renderer.temporal_aa_uniform_buffer)
	}
	if renderer.temporal_aa_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.temporal_aa_pipeline)
	}
	if renderer.temporal_aa_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.temporal_aa_pipeline_layout)
	}
	if renderer.temporal_aa_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.temporal_aa_bind_group_layout)
	}
	if renderer.temporal_aa_shader != nil {
		wgpu.ShaderModuleRelease(renderer.temporal_aa_shader)
	}
	if renderer.ambient_occlusion_uniform_buffer != nil {
		wgpu.BufferRelease(renderer.ambient_occlusion_uniform_buffer)
	}
	if renderer.ambient_occlusion_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.ambient_occlusion_pipeline)
	}
	if renderer.ambient_occlusion_blur_horizontal_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.ambient_occlusion_blur_horizontal_pipeline)
	}
	if renderer.ambient_occlusion_blur_vertical_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.ambient_occlusion_blur_vertical_pipeline)
	}
	if renderer.ambient_occlusion_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.ambient_occlusion_pipeline_layout)
	}
	if renderer.ambient_occlusion_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.ambient_occlusion_bind_group_layout)
	}
	if renderer.ambient_occlusion_shader != nil {
		wgpu.ShaderModuleRelease(renderer.ambient_occlusion_shader)
	}
	if renderer.screen_space_reflections_uniform_buffer != nil {
		wgpu.BufferRelease(renderer.screen_space_reflections_uniform_buffer)
	}
	if renderer.screen_space_reflections_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.screen_space_reflections_pipeline)
	}
	if renderer.screen_space_reflections_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.screen_space_reflections_pipeline_layout)
	}
	if renderer.screen_space_reflections_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.screen_space_reflections_bind_group_layout)
	}
	if renderer.screen_space_reflections_shader != nil {
		wgpu.ShaderModuleRelease(renderer.screen_space_reflections_shader)
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

wgpu_ensure_post_targets :: proc(
	renderer: ^WGPU_Renderer,
	width, height: u32,
	depth_view: wgpu.TextureView,
) -> string {
	if renderer.post_width == width &&
	   renderer.post_height == height &&
	   renderer.post_depth_view == depth_view &&
	   renderer.hdr_view != nil {
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

	err: string
	renderer.surface_texture, renderer.surface_view, err = wgpu_create_post_texture(
		renderer,
		"Scrapbot Surface Data",
		width,
		height,
		.RGBA16Float,
		{.RenderAttachment, .TextureBinding},
	)
	if err != "" {
		return err
	}
	renderer.indirect_diffuse_texture, renderer.indirect_diffuse_view, err =
		wgpu_create_post_texture(
			renderer,
			"Scrapbot Indirect Diffuse",
			width,
			height,
			.RGBA16Float,
			{.RenderAttachment, .TextureBinding},
		)
	if err != "" {
		return err
	}
	renderer.screen_space_reflections_texture, renderer.screen_space_reflections_view, err =
		wgpu_create_post_texture(
			renderer,
			"Scrapbot Screen-Space Reflections",
			width,
			height,
			.RGBA16Float,
			{.TextureBinding, .StorageBinding},
		)
	if err != "" {
		return err
	}
	reflections_entries := [?]wgpu.BindGroupEntry {
		{binding = 0, textureView = renderer.hdr_view},
		{binding = 1, sampler = renderer.post_sampler},
		{binding = 2, textureView = depth_view},
		{binding = 3, textureView = renderer.surface_view},
		{binding = 4, textureView = renderer.screen_space_reflections_view},
		{
			binding = 5,
			buffer = renderer.screen_space_reflections_uniform_buffer,
			offset = 0,
			size = u64(size_of(WGPU_Screen_Space_Reflections_Uniform)),
		},
	}
	renderer.screen_space_reflections_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Screen-Space Reflections Bind Group",
			layout = renderer.screen_space_reflections_bind_group_layout,
			entryCount = uint(len(reflections_entries)),
			entries = raw_data(reflections_entries[:]),
		},
	)
	if renderer.screen_space_reflections_bind_group == nil {
		return "failed to create screen-space reflections bind group"
	}
	renderer.temporal_resolved_texture, renderer.temporal_resolved_view, err =
		wgpu_create_post_texture(
			renderer,
			"Scrapbot Temporal Resolved Color",
			width,
			height,
			.RGBA16Float,
			{.TextureBinding, .StorageBinding, .CopySrc},
		)
	if err != "" {
		return err
	}
	renderer.temporal_history_texture, renderer.temporal_history_view, err =
		wgpu_create_post_texture(
			renderer,
			"Scrapbot Temporal History Color",
			width,
			height,
			.RGBA16Float,
			{.TextureBinding, .CopyDst},
		)
	if err != "" {
		return err
	}
	renderer.temporal_resolved_depth_texture, renderer.temporal_resolved_depth_view, err =
		wgpu_create_post_texture(
			renderer,
			"Scrapbot Temporal Resolved Depth",
			width,
			height,
			.R32Float,
			{.StorageBinding, .CopySrc},
		)
	if err != "" {
		return err
	}
	renderer.temporal_history_depth_texture, renderer.temporal_history_depth_view, err =
		wgpu_create_post_texture(
			renderer,
			"Scrapbot Temporal History Depth",
			width,
			height,
			.R32Float,
			{.TextureBinding, .CopyDst},
		)
	if err != "" {
		return err
	}
	ambient_occlusion_width := max(u32(1), (width + 1) / 2)
	ambient_occlusion_height := max(u32(1), (height + 1) / 2)
	for index in 0 ..< len(renderer.ambient_occlusion_textures) {
		texture := wgpu.DeviceCreateTexture(
			renderer.device,
			&wgpu.TextureDescriptor {
				label = "Scrapbot Ambient Occlusion Texture",
				usage = {.TextureBinding, .StorageBinding},
				dimension = ._2D,
				size = {
					width = ambient_occlusion_width,
					height = ambient_occlusion_height,
					depthOrArrayLayers = 1,
				},
				format = .RGBA8Unorm,
				mipLevelCount = 1,
				sampleCount = 1,
			},
		)
		if texture == nil {
			return "failed to create ambient occlusion texture"
		}
		view := wgpu.TextureCreateView(texture)
		if view == nil {
			wgpu.TextureRelease(texture)
			return "failed to create ambient occlusion texture view"
		}
		renderer.ambient_occlusion_textures[index] = texture
		renderer.ambient_occlusion_views[index] = view
	}
	ambient_occlusion_sources := [?]wgpu.TextureView {
		renderer.ambient_occlusion_views[2],
		renderer.ambient_occlusion_views[0],
		renderer.ambient_occlusion_views[1],
	}
	ambient_occlusion_destinations := [?]wgpu.TextureView {
		renderer.ambient_occlusion_views[0],
		renderer.ambient_occlusion_views[1],
		renderer.ambient_occlusion_views[2],
	}
	for index in 0 ..< len(renderer.ambient_occlusion_bind_groups) {
		entries := [?]wgpu.BindGroupEntry {
			{binding = 0, textureView = depth_view},
			{binding = 1, textureView = ambient_occlusion_sources[index]},
			{binding = 2, textureView = ambient_occlusion_destinations[index]},
			{binding = 3, textureView = renderer.surface_view},
			{
				binding = 4,
				buffer = renderer.ambient_occlusion_uniform_buffer,
				offset = 0,
				size = u64(size_of(WGPU_Ambient_Occlusion_Uniform)),
			},
		}
		renderer.ambient_occlusion_bind_groups[index] = wgpu.DeviceCreateBindGroup(
			renderer.device,
			&wgpu.BindGroupDescriptor {
				label = "Scrapbot Ambient Occlusion Bind Group",
				layout = renderer.ambient_occlusion_bind_group_layout,
				entryCount = uint(len(entries)),
				entries = raw_data(entries[:]),
			},
		)
		if renderer.ambient_occlusion_bind_groups[index] == nil {
			return "failed to create ambient occlusion bind groups"
		}
	}
	temporal_entries := [?]wgpu.BindGroupEntry {
		{binding = 0, textureView = renderer.hdr_view},
		{binding = 1, sampler = renderer.post_sampler},
		{binding = 2, textureView = depth_view},
		{binding = 3, textureView = renderer.temporal_history_view},
		{binding = 4, textureView = renderer.temporal_history_depth_view},
		{binding = 5, textureView = renderer.temporal_resolved_view},
		{binding = 6, textureView = renderer.temporal_resolved_depth_view},
		{
			binding = 7,
			buffer = renderer.temporal_aa_uniform_buffer,
			offset = 0,
			size = u64(size_of(WGPU_Temporal_AA_Uniform)),
		},
		{binding = 8, textureView = renderer.ambient_occlusion_views[2]},
		{binding = 9, textureView = renderer.screen_space_reflections_view},
		{binding = 10, textureView = renderer.surface_view},
		{binding = 11, textureView = renderer.indirect_diffuse_view},
		{
			binding = 12,
			buffer = renderer.gpu_render_uniform_buffer,
			offset = 0,
			size = u64(size_of(WGPU_GPU_Render_Uniform)),
		},
		{binding = 13, textureView = renderer.shadow_array_view},
		{binding = 14, sampler = renderer.shadow_sampler},
	}
	renderer.temporal_aa_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Temporal AA Bind Group",
			layout = renderer.temporal_aa_bind_group_layout,
			entryCount = uint(len(temporal_entries)),
			entries = raw_data(temporal_entries[:]),
		},
	)
	if renderer.temporal_aa_bind_group == nil {
		return "failed to create temporal AA bind group"
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
		source :=
			renderer.temporal_resolved_view if index == 0 else renderer.bloom_views[index - 1]
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
		textureView = renderer.temporal_resolved_view,
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
	renderer.post_depth_view = depth_view
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
	depth_view: wgpu.TextureView,
	width, height: u32,
	camera: shared.Camera_Component,
	has_camera: bool,
	world: ^shared.World,
) -> string {
	if err := wgpu_ensure_post_targets(renderer, width, height, depth_view); err != "" {
		return err
	}
	resolved_camera := camera
	if !has_camera {
		resolved_camera = shared.camera_defaults()
	}
	ambient_occlusion_width := max(u32(1), (width + 1) / 2)
	ambient_occlusion_height := max(u32(1), (height + 1) / 2)
	projection := renderer.gpu_cluster_uniform.projection
	viewport := renderer.gpu_cluster_uniform.viewport
	history_valid := f32(0)
	if renderer.temporal_history_valid {
		history_valid = 1
	}
	if resolved_camera.ambient_occlusion {
		ambient_occlusion_uniform := WGPU_Ambient_Occlusion_Uniform {
			projection = {projection[0], projection[5], projection[10], projection[14]},
			viewport = viewport,
			dimensions = {f32(width), f32(height), projection[8], projection[9]},
			parameters = {
				WGPU_VISIBILITY_AO_RADIUS,
				WGPU_VISIBILITY_AO_POWER,
				WGPU_VISIBILITY_AO_STRENGTH,
				0,
			},
			visibility_parameters = {WGPU_VISIBILITY_AO_THICKNESS, 0, 0, 0},
		}
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.ambient_occlusion_uniform_buffer,
			0,
			&ambient_occlusion_uniform,
			size_of(ambient_occlusion_uniform),
		)
		ambient_occlusion_timestamps, ambient_occlusion_timestamps_enabled :=
			wgpu_gpu_pass_timestamps(renderer, .Ambient_Occlusion)
		ambient_occlusion_timestamps_ptr: ^wgpu.PassTimestampWrites
		if ambient_occlusion_timestamps_enabled {
			ambient_occlusion_timestamps_ptr = &ambient_occlusion_timestamps
		}
		ambient_occlusion_pass := wgpu.CommandEncoderBeginComputePass(
			encoder,
			&wgpu.ComputePassDescriptor {
				label = "Scrapbot Ambient Occlusion Compute Pass",
				timestampWrites = ambient_occlusion_timestamps_ptr,
			},
		)
		if ambient_occlusion_pass == nil {
			return "failed to begin ambient occlusion compute pass"
		}
		ambient_occlusion_pipelines := [?]wgpu.ComputePipeline {
			renderer.ambient_occlusion_pipeline,
			renderer.ambient_occlusion_blur_horizontal_pipeline,
			renderer.ambient_occlusion_blur_vertical_pipeline,
		}
		for pipeline, index in ambient_occlusion_pipelines {
			wgpu.ComputePassEncoderSetPipeline(ambient_occlusion_pass, pipeline)
			wgpu.ComputePassEncoderSetBindGroup(
				ambient_occlusion_pass,
				0,
				renderer.ambient_occlusion_bind_groups[index],
			)
			wgpu.ComputePassEncoderDispatchWorkgroups(
				ambient_occlusion_pass,
				(ambient_occlusion_width + 7) / 8,
				(ambient_occlusion_height + 7) / 8,
				1,
			)
		}
		wgpu.ComputePassEncoderEnd(ambient_occlusion_pass)
		wgpu.ComputePassEncoderRelease(ambient_occlusion_pass)
	}
	if resolved_camera.screen_space_reflections {
		reflections_uniform := WGPU_Screen_Space_Reflections_Uniform {
			projection = {projection[0], projection[5], projection[10], projection[14]},
			viewport = viewport,
			parameters = {40.0, 0.08, 0.10, 0.65},
			_padding = {projection[8], projection[9], 0, 0},
		}
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.screen_space_reflections_uniform_buffer,
			0,
			&reflections_uniform,
			size_of(reflections_uniform),
		)
		reflections_timestamps, reflections_timestamps_enabled := wgpu_gpu_pass_timestamps(
			renderer,
			.Screen_Space_Reflections,
		)
		reflections_timestamps_ptr: ^wgpu.PassTimestampWrites
		if reflections_timestamps_enabled {
			reflections_timestamps_ptr = &reflections_timestamps
		}
		reflections_pass := wgpu.CommandEncoderBeginComputePass(
			encoder,
			&wgpu.ComputePassDescriptor {
				label = "Scrapbot Screen-Space Reflections Compute Pass",
				timestampWrites = reflections_timestamps_ptr,
			},
		)
		if reflections_pass == nil {
			return "failed to begin screen-space reflections compute pass"
		}
		wgpu.ComputePassEncoderSetPipeline(
			reflections_pass,
			renderer.screen_space_reflections_pipeline,
		)
		wgpu.ComputePassEncoderSetBindGroup(
			reflections_pass,
			0,
			renderer.screen_space_reflections_bind_group,
		)
		wgpu.ComputePassEncoderDispatchWorkgroups(
			reflections_pass,
			(width + 7) / 8,
			(height + 7) / 8,
			1,
		)
		wgpu.ComputePassEncoderEnd(reflections_pass)
		wgpu.ComputePassEncoderRelease(reflections_pass)
	}
	temporal_uniform := WGPU_Temporal_AA_Uniform {
		previous_view_projection = renderer.temporal_previous_view_projection,
		inverse_view = renderer.temporal_inverse_view,
		projection = renderer.temporal_current_projection,
		previous_projection = renderer.temporal_previous_projection,
		viewport = viewport,
		parameters = {projection[8], projection[9], history_valid, 0.9},
		features = {
			1 if resolved_camera.temporal_antialiasing else 0,
			1 if resolved_camera.fast_antialiasing else 0,
			1 if resolved_camera.ambient_occlusion else 0,
			1 if resolved_camera.bloom else 0,
		},
		reflections = {1 if resolved_camera.screen_space_reflections else 0, 0, 0, 0},
	}
	fog := wgpu_volumetric_fog_settings(world)
	temporal_uniform.fog_color_density = {fog.color.x, fog.color.y, fog.color.z, fog.density}
	temporal_uniform.fog_height_distance = {
		fog.height,
		fog.height_falloff,
		fog.max_distance,
		fog.anisotropy,
	}
	temporal_uniform.fog_lighting = {
		fog.ambient_intensity,
		fog.light_intensity,
		fog.point_light_intensity,
		0,
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.temporal_aa_uniform_buffer,
		0,
		&temporal_uniform,
		size_of(temporal_uniform),
	)
	temporal_timestamps, temporal_timestamps_enabled := wgpu_gpu_pass_timestamps(
		renderer,
		.Temporal_AA,
	)
	temporal_timestamps_ptr: ^wgpu.PassTimestampWrites
	if temporal_timestamps_enabled {
		temporal_timestamps_ptr = &temporal_timestamps
	}
	temporal_pass := wgpu.CommandEncoderBeginComputePass(
		encoder,
		&wgpu.ComputePassDescriptor {
			label = "Scrapbot Temporal AA Compute Pass",
			timestampWrites = temporal_timestamps_ptr,
		},
	)
	if temporal_pass == nil {
		return "failed to begin temporal AA compute pass"
	}
	wgpu.ComputePassEncoderSetPipeline(temporal_pass, renderer.temporal_aa_pipeline)
	wgpu.ComputePassEncoderSetBindGroup(temporal_pass, 0, renderer.temporal_aa_bind_group)
	wgpu.ComputePassEncoderSetBindGroup(temporal_pass, 1, renderer.gpu_cluster_bind_group)
	wgpu.ComputePassEncoderDispatchWorkgroups(temporal_pass, (width + 7) / 8, (height + 7) / 8, 1)
	wgpu.ComputePassEncoderEnd(temporal_pass)
	wgpu.ComputePassEncoderRelease(temporal_pass)
	copy_size := wgpu.Extent3D {
		width = width,
		height = height,
		depthOrArrayLayers = 1,
	}
	if resolved_camera.temporal_antialiasing {
		wgpu.CommandEncoderCopyTextureToTexture(
			encoder,
			&wgpu.TexelCopyTextureInfo {
				texture = renderer.temporal_resolved_texture,
				aspect = .All,
			},
			&wgpu.TexelCopyTextureInfo{texture = renderer.temporal_history_texture, aspect = .All},
			&copy_size,
		)
		wgpu.CommandEncoderCopyTextureToTexture(
			encoder,
			&wgpu.TexelCopyTextureInfo {
				texture = renderer.temporal_resolved_depth_texture,
				aspect = .All,
			},
			&wgpu.TexelCopyTextureInfo {
				texture = renderer.temporal_history_depth_texture,
				aspect = .All,
			},
			&copy_size,
		)
	}

	if resolved_camera.bloom {
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
	}
	err := wgpu_encode_fullscreen_pass(
		renderer,
		encoder,
		output_view,
		renderer.composite_pipeline,
		renderer.composite_bind_group,
		"Scrapbot HDR Composite Pass",
		.Composite,
	)
	if err != "" {
		return err
	}
	renderer.temporal_previous_view_projection = renderer.temporal_current_view_projection
	renderer.temporal_previous_projection = renderer.temporal_current_projection
	renderer.temporal_history_valid = resolved_camera.temporal_antialiasing
	if resolved_camera.temporal_antialiasing {
		renderer.temporal_sample_index += 1
	} else {
		renderer.temporal_sample_index = 0
	}
	return ""
}
