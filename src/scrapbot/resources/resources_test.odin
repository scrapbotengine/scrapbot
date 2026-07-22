package resources

import project "../project"
import shared "../shared"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_clone_registry_preserves_owned_resource_state_independently :: proc(t: ^testing.T) {
	source: Registry
	defer destroy_registry(&source)
	description, description_err := cube()
	defer delete(description.vertices)
	defer delete(description.indices)
	testing.expect(t, description_err == "")
	geometry, geometry_err := register_geometry(&source, "cube", description)
	material, material_err := register_material(
		&source,
		"material",
		{base_color = {0.2, 0.3, 0.4, 1}},
	)
	testing.expect(t, geometry_err == "" && material_err == "")

	cloned: Registry
	defer destroy_registry(&cloned)
	testing.expect(t, clone_registry(&source, &cloned) == "")
	cloned_geometry, geometry_alive := get_geometry(&cloned, geometry)
	cloned_material, material_alive := get_material(&cloned, material)
	testing.expect(t, geometry_alive && material_alive)
	if geometry_alive && material_alive {
		cloned_geometry.vertices[0].position.x = 42
		cloned_material.desc.base_color.x = 0.9
	}
	source_geometry, _ := get_geometry(&source, geometry)
	source_material, _ := get_material(&source, material)
	testing.expect(t, source_geometry.vertices[0].position.x != 42)
	testing.expect_value(t, source_material.desc.base_color.x, f32(0.2))
}

@(test)
test_project_material_save_writes_only_its_standalone_resource :: proc(t: ^testing.T) {
	root, temp_err := os.make_directory_temp(
		"",
		"scrapbot-resource-save-*",
		context.temp_allocator,
	)
	testing.expect(t, temp_err == nil)
	if temp_err != nil {
		return
	}
	defer os.remove_all(root)
	resources_dir, _ := filepath.join({root, shared.PROJECT_RESOURCES_DIR})
	defer delete(resources_dir)
	testing.expect(t, os.make_directory_all(resources_dir) == nil)
	resource_path, _ := filepath.join({resources_dir, "editable.resource.toml"})
	defer delete(resource_path)
	testing.expect(t, os.write_entire_file(resource_path, "untouched") == nil)
	registry: Registry
	defer destroy_registry(&registry)
	id, valid := shared.resource_uuid_parse("a2000000-0000-4000-8000-000000000002")
	testing.expect(t, valid)
	_, register_err := register_project_material(
		&registry,
		id,
		"Editable",
		"editable.resource.toml",
		{base_color = {0.25, 0.5, 0.75, 1}, emissive = {4, 2, 1}},
	)
	testing.expect(t, register_err == "")
	testing.expect(t, save_project_materials(&registry, root, []shared.Resource_UUID{id}) == "")
	bytes, read_err := os.read_entire_file(resource_path, context.temp_allocator)
	testing.expect(t, read_err == nil)
	if read_err == nil {
		text := string(bytes)
		testing.expect(t, len(text) > len("untouched"))
		testing.expect(t, text != "untouched")
	}
}

@(test)
test_project_material_save_rejects_changed_serialized_meaning_before_disk_write :: proc(
	t: ^testing.T,
) {
	root, temp_err := os.make_directory_temp(
		"",
		"scrapbot-resource-save-validation-*",
		context.temp_allocator,
	)
	testing.expect(t, temp_err == nil)
	if temp_err != nil {
		return
	}
	defer os.remove_all(root)
	resources_dir, _ := filepath.join({root, shared.PROJECT_RESOURCES_DIR})
	defer delete(resources_dir)
	testing.expect(t, os.make_directory_all(resources_dir) == nil)
	resource_path, _ := filepath.join({resources_dir, "invalid.resource.toml"})
	defer delete(resource_path)
	testing.expect(t, os.write_entire_file(resource_path, "last valid resource\n") == nil)
	registry: Registry
	defer destroy_registry(&registry)
	id, valid := shared.resource_uuid_parse("a2000000-0000-4000-8000-000000000012")
	testing.expect(t, valid)
	_, register_err := register_project_material(
		&registry,
		id,
		`Invalid " Name`,
		"invalid.resource.toml",
		{base_color = {1, 1, 1, 1}},
	)
	testing.expect(t, register_err == "")
	testing.expect(t, save_project_materials(&registry, root, []shared.Resource_UUID{id}) != "")
	bytes, read_err := os.read_entire_file(resource_path, context.temp_allocator)
	testing.expect(t, read_err == nil)
	if read_err == nil {
		testing.expect_value(t, string(bytes), "last valid resource\n")
	}
}

@(test)
test_project_material_save_derives_create_move_and_delete_deltas_from_uuid :: proc(t: ^testing.T) {
	root, temp_err := os.make_directory_temp(
		"",
		"scrapbot-resource-lifecycle-*",
		context.temp_allocator,
	)
	testing.expect(t, temp_err == nil)
	if temp_err != nil {
		return
	}
	defer os.remove_all(root)
	resources_dir, _ := filepath.join({root, shared.PROJECT_RESOURCES_DIR})
	defer delete(resources_dir)
	testing.expect(t, os.make_directory_all(resources_dir) == nil)
	id, valid := shared.resource_uuid_parse("a2000000-0000-4000-8000-000000000022")
	testing.expect(t, valid)
	old_path, _ := filepath.join({resources_dir, "old.resource.toml"})
	defer delete(old_path)
	old_source := `id = "a2000000-0000-4000-8000-000000000022"
type = "scrapbot.material"
name = "Lifecycle"

[material]
base_color = [1, 1, 1, 1]
emissive = [0, 0, 0]
`
	testing.expect(t, os.write_entire_file(old_path, old_source) == nil)
	registry: Registry
	defer destroy_registry(&registry)
	_, register_err := register_project_material(
		&registry,
		id,
		"Lifecycle",
		"old.resource.toml",
		{base_color = {1, 1, 1, 1}},
	)
	testing.expect(t, register_err == "")
	before, captured := capture_project_material(&registry, id)
	testing.expect(t, captured)
	defer {
		destroy_project_material_snapshot(before)
		free(before)
	}
	moved := clone_project_material_snapshot(before)
	delete(moved.source)
	moved.source, _ = strings.clone("nested/moved.resource.toml")
	testing.expect(t, apply_project_material_snapshot(&registry, id, moved) == "")
	destroy_project_material_snapshot(moved)
	free(moved)
	files: [dynamic]project.Save_File
	testing.expect(
		t,
		prepare_project_material_save_files(&registry, root, []shared.Resource_UUID{id}, &files) ==
		"",
	)
	testing.expect_value(t, len(files), 2)
	testing.expect(t, files[0].action == .Delete)
	testing.expect(t, files[1].action == .Write && files[1].expect_missing)
	move_result := project.commit_project_save(root, files[:])
	testing.expectf(t, move_result == "", "resource move failed: %s", move_result)
	project.destroy_owned_save_files(&files)
	moved_path, _ := filepath.join({resources_dir, "nested", "moved.resource.toml"})
	defer delete(moved_path)
	testing.expect(t, !os.exists(old_path) && os.exists(moved_path))
	loaded, load_err := project.load_project_resources(root)
	testing.expectf(t, load_err == "", "moved resource did not reload: %s", load_err)
	if len(loaded) == 1 {
		testing.expect_value(t, loaded[0].source, "nested/moved.resource.toml")
	}
	project.destroy_project_resources(&loaded)

	testing.expect(t, apply_project_material_snapshot(&registry, id, nil) == "")
	testing.expect(
		t,
		prepare_project_material_save_files(&registry, root, []shared.Resource_UUID{id}, &files) ==
		"",
	)
	testing.expect_value(t, len(files), 1)
	testing.expect(t, files[0].action == .Delete)
	testing.expectf(
		t,
		files[0].path == moved_path,
		"deletion targeted %s instead of %s",
		files[0].path,
		moved_path,
	)
	delete_result := project.commit_project_save(root, files[:])
	testing.expectf(t, delete_result == "", "resource deletion failed: %s", delete_result)
	project.destroy_owned_save_files(&files)
	testing.expect(t, !os.exists(moved_path))

	created := clone_project_material_snapshot(before)
	created.id = shared.resource_uuid_generate()
	delete(created.name)
	delete(created.source)
	created.name, _ = strings.clone("Created")
	created.source, _ = strings.clone("created.resource.toml")
	testing.expect(t, apply_project_material_snapshot(&registry, created.id, created) == "")
	testing.expect(
		t,
		prepare_project_material_save_files(
			&registry,
			root,
			[]shared.Resource_UUID{created.id},
			&files,
		) ==
		"",
	)
	testing.expect_value(t, len(files), 1)
	testing.expect(t, files[0].action == .Write && files[0].expect_missing)
	project.destroy_owned_save_files(&files)
	destroy_project_material_snapshot(created)
	free(created)
}

@(test)
test_project_material_uuid_updates_preserve_runtime_handle :: proc(t: ^testing.T) {
	registry: Registry
	defer destroy_registry(&registry)
	id, valid := shared.resource_uuid_parse("a2000000-0000-4000-8000-000000000001")
	testing.expect(t, valid)
	first, first_err := register_project_material(
		&registry,
		id,
		"First Name",
		"first.resource.toml",
		{base_color = {1, 0, 0, 1}},
	)
	second, second_err := register_project_material(
		&registry,
		id,
		"Renamed",
		"moved.resource.toml",
		{base_color = {0, 1, 0, 1}},
	)
	testing.expect(t, first_err == "" && second_err == "")
	testing.expect_value(t, second, first)
	by_id, found := material_by_uuid(&registry, id)
	testing.expect(t, found)
	testing.expect_value(t, by_id, first)
	material, alive := get_material(&registry, first)
	testing.expect(t, alive)
	if alive {
		testing.expect_value(t, material.name, "Renamed")
		testing.expect_value(t, material.source, "moved.resource.toml")
		testing.expect_value(t, material.version, u32(2))
	}
}

@(test)
test_project_material_uuid_reuses_slot_after_disappearing_and_reappearing :: proc(t: ^testing.T) {
	registry: Registry
	defer destroy_registry(&registry)
	id, valid := shared.resource_uuid_parse("a2000000-0000-4000-8000-000000000003")
	testing.expect(t, valid)
	first, first_err := register_project_material(
		&registry,
		id,
		"Transient",
		"transient.resource.toml",
		{base_color = {1, 0, 0, 1}},
	)
	testing.expect(t, first_err == "")
	testing.expect(t, register_project_materials(&registry, "", nil) == "")
	_, old_alive := get_material(&registry, first)
	testing.expect(t, !old_alive)

	revived, revived_err := register_project_material(
		&registry,
		id,
		"Revived",
		"revived.resource.toml",
		{base_color = {0, 1, 0, 1}},
	)
	testing.expect(t, revived_err == "")
	testing.expect_value(t, revived.index, first.index)
	testing.expect(t, revived.generation != first.generation)
	material, alive := get_material(&registry, revived)
	testing.expect(t, alive)
	if alive {
		testing.expect_value(t, material.name, "Revived")
	}
}

@(test)
test_project_material_batch_validation_does_not_partially_apply :: proc(t: ^testing.T) {
	registry: Registry
	defer destroy_registry(&registry)
	_, runtime_err := register_material(&registry, "Reserved", {base_color = {1, 1, 1, 1}})
	testing.expect(t, runtime_err == "")
	first_id, first_valid := shared.resource_uuid_parse("a2000000-0000-4000-8000-000000000004")
	second_id, second_valid := shared.resource_uuid_parse("a2000000-0000-4000-8000-000000000005")
	testing.expect(t, first_valid && second_valid)
	declarations := []shared.Project_Resource {
		{
			id = first_id,
			kind = .Material,
			name = "Would Otherwise Apply",
			source = "first.resource.toml",
			material = {base_color = {1, 0, 0, 1}},
		},
		{
			id = second_id,
			kind = .Material,
			name = "Reserved",
			source = "second.resource.toml",
			material = {base_color = {0, 1, 0, 1}},
		},
	}
	testing.expect(t, register_project_materials(&registry, "", declarations) != "")
	_, first_found := material_by_uuid(&registry, first_id)
	_, second_found := material_by_uuid(&registry, second_id)
	testing.expect(t, !first_found && !second_found)
}

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
test_generated_cylinder_caps_face_outward :: proc(t: ^testing.T) {
	segments := 12
	desc, err := cylinder(1, 2, segments)
	defer delete(desc.vertices)
	defer delete(desc.indices)
	testing.expect(t, err == "")
	side_index_count := segments * 6
	for cap in 0 ..< 2 {
		expected := Vec3{0, -1, 0} if cap == 0 else Vec3{0, 1, 0}
		for segment in 0 ..< segments {
			index_offset := side_index_count + (cap * segments + segment) * 3
			a := desc.vertices[desc.indices[index_offset]].position
			b := desc.vertices[desc.indices[index_offset + 1]].position
			c := desc.vertices[desc.indices[index_offset + 2]].position
			geometric_normal := cross(sub(b, a), sub(c, a))
			alignment :=
				geometric_normal.x * expected.x +
				geometric_normal.y * expected.y +
				geometric_normal.z * expected.z
			testing.expect(t, alignment > 0)
		}
	}
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

@(test)
test_textured_material_loads_project_png :: proc(t: ^testing.T) {
	registry: Registry; defer destroy_registry(&registry)
	handle, err := register_textured_material(
		&registry,
		"examples/minimal",
		"checker",
		"assets/checker.png",
		{1, 1, 1, 1},
	)
	testing.expectf(t, err == "", "failed to load texture fixture: %s", err)
	material, ok := get_material(&registry, handle)
	testing.expect(t, ok)
	if ok {
		testing.expect(t, material.desc.texture_width == 8)
		testing.expect(t, material.desc.texture_height == 8)
		testing.expect(t, len(material.desc.texture_pixels) == 8 * 8 * 4)
	}
}

@(test)
test_texture_assets_are_confined_to_assets_directory :: proc(t: ^testing.T) {
	testing.expect(t, valid_asset_path("assets/checker.png"))
	testing.expect(t, !valid_asset_path("checker.png"))
	testing.expect(t, !valid_asset_path("assets/checker.jpg"))
	testing.expect(t, !valid_asset_path("assets/../project.toml"))
	registry: Registry; defer destroy_registry(&registry)
	_, err := register_textured_material(
		&registry,
		"examples/minimal",
		"bad",
		"assets/missing.png",
		{1, 1, 1, 1},
	)
	testing.expect(t, err != "")
}

@(test)
test_materials_preserve_unbounded_hdr_emission :: proc(t: ^testing.T) {
	registry: Registry
	defer destroy_registry(&registry)
	handle, err := register_material(
		&registry,
		"neon",
		{base_color = {0.1, 0.2, 0.3, 1}, emissive = {12, 3, 0.5}},
	)
	testing.expect(t, err == "")
	material, ok := get_material(&registry, handle)
	testing.expect(t, ok)
	if ok {
		testing.expect_value(t, material.desc.emissive, Vec3{12, 3, 0.5})
	}
}

@(test)
test_materials_reject_non_finite_emission :: proc(t: ^testing.T) {
	registry: Registry
	defer destroy_registry(&registry)
	_, err := register_material(
		&registry,
		"invalid-neon",
		{base_color = {1, 1, 1, 1}, emissive = {transmute(f32)u32(0x7f80_0000), 0, 0}},
	)
	testing.expect(t, err != "")
	_, negative_err := register_material(
		&registry,
		"negative-neon",
		{base_color = {1, 1, 1, 1}, emissive = {-1, 0, 0}},
	)
	testing.expect(t, negative_err != "")
}

@(test)
test_masked_materials_validate_alpha_cutoff :: proc(t: ^testing.T) {
	registry: Registry
	defer destroy_registry(&registry)
	_, err := register_material(
		&registry,
		"invalid-mask",
		{base_color = {1, 1, 1, 1}, alpha_mode = .Mask, alpha_cutoff = 1.5},
	)
	testing.expect(t, err != "")
}

@(test)
test_pbr_materials_clone_complete_mipmapped_image_payloads :: proc(t: ^testing.T) {
	pixels: [20]u8
	for &value in pixels {
		value = 127
	}
	registry: Registry
	defer destroy_registry(&registry)
	handle, err := register_material(
		&registry,
		"pbr",
		{
			base_color = {1, 1, 1, 1},
			metallic_factor = 0.75,
			roughness_factor = 0.25,
			normal_scale = 0.5,
			occlusion_strength = 0.8,
			pbr = true,
			normal_image = {
				pixels = pixels[:],
				width = 2,
				height = 2,
				mip_count = 2,
				color_space = .Linear,
			},
		},
	)
	testing.expect_value(t, err, "")
	material, alive := get_material(&registry, handle)
	testing.expect(t, alive)
	if !alive {
		return
	}
	testing.expect_value(t, material.desc.metallic_factor, f32(0.75))
	testing.expect_value(t, material.desc.roughness_factor, f32(0.25))
	testing.expect_value(t, material.desc.normal_image.mip_count, u32(2))
	testing.expect_value(t, len(material.desc.normal_image.pixels), 20)
	pixels[0] = 255
	testing.expect_value(t, material.desc.normal_image.pixels[0], u8(127))
}

@(test)
test_pbr_materials_reject_incomplete_mip_chains :: proc(t: ^testing.T) {
	pixels: [16]u8
	registry: Registry
	defer destroy_registry(&registry)
	_, err := register_material(
		&registry,
		"invalid-pbr",
		{
			base_color = {1, 1, 1, 1},
			roughness_factor = 1,
			normal_scale = 1,
			occlusion_strength = 1,
			pbr = true,
			normal_image = {
				pixels = pixels[:],
				width = 2,
				height = 2,
				mip_count = 2,
				color_space = .Linear,
			},
		},
	)
	testing.expect(t, err != "")
}

@(test)
test_project_environment_registration_is_stable_and_revision_driven :: proc(t: ^testing.T) {
	registry: Registry
	defer destroy_registry(&registry)
	id, valid := shared.resource_uuid_parse("a2000000-0000-4000-8000-000000000019")
	testing.expect(t, valid)
	declaration := shared.Project_Resource {
		id = id,
		kind = .Environment,
		name = "Studio",
		source = "studio.resource.toml",
		environment = {source = "assets/studio.hdr"},
	}
	irradiance: [24]u16
	specular: [24]u16
	sky: [8]u16
	desc := Environment_Desc {
		sky_pixels = sky[:],
		irradiance_pixels = irradiance[:],
		specular_pixels = specular[:],
		sky_width = 2,
		sky_height = 1,
		irradiance_size = 1,
		specular_size = 1,
		specular_mip_count = 1,
	}
	handle, err := register_project_environment(&registry, declaration, desc, 96)
	testing.expect_value(t, err, "")
	testing.expect(t, handle != (Environment_Handle{}))
	background_id, background_valid := shared.resource_uuid_parse(
		"a2000000-0000-4000-8000-000000000020",
	)
	testing.expect(t, background_valid)
	background_declaration := declaration
	background_declaration.id = background_id
	background_declaration.name = "Backdrop"
	background_declaration.source = "backdrop.resource.toml"
	background_declaration.environment.source = "assets/backdrop.hdr"
	background_handle, background_err := register_project_environment(
		&registry,
		background_declaration,
		desc,
		96,
	)
	testing.expect_value(t, background_err, "")
	testing.expect(t, background_handle != (Environment_Handle{}))
	before := registry.environment_revision
	config := shared.Project_Render_Config {
		environment = id,
		environment_intensity = 1.5,
		environment_rotation = 45,
		exposure = 0.8,
		background_visible = true,
		background_environment = background_id,
		background_intensity = 0.75,
		background_rotation = 20,
		background_exposure = 1.1,
		background_blur = 0.4,
	}
	testing.expect_value(t, configure_project_environment(&registry, config), "")
	testing.expect_value(t, registry.active_environment, handle)
	testing.expect_value(t, registry.background_environment, background_handle)
	testing.expect(t, registry.background_visible)
	testing.expect_value(t, registry.background_intensity, f32(0.75))
	testing.expect_value(t, registry.background_rotation, f32(20))
	testing.expect_value(t, registry.background_exposure, f32(1.1))
	testing.expect_value(t, registry.background_blur, f32(0.4))
	testing.expect(t, registry.environment_revision > before)
	stable_revision := registry.environment_revision
	testing.expect_value(t, configure_project_environment(&registry, config), "")
	testing.expect_value(t, registry.environment_revision, stable_revision)

	specular[0] = 1
	sky[0] = 2
	updated, update_err := register_project_environment(&registry, declaration, desc, 96)
	testing.expect_value(t, update_err, "")
	testing.expect_value(t, updated, handle)
	testing.expect(t, registry.environment_revision > stable_revision)
	environment, alive := get_environment(&registry, updated)
	testing.expect(t, alive)
	if alive {
		testing.expect_value(t, environment.desc.sky_pixels[0], u16(2))
		testing.expect_value(t, environment.desc.specular_pixels[0], u16(1))
	}
}

@(test)
test_world_environment_reconciliation_is_change_driven :: proc(t: ^testing.T) {
	registry: Registry
	defer destroy_registry(&registry)
	world: shared.World
	defer {
		delete(world.entities)
		delete(world.world_environments)
	}
	environment := shared.world_environment_default()
	environment.lighting_intensity = 0.75
	environment.exposure = 1.1
	environment.background_intensity = 0.8
	environment.turbidity = 3.5
	append(&world.world_environments, environment)
	append(
		&world.entities,
		shared.World_Entity{alive = true, component_revision = 1, world_environment_index = 0},
	)
	world.world_environment_revision = 1
	world.world_environment_entity_index = -1

	testing.expect_value(t, reconcile_world_environment(&registry, &world), "")
	testing.expect_value(t, registry.environment_intensity, f32(0.75))
	testing.expect(t, registry.background_visible)
	testing.expect_value(t, registry.atmosphere_turbidity, f32(3.5))
	first_revision := registry.environment_revision
	testing.expect_value(t, reconcile_world_environment(&registry, &world), "")
	testing.expect_value(t, registry.environment_revision, first_revision)

	world.world_environments[0].background_intensity = 0.4
	world.world_environments[0].sun_glow = 2.25
	world.entities[0].component_revision += 1
	testing.expect_value(t, reconcile_world_environment(&registry, &world), "")
	testing.expect_value(t, registry.background_intensity, f32(0.4))
	testing.expect_value(t, registry.atmosphere_sun_glow, f32(2.25))
	testing.expect(t, registry.environment_revision > first_revision)
}

@(test)
test_project_lod_geometry_registers_stable_base_and_alternatives :: proc(t: ^testing.T) {
	registry: Registry
	defer destroy_registry(&registry)
	id, valid := shared.resource_uuid_parse("a2000000-0000-4000-8000-000000000020")
	testing.expect(t, valid)
	declaration := shared.Project_Resource {
		id = id,
		kind = .Geometry_LOD,
		name = "Authored Icosphere",
		source = "icosphere.resource.toml",
		geometry_lod = {
			radius = 0.5,
			subdivisions = {4, 2, 0, 0},
			lod_count = 3,
			screen_radii = {0.15, 0.04, 0},
		},
	}
	handle, err := register_project_lod_geometry(&registry, declaration)
	testing.expect(t, err == "")
	geometry, alive := get_geometry(&registry, handle)
	testing.expect(t, alive)
	if alive {
		testing.expect(t, geometry.authored)
		testing.expect_value(t, geometry.lod_count, 2)
		testing.expect_value(t, geometry.lod_screen_radii[0], f32(0.15))
		for lod_handle in geometry.lod_handles[:geometry.lod_count] {
			_, lod_alive := get_geometry(&registry, lod_handle)
			testing.expect(t, lod_alive)
		}
	}
	by_id, found := geometry_by_uuid(&registry, id)
	testing.expect(t, found)
	testing.expect_value(t, by_id, handle)
	before_revision := registry.geometry_topology_revision
	declaration.geometry_lod.subdivisions = {3, 1, 0, 0}
	declaration.geometry_lod.screen_radii = {0.2, 0.05, 0}
	updated, update_err := register_project_lod_geometry(&registry, declaration)
	testing.expect(t, update_err == "")
	testing.expect_value(t, updated, handle)
	testing.expect(t, registry.geometry_topology_revision > before_revision)
	updated_geometry, updated_alive := get_geometry(&registry, updated)
	testing.expect(t, updated_alive)
	if updated_alive {
		testing.expect_value(t, updated_geometry.lod_screen_radii[0], f32(0.2))
	}
}
