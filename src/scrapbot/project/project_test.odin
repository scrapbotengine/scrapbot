package project

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
`)
	testing.expect(t, result.err == .None)
	testing.expect(t, config.name == "Demo #1")
	testing.expect(t, config.default_scene == "scenes/main.scene.toml")
}

@(test)
test_project_config_rejects_unescaped_string_bodies :: proc(t: ^testing.T) {
	_, result := parse_project_config("name = \"Bad \\ Game\"\ndefault_scene = \"scenes/main.scene.toml\"\n")
	testing.expect(t, result.err == .Invalid_Field)
}
