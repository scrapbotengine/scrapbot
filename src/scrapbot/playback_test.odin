package scrapbot

import ecs "./ecs"
import resources "./resources"
import script "./script"
import shared "./shared"
import ui "./ui"
import "core:testing"

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
		{base_color = {0.2, 0.3, 0.4, 1}, emissive = {1, 2, 3}},
	)
	testing.expect(t, register_err == "")
	baseline: Playback_Baseline
	defer destroy_playback_baseline(&baseline)
	testing.expect(t, capture_playback_baseline(&baseline, &world, &registry) == "")
	material, alive := resources.get_material(&registry, handle)
	testing.expect(t, alive)
	material.desc.base_color = {0.9, 0.8, 0.7, 0.6}
	material.desc.emissive = {8, 7, 6}
	material.version += 1
	mutated_version := material.version
	testing.expect(t, restore_playback_baseline(&baseline, &runtime, &world, &registry) == "")
	material, alive = resources.get_material(&registry, handle)
	testing.expect(t, alive)
	if alive {
		testing.expect_value(t, material.desc.base_color, resources.Vec4{0.2, 0.3, 0.4, 1})
		testing.expect_value(t, material.desc.emissive, shared.Vec3{1, 2, 3})
		testing.expect_value(t, material.version, mutated_version + 1)
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
