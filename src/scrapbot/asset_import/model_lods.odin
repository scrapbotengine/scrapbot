package asset_import

import geometry "../geometry"
import shared "../shared"
import c "core:c"

MODEL_LOD_MIN_SOURCE_TRIANGLES :: 16
MODEL_LOD_TARGET_ERRORS :: [shared.MAX_GEOMETRY_LODS - 1]f32{0.01, 0.03, 0.08}

foreign import meshoptimizer "system:c"

foreign meshoptimizer {
	@(link_name = "meshopt_simplifyWithAttributes")
	meshopt_simplify_with_attributes :: proc(destination, indices: [^]u32, index_count: c.size_t, vertex_positions: [^]f32, vertex_count, vertex_positions_stride: c.size_t, vertex_attributes: [^]f32, vertex_attributes_stride: c.size_t, attribute_weights: [^]f32, attribute_count: c.size_t, vertex_lock: [^]u8, target_index_count: c.size_t, target_error: f32, options: u32, result_error: ^f32) -> c.size_t ---
}

build_model_primitive_lods :: proc(
	primitive: ^Model_Primitive,
	settings: shared.Project_Model_Resource,
) {
	if primitive == nil ||
	   len(primitive.indices) / 3 < MODEL_LOD_MIN_SOURCE_TRIANGLES ||
	   len(primitive.vertices) == 0 {
		return
	}
	previous_index_count := len(primitive.indices)
	target_errors := MODEL_LOD_TARGET_ERRORS
	for level in 0 ..< min(settings.lod_count, shared.MAX_GEOMETRY_LODS - 1) {
		target_index_count := max(
			3,
			int(f32(len(primitive.indices)) * settings.lod_ratios[level]) / 3 * 3,
		)
		if target_index_count >= previous_index_count {
			continue
		}
		simplified := make([]u32, len(primitive.indices), context.temp_allocator)
		attribute_weights := [5]f32{0.5, 0.5, 0.5, 0.1, 0.1}
		result_error: f32
		result_count := int(
			meshopt_simplify_with_attributes(
				raw_data(simplified),
				raw_data(primitive.indices),
				c.size_t(len(primitive.indices)),
				cast([^]f32)raw_data(primitive.vertices),
				c.size_t(len(primitive.vertices)),
				c.size_t(size_of(Model_Vertex)),
				cast([^]f32)&primitive.vertices[0].normal,
				c.size_t(size_of(Model_Vertex)),
				raw_data(attribute_weights[:]),
				c.size_t(len(attribute_weights)),
				nil,
				c.size_t(target_index_count),
				target_errors[level],
				0,
				&result_error,
			),
		)
		result_count = result_count / 3 * 3
		if result_count < 3 || result_count >= previous_index_count {
			continue
		}
		lod := compact_model_lod(
			primitive.vertices[:],
			simplified[:result_count],
			u32(level),
			settings.lod_screen_radii[level],
			result_error,
		)
		if len(lod.vertices) == 0 || len(lod.indices) == 0 {
			continue
		}
		append(&primitive.lods, lod)
		previous_index_count = result_count
	}
}

compact_model_lod :: proc(
	source_vertices: []Model_Vertex,
	source_indices: []u32,
	level: u32,
	screen_radius, simplification_error: f32,
) -> Model_Primitive_LOD {
	lod := Model_Primitive_LOD {
		vertices = make([dynamic]Model_Vertex, 0, min(len(source_vertices), len(source_indices))),
		indices = make([dynamic]u32, 0, len(source_indices)),
		level = level,
		screen_radius = screen_radius,
		simplification_error = simplification_error,
	}
	remap := make([]i32, len(source_vertices), context.temp_allocator)
	for &index in remap {
		index = -1
	}
	for source_index in source_indices {
		if int(source_index) >= len(source_vertices) {
			delete(lod.vertices)
			delete(lod.indices)
			return {}
		}
		destination_index := remap[int(source_index)]
		if destination_index < 0 {
			destination_index = i32(len(lod.vertices))
			remap[int(source_index)] = destination_index
			append(&lod.vertices, source_vertices[int(source_index)])
		}
		append(&lod.indices, u32(destination_index))
	}
	return lod
}

destroy_model_lod :: proc(lod: ^Model_Primitive_LOD) {
	if lod == nil {
		return
	}
	delete(lod.vertices)
	delete(lod.indices)
	delete(lod.page_payloads)
	geometry.destroy_hierarchy(&lod.hierarchy)
	lod^ = {}
}
