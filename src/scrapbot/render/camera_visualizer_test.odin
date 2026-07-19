package render

import ecs "../ecs"
import shared "../shared"
import ui "../ui"
import "core:testing"

@(test)
test_editor_camera_mesh_tracks_project_cameras_and_excludes_the_fly_camera :: proc(t: ^testing.T) {
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Project Camera",
			has_transform = true,
			transform = {scale = {1, 1, 1}},
			has_camera = true,
			camera = {fov = 60, near = 0.1, far = 100},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	ecs.editor_scene_camera_system(&world, {}, 0, true)

	state := new(ui.State)
	defer free(state)
	state.editor_visible = true
	state.editor_pixel_density = 1
	state.editor_has_selection = true
	state.editor_selected_entity = world.entities[0].id
	view_camera := shared.Camera_Instance {
		transform = {position = {4, 3, 6}, rotation = {-0.39, -0.59, 0}},
		camera = {fov = 60, near = 0.1, far = 100},
	}

	editor_camera_mesh_system(state, &world, {0, 0, 800, 600}, view_camera, true, true)
	testing.expect(t, state.editor_camera_mesh_segment_count == EDITOR_CAMERA_MESH_SEGMENT_COUNT)
	testing.expect(t, state.editor_camera_mesh_segments[0].color == shared.Vec4{1, 0.68, 0.22, 1})
	testing.expect(
		t,
		state.editor_camera_mesh_segments[0].start != state.editor_camera_mesh_segments[0].end,
	)

	editor_camera_mesh_system(state, &world, {0, 0, 800, 600}, view_camera, true, false)
	testing.expect(t, state.editor_camera_mesh_segment_count == 0)
}
