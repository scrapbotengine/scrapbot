package asset_import

import shared "../shared"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:testing"

model_test_declaration :: proc() -> shared.Project_Resource {
	id, _ := shared.resource_uuid_parse("a1000000-0000-4000-8000-000000000098")
	return {id = id, kind = .Model, name = "Triangle", model = {source = "assets/triangle.gltf"}}
}

make_model_test_project :: proc(t: ^testing.T) -> string {
	root, temp_err := os.make_directory_temp("", "scrapbot-model-import-*", context.allocator)
	testing.expect(t, temp_err == nil)
	assets, join_err := filepath.join({root, "assets"})
	testing.expect(t, join_err == nil)
	defer delete(assets)
	testing.expect(t, os.make_directory_all(assets) == nil)
	source, read_err := os.read_entire_file(
		"tests/fixtures/gltf/assets/triangle.gltf",
		context.temp_allocator,
	)
	testing.expect(t, read_err == nil)
	destination, destination_err := filepath.join({assets, "triangle.gltf"})
	testing.expect(t, destination_err == nil)
	defer delete(destination)
	testing.expect(t, os.write_entire_file(destination, source) == nil)
	return root
}

@(test)
test_static_gltf_import_is_incremental_and_round_trips_product :: proc(t: ^testing.T) {
	declaration := model_test_declaration()
	root := make_model_test_project(t)
	defer os.remove_all(root)
	defer delete(root)
	first := ensure_project_imports(root, []shared.Project_Resource{declaration})
	defer destroy_report(&first)
	testing.expectf(t, first.err == "", "model import failed: %s", first.err)
	testing.expect_value(t, first.imported_count, 1)
	testing.expect_value(t, len(first.products), 1)
	if len(first.products) != 1 {
		return
	}
	product := first.products[0]
	testing.expect_value(t, product.node_count, 1)
	testing.expect_value(t, product.mesh_count, 1)
	testing.expect_value(t, product.primitive_count, 1)
	testing.expect_value(t, product.vertex_count, 3)
	testing.expect_value(t, product.index_count, 3)
	testing.expect_value(t, product.material_count, 1)
	model, read_err := read_model_product(product.artifact_path)
	defer destroy_model_product(&model)
	testing.expectf(t, read_err == "", "model product read failed: %s", read_err)
	if read_err == "" {
		testing.expect_value(t, model.materials[0].name, "Coral")
		testing.expect_value(t, model.materials[0].base_color.x, f32(1))
		testing.expect_value(t, model.meshes[0].name, "Triangle Mesh")
		primitive := model.meshes[0].primitives[0]
		testing.expect(t, len(primitive.indices) == 3)
		if len(primitive.indices) == 3 {
			testing.expect_value(t, primitive.indices[0], u32(0))
			testing.expect_value(t, primitive.indices[1], u32(1))
			testing.expect_value(t, primitive.indices[2], u32(2))
		}
		testing.expect(t, math.abs(primitive.vertices[0].normal.z - 1) < 0.0001)
		testing.expect_value(t, model.nodes[0].name, "Triangle Node")
		testing.expect_value(t, model.nodes[0].mesh_index, i32(0))
		testing.expect_value(t, model.nodes[0].transform.position.x, f32(1))
		testing.expect_value(t, model.nodes[0].transform.position.y, f32(2))
		testing.expect_value(t, model.nodes[0].transform.position.z, f32(3))
	}
	second := ensure_project_imports(root, []shared.Project_Resource{declaration})
	defer destroy_report(&second)
	testing.expectf(t, second.err == "", "cached model import failed: %s", second.err)
	testing.expect_value(t, second.cached_count, 1)
}

@(test)
test_model_product_reader_rejects_corruption :: proc(t: ^testing.T) {
	root, temp_err := os.make_directory_temp("", "scrapbot-model-product-*", context.allocator)
	testing.expect(t, temp_err == nil)
	defer os.remove_all(root)
	defer delete(root)
	path, join_err := filepath.join({root, "broken.model.bin"})
	testing.expect(t, join_err == nil)
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, "SBMODEL1") == nil)
	model, read_err := read_model_product(path)
	defer destroy_model_product(&model)
	testing.expect(t, read_err != "")
	invalid_hierarchy: Model_Product
	defer delete(invalid_hierarchy.nodes)
	append(
		&invalid_hierarchy.nodes,
		Model_Node {
			name = "Loop",
			parent_index = 0,
			mesh_index = -1,
			transform = {scale = {1, 1, 1}},
		},
	)
	encoded := encode_model_product(&invalid_hierarchy)
	defer delete(encoded)
	testing.expect(t, os.write_entire_file(path, encoded) == nil)
	invalid, invalid_err := read_model_product(path)
	defer destroy_model_product(&invalid)
	testing.expect(t, invalid_err != "")
}

@(test)
test_gltf_import_rejects_external_buffers_outside_asset_directory :: proc(t: ^testing.T) {
	root, temp_err := os.make_directory_temp("", "scrapbot-model-path-*", context.allocator)
	testing.expect(t, temp_err == nil)
	if temp_err != nil {
		return
	}
	defer os.remove_all(root)
	defer delete(root)
	assets, join_err := filepath.join({root, "assets"})
	testing.expect(t, join_err == nil)
	defer delete(assets)
	testing.expect(t, os.make_directory_all(assets) == nil)
	source_path, source_err := filepath.join({assets, "triangle.gltf"})
	testing.expect(t, source_err == nil)
	defer delete(source_path)
	testing.expect(
		t,
		os.write_entire_file(
			source_path,
			`{"asset":{"version":"2.0"},"buffers":[{"byteLength":4,"uri":"../../secret.bin"}]}`,
		) ==
		nil,
	)
	declaration := model_test_declaration()
	report := ensure_project_imports(root, []shared.Project_Resource{declaration})
	defer destroy_report(&report)
	testing.expect(t, report.err != "")
}
