package render

import ecs "../ecs"
import shared "../shared"
import ui "../ui"
import "core:math"
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
	testing.expect(t, state.editor_camera_mesh_segments[0].entity == world.entities[0].id)
	testing.expect(
		t,
		state.editor_camera_mesh_segments[EDITOR_CAMERA_MESH_BODY_SEGMENT_COUNT].color ==
		shared.Vec4{1, 0.68, 0.22, 0.68},
	)
	testing.expect(
		t,
		state.editor_camera_mesh_segments[0].start != state.editor_camera_mesh_segments[0].end,
	)
	pick_position := shared.Vec2 {
		(state.editor_camera_mesh_segments[0].start.x +
			state.editor_camera_mesh_segments[0].end.x) *
		0.5,
		(state.editor_camera_mesh_segments[0].start.y +
			state.editor_camera_mesh_segments[0].end.y) *
		0.5,
	}
	picked, picked_ok := editor_pick_camera_mesh(state, pick_position)
	testing.expect(t, picked_ok && picked == world.entities[0].id)
	_, picked_ok = editor_pick_camera_mesh(state, {-100, -100})
	testing.expect(t, !picked_ok)

	editor_camera_mesh_system(state, &world, {0, 0, 800, 600}, view_camera, true, false)
	testing.expect(t, state.editor_camera_mesh_segment_count == 0)
}

@(test)
test_editor_camera_mesh_frustum_reflects_fov_aspect_and_clip_limits :: proc(t: ^testing.T) {
	transform := shared.Transform_Component {
		scale = {1, 1, 1},
	}
	narrow := editor_camera_mesh_world_points(transform, {fov = 30, near = 0.25, far = 10}, 1.5, 1)
	wide := editor_camera_mesh_world_points(transform, {fov = 90, near = 0.25, far = 10}, 2, 1)

	testing.expect(t, narrow[13].z == -0.25)
	testing.expect(t, narrow[17].z == -10)
	testing.expect(t, math.abs(wide[17].x) > math.abs(narrow[17].x))
	testing.expect(t, math.abs(wide[17].y) > math.abs(narrow[17].y))
}

@(test)
test_editor_camera_mesh_body_has_world_scale :: proc(t: ^testing.T) {
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
	state := new(ui.State)
	defer free(state)
	state.editor_visible = true
	state.editor_pixel_density = 1
	near_view := shared.Camera_Instance {
		transform = {position = {0, 0, 6}, scale = {1, 1, 1}},
		camera = {fov = 60, near = 0.1, far = 200},
	}
	far_view := near_view
	far_view.transform.position.z = 12

	editor_camera_mesh_system(state, &world, {0, 0, 800, 600}, near_view, true, true)
	near_delta := shared.Vec2 {
		state.editor_camera_mesh_segments[0].end.x - state.editor_camera_mesh_segments[0].start.x,
		state.editor_camera_mesh_segments[0].end.y - state.editor_camera_mesh_segments[0].start.y,
	}
	near_length := math.sqrt(near_delta.x * near_delta.x + near_delta.y * near_delta.y)
	editor_camera_mesh_system(state, &world, {0, 0, 800, 600}, far_view, true, true)
	far_delta := shared.Vec2 {
		state.editor_camera_mesh_segments[0].end.x - state.editor_camera_mesh_segments[0].start.x,
		state.editor_camera_mesh_segments[0].end.y - state.editor_camera_mesh_segments[0].start.y,
	}
	far_length := math.sqrt(far_delta.x * far_delta.x + far_delta.y * far_delta.y)

	testing.expect(t, near_length > far_length)
}
