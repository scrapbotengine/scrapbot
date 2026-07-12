package render

import "core:fmt"
import "core:math"
import "core:time"
import ecs "../ecs"
import platform "../platform"
import shared "../shared"
import resources "../resources"
import wgpu_sdl3 "vendor:wgpu/sdl3glue"
import "vendor:wgpu"

WGPU_RENDER_SHADER :: `
struct Render_Uniform {
	mvp: array<mat4x4<f32>, 64>,
	color: array<vec4<f32>, 64>,
};

@group(0) @binding(0)
var<uniform> render: Render_Uniform;

struct Vertex_Input {
	@location(0) position: vec3<f32>,
	@location(1) normal: vec3<f32>,
	@location(2) uv: vec2<f32>,
};

struct Vertex_Output {
	@builtin(position) position: vec4<f32>,
	@location(0) color: vec3<f32>,
};

@vertex
fn vs_main(input: Vertex_Input, @builtin(instance_index) instance_index: u32) -> Vertex_Output {
	var output: Vertex_Output;
	output.position = render.mvp[instance_index] * vec4<f32>(input.position, 1.0);
	output.color = render.color[instance_index].rgb;
	return output;
}

@fragment
fn fs_main(input: Vertex_Output) -> @location(0) vec4<f32> {
	return vec4<f32>(input.color, 1.0);
}
`

Vec3 :: shared.Vec3
Render_Instance :: shared.Render_Instance
Camera_Instance :: shared.Camera_Instance
Render_List :: shared.Render_List

Mat4 :: [16]f32

WGPU_MAX_INSTANCES :: 64

WGPU_Render_Uniform :: struct {
	mvp: [WGPU_MAX_INSTANCES]Mat4,
	color: [WGPU_MAX_INSTANCES][4]f32,
}

WGPU_Draw_Batch :: struct {
	geometry: shared.Geometry_Handle,
	material: shared.Material_Handle,
	first_instance: u32,
	instance_count: u32,
}

WGPU_Geometry_Cache :: struct {
	handle: shared.Geometry_Handle,
	version: u32,
	vertex_buffer: wgpu.Buffer,
	index_buffer: wgpu.Buffer,
	index_count: u32,
	valid: bool,
}

WGPU_Request_Adapter_State :: struct {
	completed: bool,
	status:  wgpu.RequestAdapterStatus,
	adapter: wgpu.Adapter,
	message: string,
}

WGPU_Request_Device_State :: struct {
	completed: bool,
	status:  wgpu.RequestDeviceStatus,
	device:  wgpu.Device,
	message: string,
}

WGPU_Buffer_Map_State :: struct {
	completed: bool,
	status:  wgpu.MapAsyncStatus,
	message: string,
}

WGPU_Renderer :: struct {
	instance:          wgpu.Instance,
	surface:           wgpu.Surface,
	adapter:           wgpu.Adapter,
	device:            wgpu.Device,
	queue:             wgpu.Queue,
	pipeline_layout:   wgpu.PipelineLayout,
	bind_group_layout: wgpu.BindGroupLayout,
	bind_group:        wgpu.BindGroup,
	shader:            wgpu.ShaderModule,
	pipeline:          wgpu.RenderPipeline,
	geometry_cache:    [64]WGPU_Geometry_Cache,
	geometry_cache_count: int,
	uniform_buffer:    wgpu.Buffer,
	depth_texture:     wgpu.Texture,
	depth_view:        wgpu.TextureView,
	format:            wgpu.TextureFormat,
	present_mode:      wgpu.PresentMode,
	alpha_mode:        wgpu.CompositeAlphaMode,
	width:             u32,
	height:            u32,
	configured:        bool,
}

WGPU_OFFSCREEN_WIDTH :: u32(1280)
WGPU_OFFSCREEN_HEIGHT :: u32(720)

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

wgpu_wait_for_adapter :: proc(instance: wgpu.Instance, state: ^WGPU_Request_Adapter_State) -> bool {
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

wgpu_init_renderer :: proc(use_surface: bool, offscreen_format := wgpu.TextureFormat.RGBA8Unorm) -> (renderer: WGPU_Renderer, err: string) {
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
			mode      = .AllowSpontaneos,
			callback  = wgpu_request_adapter_callback,
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

	device_state: WGPU_Request_Device_State
	wgpu.AdapterRequestDevice(
		renderer.adapter,
		&wgpu.DeviceDescriptor{label = "Scrapbot Device"},
		wgpu.RequestDeviceCallbackInfo {
			mode      = .AllowSpontaneos,
			callback  = wgpu_request_device_callback,
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

	if use_surface {
		capabilities, caps_status := wgpu.SurfaceGetCapabilities(renderer.surface, renderer.adapter)
		if caps_status != .Success || capabilities.formatCount == 0 || capabilities.presentModeCount == 0 || capabilities.alphaModeCount == 0 {
			return renderer, "failed to query wgpu surface capabilities"
		}
		defer wgpu.SurfaceCapabilitiesFreeMembers(capabilities)

		renderer.format = capabilities.formats[0]
		renderer.present_mode = capabilities.presentModes[0]
		renderer.alpha_mode = capabilities.alphaModes[0]
	} else {
		renderer.format = offscreen_format
	}

	if err = wgpu_create_render_pipeline(&renderer); err != "" {
		return renderer, err
	}

	return renderer, ""
}

wgpu_destroy_renderer :: proc(renderer: ^WGPU_Renderer) {
	if renderer.configured {
		wgpu.SurfaceUnconfigure(renderer.surface)
	}
	if renderer.pipeline != nil {
		wgpu.RenderPipelineRelease(renderer.pipeline)
	}
	if renderer.uniform_buffer != nil {
		wgpu.BufferRelease(renderer.uniform_buffer)
	}
	for &cached in renderer.geometry_cache[:renderer.geometry_cache_count] {
		if cached.vertex_buffer != nil {wgpu.BufferRelease(cached.vertex_buffer)}
		if cached.index_buffer != nil {wgpu.BufferRelease(cached.index_buffer)}
	}
	if renderer.bind_group != nil {
		wgpu.BindGroupRelease(renderer.bind_group)
	}
	if renderer.bind_group_layout != nil {
		wgpu.BindGroupLayoutRelease(renderer.bind_group_layout)
	}
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
		chain = wgpu.ChainedStruct {
			sType = .ShaderSourceWGSL,
		},
		code = WGPU_RENDER_SHADER,
	}
	renderer.shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &shader_source,
			label       = "Scrapbot Render Shader",
		},
	)
	if renderer.shader == nil {
		return "failed to create wgpu shader module"
	}

	bind_group_layout_entry := wgpu.BindGroupLayoutEntry {
		binding    = 0,
		visibility = {.Vertex},
		buffer = wgpu.BufferBindingLayout {
			type           = .Uniform,
			minBindingSize = u64(size_of(WGPU_Render_Uniform)),
		},
	}
	renderer.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label      = "Scrapbot Render Bind Group Layout",
			entryCount = 1,
			entries    = &bind_group_layout_entry,
		},
	)
	if renderer.bind_group_layout == nil {
		return "failed to create wgpu bind group layout"
	}

	renderer.pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label                = "Scrapbot Render Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts     = &renderer.bind_group_layout,
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
			size  = u64(size_of(WGPU_Render_Uniform)),
		},
	)
	if renderer.uniform_buffer == nil {
		return "failed to create wgpu uniform buffer"
	}

	bind_group_entry := wgpu.BindGroupEntry {
		binding = 0,
		buffer  = renderer.uniform_buffer,
		offset  = 0,
		size    = u64(size_of(WGPU_Render_Uniform)),
	}
	renderer.bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label      = "Scrapbot Render Bind Group",
			layout     = renderer.bind_group_layout,
			entryCount = 1,
			entries    = &bind_group_entry,
		},
	)
	if renderer.bind_group == nil {
		return "failed to create wgpu bind group"
	}

	vertex_attributes := [?]wgpu.VertexAttribute {
		{format = .Float32x3, offset = 0, shaderLocation = 0},
		{format = .Float32x3, offset = 12, shaderLocation = 1},
		{format = .Float32x2, offset = 24, shaderLocation = 2},
	}
	vertex_buffer_layout := wgpu.VertexBufferLayout {
		stepMode       = .Vertex,
		arrayStride    = u64(size_of(resources.Vertex)),
		attributeCount = uint(len(vertex_attributes)),
		attributes     = raw_data(vertex_attributes[:]),
	}
	color_target := wgpu.ColorTargetState {
		format    = renderer.format,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment_state := wgpu.FragmentState {
		module      = renderer.shader,
		entryPoint  = "fs_main",
		targetCount = 1,
		targets     = &color_target,
	}
	renderer.pipeline = wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label  = "Scrapbot Render Pipeline",
			layout = renderer.pipeline_layout,
			vertex = wgpu.VertexState {
				module      = renderer.shader,
				entryPoint  = "vs_main",
				bufferCount = 1,
				buffers     = &vertex_buffer_layout,
			},
			primitive = wgpu.PrimitiveState {
				topology  = .TriangleList,
				frontFace = .CCW,
				cullMode  = .None,
			},
			depthStencil = &wgpu.DepthStencilState {
				format            = .Depth24Plus,
				depthWriteEnabled = .True,
				depthCompare      = .Less,
			},
			multisample = wgpu.MultisampleState {
				count = 1,
				mask  = 0xFFFF_FFFF,
			},
			fragment = &fragment_state,
		},
	)
	if renderer.pipeline == nil {
		return "failed to create wgpu render pipeline"
	}

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

wgpu_create_depth_texture :: proc(renderer: ^WGPU_Renderer, width, height: u32) -> (texture: wgpu.Texture, view: wgpu.TextureView, err: string) {
	texture = wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label  = "Scrapbot Depth Texture",
			usage  = {.RenderAttachment},
			dimension = ._2D,
			size = wgpu.Extent3D {
				width              = width,
				height             = height,
				depthOrArrayLayers = 1,
			},
			format        = .Depth24Plus,
			mipLevelCount = 1,
			sampleCount   = 1,
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
		device      = renderer.device,
		format      = renderer.format,
		usage       = {.RenderAttachment},
		width       = next_width,
		height      = next_height,
		alphaMode   = renderer.alpha_mode,
		presentMode = renderer.present_mode,
	}
	wgpu.SurfaceConfigure(renderer.surface, &surface_config)
	renderer.width = next_width
	renderer.height = next_height
	renderer.configured = true

	renderer.depth_texture, renderer.depth_view, err = wgpu_create_depth_texture(renderer, next_width, next_height)
	if err != "" {
		return false, err
	}
	return true, ""
}

wgpu_acquire_surface_texture :: proc(
	renderer: ^WGPU_Renderer,
) -> (surface_texture: wgpu.SurfaceTexture, acquired, should_quit: bool) {
	for _ in 0 ..< 60 {
		surface_texture = wgpu.SurfaceGetCurrentTexture(renderer.surface)
		switch surface_texture.status {
		case .SuccessOptimal, .SuccessSuboptimal:
			return surface_texture, true, false
		case .Occluded, .Timeout:
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

wgpu_prepare_draw_batches :: proc(renderer: ^WGPU_Renderer, render_list: ^Render_List, registry: ^resources.Registry, width, height: u32) -> ([64]WGPU_Draw_Batch, int) {
	uniform: WGPU_Render_Uniform
	batches: [64]WGPU_Draw_Batch
	batch_count, instance_count := 0, 0
	for candidate in render_list.instances {
		already_batched := false
		for i in 0..<batch_count {if batches[i].geometry == candidate.geometry.handle && batches[i].material == candidate.material.handle {already_batched = true; break}}
		if already_batched {continue}
		batch := &batches[batch_count]
		batch.geometry = candidate.geometry.handle; batch.material = candidate.material.handle; batch.first_instance = u32(instance_count)
		material, material_ok := resources.get_material(registry, candidate.material.handle)
		if !material_ok {continue}
		for instance in render_list.instances {
			if instance.geometry.handle != batch.geometry || instance.material.handle != batch.material {continue}
			if instance_count >= WGPU_MAX_INSTANCES {break}
			uniform.mvp[instance_count] = wgpu_build_mvp(instance, render_list.camera, render_list.has_camera, width, height)
			color := material.desc.base_color
			uniform.color[instance_count] = {color.x,color.y,color.z,color.w}
			instance_count += 1; batch.instance_count += 1
		}
		if batch.instance_count > 0 {batch_count += 1}
	}
	if instance_count == 0 {
		return batches, 0
	}

	wgpu.QueueWriteBuffer(renderer.queue, renderer.uniform_buffer, 0, &uniform, uint(size_of(WGPU_Render_Uniform)))
	return batches, batch_count
}

wgpu_geometry_cache :: proc(renderer: ^WGPU_Renderer, registry: ^resources.Registry, handle: shared.Geometry_Handle) -> (^WGPU_Geometry_Cache, string) {
	geometry, ok := resources.get_geometry(registry, handle)
	if !ok {return nil, "render geometry handle is stale"}
	cache_index := -1
	for i in 0..<renderer.geometry_cache_count {if renderer.geometry_cache[i].handle == handle {cache_index = i; break}}
	if cache_index < 0 {
		if renderer.geometry_cache_count >= len(renderer.geometry_cache) {return nil, "too many cached geometries"}
		cache_index = renderer.geometry_cache_count; renderer.geometry_cache_count += 1
	}
	cached := &renderer.geometry_cache[cache_index]
	if cached.valid && cached.version == geometry.version {return cached, ""}
	if cached.vertex_buffer != nil {wgpu.BufferRelease(cached.vertex_buffer)}
	if cached.index_buffer != nil {wgpu.BufferRelease(cached.index_buffer)}
	cached^ = {handle = handle, version = geometry.version, index_count = u32(len(geometry.indices))}
	cached.vertex_buffer = wgpu.DeviceCreateBufferWithData(renderer.device, &wgpu.BufferWithDataDescriptor{label="Scrapbot Geometry Vertices", usage={.Vertex}}, geometry.vertices)
	cached.index_buffer = wgpu.DeviceCreateBufferWithData(renderer.device, &wgpu.BufferWithDataDescriptor{label="Scrapbot Geometry Indices", usage={.Index}}, geometry.indices)
	if cached.vertex_buffer == nil || cached.index_buffer == nil {return nil, "failed to upload geometry buffers"}
	cached.valid = true
	return cached, ""
}

wgpu_encode_render_pass :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	color_view: wgpu.TextureView,
	depth_view: wgpu.TextureView,
	batches: []WGPU_Draw_Batch,
	registry: ^resources.Registry,
	label: string,
) -> string {
	color_attachment := wgpu.RenderPassColorAttachment {
		view       = color_view,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp     = .Clear,
		storeOp    = .Store,
		clearValue = wgpu.Color{0.08, 0.10, 0.12, 1.0},
	}
	depth_attachment := wgpu.RenderPassDepthStencilAttachment {
		view            = depth_view,
		depthLoadOp     = .Clear,
		depthStoreOp    = .Store,
		depthClearValue = 1.0,
		stencilLoadOp   = .Undefined,
		stencilStoreOp  = .Undefined,
	}
	render_pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label                  = label,
			colorAttachmentCount   = 1,
			colorAttachments       = &color_attachment,
			depthStencilAttachment = &depth_attachment,
		},
	)
	if render_pass == nil {
		return "failed to begin wgpu render pass"
	}
	defer wgpu.RenderPassEncoderRelease(render_pass)

	if len(batches) > 0 {
		wgpu.RenderPassEncoderSetPipeline(render_pass, renderer.pipeline)
		wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, renderer.bind_group)
		for batch in batches {
			cached, cache_err := wgpu_geometry_cache(renderer, registry, batch.geometry)
			if cache_err != "" {return cache_err}
			wgpu.RenderPassEncoderSetVertexBuffer(render_pass, 0, cached.vertex_buffer, 0, wgpu.WHOLE_SIZE)
			wgpu.RenderPassEncoderSetIndexBuffer(render_pass, cached.index_buffer, .Uint32, 0, wgpu.WHOLE_SIZE)
			wgpu.RenderPassEncoderDrawIndexed(render_pass, cached.index_count, batch.instance_count, 0, 0, batch.first_instance)
		}
	}

	wgpu.RenderPassEncoderEnd(render_pass)
	return ""
}

wgpu_draw_frame :: proc(renderer: ^WGPU_Renderer, world: ^World, config: ^Run_Config) -> (presented, should_quit: bool, err: string) {
	drawable, configure_err := wgpu_configure_surface(renderer)
	if configure_err != "" || !drawable {
		return false, false, configure_err
	}

	surface_texture, acquired_texture, acquire_should_quit := wgpu_acquire_surface_texture(renderer)
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
		return false, false, fmt.tprintf("failed to acquire wgpu surface texture: %v", surface_texture.status)
	}
	texture := surface_texture.texture
	if texture == nil {
		return false, false, "wgpu surface returned no texture"
	}

	view := wgpu.TextureCreateView(texture)
	if view == nil {
		wgpu.TextureRelease(texture)
		return false, false, "failed to create wgpu texture view"
	}
	defer wgpu.TextureViewRelease(view)
	defer wgpu.TextureRelease(texture)

	if err = run_frame_system(config, world, 1.0 / 60.0); err != "" {
		return false, false, err
	}
	render_list := ecs.build_resource_render_list(world, config.resource_registry)
	defer ecs.destroy_render_list(&render_list)
	batches, batch_count := wgpu_prepare_draw_batches(renderer, &render_list, config.resource_registry, renderer.width, renderer.height)
	if config.stats != nil {config.stats.draw_batches = batch_count}

	encoder := wgpu.DeviceCreateCommandEncoder(renderer.device, &wgpu.CommandEncoderDescriptor{label = "Scrapbot Render Encoder"})
	if encoder == nil {
		return false, false, "failed to create wgpu command encoder"
	}
	defer wgpu.CommandEncoderRelease(encoder)

	if err = wgpu_encode_render_pass(renderer, encoder, view, renderer.depth_view, batches[:batch_count], config.resource_registry, "Scrapbot Geometry Pass"); err != "" {
		return false, false, err
	}

	command_buffer := wgpu.CommandEncoderFinish(encoder, &wgpu.CommandBufferDescriptor{label = "Scrapbot Render Commands"})
	if command_buffer == nil {
		return false, false, "failed to finish wgpu command encoder"
	}
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(renderer.queue, []wgpu.CommandBuffer{command_buffer})
	if wgpu.SurfacePresent(renderer.surface) != .Success {
		return false, false, "failed to present wgpu surface"
	}

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
	if config != nil {
		if err := run_frame_system(config, world, 1.0 / 60.0); err != "" {
			return err
		}
	}
	render_list := ecs.build_resource_render_list(world, config.resource_registry)
	defer ecs.destroy_render_list(&render_list)
	batches, batch_count := wgpu_prepare_draw_batches(renderer, &render_list, config.resource_registry, width, height)
	if config != nil && config.stats != nil {config.stats.draw_batches = batch_count}

	encoder := wgpu.DeviceCreateCommandEncoder(renderer.device, &wgpu.CommandEncoderDescriptor{label = "Scrapbot Headless Render Encoder"})
	if encoder == nil {
		return "failed to create wgpu command encoder"
	}
	defer wgpu.CommandEncoderRelease(encoder)

	if err := wgpu_encode_render_pass(renderer, encoder, view, depth_view, batches[:batch_count], config.resource_registry, "Scrapbot Headless Geometry Pass"); err != "" {
		return err
	}

	if readback != nil {
		wgpu.CommandEncoderCopyTextureToBuffer(
			encoder,
			&wgpu.TexelCopyTextureInfo {
				texture = texture,
				aspect = .All,
			},
			&wgpu.TexelCopyBufferInfo {
				buffer = readback,
				layout = wgpu.TexelCopyBufferLayout {
					bytesPerRow  = row_stride,
					rowsPerImage = height,
				},
			},
			&wgpu.Extent3D {
				width              = width,
				height             = height,
				depthOrArrayLayers = 1,
			},
		)
	}

	command_buffer := wgpu.CommandEncoderFinish(encoder, &wgpu.CommandBufferDescriptor{label = "Scrapbot Headless Render Commands"})
	if command_buffer == nil {
		return "failed to finish wgpu command encoder"
	}
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(renderer.queue, []wgpu.CommandBuffer{command_buffer})
	return ""
}

wgpu_run_headless :: proc(world: ^World, config: ^Run_Config) -> string {
	renderer, init_err := wgpu_init_renderer(true)
	defer wgpu_destroy_renderer(&renderer)
	if init_err != "" {
		return init_err
	}

	width := WGPU_OFFSCREEN_WIDTH
	height := WGPU_OFFSCREEN_HEIGHT
	row_bytes := width * 4
	row_stride := align_to(row_bytes, 256)
	readback_size := u64(row_stride * height)

	texture := wgpu.DeviceCreateTexture(
		renderer.device,
		&wgpu.TextureDescriptor {
			label  = "Scrapbot Headless Frame Texture",
			usage  = {.RenderAttachment, .CopySrc},
			dimension = ._2D,
			size = wgpu.Extent3D {
				width              = width,
				height             = height,
				depthOrArrayLayers = 1,
			},
			format     = renderer.format,
			mipLevelCount = 1,
			sampleCount   = 1,
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

	readback := wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Headless Readback Buffer",
			usage = {.CopyDst, .MapRead},
			size  = readback_size,
		},
	)
	if readback == nil {
		return "failed to create wgpu headless readback buffer"
	}
	defer wgpu.BufferRelease(readback)

	frame_count := config.max_frames
	if frame_count == 0 {
		frame_count = 1
	}
	for index in 0 ..< frame_count {
		capture := index == frame_count - 1
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
			return err
		}
	}

	map_state: WGPU_Buffer_Map_State
	wgpu.BufferMapAsync(
		readback,
		{.Read},
		0,
		uint(readback_size),
		wgpu.BufferMapCallbackInfo {
			mode      = .AllowSpontaneos,
			callback  = wgpu_buffer_map_callback,
			userdata1 = &map_state,
		},
	)
	if !wgpu_wait_for_buffer_map(renderer.instance, &map_state) {
		message := map_state.message
		if message == "" {
			message = "request timed out"
		}
		return fmt.tprintf("failed to map wgpu readback buffer: %s", message)
	}
	defer wgpu.BufferUnmap(readback)

	mapped := wgpu.BufferGetMappedRange(readback, 0, uint(readback_size))
	pixels := make([]u8, int(row_bytes * height))
	defer delete(pixels)
	for y in 0 ..< int(height) {
		dst := y * int(row_bytes)
		src := y * int(row_stride)
		copy_framegrab_row(pixels[dst:dst + int(row_bytes)], mapped[src:src + int(row_bytes)], renderer.format)
	}

	return write_png_rgba8(config.framegrab_path, pixels, width, height)
}

wgpu_build_mvp :: proc(instance: Render_Instance, camera: Camera_Instance, has_camera: bool, width, height: u32) -> Mat4 {
	transform := instance.transform
	aspect := f32(16.0 / 9.0)
	if width > 0 && height > 0 {
		aspect = f32(width) / f32(height)
	}

	eye := Vec3{0, 2, 6}
	fov := f32(60)
	near := f32(0.1)
	far := f32(100)
	if has_camera {
		eye = camera.transform.position
		if camera.camera.fov > 0 {
			fov = camera.camera.fov
		}
		if camera.camera.near > 0 {
			near = camera.camera.near
		}
		if camera.camera.far > near {
			far = camera.camera.far
		}
	}

	model := mat4_mul(
		mat4_translate(transform.position),
		mat4_mul(
			mat4_rotate_z(transform.rotation.z),
			mat4_mul(
				mat4_rotate_y(transform.rotation.y),
				mat4_mul(mat4_rotate_x(transform.rotation.x), mat4_scale(transform.scale)),
			),
		),
	)
	view := mat4_look_at(eye, Vec3{0, 0, 0}, Vec3{0, 1, 0})
	projection := mat4_perspective(math.to_radians(fov), aspect, near, far)
	return mat4_mul(projection, mat4_mul(view, model))
}

mat4_identity :: proc() -> Mat4 {
	return Mat4 {
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
}

mat4_mul :: proc(a, b: Mat4) -> Mat4 {
	result: Mat4
	for column in 0 ..< 4 {
		for row in 0 ..< 4 {
			sum: f32
			for index in 0 ..< 4 {
				sum += a[index * 4 + row] * b[column * 4 + index]
			}
			result[column * 4 + row] = sum
		}
	}
	return result
}

mat4_translate :: proc(value: Vec3) -> Mat4 {
	result := mat4_identity()
	result[12] = value.x
	result[13] = value.y
	result[14] = value.z
	return result
}

mat4_scale :: proc(value: Vec3) -> Mat4 {
	result := mat4_identity()
	result[0] = value.x
	result[5] = value.y
	result[10] = value.z
	return result
}

mat4_rotate_x :: proc(angle: f32) -> Mat4 {
	c := math.cos(angle)
	s := math.sin(angle)
	result := mat4_identity()
	result[5] = c
	result[6] = s
	result[9] = -s
	result[10] = c
	return result
}

mat4_rotate_y :: proc(angle: f32) -> Mat4 {
	c := math.cos(angle)
	s := math.sin(angle)
	result := mat4_identity()
	result[0] = c
	result[2] = -s
	result[8] = s
	result[10] = c
	return result
}

mat4_rotate_z :: proc(angle: f32) -> Mat4 {
	c := math.cos(angle)
	s := math.sin(angle)
	result := mat4_identity()
	result[0] = c
	result[1] = s
	result[4] = -s
	result[5] = c
	return result
}

mat4_perspective :: proc(fovy_radians, aspect, near, far: f32) -> Mat4 {
	f := 1 / math.tan(fovy_radians / 2)
	result: Mat4
	result[0] = f / aspect
	result[5] = f
	result[10] = far / (near - far)
	result[11] = -1
	result[14] = (far * near) / (near - far)
	return result
}

mat4_look_at :: proc(eye, target, up: Vec3) -> Mat4 {
	forward := vec3_normalize(vec3_sub(target, eye))
	side := vec3_normalize(vec3_cross(forward, up))
	true_up := vec3_cross(side, forward)

	result := mat4_identity()
	result[0] = side.x
	result[1] = true_up.x
	result[2] = -forward.x
	result[4] = side.y
	result[5] = true_up.y
	result[6] = -forward.y
	result[8] = side.z
	result[9] = true_up.z
	result[10] = -forward.z
	result[12] = -vec3_dot(side, eye)
	result[13] = -vec3_dot(true_up, eye)
	result[14] = vec3_dot(forward, eye)
	return result
}

vec3_sub :: proc(a, b: Vec3) -> Vec3 {
	return Vec3{a.x - b.x, a.y - b.y, a.z - b.z}
}

vec3_cross :: proc(a, b: Vec3) -> Vec3 {
	return Vec3 {
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x,
	}
}

vec3_dot :: proc(a, b: Vec3) -> f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

vec3_normalize :: proc(value: Vec3) -> Vec3 {
	length := math.sqrt(vec3_dot(value, value))
	if length <= 0 {
		return Vec3{}
	}
	return Vec3{value.x / length, value.y / length, value.z / length}
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
	renderer, init_err := wgpu_init_renderer(true)
	defer wgpu_destroy_renderer(&renderer)
	if init_err != "" {
		return init_err
	}

	frame_count: u32
	for config.max_frames == 0 || frame_count < config.max_frames {
		if platform.pump_runtime_window_events() {
			break
		}
		wgpu.InstanceProcessEvents(renderer.instance)

		_, should_quit, draw_err := wgpu_draw_frame(&renderer, world, config)
		if draw_err != "" {
			return draw_err
		}
		if should_quit {
			break
		}

		frame_count += 1
		time.sleep(16 * time.Millisecond)
	}

	return ""
}
