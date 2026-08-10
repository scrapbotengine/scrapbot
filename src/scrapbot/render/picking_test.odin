package render

import resources "../resources"
import shared "../shared"
import ui "../ui"
import "core:math"
import "core:testing"

@(test)
test_editor_picking_returns_nearest_transformed_triangle_hit :: proc(t: ^testing.T) {
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	desc, desc_err := resources.cube()
	testing.expect(t, desc_err == "")
	defer delete(desc.vertices)
	defer delete(desc.indices)
	handle, register_err := resources.register_geometry(&registry, "pick-cube", desc)
	testing.expect(t, register_err == "")
	list := shared.Render_List {
		has_camera = true,
		camera = {transform = {position = {0, 0, 6}}, camera = {fov = 60, near = 0.1, far = 100}},
	}
	defer delete(list.instances)
	append(
		&list.instances,
		shared.Render_Instance {
			entity = {id = {index = 1, generation = 1}, alive = true},
			transform = {position = {0, 0, 0}, scale = {1, 1, 1}},
			geometry = {handle = handle},
		},
		shared.Render_Instance {
			entity = {id = {index = 2, generation = 3}, alive = true},
			transform = {position = {0, 0, 2}, scale = {1, 1, 1}},
			geometry = {handle = handle},
		},
	)
	viewport := ui.Rect{100, 50, 800, 600}
	entity, found := editor_pick_entity(&list, &registry, {500, 350}, viewport)
	testing.expect(t, found)
	testing.expect(t, entity == shared.Entity{index = 2, generation = 3})
	ray, ray_ok := editor_pick_ray(&list, {500, 350}, viewport)
	testing.expect(t, ray_ok)
	hit, hit_found := scene_raycast_nearest(&list, &registry, ray)
	testing.expect(t, hit_found)
	testing.expect_value(t, hit.entity, shared.Entity{index = 2, generation = 3})
	testing.expect(t, math.abs(hit.position.z - 2.5) < 0.001)
	testing.expect(t, math.abs(hit.distance - 3.5) < 0.001)
	testing.expect(t, math.abs(hit.normal.z) > 0.999)
	placement, placement_found := editor_model_placement_position(
		&list,
		&registry,
		{},
		{500, 350},
		viewport,
		0.5,
	)
	testing.expect(t, placement_found)
	testing.expect_value(t, placement.position, shared.Vec3{0, 0, 2.5})
	testing.expect_value(t, placement.contact, shared.Vec3{0, 0, 2.5})
	_, found = editor_pick_entity(&list, &registry, {105, 55}, viewport)
	testing.expect(t, !found)
}

@(test)
test_scene_ray_plane_intersection_rejects_parallel_and_behind_hits :: proc(t: ^testing.T) {
	position, found := scene_ray_plane_intersection(
		Pick_Ray{origin = {1, 4, 2}, direction = {0, -1, 0}},
		{},
		{0, 1, 0},
	)
	testing.expect(t, found)
	testing.expect_value(t, position, shared.Vec3{1, 0, 2})
	_, found = scene_ray_plane_intersection(
		Pick_Ray{origin = {1, 4, 2}, direction = {1, 0, 0}},
		{},
		{0, 1, 0},
	)
	testing.expect(t, !found)
	_, found = scene_ray_plane_intersection(
		Pick_Ray{origin = {1, 4, 2}, direction = {0, 1, 0}},
		{},
		{0, 1, 0},
	)
	testing.expect(t, !found)
}

@(test)
test_model_support_projection_places_the_lowest_bound_on_the_hit_surface :: proc(t: ^testing.T) {
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	desc, desc_err := resources.cube()
	testing.expect(t, desc_err == "")
	defer delete(desc.vertices)
	defer delete(desc.indices)
	geometry, geometry_err := resources.register_geometry(&registry, "support-cube", desc)
	testing.expect(t, geometry_err == "")
	resource, parsed := shared.resource_uuid_parse("a7000000-0000-4000-8000-000000000041")
	testing.expect(t, parsed)
	mesh: resources.Model_Mesh
	append(&mesh.primitives, resources.Model_Primitive{geometry = geometry})
	model := resources.Model {
		id = resource,
		authored = true,
		generation = 1,
		alive = true,
	}
	append(&model.meshes, mesh)
	append(
		&model.nodes,
		resources.Model_Node {
			mesh_index = 0,
			parent_index = -1,
			transform = {position = {2, 1, 4}, scale = {1, 1, 1}},
		},
	)
	append(&registry.models, model)
	support, center, found := editor_model_support_projection(&registry, resource, {0, 1, 0})
	testing.expect(t, found)
	testing.expect(t, math.abs(support - 0.5) < 0.0001)
	testing.expect_value(t, center, shared.Vec3{2, 1, 4})
}

@(test)
test_editor_pick_ray_uses_camera_rotation :: proc(t: ^testing.T) {
	list := shared.Render_List {
		has_camera = true,
		camera = {
			transform = {position = {0, 0, 6}, rotation = {0, math.PI / 2, 0}},
			camera = {fov = 60},
		},
	}
	ray, ok := editor_pick_ray(&list, {400, 300}, ui.Rect{0, 0, 800, 600})
	testing.expect(t, ok)
	testing.expect(t, ray.direction.x > 0.999)
	testing.expect(t, math.abs(ray.direction.z) < 0.001)
}

@(test)
test_editor_pick_ray_tracks_live_viewport_aspect :: proc(t: ^testing.T) {
	list := shared.Render_List {
		has_camera = true,
		camera = {transform = {position = {0, 0, 6}}, camera = {fov = 60}},
	}
	ray, ok := editor_pick_ray(&list, {900, 300}, ui.Rect{0, 0, 1000, 600})
	testing.expect(t, ok)
	testing.expect(t, ray.direction.x > 0)
	testing.expect(t, ray.direction.z < 0)
	center, _ := editor_pick_ray(&list, {500, 300}, ui.Rect{0, 0, 1000, 600})
	testing.expect(t, center.direction.x == 0)
}
