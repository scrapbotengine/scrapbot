package scrapbot

import ecs "./ecs"
import script "./script"
import shared "./shared"
import "core:os"
import "core:path/filepath"
import "core:testing"

SCENE_RESET_TEST_SOURCE :: `[[entities]]
id = "a4000000-0000-4000-8000-000000000001"
name = "Restored Entity"

[entities.transform]
position = [1, 2, 3]
rotation = [0, 0, 0]
scale = [1, 1, 1]
`

@(test)
test_scene_reset_replaces_world_without_replacing_script_runtime :: proc(t: ^testing.T) {
	directory, directory_err := os.make_directory_temp(
		"",
		"scrapbot-scene-reset-*",
		context.temp_allocator,
	)
	testing.expectf(t, directory_err == nil, "failed to create temp directory: %v", directory_err)
	if directory_err != nil {
		return
	}
	defer os.remove_all(directory)
	scene_path, path_err := filepath.join({directory, "scene.toml"})
	testing.expectf(t, path_err == nil, "failed to allocate scene path: %v", path_err)
	if path_err != nil {
		return
	}
	defer delete(scene_path)
	testing.expect(t, os.write_entire_file(scene_path, SCENE_RESET_TEST_SOURCE) == nil)

	world: shared.World
	defer ecs.destroy_world(&world)
	world.time.frame_index = 42
	runtime: script.Runtime
	runtime.system_count = 3
	runtime_before := &runtime

	reset_err := reset_scene_world(scene_path, &runtime, &world)
	testing.expectf(t, reset_err == "", "reset_scene_world failed: %s", reset_err)
	testing.expect(t, &runtime == runtime_before)
	testing.expect(t, runtime.system_count == 3)
	testing.expect(t, runtime.world == &world)
	testing.expect(t, world.time.frame_index == 0)
	testing.expect(t, len(world.entities) == 1)
	testing.expect(t, world.entities[0].name == "Restored Entity")
}
