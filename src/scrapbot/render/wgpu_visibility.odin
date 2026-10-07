package render

import resources "../resources"
import shared "../shared"
import "core:os"
import "core:slice"
import "vendor:wgpu"

wgpu_validate_arena_ownership :: proc(
	allocator: ^WGPU_Arena_Allocator,
	owned: [dynamic]WGPU_Arena_Range,
) -> string {
	if allocator == nil {
		return "geometry arena allocator is unavailable"
	}
	slice.sort_by(owned[:], proc(a, b: WGPU_Arena_Range) -> bool {
		return a.offset < b.offset
	})
	owned_bytes: u64
	previous_end: u64
	for allocation, index in owned {
		if allocation.size == 0 {
			continue
		}
		allocation_end := allocation.offset + allocation.size
		if allocation_end < allocation.offset || allocation_end > allocator.high_water {
			return "geometry arena ownership exceeds the allocated address space"
		}
		if index > 0 && allocation.offset < previous_end {
			return "geometry arena ownership overlaps"
		}
		previous_end = allocation_end
		owned_bytes += allocation.size
	}
	if owned_bytes != allocator.resident_bytes {
		return "geometry arena resident-byte accounting disagrees with ownership"
	}
	for free_range in allocator.free_ranges {
		free_end := free_range.offset + free_range.size
		for allocation in owned {
			allocation_end := allocation.offset + allocation.size
			if allocation.offset < free_end && free_range.offset < allocation_end {
				return "geometry arena free space overlaps live ownership"
			}
		}
	}
	return ""
}


wgpu_visible_batch_word_count :: proc "contextless" (batch_count: int) -> int {
	return (clamp(batch_count, 0, WGPU_GPU_VISIBLE_BATCH_WORD_COUNT * 32) + 31) / 32
}

wgpu_create_visibility_readbacks :: proc(renderer: ^WGPU_Renderer) -> string {
	for &readback in renderer.gpu_visibility_readbacks {
		readback.buffer = wgpu_create_gpu_buffer(
			renderer,
			"Scrapbot GPU Visibility Readback",
			{.MapRead, .CopyDst},
			u64(size_of(WGPU_GPU_Visibility_Counters)),
		)
		if readback.buffer == nil {
			return "failed to create GPU visibility readback buffer"
		}
	}
	renderer.gpu_visibility_active_slot = -1
	return ""
}

wgpu_release_visibility_readbacks :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil {
		return
	}
	for &readback in renderer.gpu_visibility_readbacks {
		if readback.buffer == nil {
			continue
		}
		if readback.pending &&
		   readback.map_state.completed &&
		   readback.map_state.status == .Success {
			wgpu.BufferUnmap(readback.buffer)
		}
		wgpu.BufferRelease(readback.buffer)
		readback = {}
	}
}


wgpu_visibility_consume_readbacks :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
) -> string {
	if renderer == nil {
		return ""
	}
	wgpu.DevicePoll(renderer.device, false)
	for &readback in renderer.gpu_visibility_readbacks {
		if !readback.pending || !readback.map_state.completed {
			continue
		}
		readback.pending = false
		if readback.map_state.status != .Success {
			continue
		}
		// The visibility copy is encoded after every geometry pass. Mapping it proves
		// that all arena reads through this frame have completed, so retired ranges
		// may now re-enter the free lists.
		wgpu_geometry_arena_reclaim(&renderer.geometry_vertex_arena, readback.frame_index)
		wgpu_geometry_arena_reclaim(&renderer.geometry_index_arena, readback.frame_index)
		mapped := wgpu.BufferGetConstMappedRangeTyped(
			readback.buffer,
			0,
			WGPU_GPU_Visibility_Counters,
		)
		if mapped != nil {
			renderer.gpu_visibility_counters = mapped.summary
			if renderer.gpu_occlusion_debug_evidence_valid &&
			   mapped.summary.object_debug_records > 0 {
				renderer.gpu_occlusion_debug_record_count = mapped.summary.object_debug_records
			}
		}
		wgpu.BufferUnmap(readback.buffer)
	}
	return ""
}

wgpu_visibility_begin_frame :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
) -> string {
	if renderer == nil {
		return ""
	}
	if consume_err := wgpu_visibility_consume_readbacks(renderer, registry); consume_err != "" {
		return consume_err
	}
	renderer.gpu_visibility_active_slot = -1
	for offset in 0 ..< WGPU_GPU_TIMESTAMP_FRAMES {
		index := (renderer.gpu_visibility_next_slot + offset) % WGPU_GPU_TIMESTAMP_FRAMES
		if !renderer.gpu_visibility_readbacks[index].pending {
			renderer.gpu_visibility_active_slot = index
			renderer.gpu_visibility_next_slot = (index + 1) % WGPU_GPU_TIMESTAMP_FRAMES
			return ""
		}
	}
	return ""
}

wgpu_visibility_reset :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	batch_count: int,
) {
	if renderer == nil || encoder == nil {
		return
	}
	visible_batch_words := wgpu_visible_batch_word_count(batch_count)
	clear_size :=
		u64(size_of(WGPU_GPU_Visibility_Counters)) + u64(visible_batch_words * size_of(u32))
	wgpu.CommandEncoderClearBuffer(encoder, renderer.gpu_visibility_counter_buffer, 0, clear_size)
}

wgpu_visibility_resolve :: proc(renderer: ^WGPU_Renderer, encoder: wgpu.CommandEncoder) {
	if renderer == nil || renderer.gpu_visibility_active_slot < 0 {
		return
	}
	readback := &renderer.gpu_visibility_readbacks[renderer.gpu_visibility_active_slot]
	readback.frame_index = renderer.profile_frame_index
	wgpu.CommandEncoderCopyBufferToBuffer(
		encoder,
		renderer.gpu_visibility_counter_buffer,
		0,
		readback.buffer,
		0,
		u64(size_of(WGPU_GPU_Visibility_Counters)),
	)
}

wgpu_visibility_after_submit :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil || renderer.gpu_visibility_active_slot < 0 {
		return
	}
	readback := &renderer.gpu_visibility_readbacks[renderer.gpu_visibility_active_slot]
	readback.map_state = {}
	readback.pending = true
	wgpu.BufferMapAsync(
		readback.buffer,
		{.Read},
		0,
		uint(size_of(WGPU_GPU_Visibility_Counters)),
		wgpu.BufferMapCallbackInfo {
			mode = .AllowProcessEvents,
			callback = wgpu_buffer_map_callback,
			userdata1 = &readback.map_state,
		},
	)
	renderer.gpu_visibility_active_slot = -1
}

wgpu_publish_visibility :: proc(renderer: ^WGPU_Renderer, stats: ^Render_Stats) {
	if renderer == nil || stats == nil {
		return
	}
	stats.visible_instances = renderer.gpu_visibility_counters.visible_instances
	stats.visible_batches = renderer.gpu_visibility_counters.visible_batches
	stats.shadow_visible_instances = renderer.gpu_visibility_counters.shadow_visible_instances
	stats.frustum_candidates = renderer.gpu_visibility_counters.frustum_candidates
	stats.frustum_culled_instances = renderer.gpu_visibility_counters.frustum_culled_instances
	stats.occlusion_culled_instances = renderer.gpu_visibility_counters.occlusion_culled_instances
	stats.lod0_visible_instances = renderer.gpu_visibility_counters.lod_visible_instances[0]
	stats.lod1_visible_instances = renderer.gpu_visibility_counters.lod_visible_instances[1]
	stats.lod2_visible_instances = renderer.gpu_visibility_counters.lod_visible_instances[2]
	stats.lod3_visible_instances = renderer.gpu_visibility_counters.lod_visible_instances[3]

}
