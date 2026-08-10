package project

import shared "../shared"
import "core:fmt"
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
geometry_mode = "virtual"
lod_ratios = [0.6, 0.3]
lod_screen_radii = [0.2, 0.05]
`,
	)
	testing.expect(t, result.err == .None)
	testing.expect(t, resource.kind == .Model)
	testing.expect_value(t, resource.model.source, "assets/ship.glb")
	testing.expect_value(t, resource.model.geometry_mode, shared.Geometry_Mode.Virtual)
	testing.expect(t, resource.model.generate_lods)
	testing.expect_value(t, resource.model.lod_count, 2)
	testing.expect_value(t, resource.model.lod_ratios[0], f32(0.6))
	testing.expect_value(t, resource.model.lod_screen_radii[1], f32(0.05))
	_, unsafe := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000020"
type = "scrapbot.model"
name = "Unsafe"
[model]
source = "assets/../ship.gltf"
`,
	)
	testing.expect(t, unsafe.err == .Invalid_Path)
	_, mismatched_lods := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000020"
type = "scrapbot.model"
name = "Mismatched"
[model]
source = "assets/ship.gltf"
lod_ratios = [0.5, 0.25]
lod_screen_radii = [0.1]
`,
	)
	testing.expect(t, mismatched_lods.err == .Invalid_Field)
}

@(test)
test_project_icon_set_resource_parser :: proc(t: ^testing.T) {
	resource, result := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000022"
type = "scrapbot.icon_set"
name = "Interface"

[icon_set]
source = "assets/icons/interface"
`,
	)
	testing.expect(t, result.err == .None)
	testing.expect(t, resource.kind == .Icon_Set)
	testing.expect_value(t, resource.icon_set.source, "assets/icons/interface")

	_, unsafe := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000022"
type = "scrapbot.icon_set"
name = "Unsafe"
[icon_set]
source = "assets/../icons"
`,
	)
	testing.expect(t, unsafe.err == .Invalid_Path)
}

test_project_ui_theme_resource_parser_supports_hdr_tokens_and_inheritance :: proc(t: ^testing.T) {
	resource, result := parse_project_resource(
		`id = "71c20000-0000-4000-8000-000000000001"
type = "scrapbot.ui_theme"
name = "Neon Overdrive"

[theme]
base = "reduced_dark"

[theme.palette]
accent = [1.5, 0.25, 0.75, 1]
panel = [0.1, 0.01, 0.2, 0.98]

[theme.metrics]
radius = 18
control_height = 72

[theme.typography]
font = "Arcade"
`,
	)
	testing.expect(t, result.err == .None)
	testing.expect(t, resource.kind == .UI_Theme)
	testing.expect_value(t, resource.ui_theme.theme.palette.accent.x, f32(1.5))
	testing.expect_value(t, resource.ui_theme.theme.metrics.radius, f32(18))
	testing.expect_value(t, resource.ui_theme.theme.font, "Arcade")
	testing.expect_value(
		t,
		resource.ui_theme.theme.palette.warning,
		shared.ui_theme_reduced_dark().palette.warning,
	)

	_, missing_base := parse_project_resource(
		`id = "71c20000-0000-4000-8000-000000000001"
type = "scrapbot.ui_theme"
name = "No Base"
`,
	)
	testing.expect(t, missing_base.err == .Missing_Field)
	_, negative_color := parse_project_resource(
		`id = "71c20000-0000-4000-8000-000000000001"
type = "scrapbot.ui_theme"
name = "Bad Color"
[theme]
base = "reduced_dark"
[theme.palette]
accent = [-1, 0, 0, 1]
`,
	)
	testing.expect(t, negative_color.err == .Invalid_Field)
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
geometry_mode = "auto"
virtual_geometry_budget_mb = 96.5
virtual_geometry_prefetch = false
environment = "a1000000-0000-4000-8000-000000000021"
environment_intensity = 1.25
environment_rotation = 90
exposure = 0.8
background_visible = true
background_environment = "a1000000-0000-4000-8000-000000000021"
background_intensity = 0.7
background_rotation = 45
background_exposure = 1.1
background_blur = 0.25
`,
	)
	defer destroy_project_config(&config)
	testing.expect(t, config_result.err == .None)
	testing.expect_value(t, config.render.geometry_mode, shared.Geometry_Mode.Auto)
	testing.expect_value(t, config.render.virtual_geometry_budget_mb, f32(96.5))
	testing.expect(t, !config.render.virtual_geometry_prefetch)
	testing.expect_value(t, config.render.environment, resource.id)
	testing.expect_value(t, config.render.environment_intensity, f32(1.25))
	testing.expect_value(t, config.render.environment_rotation, f32(90))
	testing.expect_value(t, config.render.exposure, f32(0.8))
	testing.expect(t, config.render.background_visible)
	testing.expect_value(t, config.render.background_environment, resource.id)
	testing.expect_value(t, config.render.background_intensity, f32(0.7))
	testing.expect_value(t, config.render.background_rotation, f32(45))
	testing.expect_value(t, config.render.background_exposure, f32(1.1))
	testing.expect_value(t, config.render.background_blur, f32(0.25))
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
	background := resource
	background.id, _ = shared.resource_uuid_parse("a1000000-0000-4000-8000-000000000022")
	separate_background := config
	separate_background.render.background_environment = background.id
	testing.expect(
		t,
		validate_project_environment_reference(
			&separate_background,
			[]shared.Project_Resource{resource, background},
		) ==
		"",
	)
	background.kind = .Texture
	testing.expect(
		t,
		validate_project_environment_reference(
			&separate_background,
			[]shared.Project_Resource{resource, background},
		) !=
		"",
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

	invalid_background, invalid_background_result := parse_project_config(
		`name = "Invalid Background"
default_scene = "scenes/main.scene.toml"
[render]
background_visible = true
background_blur = 1.5
`,
	)
	defer destroy_project_config(&invalid_background)
	testing.expect(t, invalid_background_result.err == .Invalid_Field)

	invalid_budget, invalid_budget_result := parse_project_config(
		`name = "Invalid Budget"
default_scene = "scenes/main.scene.toml"
[render]
virtual_geometry_budget_mb = 0
`,
	)
	defer destroy_project_config(&invalid_budget)
	testing.expect(t, invalid_budget_result.err == .Invalid_Field)

	tiny_budget, tiny_budget_result := parse_project_config(
		`name = "Tiny Valid Budget"
default_scene = "scenes/main.scene.toml"
[render]
virtual_geometry_budget_mb = 0.015625
`,
	)
	defer destroy_project_config(&tiny_budget)
	testing.expect(t, tiny_budget_result.err == .None)
	testing.expect_value(t, tiny_budget.render.virtual_geometry_budget_mb, f32(0.015625))
	testing.expect(t, tiny_budget.render.virtual_geometry_prefetch)

	legacy_budget, legacy_budget_result := parse_project_config(
		`name = "Legacy Budget"
default_scene = "scenes/main.scene.toml"
[render]
virtual_geometry_index_budget_mb = 32
`,
	)
	defer destroy_project_config(&legacy_budget)
	testing.expect(t, legacy_budget_result.err == .None)
	testing.expect_value(t, legacy_budget.render.virtual_geometry_budget_mb, f32(32))

	missing_background, missing_background_result := parse_project_config(
		`name = "Missing Background"
default_scene = "scenes/main.scene.toml"
[render]
background_visible = true
`,
	)
	defer destroy_project_config(&missing_background)
	testing.expect(t, missing_background_result.err == .None)
	testing.expect(t, validate_project_environment_reference(&missing_background, nil) != "")
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
metallic = 0.65
roughness = 0.2
texture = "a1000000-0000-4000-8000-000000000000"
`,
	)
	testing.expect(t, result.err == .None)
	testing.expect_value(t, resource.name, "Neon")
	testing.expect_value(t, resource.material.base_color, Vec4{0.1, 0.2, 0.3, 1})
	testing.expect_value(t, resource.material.emissive, Vec3{8, 2, 0.5})
	testing.expect_value(t, resource.material.metallic, f32(0.65))
	testing.expect_value(t, resource.material.roughness, f32(0.2))
	texture_id, _ := shared.resource_uuid_parse("a1000000-0000-4000-8000-000000000000")
	testing.expect_value(t, resource.material.texture, texture_id)
}

@(test)
test_project_shader_and_blended_material_parser :: proc(t: ^testing.T) {
	shader, shader_result := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000010"
type = "scrapbot.shader"
name = "Water"
[shader]
source = "shaders/water.wgsl"
cull_mode = "none"

[shader.spectral_surface]
enabled = true
patch_size = 256
wind_speed = 14
wind_direction = [0.8, 0.6]
amplitude = 0.75
small_wave_damping = 0.4
choppiness = 0.9
`,
	)
	testing.expect(t, shader_result.err == .None)
	testing.expect_value(t, shader.kind, shared.Project_Resource_Kind.Shader)
	testing.expect_value(t, shader.shader.source, "shaders/water.wgsl")
	testing.expect_value(t, shader.shader.cull_mode, shared.Shader_Cull_Mode.None)
	testing.expect(t, shader.shader.spectral_surface.enabled)
	testing.expect_value(t, shader.shader.spectral_surface.patch_size, f32(256))
	testing.expect_value(t, shader.shader.spectral_surface.wind_direction, Vec2{0.8, 0.6})
	testing.expect_value(t, shader.shader.spectral_surface.amplitude, f32(0.75))
	testing.expect_value(t, shader.shader.spectral_surface.choppiness, f32(0.9))

	material, material_result := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000011"
type = "scrapbot.material"
name = "Water Material"
[material]
shader = "a1000000-0000-4000-8000-000000000010"
shader_parameters = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
alpha_mode = "blend"
double_sided = true
`,
	)
	testing.expect(t, material_result.err == .None)
	testing.expect_value(t, material.material.alpha_mode, shared.Material_Alpha_Mode.Blend)
	testing.expect_value(t, material.material.shader_parameters[3], Vec4{13, 14, 15, 16})
	testing.expect(t, material.material.double_sided)

	_, unsafe_result := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000012"
type = "scrapbot.shader"
name = "Unsafe"
[shader]
source = "../water.wgsl"
`,
	)
	testing.expect(t, unsafe_result.err == .Invalid_Path)

	_, invalid_spectrum := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000013"
type = "scrapbot.shader"
name = "Still Water"
[shader]
source = "shaders/water.wgsl"
[shader.spectral_surface]
enabled = true
wind_direction = [0, 0]
`,
	)
	testing.expect(t, invalid_spectrum.err == .Invalid_Field)

	_, invalid_choppiness := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000014"
type = "scrapbot.shader"
name = "Looping Water"
[shader]
source = "shaders/water.wgsl"
[shader.spectral_surface]
enabled = true
choppiness = 1.1
`,
	)
	testing.expect(t, invalid_choppiness.err == .Invalid_Field)
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
	defaults, defaults_result := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000003"
type = "scrapbot.material"
name = "Defaults"
[material]
`,
	)
	testing.expect(t, defaults_result.err == .None)
	testing.expect_value(t, defaults.material.metallic, f32(0))
	testing.expect_value(t, defaults.material.roughness, f32(0.8))
	_, invalid_metallic := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000004"
type = "scrapbot.material"
name = "Invalid Metallic"
[material]
metallic = 1.1
`,
	)
	testing.expect(t, invalid_metallic.err == .Invalid_Field)
	_, invalid_roughness := parse_project_resource(
		`id = "a1000000-0000-4000-8000-000000000005"
type = "scrapbot.material"
name = "Invalid Roughness"
[material]
roughness = -0.1
`,
	)
	testing.expect(t, invalid_roughness.err == .Invalid_Field)
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
test_scene_input_icons_require_known_icon_set_uuids :: proc(t: ^testing.T) {
	icon_set, valid := shared.resource_uuid_parse("a1000000-0000-4000-8000-000000000099")
	testing.expect(t, valid)
	input := shared.ui_input_default()
	input.icon_set = icon_set
	input.icon = "search"
	scene := Scene{}
	defer destroy_scene(&scene)
	append(&scene.entities, Scene_Entity{name = "Search", has_ui_input = true, ui_input = input})
	testing.expect(t, validate_scene_resource_references(&scene, nil) != "")
	resources := []shared.Project_Resource{{id = icon_set, kind = .Icon_Set}}
	testing.expect(t, validate_scene_resource_references(&scene, resources) == "")
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
test_scene_camera_exposure_is_positive_and_defaults_to_one :: proc(t: ^testing.T) {
	with_exposure, with_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000090"
name = "Camera"

[entities.camera]
fov = 60
near = 0.1
far = 100
exposure = 1.5
`,
	)
	defer destroy_scene(&with_exposure)
	testing.expect(t, with_result.err == .None)
	testing.expect_value(t, with_exposure.entities[0].camera.exposure, f32(1.5))

	default_exposure, default_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000091"
name = "Camera"

[entities.camera]
fov = 60
near = 0.1
far = 100
`,
	)
	defer destroy_scene(&default_exposure)
	testing.expect(t, default_result.err == .None)
	testing.expect_value(t, default_exposure.entities[0].camera.exposure, f32(1))
	testing.expect(t, default_exposure.entities[0].camera.debug_view == .Lit)
	testing.expect_value(t, default_exposure.entities[0].camera.debug_hiz_mip, f32(0))
	testing.expect_value(
		t,
		shared.camera_resolution_scale(default_exposure.entities[0].camera),
		f32(1),
	)
	testing.expect(t, !default_exposure.entities[0].camera.dynamic_resolution)
	testing.expect_value(
		t,
		shared.camera_dynamic_resolution_min_scale(default_exposure.entities[0].camera),
		f32(0.5),
	)
	testing.expect_value(
		t,
		shared.camera_dynamic_resolution_target_ms(default_exposure.entities[0].camera),
		f32(16.667),
	)
	testing.expect_value(
		t,
		shared.camera_adaptive_quality_minimum(default_exposure.entities[0].camera),
		f32(0.25),
	)
	testing.expect(t, !default_exposure.entities[0].camera.automatic_exposure)
	testing.expect_value(
		t,
		shared.camera_automatic_exposure_min(default_exposure.entities[0].camera),
		f32(0.125),
	)
	testing.expect_value(
		t,
		shared.camera_automatic_exposure_max(default_exposure.entities[0].camera),
		f32(8),
	)
	testing.expect_value(
		t,
		shared.camera_automatic_exposure_speed(default_exposure.entities[0].camera),
		f32(2),
	)
	testing.expect(t, default_exposure.entities[0].camera.temporal_antialiasing)
	testing.expect(t, !default_exposure.entities[0].camera.fast_antialiasing)
	testing.expect(t, default_exposure.entities[0].camera.ambient_occlusion)
	testing.expect_value(
		t,
		default_exposure.entities[0].camera.ambient_occlusion_quality,
		f32(0.5),
	)
	testing.expect_value(
		t,
		shared.camera_ambient_occlusion_resolution_scale(default_exposure.entities[0].camera),
		f32(0.25),
	)
	testing.expect(t, !default_exposure.entities[0].camera.screen_space_reflections)
	testing.expect_value(
		t,
		default_exposure.entities[0].camera.screen_space_reflections_quality,
		f32(0.5),
	)
	testing.expect(t, default_exposure.entities[0].camera.bloom)

	configured, configured_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000093"
name = "Camera"

[entities.camera]
debug_view = "occlusion_queries"
debug_hiz_mip = 5
debug_occlusion_freeze = true
resolution_scale = 0.75
dynamic_resolution = true
dynamic_resolution_min_scale = 0.6
dynamic_resolution_target_ms = 10
adaptive_quality_minimum = 0.5
automatic_exposure = true
automatic_exposure_min = 0.25
automatic_exposure_max = 6
automatic_exposure_speed = 1.5
temporal_antialiasing = false
fast_antialiasing = true
ambient_occlusion = false
ambient_occlusion_quality = 0.75
ambient_occlusion_resolution_scale = 0.5
screen_space_reflections = true
screen_space_reflections_quality = 0.25
bloom = false
`,
	)
	defer destroy_scene(&configured)
	testing.expect(t, configured_result.err == .None)
	testing.expect(t, configured.entities[0].camera.debug_view == .Occlusion_Queries)
	testing.expect_value(t, configured.entities[0].camera.debug_hiz_mip, f32(5))
	testing.expect(t, configured.entities[0].camera.debug_occlusion_freeze)
	testing.expect_value(t, configured.entities[0].camera.resolution_scale, f32(0.75))
	testing.expect(t, configured.entities[0].camera.dynamic_resolution)
	testing.expect_value(t, configured.entities[0].camera.dynamic_resolution_min_scale, f32(0.6))
	testing.expect_value(t, configured.entities[0].camera.dynamic_resolution_target_ms, f32(10))
	testing.expect_value(t, configured.entities[0].camera.adaptive_quality_minimum, f32(0.5))
	testing.expect(t, configured.entities[0].camera.automatic_exposure)
	testing.expect_value(t, configured.entities[0].camera.automatic_exposure_min, f32(0.25))
	testing.expect_value(t, configured.entities[0].camera.automatic_exposure_max, f32(6))
	testing.expect_value(t, configured.entities[0].camera.automatic_exposure_speed, f32(1.5))
	testing.expect(t, !configured.entities[0].camera.temporal_antialiasing)
	testing.expect(t, configured.entities[0].camera.fast_antialiasing)
	testing.expect(t, !configured.entities[0].camera.ambient_occlusion)
	testing.expect_value(t, configured.entities[0].camera.ambient_occlusion_quality, f32(0.75))
	testing.expect_value(
		t,
		configured.entities[0].camera.ambient_occlusion_resolution_scale,
		f32(0.5),
	)
	testing.expect(t, configured.entities[0].camera.screen_space_reflections)
	testing.expect_value(
		t,
		configured.entities[0].camera.screen_space_reflections_quality,
		f32(0.25),
	)
	testing.expect(t, !configured.entities[0].camera.bloom)

	invalid_debug_view, invalid_debug_view_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000099"
name = "Camera"

[entities.camera]
debug_view = "triangles"
`,
	)
	defer destroy_scene(&invalid_debug_view)
	testing.expect(t, invalid_debug_view_result.err == .Invalid_Field)

	invalid, invalid_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000092"
name = "Camera"

[entities.camera]
exposure = 0
`,
	)
	defer destroy_scene(&invalid)
	testing.expect(t, invalid_result.err == .Invalid_Field)

	invalid_range, invalid_range_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000094"
name = "Camera"

[entities.camera]
automatic_exposure_min = 4
automatic_exposure_max = 1
`,
	)
	defer destroy_scene(&invalid_range)
	testing.expect(t, invalid_range_result.err == .Invalid_Field)

	invalid_quality, invalid_quality_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000095"
name = "Camera"

[entities.camera]
ambient_occlusion_quality = 1.25
`,
	)
	defer destroy_scene(&invalid_quality)
	testing.expect(t, invalid_quality_result.err == .Invalid_Field)

	invalid_ao_scale, invalid_ao_scale_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000097"
name = "Camera"

[entities.camera]
ambient_occlusion_resolution_scale = 0.1
`,
	)
	defer destroy_scene(&invalid_ao_scale)
	testing.expect(t, invalid_ao_scale_result.err == .Invalid_Field)

	invalid_reflection_quality, invalid_reflection_quality_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000096"
name = "Camera"

[entities.camera]
screen_space_reflections_quality = 0.1
`,
	)
	defer destroy_scene(&invalid_reflection_quality)
	testing.expect(t, invalid_reflection_quality_result.err == .Invalid_Field)

	invalid_resolution_scale, invalid_resolution_scale_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000097"
name = "Camera"

[entities.camera]
resolution_scale = 0.25
`,
	)
	defer destroy_scene(&invalid_resolution_scale)
	testing.expect(t, invalid_resolution_scale_result.err == .Invalid_Field)

	invalid_dynamic_minimum, invalid_dynamic_minimum_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000098"
name = "Camera"

[entities.camera]
resolution_scale = 0.75
dynamic_resolution_min_scale = 0.9
`,
	)
	defer destroy_scene(&invalid_dynamic_minimum)
	testing.expect(t, invalid_dynamic_minimum_result.err == .Invalid_Field)

	invalid_dynamic_target, invalid_dynamic_target_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000099"
name = "Camera"

[entities.camera]
dynamic_resolution_target_ms = 0.5
`,
	)
	defer destroy_scene(&invalid_dynamic_target)
	testing.expect(t, invalid_dynamic_target_result.err == .Invalid_Field)

	invalid_adaptive_quality, invalid_adaptive_quality_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000101"
name = "Camera"

[entities.camera]
adaptive_quality_minimum = 0.1
`,
	)
	defer destroy_scene(&invalid_adaptive_quality)
	testing.expect(t, invalid_adaptive_quality_result.err == .Invalid_Field)

	invalid_dynamic_zero, invalid_dynamic_zero_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000100"
name = "Camera"

[entities.camera]
dynamic_resolution_min_scale = 0
dynamic_resolution_target_ms = 0
`,
	)
	defer destroy_scene(&invalid_dynamic_zero)
	testing.expect(t, invalid_dynamic_zero_result.err == .Invalid_Field)
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
test_scene_parses_world_environment_component :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000030"
name = "World Environment"

[entities.world_environment]
lighting = ""
lighting_intensity = 0.8
reflection_intensity = 0.55
lighting_rotation = 25
exposure = 1.2
background_visible = true
background = ""
background_intensity = 0.7
background_rotation = -15
background_exposure = 1.1
background_blur = 0.25
sky_tint = [0.9, 1.0, 1.1]
ground_color = [0.2, 0.18, 0.16]
turbidity = 4.5
atmosphere_thickness = 1.4
horizon_softness = 1.6
sun_direction = [0.3, 0.4, -0.8]
sun_color = [1.0, 0.8, 0.6]
sun_intensity = 2.5
sun_size = 1.25
sun_glow = 1.75
`,
	)
	defer destroy_scene(&scene)

	testing.expect_value(t, result.err, Parse_Error.None)
	testing.expect_value(t, len(scene.entities), 1)
	testing.expect(t, scene.entities[0].has_world_environment)
	testing.expect_value(t, scene.entities[0].world_environment.lighting_intensity, f32(0.8))
	testing.expect_value(t, scene.entities[0].world_environment.reflection_intensity, f32(0.55))
	testing.expect(t, scene.entities[0].world_environment.background_visible)
	testing.expect_value(t, scene.entities[0].world_environment.background_blur, f32(0.25))
	testing.expect_value(t, scene.entities[0].world_environment.sky_tint, shared.Vec3{0.9, 1, 1.1})
	testing.expect_value(
		t,
		scene.entities[0].world_environment.ground_color,
		shared.Vec3{0.2, 0.18, 0.16},
	)
	testing.expect_value(t, scene.entities[0].world_environment.turbidity, f32(4.5))
	testing.expect_value(t, scene.entities[0].world_environment.atmosphere_thickness, f32(1.4))
	testing.expect_value(t, scene.entities[0].world_environment.horizon_softness, f32(1.6))
	testing.expect_value(
		t,
		scene.entities[0].world_environment.sun_direction,
		shared.Vec3{0.3, 0.4, -0.8},
	)
	testing.expect_value(
		t,
		scene.entities[0].world_environment.sun_color,
		shared.Vec3{1, 0.8, 0.6},
	)
	testing.expect_value(t, scene.entities[0].world_environment.sun_intensity, f32(2.5))
	testing.expect_value(t, scene.entities[0].world_environment.sun_size, f32(1.25))
	testing.expect_value(t, scene.entities[0].world_environment.sun_glow, f32(1.75))
}

@(test)
test_scene_rejects_invalid_procedural_atmosphere_controls :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000031"
name = "Invalid World Environment"

[entities.world_environment]
atmosphere_thickness = 0
`,
	)
	defer destroy_scene(&scene)

	testing.expect_value(t, result.err, Parse_Error.Invalid_Field)
}

@(test)
test_scene_rejects_zero_procedural_sun_direction :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000032"
name = "Invalid Sun"

[entities.world_environment]
sun_direction = [0, 0, 0]
`,
	)
	defer destroy_scene(&scene)

	testing.expect_value(t, result.err, Parse_Error.Invalid_Field)
}

@(test)
test_scene_rejects_multiple_volumetric_fog_components :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000033"
name = "Fog A"

[entities.components.scrapbot.volumetric_fog]
density = 0.01

[[entities]]
id = "a6000000-0000-4000-8000-000000000034"
name = "Fog B"

[entities.components.scrapbot.volumetric_fog]
density = 0.02
`,
	)
	defer destroy_scene(&scene)

	testing.expect_value(t, result.err, Parse_Error.None)
	testing.expect_value(
		t,
		validate_scene_component_singletons(&scene),
		"a scene may contain only one scrapbot.volumetric_fog component",
	)
}

@(test)
test_scene_rejects_multiple_post_effect_components :: proc(t: ^testing.T) {
	component_names := [?]string{"scrapbot.vignette", "scrapbot.lens_flare", "scrapbot.lens_dirt"}
	for component_name in component_names {
		source := fmt.tprintf(
			`[[entities]]
id = "a6000000-0000-4000-8000-000000000035"
name = "First"
[entities.components.%s]
intensity = 0.2

[[entities]]
id = "a6000000-0000-4000-8000-000000000036"
name = "Second"
[entities.components.%s]
intensity = 0.4
`,
			component_name,
			component_name,
		)
		scene, result := parse_scene(source)
		testing.expect_value(t, result.err, Parse_Error.None)
		expected := fmt.tprintf("a scene may contain only one %s component", component_name)
		testing.expect_value(t, validate_scene_component_singletons(&scene), expected)
		destroy_scene(&scene)
	}
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
test_scene_ui_theme_recipes_resolve_before_explicit_component_overrides :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-0000000000a1"
name = "Themed Action"
ui_theme = "reduced_dark"
ui_recipes = ["primary_button"]

[entities.ui_layout]
size = [240, 72]
corner_radius = 24

[entities.ui_button]
text = "BOOST"

[[entities]]
id = "a6000000-0000-4000-8000-0000000000a2"
name = "Themed Panel"
ui_recipes = ["panel", "scroll_area"]
ui_theme = "reduced_dark"

[entities.ui_panel]
title = "THEME"
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "unexpected parse error: %s", result.message)
	testing.expect(t, len(scene.entities) == 2)
	if len(scene.entities) != 2 {
		return
	}
	theme := shared.ui_theme_reduced_dark()
	action := scene.entities[0]
	testing.expect(t, action.has_ui_layout)
	testing.expect(t, action.has_ui_button)
	testing.expect(t, action.ui_layout.size == shared.Vec2{240, 72})
	testing.expect(t, action.ui_layout.corner_radius == 24)
	testing.expect(t, action.ui_layout.background == theme.palette.accent_soft)
	testing.expect(t, action.ui_layout.border_color == theme.palette.accent)
	testing.expect(t, action.ui_button.text == "BOOST")
	testing.expect(t, action.ui_button.color == theme.palette.accent_text)

	panel := scene.entities[1]
	testing.expect(t, panel.has_ui_layout)
	testing.expect(t, panel.has_ui_panel)
	testing.expect(t, panel.has_ui_scroll_area)
	testing.expect(t, panel.ui_layout.background == theme.palette.panel)
	testing.expect(t, panel.ui_panel.title == "THEME")
	testing.expect(t, panel.ui_scroll_area.scrollbar_thumb_color == theme.palette.border_strong)
}

test_scene_project_ui_theme_resource_resolves_before_explicit_overrides :: proc(t: ^testing.T) {
	theme_id, _ := shared.resource_uuid_parse("71c20000-0000-4000-8000-000000000001")
	theme := shared.ui_theme_reduced_dark()
	theme.palette.accent_soft = {1.25, 0.1, 0.4, 1}
	theme.palette.accent_text = {0.95, 1, 0.2, 1}
	theme.metrics.radius = 24
	theme.font = "Inter"
	resources := []shared.Project_Resource {
		{id = theme_id, kind = .UI_Theme, name = "Neon", ui_theme = {theme = theme}},
	}
	scene, result := parse_scene(
		`[[entities]]
id = "30000000-0000-4000-8000-000000000001"
name = "Action"
ui_theme = "71c20000-0000-4000-8000-000000000001"
ui_recipes = ["primary_button"]

[entities.ui_layout]
size = [220, 76]

[entities.ui_button]
text = "BOOST"
`,
		resources,
	)
	defer destroy_scene(&scene)
	testing.expect(t, result.err == .None)
	testing.expect_value(t, scene.entities[0].ui_theme_resource, theme_id)
	testing.expect_value(t, scene.entities[0].ui_layout.background, theme.palette.accent_soft)
	testing.expect_value(t, scene.entities[0].ui_layout.size, shared.Vec2{220, 76})
	testing.expect_value(t, scene.entities[0].ui_button.text, "BOOST")
	testing.expect_value(t, scene.entities[0].ui_button.font, "Inter")

	unknown, unknown_result := parse_scene(
		`[[entities]]
id = "30000000-0000-4000-8000-000000000001"
name = "Unknown"
ui_theme = "71c20000-0000-4000-8000-000000000002"
ui_recipes = ["primary_button"]
`,
		resources,
	)
	defer destroy_scene(&unknown)
	testing.expect(t, unknown_result.err == .Invalid_Field)
}

@(test)
test_scene_ui_theme_directives_require_supported_complete_pairs :: proc(t: ^testing.T) {
	missing_recipes, missing_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-0000000000b1"
name = "Missing Recipes"
ui_theme = "reduced_dark"
`,
	)
	defer destroy_scene(&missing_recipes)
	testing.expect(t, missing_result.err == .Invalid_Field)

	unsupported, unsupported_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-0000000000b2"
name = "Unsupported Recipe"
ui_theme = "reduced_dark"
ui_recipes = ["glow_everything"]
`,
	)
	defer destroy_scene(&unsupported)
	testing.expect(t, unsupported_result.err == .Invalid_Field)
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
border_dash_length = 12
border_dash_gap = 8
border_dash_offset = 3
corner_radius = 6
hidden = true
fill_width = true
fill_height = true
fit_content_width = true
fit_content_height = true
fixed_in_fill = true
basis = 96
grow = 2
shrink = 3
stack_order = 7
horizontal_alignment = "center"
vertical_alignment = "end"
[entities.ui_canvas]
reference_size = [1600, 900]
scale_mode = "expand"
horizontal_alignment = "center"
vertical_alignment = "end"
safe_area = [24, 32, 40, 48]
min_scale = 0.5
max_scale = 3
[entities.ui_vstack]
gap = 8
fill = true
draggable = true
min_size = 72
reorderable = true
drag_threshold = 6
drop_indicator_color = [0.2, 1.4, 1.1, 1]
drop_indicator_thickness = 3
drop_indicator_inset = 9
line_gap = 5
[entities.ui_panel]
title = "METRICS"
title_color = [0.9, 0.9, 0.9, 1]
title_background = [0.12, 0.13, 0.14, 1]
title_size = 11
title_height = 28
disclosure_size = 9
disclosure_margin = 7
disclosure_gap = 6
disclosure_inset = 0
collapsible = true
collapsed = true
movable = true
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
wrap = true
line_height = 30
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
	testing.expect(t, scene.entities[0].ui_vstack.reorderable)
	testing.expect(t, scene.entities[0].ui_vstack.drag_threshold == 6)
	testing.expect(t, scene.entities[0].ui_vstack.drop_indicator_color.y == 1.4)
	testing.expect(t, scene.entities[0].ui_vstack.drop_indicator_thickness == 3)
	testing.expect(t, scene.entities[0].ui_vstack.drop_indicator_inset == 9)
	testing.expect(t, scene.entities[0].ui_vstack.line_gap == 5)
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
	testing.expect(t, scene.entities[0].ui_panel.disclosure_inset == 0)
	testing.expect(t, scene.entities[0].ui_panel.collapsible)
	testing.expect(t, scene.entities[0].ui_panel.collapsed)
	testing.expect(t, scene.entities[0].ui_panel.movable)
	testing.expect(t, scene.entities[0].ui_layout.border_color == Vec4{0.4, 0.5, 0.6, 1})
	testing.expect(t, scene.entities[0].ui_layout.border_width == 2)
	testing.expect(t, scene.entities[0].ui_layout.border_dash_length == 12)
	testing.expect(t, scene.entities[0].ui_layout.border_dash_gap == 8)
	testing.expect(t, scene.entities[0].ui_layout.border_dash_offset == 3)
	testing.expect(t, scene.entities[0].ui_layout.corner_radius == 6)
	testing.expect(t, scene.entities[0].ui_layout.hidden)
	testing.expect(t, scene.entities[0].ui_layout.stack_order == 7)
	testing.expect(t, scene.entities[0].ui_layout.min_size == Vec2{320, 160})
	testing.expect(t, scene.entities[0].ui_layout.fill_width)
	testing.expect(t, scene.entities[0].ui_layout.fill_height)
	testing.expect(t, scene.entities[0].ui_layout.fit_content_width)
	testing.expect(t, scene.entities[0].ui_layout.fit_content_height)
	testing.expect(t, scene.entities[0].ui_layout.fixed_in_fill)
	testing.expect(t, scene.entities[0].ui_layout.basis == 96)
	testing.expect(t, scene.entities[0].ui_layout.grow == 2)
	testing.expect(t, scene.entities[0].ui_layout.shrink == 3)
	testing.expect(t, scene.entities[0].ui_layout.horizontal_alignment == .Center)
	testing.expect(t, scene.entities[0].ui_layout.vertical_alignment == .End)
	testing.expect(t, scene.entities[0].has_ui_canvas)
	testing.expect(t, scene.entities[0].ui_canvas.reference_size == Vec2{1600, 900})
	testing.expect(t, scene.entities[0].ui_canvas.scale_mode == .Expand)
	testing.expect(t, scene.entities[0].ui_canvas.horizontal_alignment == .Center)
	testing.expect(t, scene.entities[0].ui_canvas.vertical_alignment == .End)
	testing.expect(t, scene.entities[0].ui_canvas.safe_area == Vec4{24, 32, 40, 48})
	testing.expect_value(t, scene.entities[0].ui_canvas.min_scale, f32(0.5))
	testing.expect_value(t, scene.entities[0].ui_canvas.max_scale, f32(3))
	hud_id, hud_id_ok := shared.entity_uuid_parse("a6000000-0000-4000-8000-00000000000a")
	testing.expect(t, hud_id_ok && scene.entities[1].ui_layout.parent == hud_id)
	testing.expect(t, scene.entities[1].ui_text.text == "HELLO")
	testing.expect(t, scene.entities[1].ui_text.alignment == .Right)
	testing.expect(t, scene.entities[1].ui_text.wrap)
	testing.expect(t, scene.entities[1].ui_text.line_height == 30)
	testing.expect(t, scene.entities[2].has_ui_table)
	testing.expect(t, scene.entities[2].ui_table.columns == 3)
	testing.expect(t, scene.entities[2].ui_table.column_gap == 6)
	testing.expect(t, scene.entities[2].ui_table.row_gap == 4)
	testing.expect(t, scene.entities[2].ui_table.proportional_columns)
	testing.expect(t, scene.entities[2].ui_table.resizable_columns)
	testing.expect(t, scene.entities[2].ui_table.min_column_width == 48)
}

@(test)
test_scene_parses_dock_spaces_and_validates_item_references :: proc(t: ^testing.T) {
	scene, result := parse_scene(
		`[[entities]]
id = "a6100000-0000-4000-8000-000000000001"
name = "Dock"
[entities.ui_layout]
size = [640, 480]
[entities.ui_dock_space]
active = "a6100000-0000-4000-8000-000000000002"
font = "Inter"
tab_height = 36
tab_min_width = 80
tab_max_width = 200
tab_gap = 4
tab_padding = 14
tab_size = 13
tab_corner_radius = 6
tab_connection_height = 5
tab_content_overlap = 3
tab_strip_background = [0.03, 0.04, 0.05, 1]
content_background = [0.11, 0.12, 0.13, 1]
content_corner_radius = 7
content_padding = [2, 3, 4, 5]
tab_color = [0.6, 0.7, 0.8, 1]
tab_active_color = [1.2, 1.1, 1.0, 1]
tab_background = [0.02, 0.03, 0.04, 1]
tab_hover_background = [0.08, 0.09, 0.10, 1]
tab_active_background = [0.12, 0.13, 0.14, 1]
drop_background = [0.1, 1.4, 0.8, 0.25]
draggable = false
split_horizontal = true
split_vertical = true
split_ratio = 0.4
split_edge_fraction = 0.2
split_gap = 6
split_min_size = 140
[[entities]]
id = "a6100000-0000-4000-8000-000000000002"
name = "Scene"
[entities.ui_layout]
parent = "a6100000-0000-4000-8000-000000000001"
size = [640, 444]
[entities.ui_dock_item]
title = "SCENE"
movable = false
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "parse failed: %s", result.message)
	testing.expect(t, scene.entities[0].has_ui_dock_space)
	testing.expect(t, scene.entities[0].ui_dock_space.active == scene.entities[1].id)
	testing.expect(t, scene.entities[0].ui_dock_space.font == "Inter")
	testing.expect(t, scene.entities[0].ui_dock_space.tab_height == 36)
	testing.expect(t, scene.entities[0].ui_dock_space.tab_connection_height == 5)
	testing.expect(t, scene.entities[0].ui_dock_space.tab_content_overlap == 3)
	testing.expect(t, scene.entities[0].ui_dock_space.tab_strip_background.z == 0.05)
	testing.expect(t, scene.entities[0].ui_dock_space.content_background.x == 0.11)
	testing.expect(t, scene.entities[0].ui_dock_space.content_corner_radius == 7)
	testing.expect(t, scene.entities[0].ui_dock_space.content_padding.w == 5)
	testing.expect(t, scene.entities[0].ui_dock_space.tab_active_color.x == 1.2)
	testing.expect(t, !scene.entities[0].ui_dock_space.draggable)
	testing.expect(t, scene.entities[0].ui_dock_space.split_horizontal)
	testing.expect(t, scene.entities[0].ui_dock_space.split_vertical)
	testing.expect(t, scene.entities[0].ui_dock_space.split_ratio == 0.4)
	testing.expect(t, scene.entities[0].ui_dock_space.split_edge_fraction == 0.2)
	testing.expect(t, scene.entities[0].ui_dock_space.split_gap == 6)
	testing.expect(t, scene.entities[0].ui_dock_space.split_min_size == 140)
	testing.expect(t, scene.entities[1].has_ui_dock_item)
	testing.expect(t, scene.entities[1].ui_dock_item.title == "SCENE")
	testing.expect(t, !scene.entities[1].ui_dock_item.movable)

	panel_scene, panel_result := parse_scene(
		`[[entities]]
id = "a6150000-0000-4000-8000-000000000001"
name = "Dock"
[entities.ui_layout]
size = [640, 480]
[entities.ui_dock_space]
active = "a6150000-0000-4000-8000-000000000002"
[[entities]]
id = "a6150000-0000-4000-8000-000000000002"
name = "Tools"
[entities.ui_layout]
parent = "a6150000-0000-4000-8000-000000000001"
size = [640, 448]
[entities.ui_panel]
title = "TOOLS"
movable = true
`,
	)
	defer destroy_scene(&panel_scene)
	testing.expectf(
		t,
		panel_result.err == .None,
		"panel dock parse failed: %s",
		panel_result.message,
	)
	testing.expect(t, panel_scene.entities[1].has_ui_panel)
	testing.expect(t, panel_scene.entities[1].ui_panel.movable)

	invalid_sources := [2]string {
		`[[entities]]
id = "a6200000-0000-4000-8000-000000000001"
name = "Dock"
[entities.ui_layout]
size = [640, 480]
[entities.ui_dock_space]
active = "a6200000-0000-4000-8000-000000000099"
`,
		`[[entities]]
id = "a6300000-0000-4000-8000-000000000001"
name = "Plain Parent"
[entities.ui_layout]
size = [640, 480]
[[entities]]
id = "a6300000-0000-4000-8000-000000000002"
name = "Orphan Tab"
[entities.ui_layout]
parent = "a6300000-0000-4000-8000-000000000001"
size = [640, 444]
[entities.ui_dock_item]
title = "ORPHAN"
`,
	}
	for source in invalid_sources {
		invalid_scene, invalid_result := parse_scene(source)
		destroy_scene(&invalid_scene)
		testing.expect(t, invalid_result.err == .Invalid_Field)
	}
}

@(test)
test_scene_rejects_invalid_responsive_ui_metrics_and_stack_modes :: proc(t: ^testing.T) {
	sources := [3]string {
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000040"
name = "Invalid Flex"
[entities.ui_layout]
size = [100, 40]
grow = -1
`,
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000041"
name = "Invalid Wrapped Fill"
[entities.ui_layout]
size = [100, 40]
[entities.ui_hstack]
fill = true
wrap = true
`,
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000042"
name = "Invalid Line Height"
[entities.ui_layout]
size = [100, 40]
[entities.ui_text]
text = "Nope"
line_height = -1
`,
	}
	for source in sources {
		scene, result := parse_scene(source)
		destroy_scene(&scene)
		testing.expect(t, result.err == .Invalid_Field)
	}
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
filter_input = "a6000000-0000-4000-8000-000000000031"
gap = 3
selection_background = [0.1, 0.5, 0.4, 1]
hover_background = [0.2, 0.3, 0.4, 1]
active_background = [0.3, 0.4, 0.5, 1]
highlight_corner_radius = 6
draggable = true
drag_threshold = 7
drop_edge_fraction = 0.2
drop_target_background = [0.05, 0.1, 0.15, 1]
tree_enabled = true
tree_indent = 18
virtualized = true
item_height = 30
overscan = 4
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
	testing.expect(t, list.filter_input == selected_id)
	testing.expect(t, list.gap == 3)
	testing.expect(t, list.selection_background == Vec4{0.1, 0.5, 0.4, 1})
	testing.expect(t, list.hover_background == Vec4{0.2, 0.3, 0.4, 1})
	testing.expect(t, list.active_background == Vec4{0.3, 0.4, 0.5, 1})
	testing.expect(t, list.highlight_corner_radius == 6)
	testing.expect(t, list.draggable)
	testing.expect(t, list.drag_threshold == 7)
	testing.expect(t, list.drop_edge_fraction == 0.2)
	testing.expect(t, list.drop_target_background == Vec4{0.05, 0.1, 0.15, 1})
	testing.expect(t, list.tree_enabled)
	testing.expect(t, list.tree_indent == 18)
	testing.expect(t, list.virtualized)
	testing.expect(t, list.item_height == 30)
	testing.expect(t, list.overscan == 4)
	testing.expect(t, scene.entities[1].ui_layout.tree_item)
	testing.expect(t, scene.entities[1].ui_layout.tree_parent == selected_id)
	testing.expect(t, scene.entities[1].ui_layout.tree_order == 7)
	testing.expect(t, scene.entities[1].ui_layout.tree_collapsed)

	invalid, invalid_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000032"
name = "Invalid List Radius"
[entities.ui_layout]
size = [240, 160]
[entities.ui_list]
highlight_corner_radius = -1
`,
	)
	defer destroy_scene(&invalid)
	testing.expect(t, invalid_result.err == .Invalid_Field)
}

@(test)
test_scene_parses_public_popup_anchors_and_button_targets :: proc(t: ^testing.T) {
	popup_id, _ := shared.entity_uuid_parse("a6000000-0000-4000-8000-000000000041")
	button_id, _ := shared.entity_uuid_parse("a6000000-0000-4000-8000-000000000040")
	scene, result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000040"
name = "Popup Button"
[entities.ui_layout]
size = [180, 30]
[entities.ui_button]
text = "Choose"
popup = "a6000000-0000-4000-8000-000000000041"
[[entities]]
id = "a6000000-0000-4000-8000-000000000041"
name = "Popup"
[entities.ui_layout]
size = [180, 420]
popup = true
popup_anchor = "a6000000-0000-4000-8000-000000000040"
popup_open = true
popup_close_on_selection = true
popup_gap = 4
popup_min_width = 180
popup_max_width = 320
popup_max_height = 160
popup_viewport_margin = 6
[entities.ui_vstack]
fill = true
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "parse failed: %s", result.message)
	testing.expect_value(t, len(scene.entities), 2)
	if len(scene.entities) != 2 {
		return
	}
	testing.expect_value(t, scene.entities[0].ui_button.popup, popup_id)
	layout := scene.entities[1].ui_layout
	testing.expect(t, layout.popup)
	testing.expect_value(t, layout.popup_anchor, button_id)
	testing.expect(t, layout.popup_open && layout.popup_close_on_selection)
	testing.expect(t, layout.popup_gap == 4)
	testing.expect(t, layout.popup_min_width == 180)
	testing.expect(t, layout.popup_max_width == 320)
	testing.expect(t, layout.popup_max_height == 160)
	testing.expect(t, layout.popup_viewport_margin == 6)

	invalid, invalid_result := parse_scene(
		`[[entities]]
id = "a6000000-0000-4000-8000-000000000042"
name = "Broken Popup Button"
[entities.ui_layout]
size = [180, 30]
[entities.ui_button]
text = "Choose"
popup = "a6000000-0000-4000-8000-000000000043"
`,
	)
	defer destroy_scene(&invalid)
	testing.expect(t, invalid_result.err == .Invalid_Field)
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
icon_set = "a11c0000-0000-4000-8000-000000000001"
icon = "x"
icon_position = "trailing"
icon_size = 16
icon_gap = 4
icon_inset = 5
panel_action = true
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "%s", result.message)
	testing.expect(t, len(scene.entities) == 2)
	testing.expect(t, scene.entities[1].has_ui_button)
	testing.expect(t, scene.entities[1].ui_button.icon_set == shared.builtin_icon_set_uuid())
	testing.expect(t, scene.entities[1].ui_button.icon == "x")
	testing.expect(t, scene.entities[1].ui_button.icon_position == .Trailing)
	testing.expect(t, scene.entities[1].ui_button.icon_size == 16)
	testing.expect(t, scene.entities[1].ui_button.icon_gap == 4)
	testing.expect(t, scene.entities[1].ui_button.icon_inset == 5)
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
icon_set = "a11c0000-0000-4000-8000-000000000001"
icon = "magnifying-glass"
icon_position = "trailing"
color = [0.9, 0.9, 0.9, 1]
icon_color = [0.6, 0.7, 0.8, 1]
prefix_color = [0.9, 0.3, 0.3, 1]
prefix_background = [0.9, 0.3, 0.3, 0.12]
size = 13
icon_size = 14
icon_gap = 5
icon_inset = 1
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
	testing.expect(t, input.icon_set == shared.builtin_icon_set_uuid())
	testing.expect(t, input.icon == "magnifying-glass")
	testing.expect(t, input.icon_position == .Trailing)
	testing.expect(t, input.icon_color == Vec4{0.6, 0.7, 0.8, 1})
	testing.expect(t, input.size == 13)
	testing.expect(t, input.icon_size == 14 && input.icon_gap == 5 && input.icon_inset == 1)
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
test_scene_parses_hdr_ui_color_picker :: proc(t: ^testing.T) {
	source := `
[[entities]]
id = "70000000-0000-4000-8000-000000000001"
name = "HDR picker"

[entities.ui_layout]
size = [280, 232]

[entities.ui_color_picker]
value = [4, 2, 1, 0.75]
hdr = true
show_alpha = true
exposure = 2
maximum_exposure = 12
`
	scene, result := parse_scene(source)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "parse failed: %s", result.message)
	testing.expect_value(t, len(scene.entities), 1)
	entity := scene.entities[0]
	testing.expect(t, entity.has_ui_color_picker)
	testing.expect_value(t, entity.ui_color_picker.value, Vec4{4, 2, 1, 0.75})
	testing.expect(t, entity.ui_color_picker.exposure == 2)
	testing.expect(t, entity.ui_color_picker.maximum_exposure == 12)
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
geometry_mode = "conventional"
`,
	)
	defer destroy_scene(&scene)
	testing.expectf(t, result.err == .None, "parse failed: %s", result.message)
	testing.expect_value(t, len(scene.entities), 1)
	if len(scene.entities) == 1 {
		testing.expect(t, scene.entities[0].has_model)
		testing.expect_value(
			t,
			scene.entities[0].model.resource,
			"a7000000-0000-4000-8000-000000000001",
		)
		testing.expect_value(
			t,
			scene.entities[0].model.geometry_mode,
			shared.Geometry_Mode.Conventional,
		)
	}
}

@(test)
test_geometry_mode_configuration_rejects_unknown_and_explicit_inherit_modes :: proc(
	t: ^testing.T,
) {
	modes := [2]string{"inherit", "definitely-not-a-mode"}
	for mode in modes {
		config, result := parse_project_config(
			fmt.tprintf(
				`name = "Bad Geometry Mode"
default_scene = "scenes/main.scene.toml"
[render]
geometry_mode = "%s"
`,
				mode,
			),
		)
		destroy_project_config(&config)
		testing.expect(t, result.err == .Invalid_Field)
	}
}
