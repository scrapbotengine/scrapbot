package ecs

import shared "../shared"
import "core:math"

EDITOR_SCENE_CAMERA_NAME :: "Editor Scene Camera"
EDITOR_SCENE_CAMERA_MOVE_SPEED :: f32(5)
EDITOR_SCENE_CAMERA_DOLLY_SCALE :: f32(0.5)
EDITOR_SCENE_CAMERA_LOOK_SENSITIVITY :: f32(0.0025)
EDITOR_SCENE_CAMERA_DEFAULT_ORBIT_DISTANCE :: f32(10)
EDITOR_SCENE_CAMERA_MIN_ORBIT_DISTANCE :: f32(0.05)
EDITOR_SCENE_CAMERA_NEAR :: f32(0.01)
EDITOR_SCENE_CAMERA_FOCUS_MARGIN :: f32(1.1)

reconcile_editor_scene_camera :: proc(
	world: ^World,
	enabled: bool,
) -> (
	int,
	^shared.Editor_Scene_Camera_Component,
	bool,
) {
	if world == nil {
		return -1, nil, false
	}
	if entity_index, component, ok := editor_scene_camera_entity(world); ok || !enabled {
		return entity_index, component, ok
	}

	transform := shared.Transform_Component {
		position = {0, 2, 6},
		rotation = {-0.32175055, 0, 0},
		scale = {1, 1, 1},
	}
	camera := shared.camera_defaults()
	camera.far = 100
	if source, ok := first_camera_instance(world); ok {
		transform = source.transform
		camera = source.camera
	}
	// The editor fly camera is an inspection tool. Keep the project's lens and
	// far plane, but allow close surface inspection without slicing nearby
	// geometry into screen-sized near-plane wedges.
	camera.near = min(camera.near, EDITOR_SCENE_CAMERA_NEAR)

	entity_index, created := create_world_entity(
		world,
		EDITOR_SCENE_CAMERA_NAME,
		shared.entity_uuid_from_engine_name(EDITOR_SCENE_CAMERA_NAME),
		.Editor,
		false,
	)
	if !created {
		return -1, nil, false
	}
	transform_index := len(world.transforms)
	camera_index := len(world.cameras)
	component_index := len(world.editor_scene_cameras)
	append_soa(&world.transforms, transform)
	append(&world.cameras, camera)
	world.entities[entity_index].transform_index = transform_index
	world.entities[entity_index].camera_index = camera_index
	append(
		&world.editor_scene_cameras,
		shared.Editor_Scene_Camera_Component {
			entity_index = entity_index,
			move_speed = EDITOR_SCENE_CAMERA_MOVE_SPEED,
			look_sensitivity = EDITOR_SCENE_CAMERA_LOOK_SENSITIVITY,
			orbit_target = shared.camera_vec3_add(
				transform.position,
				shared.camera_vec3_mul(
					shared.camera_forward(transform.rotation),
					EDITOR_SCENE_CAMERA_DEFAULT_ORBIT_DISTANCE,
				),
			),
			orbit_distance = EDITOR_SCENE_CAMERA_DEFAULT_ORBIT_DISTANCE,
		},
	)
	sync_render_watch_memberships(world, entity_index)
	return entity_index, &world.editor_scene_cameras[component_index], true
}

editor_scene_camera_entity :: proc(
	world: ^World,
) -> (
	int,
	^shared.Editor_Scene_Camera_Component,
	bool,
) {
	if world == nil {
		return -1, nil, false
	}
	for &component in world.editor_scene_cameras {
		index := component.entity_index
		if index >= 0 &&
		   index < len(world.entities) &&
		   world.entities[index].alive &&
		   world.entities[index].origin == .Editor {
			return index, &component, true
		}
	}
	return -1, nil, false
}

editor_scene_camera_system :: proc(
	world: ^World,
	input: shared.Editor_Fly_Camera_Input,
	delta_seconds: f32,
	enabled: bool,
) {
	entity_index, component, ok := reconcile_editor_scene_camera(world, enabled)
	if !enabled || !ok || entity_index < 0 || component == nil {
		return
	}
	entity := &world.entities[entity_index]
	if entity.transform_index < 0 || entity.transform_index >= len(world.transforms) {
		return
	}
	transform := &world.transforms[entity.transform_index]
	if input.look_active || input.orbit_active {
		transform.rotation.y += input.look_delta.x * component.look_sensitivity
		transform.rotation.x = clamp(
			transform.rotation.x - input.look_delta.y * component.look_sensitivity,
			-math.to_radians(f32(89)),
			math.to_radians(f32(89)),
		)
		transform.rotation.z = 0
	}
	if input.orbit_active {
		component.orbit_distance = max(
			component.orbit_distance,
			EDITOR_SCENE_CAMERA_MIN_ORBIT_DISTANCE,
		)
		transform.position = shared.camera_vec3_add(
			component.orbit_target,
			shared.camera_vec3_mul(
				shared.camera_forward(transform.rotation),
				-component.orbit_distance,
			),
		)
	}

	direction := shared.camera_vec3_add(
		shared.camera_vec3_mul(shared.camera_right(transform.rotation), input.movement.x),
		shared.camera_vec3_add(
			shared.camera_vec3_mul({0, 1, 0}, input.movement.y),
			shared.camera_vec3_mul(shared.camera_forward(transform.rotation), input.movement.z),
		),
	)
	direction = shared.camera_vec3_normalize(direction)
	move_speed := component.move_speed
	if input.move_fast {
		move_speed *= 4
	}
	movement := shared.camera_vec3_mul(direction, move_speed * max(delta_seconds, 0))
	transform.position = shared.camera_vec3_add(transform.position, movement)
	component.orbit_target = shared.camera_vec3_add(component.orbit_target, movement)
	if input.look_active {
		component.orbit_target = shared.camera_vec3_add(
			transform.position,
			shared.camera_vec3_mul(
				shared.camera_forward(transform.rotation),
				component.orbit_distance,
			),
		)
	}
	if input.dolly != 0 {
		component.orbit_distance = max(
			component.orbit_distance -
			input.dolly * component.move_speed * EDITOR_SCENE_CAMERA_DOLLY_SCALE,
			EDITOR_SCENE_CAMERA_MIN_ORBIT_DISTANCE,
		)
		transform.position = shared.camera_vec3_add(
			component.orbit_target,
			shared.camera_vec3_mul(
				shared.camera_forward(transform.rotation),
				-component.orbit_distance,
			),
		)
	}
}

focus_editor_scene_camera :: proc(
	world: ^World,
	target: shared.Vec3,
	radius: f32,
	aspect: f32,
) -> bool {
	entity_index, component, ok := reconcile_editor_scene_camera(world, true)
	if !ok || entity_index < 0 || entity_index >= len(world.entities) {
		return false
	}
	entity := &world.entities[entity_index]
	if entity.transform_index < 0 ||
	   entity.transform_index >= len(world.transforms) ||
	   entity.camera_index < 0 ||
	   entity.camera_index >= len(world.cameras) {
		return false
	}
	transform := world.transforms[entity.transform_index]
	camera := world.cameras[entity.camera_index]
	vertical_half_fov := math.to_radians(clamp(camera.fov, f32(1), f32(179))) * 0.5
	horizontal_half_fov := math.atan(math.tan(vertical_half_fov) * max(aspect, 0.01))
	limiting_half_fov := min(vertical_half_fov, horizontal_half_fov)
	bounded_radius := max(radius, 0.25)
	distance :=
		bounded_radius / max(math.sin(limiting_half_fov), 0.01) * EDITOR_SCENE_CAMERA_FOCUS_MARGIN
	transform.position = shared.camera_vec3_add(
		target,
		shared.camera_vec3_mul(shared.camera_forward(transform.rotation), -distance),
	)
	component.orbit_target = target
	component.orbit_distance = distance
	add_transform(world, entity_index, transform)
	return true
}

set_editor_scene_camera_pose :: proc(
	world: ^World,
	position: shared.Vec3,
	rotation: shared.Vec3,
) -> bool {
	entity_index, component, ok := reconcile_editor_scene_camera(world, true)
	if !ok || entity_index < 0 || entity_index >= len(world.entities) {
		return false
	}
	entity := &world.entities[entity_index]
	if entity.transform_index < 0 || entity.transform_index >= len(world.transforms) {
		return false
	}
	transform := world.transforms[entity.transform_index]
	transform.position = position
	transform.rotation = rotation
	transform.rotation.x = clamp(
		transform.rotation.x,
		-math.to_radians(f32(89)),
		math.to_radians(f32(89)),
	)
	transform.rotation.z = 0
	if component.orbit_distance <= 0 {
		component.orbit_distance = EDITOR_SCENE_CAMERA_DEFAULT_ORBIT_DISTANCE
	}
	component.orbit_target = shared.camera_vec3_add(
		transform.position,
		shared.camera_vec3_mul(
			shared.camera_forward(transform.rotation),
			component.orbit_distance,
		),
	)
	add_transform(world, entity_index, transform)
	return true
}

reconcile_editor_transform_gizmo :: proc(
	world: ^World,
	selected: shared.Entity,
	enabled: bool,
	mode: shared.Editor_Gizmo_Mode = .Translate,
	space: shared.Editor_Gizmo_Space = .World,
) {
	if world == nil { return }; target := INVALID_COMPONENT_INDEX
	if enabled { index := int(selected.index); if index >= 0 && index < len(world.entities) && world.entities[index].alive && world.entities[index].id.generation == selected.generation && world.entities[index].transform_index >= 0 { target = index } }
	for &entity, index in world.entities {
		if entity.editor_transform_gizmo_index < 0 { continue }
		if entity.editor_transform_gizmo_index >= len(world.editor_transform_gizmos) ||
		   world.editor_transform_gizmos[entity.editor_transform_gizmo_index].entity_index !=
			   index { entity.editor_transform_gizmo_index = INVALID_COMPONENT_INDEX; continue }
		if index !=
		   target { world.editor_transform_gizmos[entity.editor_transform_gizmo_index].entity_index = INVALID_COMPONENT_INDEX; entity.editor_transform_gizmo_index = INVALID_COMPONENT_INDEX }
	}
	if target < 0 { return }
	target_component_index := world.entities[target].editor_transform_gizmo_index
	if target_component_index >= 0 &&
	   target_component_index < len(world.editor_transform_gizmos) &&
	   world.editor_transform_gizmos[target_component_index].entity_index == target {
		world.editor_transform_gizmos[target_component_index].mode = mode
		world.editor_transform_gizmos[target_component_index].space = space
		return
	}
	component_index := INVALID_COMPONENT_INDEX
	for component, index in world.editor_transform_gizmos { if component.entity_index < 0 { component_index = index; break } }
	component := shared.Editor_Transform_Gizmo_Component {
		entity_index = target,
		mode = mode,
		space = space,
	}
	if component_index <
	   0 { component_index = len(world.editor_transform_gizmos); append(&world.editor_transform_gizmos, component) } else { world.editor_transform_gizmos[component_index] = component }
	world.entities[target].editor_transform_gizmo_index = component_index
}

editor_transform_gizmo_entity :: proc(
	world: ^World,
) -> (
	int,
	^shared.Editor_Transform_Gizmo_Component,
	bool,
) {
	if world == nil { return -1, nil, false }
	for &component, index in world.editor_transform_gizmos { if component.entity_index >= 0 && component.entity_index < len(world.entities) && world.entities[component.entity_index].alive && world.entities[component.entity_index].editor_transform_gizmo_index == index { return component.entity_index, &component, true } }
	return -1, nil, false
}
