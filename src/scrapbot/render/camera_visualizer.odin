package render

import ecs "../ecs"
import shared "../shared"
import ui "../ui"
import "core:math"

EDITOR_CAMERA_MESH_WORLD_SIZE :: f32(0.6)
EDITOR_CAMERA_FRUSTUM_PREVIEW_SIZE :: f32(5)
EDITOR_CAMERA_MESH_POINT_COUNT :: 21
EDITOR_CAMERA_MESH_BODY_SEGMENT_COUNT :: 20
EDITOR_CAMERA_MESH_FRUSTUM_SEGMENT_COUNT :: 12
EDITOR_CAMERA_MESH_SEGMENT_COUNT ::
	EDITOR_CAMERA_MESH_BODY_SEGMENT_COUNT + EDITOR_CAMERA_MESH_FRUSTUM_SEGMENT_COUNT
EDITOR_CAMERA_MESH_PICK_RADIUS :: f32(8)

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
	view_eye, _ := editor_camera_eye_fov(view_camera, has_view_camera)
	view_forward := vec3_normalize(vec3_sub({}, view_eye))
	view_near := f32(0.1)
	if has_view_camera {
		view_forward = shared.camera_forward(view_camera.transform.rotation)
		if view_camera.camera.near > 0 {
			view_near = view_camera.camera.near
		}
	}
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
		view_depth := vec3_dot(vec3_sub(transform.position, view_eye), view_forward)
		if view_depth <= view_near + EDITOR_CAMERA_MESH_WORLD_SIZE {
			continue
		}
		camera_component := world.cameras[entity.camera_index]
		points := editor_camera_mesh_world_points(
			transform,
			camera_component,
			viewport.width / viewport.height,
			EDITOR_CAMERA_MESH_WORLD_SIZE,
		)
		projected: [EDITOR_CAMERA_MESH_POINT_COUNT]shared.Vec2
		projected_valid: [EDITOR_CAMERA_MESH_POINT_COUNT]bool
		for point, point_index in points {
			projected_point, ok := editor_project_world(
				point,
				viewport,
				view_camera,
				has_view_camera,
			)
			if ok {
				projected[point_index] = projected_point
				projected_valid[point_index] = true
			}
		}

		selected := state.editor_has_selection && state.editor_selected_entity == entity.id
		color := shared.Vec4{0.38, 0.72, 0.96, 0.88}
		frustum_color := shared.Vec4{0.38, 0.72, 0.96, 0.52}
		thickness := f32(1.5) * max(state.editor_pixel_density, 1)
		if selected {
			color = {1, 0.68, 0.22, 1}
			frustum_color = {1, 0.68, 0.22, 0.68}
			thickness = 2.25 * max(state.editor_pixel_density, 1)
		}
		editor_camera_mesh_append_segments(
			state,
			projected,
			projected_valid,
			entity.id,
			color,
			frustum_color,
			thickness,
			selected,
		)
	}
}

editor_camera_mesh_world_points :: proc(
	transform: shared.Transform_Component,
	camera: shared.Camera_Component,
	aspect: f32,
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

	points[12] = transform.position
	fov := camera.fov
	if fov <= 0 {
		fov = 60
	}
	near_distance := f32(0.1)
	if camera.near > 0 {
		near_distance = camera.near
	}
	far_distance := f32(100)
	if camera.far > near_distance {
		far_distance = camera.far
	}
	preview_distance := min(
		far_distance,
		max(EDITOR_CAMERA_FRUSTUM_PREVIEW_SIZE, near_distance + size),
	)
	tangent := math.tan(math.to_radians(fov) * 0.5)
	near_half_height := tangent * near_distance
	near_half_width := near_half_height * max(aspect, 0.01)
	far_half_height := tangent * preview_distance
	far_half_width := far_half_height * max(aspect, 0.01)
	for signs, corner in corner_signs {
		points[corner + 13] = editor_camera_mesh_point(
			transform.position,
			right,
			up,
			forward,
			near_distance,
			signs[0] * near_half_width,
			signs[1] * near_half_height,
		)
		points[corner + 17] = editor_camera_mesh_point(
			transform.position,
			right,
			up,
			forward,
			preview_distance,
			signs[0] * far_half_width,
			signs[1] * far_half_height,
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
	point_valid: [EDITOR_CAMERA_MESH_POINT_COUNT]bool,
	entity: shared.Entity,
	body_color, frustum_color: shared.Vec4,
	thickness: f32,
	show_frustum: bool,
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
		{12, 17},
		{12, 18},
		{12, 19},
		{12, 20},
		{13, 14},
		{14, 15},
		{15, 16},
		{16, 13},
		{17, 18},
		{18, 19},
		{19, 20},
		{20, 17},
	}
	for edge, edge_index in edges {
		if edge_index >= EDITOR_CAMERA_MESH_BODY_SEGMENT_COUNT && !show_frustum {
			break
		}
		if !point_valid[edge[0]] || !point_valid[edge[1]] {
			continue
		}
		index := state.editor_camera_mesh_segment_count
		if index >= len(state.editor_camera_mesh_segments) {
			return
		}
		color := body_color
		segment_thickness := thickness
		if edge_index >= EDITOR_CAMERA_MESH_BODY_SEGMENT_COUNT {
			color = frustum_color
			segment_thickness *= 0.8
		}
		state.editor_camera_mesh_segments[index] = {
			entity = entity,
			start = points[edge[0]],
			end = points[edge[1]],
			color = color,
			thickness = segment_thickness,
		}
		state.editor_camera_mesh_segment_count += 1
	}
}

editor_pick_camera_mesh :: proc(state: ^ui.State, position: shared.Vec2) -> (shared.Entity, bool) {
	if state == nil || !state.editor_visible {
		return {}, false
	}
	radius := EDITOR_CAMERA_MESH_PICK_RADIUS * max(state.editor_pixel_density, 1)
	nearest := radius
	picked: shared.Entity
	found := false
	count := min(state.editor_camera_mesh_segment_count, len(state.editor_camera_mesh_segments))
	for segment in state.editor_camera_mesh_segments[:count] {
		distance := screen_point_segment_distance(position, segment.start, segment.end)
		if distance < nearest {
			nearest = distance
			picked = segment.entity
			found = true
		}
	}
	return picked, found
}
