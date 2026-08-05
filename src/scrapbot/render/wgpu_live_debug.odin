package render

import live_debug "../live_debug"
import wgpu "vendor:wgpu"

WGPU_Live_Debug_Capture :: struct {
	service: ^live_debug.Service,
	plan: live_debug.Capture_Frame_Plan,
	buffer: wgpu.Buffer,
	readback_size: u64,
	row_stride: u32,
	width: u32,
	height: u32,
	color_path: string,
}

wgpu_live_debug_prepare_capture :: proc(
	renderer: ^WGPU_Renderer,
	config: ^Run_Config,
	width, height: u32,
	copy_supported := true,
) -> WGPU_Live_Debug_Capture {
	if renderer == nil || config == nil || config.live_debug == nil {
		return {}
	}
	plan := live_debug.begin_capture_frame(config.live_debug)
	capture := WGPU_Live_Debug_Capture {
		service = config.live_debug,
		plan = plan,
		width = width,
		height = height,
	}
	if !live_debug.capture_artifact_requested(plan, .Color) {
		return capture
	}
	if !copy_supported {
		live_debug.capture_fail(
			config.live_debug,
			"the WGPU output surface does not support color readback",
		)
		return capture
	}
	capture.row_stride = align_to(width * 4, 256)
	capture.readback_size = u64(capture.row_stride) * u64(height)
	capture.buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor {
			label = "Scrapbot Live Debug Color Readback",
			usage = {.CopyDst, .MapRead},
			size = capture.readback_size,
		},
	)
	if capture.buffer == nil {
		live_debug.capture_fail(
			config.live_debug,
			"failed to create live debug color readback buffer",
		)
		return capture
	}
	path, path_err := live_debug.capture_artifact_path(plan, .Color)
	if path_err != "" {
		wgpu.BufferRelease(capture.buffer)
		capture.buffer = nil
		live_debug.capture_fail(config.live_debug, path_err)
		return capture
	}
	capture.color_path = path
	return capture
}

wgpu_live_debug_destroy_capture :: proc(capture: ^WGPU_Live_Debug_Capture) {
	if capture == nil {
		return
	}
	delete(capture.color_path)
	if capture.buffer != nil {
		wgpu.BufferRelease(capture.buffer)
	}
	capture^ = {}
}

wgpu_live_debug_encode_capture :: proc(
	capture: ^WGPU_Live_Debug_Capture,
	encoder: wgpu.CommandEncoder,
	texture: wgpu.Texture,
) {
	if capture == nil || capture.buffer == nil {
		return
	}
	wgpu.CommandEncoderCopyTextureToBuffer(
		encoder,
		&wgpu.TexelCopyTextureInfo{texture = texture, aspect = .All},
		&wgpu.TexelCopyBufferInfo {
			buffer = capture.buffer,
			layout = wgpu.TexelCopyBufferLayout {
				bytesPerRow = capture.row_stride,
				rowsPerImage = capture.height,
			},
		},
		&wgpu.Extent3D{width = capture.width, height = capture.height, depthOrArrayLayers = 1},
	)
}

wgpu_live_debug_finish_capture :: proc(
	renderer: ^WGPU_Renderer,
	capture: ^WGPU_Live_Debug_Capture,
) {
	if capture == nil || capture.buffer == nil {
		return
	}
	if write_err := wgpu_write_framegrab_readback(
		renderer,
		capture.buffer,
		capture.readback_size,
		capture.row_stride,
		capture.width,
		capture.height,
		0,
		0,
		capture.width,
		capture.height,
		capture.color_path,
	); write_err != "" {
		live_debug.capture_fail(capture.service, write_err)
	}
}
