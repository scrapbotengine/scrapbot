package scrapbot

import component "./component"
import ecs "./ecs"
import resources "./resources"
import script "./script"
import shared "./shared"
import ui "./ui"

import "core:fmt"
import "core:testing"

lifecycle_next_random :: proc(seed: ^u64) -> u64 {
	value := seed^
	value ~= value << 13
	value ~= value >> 7
	value ~= value << 17
	seed^ = value
	return value
}

lifecycle_scene_entity :: proc(world: ^shared.World, ordinal: int) -> (int, bool) {
	count := 0
	for entity, entity_index in world.entities {
		if !entity.alive || entity.origin != .Scene {
			continue
		}
		if count == ordinal {
			return entity_index, true
		}
		count += 1
	}
	return -1, false
}

lifecycle_scene_entity_count :: proc(world: ^shared.World) -> int {
	count := 0
	for entity in world.entities {
		if entity.alive && entity.origin == .Scene {
			count += 1
		}
	}
	return count
}

expect_lifecycle_world_integrity :: proc(
	t: ^testing.T,
	world: ^shared.World,
	registry: ^resources.Registry,
	seed: u64,
	step, operation: int,
) {
	failure, ok := ecs.validate_world_integrity(world, registry)
	testing.expectf(
		t,
		ok,
		"lifecycle seed=%x step=%d operation=%d: %s",
		seed,
		step,
		operation,
		ecs.format_world_integrity_failure(failure),
	)
}

@(test)
test_playback_baseline_restores_authored_entities_and_discards_runtime_state :: proc(
	t: ^testing.T,
) {
	scene: shared.Scene
	defer delete(scene.entities)
	authored_uuid := shared.entity_uuid_from_engine_name("playback-authored")
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = authored_uuid,
			name = "Authored",
			has_transform = true,
			transform = {position = {1, 2, 3}, scale = {1, 1, 1}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	geometry := shared.Geometry_Handle {
		index = 4,
		generation = 2,
	}
	material := shared.Material_Handle {
		index = 7,
		generation = 3,
	}
	ecs.add_geometry(&world, 0, geometry)
	ecs.add_material(&world, 0, material)
	world.entities[0].component_revision = 7
	runtime: script.Runtime
	runtime.world = &world
	runtime.system_count = 3
	baseline: Playback_Baseline
	defer destroy_playback_baseline(&baseline)
	testing.expect(t, capture_playback_baseline(&baseline, &world) == "")

	world.transforms[0].position = {99, 98, 97}
	_ = ecs.set_entity_name(&world, 0, "Runtime Mutation")
	_, spawned := ecs.create_world_entity(&world, "Runtime Spawn", {}, .Runtime)
	testing.expect(t, spawned)
	world.time.frame_index = 42
	testing.expect(t, restore_playback_baseline(&baseline, &runtime, &world) == "")

	testing.expect(t, runtime.world == &world)
	testing.expect(t, runtime.system_count == 3)
	testing.expect(t, world.time.frame_index == 0)
	testing.expect(t, len(world.entities) == 1)
	entity_index, found := ecs.entity_index_by_uuid(&world, authored_uuid)
	testing.expect(t, found)
	if found {
		testing.expect(t, world.entities[entity_index].name == "Authored")
		testing.expect(t, world.entities[entity_index].origin == .Scene)
		testing.expect(t, world.entities[entity_index].component_revision == 7)
		testing.expect(t, world.entities[entity_index].geometry_index >= 0)
		testing.expect(t, world.entities[entity_index].material_index >= 0)
		testing.expect(
			t,
			world.geometries[world.entities[entity_index].geometry_index].handle == geometry,
		)
		testing.expect(
			t,
			world.materials[world.entities[entity_index].material_index].handle == material,
		)
		transform_index := world.entities[entity_index].transform_index
		testing.expect(t, world.transforms[transform_index].position == shared.Vec3{1, 2, 3})
	}
}

@(test)
test_playback_stop_preserves_the_working_editor_camera :: proc(t: ^testing.T) {
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = shared.entity_uuid_from_engine_name("playback-camera-scene-entity"),
			name = "Scene Entity",
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	runtime: script.Runtime
	runtime.world = &world
	baseline: Playback_Baseline
	defer destroy_playback_baseline(&baseline)
	testing.expect(t, capture_playback_baseline(&baseline, &world) == "")

	position := shared.Vec3{17, 8, -11}
	rotation := shared.Vec3{-0.35, 1.2, 0}
	testing.expect(t, ecs.set_editor_scene_camera_pose(&world, position, rotation))
	before_index, before_component, before_found := ecs.editor_scene_camera_entity(&world)
	testing.expect(t, before_found)
	if !before_found {
		return
	}
	before_entity := world.entities[before_index]
	before_component.orbit_target = {-4, 3, 9}
	before_component.orbit_distance = 27
	world.cameras[before_entity.camera_index].fov = 63
	before_transform := world.transforms[before_entity.transform_index]
	before_camera := world.cameras[before_entity.camera_index]
	before_orbit_target := before_component.orbit_target
	before_orbit_distance := before_component.orbit_distance

	_, spawned := ecs.create_world_entity(&world, "Disposable Runtime", {}, .Runtime)
	testing.expect(t, spawned)
	testing.expect(t, restore_playback_baseline(&baseline, &runtime, &world) == "")

	after_index, after_component, after_found := ecs.editor_scene_camera_entity(&world)
	testing.expect(t, after_found)
	if !after_found {
		return
	}
	after_entity := world.entities[after_index]
	testing.expect_value(t, world.transforms[after_entity.transform_index], before_transform)
	testing.expect_value(t, world.cameras[after_entity.camera_index], before_camera)
	testing.expect_value(t, after_component.orbit_target, before_orbit_target)
	testing.expect_value(t, after_component.orbit_distance, before_orbit_distance)
	testing.expect(t, after_entity.origin == .Editor)
	testing.expect(t, len(world.entities) == 2)
}

@(test)
test_playback_baseline_restores_runtime_material_edits :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	runtime: script.Runtime
	runtime.world = &world
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	resource_id, valid := shared.resource_uuid_parse("a4000000-0000-4000-8000-000000000001")
	testing.expect(t, valid)
	handle, register_err := resources.register_project_material(
		&registry,
		resource_id,
		"Playback Material",
		"playback.resource.toml",
		{
			base_color = {0.2, 0.3, 0.4, 1},
			emissive = {1, 2, 3},
			metallic_factor = 0.25,
			roughness_factor = 0.75,
		},
	)
	testing.expect(t, register_err == "")
	baseline: Playback_Baseline
	defer destroy_playback_baseline(&baseline)
	testing.expect(t, capture_playback_baseline(&baseline, &world, &registry) == "")
	material, alive := resources.get_material(&registry, handle)
	testing.expect(t, alive)
	material.desc.base_color = {0.9, 0.8, 0.7, 0.6}
	material.desc.emissive = {8, 7, 6}
	material.desc.metallic_factor = 1
	material.desc.roughness_factor = 0.1
	material.version += 1
	mutated_version := material.version
	testing.expect(t, restore_playback_baseline(&baseline, &runtime, &world, &registry) == "")
	material, alive = resources.get_material(&registry, handle)
	testing.expect(t, alive)
	if alive {
		testing.expect_value(t, material.desc.base_color, resources.Vec4{0.2, 0.3, 0.4, 1})
		testing.expect_value(t, material.desc.emissive, shared.Vec3{1, 2, 3})
		testing.expect_value(t, material.desc.metallic_factor, f32(0.25))
		testing.expect_value(t, material.desc.roughness_factor, f32(0.75))
		testing.expect_value(t, material.version, mutated_version + 1)
	}
}

@(test)
test_playback_cycles_preserve_authored_render_resource_references :: proc(t: ^testing.T) {
	material_resource := "a4000000-0000-4000-8000-000000000002"
	geometry_resource := "icosphere"
	resource_id, valid := shared.resource_uuid_parse(material_resource)
	testing.expect(t, valid)
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	handle, register_err := resources.register_project_material(
		&registry,
		resource_id,
		"Cycled Material",
		"cycled.resource.toml",
		{base_color = {0.2, 0.3, 0.4, 1}},
	)
	testing.expect(t, register_err == "")
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = shared.entity_uuid_from_engine_name("playback-resource-cycle"),
			name = "Authored Resource Entity",
			has_geometry = true,
			geometry = {resource = geometry_resource},
			has_material = true,
			material_resource = material_resource,
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	geometry_desc, geometry_err := resources.cube(1)
	defer delete(geometry_desc.vertices)
	defer delete(geometry_desc.indices)
	testing.expect(t, geometry_err == "")
	geometry_handle, register_geometry_err := resources.register_geometry(
		&registry,
		geometry_resource,
		geometry_desc,
	)
	testing.expect(t, register_geometry_err == "")
	ecs.resolve_geometry_reference(&world, 0, geometry_handle)
	ecs.resolve_material_reference(&world, 0, handle)
	runtime: script.Runtime
	runtime.world = &world
	baseline: Playback_Baseline
	defer destroy_playback_baseline(&baseline)
	testing.expect(t, capture_playback_baseline(&baseline, &world, &registry) == "")

	for _ in 0 ..< 4 {
		testing.expect(t, restore_playback_baseline(&baseline, &runtime, &world, &registry) == "")
		testing.expect_value(t, world.entities[0].geometry_resource, geometry_resource)
		testing.expect(t, world.entities[0].geometry_index >= 0)
		if world.entities[0].geometry_index >= 0 {
			testing.expect_value(
				t,
				world.geometries[world.entities[0].geometry_index].handle,
				geometry_handle,
			)
		}
		testing.expect_value(t, world.entities[0].material_resource, material_resource)
		testing.expect(t, world.entities[0].material_index >= 0)
		if world.entities[0].material_index >= 0 {
			testing.expect_value(
				t,
				world.materials[world.entities[0].material_index].handle,
				handle,
			)
		}
		testing.expect(t, capture_playback_baseline(&baseline, &world, &registry) == "")
	}
}

@(test)
test_seeded_editor_lifecycle_preserves_world_integrity :: proc(t: ^testing.T) {
	first_resource := "a6000000-0000-4000-8000-000000000001"
	second_resource := "a6000000-0000-4000-8000-000000000002"
	first_id, first_valid := shared.resource_uuid_parse(first_resource)
	second_id, second_valid := shared.resource_uuid_parse(second_resource)
	testing.expect(t, first_valid && second_valid)
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	first_handle, first_err := resources.register_project_material(
		&registry,
		first_id,
		"Lifecycle One",
		"lifecycle-one.resource.toml",
		{base_color = {0.2, 0.3, 0.4, 1}},
	)
	_, second_err := resources.register_project_material(
		&registry,
		second_id,
		"Lifecycle Two",
		"lifecycle-two.resource.toml",
		{base_color = {0.8, 0.7, 0.6, 1}},
	)
	testing.expect(t, first_err == "" && second_err == "")
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = shared.entity_uuid_from_engine_name("lifecycle-anchor"),
			name = "Lifecycle Anchor",
			has_transform = true,
			transform = {scale = {1, 1, 1}},
			has_material = true,
			material_resource = first_resource,
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	ecs.resolve_material_reference(&world, 0, first_handle)
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	state.resource_registry = &registry
	component_registry: component.Registry
	component.init_registry(&component_registry)
	state.component_registry = &component_registry
	transform_definition, transform_found := component.find_definition(
		&component_registry,
		"scrapbot.transform",
	)
	point_light_definition, point_light_found := component.find_definition(
		&component_registry,
		"scrapbot.point_light",
	)
	ui_layout_definition, ui_layout_found := component.find_definition(
		&component_registry,
		"scrapbot.ui_layout",
	)
	testing.expect(t, transform_found && point_light_found && ui_layout_found)
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	runtime: script.Runtime
	runtime.world = &world

	initial_seed := u64(0x5c4a_9b71_d203_e8f6)
	seed := initial_seed
	for step in 0 ..< 600 {
		operation := int(lifecycle_next_random(&seed) % 12)
		scene_count := lifecycle_scene_entity_count(&world)
		target := -1
		if scene_count > 0 {
			ordinal := int(lifecycle_next_random(&seed) % u64(scene_count))
			target, _ = lifecycle_scene_entity(&world, ordinal)
		}
		switch operation {
			case 0:
				if scene_count < 24 {
					_, _ = ui.editor_authoring_create_entity(state, &world)
				}
			case 1:
				if target >= 0 && scene_count < 24 {
					_, _ = ui.editor_authoring_duplicate_entity(state, &world, target)
				}
			case 2:
				if target >= 0 && scene_count > 1 {
					_ = ui.editor_authoring_delete_entity(state, &world, target)
				}
			case 3:
				if target >= 0 {
					_ = ui.editor_authoring_rename_entity(
						state,
						&world,
						target,
						fmt.tprintf("Entity %03d", step),
					)
				}
			case 4:
				if target >= 0 {
					present := world.entities[target].transform_index >= 0
					_ = ui.editor_authoring_set_registered_component(
						state,
						&world,
						target,
						&transform_definition,
						!present,
					)
				}
			case 5:
				if target >= 0 {
					present := world.entities[target].point_light_index >= 0
					_ = ui.editor_authoring_set_registered_component(
						state,
						&world,
						target,
						&point_light_definition,
						!present,
					)
				}
			case 6:
				_ = ui.editor_history_apply(state, &world, false)
			case 7:
				_ = ui.editor_history_apply(state, &world, true)
			case 8:
				baseline: Playback_Baseline
				if capture_playback_baseline(&baseline, &world, &registry) == "" {
					ui.editor_play(state)
					_ = ui.consume_playback_begin_request(state)
					_, _ = ecs.create_world_entity(&world, "Disposable Runtime", {}, .Runtime)
					ui.editor_stop(state)
					selected_uuid, had_selection := ui.editor_selected_uuid(state, &world)
					restore_err := restore_playback_baseline(
						&baseline,
						&runtime,
						&world,
						&registry,
					)
					testing.expectf(
						t,
						restore_err == "",
						"lifecycle seed=%x step=%d restore: %s",
						initial_seed,
						step,
						restore_err,
					)
					ui.editor_world_restored(state, &world, selected_uuid, had_selection)
				}
				destroy_playback_baseline(&baseline)
			case 9:
				if scene_count < 24 {
					runtime_index, created := ecs.create_world_entity(
						&world,
						"Promoted Runtime",
						{},
						.Runtime,
					)
					if created {
						ecs.add_transform(&world, runtime_index, {scale = {1, 1, 1}})
						_ = ui.editor_authoring_promote_entity(state, &world, runtime_index)
					}
				}
			case 10:
				if target >= 0 {
					resource_id := first_id
					if lifecycle_next_random(&seed) & 1 == 1 {
						resource_id = second_id
					}
					_ = ui.editor_authoring_set_material_resource(
						state,
						&world,
						target,
						resource_id,
					)
				}
			case 11:
				if target >= 0 {
					present := world.entities[target].ui_layout_index >= 0
					_ = ui.editor_authoring_set_registered_component(
						state,
						&world,
						target,
						&ui_layout_definition,
						!present,
					)
				}
		}
		ecs.reconcile_render_instances(&world, &registry)
		expect_lifecycle_world_integrity(t, &world, &registry, initial_seed, step, operation)
		if state.editor_has_selection {
			selected := int(state.editor_selected_entity.index)
			testing.expectf(
				t,
				ecs.entity_is_current(&world, selected, state.editor_selected_entity.generation),
				"lifecycle seed=%x step=%d retains a stale selection",
				initial_seed,
				step,
			)
		}
	}
}

@(test)
test_created_entity_survives_play_stop_and_remains_undoable :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	_, disposable_before_play := ecs.create_world_entity(&world, "Existing Runtime", {}, .Runtime)
	testing.expect(t, disposable_before_play)
	created, ok := ui.editor_authoring_create_entity(state, &world)
	testing.expect(t, ok)
	if !ok {
		return
	}
	created_index := int(created.index)
	created_uuid := world.entities[created_index].uuid
	baseline: Playback_Baseline
	defer destroy_playback_baseline(&baseline)
	testing.expect(t, capture_playback_baseline(&baseline, &world) == "")

	ui.editor_play(state)
	testing.expect(t, ui.consume_playback_begin_request(state))
	world.transforms[world.entities[created_index].transform_index].position.x = 25
	_, spawned := ecs.create_world_entity(&world, "Disposable Runtime", {}, .Runtime)
	testing.expect(t, spawned)
	ui.editor_stop(state)
	selected_uuid, had_selection := ui.editor_selected_uuid(state, &world)
	runtime: script.Runtime
	runtime.world = &world
	testing.expect(t, restore_playback_baseline(&baseline, &runtime, &world) == "")
	ui.editor_world_restored(state, &world, selected_uuid, had_selection)

	restored_index, found := ecs.entity_index_by_uuid(&world, created_uuid)
	testing.expect(t, found)
	if found {
		transform_index := world.entities[restored_index].transform_index
		testing.expect(t, world.transforms[transform_index].position.x == 0)
	}
	testing.expect(t, len(world.entities) == 1)
	testing.expect(t, state.editor_scene_dirty)
	testing.expect(t, state.editor_history_count == 1)
	testing.expect(t, state.editor_has_selection)
	if found {
		testing.expect(t, state.editor_selected_entity == world.entities[restored_index].id)
		testing.expect(t, state.editor_selected_entity.index != created.index)
	}
	testing.expect(t, ui.editor_history_apply(state, &world, false))
	_, found = ecs.entity_index_by_uuid(&world, created_uuid)
	testing.expect(t, !found)
}

@(test)
test_stop_discards_live_component_membership_changes :: proc(t: ^testing.T) {
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = shared.entity_uuid_from_engine_name("live-component-target"),
			name = "Live Component Target",
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: component.Registry
	component.init_registry(&registry)
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	state.component_registry = &registry
	state.editor_simulation_stopped = true
	baseline: Playback_Baseline
	defer destroy_playback_baseline(&baseline)
	testing.expect(t, capture_playback_baseline(&baseline, &world) == "")

	ui.editor_play(state)
	testing.expect(t, ui.consume_playback_begin_request(state))
	camera_index, found := component.find_definition_index(&registry, "scrapbot.camera")
	testing.expect(t, found)
	if !found {
		return
	}
	testing.expect(
		t,
		ui.editor_set_registered_component(
			state,
			&world,
			0,
			&registry.definitions[camera_index],
			true,
		),
	)
	testing.expect(t, world.entities[0].camera_index >= 0)
	testing.expect(t, !state.editor_scene_dirty)
	testing.expect(t, state.editor_history_count == 0)

	ui.editor_stop(state)
	runtime: script.Runtime
	runtime.world = &world
	testing.expect(t, restore_playback_baseline(&baseline, &runtime, &world) == "")
	ui.editor_world_restored(state, &world, {}, false)
	testing.expect(t, world.entities[0].camera_index < 0)
	testing.expect(t, !state.editor_scene_dirty)
	testing.expect(t, state.editor_history_count == 0)
	failure, integrity_ok := ecs.validate_world_integrity(&world)
	testing.expectf(t, integrity_ok, "%s", ecs.format_world_integrity_failure(failure))
}

@(test)
test_stop_applies_staged_authored_component_edits_as_one_transaction :: proc(t: ^testing.T) {
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = shared.entity_uuid_from_engine_name("keep-play-transform"),
			name = "Keep Play Transform",
			has_transform = true,
			transform = {scale = {1, 1, 1}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: component.Registry
	component.init_registry(&registry)
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	state.component_registry = &registry
	state.editor_simulation_stopped = true
	baseline: Playback_Baseline
	defer destroy_playback_baseline(&baseline)
	testing.expect(t, capture_playback_baseline(&baseline, &world) == "")

	ui.editor_play(state)
	testing.expect(t, ui.consume_playback_begin_request(state))
	transform_index := world.entities[0].transform_index
	world.transforms[transform_index].position.x = 7
	ui.editor_history_push_transform(
		state,
		&world,
		0,
		.Transform_Position,
		{},
		world.transforms[transform_index].position,
	)
	testing.expect(t, len(state.editor_play_changes) == 1)
	testing.expect(t, state.editor_history_count == 0)

	ui.editor_stop(state)
	testing.expect(t, ui.consume_playback_stop_request(state))
	runtime: script.Runtime
	runtime.world = &world
	testing.expect(t, restore_playback_baseline(&baseline, &runtime, &world) == "")
	ui.editor_world_restored(state, &world)
	testing.expect(t, ui.editor_apply_play_changes(state, &world))

	transform_index = world.entities[0].transform_index
	testing.expect(t, world.transforms[transform_index].position.x == 7)
	testing.expect(t, len(state.editor_play_changes) == 0)
	testing.expect(t, state.editor_history_count == 1)
	testing.expect(t, state.editor_scene_dirty)
	testing.expect(t, ui.editor_undo(state, &world))
	testing.expect(t, world.transforms[transform_index].position.x == 0)
	testing.expect(t, ui.editor_redo(state, &world))
	testing.expect(t, world.transforms[transform_index].position.x == 7)
}

@(test)
test_stop_keeps_play_mode_duplicate_as_one_undoable_authored_batch :: proc(t: ^testing.T) {
	parent_id := shared.entity_uuid_from_engine_name("keep-play-duplicate-parent")
	child_id := shared.entity_uuid_from_engine_name("keep-play-duplicate-child")
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = parent_id,
			name = "Parent",
			has_transform = true,
			transform = {scale = {1, 1, 1}},
		},
		shared.Scene_Entity {
			id = child_id,
			name = "Child",
			has_transform = true,
			transform = {parent = parent_id, scale = {1, 1, 1}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	registry: component.Registry
	component.init_registry(&registry)
	state.component_registry = &registry
	state.editor_simulation_stopped = true
	baseline: Playback_Baseline
	defer destroy_playback_baseline(&baseline)
	testing.expect(t, capture_playback_baseline(&baseline, &world) == "")

	ui.editor_play(state)
	_ = ui.consume_playback_begin_request(state)
	ui.editor_authoring_select(state, &world, 0)
	testing.expect(t, ui.editor_duplicate_selected_entities(state, &world))
	duplicate_parent_id := state.editor_selected_uuids[0]
	duplicate_child_id: shared.Entity_UUID
	for entity in world.entities {
		if !entity.alive || entity.transform_index < 0 {
			continue
		}
		if world.transforms[entity.transform_index].parent == duplicate_parent_id {
			duplicate_child_id = entity.uuid
			break
		}
	}
	testing.expect(t, duplicate_child_id != (shared.Entity_UUID{}))
	duplicate_parent_index, parent_found := ecs.entity_index_by_uuid(&world, duplicate_parent_id)
	testing.expect(t, parent_found)
	if parent_found {
		testing.expect(t, world.entities[duplicate_parent_index].origin == .Scene)
		transform_index := world.entities[duplicate_parent_index].transform_index
		world.transforms[transform_index].position.x = 9
		testing.expect(
			t,
			ui.editor_stage_play_definition(
				state,
				&world,
				duplicate_parent_index,
				"scrapbot.transform",
			),
		)
	}
	testing.expect_value(t, len(state.editor_play_structural_changes), 1)
	testing.expect_value(t, len(state.editor_play_changes), 1)

	ui.editor_stop(state)
	_ = ui.consume_playback_stop_request(state)
	runtime: script.Runtime
	runtime.world = &world
	testing.expect(t, restore_playback_baseline(&baseline, &runtime, &world) == "")
	ui.editor_world_restored(state, &world)
	testing.expect(t, ui.editor_apply_play_changes(state, &world))
	duplicate_parent_index, parent_found = ecs.entity_index_by_uuid(&world, duplicate_parent_id)
	duplicate_child_index, child_found := ecs.entity_index_by_uuid(&world, duplicate_child_id)
	testing.expect(t, parent_found && child_found)
	if parent_found && child_found {
		testing.expect(t, world.entities[duplicate_parent_index].origin == .Scene)
		transform_index := world.entities[duplicate_parent_index].transform_index
		testing.expect_value(t, world.transforms[transform_index].position.x, f32(9))
		child_transform := world.transforms[world.entities[duplicate_child_index].transform_index]
		testing.expect_value(t, child_transform.parent, duplicate_parent_id)
	}
	testing.expect_value(t, state.editor_history_count, 2)
	testing.expect(t, state.editor_scene_dirty)
	testing.expect(t, ui.editor_undo(state, &world))
	duplicate_parent_index, parent_found = ecs.entity_index_by_uuid(&world, duplicate_parent_id)
	testing.expect(t, parent_found)
	if parent_found {
		transform_index := world.entities[duplicate_parent_index].transform_index
		testing.expect_value(t, world.transforms[transform_index].position.x, f32(0))
	}
	testing.expect(t, ui.editor_undo(state, &world))
	_, parent_found = ecs.entity_index_by_uuid(&world, duplicate_parent_id)
	_, child_found = ecs.entity_index_by_uuid(&world, duplicate_child_id)
	testing.expect(t, !parent_found && !child_found)
	testing.expect(t, ui.editor_redo(state, &world))
	testing.expect(t, ui.editor_redo(state, &world))
	_, parent_found = ecs.entity_index_by_uuid(&world, duplicate_parent_id)
	_, child_found = ecs.entity_index_by_uuid(&world, duplicate_child_id)
	testing.expect(t, parent_found && child_found)
}

@(test)
test_play_edit_journal_coalesces_repeated_component_edits_and_batches_targets :: proc(
	t: ^testing.T,
) {
	scene: shared.Scene
	defer delete(scene.entities)
	names := [2]string{"First Kept Entity", "Second Kept Entity"}
	for name in names {
		append(
			&scene.entities,
			shared.Scene_Entity {
				id = shared.entity_uuid_from_engine_name(name),
				name = name,
				has_transform = true,
				transform = {scale = {1, 1, 1}},
			},
		)
	}
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: component.Registry
	component.init_registry(&registry)
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	state.component_registry = &registry
	state.editor_simulation_stopped = true
	baseline: Playback_Baseline
	defer destroy_playback_baseline(&baseline)
	testing.expect(t, capture_playback_baseline(&baseline, &world) == "")

	ui.editor_play(state)
	_ = ui.consume_playback_begin_request(state)
	first_transform := world.entities[0].transform_index
	world.transforms[first_transform].position.x = 3
	testing.expect(t, ui.editor_stage_play_definition(state, &world, 0, "scrapbot.transform"))
	world.transforms[first_transform].position.x = 8
	testing.expect(t, ui.editor_stage_play_definition(state, &world, 0, "scrapbot.transform"))
	second_transform := world.entities[1].transform_index
	world.transforms[second_transform].position.y = -5
	testing.expect(t, ui.editor_stage_play_definition(state, &world, 1, "scrapbot.transform"))
	testing.expect_value(t, len(state.editor_play_changes), 2)
	testing.expect_value(t, state.editor_history_count, 0)
	testing.expect(t, !state.editor_scene_dirty)

	ui.editor_stop(state)
	_ = ui.consume_playback_stop_request(state)
	runtime: script.Runtime
	runtime.world = &world
	testing.expect(t, restore_playback_baseline(&baseline, &runtime, &world) == "")
	ui.editor_world_restored(state, &world)
	testing.expect(t, ui.editor_apply_play_changes(state, &world))
	first_transform = world.entities[0].transform_index
	second_transform = world.entities[1].transform_index
	testing.expect_value(t, world.transforms[first_transform].position.x, f32(8))
	testing.expect_value(t, world.transforms[second_transform].position.y, f32(-5))
	testing.expect_value(t, state.editor_history_count, 1)
	testing.expect(t, ui.editor_undo(state, &world))
	testing.expect_value(t, world.transforms[first_transform].position, shared.Vec3{})
	testing.expect_value(t, world.transforms[second_transform].position, shared.Vec3{})
	testing.expect(t, !state.editor_scene_dirty)
	testing.expect(t, ui.editor_redo(state, &world))
	testing.expect_value(t, world.transforms[first_transform].position.x, f32(8))
	testing.expect_value(t, world.transforms[second_transform].position.y, f32(-5))
}

@(test)
test_stop_without_staged_play_edits_does_not_create_authoring_history :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	state.editor_simulation_stopped = true
	ui.editor_play(state)
	ui.editor_stop(state)
	ui.editor_world_restored(state, &world)
	testing.expect(t, ui.editor_apply_play_changes(state, &world))
	testing.expect_value(t, state.editor_history_count, 0)
	testing.expect_value(t, state.editor_history_cursor, 0)
	testing.expect(t, !state.editor_scene_dirty)
}

@(test)
test_play_edit_eligibility_explains_runtime_derived_and_system_written_state :: proc(
	t: ^testing.T,
) {
	scene: shared.Scene
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = shared.entity_uuid_from_engine_name("play-edit-eligibility"),
			name = "Play Edit Eligibility",
			has_transform = true,
			transform = {scale = {1, 1, 1}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	registry: component.Registry
	component.init_registry(&registry)
	state := new(ui.State)
	defer free(state)
	testing.expect(t, ui.init(state) == "")
	defer ui.destroy(state)
	state.component_registry = &registry
	state.editor_simulation_stopped = false

	transform, found := component.find_definition(&registry, "scrapbot.transform")
	testing.expect(t, found)
	editable, reason := ui.editor_component_play_editable(state, &world, 0, &transform)
	testing.expect(t, editable)
	testing.expect(t, reason == "KEPT ON STOP")

	world.entities[0].origin = .Runtime
	editable, reason = ui.editor_component_play_editable(state, &world, 0, &transform)
	testing.expect(t, !editable)
	testing.expect(t, reason == "TEMPORARY / RESET ON STOP")
	world.entities[0].origin = .Scene

	derived, derived_found := component.find_definition(&registry, "scrapbot.ui_state")
	testing.expect(t, derived_found)
	editable, reason = ui.editor_component_play_editable(state, &world, 0, &derived)
	testing.expect(t, !editable)
	testing.expect(t, reason == "READ ONLY")

	testing.expect(t, component.register_system_write_access(&registry, "scrapbot.transform"))
	transform, found = component.find_definition(&registry, "scrapbot.transform")
	testing.expect(t, found)
	editable, reason = ui.editor_component_play_editable(state, &world, 0, &transform)
	testing.expect(t, editable)
	testing.expect(t, reason == "KEPT ON STOP")

	ecs.mark_project_system_component_written(&world, 0, transform.id)
	editable, reason = ui.editor_component_play_editable(state, &world, 0, &transform)
	testing.expect(t, !editable)
	testing.expect(t, reason == "TEMPORARY / RESET ON STOP")
	world.transforms[world.entities[0].transform_index].position.x = 4
	state.editor_simulation_stopped = false
	world.entities[0].project_system_written_components = {}
	testing.expect(t, ui.editor_stage_play_component(state, &world, 0, &transform))
	ecs.mark_project_system_component_written(&world, 0, transform.id)
	ui.editor_discard_system_written_play_changes(state, &world)
	testing.expect_value(t, len(state.editor_play_changes), 0)

	state.editor_simulation_stopped = true
	editable, reason = ui.editor_component_play_editable(state, &world, 0, &transform)
	testing.expect(t, editable)
	testing.expect(t, reason == "SAVED WITH SCENE")
}
