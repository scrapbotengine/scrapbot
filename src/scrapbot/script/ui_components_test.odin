package script

import ecs "../ecs"
import project "../project"
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
[entities.ui_panel]
title = "FIELD"
disclosure_size = 9
disclosure_corner_radius = 0
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
scrubbable = true
read_only = true
[entities.ui_progress]
value = 2
maximum = 10
fill_color = [0.1, 0.8, 0.6, 1]
inset = [2, 3, 4, 5]
corner_radius = 2
right_to_left = true
[[entities]]
id = "aa000000-0000-4000-8000-000000000002"
name = "Checkbox"
[entities.ui_layout]
size = [32, 32]
[entities.ui_checkbox]
checked = true
corner_radius = 0
border_width = 2
check_inset = 5
check_corner_radius = 0
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
assert(scrapbot.ui_scroll_area.id > 0)
assert(scrapbot.ui_table.id > 0)
assert(scrapbot.ui_input.id > 0)
assert(scrapbot.ui_progress.id > 0)
assert(scrapbot.ui_checkbox.id > 0)
assert(scrapbot.ui_state.id > 0)

scrapbot.system(function()
	local count = 0
	scrapbot.query(scrapbot.ui_layout, scrapbot.ui_panel, scrapbot.ui_table):each(function(entity, layout, panel, table)
		assert(layout.size.x == 240 and layout.size.y == 32)
		assert(layout.min_size.x == 120 and layout.min_size.y == 24)
		assert(layout.fill_width == true)
		assert(layout.fit_content_height == true)
		assert(layout.fixed_in_fill == true)
		assert(layout.hidden == false)
		assert(panel.title == "FIELD")
		assert(panel.disclosure_size == 9 and panel.disclosure_corner_radius == 0)
		assert(panel.collapsed == false)
		assert(table.columns == 1)
		assert(table.proportional_columns == true)
		assert(table.resizable_columns == true)
		assert(table.min_column_width == 44)
		scrapbot.add_component(entity, scrapbot.ui_table, {min_column_width = 60})
		count += 1
	end)
	assert(count == 1)
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
		assert(input.scrubbable == true)
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
	local state_count = 0
	scrapbot.query(scrapbot.ui_state):each(function(_, state)
		assert(state.hovered == true)
		assert(state.activation_revision == 3)
		assert(state.valid == true)
		assert(state.submitted == true and state.submit_revision == 4)
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
	scrapbot.query(scrapbot.ui_input):each(function(entity)
		scrapbot.add_component(entity, scrapbot.ui_input, {text = "84"})
		scrapbot.add_component(entity, scrapbot.ui_input, {size = 18})
		scrapbot.add_component(entity, scrapbot.ui_input, {prefix = "Y", number = 84})
	end)
	scrapbot.query(scrapbot.ui_checkbox):each(function(entity)
		scrapbot.remove_component(entity, scrapbot.ui_checkbox)
		scrapbot.add_component(entity, scrapbot.ui_button, {text = "Toggle", size = 14, alignment = "right"})
	end)
	local root_id = scrapbot.spawn({
		name = "Runtime UI",
		components = {
			["scrapbot.ui_layout"] = {size = {x = 120, y = 24}},
			["scrapbot.ui_text"] = {text = "Spawned"},
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
	table := world.ui_tables[world.entities[0].ui_table_index]
	testing.expect(t, table.proportional_columns && table.resizable_columns)
	testing.expect(t, table.min_column_width == 60)
	button_index := world.entities[1].ui_button_index
	testing.expect(t, button_index >= 0 && button_index < len(world.ui_buttons))
	if button_index >= 0 && button_index < len(world.ui_buttons) {
		testing.expect(t, world.ui_buttons[button_index].text == "Toggle")
		testing.expect(t, world.ui_buttons[button_index].alignment == .Right)
	}
	spawned_index := len(world.entities) - 2
	testing.expect(t, spawned_index >= 0 && world.entities[spawned_index].name == "Runtime UI")
	if spawned_index >= 0 {
		spawned := world.entities[spawned_index]
		testing.expect(t, spawned.ui_layout_index >= 0)
		testing.expect(t, spawned.ui_text_index >= 0)
		if spawned.ui_text_index >= 0 {
			text := world.ui_texts[spawned.ui_text_index]
			testing.expect(t, text.text == "Spawned")
			testing.expect(t, text.size == 16)
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
