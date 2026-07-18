package ecs

import component "../component"
import shared "../shared"
import "core:testing"

@(test)
test_registered_component_membership_is_surgical_and_registry_driven :: proc(t: ^testing.T) {
	registry: component.Registry
	component.init_registry(&registry)
	existing_schema := component.Definition {
		name = "existing",
		field_count = 1,
	}
	existing_schema.fields[0] = {
		name = "value",
		field_type = .Vec3,
	}
	testing.expect(t, component.register_project_component(&registry, existing_schema) == "")
	added_schema := component.Definition {
		name = "added",
		field_count = 1,
	}
	added_schema.fields[0] = {
		name = "velocity",
		field_type = .Vec3,
	}
	testing.expect(t, component.register_project_component(&registry, added_schema) == "")
	existing_definition, existing_found := component.find_definition(&registry, "existing")
	added_definition, added_found := component.find_definition(&registry, "added")
	point_light_definition, point_light_found := component.find_definition(
		&registry,
		"scrapbot.point_light",
	)
	derived_definition, derived_found := component.find_definition(
		&registry,
		"scrapbot.internal.render_instance",
	)
	testing.expect(t, existing_found && added_found && point_light_found && derived_found)

	scene: shared.Scene
	defer delete(scene.entities)
	value := shared.Custom_Component {
		name = "existing",
	}
	append(&value.vec3_fields, shared.Named_Vec3{name = "value", value = {4, 5, 6}})
	defer delete(value.vec3_fields)
	entity := shared.Scene_Entity {
		id = shared.entity_uuid_from_engine_name("surgical-membership"),
		name = "Surgical Membership",
		has_transform = true,
		transform = {position = {1, 2, 3}, scale = {1, 1, 1}},
	}
	append(&entity.custom_components, value)
	defer delete(entity.custom_components)
	append(&scene.entities, entity)
	world := build_world(&scene)
	defer destroy_world(&world)
	bind_custom_component_storage(&world, existing_definition.name, existing_definition.id)
	existing, existing_ok := custom_component_for_entity_ref(
		&world,
		0,
		existing_definition.id,
		existing_definition.name,
	)
	testing.expect(t, existing_ok)
	if !existing_ok {
		return
	}
	existing_fields := raw_data(existing.vec3_fields)
	transform_index := world.entities[0].transform_index
	transform_before := world.transforms[transform_index]

	testing.expect(
		t,
		set_registered_component_membership(&world, 0, &point_light_definition, true),
	)
	testing.expect(t, registered_component_is_present(&world, 0, &point_light_definition))
	testing.expect(t, world.point_lights[world.entities[0].point_light_index].range == 10)
	testing.expect(t, world.entities[0].transform_index == transform_index)
	testing.expect(t, world.transforms[transform_index] == transform_before)
	existing, existing_ok = custom_component_for_entity_ref(
		&world,
		0,
		existing_definition.id,
		existing_definition.name,
	)
	testing.expect(t, existing_ok && raw_data(existing.vec3_fields) == existing_fields)
	testing.expect(t, existing.vec3_fields[0].value == shared.Vec3{4, 5, 6})

	testing.expect(t, set_registered_component_membership(&world, 0, &added_definition, true))
	added, added_ok := custom_component_for_entity_ref(
		&world,
		0,
		added_definition.id,
		added_definition.name,
	)
	testing.expect(t, added_ok)
	if added_ok {
		testing.expect(t, len(added.vec3_fields) == 1)
		testing.expect(t, added.vec3_fields[0].name == "velocity")
	}
	existing, existing_ok = custom_component_for_entity_ref(
		&world,
		0,
		existing_definition.id,
		existing_definition.name,
	)
	testing.expect(t, existing_ok && raw_data(existing.vec3_fields) == existing_fields)
	testing.expect(t, !set_registered_component_membership(&world, 0, &derived_definition, true))

	testing.expect(t, set_registered_component_membership(&world, 0, &added_definition, false))
	testing.expect(t, !registered_component_is_present(&world, 0, &added_definition))
	testing.expect(
		t,
		set_registered_component_membership(&world, 0, &point_light_definition, false),
	)
	testing.expect(t, !registered_component_is_present(&world, 0, &point_light_definition))
	existing, existing_ok = custom_component_for_entity_ref(
		&world,
		0,
		existing_definition.id,
		existing_definition.name,
	)
	testing.expect(t, existing_ok && raw_data(existing.vec3_fields) == existing_fields)
	failure, integrity_ok := validate_world_integrity(&world)
	testing.expectf(t, integrity_ok, "%s", format_world_integrity_failure(failure))
}
