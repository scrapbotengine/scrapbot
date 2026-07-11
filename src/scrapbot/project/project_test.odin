package project

import "core:os"
import "core:path/filepath"
import "core:testing"

@(test)
test_project_config_requires_safe_scene_path :: proc(t: ^testing.T) {
	config, result := parse_project_config(`name = "Demo"
default_scene = "../outside.scene.toml"
`)
	testing.expect(t, result.err == .Invalid_Path)
	testing.expect(t, config.default_scene == "../outside.scene.toml")
}

@(test)
test_project_config_accepts_project_toml_shape :: proc(t: ^testing.T) {
	config, result := parse_project_config(`name = "Demo #1" # comments are allowed outside strings
default_scene = "scenes/main.scene.toml"

[[native_extensions]]
name = "scrappyphysics"
source = "native/scrappyphysics"
`)
	defer destroy_project_config(&config)
	testing.expect(t, result.err == .None)
	testing.expect(t, config.name == "Demo #1")
	testing.expect(t, config.default_scene == "scenes/main.scene.toml")
	testing.expect(t, len(config.native_extensions) == 1)
	testing.expect(t, config.native_extensions[0].name == "scrappyphysics")
	testing.expect(t, config.native_extensions[0].source == "native/scrappyphysics")
}

@(test)
test_project_config_rejects_unescaped_string_bodies :: proc(t: ^testing.T) {
	_, result := parse_project_config("name = \"Bad \\ Game\"\ndefault_scene = \"scenes/main.scene.toml\"\n")
	testing.expect(t, result.err == .Invalid_Field)
}

@(test)
test_project_config_requires_safe_native_extension_source_path :: proc(t: ^testing.T) {
	config, result := parse_project_config(`name = "Demo"
default_scene = "scenes/main.scene.toml"

[[native_extensions]]
name = "faststuff"
source = "../faststuff"
`)
	defer destroy_project_config(&config)
	testing.expect(t, result.err == .Invalid_Path)
}

@(test)
test_scene_accepts_namespaced_component_names :: proc(t: ^testing.T) {
	scene, result := parse_scene(`[[entities]]
name = "Body"

[entities.components.scrappyphysics.rigidbody]
velocity = [0, 0, 0]
`)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .None)
	testing.expect(t, len(scene.entities) == 1)
	testing.expect(t, len(scene.entities[0].custom_components) == 1)
	testing.expect(t, scene.entities[0].custom_components[0].name == "scrappyphysics.rigidbody")
}

@(test)
test_scene_rejects_malformed_component_names :: proc(t: ^testing.T) {
	scene, result := parse_scene(`[[entities]]
name = "Body"

[entities.components.scrappyphysics..rigidbody]
velocity = [0, 0, 0]
`)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .Invalid_Field)
}

@(test)
test_scene_component_fields_are_single_tokens :: proc(t: ^testing.T) {
	scene, result := parse_scene(`[[entities]]
name = "Body"

[entities.components.autorotate]
rotation.velocity = [0, 0, 0]
`)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .Invalid_Field)
}

@(test)
test_project_check_accepts_registered_namespaced_scene_components :: proc(t: ^testing.T) {
	scene, result := parse_scene(`[[entities]]
name = "Body"

[entities.components.scrapbot.transform]
position = [0, 0, 0]
`)
	defer destroy_scene(&scene)

	testing.expect(t, result.err == .None)
	testing.expect(t, validate_namespaced_scene_components(&scene) == "")
}

@(test)
test_project_check_rejects_unknown_namespaced_scene_components :: proc(t: ^testing.T) {
	scene, result := parse_scene(`[[entities]]
name = "Body"

[entities.components.scrappyphysics.rigidbody]
velocity = [0, 0, 0]
`)
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
