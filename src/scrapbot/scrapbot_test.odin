package scrapbot

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

@(test)
test_scene_builds_world_with_soa_transforms :: proc(t: ^testing.T) {
	scene, result := parse_scene(default_scene_template())
	defer delete(scene.entities)

	testing.expect(t, result.err == .None)
	testing.expect(t, len(scene.entities) == 2)

	world := build_world(&scene)
	defer destroy_world(&world)

	testing.expect(t, len(world.entities) == 2)
	testing.expect(t, len(world.transforms) == 2)
	testing.expect(t, len(world.cameras) == 1)
	testing.expect(t, len(world.meshes) == 1)
	testing.expect(t, world.transforms[1].position == Vec3{0, 0, 0})
}

@(test)
test_renderer_backend_names_parse :: proc(t: ^testing.T) {
	backend, ok := parse_renderer_backend("null")
	testing.expect(t, ok)
	testing.expect(t, backend == .Null)

	backend, ok = parse_renderer_backend("wgpu-native")
	testing.expect(t, ok)
	testing.expect(t, backend == .WGPU)

	_, ok = parse_renderer_backend("potato")
	testing.expect(t, !ok)
}
