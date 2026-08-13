package scrapbot

import component "./component"
import ecs "./ecs"
import project "./project"
import shared "./shared"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

SCENE_TRANSITION_FIRST_ID :: "b4000000-0000-4000-8000-000000000001"
SCENE_TRANSITION_SECOND_ID :: "b4000000-0000-4000-8000-000000000002"

scene_transition_source :: proc(scene_id, scene_name, entity_id, entity_name: string) -> string {
	return fmt.tprintf(
		`id = "%s"
name = "%s"

[[entities]]
id = "%s"
name = "%s"

[entities.transform]
position = [0, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]
`,
		scene_id,
		scene_name,
		entity_id,
		entity_name,
	)
}

@(test)
test_scene_transition_replaces_bounded_world_and_rejects_invalid_candidate :: proc(t: ^testing.T) {
	root, root_err := os.make_directory_temp(
		"",
		"scrapbot-scene-transition-*",
		context.temp_allocator,
	)
	testing.expect(t, root_err == nil)
	if root_err != nil {
		return
	}
	defer os.remove_all(root)
	scenes_dir, scenes_dir_err := filepath.join({root, "scenes"})
	testing.expect(t, scenes_dir_err == nil)
	if scenes_dir_err != nil {
		return
	}
	defer delete(scenes_dir)
	testing.expect(t, os.make_directory_all(scenes_dir) == nil)
	first_path, first_path_err := filepath.join({scenes_dir, "first.scene.toml"})
	second_path, second_path_err := filepath.join({scenes_dir, "second.scene.toml"})
	testing.expect(t, first_path_err == nil && second_path_err == nil)
	if first_path_err != nil || second_path_err != nil {
		delete(first_path)
		delete(second_path)
		return
	}
	defer delete(first_path)
	defer delete(second_path)
	first_source := scene_transition_source(
		SCENE_TRANSITION_FIRST_ID,
		"First",
		"b4100000-0000-4000-8000-000000000001",
		"First Entity",
	)
	second_source := scene_transition_source(
		SCENE_TRANSITION_SECOND_ID,
		"Second",
		"b4100000-0000-4000-8000-000000000002",
		"Second Entity",
	)
	testing.expect(t, os.write_entire_file(first_path, first_source) == nil)
	testing.expect(t, os.write_entire_file(second_path, second_source) == nil)

	first_loaded := project.load_scene_file_with_resources(first_path, nil)
	defer project.destroy_scene_load_result(&first_loaded)
	testing.expect(t, first_loaded.err == "")
	world := ecs.build_world(&first_loaded.scene)
	defer ecs.destroy_world(&world)

	runtime := new(Frame_Runtime)
	defer free(runtime)
	defer destroy_frame_runtime(runtime)
	runtime.root = root
	runtime.scene_path, _ = strings.clone(first_path)
	runtime.scene_id, _ = shared.resource_uuid_parse(SCENE_TRANSITION_FIRST_ID)
	runtime.scenes, _ = project.load_project_scenes(root, nil)
	first_scene, _ := project.project_scene_by_id(runtime.scenes[:], runtime.scene_id)
	loaded_project := project.Project_Load_Result{}
	init_resource_residency(&runtime.resource_residency, &loaded_project, first_scene)
	component.init_registry(&runtime.script_runtime.registry)
	runtime.script_runtime.world = &world
	if init_err := init_render_resources(&runtime.resources, &world); init_err != "" {
		testing.expectf(t, false, "resource initialization failed: %s", init_err)
		return
	}
	if baseline_err := capture_playback_baseline(
		&runtime.playback_baseline,
		&world,
		&runtime.resources,
	); baseline_err != "" {
		testing.expectf(t, false, "baseline capture failed: %s", baseline_err)
		return
	}

	first_stats := ecs.world_storage_stats(&world)
	first_id, _ := shared.resource_uuid_parse(SCENE_TRANSITION_FIRST_ID)
	second_id, _ := shared.resource_uuid_parse(SCENE_TRANSITION_SECOND_ID)
	for _ in 0 ..< 64 {
		runtime.script_runtime.requested_scene = second_id
		testing.expect_value(t, frame_runtime_commit_scene_request(runtime, &world), "")
		testing.expect_value(t, world.entities[0].name, "Second Entity")
		runtime.script_runtime.requested_scene = first_id
		testing.expect_value(t, frame_runtime_commit_scene_request(runtime, &world), "")
		testing.expect_value(t, world.entities[0].name, "First Entity")
	}
	final_stats := ecs.world_storage_stats(&world)
	testing.expect_value(t, final_stats.entity_slots, first_stats.entity_slots)
	testing.expect_value(t, final_stats.total_component_slots, first_stats.total_component_slots)

	testing.expect(t, os.write_entire_file(second_path, "not a scene") == nil)
	active_id := runtime.scene_id
	active_name := world.entities[0].name
	runtime.script_runtime.requested_scene = second_id
	testing.expect(t, frame_runtime_commit_scene_request(runtime, &world) != "")
	testing.expect_value(t, runtime.scene_id, active_id)
	testing.expect_value(t, world.entities[0].name, active_name)
}
