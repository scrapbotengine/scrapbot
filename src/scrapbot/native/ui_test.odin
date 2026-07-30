package native

import ecs "../ecs"
import api "../extension_api"
import resources "../resources"
import shared "../shared"
import c "core:c"
import "core:testing"

@(test)
test_native_ui_theme_api_resolves_shared_recipes_into_abi_payloads :: proc(t: ^testing.T) {
	ctx := api.System_Context{}
	recipes := [?]api.UI_Theme_Recipe{.Primary_Button, .Checkbox}
	payloads: [9]api.UI_Component_Payload
	payload_count: c.int
	err := system_resolve_ui_theme(
		&ctx,
		.Reduced_Dark,
		raw_data(recipes[:]),
		c.int(len(recipes)),
		raw_data(payloads[:]),
		c.int(len(payloads)),
		&payload_count,
	)
	testing.expect(t, err == nil)
	testing.expect(t, payload_count == 3)
	theme := shared.ui_theme_reduced_dark()
	testing.expect(t, string(payloads[0].component) == "scrapbot.ui_layout")
	testing.expect(t, payloads[0].layout.size == api.Vec2{80, theme.metrics.control_height})
	testing.expect(
		t,
		payloads[0].layout.background == api_vec4_from_shared(theme.palette.accent_soft),
	)
	testing.expect(t, string(payloads[1].component) == "scrapbot.ui_button")
	testing.expect(t, payloads[1].button.color == api_vec4_from_shared(theme.palette.accent_text))
	testing.expect(t, string(payloads[2].component) == "scrapbot.ui_checkbox")
	testing.expect(
		t,
		payloads[2].checkbox.border_color == api_vec4_from_shared(theme.palette.border_strong),
	)
}

@(test)
test_native_ui_theme_api_composes_chrome_and_semantic_frame_recipes :: proc(t: ^testing.T) {
	ctx := api.System_Context{}
	recipes := [?]api.UI_Theme_Recipe{.Chrome_Bar, .Warning_Frame}
	payloads: [1]api.UI_Component_Payload
	payload_count: c.int
	err := system_resolve_ui_theme(
		&ctx,
		.Reduced_Dark,
		raw_data(recipes[:]),
		c.int(len(recipes)),
		raw_data(payloads[:]),
		c.int(len(payloads)),
		&payload_count,
	)
	testing.expect(t, err == nil)
	testing.expect(t, payload_count == 1)
	theme := shared.ui_theme_reduced_dark()
	testing.expect(t, string(payloads[0].component) == "scrapbot.ui_layout")
	testing.expect(t, payloads[0].layout.background == api_vec4_from_shared(theme.palette.region))
	testing.expect(
		t,
		payloads[0].layout.border_color == api_vec4_from_shared(theme.palette.warning_soft),
	)
	testing.expect_value(t, payloads[0].layout.border_width, f32(2))
}

@(test)
test_native_ui_theme_api_resolves_list_highlight_radius :: proc(t: ^testing.T) {
	ctx := api.System_Context{}
	recipes := [?]api.UI_Theme_Recipe{.List}
	payloads: [1]api.UI_Component_Payload
	payload_count: c.int
	err := system_resolve_ui_theme(
		&ctx,
		.Reduced_Dark,
		raw_data(recipes[:]),
		c.int(len(recipes)),
		raw_data(payloads[:]),
		c.int(len(payloads)),
		&payload_count,
	)
	testing.expect(t, err == nil)
	testing.expect(t, payload_count == 1)
	theme := shared.ui_theme_reduced_dark()
	testing.expect(t, string(payloads[0].component) == "scrapbot.ui_list")
	testing.expect(t, payloads[0].list.highlight_corner_radius == theme.metrics.radius_small)
}

@(test)
test_native_ui_theme_api_resolves_project_theme_uuid_from_runtime_registry :: proc(t: ^testing.T) {
	registry: resources.Registry
	resources.init_registry(&registry)
	defer resources.destroy_registry(&registry)
	id, _ := shared.resource_uuid_parse("71c20000-0000-4000-8000-000000000001")
	theme := shared.ui_theme_reduced_dark()
	theme.palette.control = {0.04, 0.64, 1.25, 1}
	theme.font = "Inter"
	declaration := shared.Project_Resource {
		id = id,
		kind = .UI_Theme,
		name = "Neon",
		source = "neon.resource.toml",
		ui_theme = {theme = theme},
	}
	testing.expect(
		t,
		resources.register_project_ui_themes(&registry, []shared.Project_Resource{declaration}) ==
		"",
	)
	step := Step_Context {
		resources = &registry,
	}
	ctx := api.System_Context {
		host = &step,
	}
	recipes := [?]api.UI_Theme_Recipe{.Standard_Button}
	payloads: [2]api.UI_Component_Payload
	payload_count: c.int
	err := system_resolve_project_ui_theme(
		&ctx,
		api_resource_uuid_from_shared(id),
		raw_data(recipes[:]),
		c.int(len(recipes)),
		raw_data(payloads[:]),
		c.int(len(payloads)),
		&payload_count,
	)
	testing.expect(t, err == nil)
	testing.expect_value(t, payload_count, c.int(2))
	testing.expect(t, payloads[0].layout.background == api_vec4_from_shared(theme.palette.control))
}

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
	layout.basis = 96
	layout.grow = 2
	layout.shrink = 3
	layout.horizontal_alignment = .Center
	layout.vertical_alignment = .End
	layout.tree_item = true
	layout.tree_parent = shared.entity_uuid_from_engine_name("Native Tree Parent")
	layout.tree_order = 6
	layout.tree_collapsed = true
	layout.popup = true
	layout.popup_anchor = shared.entity_uuid_from_engine_name("Native Popup Anchor")
	layout.popup_open = true
	layout.popup_close_on_selection = true
	layout.popup_gap = 4
	layout.popup_min_width = 180
	layout.popup_max_width = 320
	layout.popup_max_height = 160
	layout.popup_viewport_margin = 6
	testing.expect(t, ecs.set_ui_layout(&world, entity_index, layout))
	canvas := shared.ui_canvas_default()
	canvas.reference_size = {1600, 900}
	canvas.scale_mode = .Expand
	canvas.safe_area = {12, 20, 28, 36}
	canvas.min_scale = 0.5
	canvas.max_scale = 3
	testing.expect(t, ecs.set_ui_canvas(&world, entity_index, canvas))
	button := shared.ui_button_default()
	button.text = "Popup"
	button.popup = world.entities[entity_index].uuid
	testing.expect(t, ecs.set_ui_button(&world, entity_index, button))
	text := shared.ui_text_default()
	text.text = "Before"
	text.font = "Inter"
	text.alignment = .Right
	text.wrap = true
	text.line_height = 22
	testing.expect(t, ecs.set_ui_text(&world, entity_index, text))
	stack := shared.ui_stack_default()
	stack.gap = 7
	stack.wrap = true
	stack.line_gap = 9
	testing.expect(t, ecs.set_ui_hstack(&world, entity_index, stack))
	icon_component := shared.ui_icon_default()
	icon_component.icon_set = shared.builtin_icon_set_uuid()
	icon_component.icon = "play"
	testing.expect(t, ecs.set_ui_icon(&world, entity_index, icon_component))
	state := ecs.ensure_ui_state(&world, entity_index)
	state.hovered = true
	state.activation_revision = 9
	state.drop_placement = .After
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
	input.icon_set = shared.builtin_icon_set_uuid()
	input.icon = "magnifying-glass"
	input.icon_position = .Trailing
	input.icon_color = {0.4, 0.5, 0.6, 1}
	input.icon_size = 14
	input.icon_gap = 5
	input.icon_inset = 1
	input.prefix_width = 13
	input.number = 42
	input.step = 0.5
	input.minimum = 0
	input.maximum = 100
	input.numeric = true
	input.has_minimum = true
	input.has_maximum = true
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
	color_picker := shared.ui_color_picker_default()
	color_picker.value = {4, 2, 1, 0.5}
	color_picker.exposure = 2
	testing.expect(t, ecs.set_ui_color_picker(&world, entity_index, color_picker))
	table := shared.ui_table_default()
	table.columns = 2
	table.proportional_columns = true
	table.resizable_columns = true
	table.min_column_width = 56
	testing.expect(t, ecs.set_ui_table(&world, entity_index, table))
	panel := shared.ui_panel_default()
	panel.title = "Native Panel"
	panel.collapsible = true
	testing.expect(t, ecs.set_ui_panel(&world, entity_index, panel))
	dock_space := shared.ui_dock_space_default()
	dock_space.active = world.entities[entity_index].uuid
	dock_space.font = "Inter"
	dock_space.tab_height = 38
	dock_space.tab_active_color = {1.5, 1.2, 1, 1}
	testing.expect(t, ecs.set_ui_dock_space(&world, entity_index, dock_space))
	dock_item := shared.ui_dock_item_default()
	dock_item.title = "NATIVE"
	dock_item.movable = false
	testing.expect(t, ecs.set_ui_dock_item(&world, entity_index, dock_item))
	list := shared.ui_list_default()
	list.filter_input = world.entities[entity_index].uuid
	list.highlight_corner_radius = 7
	list.tree_enabled = true
	list.tree_indent = 19
	list.virtualized = true
	list.item_height = 28
	list.overscan = 4
	testing.expect(t, ecs.set_ui_list(&world, entity_index, list))
	action := shared.UI_Action_Component {
		action = "native.launch",
		payload = "alpha",
	}
	testing.expect(t, ecs.set_ui_action(&world, entity_index, action))

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
	testing.expect(t, text_payload.text.wrap != 0)
	testing.expect(t, text_payload.text.line_height == 22)

	stack_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_hstack", &stack_payload) != 0,
	)
	testing.expect(t, stack_payload.stack.gap == 7)
	testing.expect(t, stack_payload.stack.wrap != 0)
	testing.expect(t, stack_payload.stack.line_gap == 9)

	icon_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_icon", &icon_payload) != 0,
	)
	icon_symbol, icon_symbol_ok := api_ui_payload_icon(&icon_payload)
	testing.expect(t, icon_symbol_ok && icon_symbol == "play")
	icon_text, _, icon_text_ok := api_ui_payload_strings(&icon_payload)
	testing.expect(t, icon_text_ok && icon_text == "")

	state_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_state", &state_payload) != 0,
	)
	testing.expect(t, state_payload.state.hovered != 0)
	testing.expect(t, state_payload.state.activation_revision == 9)
	testing.expect(t, state_payload.state.drop_placement == .After)
	testing.expect(t, system_set_ui_component(&ctx, entity, &state_payload) != nil)

	input_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_input", &input_payload) != 0,
	)
	prefix, prefix_ok := api_ui_payload_prefix(&input_payload)
	testing.expect(t, prefix_ok && prefix == "X")
	icon, icon_ok := api_ui_payload_icon(&input_payload)
	testing.expect(t, icon_ok && icon == "magnifying-glass")
	testing.expect(t, input_payload.input.icon_position == .Trailing)
	testing.expect(t, input_payload.input.icon_size == 14)
	testing.expect(t, input_payload.input.prefix_width == 13)
	testing.expect(t, input_payload.input.number == 42 && input_payload.input.step == 0.5)
	testing.expect(t, input_payload.input.numeric != 0)
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
	color_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_color_picker", &color_payload) != 0,
	)
	testing.expect(t, color_payload.color_picker.value.x == 4)
	testing.expect(t, color_payload.color_picker.exposure == 2)
	testing.expect(t, color_payload.color_picker.hdr != 0)

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
	testing.expect(t, layout_payload.layout.basis == 96)
	testing.expect(t, layout_payload.layout.grow == 2)
	testing.expect(t, layout_payload.layout.shrink == 3)
	testing.expect(t, layout_payload.layout.horizontal_alignment == .Center)
	testing.expect(t, layout_payload.layout.vertical_alignment == .End)
	testing.expect(t, layout_payload.layout.tree_item != 0)
	testing.expect(
		t,
		layout_payload.layout.tree_parent == api_uuid_from_shared(layout.tree_parent),
	)
	testing.expect(t, layout_payload.layout.tree_order == 6)
	testing.expect(t, layout_payload.layout.tree_collapsed != 0)
	testing.expect(t, layout_payload.layout.popup != 0)
	testing.expect(
		t,
		layout_payload.layout.popup_anchor == api_uuid_from_shared(layout.popup_anchor),
	)
	testing.expect(t, layout_payload.layout.popup_open != 0)
	testing.expect(t, layout_payload.layout.popup_close_on_selection != 0)
	testing.expect(t, layout_payload.layout.popup_gap == 4)
	canvas_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_canvas", &canvas_payload) != 0,
	)
	testing.expect(t, canvas_payload.canvas.reference_size == (api.Vec2{1600, 900}))
	testing.expect(t, canvas_payload.canvas.scale_mode == .Expand)
	testing.expect(t, canvas_payload.canvas.horizontal_alignment == .Center)
	testing.expect(t, canvas_payload.canvas.safe_area == (api.Vec4{12, 20, 28, 36}))
	testing.expect(t, canvas_payload.canvas.min_scale == 0.5)
	testing.expect(t, canvas_payload.canvas.max_scale == 3)
	testing.expect(t, layout_payload.layout.popup_min_width == 180)
	testing.expect(t, layout_payload.layout.popup_max_width == 320)
	testing.expect(t, layout_payload.layout.popup_max_height == 160)
	testing.expect(t, layout_payload.layout.popup_viewport_margin == 6)
	button_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_button", &button_payload) != 0,
	)
	testing.expect(
		t,
		button_payload.button.popup == api_uuid_from_shared(world.entities[entity_index].uuid),
	)
	list_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_list", &list_payload) != 0,
	)
	testing.expect(t, list_payload.list.tree_enabled != 0)
	testing.expect(t, list_payload.list.highlight_corner_radius == 7)
	testing.expect(t, list_payload.list.tree_indent == 19)
	testing.expect(
		t,
		list_payload.list.filter_input == api_uuid_from_shared(world.entities[entity_index].uuid),
	)
	testing.expect(t, list_payload.list.virtualized != 0)
	testing.expect(t, list_payload.list.item_height == 28)
	testing.expect(t, list_payload.list.overscan == 4)
	table_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_table", &table_payload) != 0,
	)
	testing.expect(t, table_payload.table.columns == 2)
	testing.expect(t, table_payload.table.proportional_columns != 0)
	testing.expect(t, table_payload.table.resizable_columns != 0)
	testing.expect(t, table_payload.table.min_column_width == 56)
	panel_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_panel", &panel_payload) != 0,
	)
	testing.expect(t, api_payload_text(&panel_payload) == "Native Panel")
	testing.expect(t, panel_payload.panel.collapsible != 0)
	dock_space_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_dock_space", &dock_space_payload) != 0,
	)
	_, dock_font, dock_space_strings_ok := api_ui_payload_dock_strings(&dock_space_payload)
	testing.expect(t, dock_space_strings_ok && dock_font == "Inter")
	testing.expect(t, dock_space_payload.dock_space.tab_height == 38)
	testing.expect(t, dock_space_payload.dock_space.tab_active_color.x == 1.5)
	dock_item_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_dock_item", &dock_item_payload) != 0,
	)
	dock_title, _, dock_item_strings_ok := api_ui_payload_dock_strings(&dock_item_payload)
	testing.expect(t, dock_item_strings_ok && dock_title == "NATIVE")
	testing.expect(t, dock_item_payload.dock_item.movable == 0)
	action_payload: api.UI_Component_Payload
	testing.expect(
		t,
		system_get_ui_component(&ctx, entity, "scrapbot.ui_action", &action_payload) != 0,
	)
	native_action, native_action_payload, action_ok := api_ui_payload_action(&action_payload)
	testing.expect(t, action_ok)
	testing.expect(t, native_action == "native.launch" && native_action_payload == "alpha")
	testing.expect(t, api_ui_payload_set_action(&action_payload, "native.commit", "beta"))
	testing.expect(t, system_set_ui_component(&ctx, entity, &action_payload) == nil)
	panel_payload.panel.collapsed = 1
	testing.expect(t, system_set_ui_component(&ctx, entity, &panel_payload) == nil)
	list_payload.list.highlight_corner_radius = 9
	testing.expect(t, system_set_ui_component(&ctx, entity, &list_payload) == nil)
	table_payload.table.min_column_width = 72
	testing.expect(t, system_set_ui_component(&ctx, entity, &table_payload) == nil)
	dock_space_payload.dock_space.tab_height = 42
	testing.expect(t, system_set_ui_component(&ctx, entity, &dock_space_payload) == nil)
	testing.expect(t, api_ui_payload_set_dock_strings(&dock_item_payload, "UPDATED", ""))
	dock_item_payload.dock_item.movable = 1
	testing.expect(t, system_set_ui_component(&ctx, entity, &dock_item_payload) == nil)
	testing.expect(t, ecs.apply_commands(&world, &commands) == "")
	stored_table := world.ui_tables[world.entities[entity_index].ui_table_index]
	testing.expect(t, stored_table.min_column_width == 72)
	stored_panel := world.ui_panels[world.entities[entity_index].ui_panel_index]
	testing.expect(t, stored_panel.collapsed)
	stored_list := world.ui_lists[world.entities[entity_index].ui_list_index]
	testing.expect(t, stored_list.highlight_corner_radius == 9)
	stored_dock_space := world.ui_dock_spaces[world.entities[entity_index].ui_dock_space_index]
	testing.expect(t, stored_dock_space.tab_height == 42)
	testing.expect(t, stored_dock_space.font == "Inter")
	stored_dock_item := world.ui_dock_items[world.entities[entity_index].ui_dock_item_index]
	testing.expect(t, stored_dock_item.title == "UPDATED")
	testing.expect(t, stored_dock_item.movable)
	stored_action := world.ui_actions[world.entities[entity_index].ui_action_index]
	testing.expect(t, stored_action.action == "native.commit" && stored_action.payload == "beta")

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

@(test)
test_native_ui_events_filter_editor_events_and_preserve_cursor_metadata :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	entity_index, created := ecs.create_world_entity(&world, "Native Event")
	testing.expect(t, created)
	entity_uuid := world.entities[entity_index].uuid
	ecs.append_ui_event(
		&world,
		{
			kind = .Submitted,
			origin = .Scene,
			entity = entity_uuid,
			action_entity = entity_uuid,
			action = "native.submit",
			payload = "gamma",
			position = {9, 11},
		},
	)
	ecs.append_ui_event(
		&world,
		{kind = .Activated, origin = .Editor, entity = entity_uuid, action = "editor.private"},
	)
	system: Native_System
	step := Step_Context {
		world = &world,
		system = &system,
	}
	ctx := api.System_Context {
		host = &step,
	}
	events: [api.MAX_UI_EVENTS]api.UI_Event
	event_count: c.int
	latest, oldest: u64
	overflowed: c.int
	err := system_ui_events(
		&ctx,
		0,
		raw_data(events[:]),
		c.int(len(events)),
		&event_count,
		&latest,
		&oldest,
		&overflowed,
	)
	testing.expect(t, err == nil)
	testing.expect(t, event_count == 1)
	testing.expect(t, latest == 2 && oldest == 1 && overflowed == 0)
	testing.expect(t, events[0].kind == .Submitted)
	testing.expect(t, events[0].entity == api_uuid_from_shared(entity_uuid))
	testing.expect(t, events[0].position == api.Vec2{9, 11})
	testing.expect(
		t,
		string(events[0].action_bytes[:int(events[0].action_len)]) == "native.submit",
	)
	testing.expect(t, string(events[0].payload_bytes[:int(events[0].payload_len)]) == "gamma")
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
