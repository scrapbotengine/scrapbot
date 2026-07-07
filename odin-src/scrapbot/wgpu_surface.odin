package main

import "core:c"

WGPU_SURFACE_CREATE_ERROR :: "create_surface"
WGPU_SURFACE_CAPABILITIES_ERROR :: "surface_capabilities"
WGPU_SURFACE_UNSUPPORTED_USAGE_ERROR :: "surface_unsupported_usage"
WGPU_SURFACE_CURRENT_TEXTURE_ERROR :: "surface_current_texture"
WGPU_SURFACE_PRESENT_ERROR :: "surface_present"

WGPU_Surface_Presentation_Report :: struct {
	width:            u32,
	height:           u32,
	format:           WGPU_Texture_Format,
	present_mode:     WGPU_Present_Mode,
	alpha_mode:       WGPU_Composite_Alpha_Mode,
	renderable_count: int,
}

wgpu_present_surface_clear :: proc(
	procs: WGPU_Offscreen_Procs,
	surface_descriptor: ^WGPU_Surface_Descriptor,
	width, height: u32,
	backend_type: WGPU_Backend_Type = WGPU_BACKEND_TYPE_UNDEFINED,
) -> (WGPU_Surface_Presentation_Report, string, bool) {
	return wgpu_present_surface_scene_with_world(procs, surface_descriptor, Runtime_World{}, width, height, backend_type, false)
}

wgpu_present_surface_scene :: proc(
	procs: WGPU_Offscreen_Procs,
	surface_descriptor: ^WGPU_Surface_Descriptor,
	world: Runtime_World,
	width, height: u32,
	backend_type: WGPU_Backend_Type = WGPU_BACKEND_TYPE_UNDEFINED,
) -> (WGPU_Surface_Presentation_Report, string, bool) {
	return wgpu_present_surface_scene_with_world(procs, surface_descriptor, world, width, height, backend_type, true)
}

wgpu_present_surface_scene_with_world :: proc(
	procs: WGPU_Offscreen_Procs,
	surface_descriptor: ^WGPU_Surface_Descriptor,
	world: Runtime_World,
	width, height: u32,
	backend_type: WGPU_Backend_Type,
	draw_world: bool,
) -> (WGPU_Surface_Presentation_Report, string, bool) {
	if width == 0 || height == 0 {
		return WGPU_Surface_Presentation_Report{}, WGPU_OFFSCREEN_INVALID_SIZE_ERROR, false
	}

	vertices: [dynamic]WGPU_Scene_Vertex
	defer delete(vertices)
	if draw_world {
		wgpu_collect_scene_vertices(&vertices, world, int(width), int(height))
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

	shader_module: WGPU_Shader_Module
	pipeline_layout: WGPU_Pipeline_Layout
	render_pipeline: WGPU_Render_Pipeline
	defer wgpu_release_scene_pipeline_resources(procs, &shader_module, &pipeline_layout, &render_pipeline)
	if len(vertices) > 0 {
		shader_code := wgpu_scene_rect_wgsl(vertices[:])
		defer delete(shader_code)
		shader_source := wgpu_shader_source_wgsl(wgpu_string_view_from_string(shader_code))
		shader_descriptor := wgpu_shader_module_descriptor_wgsl(wgpu_string_view_empty(), &shader_source)
		shader_module = procs.device_create_shader_module(device, &shader_descriptor)
		if shader_module == nil {
			return WGPU_Surface_Presentation_Report{}, WGPU_OFFSCREEN_SHADER_MODULE_CREATE_ERROR, false
		}

		pipeline_layout_descriptor := wgpu_pipeline_layout_descriptor(wgpu_string_view_empty(), nil, 0)
		pipeline_layout = procs.device_create_pipeline_layout(device, &pipeline_layout_descriptor)
		if pipeline_layout == nil {
			return WGPU_Surface_Presentation_Report{}, WGPU_OFFSCREEN_PIPELINE_LAYOUT_CREATE_ERROR, false
		}

		vertex := wgpu_vertex_state(shader_module, wgpu_string_view_from_string("vs_main"))
		color_targets := [?]WGPU_Color_Target_State{
			wgpu_color_target_state(format),
		}
		fragment := wgpu_fragment_state(shader_module, wgpu_string_view_from_string("fs_main"), &color_targets[0], 1)
		pipeline_descriptor := wgpu_render_pipeline_descriptor(
			wgpu_string_view_empty(),
			pipeline_layout,
			vertex,
			wgpu_primitive_state(),
			wgpu_multisample_state_default(),
			&fragment,
		)
		render_pipeline = procs.device_create_render_pipeline(device, &pipeline_descriptor)
		if render_pipeline == nil {
			return WGPU_Surface_Presentation_Report{}, WGPU_OFFSCREEN_RENDER_PIPELINE_CREATE_ERROR, false
		}
	}

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
	if len(vertices) > 0 {
		procs.render_pass_encoder_set_pipeline(render_pass, render_pipeline)
		procs.render_pass_encoder_draw(render_pass, u32(len(vertices)), 1, 0, 0)
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
		renderable_count = len(vertices) / 6,
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
