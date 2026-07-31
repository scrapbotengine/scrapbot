package render

import resources "../resources"
import shared "../shared"
import "core:slice"
import "vendor:wgpu"

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

wgpu_recount_virtual_page_residency :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil {
		return
	}
	renderer.virtual_geometry_index_resident_bytes = 0
	renderer.virtual_geometry_page_count = 0
	renderer.virtual_geometry_resident_page_count = 0
	renderer.virtual_geometry_pinned_page_count = 0
	for cache in renderer.geometry_cache {
		renderer.virtual_geometry_page_count += len(cache.cluster_pages)
		for page in cache.cluster_pages {
			if page.pinned {
				renderer.virtual_geometry_pinned_page_count += 1
			}
			if page.resident {
				renderer.virtual_geometry_resident_page_count += 1
				renderer.virtual_geometry_index_resident_bytes += page.range.size
			}
		}
	}
}

wgpu_refresh_geometry_page_state :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
	handle: shared.Geometry_Handle,
) -> string {
	if renderer == nil || registry == nil {
		return ""
	}
	geometry_resource, ok := resources.get_geometry(registry, handle)
	if !ok {
		return ""
	}
	cache_index := wgpu_geometry_cache_slot(renderer.geometry_cache[:], handle)
	if cache_index < 0 {
		return ""
	}
	geometry := &renderer.geometry_cache[cache_index]
	for batch in renderer.draw_batch_cache.batches[:renderer.draw_batch_cache.batch_count] {
		if !batch.virtual_geometry || batch.geometry != handle {
			continue
		}
		for cluster, local_index in geometry_resource.clusters {
			meshlet_index := int(batch.meshlet_draw_offset) + local_index
			if meshlet_index < 0 || meshlet_index >= len(renderer.gpu_meshlet_infos) {
				continue
			}
			page_resident :=
				int(cluster.page) < len(geometry.cluster_pages) &&
				geometry.cluster_pages[cluster.page].resident
			refined_resident, request_page, request_enabled := wgpu_cluster_group_residency(
				geometry_resource,
				geometry,
				cluster.refined_group,
			)
			first_index: u32
			if page_resident {
				page := geometry.cluster_pages[cluster.page]
				first_index =
					u32(page.range.offset / u64(size_of(u32))) + cluster.page_index_offset
			}
			info := &renderer.gpu_meshlet_infos[meshlet_index]
			info.first_index = first_index
			info.page_resident = 1 if page_resident else 0
			info.refined_resident = 1 if refined_resident else 0
			info.request_page_index = request_page
			info.request_enabled = 1 if request_enabled else 0
			info.identity &= 0xff7f_ffff
			if !refined_resident {
				info.identity |= 0x0080_0000
			}
			template := &renderer.gpu_meshlet_indirect_templates[meshlet_index]
			template.index_count = cluster.triangle_count * 3 if page_resident else 0
			template.first_index = first_index
		}
		byte_offset := u64(batch.meshlet_draw_offset) * u64(size_of(WGPU_GPU_Meshlet_Info))
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_meshlet_info_buffer,
			byte_offset,
			raw_data(renderer.gpu_meshlet_infos[int(batch.meshlet_draw_offset):]),
			uint(len(geometry_resource.clusters) * size_of(WGPU_GPU_Meshlet_Info)),
		)
		template_offset :=
			u64(batch.meshlet_draw_offset) * u64(size_of(WGPU_Draw_Indexed_Indirect))
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_meshlet_indirect_template_buffer,
			template_offset,
			raw_data(renderer.gpu_meshlet_indirect_templates[int(batch.meshlet_draw_offset):]),
			uint(len(geometry_resource.clusters) * size_of(WGPU_Draw_Indexed_Indirect)),
		)
		per_meshlet_capacity := wgpu_align_visible_capacity(batch.instance_count)
		identity_count := int(batch.meshlet_draw_count * per_meshlet_capacity)
		identities := make([]u32, identity_count, context.temp_allocator)
		for local_index in 0 ..< int(batch.meshlet_draw_count) {
			identity :=
				renderer.gpu_meshlet_infos[int(batch.meshlet_draw_offset) + local_index].identity
			for instance_index in 0 ..< int(per_meshlet_capacity) {
				identities[local_index * int(per_meshlet_capacity) + instance_index] = identity
			}
		}
		identity_offset := u64(batch.meshlet_visible_offset) * u64(size_of(u32))
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_meshlet_identity_buffer,
			identity_offset,
			raw_data(identities),
			uint(len(identities) * size_of(u32)),
		)
	}
	return ""
}

wgpu_evict_virtual_page :: proc(
	renderer: ^WGPU_Renderer,
	protected_frame: u64,
) -> (
	handle: shared.Geometry_Handle,
	evicted: bool,
) {
	oldest_frame := ~u64(0)
	oldest_cache := -1
	oldest_page := -1
	for cache, cache_index in renderer.geometry_cache {
		for page, page_index in cache.cluster_pages {
			if !page.resident || page.pinned || page.last_requested_frame == protected_frame {
				continue
			}
			if page.last_requested_frame < oldest_frame {
				oldest_frame = page.last_requested_frame
				oldest_cache = cache_index
				oldest_page = page_index
			}
		}
	}
	if oldest_cache < 0 {
		return {}, false
	}
	cache := &renderer.geometry_cache[oldest_cache]
	page := &cache.cluster_pages[oldest_page]
	renderer.virtual_geometry_index_resident_bytes -= min(
		renderer.virtual_geometry_index_resident_bytes,
		page.range.size,
	)
	wgpu_arena_release(&renderer.geometry_index_arena.allocator, page.range)
	page.range = {}
	page.resident = false
	renderer.virtual_geometry_page_eviction_count += 1
	return cache.handle, true
}

wgpu_process_virtual_page_requests :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
	counters: ^WGPU_GPU_Visibility_Counters,
) -> string {
	if renderer == nil || registry == nil || counters == nil {
		return ""
	}
	request_count := min(
		int(counters.virtual_page_request_count),
		WGPU_VIRTUAL_PAGE_REQUEST_CAPACITY,
	)
	if request_count == 0 {
		return ""
	}
	requests := make(
		[dynamic]WGPU_GPU_Virtual_Page_Request,
		0,
		request_count,
		context.temp_allocator,
	)
	append(&requests, ..counters.virtual_page_requests[:request_count])
	slice.sort_by(requests[:], proc(a, b: WGPU_GPU_Virtual_Page_Request) -> bool {
		if a.geometry_index != b.geometry_index {
			return a.geometry_index < b.geometry_index
		}
		if a.geometry_generation != b.geometry_generation {
			return a.geometry_generation < b.geometry_generation
		}
		return a.page_index < b.page_index
	})
	changed_handles: [dynamic]shared.Geometry_Handle
	defer delete(changed_handles)
	frame := renderer.profile_frame_index
	previous_request: WGPU_GPU_Virtual_Page_Request
	has_previous_request := false
	for request in requests {
		if has_previous_request && request == previous_request {
			continue
		}
		previous_request = request
		has_previous_request = true
		handle := shared.Geometry_Handle{request.geometry_index, request.geometry_generation}
		geometry, ok := resources.get_geometry(registry, handle)
		if !ok || int(request.page_index) >= len(geometry.cluster_pages) {
			continue
		}
		cache_index := wgpu_geometry_cache_slot(renderer.geometry_cache[:], handle)
		if cache_index < 0 {
			continue
		}
		cache := &renderer.geometry_cache[cache_index]
		page := &cache.cluster_pages[request.page_index]
		if page.last_requested_frame == frame {
			continue
		}
		page.last_requested_frame = frame
		if page.resident {
			continue
		}
		page_bytes :=
			u64(geometry.cluster_pages[request.page_index].index_count) * u64(size_of(u32))
		allocation_bytes := wgpu_align_arena_offset(page_bytes, u64(size_of(u32)))
		for renderer.virtual_geometry_index_resident_bytes + allocation_bytes >
		    renderer.virtual_geometry_index_budget_bytes {
			evicted_handle, evicted := wgpu_evict_virtual_page(renderer, frame)
			if !evicted {
				break
			}
			if !slice.contains(changed_handles[:], evicted_handle) {
				append(&changed_handles, evicted_handle)
			}
		}
		if renderer.virtual_geometry_index_resident_bytes + allocation_bytes >
		   renderer.virtual_geometry_index_budget_bytes {
			continue
		}
		indices, expand_err := wgpu_expand_cluster_page_indices(geometry, int(request.page_index))
		if expand_err != "" {
			return expand_err
		}
		allocation := wgpu_arena_allocate(
			&renderer.geometry_index_arena.allocator,
			allocation_bytes,
			u64(size_of(u32)),
		)
		previous_buffer := renderer.geometry_index_arena.buffer
		if upload_err := wgpu_geometry_arena_upload(
			renderer,
			&renderer.geometry_index_arena,
			allocation,
			raw_data(indices),
			page_bytes,
		); upload_err != "" {
			wgpu_arena_release(&renderer.geometry_index_arena.allocator, allocation)
			return upload_err
		}
		page.range = allocation
		page.resident = true
		renderer.virtual_geometry_index_resident_bytes += allocation.size
		renderer.virtual_geometry_page_upload_count += 1
		renderer.virtual_geometry_page_upload_bytes += page_bytes
		if renderer.geometry_index_arena.buffer != previous_buffer {
			if bind_err := wgpu_rebuild_submission_bind_groups(renderer); bind_err != "" {
				return bind_err
			}
		}
		if !slice.contains(changed_handles[:], handle) {
			append(&changed_handles, handle)
		}
	}
	for handle in changed_handles {
		if refresh_err := wgpu_refresh_geometry_page_state(renderer, registry, handle);
		   refresh_err != "" {
			return refresh_err
		}
	}
	wgpu_recount_virtual_page_residency(renderer)
	return ""
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
		mapped := wgpu.BufferGetConstMappedRangeTyped(
			readback.buffer,
			0,
			WGPU_GPU_Visibility_Counters,
		)
		if mapped != nil {
			renderer.gpu_visibility_counters = mapped^
			if renderer.gpu_occlusion_debug_evidence_valid && mapped.meshlet_debug_records > 0 {
				renderer.gpu_occlusion_debug_record_count = mapped.meshlet_debug_records
			}
		}
		wgpu.BufferUnmap(readback.buffer)
		if request_err := wgpu_process_virtual_page_requests(
			renderer,
			registry,
			&renderer.gpu_visibility_counters,
		); request_err != "" {
			return request_err
		}
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
	stats.visible_meshlet_draws = renderer.gpu_visibility_counters.visible_meshlet_draws
	stats.visible_virtual_clusters = renderer.gpu_visibility_counters.visible_virtual_clusters
	stats.virtual_rejected_clusters = renderer.gpu_visibility_counters.virtual_rejected_clusters
	stats.virtual_geometry_page_budget_bytes = renderer.virtual_geometry_index_budget_bytes
	stats.virtual_geometry_page_resident_bytes = renderer.virtual_geometry_index_resident_bytes
	stats.virtual_geometry_pages = renderer.virtual_geometry_page_count
	stats.virtual_geometry_resident_pages = renderer.virtual_geometry_resident_page_count
	stats.virtual_geometry_pinned_pages = renderer.virtual_geometry_pinned_page_count
	stats.virtual_geometry_page_requests = min(
		renderer.gpu_visibility_counters.virtual_page_request_count,
		u32(WGPU_VIRTUAL_PAGE_REQUEST_CAPACITY),
	)
	stats.virtual_geometry_page_request_overflow =
		renderer.gpu_visibility_counters.virtual_page_request_overflow
	stats.virtual_geometry_page_uploads = renderer.virtual_geometry_page_upload_count
	stats.virtual_geometry_page_upload_bytes = renderer.virtual_geometry_page_upload_bytes
	stats.virtual_geometry_page_evictions = renderer.virtual_geometry_page_eviction_count
	stats.shadow_visible_instances = renderer.gpu_visibility_counters.shadow_visible_instances
	stats.frustum_candidates = renderer.gpu_visibility_counters.frustum_candidates
	stats.frustum_culled_instances = renderer.gpu_visibility_counters.frustum_culled_instances
	stats.occlusion_culled_instances = renderer.gpu_visibility_counters.occlusion_culled_instances
	stats.lod0_visible_instances = renderer.gpu_visibility_counters.lod_visible_instances[0]
	stats.lod1_visible_instances = renderer.gpu_visibility_counters.lod_visible_instances[1]
	stats.lod2_visible_instances = renderer.gpu_visibility_counters.lod_visible_instances[2]
	stats.lod3_visible_instances = renderer.gpu_visibility_counters.lod_visible_instances[3]
	stats.visible_meshlets = renderer.gpu_visibility_counters.visible_meshlets
	stats.shadow_visible_meshlets = renderer.gpu_visibility_counters.shadow_visible_meshlets
	stats.frustum_culled_meshlets = renderer.gpu_visibility_counters.frustum_culled_meshlets
	stats.cone_culled_meshlets = renderer.gpu_visibility_counters.cone_culled_meshlets
	stats.occlusion_culled_meshlets = renderer.gpu_visibility_counters.occlusion_culled_meshlets
	stats.meshlet_debug_records = renderer.gpu_visibility_counters.meshlet_debug_records
	if renderer.gpu_occlusion_debug_evidence_valid && stats.meshlet_debug_records == 0 {
		stats.meshlet_debug_records = renderer.gpu_occlusion_debug_record_count
	}
}
