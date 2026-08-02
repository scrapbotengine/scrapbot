package resources

import geometry "../geometry"
import c "core:c"
import "core:mem"

MESHLET_MAX_VERTICES :: 64
MESHLET_MAX_TRIANGLES :: 124
MESHLET_CONE_WEIGHT :: f32(0.5)

Meshlet :: struct {
	vertex_offset: u32,
	triangle_offset: u32,
	vertex_count: u32,
	triangle_count: u32,
	bounds: [4]f32,
	cone_axis_cutoff: [4]f32,
}

Meshlet_Data :: struct {
	meshlets: []Meshlet,
	vertices: []u32,
	triangles: []u8,
}

Geometry_Cluster_Group :: geometry.Cluster_Group
Geometry_Cluster :: geometry.Cluster
Geometry_Cluster_Page :: geometry.Cluster_Page
Geometry_Hierarchy :: geometry.Hierarchy

Meshopt_Meshlet :: struct {
	vertex_offset: u32,
	triangle_offset: u32,
	vertex_count: u32,
	triangle_count: u32,
}

Meshopt_Bounds :: struct {
	center: [3]f32,
	radius: f32,
	cone_apex: [3]f32,
	cone_axis: [3]f32,
	cone_cutoff: f32,
	cone_axis_s8: [3]i8,
	cone_cutoff_s8: i8,
}

foreign import meshoptimizer "system:c"

foreign meshoptimizer {
	@(link_name = "meshopt_buildMeshletsBound")
	meshopt_build_meshlets_bound :: proc(index_count, max_vertices, max_triangles: c.size_t) -> c.size_t ---

	@(link_name = "meshopt_buildMeshlets")
	meshopt_build_meshlets :: proc(meshlets: [^]Meshopt_Meshlet, meshlet_vertices: [^]u32, meshlet_triangles: [^]u8, indices: [^]u32, index_count: c.size_t, vertex_positions: [^]f32, vertex_count, vertex_positions_stride, max_vertices, max_triangles: c.size_t, cone_weight: f32) -> c.size_t ---

	@(link_name = "meshopt_optimizeMeshlet")
	meshopt_optimize_meshlet :: proc(meshlet_vertices: [^]u32, meshlet_triangles: [^]u8, triangle_count, vertex_count: c.size_t) ---

	@(link_name = "meshopt_computeMeshletBounds")
	meshopt_compute_meshlet_bounds :: proc(meshlet_vertices: [^]u32, meshlet_triangles: [^]u8, triangle_count: c.size_t, vertex_positions: [^]f32, vertex_count, vertex_positions_stride: c.size_t) -> Meshopt_Bounds ---

}

build_geometry_hierarchy :: proc(
	desc: Geometry_Desc,
	allocator: mem.Allocator,
) -> (
	Geometry_Hierarchy,
	string,
) {
	if len(desc.indices) == 0 || len(desc.vertices) == 0 {
		return {}, "cluster hierarchy source geometry is empty"
	}
	return geometry.build_hierarchy(
		desc.indices,
		raw_data(desc.vertices),
		len(desc.vertices),
		size_of(Vertex),
		allocator,
	)
}

build_meshlets :: proc(desc: Geometry_Desc, allocator: mem.Allocator) -> (Meshlet_Data, string) {
	if len(desc.indices) == 0 || len(desc.vertices) == 0 {
		return {}, "meshlet source geometry is empty"
	}
	bound := int(
		meshopt_build_meshlets_bound(
			c.size_t(len(desc.indices)),
			MESHLET_MAX_VERTICES,
			MESHLET_MAX_TRIANGLES,
		),
	)
	if bound <= 0 {
		return {}, "failed to calculate meshlet capacity"
	}
	native_meshlets := make([]Meshopt_Meshlet, bound, context.temp_allocator)
	meshlet_vertices_scratch := make([]u32, len(desc.indices), context.temp_allocator)
	meshlet_triangles_scratch := make([]u8, len(desc.indices), context.temp_allocator)
	vertex_positions := cast([^]f32)raw_data(desc.vertices)
	meshlet_count := int(
		meshopt_build_meshlets(
			raw_data(native_meshlets),
			raw_data(meshlet_vertices_scratch),
			raw_data(meshlet_triangles_scratch),
			raw_data(desc.indices),
			c.size_t(len(desc.indices)),
			vertex_positions,
			c.size_t(len(desc.vertices)),
			c.size_t(size_of(Vertex)),
			MESHLET_MAX_VERTICES,
			MESHLET_MAX_TRIANGLES,
			MESHLET_CONE_WEIGHT,
		),
	)
	if meshlet_count <= 0 {
		return {}, "failed to build geometry meshlets"
	}
	last := native_meshlets[meshlet_count - 1]
	vertex_count := int(last.vertex_offset + last.vertex_count)
	triangle_byte_count := int(last.triangle_offset + last.triangle_count * 3)
	meshlet_vertices := make([]u32, vertex_count, allocator)
	meshlet_triangles := make([]u8, triangle_byte_count, allocator)
	copy(meshlet_vertices, meshlet_vertices_scratch[:vertex_count])
	copy(meshlet_triangles, meshlet_triangles_scratch[:triangle_byte_count])
	meshlets := make([]Meshlet, meshlet_count, allocator)
	for native, index in native_meshlets[:meshlet_count] {
		vertex_start := int(native.vertex_offset)
		vertex_end := int(native.vertex_offset + native.vertex_count)
		triangle_start := int(native.triangle_offset)
		triangle_end := int(native.triangle_offset + native.triangle_count * 3)
		vertices := meshlet_vertices[vertex_start:vertex_end]
		triangles := meshlet_triangles[triangle_start:triangle_end]
		meshopt_optimize_meshlet(
			raw_data(vertices),
			raw_data(triangles),
			c.size_t(native.triangle_count),
			c.size_t(native.vertex_count),
		)
		bounds := meshopt_compute_meshlet_bounds(
			raw_data(vertices),
			raw_data(triangles),
			c.size_t(native.triangle_count),
			vertex_positions,
			c.size_t(len(desc.vertices)),
			c.size_t(size_of(Vertex)),
		)
		meshlets[index] = {
			vertex_offset = native.vertex_offset,
			triangle_offset = native.triangle_offset,
			vertex_count = native.vertex_count,
			triangle_count = native.triangle_count,
			bounds = {bounds.center[0], bounds.center[1], bounds.center[2], bounds.radius},
			cone_axis_cutoff = {
				bounds.cone_axis[0],
				bounds.cone_axis[1],
				bounds.cone_axis[2],
				bounds.cone_cutoff,
			},
		}
	}
	return {meshlets = meshlets, vertices = meshlet_vertices, triangles = meshlet_triangles}, ""
}

destroy_meshlet_data :: proc(data: ^Meshlet_Data, allocator: mem.Allocator) {
	if data == nil {
		return
	}
	delete(data.meshlets, allocator)
	delete(data.vertices, allocator)
	delete(data.triangles, allocator)
	data^ = {}
}

build_leaf_meshlets :: proc(
	hierarchy: ^Geometry_Hierarchy,
	allocator: mem.Allocator,
) -> (
	Meshlet_Data,
	string,
) {
	if hierarchy == nil || len(hierarchy.clusters) == 0 {
		return {}, "geometry cluster hierarchy is empty"
	}
	leaf_count := 0
	for cluster in hierarchy.clusters {
		if cluster.refined_group == -1 {
			leaf_count += 1
		}
	}
	if leaf_count == 0 {
		return {}, "geometry cluster hierarchy has no leaf clusters"
	}
	vertex_count, triangle_byte_count := 0, 0
	for cluster in hierarchy.clusters {
		if cluster.refined_group == -1 {
			vertex_count += int(cluster.vertex_count)
			triangle_byte_count += int(cluster.triangle_count * 3)
		}
	}
	result := Meshlet_Data {
		meshlets = make([]Meshlet, leaf_count, allocator),
		vertices = make([]u32, vertex_count, allocator),
		triangles = make([]u8, triangle_byte_count, allocator),
	}
	meshlet_cursor, vertex_cursor, triangle_cursor := 0, 0, 0
	for cluster in hierarchy.clusters {
		if cluster.refined_group != -1 {
			continue
		}
		vertex_start := int(cluster.vertex_offset)
		vertex_end := vertex_start + int(cluster.vertex_count)
		triangle_start := int(cluster.triangle_offset)
		triangle_end := triangle_start + int(cluster.triangle_count * 3)
		copy(result.vertices[vertex_cursor:], hierarchy.vertices[vertex_start:vertex_end])
		copy(result.triangles[triangle_cursor:], hierarchy.triangles[triangle_start:triangle_end])
		result.meshlets[meshlet_cursor] = {
			vertex_offset = u32(vertex_cursor),
			triangle_offset = u32(triangle_cursor),
			vertex_count = cluster.vertex_count,
			triangle_count = cluster.triangle_count,
			bounds = cluster.bounds,
			cone_axis_cutoff = cluster.cone_axis_cutoff,
		}
		meshlet_cursor += 1
		vertex_cursor += int(cluster.vertex_count)
		triangle_cursor += int(cluster.triangle_count * 3)
	}
	return result, ""
}

destroy_geometry_hierarchy :: proc(data: ^Geometry_Hierarchy, allocator: mem.Allocator) {
	if data == nil {
		return
	}
	geometry.destroy_hierarchy(data, allocator)
}
