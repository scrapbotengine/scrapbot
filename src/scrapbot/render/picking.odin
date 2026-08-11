package render

import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import ui "../ui"
import "core:math"

Pick_Ray :: struct {
	origin, direction: shared.Vec3,
}

Scene_Ray_Hit :: struct {
	entity: shared.Entity,
	position, normal: shared.Vec3,
	distance: f32,
}

Scene_Raycast_Stats :: struct {
	instance_tests: u64,
	instance_bounds_rejections: u64,
	group_tests: u64,
	group_bounds_rejections: u64,
	cluster_tests: u64,
	cluster_bounds_rejections: u64,
	triangle_tests: u64,
}

Editor_Model_Placement :: struct {
	position: shared.Vec3,
	contact: shared.Vec3,
	normal: shared.Vec3,
	grounded: bool,
}

editor_selection_focus_bounds :: proc(
	world: ^shared.World,
	render_list: ^shared.Render_List,
	registry: ^resources.Registry,
	selected: shared.Entity,
	selected_uuid: shared.Entity_UUID,
) -> (
	shared.Vec3,
	f32,
	bool,
) {
	minimum, maximum: shared.Vec3
	has_bounds := false
	if render_list != nil && registry != nil {
		for instance in render_list.instances {
			matches :=
				instance.entity.id == selected || instance.entity.model_owner == selected_uuid
			if !matches && world != nil {
				instance_index := int(instance.entity.id.index)
				matches =
					ecs.entity_is_alive(world, instance_index) &&
					world.entities[instance_index].id == instance.entity.id &&
					ecs.entity_is_descendant_of_uuid(world, instance_index, selected_uuid)
			}
			if !matches {
				continue
			}
			geometry, found := resources.get_geometry(registry, instance.geometry.handle)
			if !found {
				continue
			}
			for x in 0 ..< 2 {
				for y in 0 ..< 2 {
					for z in 0 ..< 2 {
						point := editor_transform_point(
							instance.transform,
							{
								geometry.bounds.min.x if x == 0 else geometry.bounds.max.x,
								geometry.bounds.min.y if y == 0 else geometry.bounds.max.y,
								geometry.bounds.min.z if z == 0 else geometry.bounds.max.z,
							},
						)
						if !has_bounds {
							minimum = point
							maximum = point
							has_bounds = true
						} else {
							minimum = {
								min(minimum.x, point.x),
								min(minimum.y, point.y),
								min(minimum.z, point.z),
							}
							maximum = {
								max(maximum.x, point.x),
								max(maximum.y, point.y),
								max(maximum.z, point.z),
							}
						}
					}
				}
			}
		}
	}
	if has_bounds {
		center := pick_mul(pick_add(minimum, maximum), 0.5)
		half_extent := vec3_sub(maximum, center)
		return center, max(math.sqrt(vec3_dot(half_extent, half_extent)), 0.25), true
	}
	if world == nil {
		return {}, 0, false
	}
	selected_index := int(selected.index)
	if !ecs.entity_is_alive(world, selected_index) ||
	   world.entities[selected_index].id != selected ||
	   world.entities[selected_index].transform_index < 0 {
		return {}, 0, false
	}
	ecs.begin_world_transform_resolution(world)
	transform, resolved := ecs.resolve_world_transform(world, selected_index)
	if !resolved {
		return {}, 0, false
	}
	radius :=
		max(
			math.abs(transform.scale.x),
			math.abs(transform.scale.y),
			math.abs(transform.scale.z),
		) *
		0.5
	return transform.position, max(radius, 0.25), true
}

editor_gizmo_bounds_entity_matches_selection :: proc(
	world: ^shared.World,
	entity_index: int,
	selected_uuid: shared.Entity_UUID,
) -> bool {
	if world == nil || !ecs.entity_is_alive(world, entity_index) {
		return false
	}
	entity := world.entities[entity_index]
	return(
		entity.uuid == selected_uuid ||
		entity.model_owner == selected_uuid ||
		ecs.entity_is_descendant_of_uuid(world, entity_index, selected_uuid) \
	)
}

editor_gizmo_bounds_dirty_for_selection :: proc(
	world: ^shared.World,
	selected_uuid: shared.Entity_UUID,
) -> bool {
	if world == nil {
		return false
	}
	for entity_index in world.render_dirty_entities {
		if editor_gizmo_bounds_entity_matches_selection(world, entity_index, selected_uuid) {
			return true
		}
	}
	for entity_index in world.render_extract_dirty_entities {
		if editor_gizmo_bounds_entity_matches_selection(world, entity_index, selected_uuid) {
			return true
		}
	}
	for entity_index in world.render_transform_dirty_entities {
		if editor_gizmo_bounds_entity_matches_selection(world, entity_index, selected_uuid) {
			return true
		}
	}
	return false
}

editor_update_gizmo_bounds_center :: proc(
	state: ^ui.State,
	world: ^shared.World,
	registry: ^resources.Registry,
) {
	if state == nil ||
	   world == nil ||
	   registry == nil ||
	   state.editor_gizmo_pivot != .Center ||
	   state.editor_gizmo_active_handle != .None {
		return
	}
	selected_uuid, selected := ui.editor_selected_uuid(state, world)
	if !selected {
		state.editor_gizmo_bounds_valid = false
		return
	}
	invalid :=
		!state.editor_gizmo_bounds_valid ||
		state.editor_gizmo_bounds_selected != selected_uuid ||
		state.editor_gizmo_bounds_world_uuid != world.instance_uuid ||
		state.editor_gizmo_bounds_render_topology_revision != world.render_topology_revision ||
		state.editor_gizmo_bounds_render_hierarchy_revision != world.render_hierarchy_revision ||
		state.editor_gizmo_bounds_geometry_topology_revision !=
			registry.geometry_topology_revision ||
		editor_gizmo_bounds_dirty_for_selection(world, selected_uuid)
	if !invalid {
		return
	}
	render_list: shared.Render_List
	ecs.begin_world_transform_resolution(world)
	for entity_index in world.render_active_entities {
		if instance, found := ecs.resource_render_instance_for_entity(world, entity_index); found {
			append(&render_list.instances, instance)
		}
	}
	center, _, bounded := editor_selection_focus_bounds(
		world,
		&render_list,
		registry,
		state.editor_selected_entity,
		selected_uuid,
	)
	ecs.destroy_render_list(&render_list)
	state.editor_gizmo_bounds_center = center
	state.editor_gizmo_bounds_selected = selected_uuid
	state.editor_gizmo_bounds_world_uuid = world.instance_uuid
	state.editor_gizmo_bounds_render_topology_revision = world.render_topology_revision
	state.editor_gizmo_bounds_render_hierarchy_revision = world.render_hierarchy_revision
	state.editor_gizmo_bounds_geometry_topology_revision = registry.geometry_topology_revision
	state.editor_gizmo_bounds_valid = bounded
}

editor_pick_ray :: proc(
	render_list: ^shared.Render_List,
	position: shared.Vec2,
	viewport: ui.Rect,
) -> (
	Pick_Ray,
	bool,
) {
	camera: shared.Camera_Instance
	has_camera := render_list != nil && render_list.has_camera
	if has_camera {
		camera = render_list.camera
	}
	return editor_camera_pick_ray(camera, has_camera, position, viewport)
}

editor_camera_pick_ray :: proc(
	camera: shared.Camera_Instance,
	has_camera: bool,
	position: shared.Vec2,
	viewport: ui.Rect,
) -> (
	Pick_Ray,
	bool,
) {
	if viewport.width <= 0 || viewport.height <= 0 {
		return {}, false
	}
	eye := shared.Vec3{0, 2, 6}
	fov := f32(60)
	if has_camera {
		eye = camera.transform.position
		if camera.camera.fov > 0 {
			fov = camera.camera.fov
		}
	}
	forward := vec3_normalize(vec3_sub({}, eye))
	side := vec3_normalize(vec3_cross(forward, {0, 1, 0}))
	true_up := vec3_cross(side, forward)
	if has_camera {
		forward = shared.camera_forward(camera.transform.rotation)
		side = shared.camera_right(camera.transform.rotation)
		true_up = shared.camera_up(camera.transform.rotation)
	}
	ndc_x := (position.x - viewport.x) / viewport.width * 2 - 1
	ndc_y := 1 - (position.y - viewport.y) / viewport.height * 2
	tan_half := math.tan(math.to_radians(fov) * 0.5)
	aspect := viewport.width / viewport.height
	direction := pick_add(
		forward,
		pick_add(pick_mul(side, ndc_x * aspect * tan_half), pick_mul(true_up, ndc_y * tan_half)),
	)
	return {eye, vec3_normalize(direction)}, true
}

editor_pick_entity :: proc(
	render_list: ^shared.Render_List,
	registry: ^resources.Registry,
	position: shared.Vec2,
	viewport: ui.Rect,
	stats: ^Scene_Raycast_Stats = nil,
) -> (
	shared.Entity,
	bool,
) {
	if render_list == nil || registry == nil {
		return {}, false
	}
	ray, ray_ok := editor_pick_ray(render_list, position, viewport)
	if !ray_ok {
		return {}, false
	}
	hit, found := scene_raycast_nearest(render_list, registry, ray, stats)
	return hit.entity, found
}

scene_raycast_nearest :: proc(
	render_list: ^shared.Render_List,
	registry: ^resources.Registry,
	ray: Pick_Ray,
	stats: ^Scene_Raycast_Stats = nil,
) -> (
	Scene_Ray_Hit,
	bool,
) {
	if render_list == nil || registry == nil {
		return {}, false
	}
	nearest := f32(3.4028235e38)
	result: Scene_Ray_Hit
	found := false
	for instance in render_list.instances {
		if stats != nil {
			stats.instance_tests += 1
		}
		geometry, ok := resources.get_geometry(registry, instance.geometry.handle)
		if !ok {
			continue
		}
		model := wgpu_build_model(instance.transform)
		bounds_entry, bounds_hit := pick_ray_transformed_bounds(ray, geometry.bounds, model)
		if !bounds_hit || bounds_entry > nearest {
			if stats != nil {
				stats.instance_bounds_rejections += 1
			}
			continue
		}
		if !resources.geometry_has_resident_canonical(geometry) && len(geometry.clusters) > 0 {
			for group in geometry.cluster_groups {
				if stats != nil {
					stats.group_tests += 1
				}
				group_center := pick_transform_point(
					model,
					{group.bounds[0], group.bounds[1], group.bounds[2]},
				)
				group_radius :=
					group.bounds[3] *
					max(
						math.abs(instance.transform.scale.x),
						math.abs(instance.transform.scale.y),
						math.abs(instance.transform.scale.z),
					)
				group_entry, group_hit := pick_ray_sphere(ray, group_center, group_radius)
				if !group_hit || group_entry > nearest {
					if stats != nil {
						stats.group_bounds_rejections += 1
					}
					continue
				}
				cluster_start := int(group.cluster_offset)
				cluster_end := min(
					cluster_start + int(group.cluster_count),
					len(geometry.clusters),
				)
				for cluster, cluster_offset in geometry.clusters[cluster_start:cluster_end] {
					if cluster.refined_group != -1 {
						continue
					}
					if stats != nil {
						stats.cluster_tests += 1
					}
					center := pick_transform_point(
						model,
						{cluster.bounds[0], cluster.bounds[1], cluster.bounds[2]},
					)
					radius :=
						cluster.bounds[3] *
						max(
							math.abs(instance.transform.scale.x),
							math.abs(instance.transform.scale.y),
							math.abs(instance.transform.scale.z),
						)
					cluster_entry, cluster_hit := pick_ray_sphere(ray, center, radius)
					if !cluster_hit || cluster_entry > nearest {
						if stats != nil {
							stats.cluster_bounds_rejections += 1
						}
						continue
					}
					iterator := resources.geometry_query_cluster_iterator(
						geometry,
						cluster_start + cluster_offset,
					)
					pick_query_triangles(
						&iterator,
						model,
						ray,
						instance.entity.id,
						&nearest,
						&result,
						&found,
						stats,
					)
				}
			}
		} else {
			iterator := resources.geometry_query_iterator(geometry)
			pick_query_triangles(
				&iterator,
				model,
				ray,
				instance.entity.id,
				&nearest,
				&result,
				&found,
				stats,
			)
		}
	}
	return result, found
}

pick_query_triangles :: proc(
	iterator: ^resources.Geometry_Query_Iterator,
	model: Mat4,
	ray: Pick_Ray,
	entity: shared.Entity,
	nearest: ^f32,
	result: ^Scene_Ray_Hit,
	found: ^bool,
	stats: ^Scene_Raycast_Stats,
) {
	for {
		triangle, triangle_ok := resources.geometry_query_next(iterator)
		if !triangle_ok {
			return
		}
		if stats != nil {
			stats.triangle_tests += 1
		}
		a := pick_transform_point(model, triangle.a)
		b := pick_transform_point(model, triangle.b)
		c := pick_transform_point(model, triangle.c)
		if distance, hit := pick_ray_triangle(ray, a, b, c); hit && distance < nearest^ {
			nearest^ = distance
			result^ = {
				entity = entity,
				position = pick_add(ray.origin, pick_mul(ray.direction, distance)),
				normal = vec3_normalize(vec3_cross(vec3_sub(b, a), vec3_sub(c, a))),
				distance = distance,
			}
			found^ = true
		}
	}
}

pick_ray_sphere :: proc(ray: Pick_Ray, center: shared.Vec3, radius: f32) -> (f32, bool) {
	if radius < 0 {
		return 0, false
	}
	offset := vec3_sub(ray.origin, center)
	half_b := vec3_dot(offset, ray.direction)
	constant := vec3_dot(offset, offset) - radius * radius
	discriminant := half_b * half_b - constant
	if discriminant < 0 {
		return 0, false
	}
	root := math.sqrt(discriminant)
	exit := -half_b + root
	if exit < 0 {
		return 0, false
	}
	return max(-half_b - root, 0), true
}

pick_ray_transformed_bounds :: proc(
	ray: Pick_Ray,
	bounds: resources.Bounds,
	model: Mat4,
) -> (
	f32,
	bool,
) {
	minimum := shared.Vec3{f32(3.4028235e38), f32(3.4028235e38), f32(3.4028235e38)}
	maximum := shared.Vec3{f32(-3.4028235e38), f32(-3.4028235e38), f32(-3.4028235e38)}
	for x in 0 ..< 2 {
		for y in 0 ..< 2 {
			for z in 0 ..< 2 {
				point := pick_transform_point(
					model,
					{
						bounds.min.x if x == 0 else bounds.max.x,
						bounds.min.y if y == 0 else bounds.max.y,
						bounds.min.z if z == 0 else bounds.max.z,
					},
				)
				minimum = {
					min(minimum.x, point.x),
					min(minimum.y, point.y),
					min(minimum.z, point.z),
				}
				maximum = {
					max(maximum.x, point.x),
					max(maximum.y, point.y),
					max(maximum.z, point.z),
				}
			}
		}
	}
	return pick_ray_bounds(ray, minimum, maximum)
}

pick_ray_bounds :: proc(ray: Pick_Ray, minimum, maximum: shared.Vec3) -> (f32, bool) {
	entry := f32(0)
	exit := f32(3.4028235e38)
	origins := [3]f32{ray.origin.x, ray.origin.y, ray.origin.z}
	directions := [3]f32{ray.direction.x, ray.direction.y, ray.direction.z}
	minimums := [3]f32{minimum.x, minimum.y, minimum.z}
	maximums := [3]f32{maximum.x, maximum.y, maximum.z}
	for axis in 0 ..< 3 {
		if math.abs(directions[axis]) < 0.000001 {
			if origins[axis] < minimums[axis] || origins[axis] > maximums[axis] {
				return 0, false
			}
			continue
		}
		inverse := 1 / directions[axis]
		near := (minimums[axis] - origins[axis]) * inverse
		far := (maximums[axis] - origins[axis]) * inverse
		if near > far {
			near, far = far, near
		}
		entry = max(entry, near)
		exit = min(exit, far)
		if exit < entry {
			return 0, false
		}
	}
	return entry, exit >= 0
}

scene_ray_plane_intersection :: proc(
	ray: Pick_Ray,
	point, normal: shared.Vec3,
) -> (
	shared.Vec3,
	bool,
) {
	denominator := vec3_dot(ray.direction, normal)
	if math.abs(denominator) < 0.000001 {
		return {}, false
	}
	distance := vec3_dot(vec3_sub(point, ray.origin), normal) / denominator
	if distance <= 0.0001 {
		return {}, false
	}
	return pick_add(ray.origin, pick_mul(ray.direction, distance)), true
}

editor_model_placement_position :: proc(
	render_list: ^shared.Render_List,
	registry: ^resources.Registry,
	resource: shared.Resource_UUID,
	pointer: shared.Vec2,
	viewport: ui.Rect,
	snap_step: f32,
) -> (
	Editor_Model_Placement,
	bool,
) {
	ray, ray_ok := editor_pick_ray(render_list, pointer, viewport)
	if !ray_ok {
		return {}, false
	}
	contact: shared.Vec3
	normal: shared.Vec3
	grounded := false
	if hit, found := scene_raycast_nearest(render_list, registry, ray); found {
		contact = hit.position
		normal = hit.normal
		if vec3_dot(normal, ray.direction) > 0 {
			normal = pick_mul(normal, -1)
		}
		grounded = true
	} else if plane_position, found := scene_ray_plane_intersection(ray, {}, {0, 1, 0}); found {
		contact = plane_position
		normal = {0, 1, 0}
		grounded = true
	} else {
		contact = pick_add(ray.origin, pick_mul(ray.direction, 5))
	}
	if snap_step > 0 {
		contact.x = math.round(contact.x / snap_step) * snap_step
		contact.y = math.round(contact.y / snap_step) * snap_step
		contact.z = math.round(contact.z / snap_step) * snap_step
	}
	position := contact
	if grounded {
		if support, center, found := editor_model_support_projection(registry, resource, normal);
		   found {
			position = pick_add(
				pick_add(contact, pick_mul(center, -1)),
				pick_mul(normal, vec3_dot(center, normal) - support),
			)
		}
	}
	return {position = position, contact = contact, normal = normal, grounded = grounded}, true
}

editor_model_support_projection :: proc(
	registry: ^resources.Registry,
	resource: shared.Resource_UUID,
	normal: shared.Vec3,
) -> (
	f32,
	shared.Vec3,
	bool,
) {
	if registry == nil || resource == (shared.Resource_UUID{}) {
		return 0, {}, false
	}
	handle, found := resources.model_handle_by_uuid(registry, resource)
	if !found {
		return 0, {}, false
	}
	model, alive := resources.get_model(registry, handle)
	if !alive || len(model.nodes) == 0 {
		return 0, {}, false
	}
	world_transforms := make(
		[]shared.Transform_Component,
		len(model.nodes),
		context.temp_allocator,
	)
	states := make([]u8, len(model.nodes), context.temp_allocator)
	minimum := f32(0)
	bounds_minimum: shared.Vec3
	bounds_maximum: shared.Vec3
	has_point := false
	for node, node_index in model.nodes {
		if node.mesh_index < 0 || int(node.mesh_index) >= len(model.meshes) {
			continue
		}
		transform, resolved := editor_model_node_transform(
			model,
			node_index,
			world_transforms,
			states,
		)
		if !resolved {
			continue
		}
		for primitive in model.meshes[node.mesh_index].primitives {
			geometry, geometry_alive := resources.get_geometry(registry, primitive.geometry)
			if !geometry_alive {
				continue
			}
			for x in 0 ..< 2 {
				for y in 0 ..< 2 {
					for z in 0 ..< 2 {
						local := shared.Vec3 {
							geometry.bounds.min.x if x == 0 else geometry.bounds.max.x,
							geometry.bounds.min.y if y == 0 else geometry.bounds.max.y,
							geometry.bounds.min.z if z == 0 else geometry.bounds.max.z,
						}
						point := editor_transform_point(transform, local)
						projection := vec3_dot(point, normal)
						if !has_point || projection < minimum {
							minimum = projection
						}
						if !has_point {
							bounds_minimum = point
							bounds_maximum = point
						} else {
							bounds_minimum = {
								min(bounds_minimum.x, point.x),
								min(bounds_minimum.y, point.y),
								min(bounds_minimum.z, point.z),
							}
							bounds_maximum = {
								max(bounds_maximum.x, point.x),
								max(bounds_maximum.y, point.y),
								max(bounds_maximum.z, point.z),
							}
						}
						has_point = true
					}
				}
			}
		}
	}
	center := pick_mul(pick_add(bounds_minimum, bounds_maximum), 0.5)
	return minimum, center, has_point
}

editor_model_node_transform :: proc(
	model: ^resources.Model,
	index: int,
	transforms: []shared.Transform_Component,
	states: []u8,
) -> (
	shared.Transform_Component,
	bool,
) {
	if model == nil ||
	   index < 0 ||
	   index >= len(model.nodes) ||
	   index >= len(transforms) ||
	   index >= len(states) {
		return {}, false
	}
	if states[index] == 2 {
		return transforms[index], true
	}
	if states[index] == 1 {
		return {}, false
	}
	states[index] = 1
	result := model.nodes[index].transform
	parent := model.nodes[index].parent_index
	if parent >= 0 {
		parent_transform, resolved := editor_model_node_transform(
			model,
			int(parent),
			transforms,
			states,
		)
		if !resolved {
			states[index] = 0
			return {}, false
		}
		result = shared.transform_combine(parent_transform, result)
	}
	transforms[index] = result
	states[index] = 2
	return result, true
}

editor_transform_point :: proc(
	transform: shared.Transform_Component,
	point: shared.Vec3,
) -> shared.Vec3 {
	scaled := shared.Vec3 {
		point.x * transform.scale.x,
		point.y * transform.scale.y,
		point.z * transform.scale.z,
	}
	rotated := shared.transform_quaternion_rotate(
		shared.transform_quaternion_from_euler(transform.rotation),
		scaled,
	)
	return pick_add(transform.position, rotated)
}

pick_ray_triangle :: proc(ray: Pick_Ray, a, b, c: shared.Vec3) -> (f32, bool) {
	edge1 := vec3_sub(b, a)
	edge2 := vec3_sub(c, a)
	p := vec3_cross(ray.direction, edge2)
	det := vec3_dot(edge1, p)
	if math.abs(det) < 0.000001 {
		return 0, false
	}
	inverse_det := 1 / det
	tvec := vec3_sub(ray.origin, a)
	u := vec3_dot(tvec, p) * inverse_det
	if u < 0 || u > 1 {
		return 0, false
	}
	q := vec3_cross(tvec, edge1)
	v := vec3_dot(ray.direction, q) * inverse_det
	if v < 0 || u + v > 1 {
		return 0, false
	}
	distance := vec3_dot(edge2, q) * inverse_det
	return distance, distance > 0.0001
}

pick_transform_point :: proc(m: Mat4, point: shared.Vec3) -> shared.Vec3 {
	return {
		m[0] * point.x + m[4] * point.y + m[8] * point.z + m[12],
		m[1] * point.x + m[5] * point.y + m[9] * point.z + m[13],
		m[2] * point.x + m[6] * point.y + m[10] * point.z + m[14],
	}
}

pick_add :: proc(a, b: shared.Vec3) -> shared.Vec3 {
	return {a.x + b.x, a.y + b.y, a.z + b.z}
}

pick_mul :: proc(value: shared.Vec3, scalar: f32) -> shared.Vec3 {
	return {value.x * scalar, value.y * scalar, value.z * scalar}
}
