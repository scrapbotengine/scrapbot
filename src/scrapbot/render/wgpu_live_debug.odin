package render

import live_debug "../live_debug"
import "core:encoding/cbor"
import "core:encoding/endian"
import "core:fmt"
import "core:math"
import "core:os"
import wgpu "vendor:wgpu"

WGPU_LIVE_DEBUG_VISIBILITY_RECORD_LIMIT :: WGPU_MESHLET_DEBUG_RECORD_CAPACITY

WGPU_Live_Debug_Visibility_Record :: struct {
	classification: string,
	lod_level: u32,
	meshlet_identity: u32,
	bounds: [4]f32,
	query_rect: [4]f32,
	query_depths: [4]f32,
	virtual_geometry: bool,
	page_resident: bool,
	refined_resident: bool,
	group_depth: u32,
	max_depth: u32,
	group_error: f32,
	refined_error: f32,
	group_index: u32,
	request_group_index: u32,
	request_enabled: bool,
	transition_start: u32,
	refined_transition_start: u32,
	has_coarse_parent: bool,
}

WGPU_Live_Debug_Visibility :: struct {
	schema_version: int,
	frame_number: u32,
	meshlet_submission_active: bool,
	record_count: u32,
	records_written: int,
	records_truncated: bool,
	visible_instances: u32,
	visible_meshlets: u32,
	visible_virtual_clusters: u32,
	visible_virtual_blend_clusters: u32,
	virtual_rejected_clusters: u32,
	frustum_culled_instances: u32,
	occlusion_culled_instances: u32,
	frustum_culled_meshlets: u32,
	cone_culled_meshlets: u32,
	occlusion_culled_meshlets: u32,
	candidate_record_overflow: u32,
	visible_record_overflow: u32,
	shadow_record_overflow: u32,
	records: []WGPU_Live_Debug_Visibility_Record,
}

WGPU_Live_Debug_Capture :: struct {
	service: ^live_debug.Service,
	plan: live_debug.Capture_Frame_Plan,
	color_buffer: wgpu.Buffer,
	color_readback_size: u64,
	color_row_stride: u32,
	color_width: u32,
	color_height: u32,
	color_path: string,
	depth_buffer: wgpu.Buffer,
	depth_readback_size: u64,
	depth_row_stride: u32,
	depth_width: u32,
	depth_height: u32,
	depth_path: string,
	depth_preview_path: string,
	visibility_buffer: wgpu.Buffer,
	visibility_readback_size: u64,
	visibility_record_capacity: int,
	visibility_path: string,
}

wgpu_live_debug_prepare_capture :: proc(
	renderer: ^WGPU_Renderer,
	config: ^Run_Config,
	output_width, output_height: u32,
	render_width, render_height: u32,
	copy_supported := true,
) -> WGPU_Live_Debug_Capture {
	if renderer == nil || config == nil || config.live_debug == nil {
		return {}
	}
	plan := live_debug.begin_capture_frame(config.live_debug)
	capture := WGPU_Live_Debug_Capture {
		service = config.live_debug,
		plan = plan,
		color_width = output_width,
		color_height = output_height,
		depth_width = render_width,
		depth_height = render_height,
	}
	renderer.live_debug_visibility_capture = live_debug.capture_artifact_requested(
		plan,
		.Visibility,
	)
	if !plan.active {
		return capture
	}
	if live_debug.capture_artifact_requested(plan, .Color) {
		if !copy_supported {
			live_debug.capture_fail(
				config.live_debug,
				"the WGPU output surface does not support color readback",
			)
			return capture
		}
		capture.color_row_stride = align_to(output_width * 4, 256)
		capture.color_readback_size = u64(capture.color_row_stride) * u64(output_height)
		capture.color_buffer = wgpu_live_debug_create_readback(
			renderer,
			"Scrapbot Live Debug Color Readback",
			capture.color_readback_size,
		)
		capture.color_path, _ = live_debug.capture_artifact_path(plan, .Color)
	}
	if live_debug.capture_artifact_requested(plan, .Depth) {
		capture.depth_row_stride = align_to(render_width * 4, 256)
		capture.depth_readback_size = u64(capture.depth_row_stride) * u64(render_height)
		capture.depth_buffer = wgpu_live_debug_create_readback(
			renderer,
			"Scrapbot Live Debug Depth Readback",
			capture.depth_readback_size,
		)
		capture.depth_path, _ = live_debug.capture_artifact_path(plan, .Depth)
		capture.depth_preview_path, _ = live_debug.capture_companion_path(
			plan,
			"depth-preview",
			".png",
		)
	}
	if live_debug.capture_artifact_requested(plan, .Visibility) {
		if config.cpu_culling {
			live_debug.capture_fail(config.live_debug, "visibility capture requires GPU culling")
			return capture
		}
		capture.visibility_record_capacity = WGPU_LIVE_DEBUG_VISIBILITY_RECORD_LIMIT
		capture.visibility_readback_size =
			u64(size_of(WGPU_GPU_Visibility_Summary)) +
			u64(capture.visibility_record_capacity * size_of(WGPU_GPU_Meshlet_Debug_Record))
		capture.visibility_buffer = wgpu_live_debug_create_readback(
			renderer,
			"Scrapbot Live Debug Visibility Readback",
			capture.visibility_readback_size,
		)
		capture.visibility_path, _ = live_debug.capture_artifact_path(plan, .Visibility)
	}
	if (live_debug.capture_artifact_requested(plan, .Color) && capture.color_buffer == nil ||
		   live_debug.capture_artifact_requested(plan, .Depth) && capture.depth_buffer == nil ||
		   live_debug.capture_artifact_requested(plan, .Visibility) &&
			   capture.visibility_buffer == nil ||
		   live_debug.capture_artifact_requested(plan, .Color) && capture.color_path == "" ||
		   live_debug.capture_artifact_requested(plan, .Depth) &&
			   (capture.depth_path == "" || capture.depth_preview_path == "") ||
		   live_debug.capture_artifact_requested(plan, .Visibility) &&
			   capture.visibility_path == "") {
		live_debug.capture_fail(config.live_debug, "failed to prepare WGPU live debug artifacts")
	}
	return capture
}

wgpu_live_debug_create_readback :: proc(
	renderer: ^WGPU_Renderer,
	label: string,
	size: u64,
) -> wgpu.Buffer {
	if renderer == nil || size == 0 {
		return nil
	}
	return wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor{label = label, usage = {.CopyDst, .MapRead}, size = size},
	)
}

wgpu_live_debug_destroy_capture :: proc(capture: ^WGPU_Live_Debug_Capture) {
	if capture == nil {
		return
	}
	delete(capture.color_path)
	delete(capture.depth_path)
	delete(capture.depth_preview_path)
	delete(capture.visibility_path)
	buffers := [?]wgpu.Buffer {
		capture.color_buffer,
		capture.depth_buffer,
		capture.visibility_buffer,
	}
	for buffer in buffers {
		if buffer != nil {
			wgpu.BufferRelease(buffer)
		}
	}
	if capture.service != nil {
		// Capture intent is frame-local. Never leak it into a later frame.
		capture.plan = {}
	}
	capture^ = {}
}

wgpu_live_debug_encode_capture :: proc(
	renderer: ^WGPU_Renderer,
	capture: ^WGPU_Live_Debug_Capture,
	encoder: wgpu.CommandEncoder,
	output_texture: wgpu.Texture,
) {
	if renderer == nil || capture == nil {
		return
	}
	if capture.color_buffer != nil {
		wgpu.CommandEncoderCopyTextureToBuffer(
			encoder,
			&wgpu.TexelCopyTextureInfo{texture = output_texture, aspect = .All},
			&wgpu.TexelCopyBufferInfo {
				buffer = capture.color_buffer,
				layout = {
					bytesPerRow = capture.color_row_stride,
					rowsPerImage = capture.color_height,
				},
			},
			&wgpu.Extent3D {
				width = capture.color_width,
				height = capture.color_height,
				depthOrArrayLayers = 1,
			},
		)
	}
	if capture.depth_buffer != nil {
		depth_index := 1 - renderer.temporal_output_index
		wgpu.CommandEncoderCopyTextureToBuffer(
			encoder,
			&wgpu.TexelCopyTextureInfo {
				texture = renderer.temporal_depth_textures[depth_index],
				aspect = .All,
			},
			&wgpu.TexelCopyBufferInfo {
				buffer = capture.depth_buffer,
				layout = {
					bytesPerRow = capture.depth_row_stride,
					rowsPerImage = capture.depth_height,
				},
			},
			&wgpu.Extent3D {
				width = capture.depth_width,
				height = capture.depth_height,
				depthOrArrayLayers = 1,
			},
		)
	}
	if capture.visibility_buffer != nil {
		summary_size := u64(size_of(WGPU_GPU_Visibility_Summary))
		wgpu.CommandEncoderCopyBufferToBuffer(
			encoder,
			renderer.gpu_visibility_counter_buffer,
			0,
			capture.visibility_buffer,
			0,
			summary_size,
		)
		wgpu.CommandEncoderCopyBufferToBuffer(
			encoder,
			renderer.gpu_meshlet_debug_record_buffer,
			0,
			capture.visibility_buffer,
			summary_size,
			u64(capture.visibility_record_capacity * size_of(WGPU_GPU_Meshlet_Debug_Record)),
		)
	}
}

wgpu_live_debug_finish_capture :: proc(
	renderer: ^WGPU_Renderer,
	capture: ^WGPU_Live_Debug_Capture,
) {
	if renderer == nil || capture == nil {
		return
	}
	defer {
		renderer.live_debug_visibility_capture = false
	}
	if capture.color_buffer != nil {
		if write_err := wgpu_write_framegrab_readback(
			renderer,
			capture.color_buffer,
			capture.color_readback_size,
			capture.color_row_stride,
			capture.color_width,
			capture.color_height,
			0,
			0,
			capture.color_width,
			capture.color_height,
			capture.color_path,
		); write_err != "" {
			live_debug.capture_fail(capture.service, write_err)
			return
		}
	}
	if capture.depth_buffer != nil {
		if write_err := wgpu_live_debug_write_depth(renderer, capture); write_err != "" {
			live_debug.capture_fail(capture.service, write_err)
			return
		}
	}
	if capture.visibility_buffer != nil {
		if write_err := wgpu_live_debug_write_visibility(renderer, capture); write_err != "" {
			live_debug.capture_fail(capture.service, write_err)
			return
		}
	}
	if card(capture.plan.artifacts) > 0 {
		live_debug.capture_frame_artifacts_ready(capture.service, capture.plan)
	}
}

wgpu_live_debug_map :: proc(
	renderer: ^WGPU_Renderer,
	buffer: wgpu.Buffer,
	size: u64,
) -> (
	[]u8,
	string,
) {
	map_state: WGPU_Buffer_Map_State
	wgpu.BufferMapAsync(
		buffer,
		{.Read},
		0,
		uint(size),
		wgpu.BufferMapCallbackInfo {
			mode = .AllowSpontaneos,
			callback = wgpu_buffer_map_callback,
			userdata1 = &map_state,
		},
	)
	wgpu.DevicePoll(renderer.device, true)
	wgpu.InstanceProcessEvents(renderer.instance)
	if !wgpu_wait_for_buffer_map(renderer.instance, &map_state) {
		message := string(map_state.message[:map_state.message_length])
		if message == "" {
			message = "request timed out"
		}
		return nil, fmt.tprintf("failed to map WGPU live debug buffer: %s", message)
	}
	return wgpu.BufferGetMappedRange(buffer, 0, uint(size)), ""
}

wgpu_live_debug_write_depth :: proc(
	renderer: ^WGPU_Renderer,
	capture: ^WGPU_Live_Debug_Capture,
) -> string {
	mapped, map_err := wgpu_live_debug_map(
		renderer,
		capture.depth_buffer,
		capture.depth_readback_size,
	)
	if map_err != "" {
		return map_err
	}
	defer wgpu.BufferUnmap(capture.depth_buffer)
	pixel_count := int(capture.depth_width * capture.depth_height)
	depth := make([]f32, pixel_count)
	defer delete(depth)
	for y in 0 ..< int(capture.depth_height) {
		source := mapped[y * int(capture.depth_row_stride):]
		source_depth := (cast([^]f32)raw_data(source))[:int(capture.depth_width)]
		copy(depth[y * int(capture.depth_width):], source_depth)
	}
	depth_bytes := make([]u8, pixel_count * size_of(f32))
	defer delete(depth_bytes)
	for value, index in depth {
		endian.unchecked_put_u32le(depth_bytes[index * size_of(f32):], transmute(u32)value)
	}
	if write_err := os.write_entire_file(capture.depth_path, depth_bytes); write_err != nil {
		return fmt.tprintf("failed to write live debug depth data: %v", write_err)
	}
	preview := make([]u8, pixel_count * 4)
	defer delete(preview)
	for value, index in depth {
		shade: u8
		if value < 0.999999 {
			projection := renderer.temporal_current_projection
			distance := max(projection[3] / (value + projection[2]), 0.0001)
			// Log distance exposes both near silhouettes and distant geometry.
			// The .f32 artifact remains the authoritative device-depth data.
			contrast := 1.0 - clamp(math.log2(distance + 1.0) / 10.0, 0.0, 1.0)
			shade = u8(clamp(contrast * 255.0, 0.0, 255.0))
		}
		preview[index * 4 + 0] = shade
		preview[index * 4 + 1] = shade
		preview[index * 4 + 2] = shade
		preview[index * 4 + 3] = 255
	}
	return write_png_rgba8(
		capture.depth_preview_path,
		preview,
		capture.depth_width,
		capture.depth_height,
	)
}

wgpu_live_debug_write_visibility :: proc(
	renderer: ^WGPU_Renderer,
	capture: ^WGPU_Live_Debug_Capture,
) -> string {
	mapped, map_err := wgpu_live_debug_map(
		renderer,
		capture.visibility_buffer,
		capture.visibility_readback_size,
	)
	if map_err != "" {
		return map_err
	}
	defer wgpu.BufferUnmap(capture.visibility_buffer)
	summary := cast(^WGPU_GPU_Visibility_Summary)raw_data(mapped)
	record_count := min(int(summary.meshlet_debug_records), capture.visibility_record_capacity)
	total_record_count := summary.meshlet_debug_records + summary.meshlet_debug_record_overflow
	record_offset := size_of(WGPU_GPU_Visibility_Summary)
	record_bytes := mapped[record_offset:]
	meshlet_records := (cast([^]WGPU_GPU_Meshlet_Debug_Record)raw_data(
			record_bytes,
		))[:record_count]
	records := make([]WGPU_Live_Debug_Visibility_Record, record_count)
	defer delete(records)
	for meshlet_source, index in meshlet_records {
		source := meshlet_source
		record := &records[index]
		record.classification = wgpu_live_debug_visibility_classification(source.classification)
		record.lod_level = source.lod_level
		record.meshlet_identity = source.meshlet_identity
		record.bounds = source.bounds
		record.query_rect = source.query_rect
		record.query_depths = source.query_depths
		meshlet_index := int(source.meshlet_identity) - 1
		if meshlet_index < 0 || meshlet_index >= len(renderer.gpu_meshlet_infos) {
			continue
		}
		info := renderer.gpu_meshlet_infos[meshlet_index]
		record.virtual_geometry = info.virtual_geometry != 0
		record.page_resident = info.page_resident != 0
		record.refined_resident = info.refined_resident != 0
		record.group_depth = info.group_depth
		record.max_depth = info.max_depth
		record.group_error = info.group_error
		record.refined_error = info.refined_error
		record.group_index = info.group_index
		record.request_group_index = info.request_group_index
		record.request_enabled = info.request_enabled != 0
		record.transition_start = info.transition_start
		record.refined_transition_start = info.refined_transition_start
		record.has_coarse_parent = info.has_coarse_parent != 0
	}
	payload := WGPU_Live_Debug_Visibility {
		schema_version = live_debug.SCHEMA_VERSION,
		frame_number = capture.plan.frame_number,
		meshlet_submission_active = renderer.gpu_meshlet_submission_active,
		record_count = total_record_count,
		records_written = record_count,
		records_truncated = summary.meshlet_debug_record_overflow > 0,
		visible_instances = summary.visible_instances,
		visible_meshlets = summary.visible_meshlets,
		visible_virtual_clusters = summary.visible_virtual_clusters,
		visible_virtual_blend_clusters = summary.visible_virtual_blend_clusters,
		virtual_rejected_clusters = summary.virtual_rejected_clusters,
		frustum_culled_instances = summary.frustum_culled_instances,
		occlusion_culled_instances = summary.occlusion_culled_instances,
		frustum_culled_meshlets = summary.frustum_culled_meshlets,
		cone_culled_meshlets = summary.cone_culled_meshlets,
		occlusion_culled_meshlets = summary.occlusion_culled_meshlets,
		candidate_record_overflow = summary.candidate_record_overflow,
		visible_record_overflow = summary.visible_record_overflow,
		shadow_record_overflow = summary.shadow_record_overflow,
		records = records,
	}
	data, encode_err := cbor.marshal(payload, cbor.ENCODE_FULLY_DETERMINISTIC)
	defer delete(data)
	if encode_err != nil {
		return fmt.tprintf("failed to encode live debug visibility CBOR: %v", encode_err)
	}
	if write_err := os.write_entire_file(capture.visibility_path, data); write_err != nil {
		return fmt.tprintf("failed to write live debug visibility data: %v", write_err)
	}
	return ""
}

wgpu_live_debug_visibility_classification :: proc "contextless" (value: u32) -> string {
	switch value {
		case 2:
			return "instance_frustum_culled"
		case 3:
			return "instance_occlusion_culled"
		case 4:
			return "meshlet_frustum_culled"
		case 5:
			return "meshlet_cone_culled"
		case 6:
			return "meshlet_occlusion_culled"
		case 7:
			return "occlusion_query_visible"
		case 8:
			return "occlusion_query_culled"
		case 9:
			return "virtual_cluster_rejected"
	}
	return "unknown"
}
