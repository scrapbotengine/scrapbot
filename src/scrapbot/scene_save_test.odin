package scrapbot

import ecs "./ecs"
import project "./project"
import shared "./shared"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

SCENE_SAVE_TEST_SOURCE :: `[[entities]]
id = "a5000000-0000-4000-8000-000000000001"
name = "Duplicate Name"

[entities.transform]
position = [1, 2, 3] # preserve this comment
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.point_light]
color = [1, 1, 1]
intensity = 2
range = 3

[entities.ui_layout]
size = [100, 40]

[entities.ui_checkbox]
checked = false

[entities.components.velocity]
amount = [1, 0, 0]

[[entities]]
id = "a5000000-0000-4000-8000-000000000002"
name = "Duplicate Name"

[entities.transform]
position = [9, 9, 9]
rotation = [0, 0, 0]
scale = [1, 1, 1]
`

@(test)
test_scene_save_patches_scene_entities_by_uuid_and_preserves_source_structure :: proc(
	t: ^testing.T,
) {
	directory, directory_err := os.make_directory_temp(
		"",
		"scrapbot-scene-save-*",
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
	testing.expect(t, os.write_entire_file(scene_path, SCENE_SAVE_TEST_SOURCE) == nil)

	loaded := project.load_scene_file(scene_path)
	testing.expectf(t, loaded.err == "", "failed to load scene fixture: %s", loaded.err)
	if loaded.err != "" {
		project.destroy_scene_load_result(&loaded)
		return
	}
	world := ecs.build_world(&loaded.scene)
	project.destroy_scene_load_result(&loaded)
	defer ecs.destroy_world(&world)
	first_id, first_id_ok := shared.entity_uuid_parse("a5000000-0000-4000-8000-000000000001")
	testing.expect(t, first_id_ok)
	first_index, first_found := ecs.entity_index_by_uuid(&world, first_id)
	testing.expect(t, first_found)
	if !first_found {
		return
	}
	first := &world.entities[first_index]
	world.transforms[first.transform_index].position = {-4.5, 6.25, 8}
	world.point_lights[first.point_light_index].intensity = 12.5
	world.ui_checkboxes[first.ui_checkbox_index].checked = true
	for &storage in world.custom_components {
		if storage.name != "velocity" {
			continue
		}
		for &component in storage.components {
			if component.entity_index == first_index {
				component.vec3_fields[0].value = {0, 2.5, -1}
			}
		}
	}
	spawn: ecs.Spawn_Command
	testing.expect(t, ecs.init_spawn_command(&spawn, "Runtime Spawn") == "")
	_ = ecs.spawn_entity(&world, &spawn)

	save_err := save_scene_world(scene_path, &world)
	testing.expectf(t, save_err == "", "save_scene_world failed: %s", save_err)
	saved_bytes, read_err := os.read_entire_file(scene_path, context.temp_allocator)
	testing.expectf(t, read_err == nil, "failed to read saved scene: %v", read_err)
	if read_err != nil {
		return
	}
	saved := string(saved_bytes)
	testing.expect(
		t,
		strings.contains(saved, "position = [-4.5, 6.25, 8] # preserve this comment"),
	)
	testing.expect(t, strings.contains(saved, "intensity = 12.5"))
	testing.expect(t, strings.contains(saved, "checked = true"))
	testing.expect(t, strings.contains(saved, "read_only = false"))
	testing.expect(t, strings.contains(saved, "amount = [0, 2.5, -1]"))
	testing.expect(t, strings.contains(saved, "position = [9, 9, 9]"))
	testing.expect(t, !strings.contains(saved, "Runtime Spawn"))
	temp_path, temp_path_err := strings.concatenate({scene_path, ".scrapbot-save.tmp"})
	testing.expect(t, temp_path_err == nil)
	if temp_path_err == nil {
		testing.expect(t, !os.exists(temp_path))
		delete(temp_path)
	}

	reloaded := project.load_scene_file(scene_path)
	defer project.destroy_scene_load_result(&reloaded)
	testing.expectf(t, reloaded.err == "", "saved scene no longer parses: %s", reloaded.err)
}
