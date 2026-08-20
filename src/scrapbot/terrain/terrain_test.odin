package terrain

import "core:math"
import "core:testing"

make_flat_terrain :: proc(t: ^testing.T, height: f32 = 0) -> Terrain {
	heights := []f32{height, height, height, height}
	terrain: Terrain
	err := init(
		&terrain,
		Description {
			origin = {-8, -8, -8},
			voxel_size = 1,
			height_columns = 1,
			height_rows = 1,
			height_cell_size = 16,
			heights = heights,
		},
	)
	testing.expectf(t, err == "", "terrain initialization failed: %s", err)
	return terrain
}

@(test)
test_height_baseline_defines_solid_below_and_empty_above :: proc(t: ^testing.T) {
	terrain := make_flat_terrain(t)
	defer destroy(&terrain)
	testing.expect(t, density_at_world(&terrain, {0, -2, 0}) > 0)
	testing.expect(t, density_at_world(&terrain, {0, 2, 0}) < 0)
	testing.expect(t, math.abs(density_at_world(&terrain, {0, 0, 0})) < 0.00001)
}

@(test)
test_sparse_density_edit_changes_only_its_local_interpolation_cell :: proc(t: ^testing.T) {
	terrain := make_flat_terrain(t)
	defer destroy(&terrain)
	sample := Sample_Coord{8, 8, 8}
	before := density_at_sample(&terrain, sample)
	testing.expect(t, set_density_edit(&terrain, sample, -4) == "")
	testing.expect_value(t, density_at_sample(&terrain, sample), before - 4)
	testing.expect_value(
		t,
		density_at_sample(&terrain, Sample_Coord{sample.x + 2, sample.y, sample.z}),
		density_at_world(
			&terrain,
			sample_world_position(&terrain, Sample_Coord{sample.x + 2, sample.y, sample.z}),
		),
	)
}

@(test)
test_sample_dirtiness_touches_at_most_eight_chunks_and_handles_negative_space :: proc(
	t: ^testing.T,
) {
	interior := affected_chunks_for_sample({3, 3, 3}, 8)
	defer delete(interior)
	testing.expect_value(t, len(interior), 1)
	boundary := affected_chunks_for_sample({0, 0, 0}, 8)
	defer delete(boundary)
	testing.expect_value(t, len(boundary), 8)
	found_negative := false
	for chunk in boundary {
		if chunk == (Chunk_Coord{-1, -1, -1}) {
			found_negative = true
		}
	}
	testing.expect(t, found_negative)
}

@(test)
test_extraction_builds_an_upward_smooth_surface :: proc(t: ^testing.T) {
	terrain := make_flat_terrain(t)
	defer destroy(&terrain)
	mesh, err := extract_chunk(&terrain, {0, 1, 0}, 8)
	defer destroy_surface_mesh(&mesh)
	testing.expectf(t, err == "", "terrain extraction failed: %s", err)
	testing.expect(t, len(mesh.indices) > 0)
	for index := 0; index < len(mesh.indices); index += 3 {
		a := mesh.vertices[mesh.indices[index]].position
		b := mesh.vertices[mesh.indices[index + 1]].position
		c := mesh.vertices[mesh.indices[index + 2]].position
		testing.expect(t, triangle_has_area(a, b, c))
	}
	for vertex in mesh.vertices {
		testing.expect(t, vertex.normal.y > 0.99)
		testing.expect(t, math.abs(vertex.position.y) < 0.00001)
	}
}

@(test)
test_neighbor_chunks_emit_identical_vertices_on_their_shared_boundary :: proc(t: ^testing.T) {
	heights := []f32{0, 2, -1, 1}
	terrain: Terrain
	err := init(
		&terrain,
		Description {
			origin = {0, -4, 0},
			voxel_size = 1,
			height_columns = 1,
			height_rows = 1,
			height_cell_size = 16,
			heights = heights,
		},
	)
	defer destroy(&terrain)
	testing.expect(t, err == "")
	left, left_err := extract_chunk(&terrain, {0, 1, 0}, 4)
	defer destroy_surface_mesh(&left)
	right, right_err := extract_chunk(&terrain, {1, 1, 0}, 4)
	defer destroy_surface_mesh(&right)
	testing.expect(t, left_err == "" && right_err == "")
	left_boundary: [dynamic]Vec3
	right_boundary: [dynamic]Vec3
	defer delete(left_boundary)
	defer delete(right_boundary)
	boundary_x := terrain.origin.x + 4 * terrain.voxel_size
	for vertex in left.vertices {
		if math.abs(vertex.position.x - boundary_x) < 0.00001 {
			append(&left_boundary, vertex.position)
		}
	}
	for vertex in right.vertices {
		if math.abs(vertex.position.x - boundary_x) < 0.00001 {
			append(&right_boundary, vertex.position)
		}
	}
	testing.expect(t, len(left_boundary) > 0)
	for position in left_boundary {
		found := false
		for candidate in right_boundary {
			if distance_squared(position, candidate) < 0.0000001 {
				found = true
				break
			}
		}
		testing.expect(t, found)
	}
}

distance_squared :: proc(a, b: Vec3) -> f32 {
	dx := a.x - b.x
	dy := a.y - b.y
	dz := a.z - b.z
	return dx * dx + dy * dy + dz * dz
}

@(test)
test_sphere_brush_changes_only_local_samples_and_queues_unique_chunks :: proc(t: ^testing.T) {
	terrain := make_flat_terrain(t)
	defer destroy(&terrain)
	queue: Dirty_Chunk_Queue
	testing.expect(t, init_dirty_chunk_queue(&queue, 4) == "")
	defer destroy_dirty_chunk_queue(&queue)
	changed, err := apply_sphere_brush(&terrain, &queue, {0, 0, 0}, 1.5, -2)
	testing.expectf(t, err == "", "terrain brush failed: %s", err)
	testing.expect(t, changed > 1)
	testing.expect(t, density_at_sample(&terrain, {8, 8, 8}) < 0)
	testing.expect_value(t, density_at_sample(&terrain, {12, 8, 12}), f32(0))
	testing.expect(t, dirty_chunk_count(&queue) > 0)
	testing.expect(t, dirty_chunk_count(&queue) <= 8)

	queued := dirty_chunk_count(&queue)
	_, repeat_err := apply_sphere_brush(&terrain, &queue, {0, 0, 0}, 1.5, -1)
	testing.expect(t, repeat_err == "")
	testing.expect_value(t, dirty_chunk_count(&queue), queued)
}

@(test)
test_dirty_chunk_queue_does_no_work_when_stable_and_drains_incrementally :: proc(t: ^testing.T) {
	queue: Dirty_Chunk_Queue
	testing.expect(t, init_dirty_chunk_queue(&queue, 8) == "")
	defer destroy_dirty_chunk_queue(&queue)

	_, stable_has_work := take_dirty_chunk(&queue)
	testing.expect(t, !stable_has_work)
	enqueue_dirty_sample(&queue, {8, 8, 8})
	initial_count := dirty_chunk_count(&queue)
	testing.expect_value(t, initial_count, 8)

	_, first_has_work := take_dirty_chunk(&queue)
	testing.expect(t, first_has_work)
	testing.expect_value(t, dirty_chunk_count(&queue), initial_count - 1)
	for dirty_chunk_count(&queue) > 0 {
		_, has_work := take_dirty_chunk(&queue)
		testing.expect(t, has_work)
	}
	_, drained_has_work := take_dirty_chunk(&queue)
	testing.expect(t, !drained_has_work)
}

@(test)
test_dirty_chunk_queue_compacts_processed_history_during_sustained_work :: proc(t: ^testing.T) {
	queue: Dirty_Chunk_Queue
	testing.expect(t, init_dirty_chunk_queue(&queue, 8) == "")
	defer destroy_dirty_chunk_queue(&queue)
	enqueue_dirty_sample(&queue, {0, 0, 0})
	testing.expect_value(t, dirty_chunk_count(&queue), 8)
	for index in 0 ..< 3_000 {
		_, has_work := take_dirty_chunk(&queue)
		testing.expect(t, has_work)
		enqueue_dirty_chunk(&queue, {index + 100, 0, 0})
	}
	testing.expect_value(t, dirty_chunk_count(&queue), 8)
	testing.expect(t, len(queue.chunks) <= 1_032)
}

@(test)
test_sphere_brush_rejects_missing_invalidation_and_unbounded_work_atomically :: proc(
	t: ^testing.T,
) {
	terrain := make_flat_terrain(t)
	defer destroy(&terrain)
	sample := Sample_Coord{8, 8, 8}
	before := density_at_sample(&terrain, sample)

	_, missing_queue_err := apply_sphere_brush(&terrain, nil, {0, 0, 0}, 1, -1)
	testing.expect(t, missing_queue_err != "")
	testing.expect_value(t, density_at_sample(&terrain, sample), before)

	queue: Dirty_Chunk_Queue
	testing.expect(t, init_dirty_chunk_queue(&queue, 8) == "")
	defer destroy_dirty_chunk_queue(&queue)
	_, oversized_err := apply_sphere_brush(&terrain, &queue, {0, 0, 0}, 32, -1)
	testing.expect(t, oversized_err != "")
	testing.expect_value(t, density_at_sample(&terrain, sample), before)
	testing.expect_value(t, dirty_chunk_count(&queue), 0)
	_, distant_err := apply_sphere_brush(&terrain, &queue, {2_000_000_000, 0, 0}, 1, -1)
	testing.expect(t, distant_err != "")
	testing.expect_value(t, density_at_sample(&terrain, sample), before)

	testing.expect(t, set_density_edit(&terrain, sample, 3e38) == "")
	before_overflow := terrain.density_edits[sample]
	_, overflow_err := apply_sphere_brush(&terrain, &queue, {0, 0, 0}, 1, 3e38)
	testing.expect(t, overflow_err != "")
	testing.expect_value(t, terrain.density_edits[sample], before_overflow)
	testing.expect_value(t, dirty_chunk_count(&queue), 0)
}

@(test)
test_surface_extraction_reuses_vertices_across_triangle_edges :: proc(t: ^testing.T) {
	terrain := make_flat_terrain(t)
	defer destroy(&terrain)
	mesh, err := extract_region(&terrain, {6, 7, 6}, {4, 2, 4})
	defer destroy_surface_mesh(&mesh)
	testing.expectf(t, err == "", "terrain extraction failed: %s", err)
	testing.expect(t, len(mesh.indices) > len(mesh.vertices))
	testing.expect(t, len(mesh.indices) % 3 == 0)
}

@(test)
test_extraction_preserves_valid_surfaces_at_small_voxel_scales :: proc(t: ^testing.T) {
	heights := []f32{0, 0, 0, 0}
	terrain: Terrain
	err := init(
		&terrain,
		Description {
			origin = {0, -2e-12, 0},
			voxel_size = 1e-12,
			height_columns = 1,
			height_rows = 1,
			height_cell_size = 1e-11,
			heights = heights,
		},
	)
	defer destroy(&terrain)
	testing.expect(t, err == "")
	mesh, extract_err := extract_region(&terrain, {}, {2, 4, 2})
	defer destroy_surface_mesh(&mesh)
	testing.expect(t, extract_err == "")
	testing.expect(t, len(mesh.indices) > 0)
	for index := 0; index < len(mesh.indices); index += 3 {
		a := mesh.vertices[mesh.indices[index]].position
		b := mesh.vertices[mesh.indices[index + 1]].position
		c := mesh.vertices[mesh.indices[index + 2]].position
		testing.expect(t, triangle_has_area(a, b, c))
	}
}

@(test)
test_core_extraction_rejects_unbounded_regions_before_meshing :: proc(t: ^testing.T) {
	terrain := make_flat_terrain(t)
	defer destroy(&terrain)
	_, axis_err := extract_region(&terrain, {}, {65, 1, 1})
	testing.expect(t, axis_err != "")
	_, total_err := extract_region(&terrain, {}, {64, 64, 17})
	testing.expect(t, total_err != "")
}

@(test)
test_low_amplitude_edge_interpolation_is_argument_order_independent :: proc(t: ^testing.T) {
	a := Sample_Coord{0, 0, 0}
	b := Sample_Coord{1, 0, 0}
	forward := interpolate_surface_point(a, b, {0, 0, 0}, {1, 0, 0}, 9e-7, -1e-8)
	reverse := interpolate_surface_point(b, a, {1, 0, 0}, {0, 0, 0}, -1e-8, 9e-7)
	testing.expect_value(t, forward.edge, reverse.edge)
	testing.expect(t, distance_squared(forward.position, reverse.position) < 0.0000000001)
	testing.expect(t, forward.position.x > 0.98)
	testing.expect_value(t, normalize({1e-30, 0, 0}), Vec3{1, 0, 0})
	extreme_forward := interpolate_surface_point(a, b, {0, 0, 0}, {1, 0, 0}, 3e38, -3e38)
	extreme_reverse := interpolate_surface_point(b, a, {1, 0, 0}, {0, 0, 0}, -3e38, 3e38)
	testing.expect(t, distance_squared(extreme_forward.position, extreme_reverse.position) == 0)
	testing.expect_value(t, extreme_forward.position.x, f32(0.5))
	testing.expect_value(t, normalize_f64(6e38, 0, 0), Vec3{1, 0, 0})
}

@(test)
test_positive_brush_monotonically_increases_tiny_positive_edits :: proc(t: ^testing.T) {
	terrain := make_flat_terrain(t)
	defer destroy(&terrain)
	queue: Dirty_Chunk_Queue
	testing.expect(t, init_dirty_chunk_queue(&queue, 8) == "")
	defer destroy_dirty_chunk_queue(&queue)
	sample := Sample_Coord{8, 8, 8}
	testing.expect(t, set_density_edit(&terrain, sample, 5e-7) == "")
	before := terrain.density_edits[sample]
	changed, err := apply_sphere_brush(&terrain, &queue, {0, 0, 0}, 1, 5e-7)
	testing.expect(t, err == "")
	testing.expect(t, changed > 0)
	testing.expect(t, terrain.density_edits[sample] > before)
	testing.expect(t, dirty_chunk_count(&queue) > 0)
}

triangle_has_area :: proc(a, b, c: Vec3) -> bool {
	ab := Vec3{b.x - a.x, b.y - a.y, b.z - a.z}
	ac := Vec3{c.x - a.x, c.y - a.y, c.z - a.z}
	cross_value := Vec3 {
		ab.y * ac.z - ab.z * ac.y,
		ab.z * ac.x - ab.x * ac.z,
		ab.x * ac.y - ab.y * ac.x,
	}
	return cross_value.x != 0 || cross_value.y != 0 || cross_value.z != 0
}
