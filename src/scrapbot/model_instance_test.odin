package scrapbot

import ecs "./ecs"
import project "./project"
import resources "./resources"
import script "./script"
import shared "./shared"
import "core:testing"

@(test)
test_model_resource_expands_into_stable_derived_ecs_renderables :: proc(t: ^testing.T) {
	loaded := project.load_project("examples/assets")
	defer project.destroy_project_load_result(&loaded)
	testing.expectf(t, loaded.err == "", "asset example load failed: %s", loaded.err)
	if loaded.err != "" {
		return
	}
	world := ecs.build_world(&loaded.scene)
	defer ecs.destroy_world(&world)
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	init_err := init_render_resources(
		&registry,
		&world,
		"examples/assets",
		&loaded.config,
		loaded.resources[:],
	)
	testing.expectf(t, init_err == "", "model instance initialization failed: %s", init_err)
	root_id, _ := shared.entity_uuid_parse("a7100000-0000-4000-8000-000000000003")
	derived_index := -1
	for entity, entity_index in world.entities {
		if entity.alive && entity.model_owner == root_id {
			derived_index = entity_index
			break
		}
	}
	testing.expect(t, derived_index >= 0)
	if derived_index < 0 {
		return
	}
	derived := world.entities[derived_index]
	testing.expect(t, derived.origin == .Runtime)
	testing.expect(t, derived.transform_index >= 0)
	testing.expect(t, derived.geometry_index >= 0)
	testing.expect(t, derived.material_index >= 0)
	testing.expect_value(t, world.transforms[derived.transform_index].parent, root_id)
	stable_id := derived.uuid
	testing.expect(t, reconcile_model_instances(&world, &registry) == "")
	recreated_index, found := ecs.entity_index_by_uuid(&world, stable_id)
	testing.expect(t, found)
	if found {
		testing.expect(t, world.entities[recreated_index].model_owner == root_id)
		testing.expect(t, world.entities[recreated_index].geometry_index >= 0)
	}
	root_index, root_found := ecs.entity_index_by_uuid(&world, root_id)
	testing.expect(t, root_found)
	if root_found {
		duplicate, captured := ecs.capture_entity_snapshot(&world, root_index)
		testing.expect(t, captured)
		if captured {
			defer ecs.destroy_entity_snapshot(&duplicate)
			duplicate_id, _ := shared.entity_uuid_parse("a7100000-0000-4000-8000-000000000099")
			duplicate.entity.id = duplicate_id
			delete(duplicate.entity.name)
			duplicate.entity.name = ecs.clone_snapshot_string("Imported Triangle Copy")
			_, applied := ecs.apply_entity_snapshot(&world, &duplicate)
			testing.expect(t, applied)
			testing.expect(t, reconcile_model_instances(&world, &registry) == "")
			model_id, _ := shared.resource_uuid_parse("a7000000-0000-4000-8000-000000000001")
			duplicate_child := model_instance_uuid(duplicate_id, model_id, 0, -1)
			_, duplicate_child_found := ecs.entity_index_by_uuid(&world, duplicate_child)
			testing.expect(t, duplicate_child_found)
		}
	}
	baseline: Playback_Baseline
	defer destroy_playback_baseline(&baseline)
	testing.expect(t, capture_playback_baseline(&baseline, &world, &registry) == "")
	runtime: script.Runtime
	testing.expect(t, restore_playback_baseline(&baseline, &runtime, &world, &registry) == "")
	testing.expect(t, reconcile_model_instances(&world, &registry) == "")
	stopped_index, stopped_found := ecs.entity_index_by_uuid(&world, stable_id)
	testing.expect(t, stopped_found)
	if stopped_found {
		testing.expect(t, world.entities[stopped_index].model_owner == root_id)
	}
	root_index, root_found = ecs.entity_index_by_uuid(&world, root_id)
	testing.expect(t, root_found)
	if root_found {
		ecs.set_entity_model_resource(&world, root_index, "")
		_, child_still_present := ecs.entity_index_by_uuid(&world, stable_id)
		testing.expect(t, !child_still_present)
	}
}
