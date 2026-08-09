package geometry

import c "core:c"
import "core:math"
import "core:mem"

CLUSTER_MAX_VERTICES :: 64
CLUSTER_MAX_TRIANGLES :: 124
CLUSTER_PAGE_TARGET_BYTES :: 64 * 1024
CLUSTER_PAGE_TARGET_INDICES :: CLUSTER_PAGE_TARGET_BYTES / size_of(u32)
CLUSTER_TERMINAL_ERROR_THRESHOLD :: f32(1.0e30)
CLUSTER_BOOTSTRAP_TAIL_FRACTION_NUMERATOR :: u64(1)
CLUSTER_BOOTSTRAP_TAIL_FRACTION_DENOMINATOR :: u64(32)
CLUSTER_BOOTSTRAP_TAIL_MIN_EXTRA_BYTES :: u64(256 * 1024)
CLUSTER_BOOTSTRAP_TAIL_MAX_EXTRA_BYTES :: u64(2 * 1024 * 1024)

Page_Payload_Record :: struct {
	offset: u64,
	size: u64,
	vertex_count: u32,
	index_count: u32,
}

Page_Payloads :: struct {
	records: []Page_Payload_Record,
	bytes: [dynamic]u8,
}

Cluster_Group :: struct {
	bounds: [4]f32,
	error: f32,
	depth: u32,
	cluster_offset: u32,
	cluster_count: u32,
	page_offset: u32,
	page_count: u32,
}

Cluster :: struct {
	vertex_offset: u32,
	triangle_offset: u32,
	vertex_count: u32,
	triangle_count: u32,
	bounds: [4]f32,
	cone_axis_cutoff: [4]f32,
	group: i32,
	refined_group: i32,
	page: u32,
	page_index_offset: u32,
}

Cluster_Page :: struct {
	cluster_offset: u32,
	cluster_count: u32,
	index_count: u32,
	pinned: bool,
	bootstrap: bool,
}

Hierarchy :: struct {
	groups: []Cluster_Group,
	clusters: []Cluster,
	pages: []Cluster_Page,
	vertices: []u32,
	triangles: []u8,
	max_depth: u32,
}

cluster_group_is_terminal :: proc "contextless" (group: Cluster_Group) -> bool {
	// clusterlod writes FLT_MAX when a region cannot be simplified any
	// further. Terminal groups are roots of their local refinement DAG even
	// when another region reaches a greater global depth.
	return group.error > CLUSTER_TERMINAL_ERROR_THRESHOLD
}

@(private)
Native_Cluster_Group :: struct {
	bounds: [4]f32,
	error: f32,
	depth: u32,
	cluster_offset: u32,
	cluster_count: u32,
}
#assert(size_of(Native_Cluster_Group) == 32)

@(private)
Native_Cluster :: struct {
	vertex_offset: u32,
	triangle_offset: u32,
	vertex_count: u32,
	triangle_count: u32,
	bounds: [4]f32,
	cone_axis_cutoff: [4]f32,
	group: i32,
	refined_group: i32,
}
#assert(size_of(Native_Cluster) == 56)

@(private)
Native_Result :: struct {
	groups: [^]Native_Cluster_Group,
	clusters: [^]Native_Cluster,
	vertices: [^]u32,
	triangles: [^]u8,
	group_count: c.size_t,
	cluster_count: c.size_t,
	vertex_count: c.size_t,
	triangle_byte_count: c.size_t,
	max_depth: u32,
}

foreign import meshoptimizer "system:c"

foreign meshoptimizer {
	@(link_name = "scrapbot_clod_build")
	clod_build :: proc(indices: [^]u32, index_count: c.size_t, vertices: [^]f32, vertex_count, vertex_stride: c.size_t) -> Native_Result ---

	@(link_name = "scrapbot_clod_free")
	clod_free :: proc(result: Native_Result) ---
}

@(private)
clone_values :: proc(source: []$T, allocator: mem.Allocator) -> []T {
	result := make([]T, len(source), allocator)
	copy(result, source)
	return result
}

build_hierarchy :: proc(
	indices: []u32,
	vertices: rawptr,
	vertex_count, vertex_stride: int,
	allocator := context.allocator,
) -> (
	Hierarchy,
	string,
) {
	if len(indices) == 0 || vertices == nil || vertex_count <= 0 || vertex_stride < 12 {
		return {}, "cluster hierarchy source geometry is empty"
	}
	result := clod_build(
		raw_data(indices),
		c.size_t(len(indices)),
		cast([^]f32)vertices,
		c.size_t(vertex_count),
		c.size_t(vertex_stride),
	)
	defer clod_free(result)
	if result.group_count == 0 ||
	   result.cluster_count == 0 ||
	   result.vertex_count == 0 ||
	   result.triangle_byte_count == 0 {
		return {}, "failed to build geometry cluster hierarchy"
	}
	hierarchy := Hierarchy {
		groups = make([]Cluster_Group, int(result.group_count), allocator),
		clusters = make([]Cluster, int(result.cluster_count), allocator),
		vertices = clone_values(result.vertices[:int(result.vertex_count)], allocator),
		triangles = clone_values(result.triangles[:int(result.triangle_byte_count)], allocator),
		max_depth = result.max_depth,
	}
	for source, index in result.groups[:int(result.group_count)] {
		hierarchy.groups[index] = {
			bounds = source.bounds,
			error = source.error,
			depth = source.depth,
			cluster_offset = source.cluster_offset,
			cluster_count = source.cluster_count,
		}
	}
	for source, index in result.clusters[:int(result.cluster_count)] {
		hierarchy.clusters[index] = {
			vertex_offset = source.vertex_offset,
			triangle_offset = source.triangle_offset,
			vertex_count = source.vertex_count,
			triangle_count = source.triangle_count,
			bounds = source.bounds,
			cone_axis_cutoff = source.cone_axis_cutoff,
			group = source.group,
			refined_group = source.refined_group,
		}
	}
	build_cluster_pages(&hierarchy, allocator)
	mark_cluster_bootstrap_tail(&hierarchy, vertex_stride, allocator)
	if validation_err := validate_hierarchy(&hierarchy, vertex_count); validation_err != "" {
		destroy_hierarchy(&hierarchy, allocator)
		return {}, validation_err
	}
	return hierarchy, ""
}

cluster_page_payload_size :: proc "contextless" (
	hierarchy: ^Hierarchy,
	page_index: int,
	vertex_stride: int,
	marks: []u32,
	token: u32,
) -> u64 {
	if hierarchy == nil ||
	   page_index < 0 ||
	   page_index >= len(hierarchy.pages) ||
	   vertex_stride <= 0 {
		return 0
	}
	page := hierarchy.pages[page_index]
	unique_vertex_count: u64
	cluster_end := int(page.cluster_offset + page.cluster_count)
	for cluster in hierarchy.clusters[int(page.cluster_offset):cluster_end] {
		vertex_end := int(cluster.vertex_offset + cluster.vertex_count)
		for canonical_index in hierarchy.vertices[int(cluster.vertex_offset):vertex_end] {
			if int(canonical_index) >= len(marks) || marks[canonical_index] == token {
				continue
			}
			marks[canonical_index] = token
			unique_vertex_count += 1
		}
	}
	return unique_vertex_count * u64(vertex_stride) + u64(page.index_count) * u64(size_of(u32))
}

mark_cluster_bootstrap_tail :: proc(
	hierarchy: ^Hierarchy,
	vertex_stride: int,
	allocator := context.allocator,
) {
	if hierarchy == nil ||
	   len(hierarchy.groups) == 0 ||
	   len(hierarchy.pages) == 0 ||
	   len(hierarchy.vertices) == 0 ||
	   vertex_stride <= 0 {
		return
	}
	canonical_vertex_count := 0
	for canonical_index in hierarchy.vertices {
		canonical_vertex_count = max(canonical_vertex_count, int(canonical_index) + 1)
	}
	marks := make([]u32, canonical_vertex_count, allocator)
	defer delete(marks, allocator)
	page_sizes := make([]u64, len(hierarchy.pages), allocator)
	defer delete(page_sizes, allocator)
	total_bytes: u64
	bootstrap_bytes: u64
	for &page, page_index in hierarchy.pages {
		group := hierarchy.groups[hierarchy.clusters[page.cluster_offset].group]
		page.pinned = cluster_group_is_terminal(group)
		page.bootstrap = page.pinned
		page_sizes[page_index] = cluster_page_payload_size(
			hierarchy,
			page_index,
			vertex_stride,
			marks,
			u32(page_index + 1),
		)
		total_bytes += page_sizes[page_index]
		if page.pinned {
			bootstrap_bytes += page_sizes[page_index]
		}
	}
	extra_budget := clamp(
		total_bytes *
		CLUSTER_BOOTSTRAP_TAIL_FRACTION_NUMERATOR /
		CLUSTER_BOOTSTRAP_TAIL_FRACTION_DENOMINATOR,
		CLUSTER_BOOTSTRAP_TAIL_MIN_EXTRA_BYTES,
		CLUSTER_BOOTSTRAP_TAIL_MAX_EXTRA_BYTES,
	)
	target_bytes := min(total_bytes, bootstrap_bytes + extra_budget)
	group_pinned := make([]bool, len(hierarchy.groups), allocator)
	defer delete(group_pinned, allocator)
	group_reachable := make([]bool, len(hierarchy.groups), allocator)
	defer delete(group_reachable, allocator)
	for group, group_index in hierarchy.groups {
		group_pinned[group_index] = cluster_group_is_terminal(group)
	}
	for parent, parent_index in hierarchy.groups {
		if !group_pinned[parent_index] {
			continue
		}
		cluster_end := int(parent.cluster_offset + parent.cluster_count)
		for cluster in hierarchy.clusters[int(parent.cluster_offset):cluster_end] {
			if cluster.refined_group >= 0 {
				group_reachable[cluster.refined_group] = true
			}
		}
	}
	for bootstrap_bytes < target_bytes {
		best_group := -1
		best_error: f32 = -1
		best_bytes: u64
		for group, group_index in hierarchy.groups {
			if group_pinned[group_index] {
				continue
			}
			if !group_reachable[group_index] {
				continue
			}
			group_bytes: u64
			for page_index in group.page_offset ..< group.page_offset + group.page_count {
				group_bytes += page_sizes[page_index]
			}
			if group_bytes == 0 || bootstrap_bytes + group_bytes > target_bytes {
				continue
			}
			if best_group < 0 || group.error > best_error {
				best_group = group_index
				best_error = group.error
				best_bytes = group_bytes
			}
		}
		if best_group < 0 {
			break
		}
		group_pinned[best_group] = true
		group := hierarchy.groups[best_group]
		cluster_end := int(group.cluster_offset + group.cluster_count)
		for cluster in hierarchy.clusters[int(group.cluster_offset):cluster_end] {
			if cluster.refined_group >= 0 {
				group_reachable[cluster.refined_group] = true
			}
		}
		for page_index in group.page_offset ..< group.page_offset + group.page_count {
			hierarchy.pages[page_index].bootstrap = true
		}
		bootstrap_bytes += best_bytes
	}
}

build_cluster_pages :: proc(hierarchy: ^Hierarchy, allocator := context.allocator) {
	if hierarchy == nil {
		return
	}
	delete(hierarchy.pages, allocator)
	page_count := cluster_page_count(hierarchy)
	hierarchy.pages = make([]Cluster_Page, page_count, allocator)
	page_index := 0
	for &group in hierarchy.groups {
		group.page_offset = u32(page_index)
		group.page_count = 0
		cluster_cursor := int(group.cluster_offset)
		cluster_end := cluster_cursor + int(group.cluster_count)
		for cluster_cursor < cluster_end {
			page := Cluster_Page {
				cluster_offset = u32(cluster_cursor),
				pinned = cluster_group_is_terminal(group),
				bootstrap = cluster_group_is_terminal(group),
			}
			for cluster_cursor < cluster_end {
				cluster := &hierarchy.clusters[cluster_cursor]
				index_count := cluster.triangle_count * 3
				if page.cluster_count > 0 &&
				   page.index_count + index_count > u32(CLUSTER_PAGE_TARGET_INDICES) {
					break
				}
				cluster.page = u32(page_index)
				cluster.page_index_offset = page.index_count
				page.cluster_count += 1
				page.index_count += index_count
				cluster_cursor += 1
			}
			hierarchy.pages[page_index] = page
			page_index += 1
			group.page_count += 1
		}
	}
}

@(private)
cluster_page_count :: proc(hierarchy: ^Hierarchy) -> int {
	if hierarchy == nil {
		return 0
	}
	result := 0
	for group in hierarchy.groups {
		cluster_cursor := int(group.cluster_offset)
		cluster_end := cluster_cursor + int(group.cluster_count)
		for cluster_cursor < cluster_end {
			page_indices: u32
			for cluster_cursor < cluster_end {
				index_count := hierarchy.clusters[cluster_cursor].triangle_count * 3
				if page_indices > 0 &&
				   page_indices + index_count > u32(CLUSTER_PAGE_TARGET_INDICES) {
					break
				}
				page_indices += index_count
				cluster_cursor += 1
			}
			result += 1
		}
	}
	return result
}

validate_hierarchy :: proc(hierarchy: ^Hierarchy, canonical_vertex_count: int) -> string {
	if hierarchy == nil ||
	   len(hierarchy.groups) == 0 ||
	   len(hierarchy.clusters) == 0 ||
	   len(hierarchy.pages) == 0 ||
	   len(hierarchy.vertices) == 0 ||
	   len(hierarchy.triangles) == 0 ||
	   canonical_vertex_count <= 0 {
		return "cluster hierarchy is empty"
	}
	for group, group_index in hierarchy.groups {
		if group.cluster_count == 0 || group.page_count == 0 || group.depth > hierarchy.max_depth {
			return "cluster hierarchy group is invalid"
		}
		if math.is_nan(group.error) || group.error < 0 {
			return "cluster hierarchy group error is invalid"
		}
		cluster_end := u64(group.cluster_offset) + u64(group.cluster_count)
		page_end := u64(group.page_offset) + u64(group.page_count)
		if cluster_end > u64(len(hierarchy.clusters)) || page_end > u64(len(hierarchy.pages)) {
			return "cluster hierarchy group range is invalid"
		}
		for cluster in hierarchy.clusters[int(group.cluster_offset):int(cluster_end)] {
			if cluster.group != i32(group_index) || cluster.refined_group >= i32(group_index) {
				return "cluster hierarchy refinement link is invalid"
			}
		}
	}
	for page, page_index in hierarchy.pages {
		if page.cluster_count == 0 || page.index_count == 0 {
			return "cluster hierarchy page is empty"
		}
		cluster_end := u64(page.cluster_offset) + u64(page.cluster_count)
		if cluster_end > u64(len(hierarchy.clusters)) {
			return "cluster hierarchy page range is invalid"
		}
		index_count: u32
		for cluster in hierarchy.clusters[int(page.cluster_offset):int(cluster_end)] {
			if cluster.page != u32(page_index) || cluster.page_index_offset != index_count {
				return "cluster hierarchy page mapping is invalid"
			}
			if cluster.vertex_count == 0 ||
			   cluster.vertex_count > CLUSTER_MAX_VERTICES ||
			   cluster.triangle_count == 0 ||
			   cluster.triangle_count > CLUSTER_MAX_TRIANGLES {
				return "cluster hierarchy cluster size is invalid"
			}
			vertex_end := u64(cluster.vertex_offset) + u64(cluster.vertex_count)
			triangle_end := u64(cluster.triangle_offset) + u64(cluster.triangle_count) * 3
			if vertex_end > u64(len(hierarchy.vertices)) ||
			   triangle_end > u64(len(hierarchy.triangles)) {
				return "cluster hierarchy local stream is invalid"
			}
			for vertex in hierarchy.vertices[int(cluster.vertex_offset):int(vertex_end)] {
				if int(vertex) >= canonical_vertex_count {
					return "cluster hierarchy vertex is invalid"
				}
			}
			index_count += cluster.triangle_count * 3
		}
		if index_count != page.index_count {
			return "cluster hierarchy page index count is invalid"
		}
	}
	pinned_groups := make([]bool, len(hierarchy.groups), context.temp_allocator)
	bootstrap_groups := make([]bool, len(hierarchy.groups), context.temp_allocator)
	for group, group_index in hierarchy.groups {
		group_pinned := true
		group_bootstrap := true
		for page in hierarchy.pages[int(group.page_offset):int(group.page_offset + group.page_count)] {
			if page.pinned != hierarchy.pages[group.page_offset].pinned {
				return "cluster hierarchy pinned page is invalid"
			}
			if page.bootstrap != hierarchy.pages[group.page_offset].bootstrap {
				return "cluster hierarchy bootstrap page is invalid"
			}
			group_pinned = group_pinned && page.pinned
			group_bootstrap = group_bootstrap && page.bootstrap
		}
		if cluster_group_is_terminal(group) && !group_pinned {
			return "cluster hierarchy terminal page is not pinned"
		}
		if group_pinned && !group_bootstrap {
			return "cluster hierarchy pinned page is not bootstrapped"
		}
		pinned_groups[group_index] = group_pinned
		bootstrap_groups[group_index] = group_bootstrap
	}
	bootstrap_refinements := make([]bool, len(hierarchy.groups), context.temp_allocator)
	for parent, parent_index in hierarchy.groups {
		if !bootstrap_groups[parent_index] {
			continue
		}
		cluster_end := int(parent.cluster_offset + parent.cluster_count)
		for cluster in hierarchy.clusters[int(parent.cluster_offset):cluster_end] {
			if cluster.refined_group >= 0 {
				bootstrap_refinements[cluster.refined_group] = true
			}
		}
	}
	for group, group_index in hierarchy.groups {
		if bootstrap_groups[group_index] &&
		   !cluster_group_is_terminal(group) &&
		   !bootstrap_refinements[group_index] {
			return "cluster hierarchy bootstrap refinement is unreachable"
		}
	}
	return ""
}

clone_hierarchy :: proc(source: Hierarchy, allocator := context.allocator) -> Hierarchy {
	return Hierarchy {
		groups = clone_values(source.groups, allocator),
		clusters = clone_values(source.clusters, allocator),
		pages = clone_values(source.pages, allocator),
		vertices = clone_values(source.vertices, allocator),
		triangles = clone_values(source.triangles, allocator),
		max_depth = source.max_depth,
	}
}

destroy_hierarchy :: proc(hierarchy: ^Hierarchy, allocator := context.allocator) {
	if hierarchy == nil {
		return
	}
	delete(hierarchy.groups, allocator)
	delete(hierarchy.clusters, allocator)
	delete(hierarchy.pages, allocator)
	delete(hierarchy.vertices, allocator)
	delete(hierarchy.triangles, allocator)
	hierarchy^ = {}
}

build_page_payloads :: proc(
	hierarchy: ^Hierarchy,
	vertices: rawptr,
	vertex_count, vertex_stride: int,
	allocator := context.allocator,
) -> (
	Page_Payloads,
	string,
) {
	if hierarchy == nil || vertices == nil || vertex_count <= 0 || vertex_stride <= 0 {
		return {}, "geometry page payload source is empty"
	}
	if validation_err := validate_hierarchy(hierarchy, vertex_count); validation_err != "" {
		return {}, validation_err
	}
	result := Page_Payloads {
		records = make([]Page_Payload_Record, len(hierarchy.pages), allocator),
		bytes = make([dynamic]u8, 0, allocator),
	}
	marks := make([]u32, vertex_count, context.temp_allocator)
	remap := make([]u32, vertex_count, context.temp_allocator)
	source := cast([^]u8)vertices
	for page, page_index in hierarchy.pages {
		token := u32(page_index + 1)
		page_start := len(result.bytes)
		page_vertex_count: u32
		cluster_end := int(page.cluster_offset + page.cluster_count)
		for cluster in hierarchy.clusters[int(page.cluster_offset):cluster_end] {
			vertex_end := int(cluster.vertex_offset + cluster.vertex_count)
			for canonical_index in hierarchy.vertices[int(cluster.vertex_offset):vertex_end] {
				if marks[canonical_index] == token {
					continue
				}
				marks[canonical_index] = token
				remap[canonical_index] = page_vertex_count
				byte_offset := int(canonical_index) * vertex_stride
				append(&result.bytes, ..source[byte_offset:byte_offset + vertex_stride])
				page_vertex_count += 1
			}
		}
		for cluster in hierarchy.clusters[int(page.cluster_offset):cluster_end] {
			triangle_end := int(cluster.triangle_offset + cluster.triangle_count * 3)
			local_vertices := hierarchy.vertices[int(cluster.vertex_offset):int(
				cluster.vertex_offset + cluster.vertex_count,
			)]
			for local_index in hierarchy.triangles[int(cluster.triangle_offset):triangle_end] {
				canonical_index := local_vertices[local_index]
				value := remap[canonical_index]
				encoded := [4]u8{u8(value), u8(value >> 8), u8(value >> 16), u8(value >> 24)}
				append(&result.bytes, ..encoded[:])
			}
		}
		result.records[page_index] = {
			offset = u64(page_start),
			size = u64(len(result.bytes) - page_start),
			vertex_count = page_vertex_count,
			index_count = page.index_count,
		}
	}
	return result, ""
}

destroy_page_payloads :: proc(payloads: ^Page_Payloads, allocator := context.allocator) {
	if payloads == nil {
		return
	}
	delete(payloads.records, allocator)
	delete(payloads.bytes)
	payloads^ = {}
}
