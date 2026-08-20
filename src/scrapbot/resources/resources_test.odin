package resources

import asset_import "../asset_import"
import geometry_package "../geometry"
import project "../project"
import shared "../shared"
import "core:math"
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
		cloned_geometry.meshlet_vertices[0] = 0xffff_ffff
		cloned_material.desc.base_color.x = 0.9
	}
	source_geometry, _ := get_geometry(&source, geometry)
	source_material, _ := get_material(&source, material)
	testing.expect(t, source_geometry.vertices[0].position.x != 42)
	testing.expect(t, source_geometry.meshlet_vertices[0] != cloned_geometry.meshlet_vertices[0])
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
		{
			base_color = {0.25, 0.5, 0.75, 1},
			emissive = {4, 2, 1},
			metallic_factor = 0.65,
			roughness_factor = 0.2,
		},
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
	loaded, load_err := project.load_project_resources(root)
	defer project.destroy_project_resources(&loaded)
	testing.expect(t, load_err == "")
	if len(loaded) == 1 {
		testing.expect_value(t, loaded[0].material.metallic, f32(0.65))
		testing.expect_value(t, loaded[0].material.roughness, f32(0.2))
	}
}

test_project_ui_theme_registry_updates_by_uuid_and_retires_missing_entries :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)
	defer destroy_registry(&registry)
	id, _ := shared.resource_uuid_parse("71c20000-0000-4000-8000-000000000001")
	theme := shared.ui_theme_reduced_dark()
	theme.palette.accent = {1.5, 0.2, 0.8, 1}
	theme.font = "Inter"
	declaration := shared.Project_Resource {
		id = id,
		kind = .UI_Theme,
		name = "Neon",
		source = "neon.resource.toml",
		ui_theme = {theme = theme},
	}
	testing.expect(
		t,
		register_project_ui_themes(&registry, []shared.Project_Resource{declaration}) == "",
	)
	value, found := ui_theme_by_id(&registry, id)
	testing.expect(t, found)
	testing.expect_value(t, value.palette.accent.x, f32(1.5))
	generation := registry.ui_themes[0].generation

	declaration.ui_theme.theme.metrics.radius = 27
	testing.expect(
		t,
		register_project_ui_themes(&registry, []shared.Project_Resource{declaration}) == "",
	)
	value, found = ui_theme_by_id(&registry, id)
	testing.expect(t, found)
	testing.expect_value(t, value.metrics.radius, f32(27))
	testing.expect_value(t, registry.ui_themes[0].generation, generation)
	testing.expect(t, registry.ui_themes[0].version > 1)

	testing.expect(t, register_project_ui_themes(&registry, nil) == "")
	_, found = ui_theme_by_id(&registry, id)
	testing.expect(t, !found)
	testing.expect(t, registry.ui_themes[0].generation > generation)
}

@(test)
test_project_shader_registry_versions_hook_source :: proc(t: ^testing.T) {
	registry: Registry
	defer destroy_registry(&registry)
	id, _ := shared.resource_uuid_parse("a2000000-0000-4000-8000-000000000090")
	declaration := shared.Project_Resource {
		id = id,
		kind = .Shader,
		name = "Water",
		source = "water.resource.toml",
		shader = {
			source = "shaders/water.wgsl",
			cull_mode = .None,
			spectral_surface = {
				enabled = true,
				patch_size = 192,
				wind_speed = 11,
				wind_direction = {0.94, 0.34},
				amplitude = 0.7,
				small_wave_damping = 0.35,
				choppiness = 0.9,
				foam_generation = 1.8,
				foam_decay = 0.3,
				foam_coverage = 0.65,
				foam_advection = {0.2, -0.075},
				band_count = 3,
				band_patch_scale = 0.25,
				band_amplitude_scale = 0.72,
			},
		},
	}
	source := "fn scrapbot_vertex(input: Scrapbot_Vertex) -> Scrapbot_Vertex { return input; }\nfn scrapbot_fragment(input: Scrapbot_Fragment) -> Scrapbot_Surface { return Scrapbot_Surface(); }"
	handle, err := register_project_shader(&registry, declaration, source)
	testing.expect(t, err == "")
	shader, alive := get_shader(&registry, handle)
	testing.expect(t, alive)
	if alive {
		testing.expect_value(t, shader.cull_mode, shared.Shader_Cull_Mode.None)
		testing.expect(t, shader.spectral_surface.enabled)
		testing.expect_value(t, shader.spectral_surface.patch_size, f32(192))
		testing.expect_value(t, shader.spectral_surface.amplitude, f32(0.7))
		testing.expect_value(t, shader.spectral_surface.choppiness, f32(0.9))
		testing.expect_value(t, shader.spectral_surface.foam_generation, f32(1.8))
		testing.expect_value(t, shader.spectral_surface.foam_decay, f32(0.3))
		testing.expect_value(t, shader.spectral_surface.foam_coverage, f32(0.65))
		testing.expect_value(t, shader.spectral_surface.foam_advection, shared.Vec2{0.2, -0.075})
		testing.expect_value(t, shader.spectral_surface.band_count, 3)
		testing.expect_value(t, shader.spectral_surface.band_patch_scale, f32(0.25))
		testing.expect_value(t, shader.spectral_surface.band_amplitude_scale, f32(0.72))
		testing.expect_value(t, shader.version, u32(1))
	}

	changed_source := "fn scrapbot_vertex(input: Scrapbot_Vertex) -> Scrapbot_Vertex { return input; }\nfn scrapbot_fragment(input: Scrapbot_Fragment) -> Scrapbot_Surface { return Scrapbot_Surface(); }\n// changed"
	updated, update_err := register_project_shader(&registry, declaration, changed_source)
	testing.expect(t, update_err == "")
	testing.expect(t, updated == handle)
	shader, alive = get_shader(&registry, handle)
	if alive { testing.expect_value(t, shader.version, u32(2)) }

	_, invalid_err := register_project_shader(&registry, declaration, "@fragment fn main() {}")
	testing.expect(t, invalid_err != "")
}

@(test)
test_project_material_registration_preserves_authored_surface_factors :: proc(t: ^testing.T) {
	registry: Registry
	defer destroy_registry(&registry)
	id, valid := shared.resource_uuid_parse("a2000000-0000-4000-8000-000000000032")
	testing.expect(t, valid)
	handle, register_err := register_project_material(
		&registry,
		id,
		"Surface",
		"surface.resource.toml",
		{base_color = {0.25, 0.5, 0.75, 1}, metallic_factor = 0.7, roughness_factor = 0.15},
	)
	testing.expect(t, register_err == "")
	material, alive := get_material(&registry, handle)
	testing.expect(t, alive)
	if alive {
		testing.expect_value(t, material.desc.metallic_factor, f32(0.7))
		testing.expect_value(t, material.desc.roughness_factor, f32(0.15))
		testing.expect(t, !material.desc.pbr)
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
test_nonresident_geometry_reconstructs_every_exact_leaf_page :: proc(t: ^testing.T) {
	vertices := [4]Vertex {
		{position = {-1, -1, 0}},
		{position = {1, -1, 0}},
		{position = {-1, 1, 0}},
		{position = {1, 1, 0}},
	}
	indices := [6]u32{0, 1, 2, 1, 3, 2}
	groups := [2]Geometry_Cluster_Group {
		{depth = 0, cluster_offset = 0, cluster_count = 1, page_offset = 0, page_count = 1},
		{
			depth = 1,
			cluster_offset = 1,
			cluster_count = 1,
			page_offset = 1,
			page_count = 1,
			error = 3.4028235e38,
		},
	}
	clusters := [2]Geometry_Cluster {
		{
			vertex_offset = 0,
			triangle_offset = 0,
			vertex_count = 3,
			triangle_count = 1,
			group = 0,
			refined_group = -1,
			page = 0,
		},
		{
			vertex_offset = 3,
			triangle_offset = 3,
			vertex_count = 3,
			triangle_count = 1,
			group = 1,
			refined_group = -1,
			page = 1,
		},
	}
	pages := [2]Geometry_Cluster_Page {
		{cluster_offset = 0, cluster_count = 1, index_count = 3},
		{cluster_offset = 1, cluster_count = 1, index_count = 3, pinned = true, bootstrap = true},
	}
	cluster_vertices := [6]u32{0, 1, 2, 1, 3, 2}
	cluster_triangles := [6]u8{0, 1, 2, 0, 1, 2}
	hierarchy := Geometry_Hierarchy {
		groups = groups[:],
		clusters = clusters[:],
		pages = pages[:],
		vertices = cluster_vertices[:],
		triangles = cluster_triangles[:],
		max_depth = 1,
	}
	desc := Geometry_Desc {
		vertices = vertices[:],
		indices = indices[:],
	}
	prepared, prepared_err := prepare_geometry_page_source(
		desc,
		&hierarchy,
		nil,
		context.allocator,
	)
	defer destroy_prepared_geometry_page_source(&prepared, context.allocator)
	testing.expectf(t, prepared_err == "", "page source failed: %s", prepared_err)
	positions := [4]Vec3 {
		vertices[0].position,
		vertices[1].position,
		vertices[2].position,
		vertices[3].position,
	}
	resource := Geometry {
		query_proxy = {positions = positions[:]},
		canonical_vertex_count = 4,
		canonical_index_count = 6,
		cluster_groups = groups[:],
		clusters = clusters[:],
		cluster_pages = pages[:],
		cluster_vertices = cluster_vertices[:],
		cluster_triangles = cluster_triangles[:],
		page_source_kind = prepared.kind,
		page_payload_records = prepared.records,
		page_payload_bytes = prepared.bytes[:],
		cluster_max_depth = 1,
	}
	testing.expect_value(t, geometry_fallback_index_count(&resource), 6)
	fallback, fallback_err := load_geometry_canonical(&resource)
	defer destroy_geometry_canonical_view(&fallback)
	testing.expectf(t, fallback_err == "", "fallback failed: %s", fallback_err)
	testing.expect_value(t, len(fallback.vertices), 4)
	for index, position in fallback.indices {
		testing.expect_value(t, index, indices[position])
	}
	iterator := geometry_query_iterator(&resource)
	triangle_count := 0
	for {
		_, ok := geometry_query_next(&iterator)
		if !ok {
			break
		}
		triangle_count += 1
	}
	testing.expect_value(t, triangle_count, 2)
	first_cluster := geometry_query_cluster_iterator(&resource, 0)
	first_triangle, first_ok := geometry_query_next(&first_cluster)
	testing.expect(t, first_ok)
	testing.expect_value(t, first_triangle.a, positions[0])
	_, first_exhausted := geometry_query_next(&first_cluster)
	testing.expect(t, !first_exhausted)
	second_cluster := geometry_query_cluster_iterator(&resource, 1)
	second_triangle, second_ok := geometry_query_next(&second_cluster)
	testing.expect(t, second_ok)
	testing.expect_value(t, second_triangle.a, positions[1])
	_, second_exhausted := geometry_query_next(&second_cluster)
	testing.expect(t, !second_exhausted)
}

test_registered_geometry_builds_bounded_meshlets :: proc(t: ^testing.T) {
	registry := Registry{}
	defer destroy_registry(&registry)
	desc, desc_err := icosphere(1, 3)
	testing.expect(t, desc_err == "")
	if desc_err != "" {
		return
	}
	defer delete(desc.vertices)
	defer delete(desc.indices)
	handle, register_err := register_geometry(&registry, "meshlet sphere", desc)
	testing.expect(t, register_err == "")
	geometry, alive := get_geometry(&registry, handle)
	testing.expect(t, alive)
	if !alive {
		return
	}
	testing.expect(t, len(geometry.meshlets) > 1)
	total_triangles := 0
	for meshlet in geometry.meshlets {
		testing.expect(t, meshlet.vertex_count <= MESHLET_MAX_VERTICES)
		testing.expect(t, meshlet.triangle_count <= MESHLET_MAX_TRIANGLES)
		testing.expect(t, meshlet.vertex_count > 0)
		testing.expect(t, meshlet.triangle_count > 0)
		testing.expect(t, meshlet.bounds[3] >= 0)
		vertex_start := int(meshlet.vertex_offset)
		vertex_end := vertex_start + int(meshlet.vertex_count)
		triangle_start := int(meshlet.triangle_offset)
		triangle_end := triangle_start + int(meshlet.triangle_count * 3)
		testing.expect(t, vertex_end <= len(geometry.meshlet_vertices))
		testing.expect(t, triangle_end <= len(geometry.meshlet_triangles))
		if vertex_end > len(geometry.meshlet_vertices) ||
		   triangle_end > len(geometry.meshlet_triangles) {
			continue
		}
		for vertex in geometry.meshlet_vertices[vertex_start:vertex_end] {
			testing.expect(t, int(vertex) < len(geometry.vertices))
		}
		for triangle_vertex in geometry.meshlet_triangles[triangle_start:triangle_end] {
			testing.expect(t, u32(triangle_vertex) < meshlet.vertex_count)
		}
		total_triangles += int(meshlet.triangle_count)
	}
	testing.expect_value(t, total_triangles, len(geometry.indices) / 3)
	testing.expect(t, len(geometry.cluster_groups) > 1)
	testing.expect(t, len(geometry.clusters) > len(geometry.meshlets))
	testing.expect(t, len(geometry.cluster_pages) > 0)
	testing.expect(t, geometry.cluster_max_depth > 0)
	leaf_triangles := 0
	for group, group_index in geometry.cluster_groups {
		testing.expect(t, group.cluster_count > 0)
		testing.expect(t, group.depth <= geometry.cluster_max_depth)
		cluster_start := int(group.cluster_offset)
		cluster_end := cluster_start + int(group.cluster_count)
		testing.expect(t, cluster_end <= len(geometry.clusters))
		if cluster_end > len(geometry.clusters) {
			continue
		}
		for cluster in geometry.clusters[cluster_start:cluster_end] {
			testing.expect_value(t, cluster.group, i32(group_index))
			testing.expect(t, cluster.refined_group < i32(group_index))
			testing.expect(t, cluster.vertex_count <= MESHLET_MAX_VERTICES)
			testing.expect(t, cluster.triangle_count <= MESHLET_MAX_TRIANGLES)
			vertex_end := int(cluster.vertex_offset + cluster.vertex_count)
			triangle_end := int(cluster.triangle_offset + cluster.triangle_count * 3)
			testing.expect(t, vertex_end <= len(geometry.cluster_vertices))
			testing.expect(t, triangle_end <= len(geometry.cluster_triangles))
			if cluster.refined_group == -1 {
				leaf_triangles += int(cluster.triangle_count)
			}
			testing.expect(t, int(cluster.page) < len(geometry.cluster_pages))
		}
		page_start := int(group.page_offset)
		page_end := int(group.page_offset + group.page_count)
		for page in geometry.cluster_pages[page_start:page_end] {
			if geometry_package.cluster_group_is_terminal(group) {
				testing.expect(t, page.pinned)
			}
			testing.expect(t, page.index_count > 0)
			testing.expect(t, page.index_count <= 64 * 1024 / size_of(u32))
		}
	}
	testing.expect_value(t, leaf_triangles, len(geometry.indices) / 3)
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
test_plane_subdivisions_build_a_dense_displacement_grid :: proc(t: ^testing.T) {
	desc, err := plane(8, 12, 4, 3)
	defer delete(desc.vertices)
	defer delete(desc.indices)
	testing.expect(t, err == "")
	testing.expect_value(t, len(desc.vertices), 20)
	testing.expect_value(t, len(desc.indices), 72)
	testing.expect(t, validate_geometry(desc) == "")
	testing.expect_value(t, desc.vertices[0].position, Vec3{-4, 0, -6})
	testing.expect_value(t, desc.vertices[len(desc.vertices) - 1].position, Vec3{4, 0, 6})
	_, too_dense := plane(1, 1, 513, 1)
	testing.expect(t, too_dense != "")
}

@(test)
test_voxel_surface_builds_smooth_arbitrary_topology :: proc(t: ^testing.T) {
	densities := []f32 {
		-1,
		-1,
		-1,
		-1,
		1,
		-1,
		-1,
		-1,
		-1,
		1,
		1,
		1,
		1,
		2,
		1,
		1,
		1,
		1,
		-1,
		-1,
		-1,
		-1,
		1,
		-1,
		-1,
		-1,
		-1,
	}
	desc, err := voxel_surface({-1, -1, -1}, 1, {2, 2, 2}, densities)
	defer delete(desc.vertices)
	defer delete(desc.indices)
	testing.expect(t, err == "")
	testing.expect(t, validate_geometry(desc) == "")
	testing.expect(t, len(desc.vertices) > 0)
	testing.expect(t, len(desc.indices) > 0)
	_, invalid_err := voxel_surface({}, 1, {2, 2, 2}, densities[:len(densities) - 1])
	testing.expect(t, invalid_err != "")
	_, axis_limit_err := voxel_surface({}, 1, {65, 1, 1}, nil)
	testing.expect(t, axis_limit_err != "")
	_, total_limit_err := voxel_surface({}, 1, {64, 64, 17}, nil)
	testing.expect(t, total_limit_err != "")
	finite_densities := make([]f32, 8)
	defer delete(finite_densities)
	_, conversion_overflow_err := voxel_surface({0, -3e38, 0}, 3e38, {1, 1, 1}, finite_densities)
	testing.expect(t, conversion_overflow_err != "")
}

Voxel_Test_Edge :: struct {
	a, b: u32,
}

voxel_test_smooth_min :: proc(a, b, radius: f32) -> f32 {
	blend := clamp(0.5 + 0.5 * (b - a) / radius, 0, 1)
	return b + (a - b) * blend - radius * blend * (1 - blend)
}

voxel_test_smooth_max :: proc(a, b, radius: f32) -> f32 {
	return -voxel_test_smooth_min(-a, -b, radius)
}

@(test)
test_voxel_terrain_lab_surface_has_no_interior_boundary_or_reversed_triangles :: proc(
	t: ^testing.T,
) {
	cells := [3]int{50, 26, 50}
	voxel_size := f32(0.24)
	origin := Vec3{-6, -2.5, -6}
	densities := make([]f32, (cells[0] + 1) * (cells[1] + 1) * (cells[2] + 1))
	defer delete(densities)
	stride_x := cells[0] + 1
	stride_y := cells[1] + 1
	for z_index in 0 ..= cells[2] {
		z := origin.z + f32(z_index) * voxel_size
		for y_index in 0 ..= cells[1] {
			y := origin.y + f32(y_index) * voxel_size
			for x_index in 0 ..= cells[0] {
				x := origin.x + f32(x_index) * voxel_size
				hill := 3.2 * math.exp(-(x * x + z * z) / 24)
				ridges := math.sin(x * 0.62 + math.sin(z * 0.31) * 1.4) * 0.42
				detail := math.sin(x * 1.52 - z * 1.08) * 0.1
				density := hill + ridges + detail - 0.82 - y
				tunnel_x := x + math.sin(z * 0.3) * 0.34
				tunnel_y := y - 0.12 - math.sin(z * 0.22) * 0.14
				tunnel := math.sqrt(tunnel_x * tunnel_x + tunnel_y * tunnel_y) - 1.5
				density = voxel_test_smooth_min(density, tunnel, 0.32)
				arch_x := x + 3.25
				arch_y := y - 1.05
				arch_ring := math.sqrt(arch_x * arch_x + arch_y * arch_y)
				arch :=
					0.62 -
					math.sqrt((arch_ring - 1.8) * (arch_ring - 1.8) + (z + 1.25) * (z + 1.25))
				density = voxel_test_smooth_max(density, arch, 0.24)
				shelf :=
					1.72 -
					math.sqrt(
						((x - 3.35) / 1.25) * ((x - 3.35) / 1.25) +
						((y - 1.45) / 0.58) * ((y - 1.45) / 0.58) +
						((z + 0.45) / 1.05) * ((z + 0.45) / 1.05),
					)
				support :=
					1.35 -
					math.sqrt(
						((x - 2.8) / 0.62) * ((x - 2.8) / 0.62) +
						((y - 0.2) / 1.25) * ((y - 0.2) / 1.25) +
						((z + 0.2) / 0.82) * ((z + 0.2) / 0.82),
					)
				density = voxel_test_smooth_max(
					density,
					voxel_test_smooth_max(shelf, support, 0.2),
					0.24,
				)
				inset := voxel_size * 0.75
				boundary := min(
					x - origin.x - inset,
					origin.x + f32(cells[0]) * voxel_size - x - inset,
					y - origin.y - inset,
					origin.y + f32(cells[1]) * voxel_size - y - inset,
					z - origin.z - inset,
					origin.z + f32(cells[2]) * voxel_size - z - inset,
				)
				density = min(density, boundary)
				densities[(z_index * stride_y + y_index) * stride_x + x_index] = density
			}
		}
	}
	desc, err := voxel_surface(origin, voxel_size, cells, densities)
	defer delete(desc.vertices)
	defer delete(desc.indices)
	testing.expectf(t, err == "", "voxel terrain lab extraction failed: %s", err)
	edges := make(map[Voxel_Test_Edge]int)
	defer delete(edges)
	for index := 0; index < len(desc.indices); index += 3 {
		triangle := [3]u32{desc.indices[index], desc.indices[index + 1], desc.indices[index + 2]}
		a := desc.vertices[triangle[0]]
		b := desc.vertices[triangle[1]]
		c := desc.vertices[triangle[2]]
		face := cross(sub(b.position, a.position), sub(c.position, a.position))
		average_normal := add(add(a.normal, b.normal), c.normal)
		orientation :=
			face.x * average_normal.x + face.y * average_normal.y + face.z * average_normal.z
		testing.expect(t, orientation > 0)
		for edge_index in 0 ..< 3 {
			edge_a := triangle[edge_index]
			edge_b := triangle[(edge_index + 1) % 3]
			if edge_b < edge_a {
				edge_a, edge_b = edge_b, edge_a
			}
			edges[Voxel_Test_Edge{edge_a, edge_b}] += 1
		}
	}
	for _, incidence in edges {
		testing.expect_value(t, incidence, 2)
	}
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
test_custom_materials_support_opaque_and_blended_surfaces :: proc(t: ^testing.T) {
	shader := Shader_Handle {
		index = 1,
		generation = 1,
	}
	opaque_err := validate_material_desc({shader = shader, alpha_mode = .Opaque})
	blended_err := validate_material_desc({shader = shader, alpha_mode = .Blend})
	masked_err := validate_material_desc({shader = shader, alpha_mode = .Mask})
	testing.expect(t, opaque_err == "")
	testing.expect(t, blended_err == "")
	testing.expect(t, masked_err != "")
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
		environment_reflection_intensity = 0.65,
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
	testing.expect_value(t, registry.environment_reflection_intensity, f32(0.65))
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

	project_environment := config
	project_environment.background_environment = {}
	testing.expect_value(t, configure_project_environment(&registry, project_environment), "")
	testing.expect_value(t, registry.background_environment, handle)

	world_environment := shared.world_environment_default()
	world_environment.lighting = "a2000000-0000-4000-8000-000000000019"
	testing.expect_value(t, configure_world_environment(&registry, world_environment), "")
	testing.expect_value(t, registry.active_environment, handle)
	testing.expect_value(t, registry.background_environment, Environment_Handle{})
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
	environment.reflection_intensity = 0.6
	environment.exposure = 1.1
	environment.background_intensity = 0.8
	environment.turbidity = 3.5
	environment.sun_direction = {0.3, 0.4, -0.8}
	environment.sun_color = {1, 0.8, 0.6}
	environment.sun_intensity = 2.5
	append(&world.world_environments, environment)
	append(
		&world.entities,
		shared.World_Entity{alive = true, component_revision = 1, world_environment_index = 0},
	)
	world.world_environment_revision = 1
	world.world_environment_entity_index = -1

	testing.expect_value(t, reconcile_world_environment(&registry, &world), "")
	testing.expect_value(t, registry.environment_intensity, f32(0.75))
	testing.expect_value(t, registry.environment_reflection_intensity, f32(0.6))
	testing.expect(t, registry.background_visible)
	testing.expect_value(t, registry.atmosphere_turbidity, f32(3.5))
	testing.expect_value(t, registry.atmosphere_sun_direction, shared.Vec3{0.3, 0.4, -0.8})
	testing.expect_value(t, registry.atmosphere_sun_color, shared.Vec3{1, 0.8, 0.6})
	testing.expect_value(t, registry.atmosphere_sun_intensity, f32(2.5))
	first_revision := registry.environment_revision
	testing.expect_value(t, reconcile_world_environment(&registry, &world), "")
	testing.expect_value(t, registry.environment_revision, first_revision)

	world.world_environments[0].background_intensity = 0.4
	world.world_environments[0].reflection_intensity = 0.35
	world.world_environments[0].sun_glow = 2.25
	world.world_environments[0].sun_intensity = 3.5
	world.entities[0].component_revision += 1
	testing.expect_value(t, reconcile_world_environment(&registry, &world), "")
	testing.expect_value(t, registry.background_intensity, f32(0.4))
	testing.expect_value(t, registry.environment_reflection_intensity, f32(0.35))
	testing.expect_value(t, registry.atmosphere_sun_glow, f32(2.25))
	testing.expect_value(t, registry.atmosphere_sun_intensity, f32(3.5))
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

@(test)
test_project_icon_set_preserves_handle_and_versions_content :: proc(t: ^testing.T) {
	registry: Registry
	defer destroy_registry(&registry)
	id, valid := shared.resource_uuid_parse("a2000000-0000-4000-8000-000000000021")
	testing.expect(t, valid)
	declaration := shared.Project_Resource {
		id = id,
		kind = .Icon_Set,
		name = "Interface",
		source = "interface.resource.toml",
		icon_set = {source = "assets/icons"},
	}
	pixels := make([]u8, asset_import.ICON_SET_ATLAS_SIZE * asset_import.ICON_SET_ATLAS_SIZE * 4)
	defer delete(pixels)
	symbols := make([dynamic]Icon_Symbol)
	defer delete(symbols)
	append(&symbols, Icon_Symbol{name = "play", uv = {0, 0, 0.25, 0.25}})
	append(&symbols, Icon_Symbol{name = "pause", uv = {0.25, 0, 0.5, 0.25}})
	desc := Icon_Set_Desc {
		pixels = pixels,
		width = asset_import.ICON_SET_ATLAS_SIZE,
		height = asset_import.ICON_SET_ATLAS_SIZE,
		symbols = symbols,
	}
	handle, err := register_project_icon_set(&registry, declaration, desc, len(pixels))
	testing.expect_value(t, err, "")
	icon_set, alive := get_icon_set(&registry, handle)
	testing.expect(t, alive)
	if !alive {
		return
	}
	testing.expect_value(t, icon_set.version, u32(1))
	symbol, found := icon_symbol(icon_set, "pause")
	testing.expect(t, found)
	testing.expect_value(t, symbol.uv, [4]f32{0.25, 0, 0.5, 0.25})
	revision := registry.icon_set_revision
	updated, update_err := register_project_icon_set(&registry, declaration, desc, len(pixels))
	testing.expect_value(t, update_err, "")
	testing.expect_value(t, updated, handle)
	updated_set, updated_alive := get_icon_set(&registry, updated)
	testing.expect(t, updated_alive)
	if updated_alive {
		testing.expect_value(t, updated_set.version, u32(2))
		updated_set.alive = false
		updated_set.generation += 1
		updated_set.version += 1
	}
	testing.expect(t, registry.icon_set_revision > revision)
	replacement_id, replacement_valid := shared.resource_uuid_parse(
		"a2000000-0000-4000-8000-000000000022",
	)
	testing.expect(t, replacement_valid)
	declaration.id = replacement_id
	replacement, replacement_err := register_project_icon_set(
		&registry,
		declaration,
		desc,
		len(pixels),
	)
	testing.expect_value(t, replacement_err, "")
	testing.expect_value(t, replacement.index, handle.index)
	testing.expect(t, replacement.generation > handle.generation)
	_, stale_alive := get_icon_set(&registry, handle)
	testing.expect(t, !stale_alive)
}
@(test)
test_builtin_icon_set_is_registered_with_public_symbols :: proc(t: ^testing.T) {
	registry: Registry
	init_registry(&registry)
	defer destroy_registry(&registry)
	handle, found := icon_set_handle_by_uuid(&registry, shared.builtin_icon_set_uuid())
	testing.expect(t, found)
	icon_set, alive := get_icon_set(&registry, handle)
	testing.expect(t, alive)
	symbol, symbol_found := icon_symbol(icon_set, "play")
	testing.expect(t, symbol_found)
	testing.expect(t, symbol.name == "play")
	testing.expect(t, symbol.plane[2] > symbol.plane[0])
}
