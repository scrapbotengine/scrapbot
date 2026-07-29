package ecs

import shared "../shared"
import "core:strings"
import "core:testing"

@(test)
test_ui_input_icon_survives_authoring_snapshot_replacement :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)
	entity_index, created := create_world_entity(
		&world,
		"Search",
		shared.entity_uuid_from_engine_name("Search"),
	)
	testing.expect(t, created)
	input := shared.ui_input_default()
	input.icon_set = shared.builtin_icon_set_uuid()
	input.icon = "magnifying-glass"
	testing.expect(t, set_ui_input(&world, entity_index, input))

	snapshot, captured := capture_entity_snapshot(&world, entity_index)
	testing.expect(t, captured)
	defer destroy_entity_snapshot(&snapshot)
	testing.expect(t, snapshot.entity.ui_input.icon == "magnifying-glass")

	input.icon = "x"
	testing.expect(t, set_ui_input(&world, entity_index, input))
	testing.expect(t, snapshot.entity.ui_input.icon == "magnifying-glass")
}

@(test)
test_world_entity_and_ui_component_api_is_shared_and_updates_in_place :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)
	uuid := shared.entity_uuid_from_engine_name("Reusable UI")
	entity_index, created := create_world_entity(&world, "Reusable UI", uuid, .Runtime)
	testing.expect(t, created)
	testing.expect(t, entity_index == 0)
	testing.expect(t, world.entities[entity_index].origin == .Runtime)
	testing.expect(t, world.entities[entity_index].ui_layout_index == INVALID_COMPONENT_INDEX)

	duplicate_index, duplicate_created := create_world_entity(&world, "Duplicate", uuid)
	testing.expect(t, !duplicate_created)
	testing.expect(t, duplicate_index == INVALID_COMPONENT_INDEX)

	parent := shared.entity_uuid_from_engine_name("Parent")
	testing.expect(
		t,
		set_ui_layout(
			&world,
			entity_index,
			{
				parent = parent,
				size = {240, 40},
				padding = {4, 8, 4, 8},
				background = {0.01, 0.02, 0.03, 1},
				border_color = {0.1, 0.2, 0.3, 1},
				border_width = 1,
				corner_radius = 5,
			},
		),
	)
	viewport := shared.ui_viewport_default()
	viewport.resource, _ = shared.resource_uuid_parse("a6000000-0000-4000-8000-000000000099")
	testing.expect(t, set_ui_viewport(&world, entity_index, viewport))
	testing.expect(
		t,
		set_ui_scroll_area(&world, entity_index, {scroll_speed = 48, smoothness = 18}),
	)
	testing.expect(t, set_ui_panel(&world, entity_index, {title = "Panel", collapsible = true}))
	stack_index, stack_created := create_world_entity(&world, "Stack")
	testing.expect(t, stack_created)
	testing.expect(t, set_ui_layout(&world, stack_index, {size = {1, 1}}))
	testing.expect(t, set_ui_hstack(&world, stack_index, {gap = 6, fill = true}))
	list_index, list_created := create_world_entity(&world, "List")
	testing.expect(t, list_created)
	testing.expect(t, set_ui_layout(&world, list_index, {size = {1, 1}}))
	testing.expect(t, set_ui_list(&world, list_index, {gap = 2}))
	testing.expect(
		t,
		set_ui_progress(
			&world,
			entity_index,
			{value = 0.5, maximum = 1, fill_color = {0.1, 0.8, 0.6, 1}, corner_radius = 2},
		),
	)

	text_source, text_err := strings.clone("Initial")
	testing.expect(t, text_err == nil)
	testing.expect(
		t,
		set_ui_text(&world, entity_index, {text = text_source, color = {1, 1, 1, 1}, size = 12}),
	)
	delete(text_source)
	testing.expect(t, world.ui_texts[world.entities[entity_index].ui_text_index].text == "Initial")

	text_slot_count := len(world.ui_texts)
	testing.expect(
		t,
		set_ui_text(
			&world,
			entity_index,
			{text = "Replacement", color = {0.5, 0.5, 0.5, 1}, size = 12},
		),
	)
	testing.expect(t, len(world.ui_texts) == text_slot_count)
	testing.expect(t, set_ui_text_value(&world, entity_index, "Live value"))
	testing.expect(t, !set_ui_text_value(&world, entity_index, "Live value"))
	testing.expect(
		t,
		world.ui_texts[world.entities[entity_index].ui_text_index].text == "Live value",
	)

	testing.expect(t, set_ui_panel_title(&world, entity_index, "Renamed"))
	testing.expect(
		t,
		world.ui_panels[world.entities[entity_index].ui_panel_index].title == "Renamed",
	)
	testing.expect(t, set_ui_parent(&world, entity_index, {}))
	testing.expect(
		t,
		world.ui_layouts[world.entities[entity_index].ui_layout_index].parent ==
		(shared.Entity_UUID{}),
	)
	testing.expect(t, set_ui_hidden(&world, entity_index, true))
	testing.expect(t, world.ui_layouts[world.entities[entity_index].ui_layout_index].hidden)
	testing.expect(t, len(world.ui_dirty_entities) > 0)

	text_index := world.entities[entity_index].ui_text_index
	state_index := ensure_ui_state(&world, entity_index)
	testing.expect(t, state_index != nil)
	state_slot := world.entities[entity_index].ui_state_index
	testing.expect(t, remove_ui_component(&world, entity_index, "scrapbot.ui_text"))
	reused_text := shared.ui_text_default()
	reused_text.text = "Reused"
	testing.expect(t, set_ui_text(&world, entity_index, reused_text))
	testing.expect(t, world.entities[entity_index].ui_text_index == text_index)
	testing.expect(t, len(world.ui_texts) == text_slot_count)
	release_ui_state(&world, entity_index)
	testing.expect(t, ensure_ui_state(&world, entity_index) != nil)
	testing.expect(t, world.entities[entity_index].ui_state_index == state_slot)
}

@(test)
test_runtime_spawn_uses_shared_world_entity_creation_and_reuses_slots :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)
	spawn: Spawn_Command
	testing.expect(t, init_spawn_command(&spawn, "Runtime UI") == "")
	entity_index := spawn_entity(&world, &spawn)
	testing.expect(t, entity_index == 0)
	testing.expect(t, world.entities[entity_index].origin == .Runtime)
	first_uuid := world.entities[entity_index].uuid
	despawn_entity(&world, entity_index, world.entities[entity_index].id.generation)

	reused_index := spawn_entity(&world, &spawn)
	testing.expect(t, reused_index == entity_index)
	testing.expect(t, world.entities[reused_index].uuid != first_uuid)
	testing.expect(t, world.entities[reused_index].ui_layout_index == INVALID_COMPONENT_INDEX)
}

@(test)
test_ui_paint_revisions_are_domain_scoped_and_do_not_force_layout :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)
	project_index, project_created := create_world_entity(&world, "Project UI")
	editor_index, editor_created := create_world_entity(&world, "Editor UI")
	testing.expect(t, project_created && editor_created)
	world.entities[project_index].origin = .Scene
	world.entities[editor_index].origin = .Editor
	testing.expect(t, set_ui_layout(&world, project_index, {size = {100, 30}}))
	testing.expect(t, set_ui_layout(&world, editor_index, {size = {100, 30}}))
	project_layout_revision := world.ui_project_layout_revision
	editor_layout_revision := world.ui_editor_layout_revision
	project_paint_revision := world.ui_project_paint_revision
	editor_paint_revision := world.ui_editor_paint_revision

	project_layout := world.ui_layouts[world.entities[project_index].ui_layout_index]
	project_layout.background = {0.2, 0.3, 0.4, 1}
	testing.expect(t, set_ui_layout(&world, project_index, project_layout))
	testing.expect(t, world.ui_project_layout_revision == project_layout_revision)
	testing.expect(t, world.ui_project_paint_revision > project_paint_revision)
	testing.expect(t, world.ui_editor_layout_revision == editor_layout_revision)
	testing.expect(t, world.ui_editor_paint_revision == editor_paint_revision)

	project_paint_revision = world.ui_project_paint_revision
	testing.expect(t, set_ui_layout(&world, project_index, project_layout))
	testing.expect(t, world.ui_project_paint_revision == project_paint_revision)

	editor_layout := world.ui_layouts[world.entities[editor_index].ui_layout_index]
	editor_layout.size.x = 120
	testing.expect(t, set_ui_layout(&world, editor_index, editor_layout))
	testing.expect(t, world.ui_editor_layout_revision > editor_layout_revision)
	testing.expect(t, world.ui_editor_paint_revision > editor_paint_revision)
}

@(test)
test_ui_component_churn_reclaims_all_storage_slots :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)
	for cycle in 0 ..< 64 {
		entity_index, created := create_world_entity(&world, "Transient UI")
		testing.expect(t, created)
		testing.expect(t, set_ui_layout(&world, entity_index, {size = {100, 24}}))
		testing.expect(t, set_ui_hstack(&world, entity_index, {}))
		testing.expect(t, set_ui_vstack(&world, entity_index, {}))
		testing.expect(
			t,
			set_ui_scroll_area(&world, entity_index, shared.ui_scroll_area_default()),
		)
		testing.expect(t, set_ui_panel(&world, entity_index, {title = "Transient"}))
		testing.expect(t, set_ui_table(&world, entity_index, shared.ui_table_default()))
		testing.expect(t, set_ui_list(&world, entity_index, shared.ui_list_default()))
		testing.expect(t, set_ui_progress(&world, entity_index, shared.ui_progress_default()))
		testing.expect(t, set_ui_viewport(&world, entity_index, shared.ui_viewport_default()))
		text := shared.ui_text_default()
		text.text = "Transient"
		testing.expect(t, set_ui_text(&world, entity_index, text))
		button := shared.ui_button_default()
		button.text = "Transient"
		testing.expect(t, set_ui_button(&world, entity_index, button))
		testing.expect(t, set_ui_input(&world, entity_index, shared.ui_input_default()))
		testing.expect(t, set_ui_checkbox(&world, entity_index, shared.ui_checkbox_default()))
		testing.expect(
			t,
			set_ui_color_picker(&world, entity_index, shared.ui_color_picker_default()),
		)
		testing.expect(t, ensure_ui_state(&world, entity_index) != nil)
		despawn_entity(&world, entity_index, world.entities[entity_index].id.generation)
	}
	testing.expect(t, len(world.entities) == 1)
	testing.expect(t, len(world.ui_layouts) == 1)
	testing.expect(t, len(world.ui_hstacks) == 1)
	testing.expect(t, len(world.ui_vstacks) == 1)
	testing.expect(t, len(world.ui_scroll_areas) == 1)
	testing.expect(t, len(world.ui_panels) == 1)
	testing.expect(t, len(world.ui_tables) == 1)
	testing.expect(t, len(world.ui_lists) == 1)
	testing.expect(t, len(world.ui_progresses) == 1)
	testing.expect(t, len(world.ui_viewports) == 1)
	testing.expect(t, len(world.ui_states) == 1)
	testing.expect(t, len(world.ui_texts) == 1)
	testing.expect(t, len(world.ui_buttons) == 1)
	testing.expect(t, len(world.ui_inputs) == 1)
	testing.expect(t, len(world.ui_checkboxes) == 1)
	testing.expect(t, len(world.ui_color_pickers) == 1)
}
