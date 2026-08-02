package render

import resources "../resources"
import shared "../shared"
import "core:os"
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
	renderer.virtual_geometry_resident_bytes = 0
	renderer.virtual_geometry_page_count = 0
	renderer.virtual_geometry_resident_page_count = 0
	renderer.virtual_geometry_pinned_page_count = 0
	renderer.virtual_geometry_prefetched_page_count = 0
	renderer.gpu_compact_shadow_pages = false
	for cache in renderer.geometry_cache {
		if cache.virtual_geometry {
			renderer.virtual_geometry_resident_bytes +=
				cache.vertex_range.size + cache.index_range.size
			if cache.valid && cache.vertex_range.size == 0 {
				renderer.gpu_compact_shadow_pages = true
			}
		}
		renderer.virtual_geometry_page_count += len(cache.cluster_pages)
		for page in cache.cluster_pages {
			if page.pinned {
				renderer.virtual_geometry_pinned_page_count += 1
			}
			if page.resident {
				renderer.virtual_geometry_resident_page_count += 1
				if page.prefetched {
					renderer.virtual_geometry_prefetched_page_count += 1
				}
				renderer.virtual_geometry_resident_bytes +=
					page.range.size + page.vertex_range.size
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
			refined_resident, request_group, request_enabled := wgpu_cluster_group_residency(
				geometry_resource,
				geometry,
				cluster.refined_group,
			)
			first_index: u32
			base_vertex: u32
			if page_resident {
				page := geometry.cluster_pages[cluster.page]
				first_index =
					u32(page.range.offset / u64(size_of(u32))) + cluster.page_index_offset
				base_vertex = u32(page.vertex_range.offset / u64(size_of(resources.Vertex)))
			}
			info := &renderer.gpu_meshlet_infos[meshlet_index]
			info.first_index = first_index
			info.base_vertex = base_vertex
			info.page_resident = 1 if page_resident else 0
			info.refined_resident = 1 if refined_resident else 0
			info.group_index = u32(cluster.group)
			info.request_group_index = request_group
			info.request_enabled = 1 if request_enabled else 0
			info.identity &= 0xff3f_ffff
			if page_resident && geometry.cluster_pages[cluster.page].prefetched {
				info.identity |= 0x0040_0000
			}
			if !refined_resident {
				info.identity |= 0x0080_0000
			}
			template := &renderer.gpu_meshlet_indirect_templates[meshlet_index]
			template.index_count = cluster.triangle_count * 3 if page_resident else 0
			template.first_index = first_index
			template.base_vertex = i32(base_vertex)
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
		per_meshlet_capacity := wgpu_meshlet_visible_instance_capacity(batch.instance_count)
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

WGPU_VIRTUAL_PAGE_FEEDBACK_REQUEST :: u32(1)
WGPU_VIRTUAL_PAGE_FEEDBACK_TOUCH :: u32(2)
WGPU_VIRTUAL_PAGE_FEEDBACK_PREFETCH :: u32(4)
WGPU_VIRTUAL_PAGE_TOUCH_CADENCE :: u64(16)
WGPU_VIRTUAL_PAGE_FEEDBACK_GRACE_FRAMES ::
	WGPU_VIRTUAL_PAGE_TOUCH_CADENCE + u64(WGPU_GPU_TIMESTAMP_FRAMES * 2)

wgpu_virtual_page_admission_frame :: proc "contextless" (
	current_frame, feedback_frame: u64,
) -> u64 {
	// Feedback is asynchronous: residency begins when the upload is admitted,
	// never when the older request was produced.
	return max(current_frame, feedback_frame)
}

WGPU_Virtual_Group_Request :: struct {
	handle: shared.Geometry_Handle,
	group_index: u32,
	priority: f32,
	prefetch: bool,
}

wgpu_consume_virtual_page_io :: proc(renderer: ^WGPU_Renderer, registry: ^resources.Registry) {
	if renderer == nil || registry == nil {
		return
	}
	for {
		job, ok := wgpu_virtual_page_io_pop(&renderer.virtual_geometry_page_io)
		if !ok {
			break
		}
		geometry, geometry_ok := resources.get_geometry(registry, job.handle)
		cache_index := wgpu_geometry_cache_slot(renderer.geometry_cache[:], job.handle)
		if geometry_ok &&
		   geometry.version == job.geometry_version &&
		   cache_index >= 0 &&
		   int(job.page_index) < len(renderer.geometry_cache[cache_index].cluster_pages) {
			page := &renderer.geometry_cache[cache_index].cluster_pages[job.page_index]
			page.loading = false
			if !job.err {
				delete(page.loaded_payload, os.heap_allocator())
				page.loaded_payload = job.bytes
				renderer.virtual_geometry_page_read_count += 1
				renderer.virtual_geometry_page_read_bytes += u64(len(job.bytes))
				job.bytes = nil
			} else {
				renderer.virtual_geometry_page_read_failure_count += 1
			}
		}
		wgpu_virtual_page_io_destroy_job(job)
	}
}

wgpu_virtual_group_page_range :: proc "contextless" (
	geometry: ^resources.Geometry,
	group_index: u32,
) -> (
	page_offset, page_count: u32,
	ok: bool,
) {
	if geometry == nil || int(group_index) >= len(geometry.cluster_groups) {
		return 0, 0, false
	}
	group := geometry.cluster_groups[group_index]
	page_end := u64(group.page_offset) + u64(group.page_count)
	if group.page_count == 0 || page_end > u64(len(geometry.cluster_pages)) {
		return 0, 0, false
	}
	return group.page_offset, group.page_count, true
}

wgpu_touch_virtual_group :: proc "contextless" (
	cache: ^WGPU_Geometry_Cache,
	geometry: ^resources.Geometry,
	group_index: u32,
	frame: u64,
) -> (
	prefetch_hit: bool,
) {
	page_offset, page_count, ok := wgpu_virtual_group_page_range(geometry, group_index)
	if !ok || cache == nil || int(page_offset + page_count) > len(cache.cluster_pages) {
		return false
	}
	for page_index in page_offset ..< page_offset + page_count {
		page := &cache.cluster_pages[page_index]
		if page.resident {
			prefetch_hit = prefetch_hit || page.prefetched
			page.prefetched = false
			page.last_used_frame = max(page.last_used_frame, frame)
		}
	}
	return
}

wgpu_evict_virtual_group :: proc(
	renderer: ^WGPU_Renderer,
	protected_frame: u64,
	prefer_prefetched: bool,
) -> (
	handle: shared.Geometry_Handle,
	evicted: bool,
) {
	if renderer == nil {
		return {}, false
	}
	oldest_frame := ~u64(0)
	oldest_cache := -1
	oldest_group := ~u32(0)
	oldest_prefetched := false
	first_pass := 0 if prefer_prefetched else 1
	for selection_pass in first_pass ..< 2 {
		require_prefetched := selection_pass == 0
		for cache, cache_index in renderer.geometry_cache {
			page_index := 0
			for page_index < len(cache.cluster_pages) {
				group_index := cache.cluster_pages[page_index].group_index
				group_end := page_index
				resident := true
				pinned := false
				prefetched := true
				last_used: u64
				for group_end < len(cache.cluster_pages) &&
				    cache.cluster_pages[group_end].group_index == group_index {
					page := cache.cluster_pages[group_end]
					resident = resident && page.resident
					pinned = pinned || page.pinned
					prefetched = prefetched && page.prefetched
					last_used = max(last_used, page.last_used_frame)
					group_end += 1
				}
				old_enough :=
					protected_frame > WGPU_VIRTUAL_PAGE_FEEDBACK_GRACE_FRAMES &&
					last_used + WGPU_VIRTUAL_PAGE_FEEDBACK_GRACE_FRAMES < protected_frame
				eligible :=
					resident &&
					!pinned &&
					((require_prefetched && prefetched) || (!require_prefetched && old_enough))
				if eligible && last_used < oldest_frame {
					oldest_frame = last_used
					oldest_cache = cache_index
					oldest_group = group_index
					oldest_prefetched = prefetched
				}
				page_index = group_end
			}
		}
		if oldest_cache >= 0 {
			break
		}
	}
	if oldest_cache < 0 {
		return {}, false
	}
	cache := &renderer.geometry_cache[oldest_cache]
	for &page in cache.cluster_pages {
		if page.group_index != oldest_group || !page.resident {
			continue
		}
		renderer.virtual_geometry_resident_bytes -= min(
			renderer.virtual_geometry_resident_bytes,
			page.range.size + page.vertex_range.size,
		)
		wgpu_arena_release(&renderer.geometry_index_arena.allocator, page.range)
		wgpu_arena_release(&renderer.geometry_vertex_arena.allocator, page.vertex_range)
		page.range = {}
		page.vertex_range = {}
		page.resident = false
		page.prefetched = false
		renderer.virtual_geometry_page_eviction_count += 1
	}
	if oldest_prefetched {
		renderer.virtual_geometry_prefetch_eviction_count += 1
	}
	renderer.virtual_geometry_group_eviction_count += 1
	return cache.handle, true
}

wgpu_process_virtual_page_feedback :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
	counters: ^WGPU_GPU_Visibility_Counters,
	feedback_frame: u64,
	remaining_upload_bytes: ^u64,
	remaining_upload_groups: ^int,
) -> string {
	if renderer == nil ||
	   registry == nil ||
	   counters == nil ||
	   remaining_upload_bytes == nil ||
	   remaining_upload_groups == nil {
		return ""
	}
	feedback_count := min(
		int(counters.virtual_page_feedback_count),
		WGPU_VIRTUAL_PAGE_FEEDBACK_CAPACITY,
	)
	if feedback_count == 0 {
		return ""
	}
	requests := make(
		[dynamic]WGPU_Virtual_Group_Request,
		0,
		min(int(counters.virtual_page_request_count), feedback_count),
		context.temp_allocator,
	)
	prefetch_hit_handles := make([dynamic]shared.Geometry_Handle, 0, 0, context.temp_allocator)
	for feedback in counters.virtual_page_feedback[:feedback_count] {
		handle := shared.Geometry_Handle{feedback.geometry_index, feedback.geometry_generation}
		geometry, geometry_ok := resources.get_geometry(registry, handle)
		if !geometry_ok || int(feedback.group_index) >= len(geometry.cluster_groups) {
			continue
		}
		cache_index := wgpu_geometry_cache_slot(renderer.geometry_cache[:], handle)
		if cache_index < 0 {
			continue
		}
		cache := &renderer.geometry_cache[cache_index]
		if feedback.flags & WGPU_VIRTUAL_PAGE_FEEDBACK_TOUCH != 0 {
			if wgpu_touch_virtual_group(cache, geometry, feedback.group_index, feedback_frame) {
				renderer.virtual_geometry_prefetch_hit_count += 1
				if !slice.contains(prefetch_hit_handles[:], handle) {
					append(&prefetch_hit_handles, handle)
				}
			}
		}
		request := feedback.flags & WGPU_VIRTUAL_PAGE_FEEDBACK_REQUEST != 0
		prefetch := feedback.flags & WGPU_VIRTUAL_PAGE_FEEDBACK_PREFETCH != 0
		if request || prefetch {
			append(
				&requests,
				WGPU_Virtual_Group_Request {
					handle = handle,
					group_index = feedback.group_index,
					priority = feedback.priority,
					prefetch = !request,
				},
			)
		}
	}
	if len(requests) == 0 {
		for handle in prefetch_hit_handles {
			if refresh_err := wgpu_refresh_geometry_page_state(renderer, registry, handle);
			   refresh_err != "" {
				return refresh_err
			}
		}
		if len(prefetch_hit_handles) > 0 {
			wgpu_recount_virtual_page_residency(renderer)
		}
		return ""
	}
	slice.sort_by(requests[:], proc(a, b: WGPU_Virtual_Group_Request) -> bool {
		if a.handle.index != b.handle.index {
			return a.handle.index < b.handle.index
		}
		if a.handle.generation != b.handle.generation {
			return a.handle.generation < b.handle.generation
		}
		if a.group_index != b.group_index {
			return a.group_index < b.group_index
		}
		return a.priority > b.priority
	})
	unique_requests := make(
		[dynamic]WGPU_Virtual_Group_Request,
		0,
		len(requests),
		context.temp_allocator,
	)
	for request in requests {
		if len(unique_requests) > 0 {
			previous := &unique_requests[len(unique_requests) - 1]
			if previous.handle == request.handle && previous.group_index == request.group_index {
				previous.priority = max(previous.priority, request.priority)
				previous.prefetch = previous.prefetch && request.prefetch
				continue
			}
		}
		append(&unique_requests, request)
	}
	slice.sort_by(unique_requests[:], proc(a, b: WGPU_Virtual_Group_Request) -> bool {
		if a.prefetch != b.prefetch {
			return !a.prefetch
		}
		if a.priority != b.priority {
			return a.priority > b.priority
		}
		if a.handle.index != b.handle.index {
			return a.handle.index < b.handle.index
		}
		if a.handle.generation != b.handle.generation {
			return a.handle.generation < b.handle.generation
		}
		return a.group_index < b.group_index
	})
	changed_handles: [dynamic]shared.Geometry_Handle
	defer delete(changed_handles)
	append(&changed_handles, ..prefetch_hit_handles[:])
	for request in unique_requests {
		geometry, geometry_ok := resources.get_geometry(registry, request.handle)
		if !geometry_ok {
			continue
		}
		cache_index := wgpu_geometry_cache_slot(renderer.geometry_cache[:], request.handle)
		if cache_index < 0 {
			continue
		}
		cache := &renderer.geometry_cache[cache_index]
		resident, _, _ := wgpu_cluster_group_residency(geometry, cache, i32(request.group_index))
		if resident {
			if !request.prefetch &&
			   wgpu_touch_virtual_group(cache, geometry, request.group_index, feedback_frame) {
				renderer.virtual_geometry_prefetch_hit_count += 1
				if !slice.contains(changed_handles[:], request.handle) {
					append(&changed_handles, request.handle)
				}
			}
			continue
		}
		page_offset, page_count, range_ok := wgpu_virtual_group_page_range(
			geometry,
			request.group_index,
		)
		if !range_ok {
			continue
		}
		missing_pages := make([dynamic]u32, 0, int(page_count), context.temp_allocator)
		allocation_bytes: u64
		vertex_allocation_bytes: u64
		index_allocation_bytes: u64
		for page_index in page_offset ..< page_offset + page_count {
			if cache.cluster_pages[page_index].resident {
				continue
			}
			append(&missing_pages, page_index)
			record := geometry.page_payload_records[page_index]
			vertex_bytes := u64(record.vertex_count) * u64(size_of(resources.Vertex))
			index_bytes := u64(record.index_count) * u64(size_of(u32))
			vertex_allocation_bytes += wgpu_align_arena_offset(
				vertex_bytes,
				u64(size_of(resources.Vertex)),
			)
			index_allocation_bytes += wgpu_align_arena_offset(index_bytes, u64(size_of(u32)))
		}
		allocation_bytes = vertex_allocation_bytes + index_allocation_bytes
		if len(missing_pages) == 0 {
			continue
		}
		loaded_payloads: [][]u8
		if geometry.page_source_kind == .File {
			loaded_payloads = make([][]u8, len(missing_pages), context.temp_allocator)
			all_loaded := true
			for page_index, selection_index in missing_pages {
				page := &cache.cluster_pages[page_index]
				record := geometry.page_payload_records[page_index]
				if u64(len(page.loaded_payload)) == record.size {
					loaded_payloads[selection_index] = page.loaded_payload
					continue
				}
				all_loaded = false
				if page.loading {
					continue
				}
				if wgpu_virtual_page_io_schedule(
					&renderer.virtual_geometry_page_io,
					request.handle,
					geometry.version,
					page_index,
					geometry.page_source_path,
					record.offset,
					record.size,
				) {
					page.loading = true
				}
			}
			if !all_loaded {
				renderer.virtual_geometry_deferred_group_count += 1
				continue
			}
		}
		if remaining_upload_groups^ <= 0 || allocation_bytes > remaining_upload_bytes^ {
			renderer.virtual_geometry_deferred_group_count += 1
			continue
		}
		for renderer.virtual_geometry_resident_bytes + allocation_bytes >
		    renderer.virtual_geometry_budget_bytes {
			evicted_handle, evicted := wgpu_evict_virtual_group(
				renderer,
				renderer.profile_frame_index,
				!request.prefetch,
			)
			if !evicted {
				break
			}
			if !slice.contains(changed_handles[:], evicted_handle) {
				append(&changed_handles, evicted_handle)
			}
		}
		if renderer.virtual_geometry_resident_bytes + allocation_bytes >
		   renderer.virtual_geometry_budget_bytes {
			renderer.virtual_geometry_deferred_group_count += 1
			continue
		}
		upload, read_err := wgpu_read_virtual_pages(geometry, missing_pages[:], loaded_payloads)
		if read_err != "" {
			return read_err
		}
		vertex_bytes := u64(len(upload.vertices))
		index_bytes := u64(len(upload.indices)) * u64(size_of(u32))
		vertex_allocation := wgpu_arena_allocate(
			&renderer.geometry_vertex_arena.allocator,
			vertex_allocation_bytes,
			u64(size_of(resources.Vertex)),
		)
		index_allocation := wgpu_arena_allocate(
			&renderer.geometry_index_arena.allocator,
			index_allocation_bytes,
			u64(size_of(u32)),
		)
		previous_vertex_buffer := renderer.geometry_vertex_arena.buffer
		previous_index_buffer := renderer.geometry_index_arena.buffer
		if upload_err := wgpu_geometry_arena_upload(
			renderer,
			&renderer.geometry_vertex_arena,
			vertex_allocation,
			raw_data(upload.vertices),
			vertex_bytes,
		); upload_err != "" {
			wgpu_arena_release(&renderer.geometry_vertex_arena.allocator, vertex_allocation)
			wgpu_arena_release(&renderer.geometry_index_arena.allocator, index_allocation)
			return upload_err
		}
		if upload_err := wgpu_geometry_arena_upload(
			renderer,
			&renderer.geometry_index_arena,
			index_allocation,
			raw_data(upload.indices),
			index_bytes,
		); upload_err != "" {
			wgpu_arena_release(&renderer.geometry_vertex_arena.allocator, vertex_allocation)
			wgpu_arena_release(&renderer.geometry_index_arena.allocator, index_allocation)
			return upload_err
		}
		for page_index, selection_index in missing_pages {
			page := &cache.cluster_pages[page_index]
			page.range = {
				offset = index_allocation.offset + upload.index_offsets[selection_index],
				size = upload.index_offsets[selection_index + 1] - upload.index_offsets[selection_index],
			}
			page.vertex_range = {
				offset = vertex_allocation.offset + upload.vertex_offsets[selection_index],
				size = upload.vertex_offsets[selection_index + 1] - upload.vertex_offsets[selection_index],
			}
			page.resident = true
			page.prefetched = request.prefetch
			// The page becomes usable in this frame, not in the older frame that
			// produced its asynchronous request. Give a newly admitted group its
			// complete visible-use grace window so its first sampled touch can
			// arrive before eviction considers it stale.
			page.last_used_frame = wgpu_virtual_page_admission_frame(
				renderer.profile_frame_index,
				feedback_frame,
			)
			delete(page.loaded_payload, os.heap_allocator())
			page.loaded_payload = nil
		}
		renderer.virtual_geometry_resident_bytes += vertex_allocation.size + index_allocation.size
		renderer.virtual_geometry_page_upload_count += u64(len(missing_pages))
		renderer.virtual_geometry_page_upload_bytes += vertex_bytes + index_bytes
		renderer.virtual_geometry_group_upload_count += 1
		if request.prefetch {
			renderer.virtual_geometry_prefetch_group_upload_count += 1
		}
		remaining_upload_bytes^ -= allocation_bytes
		remaining_upload_groups^ -= 1
		if renderer.geometry_vertex_arena.buffer != previous_vertex_buffer ||
		   renderer.geometry_index_arena.buffer != previous_index_buffer {
			if bind_err := wgpu_rebuild_submission_bind_groups(renderer); bind_err != "" {
				return bind_err
			}
		}
		if !slice.contains(changed_handles[:], request.handle) {
			append(&changed_handles, request.handle)
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
	wgpu_consume_virtual_page_io(renderer, registry)
	wgpu.DevicePoll(renderer.device, false)
	remaining_upload_bytes := WGPU_VIRTUAL_GEOMETRY_UPLOAD_BUDGET_BYTES
	remaining_upload_groups := WGPU_VIRTUAL_GEOMETRY_UPLOAD_GROUP_BUDGET
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
		if request_err := wgpu_process_virtual_page_feedback(
			renderer,
			registry,
			&renderer.gpu_visibility_counters,
			readback.frame_index,
			&remaining_upload_bytes,
			&remaining_upload_groups,
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
	stats.visible_meshlet_draws = renderer.gpu_visibility_counters.visible_meshlet_draws
	stats.visible_virtual_clusters = renderer.gpu_visibility_counters.visible_virtual_clusters
	stats.virtual_rejected_clusters = renderer.gpu_visibility_counters.virtual_rejected_clusters
	stats.virtual_geometry_page_budget_bytes = renderer.virtual_geometry_budget_bytes
	stats.virtual_geometry_page_resident_bytes = renderer.virtual_geometry_resident_bytes
	stats.virtual_geometry_pages = renderer.virtual_geometry_page_count
	stats.virtual_geometry_resident_pages = renderer.virtual_geometry_resident_page_count
	stats.virtual_geometry_pinned_pages = renderer.virtual_geometry_pinned_page_count
	stats.virtual_geometry_prefetched_pages = renderer.virtual_geometry_prefetched_page_count
	stats.virtual_geometry_page_requests = min(
		renderer.gpu_visibility_counters.virtual_page_request_count,
		u32(WGPU_VIRTUAL_PAGE_FEEDBACK_CAPACITY),
	)
	stats.virtual_geometry_page_prefetches = min(
		renderer.gpu_visibility_counters.virtual_page_prefetch_count,
		u32(WGPU_VIRTUAL_PAGE_FEEDBACK_CAPACITY),
	)
	stats.virtual_geometry_page_request_overflow =
		renderer.gpu_visibility_counters.virtual_page_feedback_overflow
	stats.virtual_geometry_page_uploads = renderer.virtual_geometry_page_upload_count
	stats.virtual_geometry_page_upload_bytes = renderer.virtual_geometry_page_upload_bytes
	stats.virtual_geometry_page_reads = renderer.virtual_geometry_page_read_count
	stats.virtual_geometry_page_read_bytes = renderer.virtual_geometry_page_read_bytes
	stats.virtual_geometry_page_read_failures = renderer.virtual_geometry_page_read_failure_count
	stats.virtual_geometry_page_evictions = renderer.virtual_geometry_page_eviction_count
	stats.virtual_geometry_page_feedback = min(
		renderer.gpu_visibility_counters.virtual_page_feedback_count,
		u32(WGPU_VIRTUAL_PAGE_FEEDBACK_CAPACITY),
	)
	stats.virtual_geometry_group_uploads = renderer.virtual_geometry_group_upload_count
	stats.virtual_geometry_prefetch_group_uploads =
		renderer.virtual_geometry_prefetch_group_upload_count
	stats.virtual_geometry_prefetch_hits = renderer.virtual_geometry_prefetch_hit_count
	stats.virtual_geometry_prefetch_evictions = renderer.virtual_geometry_prefetch_eviction_count
	stats.virtual_geometry_group_evictions = renderer.virtual_geometry_group_eviction_count
	stats.virtual_geometry_deferred_groups = renderer.virtual_geometry_deferred_group_count
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
