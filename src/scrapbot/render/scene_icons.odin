package render

import ecs "../ecs"
import shared "../shared"
import ui "../ui"

EDITOR_SCENE_ICON_PICK_RADIUS :: f32(16)

editor_scene_icon_system :: proc(
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
	state.editor_scene_icon_count = 0
	if !enabled || world == nil || viewport.width <= 0 || viewport.height <= 0 {
		return
	}

	ecs.begin_world_transform_resolution(world)
	for entity_index in world.render_active_camera_entities {
		if state.editor_scene_icon_count >= len(state.editor_scene_icons) {
			break
		}
		editor_scene_icon_append(
			state,
			world,
			entity_index,
			.Camera,
			viewport,
			view_camera,
			has_view_camera,
			false,
		)
	}
	for entity_index in world.render_active_directional_light_entities {
		if state.editor_scene_icon_count >= len(state.editor_scene_icons) {
			break
		}
		if editor_scene_entity_has_camera(world, entity_index) {
			continue
		}
		editor_scene_icon_append(
			state,
			world,
			entity_index,
			.Directional_Light,
			viewport,
			view_camera,
			has_view_camera,
			true,
		)
	}
	for entity_index in world.render_active_point_light_entities {
		if state.editor_scene_icon_count >= len(state.editor_scene_icons) {
			break
		}
		if editor_scene_entity_has_camera(world, entity_index) ||
		   editor_scene_entity_has_directional_light(world, entity_index) {
			continue
		}
		editor_scene_icon_append(
			state,
			world,
			entity_index,
			.Point_Light,
			viewport,
			view_camera,
			has_view_camera,
			false,
		)
	}
}

editor_scene_icon_append :: proc(
	state: ^ui.State,
	world: ^shared.World,
	entity_index: int,
	kind: ui.Editor_Scene_Icon_Kind,
	viewport: ui.Rect,
	view_camera: shared.Camera_Instance,
	has_view_camera: bool,
	allow_world_origin: bool,
) {
	if state.editor_scene_icon_count >= len(state.editor_scene_icons) ||
	   entity_index < 0 ||
	   entity_index >= len(world.entities) {
		return
	}
	entity := world.entities[entity_index]
	if !entity.alive || entity.origin == .Editor {
		return
	}
	position: shared.Vec3
	if entity.transform_index >= 0 && entity.transform_index < len(world.transforms) {
		transform, resolved := ecs.resolve_world_transform(world, entity_index)
		if !resolved {
			return
		}
		position = transform.position
	} else if !allow_world_origin {
		return
	}
	center, projected := editor_project_world(position, viewport, view_camera, has_view_camera)
	if !projected {
		return
	}
	state.editor_scene_icons[state.editor_scene_icon_count] = {
		entity = entity.id,
		kind = kind,
		center = center,
		clip = viewport,
		selected = state.editor_has_selection && state.editor_selected_entity == entity.id,
	}
	state.editor_scene_icon_count += 1
}

editor_scene_entity_has_camera :: proc(world: ^shared.World, entity_index: int) -> bool {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return false
	}
	index := world.entities[entity_index].camera_index
	return index >= 0 && index < len(world.cameras)
}

editor_scene_entity_has_directional_light :: proc(
	world: ^shared.World,
	entity_index: int,
) -> bool {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return false
	}
	index := world.entities[entity_index].directional_light_index
	return index >= 0 && index < len(world.directional_lights)
}

editor_pick_scene_icon :: proc(state: ^ui.State, position: shared.Vec2) -> (shared.Entity, bool) {
	if state == nil || !state.editor_visible {
		return {}, false
	}
	radius := EDITOR_SCENE_ICON_PICK_RADIUS * max(state.editor_pixel_density, 1)
	count := min(state.editor_scene_icon_count, len(state.editor_scene_icons))
	for index := count - 1; index >= 0; index -= 1 {
		icon := state.editor_scene_icons[index]
		if position.x >= icon.center.x - radius &&
		   position.x <= icon.center.x + radius &&
		   position.y >= icon.center.y - radius &&
		   position.y <= icon.center.y + radius &&
		   ui.rect_contains(icon.clip, position) {
			return icon.entity, true
		}
	}
	return {}, false
}
