package main

import "core:testing"

@(test)
test_runtime_type_ids_distinguish_project_package_and_engine_namespaces :: proc(t: ^testing.T) {
	testing.expect_value(t, runtime_validate_project_type_id("stamina"), Runtime_Error.None)
	testing.expect_value(t, runtime_validate_project_type_id("inventory_item"), Runtime_Error.None)
	testing.expect_value(t, runtime_validate_project_type_id("com.acme.stamina"), Runtime_Error.None)
	testing.expect_value(t, runtime_validate_project_type_id("game.stamina"), Runtime_Error.None)
	testing.expect_value(t, runtime_validate_package_type_id("com.acme.stamina"), Runtime_Error.None)
	testing.expect_value(t, runtime_validate_engine_type_id("scrapbot.transform"), Runtime_Error.None)

	testing.expect_value(t, runtime_validate_project_type_id("Com.Acme.Stamina"), Runtime_Error.Invalid_Type_ID)
	testing.expect_value(t, runtime_validate_project_type_id("com.acme-stamina"), Runtime_Error.Invalid_Type_ID)
	testing.expect_value(t, runtime_validate_project_type_id("com..stamina"), Runtime_Error.Invalid_Type_ID)
	testing.expect_value(t, runtime_validate_package_type_id("stamina"), Runtime_Error.Invalid_Type_ID)
	testing.expect_value(t, runtime_validate_project_type_id("scrapbot.transform"), Runtime_Error.Reserved_Type_ID)
	testing.expect_value(t, runtime_validate_package_type_id("scrapbot.transform"), Runtime_Error.Reserved_Type_ID)
	testing.expect_value(t, runtime_validate_engine_type_id("stamina"), Runtime_Error.Reserved_Type_ID)
	testing.expect_value(t, runtime_validate_engine_type_id("com.acme.stamina"), Runtime_Error.Reserved_Type_ID)
}

@(test)
test_runtime_component_registry_accepts_identical_reload_and_rejects_incompatible_duplicate :: proc(t: ^testing.T) {
	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)

	fields := []Runtime_Component_Field_Definition{
		{name = "current", value_type = .Float},
		{name = "max", value_type = .Float},
	}
	testing.expect_value(t, runtime_register_project_component(&registry, Runtime_Component_Definition{
		id = "stamina",
		version = 1,
		fields = fields,
	}), Runtime_Error.None)
	testing.expect_value(t, runtime_register_project_component(&registry, Runtime_Component_Definition{
		id = "stamina",
		version = 1,
		fields = fields,
	}), Runtime_Error.None)

	testing.expect_value(t, runtime_registry_component_count(registry), 1)

	incompatible_fields := []Runtime_Component_Field_Definition{
		{name = "current", value_type = .Int},
		{name = "max", value_type = .Float},
	}
	testing.expect_value(t, runtime_register_project_component(&registry, Runtime_Component_Definition{
		id = "stamina",
		version = 1,
		fields = incompatible_fields,
	}), Runtime_Error.Duplicate_Component_Type)
}

@(test)
test_runtime_component_registry_rejects_duplicate_or_invalid_fields :: proc(t: ^testing.T) {
	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)

	duplicate_fields := []Runtime_Component_Field_Definition{
		{name = "current", value_type = .Float},
		{name = "current", value_type = .Int},
	}
	testing.expect_value(t, runtime_register_project_component(&registry, Runtime_Component_Definition{
		id = "com.acme.stamina",
		version = 1,
		fields = duplicate_fields,
	}), Runtime_Error.Duplicate_Component_Field)

	invalid_fields := []Runtime_Component_Field_Definition{
		{name = "Current", value_type = .Float},
	}
	testing.expect_value(t, runtime_register_project_component(&registry, Runtime_Component_Definition{
		id = "com.acme.mana",
		version = 1,
		fields = invalid_fields,
	}), Runtime_Error.Invalid_Field_Name)
}

@(test)
test_runtime_component_registry_separates_registration_contexts :: proc(t: ^testing.T) {
	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)

	testing.expect_value(t, runtime_register_project_component(&registry, Runtime_Component_Definition{
		id = "stamina",
		version = 1,
	}), Runtime_Error.None)
	testing.expect_value(t, runtime_register_package_component(&registry, Runtime_Component_Definition{
		id = "mana",
		version = 1,
	}), Runtime_Error.Invalid_Type_ID)
	testing.expect_value(t, runtime_register_package_component(&registry, Runtime_Component_Definition{
		id = "com.acme.mana",
		version = 1,
	}), Runtime_Error.None)
	testing.expect_value(t, runtime_register_project_component(&registry, Runtime_Component_Definition{
		id = "scrapbot.transform",
		version = 1,
	}), Runtime_Error.Reserved_Type_ID)
	testing.expect_value(t, runtime_register_engine_component(&registry, Runtime_Component_Definition{
		id = "scrapbot.transform",
		version = 1,
	}), Runtime_Error.None)

	testing.expect_value(t, runtime_registry_component_count(registry), 3)
}

@(test)
test_runtime_registers_engine_component_schemas :: proc(t: ^testing.T) {
	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)

	testing.expect_value(t, runtime_register_engine_components(&registry), Runtime_Error.None)

	registered_ids := [?]string{
		TRANSFORM_COMPONENT_ID,
		CUBE_RENDERER_COMPONENT_ID,
		GEOMETRY_PRIMITIVE_COMPONENT_ID,
		SURFACE_MATERIAL_COMPONENT_ID,
		RENDERER_COMPONENT_ID,
		CAMERA_COMPONENT_ID,
		DIRECTIONAL_LIGHT_COMPONENT_ID,
		SHADOW_CASTER_COMPONENT_ID,
		SHADOW_RECEIVER_COMPONENT_ID,
		UI_CANVAS_COMPONENT_ID,
		UI_RECT_COMPONENT_ID,
		UI_BORDER_COMPONENT_ID,
		UI_TEXT_COMPONENT_ID,
		UI_BUTTON_COMPONENT_ID,
		UI_HIT_AREA_COMPONENT_ID,
		UI_COMMAND_COMPONENT_ID,
		UI_COMMAND_EVENT_COMPONENT_ID,
		UI_SCROLL_VIEW_COMPONENT_ID,
		UI_VGROUP_COMPONENT_ID,
		UI_HGROUP_COMPONENT_ID,
		UI_TABLE_COMPONENT_ID,
		UI_STACK_COMPONENT_ID,
		UI_LAYOUT_ITEM_COMPONENT_ID,
		UI_SPACER_COMPONENT_ID,
		UI_TEXT_BLOCK_COMPONENT_ID,
		UI_TOGGLE_COMPONENT_ID,
		UI_PROGRESS_BAR_COMPONENT_ID,
		UI_SEPARATOR_COMPONENT_ID,
		INPUT_POINTER_COMPONENT_ID,
		INPUT_KEYBOARD_COMPONENT_ID,
		INPUT_FRAME_COMPONENT_ID,
	}
	for id in registered_ids {
		_, found := runtime_find_component(registry, id)
		testing.expect_value(t, found, true)
	}

	transform, found := runtime_find_component(registry, TRANSFORM_COMPONENT_ID)
	testing.expect_value(t, found, true)
	testing.expect_value(t, len(transform.fields), 3)
	testing.expect_value(t, transform.fields[0].name, "position")
	testing.expect_value(t, transform.fields[0].value_type, Runtime_Field_Type.Vec3)

	testing.expect_value(t, runtime_register_engine_components(&registry), Runtime_Error.None)
	testing.expect_value(t, runtime_registry_component_count(registry), 31)
}

@(test)
test_runtime_world_creates_entities_with_provenance_and_generation_handles :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	spawned, spawned_err := runtime_world_create_entity(&world, "spawned", "Spawned")
	testing.expect_value(t, spawned_err, Runtime_Error.None)
	authored, authored_err := runtime_world_create_authored_entity(&world, "authored", "Authored")
	testing.expect_value(t, authored_err, Runtime_Error.None)

	testing.expect_value(t, runtime_world_entity_count(world), 2)
	testing.expect_value(t, spawned.index, 0)
	testing.expect_value(t, spawned.generation, 1)
	testing.expect_value(t, authored.index, 1)
	testing.expect_value(t, authored.generation, 2)

	stored_spawned, entity_err := runtime_world_entity(world, spawned)
	testing.expect_value(t, entity_err, Runtime_Error.None)
	testing.expect_value(t, stored_spawned.id, "spawned")
	testing.expect_value(t, stored_spawned.provenance, Entity_Provenance.Spawned)

	stored_authored, authored_entity_err := runtime_world_entity(world, authored)
	testing.expect_value(t, authored_entity_err, Runtime_Error.None)
	testing.expect_value(t, stored_authored.id, "authored")
	testing.expect_value(t, stored_authored.provenance, Entity_Provenance.Authored)

	_, duplicate_err := runtime_world_create_entity(&world, "spawned", "Duplicate")
	testing.expect_value(t, duplicate_err, Runtime_Error.Duplicate_Entity_ID)
}

@(test)
test_runtime_world_removes_entities_and_rejects_stale_handles :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	first, first_err := runtime_world_create_entity(&world, "first", "First")
	testing.expect_value(t, first_err, Runtime_Error.None)
	middle, middle_err := runtime_world_create_entity(&world, "middle", "Middle")
	testing.expect_value(t, middle_err, Runtime_Error.None)
	last, last_err := runtime_world_create_entity(&world, "last", "Last")
	testing.expect_value(t, last_err, Runtime_Error.None)

	testing.expect_value(t, runtime_world_remove_entity(&world, middle), Runtime_Error.None)
	testing.expect_value(t, runtime_world_entity_count(world), 2)
	_, middle_found := runtime_world_find_entity_by_id(world, "middle")
	testing.expect_value(t, middle_found, false)
	_, middle_lookup_err := runtime_world_entity(world, middle)
	testing.expect_value(t, middle_lookup_err, Runtime_Error.Invalid_Entity)

	moved_last, last_found := runtime_world_find_entity_by_id(world, "last")
	testing.expect_value(t, last_found, true)
	testing.expect_value(t, moved_last.index, 1)
	testing.expect_value(t, moved_last.generation, last.generation)
	_, stale_last_err := runtime_world_entity(world, last)
	testing.expect_value(t, stale_last_err, Runtime_Error.Invalid_Entity)

	still_first, first_lookup_err := runtime_world_entity(world, first)
	testing.expect_value(t, first_lookup_err, Runtime_Error.None)
	testing.expect_value(t, still_first.id, "first")
}
