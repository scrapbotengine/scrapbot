package ecs

import shared "../shared"
import "core:math"

EDITOR_SCENE_CAMERA_NAME :: "Editor Scene Camera"
EDITOR_SCENE_CAMERA_MOVE_SPEED :: f32(5)
EDITOR_SCENE_CAMERA_LOOK_SENSITIVITY :: f32(0.0025)

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
	camera := shared.Camera_Component {
		fov = 60,
		near = 0.1,
		far = 100,
	}
	if source, ok := first_camera_instance(world); ok {
		transform = source.transform
		camera = source.camera
	}

	entity_index := len(world.entities)
	transform_index := len(world.transforms)
	camera_index := len(world.cameras)
	component_index := len(world.editor_scene_cameras)
	append_soa(&world.transforms, transform)
	append(&world.cameras, camera)
	append(
		&world.editor_scene_cameras,
		shared.Editor_Scene_Camera_Component {
			entity_index = entity_index,
			move_speed = EDITOR_SCENE_CAMERA_MOVE_SPEED,
			look_sensitivity = EDITOR_SCENE_CAMERA_LOOK_SENSITIVITY,
		},
	)
	append(
		&world.entities,
		World_Entity {
			id = {index = u32(entity_index), generation = 1},
			uuid = shared.entity_uuid_from_engine_name(EDITOR_SCENE_CAMERA_NAME),
			alive = true,
			origin = .Editor,
			name = clone_world_string(EDITOR_SCENE_CAMERA_NAME),
			transform_index = transform_index,
			camera_index = camera_index,
			ambient_light_index = INVALID_COMPONENT_INDEX,
			directional_light_index = INVALID_COMPONENT_INDEX,
			point_light_index = INVALID_COMPONENT_INDEX,
			mesh_index = INVALID_COMPONENT_INDEX,
			geometry_index = INVALID_COMPONENT_INDEX,
			material_index = INVALID_COMPONENT_INDEX,
			render_instance_index = INVALID_COMPONENT_INDEX,
			render_active_index = INVALID_COMPONENT_INDEX,
			ui_layout_index = INVALID_COMPONENT_INDEX,
			ui_hstack_index = INVALID_COMPONENT_INDEX,
			ui_vstack_index = INVALID_COMPONENT_INDEX,
			ui_scroll_area_index = INVALID_COMPONENT_INDEX,
			ui_panel_index = INVALID_COMPONENT_INDEX,
			ui_table_index = INVALID_COMPONENT_INDEX,
			ui_text_index = INVALID_COMPONENT_INDEX,
			ui_button_index = INVALID_COMPONENT_INDEX,
			ui_input_index = INVALID_COMPONENT_INDEX,
			editor_transform_gizmo_index = INVALID_COMPONENT_INDEX,
			editor_ui_index = INVALID_COMPONENT_INDEX,
		},
	)
	if world.entity_by_uuid == nil {
		world.entity_by_uuid = make(map[shared.Entity_UUID]int)
	}
	world.entity_by_uuid[world.entities[entity_index].uuid] = entity_index
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
	if input.look_active {
		transform.rotation.y += input.look_delta.x * component.look_sensitivity
		transform.rotation.x = clamp(
			transform.rotation.x - input.look_delta.y * component.look_sensitivity,
			-math.to_radians(f32(89)),
			math.to_radians(f32(89)),
		)
		transform.rotation.z = 0
	}

	direction := shared.camera_vec3_add(
		shared.camera_vec3_mul(shared.camera_right(transform.rotation), input.movement.x),
		shared.camera_vec3_add(
			shared.camera_vec3_mul({0, 1, 0}, input.movement.y),
			shared.camera_vec3_mul(shared.camera_forward(transform.rotation), input.movement.z),
		),
	)
	direction = shared.camera_vec3_normalize(direction)
	transform.position = shared.camera_vec3_add(
		transform.position,
		shared.camera_vec3_mul(direction, component.move_speed * max(delta_seconds, 0)),
	)
}

reconcile_editor_transform_gizmo :: proc(
	world: ^World,
	selected: shared.Entity,
	enabled: bool,
	mode: shared.Editor_Gizmo_Mode = .Translate,
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
	   world.editor_transform_gizmos[target_component_index].entity_index ==
		   target { world.editor_transform_gizmos[target_component_index].mode = mode; return }
	component_index := INVALID_COMPONENT_INDEX
	for component, index in world.editor_transform_gizmos { if component.entity_index < 0 { component_index = index; break } }
	component := shared.Editor_Transform_Gizmo_Component {
		entity_index = target,
		mode = mode,
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
