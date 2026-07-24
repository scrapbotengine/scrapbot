package scrapbot

import ecs "./ecs"
import project "./project"
import resources "./resources"
import shared "./shared"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_project_save_commits_scene_and_resource_as_one_reloadable_state :: proc(t: ^testing.T) {
	parent, temp_err := os.make_directory_temp(
		"",
		"scrapbot-project-save-integration-*",
		context.allocator,
	)
	testing.expect(t, temp_err == nil)
	if temp_err != nil {
		return
	}
	root, root_err := filepath.join({parent, "project"})
	testing.expect(t, root_err == nil)
	if root_err != nil {
		_ = os.remove_all(parent)
		delete(parent)
		return
	}
	defer {
		_ = os.remove_all(parent)
		delete(root)
		delete(parent)
	}
	testing.expect(t, project.init_project(root, "Transactional Save") == "")
	loaded := project.load_project(root)
	defer project.destroy_project_load_result(&loaded)
	testing.expectf(t, loaded.err == "", "failed to load project fixture: %s", loaded.err)
	if loaded.err != "" || len(loaded.scene.entities) < 2 || len(loaded.resources) != 1 {
		return
	}
	world := ecs.build_world(&loaded.scene)
	defer ecs.destroy_world(&world)
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	testing.expect(
		t,
		resources.register_project_materials(&registry, root, loaded.resources[:]) == "",
	)

	entity_id := loaded.scene.entities[1].id
	entity_index, entity_found := ecs.entity_index_by_uuid(&world, entity_id)
	testing.expect(t, entity_found)
	if !entity_found {
		return
	}
	entity := &world.entities[entity_index]
	world.transforms[entity.transform_index].position.x = 12.5
	resource_id := loaded.resources[0].id
	handle, resource_found := resources.material_by_uuid(&registry, resource_id)
	testing.expect(t, resource_found)
	material, material_alive := resources.get_material(&registry, handle)
	testing.expect(t, material_alive)
	if !material_alive {
		return
	}
	material.desc.base_color = {0.125, 0.25, 0.5, 1}
	material.desc.emissive = {3, 2, 1}
	material.desc.metallic_factor = 0.75
	material.desc.roughness_factor = 0.25

	scene_path, scene_path_err := filepath.join({root, loaded.config.default_scene})
	testing.expect(t, scene_path_err == nil)
	if scene_path_err != nil {
		return
	}
	defer delete(scene_path)
	resource_path, resource_path_err := filepath.join(
		{root, shared.PROJECT_RESOURCES_DIR, loaded.resources[0].source},
	)
	testing.expect(t, resource_path_err == nil)
	if resource_path_err != nil {
		return
	}
	defer delete(resource_path)
	testing.expectf(
		t,
		save_project_world(
			root,
			scene_path,
			&registry,
			&world,
			[]shared.Entity_UUID{entity_id},
			[]shared.Resource_UUID{resource_id},
		) ==
		"",
		"project save failed",
	)

	reloaded := project.load_project(root)
	defer project.destroy_project_load_result(&reloaded)
	testing.expectf(t, reloaded.err == "", "saved project failed to reload: %s", reloaded.err)
	if reloaded.err == "" {
		testing.expect_value(t, reloaded.scene.entities[1].transform.position.x, f32(12.5))
		testing.expect_value(t, reloaded.resources[0].material.base_color.x, f32(0.125))
		testing.expect_value(t, reloaded.resources[0].material.emissive, shared.Vec3{3, 2, 1})
		testing.expect_value(t, reloaded.resources[0].material.metallic, f32(0.75))
		testing.expect_value(t, reloaded.resources[0].material.roughness, f32(0.25))
	}

	first_scene := clone_file_text(t, scene_path)
	defer delete(first_scene)
	first_resource := clone_file_text(t, resource_path)
	defer delete(first_resource)
	testing.expect(
		t,
		save_project_world(
			root,
			scene_path,
			&registry,
			&world,
			[]shared.Entity_UUID{entity_id},
			[]shared.Resource_UUID{resource_id},
		) ==
		"",
	)
	second_scene := clone_file_text(t, scene_path)
	defer delete(second_scene)
	second_resource := clone_file_text(t, resource_path)
	defer delete(second_resource)
	testing.expect_value(t, second_scene, first_scene)
	testing.expect_value(t, second_resource, first_resource)
}

@(private)
clone_file_text :: proc(t: ^testing.T, path: string) -> string {
	bytes, read_err := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, read_err == nil)
	if read_err != nil {
		return ""
	}
	result, clone_err := strings.clone(string(bytes))
	testing.expect(t, clone_err == nil)
	return result
}
