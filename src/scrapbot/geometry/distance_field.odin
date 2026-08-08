package geometry

import c "core:c"
import "core:math"
import "core:mem"

DISTANCE_FIELD_DEFAULT_LONGEST_AXIS_CELLS :: u32(32)
DISTANCE_FIELD_DEFAULT_PADDING_CELLS :: u32(2)
DISTANCE_FIELD_MAX_AXIS_CELLS :: u32(256)

Distance_Field :: struct {
	samples: []f32,
	dimensions: [3]u32,
	bounds_min: [3]f32,
	bounds_max: [3]f32,
	voxel_size: f32,
	signed: bool,
}

Quantized_Distance_Field :: struct {
	samples: []i16,
	dimensions: [3]u32,
	bounds_min: [3]f32,
	bounds_max: [3]f32,
	voxel_size: f32,
	value_scale: f32,
	signed: bool,
}

@(private)
Native_Distance_Field :: struct {
	samples: [^]f32,
	sample_count: u32,
	dimensions: [3]u32,
	bounds_min: [3]f32,
	bounds_max: [3]f32,
	voxel_size: f32,
	signed_field: u32,
}

foreign import meshoptimizer "system:c"

foreign meshoptimizer {
	@(link_name = "scrapbot_distance_field_build")
	distance_field_build_native :: proc(positions: [^]f32, vertex_count, vertex_stride: c.size_t, indices: [^]u32, index_count: c.size_t, longest_axis_cells, padding_cells: u32) -> Native_Distance_Field ---

	@(link_name = "scrapbot_distance_field_free")
	distance_field_free_native :: proc(result: Native_Distance_Field) ---
}

build_distance_field :: proc(
	positions: rawptr,
	vertex_count, vertex_stride: int,
	indices: []u32,
	longest_axis_cells := DISTANCE_FIELD_DEFAULT_LONGEST_AXIS_CELLS,
	padding_cells := DISTANCE_FIELD_DEFAULT_PADDING_CELLS,
	allocator := context.allocator,
) -> (
	Distance_Field,
	string,
) {
	if positions == nil ||
	   vertex_count <= 0 ||
	   vertex_stride < 3 * size_of(f32) ||
	   len(indices) < 3 ||
	   len(indices) % 3 != 0 {
		return {}, "distance-field source geometry is empty or invalid"
	}
	if longest_axis_cells < 4 ||
	   longest_axis_cells > DISTANCE_FIELD_MAX_AXIS_CELLS ||
	   padding_cells > longest_axis_cells / 2 {
		return {}, "distance-field dimensions are outside supported bounds"
	}
	native := distance_field_build_native(
		cast([^]f32)positions,
		c.size_t(vertex_count),
		c.size_t(vertex_stride),
		raw_data(indices),
		c.size_t(len(indices)),
		longest_axis_cells,
		padding_cells,
	)
	defer distance_field_free_native(native)
	if native.samples == nil || native.sample_count == 0 {
		return {}, "failed to compile geometry distance field"
	}
	expected_count :=
		u64(native.dimensions[0]) * u64(native.dimensions[1]) * u64(native.dimensions[2])
	if expected_count != u64(native.sample_count) || !distance_field_descriptor_is_valid(native) {
		return {}, "compiled geometry distance field is invalid"
	}
	result := Distance_Field {
		samples = make([]f32, int(native.sample_count), allocator),
		dimensions = native.dimensions,
		bounds_min = native.bounds_min,
		bounds_max = native.bounds_max,
		voxel_size = native.voxel_size,
		signed = native.signed_field == 1,
	}
	copy(result.samples, native.samples[:int(native.sample_count)])
	return result, ""
}

@(private)
distance_field_descriptor_is_valid :: proc "contextless" (field: Native_Distance_Field) -> bool {
	if field.signed_field > 1 ||
	   math.is_nan(field.voxel_size) ||
	   math.is_inf(field.voxel_size) ||
	   field.voxel_size <= 0 {
		return false
	}
	for axis in 0 ..< 3 {
		if field.dimensions[axis] == 0 ||
		   field.dimensions[axis] > DISTANCE_FIELD_MAX_AXIS_CELLS ||
		   math.is_nan(field.bounds_min[axis]) ||
		   math.is_inf(field.bounds_min[axis]) ||
		   math.is_nan(field.bounds_max[axis]) ||
		   math.is_inf(field.bounds_max[axis]) ||
		   field.bounds_min[axis] >= field.bounds_max[axis] {
			return false
		}
	}
	return true
}

destroy_distance_field :: proc(field: ^Distance_Field, allocator := context.allocator) {
	if field == nil {
		return
	}
	delete(field.samples, allocator)
	field^ = {}
}

quantize_distance_field :: proc(
	field: ^Distance_Field,
	allocator := context.allocator,
) -> (
	Quantized_Distance_Field,
	string,
) {
	if field == nil || len(field.samples) == 0 || field.voxel_size <= 0 {
		return {}, "distance field is unavailable for quantization"
	}
	maximum := f32(0)
	for sample in field.samples {
		if math.is_nan(sample) || math.is_inf(sample) {
			return {}, "distance field contains a non-finite sample"
		}
		maximum = max(maximum, math.abs(sample))
	}
	if maximum <= 0 {
		return {}, "distance field has no representable range"
	}
	value_scale := maximum / f32(max(i16))
	result := Quantized_Distance_Field {
		samples = make([]i16, len(field.samples), allocator),
		dimensions = field.dimensions,
		bounds_min = field.bounds_min,
		bounds_max = field.bounds_max,
		voxel_size = field.voxel_size,
		value_scale = value_scale,
		signed = field.signed,
	}
	for sample, index in field.samples {
		quantized := math.round(sample / value_scale)
		result.samples[index] = i16(clamp(quantized, f32(min(i16)), f32(max(i16))))
	}
	return result, ""
}

destroy_quantized_distance_field :: proc(
	field: ^Quantized_Distance_Field,
	allocator := context.allocator,
) {
	if field == nil {
		return
	}
	delete(field.samples, allocator)
	field^ = {}
}

dequantize_distance_sample :: proc "contextless" (
	field: ^Quantized_Distance_Field,
	value: i16,
) -> f32 {
	if field == nil {
		return 0
	}
	return f32(value) * field.value_scale
}

distance_field_sample :: proc "contextless" (field: ^Distance_Field, x, y, z: u32) -> (f32, bool) {
	if field == nil ||
	   x >= field.dimensions[0] ||
	   y >= field.dimensions[1] ||
	   z >= field.dimensions[2] {
		return 0, false
	}
	index :=
		u64(x) +
		u64(y) * u64(field.dimensions[0]) +
		u64(z) * u64(field.dimensions[0]) * u64(field.dimensions[1])
	if index >= u64(len(field.samples)) {
		return 0, false
	}
	return field.samples[int(index)], true
}
