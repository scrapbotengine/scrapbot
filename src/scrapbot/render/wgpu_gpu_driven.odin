package render

import resources "../resources"
import shared "../shared"
import ui "../ui"
import "core:fmt"
import "core:math"
import "core:slice"
import "vendor:wgpu"

WGPU_INSTANCE_UPLOAD_MERGE_GAP :: 8
WGPU_INITIAL_MESHLET_DRAW_CAPACITY :: 256
WGPU_INITIAL_MESHLET_VISIBLE_CAPACITY :: 4096
WGPU_MESHLET_DEBUG_RECORD_CAPACITY :: 65_536
WGPU_MAX_MESHLET_VISIBLE_ENTRIES :: 1_048_576
WGPU_MESHLET_DEBUG_SPHERE_VERTEX_COUNT :: u32(144)
WGPU_OCCLUSION_DEBUG_RECT_VERTEX_COUNT :: u32(8)
WGPU_MESHLET_DEBUG_VERTEX_COUNT ::
	WGPU_MESHLET_DEBUG_SPHERE_VERTEX_COUNT + WGPU_OCCLUSION_DEBUG_RECT_VERTEX_COUNT
WGPU_MESHLET_MIN_BATCH_INSTANCES :: u32(2)
WGPU_AUTO_VIRTUAL_GEOMETRY_MIN_TRIANGLES :: u32(50_000)
WGPU_COMPACT_CLUSTER_VERTEX_COUNT :: u32(124 * 3)
WGPU_COMPACT_CLUSTER_BUCKET_COUNT :: 4
WGPU_COMPACT_CLUSTER_BUCKET_TRIANGLES :: [WGPU_COMPACT_CLUSTER_BUCKET_COUNT]u32{32, 64, 96, 124}
WGPU_SHADOW_CASCADE_UPDATE_CADENCE :: [WGPU_SHADOW_CASCADE_COUNT]u64{1, 2, 4, 8}
WGPU_SHADOW_CASCADE_UPDATE_OFFSET :: [WGPU_SHADOW_CASCADE_COUNT]u64{0, 0, 3, 5}

wgpu_shadow_cascade_update_mask :: proc "contextless" (frame_index: u64, force: bool) -> u32 {
	if force {
		return (u32(1) << WGPU_SHADOW_CASCADE_COUNT) - 1
	}
	mask: u32
	cadences := WGPU_SHADOW_CASCADE_UPDATE_CADENCE
	offsets := WGPU_SHADOW_CASCADE_UPDATE_OFFSET
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		cadence := cadences[cascade_index]
		if (frame_index + offsets[cascade_index]) % cadence == 0 {
			mask |= u32(1) << u32(cascade_index)
		}
	}
	return mask
}

wgpu_retain_shadow_cascades :: proc(
	renderer: ^WGPU_Renderer,
	desired: WGPU_Shadow_Cascades,
	active: bool,
	force: bool,
) -> WGPU_Shadow_Cascades {
	if renderer == nil || !active {
		if renderer != nil {
			renderer.shadow_cascades_valid = false
			renderer.shadow_cascade_render_mask = 0
		}
		return desired
	}
	force_refresh :=
		force ||
		!renderer.shadow_cascades_valid ||
		renderer.shadow_cascade_resolution != renderer.shadow_map_resolution
	mask := wgpu_shadow_cascade_update_mask(renderer.profile_frame_index, force_refresh)
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		if mask & (u32(1) << u32(cascade_index)) == 0 {
			continue
		}
		renderer.shadow_cascades.matrices[cascade_index] = desired.matrices[cascade_index]
		renderer.shadow_cascades.splits[cascade_index] = desired.splits[cascade_index]
		renderer.shadow_cascades.texel_sizes[cascade_index] = desired.texel_sizes[cascade_index]
	}
	renderer.shadow_cascades_valid = true
	renderer.shadow_cascade_resolution = renderer.shadow_map_resolution
	renderer.shadow_cascade_render_mask = mask
	return renderer.shadow_cascades
}

WGPU_Submission_Mode :: enum u32 {
	Classic,
	Meshlet,
	Compact,
}

WGPU_Draw_Submission_Span :: struct {
	next_batch: int,
	first_indirect: u32,
	indirect_count: u32,
	mode: WGPU_Submission_Mode,
}

wgpu_compact_cluster_bucket :: proc "contextless" (triangle_count: u32) -> int {
	for limit, bucket_index in WGPU_COMPACT_CLUSTER_BUCKET_TRIANGLES {
		if triangle_count <= limit {
			return bucket_index
		}
	}
	return WGPU_COMPACT_CLUSTER_BUCKET_COUNT - 1
}

wgpu_compact_cluster_bucket_vertex_count :: proc "contextless" (bucket_index: int) -> u32 {
	if bucket_index < 0 || bucket_index >= WGPU_COMPACT_CLUSTER_BUCKET_COUNT {
		return WGPU_COMPACT_CLUSTER_VERTEX_COUNT
	}
	limits := WGPU_COMPACT_CLUSTER_BUCKET_TRIANGLES
	return limits[bucket_index] * 3
}

wgpu_geometry_uses_virtual_clusters :: proc "contextless" (geometry: ^resources.Geometry) -> bool {
	return geometry != nil && len(geometry.cluster_groups) > 1 && geometry.cluster_max_depth > 0
}

wgpu_resolve_geometry_mode :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	geometry: ^resources.Geometry,
	instance_mode: shared.Geometry_Mode = .Inherit,
) -> shared.Geometry_Mode {
	mode := shared.geometry_mode_resolve(
		instance_mode,
		geometry.geometry_mode if geometry != nil else .Inherit,
		renderer.geometry_mode if renderer != nil else .Auto,
	)
	eligible :=
		renderer != nil &&
		renderer.gpu_meshlet_supported &&
		!renderer.cpu_culling &&
		wgpu_geometry_uses_virtual_clusters(geometry)
	if mode == .Virtual {
		return .Virtual if eligible else .Conventional
	}
	if mode == .Conventional || !eligible {
		return .Conventional
	}
	triangle_count := u32(resources.geometry_fallback_index_count(geometry) / 3)
	return(
		.Virtual if triangle_count >= WGPU_AUTO_VIRTUAL_GEOMETRY_MIN_TRIANGLES else .Conventional \
	)
}

wgpu_virtual_geometry_submission :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	geometry: ^resources.Geometry,
	instance_mode: shared.Geometry_Mode = .Inherit,
) -> bool {
	return wgpu_resolve_geometry_mode(renderer, geometry, instance_mode) == .Virtual
}

wgpu_geometry_draw_lod_count :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	geometry: ^resources.Geometry,
	instance_mode: shared.Geometry_Mode = .Inherit,
) -> int {
	if geometry == nil || wgpu_virtual_geometry_submission(renderer, geometry, instance_mode) {
		return 0
	}
	return geometry.lod_count
}

wgpu_virtual_geometry_uses_compaction :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	geometry: ^resources.Geometry,
	instance_mode: shared.Geometry_Mode = .Inherit,
) -> bool {
	return(
		wgpu_virtual_geometry_submission(renderer, geometry, instance_mode) &&
		!renderer.gpu_meshlet_native_multi_draw \
	)
}

wgpu_meshlet_submission_uses_compaction :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	meshlet_submission: bool,
) -> bool {
	return renderer != nil && meshlet_submission && !renderer.gpu_meshlet_native_multi_draw
}

wgpu_virtual_geometry_should_preload_pages :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	geometry: ^resources.Geometry,
	reclaimable_bytes: u64 = 0,
) -> bool {
	if renderer == nil || geometry == nil {
		return false
	}
	retained_bytes :=
		renderer.virtual_geometry_resident_bytes -
		min(renderer.virtual_geometry_resident_bytes, reclaimable_bytes)
	remaining_bytes :=
		renderer.virtual_geometry_budget_bytes -
		min(retained_bytes, renderer.virtual_geometry_budget_bytes)
	canonical_vertex_bytes := wgpu_align_arena_offset(
		u64(resources.geometry_canonical_vertex_count(geometry)) * u64(size_of(resources.Vertex)),
		u64(size_of(resources.Vertex)),
	)
	if canonical_vertex_bytes > remaining_bytes {
		return false
	}
	remaining_bytes -= canonical_vertex_bytes
	canonical_index_bytes := wgpu_align_arena_offset(
		u64(resources.geometry_fallback_index_count(geometry)) * u64(size_of(u32)),
		u64(size_of(u32)),
	)
	if canonical_index_bytes > remaining_bytes {
		return false
	}
	remaining_bytes -= canonical_index_bytes
	for page in geometry.cluster_pages {
		index_bytes := u64(page.index_count) * u64(size_of(u32))
		allocation_bytes := wgpu_align_arena_offset(index_bytes, u64(size_of(u32)))
		if allocation_bytes > remaining_bytes {
			return false
		}
		remaining_bytes -= allocation_bytes
	}
	return len(geometry.cluster_pages) > 0
}

wgpu_cached_virtual_geometry_bytes :: proc "contextless" (cache: ^WGPU_Geometry_Cache) -> u64 {
	if cache == nil || !cache.valid || !cache.virtual_geometry {
		return 0
	}
	bytes := cache.vertex_range.size + cache.index_range.size + cache.shadow_index_range.size
	for page in cache.cluster_pages {
		if page.resident {
			bytes += page.vertex_range.size + page.range.size
		}
	}
	return bytes
}

wgpu_cluster_group_residency :: proc "contextless" (
	geometry: ^resources.Geometry,
	cache: ^WGPU_Geometry_Cache,
	group_index: i32,
) -> (
	resident: bool,
	requested_group: u32,
	has_missing_group: bool,
) {
	if geometry == nil ||
	   cache == nil ||
	   group_index < 0 ||
	   int(group_index) >= len(geometry.cluster_groups) {
		return true, 0, false
	}
	group := geometry.cluster_groups[group_index]
	page_end := u64(group.page_offset) + u64(group.page_count)
	if group.page_count == 0 || page_end > u64(len(cache.cluster_pages)) {
		return false, 0, false
	}
	for page_index in group.page_offset ..< u32(page_end) {
		if !cache.cluster_pages[page_index].resident {
			return false, u32(group_index), true
		}
	}
	if int(group_index) >= len(cache.cluster_groups) ||
	   !cache.cluster_groups[group_index].active ||
	   !cache.cluster_groups[group_index].transition_complete {
		return false, u32(group_index), true
	}
	return true, 0, false
}

wgpu_meshlet_batch_submission :: proc "contextless" (meshlet_count, instance_count: u32) -> bool {
	return meshlet_count > 0 && instance_count >= WGPU_MESHLET_MIN_BATCH_INSTANCES
}

wgpu_effective_virtual_error_pixels :: proc "contextless" (renderer: ^WGPU_Renderer) -> f32 {
	if renderer == nil {
		return FRAME_BUDGET_VIRTUAL_ERROR_MINIMUM
	}
	error_pixels := renderer.dynamic_resolution.effective_virtual_error_pixels
	if renderer.gpu_compact_submission_active && renderer.gpu_virtual_batch_count > 0 {
		return max(error_pixels, WGPU_PORTABLE_COMPACT_VIRTUAL_ERROR_MINIMUM)
	}
	return error_pixels
}

wgpu_virtual_shadow_error_pixels :: proc "contextless" (
	camera_error_pixels: f32,
	cascade_index: int,
	resolution_scale: f32 = 1,
) -> f32 {
	// Compact shadow rendering executes one bucketed vertex-pulling record per
	// selected cluster. Keep its hierarchy comfortably below the shadow map's
	// texel density instead of spending portable-path invocations on geometry
	// that cannot change the stored shadow.
	multipliers := [4]f32{8, 32, 128, 512}
	return(
		camera_error_pixels *
		multipliers[clamp(cascade_index, 0, len(multipliers) - 1)] /
		max(resolution_scale, 0.01) \
	)
}

wgpu_meshlet_debug_forces_submission :: proc "contextless" (
	debug_view: shared.Render_Debug_View,
) -> bool {
	#partial switch debug_view {
		case .Meshlets, .Meshlet_Visibility, .Occlusion_Queries:
			return true
		case:
			return false
	}
}

wgpu_batch_uses_meshlets :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	batch: WGPU_Draw_Batch,
) -> bool {
	return(
		renderer != nil &&
		!batch.custom_shader &&
		renderer.gpu_meshlet_submission_active &&
		(renderer.gpu_meshlet_force_enabled || batch.meshlet_submission) \
	)
}

wgpu_batch_submission_mode :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	batch: WGPU_Draw_Batch,
) -> WGPU_Submission_Mode {
	if !wgpu_batch_uses_meshlets(renderer, batch) {
		return .Classic
	}
	if renderer.gpu_meshlet_force_enabled {
		return .Meshlet
	}
	if batch.compact_submission {
		return .Compact
	}
	return .Meshlet
}

wgpu_active_meshlet_draw_count :: proc "contextless" (renderer: ^WGPU_Renderer) -> int {
	if renderer == nil || !renderer.gpu_meshlet_submission_active {
		return 0
	}
	if renderer.gpu_meshlet_force_enabled {
		return renderer.gpu_meshlet_draw_count
	}
	return renderer.gpu_meshlet_selected_draw_count
}

wgpu_active_classic_batch_count :: proc "contextless" (renderer: ^WGPU_Renderer) -> int {
	if renderer == nil {
		return 0
	}
	if !renderer.gpu_meshlet_submission_active {
		return renderer.draw_batch_cache.batch_count
	}
	if renderer.gpu_meshlet_force_enabled {
		return 0
	}
	return renderer.gpu_classic_batch_count
}

wgpu_compact_shadow_pages_active :: proc "contextless" (renderer: ^WGPU_Renderer) -> bool {
	return renderer != nil && renderer.gpu_compact_shadow_pages
}

wgpu_geometry_uses_compact_shadow_pages :: proc "contextless" (
	geometry: ^WGPU_Geometry_Cache,
) -> bool {
	return(
		geometry != nil &&
		geometry.valid &&
		(!geometry.virtual_geometry || geometry.vertex_range.size == 0) \
	)
}

wgpu_batch_uses_compact_shadow_pages :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	batch: WGPU_Draw_Batch,
) -> bool {
	if renderer == nil || !batch.compact_submission {
		return false
	}
	cache_index := wgpu_geometry_cache_slot_for_submission(
		renderer.geometry_cache[:],
		batch.geometry,
		batch.virtual_geometry,
	)
	return(
		cache_index >= 0 &&
		wgpu_geometry_uses_compact_shadow_pages(&renderer.geometry_cache[cache_index]) \
	)
}

wgpu_draw_submission_span :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	batches: []WGPU_Draw_Batch,
	start: int,
) -> WGPU_Draw_Submission_Span {
	if renderer == nil || start < 0 || start >= len(batches) {
		return {next_batch = start + 1}
	}
	if !renderer.gpu_meshlet_supported {
		return {
			next_batch = start + 1,
			first_indirect = u32(start),
			indirect_count = 1,
			mode = .Classic,
		}
	}
	first := batches[start]
	mode := wgpu_batch_submission_mode(renderer, first)
	span := WGPU_Draw_Submission_Span {
		next_batch = start + 1,
		first_indirect = first.meshlet_draw_offset if mode == .Meshlet else (first.compact_command_index if mode == .Compact else u32(start)),
		indirect_count = first.meshlet_draw_count if mode == .Meshlet else (first.compact_command_count if mode == .Compact else 1),
		mode = mode,
	}
	for batch_index in start + 1 ..< len(batches) {
		batch := batches[batch_index]
		if batch.material != first.material ||
		   wgpu_batch_submission_mode(renderer, batch) != mode {
			break
		}
		span.next_batch = batch_index + 1
		if mode == .Meshlet {
			span.indirect_count += batch.meshlet_draw_count
		} else if mode == .Classic {
			span.indirect_count += 1
		}
	}
	return span
}

wgpu_draw_submission_count :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	batches: []WGPU_Draw_Batch,
) -> int {
	count := 0
	batch_index := 0
	for batch_index < len(batches) {
		span := wgpu_draw_submission_span(renderer, batches, batch_index)
		batch_index = span.next_batch
		count += int(span.indirect_count) if span.mode == .Compact else 1
	}
	return count
}

wgpu_shadow_batch_submission_mode :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	batch: WGPU_Draw_Batch,
) -> WGPU_Submission_Mode {
	mode := wgpu_batch_submission_mode(renderer, batch)
	if mode == .Compact && !wgpu_batch_uses_compact_shadow_pages(renderer, batch) {
		return .Classic
	}
	return mode
}

wgpu_shadow_draw_submission_span :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	batches: []WGPU_Draw_Batch,
	start: int,
) -> WGPU_Draw_Submission_Span {
	if renderer == nil || start < 0 || start >= len(batches) {
		return {next_batch = start + 1}
	}
	if !renderer.gpu_meshlet_supported {
		return {
			next_batch = start + 1,
			first_indirect = u32(start),
			indirect_count = 1,
			mode = .Classic,
		}
	}
	first := batches[start]
	mode := wgpu_shadow_batch_submission_mode(renderer, first)
	span := WGPU_Draw_Submission_Span {
		next_batch = start + 1,
		first_indirect = first.meshlet_draw_offset if mode == .Meshlet else (first.compact_command_index if mode == .Compact else u32(start)),
		indirect_count = first.meshlet_draw_count if mode == .Meshlet else (first.compact_command_count if mode == .Compact else 1),
		mode = mode,
	}
	for batch_index in start + 1 ..< len(batches) {
		batch := batches[batch_index]
		if batch.material != first.material ||
		   wgpu_shadow_batch_submission_mode(renderer, batch) != mode {
			break
		}
		span.next_batch = batch_index + 1
		if mode == .Meshlet {
			span.indirect_count += batch.meshlet_draw_count
		} else if mode == .Classic {
			span.indirect_count += 1
		}
	}
	return span
}

wgpu_shadow_draw_submission_count :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	batches: []WGPU_Draw_Batch,
) -> int {
	count := 0
	batch_index := 0
	for batch_index < len(batches) {
		span := wgpu_shadow_draw_submission_span(renderer, batches, batch_index)
		batch_index = span.next_batch
		count += int(span.indirect_count) if span.mode == .Compact else 1
	}
	return count
}

wgpu_assign_compact_submission_spans :: proc "contextless" (
	batches: []WGPU_Draw_Batch,
	first_command: u32,
) -> u32 {
	next_command := first_command
	batch_index := 0
	for batch_index < len(batches) {
		first := batches[batch_index]
		if !first.compact_submission {
			batch_index += 1
			continue
		}
		next_batch := batch_index + 1
		bucket_capacities := first.compact_visible_capacities
		for next_batch < len(batches) {
			next := batches[next_batch]
			if !next.compact_submission || next.material != first.material {
				break
			}
			for bucket_index in 0 ..< WGPU_COMPACT_CLUSTER_BUCKET_COUNT {
				bucket_capacities[bucket_index] += next.compact_visible_capacities[bucket_index]
			}
			next_batch += 1
		}
		bucket_offsets: [WGPU_COMPACT_CLUSTER_BUCKET_COUNT]u32
		bucket_commands := [WGPU_COMPACT_CLUSTER_BUCKET_COUNT]u32 {
			~u32(0),
			~u32(0),
			~u32(0),
			~u32(0),
		}
		record_offset := first.meshlet_visible_offset
		command_count: u32
		for capacity, bucket_index in bucket_capacities {
			bucket_offsets[bucket_index] = record_offset
			record_offset += capacity
			if capacity > 0 {
				bucket_commands[bucket_index] = next_command
				next_command += 1
				command_count += 1
			}
		}
		for compact_index in batch_index ..< next_batch {
			batches[compact_index].compact_command_index = next_command - command_count
			batches[compact_index].compact_command_count = command_count
			batches[compact_index].compact_bucket_commands = bucket_commands
			batches[compact_index].compact_visible_offsets = bucket_offsets
			batches[compact_index].compact_visible_capacities = bucket_capacities
		}
		batch_index = next_batch
	}
	return next_command
}

wgpu_meshlet_visible_buffer_bytes :: proc "contextless" (capacity: int) -> u64 {
	return u64(capacity) * u64(size_of(u32))
}

wgpu_compact_visible_buffer_bytes :: proc "contextless" (capacity: int) -> u64 {
	return u64(capacity) * u64(size_of(WGPU_GPU_Compact_Record))
}

wgpu_meshlet_debug_buffer_bytes :: proc "contextless" (capacity: int) -> u64 {
	return u64(capacity) * u64(size_of(WGPU_GPU_Meshlet_Debug_Record))
}

wgpu_meshlet_debug_record_offset :: proc "contextless" (
	camera: shared.Camera_Component,
	meshlet_submission_active: bool,
	visible_capacity: int,
	occlusion_evidence_valid: bool,
	force_capture := false,
) -> u32 {
	if !meshlet_submission_active || visible_capacity <= 0 {
		return 0
	}
	if force_capture {
		return 1
	}
	#partial switch camera.debug_view {
		case .Meshlet_Visibility:
			return 1
		case .Occlusion_Queries:
			if !camera.debug_occlusion_freeze || !occlusion_evidence_valid {
				return 1
			}
		case:
	}
	return 0
}

wgpu_expand_meshlet_indices :: proc(
	geometry: ^resources.Geometry,
	allocator := context.temp_allocator,
) -> (
	indices: []u32,
	err: string,
) {
	if geometry == nil {
		return nil, "meshlet geometry is not available"
	}
	index_count := 0
	for meshlet in geometry.meshlets {
		index_count += int(meshlet.triangle_count * 3)
	}
	if index_count <= 0 {
		return nil, "meshlet geometry has no triangle indices"
	}
	indices = make([]u32, index_count, allocator)
	cursor := 0
	for meshlet in geometry.meshlets {
		vertex_start := int(meshlet.vertex_offset)
		triangle_start := int(meshlet.triangle_offset)
		for local_index in 0 ..< int(meshlet.triangle_count * 3) {
			triangle_index := triangle_start + local_index
			if triangle_index < 0 || triangle_index >= len(geometry.meshlet_triangles) {
				return nil, "meshlet triangle stream is out of bounds"
			}
			vertex_index := vertex_start + int(geometry.meshlet_triangles[triangle_index])
			if vertex_index < 0 || vertex_index >= len(geometry.meshlet_vertices) {
				return nil, "meshlet vertex stream is out of bounds"
			}
			indices[cursor] = geometry.meshlet_vertices[vertex_index]
			cursor += 1
		}
	}
	return
}

wgpu_expand_cluster_indices :: proc(
	geometry: ^resources.Geometry,
	allocator := context.temp_allocator,
) -> (
	indices: []u32,
	err: string,
) {
	if geometry == nil {
		return nil, "cluster geometry is not available"
	}
	index_count := 0
	for cluster in geometry.clusters {
		index_count += int(cluster.triangle_count * 3)
	}
	if index_count <= 0 {
		return nil, "cluster hierarchy has no triangle indices"
	}
	indices = make([]u32, index_count, allocator)
	cursor := 0
	for cluster in geometry.clusters {
		vertex_start := int(cluster.vertex_offset)
		triangle_start := int(cluster.triangle_offset)
		for local_index in 0 ..< int(cluster.triangle_count * 3) {
			triangle_index := triangle_start + local_index
			if triangle_index < 0 || triangle_index >= len(geometry.cluster_triangles) {
				return nil, "cluster triangle stream is out of bounds"
			}
			vertex_index := vertex_start + int(geometry.cluster_triangles[triangle_index])
			if vertex_index < 0 || vertex_index >= len(geometry.cluster_vertices) {
				return nil, "cluster vertex stream is out of bounds"
			}
			indices[cursor] = geometry.cluster_vertices[vertex_index]
			cursor += 1
		}
	}
	return
}

wgpu_expand_cluster_page_indices :: proc(
	geometry: ^resources.Geometry,
	page_index: int,
	allocator := context.temp_allocator,
) -> (
	indices: []u32,
	err: string,
) {
	if geometry == nil || page_index < 0 || page_index >= len(geometry.cluster_pages) {
		return nil, "cluster page is not available"
	}
	page := geometry.cluster_pages[page_index]
	if page.index_count == 0 {
		return nil, "cluster page has no triangle indices"
	}
	indices = make([]u32, int(page.index_count), allocator)
	cursor := 0
	cluster_end := int(page.cluster_offset + page.cluster_count)
	if cluster_end > len(geometry.clusters) {
		return nil, "cluster page range is out of bounds"
	}
	for cluster in geometry.clusters[page.cluster_offset:cluster_end] {
		vertex_start := int(cluster.vertex_offset)
		triangle_start := int(cluster.triangle_offset)
		for local_index in 0 ..< int(cluster.triangle_count * 3) {
			triangle_index := triangle_start + local_index
			if triangle_index < 0 || triangle_index >= len(geometry.cluster_triangles) {
				return nil, "cluster page triangle stream is out of bounds"
			}
			vertex_index := vertex_start + int(geometry.cluster_triangles[triangle_index])
			if vertex_index < 0 || vertex_index >= len(geometry.cluster_vertices) {
				return nil, "cluster page vertex stream is out of bounds"
			}
			indices[cursor] = geometry.cluster_vertices[vertex_index]
			cursor += 1
		}
	}
	if cursor != len(indices) {
		return nil, "cluster page index count does not match its clusters"
	}
	return
}

wgpu_expand_cluster_pages_indices :: proc(
	geometry: ^resources.Geometry,
	page_indices: []u32,
	allocator := context.temp_allocator,
) -> (
	indices: []u32,
	page_offsets: []u32,
	err: string,
) {
	if geometry == nil || len(page_indices) == 0 {
		return nil, nil, "cluster page selection is empty"
	}
	total_indices: u64
	for page_index in page_indices {
		if int(page_index) >= len(geometry.cluster_pages) {
			return nil, nil, "cluster page selection is out of bounds"
		}
		total_indices += u64(geometry.cluster_pages[page_index].index_count)
	}
	if total_indices == 0 || total_indices > u64(~u32(0)) {
		return nil, nil, "cluster page selection size is invalid"
	}
	indices = make([]u32, int(total_indices), allocator)
	page_offsets = make([]u32, len(page_indices) + 1, allocator)
	cursor: u32
	for page_index, selection_index in page_indices {
		page_offsets[selection_index] = cursor
		page_indices_data, page_err := wgpu_expand_cluster_page_indices(
			geometry,
			int(page_index),
			allocator,
		)
		if page_err != "" {
			return nil, nil, page_err
		}
		copy(indices[int(cursor):], page_indices_data)
		cursor += u32(len(page_indices_data))
	}
	page_offsets[len(page_indices)] = cursor
	return
}

WGPU_Virtual_Page_Upload :: struct {
	vertices: []u8,
	indices: []u32,
	vertex_offsets: []u64,
	index_offsets: []u64,
}

wgpu_read_virtual_pages :: proc(
	geometry: ^resources.Geometry,
	page_indices: []u32,
	page_payloads: [][]u8 = nil,
	allocator := context.temp_allocator,
) -> (
	WGPU_Virtual_Page_Upload,
	string,
) {
	if geometry == nil || len(page_indices) == 0 {
		return {}, "virtual geometry page selection is empty"
	}
	vertex_bytes: u64
	index_bytes: u64
	for page_index in page_indices {
		if int(page_index) >= len(geometry.page_payload_records) {
			return {}, "virtual geometry page selection is out of bounds"
		}
		record := geometry.page_payload_records[page_index]
		vertex_bytes += u64(record.vertex_count) * u64(size_of(resources.Vertex))
		index_bytes += u64(record.index_count) * u64(size_of(u32))
	}
	if vertex_bytes > u64(max(int)) || index_bytes > u64(max(int)) {
		return {}, "virtual geometry page selection is too large"
	}
	result := WGPU_Virtual_Page_Upload {
		vertices = make([]u8, int(vertex_bytes), allocator),
		indices = make([]u32, int(index_bytes / u64(size_of(u32))), allocator),
		vertex_offsets = make([]u64, len(page_indices) + 1, allocator),
		index_offsets = make([]u64, len(page_indices) + 1, allocator),
	}
	vertex_cursor: u64
	index_cursor: u64
	for page_index, selection_index in page_indices {
		record := geometry.page_payload_records[page_index]
		payload: []u8
		if len(page_payloads) == len(page_indices) {
			payload = page_payloads[selection_index]
		} else {
			read_err: string
			payload, read_err = resources.read_geometry_page_payload(
				geometry,
				int(page_index),
				allocator,
			)
			if read_err != "" {
				return {}, read_err
			}
		}
		page_vertex_bytes := u64(record.vertex_count) * u64(size_of(resources.Vertex))
		page_index_bytes := u64(record.index_count) * u64(size_of(u32))
		if u64(len(payload)) != page_vertex_bytes + page_index_bytes {
			return {}, "virtual geometry page payload size is invalid"
		}
		result.vertex_offsets[selection_index] = vertex_cursor
		result.index_offsets[selection_index] = index_cursor
		copy(result.vertices[int(vertex_cursor):], payload[:int(page_vertex_bytes)])
		index_target := (cast([^]u8)raw_data(result.indices))[:len(result.indices) * size_of(u32)]
		copy(
			index_target[int(index_cursor):],
			payload[int(page_vertex_bytes):int(page_vertex_bytes + page_index_bytes)],
		)
		vertex_cursor += page_vertex_bytes
		index_cursor += page_index_bytes
	}
	result.vertex_offsets[len(page_indices)] = vertex_cursor
	result.index_offsets[len(page_indices)] = index_cursor
	return result, ""
}

wgpu_rebase_virtual_page_indices :: proc(
	indices: []u32,
	vertex_offsets: []u64,
	index_offsets: []u64,
	allocator := context.temp_allocator,
) -> []u32 {
	if len(vertex_offsets) != len(index_offsets) || len(vertex_offsets) < 2 {
		return nil
	}
	result := make([]u32, len(indices), allocator)
	copy(result, indices)
	for page_index in 0 ..< len(vertex_offsets) - 1 {
		vertex_base := u32(vertex_offsets[page_index] / u64(size_of(resources.Vertex)))
		index_start := int(index_offsets[page_index] / u64(size_of(u32)))
		index_end := int(index_offsets[page_index + 1] / u64(size_of(u32)))
		if index_end < index_start || index_end > len(result) {
			return nil
		}
		for index in index_start ..< index_end {
			result[index] += vertex_base
		}
	}
	return result
}

wgpu_virtual_group_is_pinned :: proc "contextless" (
	geometry: ^resources.Geometry,
	group_index: i32,
) -> bool {
	if geometry == nil || group_index < 0 || int(group_index) >= len(geometry.cluster_groups) {
		return false
	}
	group := geometry.cluster_groups[group_index]
	if group.page_count == 0 ||
	   int(group.page_offset + group.page_count) > len(geometry.cluster_pages) {
		return false
	}
	for page_index in group.page_offset ..< group.page_offset + group.page_count {
		if !geometry.cluster_pages[page_index].pinned {
			return false
		}
	}
	return true
}

wgpu_build_virtual_terminal_frontier_indices :: proc(
	geometry: ^resources.Geometry,
	page_indices: []u32,
	upload: ^WGPU_Virtual_Page_Upload,
	allocator := context.temp_allocator,
) -> []u32 {
	if geometry == nil ||
	   upload == nil ||
	   len(upload.vertex_offsets) != len(page_indices) + 1 ||
	   len(upload.index_offsets) != len(page_indices) + 1 {
		return nil
	}
	page_selections := make([]int, len(geometry.cluster_pages), context.temp_allocator)
	for &selection in page_selections {
		selection = -1
	}
	for page_index, selection_index in page_indices {
		if int(page_index) >= len(page_selections) {
			return nil
		}
		page_selections[page_index] = selection_index
	}
	pinned_groups := make([]bool, len(geometry.cluster_groups), context.temp_allocator)
	for _, group_index in geometry.cluster_groups {
		pinned_groups[group_index] = wgpu_virtual_group_is_pinned(geometry, i32(group_index))
	}
	result := make([dynamic]u32, 0, len(upload.indices), allocator)
	for cluster in geometry.clusters {
		if cluster.group < 0 ||
		   int(cluster.group) >= len(pinned_groups) ||
		   !pinned_groups[cluster.group] ||
		   (cluster.refined_group >= 0 &&
				   int(cluster.refined_group) < len(pinned_groups) &&
				   pinned_groups[cluster.refined_group]) ||
		   int(cluster.page) >= len(page_selections) {
			continue
		}
		selection_index := page_selections[cluster.page]
		if selection_index < 0 {
			continue
		}
		index_start :=
			int(upload.index_offsets[selection_index] / u64(size_of(u32))) +
			int(cluster.page_index_offset)
		index_end := index_start + int(cluster.triangle_count * 3)
		if index_start < 0 || index_end > len(upload.indices) {
			return nil
		}
		vertex_base := u32(upload.vertex_offsets[selection_index] / u64(size_of(resources.Vertex)))
		for index in upload.indices[index_start:index_end] {
			append(&result, index + vertex_base)
		}
	}
	return result[:]
}

wgpu_align_visible_capacity :: proc(count: u32) -> u32 {
	return(
		((max(count, 1) + WGPU_VISIBLE_ALIGNMENT - 1) / WGPU_VISIBLE_ALIGNMENT) *
		WGPU_VISIBLE_ALIGNMENT \
	)
}

wgpu_meshlet_visible_instance_capacity :: proc "contextless" (count: u32) -> u32 {
	return max(count, 1)
}

wgpu_meshlet_batch_visible_capacity :: proc(
	meshlet_count, instance_count: u32,
) -> (
	capacity: u32,
	ok: bool,
) {
	// Whole-batch slices become dynamic storage bindings and retain 256-byte
	// alignment. Meshlet slices are addressed only by element index through one
	// shared binding, so exact instance cardinality is both valid and materially
	// smaller for large single-instance hierarchies.
	value := u64(meshlet_count) * u64(wgpu_meshlet_visible_instance_capacity(instance_count))
	if value > u64(WGPU_MAX_MESHLET_VISIBLE_ENTRIES) {
		return 0, false
	}
	return u32(value), true
}

wgpu_create_gpu_world_pipeline :: proc(
	renderer: ^WGPU_Renderer,
	vertex_layout: ^wgpu.VertexBufferLayout,
	cull_mode: wgpu.CullMode,
	label: string,
	vertex_entry: string = "vs_main",
) -> wgpu.RenderPipeline {
	targets := [3]wgpu.ColorTargetState {
		{format = .RGBA16Float, writeMask = wgpu.ColorWriteMaskFlags_All},
		{format = .RGBA16Float, writeMask = wgpu.ColorWriteMaskFlags_All},
		{format = .RGBA16Float, writeMask = wgpu.ColorWriteMaskFlags_All},
	}
	fragment := wgpu.FragmentState {
		module = renderer.gpu_driven_shader,
		entryPoint = "fs_main",
		targetCount = len(targets),
		targets = raw_data(targets[:]),
	}
	return wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = label,
			layout = renderer.gpu_driven_pipeline_layout,
			vertex = {
				module = renderer.gpu_driven_shader,
				entryPoint = vertex_entry,
				bufferCount = 1,
				buffers = vertex_layout,
			},
			primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = cull_mode},
			depthStencil = &wgpu.DepthStencilState {
				format = .Depth24Plus,
				depthWriteEnabled = .False,
				depthCompare = .LessEqual,
			},
			multisample = {count = 1, mask = 0xFFFF_FFFF},
			fragment = &fragment,
		},
	)
}

wgpu_create_meshlet_debug_pipeline :: proc(renderer: ^WGPU_Renderer) -> string {
	source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_MESHLET_DEBUG_SHADER,
	}
	renderer.gpu_meshlet_debug_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &source,
			label = "Scrapbot Meshlet Debug Shader",
		},
	)
	if renderer.gpu_meshlet_debug_shader == nil {
		return "failed to create meshlet debug shader"
	}
	entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Vertex},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_GPU_Render_Uniform))},
		},
		{
			binding = 1,
			visibility = {.Vertex},
			buffer = {
				type = .ReadOnlyStorage,
				minBindingSize = u64(size_of(WGPU_GPU_Meshlet_Debug_Record)),
			},
		},
	}
	renderer.gpu_meshlet_debug_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot Meshlet Debug Bind Group Layout",
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
	if renderer.gpu_meshlet_debug_bind_group_layout == nil {
		return "failed to create meshlet debug bind group layout"
	}
	renderer.gpu_meshlet_debug_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot Meshlet Debug Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.gpu_meshlet_debug_bind_group_layout,
		},
	)
	if renderer.gpu_meshlet_debug_pipeline_layout == nil {
		return "failed to create meshlet debug pipeline layout"
	}
	target := wgpu.ColorTargetState {
		format = .RGBA16Float,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}
	fragment := wgpu.FragmentState {
		module = renderer.gpu_meshlet_debug_shader,
		entryPoint = "debug_fs",
		targetCount = 1,
		targets = &target,
	}
	renderer.gpu_meshlet_debug_pipeline = wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&wgpu.RenderPipelineDescriptor {
			label = "Scrapbot Meshlet Debug Pipeline",
			layout = renderer.gpu_meshlet_debug_pipeline_layout,
			vertex = {module = renderer.gpu_meshlet_debug_shader, entryPoint = "debug_vs"},
			primitive = {topology = .LineList, frontFace = .CCW, cullMode = .None},
			multisample = {count = 1, mask = 0xFFFF_FFFF},
			fragment = &fragment,
		},
	)
	if renderer.gpu_meshlet_debug_pipeline == nil {
		return "failed to create meshlet debug pipeline"
	}
	return ""
}

wgpu_create_gpu_depth_pipeline :: proc(
	renderer: ^WGPU_Renderer,
	vertex_layout: ^wgpu.VertexBufferLayout,
	cull_mode: wgpu.CullMode,
	masked: bool,
	label: string,
	vertex_entry: string = "depth_vs",
) -> wgpu.RenderPipeline {
	desc := wgpu.RenderPipelineDescriptor {
		label = label,
		layout = renderer.gpu_driven_depth_pipeline_layout,
		vertex = {
			module = renderer.gpu_driven_shader,
			entryPoint = vertex_entry,
			bufferCount = 1,
			buffers = vertex_layout,
		},
		primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = cull_mode},
		depthStencil = &wgpu.DepthStencilState {
			format = .Depth24Plus,
			depthWriteEnabled = .True,
			depthCompare = .Less,
		},
		multisample = {count = 1, mask = 0xFFFF_FFFF},
	}
	fragment: wgpu.FragmentState
	if masked {
		desc.layout = renderer.gpu_driven_depth_mask_pipeline_layout
		fragment = {
			module = renderer.gpu_driven_shader,
			entryPoint = "mask_fs",
		}
		desc.fragment = &fragment
	}
	return wgpu.DeviceCreateRenderPipeline(renderer.device, &desc)
}

wgpu_create_gpu_shadow_pipeline :: proc(
	renderer: ^WGPU_Renderer,
	vertex_layout: ^wgpu.VertexBufferLayout,
	cull_mode: wgpu.CullMode,
	masked: bool,
	label: string,
	vertex_entry: string = "shadow_vs",
) -> wgpu.RenderPipeline {
	desc := wgpu.RenderPipelineDescriptor {
		label = label,
		layout = renderer.gpu_driven_shadow_pipeline_layout,
		vertex = {
			module = renderer.gpu_driven_shader,
			entryPoint = vertex_entry,
			bufferCount = 1,
			buffers = vertex_layout,
		},
		primitive = {topology = .TriangleList, frontFace = .CCW, cullMode = cull_mode},
		depthStencil = &wgpu.DepthStencilState {
			format = .Depth32Float,
			depthWriteEnabled = .True,
			depthCompare = .Less,
			depthBias = 2,
			depthBiasSlopeScale = 2,
		},
		multisample = {count = 1, mask = 0xFFFF_FFFF},
	}
	fragment: wgpu.FragmentState
	if masked {
		desc.layout = renderer.gpu_driven_shadow_mask_pipeline_layout
		fragment = {
			module = renderer.gpu_driven_shader,
			entryPoint = "mask_fs",
		}
		desc.fragment = &fragment
	}
	return wgpu.DeviceCreateRenderPipeline(renderer.device, &desc)
}

wgpu_create_gpu_buffer :: proc(
	renderer: ^WGPU_Renderer,
	label: string,
	usage: wgpu.BufferUsageFlags,
	size: u64,
) -> wgpu.Buffer {
	return wgpu.DeviceCreateBuffer(
		renderer.device,
		&wgpu.BufferDescriptor{label = label, usage = usage, size = size},
	)
}

wgpu_make_cull_bind_group :: proc(
	renderer: ^WGPU_Renderer,
	batch_buffer: wgpu.Buffer,
	batch_capacity: int,
	visible_buffer, shadow_visible_buffer: wgpu.Buffer,
	visible_capacity: int,
	indirect_buffer, shadow_indirect_buffer: wgpu.Buffer,
	draw_capacity: int,
	label: string,
	meshlet: bool = false,
	compact: bool = false,
	debug: bool = false,
) -> wgpu.BindGroup {
	instance_bytes := u64(WGPU_MAX_GPU_INSTANCES) * u64(size_of(WGPU_GPU_Instance))
	batch_bytes := u64(batch_capacity) * u64(size_of(WGPU_GPU_Batch_Info))
	visible_bytes := u64(visible_capacity) * u64(size_of(u32))
	visible_binding_bytes := visible_bytes
	indirect_bytes := u64(draw_capacity) * u64(size_of(WGPU_Draw_Indexed_Indirect))
	meshlet_info_bytes :=
		u64(renderer.gpu_meshlet_draw_capacity) * u64(size_of(WGPU_GPU_Meshlet_Info))
	if meshlet {
		visible_binding_bytes = wgpu_meshlet_visible_buffer_bytes(visible_capacity)
	} else if compact {
		visible_bytes = wgpu_compact_visible_buffer_bytes(visible_capacity)
		visible_binding_bytes = visible_bytes
	} else if debug {
		visible_binding_bytes = wgpu_meshlet_debug_buffer_bytes(WGPU_MESHLET_DEBUG_RECORD_CAPACITY)
	}
	entries := [?]wgpu.BindGroupEntry {
		{binding = 0, buffer = renderer.gpu_instance_buffer, size = instance_bytes},
		{binding = 1, buffer = batch_buffer, size = batch_bytes},
		{binding = 2, buffer = visible_buffer, size = visible_binding_bytes},
		{
			binding = 3,
			buffer = shadow_visible_buffer,
			size = visible_bytes * WGPU_SHADOW_CASCADE_COUNT,
		},
		{binding = 4, buffer = indirect_buffer, size = indirect_bytes},
		{
			binding = 5,
			buffer = shadow_indirect_buffer,
			size = indirect_bytes * WGPU_SHADOW_CASCADE_COUNT,
		},
		{
			binding = 6,
			buffer = renderer.gpu_cull_uniform_buffer,
			size = u64(size_of(WGPU_GPU_Cull_Uniform)),
		},
		{binding = 7, textureView = renderer.gpu_hiz_view},
		{
			binding = 8,
			buffer = renderer.gpu_visibility_counter_buffer,
			size = WGPU_GPU_VISIBILITY_COUNTER_BUFFER_SIZE,
		},
		{binding = 9, buffer = renderer.gpu_meshlet_info_buffer, size = meshlet_info_bytes},
	}
	return wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = label,
			layout = renderer.gpu_cull_bind_group_layout,
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
}

WGPU_Compact_Cull_Bind_Group_Mode :: enum {
	Candidates,
	Camera,
	Shadow,
}

WGPU_GPU_Cull_Phase :: enum u32 {
	Disabled,
	Enabled,
	Coarse_Occluder,
}

wgpu_hiz_refinement_needed :: proc "contextless" (requested, reusable: bool) -> bool {
	return requested && !reusable
}

wgpu_initial_cull_phase :: proc "contextless" (
	occlusion_enabled, refinement_requested: bool,
) -> WGPU_GPU_Cull_Phase {
	if refinement_requested {
		return .Coarse_Occluder
	}
	if occlusion_enabled {
		return .Enabled
	}
	return .Disabled
}

wgpu_make_compact_cull_bind_group :: proc(
	renderer: ^WGPU_Renderer,
	batch_buffer: wgpu.Buffer,
	batch_capacity: int,
	candidate_buffer: wgpu.Buffer,
	candidate_capacity: int,
	camera_indirect_buffer, shadow_indirect_buffer: wgpu.Buffer,
	draw_capacity: int,
	mode: WGPU_Compact_Cull_Bind_Group_Mode,
	label: string,
) -> wgpu.BindGroup {
	instance_bytes := u64(WGPU_MAX_GPU_INSTANCES) * u64(size_of(WGPU_GPU_Instance))
	batch_bytes := u64(batch_capacity) * u64(size_of(WGPU_GPU_Batch_Info))
	candidate_bytes := u64(candidate_capacity) * u64(size_of(u32))
	compact_bytes := wgpu_compact_visible_buffer_bytes(
		renderer.gpu_meshlet_visible_buffer_capacity,
	)
	count_bytes := u64(WGPU_MAX_GPU_INSTANCES) * u64(size_of(WGPU_Draw_Indexed_Indirect))
	visible_buffer := renderer.gpu_compact_visible_buffer
	visible_bytes := compact_bytes
	indirect_buffer := camera_indirect_buffer
	indirect_bytes := u64(draw_capacity) * u64(size_of(WGPU_Draw_Indexed_Indirect))
	if mode == .Candidates {
		visible_buffer = candidate_buffer
		visible_bytes = candidate_bytes
		indirect_buffer = renderer.gpu_compact_candidate_count_buffer
		indirect_bytes = count_bytes
	} else if mode == .Shadow {
		visible_buffer = renderer.gpu_compact_shadow_visible_buffer
		visible_bytes = compact_bytes * WGPU_SHADOW_CASCADE_COUNT
		indirect_buffer = shadow_indirect_buffer
		indirect_bytes *= WGPU_SHADOW_CASCADE_COUNT
	}
	entries := [?]wgpu.BindGroupEntry {
		{binding = 0, buffer = renderer.gpu_instance_buffer, size = instance_bytes},
		{binding = 1, buffer = batch_buffer, size = batch_bytes},
		{binding = 2, buffer = visible_buffer, size = visible_bytes},
		{binding = 3, buffer = candidate_buffer, size = candidate_bytes},
		{binding = 4, buffer = indirect_buffer, size = indirect_bytes},
		{binding = 5, buffer = renderer.gpu_compact_candidate_count_buffer, size = count_bytes},
		{
			binding = 6,
			buffer = renderer.gpu_cull_uniform_buffer,
			size = u64(size_of(WGPU_GPU_Cull_Uniform)),
		},
		{binding = 7, textureView = renderer.gpu_hiz_view},
		{
			binding = 8,
			buffer = renderer.gpu_visibility_counter_buffer,
			size = WGPU_GPU_VISIBILITY_COUNTER_BUFFER_SIZE,
		},
		{
			binding = 9,
			buffer = renderer.gpu_meshlet_info_buffer,
			size = u64(renderer.gpu_meshlet_draw_capacity) * u64(size_of(WGPU_GPU_Meshlet_Info)),
		},
	}
	return wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = label,
			layout = renderer.gpu_cull_bind_group_layout,
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
}

wgpu_rebuild_meshlet_debug_bind_group :: proc(renderer: ^WGPU_Renderer) -> string {
	if renderer.gpu_meshlet_debug_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_meshlet_debug_bind_group)
		renderer.gpu_meshlet_debug_bind_group = nil
	}
	entries := [?]wgpu.BindGroupEntry {
		{
			binding = 0,
			buffer = renderer.gpu_render_uniform_buffer,
			size = u64(size_of(WGPU_GPU_Render_Uniform)),
		},
		{
			binding = 1,
			buffer = renderer.gpu_meshlet_debug_record_buffer,
			size = wgpu_meshlet_debug_buffer_bytes(WGPU_MESHLET_DEBUG_RECORD_CAPACITY),
		},
	}
	renderer.gpu_meshlet_debug_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot Meshlet Debug Bind Group",
			layout = renderer.gpu_meshlet_debug_bind_group_layout,
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
	if renderer.gpu_meshlet_debug_bind_group == nil {
		return "failed to create meshlet debug bind group"
	}
	return ""
}

wgpu_create_gpu_driven_pipelines :: proc(renderer: ^WGPU_Renderer) -> string {
	render_source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_GPU_DRIVEN_SHADER,
	}
	renderer.gpu_driven_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &render_source,
			label = "Scrapbot GPU-Driven Render Shader",
		},
	)
	if renderer.gpu_driven_shader == nil {
		return "failed to create GPU-driven render shader"
	}
	if debug_err := wgpu_create_meshlet_debug_pipeline(renderer); debug_err != "" {
		return debug_err
	}
	if cluster_err := wgpu_create_clustered_lighting(renderer); cluster_err != "" {
		return cluster_err
	}

	world_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Vertex, .Fragment},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_GPU_Render_Uniform))},
		},
		{
			binding = 1,
			visibility = {.Fragment},
			texture = {sampleType = .Depth, viewDimension = ._2DArray},
		},
		{binding = 2, visibility = {.Fragment}, sampler = {type = .Comparison}},
		{
			binding = 3,
			visibility = {.Vertex},
			buffer = {type = .ReadOnlyStorage, minBindingSize = u64(size_of(WGPU_GPU_Instance))},
		},
		{
			binding = 4,
			visibility = {.Vertex},
			buffer = {type = .ReadOnlyStorage, minBindingSize = 4},
		},
		{binding = 5, visibility = {.Fragment}, buffer = {type = .ReadOnlyStorage}},
		{binding = 6, visibility = {.Fragment}, buffer = {type = .ReadOnlyStorage}},
		{binding = 7, visibility = {.Fragment}, buffer = {type = .ReadOnlyStorage}},
		{
			binding = 8,
			visibility = {.Fragment},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_Cluster_Uniform))},
		},
		{
			binding = 10,
			visibility = {.Vertex},
			buffer = {type = .ReadOnlyStorage, minBindingSize = 4},
		},
		{binding = 11, visibility = {.Vertex}, buffer = {type = .ReadOnlyStorage}},
		{binding = 12, visibility = {.Vertex}, buffer = {type = .ReadOnlyStorage}},
		{binding = 13, visibility = {.Vertex}, buffer = {type = .ReadOnlyStorage}},
	}
	renderer.gpu_driven_world_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot GPU-Driven World Bind Group Layout",
			entryCount = uint(len(world_entries)),
			entries = raw_data(world_entries[:]),
		},
	)
	if renderer.gpu_driven_world_bind_group_layout == nil {
		return "failed to create GPU-driven world bind group layout"
	}
	shadow_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Vertex},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_GPU_Render_Uniform))},
		},
		{
			binding = 3,
			visibility = {.Vertex},
			buffer = {type = .ReadOnlyStorage, minBindingSize = u64(size_of(WGPU_GPU_Instance))},
		},
		{
			binding = 4,
			visibility = {.Vertex},
			buffer = {type = .ReadOnlyStorage, minBindingSize = 4},
		},
		{
			binding = 9,
			visibility = {.Vertex},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_Shadow_Cascade_Uniform))},
		},
		{
			binding = 10,
			visibility = {.Vertex},
			buffer = {type = .ReadOnlyStorage, minBindingSize = 4},
		},
		{binding = 11, visibility = {.Vertex}, buffer = {type = .ReadOnlyStorage}},
		{binding = 12, visibility = {.Vertex}, buffer = {type = .ReadOnlyStorage}},
		{binding = 13, visibility = {.Vertex}, buffer = {type = .ReadOnlyStorage}},
	}
	renderer.gpu_driven_shadow_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot GPU-Driven Shadow Bind Group Layout",
			entryCount = uint(len(shadow_entries)),
			entries = raw_data(shadow_entries[:]),
		},
	)
	if renderer.gpu_driven_shadow_bind_group_layout == nil {
		return "failed to create GPU-driven shadow bind group layout"
	}

	world_layouts := [?]wgpu.BindGroupLayout {
		renderer.gpu_driven_world_bind_group_layout,
		renderer.material_bind_group_layout,
		renderer.environment_bind_group_layout,
	}
	renderer.gpu_driven_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot GPU-Driven Pipeline Layout",
			bindGroupLayoutCount = uint(len(world_layouts)),
			bindGroupLayouts = raw_data(world_layouts[:]),
		},
	)
	if renderer.gpu_driven_pipeline_layout == nil {
		return "failed to create GPU-driven pipeline layout"
	}
	renderer.gpu_driven_shadow_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot GPU-Driven Shadow Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.gpu_driven_shadow_bind_group_layout,
		},
	)
	if renderer.gpu_driven_shadow_pipeline_layout == nil {
		return "failed to create GPU-driven shadow pipeline layout"
	}
	depth_mask_layouts := [?]wgpu.BindGroupLayout {
		renderer.gpu_driven_world_bind_group_layout,
		renderer.material_bind_group_layout,
	}
	renderer.gpu_driven_depth_mask_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot GPU-Driven Masked Depth Pipeline Layout",
			bindGroupLayoutCount = uint(len(depth_mask_layouts)),
			bindGroupLayouts = raw_data(depth_mask_layouts[:]),
		},
	)
	shadow_mask_layouts := [?]wgpu.BindGroupLayout {
		renderer.gpu_driven_shadow_bind_group_layout,
		renderer.material_bind_group_layout,
	}
	renderer.gpu_driven_shadow_mask_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot GPU-Driven Masked Shadow Pipeline Layout",
			bindGroupLayoutCount = uint(len(shadow_mask_layouts)),
			bindGroupLayouts = raw_data(shadow_mask_layouts[:]),
		},
	)
	if renderer.gpu_driven_depth_mask_pipeline_layout == nil ||
	   renderer.gpu_driven_shadow_mask_pipeline_layout == nil {
		return "failed to create GPU-driven masked material pipeline layouts"
	}

	vertex_attributes := [?]wgpu.VertexAttribute {
		{format = .Float32x3, offset = 0, shaderLocation = 0},
		{format = .Float32x3, offset = 12, shaderLocation = 1},
		{format = .Float32x2, offset = 24, shaderLocation = 2},
		{format = .Float32x4, offset = 32, shaderLocation = 3},
	}
	vertex_buffer_layout := wgpu.VertexBufferLayout {
		stepMode = .Vertex,
		arrayStride = u64(size_of(resources.Vertex)),
		attributeCount = uint(len(vertex_attributes)),
		attributes = raw_data(vertex_attributes[:]),
	}
	compact_attributes := [?]wgpu.VertexAttribute {
		{format = .Uint32, offset = 0, shaderLocation = 4},
		{format = .Uint32, offset = 4, shaderLocation = 5},
	}
	compact_buffer_layout := wgpu.VertexBufferLayout {
		stepMode = .Instance,
		arrayStride = u64(size_of(WGPU_GPU_Compact_Record)),
		attributeCount = uint(len(compact_attributes)),
		attributes = raw_data(compact_attributes[:]),
	}
	renderer.gpu_driven_pipeline = wgpu_create_gpu_world_pipeline(
		renderer,
		&vertex_buffer_layout,
		.Back,
		"Scrapbot GPU-Driven Render Pipeline",
	)
	renderer.gpu_driven_double_sided_pipeline = wgpu_create_gpu_world_pipeline(
		renderer,
		&vertex_buffer_layout,
		.None,
		"Scrapbot GPU-Driven Double-Sided Render Pipeline",
	)
	renderer.gpu_compact_pipeline = wgpu_create_gpu_world_pipeline(
		renderer,
		&compact_buffer_layout,
		.Back,
		"Scrapbot GPU Compact Cluster Render Pipeline",
		"compact_vs",
	)
	renderer.gpu_compact_double_sided_pipeline = wgpu_create_gpu_world_pipeline(
		renderer,
		&compact_buffer_layout,
		.None,
		"Scrapbot GPU Compact Double-Sided Render Pipeline",
		"compact_vs",
	)
	renderer.gpu_driven_depth_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot GPU-Driven Depth Prepass Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.gpu_driven_world_bind_group_layout,
		},
	)
	if renderer.gpu_driven_depth_pipeline_layout == nil {
		return "failed to create GPU-driven depth prepass pipeline layout"
	}
	renderer.gpu_driven_depth_pipeline = wgpu_create_gpu_depth_pipeline(
		renderer,
		&vertex_buffer_layout,
		.Back,
		false,
		"Scrapbot GPU-Driven Depth Prepass Pipeline",
	)
	renderer.gpu_driven_depth_double_sided_pipeline = wgpu_create_gpu_depth_pipeline(
		renderer,
		&vertex_buffer_layout,
		.None,
		false,
		"Scrapbot GPU-Driven Double-Sided Depth Pipeline",
	)
	renderer.gpu_driven_depth_mask_pipeline = wgpu_create_gpu_depth_pipeline(
		renderer,
		&vertex_buffer_layout,
		.Back,
		true,
		"Scrapbot GPU-Driven Masked Depth Pipeline",
	)
	renderer.gpu_driven_depth_mask_double_sided_pipeline = wgpu_create_gpu_depth_pipeline(
		renderer,
		&vertex_buffer_layout,
		.None,
		true,
		"Scrapbot GPU-Driven Masked Double-Sided Depth Pipeline",
	)
	renderer.gpu_compact_depth_pipeline = wgpu_create_gpu_depth_pipeline(
		renderer,
		&compact_buffer_layout,
		.Back,
		false,
		"Scrapbot GPU Compact Depth Prepass Pipeline",
		"compact_depth_only_vs",
	)
	renderer.gpu_compact_depth_double_sided_pipeline = wgpu_create_gpu_depth_pipeline(
		renderer,
		&compact_buffer_layout,
		.None,
		false,
		"Scrapbot GPU Compact Double-Sided Depth Pipeline",
		"compact_depth_only_vs",
	)
	renderer.gpu_compact_depth_mask_pipeline = wgpu_create_gpu_depth_pipeline(
		renderer,
		&compact_buffer_layout,
		.Back,
		true,
		"Scrapbot GPU Compact Masked Depth Pipeline",
		"compact_depth_vs",
	)
	renderer.gpu_compact_depth_mask_double_sided_pipeline = wgpu_create_gpu_depth_pipeline(
		renderer,
		&compact_buffer_layout,
		.None,
		true,
		"Scrapbot GPU Compact Masked Double-Sided Depth Pipeline",
		"compact_depth_vs",
	)
	renderer.gpu_driven_shadow_pipeline = wgpu_create_gpu_shadow_pipeline(
		renderer,
		&vertex_buffer_layout,
		.Back,
		false,
		"Scrapbot GPU-Driven Shadow Pipeline",
	)
	renderer.gpu_driven_shadow_double_sided_pipeline = wgpu_create_gpu_shadow_pipeline(
		renderer,
		&vertex_buffer_layout,
		.None,
		false,
		"Scrapbot GPU-Driven Double-Sided Shadow Pipeline",
	)
	renderer.gpu_driven_shadow_mask_pipeline = wgpu_create_gpu_shadow_pipeline(
		renderer,
		&vertex_buffer_layout,
		.Back,
		true,
		"Scrapbot GPU-Driven Masked Shadow Pipeline",
	)
	renderer.gpu_driven_shadow_mask_double_sided_pipeline = wgpu_create_gpu_shadow_pipeline(
		renderer,
		&vertex_buffer_layout,
		.None,
		true,
		"Scrapbot GPU-Driven Masked Double-Sided Shadow Pipeline",
	)
	renderer.gpu_compact_shadow_pipeline = wgpu_create_gpu_shadow_pipeline(
		renderer,
		&compact_buffer_layout,
		.Back,
		false,
		"Scrapbot GPU Compact Shadow Pipeline",
		"compact_shadow_depth_only_vs",
	)
	renderer.gpu_compact_shadow_double_sided_pipeline = wgpu_create_gpu_shadow_pipeline(
		renderer,
		&compact_buffer_layout,
		.None,
		false,
		"Scrapbot GPU Compact Double-Sided Shadow Pipeline",
		"compact_shadow_depth_only_vs",
	)
	renderer.gpu_compact_shadow_mask_pipeline = wgpu_create_gpu_shadow_pipeline(
		renderer,
		&compact_buffer_layout,
		.Back,
		true,
		"Scrapbot GPU Compact Masked Shadow Pipeline",
		"compact_shadow_vs",
	)
	renderer.gpu_compact_shadow_mask_double_sided_pipeline = wgpu_create_gpu_shadow_pipeline(
		renderer,
		&compact_buffer_layout,
		.None,
		true,
		"Scrapbot GPU Compact Masked Double-Sided Shadow Pipeline",
		"compact_shadow_vs",
	)
	if renderer.gpu_driven_pipeline == nil ||
	   renderer.gpu_driven_double_sided_pipeline == nil ||
	   renderer.gpu_compact_pipeline == nil ||
	   renderer.gpu_compact_double_sided_pipeline == nil ||
	   renderer.gpu_driven_depth_pipeline == nil ||
	   renderer.gpu_driven_depth_double_sided_pipeline == nil ||
	   renderer.gpu_driven_depth_mask_pipeline == nil ||
	   renderer.gpu_driven_depth_mask_double_sided_pipeline == nil ||
	   renderer.gpu_compact_depth_pipeline == nil ||
	   renderer.gpu_compact_depth_double_sided_pipeline == nil ||
	   renderer.gpu_compact_depth_mask_pipeline == nil ||
	   renderer.gpu_compact_depth_mask_double_sided_pipeline == nil ||
	   renderer.gpu_driven_shadow_pipeline == nil ||
	   renderer.gpu_driven_shadow_double_sided_pipeline == nil ||
	   renderer.gpu_driven_shadow_mask_pipeline == nil ||
	   renderer.gpu_driven_shadow_mask_double_sided_pipeline == nil ||
	   renderer.gpu_compact_shadow_pipeline == nil ||
	   renderer.gpu_compact_shadow_double_sided_pipeline == nil ||
	   renderer.gpu_compact_shadow_mask_pipeline == nil ||
	   renderer.gpu_compact_shadow_mask_double_sided_pipeline == nil {
		return "failed to create GPU-driven material render pipelines"
	}

	transform_source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_GPU_TRANSFORM_SHADER,
	}
	renderer.gpu_transform_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &transform_source,
			label = "Scrapbot GPU Transform Shader",
		},
	)
	if renderer.gpu_transform_shader == nil {
		return "failed to create GPU transform shader"
	}
	transform_entries := [?]wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Compute},
			buffer = {
				type = .ReadOnlyStorage,
				minBindingSize = u64(size_of(WGPU_GPU_Instance_Transform)),
			},
		},
		{
			binding = 1,
			visibility = {.Compute},
			buffer = {type = .Storage, minBindingSize = u64(size_of(WGPU_GPU_Instance))},
		},
	}
	renderer.gpu_transform_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot GPU Transform Bind Group Layout",
			entryCount = uint(len(transform_entries)),
			entries = raw_data(transform_entries[:]),
		},
	)
	if renderer.gpu_transform_bind_group_layout == nil {
		return "failed to create GPU transform bind group layout"
	}
	renderer.gpu_transform_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot GPU Transform Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.gpu_transform_bind_group_layout,
		},
	)
	if renderer.gpu_transform_pipeline_layout == nil {
		return "failed to create GPU transform pipeline layout"
	}
	renderer.gpu_transform_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot GPU Transform Pipeline",
			layout = renderer.gpu_transform_pipeline_layout,
			compute = {module = renderer.gpu_transform_shader, entryPoint = "expand_transforms"},
		},
	)
	if renderer.gpu_transform_pipeline == nil {
		return "failed to create GPU transform pipeline"
	}

	cull_source := wgpu.ShaderSourceWGSL {
		chain = {sType = .ShaderSourceWGSL},
		code = WGPU_GPU_CULL_SHADER,
	}
	renderer.gpu_cull_shader = wgpu.DeviceCreateShaderModule(
		renderer.device,
		&wgpu.ShaderModuleDescriptor {
			nextInChain = &cull_source,
			label = "Scrapbot GPU Culling Shader",
		},
	)
	if renderer.gpu_cull_shader == nil {
		return "failed to create GPU culling shader"
	}
	cull_entries := [?]wgpu.BindGroupLayoutEntry {
		{binding = 0, visibility = {.Compute}, buffer = {type = .ReadOnlyStorage}},
		{binding = 1, visibility = {.Compute}, buffer = {type = .ReadOnlyStorage}},
		{binding = 2, visibility = {.Compute}, buffer = {type = .Storage}},
		{binding = 3, visibility = {.Compute}, buffer = {type = .Storage}},
		{binding = 4, visibility = {.Compute}, buffer = {type = .Storage}},
		{binding = 5, visibility = {.Compute}, buffer = {type = .Storage}},
		{
			binding = 6,
			visibility = {.Compute},
			buffer = {type = .Uniform, minBindingSize = u64(size_of(WGPU_GPU_Cull_Uniform))},
		},
		{
			binding = 7,
			visibility = {.Compute},
			texture = {sampleType = .UnfilterableFloat, viewDimension = ._2D},
		},
		{binding = 8, visibility = {.Compute}, buffer = {type = .Storage}},
		{binding = 9, visibility = {.Compute}, buffer = {type = .ReadOnlyStorage}},
	}
	renderer.gpu_cull_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&wgpu.BindGroupLayoutDescriptor {
			label = "Scrapbot GPU Culling Bind Group Layout",
			entryCount = uint(len(cull_entries)),
			entries = raw_data(cull_entries[:]),
		},
	)
	if renderer.gpu_cull_bind_group_layout == nil {
		return "failed to create GPU culling bind group layout"
	}
	renderer.gpu_cull_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&wgpu.PipelineLayoutDescriptor {
			label = "Scrapbot GPU Culling Pipeline Layout",
			bindGroupLayoutCount = 1,
			bindGroupLayouts = &renderer.gpu_cull_bind_group_layout,
		},
	)
	if renderer.gpu_cull_pipeline_layout == nil {
		return "failed to create GPU culling pipeline layout"
	}
	renderer.gpu_cull_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot GPU Classic Culling Pipeline",
			layout = renderer.gpu_cull_pipeline_layout,
			compute = {module = renderer.gpu_cull_shader, entryPoint = "cull_classic_instances"},
		},
	)
	renderer.gpu_meshlet_cull_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot GPU Meshlet Culling Pipeline",
			layout = renderer.gpu_cull_pipeline_layout,
			compute = {module = renderer.gpu_cull_shader, entryPoint = "cull_meshlet_instances"},
		},
	)
	renderer.gpu_compact_cull_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot GPU Compact Cluster Culling Pipeline",
			layout = renderer.gpu_cull_pipeline_layout,
			compute = {module = renderer.gpu_cull_shader, entryPoint = "cull_compact_instances"},
		},
	)
	renderer.gpu_compact_cluster_cull_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot GPU Parallel Compact Cluster Culling Pipeline",
			layout = renderer.gpu_cull_pipeline_layout,
			compute = {
				module = renderer.gpu_cull_shader,
				entryPoint = "cull_compact_cluster_instances",
			},
		},
	)
	renderer.gpu_compact_shadow_cluster_cull_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot GPU Parallel Compact Shadow Cluster Culling Pipeline",
			layout = renderer.gpu_cull_pipeline_layout,
			compute = {
				module = renderer.gpu_cull_shader,
				entryPoint = "cull_compact_shadow_cluster_instances",
			},
		},
	)
	renderer.gpu_meshlet_debug_cull_pipeline = wgpu.DeviceCreateComputePipeline(
		renderer.device,
		&wgpu.ComputePipelineDescriptor {
			label = "Scrapbot Meshlet Diagnostic Culling Pipeline",
			layout = renderer.gpu_cull_pipeline_layout,
			compute = {
				module = renderer.gpu_cull_shader,
				entryPoint = "capture_meshlet_debug_instances",
			},
		},
	)
	if renderer.gpu_cull_pipeline == nil ||
	   renderer.gpu_meshlet_cull_pipeline == nil ||
	   renderer.gpu_compact_cull_pipeline == nil ||
	   renderer.gpu_compact_cluster_cull_pipeline == nil ||
	   renderer.gpu_compact_shadow_cluster_cull_pipeline == nil ||
	   renderer.gpu_meshlet_debug_cull_pipeline == nil {
		return "failed to create GPU culling pipelines"
	}
	if hiz_err := wgpu_create_hiz_pipelines(renderer); hiz_err != "" {
		return hiz_err
	}
	if distance_field_err := wgpu_create_distance_field_debug_pipeline(renderer);
	   distance_field_err != "" {
		return distance_field_err
	}
	if clipmap_err := wgpu_create_distance_field_clipmap_pipeline(renderer); clipmap_err != "" {
		return clipmap_err
	}
	if hiz_err := wgpu_ensure_hiz_targets(renderer, 1, 1); hiz_err != "" {
		return hiz_err
	}

	instance_bytes := u64(WGPU_MAX_GPU_INSTANCES) * u64(size_of(WGPU_GPU_Instance))
	transform_update_bytes :=
		u64(WGPU_MAX_GPU_INSTANCES + 1) * u64(size_of(WGPU_GPU_Instance_Transform))
	visible_entries := WGPU_MAX_GPU_INSTANCES + WGPU_INITIAL_DRAW_CAPACITY * WGPU_VISIBLE_ALIGNMENT
	visible_bytes := u64(visible_entries) * u64(size_of(u32))
	shadow_visible_bytes := visible_bytes * WGPU_SHADOW_CASCADE_COUNT
	batch_bytes := u64(WGPU_INITIAL_DRAW_CAPACITY) * u64(size_of(WGPU_GPU_Batch_Info))
	indirect_bytes := u64(WGPU_INITIAL_DRAW_CAPACITY) * u64(size_of(WGPU_Draw_Indexed_Indirect))
	meshlet_info_bytes :=
		u64(WGPU_INITIAL_MESHLET_DRAW_CAPACITY) * u64(size_of(WGPU_GPU_Meshlet_Info))
	meshlet_visible_bytes := u64(WGPU_INITIAL_MESHLET_VISIBLE_CAPACITY) * u64(size_of(u32))
	meshlet_indirect_bytes :=
		u64(WGPU_INITIAL_MESHLET_DRAW_CAPACITY) * u64(size_of(WGPU_Draw_Indexed_Indirect))
	renderer.gpu_instance_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Instance Table",
		{.Storage, .CopyDst},
		instance_bytes,
	)
	renderer.gpu_transform_update_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Transform Updates",
		{.Storage, .CopyDst},
		transform_update_bytes,
	)
	renderer.gpu_batch_info_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Batch Table",
		{.Storage, .CopyDst},
		batch_bytes,
	)
	renderer.gpu_visible_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Visible Instances",
		{.Storage, .CopyDst},
		visible_bytes,
	)
	renderer.gpu_shadow_visible_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Shadow Visible Instances",
		{.Storage, .CopyDst},
		shadow_visible_bytes,
	)
	renderer.gpu_indirect_template_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Indirect Template",
		{.CopySrc, .CopyDst},
		indirect_bytes,
	)
	renderer.gpu_shadow_indirect_template_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Shadow Indirect Template",
		{.CopySrc, .CopyDst},
		indirect_bytes,
	)
	renderer.gpu_indirect_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Indirect Draws",
		{.Storage, .Indirect, .CopyDst},
		indirect_bytes,
	)
	renderer.gpu_shadow_indirect_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Shadow Indirect Draws",
		{.Storage, .Indirect, .CopyDst},
		indirect_bytes * WGPU_SHADOW_CASCADE_COUNT,
	)
	renderer.gpu_meshlet_info_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Table",
		{.Storage, .CopyDst},
		meshlet_info_bytes,
	)
	renderer.gpu_meshlet_visible_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Visible Instances",
		{.Storage, .CopyDst},
		wgpu_meshlet_visible_buffer_bytes(WGPU_INITIAL_MESHLET_VISIBLE_CAPACITY),
	)
	renderer.gpu_meshlet_identity_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Identities",
		{.Storage, .CopyDst},
		meshlet_visible_bytes,
	)
	renderer.gpu_zero_identity_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Zero Identities",
		{.Storage},
		visible_bytes,
	)
	renderer.gpu_meshlet_debug_indirect_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Debug Indirect Draw",
		{.Storage, .Indirect, .CopyDst},
		u64(size_of(WGPU_Draw_Indirect)),
	)
	renderer.gpu_meshlet_debug_record_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Debug Records",
		{.Storage, .CopySrc},
		wgpu_meshlet_debug_buffer_bytes(WGPU_MESHLET_DEBUG_RECORD_CAPACITY),
	)
	renderer.gpu_meshlet_shadow_visible_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Shadow Visible Instances",
		{.Storage, .CopyDst},
		meshlet_visible_bytes * WGPU_SHADOW_CASCADE_COUNT,
	)
	renderer.gpu_compact_visible_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Compact Cluster Records",
		{.Storage, .Vertex},
		wgpu_compact_visible_buffer_bytes(WGPU_INITIAL_MESHLET_VISIBLE_CAPACITY),
	)
	renderer.gpu_compact_shadow_visible_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Compact Shadow Cluster Records",
		{.Storage, .Vertex},
		u64(WGPU_INITIAL_MESHLET_VISIBLE_CAPACITY) *
		u64(size_of(WGPU_GPU_Compact_Record)) *
		WGPU_SHADOW_CASCADE_COUNT,
	)
	renderer.gpu_compact_candidate_count_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Compact Candidate Counts",
		{.Storage, .CopyDst},
		u64(WGPU_MAX_GPU_INSTANCES) * u64(size_of(WGPU_Draw_Indexed_Indirect)),
	)
	renderer.gpu_meshlet_indirect_template_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Indirect Template",
		{.CopySrc, .CopyDst},
		meshlet_indirect_bytes,
	)
	renderer.gpu_meshlet_indirect_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Indirect Draws",
		{.Storage, .Indirect, .CopyDst},
		meshlet_indirect_bytes,
	)
	renderer.gpu_meshlet_shadow_indirect_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Shadow Indirect Draws",
		{.Storage, .Indirect, .CopyDst},
		meshlet_indirect_bytes * WGPU_SHADOW_CASCADE_COUNT,
	)
	renderer.gpu_cull_uniform_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Culling Uniform",
		{.Uniform, .CopyDst},
		u64(size_of(WGPU_GPU_Cull_Uniform)),
	)
	renderer.gpu_cull_initial_uniform_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Initial Culling Uniform",
		{.CopySrc, .CopyDst},
		u64(size_of(WGPU_GPU_Cull_Uniform)),
	)
	renderer.gpu_cull_refine_uniform_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Refined Culling Uniform",
		{.CopySrc, .CopyDst},
		u64(size_of(WGPU_GPU_Cull_Uniform)),
	)
	renderer.gpu_render_uniform_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Render Uniform",
		{.Uniform, .CopyDst},
		u64(size_of(WGPU_GPU_Render_Uniform)),
	)
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		renderer.gpu_shadow_cascade_uniform_buffers[cascade_index] = wgpu_create_gpu_buffer(
			renderer,
			"Scrapbot Shadow Cascade Uniform",
			{.Uniform, .CopyDst},
			u64(size_of(WGPU_Shadow_Cascade_Uniform)),
		)
		if renderer.gpu_shadow_cascade_uniform_buffers[cascade_index] == nil {
			return "failed to allocate shadow cascade uniform buffer"
		}
		cascade_uniform := WGPU_Shadow_Cascade_Uniform {
			index = u32(cascade_index),
		}
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_shadow_cascade_uniform_buffers[cascade_index],
			0,
			&cascade_uniform,
			uint(size_of(cascade_uniform)),
		)
	}
	renderer.gpu_visibility_counter_buffer = wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Visibility Counters",
		{.Storage, .CopySrc, .CopyDst},
		WGPU_GPU_VISIBILITY_COUNTER_BUFFER_SIZE,
	)
	if renderer.gpu_instance_buffer == nil ||
	   renderer.gpu_transform_update_buffer == nil ||
	   renderer.gpu_batch_info_buffer == nil ||
	   renderer.gpu_visible_buffer == nil ||
	   renderer.gpu_shadow_visible_buffer == nil ||
	   renderer.gpu_indirect_template_buffer == nil ||
	   renderer.gpu_shadow_indirect_template_buffer == nil ||
	   renderer.gpu_indirect_buffer == nil ||
	   renderer.gpu_shadow_indirect_buffer == nil ||
	   renderer.gpu_meshlet_info_buffer == nil ||
	   renderer.gpu_meshlet_visible_buffer == nil ||
	   renderer.gpu_meshlet_identity_buffer == nil ||
	   renderer.gpu_zero_identity_buffer == nil ||
	   renderer.gpu_meshlet_debug_indirect_buffer == nil ||
	   renderer.gpu_meshlet_debug_record_buffer == nil ||
	   renderer.gpu_meshlet_shadow_visible_buffer == nil ||
	   renderer.gpu_compact_visible_buffer == nil ||
	   renderer.gpu_compact_shadow_visible_buffer == nil ||
	   renderer.gpu_compact_candidate_count_buffer == nil ||
	   renderer.gpu_meshlet_indirect_template_buffer == nil ||
	   renderer.gpu_meshlet_indirect_buffer == nil ||
	   renderer.gpu_meshlet_shadow_indirect_buffer == nil ||
	   renderer.gpu_cull_uniform_buffer == nil ||
	   renderer.gpu_cull_initial_uniform_buffer == nil ||
	   renderer.gpu_cull_refine_uniform_buffer == nil ||
	   renderer.gpu_render_uniform_buffer == nil ||
	   renderer.gpu_visibility_counter_buffer == nil {
		return "failed to allocate GPU-driven renderer buffers"
	}
	transform_bind_entries := [?]wgpu.BindGroupEntry {
		{
			binding = 0,
			buffer = renderer.gpu_transform_update_buffer,
			size = transform_update_bytes,
		},
		{binding = 1, buffer = renderer.gpu_instance_buffer, size = instance_bytes},
	}
	renderer.gpu_transform_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = "Scrapbot GPU Transform Bind Group",
			layout = renderer.gpu_transform_bind_group_layout,
			entryCount = uint(len(transform_bind_entries)),
			entries = raw_data(transform_bind_entries[:]),
		},
	)
	if renderer.gpu_transform_bind_group == nil {
		return "failed to create GPU transform bind group"
	}

	renderer.gpu_draw_capacity = WGPU_INITIAL_DRAW_CAPACITY
	renderer.gpu_visible_buffer_capacity = visible_entries
	renderer.gpu_meshlet_draw_capacity = WGPU_INITIAL_MESHLET_DRAW_CAPACITY
	renderer.gpu_meshlet_visible_buffer_capacity = WGPU_INITIAL_MESHLET_VISIBLE_CAPACITY
	if debug_err := wgpu_rebuild_meshlet_debug_bind_group(renderer); debug_err != "" {
		return debug_err
	}
	if debug_err := wgpu_rebuild_hiz_debug_bind_group(renderer); debug_err != "" {
		return debug_err
	}
	renderer.gpu_cull_bind_group = wgpu_make_cull_bind_group(
		renderer,
		renderer.gpu_batch_info_buffer,
		renderer.gpu_draw_capacity,
		renderer.gpu_visible_buffer,
		renderer.gpu_shadow_visible_buffer,
		renderer.gpu_visible_buffer_capacity,
		renderer.gpu_indirect_buffer,
		renderer.gpu_shadow_indirect_buffer,
		renderer.gpu_draw_capacity,
		"Scrapbot GPU Culling Bind Group",
	)
	renderer.gpu_meshlet_cull_bind_group = wgpu_make_cull_bind_group(
		renderer,
		renderer.gpu_batch_info_buffer,
		renderer.gpu_draw_capacity,
		renderer.gpu_meshlet_visible_buffer,
		renderer.gpu_meshlet_shadow_visible_buffer,
		renderer.gpu_meshlet_visible_buffer_capacity,
		renderer.gpu_meshlet_indirect_buffer,
		renderer.gpu_meshlet_shadow_indirect_buffer,
		renderer.gpu_meshlet_draw_capacity,
		"Scrapbot GPU Meshlet Culling Bind Group",
		meshlet = true,
	)
	renderer.gpu_compact_cull_bind_group = wgpu_make_compact_cull_bind_group(
		renderer,
		renderer.gpu_batch_info_buffer,
		renderer.gpu_draw_capacity,
		renderer.gpu_visible_buffer,
		renderer.gpu_visible_buffer_capacity,
		renderer.gpu_indirect_buffer,
		renderer.gpu_shadow_indirect_buffer,
		renderer.gpu_draw_capacity,
		.Candidates,
		"Scrapbot GPU Compact Candidate Culling Bind Group",
	)
	renderer.gpu_compact_camera_cull_bind_group = wgpu_make_compact_cull_bind_group(
		renderer,
		renderer.gpu_batch_info_buffer,
		renderer.gpu_draw_capacity,
		renderer.gpu_visible_buffer,
		renderer.gpu_visible_buffer_capacity,
		renderer.gpu_indirect_buffer,
		renderer.gpu_shadow_indirect_buffer,
		renderer.gpu_draw_capacity,
		.Camera,
		"Scrapbot GPU Compact Camera Cluster Culling Bind Group",
	)
	renderer.gpu_compact_shadow_cull_bind_group = wgpu_make_compact_cull_bind_group(
		renderer,
		renderer.gpu_batch_info_buffer,
		renderer.gpu_draw_capacity,
		renderer.gpu_visible_buffer,
		renderer.gpu_visible_buffer_capacity,
		renderer.gpu_indirect_buffer,
		renderer.gpu_shadow_indirect_buffer,
		renderer.gpu_draw_capacity,
		.Shadow,
		"Scrapbot GPU Compact Shadow Cluster Culling Bind Group",
	)
	renderer.gpu_meshlet_debug_cull_bind_group = wgpu_make_cull_bind_group(
		renderer,
		renderer.gpu_batch_info_buffer,
		renderer.gpu_draw_capacity,
		renderer.gpu_meshlet_debug_record_buffer,
		renderer.gpu_meshlet_shadow_visible_buffer,
		renderer.gpu_meshlet_visible_buffer_capacity,
		renderer.gpu_meshlet_indirect_buffer,
		renderer.gpu_meshlet_shadow_indirect_buffer,
		renderer.gpu_meshlet_draw_capacity,
		"Scrapbot Meshlet Diagnostic Culling Bind Group",
		debug = true,
	)
	if renderer.gpu_cull_bind_group == nil ||
	   renderer.gpu_meshlet_cull_bind_group == nil ||
	   renderer.gpu_compact_cull_bind_group == nil ||
	   renderer.gpu_compact_camera_cull_bind_group == nil ||
	   renderer.gpu_compact_shadow_cull_bind_group == nil ||
	   renderer.gpu_meshlet_debug_cull_bind_group == nil {
		if renderer.gpu_cull_bind_group != nil {
			wgpu.BindGroupRelease(renderer.gpu_cull_bind_group)
			renderer.gpu_cull_bind_group = nil
		}
		if renderer.gpu_meshlet_cull_bind_group != nil {
			wgpu.BindGroupRelease(renderer.gpu_meshlet_cull_bind_group)
			renderer.gpu_meshlet_cull_bind_group = nil
		}
		if renderer.gpu_compact_cull_bind_group != nil {
			wgpu.BindGroupRelease(renderer.gpu_compact_cull_bind_group)
			renderer.gpu_compact_cull_bind_group = nil
		}
		if renderer.gpu_compact_camera_cull_bind_group != nil {
			wgpu.BindGroupRelease(renderer.gpu_compact_camera_cull_bind_group)
			renderer.gpu_compact_camera_cull_bind_group = nil
		}
		if renderer.gpu_compact_shadow_cull_bind_group != nil {
			wgpu.BindGroupRelease(renderer.gpu_compact_shadow_cull_bind_group)
			renderer.gpu_compact_shadow_cull_bind_group = nil
		}
		if renderer.gpu_meshlet_debug_cull_bind_group != nil {
			wgpu.BindGroupRelease(renderer.gpu_meshlet_debug_cull_bind_group)
			renderer.gpu_meshlet_debug_cull_bind_group = nil
		}
		return "failed to create GPU culling bind groups"
	}
	if visibility_err := wgpu_create_visibility_readbacks(renderer); visibility_err != "" {
		return visibility_err
	}
	return ""
}

wgpu_grow_capacity :: proc "contextless" (current, required: int) -> int {
	capacity := max(current, 1)
	for capacity < required {
		capacity *= 2
	}
	return capacity
}

wgpu_grow_storage_binding_capacity :: proc "contextless" (
	current, required: int,
	element_size, max_binding_bytes: u64,
) -> (
	capacity: int,
	ok: bool,
) {
	if current < 0 || required < 0 || element_size == 0 || max_binding_bytes < element_size {
		return 0, false
	}
	max_capacity := max_binding_bytes / element_size
	if u64(required) > max_capacity {
		return 0, false
	}
	capacity = wgpu_grow_capacity(current, required)
	if u64(capacity) > max_capacity {
		capacity = int(max_capacity)
	}
	return capacity, true
}

wgpu_rebuild_cull_bind_group :: proc(renderer: ^WGPU_Renderer) -> string {
	if renderer == nil ||
	   renderer.gpu_instance_buffer == nil ||
	   renderer.gpu_batch_info_buffer == nil ||
	   renderer.gpu_hiz_view == nil {
		return ""
	}
	bind_group := wgpu_make_cull_bind_group(
		renderer,
		renderer.gpu_batch_info_buffer,
		renderer.gpu_draw_capacity,
		renderer.gpu_visible_buffer,
		renderer.gpu_shadow_visible_buffer,
		renderer.gpu_visible_buffer_capacity,
		renderer.gpu_indirect_buffer,
		renderer.gpu_shadow_indirect_buffer,
		renderer.gpu_draw_capacity,
		"Scrapbot GPU Culling Bind Group",
	)
	meshlet_bind_group := wgpu_make_cull_bind_group(
		renderer,
		renderer.gpu_batch_info_buffer,
		renderer.gpu_draw_capacity,
		renderer.gpu_meshlet_visible_buffer,
		renderer.gpu_meshlet_shadow_visible_buffer,
		renderer.gpu_meshlet_visible_buffer_capacity,
		renderer.gpu_meshlet_indirect_buffer,
		renderer.gpu_meshlet_shadow_indirect_buffer,
		renderer.gpu_meshlet_draw_capacity,
		"Scrapbot GPU Meshlet Culling Bind Group",
		meshlet = true,
	)
	compact_bind_group := wgpu_make_compact_cull_bind_group(
		renderer,
		renderer.gpu_batch_info_buffer,
		renderer.gpu_draw_capacity,
		renderer.gpu_visible_buffer,
		renderer.gpu_visible_buffer_capacity,
		renderer.gpu_indirect_buffer,
		renderer.gpu_shadow_indirect_buffer,
		renderer.gpu_draw_capacity,
		.Candidates,
		"Scrapbot GPU Compact Candidate Culling Bind Group",
	)
	compact_camera_bind_group := wgpu_make_compact_cull_bind_group(
		renderer,
		renderer.gpu_batch_info_buffer,
		renderer.gpu_draw_capacity,
		renderer.gpu_visible_buffer,
		renderer.gpu_visible_buffer_capacity,
		renderer.gpu_indirect_buffer,
		renderer.gpu_shadow_indirect_buffer,
		renderer.gpu_draw_capacity,
		.Camera,
		"Scrapbot GPU Compact Camera Cluster Culling Bind Group",
	)
	compact_shadow_bind_group := wgpu_make_compact_cull_bind_group(
		renderer,
		renderer.gpu_batch_info_buffer,
		renderer.gpu_draw_capacity,
		renderer.gpu_visible_buffer,
		renderer.gpu_visible_buffer_capacity,
		renderer.gpu_indirect_buffer,
		renderer.gpu_shadow_indirect_buffer,
		renderer.gpu_draw_capacity,
		.Shadow,
		"Scrapbot GPU Compact Shadow Cluster Culling Bind Group",
	)
	debug_bind_group := wgpu_make_cull_bind_group(
		renderer,
		renderer.gpu_batch_info_buffer,
		renderer.gpu_draw_capacity,
		renderer.gpu_meshlet_debug_record_buffer,
		renderer.gpu_meshlet_shadow_visible_buffer,
		renderer.gpu_meshlet_visible_buffer_capacity,
		renderer.gpu_meshlet_indirect_buffer,
		renderer.gpu_meshlet_shadow_indirect_buffer,
		renderer.gpu_meshlet_draw_capacity,
		"Scrapbot Meshlet Diagnostic Culling Bind Group",
		debug = true,
	)
	if bind_group == nil ||
	   meshlet_bind_group == nil ||
	   compact_bind_group == nil ||
	   compact_camera_bind_group == nil ||
	   compact_shadow_bind_group == nil ||
	   debug_bind_group == nil {
		if bind_group != nil {
			wgpu.BindGroupRelease(bind_group)
		}
		if meshlet_bind_group != nil {
			wgpu.BindGroupRelease(meshlet_bind_group)
		}
		if compact_bind_group != nil {
			wgpu.BindGroupRelease(compact_bind_group)
		}
		if compact_camera_bind_group != nil {
			wgpu.BindGroupRelease(compact_camera_bind_group)
		}
		if compact_shadow_bind_group != nil {
			wgpu.BindGroupRelease(compact_shadow_bind_group)
		}
		if debug_bind_group != nil {
			wgpu.BindGroupRelease(debug_bind_group)
		}
		return "failed to rebuild GPU culling bind groups"
	}
	if renderer.gpu_cull_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_cull_bind_group)
	}
	if renderer.gpu_meshlet_cull_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_meshlet_cull_bind_group)
	}
	if renderer.gpu_compact_cull_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_compact_cull_bind_group)
	}
	if renderer.gpu_compact_camera_cull_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_compact_camera_cull_bind_group)
	}
	if renderer.gpu_compact_shadow_cull_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_compact_shadow_cull_bind_group)
	}
	if renderer.gpu_meshlet_debug_cull_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_meshlet_debug_cull_bind_group)
	}
	renderer.gpu_cull_bind_group = bind_group
	renderer.gpu_meshlet_cull_bind_group = meshlet_bind_group
	renderer.gpu_compact_cull_bind_group = compact_bind_group
	renderer.gpu_compact_camera_cull_bind_group = compact_camera_bind_group
	renderer.gpu_compact_shadow_cull_bind_group = compact_shadow_bind_group
	renderer.gpu_meshlet_debug_cull_bind_group = debug_bind_group
	return ""
}

wgpu_ensure_gpu_draw_buffers :: proc(
	renderer: ^WGPU_Renderer,
	required_batches, required_visible: int,
) -> string {
	if required_batches <= renderer.gpu_draw_capacity &&
	   required_visible <= renderer.gpu_visible_buffer_capacity {
		return ""
	}
	draw_capacity := wgpu_grow_capacity(renderer.gpu_draw_capacity, required_batches)
	visible_capacity := wgpu_grow_capacity(renderer.gpu_visible_buffer_capacity, required_visible)
	batch_bytes := u64(draw_capacity) * u64(size_of(WGPU_GPU_Batch_Info))
	visible_bytes := u64(visible_capacity) * u64(size_of(u32))
	shadow_visible_bytes := visible_bytes * WGPU_SHADOW_CASCADE_COUNT
	indirect_bytes := u64(draw_capacity) * u64(size_of(WGPU_Draw_Indexed_Indirect))
	shadow_indirect_bytes := indirect_bytes * WGPU_SHADOW_CASCADE_COUNT
	batch_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Batch Table",
		{.Storage, .CopyDst},
		batch_bytes,
	)
	visible_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Visible Instances",
		{.Storage, .CopyDst},
		visible_bytes,
	)
	zero_identity_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Zero Identities",
		{.Storage},
		visible_bytes,
	)
	shadow_visible_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Shadow Visible Instances",
		{.Storage, .CopyDst},
		shadow_visible_bytes,
	)
	indirect_template_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Indirect Template",
		{.CopySrc, .CopyDst},
		indirect_bytes,
	)
	shadow_indirect_template_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Shadow Indirect Template",
		{.CopySrc, .CopyDst},
		indirect_bytes,
	)
	indirect_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Indirect Draws",
		{.Storage, .Indirect, .CopyDst},
		indirect_bytes,
	)
	shadow_indirect_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Shadow Indirect Draws",
		{.Storage, .Indirect, .CopyDst},
		shadow_indirect_bytes,
	)
	new_buffers := [?]wgpu.Buffer {
		batch_buffer,
		visible_buffer,
		zero_identity_buffer,
		shadow_visible_buffer,
		indirect_template_buffer,
		shadow_indirect_template_buffer,
		indirect_buffer,
		shadow_indirect_buffer,
	}
	for buffer in new_buffers {
		if buffer == nil {
			for cleanup in new_buffers {
				if cleanup != nil {
					wgpu.BufferRelease(cleanup)
				}
			}
			return "failed to grow GPU draw database buffers"
		}
	}
	cull_bind_group := wgpu_make_cull_bind_group(
		renderer,
		batch_buffer,
		draw_capacity,
		visible_buffer,
		shadow_visible_buffer,
		visible_capacity,
		indirect_buffer,
		shadow_indirect_buffer,
		draw_capacity,
		"Scrapbot GPU Culling Bind Group",
	)
	meshlet_cull_bind_group := wgpu_make_cull_bind_group(
		renderer,
		batch_buffer,
		draw_capacity,
		renderer.gpu_meshlet_visible_buffer,
		renderer.gpu_meshlet_shadow_visible_buffer,
		renderer.gpu_meshlet_visible_buffer_capacity,
		renderer.gpu_meshlet_indirect_buffer,
		renderer.gpu_meshlet_shadow_indirect_buffer,
		renderer.gpu_meshlet_draw_capacity,
		"Scrapbot GPU Meshlet Culling Bind Group",
		meshlet = true,
	)
	compact_cull_bind_group := wgpu_make_cull_bind_group(
		renderer,
		batch_buffer,
		draw_capacity,
		renderer.gpu_compact_visible_buffer,
		renderer.gpu_compact_shadow_visible_buffer,
		renderer.gpu_meshlet_visible_buffer_capacity,
		indirect_buffer,
		shadow_indirect_buffer,
		draw_capacity,
		"Scrapbot GPU Compact Cluster Culling Bind Group",
		compact = true,
	)
	if cull_bind_group == nil || meshlet_cull_bind_group == nil || compact_cull_bind_group == nil {
		if cull_bind_group != nil {
			wgpu.BindGroupRelease(cull_bind_group)
		}
		if meshlet_cull_bind_group != nil {
			wgpu.BindGroupRelease(meshlet_cull_bind_group)
		}
		if compact_cull_bind_group != nil {
			wgpu.BindGroupRelease(compact_cull_bind_group)
		}
		for buffer in new_buffers {
			wgpu.BufferRelease(buffer)
		}
		return "failed to grow GPU culling bind groups"
	}
	if renderer.gpu_cull_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_cull_bind_group)
	}
	if renderer.gpu_meshlet_cull_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_meshlet_cull_bind_group)
	}
	if renderer.gpu_compact_cull_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_compact_cull_bind_group)
	}
	old_buffers := [?]wgpu.Buffer {
		renderer.gpu_batch_info_buffer,
		renderer.gpu_visible_buffer,
		renderer.gpu_zero_identity_buffer,
		renderer.gpu_shadow_visible_buffer,
		renderer.gpu_indirect_template_buffer,
		renderer.gpu_shadow_indirect_template_buffer,
		renderer.gpu_indirect_buffer,
		renderer.gpu_shadow_indirect_buffer,
	}
	for buffer in old_buffers {
		if buffer != nil {
			wgpu.BufferRelease(buffer)
		}
	}
	renderer.gpu_batch_info_buffer = batch_buffer
	renderer.gpu_visible_buffer = visible_buffer
	renderer.gpu_zero_identity_buffer = zero_identity_buffer
	renderer.gpu_shadow_visible_buffer = shadow_visible_buffer
	renderer.gpu_indirect_template_buffer = indirect_template_buffer
	renderer.gpu_shadow_indirect_template_buffer = shadow_indirect_template_buffer
	renderer.gpu_indirect_buffer = indirect_buffer
	renderer.gpu_shadow_indirect_buffer = shadow_indirect_buffer
	renderer.gpu_cull_bind_group = cull_bind_group
	renderer.gpu_meshlet_cull_bind_group = meshlet_cull_bind_group
	renderer.gpu_compact_cull_bind_group = compact_cull_bind_group
	renderer.gpu_draw_capacity = draw_capacity
	renderer.gpu_visible_buffer_capacity = visible_capacity
	renderer.gpu_draw_database_rebuild_count += 1
	clear(&renderer.gpu_indirect_templates)
	clear(&renderer.gpu_shadow_indirect_templates)
	return wgpu_rebuild_cull_bind_group(renderer)
}

wgpu_ensure_gpu_meshlet_buffers :: proc(
	renderer: ^WGPU_Renderer,
	required_draws, required_visible: int,
) -> string {
	if required_visible > WGPU_MAX_MESHLET_VISIBLE_ENTRIES {
		renderer.gpu_meshlet_layout_valid = false
		return ""
	}
	if required_draws <= renderer.gpu_meshlet_draw_capacity &&
	   required_visible <= renderer.gpu_meshlet_visible_buffer_capacity {
		return ""
	}
	draw_capacity, draw_capacity_ok := wgpu_grow_storage_binding_capacity(
		renderer.gpu_meshlet_draw_capacity,
		required_draws,
		u64(size_of(WGPU_GPU_Meshlet_Info)),
		renderer.max_storage_buffer_binding_size,
	)
	if !draw_capacity_ok {
		renderer.gpu_meshlet_layout_valid = false
		return ""
	}
	visible_capacity := wgpu_grow_capacity(
		renderer.gpu_meshlet_visible_buffer_capacity,
		required_visible,
	)
	info_bytes := u64(draw_capacity) * u64(size_of(WGPU_GPU_Meshlet_Info))
	visible_bytes := u64(visible_capacity) * u64(size_of(u32))
	indirect_bytes := u64(draw_capacity) * u64(size_of(WGPU_Draw_Indexed_Indirect))
	info_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Table",
		{.Storage, .CopyDst},
		info_bytes,
	)
	visible_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Visible Instances",
		{.Storage, .CopyDst},
		wgpu_meshlet_visible_buffer_bytes(visible_capacity),
	)
	identity_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Identities",
		{.Storage, .CopyDst},
		visible_bytes,
	)
	shadow_visible_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Shadow Visible Instances",
		{.Storage, .CopyDst},
		visible_bytes * WGPU_SHADOW_CASCADE_COUNT,
	)
	compact_visible_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Compact Cluster Records",
		{.Storage, .Vertex},
		wgpu_compact_visible_buffer_bytes(visible_capacity),
	)
	compact_shadow_visible_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Compact Shadow Cluster Records",
		{.Storage, .Vertex},
		u64(visible_capacity) * u64(size_of(WGPU_GPU_Compact_Record)) * WGPU_SHADOW_CASCADE_COUNT,
	)
	template_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Indirect Template",
		{.CopySrc, .CopyDst},
		indirect_bytes,
	)
	indirect_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Indirect Draws",
		{.Storage, .Indirect, .CopyDst},
		indirect_bytes,
	)
	shadow_indirect_buffer := wgpu_create_gpu_buffer(
		renderer,
		"Scrapbot GPU Meshlet Shadow Indirect Draws",
		{.Storage, .Indirect, .CopyDst},
		indirect_bytes * WGPU_SHADOW_CASCADE_COUNT,
	)
	new_buffers := [?]wgpu.Buffer {
		info_buffer,
		visible_buffer,
		identity_buffer,
		shadow_visible_buffer,
		compact_visible_buffer,
		compact_shadow_visible_buffer,
		template_buffer,
		indirect_buffer,
		shadow_indirect_buffer,
	}
	for buffer in new_buffers {
		if buffer != nil {
			continue
		}
		for cleanup in new_buffers {
			if cleanup != nil {
				wgpu.BufferRelease(cleanup)
			}
		}
		return "failed to grow GPU meshlet buffers"
	}
	old_buffers := [?]wgpu.Buffer {
		renderer.gpu_meshlet_info_buffer,
		renderer.gpu_meshlet_visible_buffer,
		renderer.gpu_meshlet_identity_buffer,
		renderer.gpu_meshlet_shadow_visible_buffer,
		renderer.gpu_compact_visible_buffer,
		renderer.gpu_compact_shadow_visible_buffer,
		renderer.gpu_meshlet_indirect_template_buffer,
		renderer.gpu_meshlet_indirect_buffer,
		renderer.gpu_meshlet_shadow_indirect_buffer,
	}
	old_draw_capacity := renderer.gpu_meshlet_draw_capacity
	old_visible_capacity := renderer.gpu_meshlet_visible_buffer_capacity
	renderer.gpu_meshlet_info_buffer = info_buffer
	renderer.gpu_meshlet_visible_buffer = visible_buffer
	renderer.gpu_meshlet_identity_buffer = identity_buffer
	renderer.gpu_meshlet_shadow_visible_buffer = shadow_visible_buffer
	renderer.gpu_compact_visible_buffer = compact_visible_buffer
	renderer.gpu_compact_shadow_visible_buffer = compact_shadow_visible_buffer
	renderer.gpu_meshlet_indirect_template_buffer = template_buffer
	renderer.gpu_meshlet_indirect_buffer = indirect_buffer
	renderer.gpu_meshlet_shadow_indirect_buffer = shadow_indirect_buffer
	renderer.gpu_meshlet_draw_capacity = draw_capacity
	renderer.gpu_meshlet_visible_buffer_capacity = visible_capacity
	rebuild_err := wgpu_rebuild_cull_bind_group(renderer)
	if rebuild_err == "" {
		rebuild_err = wgpu_rebuild_meshlet_debug_bind_group(renderer)
	}
	if rebuild_err != "" {
		renderer.gpu_meshlet_info_buffer = old_buffers[0]
		renderer.gpu_meshlet_visible_buffer = old_buffers[1]
		renderer.gpu_meshlet_identity_buffer = old_buffers[2]
		renderer.gpu_meshlet_shadow_visible_buffer = old_buffers[3]
		renderer.gpu_compact_visible_buffer = old_buffers[4]
		renderer.gpu_compact_shadow_visible_buffer = old_buffers[5]
		renderer.gpu_meshlet_indirect_template_buffer = old_buffers[6]
		renderer.gpu_meshlet_indirect_buffer = old_buffers[7]
		renderer.gpu_meshlet_shadow_indirect_buffer = old_buffers[8]
		renderer.gpu_meshlet_draw_capacity = old_draw_capacity
		renderer.gpu_meshlet_visible_buffer_capacity = old_visible_capacity
		_ = wgpu_rebuild_cull_bind_group(renderer)
		_ = wgpu_rebuild_meshlet_debug_bind_group(renderer)
		for buffer in new_buffers {
			wgpu.BufferRelease(buffer)
		}
		return rebuild_err
	}
	for buffer in old_buffers {
		if buffer != nil {
			wgpu.BufferRelease(buffer)
		}
	}
	renderer.gpu_draw_database_rebuild_count += 1
	return ""
}

wgpu_release_batch_bind_groups :: proc(cache: ^WGPU_Draw_Batch_Cache) {
	if cache == nil {
		return
	}
	for batch_index in 0 ..< cache.batch_count {
		batch := &cache.batches[batch_index]
		if batch.world_bind_group != nil {
			wgpu.BindGroupRelease(batch.world_bind_group)
		}
		for shadow_bind_group in batch.shadow_bind_groups {
			if shadow_bind_group != nil {
				wgpu.BindGroupRelease(shadow_bind_group)
			}
		}
		batch.world_bind_group = nil
		batch.shadow_bind_groups = {}
	}
}

wgpu_release_submission_bind_groups :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil {
		return
	}
	if renderer.gpu_world_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_world_bind_group)
	}
	if renderer.gpu_meshlet_world_bind_group != nil {
		wgpu.BindGroupRelease(renderer.gpu_meshlet_world_bind_group)
	}
	if renderer.transparent_world_bind_group != nil {
		wgpu.BindGroupRelease(renderer.transparent_world_bind_group)
	}
	for bind_group in renderer.gpu_shadow_bind_groups {
		if bind_group != nil {
			wgpu.BindGroupRelease(bind_group)
		}
	}
	for bind_group in renderer.gpu_meshlet_shadow_bind_groups {
		if bind_group != nil {
			wgpu.BindGroupRelease(bind_group)
		}
	}
	renderer.gpu_world_bind_group = nil
	renderer.gpu_shadow_bind_groups = {}
	renderer.gpu_meshlet_world_bind_group = nil
	renderer.gpu_meshlet_shadow_bind_groups = {}
	renderer.transparent_world_bind_group = nil
}

wgpu_geometry_storage_binding_bytes :: proc "contextless" (
	renderer: ^WGPU_Renderer,
	capacity: u64,
) -> u64 {
	if renderer == nil || renderer.max_storage_buffer_binding_size == 0 {
		return capacity
	}
	return min(capacity, renderer.max_storage_buffer_binding_size)
}

wgpu_make_batch_bind_group :: proc(
	renderer: ^WGPU_Renderer,
	visible_buffer: wgpu.Buffer,
	visible_offset, visible_capacity: u32,
	label: string,
	shadow: bool = false,
	shadow_cascade_index: int = 0,
	shadow_visible_stride: int = 0,
	meshlet_identity: bool = false,
) -> wgpu.BindGroup {
	identity_buffer := renderer.gpu_zero_identity_buffer
	identity_offset: u64
	identity_size := u64(max(visible_capacity, 1)) * u64(size_of(u32))
	if meshlet_identity {
		identity_buffer = renderer.gpu_meshlet_identity_buffer
		identity_offset = u64(visible_offset) * u64(size_of(u32))
		identity_size = u64(visible_capacity) * u64(size_of(u32))
	}
	if shadow {
		visible_stride := shadow_visible_stride
		if visible_stride <= 0 {
			visible_stride = renderer.gpu_visible_buffer_capacity
		}
		entries := [?]wgpu.BindGroupEntry {
			{
				binding = 0,
				buffer = renderer.gpu_render_uniform_buffer,
				size = u64(size_of(WGPU_GPU_Render_Uniform)),
			},
			{
				binding = 3,
				buffer = renderer.gpu_instance_buffer,
				size = u64(WGPU_MAX_GPU_INSTANCES) * u64(size_of(WGPU_GPU_Instance)),
			},
			{
				binding = 4,
				buffer = visible_buffer,
				offset = u64(shadow_cascade_index * visible_stride + int(visible_offset)) *
				u64(size_of(u32)),
				size = u64(visible_capacity) * u64(size_of(u32)),
			},
			{
				binding = 9,
				buffer = renderer.gpu_shadow_cascade_uniform_buffers[shadow_cascade_index],
				size = u64(size_of(WGPU_Shadow_Cascade_Uniform)),
			},
			{
				binding = 10,
				buffer = identity_buffer,
				offset = identity_offset,
				size = identity_size,
			},
			{
				binding = 11,
				buffer = renderer.geometry_vertex_arena.buffer,
				size = wgpu_geometry_storage_binding_bytes(
					renderer,
					renderer.geometry_vertex_arena.capacity,
				),
			},
			{
				binding = 12,
				buffer = renderer.geometry_index_arena.buffer,
				size = wgpu_geometry_storage_binding_bytes(
					renderer,
					renderer.geometry_index_arena.capacity,
				),
			},
			{
				binding = 13,
				buffer = renderer.gpu_meshlet_info_buffer,
				size = u64(renderer.gpu_meshlet_draw_capacity) *
				u64(size_of(WGPU_GPU_Meshlet_Info)),
			},
		}
		return wgpu.DeviceCreateBindGroup(
			renderer.device,
			&wgpu.BindGroupDescriptor {
				label = label,
				layout = renderer.gpu_driven_shadow_bind_group_layout,
				entryCount = uint(len(entries)),
				entries = raw_data(entries[:]),
			},
		)
	}
	entries := [?]wgpu.BindGroupEntry {
		{
			binding = 0,
			buffer = renderer.gpu_render_uniform_buffer,
			size = u64(size_of(WGPU_GPU_Render_Uniform)),
		},
		{binding = 1, textureView = renderer.shadow_array_view},
		{binding = 2, sampler = renderer.shadow_sampler},
		{
			binding = 3,
			buffer = renderer.gpu_instance_buffer,
			size = u64(WGPU_MAX_GPU_INSTANCES) * u64(size_of(WGPU_GPU_Instance)),
		},
		{
			binding = 4,
			buffer = visible_buffer,
			offset = u64(visible_offset) * u64(size_of(u32)),
			size = u64(visible_capacity) * u64(size_of(u32)),
		},
		{
			binding = 5,
			buffer = renderer.gpu_point_light_buffer,
			size = u64(renderer.gpu_point_light_capacity) * u64(size_of(WGPU_GPU_Point_Light)),
		},
		{
			binding = 6,
			buffer = renderer.gpu_cluster_count_buffer,
			size = u64(WGPU_CLUSTER_COUNT) * u64(size_of(u32)),
		},
		{
			binding = 7,
			buffer = renderer.gpu_cluster_index_buffer,
			size = u64(WGPU_CLUSTER_COUNT * renderer.gpu_cluster_light_capacity) *
			u64(size_of(u32)),
		},
		{
			binding = 8,
			buffer = renderer.gpu_cluster_uniform_buffer,
			size = u64(size_of(WGPU_Cluster_Uniform)),
		},
		{binding = 10, buffer = identity_buffer, offset = identity_offset, size = identity_size},
		{
			binding = 11,
			buffer = renderer.geometry_vertex_arena.buffer,
			size = wgpu_geometry_storage_binding_bytes(
				renderer,
				renderer.geometry_vertex_arena.capacity,
			),
		},
		{
			binding = 12,
			buffer = renderer.geometry_index_arena.buffer,
			size = wgpu_geometry_storage_binding_bytes(
				renderer,
				renderer.geometry_index_arena.capacity,
			),
		},
		{
			binding = 13,
			buffer = renderer.gpu_meshlet_info_buffer,
			size = u64(renderer.gpu_meshlet_draw_capacity) * u64(size_of(WGPU_GPU_Meshlet_Info)),
		},
	}
	return wgpu.DeviceCreateBindGroup(
		renderer.device,
		&wgpu.BindGroupDescriptor {
			label = label,
			layout = renderer.gpu_driven_world_bind_group_layout,
			entryCount = uint(len(entries)),
			entries = raw_data(entries[:]),
		},
	)
}

wgpu_rebuild_submission_bind_groups :: proc(renderer: ^WGPU_Renderer) -> string {
	if renderer == nil || !renderer.gpu_meshlet_supported {
		return ""
	}
	// A valid world may have no renderable topology yet. The shared arenas are created lazily with
	// the first Geometry upload, so there is no submission bind group to build until then.
	if renderer.geometry_vertex_arena.buffer == nil ||
	   renderer.geometry_index_arena.buffer == nil {
		wgpu_release_submission_bind_groups(renderer)
		return ""
	}
	world_bind_group := wgpu_make_batch_bind_group(
		renderer,
		renderer.gpu_visible_buffer,
		0,
		u32(renderer.gpu_visible_buffer_capacity),
		"Scrapbot GPU Shared World Bind Group",
	)
	meshlet_world_bind_group := wgpu_make_batch_bind_group(
		renderer,
		renderer.gpu_meshlet_visible_buffer,
		0,
		u32(renderer.gpu_meshlet_visible_buffer_capacity),
		"Scrapbot GPU Shared Meshlet World Bind Group",
		meshlet_identity = true,
	)
	shadow_bind_groups: [WGPU_SHADOW_CASCADE_COUNT]wgpu.BindGroup
	meshlet_shadow_bind_groups: [WGPU_SHADOW_CASCADE_COUNT]wgpu.BindGroup
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		shadow_bind_groups[cascade_index] = wgpu_make_batch_bind_group(
			renderer,
			renderer.gpu_shadow_visible_buffer,
			0,
			u32(renderer.gpu_visible_buffer_capacity),
			"Scrapbot GPU Shared Shadow Bind Group",
			true,
			cascade_index,
		)
		meshlet_shadow_bind_groups[cascade_index] = wgpu_make_batch_bind_group(
			renderer,
			renderer.gpu_meshlet_shadow_visible_buffer,
			0,
			u32(renderer.gpu_meshlet_visible_buffer_capacity),
			"Scrapbot GPU Shared Meshlet Shadow Bind Group",
			true,
			cascade_index,
			renderer.gpu_meshlet_visible_buffer_capacity,
			true,
		)
	}
	valid := world_bind_group != nil && meshlet_world_bind_group != nil
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		valid =
			valid &&
			shadow_bind_groups[cascade_index] != nil &&
			meshlet_shadow_bind_groups[cascade_index] != nil
	}
	if !valid {
		if world_bind_group != nil {
			wgpu.BindGroupRelease(world_bind_group)
		}
		if meshlet_world_bind_group != nil {
			wgpu.BindGroupRelease(meshlet_world_bind_group)
		}
		for bind_group in shadow_bind_groups {
			if bind_group != nil {
				wgpu.BindGroupRelease(bind_group)
			}
		}
		for bind_group in meshlet_shadow_bind_groups {
			if bind_group != nil {
				wgpu.BindGroupRelease(bind_group)
			}
		}
		return "failed to create shared GPU submission bind groups"
	}
	wgpu_release_submission_bind_groups(renderer)
	renderer.gpu_world_bind_group = world_bind_group
	renderer.gpu_shadow_bind_groups = shadow_bind_groups
	renderer.gpu_meshlet_world_bind_group = meshlet_world_bind_group
	renderer.gpu_meshlet_shadow_bind_groups = meshlet_shadow_bind_groups
	if err := wgpu_rebuild_transparent_world_bind_group(renderer); err != "" {
		return err
	}
	return ""
}

wgpu_sync_gpu_topology :: proc(
	renderer: ^WGPU_Renderer,
	render_list: ^Render_List,
	registry: ^resources.Registry,
) -> (
	^WGPU_Draw_Batch_Cache,
	string,
) {
	topology_changed :=
		!renderer.gpu_topology_valid ||
		!renderer.draw_batch_cache.valid ||
		renderer.gpu_world_uuid != render_list.world_uuid ||
		renderer.gpu_topology_revision != render_list.topology_revision ||
		renderer.draw_batch_cache.geometry_topology_revision != registry.geometry_topology_revision
	cache := wgpu_ensure_draw_batch_cache(renderer, render_list, registry)
	if cache == nil {
		return nil, "failed to build GPU draw batches"
	}
	if !topology_changed {
		return cache, ""
	}
	if err := wgpu_refresh_gpu_batch_layout(renderer, cache, registry); err != "" {
		return nil, err
	}
	renderer.gpu_topology_revision = render_list.topology_revision
	renderer.gpu_world_uuid = render_list.world_uuid
	renderer.gpu_topology_valid = true
	return cache, ""
}

wgpu_refresh_gpu_batch_layout :: proc(
	renderer: ^WGPU_Renderer,
	cache: ^WGPU_Draw_Batch_Cache,
	registry: ^resources.Registry,
) -> string {
	wgpu_release_batch_bind_groups(cache)
	visible_offset: u32
	meshlet_draw_offset: u32
	meshlet_visible_offset: u32
	meshlet_capacity_valid := true
	meshlet_selected_draw_count := 0
	meshlet_selected_batch_count := 0
	compact_selected_batch_count := 0
	compact_selected_instance_count := 0
	virtual_cluster_draw_count := 0
	conventional_batch_count := 0
	virtual_batch_count := 0
	conventional_instance_count := 0
	virtual_instance_count := 0
	for batch_index in 0 ..< cache.batch_count {
		batch := &cache.batches[batch_index]
		batch.visible_offset = visible_offset
		batch.visible_capacity = wgpu_align_visible_capacity(batch.instance_count)
		visible_offset += batch.visible_capacity
		geometry, ok := resources.get_geometry(registry, batch.geometry)
		if !ok {
			return "GPU draw batch references unavailable geometry"
		}
		material, material_ok := resources.get_material(registry, batch.material)
		if !material_ok {
			return "GPU draw batch references unavailable material"
		}
		batch.custom_shader = material.desc.shader != (shared.Shader_Handle{})
		batch.meshlet_draw_offset = meshlet_draw_offset
		batch.virtual_geometry = wgpu_virtual_geometry_submission(
			renderer,
			geometry,
			batch.geometry_mode,
		)
		batch.meshlet_draw_count = u32(
			len(geometry.clusters) if batch.virtual_geometry else len(geometry.meshlets),
		)
		batch.meshlet_submission =
			batch.virtual_geometry ||
			wgpu_meshlet_batch_submission(batch.meshlet_draw_count, batch.instance_count)
		batch.compact_submission = wgpu_meshlet_submission_uses_compaction(
			renderer,
			batch.meshlet_submission,
		)
		if batch.meshlet_submission {
			meshlet_selected_draw_count += int(batch.meshlet_draw_count)
			meshlet_selected_batch_count += 1
		}
		if batch.compact_submission {
			compact_selected_batch_count += 1
			compact_selected_instance_count += int(batch.instance_count)
		}
		if batch.virtual_geometry {
			virtual_cluster_draw_count += int(batch.meshlet_draw_count)
			virtual_batch_count += 1
			virtual_instance_count += int(batch.instance_count)
		} else {
			conventional_batch_count += 1
			conventional_instance_count += int(batch.instance_count)
		}
		batch.meshlet_visible_offset = meshlet_visible_offset
		batch_capacity, batch_capacity_ok := wgpu_meshlet_batch_visible_capacity(
			batch.meshlet_draw_count,
			batch.instance_count,
		)
		batch.meshlet_visible_capacity = batch_capacity
		meshlet_capacity_valid = meshlet_capacity_valid && batch_capacity_ok
		batch.compact_visible_capacities = {}
		if batch.compact_submission {
			per_cluster_capacity := wgpu_meshlet_visible_instance_capacity(batch.instance_count)
			for cluster in geometry.clusters {
				bucket_index := wgpu_compact_cluster_bucket(cluster.triangle_count)
				batch.compact_visible_capacities[bucket_index] += per_cluster_capacity
			}
		}
		meshlet_draw_offset += batch.meshlet_draw_count
		meshlet_visible_offset += batch.meshlet_visible_capacity
	}
	indirect_command_count := wgpu_assign_compact_submission_spans(
		cache.batches[:cache.batch_count],
		u32(cache.batch_count),
	)
	renderer.gpu_indirect_command_count = int(indirect_command_count)
	if buffer_err := wgpu_ensure_gpu_draw_buffers(
		renderer,
		max(cache.batch_count, renderer.gpu_indirect_command_count),
		int(visible_offset),
	); buffer_err != "" {
		return buffer_err
	}
	renderer.gpu_meshlet_layout_valid =
		renderer.gpu_meshlet_supported &&
		meshlet_capacity_valid &&
		int(meshlet_visible_offset) <= WGPU_MAX_MESHLET_VISIBLE_ENTRIES
	if renderer.gpu_meshlet_layout_valid {
		if buffer_err := wgpu_ensure_gpu_meshlet_buffers(
			renderer,
			int(meshlet_draw_offset),
			int(meshlet_visible_offset),
		); buffer_err != "" {
			return buffer_err
		}
	}
	for batch in cache.batches[:cache.batch_count] {
		if _, geometry_err := wgpu_geometry_cache(
			renderer,
			registry,
			batch.geometry,
			batch.geometry_mode,
		); geometry_err != "" {
			return geometry_err
		}
	}
	if bind_group_err := wgpu_rebuild_submission_bind_groups(renderer); bind_group_err != "" {
		return bind_group_err
	}
	batch_info := make([]WGPU_GPU_Batch_Info, cache.batch_count)
	defer delete(batch_info)
	meshlet_identity_count := 1
	if renderer.gpu_meshlet_layout_valid {
		meshlet_identity_count = int(meshlet_visible_offset)
	}
	meshlet_identities := make([]u32, meshlet_identity_count)
	defer delete(meshlet_identities)
	resize(&renderer.gpu_meshlet_infos, int(meshlet_draw_offset))
	resize(&renderer.gpu_meshlet_indirect_templates, int(meshlet_draw_offset))
	for batch_index in 0 ..< cache.batch_count {
		batch := &cache.batches[batch_index]
		geometry, geometry_err := wgpu_geometry_cache(
			renderer,
			registry,
			batch.geometry,
			batch.geometry_mode,
		)
		if geometry_err != "" {
			return geometry_err
		}
		batch_info[batch_index] = {
			visible_offset = batch.visible_offset,
			visible_capacity = batch.visible_capacity,
			meshlet_offset = batch.meshlet_draw_offset,
			meshlet_count = batch.meshlet_draw_count,
			submission_mode = u32(
				WGPU_Submission_Mode.Compact if batch.compact_submission else (WGPU_Submission_Mode.Meshlet if batch.meshlet_submission else WGPU_Submission_Mode.Classic),
			),
			compact_command_index = batch.compact_command_index,
			compact_command_count = batch.compact_command_count,
			compact_bucket_commands = batch.compact_bucket_commands,
			compact_visible_offsets = batch.compact_visible_offsets,
			compact_visible_capacities = batch.compact_visible_capacities,
			compact_shadow_pages = 1 if batch.compact_submission && wgpu_geometry_uses_compact_shadow_pages(geometry) else 0,
		}
		if !renderer.gpu_meshlet_supported {
			batch.world_bind_group = wgpu_make_batch_bind_group(
				renderer,
				renderer.gpu_visible_buffer,
				batch.visible_offset,
				batch.visible_capacity,
				"Scrapbot GPU-Driven Batch Bind Group",
			)
			for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
				batch.shadow_bind_groups[cascade_index] = wgpu_make_batch_bind_group(
					renderer,
					renderer.gpu_shadow_visible_buffer,
					batch.visible_offset,
					batch.visible_capacity,
					"Scrapbot GPU-Driven Shadow Batch Bind Group",
					true,
					cascade_index,
				)
			}
			if batch.world_bind_group == nil {
				return "failed to create GPU-driven batch bind groups"
			}
			for shadow_bind_group in batch.shadow_bind_groups {
				if shadow_bind_group == nil {
					return "failed to create GPU-driven shadow batch bind groups"
				}
			}
		}
		material, material_ok := resources.get_material(registry, batch.material)
		if !material_ok {
			return "GPU draw batch references unavailable material"
		}
		geometry_resource, geometry_ok := resources.get_geometry(registry, batch.geometry)
		if !geometry_ok {
			return "GPU draw batch references unavailable geometry"
		}
		first_index := u32(geometry.meshlet_index_range.offset / u64(size_of(u32)))
		base_vertex := i32(geometry.vertex_range.offset / u64(size_of(resources.Vertex)))
		per_meshlet_capacity := wgpu_meshlet_visible_instance_capacity(batch.instance_count)
		if batch.virtual_geometry {
			for cluster, local_meshlet_index in geometry_resource.clusters {
				meshlet_index := int(batch.meshlet_draw_offset) + local_meshlet_index
				local_visible_offset := u32(local_meshlet_index) * per_meshlet_capacity
				group := geometry_resource.cluster_groups[cluster.group]
				refined_bounds: [4]f32
				refined_error: f32
				if cluster.refined_group >= 0 {
					refined := geometry_resource.cluster_groups[cluster.refined_group]
					refined_bounds = refined.bounds
					refined_error = refined.error
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
				transition_start: u32
				group_state := geometry.cluster_groups[cluster.group]
				if group_state.active && !group_state.transition_complete {
					transition_start = wgpu_virtual_transition_token(
						group_state.transition_start_frame,
					)
				}
				refined_transition_start: u32
				if cluster.refined_group >= 0 &&
				   int(cluster.refined_group) < len(geometry.cluster_groups) {
					refined_state := geometry.cluster_groups[cluster.refined_group]
					if refined_state.active && !refined_state.transition_complete {
						refined_transition_start = wgpu_virtual_transition_token(
							refined_state.transition_start_frame,
						)
					}
				}
				has_coarse_parent :=
					int(cluster.group + 1) < len(geometry.refined_group_parent_offsets) &&
					geometry.refined_group_parent_offsets[cluster.group] <
						geometry.refined_group_parent_offsets[cluster.group + 1]
				cluster_first_index: u32
				cluster_base_vertex: u32
				if page_resident {
					page := geometry.cluster_pages[cluster.page]
					cluster_first_index =
						u32(page.range.offset / u64(size_of(u32))) + cluster.page_index_offset
					cluster_base_vertex = u32(
						page.vertex_range.offset / u64(size_of(resources.Vertex)),
					)
				}
				renderer.gpu_meshlet_infos[meshlet_index] = {
					bounds = cluster.bounds,
					cone_axis_cutoff = cluster.cone_axis_cutoff,
					group_bounds = group.bounds,
					refined_bounds = refined_bounds,
					visible_offset = batch.meshlet_visible_offset + local_visible_offset,
					visible_capacity = per_meshlet_capacity,
					flags = 1 if material.desc.double_sided else 0,
					group_depth = group.depth,
					group_error = group.error,
					refined_error = refined_error,
					max_depth = geometry_resource.cluster_max_depth,
					virtual_geometry = 1,
					first_index = cluster_first_index,
					base_vertex = cluster_base_vertex,
					triangle_count = cluster.triangle_count,
					page_resident = 1 if page_resident else 0,
					refined_resident = 1 if refined_resident else 0,
					request_geometry_index = batch.geometry.index,
					request_geometry_generation = batch.geometry.generation,
					group_index = u32(cluster.group),
					request_group_index = request_group,
					request_enabled = 1 if request_enabled else 0,
					batch_index = u32(batch_index),
					transition_start = transition_start,
					refined_transition_start = refined_transition_start,
					has_coarse_parent = 1 if has_coarse_parent else 0,
				}
				level_byte := group.depth * 255 / max(geometry_resource.cluster_max_depth, 1)
				identity := (level_byte << 24) | (u32(meshlet_index + 1) & 0x003f_ffff)
				if page_resident && geometry.cluster_pages[cluster.page].prefetched {
					identity |= 0x0040_0000
				}
				if !refined_resident {
					identity |= 0x0080_0000
				}
				renderer.gpu_meshlet_infos[meshlet_index].identity = identity
				renderer.gpu_meshlet_indirect_templates[meshlet_index] = {
					index_count = cluster.triangle_count * 3 if page_resident else 0,
					first_index = cluster_first_index,
					base_vertex = i32(cluster_base_vertex),
					first_instance = batch.meshlet_visible_offset + local_visible_offset,
				}
				if renderer.gpu_meshlet_layout_valid {
					for identity_index in 0 ..< int(per_meshlet_capacity) {
						meshlet_identities[int(batch.meshlet_visible_offset + local_visible_offset) + identity_index] =
							identity
					}
				}
			}
		} else {
			for meshlet, local_meshlet_index in geometry_resource.meshlets {
				meshlet_index := int(batch.meshlet_draw_offset) + local_meshlet_index
				local_visible_offset := u32(local_meshlet_index) * per_meshlet_capacity
				renderer.gpu_meshlet_infos[meshlet_index] = {
					bounds = meshlet.bounds,
					cone_axis_cutoff = meshlet.cone_axis_cutoff,
					visible_offset = batch.meshlet_visible_offset + local_visible_offset,
					visible_capacity = per_meshlet_capacity,
					flags = 1 if material.desc.double_sided else 0,
					first_index = first_index,
					base_vertex = u32(base_vertex),
					triangle_count = meshlet.triangle_count,
					identity = u32(meshlet_index + 1),
					batch_index = u32(batch_index),
				}
				renderer.gpu_meshlet_indirect_templates[meshlet_index] = {
					index_count = meshlet.triangle_count * 3,
					first_index = first_index,
					base_vertex = base_vertex,
					first_instance = batch.meshlet_visible_offset + local_visible_offset,
				}
				if renderer.gpu_meshlet_layout_valid {
					for identity_index in 0 ..< int(per_meshlet_capacity) {
						meshlet_identities[int(batch.meshlet_visible_offset + local_visible_offset) + identity_index] =
							u32(meshlet_index + 1)
					}
				}
				first_index += meshlet.triangle_count * 3
			}
		}
	}
	renderer.gpu_visible_capacity = int(visible_offset)
	renderer.gpu_meshlet_draw_count = int(meshlet_draw_offset)
	renderer.gpu_meshlet_selected_draw_count = meshlet_selected_draw_count
	renderer.gpu_meshlet_selected_batch_count = meshlet_selected_batch_count
	renderer.gpu_compact_selected_batch_count = compact_selected_batch_count
	renderer.gpu_compact_selected_instance_count = compact_selected_instance_count
	renderer.gpu_virtual_cluster_draw_count = virtual_cluster_draw_count
	renderer.gpu_classic_batch_count = cache.batch_count - meshlet_selected_batch_count
	renderer.gpu_conventional_batch_count = conventional_batch_count
	renderer.gpu_virtual_batch_count = virtual_batch_count
	renderer.gpu_conventional_instance_count = conventional_instance_count
	renderer.gpu_virtual_instance_count = virtual_instance_count
	renderer.gpu_meshlet_visible_capacity = int(meshlet_visible_offset)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_batch_info_buffer,
		0,
		raw_data(batch_info),
		uint(len(batch_info) * size_of(WGPU_GPU_Batch_Info)),
	)
	if renderer.gpu_meshlet_layout_valid && renderer.gpu_meshlet_draw_count > 0 {
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_meshlet_identity_buffer,
			0,
			raw_data(meshlet_identities),
			uint(len(meshlet_identities) * size_of(u32)),
		)
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_meshlet_info_buffer,
			0,
			raw_data(renderer.gpu_meshlet_infos[:]),
			uint(len(renderer.gpu_meshlet_infos) * size_of(WGPU_GPU_Meshlet_Info)),
		)
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_meshlet_indirect_template_buffer,
			0,
			raw_data(renderer.gpu_meshlet_indirect_templates[:]),
			uint(
				len(renderer.gpu_meshlet_indirect_templates) * size_of(WGPU_Draw_Indexed_Indirect),
			),
		)
	}
	return ""
}

wgpu_update_indirect_template_cache :: proc(
	renderer: ^WGPU_Renderer,
	cache: ^WGPU_Draw_Batch_Cache,
	registry: ^resources.Registry,
) -> (
	changed: bool,
	err: string,
) {
	if renderer == nil || cache == nil {
		return false, "GPU draw-batch cache is not available"
	}
	command_count := max(renderer.gpu_indirect_command_count, cache.batch_count)
	if len(renderer.gpu_indirect_templates) != command_count {
		resize(&renderer.gpu_indirect_templates, command_count)
		changed = true
	}
	if len(renderer.gpu_shadow_indirect_templates) != command_count {
		resize(&renderer.gpu_shadow_indirect_templates, command_count)
		changed = true
	}
	for batch, batch_index in cache.batches[:cache.batch_count] {
		geometry, geometry_err := wgpu_geometry_cache(
			renderer,
			registry,
			batch.geometry,
			batch.geometry_mode,
		)
		if geometry_err != "" {
			return false, geometry_err
		}
		template := wgpu_geometry_indirect_template(
			geometry,
			batch.visible_offset,
			renderer.gpu_meshlet_supported,
		)
		shadow_template := template
		if batch.compact_submission && geometry.shadow_index_count > 0 {
			shadow_template = wgpu_geometry_shadow_indirect_template(
				geometry,
				batch.visible_offset,
				renderer.gpu_meshlet_supported,
			)
		}
		if renderer.gpu_indirect_templates[batch_index] != template {
			renderer.gpu_indirect_templates[batch_index] = template
			changed = true
		}
		if renderer.gpu_shadow_indirect_templates[batch_index] != shadow_template {
			renderer.gpu_shadow_indirect_templates[batch_index] = shadow_template
			changed = true
		}
		if batch.compact_submission {
			compact_shadow := geometry.vertex_range.size == 0 && geometry.shadow_index_count == 0
			for command_index, bucket_index in batch.compact_bucket_commands {
				if command_index == ~u32(0) {
					continue
				}
				compact_template := WGPU_Draw_Indexed_Indirect {
					index_count = wgpu_compact_cluster_bucket_vertex_count(bucket_index),
					base_vertex = i32(batch.compact_visible_offsets[bucket_index]),
				}
				if renderer.gpu_indirect_templates[command_index] != compact_template {
					renderer.gpu_indirect_templates[command_index] = compact_template
					changed = true
				}
				compact_shadow_template :=
					compact_template if compact_shadow else WGPU_Draw_Indexed_Indirect{}
				if renderer.gpu_shadow_indirect_templates[command_index] !=
				   compact_shadow_template {
					renderer.gpu_shadow_indirect_templates[command_index] = compact_shadow_template
					changed = true
				}
			}
		}
	}
	return
}

wgpu_geometry_shadow_indirect_template :: proc "contextless" (
	geometry: ^WGPU_Geometry_Cache,
	visible_offset: u32,
	global_visible_buffer: bool,
) -> WGPU_Draw_Indexed_Indirect {
	if geometry == nil || geometry.shadow_index_count == 0 {
		return {}
	}
	return {
		index_count = geometry.shadow_index_count,
		first_index = u32(geometry.shadow_index_range.offset / u64(size_of(u32))),
		base_vertex = geometry.shadow_base_vertex,
		first_instance = visible_offset if global_visible_buffer else 0,
	}
}

wgpu_geometry_indirect_template :: proc "contextless" (
	geometry: ^WGPU_Geometry_Cache,
	visible_offset: u32,
	global_visible_buffer: bool,
) -> WGPU_Draw_Indexed_Indirect {
	if geometry == nil {
		return {}
	}
	// Streamed virtual Geometry deliberately has no complete canonical arena
	// allocation. If compact or native cluster submission is unavailable, draw
	// the indexed proxy assembled from its pinned coarse pages instead of
	// emitting an empty classic command. Capacity pressure may reduce detail,
	// but it must never make an otherwise drawable resource disappear.
	if geometry.virtual_geometry &&
	   geometry.vertex_range.size == 0 &&
	   geometry.index_range.size == 0 &&
	   geometry.shadow_index_count > 0 {
		return wgpu_geometry_shadow_indirect_template(
			geometry,
			visible_offset,
			global_visible_buffer,
		)
	}
	return {
		index_count = geometry.index_count,
		first_index = u32(geometry.index_range.offset / u64(size_of(u32))),
		base_vertex = i32(geometry.vertex_range.offset / u64(size_of(resources.Vertex))),
		first_instance = visible_offset if global_visible_buffer else 0,
	}
}

wgpu_refresh_indirect_templates :: proc(
	renderer: ^WGPU_Renderer,
	cache: ^WGPU_Draw_Batch_Cache,
	registry: ^resources.Registry,
) -> string {
	changed, err := wgpu_update_indirect_template_cache(renderer, cache, registry)
	if err != "" {
		return err
	}
	if !changed {
		return ""
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_indirect_template_buffer,
		0,
		raw_data(renderer.gpu_indirect_templates[:]),
		uint(len(renderer.gpu_indirect_templates) * size_of(WGPU_Draw_Indexed_Indirect)),
	)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_shadow_indirect_template_buffer,
		0,
		raw_data(renderer.gpu_shadow_indirect_templates[:]),
		uint(len(renderer.gpu_shadow_indirect_templates) * size_of(WGPU_Draw_Indexed_Indirect)),
	)
	return ""
}

wgpu_instance_local_bounds :: proc(geometry: ^resources.Geometry) -> [4]f32 {
	center := Vec3 {
		(geometry.bounds.min.x + geometry.bounds.max.x) * 0.5,
		(geometry.bounds.min.y + geometry.bounds.max.y) * 0.5,
		(geometry.bounds.min.z + geometry.bounds.max.z) * 0.5,
	}
	half_extent := Vec3 {
		(geometry.bounds.max.x - geometry.bounds.min.x) * 0.5,
		(geometry.bounds.max.y - geometry.bounds.min.y) * 0.5,
		(geometry.bounds.max.z - geometry.bounds.min.z) * 0.5,
	}
	local_radius := math.sqrt(
		half_extent.x * half_extent.x +
		half_extent.y * half_extent.y +
		half_extent.z * half_extent.z,
	)
	return {center.x, center.y, center.z, local_radius}
}

wgpu_instance_bounds :: proc(
	instance: Render_Instance,
	geometry: ^resources.Geometry,
	model: Mat4,
) -> [4]f32 {
	local_bounds := wgpu_instance_local_bounds(geometry)
	center := Vec3{local_bounds[0], local_bounds[1], local_bounds[2]}
	world_center := Vec3 {
		model[0] * center.x + model[4] * center.y + model[8] * center.z + model[12],
		model[1] * center.x + model[5] * center.y + model[9] * center.z + model[13],
		model[2] * center.x + model[6] * center.y + model[10] * center.z + model[14],
	}
	max_scale := max(
		math.abs(instance.transform.scale.x),
		math.abs(instance.transform.scale.y),
		math.abs(instance.transform.scale.z),
	)
	return {world_center.x, world_center.y, world_center.z, local_bounds[3] * max_scale}
}

wgpu_build_gpu_instance_transform :: proc(
	instance: Render_Instance,
	geometry: ^resources.Geometry,
) -> WGPU_GPU_Instance_Transform {
	transform := instance.transform
	return {
		position = {transform.position.x, transform.position.y, transform.position.z, 0},
		rotation = {transform.rotation.x, transform.rotation.y, transform.rotation.z, 0},
		scale = {transform.scale.x, transform.scale.y, transform.scale.z, 0},
		local_bounds = wgpu_instance_local_bounds(geometry),
	}
}

wgpu_update_gpu_instance_transform :: proc(
	record: ^WGPU_GPU_Instance_Transform,
	transform: shared.Transform_Component,
) {
	if record == nil {
		return
	}
	record.position = {transform.position.x, transform.position.y, transform.position.z, 0}
	record.rotation = {transform.rotation.x, transform.rotation.y, transform.rotation.z, 0}
	record.scale = {transform.scale.x, transform.scale.y, transform.scale.z, 0}
}

wgpu_build_gpu_instance :: proc(
	instance: Render_Instance,
	geometry: ^resources.Geometry,
	material: ^resources.Material,
	batch_indices: [shared.MAX_GEOMETRY_LODS]u32,
	lod_count: u32,
) -> WGPU_GPU_Instance {
	color := material.desc.base_color
	emissive := material.desc.emissive
	model := wgpu_build_model(instance.transform)
	return WGPU_GPU_Instance {
		model = model,
		normal_model = wgpu_build_normal_model_from_model(model, instance.transform.scale),
		color = {color.x, color.y, color.z, color.w},
		emissive = {emissive.x, emissive.y, emissive.z, 0},
		render_flags = {
			1 if instance.shadow_caster else 0,
			1 if instance.shadow_receiver else 0,
			1 if wgpu_transform_preserves_meshlet_cones(instance.transform.scale) else 0,
			0,
		},
		bounds = wgpu_instance_bounds(instance, geometry, model),
		batch_indices = batch_indices,
		lod_screen_radii = {
			geometry.lod_screen_radii[0],
			geometry.lod_screen_radii[1],
			geometry.lod_screen_radii[2],
			0,
		},
		lod_count = lod_count,
		active = 1,
	}
}

wgpu_transform_preserves_meshlet_cones :: proc(scale: Vec3) -> bool {
	minimum := min(scale.x, min(scale.y, scale.z))
	maximum := max(scale.x, max(scale.y, scale.z))
	return minimum > 0.000001 && maximum <= minimum * 1.001
}

wgpu_find_draw_batch :: proc(
	cache: ^WGPU_Draw_Batch_Cache,
	geometry: shared.Geometry_Handle,
	material: shared.Material_Handle,
	geometry_mode: shared.Geometry_Mode,
) -> int {
	if cache == nil {
		return -1
	}
	for batch, batch_index in cache.batches[:cache.batch_count] {
		if batch.geometry == geometry &&
		   batch.material == material &&
		   batch.geometry_mode == geometry_mode {
			return batch_index
		}
	}
	return -1
}

wgpu_render_instance_by_slot :: proc(
	render_list: ^Render_List,
	slot: int,
) -> (
	Render_Instance,
	bool,
) {
	if render_list == nil || slot < 0 || slot >= len(render_list.instance_index_by_slot) {
		return {}, false
	}
	instance_index := render_list.instance_index_by_slot[slot]
	if instance_index < 0 || instance_index >= len(render_list.instances) {
		return {}, false
	}
	instance := render_list.instances[instance_index]
	return instance, instance.slot == slot
}

wgpu_render_instance_pointer_by_slot :: proc(
	render_list: ^Render_List,
	slot: int,
) -> ^Render_Instance {
	if render_list == nil || slot < 0 || slot >= len(render_list.instance_index_by_slot) {
		return nil
	}
	instance_index := render_list.instance_index_by_slot[slot]
	if instance_index < 0 || instance_index >= len(render_list.instances) {
		return nil
	}
	instance := &render_list.instances[instance_index]
	if instance.slot != slot {
		return nil
	}
	return instance
}

wgpu_batch_indices_for_instance :: proc(
	renderer: ^WGPU_Renderer,
	cache: ^WGPU_Draw_Batch_Cache,
	instance: Render_Instance,
	registry: ^resources.Registry,
) -> (
	indices: [shared.MAX_GEOMETRY_LODS]u32,
	ok: bool,
) {
	geometry, geometry_ok := resources.get_geometry(registry, instance.geometry.handle)
	if !geometry_ok {
		return {}, false
	}
	geometry_mode := wgpu_resolve_geometry_mode(
		renderer,
		geometry,
		instance.geometry.geometry_mode,
	)
	base_batch := wgpu_find_draw_batch(
		cache,
		instance.geometry.handle,
		instance.material.handle,
		geometry_mode,
	)
	if base_batch < 0 {
		return {}, false
	}
	indices[0] = u32(base_batch)
	lod_count := wgpu_geometry_draw_lod_count(renderer, geometry, geometry_mode)
	for handle, lod_index in geometry.lod_handles[:lod_count] {
		lod_batch := wgpu_find_draw_batch(cache, handle, instance.material.handle, geometry_mode)
		if lod_batch < 0 {
			return {}, false
		}
		indices[lod_index + 1] = u32(lod_batch)
	}
	return indices, true
}

wgpu_adjust_batch_membership :: proc(
	cache: ^WGPU_Draw_Batch_Cache,
	indices: [shared.MAX_GEOMETRY_LODS]u32,
	lod_count: u32,
	delta: int,
) -> (
	layout_changed: bool,
) {
	count := min(int(lod_count) + 1, shared.MAX_GEOMETRY_LODS)
	for ordinal in 0 ..< count {
		index := indices[ordinal]
		duplicate := false
		for previous_ordinal in 0 ..< ordinal {
			previous := indices[previous_ordinal]
			if previous == index {
				duplicate = true
				break
			}
		}
		if duplicate || int(index) >= cache.batch_count {
			continue
		}
		batch := &cache.batches[index]
		previous_meshlet_submission := wgpu_meshlet_batch_submission(
			batch.meshlet_draw_count,
			batch.instance_count,
		)
		if delta > 0 {
			batch.instance_count += u32(delta)
			cache.instance_count += delta
			layout_changed = layout_changed || batch.instance_count > batch.visible_capacity
		} else if batch.instance_count > 0 {
			batch.instance_count -= u32(-delta)
			cache.instance_count = max(cache.instance_count + delta, 0)
			if batch.instance_count == 0 {
				cache.valid = false
			}
		}
		layout_changed =
			layout_changed ||
			previous_meshlet_submission !=
				wgpu_meshlet_batch_submission(batch.meshlet_draw_count, batch.instance_count)
	}
	return
}

wgpu_instance_membership_matches :: proc(
	previous: WGPU_Instance_Source_State,
	indices: [shared.MAX_GEOMETRY_LODS]u32,
	lod_count: u32,
) -> bool {
	return previous.lod_count == lod_count && previous.batch_indices == indices
}

wgpu_instance_batch_key_matches :: proc(
	previous: WGPU_Instance_Source_State,
	instance: Render_Instance,
) -> bool {
	return(
		previous.geometry == instance.geometry.handle &&
		previous.material == instance.material.handle \
	)
}

wgpu_instance_update_work :: proc(
	previous_active: bool,
	previous, current: WGPU_Instance_Source_State,
	previous_transform, current_transform: shared.Transform_Component,
) -> (
	static_changed, transform_input_changed, expand_transform: bool,
) {
	static_changed = !previous_active || previous != current
	transform_changed := !previous_active || previous_transform != current_transform
	bounds_source_changed :=
		!previous_active ||
		previous.geometry != current.geometry ||
		previous.geometry_version != current.geometry_version
	transform_input_changed = transform_changed || bounds_source_changed
	expand_transform = transform_changed && !static_changed
	return
}

wgpu_instance_source_changed :: proc(
	previous_active: bool,
	previous, current: WGPU_Instance_Source_State,
	previous_transform, current_transform: shared.Transform_Component,
) -> bool {
	return !previous_active || previous != current || previous_transform != current_transform
}

wgpu_sync_dirty_instance_slot :: proc(
	renderer: ^WGPU_Renderer,
	cache: ^WGPU_Draw_Batch_Cache,
	render_list: ^Render_List,
	registry: ^resources.Registry,
	slot: int,
	cpu_culling: bool,
) -> (
	batch_layout_changed: bool,
	err: string,
) {
	if slot < 0 || slot >= render_list.instance_slot_count {
		return
	}
	instance, active := wgpu_render_instance_by_slot(render_list, slot)
	previous_active := renderer.gpu_active_slots[slot]
	previous_source := renderer.gpu_instance_sources[slot]
	previous_transform := renderer.gpu_instance_source_transforms[slot]
	if !active {
		if previous_active {
			_ = wgpu_adjust_batch_membership(
				cache,
				previous_source.batch_indices,
				previous_source.lod_count,
				-1,
			)
			renderer.gpu_instance_records[slot] = {}
			renderer.gpu_instance_transform_records[slot] = {}
			renderer.gpu_instance_sources[slot] = {}
			renderer.gpu_instance_source_transforms[slot] = {}
			renderer.gpu_active_slots[slot] = false
			append(&renderer.gpu_dirty_indices, slot)
		}
		return
	}
	geometry, geometry_ok := resources.get_geometry(registry, instance.geometry.handle)
	material, material_ok := resources.get_material(registry, instance.material.handle)
	if !geometry_ok || !material_ok {
		return
	}
	batch_indices := previous_source.batch_indices
	if !previous_active || !wgpu_instance_batch_key_matches(previous_source, instance) {
		batches_ok: bool
		batch_indices, batches_ok = wgpu_batch_indices_for_instance(
			renderer,
			cache,
			instance,
			registry,
		)
		if !batches_ok {
			return false, "GPU instance is missing its draw batch"
		}
	}
	lod_count := u32(wgpu_geometry_draw_lod_count(renderer, geometry))
	source := WGPU_Instance_Source_State {
		geometry = instance.geometry.handle,
		material = instance.material.handle,
		geometry_version = geometry.version,
		material_version = material.version,
		shadow_caster = instance.shadow_caster,
		shadow_receiver = instance.shadow_receiver,
		batch_indices = batch_indices,
		lod_screen_radii = {
			geometry.lod_screen_radii[0],
			geometry.lod_screen_radii[1],
			geometry.lod_screen_radii[2],
			0,
		},
		lod_count = lod_count,
	}
	membership_changed :=
		!previous_active ||
		!wgpu_instance_membership_matches(previous_source, batch_indices, lod_count)
	if membership_changed && previous_active {
		_ = wgpu_adjust_batch_membership(
			cache,
			previous_source.batch_indices,
			previous_source.lod_count,
			-1,
		)
	}
	if membership_changed {
		batch_layout_changed = wgpu_adjust_batch_membership(cache, batch_indices, lod_count, 1)
	}
	if wgpu_instance_source_changed(
		previous_active,
		previous_source,
		source,
		previous_transform,
		instance.transform,
	) {
		static_changed, transform_input_changed, expand_transform := wgpu_instance_update_work(
			previous_active,
			previous_source,
			source,
			previous_transform,
			instance.transform,
		)
		if static_changed || cpu_culling {
			renderer.gpu_instance_records[slot] = wgpu_build_gpu_instance(
				instance,
				geometry,
				material,
				batch_indices,
				lod_count,
			)
		}
		if static_changed {
			append(&renderer.gpu_dirty_indices, slot)
		}
		if transform_input_changed {
			renderer.gpu_instance_transform_records[slot] = wgpu_build_gpu_instance_transform(
				instance,
				geometry,
			)
		}
		if expand_transform {
			wgpu_append_transform_update(renderer, slot)
		}
		renderer.gpu_instance_sources[slot] = source
		renderer.gpu_instance_source_transforms[slot] = instance.transform
		renderer.gpu_active_slots[slot] = true
	}
	return
}

wgpu_rebuild_instance_batch_cache :: proc(
	renderer: ^WGPU_Renderer,
	cache: ^WGPU_Draw_Batch_Cache,
	render_list: ^Render_List,
	registry: ^resources.Registry,
	slot_count: int,
) -> string {
	resize(&renderer.gpu_batch_indices_by_slot, slot_count)
	for instance in render_list.instances {
		if instance.slot < 0 || instance.slot >= slot_count {
			continue
		}
		geometry, ok := resources.get_geometry(registry, instance.geometry.handle)
		if !ok {
			return "GPU instance references unavailable geometry"
		}
		geometry_mode := wgpu_resolve_geometry_mode(
			renderer,
			geometry,
			instance.geometry.geometry_mode,
		)
		batch_indices: [shared.MAX_GEOMETRY_LODS]u32
		base_batch := wgpu_find_draw_batch(
			cache,
			instance.geometry.handle,
			instance.material.handle,
			geometry_mode,
		)
		if base_batch < 0 {
			return "GPU instance is missing its draw batch"
		}
		batch_indices[0] = u32(base_batch)
		lod_count := wgpu_geometry_draw_lod_count(renderer, geometry, geometry_mode)
		for handle, lod_index in geometry.lod_handles[:lod_count] {
			lod_batch := wgpu_find_draw_batch(
				cache,
				handle,
				instance.material.handle,
				geometry_mode,
			)
			if lod_batch < 0 {
				return "GPU LOD geometry is missing its draw batch"
			}
			batch_indices[lod_index + 1] = u32(lod_batch)
		}
		renderer.gpu_batch_indices_by_slot[instance.slot] = batch_indices
	}
	return ""
}

wgpu_next_instance_upload_range :: proc(
	dirty_indices: []int,
	start: int,
) -> (
	first, last, next: int,
) {
	first = dirty_indices[start]
	last = first + 1
	next = start + 1
	for next < len(dirty_indices) {
		slot := dirty_indices[next]
		if slot < last {
			next += 1
			continue
		}
		if slot - last > WGPU_INSTANCE_UPLOAD_MERGE_GAP {
			break
		}
		last = slot + 1
		next += 1
	}
	return
}

wgpu_sort_dirty_indices_if_needed :: proc(dirty_indices: []int) {
	for index in 1 ..< len(dirty_indices) {
		if dirty_indices[index] < dirty_indices[index - 1] {
			slice.sort(dirty_indices)
			return
		}
	}
}

wgpu_upload_dirty_instance_ranges :: proc(renderer: ^WGPU_Renderer, dirty_indices: []int) {
	if len(dirty_indices) == 0 {
		return
	}
	wgpu_sort_dirty_indices_if_needed(dirty_indices)
	index := 0
	for index < len(dirty_indices) {
		first, last, next := wgpu_next_instance_upload_range(dirty_indices, index)
		index = next
		count := last - first
		byte_count := uint(count * size_of(WGPU_GPU_Instance))
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_instance_buffer,
			u64(first * size_of(WGPU_GPU_Instance)),
			raw_data(renderer.gpu_instance_records[first:last]),
			byte_count,
		)
		renderer.gpu_instance_upload_count += 1
		renderer.gpu_instance_upload_bytes += u64(byte_count)
	}
}

wgpu_append_transform_update :: proc(renderer: ^WGPU_Renderer, slot: int) {
	if renderer == nil || slot < 0 || slot >= len(renderer.gpu_instance_transform_records) {
		return
	}
	update := renderer.gpu_instance_transform_records[slot]
	update.position[3] = f32(slot)
	append(&renderer.gpu_transform_updates, update)
}

wgpu_upload_transform_updates :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil || len(renderer.gpu_transform_updates) <= 1 {
		return
	}
	update_count := len(renderer.gpu_transform_updates) - 1
	renderer.gpu_transform_updates[0].position[3] = f32(update_count)
	byte_count := uint(len(renderer.gpu_transform_updates) * size_of(WGPU_GPU_Instance_Transform))
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_transform_update_buffer,
		0,
		raw_data(renderer.gpu_transform_updates[:]),
		byte_count,
	)
	renderer.gpu_instance_upload_count += 1
	renderer.gpu_instance_upload_bytes += u64(byte_count)
	renderer.gpu_instance_transform_upload_count += 1
	renderer.gpu_instance_transform_upload_bytes += u64(byte_count)
}

wgpu_cpu_cull_counts :: proc(
	instances: []WGPU_GPU_Instance,
	planes: [6][4]f32,
	batch_count: int,
	shadow: bool = false,
	view_projection: Mat4 = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
) -> [dynamic]u32 {
	counts := make([dynamic]u32, batch_count)
	for instance in instances {
		lod_level := wgpu_cpu_instance_lod_level(instance, view_projection)
		batch_index := instance.batch_indices[lod_level]
		if instance.active == 0 || int(batch_index) >= batch_count {
			continue
		}
		if shadow && instance.render_flags[0] < 0.5 {
			continue
		}
		if wgpu_sphere_visible(instance.bounds, planes) {
			counts[batch_index] += 1
		}
	}
	return counts
}

wgpu_cpu_instance_lod_level :: proc(instance: WGPU_GPU_Instance, view_projection: Mat4) -> int {
	if instance.lod_count == 0 {
		return 0
	}
	clip_w :=
		view_projection[3] * instance.bounds[0] +
		view_projection[7] * instance.bounds[1] +
		view_projection[11] * instance.bounds[2] +
		view_projection[15]
	if clip_w <= 0.0001 {
		return 0
	}
	screen_radius := math.abs(instance.bounds[3] * view_projection[5] / clip_w) * 0.5
	level := 0
	radii := instance.lod_screen_radii
	for threshold, index in radii[:int(instance.lod_count)] {
		if screen_radius < threshold {
			level = index + 1
		}
	}
	return level
}

wgpu_hiz_reuse_allowed :: proc(
	requested, valid, instance_data_changed: bool,
	previous_view_projection, current_view_projection: Mat4,
) -> bool {
	return(
		requested &&
		valid &&
		!instance_data_changed &&
		previous_view_projection == current_view_projection \
	)
}

wgpu_hiz_build_requested :: proc(slot_count: int, instance_data_changed: bool) -> bool {
	return slot_count >= WGPU_HIZ_MIN_INSTANCES && !instance_data_changed
}

wgpu_hiz_occlusion_status :: proc(
	forced, valid, instance_data_changed: bool,
	slot_count: int,
	previous_view_projection, current_view_projection: Mat4,
) -> shared.HiZ_Occlusion_Status {
	if !forced && slot_count < WGPU_HIZ_MIN_INSTANCES {
		return .Below_Threshold
	}
	if instance_data_changed {
		return .Scene_Changed
	}
	if !valid {
		return .Warming_Up
	}
	if previous_view_projection != current_view_projection {
		return .Camera_Changed
	}
	return .Active
}

wgpu_hiz_sphere_projection_safe :: proc(bounds: [4]f32, camera_position: Vec3) -> bool {
	offset := Vec3 {
		bounds[0] - camera_position.x,
		bounds[1] - camera_position.y,
		bounds[2] - camera_position.z,
	}
	distance_squared := offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
	conservative_distance := bounds[3] * 4
	return distance_squared > conservative_distance * conservative_distance
}

wgpu_retain_render_uniform :: proc(
	renderer: ^WGPU_Renderer,
	uniform: WGPU_GPU_Render_Uniform,
) -> bool {
	if renderer.gpu_render_uniform_valid && renderer.gpu_render_uniform == uniform {
		return false
	}
	renderer.gpu_render_uniform = uniform
	renderer.gpu_render_uniform_valid = true
	return true
}

wgpu_retain_cull_uniform :: proc(
	renderer: ^WGPU_Renderer,
	uniform: WGPU_GPU_Cull_Uniform,
) -> bool {
	if renderer.gpu_cull_uniform_valid && renderer.gpu_cull_uniform == uniform {
		return false
	}
	renderer.gpu_cull_uniform = uniform
	renderer.gpu_cull_uniform_valid = true
	return true
}

wgpu_reset_gpu_instance_slots :: proc(renderer: ^WGPU_Renderer) {
	if renderer == nil {
		return
	}
	for slot in 0 ..< len(renderer.gpu_instance_records) {
		renderer.gpu_instance_records[slot] = {}
		renderer.gpu_instance_transform_records[slot] = {}
		renderer.gpu_instance_sources[slot] = {}
		renderer.gpu_instance_source_transforms[slot] = {}
		renderer.gpu_active_slots[slot] = false
		append(&renderer.gpu_dirty_indices, slot)
	}
	clear(&renderer.gpu_live_slots)
}

wgpu_material_instance_needs_sync :: proc(
	renderer: ^WGPU_Renderer,
	registry: ^resources.Registry,
	instance: Render_Instance,
) -> bool {
	if renderer == nil || registry == nil {
		return false
	}
	slot := instance.slot
	if slot < 0 ||
	   slot >= len(renderer.gpu_active_slots) ||
	   slot >= len(renderer.gpu_instance_sources) ||
	   !renderer.gpu_active_slots[slot] {
		return false
	}
	material, alive := resources.get_material(registry, instance.material.handle)
	return alive && renderer.gpu_instance_sources[slot].material_version != material.version
}

wgpu_prepare_gpu_draw_batches :: proc(
	renderer: ^WGPU_Renderer,
	render_list: ^Render_List,
	registry: ^resources.Registry,
	viewport: ui.Rect,
	target_width, target_height: u32,
	cpu_culling: bool,
) -> (
	[]WGPU_Draw_Batch,
	int,
	string,
) {
	slot_count := render_list.instance_slot_count
	temporal_world_changed :=
		renderer.gpu_topology_valid && renderer.gpu_world_uuid != render_list.world_uuid
	if slot_count > WGPU_MAX_GPU_INSTANCES {
		return nil, 0, "GPU-driven renderer exceeded its instance-slot capacity"
	}
	if renderer.gpu_topology_valid &&
	   renderer.gpu_world_uuid == render_list.world_uuid &&
	   renderer.draw_batch_cache.geometry_topology_revision ==
		   registry.geometry_topology_revision {
		for slot in render_list.dirty_instance_slots {
			if instance, active := wgpu_render_instance_by_slot(render_list, slot); active {
				if slot >= 0 &&
				   slot < len(renderer.gpu_active_slots) &&
				   renderer.gpu_active_slots[slot] &&
				   wgpu_instance_batch_key_matches(renderer.gpu_instance_sources[slot], instance) {
					continue
				}
				if _, found := wgpu_batch_indices_for_instance(
					renderer,
					&renderer.draw_batch_cache,
					instance,
					registry,
				); !found {
					renderer.draw_batch_cache.valid = false
					break
				}
			}
		}
	}
	topology_changed :=
		!renderer.gpu_topology_valid ||
		!renderer.draw_batch_cache.valid ||
		renderer.gpu_world_uuid != render_list.world_uuid ||
		renderer.gpu_topology_revision != render_list.topology_revision ||
		renderer.draw_batch_cache.geometry_topology_revision != registry.geometry_topology_revision
	cache, topology_err := wgpu_sync_gpu_topology(renderer, render_list, registry)
	if topology_err != "" {
		return nil, 0, topology_err
	}
	debug_view := shared.Render_Debug_View.Lit
	if render_list.has_camera {
		debug_view = render_list.camera.camera.debug_view
	}
	renderer.gpu_meshlet_force_enabled =
		!cpu_culling && wgpu_meshlet_debug_forces_submission(debug_view)
	renderer.gpu_meshlet_submission_active =
		!cpu_culling &&
		renderer.gpu_meshlet_supported &&
		renderer.gpu_meshlet_layout_valid &&
		renderer.gpu_meshlet_draw_count > 0 &&
		(renderer.gpu_meshlet_selected_batch_count > 0 || renderer.gpu_meshlet_force_enabled)
	renderer.gpu_compact_submission_active =
		renderer.gpu_meshlet_submission_active &&
		!renderer.gpu_meshlet_force_enabled &&
		renderer.gpu_compact_selected_batch_count > 0
	renderer.gpu_native_meshlet_submission_active =
		renderer.gpu_meshlet_submission_active &&
		(renderer.gpu_meshlet_selected_batch_count > renderer.gpu_compact_selected_batch_count ||
				renderer.gpu_meshlet_force_enabled)
	old_point_light_buffer, old_cluster_index_buffer, cluster_buffers_grew, cluster_err :=
		wgpu_ensure_clustered_light_capacity(renderer, render_list.point_light_count)
	if cluster_err != "" {
		return nil, 0, cluster_err
	}
	if cluster_buffers_grew {
		if batch_layout_err := wgpu_refresh_gpu_batch_layout(renderer, cache, registry);
		   batch_layout_err != "" {
			return nil, 0, batch_layout_err
		}
		wgpu.BufferRelease(old_point_light_buffer)
		wgpu.BufferRelease(old_cluster_index_buffer)
	}
	if topology_changed {
		if batch_cache_err := wgpu_rebuild_instance_batch_cache(
			renderer,
			cache,
			render_list,
			registry,
			slot_count,
		); batch_cache_err != "" {
			return nil, 0, batch_cache_err
		}
	}
	if indirect_err := wgpu_refresh_indirect_templates(renderer, cache, registry);
	   indirect_err != "" {
		return nil, 0, indirect_err
	}
	uniform: WGPU_GPU_Render_Uniform
	view, projection := wgpu_build_camera_matrices(
		render_list.camera,
		render_list.has_camera,
		u32(viewport.width),
		u32(viewport.height),
	)
	view_projection := mat4_mul(projection, view)
	temporal_camera := wgpu_temporal_camera_state(render_list.camera, render_list.has_camera)
	shadow_camera_discontinuous :=
		renderer.temporal_camera_valid &&
		!wgpu_temporal_camera_continuous(renderer.temporal_camera, temporal_camera)
	if temporal_world_changed || shadow_camera_discontinuous {
		renderer.temporal_history_valid = false
		renderer.temporal_sample_index = 0
	}
	renderer.temporal_camera = temporal_camera
	renderer.temporal_camera_valid = true
	jitter: Vec2
	if render_list.has_camera &&
	   render_list.camera.camera.debug_view == .Lit &&
	   render_list.camera.camera.temporal_antialiasing {
		jitter = wgpu_temporal_jitter(
			renderer.temporal_sample_index,
			u32(viewport.width),
			u32(viewport.height),
		)
	}
	jittered_projection := wgpu_jitter_projection(projection, jitter)
	jittered_view_projection := mat4_mul(jittered_projection, view)
	renderer.temporal_current_view_projection = wgpu_temporal_history_view_projection(
		projection,
		view,
	)
	renderer.temporal_current_projection = {
		jittered_projection[0],
		jittered_projection[5],
		jittered_projection[10],
		jittered_projection[14],
	}
	renderer.temporal_inverse_view = wgpu_inverse_rigid_view(view)
	if hiz_err := wgpu_ensure_hiz_targets(renderer, target_width, target_height); hiz_err != "" {
		return nil, 0, hiz_err
	}
	shadow_cascades: WGPU_Shadow_Cascades
	for &cascade_matrix in shadow_cascades.matrices {
		cascade_matrix = mat4_identity()
	}
	if render_list.directional_light_count > 0 {
		shadow_cascades = wgpu_build_directional_shadow_cascades(
			render_list.camera,
			render_list.has_camera,
			u32(viewport.width),
			u32(viewport.height),
			render_list.directional_lights[0].light.direction,
			max(renderer.shadow_map_resolution, WGPU_SHADOW_MAP_MIN_SIZE),
		)
	}
	shadow_cascades = wgpu_retain_shadow_cascades(
		renderer,
		shadow_cascades,
		render_list.directional_light_count > 0,
		temporal_world_changed ||
		topology_changed ||
		shadow_camera_discontinuous ||
		len(render_list.dirty_instance_slots) > 0,
	)
	uniform.view_projection = jittered_view_projection
	uniform.view = view
	uniform.shadow_view_projections = shadow_cascades.matrices
	uniform.shadow_cascade_splits = shadow_cascades.splits
	uniform.shadow_cascade_texel_sizes = shadow_cascades.texel_sizes
	shadow_resolution := max(renderer.shadow_map_resolution, WGPU_SHADOW_MAP_MIN_SIZE)
	uniform.shadow_map_parameters = {
		f32(shadow_resolution) / f32(WGPU_SHADOW_MAP_SIZE),
		1.0 / f32(WGPU_SHADOW_MAP_SIZE),
		f32(shadow_resolution),
		f32(WGPU_SHADOW_MAP_SIZE),
	}
	camera_position := Vec3{0, 2, 6}
	if render_list.has_camera {
		camera_position = render_list.camera.transform.position
	}
	uniform.camera_position = {camera_position.x, camera_position.y, camera_position.z, 1}
	camera := shared.camera_defaults()
	if render_list.has_camera {
		camera = render_list.camera.camera
	}
	prediction_history_valid :=
		renderer.virtual_geometry_camera_valid &&
		!temporal_world_changed &&
		renderer.virtual_geometry_camera_frame + 1 == renderer.profile_frame_index
	camera_forward := vec3_normalize(Vec3{0, -2, -6})
	if render_list.has_camera {
		camera_forward = shared.camera_forward(render_list.camera.transform.rotation)
	}
	prediction := wgpu_predict_virtual_camera(
		camera_position,
		camera_forward,
		renderer.virtual_geometry_camera_position,
		renderer.virtual_geometry_camera_forward,
		renderer.virtual_geometry_camera_velocity,
		camera.far,
		prediction_history_valid,
	)
	prediction.enabled =
		prediction.enabled && renderer.virtual_geometry_prefetch_enabled && render_list.has_camera
	renderer.virtual_geometry_camera_position = camera_position
	renderer.virtual_geometry_camera_forward = camera_forward
	renderer.virtual_geometry_camera_velocity = prediction.velocity
	renderer.virtual_geometry_camera_frame = renderer.profile_frame_index
	renderer.virtual_geometry_camera_valid = render_list.has_camera
	predictive_view_projection := view_projection
	if prediction.enabled {
		up := shared.camera_up(render_list.camera.transform.rotation)
		predictive_view := mat4_look_at(
			prediction.position,
			wgpu_vec3_add(prediction.position, prediction.forward),
			up,
		)
		aspect := f32(16.0 / 9.0)
		if viewport.width > 0 && viewport.height > 0 {
			aspect = viewport.width / viewport.height
		}
		predictive_fov := clamp(camera.fov + 20, f32(1), f32(120))
		predictive_projection := mat4_perspective(
			math.to_radians(predictive_fov),
			aspect,
			camera.near,
			camera.far,
		)
		predictive_view_projection = mat4_mul(predictive_projection, predictive_view)
	}
	if camera.debug_view != .Occlusion_Queries {
		renderer.gpu_occlusion_debug_evidence_valid = false
		renderer.gpu_occlusion_debug_record_count = 0
	}
	uniform.debug = {
		u32(camera.debug_view),
		1 if renderer.gpu_meshlet_submission_active else 0,
		min(shared.camera_debug_hiz_mip(camera), u32(max(renderer.gpu_hiz_mip_count - 1, 0))),
		1 if camera.debug_occlusion_freeze else 0,
	}
	uniform.camera_clip = {camera.near, camera.far, 0, 0}
	uniform.virtual_geometry = {
		wgpu_effective_virtual_error_pixels(renderer),
		f32(max(viewport.height, 1)),
		WGPU_VIRTUAL_GEOMETRY_BLEND_LOW_SCALE,
		WGPU_VIRTUAL_GEOMETRY_BLEND_HIGH_SCALE,
	}
	uniform.virtual_geometry_epoch = {
		u32(renderer.profile_frame_index),
		u32(WGPU_VIRTUAL_GROUP_TRANSITION_FRAMES),
		1 if camera.temporal_antialiasing && camera.debug_view == .Lit else 0,
		0,
	}
	uniform.ambient = {render_list.ambient.x, render_list.ambient.y, render_list.ambient.z, 1}
	uniform.light_counts = {
		u32(render_list.directional_light_count),
		u32(render_list.point_light_count),
		0,
		0,
	}
	for light, index in render_list.directional_lights[:render_list.directional_light_count] {
		uniform.directional_direction_intensity[index] = {
			light.light.direction.x,
			light.light.direction.y,
			light.light.direction.z,
			light.light.intensity,
		}
		uniform.directional_color[index] = {
			light.light.color.x,
			light.light.color.y,
			light.light.color.z,
			1,
		}
	}
	wgpu_prepare_clustered_lighting(renderer, render_list, view, jittered_projection, viewport)
	if wgpu_retain_render_uniform(renderer, uniform) {
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_render_uniform_buffer,
			0,
			&uniform,
			uint(size_of(uniform)),
		)
	}

	previous_slot_count := len(renderer.gpu_instance_records)
	if slot_count > previous_slot_count {
		resize(&renderer.gpu_instance_records, slot_count)
		resize(&renderer.gpu_instance_transform_records, slot_count)
		resize(&renderer.gpu_instance_sources, slot_count)
		resize(&renderer.gpu_instance_source_transforms, slot_count)
		resize(&renderer.gpu_active_slots, slot_count)
	}
	clear(&renderer.gpu_dirty_indices)
	clear(&renderer.gpu_transform_updates)
	append(&renderer.gpu_transform_updates, WGPU_GPU_Instance_Transform{})
	reset_instances := render_list.full_instance_sync || topology_changed
	if reset_instances {
		wgpu_reset_gpu_instance_slots(renderer)
	}
	batch_layout_changed := false
	instances := render_list.instances[:]
	if !reset_instances {
		instances = nil
	}
	for instance in instances {
		if instance.slot < 0 || instance.slot >= slot_count {
			continue
		}
		geometry, geometry_ok := resources.get_geometry(registry, instance.geometry.handle)
		material, material_ok := resources.get_material(registry, instance.material.handle)
		if !geometry_ok || !material_ok {
			continue
		}
		slot := instance.slot
		batch_indices := renderer.gpu_batch_indices_by_slot[slot]
		lod_count := u32(wgpu_geometry_draw_lod_count(renderer, geometry))
		source := WGPU_Instance_Source_State {
			geometry = instance.geometry.handle,
			material = instance.material.handle,
			geometry_version = geometry.version,
			material_version = material.version,
			shadow_caster = instance.shadow_caster,
			shadow_receiver = instance.shadow_receiver,
			batch_indices = batch_indices,
			lod_screen_radii = {
				geometry.lod_screen_radii[0],
				geometry.lod_screen_radii[1],
				geometry.lod_screen_radii[2],
				0,
			},
			lod_count = lod_count,
		}
		if !renderer.gpu_active_slots[slot] || renderer.gpu_instance_sources[slot] != source {
			record := wgpu_build_gpu_instance(
				instance,
				geometry,
				material,
				batch_indices,
				lod_count,
			)
			renderer.gpu_instance_records[slot] = record
			renderer.gpu_instance_transform_records[slot] = wgpu_build_gpu_instance_transform(
				instance,
				geometry,
			)
			renderer.gpu_instance_sources[slot] = source
			renderer.gpu_instance_source_transforms[slot] = instance.transform
			renderer.gpu_active_slots[slot] = true
			append(&renderer.gpu_dirty_indices, slot)
		}
		if reset_instances {
			append(&renderer.gpu_live_slots, slot)
		}
	}
	if !reset_instances && renderer.gpu_material_revision != registry.material_revision {
		for instance in render_list.instances {
			slot := instance.slot
			if slot < 0 ||
			   slot >= slot_count ||
			   !wgpu_material_instance_needs_sync(renderer, registry, instance) {
				continue
			}
			layout_changed, sync_err := wgpu_sync_dirty_instance_slot(
				renderer,
				cache,
				render_list,
				registry,
				slot,
				cpu_culling,
			)
			if sync_err != "" {
				return nil, 0, sync_err
			}
			batch_layout_changed = batch_layout_changed || layout_changed
		}
	}
	renderer.gpu_material_revision = registry.material_revision
	if !reset_instances {
		for slot in render_list.dirty_instance_slots {
			layout_changed, sync_err := wgpu_sync_dirty_instance_slot(
				renderer,
				cache,
				render_list,
				registry,
				slot,
				cpu_culling,
			)
			if sync_err != "" {
				return nil, 0, sync_err
			}
			batch_layout_changed = batch_layout_changed || layout_changed
		}
		for slot in render_list.dirty_transform_slots {
			if slot < 0 || slot >= slot_count {
				continue
			}
			instance := wgpu_render_instance_pointer_by_slot(render_list, slot)
			if instance == nil && !renderer.gpu_active_slots[slot] {
				continue
			}
			if instance != nil && !renderer.gpu_active_slots[slot] {
				layout_changed, sync_err := wgpu_sync_dirty_instance_slot(
					renderer,
					cache,
					render_list,
					registry,
					slot,
					cpu_culling,
				)
				if sync_err != "" {
					return nil, 0, sync_err
				}
				batch_layout_changed = batch_layout_changed || layout_changed
			}
			if instance == nil || !renderer.gpu_active_slots[slot] {
				return nil, 0, fmt.tprintf(
					"transform-dirty GPU slot %d could not be reconciled (render list: %v, GPU: %v, static dirty: %v)",
					slot,
					instance != nil,
					renderer.gpu_active_slots[slot],
					slice.contains(render_list.dirty_instance_slots[:], slot),
				)
			}
			previous := &renderer.gpu_instance_sources[slot]
			if !wgpu_instance_batch_key_matches(previous^, instance^) ||
			   previous.shadow_caster != instance.shadow_caster ||
			   previous.shadow_receiver != instance.shadow_receiver {
				return nil, 0, "transform-dirty GPU instance changed static render state"
			}
			previous_transform := &renderer.gpu_instance_source_transforms[slot]
			if previous_transform^ == instance.transform {
				continue
			}
			previous_transform^ = instance.transform
			wgpu_update_gpu_instance_transform(
				&renderer.gpu_instance_transform_records[slot],
				instance.transform,
			)
			if cpu_culling {
				geometry, geometry_ok := resources.get_geometry(registry, instance.geometry.handle)
				material, material_ok := resources.get_material(registry, instance.material.handle)
				if !geometry_ok || !material_ok {
					continue
				}
				renderer.gpu_instance_records[slot] = wgpu_build_gpu_instance(
					instance^,
					geometry,
					material,
					previous.batch_indices,
					previous.lod_count,
				)
				append(&renderer.gpu_dirty_indices, slot)
			} else {
				wgpu_append_transform_update(renderer, slot)
			}
		}
	}
	if batch_layout_changed {
		if layout_err := wgpu_refresh_gpu_batch_layout(renderer, cache, registry);
		   layout_err != "" {
			return nil, 0, layout_err
		}
	}
	renderer.gpu_meshlet_submission_active =
		!cpu_culling &&
		renderer.gpu_meshlet_supported &&
		renderer.gpu_meshlet_layout_valid &&
		renderer.gpu_meshlet_draw_count > 0 &&
		(renderer.gpu_meshlet_selected_batch_count > 0 || renderer.gpu_meshlet_force_enabled)
	renderer.gpu_compact_submission_active =
		renderer.gpu_meshlet_submission_active &&
		!renderer.gpu_meshlet_force_enabled &&
		renderer.gpu_compact_selected_batch_count > 0
	renderer.gpu_native_meshlet_submission_active =
		renderer.gpu_meshlet_submission_active &&
		(renderer.gpu_meshlet_selected_batch_count > renderer.gpu_compact_selected_batch_count ||
				renderer.gpu_meshlet_force_enabled)
	instance_data_changed :=
		len(renderer.gpu_dirty_indices) > 0 || len(renderer.gpu_transform_updates) > 1
	wgpu_upload_dirty_instance_ranges(renderer, renderer.gpu_dirty_indices[:])
	wgpu_upload_transform_updates(renderer)
	renderer.gpu_slot_count = slot_count
	hiz_forced := camera.debug_view == .HiZ || camera.debug_view == .Occlusion_Queries
	renderer.gpu_hiz_requested =
		hiz_forced || wgpu_hiz_build_requested(slot_count, instance_data_changed)
	renderer.gpu_hiz_occlusion_status = wgpu_hiz_occlusion_status(
		hiz_forced,
		renderer.gpu_hiz_valid,
		instance_data_changed,
		slot_count,
		renderer.gpu_previous_view_projection,
		view_projection,
	)
	hiz_reusable := wgpu_hiz_reuse_allowed(
		renderer.gpu_hiz_requested,
		renderer.gpu_hiz_valid,
		instance_data_changed,
		renderer.gpu_previous_view_projection,
		view_projection,
	)
	renderer.gpu_hiz_refinement_requested = wgpu_hiz_refinement_needed(
		renderer.gpu_hiz_requested,
		hiz_reusable,
	)
	renderer.gpu_current_view_projection = view_projection
	renderer.gpu_hiz_occlusion_enabled = hiz_reusable || renderer.gpu_hiz_refinement_requested
	cull_uniform := WGPU_GPU_Cull_Uniform {
		camera_planes = wgpu_extract_frustum_planes(view_projection),
		predictive_camera_planes = wgpu_extract_frustum_planes(predictive_view_projection),
		view_projection = view_projection,
		hiz_view_projection = view_projection if renderer.gpu_hiz_refinement_requested else renderer.gpu_previous_depth_view_projection,
		viewport = {viewport.x, viewport.y, viewport.width, viewport.height},
		camera_position = {camera_position.x, camera_position.y, camera_position.z, 1},
		predictive_camera_position = {
			prediction.position.x,
			prediction.position.y,
			prediction.position.z,
			1,
		},
		slot_count = u32(slot_count),
		batch_count = u32(cache.batch_count),
		hiz_mip_count = u32(renderer.gpu_hiz_mip_count),
		hiz_enabled = 1 if renderer.gpu_hiz_occlusion_enabled else 0,
		shadow_visible_stride = u32(renderer.gpu_visible_buffer_capacity),
		meshlet_enabled = 1 if renderer.gpu_meshlet_submission_active else 0,
		meshlet_shadow_visible_stride = u32(renderer.gpu_meshlet_visible_buffer_capacity),
		indirect_command_stride = u32(renderer.gpu_indirect_command_count),
		meshlet_debug_record_offset = 0,
		debug_view = u32(camera.debug_view),
		meshlet_force_enabled = 1 if renderer.gpu_meshlet_force_enabled else 0,
		virtual_error_pixels = wgpu_effective_virtual_error_pixels(renderer),
		projection_y = projection[5],
		virtual_feedback_epoch = u32(renderer.profile_frame_index),
		virtual_transition_frames = u32(WGPU_VIRTUAL_GROUP_TRANSITION_FRAMES),
		virtual_prefetch_enabled = 1 if prediction.enabled else 0,
		meshlet_count = u32(renderer.gpu_meshlet_draw_count),
		occlusion_depth_scale = math.abs(projection[14]),
		occlusion_world_bias = WGPU_HIZ_OCCLUSION_WORLD_BIAS,
		virtual_blend_low_scale = WGPU_VIRTUAL_GEOMETRY_BLEND_LOW_SCALE,
		virtual_blend_high_scale = WGPU_VIRTUAL_GEOMETRY_BLEND_HIGH_SCALE,
	}
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		cull_uniform.virtual_shadow_error_pixels[cascade_index] = wgpu_virtual_shadow_error_pixels(
			cull_uniform.virtual_error_pixels,
			cascade_index,
			f32(max(renderer.shadow_map_resolution, WGPU_SHADOW_MAP_MIN_SIZE)) /
			f32(WGPU_SHADOW_MAP_SIZE),
		)
	}
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		cull_uniform.shadow_planes[cascade_index] = wgpu_extract_frustum_planes(
			shadow_cascades.matrices[cascade_index],
		)
	}
	cull_uniform._padding[0] = u32(
		wgpu_initial_cull_phase(
			renderer.gpu_hiz_occlusion_enabled,
			renderer.gpu_hiz_refinement_requested,
		),
	)
	if wgpu_retain_cull_uniform(renderer, cull_uniform) {
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_cull_initial_uniform_buffer,
			0,
			&cull_uniform,
			uint(size_of(cull_uniform)),
		)
		refine_uniform := cull_uniform
		refine_uniform._padding[0] = u32(WGPU_GPU_Cull_Phase.Enabled)
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_cull_refine_uniform_buffer,
			0,
			&refine_uniform,
			uint(size_of(refine_uniform)),
		)
	}
	return cache.batches[:cache.batch_count], cache.batch_count, ""
}

wgpu_encode_gpu_instance_expansion :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
) -> string {
	if renderer == nil || len(renderer.gpu_transform_updates) <= 1 {
		return ""
	}
	timestamps, timestamps_enabled := wgpu_gpu_pass_timestamps(renderer, .Instance_Expansion)
	timestamps_ptr: ^wgpu.PassTimestampWrites
	if timestamps_enabled {
		timestamps_ptr = &timestamps
	}
	pass := wgpu.CommandEncoderBeginComputePass(
		encoder,
		&wgpu.ComputePassDescriptor {
			label = "Scrapbot GPU Transform Expansion Pass",
			timestampWrites = timestamps_ptr,
		},
	)
	if pass == nil {
		return "failed to begin GPU transform expansion pass"
	}
	defer wgpu.ComputePassEncoderRelease(pass)
	wgpu.ComputePassEncoderSetPipeline(pass, renderer.gpu_transform_pipeline)
	wgpu.ComputePassEncoderSetBindGroup(pass, 0, renderer.gpu_transform_bind_group)
	update_count := len(renderer.gpu_transform_updates) - 1
	workgroups := u32((update_count + 63) / 64)
	wgpu.ComputePassEncoderDispatchWorkgroups(pass, workgroups, 1, 1)
	wgpu.ComputePassEncoderEnd(pass)
	renderer.gpu_instance_expand_dispatch_count += 1
	renderer.gpu_instance_expanded_slot_count += u64(update_count)
	return ""
}

wgpu_encode_gpu_culling :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	batch_count: int,
	cull_phase: WGPU_GPU_Cull_Phase = .Enabled,
	timestamp_phase: WGPU_GPU_Timestamp_Phase = .Cull,
) -> string {
	if batch_count <= 0 || renderer.gpu_slot_count <= 0 {
		renderer.gpu_visibility_counters = {}
		return ""
	}
	uniform_buffer := renderer.gpu_cull_initial_uniform_buffer
	if cull_phase == .Enabled {
		uniform_buffer = renderer.gpu_cull_refine_uniform_buffer
	}
	wgpu.CommandEncoderCopyBufferToBuffer(
		encoder,
		uniform_buffer,
		0,
		renderer.gpu_cull_uniform_buffer,
		0,
		u64(size_of(WGPU_GPU_Cull_Uniform)),
	)
	renderer.gpu_cull_pass_count += 1
	debug_view := shared.Render_Debug_View(renderer.gpu_render_uniform.debug.x)
	capture_debug_evidence :=
		(renderer.live_debug_visibility_capture ||
			debug_view == .Meshlet_Visibility ||
			debug_view == .Occlusion_Queries) &&
		renderer.gpu_meshlet_submission_active &&
		renderer.gpu_meshlet_debug_cull_bind_group != nil
	if capture_debug_evidence {
		debug_draw := WGPU_Draw_Indirect {
			vertex_count = WGPU_MESHLET_DEBUG_VERTEX_COUNT,
		}
		wgpu.QueueWriteBuffer(
			renderer.queue,
			renderer.gpu_meshlet_debug_indirect_buffer,
			0,
			&debug_draw,
			uint(size_of(debug_draw)),
		)
	}
	wgpu_visibility_reset(renderer, encoder, batch_count)
	wgpu.CommandEncoderClearBuffer(
		encoder,
		renderer.gpu_compact_candidate_count_buffer,
		0,
		u64(batch_count) * u64(size_of(WGPU_Draw_Indexed_Indirect)),
	)
	copy_size :=
		u64(renderer.gpu_indirect_command_count) * u64(size_of(WGPU_Draw_Indexed_Indirect))
	wgpu.CommandEncoderCopyBufferToBuffer(
		encoder,
		renderer.gpu_indirect_template_buffer,
		0,
		renderer.gpu_indirect_buffer,
		0,
		copy_size,
	)
	wgpu.CommandEncoderCopyBufferToBuffer(
		encoder,
		renderer.gpu_shadow_indirect_template_buffer,
		0,
		renderer.gpu_shadow_indirect_buffer,
		0,
		copy_size,
	)
	for cascade_index in 1 ..< WGPU_SHADOW_CASCADE_COUNT {
		wgpu.CommandEncoderCopyBufferToBuffer(
			encoder,
			renderer.gpu_shadow_indirect_template_buffer,
			0,
			renderer.gpu_shadow_indirect_buffer,
			u64(cascade_index) * copy_size,
			copy_size,
		)
	}
	if renderer.gpu_native_meshlet_submission_active {
		meshlet_copy_size :=
			u64(renderer.gpu_meshlet_draw_count) * u64(size_of(WGPU_Draw_Indexed_Indirect))
		wgpu.CommandEncoderCopyBufferToBuffer(
			encoder,
			renderer.gpu_meshlet_indirect_template_buffer,
			0,
			renderer.gpu_meshlet_indirect_buffer,
			0,
			meshlet_copy_size,
		)
		for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
			wgpu.CommandEncoderCopyBufferToBuffer(
				encoder,
				renderer.gpu_meshlet_indirect_template_buffer,
				0,
				renderer.gpu_meshlet_shadow_indirect_buffer,
				u64(cascade_index) *
				u64(renderer.gpu_meshlet_draw_capacity) *
				u64(size_of(WGPU_Draw_Indexed_Indirect)),
				meshlet_copy_size,
			)
		}
	}
	cull_timestamps, cull_timestamps_enabled := wgpu_gpu_pass_timestamps(renderer, timestamp_phase)
	cull_timestamps_ptr: ^wgpu.PassTimestampWrites
	if cull_timestamps_enabled {
		cull_timestamps_ptr = &cull_timestamps
	}
	pass := wgpu.CommandEncoderBeginComputePass(
		encoder,
		&wgpu.ComputePassDescriptor {
			label = "Scrapbot GPU Visibility Pass",
			timestampWrites = cull_timestamps_ptr,
		},
	)
	if pass == nil {
		return "failed to begin GPU visibility pass"
	}
	defer wgpu.ComputePassEncoderRelease(pass)
	workgroups := u32((renderer.gpu_slot_count + 63) / 64)
	if wgpu_active_classic_batch_count(renderer) > 0 || renderer.gpu_compact_submission_active {
		wgpu.ComputePassEncoderSetPipeline(pass, renderer.gpu_cull_pipeline)
		wgpu.ComputePassEncoderSetBindGroup(pass, 0, renderer.gpu_cull_bind_group)
		wgpu.ComputePassEncoderDispatchWorkgroups(pass, workgroups, WGPU_SHADOW_CASCADE_COUNT, 1)
	}
	if renderer.gpu_native_meshlet_submission_active {
		wgpu.ComputePassEncoderSetPipeline(pass, renderer.gpu_meshlet_cull_pipeline)
		wgpu.ComputePassEncoderSetBindGroup(pass, 0, renderer.gpu_meshlet_cull_bind_group)
		wgpu.ComputePassEncoderDispatchWorkgroups(pass, workgroups, WGPU_SHADOW_CASCADE_COUNT, 1)
	}
	if renderer.gpu_compact_submission_active {
		wgpu.ComputePassEncoderSetPipeline(pass, renderer.gpu_compact_cull_pipeline)
		wgpu.ComputePassEncoderSetBindGroup(pass, 0, renderer.gpu_compact_cull_bind_group)
		wgpu.ComputePassEncoderDispatchWorkgroups(pass, workgroups, 1, 1)
		if renderer.gpu_meshlet_draw_count > 0 {
			cluster_workgroups := u32((renderer.gpu_meshlet_draw_count + 63) / 64)
			wgpu.ComputePassEncoderSetPipeline(pass, renderer.gpu_compact_cluster_cull_pipeline)
			wgpu.ComputePassEncoderSetBindGroup(
				pass,
				0,
				renderer.gpu_compact_camera_cull_bind_group,
			)
			wgpu.ComputePassEncoderDispatchWorkgroups(pass, cluster_workgroups, 1, 1)
			if wgpu_compact_shadow_pages_active(renderer) {
				wgpu.ComputePassEncoderSetPipeline(
					pass,
					renderer.gpu_compact_shadow_cluster_cull_pipeline,
				)
				wgpu.ComputePassEncoderSetBindGroup(
					pass,
					0,
					renderer.gpu_compact_shadow_cull_bind_group,
				)
				wgpu.ComputePassEncoderDispatchWorkgroups(
					pass,
					cluster_workgroups,
					WGPU_SHADOW_CASCADE_COUNT,
					1,
				)
			}
		}
	}
	if capture_debug_evidence {
		wgpu.ComputePassEncoderSetPipeline(pass, renderer.gpu_meshlet_debug_cull_pipeline)
		wgpu.ComputePassEncoderSetBindGroup(pass, 0, renderer.gpu_meshlet_debug_cull_bind_group)
		wgpu.ComputePassEncoderDispatchWorkgroups(pass, workgroups, 1, 1)
	}
	wgpu.ComputePassEncoderEnd(pass)
	if capture_debug_evidence {
		wgpu.CommandEncoderCopyBufferToBuffer(
			encoder,
			renderer.gpu_visibility_counter_buffer,
			u64(offset_of(WGPU_GPU_Visibility_Summary, meshlet_debug_records)),
			renderer.gpu_meshlet_debug_indirect_buffer,
			u64(offset_of(WGPU_Draw_Indirect, instance_count)),
			u64(size_of(u32)),
		)
		if debug_view == .Occlusion_Queries {
			renderer.gpu_occlusion_debug_evidence_valid = true
		}
	}
	return ""
}

wgpu_encode_meshlet_debug_overlay :: proc(
	renderer: ^WGPU_Renderer,
	encoder: wgpu.CommandEncoder,
	viewport: ui.Rect,
) -> string {
	if renderer == nil || !renderer.gpu_meshlet_submission_active {
		return ""
	}
	debug_view := shared.Render_Debug_View(renderer.gpu_render_uniform.debug.x)
	if debug_view != .Meshlet_Visibility && debug_view != .Occlusion_Queries {
		return ""
	}
	if debug_view == .Occlusion_Queries && !renderer.gpu_occlusion_debug_evidence_valid {
		return ""
	}
	attachment := wgpu.RenderPassColorAttachment {
		view = renderer.hdr_view,
		depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		loadOp = .Load,
		storeOp = .Store,
	}
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			label = "Scrapbot Meshlet Debug Overlay Pass",
			colorAttachmentCount = 1,
			colorAttachments = &attachment,
		},
	)
	if pass == nil {
		return "failed to begin meshlet debug overlay pass"
	}
	defer wgpu.RenderPassEncoderRelease(pass)
	wgpu.RenderPassEncoderSetViewport(
		pass,
		viewport.x,
		viewport.y,
		viewport.width,
		viewport.height,
		0,
		1,
	)
	wgpu.RenderPassEncoderSetScissorRect(
		pass,
		u32(viewport.x),
		u32(viewport.y),
		u32(viewport.width),
		u32(viewport.height),
	)
	wgpu.RenderPassEncoderSetPipeline(pass, renderer.gpu_meshlet_debug_pipeline)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, renderer.gpu_meshlet_debug_bind_group)
	wgpu.RenderPassEncoderDrawIndirect(pass, renderer.gpu_meshlet_debug_indirect_buffer, 0)
	wgpu.RenderPassEncoderEnd(pass)
	return ""
}

wgpu_prepare_cpu_culling :: proc(
	renderer: ^WGPU_Renderer,
	render_list: ^Render_List,
	width, height: u32,
) {
	if renderer == nil || renderer.gpu_slot_count <= 0 {
		return
	}
	view_projection := wgpu_build_view_projection(
		render_list.camera,
		render_list.has_camera,
		width,
		height,
	)
	shadow_cascades: WGPU_Shadow_Cascades
	for &cascade_matrix in shadow_cascades.matrices {
		cascade_matrix = mat4_identity()
	}
	if render_list.directional_light_count > 0 {
		shadow_cascades = wgpu_build_directional_shadow_cascades(
			render_list.camera,
			render_list.has_camera,
			width,
			height,
			render_list.directional_lights[0].light.direction,
			max(renderer.shadow_map_resolution, WGPU_SHADOW_MAP_MIN_SIZE),
		)
	}
	camera_planes := wgpu_extract_frustum_planes(view_projection)
	if len(renderer.gpu_cpu_visible) < renderer.gpu_visible_capacity {
		resize(&renderer.gpu_cpu_visible, renderer.gpu_visible_capacity)
	}
	shadow_visible_capacity := renderer.gpu_visible_capacity * WGPU_SHADOW_CASCADE_COUNT
	if len(renderer.gpu_cpu_shadow_visible) < shadow_visible_capacity {
		resize(&renderer.gpu_cpu_shadow_visible, shadow_visible_capacity)
	}
	visible := renderer.gpu_cpu_visible[:renderer.gpu_visible_capacity]
	shadow_visible := renderer.gpu_cpu_shadow_visible[:shadow_visible_capacity]
	camera_counts := wgpu_cpu_cull_counts(
		renderer.gpu_instance_records[:renderer.gpu_slot_count],
		camera_planes,
		renderer.draw_batch_cache.batch_count,
		false,
		view_projection,
	)
	defer delete(camera_counts)
	shadow_counts: [WGPU_SHADOW_CASCADE_COUNT][dynamic]u32
	shadow_planes: [WGPU_SHADOW_CASCADE_COUNT][6][4]f32
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		shadow_planes[cascade_index] = wgpu_extract_frustum_planes(
			shadow_cascades.matrices[cascade_index],
		)
		shadow_counts[cascade_index] = wgpu_cpu_cull_counts(
			renderer.gpu_instance_records[:renderer.gpu_slot_count],
			shadow_planes[cascade_index],
			renderer.draw_batch_cache.batch_count,
			true,
			view_projection,
		)
	}
	defer {
		for counts in shadow_counts {
			delete(counts)
		}
	}
	renderer.gpu_visibility_counters = {}
	for count in camera_counts {
		renderer.gpu_visibility_counters.visible_instances += count
		if count > 0 {
			renderer.gpu_visibility_counters.visible_batches += 1
		}
	}
	for counts in shadow_counts {
		for count in counts {
			renderer.gpu_visibility_counters.shadow_visible_instances += count
		}
	}
	camera_cursors := make([]u32, renderer.draw_batch_cache.batch_count)
	defer delete(camera_cursors)
	shadow_cursors: [WGPU_SHADOW_CASCADE_COUNT][]u32
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		shadow_cursors[cascade_index] = make([]u32, renderer.draw_batch_cache.batch_count)
	}
	defer {
		for cursors in shadow_cursors {
			delete(cursors)
		}
	}
	for instance, slot in renderer.gpu_instance_records[:renderer.gpu_slot_count] {
		lod_level := wgpu_cpu_instance_lod_level(instance, view_projection)
		batch_index := instance.batch_indices[lod_level]
		if instance.active == 0 || int(batch_index) >= renderer.draw_batch_cache.batch_count {
			continue
		}
		batch := renderer.draw_batch_cache.batches[batch_index]
		if wgpu_sphere_visible(instance.bounds, camera_planes) {
			renderer.gpu_visibility_counters.frustum_candidates += 1
			visible[batch.visible_offset + camera_cursors[batch_index]] = u32(slot)
			camera_cursors[batch_index] += 1
			renderer.gpu_visibility_counters.lod_visible_instances[lod_level] += 1
		} else {
			renderer.gpu_visibility_counters.frustum_culled_instances += 1
		}
		for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
			if instance.render_flags[0] > 0.5 &&
			   wgpu_sphere_visible(instance.bounds, shadow_planes[cascade_index]) {
				shadow_visible_index :=
					cascade_index * renderer.gpu_visible_capacity +
					int(batch.visible_offset + shadow_cursors[cascade_index][batch_index])
				shadow_visible[shadow_visible_index] = u32(slot)
				shadow_cursors[cascade_index][batch_index] += 1
			}
		}
	}
	indirect := make([]WGPU_Draw_Indexed_Indirect, len(renderer.gpu_indirect_templates))
	defer delete(indirect)
	for batch, batch_index in renderer.draw_batch_cache.batches[:renderer.draw_batch_cache.batch_count] {
		geometry_index := wgpu_geometry_cache_slot_for_submission(
			renderer.geometry_cache[:],
			batch.geometry,
			batch.virtual_geometry,
		)
		if geometry_index < 0 {
			continue
		}
		indirect[batch_index] = wgpu_geometry_indirect_template(
			&renderer.geometry_cache[geometry_index],
			batch.visible_offset,
			true,
		)
	}
	shadow_indirect := make(
		[]WGPU_Draw_Indexed_Indirect,
		len(renderer.gpu_indirect_templates) * WGPU_SHADOW_CASCADE_COUNT,
	)
	defer delete(shadow_indirect)
	for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
		start := cascade_index * len(renderer.gpu_indirect_templates)
		copy(shadow_indirect[start:start + len(renderer.gpu_indirect_templates)], indirect)
	}
	for batch_index in 0 ..< renderer.draw_batch_cache.batch_count {
		indirect[batch_index].instance_count = camera_counts[batch_index]
		for cascade_index in 0 ..< WGPU_SHADOW_CASCADE_COUNT {
			shadow_indirect_index :=
				cascade_index * renderer.gpu_indirect_command_count + batch_index
			shadow_indirect[shadow_indirect_index].instance_count =
				shadow_counts[cascade_index][batch_index]
		}
	}
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_visible_buffer,
		0,
		raw_data(visible),
		uint(len(visible) * size_of(u32)),
	)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_shadow_visible_buffer,
		0,
		raw_data(shadow_visible),
		uint(len(shadow_visible) * size_of(u32)),
	)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_indirect_buffer,
		0,
		raw_data(indirect),
		uint(len(indirect) * size_of(WGPU_Draw_Indexed_Indirect)),
	)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.gpu_shadow_indirect_buffer,
		0,
		raw_data(shadow_indirect),
		uint(len(shadow_indirect) * size_of(WGPU_Draw_Indexed_Indirect)),
	)
}
