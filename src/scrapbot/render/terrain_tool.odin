package render

import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import ui "../ui"
import "core:math"

editor_terrain_tool_system :: proc(
	state: ^ui.State,
	world: ^shared.World,
	registry: ^resources.Registry,
	pointer: ui.Pointer_Input,
	viewport: ui.Rect,
	camera: shared.Camera_Instance,
	has_camera: bool,
) {
	if state != nil {
		state.editor_terrain_preview_visible = false
	}
	if state == nil ||
	   world == nil ||
	   registry == nil ||
	   !state.editor_visible ||
	   !state.editor_simulation_stopped ||
	   state.editor_terrain_tool == .None ||
	   !pointer.available ||
	   ui.editor_pointer_consumed_by_chrome(state, pointer) {
		return
	}
	target_entity, target_handle, target_transform, target_ok := editor_selected_voxel_surface(
		state,
		world,
		registry,
	)
	if !target_ok {
		return
	}
	ray, ray_ok := editor_camera_pick_ray(camera, has_camera, pointer.position, viewport)
	if !ray_ok {
		return
	}
	hit, hit_ok := editor_terrain_raycast_selected(
		registry,
		target_handle,
		target_transform,
		target_entity,
		ray,
	)
	if !hit_ok {
		return
	}
	local_contact, contact_ok := editor_terrain_inverse_point(target_transform, hit.position)
	local_normal, normal_ok := editor_terrain_inverse_normal(target_transform, hit.normal)
	if !contact_ok || !normal_ok {
		return
	}
	geometry, alive := resources.get_geometry(registry, target_handle)
	if !alive || !geometry.has_voxel_surface {
		return
	}
	adding := state.editor_terrain_tool == .Add_Cell
	cell, cell_ok := resources.voxel_surface_cell_at_contact(
		&geometry.voxel_surface,
		local_contact,
		local_normal,
		adding,
	)
	if !cell_ok {
		return
	}
	minimum, maximum := resources.voxel_surface_cell_bounds(&geometry.voxel_surface, cell)
	if editor_terrain_project_cell_preview(
		state,
		target_transform,
		minimum,
		maximum,
		viewport,
		camera,
		has_camera,
	) {
		state.editor_terrain_preview_visible = true
		state.editor_terrain_preview_clip = viewport
	}
	pressed := pointer.primary_down && !state.editor_previous_primary_down
	if pressed {
		list := ecs.build_resource_render_list(world, registry, true)
		nearest, nearest_ok := scene_raycast_nearest(&list, registry, ray)
		ecs.destroy_render_list(&list)
		if !nearest_ok || nearest.entity != target_entity {
			return
		}
		edit, edit_err := resources.edit_voxel_surface_cell(registry, target_handle, cell, adding)
		if edit_err == "" && edit != nil {
			ui.editor_history_push_terrain_edit(state, edit)
			ecs.mark_all_render_entities_dirty(world)
			ecs.reconcile_render_instances(world, registry)
			ui.consume_editor_pointer_activation(state, pointer)
		}
	}
}

editor_terrain_raycast_selected :: proc(
	registry: ^resources.Registry,
	handle: shared.Geometry_Handle,
	transform: shared.Transform_Component,
	entity: shared.Entity,
	ray: Pick_Ray,
) -> (
	Scene_Ray_Hit,
	bool,
) {
	geometry, alive := resources.get_geometry(registry, handle)
	if !alive {
		return {}, false
	}
	model := wgpu_build_model(transform)
	if _, hit_bounds := pick_ray_transformed_bounds(ray, geometry.bounds, model); !hit_bounds {
		return {}, false
	}
	iterator := resources.geometry_query_iterator(geometry)
	nearest := f32(3.4028235e38)
	result: Scene_Ray_Hit
	found := false
	pick_query_triangles(&iterator, model, ray, entity, &nearest, &result, &found, nil)
	return result, found
}

editor_selected_voxel_surface :: proc(
	state: ^ui.State,
	world: ^shared.World,
	registry: ^resources.Registry,
) -> (
	shared.Entity,
	shared.Geometry_Handle,
	shared.Transform_Component,
	bool,
) {
	if state == nil || !state.editor_has_selection {
		return {}, {}, {}, false
	}
	entity_index := int(state.editor_selected_entity.index)
	if !ecs.entity_is_alive(world, entity_index) ||
	   world.entities[entity_index].id != state.editor_selected_entity {
		return {}, {}, {}, false
	}
	entity := world.entities[entity_index]
	handle: shared.Geometry_Handle
	has_handle := false
	if entity.mesh_index >= 0 && entity.mesh_index < len(world.meshes) {
		handle, has_handle = resources.geometry_by_name(
			registry,
			world.meshes[entity.mesh_index].primitive,
		)
	} else if entity.geometry_index >= 0 && entity.geometry_index < len(world.geometries) {
		handle = world.geometries[entity.geometry_index].handle
		has_handle = true
	}
	if !has_handle {
		return {}, {}, {}, false
	}
	geometry, alive := resources.get_geometry(registry, handle)
	if !alive || !geometry.has_voxel_surface {
		return {}, {}, {}, false
	}
	transform, transformed := ecs.resolve_world_transform(world, entity_index)
	if !transformed {
		transform = {
			scale = {1, 1, 1},
		}
	}
	return entity.id, handle, transform, true
}

editor_terrain_inverse_point :: proc(
	transform: shared.Transform_Component,
	point: shared.Vec3,
) -> (
	shared.Vec3,
	bool,
) {
	if transform.scale.x == 0 || transform.scale.y == 0 || transform.scale.z == 0 {
		return {}, false
	}
	delta := shared.Vec3 {
		point.x - transform.position.x,
		point.y - transform.position.y,
		point.z - transform.position.z,
	}
	unrotated := shared.transform_quaternion_rotate(
		shared.transform_quaternion_conjugate(
			shared.transform_quaternion_from_euler(transform.rotation),
		),
		delta,
	)
	return {
			unrotated.x / transform.scale.x,
			unrotated.y / transform.scale.y,
			unrotated.z / transform.scale.z,
		},
		true
}

editor_terrain_inverse_normal :: proc(
	transform: shared.Transform_Component,
	normal: shared.Vec3,
) -> (
	shared.Vec3,
	bool,
) {
	unrotated := shared.transform_quaternion_rotate(
		shared.transform_quaternion_conjugate(
			shared.transform_quaternion_from_euler(transform.rotation),
		),
		normal,
	)
	local := shared.Vec3 {
		unrotated.x * transform.scale.x,
		unrotated.y * transform.scale.y,
		unrotated.z * transform.scale.z,
	}
	length_squared := local.x * local.x + local.y * local.y + local.z * local.z
	if length_squared <= 0.0000001 {
		return {}, false
	}
	inverse_length := 1 / math.sqrt(length_squared)
	return {local.x * inverse_length, local.y * inverse_length, local.z * inverse_length}, true
}

editor_terrain_project_cell_preview :: proc(
	state: ^ui.State,
	transform: shared.Transform_Component,
	minimum, maximum: shared.Vec3,
	viewport: ui.Rect,
	camera: shared.Camera_Instance,
	has_camera: bool,
) -> bool {
	local_corners := [8]shared.Vec3 {
		{minimum.x, minimum.y, minimum.z},
		{maximum.x, minimum.y, minimum.z},
		{maximum.x, maximum.y, minimum.z},
		{minimum.x, maximum.y, minimum.z},
		{minimum.x, minimum.y, maximum.z},
		{maximum.x, minimum.y, maximum.z},
		{maximum.x, maximum.y, maximum.z},
		{minimum.x, maximum.y, maximum.z},
	}
	projected: [8]shared.Vec2
	for corner, index in local_corners {
		world_corner := editor_transform_point(transform, corner)
		point, ok := editor_project_world(world_corner, viewport, camera, has_camera)
		if !ok {
			return false
		}
		projected[index] = point
	}
	edges := [12][2]int {
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
	}
	for edge, index in edges {
		state.editor_terrain_preview_segments[index] = {
			start = projected[edge[0]],
			end = projected[edge[1]],
		}
	}
	return true
}
