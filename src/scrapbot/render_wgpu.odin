package scrapbot

import "core:fmt"
import "core:time"
import wgpu_sdl3 "vendor:wgpu/sdl3glue"
import "vendor:wgpu"

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

wgpu_acquire_surface_texture :: proc(
	instance: wgpu.Instance,
	surface: wgpu.Surface,
) -> (surface_texture: wgpu.SurfaceTexture, ok: bool) {
	for _ in 0 ..< 60 {
		surface_texture = wgpu.SurfaceGetCurrentTexture(surface)
		switch surface_texture.status {
		case .SuccessOptimal, .SuccessSuboptimal:
			return surface_texture, true
		case .Occluded, .Timeout:
			pump_runtime_window_events()
			wgpu.InstanceProcessEvents(instance)
			time.sleep(16 * time.Millisecond)
			continue
		case .Outdated, .Lost, .Error:
			return surface_texture, false
		}
	}

	return surface_texture, false
}

wgpu_clear_window :: proc(frame: Render_Frame) -> string {
	if runtime_window == nil {
		return "wgpu renderer requires an SDL3 window"
	}

	instance := wgpu.CreateInstance()
	if instance == nil {
		return "failed to create wgpu instance"
	}
	defer wgpu.InstanceRelease(instance)

	surface := wgpu_sdl3.GetSurface(instance, runtime_window)
	if surface == nil {
		return "failed to create wgpu SDL3 surface"
	}
	defer wgpu.SurfaceRelease(surface)

	adapter_state: WGPU_Request_Adapter_State
	adapter_options := wgpu.RequestAdapterOptions {
		powerPreference   = .HighPerformance,
		compatibleSurface = surface,
	}
	wgpu.InstanceRequestAdapter(
		instance,
		&adapter_options,
		wgpu.RequestAdapterCallbackInfo {
			mode      = .AllowSpontaneos,
			callback  = wgpu_request_adapter_callback,
			userdata1 = &adapter_state,
		},
	)
	if !wgpu_wait_for_adapter(instance, &adapter_state) {
		message := adapter_state.message
		if message == "" {
			message = "request timed out"
		}
		return fmt.tprintf("failed to request wgpu adapter: %s", message)
	}
	adapter := adapter_state.adapter
	defer wgpu.AdapterRelease(adapter)

	device_state: WGPU_Request_Device_State
	wgpu.AdapterRequestDevice(
		adapter,
		&wgpu.DeviceDescriptor{label = "Scrapbot Device"},
		wgpu.RequestDeviceCallbackInfo {
			mode      = .AllowSpontaneos,
			callback  = wgpu_request_device_callback,
			userdata1 = &device_state,
		},
	)
	if !wgpu_wait_for_device(instance, &device_state) {
		message := device_state.message
		if message == "" {
			message = "request timed out"
		}
		return fmt.tprintf("failed to request wgpu device: %s", message)
	}
	device := device_state.device
	defer wgpu.DeviceRelease(device)

	queue := wgpu.DeviceGetQueue(device)
	if queue == nil {
		return "failed to get wgpu queue"
	}
	defer wgpu.QueueRelease(queue)

	capabilities, caps_status := wgpu.SurfaceGetCapabilities(surface, adapter)
	if caps_status != .Success || capabilities.formatCount == 0 || capabilities.presentModeCount == 0 || capabilities.alphaModeCount == 0 {
		return "failed to query wgpu surface capabilities"
	}
	defer wgpu.SurfaceCapabilitiesFreeMembers(capabilities)

	format := capabilities.formats[0]
	present_mode := capabilities.presentModes[0]
	alpha_mode := capabilities.alphaModes[0]

	surface_config := wgpu.SurfaceConfiguration {
		device      = device,
		format      = format,
		usage       = {.RenderAttachment},
		width       = 1280,
		height      = 720,
		alphaMode   = alpha_mode,
		presentMode = present_mode,
	}
	wgpu.SurfaceConfigure(surface, &surface_config)
	defer wgpu.SurfaceUnconfigure(surface)

	surface_texture, acquired_texture := wgpu_acquire_surface_texture(instance, surface)
	if !acquired_texture {
		return fmt.tprintf("failed to acquire wgpu surface texture: %v", surface_texture.status)
	}
	texture := surface_texture.texture
	if texture == nil {
		return "wgpu surface returned no texture"
	}

	view := wgpu.TextureCreateView(texture)
	if view == nil {
		wgpu.TextureRelease(texture)
		return "failed to create wgpu texture view"
	}
	defer wgpu.TextureViewRelease(view)
	defer wgpu.TextureRelease(texture)

	encoder := wgpu.DeviceCreateCommandEncoder(device, &wgpu.CommandEncoderDescriptor{label = "Scrapbot Clear Encoder"})
	if encoder == nil {
		return "failed to create wgpu command encoder"
	}
	defer wgpu.CommandEncoderRelease(encoder)

	clear_color := wgpu.Color{0.08, 0.10, 0.12, 1.0}
	color_attachment := wgpu.RenderPassColorAttachment {
		view       = view,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp     = .Clear,
		storeOp    = .Store,
		clearValue = clear_color,
	}
	render_pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label                = "Scrapbot Clear Pass",
			colorAttachmentCount = 1,
			colorAttachments     = &color_attachment,
		},
	)
	if render_pass == nil {
		return "failed to begin wgpu render pass"
	}
	wgpu.RenderPassEncoderEnd(render_pass)
	wgpu.RenderPassEncoderRelease(render_pass)

	command_buffer := wgpu.CommandEncoderFinish(encoder, &wgpu.CommandBufferDescriptor{label = "Scrapbot Clear Commands"})
	if command_buffer == nil {
		return "failed to finish wgpu command encoder"
	}
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(queue, []wgpu.CommandBuffer{command_buffer})
	if wgpu.SurfacePresent(surface) != .Success {
		return "failed to present wgpu surface"
	}

	return ""
}
