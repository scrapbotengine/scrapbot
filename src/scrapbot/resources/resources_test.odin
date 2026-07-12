package resources

import "core:testing"

@(test)
test_cube_is_full_indexed_geometry :: proc(t: ^testing.T) {
	desc, err := cube(2)
	defer delete(desc.vertices); defer delete(desc.indices)
	testing.expect(t, err == "")
	testing.expect(t, len(desc.vertices) == 24)
	testing.expect(t, len(desc.indices) == 36)
	testing.expect(t, calculate_bounds(desc.vertices).min.x == -1)
	testing.expect(t, validate_geometry(desc) == "")
}

@(test)
test_named_geometry_updates_share_a_stable_handle :: proc(t: ^testing.T) {
	registry: Registry; defer destroy_registry(&registry)
	first, _ := cube(1); defer delete(first.vertices); defer delete(first.indices)
	handle, err := register_geometry(&registry, "cube", first)
	testing.expect(t, err == "")
	second, _ := cube(2); defer delete(second.vertices); defer delete(second.indices)
	updated, update_err := register_geometry(&registry, "cube", second)
	testing.expect(t, update_err == "")
	testing.expect(t, updated == handle)
	geometry, ok := get_geometry(&registry, handle)
	testing.expect(t, ok)
	testing.expect(t, geometry.version == 2)
	testing.expect(t, geometry.bounds.max.x == 1)
}

@(test)
test_geometry_validation_rejects_invalid_indices :: proc(t: ^testing.T) {
	desc, _ := plane()
	defer delete(desc.vertices); defer delete(desc.indices)
	desc.indices[0] = 99
	testing.expect(t, validate_geometry(desc) == "geometry index is outside the vertex array")
}

@(test)
test_generated_primitives_are_valid_indexed_geometry :: proc(t: ^testing.T) {
	descriptions := [4]Geometry_Desc{}
	errors := [4]string{}
	descriptions[0], errors[0] = icosphere(1, 1)
	descriptions[1], errors[1] = sphere(1, 12, 8)
	descriptions[2], errors[2] = pyramid(2, 3, 2)
	descriptions[3], errors[3] = cylinder(1, 2, 12)
	for desc, i in descriptions {
		defer delete(desc.vertices); defer delete(desc.indices)
		testing.expect(t, errors[i] == "")
		testing.expect(t, validate_geometry(desc) == "")
	}
	testing.expect(t, len(descriptions[0].indices) == 240)
	testing.expect(t, len(descriptions[1].indices) == 504)
	testing.expect(t, len(descriptions[2].indices) == 18)
	testing.expect(t, len(descriptions[3].indices) == 144)
}

@(test)
test_generated_primitives_reject_invalid_tessellation :: proc(t: ^testing.T) {
	_, sphere_err := sphere(1, 2, 8)
	_, cylinder_err := cylinder(1, 1, 257)
	_, ico_err := icosphere(1, 5)
	testing.expect(t, sphere_err != "")
	testing.expect(t, cylinder_err != "")
	testing.expect(t, ico_err != "")
}
