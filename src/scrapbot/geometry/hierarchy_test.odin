package geometry

import "core:testing"

Test_Hierarchy_Vertex :: struct {
	position, normal: [3]f32,
	uv: [2]f32,
	tangent: [4]f32,
}

test_open_grid_hierarchy :: proc(
	size: int,
	hole_min, hole_max: int,
) -> (
	[]Test_Hierarchy_Vertex,
	[]u32,
) {
	vertices := make([]Test_Hierarchy_Vertex, size * size)
	for z in 0 ..< size {
		for x in 0 ..< size {
			vertices[z * size + x] = {
				position = {f32(x), 0, f32(z)},
				normal = {0, 1, 0},
				uv = {f32(x) / f32(size - 1), f32(z) / f32(size - 1)},
				tangent = {1, 0, 0, 1},
			}
		}
	}
	indices := make([dynamic]u32, 0, (size - 1) * (size - 1) * 6)
	for z in 0 ..< size - 1 {
		for x in 0 ..< size - 1 {
			if x >= hole_min && x < hole_max && z >= hole_min && z < hole_max {
				continue
			}
			a := u32(z * size + x)
			b := a + 1
			c := a + u32(size)
			d := c + 1
			append(&indices, a, c, b, b, c, d)
		}
	}
	return vertices, indices[:]
}

test_terminal_frontier_contains_vertex :: proc(hierarchy: ^Hierarchy, vertex: u32) -> bool {
	for group in hierarchy.groups {
		if !cluster_group_is_terminal(group) {
			continue
		}
		for cluster in hierarchy.clusters[int(group.cluster_offset):int(group.cluster_offset + group.cluster_count)] {
			for candidate in hierarchy.vertices[int(cluster.vertex_offset):int(cluster.vertex_offset + cluster.vertex_count)] {
				if candidate == vertex {
					return true
				}
			}
		}
	}
	return false
}

@(test)
test_cluster_pages_pin_every_terminal_group :: proc(t: ^testing.T) {
	hierarchy := Hierarchy {
		groups = make([]Cluster_Group, 3),
		clusters = make([]Cluster, 3),
		max_depth = 2,
	}
	defer destroy_hierarchy(&hierarchy)

	hierarchy.groups[0] = {
		error = 3.4028235e38,
		depth = 0,
		cluster_offset = 0,
		cluster_count = 1,
	}
	hierarchy.groups[1] = {
		error = 0.25,
		depth = 1,
		cluster_offset = 1,
		cluster_count = 1,
	}
	hierarchy.groups[2] = {
		error = 3.4028235e38,
		depth = 2,
		cluster_offset = 2,
		cluster_count = 1,
	}
	for &cluster, index in hierarchy.clusters {
		cluster.group = i32(index)
		cluster.triangle_count = 1
	}

	build_cluster_pages(&hierarchy)

	testing.expect_value(t, len(hierarchy.pages), 3)
	testing.expect(t, hierarchy.pages[0].pinned)
	testing.expect(t, !hierarchy.pages[1].pinned)
	testing.expect(t, hierarchy.pages[2].pinned)
	testing.expect(t, hierarchy.pages[0].bootstrap)
	testing.expect(t, !hierarchy.pages[1].bootstrap)
	testing.expect(t, hierarchy.pages[2].bootstrap)
}

@(test)
test_open_mesh_boundaries_survive_the_terminal_frontier :: proc(t: ^testing.T) {
	GRID_SIZE :: 24
	HOLE_MIN :: 9
	HOLE_MAX :: 14
	vertices, indices := test_open_grid_hierarchy(GRID_SIZE, HOLE_MIN, HOLE_MAX)
	defer delete(vertices)
	defer delete(indices)

	hierarchy, hierarchy_err := build_hierarchy(
		indices,
		raw_data(vertices),
		len(vertices),
		size_of(Test_Hierarchy_Vertex),
	)
	defer destroy_hierarchy(&hierarchy)
	testing.expectf(t, hierarchy_err == "", "hierarchy build failed: %s", hierarchy_err)
	if hierarchy_err != "" {
		return
	}

	for coordinate in 0 ..< GRID_SIZE {
		testing.expect(t, test_terminal_frontier_contains_vertex(&hierarchy, u32(coordinate)))
		testing.expect(
			t,
			test_terminal_frontier_contains_vertex(
				&hierarchy,
				u32((GRID_SIZE - 1) * GRID_SIZE + coordinate),
			),
		)
	}
	for coordinate in HOLE_MIN ..= HOLE_MAX {
		boundary_vertices := [4]u32 {
			u32(HOLE_MIN * GRID_SIZE + coordinate),
			u32(HOLE_MAX * GRID_SIZE + coordinate),
			u32(coordinate * GRID_SIZE + HOLE_MIN),
			u32(coordinate * GRID_SIZE + HOLE_MAX),
		}
		for vertex in boundary_vertices {
			testing.expect(t, test_terminal_frontier_contains_vertex(&hierarchy, vertex))
		}
	}
}

@(test)
test_resident_tail_refines_terminal_frontier_within_byte_cap :: proc(t: ^testing.T) {
	GRID_SIZE :: 64
	vertices, indices := test_open_grid_hierarchy(GRID_SIZE, -1, -1)
	defer delete(vertices)
	defer delete(indices)

	hierarchy, hierarchy_err := build_hierarchy(
		indices,
		raw_data(vertices),
		len(vertices),
		size_of(Test_Hierarchy_Vertex),
	)
	defer destroy_hierarchy(&hierarchy)
	testing.expectf(t, hierarchy_err == "", "hierarchy build failed: %s", hierarchy_err)
	if hierarchy_err != "" {
		return
	}

	marks := make([]u32, len(vertices), context.temp_allocator)
	terminal_bytes: u64
	bootstrap_bytes: u64
	bootstrap_refinement_count := 0
	for group in hierarchy.groups {
		for page_index in group.page_offset ..< group.page_offset + group.page_count {
			page_bytes := cluster_page_payload_size(
				&hierarchy,
				int(page_index),
				size_of(Test_Hierarchy_Vertex),
				marks,
				page_index + 1,
			)
			if cluster_group_is_terminal(group) {
				terminal_bytes += page_bytes
			}
			if hierarchy.pages[page_index].bootstrap {
				bootstrap_bytes += page_bytes
				if !cluster_group_is_terminal(group) {
					bootstrap_refinement_count += 1
				}
			}
		}
	}
	testing.expect(t, bootstrap_refinement_count > 0)
	testing.expect(t, bootstrap_bytes >= terminal_bytes)
	testing.expect(t, bootstrap_bytes <= terminal_bytes + CLUSTER_BOOTSTRAP_TAIL_MAX_EXTRA_BYTES)
	testing.expect_value(t, validate_hierarchy(&hierarchy, len(vertices)), "")

	for group in hierarchy.groups {
		if cluster_group_is_terminal(group) {
			continue
		}
		for page_index in group.page_offset ..< group.page_offset + group.page_count {
			hierarchy.pages[page_index].bootstrap = false
		}
	}
	unreachable_group := -1
	for group, group_index in hierarchy.groups {
		if cluster_group_is_terminal(group) {
			continue
		}
		has_terminal_parent := false
		for parent in hierarchy.groups {
			if !cluster_group_is_terminal(parent) {
				continue
			}
			cluster_end := int(parent.cluster_offset + parent.cluster_count)
			for cluster in hierarchy.clusters[int(parent.cluster_offset):cluster_end] {
				if cluster.refined_group == i32(group_index) {
					has_terminal_parent = true
					break
				}
			}
		}
		if !has_terminal_parent {
			unreachable_group = group_index
			break
		}
	}
	testing.expect(t, unreachable_group >= 0)
	if unreachable_group >= 0 {
		group := hierarchy.groups[unreachable_group]
		for page_index in group.page_offset ..< group.page_offset + group.page_count {
			hierarchy.pages[page_index].bootstrap = true
		}
		testing.expect_value(
			t,
			validate_hierarchy(&hierarchy, len(vertices)),
			"cluster hierarchy bootstrap refinement is unreachable",
		)
	}
}
