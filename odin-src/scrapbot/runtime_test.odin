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

@(test)
test_runtime_world_sets_gets_and_updates_component_fields :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	entity, entity_err := runtime_world_create_entity(&world, "moving", "Moving")
	testing.expect_value(t, entity_err, Runtime_Error.None)

	testing.expect_value(t, runtime_world_set_component(&world, entity, "motion", []Runtime_Component_Field_Value{
		{name = "position", value = runtime_component_value_vec3([3]f32{1, 2, 3})},
		{name = "label", value = runtime_component_value_string("idle")},
		{name = "enabled", value = runtime_component_value_boolean(true)},
		{name = "count", value = runtime_component_value_int(3)},
		{name = "speed", value = runtime_component_value_float(1.5)},
	}), Runtime_Error.None)

	testing.expect_value(t, runtime_world_component_instance_count(world), 1)
	has_motion, has_err := runtime_world_has_component(world, entity, "motion")
	testing.expect_value(t, has_err, Runtime_Error.None)
	testing.expect_value(t, has_motion, true)

	position, position_err := runtime_world_get_component_field_value(world, entity, "motion", "position")
	testing.expect_value(t, position_err, Runtime_Error.None)
	testing.expect_value(t, position.value_type, Runtime_Field_Type.Vec3)
	testing.expect_value(t, position.vec3[0], f32(1))
	testing.expect_value(t, position.vec3[1], f32(2))
	testing.expect_value(t, position.vec3[2], f32(3))

	label, label_err := runtime_world_get_component_field_value(world, entity, "motion", "label")
	testing.expect_value(t, label_err, Runtime_Error.None)
	testing.expect_value(t, label.string_value, "idle")

	testing.expect_value(t, runtime_world_set_component_field_value(&world, entity, "motion", "label", runtime_component_value_string("running")), Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component_field_value(&world, entity, "motion", "speed", runtime_component_value_float(2.25)), Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component_field_value(&world, entity, "motion", "label", runtime_component_value_string("")), Runtime_Error.None)

	updated_label, updated_label_err := runtime_world_get_component_field_value(world, entity, "motion", "label")
	testing.expect_value(t, updated_label_err, Runtime_Error.None)
	testing.expect_value(t, updated_label.string_value, "")
	updated_speed, updated_speed_err := runtime_world_get_component_field_value(world, entity, "motion", "speed")
	testing.expect_value(t, updated_speed_err, Runtime_Error.None)
	testing.expect_value(t, updated_speed.float, f32(2.25))

	testing.expect_value(t, runtime_world_set_component(&world, entity, "motion", []Runtime_Component_Field_Value{
		{name = "speed", value = runtime_component_value_float(4.0)},
		{name = "count", value = runtime_component_value_int(8)},
		{name = "enabled", value = runtime_component_value_boolean(false)},
		{name = "label", value = runtime_component_value_string("done")},
		{name = "position", value = runtime_component_value_vec3([3]f32{9, 8, 7})},
	}), Runtime_Error.None)
	testing.expect_value(t, runtime_world_component_instance_count(world), 1)

	replaced_position, replaced_position_err := runtime_world_get_component_field_value(world, entity, "motion", "position")
	testing.expect_value(t, replaced_position_err, Runtime_Error.None)
	testing.expect_value(t, replaced_position.vec3[0], f32(9))
	testing.expect_value(t, replaced_position.vec3[1], f32(8))
	testing.expect_value(t, replaced_position.vec3[2], f32(7))

	testing.expect_value(t, runtime_world_set_component_field_value(&world, entity, "motion", "enabled", runtime_component_value_int(1)), Runtime_Error.Invalid_Field_Type)
	testing.expect_value(t, runtime_world_set_component_field_value(&world, entity, "motion", "missing", runtime_component_value_boolean(true)), Runtime_Error.Unknown_Field)
	testing.expect_value(t, runtime_world_set_component_field_value(&world, entity, "missing", "enabled", runtime_component_value_boolean(true)), Runtime_Error.Unknown_Component)
	_, missing_field_err := runtime_world_get_component_field_value(world, entity, "motion", "missing")
	testing.expect_value(t, missing_field_err, Runtime_Error.Unknown_Field)
}

@(test)
test_runtime_world_queries_entities_with_component_sets :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	plain, plain_err := runtime_world_create_entity(&world, "plain", "Plain")
	testing.expect_value(t, plain_err, Runtime_Error.None)
	spinner, spinner_err := runtime_world_create_entity(&world, "spinner", "Spinner")
	testing.expect_value(t, spinner_err, Runtime_Error.None)
	mover, mover_err := runtime_world_create_entity(&world, "mover", "Mover")
	testing.expect_value(t, mover_err, Runtime_Error.None)

	plain_transform := [3]Runtime_Component_Field_Value{
		{name = "position", value = runtime_component_value_vec3([3]f32{0, 0, 0})},
		{name = "rotation", value = runtime_component_value_vec3([3]f32{0, 0, 0})},
		{name = "scale", value = runtime_component_value_vec3([3]f32{1, 1, 1})},
	}
	spinner_transform := [3]Runtime_Component_Field_Value{
		{name = "position", value = runtime_component_value_vec3([3]f32{1, 0, 0})},
		{name = "rotation", value = runtime_component_value_vec3([3]f32{0, 0, 0})},
		{name = "scale", value = runtime_component_value_vec3([3]f32{1, 1, 1})},
	}
	mover_transform := [3]Runtime_Component_Field_Value{
		{name = "position", value = runtime_component_value_vec3([3]f32{2, 0, 0})},
		{name = "rotation", value = runtime_component_value_vec3([3]f32{0, 0, 0})},
		{name = "scale", value = runtime_component_value_vec3([3]f32{1, 1, 1})},
	}

	testing.expect_value(t, runtime_world_set_component(&world, plain, TRANSFORM_COMPONENT_ID, plain_transform[:]), Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component(&world, spinner, TRANSFORM_COMPONENT_ID, spinner_transform[:]), Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component(&world, mover, TRANSFORM_COMPONENT_ID, mover_transform[:]), Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component(&world, spinner, "spin", []Runtime_Component_Field_Value{
		{name = "rate", value = runtime_component_value_float(90)},
	}), Runtime_Error.None)

	cursor := 0
	match, found := runtime_world_query_next(world, []string{TRANSFORM_COMPONENT_ID, "spin"}, &cursor)
	testing.expect_value(t, found, true)
	testing.expect_value(t, match.index, spinner.index)
	testing.expect_value(t, match.generation, spinner.generation)
	_, found = runtime_world_query_next(world, []string{TRANSFORM_COMPONENT_ID, "spin"}, &cursor)
	testing.expect_value(t, found, false)

	cursor = 0
	count := 0
	for {
		_, has_next := runtime_world_query_next(world, []string{TRANSFORM_COMPONENT_ID}, &cursor)
		if !has_next {
			break
		}
		count += 1
	}
	testing.expect_value(t, count, 3)

	cursor = 0
	_, found = runtime_world_query_next(world, []string{"missing"}, &cursor)
	testing.expect_value(t, found, false)
}

@(test)
test_runtime_world_removes_components_and_repairs_entity_rows :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)

	first, first_err := runtime_world_create_entity(&world, "first", "First")
	testing.expect_value(t, first_err, Runtime_Error.None)
	middle, middle_err := runtime_world_create_entity(&world, "middle", "Middle")
	testing.expect_value(t, middle_err, Runtime_Error.None)
	last, last_err := runtime_world_create_entity(&world, "last", "Last")
	testing.expect_value(t, last_err, Runtime_Error.None)

	first_health := [1]Runtime_Component_Field_Value{{name = "current", value = runtime_component_value_int(10)}}
	middle_health := [1]Runtime_Component_Field_Value{{name = "current", value = runtime_component_value_int(20)}}
	last_health_fields := [1]Runtime_Component_Field_Value{{name = "current", value = runtime_component_value_int(30)}}
	testing.expect_value(t, runtime_world_set_component(&world, first, "health", first_health[:]), Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component(&world, middle, "health", middle_health[:]), Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component(&world, last, "health", last_health_fields[:]), Runtime_Error.None)

	removed, remove_err := runtime_world_remove_component(&world, middle, "health")
	testing.expect_value(t, remove_err, Runtime_Error.None)
	testing.expect_value(t, removed, true)
	testing.expect_value(t, runtime_world_component_instance_count(world), 2)
	has_middle_health, has_middle_err := runtime_world_has_component(world, middle, "health")
	testing.expect_value(t, has_middle_err, Runtime_Error.None)
	testing.expect_value(t, has_middle_health, false)

	last_health, last_health_err := runtime_world_get_component_field_value(world, last, "health", "current")
	testing.expect_value(t, last_health_err, Runtime_Error.None)
	testing.expect_value(t, last_health.int_value, 30)

	restored_middle_health := [1]Runtime_Component_Field_Value{{name = "current", value = runtime_component_value_int(25)}}
	testing.expect_value(t, runtime_world_set_component(&world, middle, "health", restored_middle_health[:]), Runtime_Error.None)
	testing.expect_value(t, runtime_world_component_instance_count(world), 3)
	testing.expect_value(t, runtime_world_remove_entity(&world, middle), Runtime_Error.None)
	testing.expect_value(t, runtime_world_entity_count(world), 2)
	testing.expect_value(t, runtime_world_component_instance_count(world), 2)

	_, stale_middle_err := runtime_world_entity(world, middle)
	testing.expect_value(t, stale_middle_err, Runtime_Error.Invalid_Entity)
	moved_last, last_found := runtime_world_find_entity_by_id(world, "last")
	testing.expect_value(t, last_found, true)
	testing.expect_value(t, moved_last.index, u32(1))
	testing.expect_value(t, moved_last.generation, last.generation)
	_, stale_last_health_err := runtime_world_get_component_field_value(world, last, "health", "current")
	testing.expect_value(t, stale_last_health_err, Runtime_Error.Invalid_Entity)

	moved_last_health, moved_last_health_err := runtime_world_get_component_field_value(world, moved_last, "health", "current")
	testing.expect_value(t, moved_last_health_err, Runtime_Error.None)
	testing.expect_value(t, moved_last_health.int_value, 30)
}

@(test)
test_runtime_registry_validates_system_access_and_duplicates :: proc(t: ^testing.T) {
	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)

	marker_fields := [1]Runtime_Component_Field_Definition{{name = "value", value_type = .Int}}
	testing.expect_value(t, runtime_register_project_component(&registry, Runtime_Component_Definition{
		id = "marker",
		version = 1,
		fields = marker_fields[:],
	}), Runtime_Error.None)

	reads_marker := [1]string{"marker"}
	testing.expect_value(t, runtime_register_project_system(&registry, Runtime_System_Definition{
		id = "read_marker",
		phase = .Update,
		reads = reads_marker[:],
	}), Runtime_Error.None)
	testing.expect_value(t, runtime_register_project_system(&registry, Runtime_System_Definition{
		id = "read_marker",
		phase = .Update,
		reads = reads_marker[:],
	}), Runtime_Error.None)
	testing.expect_value(t, runtime_registry_system_count(registry), 1)

	writes_marker := [1]string{"marker"}
	testing.expect_value(t, runtime_register_project_system(&registry, Runtime_System_Definition{
		id = "read_marker",
		phase = .Update,
		writes = writes_marker[:],
	}), Runtime_Error.Duplicate_System_Type)

	missing_reads := [1]string{"missing"}
	testing.expect_value(t, runtime_register_project_system(&registry, Runtime_System_Definition{
		id = "missing_reader",
		phase = .Update,
		reads = missing_reads[:],
	}), Runtime_Error.Unknown_Component_Type)

	testing.expect_value(t, runtime_register_project_system(&registry, Runtime_System_Definition{
		id = "conflicting_access",
		phase = .Update,
		reads = reads_marker[:],
		writes = writes_marker[:],
	}), Runtime_Error.Duplicate_System_Access)

	duplicate_reads := [2]string{"marker", "marker"}
	testing.expect_value(t, runtime_register_project_system(&registry, Runtime_System_Definition{
		id = "duplicate_reads",
		phase = .Update,
		reads = duplicate_reads[:],
	}), Runtime_Error.Duplicate_System_Access)
}

@(test)
test_runtime_builds_schedule_batches_from_order_and_access :: proc(t: ^testing.T) {
	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)

	component_ids := [2]string{"a", "b"}
	for id in component_ids {
		testing.expect_value(t, runtime_register_project_component(&registry, Runtime_Component_Definition{id = id, version = 1}), Runtime_Error.None)
	}

	reads_a := [1]string{"a"}
	writes_a := [1]string{"a"}
	writes_b := [1]string{"b"}
	testing.expect_value(t, runtime_register_project_system(&registry, Runtime_System_Definition{id = "read_a", phase = .Update, reads = reads_a[:]}), Runtime_Error.None)
	testing.expect_value(t, runtime_register_project_system(&registry, Runtime_System_Definition{id = "write_a", phase = .Update, writes = writes_a[:]}), Runtime_Error.None)
	testing.expect_value(t, runtime_register_project_system(&registry, Runtime_System_Definition{id = "write_b", phase = .Update, writes = writes_b[:]}), Runtime_Error.None)

	schedule, schedule_err := runtime_build_system_schedule(registry, .Update)
	testing.expect_value(t, schedule_err, Runtime_Error.None)
	defer runtime_system_schedule_free(schedule)
	testing.expect_value(t, runtime_system_schedule_batch_count(schedule), 2)
	testing.expect_value(t, runtime_system_schedule_system_count(schedule), 3)
	testing.expect_value(t, len(schedule.batches[0].systems), 2)
	testing.expect_value(t, schedule.batches[0].systems[0].id, "read_a")
	testing.expect_value(t, schedule.batches[0].systems[1].id, "write_b")
	testing.expect_value(t, schedule.batches[1].systems[0].id, "write_a")
}

@(test)
test_runtime_builds_ordered_schedule_and_rejects_cycles :: proc(t: ^testing.T) {
	ordered := Runtime_Component_Registry{}
	defer runtime_registry_free(&ordered)

	testing.expect_value(t, runtime_register_project_component(&ordered, Runtime_Component_Definition{id = "marker", version = 1}), Runtime_Error.None)
	reads_marker := [1]string{"marker"}
	before_second := [1]string{"second"}
	after_first := [1]string{"first"}
	testing.expect_value(t, runtime_register_project_system(&ordered, Runtime_System_Definition{
		id = "first",
		phase = .Startup,
		reads = reads_marker[:],
		before = before_second[:],
	}), Runtime_Error.None)
	testing.expect_value(t, runtime_register_project_system(&ordered, Runtime_System_Definition{
		id = "second",
		phase = .Startup,
		reads = reads_marker[:],
		after = after_first[:],
	}), Runtime_Error.None)

	schedule, schedule_err := runtime_build_system_schedule(ordered, .Startup)
	testing.expect_value(t, schedule_err, Runtime_Error.None)
	defer runtime_system_schedule_free(schedule)
	testing.expect_value(t, runtime_system_schedule_batch_count(schedule), 2)
	testing.expect_value(t, schedule.batches[0].systems[0].id, "first")
	testing.expect_value(t, schedule.batches[1].systems[0].id, "second")

	cyclic := Runtime_Component_Registry{}
	defer runtime_registry_free(&cyclic)
	testing.expect_value(t, runtime_register_project_component(&cyclic, Runtime_Component_Definition{id = "marker", version = 1}), Runtime_Error.None)
	one_before_two := [1]string{"two"}
	two_before_one := [1]string{"one"}
	testing.expect_value(t, runtime_register_project_system(&cyclic, Runtime_System_Definition{
		id = "one",
		phase = .Startup,
		reads = reads_marker[:],
		before = one_before_two[:],
	}), Runtime_Error.None)
	testing.expect_value(t, runtime_register_project_system(&cyclic, Runtime_System_Definition{
		id = "two",
		phase = .Startup,
		reads = reads_marker[:],
		before = two_before_one[:],
	}), Runtime_Error.None)
	_, cyclic_err := runtime_build_system_schedule(cyclic, .Startup)
	testing.expect_value(t, cyclic_err, Runtime_Error.Cyclic_System_Order)
}

@(test)
test_runtime_deferred_component_adds_flush_after_system_boundary :: proc(t: ^testing.T) {
	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)
	world := runtime_world_init()
	defer runtime_world_free(&world)
	buffer := Runtime_Deferred_Command_Buffer{}
	defer runtime_deferred_command_buffer_free(&buffer)

	marker_fields := [1]Runtime_Component_Field_Definition{{name = "value", value_type = .Int}}
	testing.expect_value(t, runtime_register_project_component(&registry, Runtime_Component_Definition{id = "marker", version = 1, fields = marker_fields[:]}), Runtime_Error.None)
	writes_marker := [1]string{"marker"}
	system := Runtime_System_Definition{id = "create_marker", phase = .Startup, writes = writes_marker[:]}

	entity, entity_err := runtime_world_create_entity(&world, "queued", "Queued")
	testing.expect_value(t, entity_err, Runtime_Error.None)
	testing.expect_value(t, runtime_deferred_record_immediate_spawn(&buffer, entity), Runtime_Error.None)
	component_fields := [1]Runtime_Component_Field_Value{{name = "value", value = runtime_component_value_int(11)}}
	testing.expect_value(t, runtime_deferred_queue_add_component(&buffer, system, entity, "marker", component_fields[:]), Runtime_Error.None)

	has_marker, has_err := runtime_world_has_component(world, entity, "marker")
	testing.expect_value(t, has_err, Runtime_Error.None)
	testing.expect_value(t, has_marker, false)

	testing.expect_value(t, runtime_deferred_flush(&buffer, &world, registry), Runtime_Error.None)
	value, value_err := runtime_world_get_component_field_value(world, entity, "marker", "value")
	testing.expect_value(t, value_err, Runtime_Error.None)
	testing.expect_value(t, value.int_value, 11)
	testing.expect_value(t, len(buffer.commands), 0)
	testing.expect_value(t, len(buffer.immediate_spawns), 0)
}

@(test)
test_runtime_deferred_mutations_require_declared_write_access :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)
	buffer := Runtime_Deferred_Command_Buffer{}
	defer runtime_deferred_command_buffer_free(&buffer)

	entity, entity_err := runtime_world_create_entity(&world, "entity", "Entity")
	testing.expect_value(t, entity_err, Runtime_Error.None)
	reads_marker := [1]string{"marker"}
	read_only_system := Runtime_System_Definition{id = "reader", phase = .Update, reads = reads_marker[:]}
	component_fields := [1]Runtime_Component_Field_Value{{name = "value", value = runtime_component_value_int(1)}}
	testing.expect_value(t, runtime_deferred_queue_add_component(&buffer, read_only_system, entity, "marker", component_fields[:]), Runtime_Error.Access_Denied)
	testing.expect_value(t, runtime_deferred_queue_remove_component(&buffer, read_only_system, entity, "marker"), Runtime_Error.Access_Denied)
}

@(test)
test_runtime_deferred_discard_rolls_back_immediate_spawns :: proc(t: ^testing.T) {
	world := runtime_world_init()
	defer runtime_world_free(&world)
	buffer := Runtime_Deferred_Command_Buffer{}
	defer runtime_deferred_command_buffer_free(&buffer)

	first, first_err := runtime_world_create_entity(&world, "first", "First")
	testing.expect_value(t, first_err, Runtime_Error.None)
	second, second_err := runtime_world_create_entity(&world, "second", "Second")
	testing.expect_value(t, second_err, Runtime_Error.None)
	testing.expect_value(t, runtime_deferred_record_immediate_spawn(&buffer, first), Runtime_Error.None)
	testing.expect_value(t, runtime_deferred_record_immediate_spawn(&buffer, second), Runtime_Error.None)
	testing.expect_value(t, runtime_world_entity_count(world), 2)

	runtime_deferred_discard(&buffer, &world)
	testing.expect_value(t, runtime_world_entity_count(world), 0)
	_, first_found := runtime_world_find_entity_by_id(world, "first")
	testing.expect_value(t, first_found, false)
	_, second_found := runtime_world_find_entity_by_id(world, "second")
	testing.expect_value(t, second_found, false)
}

@(test)
test_runtime_deferred_flush_rejects_mutation_after_despawn_and_rolls_back_spawns :: proc(t: ^testing.T) {
	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)
	world := runtime_world_init()
	defer runtime_world_free(&world)
	buffer := Runtime_Deferred_Command_Buffer{}
	defer runtime_deferred_command_buffer_free(&buffer)

	marker_fields := [1]Runtime_Component_Field_Definition{{name = "value", value_type = .Int}}
	testing.expect_value(t, runtime_register_project_component(&registry, Runtime_Component_Definition{id = "marker", version = 1, fields = marker_fields[:]}), Runtime_Error.None)
	writes_marker := [1]string{"marker"}
	system := Runtime_System_Definition{id = "bad_flush", phase = .Startup, writes = writes_marker[:]}

	entity, entity_err := runtime_world_create_entity(&world, "rolled-back", "Rolled Back")
	testing.expect_value(t, entity_err, Runtime_Error.None)
	testing.expect_value(t, runtime_deferred_record_immediate_spawn(&buffer, entity), Runtime_Error.None)
	testing.expect_value(t, runtime_deferred_queue_despawn_entity(&buffer, world, system, entity), Runtime_Error.None)
	component_fields := [1]Runtime_Component_Field_Value{{name = "value", value = runtime_component_value_int(3)}}
	testing.expect_value(t, runtime_deferred_queue_add_component(&buffer, system, entity, "marker", component_fields[:]), Runtime_Error.None)

	testing.expect_value(t, runtime_deferred_flush(&buffer, &world, registry), Runtime_Error.Invalid_Structural_Command)
	testing.expect_value(t, runtime_world_entity_count(world), 0)
	testing.expect_value(t, len(buffer.commands), 0)
	testing.expect_value(t, len(buffer.immediate_spawns), 0)
}

@(test)
test_runtime_deferred_despawn_requires_write_access_to_all_components :: proc(t: ^testing.T) {
	registry := Runtime_Component_Registry{}
	defer runtime_registry_free(&registry)
	world := runtime_world_init()
	defer runtime_world_free(&world)
	buffer := Runtime_Deferred_Command_Buffer{}
	defer runtime_deferred_command_buffer_free(&buffer)

	testing.expect_value(t, runtime_register_project_component(&registry, Runtime_Component_Definition{id = "marker", version = 1}), Runtime_Error.None)
	testing.expect_value(t, runtime_register_project_component(&registry, Runtime_Component_Definition{id = "tag", version = 1}), Runtime_Error.None)
	entity, entity_err := runtime_world_create_entity(&world, "doomed", "Doomed")
	testing.expect_value(t, entity_err, Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component(&world, entity, "marker", []Runtime_Component_Field_Value{}), Runtime_Error.None)
	testing.expect_value(t, runtime_world_set_component(&world, entity, "tag", []Runtime_Component_Field_Value{}), Runtime_Error.None)

	writes_marker := [1]string{"marker"}
	limited_system := Runtime_System_Definition{id = "limited", phase = .Update, writes = writes_marker[:]}
	testing.expect_value(t, runtime_deferred_queue_despawn_entity(&buffer, world, limited_system, entity), Runtime_Error.Access_Denied)

	writes_all := [2]string{"marker", "tag"}
	full_system := Runtime_System_Definition{id = "full", phase = .Update, writes = writes_all[:]}
	testing.expect_value(t, runtime_deferred_queue_despawn_entity(&buffer, world, full_system, entity), Runtime_Error.None)
	testing.expect_value(t, runtime_deferred_flush(&buffer, &world, registry), Runtime_Error.None)
	testing.expect_value(t, runtime_world_entity_count(world), 0)
}
