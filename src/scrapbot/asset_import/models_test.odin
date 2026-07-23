package asset_import

import shared "../shared"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import cgltf "vendor:cgltf"

model_test_declaration :: proc() -> shared.Project_Resource {
	id, _ := shared.resource_uuid_parse("a1000000-0000-4000-8000-000000000098")
	return {id = id, kind = .Model, name = "Triangle", model = {source = "assets/triangle.gltf"}}
}

make_named_model_test_project :: proc(t: ^testing.T, fixture, destination_name: string) -> string {
	root, temp_err := os.make_directory_temp("", "scrapbot-model-import-*", context.allocator)
	testing.expect(t, temp_err == nil)
	assets, join_err := filepath.join({root, "assets"})
	testing.expect(t, join_err == nil)
	defer delete(assets)
	testing.expect(t, os.make_directory_all(assets) == nil)
	source, read_err := os.read_entire_file(fixture, context.temp_allocator)
	testing.expect(t, read_err == nil)
	destination, destination_err := filepath.join({assets, destination_name})
	testing.expect(t, destination_err == nil)
	defer delete(destination)
	testing.expect(t, os.write_entire_file(destination, source) == nil)
	return root
}

make_model_test_project :: proc(t: ^testing.T) -> string {
	return make_named_model_test_project(
		t,
		"tests/fixtures/gltf/assets/triangle.gltf",
		"triangle.gltf",
	)
}

@(test)
test_external_model_image_does_not_take_ownership_of_source_directory :: proc(t: ^testing.T) {
	root, temp_err := os.make_directory_temp("", "scrapbot-model-image-*", context.allocator)
	testing.expect(t, temp_err == nil)
	if temp_err != nil {
		return
	}
	defer os.remove_all(root)
	defer delete(root)
	source_path, source_err := filepath.join({root, "model.gltf"})
	testing.expect(t, source_err == nil)
	if source_err != nil {
		return
	}
	defer delete(source_path)
	image_path, image_path_err := filepath.join({root, "pixel.bin"})
	testing.expect(t, image_path_err == nil)
	if image_path_err != nil {
		return
	}
	defer delete(image_path)
	testing.expect(t, os.write_entire_file(image_path, []u8{1, 2, 3, 4}) == nil)
	uri, uri_err := strings.clone_to_cstring("pixel.bin", context.temp_allocator)
	testing.expect(t, uri_err == nil)
	if uri_err != nil {
		return
	}
	image := cgltf.image {
		uri = uri,
	}
	bytes, load_err := load_model_image_bytes(&image, source_path)
	defer delete(bytes)
	testing.expectf(t, load_err == "", "external image load failed: %s", load_err)
	testing.expect_value(t, len(bytes), 4)
	if len(bytes) == 4 {
		testing.expect(t, bytes[0] == 1 && bytes[1] == 2 && bytes[2] == 3 && bytes[3] == 4)
	}
}

@(test)
test_gltf_import_decodes_embedded_base_color_image :: proc(t: ^testing.T) {
	declaration := model_test_declaration()
	declaration.model.source = "assets/textured-triangle.gltf"
	root := make_named_model_test_project(
		t,
		"tests/fixtures/gltf/assets/textured-triangle.gltf",
		"textured-triangle.gltf",
	)
	defer os.remove_all(root)
	defer delete(root)
	report := ensure_project_imports(root, []shared.Project_Resource{declaration})
	defer destroy_report(&report)
	testing.expectf(t, report.err == "", "textured model import failed: %s", report.err)
	if report.err != "" || len(report.products) != 1 {
		return
	}
	model, read_err := read_model_product(report.products[0].artifact_path)
	defer destroy_model_product(&model)
	testing.expectf(t, read_err == "", "textured model product read failed: %s", read_err)
	if read_err != "" || len(model.materials) != 1 {
		return
	}
	material := model.materials[0]
	testing.expect_value(t, material.alpha_mode, shared.Material_Alpha_Mode.Mask)
	testing.expect_value(t, material.alpha_cutoff, f32(0.4))
	testing.expect(t, material.double_sided)
	testing.expect_value(t, material.base_color_image.width, u32(8))
	testing.expect_value(t, material.base_color_image.height, u32(8))
	testing.expect_value(t, material.base_color_image.mip_count, u32(4))
	testing.expect_value(
		t,
		material.base_color_image.sampler.mag_filter,
		shared.Texture_Filter.Nearest,
	)
	testing.expect_value(
		t,
		material.base_color_image.sampler.min_filter,
		shared.Texture_Filter.Linear,
	)
	testing.expect_value(
		t,
		material.base_color_image.sampler.mipmap_filter,
		shared.Texture_Mipmap_Filter.Nearest,
	)
	testing.expect_value(
		t,
		material.base_color_image.sampler.address_u,
		shared.Texture_Address_Mode.Clamp_To_Edge,
	)
	testing.expect_value(
		t,
		material.base_color_image.sampler.address_v,
		shared.Texture_Address_Mode.Mirrored_Repeat,
	)
	testing.expect_value(t, len(material.base_color_image.pixels), (8 * 8 + 4 * 4 + 2 * 2 + 1) * 4)
	testing.expect_value(t, material.base_color.x, f32(0.5))
}

@(test)
test_gltf_import_ignores_unsupported_materials_outside_selected_scene :: proc(t: ^testing.T) {
	declaration := model_test_declaration()
	root := make_named_model_test_project(
		t,
		"tests/fixtures/gltf/assets/triangle.gltf",
		"triangle.gltf",
	)
	defer os.remove_all(root)
	defer delete(root)
	path, join_err := filepath.join({root, "assets/triangle.gltf"})
	testing.expect(t, join_err == nil)
	defer delete(path)
	testing.expect(
		t,
		os.write_entire_file(
			path,
			`{"asset":{"version":"2.0"},"materials":[{"alphaMode":"BLEND"}]}`,
		) ==
		nil,
	)
	report := ensure_project_imports(root, []shared.Project_Resource{declaration})
	defer destroy_report(&report)
	testing.expectf(t, report.err == "", "unreferenced material should be ignored: %s", report.err)
}

@(test)
test_gltf_import_only_contains_selected_scene_reachable_resources :: proc(t: ^testing.T) {
	declaration := model_test_declaration()
	root := make_model_test_project(t)
	defer os.remove_all(root)
	defer delete(root)
	path, join_err := filepath.join({root, "assets/triangle.gltf"})
	testing.expect(t, join_err == nil)
	defer delete(path)
	fixture := `{
  "asset":{"version":"2.0"},
  "scene":1,
  "scenes":[{"nodes":[0]},{"nodes":[1]}],
  "nodes":[{"name":"Unused Node","mesh":0},{"name":"Selected Node","mesh":1}],
  "meshes":[
    {"name":"Unused Mesh","primitives":[{"attributes":{"POSITION":0},"indices":1,"material":0}]},
    {"name":"Selected Mesh","primitives":[{"attributes":{"POSITION":0},"indices":1,"material":1}]}
  ],
  "materials":[
    {"name":"Unused Material","alphaMode":"BLEND"},
    {"name":"Selected Material"}
  ],
  "buffers":[{"byteLength":42,"uri":"data:application/octet-stream;base64,AAAAAAAAgD8AAAAAAACAvwAAgL8AAAAAAACAPwAAgL8AAAAAAAABAAIA"}],
  "bufferViews":[
    {"buffer":0,"byteOffset":0,"byteLength":36,"target":34962},
    {"buffer":0,"byteOffset":36,"byteLength":6,"target":34963}
  ],
  "accessors":[
    {"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},
    {"bufferView":1,"componentType":5123,"count":3,"type":"SCALAR"}
  ]
}`
	testing.expect(t, os.write_entire_file(path, fixture) == nil)
	report := ensure_project_imports(root, []shared.Project_Resource{declaration})
	defer destroy_report(&report)
	testing.expectf(t, report.err == "", "selected-scene import failed: %s", report.err)
	if report.err != "" || len(report.products) != 1 {
		return
	}
	testing.expect_value(t, report.products[0].node_count, 1)
	testing.expect_value(t, report.products[0].mesh_count, 1)
	testing.expect_value(t, report.products[0].material_count, 1)
	model, read_err := read_model_product(report.products[0].artifact_path)
	defer destroy_model_product(&model)
	testing.expectf(t, read_err == "", "selected-scene product read failed: %s", read_err)
	if read_err == "" {
		testing.expect_value(t, model.nodes[0].key, "node:Selected Node")
		testing.expect_value(t, model.meshes[0].key, "mesh:Selected Mesh")
		testing.expect_value(t, model.materials[0].key, "material:Selected Material")
		testing.expect_value(t, model.meshes[0].primitives[0].material_index, i32(0))
	}
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

@(test)
test_gltf_import_rejects_external_images_outside_asset_directory :: proc(t: ^testing.T) {
	root, temp_err := os.make_directory_temp("", "scrapbot-model-image-path-*", context.allocator)
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
			`{"asset":{"version":"2.0"},"images":[{"uri":"../../secret.png"}]}`,
		) ==
		nil,
	)
	declaration := model_test_declaration()
	report := ensure_project_imports(root, []shared.Project_Resource{declaration})
	defer destroy_report(&report)
	testing.expect(t, report.err != "")
}
