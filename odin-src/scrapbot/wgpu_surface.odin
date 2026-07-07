package main

import "core:c"

WGPU_SURFACE_CREATE_ERROR :: "create_surface"
WGPU_SURFACE_CAPABILITIES_ERROR :: "surface_capabilities"
WGPU_SURFACE_UNSUPPORTED_USAGE_ERROR :: "surface_unsupported_usage"
WGPU_SURFACE_CURRENT_TEXTURE_ERROR :: "surface_current_texture"
WGPU_SURFACE_PRESENT_ERROR :: "surface_present"

WGPU_Surface_Presentation_Report :: struct {
	width:        u32,
	height:       u32,
	format:       WGPU_Texture_Format,
	present_mode: WGPU_Present_Mode,
	alpha_mode:   WGPU_Composite_Alpha_Mode,
}

wgpu_present_surface_clear :: proc(
	procs: WGPU_Offscreen_Procs,
	surface_descriptor: ^WGPU_Surface_Descriptor,
	width, height: u32,
	backend_type: WGPU_Backend_Type = WGPU_BACKEND_TYPE_UNDEFINED,
) -> (WGPU_Surface_Presentation_Report, string, bool) {
	if width == 0 || height == 0 {
		return WGPU_Surface_Presentation_Report{}, WGPU_OFFSCREEN_INVALID_SIZE_ERROR, false
	}

	descriptor := wgpu_instance_descriptor_default()
	instance := procs.create_instance(&descriptor)
	if instance == nil {
		return WGPU_Surface_Presentation_Report{}, WGPU_OFFSCREEN_INSTANCE_CREATE_ERROR, false
	}
	defer procs.instance_release(instance)

	surface := procs.instance_create_surface(instance, surface_descriptor)
	if surface == nil {
		return WGPU_Surface_Presentation_Report{}, WGPU_SURFACE_CREATE_ERROR, false
	}
	defer procs.surface_release(surface)

	adapter, adapter_error, adapter_ok := wgpu_request_adapter_sync(procs, instance, backend_type, surface)
	if !adapter_ok {
		return WGPU_Surface_Presentation_Report{}, adapter_error, false
	}
	defer procs.adapter_release(adapter)

	capabilities := WGPU_Surface_Capabilities{}
	capabilities_status := procs.surface_get_capabilities(surface, adapter, &capabilities)
	if capabilities_status != WGPU_STATUS_SUCCESS {
		return WGPU_Surface_Presentation_Report{}, WGPU_SURFACE_CAPABILITIES_ERROR, false
	}
	defer procs.surface_capabilities_free_members(capabilities)

	usage := WGPU_TEXTURE_USAGE_RENDER_ATTACHMENT
	if capabilities.usages != WGPU_TEXTURE_USAGE_NONE && (capabilities.usages & usage) == WGPU_TEXTURE_USAGE_NONE {
		return WGPU_Surface_Presentation_Report{}, WGPU_SURFACE_UNSUPPORTED_USAGE_ERROR, false
	}

	device, device_error, device_ok := wgpu_request_device_sync(procs, instance, adapter)
	if !device_ok {
		return WGPU_Surface_Presentation_Report{}, device_error, false
	}
	defer procs.device_release(device)

	queue := procs.device_get_queue(device)
	if queue == nil {
		return WGPU_Surface_Presentation_Report{}, WGPU_OFFSCREEN_QUEUE_GET_ERROR, false
	}
	defer procs.queue_release(queue)

	format := wgpu_surface_choose_format(capabilities)
	present_mode := wgpu_surface_choose_present_mode(capabilities)
	alpha_mode := wgpu_surface_choose_alpha_mode(capabilities)
	config := wgpu_surface_configuration(device, format, width, height, usage, present_mode, alpha_mode)
	procs.surface_configure(surface, &config)
	defer procs.surface_unconfigure(surface)

	surface_texture := wgpu_surface_texture_error()
	procs.surface_get_current_texture(surface, &surface_texture)
	if !wgpu_surface_texture_status_is_presentable(surface_texture.status) || surface_texture.texture == nil {
		return WGPU_Surface_Presentation_Report{}, WGPU_SURFACE_CURRENT_TEXTURE_ERROR, false
	}
	defer procs.texture_release(surface_texture.texture)

	view_descriptor := wgpu_texture_view_descriptor_default(wgpu_string_view_empty())
	texture_view := procs.texture_create_view(surface_texture.texture, &view_descriptor)
	if texture_view == nil {
		return WGPU_Surface_Presentation_Report{}, WGPU_OFFSCREEN_TEXTURE_VIEW_CREATE_ERROR, false
	}
	defer procs.texture_view_release(texture_view)

	encoder_descriptor := wgpu_command_encoder_descriptor(wgpu_string_view_empty())
	encoder := procs.device_create_command_encoder(device, &encoder_descriptor)
	if encoder == nil {
		return WGPU_Surface_Presentation_Report{}, WGPU_OFFSCREEN_COMMAND_ENCODER_CREATE_ERROR, false
	}
	defer procs.command_encoder_release(encoder)

	color_attachments := [?]WGPU_Color_Attachment{
		wgpu_color_attachment_clear(texture_view, wgpu_color(0.006049, 0.008023, 0.012286, 1.0)),
	}
	pass_descriptor := wgpu_render_pass_descriptor(wgpu_string_view_empty(), &color_attachments[0], 1)
	render_pass := procs.command_encoder_begin_render_pass(encoder, &pass_descriptor)
	if render_pass == nil {
		return WGPU_Surface_Presentation_Report{}, WGPU_OFFSCREEN_RENDER_PASS_CREATE_ERROR, false
	}
	procs.render_pass_encoder_end(render_pass)
	procs.render_pass_encoder_release(render_pass)

	command_buffer_descriptor := wgpu_command_buffer_descriptor(wgpu_string_view_empty())
	command_buffer := procs.command_encoder_finish(encoder, &command_buffer_descriptor)
	if command_buffer == nil {
		return WGPU_Surface_Presentation_Report{}, WGPU_OFFSCREEN_COMMAND_BUFFER_CREATE_ERROR, false
	}

	command_buffers := [?]WGPU_Command_Buffer{command_buffer}
	procs.queue_submit(queue, 1, &command_buffers[0])
	procs.command_buffer_release(command_buffer)

	present_status := procs.surface_present(surface)
	if present_status != WGPU_STATUS_SUCCESS {
		return WGPU_Surface_Presentation_Report{}, WGPU_SURFACE_PRESENT_ERROR, false
	}

	return WGPU_Surface_Presentation_Report{
		width = width,
		height = height,
		format = format,
		present_mode = present_mode,
		alpha_mode = alpha_mode,
	}, "", true
}

wgpu_surface_choose_format :: proc(capabilities: WGPU_Surface_Capabilities) -> WGPU_Texture_Format {
	if capabilities.format_count > 0 && capabilities.formats != nil {
		return capabilities.formats[0]
	}
	return WGPU_DEFAULT_TARGET_FORMAT
}

wgpu_surface_choose_present_mode :: proc(capabilities: WGPU_Surface_Capabilities) -> WGPU_Present_Mode {
	if capabilities.present_mode_count > 0 && capabilities.present_modes != nil {
		for i: c.size_t = 0; i < capabilities.present_mode_count; i += 1 {
			if capabilities.present_modes[i] == WGPU_PRESENT_MODE_FIFO {
				return WGPU_PRESENT_MODE_FIFO
			}
		}
		return capabilities.present_modes[0]
	}
	return WGPU_PRESENT_MODE_FIFO
}

wgpu_surface_choose_alpha_mode :: proc(capabilities: WGPU_Surface_Capabilities) -> WGPU_Composite_Alpha_Mode {
	if capabilities.alpha_mode_count > 0 && capabilities.alpha_modes != nil {
		for i: c.size_t = 0; i < capabilities.alpha_mode_count; i += 1 {
			if capabilities.alpha_modes[i] == WGPU_COMPOSITE_ALPHA_MODE_AUTO {
				return WGPU_COMPOSITE_ALPHA_MODE_AUTO
			}
		}
		return capabilities.alpha_modes[0]
	}
	return WGPU_COMPOSITE_ALPHA_MODE_AUTO
}

wgpu_surface_texture_status_is_presentable :: proc(status: WGPU_Surface_Get_Current_Texture_Status) -> bool {
	return status == WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_OPTIMAL ||
	       status == WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_SUBOPTIMAL
}

wgpu_surface_texture_status_label :: proc(status: WGPU_Surface_Get_Current_Texture_Status) -> string {
	switch status {
	case WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_OPTIMAL:
		return "success-optimal"
	case WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_SUBOPTIMAL:
		return "success-suboptimal"
	case WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_TIMEOUT:
		return "timeout"
	case WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_OUTDATED:
		return "outdated"
	case WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_LOST:
		return "lost"
	case WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_OUT_OF_MEMORY:
		return "out-of-memory"
	case WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_DEVICE_LOST:
		return "device-lost"
	case WGPU_SURFACE_GET_CURRENT_TEXTURE_STATUS_ERROR:
		return "error"
	}
	return "unknown"
}
