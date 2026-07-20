package render

import "vendor:wgpu"

wgpu_gpu_timestamp_bytes :: proc() -> u64 {
	return u64(WGPU_GPU_TIMESTAMP_QUERY_COUNT) * u64(size_of(u64))
}

wgpu_create_gpu_timing :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil || renderer.device == nil || renderer.queue == nil {
		return
	}
	if !bool(wgpu.DeviceHasFeature(renderer.device, .TimestampQuery)) || renderer.queue == nil {
		return
	}
	query_set := wgpu.DeviceCreateQuerySet(
		renderer.device,
		&wgpu.QuerySetDescriptor {
			label = "Scrapbot GPU Frame Timestamps",
			type = .Timestamp,
			count = u32(WGPU_GPU_TIMESTAMP_QUERY_COUNT),
		},
	)
	if query_set == nil {
		return
	}
	resolve_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Timestamp Resolve Buffer",
		{.QueryResolve, .CopySrc},
		wgpu_gpu_timestamp_bytes(),
	)
	if resolve_buffer == nil {
		wgpu.QuerySetRelease(query_set)
		return
	}
	readbacks: [WGPU_GPU_TIMESTAMP_FRAMES]wgpu.Buffer
	for index in 0 ..< WGPU_GPU_TIMESTAMP_FRAMES {
		readbacks[index] = wgpu_create_gpu_buffer(
			renderer,
			"Scrapbot GPU Timestamp Readback",
			{.MapRead, .CopyDst},
			wgpu_gpu_timestamp_bytes(),
		)
		if readbacks[index] == nil {
			for cleanup_index in 0 ..< index {
				wgpu.BufferRelease(readbacks[cleanup_index])
			}
			wgpu.BufferRelease(resolve_buffer)
			wgpu.QuerySetRelease(query_set)
			return
		}
	}
	renderer.gpu_timestamp_query_set = query_set
	renderer.gpu_timestamp_resolve_buffer = resolve_buffer
	for buffer, index in readbacks {
		renderer.gpu_timestamp_readbacks[index].buffer = buffer
	}
	renderer.gpu_timestamp_period_ns = f64(wgpu.QueueGetTimestampPeriod(renderer.queue))
	renderer.gpu_timestamp_active_slot = -1
	renderer.gpu_timestamp_supported = true
}

wgpu_release_gpu_timing :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil {
		return
	}
	for &readback in renderer.gpu_timestamp_readbacks {
		if readback.buffer != nil {
			if readback.pending &&
			   readback.map_state.completed &&
			   readback.map_state.status == .Success {
				wgpu.BufferUnmap(readback.buffer)
			}
			wgpu.BufferRelease(readback.buffer)
		}
	}
	if renderer.gpu_timestamp_resolve_buffer != nil {
		wgpu.BufferRelease(renderer.gpu_timestamp_resolve_buffer)
	}
	if renderer.gpu_timestamp_query_set != nil {
		wgpu.QuerySetRelease(renderer.gpu_timestamp_query_set)
	}
	renderer.gpu_timestamp_query_set = nil
	renderer.gpu_timestamp_resolve_buffer = nil
	renderer.gpu_timestamp_supported = false
}

wgpu_gpu_timing_consume_readbacks :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil || !renderer.gpu_timestamp_supported {
		return
	}
	wgpu.DevicePoll(renderer.device, false)
	for &readback in renderer.gpu_timestamp_readbacks {
		if !readback.pending || !readback.map_state.completed {
			continue
		}
		readback.pending = false
		if readback.map_state.status != .Success {
			continue
		}
		values := wgpu.BufferGetConstMappedRangeSlice(
			readback.buffer,
			0,
			uint(WGPU_GPU_TIMESTAMP_QUERY_COUNT),
			u64,
		)
		frame_ms := 0.0
		for phase_index in 0 ..< WGPU_GPU_TIMESTAMP_PHASE_COUNT {
			if readback.phase_mask & (u32(1) << u32(phase_index)) == 0 {
				renderer.gpu_timestamp_phase_ms[phase_index] = 0
				continue
			}
			begin := values[phase_index * 2]
			end := values[phase_index * 2 + 1]
			duration_ms := 0.0
			if end >= begin {
				duration_ms = f64(end - begin) * renderer.gpu_timestamp_period_ns / 1_000_000.0
			}
			renderer.gpu_timestamp_phase_ms[phase_index] = duration_ms
			frame_ms += duration_ms
		}
		for mip_index in 1 ..< readback.hiz_mip_count {
			query_index := WGPU_GPU_HIZ_EXTRA_QUERY_BASE + (mip_index - 1) * 2
			begin := values[query_index]
			end := values[query_index + 1]
			if end >= begin {
				duration_ms := f64(end - begin) * renderer.gpu_timestamp_period_ns / 1_000_000.0
				renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.HiZ)] += duration_ms
				frame_ms += duration_ms
			}
		}
		renderer.gpu_timestamp_frame_ms = frame_ms
		renderer.gpu_timestamp_valid = true
		wgpu.BufferUnmap(readback.buffer)
	}
}

wgpu_gpu_timing_begin_frame :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil || !renderer.gpu_timestamp_supported {
		return
	}
	wgpu_gpu_timing_consume_readbacks(renderer)
	renderer.gpu_timestamp_active_slot = -1
	for offset in 0 ..< WGPU_GPU_TIMESTAMP_FRAMES {
		index := (renderer.gpu_timestamp_next_slot + offset) % WGPU_GPU_TIMESTAMP_FRAMES
		readback := &renderer.gpu_timestamp_readbacks[index]
		if !readback.pending {
			readback.phase_mask = 0
			renderer.gpu_timestamp_active_slot = index
			renderer.gpu_timestamp_next_slot = (index + 1) % WGPU_GPU_TIMESTAMP_FRAMES
			return
		}
	}
}

wgpu_gpu_pass_timestamps :: proc(
	renderer: ^WGPU_Renderer,
	phase: WGPU_GPU_Timestamp_Phase,
) -> (
	wgpu.PassTimestampWrites,
	bool,
) {
	if renderer == nil || renderer.gpu_timestamp_active_slot < 0 {
		return {}, false
	}
	readback := &renderer.gpu_timestamp_readbacks[renderer.gpu_timestamp_active_slot]
	readback.phase_mask |= u32(1) << u32(phase)
	query_index := u32(phase) * 2
	return wgpu.PassTimestampWrites {
			querySet = renderer.gpu_timestamp_query_set,
			beginningOfPassWriteIndex = query_index,
			endOfPassWriteIndex = query_index + 1,
		},
		true
}

wgpu_gpu_hiz_pass_timestamps :: proc(
	renderer: ^WGPU_Renderer,
	mip_index: int,
) -> (
	wgpu.PassTimestampWrites,
	bool,
) {
	if mip_index == 0 {
		return wgpu_gpu_pass_timestamps(renderer, .HiZ)
	}
	if renderer == nil ||
	   renderer.gpu_timestamp_active_slot < 0 ||
	   mip_index < 0 ||
	   mip_index >= WGPU_MAX_HIZ_LEVELS {
		return {}, false
	}
	query_index := u32(WGPU_GPU_HIZ_EXTRA_QUERY_BASE + (mip_index - 1) * 2)
	return wgpu.PassTimestampWrites {
			querySet = renderer.gpu_timestamp_query_set,
			beginningOfPassWriteIndex = query_index,
			endOfPassWriteIndex = query_index + 1,
		},
		true
}

wgpu_gpu_timing_resolve :: proc(renderer: ^WGPU_Renderer, encoder: wgpu.CommandEncoder) {
	if renderer == nil || renderer.gpu_timestamp_active_slot < 0 {
		return
	}
	readback := &renderer.gpu_timestamp_readbacks[renderer.gpu_timestamp_active_slot]
	readback.hiz_mip_count = renderer.gpu_hiz_mip_count if renderer.gpu_hiz_requested else 0
	wgpu.CommandEncoderResolveQuerySet(
		encoder,
		renderer.gpu_timestamp_query_set,
		0,
		u32(WGPU_GPU_TIMESTAMP_QUERY_COUNT),
		renderer.gpu_timestamp_resolve_buffer,
		0,
	)
	wgpu.CommandEncoderCopyBufferToBuffer(
		encoder,
		renderer.gpu_timestamp_resolve_buffer,
		0,
		readback.buffer,
		0,
		wgpu_gpu_timestamp_bytes(),
	)
}

wgpu_gpu_timing_after_submit :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil || renderer.gpu_timestamp_active_slot < 0 {
		return
	}
	readback := &renderer.gpu_timestamp_readbacks[renderer.gpu_timestamp_active_slot]
	readback.map_state = {}
	readback.pending = true
	wgpu.BufferMapAsync(
		readback.buffer,
		{.Read},
		0,
		uint(wgpu_gpu_timestamp_bytes()),
		wgpu.BufferMapCallbackInfo {
			mode = .AllowProcessEvents,
			callback = wgpu_buffer_map_callback,
			userdata1 = &readback.map_state,
		},
	)
	renderer.gpu_timestamp_active_slot = -1
}

wgpu_publish_gpu_timing :: proc(renderer: ^WGPU_Renderer, stats: ^Render_Stats) {
	if renderer == nil || stats == nil {
		return
	}
	stats.gpu_timestamps_supported = renderer.gpu_timestamp_supported
	stats.gpu_timestamps_valid = renderer.gpu_timestamp_valid
	stats.gpu_frame_ms = renderer.gpu_timestamp_frame_ms
	stats.gpu_cull_ms = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Cull)]
	stats.gpu_shadow_ms = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Shadow)]
	stats.gpu_depth_ms = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Depth)]
	stats.gpu_world_ms = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.World)]
	stats.gpu_hiz_ms = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.HiZ)]
	stats.gpu_bloom_ms = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Bloom)]
	stats.gpu_composite_ms =
		renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Composite)]
	stats.gpu_post_ms = stats.gpu_bloom_ms + stats.gpu_composite_ms
	stats.gpu_ui_ms = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.UI)]
	stats.hiz_occlusion = renderer.gpu_hiz_occlusion_enabled
	stats.hiz_valid = renderer.gpu_hiz_valid
	stats.hiz_mip_count = renderer.gpu_hiz_mip_count
}
