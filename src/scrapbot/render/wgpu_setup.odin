package render

import ecs "../ecs"
import platform "../platform"
import resources "../resources"
import shared "../shared"
import ui "../ui"
import "core:fmt"
import "core:time"
import "vendor:wgpu"
import wgpu_sdl3 "vendor:wgpu/sdl3glue"

wgpu_request_adapter_callback :: proc "c" (
	status: wgpu.RequestAdapterStatus,
	adapter: wgpu.Adapter,
	message: wgpu.StringView,
	userdata1: rawptr,
	userdata2: rawptr,
) {
	state := cast(^WGPU_Request_Adapter_State)userdata1
	state.completed = true
	state.status = status
	state.adapter = adapter
	state.message = message
}

wgpu_request_device_callback :: proc "c" (
	status: wgpu.RequestDeviceStatus,
	device: wgpu.Device,
	message: wgpu.StringView,
	userdata1: rawptr,
	userdata2: rawptr,
) {
	state := cast(^WGPU_Request_Device_State)userdata1
	state.completed = true
	state.status = status
	state.device = device
	state.message = message
}

wgpu_buffer_map_callback :: proc "c" (
	status: wgpu.MapAsyncStatus,
	message: wgpu.StringView,
	userdata1: rawptr,
	userdata2: rawptr,
) {
	state := cast(^WGPU_Buffer_Map_State)userdata1
	state.completed = true
	state.status = status
	state.message = message
}

wgpu_wait_for_adapter :: proc(
	instance: wgpu.Instance,
	state: ^WGPU_Request_Adapter_State,
) -> bool {
	for _ in 0 ..< 500 {
		if state.completed {
			return state.status == .Success
		}
		wgpu.InstanceProcessEvents(instance)
		time.sleep(1 * time.Millisecond)
	}
	return false
}

wgpu_wait_for_device :: proc(instance: wgpu.Instance, state: ^WGPU_Request_Device_State) -> bool {
	for _ in 0 ..< 500 {
		if state.completed {
			return state.status == .Success
		}
		wgpu.InstanceProcessEvents(instance)
		time.sleep(1 * time.Millisecond)
	}
	return false
}

wgpu_wait_for_buffer_map :: proc(instance: wgpu.Instance, state: ^WGPU_Buffer_Map_State) -> bool {
	for _ in 0 ..< 1000 {
		if state.completed {
			return state.status == .Success
		}
		wgpu.InstanceProcessEvents(instance)
		time.sleep(1 * time.Millisecond)
	}
	return false
}

wgpu_init_renderer :: proc(
	use_surface: bool,
	ui_state: ^ui.State = nil,
	offscreen_format := wgpu.TextureFormat.RGBA8UnormSrgb,
) -> (
	renderer: WGPU_Renderer,
	err: string,
) {
	if use_surface && platform.runtime_window == nil {
		return renderer, "wgpu renderer requires an SDL3 window"
	}

	renderer.instance = wgpu.CreateInstance()
	if renderer.instance == nil {
		return renderer, "failed to create wgpu instance"
	}

	if use_surface {
		renderer.surface = wgpu_sdl3.GetSurface(renderer.instance, platform.runtime_window)
		if renderer.surface == nil {
			return renderer, "failed to create wgpu SDL3 surface"
		}
	}

	adapter_state: WGPU_Request_Adapter_State
	adapter_options := wgpu.RequestAdapterOptions {
		powerPreference = .HighPerformance,
	}
	if use_surface {
		adapter_options.compatibleSurface = renderer.surface
	} else {
		when ODIN_OS == .Darwin {
			adapter_options.backendType = .Metal
		} else when ODIN_OS == .Windows {
			adapter_options.backendType = .D3D12
		} else when ODIN_OS == .Linux {
			adapter_options.backendType = .Vulkan
		}
	}
	wgpu.InstanceRequestAdapter(
		renderer.instance,
		&adapter_options,
		wgpu.RequestAdapterCallbackInfo {
			mode = .AllowSpontaneos,
			callback = wgpu_request_adapter_callback,
			userdata1 = &adapter_state,
		},
	)
	if !wgpu_wait_for_adapter(renderer.instance, &adapter_state) {
		message := adapter_state.message
		if message == "" {
			message = "request timed out"
		}
		return renderer, fmt.tprintf("failed to request wgpu adapter: %s", message)
	}
	renderer.adapter = adapter_state.adapter

	timestamp_features := [?]wgpu.FeatureName{.TimestampQuery}
	timestamp_supported := bool(wgpu.AdapterHasFeature(renderer.adapter, .TimestampQuery))
	device_descriptor := wgpu.DeviceDescriptor {
		label = "Scrapbot Device",
	}
	if timestamp_supported {
		device_descriptor.requiredFeatureCount = uint(len(timestamp_features))
		device_descriptor.requiredFeatures = raw_data(timestamp_features[:])
	}
	device_state: WGPU_Request_Device_State
	wgpu.AdapterRequestDevice(
		renderer.adapter,
		&device_descriptor,
		wgpu.RequestDeviceCallbackInfo {
			mode = .AllowSpontaneos,
			callback = wgpu_request_device_callback,
			userdata1 = &device_state,
		},
	)
	if !wgpu_wait_for_device(renderer.instance, &device_state) {
		message := device_state.message
		if message == "" {
			message = "request timed out"
		}
		return renderer, fmt.tprintf("failed to request wgpu device: %s", message)
	}
	renderer.device = device_state.device

	renderer.queue = wgpu.DeviceGetQueue(renderer.device)
	if renderer.queue == nil {
		return renderer, "failed to get wgpu queue"
	}
	wgpu_create_gpu_timing(&renderer)
	if use_surface {
		capabilities, caps_status := wgpu.SurfaceGetCapabilities(
			renderer.surface,
			renderer.adapter,
		)
		if caps_status != .Success ||
		   capabilities.formatCount == 0 ||
		   capabilities.presentModeCount == 0 ||
		   capabilities.alphaModeCount == 0 {
			return renderer, "failed to query wgpu surface capabilities"
		}
		defer wgpu.SurfaceCapabilitiesFreeMembers(capabilities)

		renderer.format = capabilities.formats[0]
		for i in 0 ..< int(capabilities.formatCount) {
			candidate := capabilities.formats[i]
			if candidate == .BGRA8UnormSrgb || candidate == .RGBA8UnormSrgb {
				renderer.format = candidate
				break
			}
		}
		// FIFO is guaranteed by WebGPU and provides the window loop's frame pacing.
		renderer.present_mode = .Fifo
		renderer.alpha_mode = capabilities.alphaModes[0]
	} else {
		renderer.format = offscreen_format
	}

	if err = wgpu_create_environment_resources(&renderer); err != "" {
		return renderer, err
	}
	if err = wgpu_create_render_pipeline(&renderer); err != "" {
		return renderer, err
	}
	if err = wgpu_create_gpu_driven_pipelines(&renderer); err != "" {
		return renderer, err
	}
	if err = wgpu_create_post_process_pipelines(&renderer); err != "" {
		return renderer, err
	}
	if ui_state !=
	   nil { if err = wgpu_create_ui_pipeline(&renderer, ui_state); err != "" { return renderer, err } }

	return renderer, ""
}

wgpu_destroy_renderer :: proc(renderer: ^WGPU_Renderer) {
	if renderer.device != nil {
		wgpu.DevicePoll(renderer.device, true)
	}
	wgpu_release_gpu_timing(renderer)
	wgpu_release_environment_resources(renderer)
	if renderer.configured {
		wgpu.SurfaceUnconfigure(renderer.surface)
	}
	if renderer.pipeline != nil {
		wgpu.RenderPipelineRelease(renderer.pipeline)
	}
	wgpu_release_post_process(renderer)
	if renderer.ui_pipeline != nil { wgpu.RenderPipelineRelease(renderer.ui_pipeline) }
	if renderer.ui_viewport_pipeline != nil {
		wgpu.RenderPipelineRelease(renderer.ui_viewport_pipeline)
	}
	if renderer.ui_viewport_texture_pipeline != nil {
		wgpu.RenderPipelineRelease(renderer.ui_viewport_texture_pipeline)
	}
	if renderer.ui_viewport_texture_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.ui_viewport_texture_pipeline_layout)
	}
	if renderer.ui_viewport_texture_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.ui_viewport_texture_bind_group_layout)
	}
	if renderer.ui_shader != nil { wgpu.ShaderModuleRelease(renderer.ui_shader) }
	if renderer.ui_bind_group != nil { wgpu.BindGroupRelease(renderer.ui_bind_group) }
	if renderer.ui_font_sampler != nil { wgpu.SamplerRelease(renderer.ui_font_sampler) }
	if renderer.ui_font_view != nil { wgpu.TextureViewRelease(renderer.ui_font_view) }
	if renderer.ui_font_texture != nil { wgpu.TextureRelease(renderer.ui_font_texture) }
	for layer in 0 ..< ui.MAX_EMBEDDED_VIEWPORTS {
		if renderer.ui_viewport_bind_groups[layer] != nil {
			wgpu.BindGroupRelease(renderer.ui_viewport_bind_groups[layer])
		}
		if renderer.ui_viewport_uniform_buffers[layer] != nil {
			wgpu.BufferRelease(renderer.ui_viewport_uniform_buffers[layer])
		}
		if renderer.ui_viewport_depth_views[layer] != nil {
			wgpu.TextureViewRelease(renderer.ui_viewport_depth_views[layer])
		}
		if renderer.ui_viewport_depth_textures[layer] != nil {
			wgpu.TextureRelease(renderer.ui_viewport_depth_textures[layer])
		}
		if renderer.ui_viewport_layer_views[layer] != nil {
			wgpu.TextureViewRelease(renderer.ui_viewport_layer_views[layer])
		}
		if renderer.ui_viewport_textures[layer] != nil {
			wgpu.TextureRelease(renderer.ui_viewport_textures[layer])
		}
	}
	if renderer.ui_viewport_preview_vertex_buffer != nil {
		wgpu.BufferRelease(renderer.ui_viewport_preview_vertex_buffer)
	}
	if renderer.ui_viewport_preview_index_buffer != nil {
		wgpu.BufferRelease(renderer.ui_viewport_preview_index_buffer)
	}
	if renderer.ui_project_vertex_buffer != nil {
		wgpu.BufferRelease(renderer.ui_project_vertex_buffer)
	}
	if renderer.ui_editor_vertex_buffer != nil {
		wgpu.BufferRelease(renderer.ui_editor_vertex_buffer)
	}
	if renderer.ui_overlay_vertex_buffer != nil {
		wgpu.BufferRelease(renderer.ui_overlay_vertex_buffer)
	}
	delete(renderer.ui_project_vertices)
	delete(renderer.ui_editor_vertices)
	delete(renderer.ui_overlay_vertices)
	wgpu_release_batch_bind_groups(&renderer.draw_batch_cache)
	delete(renderer.draw_batch_cache.source_indices)
	delete(renderer.draw_batch_cache.batches)
	delete(renderer.gpu_instance_records)
	delete(renderer.gpu_instance_transform_records)
	delete(renderer.gpu_instance_sources)
	delete(renderer.gpu_instance_source_transforms)
	delete(renderer.gpu_active_slots)
	delete(renderer.gpu_dirty_indices)
	delete(renderer.gpu_transform_updates)
	delete(renderer.gpu_live_slots)
	delete(renderer.gpu_batch_indices_by_slot)
	delete(renderer.gpu_cpu_visible)
	delete(renderer.gpu_cpu_shadow_visible)
	delete(renderer.gpu_indirect_templates)
	wgpu_release_visibility_readbacks(renderer)
	ecs.destroy_render_list(&renderer.render_list)
	if renderer.gpu_cull_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_cull_bind_group)
	}
	if renderer.gpu_cull_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.gpu_cull_pipeline)
	}
	if renderer.gpu_cull_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.gpu_cull_pipeline_layout)
	}
	if renderer.gpu_cull_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.gpu_cull_bind_group_layout)
	}
	if renderer.gpu_cull_shader != nil {
		wgpu.ShaderModuleRelease(renderer.gpu_cull_shader)
	}
	if renderer.gpu_transform_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_transform_bind_group)
	}
	if renderer.gpu_transform_pipeline != nil {
		wgpu.ComputePipelineRelease(renderer.gpu_transform_pipeline)
	}
	if renderer.gpu_transform_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.gpu_transform_pipeline_layout)
	}
	if renderer.gpu_transform_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.gpu_transform_bind_group_layout)
	}
	if renderer.gpu_transform_shader != nil {
		wgpu.ShaderModuleRelease(renderer.gpu_transform_shader)
	}
	if renderer.gpu_driven_pipeline != nil {
		wgpu.RenderPipelineRelease(renderer.gpu_driven_pipeline)
	}
	if renderer.gpu_driven_depth_pipeline != nil {
		wgpu.RenderPipelineRelease(renderer.gpu_driven_depth_pipeline)
	}
	if renderer.gpu_driven_depth_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.gpu_driven_depth_pipeline_layout)
	}
	if renderer.gpu_driven_shadow_pipeline != nil {
		wgpu.RenderPipelineRelease(renderer.gpu_driven_shadow_pipeline)
	}
	if renderer.gpu_driven_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.gpu_driven_pipeline_layout)
	}
	if renderer.gpu_driven_shadow_pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.gpu_driven_shadow_pipeline_layout)
	}
	if renderer.gpu_driven_world_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.gpu_driven_world_bind_group_layout)
	}
	if renderer.gpu_driven_shadow_bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.gpu_driven_shadow_bind_group_layout)
	}
	if renderer.gpu_driven_shader != nil {
		wgpu.ShaderModuleRelease(renderer.gpu_driven_shader)
	}
	wgpu_release_hiz(renderer)
	gpu_buffers := [?]wgpu.Buffer {
		renderer.gpu_instance_buffer,
		renderer.gpu_transform_update_buffer,
		renderer.gpu_batch_info_buffer,
		renderer.gpu_visible_buffer,
		renderer.gpu_shadow_visible_buffer,
		renderer.gpu_indirect_template_buffer,
		renderer.gpu_indirect_buffer,
		renderer.gpu_shadow_indirect_buffer,
		renderer.gpu_cull_uniform_buffer,
		renderer.gpu_render_uniform_buffer,
		renderer.gpu_visibility_counter_buffer,
	}
	for buffer in gpu_buffers {
		if buffer != nil {
			wgpu.BufferRelease(buffer)
		}
	}
	if renderer.ui_pipeline_layout !=
	   nil { wgpu.PipelineLayoutRelease(renderer.ui_pipeline_layout) }
	if renderer.ui_bind_group_layout !=
	   nil { wgpu.BindGroupLayoutRelease(renderer.ui_bind_group_layout) }
	if renderer.shadow_pipeline != nil { wgpu.RenderPipelineRelease(renderer.shadow_pipeline) }
	if renderer.shadow_bind_group != nil { wgpu.BindGroupRelease(renderer.shadow_bind_group) }
	if renderer.shadow_bind_group_layout !=
	   nil { wgpu.BindGroupLayoutRelease(renderer.shadow_bind_group_layout) }
	if renderer.shadow_pipeline_layout !=
	   nil { wgpu.PipelineLayoutRelease(renderer.shadow_pipeline_layout) }
	if renderer.uniform_buffer != nil {
		wgpu.BufferRelease(renderer.uniform_buffer)
	}
	for &cached in renderer.geometry_cache {
		if cached.vertex_buffer != nil { wgpu.BufferRelease(cached.vertex_buffer) }
		if cached.index_buffer != nil { wgpu.BufferRelease(cached.index_buffer) }
	}
	delete(renderer.geometry_cache)
	for &cached in renderer.texture_cache {
		if cached.view != nil { wgpu.TextureViewRelease(cached.view) }
		if cached.texture != nil { wgpu.TextureRelease(cached.texture) }
	}
	delete(renderer.texture_cache)
	for &cached in renderer.material_cache {
		if cached.bind_group != nil { wgpu.BindGroupRelease(cached.bind_group) }
		if cached.uniform_buffer != nil { wgpu.BufferRelease(cached.uniform_buffer) }
		for owns, index in cached.owns_texture {
			if !owns {
				continue
			}
			if cached.views[index] != nil { wgpu.TextureViewRelease(cached.views[index]) }
			if cached.textures[index] != nil { wgpu.TextureRelease(cached.textures[index]) }
		}
	}
	delete(renderer.material_cache)
	for view in renderer.material_fallback_views {
		if view != nil {
			wgpu.TextureViewRelease(view)
		}
	}
	for texture in renderer.material_fallback_textures {
		if texture != nil {
			wgpu.TextureRelease(texture)
		}
	}
	if renderer.bind_group != nil {
		wgpu.BindGroupRelease(renderer.bind_group)
	}
	if renderer.bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.bind_group_layout)
	}
	if renderer.material_sampler != nil { wgpu.SamplerRelease(renderer.material_sampler) }
	if renderer.material_bind_group_layout !=
	   nil { wgpu.BindGroupLayoutRelease(renderer.material_bind_group_layout) }
	if renderer.shadow_sampler != nil { wgpu.SamplerRelease(renderer.shadow_sampler) }
	if renderer.shadow_view != nil { wgpu.TextureViewRelease(renderer.shadow_view) }
	if renderer.shadow_texture != nil { wgpu.TextureRelease(renderer.shadow_texture) }
	if renderer.depth_view != nil {
		wgpu.TextureViewRelease(renderer.depth_view)
	}
	if renderer.depth_texture != nil {
		wgpu.TextureRelease(renderer.depth_texture)
	}
	if renderer.shader != nil {
		wgpu.ShaderModuleRelease(renderer.shader)
	}
	if renderer.pipeline_layout != nil {
		wgpu.PipelineLayoutRelease(renderer.pipeline_layout)
	}
	if renderer.queue != nil {
		wgpu.QueueRelease(renderer.queue)
	}
	if renderer.device != nil {
		wgpu.DeviceRelease(renderer.device)
	}
	if renderer.adapter != nil {
		wgpu.AdapterRelease(renderer.adapter)
	}
	if renderer.surface != nil {
		wgpu.SurfaceRelease(renderer.surface)
	}
	if renderer.instance != nil {
		wgpu.InstanceRelease(renderer.instance)
	}
	renderer^ = {}
}

wgpu_create_render_pipeline :: proc(renderer: ^WGPU_Renderer) -> string {
	shader_source := wgpu.ShaderSourceWGSL {
		chain = wgpu.ChainedStruct{sType = .ShaderSourceWGSL},
		code = WGPU_RENDER_SHADER,
	}
	renderer.shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &shader_source,
			label = "Scrapbot Render Shader",
		},
	)
	if renderer.shader == nil {
		return "failed to create wgpu shader module"
	}

	bind_group_layout_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Vertex, .Fragment},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_Render_Uniform))},
		},
		{
			binding = 1,
			visibility = {.Fragment},
			texture = {sampleType = .Depth, viewDimension = ._2D},
		},
		{binding = 2, visibility = {.Fragment}, sampler = {type = .Comparison}},
	}
	renderer.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Render Bind Group Layout",
			entryCount = uint(len(bind_group_layout_entries)),
			entries = raw_data(bind_group_layout_entries[:]),
		},
	)
	if renderer.bind_group_layout == nil {
		return "failed to create wgpu bind group layout"
	}
	material_layout_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{binding = 1, visibility = {.Fragment}, sampler = {type = .Filtering}},
		{
			binding = 2,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 3,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 4,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 5,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{
			binding = 6,
			visibility = {.Fragment},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_Material_Uniform))},
		},
	}
	renderer.material_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Material Bind Group Layout",
			entryCount = uint(len(material_layout_entries)),
			entries = raw_data(material_layout_entries[:]),
		},
	)
	if renderer.material_bind_group_layout ==
	   nil { return "failed to create material bind group layout" }
	renderer.material_sampler = wgpu.DeviceCreateSampler(
		renderer.device,
		&wgpu.SamplerDescriptor {
			label = "Scrapbot Material Sampler",
			addressModeU = .Repeat,
			addressModeV = .Repeat,
			addressModeW = .Repeat,
			magFilter = .Linear,
			minFilter = .Linear,
			mipmapFilter = .Linear,
			maxAnisotropy = 8,
		},
	)
	if renderer.material_sampler == nil { return "failed to create material sampler" }
	fallbacks := [?][4]u8 {
		{255, 255, 255, 255},
		{255, 255, 255, 255},
		{128, 128, 255, 255},
		{255, 255, 255, 255},
		{0, 0, 0, 255},
	}
	fallback_spaces := [?]shared.Texture_Color_Space{.SRGB, .Linear, .Linear, .Linear, .SRGB}
	fallback_labels := [?]string {
		"Scrapbot Base Color Fallback",
		"Scrapbot Metallic Roughness Fallback",
		"Scrapbot Normal Fallback",
		"Scrapbot Occlusion Fallback",
		"Scrapbot Emissive Fallback",
	}
	for fallback, index in fallbacks {
		texture, view, fallback_err := wgpu_create_material_image(
			renderer,
			{color_space = fallback_spaces[index]},
			fallback,
			fallback_labels[index],
		)
		if fallback_err != "" {
			return fallback_err
		}
		renderer.material_fallback_textures[index] = texture
		renderer.material_fallback_views[index] = view
	}

	pipeline_layouts := [?]wgpu.BindGroupLayout {
		renderer.bind_group_layout,
		renderer.material_bind_group_layout,
		renderer.environment_bind_group_layout,
	}
	renderer.pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Render Pipeline Layout",
			bindGroupLayoutCount = uint(len(pipeline_layouts)),
			bindGroupLayouts = raw_data(pipeline_layouts[:]),
		},
	)
	if renderer.pipeline_layout == nil {
		return "failed to create wgpu pipeline layout"
	}

	renderer.uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Render Uniform Buffer",
			usage = {.Uniform, .CopyDst},
			size = u64(size_of(WGPU_Render_Uniform)),
		},
	)
	if renderer.uniform_buffer == nil {
		return "failed to create wgpu uniform buffer"
	}

	renderer.shadow_texture = wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label = "Scrapbot Directional Shadow Map",
			usage = {.RenderAttachment, .TextureBinding},
			dimension = ._2D,
			size = {
				width = WGPU_SHADOW_MAP_SIZE,
				height = WGPU_SHADOW_MAP_SIZE,
				depthOrArrayLayers = 1,
			},
			format = .Depth32Float,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	if renderer.shadow_texture == nil { return "failed to create wgpu shadow texture" }
	renderer.shadow_view = wgpu.TextureCreateView(renderer.shadow_texture)
	if renderer.shadow_view == nil { return "failed to create wgpu shadow texture view" }
	renderer.shadow_sampler = wgpu.DeviceCreateSampler(
		renderer.device,
		&wgpu.SamplerDescriptor {
			label = "Scrapbot Shadow Sampler",
			addressModeU = .ClampToEdge,
			addressModeV = .ClampToEdge,
			addressModeW = .ClampToEdge,
			magFilter = .Linear,
			minFilter = .Linear,
			mipmapFilter = .Linear,
			compare = .LessEqual,
			maxAnisotropy = 1,
		},
	)
	if renderer.shadow_sampler == nil { return "failed to create wgpu shadow sampler" }

	bind_group_entries := [?]wgpu.BindGroupEntry {
		{
			binding = 0,
			buffer = renderer.uniform_buffer,
			offset = 0,
			size = u64(size_of(WGPU_Render_Uniform)),
		},
		{binding = 1, textureView = renderer.shadow_view},
		{binding = 2, sampler = renderer.shadow_sampler},
	}
	renderer.bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Render Bind Group",
			layout = renderer.bind_group_layout,
			entryCount = uint(len(bind_group_entries)),
			entries = raw_data(bind_group_entries[:]),
		},
	)
	if renderer.bind_group == nil {
		return "failed to create wgpu bind group"
	}

	shadow_layout_entry := wgpu.BindGroupLayoutEntry {
		binding = 0,
		visibility = {.Vertex},
		buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_Render_Uniform))},
	}
	renderer.shadow_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Shadow Bind Group Layout",
			entryCount = 1,
			entries = &shadow_layout_entry,
		},
	)
	if renderer.shadow_bind_group_layout ==
	   nil { return "failed to create wgpu shadow bind group layout" }
	renderer.shadow_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Shadow Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.shadow_bind_group_layout,
		},
	)
	if renderer.shadow_pipeline_layout ==
	   nil { return "failed to create wgpu shadow pipeline layout" }
	shadow_bind_entry := wgpu.BindGroupEntry {
		binding = 0,
		buffer = renderer.uniform_buffer,
		offset = 0,
		size = u64(size_of(WGPU_Render_Uniform)),
	}
	renderer.shadow_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Shadow Bind Group",
			layout = renderer.shadow_bind_group_layout,
			entryCount = 1,
			entries = &shadow_bind_entry,
		},
	)
	if renderer.shadow_bind_group == nil { return "failed to create wgpu shadow bind group" }

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
		module = renderer.shader,
		entryPoint = "fs_main",
		targetCount = 1,
		targets = &color_target,
	}
	renderer.pipeline = wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = "Scrapbot Render Pipeline",
			layout = renderer.pipeline_layout,
			vertex = wgpu.VertexState {
				module = renderer.shader,
				entryPoint = "vs_main",
				bufferCount = 1,
				buffers = &vertex_buffer_layout,
			},
			primitive = wgpu.PrimitiveState {
				topology = .TriangleList,
				frontFace = .CCW,
				cullMode = .None,
			},
			depthStencil = &wgpu.DepthStencilState {
				format = .Depth24Plus,
				depthWriteEnabled = .True,
				depthCompare = .Less,
			},
			multisample = wgpu.MultisampleState{count = 1, mask = 0xFFFF_FFFF},
			fragment = &fragment_state,
		},
	)
	if renderer.pipeline == nil {
		return "failed to create wgpu render pipeline"
	}

	renderer.shadow_pipeline = wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = "Scrapbot Shadow Pipeline",
			layout = renderer.shadow_pipeline_layout,
			vertex = {
				module = renderer.shader,
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
	if renderer.shadow_pipeline == nil { return "failed to create wgpu shadow pipeline" }

	return ""
}

wgpu_create_ui_pipeline :: proc(renderer: ^WGPU_Renderer, state: ^ui.State) -> string {
	chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_UI_SHADER,
	}
	renderer.ui_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor{nextInChain = &chain, label = "Scrapbot UI Shader"},
	); if renderer.ui_shader == nil { return "failed to create UI shader" }
	layout_entries: [2 + ui.MAX_EMBEDDED_VIEWPORTS]wgpu.BindGroupLayoutEntry
	layout_entries[0] = {
		binding = 0,
		visibility = {.Fragment},
		texture = {sampleType = .Float, viewDimension = ._2DArray},
	}
	layout_entries[1] = {
		binding = 1,
		visibility = {.Fragment},
		sampler = {type = .Filtering},
	}
	for layer in 0 ..< ui.MAX_EMBEDDED_VIEWPORTS {
		layout_entries[2 + layer] = {
			binding = u32(2 + layer),
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		}
	}
	renderer.ui_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot UI Bind Group Layout",
			entryCount = uint(len(layout_entries)),
			entries = raw_data(layout_entries[:]),
		},
	); if renderer.ui_bind_group_layout == nil { return "failed to create UI bind group layout" }
	renderer.ui_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot UI Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.ui_bind_group_layout,
		},
	); if renderer.ui_pipeline_layout == nil { return "failed to create UI pipeline layout" }
	renderer.ui_font_texture = wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label = "Scrapbot UI Font Atlas",
			usage = {.TextureBinding, .CopyDst},
			dimension = ._2D,
			size = {
				width = ui.FONT_ATLAS_SIZE,
				height = ui.FONT_ATLAS_SIZE,
				depthOrArrayLayers = shared.MAX_PROJECT_FONTS + 1,
			},
			format = .RGBA8Unorm,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	); if renderer.ui_font_texture == nil { return "failed to create UI font texture" }
	wgpu.QueueWriteTexture(
		renderer.queue,
		&wgpu.TexelCopyTextureInfo{texture = renderer.ui_font_texture, aspect = .All},
		raw_data(ui.FONT_ATLAS_DATA),
		uint(len(ui.FONT_ATLAS_DATA)),
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
	renderer.ui_font_view = wgpu.TextureCreateView(
		renderer.ui_font_texture,
		&wgpu.TextureViewDescriptor {
			format = .RGBA8Unorm,
			dimension = ._2DArray,
			baseMipLevel = 0,
			mipLevelCount = 1,
			baseArrayLayer = 0,
			arrayLayerCount = shared.MAX_PROJECT_FONTS + 1,
			aspect = .All,
			usage = {.TextureBinding},
		},
	); if renderer.ui_font_view == nil { return "failed to create UI font view" }
	renderer.ui_font_sampler = wgpu.DeviceCreateSampler(
		renderer.device,
		&wgpu.SamplerDescriptor {
			label = "Scrapbot UI Font Sampler",
			addressModeU = .ClampToEdge,
			addressModeV = .ClampToEdge,
			addressModeW = .ClampToEdge,
			magFilter = .Linear,
			minFilter = .Linear,
			mipmapFilter = .Nearest,
			maxAnisotropy = 1,
		},
	); if renderer.ui_font_sampler == nil { return "failed to create UI font sampler" }
	for layer in 0 ..< ui.MAX_EMBEDDED_VIEWPORTS {
		if err := wgpu_create_viewport_color_target(
			renderer,
			layer,
			WGPU_VIEWPORT_TARGET_MIN_SIZE,
			WGPU_VIEWPORT_TARGET_MIN_SIZE,
		); err != "" {
			return err
		}
	}
	if err := wgpu_rebuild_ui_bind_group(renderer); err != "" {
		return err
	}
	attributes := [?]wgpu.VertexAttribute {
		{format = .Float32x2, offset = 0, shaderLocation = 0},
		{format = .Float32x2, offset = 8, shaderLocation = 1},
		{format = .Float32x4, offset = 16, shaderLocation = 2},
		{format = .Float32, offset = 32, shaderLocation = 3},
		{format = .Float32x3, offset = 36, shaderLocation = 4},
		{format = .Float32x4, offset = 48, shaderLocation = 5},
		{format = .Float32x4, offset = 64, shaderLocation = 6},
		{format = .Float32, offset = 80, shaderLocation = 7},
		{format = .Float32, offset = 84, shaderLocation = 8},
	}
	buffer_layout := wgpu.VertexBufferLayout {
		arrayStride = u64(size_of(WGPU_UI_Vertex)),
		stepMode = .Vertex,
		attributeCount = uint(len(attributes)),
		attributes = raw_data(attributes[:]),
	}
	blend := wgpu.BlendState {
		color = {operation = .Add, srcFactor = .SrcAlpha, dstFactor = .OneMinusSrcAlpha},
		alpha = {operation = .Add, srcFactor = .One, dstFactor = .OneMinusSrcAlpha},
	}
	color_target := wgpu.ColorTargetState {
		format = renderer.format,
		blend = &blend,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}; fragment := wgpu.FragmentState {
		module = renderer.ui_shader,
		entryPoint = "ui_fs",
		targetCount = 1,
		targets = &color_target,
	}
	renderer.ui_pipeline = wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = "Scrapbot UI Pipeline",
			layout = renderer.ui_pipeline_layout,
			vertex = {
				module = renderer.ui_shader,
				entryPoint = "ui_vs",
				bufferCount = 1,
				buffers = &buffer_layout,
			},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = .None},
			depthStencil = &wgpu.DepthStencilState {
				format = .Depth24Plus,
				depthWriteEnabled = .False,
				depthCompare = .Always,
			},
			multisample = {count = 1, mask = 0xFFFF_FFFF},
			fragment = &fragment,
		},
	)
	if renderer.ui_pipeline == nil { return "failed to create UI pipeline" }
	return wgpu_create_embedded_viewport_resources(renderer)
}

wgpu_create_viewport_color_target :: proc(
	renderer: ^WGPU_Renderer,
	layer: int,
	width, height: u32,
) -> string {
	if renderer == nil || layer < 0 || layer >= ui.MAX_EMBEDDED_VIEWPORTS {
		return "embedded viewport target is out of range"
	}
	texture := wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label = "Scrapbot Embedded Viewport Target",
			usage = {.RenderAttachment, .TextureBinding},
			dimension = ._2D,
			size = {width = width, height = height, depthOrArrayLayers = 1},
			format = .RGBA8UnormSrgb,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	if texture == nil {
		return "failed to create embedded viewport target"
	}
	view := wgpu.TextureCreateView(texture)
	if view == nil {
		wgpu.TextureRelease(texture)
		return "failed to create embedded viewport target view"
	}
	renderer.ui_viewport_textures[layer] = texture
	renderer.ui_viewport_layer_views[layer] = view
	renderer.ui_viewport_widths[layer] = width
	renderer.ui_viewport_heights[layer] = height
	return ""
}

wgpu_rebuild_ui_bind_group :: proc(renderer: ^WGPU_Renderer) -> string {
	if renderer == nil || renderer.ui_bind_group_layout == nil {
		return "UI bind group layout is unavailable"
	}
	entries: [2 + ui.MAX_EMBEDDED_VIEWPORTS]wgpu.BindGroupEntry
	entries[0] = {
		binding = 0,
		textureView = renderer.ui_font_view,
	}
	entries[1] = {
		binding = 1,
		sampler = renderer.ui_font_sampler,
	}
	for layer in 0 ..< ui.MAX_EMBEDDED_VIEWPORTS {
		if renderer.ui_viewport_layer_views[layer] == nil {
			return "embedded viewport target view is unavailable"
		}
		entries[2 + layer] = {
			binding = u32(2 + layer),
			textureView = renderer.ui_viewport_layer_views[layer],
		}
	}
	bind_group := wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot UI Bind Group",
			layout = renderer.ui_bind_group_layout,
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
	if bind_group == nil {
		return "failed to create UI bind group"
	}
	if renderer.ui_bind_group != nil {
		wgpu.BindGroupRelease(renderer.ui_bind_group)
	}
	renderer.ui_bind_group = bind_group
	return ""
}

wgpu_resize_viewport_target :: proc(
	renderer: ^WGPU_Renderer,
	layer: int,
	width, height: u32,
) -> string {
	if renderer == nil || layer < 0 || layer >= ui.MAX_EMBEDDED_VIEWPORTS {
		return "embedded viewport target is out of range"
	}
	if renderer.ui_viewport_widths[layer] == width &&
	   renderer.ui_viewport_heights[layer] == height {
		return ""
	}
	old_texture := renderer.ui_viewport_textures[layer]
	old_view := renderer.ui_viewport_layer_views[layer]
	old_depth_texture := renderer.ui_viewport_depth_textures[layer]
	old_depth_view := renderer.ui_viewport_depth_views[layer]
	old_width := renderer.ui_viewport_widths[layer]
	old_height := renderer.ui_viewport_heights[layer]
	renderer.ui_viewport_textures[layer] = nil
	renderer.ui_viewport_layer_views[layer] = nil
	if err := wgpu_create_viewport_color_target(renderer, layer, width, height); err != "" {
		renderer.ui_viewport_textures[layer] = old_texture
		renderer.ui_viewport_layer_views[layer] = old_view
		renderer.ui_viewport_widths[layer] = old_width
		renderer.ui_viewport_heights[layer] = old_height
		return err
	}
	depth_texture, depth_view, depth_err := wgpu_create_depth_texture(renderer, width, height)
	if depth_err != "" {
		wgpu.TextureViewRelease(renderer.ui_viewport_layer_views[layer])
		wgpu.TextureRelease(renderer.ui_viewport_textures[layer])
		renderer.ui_viewport_textures[layer] = old_texture
		renderer.ui_viewport_layer_views[layer] = old_view
		renderer.ui_viewport_widths[layer] = old_width
		renderer.ui_viewport_heights[layer] = old_height
		return depth_err
	}
	renderer.ui_viewport_depth_textures[layer] = depth_texture
	renderer.ui_viewport_depth_views[layer] = depth_view
	if err := wgpu_rebuild_ui_bind_group(renderer); err != "" {
		wgpu.TextureViewRelease(depth_view)
		wgpu.TextureRelease(depth_texture)
		wgpu.TextureViewRelease(renderer.ui_viewport_layer_views[layer])
		wgpu.TextureRelease(renderer.ui_viewport_textures[layer])
		renderer.ui_viewport_textures[layer] = old_texture
		renderer.ui_viewport_layer_views[layer] = old_view
		renderer.ui_viewport_depth_textures[layer] = old_depth_texture
		renderer.ui_viewport_depth_views[layer] = old_depth_view
		renderer.ui_viewport_widths[layer] = old_width
		renderer.ui_viewport_heights[layer] = old_height
		return err
	}
	if old_view != nil {
		wgpu.TextureViewRelease(old_view)
	}
	if old_texture != nil {
		wgpu.TextureRelease(old_texture)
	}
	if old_depth_view != nil {
		wgpu.TextureViewRelease(old_depth_view)
	}
	if old_depth_texture != nil {
		wgpu.TextureRelease(old_depth_texture)
	}
	renderer.ui_viewport_cache_valid[layer] = false
	renderer.ui_viewport_cache_warmup_frames[layer] = 0
	renderer.ui_viewport_target_resize_count += 1
	return ""
}

wgpu_create_embedded_viewport_resources :: proc(renderer: ^WGPU_Renderer) -> string {
	if renderer == nil {
		return "embedded viewport renderer is unavailable"
	}
	for layer in 0 ..< ui.MAX_EMBEDDED_VIEWPORTS {
		depth_texture, depth_view, depth_err := wgpu_create_depth_texture(
			renderer,
			renderer.ui_viewport_widths[layer],
			renderer.ui_viewport_heights[layer],
		)
		if depth_err != "" {
			return depth_err
		}
		renderer.ui_viewport_depth_textures[layer] = depth_texture
		renderer.ui_viewport_depth_views[layer] = depth_view
		renderer.ui_viewport_uniform_buffers[layer] = wgpu.DeviceCreateBuffer(
			renderer.device,
			&wgpu.BufferDescriptor {
				label = "Scrapbot Embedded Viewport Uniform Buffer",
				usage = {.Uniform, .CopyDst},
				size = u64(size_of(WGPU_Render_Uniform)),
			},
		)
		if renderer.ui_viewport_uniform_buffers[layer] == nil {
			return "failed to create embedded viewport uniform buffer"
		}
		entries := [?]wgpu.BindGroupEntry {
			{
				binding = 0,
				buffer = renderer.ui_viewport_uniform_buffers[layer],
				offset = 0,
				size = u64(size_of(WGPU_Render_Uniform)),
			},
			{binding = 1, textureView = renderer.shadow_view},
			{binding = 2, sampler = renderer.shadow_sampler},
		}
		renderer.ui_viewport_bind_groups[layer] = wgpu.DeviceCreateBindGroup(
			renderer.device,
			&wgpu.BindGroupDescriptor {
				label = "Scrapbot Embedded Viewport Bind Group",
				layout = renderer.bind_group_layout,
				entryCount = uint(len(entries)),
				entries = raw_data(entries[:]),
			},
		)
		if renderer.ui_viewport_bind_groups[layer] == nil {
			return "failed to create embedded viewport bind group"
		}
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
		format = .RGBA8UnormSrgb,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment_state := wgpu.FragmentState {
		module = renderer.shader,
		entryPoint = "fs_main",
		targetCount = 1,
		targets = &color_target,
	}
	renderer.ui_viewport_pipeline = wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = "Scrapbot Embedded Viewport Pipeline",
			layout = renderer.pipeline_layout,
			vertex = {
				module = renderer.shader,
				entryPoint = "vs_main",
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
			fragment = &fragment_state,
		},
	)
	if renderer.ui_viewport_pipeline == nil {
		return "failed to create embedded viewport pipeline"
	}
	texture_chain := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_VIEWPORT_TEXTURE_SHADER,
	}
	texture_shader := wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &texture_chain,
			label = "Scrapbot Embedded Texture Preview Shader",
		},
	)
	if texture_shader == nil {
		return "failed to create embedded texture preview shader"
	}
	defer wgpu.ShaderModuleRelease(texture_shader)
	texture_layout_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
		{binding = 1, visibility = {.Fragment}, sampler = {type = .Filtering}},
	}
	renderer.ui_viewport_texture_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Embedded Texture Preview Bind Group Layout",
			entryCount = uint(len(texture_layout_entries)),
			entries = raw_data(texture_layout_entries[:]),
		},
	)
	if renderer.ui_viewport_texture_bind_group_layout == nil {
		return "failed to create embedded texture preview bind group layout"
	}
	renderer.ui_viewport_texture_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Embedded Texture Preview Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.ui_viewport_texture_bind_group_layout,
		},
	)
	if renderer.ui_viewport_texture_pipeline_layout == nil {
		return "failed to create embedded texture preview pipeline layout"
	}
	texture_fragment := wgpu.FragmentState {
		module = texture_shader,
		entryPoint = "fs_main",
		targetCount = 1,
		targets = &color_target,
	}
	renderer.ui_viewport_texture_pipeline = wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = "Scrapbot Embedded Texture Preview Pipeline",
			layout = renderer.ui_viewport_texture_pipeline_layout,
			vertex = {module = texture_shader, entryPoint = "vs_main"},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = .None},
			multisample = {count = 1, mask = 0xFFFF_FFFF},
			fragment = &texture_fragment,
		},
	)
	if renderer.ui_viewport_texture_pipeline == nil {
		return "failed to create embedded texture preview pipeline"
	}
	preview_desc, preview_err := resources.icosphere(0.75, 2)
	if preview_err != "" {
		return preview_err
	}
	defer delete(preview_desc.vertices)
	defer delete(preview_desc.indices)
	renderer.ui_viewport_preview_vertex_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Material Preview Vertices",
			usage = {.Vertex, .CopyDst},
			size = u64(len(preview_desc.vertices) * size_of(resources.Vertex)),
		},
	)
	renderer.ui_viewport_preview_index_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Material Preview Indices",
			usage = {.Index, .CopyDst},
			size = u64(len(preview_desc.indices) * size_of(u32)),
		},
	)
	if renderer.ui_viewport_preview_vertex_buffer == nil ||
	   renderer.ui_viewport_preview_index_buffer == nil {
		return "failed to create material preview geometry"
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.ui_viewport_preview_vertex_buffer,
		0,
		raw_data(preview_desc.vertices),
		uint(len(preview_desc.vertices) * size_of(resources.Vertex)),
	)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.ui_viewport_preview_index_buffer,
		0,
		raw_data(preview_desc.indices),
		uint(len(preview_desc.indices) * size_of(u32)),
	)
	renderer.ui_viewport_preview_index_count = u32(len(preview_desc.indices))
	return ""
}

wgpu_release_surface_depth :: proc(renderer: ^WGPU_Renderer) {
	if renderer.depth_view != nil {
		wgpu.TextureViewRelease(renderer.depth_view)
		renderer.depth_view = nil
	}
	if renderer.depth_texture != nil {
		wgpu.TextureRelease(renderer.depth_texture)
		renderer.depth_texture = nil
	}
}

wgpu_create_depth_texture :: proc(
	renderer: ^WGPU_Renderer,
	width, height: u32,
) -> (
	texture: wgpu.Texture,
	view: wgpu.TextureView,
	err: string,
) {
	texture = wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label = "Scrapbot Depth Texture",
			usage = {.RenderAttachment, .TextureBinding},
			dimension = ._2D,
			size = wgpu.Extent3D{width = width, height = height, depthOrArrayLayers = 1},
			format = .Depth24Plus,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	if texture == nil {
		return nil, nil, "failed to create wgpu depth texture"
	}

	view = wgpu.TextureCreateView(texture)
	if view == nil {
		wgpu.TextureRelease(texture)
		return nil, nil, "failed to create wgpu depth texture view"
	}

	return texture, view, ""
}

wgpu_configure_surface :: proc(renderer: ^WGPU_Renderer) -> (drawable: bool, err: string) {
	width, height, ok := platform.runtime_window_pixel_size()
	if !ok {
		return false, "failed to query SDL3 window pixel size"
	}
	if width <= 0 || height <= 0 {
		return false, ""
	}

	next_width := u32(width)
	next_height := u32(height)
	if renderer.configured && renderer.width == next_width && renderer.height == next_height {
		return true, ""
	}

	wgpu_release_surface_depth(renderer)

	surface_config := wgpu.SurfaceConfiguration {
		device = renderer.device,
		format = renderer.format,
		usage = {.RenderAttachment},
		width = next_width,
		height = next_height,
		alphaMode = renderer.alpha_mode,
		presentMode = renderer.present_mode,
	}
	wgpu.SurfaceConfigure(renderer.surface, &surface_config)
	renderer.width = next_width
	renderer.height = next_height
	renderer.configured = true

	renderer.depth_texture, renderer.depth_view, err = wgpu_create_depth_texture(
		renderer,
		next_width,
		next_height,
	)
	if err != "" {
		return false, err
	}
	return true, ""
}

wgpu_acquire_surface_texture :: proc(
	renderer: ^WGPU_Renderer,
	pump_events := true,
) -> (
	surface_texture: wgpu.SurfaceTexture,
	acquired, should_quit: bool,
) {
	for _ in 0 ..< 60 {
		surface_texture = wgpu.SurfaceGetCurrentTexture(renderer.surface)
		switch surface_texture.status {
			case .SuccessOptimal, .SuccessSuboptimal:
				return surface_texture, true, false
			case .Occluded, .Timeout:
				if !pump_events {
					return surface_texture, false, false
				}
				if platform.pump_runtime_window_events() {
					return surface_texture, false, true
				}
				wgpu.InstanceProcessEvents(renderer.instance)
				time.sleep(16 * time.Millisecond)
				continue
			case .Outdated, .Lost, .Error:
				return surface_texture, false, false
		}
	}

	return surface_texture, false, false
}
