package resources

import asset_import "../asset_import"
import shared "../shared"
import "core:os"
import "core:path/filepath"
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
