package scrapbot

import ecs "./ecs"
import project "./project"
import shared "./shared"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:testing"

SCENE_SAVE_TEST_SOURCE :: `[[entities]]
id = "a5000000-0000-4000-8000-000000000001"
name = "Duplicate Name"

[entities.transform]
position = [1, 2, 3] # preserve this comment
rotation = [0.12, 0.18, 0.32]
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
position = [9.1, 0.12, -0.8]
rotation = [0, 0, 0]
scale = [1, 1, 1]
`

@(test)
test_scene_float_format_is_short_human_readable_and_roundtrips_f32 :: proc(t: ^testing.T) {
	testing.expect(t, scene_f32(f32(0.12)) == "0.12")
	value := f32(1.2345678)
	formatted := scene_f32(value)
	parsed, ok := strconv.parse_f32(formatted)
	testing.expect(t, ok && parsed == value)
}

@(test)
test_scene_camera_serialization_persists_effective_exposure :: proc(t: ^testing.T) {
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	entity := shared.Scene_Entity {
		id = shared.entity_uuid_from_engine_name("scene-save-camera"),
		name = "Camera",
		has_camera = true,
		camera = {fov = 60, near = 0.1, far = 100, exposure = 1.5},
	}
	write_scene_entity(&builder, &entity)
	testing.expect(t, strings.contains(strings.to_string(builder), "exposure = 1.5"))
}

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

	dirty_entities := [1]shared.Entity_UUID{first_id}
	save_err := save_scene_world(scene_path, &world, dirty_entities[:])
	testing.expectf(t, save_err == "", "save_scene_world failed: %s", save_err)
	saved_bytes, read_err := os.read_entire_file(scene_path, context.temp_allocator)
	testing.expectf(t, read_err == nil, "failed to read saved scene: %v", read_err)
	if read_err != nil {
		return
	}
	saved := string(saved_bytes)
	expected := strings.builder_make()
	defer strings.builder_destroy(&expected)
	strings.write_string(&expected, SCENE_SAVE_TEST_SOURCE)
	replaced, replace_err := strings.builder_replace(
		&expected,
		"position = [1, 2, 3]",
		"position = [-4.5, 6.25, 8]",
		1,
	)
	testing.expect(t, replace_err == nil && replaced == 1)
	replaced, replace_err = strings.builder_replace(
		&expected,
		"intensity = 2",
		"intensity = 12.5",
		1,
	)
	testing.expect(t, replace_err == nil && replaced == 1)
	replaced, replace_err = strings.builder_replace(
		&expected,
		"checked = false",
		"checked = true",
		1,
	)
	testing.expect(t, replace_err == nil && replaced == 1)
	replaced, replace_err = strings.builder_replace(
		&expected,
		"amount = [1, 0, 0]",
		"amount = [0, 2.5, -1]",
		1,
	)
	testing.expect(t, replace_err == nil && replaced == 1)
	testing.expect(t, saved == strings.to_string(expected))
	testing.expect(
		t,
		strings.contains(saved, "position = [-4.5, 6.25, 8] # preserve this comment"),
	)
	testing.expect(t, strings.contains(saved, "intensity = 12.5"))
	testing.expect(t, strings.contains(saved, "checked = true"))
	testing.expect(t, !strings.contains(saved, "read_only = false"))
	testing.expect(t, strings.contains(saved, "amount = [0, 2.5, -1]"))
	testing.expect(t, strings.contains(saved, "position = [9.1, 0.12, -0.8]"))
	testing.expect(t, strings.contains(saved, "rotation = [0.12, 0.18, 0.32]"))
	testing.expect(t, strings.contains(saved, "color = [1, 1, 1]"))
	testing.expect(t, !strings.contains(saved, "0.119999"))
	testing.expect(t, !strings.contains(saved, "-0.800000"))
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

@(test)
test_scene_save_persists_uuid_scoped_structural_entity_changes :: proc(t: ^testing.T) {
	directory, directory_err := os.make_directory_temp(
		"",
		"scrapbot-structural-scene-save-*",
		context.temp_allocator,
	)
	testing.expect(t, directory_err == nil)
	if directory_err != nil { return }
	defer os.remove_all(directory)
	scene_path, path_err := filepath.join({directory, "scene.toml"})
	testing.expect(t, path_err == nil)
	if path_err != nil { return }
	defer delete(scene_path)
	fixture := strings.builder_make()
	defer strings.builder_destroy(&fixture)
	strings.write_string(&fixture, SCENE_SAVE_TEST_SOURCE)
	unchanged_block := `[[entities]]
id = "a5000000-0000-4000-8000-000000000003"
name = "Untouched" # preserve the complete clean block

[entities.transform]
position = [7.000, 8.000, 9.000]
rotation = [0, 0, 0]
scale = [1, 1, 1]
`
	strings.write_string(&fixture, unchanged_block)
	testing.expect(t, os.write_entire_file(scene_path, strings.to_string(fixture)) == nil)

	loaded := project.load_scene_file(scene_path)
	testing.expectf(t, loaded.err == "", "fixture failed to load: %s", loaded.err)
	if loaded.err != "" {
		project.destroy_scene_load_result(&loaded)
		return
	}
	world := ecs.build_world(&loaded.scene)
	project.destroy_scene_load_result(&loaded)
	defer ecs.destroy_world(&world)
	first_id, _ := shared.entity_uuid_parse("a5000000-0000-4000-8000-000000000001")
	second_id, _ := shared.entity_uuid_parse("a5000000-0000-4000-8000-000000000002")
	first_index, _ := ecs.entity_index_by_uuid(&world, first_id)
	first_snapshot, captured := ecs.capture_entity_snapshot(&world, first_index)
	testing.expect(t, captured)
	defer ecs.destroy_entity_snapshot(&first_snapshot)
	delete(first_snapshot.entity.name)
	first_snapshot.entity.name = ecs.clone_snapshot_string("Structurally Edited")
	first_snapshot.entity.has_point_light = false
	_, applied := ecs.apply_entity_snapshot(&world, &first_snapshot)
	testing.expect(t, applied)
	testing.expect(t, ecs.delete_entity_by_uuid(&world, second_id))

	created: ecs.Entity_Snapshot
	created.origin = .Scene
	created.entity.id = shared.entity_uuid_generate()
	created.entity.name = ecs.clone_snapshot_string("Created Entity")
	created.entity.has_transform = true
	created.entity.transform = {
		position = {4, 5, 6},
		scale = {1, 1, 1},
	}
	created.entity.has_point_light = true
	created.entity.point_light = {
		color = {0.2, 0.4, 0.8},
		intensity = 3,
		range = 9,
	}
	defer ecs.destroy_entity_snapshot(&created)
	_, applied = ecs.apply_entity_snapshot(&world, &created)
	testing.expect(t, applied)

	dirty := [3]shared.Entity_UUID{first_id, second_id, created.entity.id}
	save_err := save_scene_world(scene_path, &world, dirty[:])
	testing.expectf(t, save_err == "", "structural save failed: %s", save_err)
	reloaded := project.load_scene_file(scene_path)
	defer project.destroy_scene_load_result(&reloaded)
	testing.expectf(t, reloaded.err == "", "structural result failed to load: %s", reloaded.err)
	if reloaded.err != "" { return }
	saved_bytes, read_err := os.read_entire_file(scene_path, context.temp_allocator)
	testing.expect(t, read_err == nil)
	if read_err ==
	   nil { testing.expect(t, strings.contains(string(saved_bytes), unchanged_block)) }
	testing.expect(t, len(reloaded.scene.entities) == 3)
	first, first_found := scene_entity_by_uuid(&reloaded.scene, first_id)
	created_entity, created_found := scene_entity_by_uuid(&reloaded.scene, created.entity.id)
	_, second_found := scene_entity_by_uuid(&reloaded.scene, second_id)
	testing.expect(t, first_found && first.name == "Structurally Edited")
	testing.expect(t, first_found && !first.has_point_light)
	testing.expect(
		t,
		created_found && created_entity.has_transform && created_entity.has_point_light,
	)
	testing.expect(t, created_found && created_entity.transform.position == shared.Vec3{4, 5, 6})
	testing.expect(t, !second_found)
}
