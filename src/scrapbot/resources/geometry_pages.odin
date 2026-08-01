package resources

import "core:fmt"
import "core:mem"
import "core:os"

Geometry_Canonical_View :: struct {
	vertices: []Vertex,
	indices: []u32,
	owned: bool,
}

Geometry_Query_Triangle :: struct {
	a, b, c: Vec3,
}

Geometry_Query_Iterator :: struct {
	geometry: ^Geometry,
	canonical_triangle: int,
	cluster_index: int,
	cluster_triangle: int,
}

geometry_canonical_vertex_count :: proc "contextless" (geometry: ^Geometry) -> int {
	if geometry == nil {
		return 0
	}
	if geometry.canonical_vertex_count > 0 {
		return int(geometry.canonical_vertex_count)
	}
	return len(geometry.vertices)
}

geometry_canonical_index_count :: proc "contextless" (geometry: ^Geometry) -> int {
	if geometry == nil {
		return 0
	}
	if geometry.canonical_index_count > 0 {
		return int(geometry.canonical_index_count)
	}
	return len(geometry.indices)
}

geometry_fallback_index_count :: proc "contextless" (geometry: ^Geometry) -> int {
	if geometry == nil {
		return 0
	}
	if geometry_has_resident_canonical(geometry) {
		return len(geometry.indices)
	}
	result := 0
	for cluster in geometry.clusters {
		if cluster.refined_group == -1 {
			result += int(cluster.triangle_count * 3)
		}
	}
	return result
}

geometry_has_resident_canonical :: proc "contextless" (geometry: ^Geometry) -> bool {
	return(
		geometry != nil &&
		len(geometry.vertices) == geometry_canonical_vertex_count(geometry) &&
		len(geometry.indices) == geometry_canonical_index_count(geometry) \
	)
}

destroy_geometry_canonical_view :: proc(
	view: ^Geometry_Canonical_View,
	allocator: mem.Allocator = context.allocator,
) {
	if view == nil {
		return
	}
	if view.owned {
		delete(view.vertices, allocator)
		delete(view.indices, allocator)
	}
	view^ = {}
}

load_geometry_canonical :: proc(
	geometry: ^Geometry,
	allocator: mem.Allocator = context.allocator,
) -> (
	Geometry_Canonical_View,
	string,
) {
	if geometry == nil {
		return {}, "geometry is unavailable"
	}
	if geometry_has_resident_canonical(geometry) {
		return {vertices = geometry.vertices, indices = geometry.indices}, ""
	}
	vertex_count := geometry_canonical_vertex_count(geometry)
	index_count := geometry_fallback_index_count(geometry)
	if vertex_count <= 0 || index_count <= 0 || len(geometry.cluster_pages) == 0 {
		return {}, "geometry has no canonical fallback source"
	}
	result := Geometry_Canonical_View {
		vertices = make([]Vertex, vertex_count, allocator),
		indices = make([]u32, index_count, allocator),
		owned = true,
	}
	failed := true
	defer if failed {
		destroy_geometry_canonical_view(&result, allocator)
	}
	page_marks := make([]u32, vertex_count, context.temp_allocator)
	page_token := u32(1)
	index_cursor := 0
	for page, page_index in geometry.cluster_pages {
		page_has_leaf := false
		cluster_end := int(page.cluster_offset + page.cluster_count)
		if cluster_end > len(geometry.clusters) {
			return {}, "geometry fallback page cluster range is invalid"
		}
		for cluster in geometry.clusters[int(page.cluster_offset):cluster_end] {
			if cluster.refined_group == -1 {
				page_has_leaf = true
				break
			}
		}
		if !page_has_leaf {
			continue
		}
		if page_index >= len(geometry.page_payload_records) {
			return {}, "geometry fallback page metadata is truncated"
		}
		record := geometry.page_payload_records[page_index]
		payload, payload_err := read_geometry_page_payload(geometry, page_index, allocator)
		if payload_err != "" {
			return {}, payload_err
		}
		page_vertices := make([]Vertex, int(record.vertex_count), allocator)
		vertex_bytes := len(page_vertices) * size_of(Vertex)
		if vertex_bytes > len(payload) {
			delete(page_vertices, allocator)
			delete(payload, allocator)
			return {}, "geometry fallback page vertex payload is truncated"
		}
		page_vertex_bytes := (cast([^]u8)raw_data(page_vertices))[:vertex_bytes]
		copy(page_vertex_bytes, payload[:vertex_bytes])
		page_vertex_cursor := 0
		for cluster in geometry.clusters[int(page.cluster_offset):cluster_end] {
			vertex_start := int(cluster.vertex_offset)
			vertex_end := vertex_start + int(cluster.vertex_count)
			triangle_start := int(cluster.triangle_offset)
			triangle_end := triangle_start + int(cluster.triangle_count * 3)
			if vertex_end > len(geometry.cluster_vertices) ||
			   triangle_end > len(geometry.cluster_triangles) {
				delete(page_vertices, allocator)
				delete(payload, allocator)
				return {}, "geometry fallback cluster stream is invalid"
			}
			cluster_vertices := geometry.cluster_vertices[vertex_start:vertex_end]
			for canonical_index in cluster_vertices {
				if int(canonical_index) >= vertex_count {
					delete(page_vertices, allocator)
					delete(payload, allocator)
					return {}, "geometry fallback vertex index is invalid"
				}
				if page_marks[canonical_index] == page_token {
					continue
				}
				if page_vertex_cursor >= len(page_vertices) {
					delete(page_vertices, allocator)
					delete(payload, allocator)
					return {}, "geometry fallback page vertex mapping is invalid"
				}
				page_marks[canonical_index] = page_token
				result.vertices[canonical_index] = page_vertices[page_vertex_cursor]
				page_vertex_cursor += 1
			}
			if cluster.refined_group != -1 {
				continue
			}
			for local_index in geometry.cluster_triangles[triangle_start:triangle_end] {
				if int(local_index) >= len(cluster_vertices) ||
				   index_cursor >= len(result.indices) {
					delete(page_vertices, allocator)
					delete(payload, allocator)
					return {}, "geometry fallback triangle stream is invalid"
				}
				result.indices[index_cursor] = cluster_vertices[local_index]
				index_cursor += 1
			}
		}
		delete(page_vertices, allocator)
		delete(payload, allocator)
		if page_vertex_cursor != int(record.vertex_count) {
			return {}, "geometry fallback page vertex count does not match its topology"
		}
		page_token += 1
	}
	if index_cursor != len(result.indices) {
		return {}, "geometry fallback index count does not match its leaf topology"
	}
	failed = false
	return result, ""
}

geometry_query_iterator :: proc "contextless" (geometry: ^Geometry) -> Geometry_Query_Iterator {
	return {geometry = geometry}
}

geometry_query_next :: proc "contextless" (
	iterator: ^Geometry_Query_Iterator,
) -> (
	Geometry_Query_Triangle,
	bool,
) {
	if iterator == nil || iterator.geometry == nil {
		return {}, false
	}
	geometry := iterator.geometry
	if geometry_has_resident_canonical(geometry) {
		index := iterator.canonical_triangle * 3
		if index + 2 >= len(geometry.indices) {
			return {}, false
		}
		iterator.canonical_triangle += 1
		a := geometry.indices[index]
		b := geometry.indices[index + 1]
		c := geometry.indices[index + 2]
		if int(a) >= len(geometry.vertices) ||
		   int(b) >= len(geometry.vertices) ||
		   int(c) >= len(geometry.vertices) {
			return {}, false
		}
		return {
				a = geometry.vertices[a].position,
				b = geometry.vertices[b].position,
				c = geometry.vertices[c].position,
			},
			true
	}
	for iterator.cluster_index < len(geometry.clusters) {
		cluster := geometry.clusters[iterator.cluster_index]
		if cluster.refined_group != -1 ||
		   iterator.cluster_triangle >= int(cluster.triangle_count) {
			iterator.cluster_index += 1
			iterator.cluster_triangle = 0
			continue
		}
		triangle_start := int(cluster.triangle_offset) + iterator.cluster_triangle * 3
		vertex_start := int(cluster.vertex_offset)
		iterator.cluster_triangle += 1
		if triangle_start + 2 >= len(geometry.cluster_triangles) {
			return {}, false
		}
		local_a := int(geometry.cluster_triangles[triangle_start])
		local_b := int(geometry.cluster_triangles[triangle_start + 1])
		local_c := int(geometry.cluster_triangles[triangle_start + 2])
		if local_a >= int(cluster.vertex_count) ||
		   local_b >= int(cluster.vertex_count) ||
		   local_c >= int(cluster.vertex_count) {
			return {}, false
		}
		a := geometry.cluster_vertices[vertex_start + local_a]
		b := geometry.cluster_vertices[vertex_start + local_b]
		c := geometry.cluster_vertices[vertex_start + local_c]
		if int(a) >= len(geometry.query_proxy.positions) ||
		   int(b) >= len(geometry.query_proxy.positions) ||
		   int(c) >= len(geometry.query_proxy.positions) {
			return {}, false
		}
		return {
				a = geometry.query_proxy.positions[a],
				b = geometry.query_proxy.positions[b],
				c = geometry.query_proxy.positions[c],
			},
			true
	}
	return {}, false
}

read_geometry_page_payload :: proc(
	geometry: ^Geometry,
	page_index: int,
	allocator: mem.Allocator = context.allocator,
) -> (
	[]u8,
	string,
) {
	if geometry == nil || page_index < 0 || page_index >= len(geometry.page_payload_records) {
		return nil, "geometry page is out of bounds"
	}
	record := geometry.page_payload_records[page_index]
	if record.size == 0 || record.size > u64(max(int)) {
		return nil, "geometry page size is invalid"
	}
	bytes := make([]u8, int(record.size), allocator)
	#partial switch geometry.page_source_kind {
		case .Memory:
			end := record.offset + record.size
			if end > u64(len(geometry.page_payload_bytes)) {
				delete(bytes, allocator)
				return nil, "geometry memory page is truncated"
			}
			copy(bytes, geometry.page_payload_bytes[int(record.offset):int(end)])
		case .File:
			file, open_err := os.open(geometry.page_source_path)
			if open_err != nil {
				delete(bytes, allocator)
				return nil, fmt.tprintf("failed to open geometry page source: %v", open_err)
			}
			defer os.close(file)
			read_count, read_err := os.read_at(file, bytes, i64(record.offset))
			if read_err != nil || read_count != len(bytes) {
				delete(bytes, allocator)
				return nil, "failed to read complete geometry page"
			}
	}
	return bytes, ""
}

geometry_page_vertex_bytes :: proc(geometry: ^Geometry, page_index: int) -> u64 {
	if geometry == nil || page_index < 0 || page_index >= len(geometry.page_payload_records) {
		return 0
	}
	return u64(geometry.page_payload_records[page_index].vertex_count) * u64(size_of(Vertex))
}
