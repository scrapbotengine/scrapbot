package script

import ecs "../ecs"
import project "../project"
import resources "../resources"
import shared "../shared"
import "core:testing"

@(test)
test_luau_exposes_and_queries_all_public_ui_container_and_input_components :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "aa000000-0000-4000-8000-000000000001"
name = "Inspector Field"
[entities.ui_layout]
size = [240, 32]
min_size = [120, 24]
fill_width = true
fit_content_height = true
fixed_in_fill = true
basis = 90
grow = 2
shrink = 3
horizontal_alignment = "center"
vertical_alignment = "end"
tree_item = true
tree_parent = "aa000000-0000-4000-8000-000000000002"
tree_order = 4
tree_collapsed = true
stack_order = 7
[entities.ui_canvas]
reference_size = [1600, 900]
scale_mode = "expand"
horizontal_alignment = "center"
vertical_alignment = "end"
safe_area = [20, 28, 36, 44]
min_scale = 0.5
max_scale = 3
[entities.ui_panel]
title = "FIELD"
disclosure_size = 9
disclosure_inset = 0
collapsible = true
movable = true
[entities.ui_scroll_area]
scrollbar_width = 5
scrollbar_corner_radius = 0
scrollbar_thumb_color = [0.7, 0.8, 0.9, 1]
[entities.ui_table]
columns = 1
proportional_columns = true
resizable_columns = true
min_column_width = 44
[entities.ui_input]
text = "42"
font = "Inter"
prefix = "X"
prefix_width = 13
prefix_gap = 4
prefix_corner_radius = 0
invalid_border_width = 3
caret_width = 2
number = 42
step = 0.5
minimum = 0
maximum = 100
numeric = true
has_minimum = true
has_maximum = true
read_only = true
[entities.ui_progress]
value = 2
maximum = 10
fill_color = [0.1, 0.8, 0.6, 1]
inset = [2, 3, 4, 5]
corner_radius = 2
right_to_left = true
[entities.ui_action]
action = "inspector.commit"
payload = "position"
drag_source = true
drop_target = true
drag_threshold = 7
drop_background = [0.2, 0.4, 0.6, 0.8]
[[entities]]
id = "aa000000-0000-4000-8000-000000000002"
name = "Checkbox"
[entities.ui_layout]
size = [32, 32]
popup = true
popup_anchor = "aa000000-0000-4000-8000-000000000001"
popup_open = true
popup_close_on_selection = true
popup_gap = 4
popup_min_width = 180
popup_max_width = 320
popup_max_height = 160
popup_viewport_margin = 6
[entities.ui_list]
filter_input = "aa000000-0000-4000-8000-000000000002"
highlight_corner_radius = 6
tree_enabled = true
tree_indent = 18
virtualized = true
item_height = 32
overscan = 3
[entities.ui_checkbox]
checked = true
corner_radius = 0
border_width = 2
check_inset = 5
check_corner_radius = 0
[[entities]]
id = "aa000000-0000-4000-8000-000000000003"
name = "HDR Color"
[entities.ui_layout]
size = [240, 180]
[entities.ui_color_picker]
value = [4, 2, 1, 0.5]
exposure = 2
maximum_exposure = 12
[[entities]]
id = "aa000000-0000-4000-8000-000000000004"
name = "Dock"
[entities.ui_layout]
size = [480, 320]
[entities.ui_dock_space]
active = "aa000000-0000-4000-8000-000000000005"
font = "Inter"
tab_height = 36
tab_connection_height = 5
tab_content_overlap = 3
tab_strip_background = [0.03, 0.04, 0.05, 1]
content_background = [0.11, 0.12, 0.13, 1]
content_corner_radius = 7
content_padding = [2, 3, 4, 5]
tab_active_color = [1.5, 1.2, 1, 1]
split_horizontal = true
split_ratio = 0.4
split_gap = 6
[[entities]]
id = "aa000000-0000-4000-8000-000000000005"
name = "Dock Item"
[entities.ui_layout]
parent = "aa000000-0000-4000-8000-000000000004"
size = [480, 284]
[entities.ui_dock_item]
title = "SCENE"
movable = false
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)

	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := ecs.ensure_ui_state(&world, 0)
	state.hovered = true
	state.activation_revision = 3
	state.valid = true
	state.submitted = true
	state.submit_revision = 4
	state.drop_placement = .Before
	progress_before_script := world.ui_progresses[world.entities[0].ui_progress_index]
	testing.expect(t, progress_before_script.value == 2 && progress_before_script.maximum == 10)
	testing.expect(
		t,
		progress_before_script.inset.x == 2 &&
		progress_before_script.inset.y == 3 &&
		progress_before_script.inset.z == 4 &&
		progress_before_script.inset.w == 5,
	)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
assert(scrapbot.ui_panel.id > 0)
assert(scrapbot.ui_dock_space.id > 0)
assert(scrapbot.ui_dock_item.id > 0)
assert(scrapbot.ui_canvas.id > 0)
assert(scrapbot.ui_scroll_area.id > 0)
assert(scrapbot.ui_table.id > 0)
assert(scrapbot.ui_input.id > 0)
assert(scrapbot.ui_progress.id > 0)
assert(scrapbot.ui_checkbox.id > 0)
assert(scrapbot.ui_color_picker.id > 0)
assert(scrapbot.ui_action.id > 0)
assert(scrapbot.ui_state.id > 0)

scrapbot.system(function()
	local count = 0
	scrapbot.query(scrapbot.ui_layout, scrapbot.ui_panel, scrapbot.ui_table):each(function(entity, layout, panel, table)
		assert(layout.size.x == 240 and layout.size.y == 32)
		assert(layout.min_size.x == 120 and layout.min_size.y == 24)
		assert(layout.fill_width == true)
		assert(layout.fit_content_height == true)
		assert(layout.fixed_in_fill == true)
		assert(layout.basis == 90 and layout.grow == 2 and layout.shrink == 3)
		assert(layout.horizontal_alignment == "center")
		assert(layout.vertical_alignment == "end")
		assert(layout.tree_item == true)
		assert(layout.tree_parent == "aa000000-0000-4000-8000-000000000002")
		assert(layout.tree_order == 4)
		assert(layout.tree_collapsed == true)
		assert(layout.stack_order == 7)
		assert(layout.hidden == false)
		assert(panel.title == "FIELD")
		assert(panel.disclosure_size == 9 and panel.disclosure_inset == 0)
		assert(panel.collapsible == true)
		assert(panel.collapsed == false)
		assert(panel.movable == true)
		assert(table.columns == 1)
		assert(table.proportional_columns == true)
		assert(table.resizable_columns == true)
		assert(table.min_column_width == 44)
		scrapbot.add_component(entity, scrapbot.ui_table, {min_column_width = 60})
		scrapbot.add_component(entity, scrapbot.ui_panel, {collapsed = true})
		scrapbot.add_component(entity, scrapbot.ui_layout, {stack_order = 8})
		count += 1
	end)
	assert(count == 1)
	local dock_count = 0
	scrapbot.query(scrapbot.ui_dock_space):each(function(entity, dock)
		assert(dock.active == "aa000000-0000-4000-8000-000000000005")
		assert(dock.font == "Inter" and dock.tab_height == 36)
		assert(dock.tab_connection_height == 5)
		assert(dock.tab_content_overlap == 3)
		assert(math.abs(dock.tab_strip_background.z - 0.05) < 0.0001)
		assert(math.abs(dock.content_background.x - 0.11) < 0.0001)
		assert(dock.content_corner_radius == 7)
		assert(dock.content_padding.w == 5)
		assert(math.abs(dock.tab_active_color.x - 1.5) < 0.0001)
		assert(dock.split_horizontal == true)
		assert(math.abs(dock.split_ratio - 0.4) < 0.0001)
		assert(dock.split_gap == 6)
		scrapbot.add_component(entity, scrapbot.ui_dock_space, {
			tab_height = 40,
			tab_connection_height = 7,
			tab_content_overlap = 4,
			tab_strip_background = {0.04, 0.05, 0.06, 1},
			content_padding = {3, 3, 3, 3},
			draggable = false,
			split_vertical = true,
			split_min_size = 144,
		})
		dock_count += 1
	end)
	assert(dock_count == 1)
	local dock_item_count = 0
	scrapbot.query(scrapbot.ui_dock_item):each(function(entity, item)
		assert(item.title == "SCENE" and item.movable == false)
		scrapbot.add_component(entity, scrapbot.ui_dock_item, {
			title = "GAME",
			movable = true,
		})
		dock_item_count += 1
	end)
	assert(dock_item_count == 1)
	local canvas_count = 0
	scrapbot.query(scrapbot.ui_canvas):each(function(entity, canvas)
		assert(canvas.reference_size.x == 1600 and canvas.reference_size.y == 900)
		assert(canvas.scale_mode == "expand")
		assert(canvas.horizontal_alignment == "center")
		assert(canvas.vertical_alignment == "end")
		assert(canvas.safe_area.x == 20 and canvas.safe_area.w == 44)
		assert(canvas.min_scale == 0.5 and canvas.max_scale == 3)
		scrapbot.add_component(entity, scrapbot.ui_canvas, {
			scale_mode = "fit",
			safe_area = {x = 24, y = 32, z = 40, w = 48},
		})
		canvas_count += 1
	end)
	assert(canvas_count == 1)
	scrapbot.query(scrapbot.ui_layout, scrapbot.ui_list):each(function(entity, layout, list)
		assert(layout.popup == true)
		assert(layout.popup_anchor == "aa000000-0000-4000-8000-000000000001")
		assert(layout.popup_open == true and layout.popup_close_on_selection == true)
		assert(layout.popup_gap == 4 and layout.popup_min_width == 180)
		assert(layout.popup_max_width == 320 and layout.popup_max_height == 160)
		assert(layout.popup_viewport_margin == 6)
		assert(list.tree_enabled == true and list.tree_indent == 18)
		assert(list.filter_input == "aa000000-0000-4000-8000-000000000002")
		assert(list.highlight_corner_radius == 6)
		assert(list.virtualized == true and list.item_height == 32 and list.overscan == 3)
		scrapbot.add_component(entity, scrapbot.ui_list, {
			highlight_corner_radius = 9,
			tree_indent = 20,
			item_height = 36,
			overscan = 5,
		})
	end)
	scrapbot.query(scrapbot.ui_scroll_area):each(function(entity, scroll)
		assert(scroll.scrollbar_width == 5 and scroll.scrollbar_corner_radius == 0)
		assert(math.abs(scroll.scrollbar_thumb_color.x - 0.7) < 0.0001)
		scrapbot.add_component(entity, scrapbot.ui_scroll_area, {scrollbar_width = 6})
	end)
	local input_count = 0
	scrapbot.query(scrapbot.ui_input):each(function(_, input)
		assert(input.text == "42")
		assert(input.prefix == "X" and input.prefix_width == 13)
		assert(input.prefix_gap == 4 and input.prefix_corner_radius == 0)
		assert(input.invalid_border_width == 3 and input.caret_width == 2)
		assert(input.numeric == true and input.number == 42 and input.step == 0.5)
		assert(input.has_minimum == true and input.minimum == 0)
		assert(input.has_maximum == true and input.maximum == 100)
		assert(input.read_only == true)
		input_count += 1
	end)
	assert(input_count == 1)
	local progress_count = 0
	scrapbot.query(scrapbot.ui_progress):each(function(entity, progress)
		assert(progress.value == 2 and progress.maximum == 10)
		assert(math.abs(progress.fill_color.y - 0.8) < 0.0001)
		assert(progress.inset.w == 5)
		assert(progress.corner_radius == 2)
		assert(progress.right_to_left == true)
		scrapbot.add_component(entity, scrapbot.ui_progress, {value = 6})
		progress_count += 1
	end)
	assert(progress_count == 1)
	local action_count = 0
	scrapbot.query(scrapbot.ui_action):each(function(entity, action)
		assert(action.action == "inspector.commit" and action.payload == "position")
		assert(action.drag_source == true and action.drop_target == true)
		assert(action.drag_threshold == 7 and math.abs(action.drop_background.w - 0.8) < 0.0001)
		scrapbot.add_component(entity, scrapbot.ui_action, {
			action = "inspector.apply",
			payload = "rotation",
			drag_source = false,
			drop_target = true,
			drag_threshold = 9,
			drop_background = {x = 0.1, y = 0.2, z = 0.3, w = 0.4},
		})
		action_count += 1
	end)
	assert(action_count == 1)
	local state_count = 0
	scrapbot.query(scrapbot.ui_state):each(function(_, state)
		assert(state.hovered == true)
		assert(state.activation_revision == 3)
		assert(state.valid == true)
		assert(state.submitted == true and state.submit_revision == 4)
		assert(state.drop_placement == "before")
		state_count += 1
	end)
	assert(state_count == 1)
	local checkbox_count = 0
	scrapbot.query(scrapbot.ui_checkbox):each(function(_, checkbox)
		assert(checkbox.checked == true)
		assert(checkbox.corner_radius == 0 and checkbox.border_width == 2)
		assert(checkbox.check_inset == 5 and checkbox.check_corner_radius == 0)
		assert(checkbox.read_only == false)
		checkbox_count += 1
	end)
	assert(checkbox_count == 1)
	local color_count = 0
	scrapbot.query(scrapbot.ui_color_picker):each(function(entity, color)
		assert(color.value.x == 4 and color.value.w == 0.5)
		assert(color.hdr == true and color.exposure == 2 and color.maximum_exposure == 12)
		scrapbot.add_component(entity, scrapbot.ui_color_picker, {value = {x = 8, y = 4, z = 2, w = 0.75}, exposure = 3})
		color_count += 1
	end)
	assert(color_count == 1)
	scrapbot.query(scrapbot.ui_input):each(function(entity)
		scrapbot.add_component(entity, scrapbot.ui_input, {text = "84"})
		scrapbot.add_component(entity, scrapbot.ui_input, {size = 18})
		scrapbot.add_component(entity, scrapbot.ui_input, {prefix = "Y", number = 84, icon_set = scrapbot.ui.builtin_icon_set, icon = "magnifying-glass", icon_position = "trailing", icon_color = {x = 0.4, y = 0.5, z = 0.6, w = 1}, icon_size = 14, icon_gap = 5, icon_inset = 1})
	end)
	scrapbot.query(scrapbot.ui_checkbox):each(function(entity)
		scrapbot.remove_component(entity, scrapbot.ui_checkbox)
		scrapbot.add_component(entity, scrapbot.ui_button, {text = "Toggle", popup = "aa000000-0000-4000-8000-000000000002", size = 14, alignment = "right", icon_set = scrapbot.ui.builtin_icon_set, icon = "x", icon_position = "trailing", icon_inset = 4, panel_action = true})
	end)
	local dock_root_id = scrapbot.spawn({
		name = "Runtime Dock",
		components = {
			["scrapbot.ui_layout"] = {size = {x = 320, y = 180}},
			["scrapbot.ui_dock_space"] = {tab_height = 34, font = "Inter"},
		},
	})
	scrapbot.spawn({
		name = "Runtime Dock Item",
		components = {
			["scrapbot.ui_layout"] = {parent = dock_root_id, size = {x = 320, y = 146}},
			["scrapbot.ui_dock_item"] = {title = "RUNTIME", movable = true},
		},
	})
	local root_id = scrapbot.spawn({
		name = "Runtime UI",
		components = {
			["scrapbot.ui_layout"] = {size = {x = 120, y = 24}, basis = 80, grow = 1, shrink = 2},
			["scrapbot.ui_hstack"] = {gap = 4, wrap = true, line_gap = 6},
			["scrapbot.ui_text"] = {text = "Spawned responsive text", wrap = true, line_height = 20},
		},
	})
	assert(type(root_id) == "string" and #root_id == 36)
	scrapbot.spawn({
		name = "Runtime UI Child",
		components = {
			["scrapbot.ui_layout"] = {parent = root_id, size = {x = 80, y = 20}},
			["scrapbot.ui_text"] = {text = "Child"},
		},
	})
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)
	step_err := step_runtime(&runtime, &world, 0)
	testing.expectf(t, step_err == "", "UI system step failed: %s", step_err)
	input := world.ui_inputs[world.entities[0].ui_input_index]
	testing.expect(t, input.text == "84" && input.size == 18)
	testing.expect(t, input.prefix == "Y" && input.number == 84)
	testing.expect(t, input.icon_set == shared.builtin_icon_set_uuid())
	testing.expect(t, input.icon == "magnifying-glass" && input.icon_position == .Trailing)
	testing.expect(t, input.icon_color == shared.Vec4{0.4, 0.5, 0.6, 1})
	testing.expect(t, input.icon_size == 14 && input.icon_gap == 5 && input.icon_inset == 1)
	testing.expect(t, input.font == "Inter")
	testing.expect(t, input.read_only)
	testing.expect(t, input.selection_background.x == 0.15)
	testing.expect(
		t,
		world.ui_scroll_areas[world.entities[0].ui_scroll_area_index].scrollbar_width == 6,
	)
	progress := world.ui_progresses[world.entities[0].ui_progress_index]
	testing.expect(t, progress.value == 6 && progress.maximum == 10)
	testing.expect(t, progress.right_to_left)
	action := world.ui_actions[world.entities[0].ui_action_index]
	testing.expect(t, action.action == "inspector.apply" && action.payload == "rotation")
	testing.expect(t, !action.drag_source && action.drop_target)
	testing.expect(t, action.drag_threshold == 9)
	testing.expect(t, action.drop_background.x > 0.099 && action.drop_background.x < 0.101)
	testing.expect(t, action.drop_background.w > 0.399 && action.drop_background.w < 0.401)
	table := world.ui_tables[world.entities[0].ui_table_index]
	testing.expect(t, table.proportional_columns && table.resizable_columns)
	testing.expect(t, table.min_column_width == 60)
	panel := world.ui_panels[world.entities[0].ui_panel_index]
	testing.expect(t, panel.collapsible && panel.collapsed)
	testing.expect(t, panel.movable)
	testing.expect(t, world.ui_layouts[world.entities[0].ui_layout_index].stack_order == 8)
	canvas := world.ui_canvases[world.entities[0].ui_canvas_index]
	testing.expect(t, canvas.scale_mode == .Fit)
	testing.expect(t, canvas.safe_area == shared.Vec4{24, 32, 40, 48})
	list := world.ui_lists[world.entities[1].ui_list_index]
	testing.expect(t, list.filter_input == world.entities[1].uuid)
	testing.expect(t, list.highlight_corner_radius == 9)
	testing.expect(t, list.virtualized && list.item_height == 36 && list.overscan == 5)
	dock_space := world.ui_dock_spaces[world.entities[3].ui_dock_space_index]
	testing.expect(t, dock_space.active == world.entities[4].uuid)
	testing.expect(t, dock_space.font == "Inter" && dock_space.tab_height == 40)
	testing.expect(t, !dock_space.draggable)
	testing.expect(t, dock_space.split_horizontal && dock_space.split_vertical)
	testing.expect(t, dock_space.split_ratio == 0.4)
	testing.expect(t, dock_space.split_gap == 6)
	testing.expect(t, dock_space.split_min_size == 144)
	dock_item := world.ui_dock_items[world.entities[4].ui_dock_item_index]
	testing.expect(t, dock_item.title == "GAME" && dock_item.movable)
	button_index := world.entities[1].ui_button_index
	testing.expect(t, button_index >= 0 && button_index < len(world.ui_buttons))
	if button_index >= 0 && button_index < len(world.ui_buttons) {
		testing.expect(t, world.ui_buttons[button_index].text == "Toggle")
		testing.expect(t, world.ui_buttons[button_index].popup == world.entities[1].uuid)
		testing.expect(t, world.ui_buttons[button_index].alignment == .Right)
		testing.expect(
			t,
			world.ui_buttons[button_index].icon_set == shared.builtin_icon_set_uuid(),
		)
		testing.expect(t, world.ui_buttons[button_index].icon == "x")
		testing.expect(t, world.ui_buttons[button_index].icon_position == .Trailing)
		testing.expect(t, world.ui_buttons[button_index].panel_action)
	}
	color_picker := world.ui_color_pickers[world.entities[2].ui_color_picker_index]
	testing.expect(t, color_picker.value == shared.Vec4{8, 4, 2, 0.75})
	testing.expect(t, color_picker.exposure == 3)
	runtime_dock_index := -1
	runtime_dock_item_index := -1
	for entity, entity_index in world.entities {
		if entity.name == "Runtime Dock" {
			runtime_dock_index = entity_index
		} else if entity.name == "Runtime Dock Item" {
			runtime_dock_item_index = entity_index
		}
	}
	testing.expect(t, runtime_dock_index >= 0 && runtime_dock_item_index >= 0)
	if runtime_dock_index >= 0 && runtime_dock_item_index >= 0 {
		runtime_dock := world.entities[runtime_dock_index]
		runtime_dock_item := world.entities[runtime_dock_item_index]
		testing.expect(t, runtime_dock.ui_dock_space_index >= 0)
		testing.expect(t, runtime_dock_item.ui_dock_item_index >= 0)
		testing.expect(
			t,
			world.ui_layouts[runtime_dock_item.ui_layout_index].parent == runtime_dock.uuid,
		)
		testing.expect(t, world.ui_dock_spaces[runtime_dock.ui_dock_space_index].tab_height == 34)
		testing.expect(
			t,
			world.ui_dock_items[runtime_dock_item.ui_dock_item_index].title == "RUNTIME",
		)
	}
	spawned_index := len(world.entities) - 2
	testing.expect(t, spawned_index >= 0 && world.entities[spawned_index].name == "Runtime UI")
	if spawned_index >= 0 {
		spawned := world.entities[spawned_index]
		testing.expect(t, spawned.ui_layout_index >= 0)
		testing.expect(t, spawned.ui_text_index >= 0)
		testing.expect(t, spawned.ui_hstack_index >= 0)
		if spawned.ui_layout_index >= 0 {
			layout := world.ui_layouts[spawned.ui_layout_index]
			testing.expect(t, layout.basis == 80 && layout.grow == 1 && layout.shrink == 2)
		}
		if spawned.ui_hstack_index >= 0 {
			stack := world.ui_hstacks[spawned.ui_hstack_index]
			testing.expect(t, stack.wrap && stack.line_gap == 6)
		}
		if spawned.ui_text_index >= 0 {
			text := world.ui_texts[spawned.ui_text_index]
			testing.expect(t, text.text == "Spawned responsive text")
			testing.expect(t, text.size == 16)
			testing.expect(t, text.wrap && text.line_height == 20)
			testing.expect(
				t,
				text.color.x == 1 && text.color.y == 1 && text.color.z == 1 && text.color.w == 1,
			)
		}
	}
	child := world.entities[len(world.entities) - 1]
	testing.expect(t, child.name == "Runtime UI Child")
	if child.ui_layout_index >= 0 {
		parent := world.ui_layouts[child.ui_layout_index].parent
		testing.expect(t, parent == world.entities[spawned_index].uuid)
	}
}

@(test)
test_luau_ui_events_are_immutable_cursor_snapshots :: proc(t: ^testing.T) {
	scene, parse_result := project.parse_scene(
		`[[entities]]
id = "ab000000-0000-4000-8000-000000000001"
name = "Action"
[entities.ui_layout]
size = [120, 32]
[entities.ui_button]
text = "Launch"
[entities.ui_action]
action = "flight.launch"
payload = "alpha"
`,
	)
	defer project.destroy_scene(&scene)
	testing.expect(t, parse_result.err == .None)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	ecs.append_ui_event(
		&world,
		{
			kind = .Activated,
			origin = .Scene,
			entity = scene.entities[0].id,
			action_entity = scene.entities[0].id,
			action = "flight.launch",
			payload = "alpha",
			position = {12, 18},
		},
	)
	ecs.append_ui_event(
		&world,
		{
			kind = .Changed,
			origin = .Editor,
			entity = scene.entities[0].id,
			action = "editor.private",
		},
	)

	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
scrapbot.system(function()
	local first = scrapbot.ui.events(0)
	assert(first.latest_sequence == 2)
	assert(first.oldest_sequence == 1)
	assert(first.overflowed == false)
	assert(#first.events == 1)
	local event = first.events[1]
	assert(event.sequence == 1 and event.frame_index == 0)
	assert(event.kind == "activated" and event.part == "control")
	assert(event.entity == "ab000000-0000-4000-8000-000000000001")
	assert(event.action_entity == event.entity)
	assert(event.action == "flight.launch" and event.payload == "alpha")
	assert(event.position.x == 12 and event.position.y == 18)

	local same = scrapbot.ui.events(0)
	assert(#same.events == 1 and same.events[1].sequence == event.sequence)
	local consumed = scrapbot.ui.events(first.latest_sequence)
	assert(#consumed.events == 0)
end)
`,
		"=test",
		&world,
	)
	testing.expect(t, result.err == "")
	testing.expect(t, result.ran)
	step_err := step_runtime(&runtime, &world, 0)
	testing.expectf(t, step_err == "", "UI event system step failed: %s", step_err)
}

@(test)
test_luau_ui_theme_resolver_returns_overridable_spawn_components :: proc(t: ^testing.T) {
	world: ecs.World
	defer ecs.destroy_world(&world)
	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source(
		&runtime,
		`
local spawned = false
scrapbot.system({
	name = "spawn_themed_ui",
	writes = { scrapbot.ui_layout, scrapbot.ui_button, scrapbot.ui_panel, scrapbot.ui_scroll_area },
}, function()
	if spawned then return end
	spawned = true

	local action = scrapbot.ui.resolve("reduced_dark", { "primary_button" })
	action["scrapbot.ui_layout"].size = { x = 240, y = 72 }
	action["scrapbot.ui_layout"].corner_radius = 24
	action["scrapbot.ui_button"].text = "BOOST"
	scrapbot.spawn({ name = "Themed Action", components = action })

	local panel = scrapbot.ui.resolve("reduced_dark", { "panel", "scroll_area" })
	panel["scrapbot.ui_panel"].title = "THEME"
	scrapbot.spawn({ name = "Themed Panel", components = panel })
end)
`,
		"=test",
		&world,
	)
	testing.expectf(t, result.err == "", "script failed: %s", result.err)
	testing.expect(t, result.ran)
	step_err := step_runtime(&runtime, &world, 0)
	testing.expectf(t, step_err == "", "themed UI spawn failed: %s", step_err)
	testing.expect(t, len(world.entities) == 2)
	if len(world.entities) != 2 {
		return
	}
	theme := shared.ui_theme_reduced_dark()
	action := world.entities[0]
	testing.expect(t, action.ui_layout_index >= 0)
	testing.expect(t, action.ui_button_index >= 0)
	if action.ui_layout_index >= 0 {
		layout := world.ui_layouts[action.ui_layout_index]
		testing.expect(t, layout.size == shared.Vec2{240, 72})
		testing.expect(t, layout.corner_radius == 24)
		testing.expect(t, layout.background == theme.palette.accent_soft)
	}
	if action.ui_button_index >= 0 {
		button := world.ui_buttons[action.ui_button_index]
		testing.expect(t, button.text == "BOOST")
		testing.expect(t, button.color == theme.palette.accent_text)
	}
	panel := world.entities[1]
	testing.expect(t, panel.ui_layout_index >= 0)
	testing.expect(t, panel.ui_panel_index >= 0)
	testing.expect(t, panel.ui_scroll_area_index >= 0)
}

@(test)
test_luau_ui_theme_resolver_accepts_project_theme_uuid :: proc(t: ^testing.T) {
	world: ecs.World
	defer ecs.destroy_world(&world)
	resource_registry: resources.Registry
	resources.init_registry(&resource_registry)
	defer resources.destroy_registry(&resource_registry)
	id, _ := shared.resource_uuid_parse("71c20000-0000-4000-8000-000000000001")
	theme := shared.ui_theme_reduced_dark()
	theme.palette.accent_soft = {1.4, 0.1, 0.5, 1}
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
		resources.register_project_ui_themes(
			&resource_registry,
			[]shared.Project_Resource{declaration},
		) ==
		"",
	)
	runtime: Runtime
	defer destroy_runtime(&runtime)
	result := run_source_with_options(
		&runtime,
		`
local components = scrapbot.ui.resolve(
	"71c20000-0000-4000-8000-000000000001",
	{ "primary_button" }
)
assert(components["scrapbot.ui_layout"].background.x > 1.39)
assert(components["scrapbot.ui_button"].font == "Inter")
`,
		"=test",
		&world,
		Source_Options{resource_registry = &resource_registry},
	)
	testing.expectf(t, result.err == "", "project theme resolution failed: %s", result.err)
}
