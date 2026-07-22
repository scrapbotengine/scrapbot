package project

import shared "../shared"
import "core:os"
import "core:path/filepath"
import "core:testing"

@(test)
test_scene_transform_hierarchy_requires_existing_acyclic_transform_parents :: proc(t: ^testing.T) {
	valid := `[[entities]]
id = "91000000-0000-4000-8000-000000000001"
name = "Parent"
[entities.transform]
position = [1, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]
[[entities]]
id = "91000000-0000-4000-8000-000000000002"
name = "Child"
[entities.transform]
parent = "91000000-0000-4000-8000-000000000001"
position = [0, 2, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]
`
	scene, valid_result := parse_scene(valid)
	defer destroy_scene(&scene)
	testing.expect(t, valid_result.err == .None)
	testing.expect_value(t, scene.entities[1].transform.parent, scene.entities[0].id)

	transformless_parent := `[[entities]]
id = "91500000-0000-4000-8000-000000000001"
name = "Transformless Parent"
[[entities]]
id = "91500000-0000-4000-8000-000000000002"
name = "Child"
[entities.transform]
parent = "91500000-0000-4000-8000-000000000001"
position = [0, 2, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]
`
	transformless_scene, transformless_result := parse_scene(transformless_parent)
	defer destroy_scene(&transformless_scene)
	testing.expect(t, transformless_result.err == .None)

	missing := `[[entities]]
id = "92000000-0000-4000-8000-000000000001"
name = "Child"
[entities.transform]
parent = "92000000-0000-4000-8000-000000000099"
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]
`
	missing_scene, missing_result := parse_scene(missing)
	defer destroy_scene(&missing_scene)
	testing.expect(t, missing_result.err == .Invalid_Field)

	cycle := `[[entities]]
id = "93000000-0000-4000-8000-000000000001"
name = "One"
[entities.transform]
parent = "93000000-0000-4000-8000-000000000002"
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]
[[entities]]
id = "93000000-0000-4000-8000-000000000002"
name = "Two"
[entities.transform]
parent = "93000000-0000-4000-8000-000000000001"
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]
`
	cycle_scene, cycle_result := parse_scene(cycle)
	defer destroy_scene(&cycle_scene)
	testing.expect(t, cycle_result.err == .Invalid_Field)
}

@(test)
test_project_model_resource_parser :: proc(t: ^testing.T) {
	resource, result := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000020"
type = "scrapbot.model"
name = "Ship"

[model]
source = "assets/ship.glb"
`,
	)
	testing.expect(t, result.err == .None)
	testing.expect(t, resource.kind == .Model)
	testing.expect_value(t, resource.model.source, "assets/ship.glb")
	_, unsafe := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000020"
type = "scrapbot.model"
name = "Unsafe"
[model]
source = "assets/../ship.gltf"
`,
	)
	testing.expect(t, unsafe.err == .Invalid_Path)
}

@(test)
test_project_environment_resource_and_render_config :: proc(t: ^testing.T) {
	resource, result := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000021"
type = "scrapbot.environment"
name = "Studio"

[environment]
source = "assets/studio.hdr"
`,
	)
	testing.expect(t, result.err == .None)
	testing.expect(t, resource.kind == .Environment)
	testing.expect_value(t, resource.environment.source, "assets/studio.hdr")

	config, config_result := parse_project_config(
		`name = "Environment Demo"
default_scene = "scenes/main.scene.toml"

[render]
environment = "a1000000-0000-4000-8000-000000000021"
environment_intensity = 1.25
environment_rotation = 90
exposure = 0.8
`,
	)
	defer destroy_project_config(&config)
	testing.expect(t, config_result.err == .None)
	testing.expect_value(t, config.render.environment, resource.id)
	testing.expect_value(t, config.render.environment_intensity, f32(1.25))
	testing.expect_value(t, config.render.environment_rotation, f32(90))
	testing.expect_value(t, config.render.exposure, f32(0.8))
	testing.expect(
		t,
		validate_project_environment_reference(&config, []shared.Project_Resource{resource}) == "",
	)

	wrong := resource
	wrong.kind = .Texture
	testing.expect(
		t,
		validate_project_environment_reference(&config, []shared.Project_Resource{wrong}) != "",
	)
}

@(test)
test_project_environment_rejects_non_hdr_and_invalid_render_values :: proc(t: ^testing.T) {
	_, resource_result := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000021"
type = "scrapbot.environment"
name = "Wrong"
[environment]
source = "assets/studio.png"
`,
	)
	testing.expect(t, resource_result.err == .Invalid_Path)
	config, config_result := parse_project_config(
		`name = "Invalid"
default_scene = "scenes/main.scene.toml"
[render]
environment_intensity = -1
exposure = 0
`,
	)
	defer destroy_project_config(&config)
	testing.expect(t, config_result.err == .Invalid_Field)
}

@(test)
test_project_texture_resource_parser :: proc(t: ^testing.T) {
	resource, result := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000000"
type = "scrapbot.texture"
name = "Checker"

[texture]
source = "assets/checker.png"
color_space = "linear"
generate_mipmaps = false
`,
	)
	testing.expect(t, result.err == .None)
	testing.expect(t, resource.kind == .Texture)
	testing.expect_value(t, resource.texture.source, "assets/checker.png")
	testing.expect(t, resource.texture.color_space == .Linear)
	testing.expect(t, !resource.texture.generate_mipmaps)
}

@(test)
test_project_texture_resource_parser_rejects_missing_and_unsafe_sources :: proc(t: ^testing.T) {
	_, missing := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000000"
type = "scrapbot.texture"
name = "Missing"
[texture]
`,
	)
	testing.expect(t, missing.err == .Missing_Field)
	_, unsafe := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000000"
type = "scrapbot.texture"
name = "Unsafe"
[texture]
source = "../outside.png"
`,
	)
	testing.expect(t, unsafe.err == .Invalid_Path)
}

@(test)
test_project_material_resource_parser :: proc(t: ^testing.T) {
	resource, result := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000001"
type = "scrapbot.material"
name = "Neon"

[material]
base_color = [0.1, 0.2, 0.3, 1]
emissive = [8, 2, 0.5]
texture = "a1000000-0000-4000-8000-000000000000"
`,
	)
	testing.expect(t, result.err == .None)
	testing.expect_value(t, resource.name, "Neon")
	testing.expect_value(t, resource.material.base_color, Vec4{0.1, 0.2, 0.3, 1})
	testing.expect_value(t, resource.material.emissive, Vec3{8, 2, 0.5})
	texture_id, _ := shared.resource_uuid_parse("a1000000-0000-4000-8000-000000000000")
	testing.expect_value(t, resource.material.texture, texture_id)
}

@(test)
test_project_material_resource_parser_rejects_invalid_values :: proc(t: ^testing.T) {
	_, missing_id := parse_project_resource(
		`type = "scrapbot.material"
name = "Missing"
[material]
base_color = [1, 1, 1, 1]
`,
	)
	testing.expect(t, missing_id.err == .Missing_Field)
	_, unsafe_texture := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000002"
type = "scrapbot.material"
name = "Unsafe"
[material]
texture = "../outside.png"
`,
	)
	testing.expect(t, unsafe_texture.err == .Invalid_Field)
}

@(test)
test_project_geometry_lod_resource_parser :: proc(t: ^testing.T) {
	resource, result := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000010"
type = "scrapbot.geometry_lod"
name = "Icosphere LOD"

[geometry_lod]
radius = 0.75
subdivisions = [4, 2, 0]
screen_radii = [0.15, 0.04]
`,
	)
	testing.expect(t, result.err == .None)
	testing.expect(t, resource.kind == .Geometry_LOD)
	testing.expect_value(t, resource.geometry_lod.radius, f32(0.75))
	testing.expect_value(t, resource.geometry_lod.lod_count, 3)
	testing.expect_value(t, resource.geometry_lod.subdivisions, [4]int{4, 2, 0, 0})
	testing.expect_value(t, resource.geometry_lod.screen_radii, [3]f32{0.15, 0.04, 0})
}

@(test)
test_project_geometry_lod_resource_parser_rejects_mismatched_thresholds :: proc(t: ^testing.T) {
	_, result := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000011"
type = "scrapbot.geometry_lod"
name = "Broken LOD"

[geometry_lod]
subdivisions = [4, 2, 0]
screen_radii = [0.15]
`,
	)
	testing.expect(t, result.err == .Invalid_Field)
}

@(test)
test_scene_material_references_require_known_resource_uuids :: proc(t: ^testing.T) {
	scene := Scene{}
	defer destroy_scene(&scene)
	append(
		&scene.entities,
		Scene_Entity {
			name = "Body",
			has_material = true,
			material_resource = "a1000000-0000-4000-8000-000000000003",
		},
	)
	resource_id, valid := shared.resource_uuid_parse("a1000000-0000-4000-8000-000000000003")
	testing.expect(t, valid)
	resources := []shared.Project_Resource{{id = resource_id, kind = .Material}}
	testing.expect(t, validate_scene_resource_references(&scene, resources) == "")
	scene.entities[0].material_resource = "not-a-uuid"
	testing.expect(t, validate_scene_resource_references(&scene, resources) != "")
}

@(test)
test_project_config_requires_safe_scene_path :: proc(t: ^testing.T) {
	config, result := parse_project_config(
		`name = "Demo"
default_scene = "../outside.scene.toml"
`,
	)
	testing.expect(t, result.err == .Invalid_Path)
	testing.expect(t, config.default_scene == "../outside.scene.toml")
}

@(test)
test_project_config_accepts_project_toml_shape :: proc(t: ^testing.T) {
	config, result := parse_project_config(
		`name = "Demo #1" # comments are allowed outside strings
default_scene = "scenes/main.scene.toml"

[window]
width = 1920
height = 1080

[[native_extensions]]
name = "scrappyphysics"
source = "native/scrappyphysics"
`,
	)
	defer destroy_project_config(&config)
	testing.expect(t, result.err == .None)
	testing.expect(t, config.name == "Demo #1")
	testing.expect(t, config.default_scene == "scenes/main.scene.toml")
	testing.expect(t, config.window.width == 1920)
	testing.expect(t, config.window.height == 1080)
	testing.expect(t, len(config.native_extensions) == 1)
	testing.expect(t, config.native_extensions[0].name == "scrappyphysics")
	testing.expect(t, config.native_extensions[0].source == "native/scrappyphysics")
}

@(test)
test_project_config_defaults_and_validates_window_size :: proc(t: ^testing.T) {
	defaults, defaults_result := parse_project_config(
		`name = "Defaults"
default_scene = "scenes/main.scene.toml"
`,
	)
	defer destroy_project_config(&defaults)
	testing.expect(t, defaults_result.err == .None)
	testing.expect(t, defaults.window.width == shared.DEFAULT_WINDOW_WIDTH)
	testing.expect(t, defaults.window.height == shared.DEFAULT_WINDOW_HEIGHT)

	invalid, invalid_result := parse_project_config(
		`name = "Invalid"
default_scene = "scenes/main.scene.toml"
[window]
width = 0
height = 900
`,
	)
	defer destroy_project_config(&invalid)
	testing.expect(t, invalid_result.err == .Invalid_Field)
}

@(test)
test_project_config_accepts_project_fonts :: proc(t: ^testing.T) {
	config, result := parse_project_config(
		`name = "Font Demo"
default_scene = "scenes/main.scene.toml"

[[fonts]]
name = "display"
source = "assets/fonts/display.otf"
`,
	)
	defer destroy_project_config(&config)
	testing.expect(t, result.err == .None)
	testing.expect(t, len(config.fonts) == 1)
	if len(config.fonts) == 1 {
		testing.expect(t, config.fonts[0].name == "display")
		testing.expect(t, config.fonts[0].source == "assets/fonts/display.otf")
	}
}

@(test)
test_project_config_rejects_unsafe_or_duplicate_fonts :: proc(t: ^testing.T) {
	unsafe, unsafe_result := parse_project_config(
		`name = "Font Demo"
default_scene = "scenes/main.scene.toml"
[[fonts]]
name = "display"
source = "../display.ttf"
`,
	)
	defer destroy_project_config(&unsafe)
	testing.expect(t, unsafe_result.err == .Invalid_Path)

	duplicate, duplicate_result := parse_project_config(
		`name = "Font Demo"
default_scene = "scenes/main.scene.toml"
[[fonts]]
name = "display"
source = "assets/fonts/first.ttf"
[[fonts]]
name = "display"
source = "assets/fonts/second.ttf"
`,
	)
	defer destroy_project_config(&duplicate)
	testing.expect(t, duplicate_result.err == .Invalid_Field)
}

@(test)
test_scene_font_references_must_be_declared_by_the_project :: proc(t: ^testing.T) {
	config := shared.Project_Config{}
	defer destroy_project_config(&config)
	append(&config.fonts, shared.Project_Font{name = "display", source = "assets/display.ttf"})
	scene := shared.Scene{}
	defer destroy_scene(&scene)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Title",
			has_ui_layout = true,
			has_ui_text = true,
			ui_text = {text = "Hello", font = "missing"},
		},
	)
	testing.expect(t, validate_scene_font_references(&scene, &config) != "")
	scene.entities[0].ui_text.font = "display"
	testing.expect(t, validate_scene_font_references(&scene, &config) == "")
}

@(test)
test_project_config_rejects_unescaped_string_bodies :: proc(t: ^testing.T) {
	_, result := parse_project_config(
		"name = \"Bad \\ Game\"\ndefault_scene = \"scenes/main.scene.toml\"\n",
	)
	testing.expect(t, result.err == .Invalid_Field)
}

@(test)
test_project_config_requires_safe_native_extension_source_path :: proc(t: ^testing.T) {
	config, result := parse_project_config(
		`name = "Demo"
default_scene = "scenes/main.scene.toml"

[[native_extensions]]
name = "faststuff"
source = "../faststuff"
`,
	)
	defer destroy_project_config(&config)
	testing.expect(t, result.err == .Invalid_Path)
}

@(test)
test_default_scene_template_mints_fresh_entity_ids :: proc(t: ^testing.T) {
	first_source := default_scene_template()
	second_source := default_scene_template()
	first, first_result := parse_scene(first_source)
	defer destroy_scene(&first)
	second, second_result := parse_scene(second_source)
	defer destroy_scene(&second)
	testing.expect(t, first_result.err == .None && second_result.err == .None)
	testing.expect(t, len(first.entities) == 2 && len(second.entities) == 2)
	if len(first.entities) == 2 && len(second.entities) == 2 {
		testing.expect(t, first.entities[0].id != first.entities[1].id)
		testing.expect(t, first.entities[0].id != second.entities[0].id)
		testing.expect(t, first.entities[1].id != second.entities[1].id)
	}
}

@(test)
test_scene_accepts_namespaced_component_names :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000001"
name = "Body"

[entities.components.scrappyphysics.rigidbody]
velocity = [0, 0, 0]
`,
	)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .None)
	testing.expect(t, len(scene.entities) == 1)
	testing.expect(t, len(scene.entities[0].custom_components) == 1)
	testing.expect(t, scene.entities[0].custom_components[0].name == "scrappyphysics.rigidbody")
}

@(test)
test_scene_rejects_malformed_component_names :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000002"
name = "Body"

[entities.components.scrappyphysics..rigidbody]
velocity = [0, 0, 0]
`,
	)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .Invalid_Field)
}

@(test)
test_scene_requires_valid_unique_entity_ids :: proc(t: ^testing.T) {
	missing_scene, missing_result := parse_scene(`[[entities]]
name = "Missing ID"
`)
	defer destroy_scene(&missing_scene)
	testing.expect(t, missing_result.err == .Missing_Field)

	invalid_scene, invalid_result := parse_scene(
		`[[entities]]
id = "not-a-uuid"
name = "Invalid ID"
`,
	)
	defer destroy_scene(&invalid_scene)
	testing.expect(t, invalid_result.err == .Invalid_Field)

	duplicate_scene, duplicate_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000020"
name = "First"

[[entities]]
id = "a6000000-0000-4000-8000-000000000020"
name = "Second"
`,
	)
	defer destroy_scene(&duplicate_scene)
	testing.expect(t, duplicate_result.err == .Invalid_Field)
}

@(test)
test_scene_component_fields_are_single_tokens :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000003"
name = "Body"

[entities.components.autorotate]
rotation.velocity = [0, 0, 0]
`,
	)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .Invalid_Field)
}

@(test)
test_scene_parses_engine_light_components :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000004"
name = "Ambient"
[entities.ambient_light]
color = [0.2, 0.3, 0.4]
intensity = 0.5

[[entities]]
id = "a6000000-0000-4000-8000-000000000005"
name = "Sun"
[entities.directional_light]
direction = [-1, -2, -3]
color = [1, 0.9, 0.8]
intensity = 1.25

[[entities]]
id = "a6000000-0000-4000-8000-000000000006"
name = "Lamp"
[entities.point_light]
color = [0.1, 0.4, 1]
intensity = 8
range = 12
`,
	)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .None)
	testing.expect(t, len(scene.entities) == 3)
	testing.expect(t, scene.entities[0].has_ambient_light)
	testing.expect(t, scene.entities[0].ambient_light.color.z == 0.4)
	testing.expect(t, scene.entities[1].has_directional_light)
	testing.expect(t, scene.entities[1].directional_light.direction.y == -2)
	testing.expect(t, scene.entities[2].has_point_light)
	testing.expect(t, scene.entities[2].point_light.intensity == 8)
	testing.expect(t, scene.entities[2].point_light.range == 12)
}

@(test)
test_scene_parses_shadow_marker_components :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000007"
name = "Cube"
[entities.shadow_caster]
[entities.shadow_receiver]
`,
	)
	defer destroy_scene(&scene)
	testing.expect(t, result.err == .None)
	testing.expect(t, len(scene.entities) == 1)
	testing.expect(t, scene.entities[0].has_shadow_caster)
	testing.expect(t, scene.entities[0].has_shadow_receiver)
}

@(test)
test_project_check_accepts_registered_namespaced_scene_components :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000008"
name = "Body"

[entities.components.scrapbot.transform]
position = [0, 0, 0]
`,
	)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .None)
	testing.expect(t, validate_namespaced_scene_components(&scene) == "")
}

@(test)
test_project_check_rejects_unknown_namespaced_scene_components :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000009"
name = "Body"

[entities.components.scrappyphysics.rigidbody]
velocity = [0, 0, 0]
`,
	)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .None)
	testing.expect(
		t,
		validate_namespaced_scene_components(&scene) ==
		`scene component "scrappyphysics.rigidbody" is not registered`,
	)
}

@(test)
test_init_project_writes_luau_lsp_metadata :: proc(t: ^testing.T) {
	parent, temp_err := os.make_directory_temp("", "scrapbot-init-*", context.temp_allocator)
	testing.expect(t, temp_err == nil)
	defer os.remove_all(parent)

	root, join_root_err := filepath.join({parent, "project"})
	testing.expect(t, join_root_err == nil)
	defer delete(root)
	defer os.remove_all(root)

	init_err := init_project(root, "Typed Demo")
	testing.expect(t, init_err == "")

	types_path, join_types_err := filepath.join({root, DEFAULT_LUAU_TYPES})
	testing.expect(t, join_types_err == nil)
	defer delete(types_path)
	settings_path, join_settings_err := filepath.join({root, DEFAULT_VSCODE_SETTINGS})
	testing.expect(t, join_settings_err == nil)
	defer delete(settings_path)

	types_bytes, types_err := os.read_entire_file(types_path, context.temp_allocator)
	testing.expect(t, types_err == nil)
	expected_types := default_luau_types_template()
	defer delete(expected_types)
	testing.expect(t, string(types_bytes) == expected_types)

	settings_bytes, settings_err := os.read_entire_file(settings_path, context.temp_allocator)
	testing.expect(t, settings_err == nil)
	testing.expect(t, string(settings_bytes) == default_vscode_settings_template())
}

@(test)
test_init_project_bootstraps_a_valid_clean_project :: proc(t: ^testing.T) {
	parent, temp_err := os.make_directory_temp(
		"",
		"scrapbot-init-layout-*",
		context.temp_allocator,
	)
	testing.expect(t, temp_err == nil)
	defer os.remove_all(parent)

	root, join_root_err := filepath.join({parent, "little-orbit"})
	testing.expect(t, join_root_err == nil)
	defer delete(root)

	init_err := init_project(root, "")
	testing.expectf(t, init_err == "", "init_project failed: %s", init_err)

	generated_files := []string {
		PROJECT_FILE,
		DEFAULT_SCENE,
		"resources/default.resource.toml",
		DEFAULT_SCRIPT,
		DEFAULT_LUAU_TYPES,
		DEFAULT_VSCODE_SETTINGS,
		".gitignore",
	}
	for relative_path in generated_files {
		path, path_err := filepath.join({root, relative_path})
		testing.expect(t, path_err == nil)
		testing.expectf(t, os.exists(path), "expected generated file %s", relative_path)
		delete(path)
	}
	expected_directories := []string {
		"assets",
		"native",
		"resources",
		"scenes",
		"scripts",
		".scrapbot/types",
		".vscode",
	}
	for relative_path in expected_directories {
		path, path_err := filepath.join({root, relative_path})
		testing.expect(t, path_err == nil)
		testing.expectf(t, os.is_dir(path), "expected generated directory %s", relative_path)
		delete(path)
	}

	project_path, project_path_err := filepath.join({root, PROJECT_FILE})
	testing.expect(t, project_path_err == nil)
	defer delete(project_path)
	project_bytes, project_read_err := os.read_entire_file(project_path, context.temp_allocator)
	testing.expect(t, project_read_err == nil)
	testing.expect(t, string(project_bytes) == project_toml_template("little-orbit"))

	gitignore_path, gitignore_path_err := filepath.join({root, ".gitignore"})
	testing.expect(t, gitignore_path_err == nil)
	defer delete(gitignore_path)
	gitignore_bytes, gitignore_read_err := os.read_entire_file(
		gitignore_path,
		context.temp_allocator,
	)
	testing.expect(t, gitignore_read_err == nil)
	testing.expect(t, string(gitignore_bytes) == ".scrapbot/\nbuild/\n")

	loaded := load_project(root)
	defer destroy_project_load_result(&loaded)
	testing.expectf(t, loaded.err == "", "generated project did not load: %s", loaded.err)
	testing.expect(t, loaded.config.name == "little-orbit")
	testing.expect(t, loaded.config.window.width == shared.DEFAULT_WINDOW_WIDTH)
	testing.expect(t, loaded.config.window.height == shared.DEFAULT_WINDOW_HEIGHT)
	testing.expect(t, len(loaded.scene.entities) == 2)
	testing.expect(t, len(loaded.resources) == 1)
}

@(test)
test_init_project_refuses_to_overwrite_any_generated_file :: proc(t: ^testing.T) {
	root, temp_err := os.make_directory_temp(
		"",
		"scrapbot-init-conflict-*",
		context.temp_allocator,
	)
	testing.expect(t, temp_err == nil)
	defer os.remove_all(root)

	scene_path, scene_path_err := filepath.join({root, DEFAULT_SCENE})
	testing.expect(t, scene_path_err == nil)
	defer delete(scene_path)
	scene_directory := os.dir(scene_path)
	testing.expect(t, os.make_directory_all(scene_directory) == nil)
	testing.expect(t, os.write_entire_file(scene_path, "keep me") == nil)

	init_err := init_project(root, "No Clobber")
	testing.expectf(
		t,
		init_err == "refusing to overwrite existing project file scenes/main.scene.toml",
		"unexpected init error: %s",
		init_err,
	)

	scene_bytes, scene_read_err := os.read_entire_file(scene_path, context.temp_allocator)
	testing.expect(t, scene_read_err == nil)
	testing.expect(t, string(scene_bytes) == "keep me")
	project_path, project_path_err := filepath.join({root, PROJECT_FILE})
	testing.expect(t, project_path_err == nil)
	defer delete(project_path)
	testing.expect(t, !os.exists(project_path))
}
@(test)
test_scene_parses_ecs_ui_hierarchy :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-00000000000a"
name = "HUD"
[entities.ui_layout]
position = [20, 30]
size = [400, 200]
min_size = [320, 160]
padding = [12, 12, 12, 12]
background = [0.1, 0.2, 0.3, 0.9]
border_color = [0.4, 0.5, 0.6, 1.0]
border_width = 2
corner_radius = 6
hidden = true
fill_width = true
fill_height = true
fit_content_width = true
fit_content_height = true
fixed_in_fill = true
[entities.ui_vstack]
gap = 8
fill = true
draggable = true
min_size = 72
[entities.ui_panel]
title = "METRICS"
title_color = [0.9, 0.9, 0.9, 1]
title_background = [0.12, 0.13, 0.14, 1]
title_size = 11
title_height = 28
disclosure_size = 9
disclosure_margin = 7
disclosure_gap = 6
disclosure_corner_radius = 0
collapsible = true
collapsed = true
[entities.ui_scroll_area]
scroll_speed = 64
smoothness = 12
scrollbar_width = 5
scrollbar_right = 6
scrollbar_vertical_inset = 7
minimum_thumb_size = 20
scrollbar_corner_radius = 0
scrollbar_track_color = [0.01, 0.02, 0.03, 1]
scrollbar_thumb_color = [0.7, 0.8, 0.9, 1]
[[entities]]
id = "a6000000-0000-4000-8000-00000000000b"
name = "Title"
[entities.ui_layout]
parent = "a6000000-0000-4000-8000-00000000000a"
size = [300, 40]
[entities.ui_text]
text = "HELLO"
color = [1, 0.8, 0.2, 1]
size = 24
alignment = "right"
[[entities]]
id = "a6000000-0000-4000-8000-00000000000c"
name = "Stats"
[entities.ui_layout]
parent = "a6000000-0000-4000-8000-00000000000a"
size = [300, 80]
[entities.ui_table]
columns = 3
column_gap = 6
row_gap = 4
proportional_columns = true
resizable_columns = true
min_column_width = 48
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "parse failed: %s", result.message)
	testing.expect(t, len(scene.entities) == 3)
	testing.expect(t, scene.entities[0].has_ui_vstack)
	testing.expect(t, scene.entities[0].ui_vstack.gap == 8)
	testing.expect(t, scene.entities[0].ui_vstack.fill)
	testing.expect(t, scene.entities[0].ui_vstack.draggable)
	testing.expect(t, scene.entities[0].ui_vstack.min_size == 72)
	testing.expect(t, scene.entities[0].has_ui_scroll_area)
	testing.expect(t, scene.entities[0].ui_scroll_area.scroll_speed == 64)
	testing.expect(t, scene.entities[0].ui_scroll_area.smoothness == 12)
	testing.expect(t, scene.entities[0].ui_scroll_area.scrollbar_width == 5)
	testing.expect(t, scene.entities[0].ui_scroll_area.scrollbar_corner_radius == 0)
	testing.expect(t, scene.entities[0].ui_scroll_area.scrollbar_thumb_color.x == 0.7)
	testing.expect(t, scene.entities[0].has_ui_panel)
	testing.expect(t, scene.entities[0].ui_panel.title == "METRICS")
	testing.expect(t, scene.entities[0].ui_panel.title_size == 11)
	testing.expect(t, scene.entities[0].ui_panel.title_height == 28)
	testing.expect(t, scene.entities[0].ui_panel.disclosure_size == 9)
	testing.expect(t, scene.entities[0].ui_panel.disclosure_corner_radius == 0)
	testing.expect(t, scene.entities[0].ui_panel.collapsible)
	testing.expect(t, scene.entities[0].ui_panel.collapsed)
	testing.expect(t, scene.entities[0].ui_layout.border_color == Vec4{0.4, 0.5, 0.6, 1})
	testing.expect(t, scene.entities[0].ui_layout.border_width == 2)
	testing.expect(t, scene.entities[0].ui_layout.corner_radius == 6)
	testing.expect(t, scene.entities[0].ui_layout.hidden)
	testing.expect(t, scene.entities[0].ui_layout.min_size == Vec2{320, 160})
	testing.expect(t, scene.entities[0].ui_layout.fill_width)
	testing.expect(t, scene.entities[0].ui_layout.fill_height)
	testing.expect(t, scene.entities[0].ui_layout.fit_content_width)
	testing.expect(t, scene.entities[0].ui_layout.fit_content_height)
	testing.expect(t, scene.entities[0].ui_layout.fixed_in_fill)
	hud_id, hud_id_ok := shared.entity_uuid_parse("a6000000-0000-4000-8000-00000000000a")
	testing.expect(t, hud_id_ok && scene.entities[1].ui_layout.parent == hud_id)
	testing.expect(t, scene.entities[1].ui_text.text == "HELLO")
	testing.expect(t, scene.entities[1].ui_text.alignment == .Right)
	testing.expect(t, scene.entities[2].has_ui_table)
	testing.expect(t, scene.entities[2].ui_table.columns == 3)
	testing.expect(t, scene.entities[2].ui_table.column_gap == 6)
	testing.expect(t, scene.entities[2].ui_table.row_gap == 4)
	testing.expect(t, scene.entities[2].ui_table.proportional_columns)
	testing.expect(t, scene.entities[2].ui_table.resizable_columns)
	testing.expect(t, scene.entities[2].ui_table.min_column_width == 48)
}

@(test)
test_scene_parses_selectable_ui_list :: proc(t: ^testing.T) {
	selected_id, selected_id_ok := shared.entity_uuid_parse("a6000000-0000-4000-8000-000000000031")
	testing.expect(t, selected_id_ok)
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000030"
name = "List"
[entities.ui_layout]
size = [240, 160]
[entities.ui_list]
selected = "a6000000-0000-4000-8000-000000000031"
gap = 3
selection_background = [0.1, 0.5, 0.4, 1]
hover_background = [0.2, 0.3, 0.4, 1]
active_background = [0.3, 0.4, 0.5, 1]
draggable = true
drag_threshold = 7
drop_edge_fraction = 0.2
drop_target_background = [0.05, 0.1, 0.15, 1]
tree_enabled = true
tree_indent = 18
[[entities]]
id = "a6000000-0000-4000-8000-000000000031"
name = "Item"
[entities.ui_layout]
parent = "a6000000-0000-4000-8000-000000000030"
size = [240, 30]
tree_item = true
tree_parent = "a6000000-0000-4000-8000-000000000031"
tree_order = 7
tree_collapsed = true
[entities.ui_text]
text = "Item"
size = 14
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "parse failed: %s", result.message)
	testing.expect(t, len(scene.entities) == 2)
	testing.expect(t, scene.entities[0].has_ui_list)
	list := scene.entities[0].ui_list
	testing.expect(t, list.selected == selected_id)
	testing.expect(t, list.gap == 3)
	testing.expect(t, list.selection_background == Vec4{0.1, 0.5, 0.4, 1})
	testing.expect(t, list.hover_background == Vec4{0.2, 0.3, 0.4, 1})
	testing.expect(t, list.active_background == Vec4{0.3, 0.4, 0.5, 1})
	testing.expect(t, list.draggable)
	testing.expect(t, list.drag_threshold == 7)
	testing.expect(t, list.drop_edge_fraction == 0.2)
	testing.expect(t, list.drop_target_background == Vec4{0.05, 0.1, 0.15, 1})
	testing.expect(t, list.tree_enabled)
	testing.expect(t, list.tree_indent == 18)
	testing.expect(t, scene.entities[1].ui_layout.tree_item)
	testing.expect(t, scene.entities[1].ui_layout.tree_parent == selected_id)
	testing.expect(t, scene.entities[1].ui_layout.tree_order == 7)
	testing.expect(t, scene.entities[1].ui_layout.tree_collapsed)
}

@(test)
test_scene_parses_styled_ui_progress :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000032"
name = "Progress"
[entities.ui_layout]
size = [240, 20]
[entities.ui_progress]
value = 25
maximum = 100
fill_color = [0.1, 0.8, 0.6, 1]
background_color = [0.02, 0.03, 0.04, 1]
inset = [4, 8, 4, 8]
corner_radius = 3
right_to_left = true
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "parse failed: %s", result.message)
	testing.expect(t, len(scene.entities) == 1)
	testing.expect(t, scene.entities[0].has_ui_progress)
	progress := scene.entities[0].ui_progress
	testing.expect(t, progress.value == 25)
	testing.expect(t, progress.maximum == 100)
	testing.expect(t, progress.fill_color == Vec4{0.1, 0.8, 0.6, 1})
	testing.expect(t, progress.background_color == Vec4{0.02, 0.03, 0.04, 1})
	testing.expect(t, progress.inset == Vec4{4, 8, 4, 8})
	testing.expect(t, progress.corner_radius == 3)
	testing.expect(t, progress.right_to_left)
}

@(test)
test_scene_parses_embedded_ui_viewport :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000042"
name = "Viewport"
[entities.ui_layout]
size = [320, 180]
[entities.ui_viewport]
resource = "a7000000-0000-4000-8000-000000000001"
orbit = [-0.25, 0.75]
distance = 4
clear_color = [0.01, 0.02, 0.03, 1]
interactive = true
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "parse failed: %s", result.message)
	testing.expect(t, len(scene.entities) == 1)
	testing.expect(t, scene.entities[0].has_ui_viewport)
	viewport := scene.entities[0].ui_viewport
	testing.expect(t, viewport.orbit == Vec2{-0.25, 0.75})
	testing.expect(t, viewport.distance == 4)
	testing.expect(t, viewport.clear_color == Vec4{0.01, 0.02, 0.03, 1})
	testing.expect(t, viewport.interactive)
}

@(test)
test_scene_rejects_collapsed_panel_without_collapsible_opt_in :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000010"
name = "Invalid Panel"
[entities.ui_layout]
size = [200, 100]
[entities.ui_panel]
title = "INVALID"
collapsed = true
`,
	)
	defer destroy_scene(&scene)
	testing.expect(t, result.err == .Invalid_Field)
}

@(test)
test_scene_rejects_removed_panel_action_fields :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000011"
name = "Invalid Panel Action"
[entities.ui_layout]
size = [200, 100]
[entities.ui_panel]
action_enabled = true
`,
	)
	defer destroy_scene(&scene)
	testing.expect(t, result.err == .Invalid_Field)
}

@(test)
test_scene_parses_composable_panel_icon_button_action :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000012"
name = "Panel"
[entities.ui_layout]
size = [200, 100]
[entities.ui_panel]
title = "PANEL"
[[entities]]
id = "a6000000-0000-4000-8000-000000000013"
name = "Close"
[entities.ui_layout]
parent = "a6000000-0000-4000-8000-000000000012"
size = [22, 22]
[entities.ui_button]
icon = "close"
icon_inset = 5
icon_stroke = 2
panel_action = true
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "%s", result.message)
	testing.expect(t, len(scene.entities) == 2)
	testing.expect(t, scene.entities[1].has_ui_button)
	testing.expect(t, scene.entities[1].ui_button.icon == .Close)
	testing.expect(t, scene.entities[1].ui_button.icon_inset == 5)
	testing.expect(t, scene.entities[1].ui_button.icon_stroke == 2)
	testing.expect(t, scene.entities[1].ui_button.panel_action)
}

@(test)
test_scene_parses_single_line_ui_input :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-00000000000d"
name = "Name Input"
[entities.ui_layout]
size = [240, 32]
[entities.ui_input]
text = "Scrapbot"
prefix = "X"
color = [0.9, 0.9, 0.9, 1]
prefix_color = [0.9, 0.3, 0.3, 1]
prefix_background = [0.9, 0.3, 0.3, 0.12]
size = 13
prefix_width = 14
selection_background = [0.1, 0.5, 0.4, 0.5]
focus_border_color = [0.1, 0.8, 0.7, 1]
invalid_border_color = [1, 0.1, 0.2, 1]
caret_color = [0.2, 1, 0.8, 1]
number = 42
step = 0.5
minimum = 0
maximum = 100
prefix_gap = 4
prefix_corner_radius = 0
prefix_text_padding = 2
selection_corner_radius = 0
focus_border_width = 2
invalid_border_width = 3
caret_width = 2
caret_inset = 3
numeric = true
draggable = true
has_minimum = true
has_maximum = true
read_only = false
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "parse failed: %s", result.message)
	testing.expect(t, len(scene.entities) == 1)
	input := scene.entities[0].ui_input
	testing.expect(t, scene.entities[0].has_ui_input)
	testing.expect(t, input.text == "Scrapbot")
	testing.expect(t, input.prefix == "X")
	testing.expect(t, input.size == 13)
	testing.expect(t, input.prefix_width == 14)
	testing.expect(t, input.number == 42 && input.step == 0.5)
	testing.expect(t, input.minimum == 0 && input.maximum == 100)
	testing.expect(t, input.prefix_gap == 4 && input.prefix_corner_radius == 0)
	testing.expect(t, input.selection_corner_radius == 0)
	testing.expect(t, input.focus_border_width == 2 && input.invalid_border_width == 3)
	testing.expect(t, input.caret_width == 2 && input.caret_inset == 3)
	testing.expect(t, input.numeric && input.draggable && input.has_minimum && input.has_maximum)
	testing.expect(t, input.selection_background == Vec4{0.1, 0.5, 0.4, 0.5})
	testing.expect(t, input.focus_border_color == Vec4{0.1, 0.8, 0.7, 1})
}

@(test)
test_scene_parses_all_custom_numeric_field_shapes :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000022"
name = "Typed"
[entities.components.typed]
amount = 1.5
uv = [2, 3]
direction = [4, 5, 6]
tint = [0.1, 0.2, 0.3, 0.4]
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "parse failed: %s", result.message)
	component := scene.entities[0].custom_components[0]
	testing.expect(t, component.number_fields[0].value == 1.5)
	testing.expect(t, component.vec2_fields[0].value == Vec2{2, 3})
	testing.expect(t, component.vec3_fields[0].value == Vec3{4, 5, 6})
	testing.expect(t, component.vec4_fields[0].value == Vec4{0.1, 0.2, 0.3, 0.4})
}

@(test)
test_scene_parses_ui_checkbox :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000021"
name = "Enabled"
[entities.ui_layout]
size = [32, 32]
[entities.ui_checkbox]
checked = true
box_size = 20
checked_background = [0.1, 0.6, 0.5, 1]
corner_radius = 0
border_width = 2
check_inset = 5
check_corner_radius = 0
read_only = true
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "parse failed: %s", result.message)
	testing.expect(t, len(scene.entities) == 1)
	checkbox := scene.entities[0].ui_checkbox
	testing.expect(t, scene.entities[0].has_ui_checkbox)
	testing.expect(t, checkbox.checked)
	testing.expect(t, checkbox.box_size == 20)
	testing.expect(t, checkbox.checked_background == Vec4{0.1, 0.6, 0.5, 1})
	testing.expect(t, checkbox.corner_radius == 0 && checkbox.border_width == 2)
	testing.expect(t, checkbox.check_inset == 5 && checkbox.check_corner_radius == 0)
	testing.expect(t, checkbox.read_only)
}

@(test)
test_scene_rejects_ui_parent_cycles :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-00000000000e"
name = "A"
[entities.ui_layout]
parent = "a6000000-0000-4000-8000-00000000000f"
size = [10, 10]
[[entities]]
id = "a6000000-0000-4000-8000-00000000000f"
name = "B"
[entities.ui_layout]
parent = "a6000000-0000-4000-8000-00000000000e"
size = [10, 10]
`,
	)
	defer destroy_scene(&scene)
	testing.expect(t, result.err == .Invalid_Field)
}

@(test)
test_scene_parses_model_resource_component :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000020"
name = "Imported Model"
[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]
[entities.model]
resource = "a7000000-0000-4000-8000-000000000001"
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "parse failed: %s", result.message)
	testing.expect_value(t, len(scene.entities), 1)
	if len(scene.entities) == 1 {
		testing.expect(t, scene.entities[0].has_model)
		testing.expect_value(
			t,
			scene.entities[0].model_resource,
			"a7000000-0000-4000-8000-000000000001",
		)
	}
}
