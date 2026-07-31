package resources

import asset_import "../asset_import"
import shared "../shared"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_project_model_products_register_generated_meshes_and_materials :: proc(t: ^testing.T) {
	root, temp_err := os.make_directory_temp("", "scrapbot-model-registry-*", context.allocator)
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
	source, read_err := os.read_entire_file(
		"tests/fixtures/gltf/assets/triangle.gltf",
		context.temp_allocator,
	)
	testing.expect(t, read_err == nil)
	destination, destination_err := filepath.join({assets, "triangle.gltf"})
	testing.expect(t, destination_err == nil)
	defer delete(destination)
	testing.expect(t, os.write_entire_file(destination, source) == nil)
	id, valid := shared.resource_uuid_parse("a1000000-0000-4000-8000-000000000097")
	testing.expect(t, valid)
	declaration := shared.Project_Resource {
		id = id,
		kind = .Model,
		name = "Triangle",
		source = "triangle.resource.toml",
		model = {source = "assets/triangle.gltf"},
	}
	imports := asset_import.ensure_project_imports(root, []shared.Project_Resource{declaration})
	defer asset_import.destroy_report(&imports)
	testing.expectf(t, imports.err == "", "model import failed: %s", imports.err)
	registry: Registry
	defer destroy_registry(&registry)
	register_err := register_project_models(
		&registry,
		[]shared.Project_Resource{declaration},
		imports.products[:],
	)
	testing.expectf(t, register_err == "", "model registration failed: %s", register_err)
	handle, found := model_handle_by_uuid(&registry, id)
	testing.expect(t, found)
	model, alive := get_model(&registry, handle)
	testing.expect(t, alive)
	if !alive {
		return
	}
	testing.expect_value(t, model.asset_source, "assets/triangle.gltf")
	testing.expect_value(t, len(model.nodes), 1)
	testing.expect_value(t, len(model.meshes), 1)
	testing.expect_value(t, len(model.meshes[0].primitives), 1)
	geometry, geometry_alive := get_geometry(&registry, model.meshes[0].primitives[0].geometry)
	material, material_alive := get_material(&registry, model.meshes[0].primitives[0].material)
	testing.expect(t, geometry_alive)
	testing.expect(t, material_alive)
	if geometry_alive {
		testing.expect_value(t, len(geometry.vertices), 3)
		testing.expect_value(t, len(geometry.indices), 3)
	}
	if material_alive {
		testing.expect_value(t, material.desc.base_color.x, f32(1))
		testing.expect_value(t, material.desc.base_color.y, f32(0.25))
	}
	cloned: Registry
	defer destroy_registry(&cloned)
	testing.expect(t, clone_registry(&registry, &cloned) == "")
	cloned_model, cloned_alive := get_model(&cloned, handle)
	testing.expect(t, cloned_alive)
	if cloned_alive {
		testing.expect_value(t, cloned_model.meshes[0].name, "Triangle Mesh")
	}
	geometry_handle := model.meshes[0].primitives[0].geometry
	material_handle := model.meshes[0].primitives[0].material
	retire_err := register_project_models(&registry, nil, nil)
	testing.expectf(t, retire_err == "", "model retirement failed: %s", retire_err)
	_, model_still_alive := get_model(&registry, handle)
	_, geometry_still_alive := get_geometry(&registry, geometry_handle)
	_, material_still_alive := get_material(&registry, material_handle)
	testing.expect(t, !model_still_alive)
	testing.expect(t, !geometry_still_alive)
	testing.expect(t, !material_still_alive)
}

@(test)
test_project_model_registers_embedded_base_color_image_on_generated_material :: proc(
	t: ^testing.T,
) {
	root, temp_err := os.make_directory_temp(
		"",
		"scrapbot-textured-model-registry-*",
		context.allocator,
	)
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
	source, read_err := os.read_entire_file(
		"tests/fixtures/gltf/assets/textured-triangle.gltf",
		context.temp_allocator,
	)
	testing.expect(t, read_err == nil)
	destination, destination_err := filepath.join({assets, "textured-triangle.gltf"})
	testing.expect(t, destination_err == nil)
	defer delete(destination)
	testing.expect(t, os.write_entire_file(destination, source) == nil)
	id, valid := shared.resource_uuid_parse("a1000000-0000-4000-8000-000000000096")
	testing.expect(t, valid)
	declaration := shared.Project_Resource {
		id = id,
		kind = .Model,
		name = "Textured Triangle",
		source = "textured-triangle.resource.toml",
		model = {source = "assets/textured-triangle.gltf"},
	}
	imports := asset_import.ensure_project_imports(root, []shared.Project_Resource{declaration})
	defer asset_import.destroy_report(&imports)
	testing.expectf(t, imports.err == "", "textured model import failed: %s", imports.err)
	registry: Registry
	defer destroy_registry(&registry)
	register_err := register_project_models(
		&registry,
		[]shared.Project_Resource{declaration},
		imports.products[:],
	)
	testing.expectf(t, register_err == "", "textured model registration failed: %s", register_err)
	handle, found := model_handle_by_uuid(&registry, id)
	testing.expect(t, found)
	model, alive := get_model(&registry, handle)
	if !alive {
		return
	}
	material, material_alive := get_material(&registry, model.material_handles[0])
	testing.expect(t, material_alive)
	if material_alive {
		testing.expect_value(t, material.desc.alpha_mode, shared.Material_Alpha_Mode.Mask)
		testing.expect_value(t, material.desc.alpha_cutoff, f32(0.4))
		testing.expect(t, material.desc.double_sided)
		testing.expect_value(t, material.desc.texture_width, u32(8))
		testing.expect_value(t, material.desc.texture_height, u32(8))
		testing.expect_value(t, material.desc.texture_mip_count, u32(4))
		testing.expect_value(t, len(material.desc.texture_pixels), (8 * 8 + 4 * 4 + 2 * 2 + 1) * 4)
	}
}

make_semantic_reimport_product :: proc(
	reverse: bool,
	with_lods: bool = true,
) -> asset_import.Model_Product {
	product: asset_import.Model_Product
	material_keys := [?]string{"material:Red", "material:Blue"}
	mesh_keys := [?]string{"mesh:Body", "mesh:Trim"}
	for offset in 0 ..< 2 {
		index := offset
		if reverse {
			index = 1 - offset
		}
		key, _ := strings.clone(material_keys[index])
		name, _ := strings.clone(material_keys[index])
		append(
			&product.materials,
			asset_import.Model_Material {
				key = key,
				name = name,
				base_color = {1, 1, 1, 1},
				metallic_factor = 1,
				roughness_factor = 1,
				normal_scale = 1,
				occlusion_strength = 1,
			},
		)
	}
	for offset in 0 ..< 2 {
		index := offset
		if reverse {
			index = 1 - offset
		}
		mesh := asset_import.Model_Mesh{}
		mesh.key, _ = strings.clone(mesh_keys[index])
		mesh.name, _ = strings.clone(mesh_keys[index])
		primitive := asset_import.Model_Primitive {
			material_index = i32(offset),
		}
		primitive.key, _ = strings.clone(mesh_keys[index])
		append(&primitive.vertices, asset_import.Model_Vertex{position = {-1, -1, 0}})
		append(&primitive.vertices, asset_import.Model_Vertex{position = {1, -1, 0}})
		append(&primitive.vertices, asset_import.Model_Vertex{position = {-1, 1, 0}})
		append(&primitive.vertices, asset_import.Model_Vertex{position = {1, 1, 0}})
		append(&primitive.indices, 0, 1, 2, 1, 3, 2)
		if with_lods {
			lod := asset_import.Model_Primitive_LOD {
				screen_radius = 0.1,
				simplification_error = 0.01,
			}
			append(
				&lod.vertices,
				primitive.vertices[0],
				primitive.vertices[1],
				primitive.vertices[2],
			)
			append(&lod.indices, 0, 1, 2)
			append(&primitive.lods, lod)
		}
		_ = asset_import.build_model_primitive_hierarchies(&primitive)
		append(&mesh.primitives, primitive)
		append(&product.meshes, mesh)
	}
	return product
}

@(test)
test_model_reimport_preserves_generated_handles_across_source_reordering :: proc(t: ^testing.T) {
	id, valid := shared.resource_uuid_parse("a1000000-0000-4000-8000-000000000095")
	testing.expect(t, valid)
	declaration := shared.Project_Resource {
		id = id,
		kind = .Model,
		name = "Semantic Model",
		source = "semantic.resource.toml",
		model = {source = "assets/semantic.gltf"},
	}
	registry: Registry
	defer destroy_registry(&registry)
	first := make_semantic_reimport_product(false)
	defer asset_import.destroy_model_product(&first)
	handle, first_err := register_project_model(&registry, declaration, &first)
	testing.expectf(t, first_err == "", "first model registration failed: %s", first_err)
	first_model, first_alive := get_model(&registry, handle)
	testing.expect(t, first_alive)
	if !first_alive {
		return
	}
	red_material := first_model.material_handles[0]
	body_geometry := first_model.meshes[0].primitives[0].geometry
	body_lod := first_model.meshes[0].primitives[0].lod_geometries[0]
	body_resource, body_resource_alive := get_geometry(&registry, body_geometry)
	testing.expect(t, body_resource_alive)
	if body_resource_alive {
		testing.expect_value(t, body_resource.lod_count, 1)
		testing.expect_value(t, body_resource.lod_handles[0], body_lod)
		testing.expect_value(t, body_resource.lod_screen_radii[0], f32(0.1))
		testing.expect_value(t, body_resource.lod_simplification_errors[0], f32(0.01))
	}
	second := make_semantic_reimport_product(true)
	defer asset_import.destroy_model_product(&second)
	second_handle, second_err := register_project_model(&registry, declaration, &second)
	testing.expectf(t, second_err == "", "reordered model registration failed: %s", second_err)
	testing.expect_value(t, second_handle, handle)
	second_model, second_alive := get_model(&registry, second_handle)
	testing.expect(t, second_alive)
	if second_alive {
		testing.expect_value(t, second_model.material_handles[1], red_material)
		testing.expect_value(t, second_model.meshes[1].primitives[0].geometry, body_geometry)
		testing.expect_value(t, second_model.meshes[1].primitives[0].lod_geometries[0], body_lod)
	}
	_, red_alive := get_material(&registry, red_material)
	_, body_alive := get_geometry(&registry, body_geometry)
	testing.expect(t, red_alive)
	testing.expect(t, body_alive)
	_, body_lod_alive := get_geometry(&registry, body_lod)
	testing.expect(t, body_lod_alive)
	without_lods := make_semantic_reimport_product(true, false)
	defer asset_import.destroy_model_product(&without_lods)
	third_handle, third_err := register_project_model(&registry, declaration, &without_lods)
	testing.expectf(t, third_err == "", "LOD-removing model registration failed: %s", third_err)
	testing.expect_value(t, third_handle, handle)
	third_model, third_alive := get_model(&registry, third_handle)
	testing.expect(t, third_alive)
	if third_alive {
		testing.expect_value(t, third_model.meshes[1].primitives[0].geometry, body_geometry)
		testing.expect_value(t, third_model.meshes[1].primitives[0].lod_count, 0)
	}
	_, retired_lod_alive := get_geometry(&registry, body_lod)
	testing.expect(t, !retired_lod_alive)
}
