package ecs

import project "../project"
import resources "../resources"
import shared "../shared"
import "core:strings"
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
	reconcile_render_instances(&world, &registry)
	testing.expect(t, world.entities[0].render_instance_index >= 0)
	testing.expect(t, world.render_structure_sync_count == 2)
	remove_material(&world, 0)
	reconcile_render_instances(&world, &registry)
	testing.expect(t, world.entities[0].render_instance_index == -1)
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
	delete(world.entities[0].name)
	world.entities[0].name, _ = strings.clone("Renamed Label")
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
	testing.expect(t, spawn_command_name(&destination.commands[0].spawn) == "First")
	testing.expect(t, spawn_command_name(&destination.commands[1].spawn) == "Second")
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
	}

	entity_index := spawn_entity(&world, &spawn)
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
