package render

import ecs "../ecs"
import shared "../shared"
import ui "../ui"
import "core:math"

EDITOR_GIZMO_SCREEN_SIZE :: f32(92)
EDITOR_GIZMO_HIT_RADIUS :: f32(10)

editor_transform_gizmo_system :: proc(
	state: ^ui.State,
	world: ^shared.World,
	pointer: ui.Pointer_Input,
	viewport: ui.Rect,
	camera: shared.Camera_Instance,
	has_camera: bool,
) {
	if state == nil || world == nil { editor_hide_gizmo(state); return }
	ecs.reconcile_editor_transform_gizmo(
		world,
		state.editor_selected_entity,
		state.editor_visible && state.editor_has_selection,
		state.editor_gizmo_mode,
		state.editor_gizmo_space,
	)
	entity_index, gizmo, has_gizmo := ecs.editor_transform_gizmo_entity(world)
	if !has_gizmo { editor_hide_gizmo(state); return }
	entity := &world.entities[entity_index]
	if entity.transform_index < 0 ||
	   entity.transform_index >= len(world.transforms) { editor_hide_gizmo(state); return }
	transform := &world.transforms[entity.transform_index]
	eye, fov := editor_camera_eye_fov(
		camera,
		has_camera,
	); distance := math.sqrt(vec3_dot(vec3_sub(transform.position, eye), vec3_sub(transform.position, eye)))
	world_size := max(
		2 *
		max(distance, 0.1) *
		math.tan(math.to_radians(fov) * 0.5) /
		max(viewport.height, 1) *
		EDITOR_GIZMO_SCREEN_SIZE,
		0.05,
	)
	world_axes := editor_gizmo_axes(transform.rotation, gizmo.space)
	if state.editor_gizmo_active_handle != .None {
		world_axes = state.editor_gizmo_drag_world_axes
	}
	if !editor_project_gizmo(
		state,
		transform.position,
		world_size,
		world_axes,
		gizmo.mode,
		viewport,
		camera,
		has_camera,
	) { editor_hide_gizmo(state); return }
	just_pressed :=
		pointer.available && pointer.primary_down && !state.editor_previous_primary_down
	if state.editor_gizmo_active_handle == .None {
		state.editor_gizmo_hovered_handle = editor_gizmo_hit_handle(
			pointer.position,
			state.editor_gizmo_origin,
			state.editor_gizmo_endpoints,
			state.editor_gizmo_plane_points,
			state.editor_gizmo_ring_points,
			gizmo.mode,
			pointer.available,
		)
		if just_pressed && state.editor_gizmo_hovered_handle != .None {
			handle := state.editor_gizmo_hovered_handle
			delta := shared.Vec2{1, -1}; pixels := EDITOR_GIZMO_SCREEN_SIZE
			if handle >= .X && handle <= .Z {
				axis_index := int(handle) - 1
				delta = screen_sub(
					state.editor_gizmo_endpoints[axis_index],
					state.editor_gizmo_origin,
				); pixels = screen_length(delta)
			}
			if gizmo.mode ==
			   .Rotate { pixels = screen_length(screen_sub(pointer.position, state.editor_gizmo_origin)) }
			if pixels > 0.001 {
				state.editor_gizmo_active_handle = handle
				state.editor_gizmo_captures_pointer = true
				state.editor_gizmo_drag_pointer = pointer.position
				state.editor_gizmo_drag_last_pointer = pointer.position
				state.editor_gizmo_drag_angle = 0
				state.editor_gizmo_drag_position = transform.position
				state.editor_gizmo_drag_rotation = transform.rotation
				state.editor_gizmo_drag_scale = transform.scale
				state.editor_gizmo_drag_direction = {
					delta.x / max(screen_length(delta), 0.001),
					delta.y / max(screen_length(delta), 0.001),
				}
				for endpoint, index in state.editor_gizmo_endpoints { state.editor_gizmo_drag_screen_axes[index] = screen_sub(endpoint, state.editor_gizmo_origin) }
				state.editor_gizmo_drag_world_axes = world_axes
				state.editor_gizmo_drag_camera_right = shared.camera_right(
					camera.transform.rotation,
				)
				state.editor_gizmo_drag_camera_up = shared.camera_up(camera.transform.rotation)
				if !has_camera { state.editor_gizmo_drag_camera_right = {1, 0, 0}; state.editor_gizmo_drag_camera_up = {0, 1, 0} }
				state.editor_gizmo_drag_pixels = pixels
				state.editor_gizmo_drag_world_scale = world_size
			}
		}
	} else if !pointer.primary_down {
		switch gizmo.mode {
			case .Translate:
				ui.editor_history_push_transform(
					state,
					world,
					entity_index,
					.Transform_Position,
					state.editor_gizmo_drag_position,
					transform.position,
				)
			case .Rotate:
				ui.editor_history_push_transform(
					state,
					world,
					entity_index,
					.Transform_Rotation,
					state.editor_gizmo_drag_rotation,
					transform.rotation,
				)
			case .Scale:
				ui.editor_history_push_transform(
					state,
					world,
					entity_index,
					.Transform_Scale,
					state.editor_gizmo_drag_scale,
					transform.scale,
				)
		}
		state.editor_gizmo_active_handle = .None; state.editor_gizmo_captures_pointer = false
	} else {
		state.editor_gizmo_captures_pointer =
			true; state.editor_gizmo_hovered_handle = state.editor_gizmo_active_handle
		switch gizmo.mode {
			case .Translate:
				delta := screen_sub(pointer.position, state.editor_gizmo_drag_pointer)
				transform.position = state.editor_gizmo_drag_position
				if first, second, ok := editor_gizmo_pair_axes(state.editor_gizmo_active_handle);
				   ok {
					first_amount, second_amount, solved := screen_solve_basis(
						delta,
						state.editor_gizmo_drag_screen_axes[first],
						state.editor_gizmo_drag_screen_axes[second],
					)
					if solved {
						transform.position = vec3_add(
							transform.position,
							vec3_mul(
								state.editor_gizmo_drag_world_axes[first],
								first_amount * state.editor_gizmo_drag_world_scale,
							),
						)
						transform.position = vec3_add(
							transform.position,
							vec3_mul(
								state.editor_gizmo_drag_world_axes[second],
								second_amount * state.editor_gizmo_drag_world_scale,
							),
						)
					}
				} else if state.editor_gizmo_active_handle == .Center {
					world_per_pixel :=
						state.editor_gizmo_drag_world_scale / EDITOR_GIZMO_SCREEN_SIZE
					transform.position = vec3_add(
						transform.position,
						vec3_mul(state.editor_gizmo_drag_camera_right, delta.x * world_per_pixel),
					)
					transform.position = vec3_add(
						transform.position,
						vec3_mul(state.editor_gizmo_drag_camera_up, -delta.y * world_per_pixel),
					)
				} else {
					pixels :=
						delta.x * state.editor_gizmo_drag_direction.x +
						delta.y *
							state.editor_gizmo_drag_direction.y; amount := pixels / state.editor_gizmo_drag_pixels * state.editor_gizmo_drag_world_scale
					axis_index, axis_ok := editor_gizmo_single_axis(
						state.editor_gizmo_active_handle,
					)
					if axis_ok {
						transform.position = vec3_add(
							transform.position,
							vec3_mul(state.editor_gizmo_drag_world_axes[axis_index], amount),
						)
					}
				}
			case .Rotate:
				previous := screen_sub(
					state.editor_gizmo_drag_last_pointer,
					state.editor_gizmo_origin,
				)
				current := screen_sub(pointer.position, state.editor_gizmo_origin)
				state.editor_gizmo_drag_angle += screen_rotation_delta(previous, current)
				state.editor_gizmo_drag_last_pointer = pointer.position
				axis_index, axis_ok := editor_gizmo_single_axis(state.editor_gizmo_active_handle)
				if axis_ok {
					transform.rotation = editor_gizmo_rotated_euler(
						state.editor_gizmo_drag_rotation,
						axis_index,
						state.editor_gizmo_drag_angle,
						gizmo.space,
					)
				}
			case .Scale:
				delta := screen_sub(pointer.position, state.editor_gizmo_drag_pointer)
				transform.scale = state.editor_gizmo_drag_scale
				if first, second, ok := editor_gizmo_pair_axes(state.editor_gizmo_active_handle);
				   ok {
					first_amount, second_amount, solved := screen_solve_basis(
						delta,
						state.editor_gizmo_drag_screen_axes[first],
						state.editor_gizmo_drag_screen_axes[second],
					)
					if solved { vec3_mul_axis(&transform.scale, first, max(1 + first_amount, 0.01)); vec3_mul_axis(&transform.scale, second, max(1 + second_amount, 0.01)) }
				} else {
					pixels :=
						delta.x * state.editor_gizmo_drag_direction.x +
						delta.y *
							state.editor_gizmo_drag_direction.y; factor := max(1 + pixels / state.editor_gizmo_drag_pixels, 0.01)
					switch state.editor_gizmo_active_handle {case .X:
							transform.scale.x *= factor; case .Y:
							transform.scale.y *= factor; case .Z:
							transform.scale.z *= factor; case .Center:
							transform.scale.x *= factor; transform.scale.y *= factor
							transform.scale.z *= factor; case .None, .XY, .XZ, .YZ:}
				}
		}
		ui.editor_mark_scene_dirty(state, entity)
		_ = editor_project_gizmo(
			state,
			transform.position,
			world_size,
			state.editor_gizmo_drag_world_axes,
			gizmo.mode,
			viewport,
			camera,
			has_camera,
		)
	}
}

editor_hide_gizmo :: proc(state: ^ui.State) {if state == nil { return }
	state.editor_gizmo_visible = false
	state.editor_gizmo_hovered_handle = .None
	state.editor_gizmo_active_handle = .None
	state.editor_gizmo_captures_pointer = false}

editor_project_gizmo :: proc(
	state: ^ui.State,
	origin: shared.Vec3,
	world_size: f32,
	world_axes: [3]shared.Vec3,
	mode: shared.Editor_Gizmo_Mode,
	viewport: ui.Rect,
	camera: shared.Camera_Instance,
	has_camera: bool,
) -> bool {
	origin_screen, ok := editor_project_world(
		origin,
		viewport,
		camera,
		has_camera,
	); if !ok { return false }
	world_endpoints: [3]shared.Vec3
	for axis, index in world_axes {
		world_endpoints[index] = vec3_add(origin, vec3_mul(axis, world_size))
	}
	endpoints: [3]shared.Vec2
	for endpoint, index in world_endpoints {projected, projected_ok := editor_project_world(
			endpoint,
			viewport,
			camera,
			has_camera,
		)
		if !projected_ok { return false }
		endpoints[index] = projected}
	state.editor_gizmo_origin = origin_screen; state.editor_gizmo_endpoints = endpoints
	pairs := [3][2]int{{0, 1}, {0, 2}, {1, 2}}
	for pair, pair_index in pairs {
		for corner in 0 ..< 4 {
			first_factor := f32(0.22); second_factor := f32(0.22)
			if corner == 1 || corner == 2 { first_factor = 0.43 }
			if corner >= 2 { second_factor = 0.43 }
			point := origin
			point = vec3_add(point, vec3_mul(world_axes[pair[0]], world_size * first_factor))
			point = vec3_add(point, vec3_mul(world_axes[pair[1]], world_size * second_factor))
			projected, projected_ok := editor_project_world(
				point,
				viewport,
				camera,
				has_camera,
			); if !projected_ok { return false }
			state.editor_gizmo_plane_points[pair_index][corner] = projected
		}
	}
	if mode == .Rotate {
		for axis in 0 ..< 3 {
			for point_index in 0 ..< ui.EDITOR_GIZMO_RING_POINT_COUNT {
				angle := f32(point_index) / f32(ui.EDITOR_GIZMO_RING_POINT_COUNT) * 2 * math.PI
				c, s := f32(math.cos(angle)) * world_size, f32(math.sin(angle)) * world_size
				first, second := 0, 1
				switch axis {
					case 0:
						first, second = 1, 2
					case 1:
						first, second = 0, 2
					case 2:
						first, second = 0, 1
				}
				point := vec3_add(
					origin,
					vec3_add(vec3_mul(world_axes[first], c), vec3_mul(world_axes[second], s)),
				)
				projected, projected_ok := editor_project_world(
					point,
					viewport,
					camera,
					has_camera,
				); if !projected_ok { return false }
				state.editor_gizmo_ring_points[axis][point_index] = projected
			}
		}
	}
	state.editor_gizmo_visible = true; return true
}

editor_project_world :: proc(
	point: shared.Vec3,
	viewport: ui.Rect,
	camera: shared.Camera_Instance,
	has_camera: bool,
) -> (
	shared.Vec2,
	bool,
) {
	if viewport.width <= 0 ||
	   viewport.height <=
		   0 { return {}, false }; eye, fov := editor_camera_eye_fov(camera, has_camera); near, far := f32(0.1), f32(100)
	if has_camera { if camera.camera.near > 0 { near = camera.camera.near }; if camera.camera.far > near { far = camera.camera.far } }
	target :=
		shared.Vec3{}; up := shared.Vec3{0, 1, 0}; if has_camera { target = shared.camera_vec3_add(eye, shared.camera_forward(camera.transform.rotation)); up = shared.camera_up(camera.transform.rotation) }
	view := mat4_look_at(
		eye,
		target,
		up,
	); projection := mat4_perspective(math.to_radians(fov), viewport.width / viewport.height, near, far); vp := mat4_mul(projection, view)
	clip_x :=
		vp[0] * point.x +
		vp[4] * point.y +
		vp[8] * point.z +
		vp[12]; clip_y := vp[1] * point.x + vp[5] * point.y + vp[9] * point.z + vp[13]; clip_w := vp[3] * point.x + vp[7] * point.y + vp[11] * point.z + vp[15]
	if clip_w <= 0.0001 { return {}, false }; ndc_x, ndc_y := clip_x / clip_w, clip_y / clip_w
	return {
			viewport.x + (ndc_x + 1) * 0.5 * viewport.width,
			viewport.y + (1 - ndc_y) * 0.5 * viewport.height,
		},
		true
}

editor_camera_eye_fov :: proc(
	camera: shared.Camera_Instance,
	has_camera: bool,
) -> (
	shared.Vec3,
	f32,
) {eye := shared.Vec3{0, 2, 6}; fov := f32(60); if has_camera {eye = camera.transform.position
		if camera.camera.fov > 0 { fov = camera.camera.fov }}
	return eye, fov}

editor_gizmo_hit_handle :: proc(
	point, origin: shared.Vec2,
	endpoints: [3]shared.Vec2,
	planes: [3][4]shared.Vec2,
	rings: [3][ui.EDITOR_GIZMO_RING_POINT_COUNT]shared.Vec2,
	mode: shared.Editor_Gizmo_Mode,
	available: bool,
) -> ui.Editor_Gizmo_Handle {
	if !available { return .None }; nearest := EDITOR_GIZMO_HIT_RADIUS; axis := ui.Editor_Gizmo_Handle.None
	if mode == .Rotate {
		for ring, index in rings {for point_index in 0 ..< len(
				ring,
			) { distance := screen_point_segment_distance(point, ring[point_index], ring[(point_index + 1) % len(ring)]); if distance <= nearest { nearest = distance; axis = ui.Editor_Gizmo_Handle(index + 1) } }}
	} else {
		if screen_length(screen_sub(point, origin)) <= 8 { return .Center }
		for endpoint, index in endpoints {distance := screen_point_segment_distance(
				point,
				origin,
				endpoint,
			)
			if distance <=
			   nearest { nearest = distance; axis = ui.Editor_Gizmo_Handle(index + 1) }}
		if axis != .None { return axis }
		for plane, index in planes {if screen_point_in_quad(
				point,
				plane,
			) { return ui.Editor_Gizmo_Handle(int(ui.Editor_Gizmo_Handle.XY) + index) }}
	}
	return axis
}

editor_gizmo_pair_axes :: proc(handle: ui.Editor_Gizmo_Handle) -> (int, int, bool) {switch
	handle {case .XY:
			return 0, 1, true; case .XZ:
			return 0, 2, true; case .YZ:
			return 1, 2, true; case .None, .X, .Y, .Z, .Center:
			return 0, 0, false}
	return 0, 0, false}

editor_gizmo_single_axis :: proc(handle: ui.Editor_Gizmo_Handle) -> (int, bool) {
	switch handle {
		case .X:
			return 0, true
		case .Y:
			return 1, true
		case .Z:
			return 2, true
		case .None, .XY, .XZ, .YZ, .Center:
			return 0, false
	}
	return 0, false
}

editor_gizmo_rotation_matrix :: proc(rotation: shared.Vec3) -> Mat4 {
	return mat4_mul(
		mat4_rotate_z(rotation.z),
		mat4_mul(mat4_rotate_y(rotation.y), mat4_rotate_x(rotation.x)),
	)
}

editor_gizmo_axes :: proc(
	rotation: shared.Vec3,
	space: shared.Editor_Gizmo_Space,
) -> [3]shared.Vec3 {
	if space == .World {
		return {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}
	}
	rotation_matrix := editor_gizmo_rotation_matrix(rotation)
	return {
		{rotation_matrix[0], rotation_matrix[1], rotation_matrix[2]},
		{rotation_matrix[4], rotation_matrix[5], rotation_matrix[6]},
		{rotation_matrix[8], rotation_matrix[9], rotation_matrix[10]},
	}
}

editor_gizmo_matrix_euler :: proc(rotation_matrix: Mat4) -> shared.Vec3 {
	sin_y := clamp(-rotation_matrix[2], -1, 1)
	y := f32(math.asin(sin_y))
	cos_y := f32(math.cos(y))
	if math.abs(cos_y) > 0.00001 {
		return {
			f32(math.atan2(rotation_matrix[6], rotation_matrix[10])),
			y,
			f32(math.atan2(rotation_matrix[1], rotation_matrix[0])),
		}
	}
	x := f32(math.atan2(rotation_matrix[4], rotation_matrix[5]))
	if sin_y < 0 {
		x = -x
	}
	return {x, y, 0}
}

editor_gizmo_rotated_euler :: proc(
	start: shared.Vec3,
	axis: int,
	angle: f32,
	space: shared.Editor_Gizmo_Space,
) -> shared.Vec3 {
	delta := mat4_identity()
	switch axis {
		case 0:
			delta = mat4_rotate_x(angle)
		case 1:
			delta = mat4_rotate_y(angle)
		case 2:
			delta = mat4_rotate_z(angle)
		case:
			return start
	}
	start_matrix := editor_gizmo_rotation_matrix(start)
	result := mat4_mul(delta, start_matrix)
	if space == .Local {
		result = mat4_mul(start_matrix, delta)
	}
	return editor_gizmo_matrix_euler(result)
}

screen_solve_basis :: proc(delta, first, second: shared.Vec2) -> (f32, f32, bool) {det :=
		first.x * second.y - first.y * second.x
	if math.abs(det) < 0.001 { return 0, 0, false }
	return (delta.x * second.y - delta.y * second.x) / det,
		(first.x * delta.y - first.y * delta.x) / det,
		true}
screen_point_in_quad :: proc(point: shared.Vec2, quad: [4]shared.Vec2) -> bool {return(
		screen_point_in_triangle(point, quad[0], quad[1], quad[2]) ||
		screen_point_in_triangle(point, quad[0], quad[2], quad[3]) \
	)}
screen_point_in_triangle :: proc(point, a, b, c: shared.Vec2) -> bool {ab := screen_cross(
		screen_sub(b, a),
		screen_sub(point, a),
	)
	bc := screen_cross(screen_sub(c, b), screen_sub(point, b))
	ca := screen_cross(screen_sub(a, c), screen_sub(point, c))
	return (ab >= 0 && bc >= 0 && ca >= 0) || (ab <= 0 && bc <= 0 && ca <= 0)}
screen_cross :: proc(a, b: shared.Vec2) -> f32 { return a.x * b.y - a.y * b.x }
vec3_mul_axis :: proc(value: ^shared.Vec3, axis: int, factor: f32) {switch axis {case 0:
			value.x *= factor; case 1:
			value.y *= factor; case 2:
			value.z *= factor; case:}}
vec3_add :: proc(a, b: shared.Vec3) -> shared.Vec3 { return {a.x + b.x, a.y + b.y, a.z + b.z} }
vec3_mul :: proc(value: shared.Vec3, amount: f32) -> shared.Vec3 {return{
		value.x * amount,
		value.y * amount,
		value.z * amount,
	}}

screen_point_segment_distance :: proc(point, a, b: shared.Vec2) -> f32 {ab := screen_sub(b, a)
	length_squared := ab.x * ab.x + ab.y * ab.y
	if length_squared <= 0 { return screen_length(screen_sub(point, a)) }
	ap := screen_sub(point, a)
	t := clamp((ap.x * ab.x + ap.y * ab.y) / length_squared, 0, 1)
	closest := shared.Vec2{a.x + ab.x * t, a.y + ab.y * t}
	return screen_length(screen_sub(point, closest))}
screen_sub :: proc(a, b: shared.Vec2) -> shared.Vec2 { return {a.x - b.x, a.y - b.y} }
screen_length :: proc(value: shared.Vec2) -> f32 {return math.sqrt(
		value.x * value.x + value.y * value.y,
	)}
screen_rotation_delta :: proc(previous, current: shared.Vec2) -> f32 {
	// Screen Y increases downward, opposite the world/Euler rotation convention.
	return(
		-f32(
			math.atan2(
				previous.x * current.y - previous.y * current.x,
				previous.x * current.x + previous.y * current.y,
			),
		) \
	)
}
