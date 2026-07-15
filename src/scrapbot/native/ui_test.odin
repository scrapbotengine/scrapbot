package native

import ecs "../ecs"
import api "../extension_api"
import shared "../shared"
import c "core:c"
import "core:testing"

@(test)
test_native_ui_api_reads_defers_updates_removes_and_spawns_shared_components :: proc(
	t: ^testing.T,
) {
	world: shared.World
	defer ecs.destroy_world(&world)
	entity_index, created := ecs.create_world_entity(&world, "Native UI")
	testing.expect(t, created)
	layout := shared.ui_layout_default()
	layout.size = {240, 40}
	layout.padding = {4, 8, 4, 8}
	layout.corner_radius = 7
	layout.min_size = {120, 24}
	layout.fill_width = true
	layout.fit_content_height = true
	layout.fixed_in_fill = true
	testing.expect(t, ecs.set_ui_layout(&world, entity_index, layout))
	text := shared.ui_text_default()
	text.text = "Before"
	text.font = "Inter"
	text.alignment = .Right
	testing.expect(t, ecs.set_ui_text(&world, entity_index, text))
	state := ecs.ensure_ui_state(&world, entity_index)
	state.hovered = true
	state.activation_revision = 9
	progress := shared.ui_progress_default()
	progress.value = 2.5
	progress.maximum = 10
	progress.fill_color = {0.1, 0.8, 0.6, 1}
	progress.inset = {3, 4, 5, 6}
	progress.corner_radius = 2
	progress.right_to_left = true
	testing.expect(t, ecs.set_ui_progress(&world, entity_index, progress))
	scroll := shared.ui_scroll_area_default()
	scroll.scrollbar_width = 5
	scroll.scrollbar_corner_radius = 0
	scroll.scrollbar_thumb_color = {0.7, 0.8, 0.9, 1}
	testing.expect(t, ecs.set_ui_scroll_area(&world, entity_index, scroll))
	input := shared.ui_input_default()
	input.text = "42"
	input.font = "Inter"
	input.prefix = "X"
	input.prefix_width = 13
	input.number = 42
	input.step = 0.5
	input.minimum = 0
	input.maximum = 100
	input.numeric = true
	input.has_minimum = true
	input.has_maximum = true
	input.scrubbable = true
	input.prefix_gap = 4
	input.prefix_corner_radius = 0
	input.invalid_border_width = 3
	input.caret_width = 2
	testing.expect(t, ecs.set_ui_input(&world, entity_index, input))
	checkbox := shared.ui_checkbox_default()
	checkbox.corner_radius = 0
	checkbox.border_width = 2
	checkbox.check_inset = 5
	checkbox.check_corner_radius = 0
	testing.expect(t, ecs.set_ui_checkbox(&world, entity_index, checkbox))
	table := shared.ui_table_default()
	table.columns = 2
	table.proportional_columns = true
	table.resizable_columns = true
	table.min_column_width = 56
	testing.expect(t, ecs.set_ui_table(&world, entity_index, table))

	commands: ecs.Command_Buffer
	ecs.init_command_buffer(&commands)
	defer ecs.destroy_command_buffer(&commands)
	system: Native_System
	step := Step_Context {
		world = &world,
		system = &system,
		commands = &commands,
	}
	ctx := api.System_Context {
		host = &step,
	}
	entity := api.Entity {
		index = c.int(entity_index),
		generation = world.entities[entity_index].id.generation,
	}

	text_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_text", &text_payload) != 0,
	)
	testing.expect(t, api_payload_text(&text_payload) == "Before")
	testing.expect(t, api_payload_font(&text_payload) == "Inter")
	testing.expect(t, text_payload.text.size == 16)
	testing.expect(t, text_payload.text.alignment == .Right)

	state_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_state", &state_payload) != 0,
	)
	testing.expect(t, state_payload.state.hovered != 0)
	testing.expect(t, state_payload.state.activation_revision == 9)
	testing.expect(t, system_set_ui_component(&ctx, entity, &state_payload) != nil)

	input_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_input", &input_payload) != 0,
	)
	prefix, prefix_ok := api_ui_payload_prefix(&input_payload)
	testing.expect(t, prefix_ok && prefix == "X")
	testing.expect(t, input_payload.input.prefix_width == 13)
	testing.expect(t, input_payload.input.number == 42 && input_payload.input.step == 0.5)
	testing.expect(t, input_payload.input.numeric != 0 && input_payload.input.scrubbable != 0)
	testing.expect(t, input_payload.input.prefix_gap == 4)
	testing.expect(t, input_payload.input.prefix_corner_radius == 0)
	testing.expect(t, input_payload.input.invalid_border_width == 3)

	scroll_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_scroll_area", &scroll_payload) != 0,
	)
	testing.expect(t, scroll_payload.scroll_area.scrollbar_width == 5)
	testing.expect(t, scroll_payload.scroll_area.scrollbar_corner_radius == 0)
	checkbox_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_checkbox", &checkbox_payload) != 0,
	)
	testing.expect(t, checkbox_payload.checkbox.corner_radius == 0)
	testing.expect(t, checkbox_payload.checkbox.border_width == 2)

	progress_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_progress", &progress_payload) != 0,
	)
	testing.expect(t, progress_payload.progress.value == 2.5)
	testing.expect(t, progress_payload.progress.maximum == 10)
	testing.expect(t, progress_payload.progress.corner_radius == 2)
	testing.expect(t, progress_payload.progress.right_to_left != 0)
	layout_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_layout", &layout_payload) != 0,
	)
	testing.expect(t, layout_payload.layout.min_size == (api.Vec2{120, 24}))
	testing.expect(t, layout_payload.layout.fill_width != 0)
	testing.expect(t, layout_payload.layout.fit_content_height != 0)
	testing.expect(t, layout_payload.layout.fixed_in_fill != 0)
	table_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_table", &table_payload) != 0,
	)
	testing.expect(t, table_payload.table.columns == 2)
	testing.expect(t, table_payload.table.proportional_columns != 0)
	testing.expect(t, table_payload.table.resizable_columns != 0)
	testing.expect(t, table_payload.table.min_column_width == 56)
	table_payload.table.min_column_width = 72
	testing.expect(t, system_set_ui_component(&ctx, entity, &table_payload) == nil)
	testing.expect(t, ecs.apply_commands(&world, &commands) == "")
	stored_table := world.ui_tables[world.entities[entity_index].ui_table_index]
	testing.expect(t, stored_table.min_column_width == 72)

	text_payload.text.size = 20
	testing.expect(t, api_payload_set_strings(&text_payload, "After", "Project Font"))
	testing.expect(t, system_set_ui_component(&ctx, entity, &text_payload) == nil)
	testing.expect(t, commands.command_count == 1)
	stored_before := world.ui_texts[world.entities[entity_index].ui_text_index]
	testing.expect(t, stored_before.text == "Before")
	testing.expect(t, ecs.apply_commands(&world, &commands) == "")
	stored_after := world.ui_texts[world.entities[entity_index].ui_text_index]
	testing.expect(t, stored_after.text == "After")
	testing.expect(t, stored_after.font == "Project Font")
	testing.expect(t, stored_after.size == 20)
	testing.expect(t, stored_after.alignment == .Right)

	testing.expect(t, system_remove_component(&ctx, entity, "scrapbot.ui_text") == nil)
	testing.expect(t, world.entities[entity_index].ui_text_index >= 0)
	testing.expect(t, ecs.apply_commands(&world, &commands) == "")
	testing.expect(t, world.entities[entity_index].ui_text_index < 0)

	spawn_layout: api.UI_Component_Payload
	spawn_layout.component = "scrapbot.ui_layout"
	spawn_layout.layout.size = {320, 180}
	spawn_layout.layout.corner_radius = 12
	spawn_button: api.UI_Component_Payload
	spawn_button.component = "scrapbot.ui_button"
	spawn_button.button.color = {0.8, 0.9, 1, 1}
	spawn_button.button.size = 18
	spawn_button.button.alignment = .Right
	testing.expect(t, api_payload_set_strings(&spawn_button, "Native Spawn", "Inter"))
	spawn_ui := [?]api.UI_Component_Payload{spawn_layout, spawn_button}
	spawn_uuid: api.UUID
	options := api.Spawn_Options {
		name = "Native Spawned UI",
		ui_components = raw_data(spawn_ui[:]),
		ui_component_count = c.int(len(spawn_ui)),
		out_uuid = &spawn_uuid,
	}
	testing.expect(t, system_spawn(&ctx, &options) == nil)
	testing.expect(t, spawn_uuid != (api.UUID{}))
	testing.expect(t, ecs.apply_commands(&world, &commands) == "")
	spawned_index, found := ecs.entity_index_by_uuid(&world, shared_uuid_from_api(spawn_uuid))
	testing.expect(t, found)
	if found {
		spawned := world.entities[spawned_index]
		testing.expect(t, spawned.ui_layout_index >= 0)
		testing.expect(t, spawned.ui_button_index >= 0)
		testing.expect(t, world.ui_layouts[spawned.ui_layout_index].corner_radius == 12)
		testing.expect(t, world.ui_buttons[spawned.ui_button_index].text == "Native Spawn")
		testing.expect(t, world.ui_buttons[spawned.ui_button_index].alignment == .Right)
	}
}

api_payload_set_strings :: proc(
	payload: ^api.UI_Component_Payload,
	text: string,
	font: string,
) -> bool {
	return api_ui_payload_set_strings(payload, text, font)
}

api_payload_text :: proc(payload: ^api.UI_Component_Payload) -> string {
	text, _, ok := api_ui_payload_strings(payload)
	return text if ok else ""
}

api_payload_font :: proc(payload: ^api.UI_Component_Payload) -> string {
	_, font, ok := api_ui_payload_strings(payload)
	return font if ok else ""
}
