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

wgpu_validate_virtual_geometry_arena_ownership :: proc(renderer: ^WGPU_Renderer) -> string {
	if renderer == nil {
		return ""
	}
	vertex_ranges := make([dynamic]WGPU_Arena_Range, 0, 0, context.temp_allocator)
	index_ranges := make([dynamic]WGPU_Arena_Range, 0, 0, context.temp_allocator)
	for cache in renderer.geometry_cache {
		if cache.vertex_range.size > 0 {
			append(&vertex_ranges, cache.vertex_range)
		}
		if cache.index_range.size > 0 {
			append(&index_ranges, cache.index_range)
		}
		if cache.shadow_index_range.size > 0 {
			append(&index_ranges, cache.shadow_index_range)
		}
		if cache.meshlet_index_range.size > 0 {
			append(&index_ranges, cache.meshlet_index_range)
		}
		for page in cache.cluster_pages {
			if !page.resident {
				continue
			}
			append(&vertex_ranges, page.vertex_range)
			append(&index_ranges, page.range)
		}
	}
	for retirement in renderer.geometry_vertex_arena.retirements {
		append(&vertex_ranges, retirement.range)
	}
	for retirement in renderer.geometry_index_arena.retirements {
		append(&index_ranges, retirement.range)
	}
	if err := wgpu_validate_arena_ownership(
		&renderer.geometry_vertex_arena.allocator,
		vertex_ranges,
	); err != "" {
		return err
	}
	return wgpu_validate_arena_ownership(&renderer.geometry_index_arena.allocator, index_ranges)
}

wgpu_validate_virtual_geometry_residency :: proc(renderer: ^WGPU_Renderer) -> string {
	if renderer == nil {
		return ""
	}
	for &cache in renderer.geometry_cache {
		expected_parent_refs := make([]u32, len(cache.cluster_groups), context.temp_allocator)
		for group, group_index in cache.cluster_groups {
			if group.active && !group.resident {
				return "active virtual-geometry group is not resident"
			}
			if !group.active {
				continue
			}
			if group_index + 1 >= len(cache.refined_group_parent_offsets) {
				continue
			}
			for parent_index in cache.refined_group_parent_offsets[group_index] ..< cache.refined_group_parent_offsets[group_index + 1] {
				parent_group := cache.refined_group_parents[parent_index]
				if int(parent_group) < len(expected_parent_refs) {
					expected_parent_refs[parent_group] += 1
				}
			}
		}
		for group, group_index in cache.cluster_groups {
			if group.resident_refinement_count != expected_parent_refs[group_index] {
				return "virtual-geometry fallback reference count is stale"
			}
			page_count: int
			resident_page_count: int
			for page in cache.cluster_pages {
				if page.group_index != u32(group_index) {
					continue
				}
				page_count += 1
				if page.resident {
					if !renderer.gpu_meshlet_native_multi_draw &&
					   (!wgpu_arena_range_within_limit(
								   page.vertex_range,
								   renderer.max_storage_buffer_binding_size,
							   ) ||
							   !wgpu_arena_range_within_limit(
									   page.range,
									   renderer.max_storage_buffer_binding_size,
								   )) {
						return(
							"resident virtual-geometry page exceeds the compact storage-binding window" \
						)
					}
					resident_page_count += 1
				}
			}
			if group.resident && (page_count == 0 || resident_page_count != page_count) {
				return "resident virtual-geometry group has missing pages"
			}
			if !group.resident && resident_page_count > 0 {
				return "nonresident virtual-geometry group owns resident pages"
			}
			if group.pinned && !group.resident {
				return "pinned virtual-geometry group is not resident"
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
	for &cache in renderer.geometry_cache {
		if cache.virtual_geometry {
			renderer.virtual_geometry_resident_bytes +=
				cache.vertex_range.size + cache.index_range.size + cache.shadow_index_range.size
			if wgpu_geometry_uses_compact_shadow_pages(&cache) {
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

WGPU_Virtual_Group_Parent :: struct {
	child: u32,
	parent: u32,
}

wgpu_build_refined_group_cluster_index :: proc(
	geometry: ^resources.Geometry,
) -> (
	cluster_offsets, clusters, parent_offsets, parents: [dynamic]u32,
) {
	if geometry == nil || len(geometry.cluster_groups) == 0 {
		return
	}
	resize(&cluster_offsets, len(geometry.cluster_groups) + 1)
	parent_pairs := make(
		[dynamic]WGPU_Virtual_Group_Parent,
		0,
		len(geometry.cluster_groups),
		context.temp_allocator,
	)
	for cluster in geometry.clusters {
		if cluster.refined_group >= 0 &&
		   int(cluster.refined_group) < len(geometry.cluster_groups) {
			cluster_offsets[cluster.refined_group + 1] += 1
			if cluster.group >= 0 && int(cluster.group) < len(geometry.cluster_groups) {
				append(
					&parent_pairs,
					WGPU_Virtual_Group_Parent {
						child = u32(cluster.refined_group),
						parent = u32(cluster.group),
					},
				)
			}
		}
	}
	for index in 1 ..< len(cluster_offsets) {
		cluster_offsets[index] += cluster_offsets[index - 1]
	}
	resize(&clusters, int(cluster_offsets[len(cluster_offsets) - 1]))
	cursors := make([]u32, len(geometry.cluster_groups), context.temp_allocator)
	copy(cursors, cluster_offsets[:len(cursors)])
	for cluster, cluster_index in geometry.clusters {
		if cluster.refined_group < 0 ||
		   int(cluster.refined_group) >= len(geometry.cluster_groups) {
			continue
		}
		group_index := int(cluster.refined_group)
		clusters[cursors[group_index]] = u32(cluster_index)
		cursors[group_index] += 1
	}
	slice.sort_by(parent_pairs[:], proc(a, b: WGPU_Virtual_Group_Parent) -> bool {
		if a.child != b.child {
			return a.child < b.child
		}
		return a.parent < b.parent
	})
	resize(&parent_offsets, len(geometry.cluster_groups) + 1)
	previous := WGPU_Virtual_Group_Parent {
		child = ~u32(0),
		parent = ~u32(0),
	}
	for pair in parent_pairs {
		if pair == previous {
			continue
		}
		parent_offsets[pair.child + 1] += 1
		append(&parents, pair.parent)
		previous = pair
	}
	for index in 1 ..< len(parent_offsets) {
		parent_offsets[index] += parent_offsets[index - 1]
	}
	return
}

wgpu_adjust_virtual_fallback_protection :: proc "contextless" (
	groups: []WGPU_Cluster_Group_Cache,
	parent_offsets, parents: []u32,
	child_group: u32,
	delta: int,
) {
	if int(child_group + 1) >= len(parent_offsets) {
		return
	}
	for parent_index in parent_offsets[child_group] ..< parent_offsets[child_group + 1] {
		parent_group := parents[parent_index]
		if int(parent_group) >= len(groups) {
			continue
		}
		if delta > 0 {
			groups[parent_group].resident_refinement_count += u32(delta)
		} else if delta < 0 {
			groups[parent_group].resident_refinement_count -= min(
				groups[parent_group].resident_refinement_count,
				u32(-delta),
			)
		}
	}
}

WGPU_Virtual_Group_Change :: struct {
	handle: shared.Geometry_Handle,
	group_index: u32,
}

wgpu_append_virtual_group_change :: proc(
	changes: ^[dynamic]WGPU_Virtual_Group_Change,
	handle: shared.Geometry_Handle,
	group_index: u32,
) {
	change := WGPU_Virtual_Group_Change {
		handle = handle,
		group_index = group_index,
	}
	if !slice.contains(changes[:], change) {
		append(changes, change)
	}
}

wgpu_refresh_virtual_group_changes :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
	changes: []WGPU_Virtual_Group_Change,
) -> string {
	processed_handles := make([dynamic]shared.Geometry_Handle, 0, 0, context.temp_allocator)
	for change in changes {
		if slice.contains(processed_handles[:], change.handle) {
			continue
		}
		append(&processed_handles, change.handle)
		handle_groups := make([dynamic]u32, 0, 0, context.temp_allocator)
		for candidate in changes {
			if candidate.handle == change.handle &&
			   !slice.contains(handle_groups[:], candidate.group_index) {
				append(&handle_groups, candidate.group_index)
			}
		}
		if refresh_err := wgpu_refresh_geometry_group_state(
			renderer,
			registry,
			change.handle,
			handle_groups[:],
		); refresh_err != "" {
			return refresh_err
		}
	}
	return ""
}

wgpu_refresh_geometry_group_state :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
	handle: shared.Geometry_Handle,
	changed_groups: []u32,
) -> string {
	if renderer == nil || registry == nil || len(changed_groups) == 0 {
		return ""
	}
	geometry_resource, ok := resources.get_geometry(registry, handle)
	if !ok {
		return ""
	}
	cache_index := wgpu_geometry_cache_slot_for_submission(
		renderer.geometry_cache[:],
		handle,
		true,
	)
	if cache_index < 0 {
		return ""
	}
	geometry := &renderer.geometry_cache[cache_index]
	dirty_clusters := make([dynamic]u32, 0, len(changed_groups) * 16, context.temp_allocator)
	for group_index in changed_groups {
		if int(group_index) >= len(geometry_resource.cluster_groups) {
			continue
		}
		group := geometry_resource.cluster_groups[group_index]
		cluster_end := min(
			u64(group.cluster_offset) + u64(group.cluster_count),
			u64(len(geometry_resource.clusters)),
		)
		for cluster_index in group.cluster_offset ..< u32(cluster_end) {
			append(&dirty_clusters, cluster_index)
		}
		if len(geometry.refined_group_cluster_offsets) !=
		   len(geometry_resource.cluster_groups) + 1 {
			continue
		}
		dependent_offset := geometry.refined_group_cluster_offsets[group_index]
		dependent_end := geometry.refined_group_cluster_offsets[group_index + 1]
		append(&dirty_clusters, ..geometry.refined_group_clusters[dependent_offset:dependent_end])
	}
	if len(dirty_clusters) == 0 {
		return ""
	}
	slice.sort(dirty_clusters[:])
	unique_count := 1
	for index in 1 ..< len(dirty_clusters) {
		if dirty_clusters[index] == dirty_clusters[unique_count - 1] {
			continue
		}
		dirty_clusters[unique_count] = dirty_clusters[index]
		unique_count += 1
	}
	resize(&dirty_clusters, unique_count)
	for batch in renderer.draw_batch_cache.batches[:renderer.draw_batch_cache.batch_count] {
		if !batch.virtual_geometry || batch.geometry != handle {
			continue
		}
		per_meshlet_capacity := wgpu_meshlet_visible_instance_capacity(batch.instance_count)
		for local_index_u32 in dirty_clusters {
			local_index := int(local_index_u32)
			cluster := geometry_resource.clusters[local_index]
			meshlet_index := int(batch.meshlet_draw_offset) + local_index
			if meshlet_index < 0 || meshlet_index >= len(renderer.gpu_meshlet_infos) {
				continue
			}
			page_resident :=
				int(cluster.page) < len(geometry.cluster_pages) &&
				geometry.cluster_pages[cluster.page].resident &&
				cluster.group >= 0 &&
				int(cluster.group) < len(geometry.cluster_groups) &&
				geometry.cluster_groups[cluster.group].active
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
			group_state := geometry.cluster_groups[cluster.group]
			info.transition_start = 0
			if group_state.active && !group_state.transition_complete {
				info.transition_start = wgpu_virtual_transition_token(
					group_state.transition_start_frame,
				)
			}
			info.refined_transition_start = 0
			if cluster.refined_group >= 0 &&
			   int(cluster.refined_group) < len(geometry.cluster_groups) {
				refined_state := geometry.cluster_groups[cluster.refined_group]
				if refined_state.active && !refined_state.transition_complete {
					info.refined_transition_start = wgpu_virtual_transition_token(
						refined_state.transition_start_frame,
					)
				}
			}
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
		run_offset := 0
		for run_offset < len(dirty_clusters) {
			run_end := run_offset + 1
			for run_end < len(dirty_clusters) &&
			    dirty_clusters[run_end] == dirty_clusters[run_end - 1] + 1 {
				run_end += 1
			}
			first_local := int(dirty_clusters[run_offset])
			last_local := int(dirty_clusters[run_end - 1]) + 1
			first_meshlet := int(batch.meshlet_draw_offset) + first_local
			last_meshlet := int(batch.meshlet_draw_offset) + last_local
			wgpu.QueueWriteBuffer(
				renderer.queue,
				renderer.gpu_meshlet_info_buffer,
				u64(first_meshlet) * u64(size_of(WGPU_GPU_Meshlet_Info)),
				raw_data(renderer.gpu_meshlet_infos[first_meshlet:last_meshlet]),
				uint((last_meshlet - first_meshlet) * size_of(WGPU_GPU_Meshlet_Info)),
			)
			wgpu.QueueWriteBuffer(
				renderer.queue,
				renderer.gpu_meshlet_indirect_template_buffer,
				u64(first_meshlet) * u64(size_of(WGPU_Draw_Indexed_Indirect)),
				raw_data(renderer.gpu_meshlet_indirect_templates[first_meshlet:last_meshlet]),
				uint((last_meshlet - first_meshlet) * size_of(WGPU_Draw_Indexed_Indirect)),
			)
			identity_count := (last_local - first_local) * int(per_meshlet_capacity)
			identities := make([]u32, identity_count, context.temp_allocator)
			for local_index in first_local ..< last_local {
				meshlet_index := int(batch.meshlet_draw_offset) + local_index
				identity := renderer.gpu_meshlet_infos[meshlet_index].identity
				identity_base := (local_index - first_local) * int(per_meshlet_capacity)
				for instance_index in 0 ..< int(per_meshlet_capacity) {
					identities[identity_base + instance_index] = identity
				}
			}
			identity_offset :=
				u64(batch.meshlet_visible_offset + u32(first_local) * per_meshlet_capacity) *
				u64(size_of(u32))
			wgpu.QueueWriteBuffer(
				renderer.queue,
				renderer.gpu_meshlet_identity_buffer,
				identity_offset,
				raw_data(identities),
				uint(len(identities) * size_of(u32)),
			)
			run_offset = run_end
		}
	}
	return ""
}

WGPU_VIRTUAL_PAGE_FEEDBACK_REQUEST :: u32(1)
WGPU_VIRTUAL_PAGE_FEEDBACK_TOUCH :: u32(2)
WGPU_VIRTUAL_PAGE_FEEDBACK_PREFETCH :: u32(4)
WGPU_VIRTUAL_PAGE_TOUCH_CADENCE :: u64(16)
WGPU_VIRTUAL_PAGE_FEEDBACK_GRACE_FRAMES ::
	WGPU_VIRTUAL_PAGE_TOUCH_CADENCE + u64(WGPU_GPU_TIMESTAMP_FRAMES * 2)
WGPU_VIRTUAL_PAGE_PRIORITY_HYSTERESIS :: f32(1.2)
WGPU_VIRTUAL_PAGE_MAX_HOLD_FRAMES :: WGPU_VIRTUAL_PAGE_FEEDBACK_GRACE_FRAMES * 3
WGPU_VIRTUAL_PAGE_STAGED_PAYLOAD_GRACE_FRAMES :: WGPU_VIRTUAL_PAGE_MAX_HOLD_FRAMES

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

WGPU_Virtual_Eviction_Candidate :: struct {
	cache_index: int,
	group_index: u32,
	last_used_frame: u64,
	priority: f32,
	prefetched: bool,
	expired: bool,
}

wgpu_build_virtual_eviction_candidates :: proc(
	renderer: ^WGPU_Renderer,
	protected_frame: u64,
) -> [dynamic]WGPU_Virtual_Eviction_Candidate {
	candidates := make([dynamic]WGPU_Virtual_Eviction_Candidate, 0, 0, context.temp_allocator)
	if renderer == nil {
		return candidates
	}
	for cache, cache_index in renderer.geometry_cache {
		for group, group_index in cache.cluster_groups {
			if !group.resident || group.pinned || group.resident_refinement_count > 0 {
				continue
			}
			old_enough :=
				protected_frame > WGPU_VIRTUAL_PAGE_FEEDBACK_GRACE_FRAMES &&
				group.last_used_frame + WGPU_VIRTUAL_PAGE_FEEDBACK_GRACE_FRAMES < protected_frame
			if !group.prefetched && !old_enough {
				continue
			}
			expired :=
				protected_frame > WGPU_VIRTUAL_PAGE_MAX_HOLD_FRAMES &&
				group.last_used_frame + WGPU_VIRTUAL_PAGE_MAX_HOLD_FRAMES < protected_frame
			append(
				&candidates,
				WGPU_Virtual_Eviction_Candidate {
					cache_index = cache_index,
					group_index = u32(group_index),
					last_used_frame = group.last_used_frame,
					priority = group.priority,
					prefetched = group.prefetched,
					expired = expired,
				},
			)
		}
	}
	slice.sort_by(candidates[:], proc(a, b: WGPU_Virtual_Eviction_Candidate) -> bool {
		if a.prefetched != b.prefetched {
			return a.prefetched
		}
		if a.expired != b.expired {
			return a.expired
		}
		if a.priority != b.priority {
			return a.priority < b.priority
		}
		return a.last_used_frame < b.last_used_frame
	})
	return candidates
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
		cache_index := wgpu_geometry_cache_slot_for_submission(
			renderer.geometry_cache[:],
			job.handle,
			true,
		)
		if geometry_ok &&
		   geometry.version == job.geometry_version &&
		   cache_index >= 0 &&
		   int(job.page_index) < len(renderer.geometry_cache[cache_index].cluster_pages) {
			page := &renderer.geometry_cache[cache_index].cluster_pages[job.page_index]
			page.loading = false
			if !job.err {
				renderer.virtual_geometry_staged_payload_bytes -= min(
					renderer.virtual_geometry_staged_payload_bytes,
					u64(len(page.loaded_payload)),
				)
				delete(page.loaded_payload, os.heap_allocator())
				page.loaded_payload = nil
				if wgpu_reserve_virtual_staged_payload(renderer, u64(len(job.bytes))) {
					page.loaded_payload = job.bytes
					renderer.virtual_geometry_staged_payload_bytes += u64(len(job.bytes))
					renderer.virtual_geometry_page_read_count += 1
					renderer.virtual_geometry_page_read_bytes += u64(len(job.bytes))
					job.bytes = nil
				}
			} else {
				renderer.virtual_geometry_page_read_failure_count += 1
			}
		}
		wgpu_virtual_page_io_destroy_job(job)
	}
}

wgpu_reserve_virtual_staged_payload :: proc(renderer: ^WGPU_Renderer, incoming: u64) -> bool {
	if renderer == nil || incoming > WGPU_VIRTUAL_GEOMETRY_STAGED_PAYLOAD_BUDGET_BYTES {
		return false
	}
	for renderer.virtual_geometry_staged_payload_bytes + incoming >
	    WGPU_VIRTUAL_GEOMETRY_STAGED_PAYLOAD_BUDGET_BYTES {
		oldest_cache := -1
		oldest_page := -1
		oldest_frame := ~u64(0)
		for &cache, cache_index in renderer.geometry_cache {
			for page, page_index in cache.cluster_pages {
				if page.resident ||
				   page.loading ||
				   len(page.loaded_payload) == 0 ||
				   page.last_used_frame >= oldest_frame {
					continue
				}
				oldest_cache = cache_index
				oldest_page = page_index
				oldest_frame = page.last_used_frame
			}
		}
		if oldest_cache < 0 {
			return false
		}
		page := &renderer.geometry_cache[oldest_cache].cluster_pages[oldest_page]
		renderer.virtual_geometry_staged_payload_bytes -= min(
			renderer.virtual_geometry_staged_payload_bytes,
			u64(len(page.loaded_payload)),
		)
		delete(page.loaded_payload, os.heap_allocator())
		page.loaded_payload = nil
	}
	return true
}

wgpu_discard_stale_virtual_page_payloads :: proc(
	renderer: ^WGPU_Renderer,
) -> (
	discarded_pages: u64,
	discarded_bytes: u64,
) {
	if renderer == nil ||
	   renderer.profile_frame_index <= WGPU_VIRTUAL_PAGE_STAGED_PAYLOAD_GRACE_FRAMES {
		return
	}
	stale_before := renderer.profile_frame_index - WGPU_VIRTUAL_PAGE_STAGED_PAYLOAD_GRACE_FRAMES
	for &cache in renderer.geometry_cache {
		for &page in cache.cluster_pages {
			if page.resident ||
			   page.loading ||
			   len(page.loaded_payload) == 0 ||
			   page.last_used_frame >= stale_before {
				continue
			}
			discarded_pages += 1
			discarded_bytes += u64(len(page.loaded_payload))
			renderer.virtual_geometry_staged_payload_bytes -= min(
				renderer.virtual_geometry_staged_payload_bytes,
				u64(len(page.loaded_payload)),
			)
			delete(page.loaded_payload, os.heap_allocator())
			page.loaded_payload = nil
		}
	}
	return
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

wgpu_virtual_group_pages_resident :: proc "contextless" (
	geometry: ^resources.Geometry,
	cache: ^WGPU_Geometry_Cache,
	group_index: u32,
) -> bool {
	page_offset, page_count, ok := wgpu_virtual_group_page_range(geometry, group_index)
	if !ok || cache == nil || int(page_offset + page_count) > len(cache.cluster_pages) {
		return false
	}
	for page_index in page_offset ..< page_offset + page_count {
		if !cache.cluster_pages[page_index].resident {
			return false
		}
	}
	return true
}

wgpu_virtual_transition_token :: proc "contextless" (frame: u64) -> u32 {
	token := u32(frame) + 1
	if token == 0 {
		return ~u32(0)
	}
	return token
}

wgpu_virtual_group_parents_settled :: proc "contextless" (
	cache: ^WGPU_Geometry_Cache,
	group_index: u32,
) -> bool {
	if cache == nil || int(group_index + 1) >= len(cache.refined_group_parent_offsets) {
		return true
	}
	for parent_index in cache.refined_group_parent_offsets[group_index] ..< cache.refined_group_parent_offsets[group_index + 1] {
		parent_group := cache.refined_group_parents[parent_index]
		if int(parent_group) >= len(cache.cluster_groups) {
			return false
		}
		parent := cache.cluster_groups[parent_group]
		if !parent.resident || !parent.active || !parent.transition_complete {
			return false
		}
	}
	return true
}

wgpu_finish_virtual_group_transitions :: proc(
	renderer: ^WGPU_Renderer,
	changes: ^[dynamic]WGPU_Virtual_Group_Change,
) {
	if renderer == nil || changes == nil {
		return
	}
	frame := renderer.profile_frame_index
	write_index := 0
	for transition in renderer.virtual_geometry_transitions {
		cache_index := wgpu_geometry_cache_slot_for_submission(
			renderer.geometry_cache[:],
			transition.handle,
			true,
		)
		if cache_index < 0 ||
		   int(transition.group_index) >=
			   len(renderer.geometry_cache[cache_index].cluster_groups) {
			continue
		}
		group := &renderer.geometry_cache[cache_index].cluster_groups[transition.group_index]
		if !group.resident || !group.active || group.transition_complete {
			continue
		}
		if frame < group.transition_start_frame + WGPU_VIRTUAL_GROUP_TRANSITION_FRAMES {
			renderer.virtual_geometry_transitions[write_index] = transition
			write_index += 1
			continue
		}
		group.transition_complete = true
		group.transition_start_frame = 0
		wgpu_append_virtual_group_change(changes, transition.handle, transition.group_index)
	}
	resize(&renderer.virtual_geometry_transitions, write_index)
}

wgpu_activate_stable_virtual_groups :: proc(
	renderer: ^WGPU_Renderer,
	changes: ^[dynamic]WGPU_Virtual_Group_Change,
) {
	if renderer == nil || changes == nil {
		return
	}
	frame := renderer.profile_frame_index
	write_index := 0
	for activation in renderer.virtual_geometry_pending_activations {
		cache_index := wgpu_geometry_cache_slot_for_submission(
			renderer.geometry_cache[:],
			activation.handle,
			true,
		)
		if cache_index < 0 ||
		   int(activation.group_index) >=
			   len(renderer.geometry_cache[cache_index].cluster_groups) {
			continue
		}
		cache := &renderer.geometry_cache[cache_index]
		group := &cache.cluster_groups[activation.group_index]
		if !group.resident || group.active || group.pinned {
			continue
		}
		settled := frame >= group.resident_since_frame + WGPU_VIRTUAL_GROUP_ACTIVATION_GRACE_FRAMES
		demand_quiet :=
			frame >= group.last_demand_frame + WGPU_VIRTUAL_GROUP_ACTIVATION_GRACE_FRAMES
		max_hold_elapsed :=
			frame >= group.resident_since_frame + WGPU_VIRTUAL_GROUP_ACTIVATION_MAX_HOLD_FRAMES
		parents_settled := wgpu_virtual_group_parents_settled(cache, activation.group_index)
		if !parents_settled || !settled || (!demand_quiet && !max_hold_elapsed) {
			renderer.virtual_geometry_pending_activations[write_index] = activation
			write_index += 1
			continue
		}
		group.active = true
		group.transition_complete = false
		group.transition_start_frame = frame
		renderer.virtual_geometry_group_activation_count += 1
		wgpu_append_virtual_group_change(
			&renderer.virtual_geometry_transitions,
			activation.handle,
			activation.group_index,
		)
		wgpu_adjust_virtual_fallback_protection(
			cache.cluster_groups[:],
			cache.refined_group_parent_offsets[:],
			cache.refined_group_parents[:],
			activation.group_index,
			1,
		)
		wgpu_append_virtual_group_change(changes, cache.handle, activation.group_index)
	}
	resize(&renderer.virtual_geometry_pending_activations, write_index)
}

wgpu_touch_virtual_group :: proc "contextless" (
	cache: ^WGPU_Geometry_Cache,
	geometry: ^resources.Geometry,
	group_index: u32,
	frame: u64,
	priority: f32,
) -> (
	prefetch_hit: bool,
	promoted_pages: u32,
) {
	page_offset, page_count, ok := wgpu_virtual_group_page_range(geometry, group_index)
	if !ok ||
	   cache == nil ||
	   int(group_index) >= len(cache.cluster_groups) ||
	   int(page_offset + page_count) > len(cache.cluster_pages) {
		return false, 0
	}
	group := &cache.cluster_groups[group_index]
	prefetch_hit = group.prefetched
	group.prefetched = false
	group.last_used_frame = max(group.last_used_frame, frame)
	group.priority = max(priority, 0)
	for page_index in page_offset ..< page_offset + page_count {
		page := &cache.cluster_pages[page_index]
		if page.resident {
			if page.prefetched {
				promoted_pages += 1
			}
			page.prefetched = false
			page.last_used_frame = max(page.last_used_frame, frame)
		}
	}
	return
}

wgpu_evict_virtual_group_at :: proc(
	renderer: ^WGPU_Renderer,
	cache_index: int,
	group_index: u32,
) -> (
	handle: shared.Geometry_Handle,
	evicted: bool,
) {
	if renderer == nil ||
	   cache_index < 0 ||
	   cache_index >= len(renderer.geometry_cache) ||
	   int(group_index) >= len(renderer.geometry_cache[cache_index].cluster_groups) {
		return {}, false
	}
	cache := &renderer.geometry_cache[cache_index]
	group := &cache.cluster_groups[group_index]
	if !group.resident || group.pinned || group.resident_refinement_count > 0 {
		return {}, false
	}
	if group.active {
		wgpu_adjust_virtual_fallback_protection(
			cache.cluster_groups[:],
			cache.refined_group_parent_offsets[:],
			cache.refined_group_parents[:],
			group_index,
			-1,
		)
	}
	oldest_prefetched := group.prefetched
	retire_after_frame := u64(0)
	if renderer.profile_frame_index > 0 {
		retire_after_frame = renderer.profile_frame_index - 1
	}
	for &page in cache.cluster_pages {
		if page.group_index != group_index || !page.resident {
			continue
		}
		renderer.virtual_geometry_resident_bytes -= min(
			renderer.virtual_geometry_resident_bytes,
			page.range.size + page.vertex_range.size,
		)
		wgpu_geometry_arena_retire(&renderer.geometry_index_arena, page.range, retire_after_frame)
		wgpu_geometry_arena_retire(
			&renderer.geometry_vertex_arena,
			page.vertex_range,
			retire_after_frame,
		)
		page.range = {}
		page.vertex_range = {}
		page.resident = false
		renderer.virtual_geometry_resident_page_count -= min(
			renderer.virtual_geometry_resident_page_count,
			1,
		)
		if page.prefetched {
			renderer.virtual_geometry_prefetched_page_count -= min(
				renderer.virtual_geometry_prefetched_page_count,
				1,
			)
		}
		page.prefetched = false
		renderer.virtual_geometry_page_eviction_count += 1
	}
	if oldest_prefetched {
		renderer.virtual_geometry_prefetch_eviction_count += 1
	}
	group.resident = false
	group.active = false
	group.transition_complete = false
	group.transition_start_frame = 0
	group.prefetched = false
	group.priority = 0
	renderer.virtual_geometry_group_eviction_count += 1
	return cache.handle, true
}

wgpu_evict_virtual_group :: proc(
	renderer: ^WGPU_Renderer,
	protected_frame: u64,
	prefer_prefetched: bool,
	incoming_priority: f32 = 0,
) -> (
	handle: shared.Geometry_Handle,
	group_index: u32,
	evicted: bool,
) {
	if renderer == nil {
		return {}, 0, false
	}
	oldest_frame := ~u64(0)
	oldest_cache := -1
	oldest_group := ~u32(0)
	first_pass := 0 if prefer_prefetched else 1
	for selection_pass in first_pass ..< 2 {
		require_prefetched := selection_pass == 0
		for cache, cache_index in renderer.geometry_cache {
			for group, group_index in cache.cluster_groups {
				last_used := group.last_used_frame
				old_enough :=
					protected_frame > WGPU_VIRTUAL_PAGE_FEEDBACK_GRACE_FRAMES &&
					last_used + WGPU_VIRTUAL_PAGE_FEEDBACK_GRACE_FRAMES < protected_frame
				priority_wins :=
					incoming_priority >= group.priority * WGPU_VIRTUAL_PAGE_PRIORITY_HYSTERESIS
				expired :=
					protected_frame > WGPU_VIRTUAL_PAGE_MAX_HOLD_FRAMES &&
					last_used + WGPU_VIRTUAL_PAGE_MAX_HOLD_FRAMES < protected_frame
				eligible :=
					group.resident &&
					!group.pinned &&
					group.resident_refinement_count == 0 &&
					((require_prefetched && group.prefetched) ||
							(!require_prefetched && old_enough && (priority_wins || expired)))
				if eligible && last_used < oldest_frame {
					oldest_frame = last_used
					oldest_cache = cache_index
					oldest_group = u32(group_index)
				}
			}
		}
		if oldest_cache >= 0 {
			break
		}
	}
	if oldest_cache < 0 {
		return {}, 0, false
	}
	handle, evicted = wgpu_evict_virtual_group_at(renderer, oldest_cache, oldest_group)
	return handle, oldest_group, evicted
}

wgpu_evict_virtual_candidate :: proc(
	renderer: ^WGPU_Renderer,
	candidates: []WGPU_Virtual_Eviction_Candidate,
	cursor: ^int,
	incoming_priority: f32,
) -> (
	handle: shared.Geometry_Handle,
	group_index: u32,
	evicted: bool,
) {
	if renderer == nil || cursor == nil {
		return {}, 0, false
	}
	for cursor^ < len(candidates) {
		candidate := candidates[cursor^]
		cursor^ += 1
		if candidate.cache_index < 0 || candidate.cache_index >= len(renderer.geometry_cache) {
			continue
		}
		cache := &renderer.geometry_cache[candidate.cache_index]
		if int(candidate.group_index) >= len(cache.cluster_groups) {
			continue
		}
		group := cache.cluster_groups[candidate.group_index]
		if !group.resident || group.pinned || group.resident_refinement_count > 0 {
			continue
		}
		priority_wins :=
			incoming_priority >= candidate.priority * WGPU_VIRTUAL_PAGE_PRIORITY_HYSTERESIS
		if !candidate.prefetched && !candidate.expired && !priority_wins {
			continue
		}
		handle, evicted = wgpu_evict_virtual_group_at(
			renderer,
			candidate.cache_index,
			candidate.group_index,
		)
		return handle, candidate.group_index, evicted
	}
	return {}, 0, false
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
	demand_feedback_count := min(
		int(counters.summary.virtual_page_demand_feedback_count),
		WGPU_VIRTUAL_PAGE_DEMAND_FEEDBACK_CAPACITY,
	)
	touch_feedback_count := min(
		int(counters.summary.virtual_page_touch_feedback_count),
		WGPU_VIRTUAL_PAGE_FEEDBACK_CAPACITY,
	)
	prefetch_feedback_count := min(
		int(counters.summary.virtual_page_prefetch_feedback_count),
		WGPU_VIRTUAL_PAGE_FEEDBACK_CAPACITY,
	)
	feedback_count := demand_feedback_count + touch_feedback_count + prefetch_feedback_count
	changed_groups: [dynamic]WGPU_Virtual_Group_Change
	defer delete(changed_groups)
	if feedback_count == 0 {
		wgpu_activate_stable_virtual_groups(renderer, &changed_groups)
		return wgpu_refresh_virtual_group_changes(renderer, registry, changed_groups[:])
	}
	if len(renderer.virtual_geometry_pending_activations) > 0 {
		// Activation is change-driven by the compact staged-group queue, even
		// when this readback carries only unrelated visibility feedback.
		wgpu_activate_stable_virtual_groups(renderer, &changed_groups)
	}
	requests := make(
		[dynamic]WGPU_Virtual_Group_Request,
		0,
		min(int(counters.summary.virtual_page_request_count), feedback_count),
		context.temp_allocator,
	)
	feedback_lanes := [?][]WGPU_GPU_Virtual_Page_Feedback {
		counters.virtual_page_touch_feedback[:touch_feedback_count],
		counters.virtual_page_demand_feedback[:demand_feedback_count],
		counters.virtual_page_prefetch_feedback[:prefetch_feedback_count],
	}
	for feedback_lane in feedback_lanes {
		for feedback in feedback_lane {
			handle := shared.Geometry_Handle{feedback.geometry_index, feedback.geometry_generation}
			geometry, geometry_ok := resources.get_geometry(registry, handle)
			if !geometry_ok || int(feedback.group_index) >= len(geometry.cluster_groups) {
				continue
			}
			cache_index := wgpu_geometry_cache_slot_for_submission(
				renderer.geometry_cache[:],
				handle,
				true,
			)
			if cache_index < 0 {
				continue
			}
			cache := &renderer.geometry_cache[cache_index]
			if feedback.flags & WGPU_VIRTUAL_PAGE_FEEDBACK_REQUEST != 0 {
				cache.cluster_groups[feedback.group_index].last_demand_frame =
					renderer.profile_frame_index
			}
			if feedback.flags & WGPU_VIRTUAL_PAGE_FEEDBACK_TOUCH != 0 {
				prefetch_hit, promoted_pages := wgpu_touch_virtual_group(
					cache,
					geometry,
					feedback.group_index,
					feedback_frame,
					feedback.priority,
				)
				renderer.virtual_geometry_prefetched_page_count -= min(
					renderer.virtual_geometry_prefetched_page_count,
					int(promoted_pages),
				)
				if prefetch_hit {
					renderer.virtual_geometry_prefetch_hit_count += 1
					wgpu_append_virtual_group_change(&changed_groups, handle, feedback.group_index)
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
	}
	if len(requests) == 0 {
		wgpu_activate_stable_virtual_groups(renderer, &changed_groups)
		if refresh_err := wgpu_refresh_virtual_group_changes(
			renderer,
			registry,
			changed_groups[:],
		); refresh_err != "" {
			return refresh_err
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
		a_priority := a.priority * (f32(0.75) if a.prefetch else f32(1))
		b_priority := b.priority * (f32(0.75) if b.prefetch else f32(1))
		if a_priority != b_priority {
			return a_priority > b_priority
		}
		if a.prefetch != b.prefetch {
			return !a.prefetch
		}
		if a.handle.index != b.handle.index {
			return a.handle.index < b.handle.index
		}
		if a.handle.generation != b.handle.generation {
			return a.handle.generation < b.handle.generation
		}
		return a.group_index < b.group_index
	})
	eviction_candidates := wgpu_build_virtual_eviction_candidates(
		renderer,
		renderer.profile_frame_index,
	)
	eviction_cursor := 0
	for request in unique_requests {
		geometry, geometry_ok := resources.get_geometry(registry, request.handle)
		if !geometry_ok {
			continue
		}
		cache_index := wgpu_geometry_cache_slot_for_submission(
			renderer.geometry_cache[:],
			request.handle,
			true,
		)
		if cache_index < 0 {
			continue
		}
		cache := &renderer.geometry_cache[cache_index]
		if wgpu_virtual_group_pages_resident(geometry, cache, request.group_index) {
			prefetch_hit := false
			promoted_pages: u32
			if !request.prefetch {
				prefetch_hit, promoted_pages = wgpu_touch_virtual_group(
					cache,
					geometry,
					request.group_index,
					feedback_frame,
					request.priority,
				)
			}
			renderer.virtual_geometry_prefetched_page_count -= min(
				renderer.virtual_geometry_prefetched_page_count,
				int(promoted_pages),
			)
			if prefetch_hit {
				renderer.virtual_geometry_prefetch_hit_count += 1
				wgpu_append_virtual_group_change(
					&changed_groups,
					request.handle,
					request.group_index,
				)
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
			cache.cluster_pages[page_index].last_used_frame = renderer.profile_frame_index
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
			evicted_handle, evicted_group, evicted := wgpu_evict_virtual_candidate(
				renderer,
				eviction_candidates[:],
				&eviction_cursor,
				request.priority,
			)
			if !evicted {
				break
			}
			wgpu_append_virtual_group_change(&changed_groups, evicted_handle, evicted_group)
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
		vertex_allocation, vertex_addressable := wgpu_arena_allocate_bounded(
			&renderer.geometry_vertex_arena.allocator,
			vertex_allocation_bytes,
			u64(size_of(resources.Vertex)),
			renderer.max_storage_buffer_binding_size,
		)
		if !vertex_addressable {
			renderer.virtual_geometry_deferred_group_count += 1
			continue
		}
		index_allocation, index_addressable := wgpu_arena_allocate_bounded(
			&renderer.geometry_index_arena.allocator,
			index_allocation_bytes,
			u64(size_of(u32)),
			renderer.max_storage_buffer_binding_size,
		)
		if !index_addressable {
			wgpu_arena_release(&renderer.geometry_vertex_arena.allocator, vertex_allocation)
			renderer.virtual_geometry_deferred_group_count += 1
			continue
		}
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
			renderer.virtual_geometry_staged_payload_bytes -= min(
				renderer.virtual_geometry_staged_payload_bytes,
				u64(len(page.loaded_payload)),
			)
			delete(page.loaded_payload, os.heap_allocator())
			page.loaded_payload = nil
		}
		group_state := &cache.cluster_groups[request.group_index]
		group_state.last_used_frame = wgpu_virtual_page_admission_frame(
			renderer.profile_frame_index,
			feedback_frame,
		)
		group_state.resident_since_frame = renderer.profile_frame_index
		group_state.priority = max(request.priority, 0)
		group_state.resident = true
		group_state.active = false
		group_state.transition_complete = false
		group_state.transition_start_frame = 0
		group_state.prefetched = request.prefetch
		wgpu_append_virtual_group_change(
			&renderer.virtual_geometry_pending_activations,
			request.handle,
			request.group_index,
		)
		renderer.virtual_geometry_resident_bytes += vertex_allocation.size + index_allocation.size
		renderer.virtual_geometry_resident_page_count += len(missing_pages)
		if request.prefetch {
			renderer.virtual_geometry_prefetched_page_count += len(missing_pages)
		}
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
		wgpu_append_virtual_group_change(&changed_groups, request.handle, request.group_index)
	}
	wgpu_activate_stable_virtual_groups(renderer, &changed_groups)
	if refresh_err := wgpu_refresh_virtual_group_changes(renderer, registry, changed_groups[:]);
	   refresh_err != "" {
		return refresh_err
	}
	return ""
}

wgpu_visibility_consume_readbacks :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
) -> string {
	if renderer == nil {
		return ""
	}
	transition_changes: [dynamic]WGPU_Virtual_Group_Change
	defer delete(transition_changes)
	wgpu_finish_virtual_group_transitions(renderer, &transition_changes)
	if transition_err := wgpu_refresh_virtual_group_changes(
		renderer,
		registry,
		transition_changes[:],
	); transition_err != "" {
		return transition_err
	}
	wgpu_consume_virtual_page_io(renderer, registry)
	wgpu_discard_stale_virtual_page_payloads(renderer)
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
			   mapped.summary.meshlet_debug_records > 0 {
				renderer.gpu_occlusion_debug_record_count = mapped.summary.meshlet_debug_records
			}
			if request_err := wgpu_process_virtual_page_feedback(
				renderer,
				registry,
				mapped,
				readback.frame_index,
				&remaining_upload_bytes,
				&remaining_upload_groups,
			); request_err != "" {
				wgpu.BufferUnmap(readback.buffer)
				return request_err
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
	if renderer.render_list.has_camera &&
	   renderer.render_list.camera.camera.debug_view == .Virtual_Geometry &&
	   renderer.profile_frame_index % 256 == 0 {
		if ownership_err := wgpu_validate_virtual_geometry_arena_ownership(renderer);
		   ownership_err != "" {
			return ownership_err
		}
		if residency_err := wgpu_validate_virtual_geometry_residency(renderer);
		   residency_err != "" {
			return residency_err
		}
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
	stats.visible_virtual_blend_clusters =
		renderer.gpu_visibility_counters.visible_virtual_blend_clusters
	stats.virtual_rejected_clusters = renderer.gpu_visibility_counters.virtual_rejected_clusters
	stats.virtual_geometry_page_budget_bytes = renderer.virtual_geometry_budget_bytes
	stats.virtual_geometry_page_resident_bytes = renderer.virtual_geometry_resident_bytes
	stats.virtual_geometry_error_pixels =
		renderer.dynamic_resolution.effective_virtual_error_pixels
	stats.virtual_geometry_pages = renderer.virtual_geometry_page_count
	stats.virtual_geometry_resident_pages = renderer.virtual_geometry_resident_page_count
	stats.virtual_geometry_pinned_pages = renderer.virtual_geometry_pinned_page_count
	stats.virtual_geometry_prefetched_pages = renderer.virtual_geometry_prefetched_page_count
	stats.virtual_geometry_page_requests = min(
		renderer.gpu_visibility_counters.virtual_page_request_count,
		u32(WGPU_VIRTUAL_PAGE_DEMAND_FEEDBACK_CAPACITY),
	)
	stats.virtual_geometry_page_prefetches = min(
		renderer.gpu_visibility_counters.virtual_page_prefetch_count,
		u32(WGPU_VIRTUAL_PAGE_FEEDBACK_CAPACITY),
	)
	stats.virtual_geometry_page_request_overflow =
		renderer.gpu_visibility_counters.virtual_page_demand_feedback_overflow +
		renderer.gpu_visibility_counters.virtual_page_touch_feedback_overflow +
		renderer.gpu_visibility_counters.virtual_page_prefetch_feedback_overflow
	stats.virtual_geometry_page_uploads = renderer.virtual_geometry_page_upload_count
	stats.virtual_geometry_page_upload_bytes = renderer.virtual_geometry_page_upload_bytes
	stats.virtual_geometry_page_reads = renderer.virtual_geometry_page_read_count
	stats.virtual_geometry_page_read_bytes = renderer.virtual_geometry_page_read_bytes
	stats.virtual_geometry_page_read_failures = renderer.virtual_geometry_page_read_failure_count
	stats.virtual_geometry_page_evictions = renderer.virtual_geometry_page_eviction_count
	stats.virtual_geometry_page_feedback =
		min(
			renderer.gpu_visibility_counters.virtual_page_demand_feedback_count,
			u32(WGPU_VIRTUAL_PAGE_DEMAND_FEEDBACK_CAPACITY),
		) +
		min(
			renderer.gpu_visibility_counters.virtual_page_touch_feedback_count,
			u32(WGPU_VIRTUAL_PAGE_FEEDBACK_CAPACITY),
		) +
		min(
			renderer.gpu_visibility_counters.virtual_page_prefetch_feedback_count,
			u32(WGPU_VIRTUAL_PAGE_FEEDBACK_CAPACITY),
		)
	stats.virtual_geometry_group_uploads = renderer.virtual_geometry_group_upload_count
	stats.virtual_geometry_group_activations = renderer.virtual_geometry_group_activation_count
	stats.virtual_geometry_transitioning_groups = u32(len(renderer.virtual_geometry_transitions))
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
	stats.shadow_visible_meshlets_by_cascade =
		renderer.gpu_visibility_counters.shadow_visible_meshlets_by_cascade
	stats.candidate_record_overflow = renderer.gpu_visibility_counters.candidate_record_overflow
	stats.visible_record_overflow = renderer.gpu_visibility_counters.visible_record_overflow
	stats.shadow_record_overflow = renderer.gpu_visibility_counters.shadow_record_overflow
	stats.frustum_culled_meshlets = renderer.gpu_visibility_counters.frustum_culled_meshlets
	stats.cone_culled_meshlets = renderer.gpu_visibility_counters.cone_culled_meshlets
	stats.occlusion_culled_meshlets = renderer.gpu_visibility_counters.occlusion_culled_meshlets
	stats.meshlet_debug_records = renderer.gpu_visibility_counters.meshlet_debug_records
	if renderer.gpu_occlusion_debug_evidence_valid && stats.meshlet_debug_records == 0 {
		stats.meshlet_debug_records = renderer.gpu_occlusion_debug_record_count
	}
}
