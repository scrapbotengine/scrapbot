package render

import "vendor:wgpu"

wgpu_timestamp_required_features :: proc(
	timestamp_query_supported: bool,
) -> (
	features: [1]wgpu.FeatureName,
	count: int,
) {
	if !timestamp_query_supported {
		return
	}
	features[0] = .TimestampQuery
	count = 1
	return
}

wgpu_renderer_required_features :: proc(
	timestamp_query_supported,
	indirect_first_instance_supported,
	multi_draw_indirect_count_supported: bool,
) -> (
	features: [3]wgpu.FeatureName,
	count: int,
) {
	if timestamp_query_supported {
		features[count] = .TimestampQuery
		count += 1
	}
	if indirect_first_instance_supported {
		features[count] = .IndirectFirstInstance
		count += 1
	}
	if multi_draw_indirect_count_supported {
		features[count] = .MultiDrawIndirectCount
		count += 1
	}
	return
}

wgpu_gpu_timestamp_bytes :: proc() -> u64 {
	return u64(WGPU_GPU_TIMESTAMP_QUERY_COUNT) * u64(size_of(u64))
}

wgpu_gpu_timestamp_resolve_bytes :: proc() -> u64 {
	return u64(WGPU_GPU_TIMESTAMP_RESOLVE_RANGE_COUNT) * WGPU_GPU_TIMESTAMP_RESOLVE_ALIGNMENT
}

wgpu_gpu_span_ms :: proc(
	frame_begin, scene_end, frame_end: u64,
	timestamp_period_ns: f64,
) -> (
	frame_ms, scene_ms: f64,
	valid: bool,
) {
	if timestamp_period_ns <= 0 || scene_end < frame_begin || frame_end < scene_end {
		return
	}
	scene_ms = f64(scene_end - frame_begin) * timestamp_period_ns / 1_000_000.0
	frame_ms = f64(frame_end - frame_begin) * timestamp_period_ns / 1_000_000.0
	valid = frame_ms > 0
	return
}

WGPU_GPU_Timestamp_Span :: struct {
	frame_begin: u64,
	scene_end: u64,
	frame_end: u64,
	has_frame: bool,
	has_scene: bool,
}

wgpu_gpu_timestamp_span_include :: proc(
	span: ^WGPU_GPU_Timestamp_Span,
	begin, end: u64,
	scene: bool,
) {
	if span == nil || end < begin {
		return
	}
	if !span.has_frame || begin < span.frame_begin {
		span.frame_begin = begin
	}
	if !span.has_frame || end > span.frame_end {
		span.frame_end = end
	}
	span.has_frame = true
	if scene {
		if !span.has_scene || end > span.scene_end {
			span.scene_end = end
		}
		span.has_scene = true
	}
}

wgpu_gpu_timestamp_resolve_ranges :: proc(
	phase_mask: u32,
	hiz_mip_count: int,
	shadow_cascade_mask: u32 = 0,
) -> (
	ranges: [WGPU_GPU_TIMESTAMP_RESOLVE_RANGE_COUNT]WGPU_GPU_Timestamp_Resolve_Range,
	count: int,
) {
	for phase_index in 0 ..< WGPU_GPU_TIMESTAMP_PHASE_COUNT {
		if phase_mask & (u32(1) << u32(phase_index)) == 0 {
			continue
		}
		ranges[count] = {
			first = u32(phase_index * 2),
			count = 2,
		}
		count += 1
	}
	if hiz_mip_count > 1 {
		ranges[count] = {
			first = u32(WGPU_GPU_HIZ_EXTRA_QUERY_BASE),
			count = u32((hiz_mip_count - 1) * 2),
		}
		count += 1
	}
	for cascade_index in 1 ..< WGPU_SHADOW_CASCADE_COUNT {
		if shadow_cascade_mask & (u32(1) << u32(cascade_index)) == 0 {
			continue
		}
		ranges[count] = {
			first = u32(WGPU_GPU_SHADOW_EXTRA_QUERY_BASE + (cascade_index - 1) * 2),
			count = 2,
		}
		count += 1
	}
	return
}

wgpu_create_gpu_timing :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil {
		return
	}
	renderer.gpu_timestamp_active_slot = -1
	renderer.gpu_timestamp_supported = false
	if renderer.device == nil || renderer.queue == nil {
		return
	}
	if !bool(wgpu.DeviceHasFeature(renderer.device, .TimestampQuery)) {
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
		wgpu_gpu_timestamp_resolve_bytes(),
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
	renderer.gpu_timestamp_active_slot = -1
	renderer.gpu_timestamp_supported = false
}

wgpu_gpu_timing_consume_readbacks :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil || !renderer.gpu_timestamp_supported {
		return
	}
	wgpu.DevicePoll(renderer.device, false)
	wgpu.InstanceProcessEvents(renderer.instance)
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
		scene_ms := 0.0
		frame_span_valid := false
		timestamp_span: WGPU_GPU_Timestamp_Span
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
				wgpu_gpu_timestamp_span_include(
					&timestamp_span,
					begin,
					end,
					phase_index != int(WGPU_GPU_Timestamp_Phase.UI),
				)
			}
			renderer.gpu_timestamp_phase_ms[phase_index] = duration_ms
		}
		renderer.gpu_timestamp_shadow_cascade_ms = {}
		if readback.shadow_cascade_mask & 1 != 0 {
			renderer.gpu_timestamp_shadow_cascade_ms[0] =
				renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Shadow)]
		}
		for mip_index in 1 ..< readback.hiz_mip_count {
			query_index := WGPU_GPU_HIZ_EXTRA_QUERY_BASE + (mip_index - 1) * 2
			begin := values[query_index]
			end := values[query_index + 1]
			if end >= begin {
				duration_ms := f64(end - begin) * renderer.gpu_timestamp_period_ns / 1_000_000.0
				renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.HiZ)] += duration_ms
				wgpu_gpu_timestamp_span_include(&timestamp_span, begin, end, true)
			}
		}
		if readback.phase_mask & (u32(1) << u32(WGPU_GPU_Timestamp_Phase.Shadow)) != 0 {
			for cascade_index in 1 ..< WGPU_SHADOW_CASCADE_COUNT {
				if readback.shadow_cascade_mask & (u32(1) << u32(cascade_index)) == 0 {
					continue
				}
				query_index := WGPU_GPU_SHADOW_EXTRA_QUERY_BASE + (cascade_index - 1) * 2
				begin := values[query_index]
				end := values[query_index + 1]
				if end >= begin {
					duration_ms :=
						f64(end - begin) * renderer.gpu_timestamp_period_ns / 1_000_000.0
					renderer.gpu_timestamp_shadow_cascade_ms[cascade_index] = duration_ms
					renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Shadow)] +=
						duration_ms
					wgpu_gpu_timestamp_span_include(&timestamp_span, begin, end, true)
				}
			}
		}
		if timestamp_span.has_frame && timestamp_span.has_scene {
			frame_ms, scene_ms, frame_span_valid = wgpu_gpu_span_ms(
				timestamp_span.frame_begin,
				timestamp_span.scene_end,
				timestamp_span.frame_end,
				renderer.gpu_timestamp_period_ns,
			)
		}
		if !frame_span_valid {
			wgpu.BufferUnmap(readback.buffer)
			continue
		}
		renderer.gpu_timestamp_frame_ms = frame_ms
		renderer.gpu_timestamp_scene_ms = scene_ms
		renderer.gpu_timestamp_valid = true
		wgpu_dynamic_resolution_accumulate_sample(
			renderer,
			readback.dynamic_resolution_generation,
			readback.frame_index,
			scene_ms,
		)
		profile_record_gpu_frame(
			renderer.profile,
			readback.frame_index,
			{
				frame = frame_ms,
				scene = scene_ms,
				instance_expansion = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Instance_Expansion)],
				clustered_lighting = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Clustered_Lighting)],
				cull = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Cull)] +
				renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Cull_Refine)],
				shadow = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Shadow)],
				shadow_cascades = renderer.gpu_timestamp_shadow_cascade_ms,
				depth = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Depth)] +
				renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Depth_Occluder)],
				world = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.World)],
				hiz = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.HiZ)],
				temporal_aa = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Temporal_AA)],
				ambient_occlusion = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Ambient_Occlusion)],
				screen_space_reflections = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Screen_Space_Reflections)],
				volumetric_fog = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Volumetric_Fog)],
				bloom = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Bloom)],
				automatic_exposure = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Automatic_Exposure)],
				composite = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Composite)],
				ui = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.UI)],
			},
		)
		wgpu.BufferUnmap(readback.buffer)
	}
}

wgpu_gpu_timing_begin_frame :: proc(renderer: ^WGPU_Renderer, frame_index: u64 = 0) {
	if renderer == nil {
		return
	}
	renderer.gpu_timestamp_active_slot = -1
	if !renderer.gpu_timestamp_supported || renderer.gpu_timestamp_query_set == nil {
		return
	}
	wgpu_gpu_timing_consume_readbacks(renderer)
	for offset in 0 ..< WGPU_GPU_TIMESTAMP_FRAMES {
		index := (renderer.gpu_timestamp_next_slot + offset) % WGPU_GPU_TIMESTAMP_FRAMES
		readback := &renderer.gpu_timestamp_readbacks[index]
		if !readback.pending {
			readback.phase_mask = 0
			readback.shadow_cascade_mask = 0
			readback.frame_index = frame_index
			renderer.gpu_timestamp_active_slot = index
			renderer.gpu_timestamp_next_slot = (index + 1) % WGPU_GPU_TIMESTAMP_FRAMES
			return
		}
	}
}

wgpu_gpu_timing_drain :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil || !renderer.gpu_timestamp_supported {
		return
	}
	wgpu.DevicePoll(renderer.device, true)
	wgpu.InstanceProcessEvents(renderer.instance)
	wgpu_gpu_timing_consume_readbacks(renderer)
}

wgpu_gpu_timing_active :: proc(renderer: ^WGPU_Renderer) -> bool {
	if renderer == nil ||
	   !renderer.gpu_timestamp_supported ||
	   renderer.gpu_timestamp_query_set == nil {
		return false
	}
	return(
		renderer.gpu_timestamp_active_slot >= 0 &&
		renderer.gpu_timestamp_active_slot < WGPU_GPU_TIMESTAMP_FRAMES \
	)
}

wgpu_gpu_pass_timestamps :: proc(
	renderer: ^WGPU_Renderer,
	phase: WGPU_GPU_Timestamp_Phase,
) -> (
	wgpu.PassTimestampWrites,
	bool,
) {
	if !wgpu_gpu_timing_active(renderer) {
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

wgpu_gpu_shadow_pass_timestamps :: proc(
	renderer: ^WGPU_Renderer,
	cascade_index: int,
) -> (
	wgpu.PassTimestampWrites,
	bool,
) {
	if !wgpu_gpu_timing_active(renderer) ||
	   cascade_index < 0 ||
	   cascade_index >= WGPU_SHADOW_CASCADE_COUNT {
		return {}, false
	}
	readback := &renderer.gpu_timestamp_readbacks[renderer.gpu_timestamp_active_slot]
	readback.shadow_cascade_mask |= u32(1) << u32(cascade_index)
	if cascade_index == 0 {
		return wgpu_gpu_pass_timestamps(renderer, .Shadow)
	}
	query_index := u32(WGPU_GPU_SHADOW_EXTRA_QUERY_BASE + (cascade_index - 1) * 2)
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
	if !wgpu_gpu_timing_active(renderer) || mip_index < 0 || mip_index >= WGPU_MAX_HIZ_LEVELS {
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
	if !wgpu_gpu_timing_active(renderer) {
		return
	}
	readback := &renderer.gpu_timestamp_readbacks[renderer.gpu_timestamp_active_slot]
	if wgpu.BufferGetSize(renderer.gpu_timestamp_resolve_buffer) <
		   wgpu_gpu_timestamp_resolve_bytes() ||
	   wgpu.BufferGetSize(readback.buffer) < wgpu_gpu_timestamp_bytes() {
		return
	}
	readback.hiz_mip_count = renderer.gpu_hiz_mip_count if renderer.gpu_hiz_requested else 0
	ranges, range_count := wgpu_gpu_timestamp_resolve_ranges(
		readback.phase_mask,
		readback.hiz_mip_count,
		readback.shadow_cascade_mask,
	)
	for resolve_range, range_index in ranges[:range_count] {
		resolve_offset := u64(range_index) * WGPU_GPU_TIMESTAMP_RESOLVE_ALIGNMENT
		copy_size := u64(resolve_range.count) * u64(size_of(u64))
		wgpu.CommandEncoderResolveQuerySet(
			encoder,
			renderer.gpu_timestamp_query_set,
			resolve_range.first,
			resolve_range.count,
			renderer.gpu_timestamp_resolve_buffer,
			resolve_offset,
		)
		wgpu.CommandEncoderCopyBufferToBuffer(
			encoder,
			renderer.gpu_timestamp_resolve_buffer,
			resolve_offset,
			readback.buffer,
			u64(resolve_range.first) * u64(size_of(u64)),
			copy_size,
		)
	}
}

wgpu_gpu_timing_after_submit :: proc(renderer: ^WGPU_Renderer) {
	if !wgpu_gpu_timing_active(renderer) {
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
	stats.gpu_scene_ms = renderer.gpu_timestamp_scene_ms
	stats.gpu_instance_expansion_ms =
		renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Instance_Expansion)]
	stats.gpu_clustered_lighting_ms =
		renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Clustered_Lighting)]
	stats.gpu_cull_ms =
		renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Cull)] +
		renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Cull_Refine)]
	stats.gpu_shadow_ms = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Shadow)]
	stats.gpu_shadow_cascade_ms = renderer.gpu_timestamp_shadow_cascade_ms
	stats.gpu_depth_ms =
		renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Depth)] +
		renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Depth_Occluder)]
	stats.gpu_world_ms = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.World)]
	stats.gpu_hiz_ms = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.HiZ)]
	stats.gpu_temporal_aa_ms =
		renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Temporal_AA)]
	stats.gpu_ambient_occlusion_ms =
		renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Ambient_Occlusion)]
	stats.gpu_screen_space_reflections_ms =
		renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Screen_Space_Reflections)]
	stats.gpu_volumetric_fog_ms =
		renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Volumetric_Fog)]
	stats.gpu_bloom_ms = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Bloom)]
	stats.gpu_automatic_exposure_ms =
		renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Automatic_Exposure)]
	stats.gpu_composite_ms =
		renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.Composite)]
	stats.gpu_post_ms =
		stats.gpu_temporal_aa_ms +
		stats.gpu_ambient_occlusion_ms +
		stats.gpu_screen_space_reflections_ms +
		stats.gpu_volumetric_fog_ms +
		stats.gpu_bloom_ms +
		stats.gpu_automatic_exposure_ms +
		stats.gpu_composite_ms
	stats.gpu_ui_ms = renderer.gpu_timestamp_phase_ms[int(WGPU_GPU_Timestamp_Phase.UI)]
	stats.hiz_occlusion = renderer.gpu_hiz_occlusion_enabled
	stats.hiz_occlusion_status = renderer.gpu_hiz_occlusion_status
	stats.hiz_instance_threshold = WGPU_HIZ_MIN_INSTANCES
	stats.hiz_valid = renderer.gpu_hiz_valid
	stats.hiz_mip_count = renderer.gpu_hiz_mip_count
}
