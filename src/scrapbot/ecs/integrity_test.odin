package ecs

import resources "../resources"
import shared "../shared"
import "core:testing"

integrity_test_world :: proc() -> (World, resources.Registry, shared.Material_Handle) {
	material_resource := "a5000000-0000-4000-8000-000000000001"
	material_id, _ := shared.resource_uuid_parse(material_resource)
	registry: resources.Registry
	resources.init_registry(&registry)
	handle, _ := resources.register_project_material(
		&registry,
		material_id,
		"Integrity Material",
		"integrity.resource.toml",
		{base_color = {0.2, 0.3, 0.4, 1}},
	)
	root_id := shared.entity_uuid_from_engine_name("integrity-root")
	scene: shared.Scene
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = root_id,
			name = "Root",
			has_transform = true,
			transform = {scale = {1, 1, 1}},
			has_camera = true,
			camera = {fov = 60, near = 0.1, far = 100},
			has_ambient_light = true,
			ambient_light = {color = {0.1, 0.1, 0.1}, intensity = 1},
			has_directional_light = true,
			directional_light = {direction = {0, -1, 0}, color = {1, 1, 1}, intensity = 1},
			has_point_light = true,
			point_light = {color = {1, 0, 0}, intensity = 2, range = 5},
			has_material = true,
			material_resource = material_resource,
			has_ui_layout = true,
			ui_layout = {size = {100, 100}},
		},
	)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = shared.entity_uuid_from_engine_name("integrity-child"),
			name = "Child",
			has_ui_layout = true,
			ui_layout = {parent = root_id, size = {20, 20}},
		},
	)
	world := build_world(&scene)
	delete(scene.entities)
	resolve_material_reference(&world, 0, handle)
	return world, registry, handle
}

expect_world_integrity_failure :: proc(
	t: ^testing.T,
	world: ^World,
	registry: ^resources.Registry,
	code: World_Integrity_Code,
) {
	failure, ok := validate_world_integrity(world, registry)
	testing.expectf(t, !ok, "expected %s integrity failure, got success", code)
	if !ok {
		testing.expect_value(t, failure.code, code)
	}
}

@(test)
test_world_integrity_accepts_consistent_world :: proc(t: ^testing.T) {
	world, registry, _ := integrity_test_world()
	defer destroy_world(&world)
	defer resources.destroy_registry(&registry)
	failure, ok := validate_world_integrity(&world, &registry)
	testing.expectf(t, ok, "%s", format_world_integrity_failure(failure))
}

@(test)
test_world_integrity_accepts_fully_despawned_world :: proc(t: ^testing.T) {
	world, registry, _ := integrity_test_world()
	defer destroy_world(&world)
	defer resources.destroy_registry(&registry)
	world.entities[0].editor_transform_gizmo_index = len(world.editor_transform_gizmos)
	append(
		&world.editor_transform_gizmos,
		shared.Editor_Transform_Gizmo_Component{entity_index = 0},
	)
	world.entities[0].editor_ui_index = len(world.editor_uis)
	append(&world.editor_uis, shared.Editor_UI_Component{entity_index = 0})
	testing.expect(t, delete_entity_by_uuid(&world, world.entities[1].uuid))
	testing.expect(t, delete_entity_by_uuid(&world, world.entities[0].uuid))
	failure, ok := validate_world_integrity(&world, &registry)
	testing.expectf(t, ok, "%s", format_world_integrity_failure(failure))
}

@(test)
test_reused_entity_slot_coalesces_pending_dirty_notifications :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)
	entity_index, created := create_world_entity(&world, "First")
	testing.expect(t, created)
	mark_render_entity_dirty(&world, entity_index)
	mark_ui_entity_dirty(&world, entity_index)
	despawn_entity(&world, entity_index, world.entities[entity_index].id.generation)
	reused_index, reused := create_world_entity(&world, "Second")
	testing.expect(t, reused)
	testing.expect_value(t, reused_index, entity_index)
	mark_render_entity_dirty(&world, reused_index)
	mark_ui_entity_dirty(&world, reused_index)
	testing.expect_value(t, len(world.render_dirty_entities), 1)
	testing.expect_value(t, len(world.ui_dirty_entities), 1)
	testing.expect(t, world.entities[reused_index].render_dirty)
	testing.expect(t, world.entities[reused_index].ui_dirty)
	failure, ok := validate_world_integrity(&world)
	testing.expectf(t, ok, "%s", format_world_integrity_failure(failure))
}

@(test)
test_world_integrity_rejects_a_stale_dirty_queue_entry :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)
	entity_index, created := create_world_entity(&world, "Dirty")
	testing.expect(t, created)
	mark_render_entity_dirty(&world, entity_index)
	world.entities[entity_index].render_dirty = false
	expect_world_integrity_failure(t, &world, nil, .Dirty_Queue)
}

@(test)
test_world_integrity_reports_entity_and_component_corruption :: proc(t: ^testing.T) {
	world, registry, _ := integrity_test_world()
	defer destroy_world(&world)
	defer resources.destroy_registry(&registry)

	world.entities[0].transform_index = len(world.transforms)
	expect_world_integrity_failure(t, &world, &registry, .Component_Index)
	world.entities[0].transform_index = 0

	world.entities[1].transform_index = 0
	expect_world_integrity_failure(t, &world, &registry, .Component_Aliasing)
	world.entities[1].transform_index = INVALID_COMPONENT_INDEX

	append(&world.free_transform_indices, 0)
	expect_world_integrity_failure(t, &world, &registry, .Free_Slot)
	clear(&world.free_transform_indices)

	delete_key(&world.entity_by_uuid, world.entities[0].uuid)
	expect_world_integrity_failure(t, &world, &registry, .Entity_UUID_Map)
	world.entity_by_uuid[world.entities[0].uuid] = 0
}

@(test)
test_world_integrity_reports_active_hierarchy_and_resource_corruption :: proc(t: ^testing.T) {
	world, registry, handle := integrity_test_world()
	defer destroy_world(&world)
	defer resources.destroy_registry(&registry)

	for &entity in world.entities {
		entity.render_dirty = false
	}
	clear(&world.render_dirty_entities)
	world.entities[0].render_active_index = 0
	append(&world.render_active_entities, 0)
	expect_world_integrity_failure(t, &world, &registry, .Active_Set)
	world.entities[0].render_active_index = INVALID_COMPONENT_INDEX
	clear(&world.render_active_entities)

	world.ui_layouts[world.entities[1].ui_layout_index].parent =
		shared.entity_uuid_from_engine_name("missing-ui-parent")
	expect_world_integrity_failure(t, &world, &registry, .UI_Hierarchy)
	world.ui_layouts[world.entities[1].ui_layout_index].parent = world.entities[0].uuid

	second_id, _ := shared.resource_uuid_parse("a5000000-0000-4000-8000-000000000002")
	second_handle, _ := resources.register_project_material(
		&registry,
		second_id,
		"Wrong Material",
		"wrong.resource.toml",
		{base_color = {1, 0, 0, 1}},
	)
	world.materials[world.entities[0].material_index].handle = second_handle
	expect_world_integrity_failure(t, &world, &registry, .Resource_Reference)
	world.materials[world.entities[0].material_index].handle = handle
}
