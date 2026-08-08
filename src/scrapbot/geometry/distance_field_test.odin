package geometry

import "core:testing"

Distance_Field_Test_Vertex :: struct {
	position: [3]f32,
}

@(test)
test_distance_field_compiles_signed_closed_geometry :: proc(t: ^testing.T) {
	vertices := []Distance_Field_Test_Vertex {
		{{-1, -1, -1}},
		{{1, -1, -1}},
		{{1, 1, -1}},
		{{-1, 1, -1}},
		{{-1, -1, 1}},
		{{1, -1, 1}},
		{{1, 1, 1}},
		{{-1, 1, 1}},
	}
	indices := []u32 {
		0,
		2,
		1,
		0,
		3,
		2,
		4,
		5,
		6,
		4,
		6,
		7,
		0,
		1,
		5,
		0,
		5,
		4,
		1,
		2,
		6,
		1,
		6,
		5,
		2,
		3,
		7,
		2,
		7,
		6,
		3,
		0,
		4,
		3,
		4,
		7,
	}
	field, err := build_distance_field(
		raw_data(vertices),
		len(vertices),
		size_of(vertices[0]),
		indices,
		16,
		2,
	)
	defer destroy_distance_field(&field)
	testing.expect_value(t, err, "")
	testing.expect(t, field.signed)
	testing.expect_value(t, field.dimensions, [3]u32{20, 20, 20})
	testing.expect_value(t, len(field.samples), 8_000)
	center, center_ok := distance_field_sample(&field, 10, 10, 10)
	testing.expect(t, center_ok)
	testing.expect(t, center < -0.8)
	outside, outside_ok := distance_field_sample(&field, 0, 0, 0)
	testing.expect(t, outside_ok)
	testing.expect(t, outside > 0)
}

@(test)
test_distance_field_keeps_open_geometry_unsigned :: proc(t: ^testing.T) {
	vertices := []Distance_Field_Test_Vertex {
		{{-1, 0, -1}},
		{{1, 0, -1}},
		{{1, 0, 1}},
		{{-1, 0, 1}},
	}
	indices := []u32{0, 1, 2, 0, 2, 3}
	field, err := build_distance_field(
		raw_data(vertices),
		len(vertices),
		size_of(vertices[0]),
		indices,
		8,
		2,
	)
	defer destroy_distance_field(&field)
	testing.expect_value(t, err, "")
	testing.expect(t, !field.signed)
	for sample in field.samples {
		testing.expect(t, sample >= 0)
	}
}

@(test)
test_distance_field_rejects_invalid_sources_and_coordinates :: proc(t: ^testing.T) {
	field, err := build_distance_field(nil, 0, 0, nil)
	testing.expect(t, err != "")
	_, ok := distance_field_sample(&field, 0, 0, 0)
	testing.expect(t, !ok)
}
