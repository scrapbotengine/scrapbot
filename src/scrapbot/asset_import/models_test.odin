package asset_import

import shared "../shared"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import cgltf "vendor:cgltf"

make_model_grid_primitive :: proc(size: int) -> Model_Primitive {
	primitive := Model_Primitive {
		material_index = -1,
	}
	for y in 0 ..= size {
		for x in 0 ..= size {
			append(
				&primitive.vertices,
				Model_Vertex {
					position = {f32(x), f32(y), 0},
					normal = {0, 0, 1},
					uv = {f32(x) / f32(size), f32(y) / f32(size)},
					tangent = {1, 0, 0, 1},
				},
			)
		}
	}
	row := size + 1
	for y in 0 ..< size {
		for x in 0 ..< size {
			a := u32(y * row + x)
			b := u32(y * row + x + 1)
			c := u32((y + 1) * row + x)
			d := u32((y + 1) * row + x + 1)
			append(&primitive.indices, a, b, c, b, d, c)
		}
	}
	return primitive
}

@(test)
test_model_offline_lods_are_deterministic_compact_and_round_trip :: proc(t: ^testing.T) {
	settings := shared.Project_Model_Resource {
		generate_lods = true,
		lod_ratios = {0.5, 0.25, 0.125},
		lod_screen_radii = {0.18, 0.07, 0.025},
		lod_count = 3,
	}
	primitive := make_model_grid_primitive(12)
	defer destroy_model_primitive(&primitive)
	build_model_primitive_lods(&primitive, settings)
	testing.expect_value(t, len(primitive.lods), 3)
	previous_index_count := len(primitive.indices)
	for lod, level in primitive.lods {
		testing.expect(t, len(lod.indices) < previous_index_count)
		testing.expect(t, len(lod.vertices) <= len(primitive.vertices))
		testing.expect_value(t, lod.screen_radius, settings.lod_screen_radii[level])
		testing.expect(t, lod.simplification_error >= 0)
		for index in lod.indices {
			testing.expect(t, int(index) < len(lod.vertices))
		}
		previous_index_count = len(lod.indices)
	}
	second := make_model_grid_primitive(12)
	defer destroy_model_primitive(&second)
	build_model_primitive_lods(&second, settings)
	testing.expect_value(t, len(second.lods), len(primitive.lods))
	for lod, level in primitive.lods {
		testing.expect_value(t, len(second.lods[level].indices), len(lod.indices))
		testing.expect_value(t, len(second.lods[level].vertices), len(lod.vertices))
		for element, index in lod.indices {
			testing.expect_value(t, second.lods[level].indices[index], element)
		}
		for vertex, vertex_index in lod.vertices {
			testing.expect_value(t, second.lods[level].vertices[vertex_index], vertex)
		}
	}
	hierarchy_err := build_model_primitive_hierarchies(&primitive)
	testing.expectf(t, hierarchy_err == "", "hierarchy build failed: %s", hierarchy_err)
	testing.expect(t, len(primitive.hierarchy.pages) > 0)
	pinned_pages := 0
	for page in primitive.hierarchy.pages {
		if page.pinned {
			pinned_pages += 1
		}
	}
	testing.expect(t, pinned_pages > 0)
	model: Model_Product
	mesh := Model_Mesh{}
	mesh.key, _ = strings.clone("mesh:grid")
	mesh.name, _ = strings.clone("Grid")
	primitive.key, _ = strings.clone("mesh:grid/primitive:default")
	append(&mesh.primitives, primitive)
	primitive = {}
	append(&model.meshes, mesh)
	defer destroy_model_product(&model)
	encoded := encode_model_product_for_test(&model)
	defer delete(encoded)
	root, temp_err := os.make_directory_temp("", "scrapbot-model-lods-*", context.allocator)
	testing.expect(t, temp_err == nil)
	if temp_err != nil {
		return
	}
	defer os.remove_all(root)
	defer delete(root)
	path, path_err := filepath.join({root, "grid.model.bin"})
	testing.expect(t, path_err == nil)
	if path_err != nil {
		return
	}
	defer delete(path)
	testing.expect(t, os.write_entire_file(path, encoded) == nil)
	product_file, open_err := os.open(path)
	testing.expect(t, open_err == nil)
	product_directory: Asset_Product_Directory
	if open_err == nil {
		directory_err: string
		product_directory, directory_err = read_asset_product_directory(
			product_file,
			len(encoded),
			.Model,
		)
		testing.expectf(
			t,
			directory_err == "",
			"split product directory failed: %s",
			directory_err,
		)
		os.close(product_file)
	}
	defer destroy_asset_product_directory(&product_directory)
	testing.expect_value(t, len(product_directory.chunks), MODEL_PRODUCT_CHUNK_COUNT)
	image_chunk, image_found := asset_product_find_chunk(
		&product_directory,
		.Model_Material_Images,
	)
	coarse_chunk, coarse_found := asset_product_find_chunk(
		&product_directory,
		.Model_Coarse_Geometry,
	)
	detail_chunk, detail_found := asset_product_find_chunk(
		&product_directory,
		.Model_Detail_Geometry,
	)
	catalog_chunk, catalog_found := asset_product_find_chunk(&product_directory, .Model_Catalog)
	testing.expect(t, image_found)
	testing.expect(t, coarse_found)
	testing.expect(t, detail_found)
	testing.expect(t, catalog_found)
	testing.expect(t, image_chunk.offset < coarse_chunk.offset)
	testing.expect(t, coarse_chunk.offset < detail_chunk.offset)
	testing.expect(t, detail_chunk.offset < catalog_chunk.offset)
	decoded, decode_err := read_model_product(path)
	defer destroy_model_product(&decoded)
	testing.expectf(t, decode_err == "", "LOD product round trip failed: %s", decode_err)
	if decode_err == "" {
		decoded_primitive := decoded.meshes[0].primitives[0]
		testing.expect_value(
			t,
			len(decoded_primitive.page_payloads),
			len(decoded_primitive.hierarchy.pages),
		)
		for record, page_index in decoded_primitive.page_payloads {
			expected_size :=
				u64(record.vertex_count) * u64(size_of(Model_Vertex)) +
				u64(record.index_count) * u64(size_of(u32))
			testing.expect_value(t, record.size, expected_size)
			testing.expect_value(
				t,
				record.index_count,
				decoded_primitive.hierarchy.pages[page_index].index_count,
			)
			testing.expect(t, record.offset + record.size <= u64(len(encoded)))
			expected_chunk := detail_chunk
			if decoded_primitive.hierarchy.pages[page_index].pinned {
				expected_chunk = coarse_chunk
			}
			testing.expect(t, model_chunk_contains(expected_chunk, record.offset, record.size))
		}
		testing.expect_value(
			t,
			len(decoded_primitive.hierarchy.pages),
			len(model.meshes[0].primitives[0].hierarchy.pages),
		)
		testing.expect_value(
			t,
			len(decoded_primitive.hierarchy.clusters),
			len(model.meshes[0].primitives[0].hierarchy.clusters),
		)
		testing.expect_value(t, len(decoded.meshes[0].primitives[0].lods), 3)
		decoded_lod := decoded.meshes[0].primitives[0].lods[2]
		source_lod := model.meshes[0].primitives[0].lods[2]
		testing.expect_value(t, decoded_lod.index_count, u32(len(source_lod.indices)))
		testing.expect_value(t, decoded_lod.vertex_count, u32(len(source_lod.vertices)))
		testing.expect_value(t, len(decoded_lod.query_positions), len(source_lod.vertices))
		for vertex, index in source_lod.vertices {
			testing.expect_value(t, decoded_lod.query_positions[index], vertex.position)
		}
		for lod in decoded_primitive.lods {
			testing.expect(t, len(lod.hierarchy.pages) > 0)
		}
	}
}

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
	testing.expect_value(t, product.cluster_count, 1)
	testing.expect_value(t, product.cluster_group_count, 1)
	testing.expect_value(t, product.cluster_page_count, 1)
	model, read_err := read_model_product(product.artifact_path)
	defer destroy_model_product(&model)
	testing.expectf(t, read_err == "", "model product read failed: %s", read_err)
	if read_err == "" {
		testing.expect_value(t, model.materials[0].name, "Coral")
		testing.expect_value(t, model.materials[0].base_color.x, f32(1))
		testing.expect_value(t, model.meshes[0].name, "Triangle Mesh")
		primitive := model.meshes[0].primitives[0]
		testing.expect_value(t, primitive.vertex_count, u32(3))
		testing.expect_value(t, primitive.index_count, u32(3))
		testing.expect_value(t, len(primitive.query_positions), 3)
		testing.expect_value(t, primitive.query_positions[0], shared.Vec3{0, 1, 0})
		testing.expect_value(t, len(primitive.hierarchy.clusters), 1)
		testing.expect_value(t, primitive.hierarchy.clusters[0].triangle_count, u32(1))
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
	declaration.model.generate_lods = true
	declaration.model.lod_ratios = {0.5, 0.25, 0.125}
	declaration.model.lod_screen_radii = {0.18, 0.07, 0.025}
	declaration.model.lod_count = 3
	settings_changed := ensure_project_imports(root, []shared.Project_Resource{declaration})
	defer destroy_report(&settings_changed)
	testing.expectf(
		t,
		settings_changed.err == "",
		"model LOD settings reimport failed: %s",
		settings_changed.err,
	)
	testing.expect_value(t, settings_changed.imported_count, 1)
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
	encoded := encode_model_product_for_test(&invalid_hierarchy)
	defer delete(encoded)
	testing.expect(t, os.write_entire_file(path, encoded) == nil)
	invalid, invalid_err := read_model_product(path)
	defer destroy_model_product(&invalid)
	testing.expect(t, invalid_err != "")
}

@(test)
test_model_reader_buffers_scalars_and_skips_payload_without_prefetch :: proc(t: ^testing.T) {
	root, temp_err := os.make_directory_temp("", "scrapbot-model-reader-*", context.allocator)
	testing.expect(t, temp_err == nil)
	if temp_err != nil {
		return
	}
	defer os.remove_all(root)
	defer delete(root)
	path, path_err := filepath.join({root, "buffered.bin"})
	testing.expect(t, path_err == nil)
	if path_err != nil {
		return
	}
	defer delete(path)
	bytes := make([]u8, MODEL_READER_BUFFER_SIZE * 4)
	defer delete(bytes)
	testing.expect(t, os.write_entire_file(path, bytes) == nil)
	file, open_err := os.open(path)
	testing.expect(t, open_err == nil)
	if open_err != nil {
		return
	}
	defer os.close(file)
	reader := Model_Reader {
		file = file,
		size = len(bytes),
	}
	for _ in 0 ..< 1024 {
		_, ok := model_read_u32(&reader)
		testing.expect(t, ok)
	}
	testing.expect_value(t, reader.read_operations, 1)
	testing.expect(t, model_skip_bytes(&reader, MODEL_READER_BUFFER_SIZE * 2))
	header: [12]u8
	testing.expect(t, model_read_exact_direct(&reader, header[:]))
	testing.expect_value(t, reader.read_operations, 2)
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
