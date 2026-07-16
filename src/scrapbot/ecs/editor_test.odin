package ecs

import shared "../shared"
import "core:math"
import "core:testing"

@(test)
test_editor_transform_gizmo_component_follows_selection :: proc(t: ^testing.T) {
	world: World; defer delete(world.entities); defer delete(world.transforms); defer delete(world.editor_transform_gizmos)
	append_soa(&world.transforms, shared.Transform_Component{}, shared.Transform_Component{})
	append(
		&world.entities,
		shared.World_Entity {
			id = {index = 0, generation = 1},
			alive = true,
			transform_index = 0,
			editor_transform_gizmo_index = -1,
		},
		shared.World_Entity {
			id = {index = 1, generation = 1},
			alive = true,
			transform_index = 1,
			editor_transform_gizmo_index = -1,
		},
	)

	reconcile_editor_transform_gizmo(&world, {index = 0, generation = 1}, true)
	entity_index, gizmo, ok := editor_transform_gizmo_entity(&world)
	testing.expect(t, ok && entity_index == 0 && gizmo.mode == .Translate)
	testing.expect(t, world.entities[0].editor_transform_gizmo_index >= 0)
	reconcile_editor_transform_gizmo(&world, {index = 0, generation = 1}, true, .Rotate, .Local)
	_, gizmo, ok = editor_transform_gizmo_entity(&world)
	testing.expect(t, ok && gizmo.mode == .Rotate && gizmo.space == .Local)

	reconcile_editor_transform_gizmo(&world, {index = 1, generation = 1}, true)
	entity_index, _, ok = editor_transform_gizmo_entity(&world)
	testing.expect(t, ok && entity_index == 1)
	testing.expect(t, world.entities[0].editor_transform_gizmo_index == -1)
	testing.expect(t, world.entities[1].editor_transform_gizmo_index >= 0)

	reconcile_editor_transform_gizmo(&world, {}, false)
	_, _, ok = editor_transform_gizmo_entity(&world)
	testing.expect(t, !ok)
	testing.expect(t, world.entities[1].editor_transform_gizmo_index == -1)
}

@(test)
test_editor_scene_camera_is_an_ecs_entity_and_fly_system_moves_it :: proc(t: ^testing.T) {
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Project Camera",
			has_transform = true,
			transform = {position = {0, 1, 8}, rotation = {-0.1, 0, 0}, scale = {1, 1, 1}},
			has_camera = true,
			camera = {fov = 55, near = 0.2, far = 250},
		},
	)
	world := build_world(&scene)
	defer destroy_world(&world)

	editor_scene_camera_system(&world, {}, 1.0 / 60.0, false)
	testing.expect(t, len(world.entities) == 1)

	editor_scene_camera_system(&world, {}, 1.0 / 60.0, true)
	entity_index, component, ok := editor_scene_camera_entity(&world)
	testing.expect(t, ok)
	testing.expect(t, entity_index == 1)
	testing.expect(t, component.move_speed == EDITOR_SCENE_CAMERA_MOVE_SPEED)
	testing.expect(t, world.entities[entity_index].origin == .Editor)
	testing.expect(t, world.entities[entity_index].name == EDITOR_SCENE_CAMERA_NAME)
	testing.expect(t, project_entity_count(&world) == 1)
	transform_query: Query
	transform_query.term_count = 1
	transform_query.terms[0].name = "scrapbot.transform"
	testing.expect(t, query_count(&world, transform_query) == 1)
	camera, has_camera := active_camera_instance(&world, true)
	testing.expect(t, has_camera)
	testing.expect(t, camera.entity.id.index == u32(entity_index))
	testing.expect(t, camera.camera.fov == 55)

	before := camera.transform.position
	editor_scene_camera_system(
		&world,
		{movement = {0, 0, 1}, look_delta = {100, -100}, look_active = true},
		1,
		true,
	)
	after, _ := active_camera_instance(&world, true)
	delta := shared.Vec3 {
		after.transform.position.x - before.x,
		after.transform.position.y - before.y,
		after.transform.position.z - before.z,
	}
	distance := math.sqrt(shared.camera_vec3_dot(delta, delta))
	testing.expect(t, math.abs(distance - EDITOR_SCENE_CAMERA_MOVE_SPEED) < 0.0001)
	testing.expect(t, after.transform.rotation.y > camera.transform.rotation.y)
	testing.expect(t, after.transform.rotation.x > camera.transform.rotation.x)
}
