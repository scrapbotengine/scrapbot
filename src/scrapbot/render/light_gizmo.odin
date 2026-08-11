package render

import ecs "../ecs"
import shared "../shared"
import ui "../ui"
import "core:math"

EDITOR_LIGHT_GIZMO_RING_POINTS :: 48
EDITOR_LIGHT_GIZMO_DIRECTION_PIXELS :: f32(110)
EDITOR_LIGHT_GIZMO_HIT_RADIUS :: f32(11)

editor_light_gizmo_system :: proc(
	state: ^ui.State,
	world: ^shared.World,
	pointer: ui.Pointer_Input,
	viewport: ui.Rect,
	camera: shared.Camera_Instance,
	has_camera: bool,
	keyboard: ui.Keyboard_Input = {},
) {
	if state == nil {
		return
	}
	state.editor_light_gizmo_segment_count = 0
	state.editor_light_gizmo_hovered = false
	state.editor_light_gizmo_visible = false
	if world == nil || !state.editor_visible || !state.editor_has_selection {
		editor_light_gizmo_cancel(state, world, true)
		return
	}
	entity_index := int(state.editor_selected_entity.index)
	if entity_index < 0 || entity_index >= len(world.entities) {
		editor_light_gizmo_cancel(state, world, true)
		return
	}
	entity := &world.entities[entity_index]
	if !entity.alive || entity.id != state.editor_selected_entity || entity.origin == .Editor {
		editor_light_gizmo_cancel(state, world, true)
		return
	}
	if state.editor_light_gizmo_active && state.editor_light_gizmo_entity != entity.id {
		editor_light_gizmo_cancel(state, world, true)
		return
	}

	ecs.begin_world_transform_resolution(world)
	origin: shared.Vec3
	has_origin := false
	if entity.transform_index >= 0 && entity.transform_index < len(world.transforms) {
		if transform, resolved := ecs.resolve_world_transform(world, entity_index); resolved {
			origin = transform.position
			has_origin = true
		}
	}

	point_index := entity.point_light_index
	directional_index := entity.directional_light_index
	if point_index >= 0 && point_index < len(world.point_lights) && has_origin {
		editor_point_light_gizmo(
			state,
			world,
			entity_index,
			origin,
			pointer,
			viewport,
			camera,
			has_camera,
			keyboard,
		)
		return
	}
	if directional_index >= 0 && directional_index < len(world.directional_lights) {
		editor_directional_light_gizmo(
			state,
			world,
			entity_index,
			origin,
			pointer,
			viewport,
			camera,
			has_camera,
			keyboard,
		)
		return
	}
	editor_light_gizmo_cancel(state, world, true)
}

editor_point_light_gizmo :: proc(
	state: ^ui.State,
	world: ^shared.World,
	entity_index: int,
	origin: shared.Vec3,
	pointer: ui.Pointer_Input,
	viewport: ui.Rect,
	camera: shared.Camera_Instance,
	has_camera: bool,
	keyboard: ui.Keyboard_Input,
) {
	entity := &world.entities[entity_index]
	light := &world.point_lights[entity.point_light_index]
	radius := max(light.range, 0.01)
	editor_light_gizmo_begin_visual(state, entity.id, .Point_Range, viewport)

	axes := [3][2]shared.Vec3 {
		{{1, 0, 0}, {0, 1, 0}},
		{{1, 0, 0}, {0, 0, 1}},
		{{0, 1, 0}, {0, 0, 1}},
	}
	for ring_axes in axes {
		previous: shared.Vec2
		previous_ok := false
		for step in 0 ..= EDITOR_LIGHT_GIZMO_RING_POINTS {
			angle := f32(step) / f32(EDITOR_LIGHT_GIZMO_RING_POINTS) * 2 * math.PI
			point := vec3_add(
				origin,
				vec3_add(
					vec3_mul(ring_axes[0], math.cos(angle) * radius),
					vec3_mul(ring_axes[1], math.sin(angle) * radius),
				),
			)
			projected, projected_ok := editor_project_world(point, viewport, camera, has_camera)
			if previous_ok && projected_ok {
				editor_light_gizmo_append_segment(state, previous, projected)
			}
			previous = projected
			previous_ok = projected_ok
		}
	}

	right := shared.Vec3{1, 0, 0}
	if has_camera {
		right = shared.camera_right(camera.transform.rotation)
	}
	handle_world := vec3_add(origin, vec3_mul(right, radius))
	origin_screen, origin_ok := editor_project_world(origin, viewport, camera, has_camera)
	handle_screen, handle_ok := editor_project_world(handle_world, viewport, camera, has_camera)
	if !origin_ok || !handle_ok {
		state.editor_light_gizmo_visible = false
		return
	}
	state.editor_light_gizmo_origin = origin_screen
	state.editor_light_gizmo_handle = handle_screen
	editor_light_gizmo_interact_point(state, world, entity_index, pointer, keyboard, radius)
}

editor_directional_light_gizmo :: proc(
	state: ^ui.State,
	world: ^shared.World,
	entity_index: int,
	origin: shared.Vec3,
	pointer: ui.Pointer_Input,
	viewport: ui.Rect,
	camera: shared.Camera_Instance,
	has_camera: bool,
	keyboard: ui.Keyboard_Input,
) {
	entity := &world.entities[entity_index]
	light := &world.directional_lights[entity.directional_light_index]
	direction := vec3_normalize(light.direction)
	if vec3_dot(direction, direction) < 0.0001 {
		direction = {0, -1, 0}
	}
	eye, fov := editor_camera_eye_fov(camera, has_camera)
	distance := math.sqrt(vec3_dot(vec3_sub(origin, eye), vec3_sub(origin, eye)))
	world_size := max(
		2 *
		max(distance, 0.1) *
		math.tan(math.to_radians(fov) * 0.5) /
		max(viewport.height, 1) *
		EDITOR_LIGHT_GIZMO_DIRECTION_PIXELS,
		0.05,
	)
	if state.editor_light_gizmo_active {
		world_size = state.editor_light_gizmo_drag_world_size
	}
	end := vec3_add(origin, vec3_mul(direction, world_size))
	origin_screen, origin_ok := editor_project_world(origin, viewport, camera, has_camera)
	handle_screen, handle_ok := editor_project_world(end, viewport, camera, has_camera)
	if !origin_ok || !handle_ok {
		state.editor_light_gizmo_visible = false
		return
	}
	editor_light_gizmo_begin_visual(state, entity.id, .Directional_Direction, viewport)
	state.editor_light_gizmo_origin = origin_screen
	state.editor_light_gizmo_handle = handle_screen
	editor_light_gizmo_append_segment(state, origin_screen, handle_screen)
	editor_light_gizmo_interact_direction(
		state,
		world,
		entity_index,
		origin,
		pointer,
		viewport,
		camera,
		has_camera,
		keyboard,
		direction,
		world_size,
	)
}

editor_light_gizmo_begin_visual :: proc(
	state: ^ui.State,
	entity: shared.Entity,
	kind: ui.Editor_Light_Gizmo_Kind,
	viewport: ui.Rect,
) {
	state.editor_light_gizmo_visible = true
	state.editor_light_gizmo_entity = entity
	state.editor_light_gizmo_kind = kind
	state.editor_light_gizmo_clip = viewport
}

editor_light_gizmo_append_segment :: proc(state: ^ui.State, start, end: shared.Vec2) {
	if state.editor_light_gizmo_segment_count >= len(state.editor_light_gizmo_segments) {
		return
	}
	state.editor_light_gizmo_segments[state.editor_light_gizmo_segment_count] = {start, end}
	state.editor_light_gizmo_segment_count += 1
}

editor_light_gizmo_hit_handle :: proc(state: ^ui.State, pointer: ui.Pointer_Input) -> bool {
	if !pointer.available {
		return false
	}
	delta := shared.Vec2 {
		pointer.position.x - state.editor_light_gizmo_handle.x,
		pointer.position.y - state.editor_light_gizmo_handle.y,
	}
	radius := EDITOR_LIGHT_GIZMO_HIT_RADIUS * max(state.editor_pixel_density, 1)
	return delta.x * delta.x + delta.y * delta.y <= radius * radius
}

editor_light_gizmo_interact_point :: proc(
	state: ^ui.State,
	world: ^shared.World,
	entity_index: int,
	pointer: ui.Pointer_Input,
	keyboard: ui.Keyboard_Input,
	radius: f32,
) {
	state.editor_light_gizmo_hovered = editor_light_gizmo_hit_handle(state, pointer)
	just_pressed :=
		pointer.available && pointer.primary_down && !state.editor_previous_primary_down
	if !state.editor_light_gizmo_active && just_pressed && state.editor_light_gizmo_hovered {
		state.editor_light_gizmo_active = true
		state.editor_light_gizmo_captures_pointer = true
		state.editor_light_gizmo_drag_range = radius
		pixel_radius := screen_length(
			screen_sub(state.editor_light_gizmo_handle, state.editor_light_gizmo_origin),
		)
		state.editor_light_gizmo_drag_pixels_per_world = pixel_radius / max(radius, 0.01)
		ui.consume_editor_pointer_activation(state, pointer)
	}
	if !state.editor_light_gizmo_active {
		return
	}
	state.editor_light_gizmo_captures_pointer = true
	if keyboard.escape {
		editor_light_gizmo_write_point_range(
			state,
			world,
			entity_index,
			state.editor_light_gizmo_drag_range,
		)
		state.editor_keyboard_escape_consumed = true
		state.editor_light_gizmo_active = false
		state.editor_light_gizmo_captures_pointer = false
		return
	}
	if !pointer.primary_down {
		binding := shared.Editor_UI_Component {
			target = world.entities[entity_index].id,
			inspector_field = .Point_Range,
		}
		ui.editor_history_push(state, world, binding, state.editor_light_gizmo_drag_range, radius)
		state.editor_light_gizmo_active = false
		state.editor_light_gizmo_captures_pointer = false
		return
	}
	pixel_radius := screen_length(screen_sub(pointer.position, state.editor_light_gizmo_origin))
	new_range := max(
		pixel_radius / max(state.editor_light_gizmo_drag_pixels_per_world, 0.001),
		0.01,
	)
	editor_light_gizmo_write_point_range(state, world, entity_index, new_range)
}

editor_light_gizmo_interact_direction :: proc(
	state: ^ui.State,
	world: ^shared.World,
	entity_index: int,
	origin: shared.Vec3,
	pointer: ui.Pointer_Input,
	viewport: ui.Rect,
	camera: shared.Camera_Instance,
	has_camera: bool,
	keyboard: ui.Keyboard_Input,
	direction: shared.Vec3,
	world_size: f32,
) {
	state.editor_light_gizmo_hovered = editor_light_gizmo_hit_handle(state, pointer)
	just_pressed :=
		pointer.available && pointer.primary_down && !state.editor_previous_primary_down
	if !state.editor_light_gizmo_active && just_pressed && state.editor_light_gizmo_hovered {
		state.editor_light_gizmo_active = true
		state.editor_light_gizmo_captures_pointer = true
		state.editor_light_gizmo_drag_direction = direction
		state.editor_light_gizmo_drag_origin = origin
		state.editor_light_gizmo_drag_world_size = world_size
		ui.consume_editor_pointer_activation(state, pointer)
	}
	if !state.editor_light_gizmo_active {
		return
	}
	state.editor_light_gizmo_captures_pointer = true
	if keyboard.escape {
		editor_light_gizmo_write_direction(
			state,
			world,
			entity_index,
			state.editor_light_gizmo_drag_direction,
		)
		state.editor_keyboard_escape_consumed = true
		state.editor_light_gizmo_active = false
		state.editor_light_gizmo_captures_pointer = false
		return
	}
	if !pointer.primary_down {
		ui.editor_history_push_transform(
			state,
			world,
			entity_index,
			.Directional_Direction,
			state.editor_light_gizmo_drag_direction,
			direction,
		)
		state.editor_light_gizmo_active = false
		state.editor_light_gizmo_captures_pointer = false
		return
	}
	ray, ray_ok := editor_camera_pick_ray(camera, has_camera, pointer.position, viewport)
	if !ray_ok {
		return
	}
	new_direction, solved := editor_light_gizmo_direction_on_sphere(
		ray,
		state.editor_light_gizmo_drag_origin,
		state.editor_light_gizmo_drag_world_size,
		direction,
	)
	if solved {
		editor_light_gizmo_write_direction(state, world, entity_index, new_direction)
	}
}

editor_light_gizmo_direction_on_sphere :: proc(
	ray: Pick_Ray,
	origin: shared.Vec3,
	radius: f32,
	current: shared.Vec3,
) -> (
	shared.Vec3,
	bool,
) {
	offset := vec3_sub(ray.origin, origin)
	half_b := vec3_dot(offset, ray.direction)
	constant := vec3_dot(offset, offset) - radius * radius
	discriminant := half_b * half_b - constant
	if discriminant >= 0 {
		root := math.sqrt(discriminant)
		first := -half_b - root
		second := -half_b + root
		best: shared.Vec3
		found := false
		distances := [2]f32{first, second}
		for distance in distances {
			if distance < 0 {
				continue
			}
			candidate := vec3_normalize(
				vec3_sub(vec3_add(ray.origin, vec3_mul(ray.direction, distance)), origin),
			)
			if !found || vec3_dot(candidate, current) > vec3_dot(best, current) {
				best = candidate
				found = true
			}
		}
		if found {
			return best, true
		}
	}
	closest_distance := max(-vec3_dot(offset, ray.direction), 0)
	closest := vec3_sub(vec3_add(ray.origin, vec3_mul(ray.direction, closest_distance)), origin)
	if vec3_dot(closest, closest) < 0.000001 {
		return {}, false
	}
	return vec3_normalize(closest), true
}

editor_light_gizmo_write_point_range :: proc(
	state: ^ui.State,
	world: ^shared.World,
	entity_index: int,
	value: f32,
) {
	_ = ui.write_inspector_numeric(
		state,
		world,
		{target = world.entities[entity_index].id, inspector_field = .Point_Range},
		value,
	)
}

editor_light_gizmo_write_direction :: proc(
	state: ^ui.State,
	world: ^shared.World,
	entity_index: int,
	value: shared.Vec3,
) {
	normalized := vec3_normalize(value)
	values := [3]f32{normalized.x, normalized.y, normalized.z}
	axes := [3]shared.Editor_Inspector_Axis{.X, .Y, .Z}
	for axis, index in axes {
		_ = ui.write_inspector_numeric(
			state,
			world,
			{
				target = world.entities[entity_index].id,
				inspector_field = .Directional_Direction,
				inspector_axis = axis,
			},
			values[index],
		)
	}
}

editor_light_gizmo_cancel :: proc(state: ^ui.State, world: ^shared.World, restore: bool) {
	if state == nil {
		return
	}
	if restore && state.editor_light_gizmo_active && world != nil {
		entity_index := int(state.editor_light_gizmo_entity.index)
		if entity_index >= 0 &&
		   entity_index < len(world.entities) &&
		   world.entities[entity_index].alive &&
		   world.entities[entity_index].id == state.editor_light_gizmo_entity {
			switch state.editor_light_gizmo_kind {
				case .Point_Range:
					editor_light_gizmo_write_point_range(
						state,
						world,
						entity_index,
						state.editor_light_gizmo_drag_range,
					)
				case .Directional_Direction:
					editor_light_gizmo_write_direction(
						state,
						world,
						entity_index,
						state.editor_light_gizmo_drag_direction,
					)
				case .None:
			}
		}
	}
	state.editor_light_gizmo_active = false
	state.editor_light_gizmo_captures_pointer = false
	state.editor_light_gizmo_visible = false
}
