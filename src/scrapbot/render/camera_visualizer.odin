package render

import ecs "../ecs"
import shared "../shared"
import ui "../ui"
import "core:math"

EDITOR_CAMERA_MESH_SCREEN_SIZE :: f32(54)
EDITOR_CAMERA_MESH_POINT_COUNT :: 12
EDITOR_CAMERA_MESH_SEGMENT_COUNT :: 20

editor_camera_mesh_system :: proc(
	state: ^ui.State,
	world: ^shared.World,
	viewport: ui.Rect,
	view_camera: shared.Camera_Instance,
	has_view_camera: bool,
	enabled: bool,
) {
	if state == nil {
		return
	}
	state.editor_camera_mesh_segment_count = 0
	if !enabled || world == nil || viewport.width <= 0 || viewport.height <= 0 {
		return
	}

	ecs.begin_world_transform_resolution(world)
	eye, view_fov := editor_camera_eye_fov(view_camera, has_view_camera)
	for entity_index in world.render_active_camera_entities {
		if entity_index < 0 || entity_index >= len(world.entities) {
			continue
		}
		entity := world.entities[entity_index]
		if !entity.alive ||
		   entity.origin == .Editor ||
		   entity.camera_index < 0 ||
		   entity.camera_index >= len(world.cameras) ||
		   entity.transform_index < 0 ||
		   entity.transform_index >= len(world.transforms) {
			continue
		}
		if state.editor_camera_mesh_segment_count + EDITOR_CAMERA_MESH_SEGMENT_COUNT >
		   len(state.editor_camera_mesh_segments) {
			break
		}

		transform, _ := ecs.resolve_world_transform(world, entity_index)
		delta := vec3_sub(transform.position, eye)
		distance := math.sqrt(vec3_dot(delta, delta))
		world_size := max(
			2 *
			max(distance, 0.1) *
			math.tan(math.to_radians(view_fov) * 0.5) /
			max(viewport.height, 1) *
			EDITOR_CAMERA_MESH_SCREEN_SIZE,
			0.05,
		)
		points := editor_camera_mesh_world_points(transform, world_size)
		projected: [EDITOR_CAMERA_MESH_POINT_COUNT]shared.Vec2
		visible := true
		for point, point_index in points {
			projected_point, ok := editor_project_world(
				point,
				viewport,
				view_camera,
				has_view_camera,
			)
			if !ok {
				visible = false
				break
			}
			projected[point_index] = projected_point
		}
		if !visible {
			continue
		}

		selected := state.editor_has_selection && state.editor_selected_entity == entity.id
		color := shared.Vec4{0.38, 0.72, 0.96, 0.88}
		thickness := f32(1.5) * max(state.editor_pixel_density, 1)
		if selected {
			color = {1, 0.68, 0.22, 1}
			thickness = 2.25 * max(state.editor_pixel_density, 1)
		}
		editor_camera_mesh_append_segments(state, projected, color, thickness)
	}
}

editor_camera_mesh_world_points :: proc(
	transform: shared.Transform_Component,
	size: f32,
) -> [EDITOR_CAMERA_MESH_POINT_COUNT]shared.Vec3 {
	right := shared.camera_right(transform.rotation)
	up := shared.camera_up(transform.rotation)
	forward := shared.camera_forward(transform.rotation)
	points: [EDITOR_CAMERA_MESH_POINT_COUNT]shared.Vec3
	corner_signs := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
	for signs, corner in corner_signs {
		points[corner] = editor_camera_mesh_point(
			transform.position,
			right,
			up,
			forward,
			-0.20 * size,
			signs[0] * 0.36 * size,
			signs[1] * 0.27 * size,
		)
		points[corner + 4] = editor_camera_mesh_point(
			transform.position,
			right,
			up,
			forward,
			0.18 * size,
			signs[0] * 0.36 * size,
			signs[1] * 0.27 * size,
		)
		points[corner + 8] = editor_camera_mesh_point(
			transform.position,
			right,
			up,
			forward,
			0.62 * size,
			signs[0] * 0.22 * size,
			signs[1] * 0.16 * size,
		)
	}
	return points
}

editor_camera_mesh_point :: proc(
	origin, right, up, forward: shared.Vec3,
	forward_offset, right_offset, up_offset: f32,
) -> shared.Vec3 {
	return vec3_add(
		origin,
		vec3_add(
			vec3_mul(forward, forward_offset),
			vec3_add(vec3_mul(right, right_offset), vec3_mul(up, up_offset)),
		),
	)
}

editor_camera_mesh_append_segments :: proc(
	state: ^ui.State,
	points: [EDITOR_CAMERA_MESH_POINT_COUNT]shared.Vec2,
	color: shared.Vec4,
	thickness: f32,
) {
	edges := [EDITOR_CAMERA_MESH_SEGMENT_COUNT][2]int {
		{0, 1},
		{1, 2},
		{2, 3},
		{3, 0},
		{4, 5},
		{5, 6},
		{6, 7},
		{7, 4},
		{0, 4},
		{1, 5},
		{2, 6},
		{3, 7},
		{8, 9},
		{9, 10},
		{10, 11},
		{11, 8},
		{4, 8},
		{5, 9},
		{6, 10},
		{7, 11},
	}
	for edge in edges {
		index := state.editor_camera_mesh_segment_count
		if index >= len(state.editor_camera_mesh_segments) {
			return
		}
		state.editor_camera_mesh_segments[index] = {
			start = points[edge[0]],
			end = points[edge[1]],
			color = color,
			thickness = thickness,
		}
		state.editor_camera_mesh_segment_count += 1
	}
}
