package render

import "core:fmt"
import "core:time"
import platform "../platform"
import wgpu_sdl3 "vendor:wgpu/sdl3glue"
import "vendor:wgpu"

WGPU_TRIANGLE_SHADER :: `
@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> @builtin(position) vec4<f32> {
	var positions = array<vec2<f32>, 3>(
		vec2<f32>(0.0, 0.6),
		vec2<f32>(-0.65, -0.45),
		vec2<f32>(0.65, -0.45),
	);

	let position = positions[vertex_index];
	return vec4<f32>(position, 0.0, 1.0);
}

@fragment
fn fs_main() -> @location(0) vec4<f32> {
	return vec4<f32>(1.0, 0.42, 0.12, 1.0);
}
`

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
	instance:        wgpu.Instance,
	surface:         wgpu.Surface,
	adapter:         wgpu.Adapter,
	device:          wgpu.Device,
	queue:           wgpu.Queue,
	pipeline_layout: wgpu.PipelineLayout,
	shader:          wgpu.ShaderModule,
	pipeline:        wgpu.RenderPipeline,
	format:          wgpu.TextureFormat,
	present_mode:    wgpu.PresentMode,
	alpha_mode:      wgpu.CompositeAlphaMode,
	width:           u32,
	height:          u32,
	configured:      bool,
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

	if err = wgpu_create_triangle_pipeline(&renderer); err != "" {
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

wgpu_create_triangle_pipeline :: proc(renderer: ^WGPU_Renderer) -> string {
	shader_source := wgpu.ShaderSourceWGSL {
		chain = wgpu.ChainedStruct {
			sType = .ShaderSourceWGSL,
		},
		code = WGPU_TRIANGLE_SHADER,
	}
	renderer.shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &shader_source,
			label       = "Scrapbot Triangle Shader",
		},
	)
	if renderer.shader == nil {
		return "failed to create wgpu shader module"
	}

	renderer.pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Triangle Pipeline Layout",
		},
	)
	if renderer.pipeline_layout == nil {
		return "failed to create wgpu pipeline layout"
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
			label  = "Scrapbot Triangle Pipeline",
			layout = renderer.pipeline_layout,
			vertex = wgpu.VertexState {
				module     = renderer.shader,
				entryPoint = "vs_main",
			},
			primitive = wgpu.PrimitiveState {
				topology  = .TriangleList,
				frontFace = .CCW,
				cullMode  = .None,
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

wgpu_draw_triangle_frame :: proc(renderer: ^WGPU_Renderer) -> (presented, should_quit: bool, err: string) {
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

	encoder := wgpu.DeviceCreateCommandEncoder(renderer.device, &wgpu.CommandEncoderDescriptor{label = "Scrapbot Triangle Encoder"})
	if encoder == nil {
		return false, false, "failed to create wgpu command encoder"
	}
	defer wgpu.CommandEncoderRelease(encoder)

	color_attachment := wgpu.RenderPassColorAttachment {
		view       = view,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp     = .Clear,
		storeOp    = .Store,
		clearValue = wgpu.Color{0.08, 0.10, 0.12, 1.0},
	}
	render_pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label                = "Scrapbot Triangle Pass",
			colorAttachmentCount = 1,
			colorAttachments     = &color_attachment,
		},
	)
	if render_pass == nil {
		return false, false, "failed to begin wgpu render pass"
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, renderer.pipeline)
	wgpu.RenderPassEncoderDraw(render_pass, 3, 1, 0, 0)
	wgpu.RenderPassEncoderEnd(render_pass)
	wgpu.RenderPassEncoderRelease(render_pass)

	command_buffer := wgpu.CommandEncoderFinish(encoder, &wgpu.CommandBufferDescriptor{label = "Scrapbot Triangle Commands"})
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
	texture: wgpu.Texture,
	view: wgpu.TextureView,
	readback: wgpu.Buffer = nil,
	row_stride: u32 = 0,
	width: u32 = 0,
	height: u32 = 0,
) -> string {
	encoder := wgpu.DeviceCreateCommandEncoder(renderer.device, &wgpu.CommandEncoderDescriptor{label = "Scrapbot Headless Triangle Encoder"})
	if encoder == nil {
		return "failed to create wgpu command encoder"
	}
	defer wgpu.CommandEncoderRelease(encoder)

	color_attachment := wgpu.RenderPassColorAttachment {
		view       = view,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp     = .Clear,
		storeOp    = .Store,
		clearValue = wgpu.Color{0.08, 0.10, 0.12, 1.0},
	}
	render_pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label                = "Scrapbot Headless Triangle Pass",
			colorAttachmentCount = 1,
			colorAttachments     = &color_attachment,
		},
	)
	if render_pass == nil {
		return "failed to begin wgpu render pass"
	}
	wgpu.RenderPassEncoderSetPipeline(render_pass, renderer.pipeline)
	wgpu.RenderPassEncoderDraw(render_pass, 3, 1, 0, 0)
	wgpu.RenderPassEncoderEnd(render_pass)
	wgpu.RenderPassEncoderRelease(render_pass)

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

	command_buffer := wgpu.CommandEncoderFinish(encoder, &wgpu.CommandBufferDescriptor{label = "Scrapbot Headless Triangle Commands"})
	if command_buffer == nil {
		return "failed to finish wgpu command encoder"
	}
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(renderer.queue, []wgpu.CommandBuffer{command_buffer})
	return ""
}

wgpu_run_headless :: proc(frame: Render_Frame, max_frames: u32, framegrab_path: string) -> string {
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

	frame_count := max_frames
	if frame_count == 0 {
		frame_count = 1
	}
	for index in 0 ..< frame_count {
		capture := index == frame_count - 1
		err := wgpu_render_offscreen_frame(
			&renderer,
			texture,
			view,
			readback if capture else nil,
			row_stride if capture else 0,
			width if capture else 0,
			height if capture else 0,
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

	return write_png_rgba8(framegrab_path, pixels, width, height)
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

wgpu_run_window :: proc(frame: Render_Frame, max_frames: u32) -> string {
	renderer, init_err := wgpu_init_renderer(true)
	defer wgpu_destroy_renderer(&renderer)
	if init_err != "" {
		return init_err
	}

	frame_count: u32
	for max_frames == 0 || frame_count < max_frames {
		if platform.pump_runtime_window_events() {
			break
		}
		wgpu.InstanceProcessEvents(renderer.instance)

		_, should_quit, draw_err := wgpu_draw_triangle_frame(&renderer)
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
