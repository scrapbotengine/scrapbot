package ecs

import project "../project"
import resources "../resources"
import shared "../shared"
import "core:fmt"
import "core:slice"
import "core:testing"

MULTI_CUBE_SCENE :: `[[entities]]
id = "a2000000-0000-4000-8000-000000000001"
name = "Main Camera"

[entities.transform]
position = [0, 2, 6]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.camera]
fov = 60
near = 0.1
far = 100

[[entities]]
id = "a2000000-0000-4000-8000-000000000002"
name = "Left Cube"

[entities.transform]
position = [-1.25, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.mesh]
primitive = "cube"

[entities.components.autorotate]
velocity = [0, 1.5707963, 0]

[[entities]]
id = "a2000000-0000-4000-8000-000000000003"
name = "Right Cube"

[entities.transform]
position = [1.25, 0, 0]
rotation = [0, 0, 0]
scale = [1, 1, 1]

[entities.mesh]
primitive = "cube"

[entities.components.autorotate]
velocity = [0, -1.5707963, 0]
`

@(test)
test_render_reconciliation_tracks_geometry_and_material_eligibility :: proc(t: ^testing.T) {
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	cube_desc, _ := resources.cube()
	defer delete(cube_desc.vertices); defer delete(cube_desc.indices)
	geometry, geometry_err := resources.register_geometry(&registry, "cube", cube_desc)
	material, material_err := resources.register_material(
		&registry,
		"white",
		{base_color = {1, 1, 1, 1}},
	)
	testing.expect(t, geometry_err == "" && material_err == "")

	world: World
	defer destroy_world(&world)
	append(
		&world.entities,
		World_Entity {
			id = {0, 1},
			alive = true,
			transform_index = 0,
			camera_index = -1,
			mesh_index = -1,
			geometry_index = -1,
			material_index = -1,
			render_instance_index = -1,
		},
	)
	append_soa(&world.transforms, Transform_Component{scale = {1, 1, 1}})
	add_geometry(&world, 0, geometry)
	reconcile_render_instances(&world, &registry)
	testing.expect(t, world.entities[0].render_instance_index == -1)
	testing.expect(t, world.render_structure_sync_count == 1)
	reconcile_render_instances(&world, &registry)
	testing.expect(t, world.render_structure_sync_count == 1)

	add_material(&world, 0, material)
	list: Render_List
	defer destroy_render_list(&list)
	populate_resource_render_list(&world, &registry, &list)
	testing.expect(t, world.entities[0].render_instance_index >= 0)
	testing.expect(t, len(list.instances) == 1)
	testing.expect(t, list.topology_revision == world.render_topology_revision)
	testing.expect(t, world.render_structure_sync_count == 2)
	remove_material(&world, 0)
	reconcile_render_instances(&world, &registry)
	testing.expect(t, world.entities[0].render_instance_index == -1)
}

@(test)
test_resource_render_list_updates_only_dirty_entities_and_removes_slots_incrementally :: proc(
	t: ^testing.T,
) {
	scene, result := project.parse_scene(MULTI_CUBE_SCENE)
	defer project.destroy_scene(&scene)
	testing.expect(t, result.err == .None)
	world := build_world(&scene)
	defer destroy_world(&world)
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	cube_desc, _ := resources.cube()
	defer delete(cube_desc.vertices)
	defer delete(cube_desc.indices)
	_, geometry_err := resources.register_geometry(&registry, "cube", cube_desc)
	_, material_err := resources.register_material(
		&registry,
		"default",
		{base_color = {1, 1, 1, 1}},
	)
	testing.expect(t, geometry_err == "" && material_err == "")

	list: Render_List
	defer destroy_render_list(&list)
	populate_resource_render_list(&world, &registry, &list)
	testing.expect_value(t, len(list.instances), 2)
	testing.expect(t, list.full_instance_sync)
	initial_visits := list.instance_visit_count
	initial_structure_syncs := world.render_structure_sync_count
	populate_resource_render_list(&world, &registry, &list)
	testing.expect(t, !list.full_instance_sync)
	testing.expect_value(t, list.instance_visit_count, initial_visits)
	testing.expect_value(t, len(list.dirty_instance_slots), 0)
	testing.expect_value(t, len(list.dirty_transform_slots), 0)

	left_index := 1
	left_transform := world.entities[left_index].transform_index
	world.transforms[left_transform].position.x = -9
	mark_render_transform_dirty(&world, left_index)
	populate_resource_render_list(&world, &registry, &list)
	testing.expect_value(t, world.render_structure_sync_count, initial_structure_syncs)
	testing.expect_value(t, list.instance_visit_count, initial_visits + 1)
	list_index := list.instance_index_by_entity[left_index]
	testing.expect(t, list_index >= 0 && list_index < len(list.instances))
	testing.expect_value(t, list.instances[list_index].transform.position.x, f32(-9))
	testing.expect_value(t, len(list.dirty_instance_slots), 0)
	testing.expect_value(t, len(list.dirty_transform_slots), 1)

	world.transforms[left_transform].position.x = -10
	mark_render_transform_dirty(&world, left_index)
	mark_render_entity_dirty(&world, left_index)
	populate_resource_render_list(&world, &registry, &list)
	testing.expect_value(t, list.instances[list_index].transform.position.x, f32(-10))
	testing.expect_value(t, len(list.dirty_instance_slots), 1)
	testing.expect_value(t, len(list.dirty_transform_slots), 0)

	topology_revision := world.render_topology_revision
	right_index := 2
	right_slot := world.entities[right_index].render_instance_index
	despawn_entity(&world, right_index, world.entities[right_index].id.generation)
	populate_resource_render_list(&world, &registry, &list)
	testing.expect_value(t, world.render_topology_revision, topology_revision)
	testing.expect_value(t, len(list.instances), 1)
	testing.expect_value(t, list.instance_index_by_slot[right_slot], INVALID_COMPONENT_INDEX)
	testing.expect(t, slice.contains(list.dirty_instance_slots[:], right_slot))
}

@(test)
test_resource_render_list_updates_renderable_descendants_of_dirty_transforms :: proc(
	t: ^testing.T,
) {
	parent_id, _ := shared.entity_uuid_parse("a2100000-0000-4000-8000-000000000001")
	child_id, _ := shared.entity_uuid_parse("a2100000-0000-4000-8000-000000000002")
	unrelated_id, _ := shared.entity_uuid_parse("a2100000-0000-4000-8000-000000000003")
	second_parent_id, _ := shared.entity_uuid_parse("a2100000-0000-4000-8000-000000000004")
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = parent_id,
			name = "Parent",
			has_transform = true,
			transform = {position = {2, 0, 0}, scale = {1, 1, 1}},
		},
		shared.Scene_Entity {
			id = child_id,
			name = "Child",
			has_transform = true,
			transform = {parent = parent_id, position = {1, 0, 0}, scale = {1, 1, 1}},
			has_mesh = true,
			mesh = {primitive = "cube"},
		},
		shared.Scene_Entity {
			id = unrelated_id,
			name = "Unrelated",
			has_transform = true,
			transform = {position = {8, 0, 0}, scale = {1, 1, 1}},
			has_mesh = true,
			mesh = {primitive = "cube"},
		},
		shared.Scene_Entity {
			id = second_parent_id,
			name = "Second Parent",
			has_transform = true,
			transform = {position = {10, 0, 0}, scale = {1, 1, 1}},
		},
	)
	world := build_world(&scene)
	defer destroy_world(&world)
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	cube_desc, _ := resources.cube()
	defer delete(cube_desc.vertices)
	defer delete(cube_desc.indices)
	_, geometry_err := resources.register_geometry(&registry, "cube", cube_desc)
	_, material_err := resources.register_material(
		&registry,
		"default",
		{base_color = {1, 1, 1, 1}},
	)
	testing.expect(t, geometry_err == "" && material_err == "")

	list: Render_List
	defer destroy_render_list(&list)
	populate_resource_render_list(&world, &registry, &list)
	testing.expect_value(t, len(list.instances), 2)
	initial_visits := list.instance_visit_count
	initial_structure_syncs := world.render_structure_sync_count
	world.transforms[world.entities[0].transform_index].position.x = 5
	mark_render_transform_dirty(&world, 0)
	populate_resource_render_list(&world, &registry, &list)
	testing.expect_value(t, world.render_structure_sync_count, initial_structure_syncs)
	testing.expect_value(t, list.instance_visit_count, initial_visits + 2)
	child_list_index := list.instance_index_by_entity[1]
	testing.expect(t, child_list_index >= 0 && child_list_index < len(list.instances))
	testing.expect_value(t, list.instances[child_list_index].transform.position.x, f32(6))
	testing.expect_value(t, len(list.dirty_instance_slots), 0)
	testing.expect_value(t, len(list.dirty_transform_slots), 1)

	testing.expect(t, set_transform_parent(&world, 1, second_parent_id, true))
	populate_resource_render_list(&world, &registry, &list)
	visits_after_reparent := list.instance_visit_count
	structure_syncs_after_reparent := world.render_structure_sync_count
	world.transforms[world.entities[3].transform_index].position.x = 12
	mark_render_transform_dirty(&world, 3)
	populate_resource_render_list(&world, &registry, &list)
	testing.expect_value(t, world.render_structure_sync_count, structure_syncs_after_reparent)
	testing.expect_value(t, list.instance_visit_count, visits_after_reparent + 2)
	child_list_index = list.instance_index_by_entity[1]
	testing.expect_value(t, list.instances[child_list_index].transform.position.x, f32(8))
}

@(test)
test_render_batches_group_shared_geometry_and_material :: proc(t: ^testing.T) {
	g := shared.Geometry_Handle {
		1,
		1,
	}; a := shared.Material_Handle{1, 1}; b := shared.Material_Handle{2, 1}
	list: Render_List; defer destroy_render_list(&list)
	append(&list.instances, Render_Instance{geometry = {handle = g}, material = {handle = a}})
	append(&list.instances, Render_Instance{geometry = {handle = g}, material = {handle = a}})
	append(&list.instances, Render_Instance{geometry = {handle = g}, material = {handle = b}})
	testing.expect(t, render_batch_count(&list) == 2)
}

@(test)
test_scene_order_allocation_is_monotonic_across_reused_entity_slots :: proc(t: ^testing.T) {
	scene: shared.Scene
	defer delete(scene.entities)
	append(&scene.entities, shared.Scene_Entity{name = "One"})
	append(&scene.entities, shared.Scene_Entity{name = "Two"})
	world := build_world(&scene)
	defer destroy_world(&world)
	first_runtime, created := create_world_entity(&world, "Runtime A", {}, .Runtime)
	testing.expect(t, created)
	testing.expect_value(t, world.entities[first_runtime].scene_order, 2)
	despawn_entity(&world, first_runtime, world.entities[first_runtime].id.generation)
	second_runtime, reused := create_world_entity(&world, "Runtime B", {}, .Runtime, true)
	testing.expect(t, reused)
	testing.expect_value(t, second_runtime, first_runtime)
	testing.expect_value(t, world.entities[second_runtime].scene_order, 3)
	testing.expect_value(t, next_scene_order_index(&world), 4)
}

@(test)
test_render_list_extracts_ambient_directional_and_point_lights :: proc(t: ^testing.T) {
	scene, result := project.parse_scene(
		`[[entities]]
id = "a2000000-0000-4000-8000-000000000004"
name = "Ambient"
[entities.ambient_light]
color = [0.2, 0.4, 0.6]
intensity = 0.5

[[entities]]
id = "a2000000-0000-4000-8000-000000000005"
name = "Sun"
[entities.directional_light]
direction = [0, -1, 0]
color = [1, 0.9, 0.8]
intensity = 1.5

[[entities]]
id = "a2000000-0000-4000-8000-000000000006"
name = "Lamp"
[entities.transform]
position = [2, 3, 4]
rotation = [0, 0, 0]
scale = [1, 1, 1]
[entities.point_light]
color = [0.1, 0.2, 1]
intensity = 12
range = 7
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, result.err == .None)

	world := build_world(&scene)
	defer destroy_world(&world)
	testing.expect(t, len(world.render_active_ambient_light_entities) == 1)
	testing.expect(t, len(world.render_active_directional_light_entities) == 1)
	testing.expect(t, len(world.render_active_point_light_entities) == 1)
	list: Render_List
	extract_lights(&world, &list)

	testing.expect(t, list.ambient == shared.Vec3{0.1, 0.2, 0.3})
	testing.expect(t, list.directional_light_count == 1)
	testing.expect(t, list.directional_lights[0].light.direction == shared.Vec3{0, -1, 0})
	testing.expect(t, list.directional_lights[0].light.intensity == 1.5)
	testing.expect(t, list.point_light_count == 1)
	testing.expect(t, list.point_lights[0].position == shared.Vec3{2, 3, 4})
	testing.expect(t, list.point_lights[0].light.range == 7)
}

@(test)
test_render_watch_membership_tracks_transform_changes_and_despawns :: proc(t: ^testing.T) {
	scene, result := project.parse_scene(
		`[[entities]]
id = "a2000000-0000-4000-8000-000000000021"
name = "Camera"
[entities.transform]
position = [0, 0, 5]
rotation = [0, 0, 0]
scale = [1, 1, 1]
[entities.camera]
fov = 60
near = 0.1
far = 100

[[entities]]
id = "a2000000-0000-4000-8000-000000000022"
name = "First Light"
[entities.transform]
position = [1, 2, 3]
rotation = [0, 0, 0]
scale = [1, 1, 1]
[entities.point_light]
color = [1, 0, 0]
intensity = 2
range = 5

[[entities]]
id = "a2000000-0000-4000-8000-000000000023"
name = "Second Light"
[entities.transform]
position = [4, 5, 6]
rotation = [0, 0, 0]
scale = [1, 1, 1]
[entities.point_light]
color = [0, 1, 0]
intensity = 3
range = 6
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, result.err == .None)

	world := build_world(&scene)
	defer destroy_world(&world)
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	reconcile_render_instances(&world, &registry)

	testing.expect(t, len(world.render_active_camera_entities) == 1)
	testing.expect(t, len(world.render_active_point_light_entities) == 2)
	remove_transform(&world, 2)
	reconcile_render_instances(&world, &registry)
	testing.expect(t, len(world.render_active_point_light_entities) == 1)
	testing.expect(t, world.entities[2].render_point_light_active_index == -1)

	add_transform(&world, 2, Transform_Component{position = {7, 8, 9}, scale = {1, 1, 1}})
	reconcile_render_instances(&world, &registry)
	testing.expect(t, len(world.render_active_point_light_entities) == 2)

	despawn_entity(&world, 1, world.entities[1].id.generation)
	testing.expect(t, len(world.render_active_point_light_entities) == 1)
	testing.expect(t, world.render_active_point_light_entities[0] == 2)
	testing.expect(t, world.entities[2].render_point_light_active_index == 0)

	remove_transform(&world, 0)
	reconcile_render_instances(&world, &registry)
	testing.expect(t, len(world.render_active_camera_entities) == 0)
	_, camera_ok := first_camera_instance(&world)
	testing.expect(t, !camera_ok)
}

@(test)
test_deferred_render_components_drive_reconciliation :: proc(t: ^testing.T) {
	registry: resources.Registry; defer resources.destroy_registry(&registry)
	desc, _ := resources.cube(); defer delete(desc.vertices); defer delete(desc.indices)
	geometry, _ := resources.register_geometry(
		&registry,
		"cube",
		desc,
	); material, _ := resources.register_material(&registry, "white", {base_color = {1, 1, 1, 1}})
	world: World; defer destroy_world(&world)
	append(
		&world.entities,
		World_Entity {
			id = {0, 1},
			alive = true,
			transform_index = 0,
			camera_index = -1,
			mesh_index = -1,
			geometry_index = -1,
			material_index = -1,
			render_instance_index = -1,
		},
	)
	append_soa(&world.transforms, Transform_Component{scale = {1, 1, 1}})
	commands: Command_Buffer; init_command_buffer(&commands); defer destroy_command_buffer(&commands)
	testing.expect(
		t,
		queue_add_geometry(&commands, 0, 1, geometry) == "",
	); testing.expect(t, queue_add_material(&commands, 0, 1, material) == "")
	apply_commands(
		&world,
		&commands,
	); reconcile_render_instances(&world, &registry); testing.expect(t, world.entities[0].render_instance_index >= 0)
	queue_remove_component(
		&commands,
		0,
		1,
		0,
		"scrapbot.material",
	); apply_commands(&world, &commands); reconcile_render_instances(&world, &registry)
	testing.expect(t, world.entities[0].render_instance_index < 0)
}

@(test)
test_scene_builds_world_with_soa_transforms :: proc(t: ^testing.T) {
	scene, result := project.parse_scene(project.default_scene_template())
	defer project.destroy_scene(&scene)

	testing.expect(t, result.err == .None)
	testing.expect(t, len(scene.entities) == 2)

	world := build_world(&scene)
	defer destroy_world(&world)

	testing.expect(t, len(world.entities) == 2)
	testing.expect(t, len(world.transforms) == 2)
	testing.expect(t, len(world.cameras) == 1)
	testing.expect(t, len(world.meshes) == 1)
	testing.expect(t, len(world.renderables) == 1)
	testing.expect(t, len(world.custom_components) == 1)
	testing.expect(t, world.entities[0].camera_index == 0)
	testing.expect(t, world.entities[1].transform_index == 1)
	testing.expect(t, world.entities[1].mesh_index == 0)
	testing.expect(t, world.renderables[0].entity_index == 1)
	testing.expect(t, world.custom_components[0].name == "autorotate")
	testing.expect(t, len(world.custom_components[0].components) == 1)
	testing.expect(t, world.custom_components[0].components[0].entity_index == 1)
	testing.expect(t, world.transforms[1].position == shared.Vec3{0, 0, 0})
}

@(test)
test_render_list_includes_multiple_cube_renderables :: proc(t: ^testing.T) {
	scene, result := project.parse_scene(MULTI_CUBE_SCENE)
	defer project.destroy_scene(&scene)

	testing.expect(t, result.err == .None)
	testing.expect(t, len(scene.entities) == 3)

	world := build_world(&scene)
	defer destroy_world(&world)

	testing.expect(t, len(world.entities) == 3)
	testing.expect(t, len(world.transforms) == 3)
	testing.expect(t, len(world.meshes) == 2)
	testing.expect(t, len(world.renderables) == 2)
	testing.expect(t, len(world.custom_components) == 1)
	testing.expect(t, len(world.custom_components[0].components) == 2)

	render_list := build_render_list(&world)
	defer destroy_render_list(&render_list)

	testing.expect(t, render_list.has_camera)
	testing.expect(t, len(render_list.instances) == 2)
	testing.expect(t, render_list.instances[0].entity.name == "Left Cube")
	testing.expect(t, render_list.instances[1].entity.name == "Right Cube")
}

@(test)
test_world_transform_hierarchy_resolves_and_reparents_without_moving_world_pose :: proc(
	t: ^testing.T,
) {
	parent_id, _ := shared.entity_uuid_parse("94000000-0000-4000-8000-000000000001")
	child_id, _ := shared.entity_uuid_parse("94000000-0000-4000-8000-000000000002")
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = parent_id,
			name = "Parent",
			has_transform = true,
			transform = {position = {2, 0, 0}, rotation = {0, 0, 0}, scale = {2, 2, 2}},
		},
		shared.Scene_Entity {
			id = child_id,
			name = "Child",
			has_transform = true,
			transform = {parent = parent_id, position = {1, 0, 0}, scale = {1, 1, 1}},
		},
	)
	world := build_world(&scene)
	defer destroy_world(&world)
	begin_world_transform_resolution(&world)
	child_world, valid := resolve_world_transform(&world, 1)
	testing.expect(t, valid)
	testing.expect_value(t, child_world.position, shared.Vec3{4, 0, 0})
	testing.expect_value(t, child_world.scale, shared.Vec3{2, 2, 2})
	testing.expect(t, !set_transform_parent(&world, 0, child_id, true))
	testing.expect(t, set_transform_parent(&world, 1, {}, true))
	begin_world_transform_resolution(&world)
	unparented: shared.Transform_Component
	unparented, valid = resolve_world_transform(&world, 1)
	testing.expect(t, valid)
	testing.expect_value(t, unparented.position, child_world.position)
	testing.expect_value(t, unparented.scale, child_world.scale)
}

@(test)
test_world_preserves_project_custom_components :: proc(t: ^testing.T) {
	scene, result := project.parse_scene(MULTI_CUBE_SCENE)
	defer project.destroy_scene(&scene)

	testing.expect(t, result.err == .None)

	world := build_world(&scene)
	defer destroy_world(&world)

	testing.expect(t, len(world.custom_components) == 1)
	testing.expect(t, world.custom_components[0].name == "autorotate")
	testing.expect(t, len(world.custom_components[0].components) == 2)
	testing.expect(t, world.custom_components[0].components[0].entity_index == 1)
	testing.expect(t, len(world.custom_components[0].components[0].vec3_fields) == 1)
	testing.expect(t, world.custom_components[0].components[0].vec3_fields[0].name == "velocity")
	testing.expect(t, world.custom_components[0].components[0].vec3_fields[0].value.y > 0)
	testing.expect(t, world.custom_components[0].components[1].entity_index == 2)
	testing.expect(t, world.custom_components[0].components[1].vec3_fields[0].value.y < 0)

	camera, camera_ok := first_camera_instance(&world)
	testing.expect(t, camera_ok)
	testing.expect(t, camera.camera.fov == 60)
}

@(test)
test_query_view_iterates_one_component_storage_group :: proc(t: ^testing.T) {
	scene, result := project.parse_scene(MULTI_CUBE_SCENE)
	defer project.destroy_scene(&scene)
	testing.expect(t, result.err == .None)

	world := build_world(&scene)
	defer destroy_world(&world)

	view := query_view(&world, shared.INVALID_COMPONENT_ID, "autorotate")
	testing.expect(t, query_view_count(&world, view) == 2)

	component, ok := query_view_component_at(&world, view, 0)
	testing.expect(t, ok)
	testing.expect(t, component.entity_index == 1)
	testing.expect(t, component.vec3_fields[0].value.y > 0)

	remove_custom_component(&world, 1, shared.INVALID_COMPONENT_ID, "autorotate")
	testing.expect(t, query_view_count(&world, view) == 1)

	component, ok = query_view_component_at(&world, view, 0)
	testing.expect(t, ok)
	testing.expect(t, component.entity_index == 2)
}

@(test)
test_query_matches_entities_with_all_requested_components :: proc(t: ^testing.T) {
	scene, result := project.parse_scene(MULTI_CUBE_SCENE)
	defer project.destroy_scene(&scene)
	testing.expect(t, result.err == .None)

	world := build_world(&scene)
	defer destroy_world(&world)

	query: Query
	query.terms[0] = Query_Term {
		name = "scrapbot.transform",
	}
	query.terms[1] = Query_Term {
		component_id = shared.INVALID_COMPONENT_ID,
		name = "autorotate",
	}
	query.term_count = 2

	testing.expect(t, query_count(&world, query) == 2)
	next_entity_index := 0
	first_match, first_found := query_next(&world, query, &next_entity_index)
	second_match, second_found := query_next(&world, query, &next_entity_index)
	exhausted_cursor := next_entity_index
	_, exhausted := query_next(&world, query, &next_entity_index)
	testing.expect(t, first_found && first_match == 1)
	testing.expect(t, second_found && second_match == 2)
	testing.expect(t, !exhausted && next_entity_index == exhausted_cursor)

	entity_index, ok := query_entity_at(&world, query, 0)
	testing.expect(t, ok)
	testing.expect(t, world.entities[entity_index].name == "Left Cube")

	remove_transform(&world, 1)
	testing.expect(t, query_count(&world, query) == 1)

	entity_index, ok = query_entity_at(&world, query, 0)
	testing.expect(t, ok)
	testing.expect(t, world.entities[entity_index].name == "Right Cube")

	world.entities[2].alive = false
	testing.expect(t, query_count(&world, query) == 0)
}

@(test)
test_query_cursor_uses_the_smallest_custom_component_storage :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)
	for index in 0 ..< 128 {
		_, created := create_world_entity(&world, "Candidate")
		testing.expect(t, created)
	}
	dense := ensure_custom_component_storage(&world, 1, "dense")
	sparse := ensure_custom_component_storage(&world, 2, "sparse")
	for entity_index in 0 ..< 128 {
		value := shared.Custom_Component {
			name = "dense",
		}
		add_scene_custom_component(&world, entity_index, value)
	}
	sparse_entities := [?]int{3, 97}
	for entity_index in 0 ..< 128 {
		value := shared.Custom_Component {
			name = "sparse",
		}
		add_scene_custom_component(&world, entity_index, value)
	}
	bind_custom_component_storage(&world, "dense", 1)
	bind_custom_component_storage(&world, "sparse", 2)
	for entity_index in 0 ..< 128 {
		if entity_index == sparse_entities[0] || entity_index == sparse_entities[1] {
			continue
		}
		remove_custom_component(&world, entity_index, 2, "sparse")
	}
	testing.expect(t, dense.storage_index != sparse.storage_index)
	testing.expect(t, len(dense.components) == len(sparse.components))
	testing.expect(t, len(sparse.active_component_indices) == len(sparse_entities))
	query: Query
	query.terms[0] = {
		component_id = 1,
		name = "dense",
	}
	query.terms[1] = {
		component_id = 2,
		name = "sparse",
	}
	query.term_count = 2
	cursor := 0
	first, first_ok := query_next(&world, query, &cursor)
	second, second_ok := query_next(&world, query, &cursor)
	_, exhausted := query_next(&world, query, &cursor)
	testing.expect(t, first_ok && second_ok)
	testing.expect(
		t,
		(first == sparse_entities[0] && second == sparse_entities[1]) ||
		(first == sparse_entities[1] && second == sparse_entities[0]),
	)
	testing.expect(t, !exhausted)
	testing.expect(t, world.query_candidate_visit_count == 2)
}

@(test)
test_compiled_query_retains_storage_plan_across_membership_changes :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)
	for index in 0 ..< 96 {
		_, created := create_world_entity(&world, "Candidate")
		testing.expect(t, created)
		add_scene_custom_component(&world, index, shared.Custom_Component{name = "dense"})
	}
	sparse_entities := [?]int{7, 63}
	for entity_index in sparse_entities {
		add_scene_custom_component(&world, entity_index, shared.Custom_Component{name = "sparse"})
	}
	bind_custom_component_storage(&world, "dense", 1)
	bind_custom_component_storage(&world, "sparse", 2)
	query: Query
	query.terms[0] = {
		component_id = 1,
		name = "dense",
	}
	query.terms[1] = {
		component_id = 2,
		name = "sparse",
	}
	query.term_count = 2
	compiled := compile_query(&world, query)
	testing.expect(t, compiled.anchor_storage_index >= 0)

	cursor := 0
	first, first_ok := compiled_query_next(&world, compiled, &cursor)
	second, second_ok := compiled_query_next(&world, compiled, &cursor)
	_, exhausted := compiled_query_next(&world, compiled, &cursor)
	testing.expect(t, first_ok && second_ok && !exhausted)
	testing.expect(t, first == 7 && second == 63)
	testing.expect(t, world.query_candidate_visit_count == 2)

	remove_custom_component(&world, 7, 2, "sparse")
	add_scene_custom_component(&world, 91, shared.Custom_Component{name = "sparse"})
	bind_custom_component_storage(&world, "sparse", 2)
	cursor = 0
	first, first_ok = compiled_query_next(&world, compiled, &cursor)
	second, second_ok = compiled_query_next(&world, compiled, &cursor)
	_, exhausted = compiled_query_next(&world, compiled, &cursor)
	testing.expect(t, first_ok && second_ok && !exhausted)
	testing.expect(t, first == 63 && second == 91)
}

@(test)
test_despawn_releases_only_custom_storages_owned_by_the_entity :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)
	target, created := create_world_entity(&world, "Target")
	testing.expect(t, created)
	for storage_index in 0 ..< 64 {
		name := fmt.tprintf("component_%d", storage_index)
		_ = ensure_custom_component_storage(&world, shared.Component_ID(storage_index + 1), name)
	}
	owned_storages := [?]int{7, 41}
	for storage_index in owned_storages {
		storage := &world.custom_components[storage_index]
		add_scene_custom_component(&world, target, shared.Custom_Component{name = storage.name})
	}
	despawn_entity(&world, target, world.entities[target].id.generation)
	testing.expect(t, world.custom_teardown_storage_visit_count == 2)
	failure, valid := validate_world_integrity(&world)
	testing.expectf(t, valid, "%s", format_world_integrity_failure(failure))
}

@(test)
test_deferred_commands_spawn_entities_when_applied :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)

	commands: Command_Buffer
	init_command_buffer(&commands)
	defer destroy_command_buffer(&commands)
	err := queue_spawn(&commands, "Spawned")
	testing.expect(t, err == "")
	testing.expect(t, alive_entity_count(&world) == 0)

	apply_err := apply_commands(&world, &commands)
	testing.expect(t, apply_err == "")
	testing.expect(t, commands.command_count == 0)
	testing.expect(t, alive_entity_count(&world) == 1)
	testing.expect(t, world.entities[0].name == "Spawned")
	testing.expect(t, world.entities[0].origin == .Runtime)
	testing.expect(t, world.entities[0].camera_index == INVALID_COMPONENT_INDEX)
	testing.expect(t, world.entities[0].ambient_light_index == INVALID_COMPONENT_INDEX)
	testing.expect(t, world.entities[0].directional_light_index == INVALID_COMPONENT_INDEX)
	testing.expect(t, world.entities[0].point_light_index == INVALID_COMPONENT_INDEX)
	testing.expect(t, world.entities[0].geometry_index == INVALID_COMPONENT_INDEX)
	testing.expect(t, world.entities[0].material_index == INVALID_COMPONENT_INDEX)
	testing.expect(t, world.entities[0].render_instance_index == INVALID_COMPONENT_INDEX)
	testing.expect(t, world.entities[0].uuid != (shared.Entity_UUID{}))
	entity_index, found := entity_index_by_uuid(&world, world.entities[0].uuid)
	testing.expect(t, found && entity_index == 0)
}

@(test)
test_scene_entity_uuid_is_stable_and_independent_from_name :: proc(t: ^testing.T) {
	id, id_ok := shared.entity_uuid_parse("a2000000-0000-4000-8000-000000000020")
	testing.expect(t, id_ok)
	scene := Scene{}
	defer delete(scene.entities)
	append(&scene.entities, shared.Scene_Entity{id = id, name = "Original Label"})
	world := build_world(&scene)
	defer destroy_world(&world)

	testing.expect(t, world.entities[0].uuid == id)
	entity_index, found := entity_index_by_uuid(&world, id)
	testing.expect(t, found && entity_index == 0)
	delete_world_string(&world, world.entities[0].name)
	world.entities[0].name = clone_world_string(&world, "Renamed Label")
	entity_index, found = entity_index_by_uuid(&world, id)
	testing.expect(t, found && entity_index == 0)
}

@(test)
test_scene_and_runtime_entities_keep_distinct_origins :: proc(t: ^testing.T) {
	scene :=
		Scene{}; defer delete(scene.entities); append(&scene.entities, shared.Scene_Entity{name = "Authored"})
	world := build_world(&scene); defer destroy_world(&world)
	testing.expect(t, world.entities[0].origin == .Scene)
	commands: Command_Buffer; init_command_buffer(&commands); defer destroy_command_buffer(&commands)
	testing.expect(
		t,
		queue_spawn(&commands, "Live") == "",
	); testing.expect(t, apply_commands(&world, &commands) == "")
	testing.expect(t, world.entities[1].origin == .Runtime)
}

@(test)
test_shadow_markers_participate_in_queries_and_deferred_commands :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)
	commands: Command_Buffer
	init_command_buffer(&commands)
	defer destroy_command_buffer(&commands)

	spawn: Spawn_Command
	testing.expect(t, init_spawn_command(&spawn, "Shadowed") == "")
	testing.expect(t, spawn_set_marker(&spawn, "scrapbot.shadow_caster") == "")
	testing.expect(t, queue_spawn_command(&commands, spawn) == "")
	testing.expect(t, apply_commands(&world, &commands) == "")
	testing.expect(t, entity_has_component(&world, 0, 0, "scrapbot.shadow_caster"))
	testing.expect(t, !entity_has_component(&world, 0, 0, "scrapbot.shadow_receiver"))

	testing.expect(t, queue_add_marker(&commands, 0, 1, "scrapbot.shadow_receiver") == "")
	testing.expect(t, apply_commands(&world, &commands) == "")
	testing.expect(t, entity_has_component(&world, 0, 0, "scrapbot.shadow_receiver"))
	testing.expect(t, queue_remove_component(&commands, 0, 1, 0, "scrapbot.shadow_caster") == "")
	testing.expect(t, apply_commands(&world, &commands) == "")
	testing.expect(t, !entity_has_component(&world, 0, 0, "scrapbot.shadow_caster"))
}

@(test)
test_deferred_command_buffers_merge_in_source_order :: proc(t: ^testing.T) {
	destination, source: Command_Buffer
	init_command_buffer(&destination)
	defer destroy_command_buffer(&destination)
	init_command_buffer(&source)
	defer destroy_command_buffer(&source)

	testing.expect(t, queue_spawn(&destination, "First") == "")
	testing.expect(t, queue_spawn(&source, "Second") == "")
	testing.expect(t, append_commands(&destination, &source) == "")
	testing.expect(t, destination.command_count == 2)
	testing.expect(t, source.command_count == 0)
	first := &destination.spawns[destination.commands[0].payload_index]
	second := &destination.spawns[destination.commands[1].payload_index]
	testing.expect(t, queued_spawn_command_name(first) == "First")
	testing.expect(t, queued_spawn_command_name(second) == "Second")
}

@(test)
test_deferred_command_buffers_grow_beyond_the_initial_capacity :: proc(t: ^testing.T) {
	commands: Command_Buffer
	init_command_buffer_capacity(&commands, 1)
	defer destroy_command_buffer(&commands)

	command_count := DEFAULT_COMMAND_CAPACITY * 4
	for index in 0 ..< command_count {
		testing.expectf(
			t,
			queue_spawn(&commands, "Deferred") == "",
			"command %d should fit",
			index,
		)
	}
	testing.expect(t, commands.command_count == command_count)
	testing.expect(t, len(commands.commands) == command_count)
	testing.expect(t, len(commands.spawns) == command_count)
	testing.expect(t, len(commands.despawns) == 0)
}

@(test)
test_deferred_command_buffers_store_only_the_queued_payload_kind :: proc(t: ^testing.T) {
	commands: Command_Buffer
	init_command_buffer_capacity(&commands, 1)
	defer destroy_command_buffer(&commands)

	command_count := DEFAULT_COMMAND_CAPACITY * 4
	for index in 0 ..< command_count {
		testing.expect(t, queue_despawn(&commands, index, 1) == "")
	}

	testing.expect(t, len(commands.commands) == command_count)
	testing.expect(t, len(commands.despawns) == command_count)
	testing.expect(t, len(commands.spawns) == 0)
	testing.expect(t, len(commands.spawn_components) == 0)
	testing.expect(t, len(commands.spawn_ui_components) == 0)
	testing.expect(t, len(commands.add_components) == 0)
	testing.expect(t, len(commands.remove_components) == 0)
	testing.expect(t, size_of(Command_Header) <= 16)
	testing.expect(t, size_of(Despawn_Command) <= 16)
	testing.expect(t, size_of(Queued_Spawn_Command) < size_of(Spawn_Command))
}

@(test)
test_deferred_spawn_storage_pools_only_present_components :: proc(t: ^testing.T) {
	commands: Command_Buffer
	init_command_buffer_capacity(&commands, 1)
	defer destroy_command_buffer(&commands)

	first_component, second_component: Command_Component
	testing.expect(t, init_command_component(&first_component, 1, "first") == "")
	testing.expect(t, init_command_component(&second_component, 2, "second") == "")
	spawn: Spawn_Command
	testing.expect(t, init_spawn_command(&spawn, "Pooled") == "")
	testing.expect(t, spawn_add_custom_component(&spawn, first_component) == "")
	testing.expect(t, spawn_add_custom_component(&spawn, second_component) == "")
	testing.expect(t, queue_spawn_command(&commands, spawn) == "")

	testing.expect(t, len(commands.spawns) == 1)
	testing.expect(t, len(commands.spawn_components) == 2)
	testing.expect(t, len(commands.spawn_ui_components) == 0)
	testing.expect(t, commands.spawns[0].custom_component_start == 0)
	testing.expect(t, commands.spawns[0].custom_component_count == 2)
	testing.expect(t, command_component_name(&commands.spawn_components[0]) == "first")
	testing.expect(t, command_component_name(&commands.spawn_components[1]) == "second")
}

@(test)
test_deferred_command_buffers_merge_beyond_the_initial_capacity :: proc(t: ^testing.T) {
	destination, source: Command_Buffer
	init_command_buffer_capacity(&destination, 1)
	defer destroy_command_buffer(&destination)
	init_command_buffer_capacity(&source, 1)
	defer destroy_command_buffer(&source)

	commands_per_buffer := DEFAULT_COMMAND_CAPACITY
	for index in 0 ..< commands_per_buffer {
		testing.expect(t, queue_spawn(&destination, "Destination") == "")
		testing.expect(t, queue_spawn(&source, "Source") == "")
	}

	testing.expect(t, append_commands(&destination, &source) == "")
	testing.expect(t, destination.command_count == commands_per_buffer * 2)
	testing.expect(t, source.command_count == 0)
	testing.expect(t, len(destination.commands) == commands_per_buffer * 2)
	testing.expect(t, len(destination.spawns) == commands_per_buffer * 2)
	first_source_index := destination.commands[commands_per_buffer].payload_index
	first_source := &destination.spawns[first_source_index]
	testing.expect(t, queued_spawn_command_name(first_source) == "Source")
}

@(test)
test_deferred_command_merge_remaps_spawn_component_ranges :: proc(t: ^testing.T) {
	destination, source: Command_Buffer
	init_command_buffer_capacity(&destination, 1)
	defer destroy_command_buffer(&destination)
	init_command_buffer_capacity(&source, 1)
	defer destroy_command_buffer(&source)

	first, second, third: Command_Component
	testing.expect(t, init_command_component(&first, 1, "first") == "")
	testing.expect(t, init_command_component(&second, 2, "second") == "")
	testing.expect(t, init_command_component(&third, 3, "third") == "")
	destination_spawn, source_spawn: Spawn_Command
	testing.expect(t, init_spawn_command(&destination_spawn, "Destination") == "")
	testing.expect(t, spawn_add_custom_component(&destination_spawn, first) == "")
	testing.expect(t, queue_spawn_command(&destination, destination_spawn) == "")
	testing.expect(t, init_spawn_command(&source_spawn, "Source") == "")
	testing.expect(t, spawn_add_custom_component(&source_spawn, second) == "")
	testing.expect(t, spawn_add_custom_component(&source_spawn, third) == "")
	testing.expect(t, queue_spawn_command(&source, source_spawn) == "")

	testing.expect(t, append_commands(&destination, &source) == "")
	testing.expect(t, len(destination.spawn_components) == 3)
	merged_spawn := &destination.spawns[1]
	testing.expect(t, merged_spawn.custom_component_start == 1)
	testing.expect(t, merged_spawn.custom_component_count == 2)
	testing.expect(t, command_component_name(&destination.spawn_components[1]) == "second")
	testing.expect(t, command_component_name(&destination.spawn_components[2]) == "third")
}

@(test)
test_deferred_commands_despawn_entities_without_shifting_indices :: proc(t: ^testing.T) {
	scene, result := project.parse_scene(MULTI_CUBE_SCENE)
	defer project.destroy_scene(&scene)
	testing.expect(t, result.err == .None)

	world := build_world(&scene)
	defer destroy_world(&world)

	commands: Command_Buffer
	init_command_buffer(&commands)
	defer destroy_command_buffer(&commands)
	err := queue_despawn(&commands, 1, world.entities[1].id.generation)
	testing.expect(t, err == "")
	testing.expect(t, alive_entity_count(&world) == 3)
	testing.expect(t, render_frame_from_world(&world).renderable_count == 2)

	apply_err := apply_commands(&world, &commands)
	testing.expect(t, apply_err == "")
	testing.expect(t, alive_entity_count(&world) == 2)
	testing.expect(t, !entity_is_alive(&world, 1))
	testing.expect(t, world.entities[2].id.index == 2)
	testing.expect(t, render_frame_from_world(&world).renderable_count == 1)
}

@(test)
test_runtime_entity_churn_reuses_generation_safe_storage :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)

	component: Command_Component
	testing.expect(t, init_command_component(&component, 7, "lifetime") == "")
	testing.expect(t, command_component_add_vec3(&component, "remaining", {0, 2, 0}) == "")
	spawn: Spawn_Command
	testing.expect(t, init_spawn_command(&spawn, "Transient") == "")
	testing.expect(t, spawn_set_transform(&spawn, {scale = {1, 1, 1}}) == "")
	testing.expect(t, spawn_set_geometry(&spawn, {index = 3, generation = 1}) == "")
	testing.expect(t, spawn_set_material(&spawn, {index = 4, generation = 1}) == "")
	testing.expect(t, spawn_add_custom_component(&spawn, component) == "")

	first_id: Entity
	first_uuid: shared.Entity_UUID
	for cycle in 0 ..< 1000 {
		entity_index := spawn_entity(&world, &spawn)
		testing.expect(t, entity_index == 0)
		if cycle == 0 {
			first_id = world.entities[entity_index].id
			first_uuid = world.entities[entity_index].uuid
		}
		testing.expect(
			t,
			entity_is_current(&world, entity_index, world.entities[entity_index].id.generation),
		)
		despawn_entity(&world, entity_index, world.entities[entity_index].id.generation)
		testing.expect(t, !entity_is_alive(&world, entity_index))
		testing.expect(t, len(world.free_entity_indices) == 1)
	}

	entity_index := spawn_entity(&world, &spawn)
	testing.expect(t, len(world.free_entity_indices) == 0)
	testing.expect(t, len(world.entities) == 1)
	testing.expect(t, len(world.transforms) == 1)
	testing.expect(t, len(world.geometries) == 1)
	testing.expect(t, len(world.materials) == 1)
	testing.expect(t, len(world.custom_components) == 1)
	testing.expect(t, len(world.custom_components[0].components) == 1)
	testing.expect(t, query_view_count(&world, query_view(&world, 7, "lifetime")) == 1)
	testing.expect(t, !entity_is_current(&world, int(first_id.index), first_id.generation))
	testing.expect(t, world.entities[entity_index].id.generation != first_id.generation)
	testing.expect(t, world.entities[entity_index].uuid != first_uuid)
	_, old_uuid_found := entity_index_by_uuid(&world, first_uuid)
	testing.expect(t, !old_uuid_found)
	current_index, current_uuid_found := entity_index_by_uuid(
		&world,
		world.entities[entity_index].uuid,
	)
	testing.expect(t, current_uuid_found && current_index == entity_index)
	stats := world_storage_stats(&world)
	testing.expect(t, stats.live_entities == 1)
	testing.expect(t, stats.entity_slots == 1)
	testing.expect(t, stats.transform_slots == 1)
	testing.expect(t, stats.geometry_slots == 1)
	testing.expect(t, stats.material_slots == 1)
	testing.expect(t, stats.custom_component_slots == 1)
	testing.expect(t, stats.total_component_slots == 4)
}

@(test)
test_mixed_runtime_archetypes_share_released_component_slots :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)

	renderable_spawn: Spawn_Command
	testing.expect(t, init_spawn_command(&renderable_spawn, "Renderable") == "")
	testing.expect(t, spawn_set_transform(&renderable_spawn, {scale = {1, 1, 1}}) == "")
	testing.expect(t, spawn_set_mesh(&renderable_spawn, "cube") == "")
	testing.expect(t, spawn_set_geometry(&renderable_spawn, {index = 3, generation = 1}) == "")
	testing.expect(t, spawn_set_material(&renderable_spawn, {index = 4, generation = 1}) == "")
	empty_spawn: Spawn_Command
	testing.expect(t, init_spawn_command(&empty_spawn, "Empty") == "")

	for _ in 0 ..< 1000 {
		index := spawn_entity(&world, &renderable_spawn)
		despawn_entity(&world, index, world.entities[index].id.generation)
		index = spawn_entity(&world, &empty_spawn)
		despawn_entity(&world, index, world.entities[index].id.generation)
	}

	index := spawn_entity(&world, &renderable_spawn)
	stats := world_storage_stats(&world)
	testing.expect(t, index == 0)
	testing.expect(t, stats.entity_slots == 1)
	testing.expect(t, stats.transform_slots == 1)
	testing.expect(t, stats.mesh_slots == 1)
	testing.expect(t, stats.geometry_slots == 1)
	testing.expect(t, stats.material_slots == 1)
	testing.expect(t, stats.renderable_slots == 1)
}

@(test)
test_builtin_component_add_remove_churn_reuses_storage :: proc(t: ^testing.T) {
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	desc, _ := resources.cube()
	defer delete(desc.vertices)
	defer delete(desc.indices)
	geometry, geometry_err := resources.register_geometry(&registry, "cube", desc)
	material, material_err := resources.register_material(
		&registry,
		"white",
		{base_color = {1, 1, 1, 1}},
	)
	testing.expect(t, geometry_err == "" && material_err == "")

	world: World
	defer destroy_world(&world)
	append(
		&world.entities,
		World_Entity {
			id = {index = 0, generation = 1},
			alive = true,
			transform_index = INVALID_COMPONENT_INDEX,
			camera_index = INVALID_COMPONENT_INDEX,
			mesh_index = INVALID_COMPONENT_INDEX,
			geometry_index = INVALID_COMPONENT_INDEX,
			material_index = INVALID_COMPONENT_INDEX,
			render_instance_index = INVALID_COMPONENT_INDEX,
		},
	)

	for _ in 0 ..< 1000 {
		add_transform(&world, 0, {scale = {1, 1, 1}})
		add_mesh(&world, 0, "cube")
		add_mesh(&world, 0, "replacement")
		add_geometry(&world, 0, geometry)
		add_material(&world, 0, material)
		reconcile_render_instances(&world, &registry)
		remove_mesh(&world, 0)
		remove_transform(&world, 0)
		remove_geometry(&world, 0)
		remove_material(&world, 0)
	}

	stats := world_storage_stats(&world)
	testing.expect(t, stats.transform_slots == 1)
	testing.expect(t, stats.mesh_slots == 1)
	testing.expect(t, stats.geometry_slots == 1)
	testing.expect(t, stats.material_slots == 1)
	testing.expect(t, stats.render_instance_slots == 1)
	testing.expect(t, stats.renderable_slots == 1)
}
