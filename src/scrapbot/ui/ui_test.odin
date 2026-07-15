package ui

import ecs "../ecs"
import resources "../resources"
import shared "../shared"
import "core:math"
import "core:testing"

ui_test_id :: proc(name: string) -> shared.Entity_UUID {
	return shared.entity_uuid_from_engine_name(name)
}

find_editor_role_node :: proc(state: ^State, role: shared.Editor_UI_Role) -> int {
	for node, index in state.nodes[:state.node_count] { if node.origin == .Editor && node.editor_role == role { return index } }
	return -1
}

find_editor_name_node :: proc(state: ^State, world: ^shared.World, name: string) -> int {
	for node, index in state.nodes[:state.node_count] {
		entity_index := int(node.entity.index)
		if node.origin == .Editor &&
		   entity_index >= 0 &&
		   entity_index < len(world.entities) &&
		   world.entities[entity_index].name == name {
			return index
		}
	}
	return -1
}

editor_browser_row_count :: proc(world: ^shared.World) -> int {
	count := 0
	for component in world.editor_uis {
		if component.role != .Browser_Row ||
		   component.entity_index < 0 ||
		   component.entity_index >= len(world.entities) { continue }
		entity := world.entities[component.entity_index]
		if entity.alive &&
		   entity.ui_layout_index >= 0 &&
		   !world.ui_layouts[entity.ui_layout_index].hidden { count += 1 }
	}
	return count
}

@(test)
test_embedded_mtsdf_font_has_expected_atlas_and_proportional_metrics :: proc(t: ^testing.T) {
	testing.expect(t, len(FONT_ATLAS_DATA) == FONT_ATLAS_SIZE * FONT_ATLAS_SIZE * 4)
	i := FONT_GLYPHS[int('I') - FONT_FIRST_CHAR]
	w := FONT_GLYPHS[int('W') - FONT_FIRST_CHAR]
	testing.expect(t, i.advance > 0)
	testing.expect(t, w.advance > i.advance)
	testing.expect(t, w.uv.z > w.uv.x && w.uv.w > w.uv.y)
}

@(test)
test_progress_paints_overridable_track_and_right_anchored_fill :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Progress"),
			name = "Progress",
			has_ui_layout = true,
			ui_layout = {position = {20, 20}, size = {200, 20}},
			has_ui_progress = true,
			ui_progress = {
				value = 25,
				maximum = 100,
				fill_color = {0.2, 0.8, 0.6, 1},
				background_color = {0.1, 0.1, 0.1, 1},
				inset = {4, 10, 4, 10},
				corner_radius = 3,
				right_to_left = true,
			},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 320, 120) == "")
	testing.expect(t, state.paint_count == 2)
	if state.paint_count == 2 {
		track := state.paint[0]
		fill := state.paint[1]
		testing.expect(t, track.kind == .Panel)
		testing.expect(t, track.rect == (Rect{30, 24, 180, 12}))
		testing.expect(t, track.color == (shared.Vec4{0.1, 0.1, 0.1, 1}))
		testing.expect(t, track.corner_radius == 3)
		testing.expect(t, fill.rect == (Rect{165, 24, 45, 12}))
		testing.expect(t, fill.color == (shared.Vec4{0.2, 0.8, 0.6, 1}))
		testing.expect(t, fill.corner_radius == 3)
	}
}

@(test)
test_layout_fill_and_fit_content_are_reusable_and_ignore_hidden_children :: proc(t: ^testing.T) {
	root_id := ui_test_id("Responsive Root")
	content_id := ui_test_id("Responsive Content")
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = root_id,
			name = "Responsive Root",
			has_ui_layout = true,
			ui_layout = {size = {200, 100}, padding = {10, 10, 10, 10}},
			has_ui_scroll_area = true,
			ui_scroll_area = shared.ui_scroll_area_default(),
		},
		shared.Scene_Entity {
			id = content_id,
			name = "Responsive Content",
			has_ui_layout = true,
			ui_layout = {
				parent = root_id,
				size = {10, 10},
				min_size = {120, 80},
				fill_width = true,
				fill_height = true,
				fit_content_height = true,
			},
			has_ui_vstack = true,
			ui_vstack = {gap = 5},
		},
		shared.Scene_Entity {
			id = ui_test_id("Responsive Child A"),
			name = "Responsive Child A",
			has_ui_layout = true,
			ui_layout = {parent = content_id, size = {40, 60}},
		},
		shared.Scene_Entity {
			id = ui_test_id("Responsive Child B"),
			name = "Responsive Child B",
			has_ui_layout = true,
			ui_layout = {parent = content_id, size = {40, 60}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 320, 180) == "")
	content_layout := world.ui_layouts[world.entities[1].ui_layout_index]
	content_node := find_node_by_entity_index(state, 1)
	testing.expectf(
		t,
		content_layout.size.y == 10,
		"authored height changed during layout: %.2f",
		content_layout.size.y,
	)
	testing.expectf(
		t,
		content_node >= 0 && state.nodes[content_node].rect.height == 125,
		"expected fitted height 125, got %.2f",
		state.nodes[content_node].rect.height,
	)
	testing.expect(t, content_node >= 0 && state.nodes[content_node].rect.width == 180)
	root_node := find_node_by_entity_index(state, 0)
	testing.expectf(
		t,
		root_node >= 0 && state.nodes[root_node].scroll_max == 45,
		"expected scroll max 45, got %.2f",
		state.nodes[root_node].scroll_max,
	)

	world.ui_layouts[world.entities[3].ui_layout_index].hidden = true
	testing.expect(t, reconcile(state, &world, 320, 180) == "")
	content_layout = world.ui_layouts[world.entities[1].ui_layout_index]
	testing.expect(t, content_layout.size.y == 10)
	testing.expect(t, state.nodes[content_node].rect.height == 80)
	testing.expect(t, state.nodes[root_node].scroll_max == 0)
}

@(test)
test_fill_stack_can_keep_fixed_children_while_siblings_grow :: proc(t: ^testing.T) {
	root_id := ui_test_id("Fixed Fill Root")
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = root_id,
			name = "Fixed Fill Root",
			has_ui_layout = true,
			ui_layout = {size = {200, 150}},
			has_ui_vstack = true,
			ui_vstack = {fill = true},
		},
		shared.Scene_Entity {
			id = ui_test_id("Fixed Fill Header"),
			name = "Fixed Fill Header",
			has_ui_layout = true,
			ui_layout = {parent = root_id, size = {200, 20}, fixed_in_fill = true},
		},
		shared.Scene_Entity {
			id = ui_test_id("Fixed Fill Body"),
			name = "Fixed Fill Body",
			has_ui_layout = true,
			ui_layout = {parent = root_id, size = {200, 80}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 320, 180) == "")
	header := find_node_by_entity_index(state, 1)
	body := find_node_by_entity_index(state, 2)
	testing.expect(t, header >= 0 && state.nodes[header].rect.height == 20)
	testing.expect(t, body >= 0 && state.nodes[body].rect.height == 130)
}

@(test)
test_checkbox_paints_sdf_mark_and_toggles_unless_read_only :: proc(t: ^testing.T) {
	checkbox_style := shared.ui_checkbox_default()
	checkbox_style.checked = true
	checkbox_style.box_size = 20
	checkbox_style.background = {0.02, 0.03, 0.04, 1}
	checkbox_style.checked_background = {0.08, 0.55, 0.46, 1}
	checkbox_style.border_color = {0.24, 0.27, 0.32, 1}
	checkbox_style.check_color = {1, 1, 1, 1}
	checkbox_style.corner_radius = 0
	checkbox_style.border_width = 2
	checkbox_style.check_inset = 5
	checkbox_style.check_corner_radius = 0
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Checkbox"),
			name = "Checkbox",
			has_ui_layout = true,
			ui_layout = {position = {20, 20}, size = {80, 32}},
			has_ui_checkbox = true,
			ui_checkbox = checkbox_style,
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 200, 120) == "")
	checkbox_state := &world.ui_states[world.entities[0].ui_state_index]
	found_checkmark := false
	found_square_box := false
	for command in state.paint[:state.paint_count] {
		found_checkmark = found_checkmark || command.kind == .Checkmark
		found_square_box =
			found_square_box ||
			(command.kind == .Panel && command.corner_radius == 0 && command.border_width == 2)
	}
	testing.expect(t, found_checkmark)
	testing.expect(t, found_square_box)
	pointer := Pointer_Input {
		position = {30, 30},
		primary_down = true,
		available = true,
	}
	testing.expect(t, reconcile(state, &world, 200, 120, pointer) == "")
	testing.expect(t, !world.ui_checkboxes[0].checked)
	testing.expect(t, checkbox_state.changed && checkbox_state.change_revision == 1)
	pointer.primary_down = false
	testing.expect(t, reconcile(state, &world, 200, 120, pointer) == "")
	testing.expect(t, !checkbox_state.changed)
	world.ui_checkboxes[0].read_only = true
	pointer.primary_down = true
	testing.expect(t, reconcile(state, &world, 200, 120, pointer) == "")
	testing.expect(t, !world.ui_checkboxes[0].checked)
}

@(test)
test_selectable_list_lays_out_full_width_rows_and_selects_direct_child :: proc(t: ^testing.T) {
	list_id := ui_test_id("List")
	first_id := ui_test_id("First")
	second_id := ui_test_id("Second")
	selection_color := shared.Vec4{0.1, 0.5, 0.4, 1}
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = list_id,
			name = "List",
			has_ui_layout = true,
			ui_layout = {size = {200, 100}},
			has_ui_list = true,
			ui_list = {
				gap = 3,
				selection_background = selection_color,
				hover_background = {0.2, 0.2, 0.2, 1},
				active_background = {0.3, 0.3, 0.3, 1},
			},
		},
		shared.Scene_Entity {
			id = first_id,
			name = "First",
			has_ui_layout = true,
			ui_layout = {parent = list_id, size = {40, 30}},
			has_ui_text = true,
			ui_text = {text = "First", color = {1, 1, 1, 1}, size = 12},
		},
		shared.Scene_Entity {
			id = second_id,
			name = "Second",
			has_ui_layout = true,
			ui_layout = {parent = list_id, size = {60, 30}},
			has_ui_text = true,
			ui_text = {text = "Second", color = {1, 1, 1, 1}, size = 12},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 200, 100) == "")
	first_node := find_node_by_entity_index(state, 1)
	second_node := find_node_by_entity_index(state, 2)
	testing.expect(t, first_node >= 0 && second_node >= 0)
	if first_node < 0 || second_node < 0 { return }
	testing.expect(t, state.nodes[first_node].rect.width == 200)
	testing.expect(t, state.nodes[second_node].rect.width == 200)
	testing.expect(t, state.nodes[second_node].rect.y == 33)
	point := shared.Vec2 {
		state.nodes[second_node].rect.x + 20,
		state.nodes[second_node].rect.y + 15,
	}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			200,
			100,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, world.ui_lists[0].selected == second_id)
	list_state := world.ui_states[world.entities[0].ui_state_index]
	testing.expect(t, list_state.changed && list_state.change_revision == 1)
	testing.expect(
		t,
		reconcile(state, &world, 200, 100, {position = point, available = true}) == "",
	)
	selected_painted := false
	for command in state.paint[:state.paint_count] {
		if command.kind == .Panel &&
		   command.rect == state.nodes[second_node].rect &&
		   command.color == selection_color {
			selected_painted = true
		}
	}
	testing.expect(t, selected_painted)
}

@(test)
test_reconcile_tracks_ui_entity_appearance_and_disappearance :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {
				size = {300, 160},
				padding = {10, 10, 10, 10},
				background = {0.1, 0.2, 0.3, 1},
			},
			has_ui_vstack = true,
			ui_vstack = {gap = 0},
		},
		shared.Scene_Entity {
			name = "Label",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {200, 40}},
			has_ui_text = true,
			ui_text = {text = "HELLO", color = {1, 1, 1, 1}, size = 16},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	ecs.delete_world_string(&world, world.entities[0].name)
	world.entities[0].name = ecs.clone_world_string(&world, "Renamed Root Label")
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.node_count == 2)
	label_node := find_node_by_entity_index(state, 1)
	testing.expect(t, label_node >= 0 && state.nodes[label_node].parent_entity_index == 0)
	testing.expect(t, state.paint_count > 2)
	testing.expect(t, state.ui_structure_sync_count == 1)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.ui_structure_sync_count == 1)
	world.ui_layouts[world.entities[0].ui_layout_index].hidden = true
	ecs.mark_ui_subtree_dirty(&world, 0)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.node_count == 0)
	testing.expect(t, state.ui_structure_sync_count == 2)
	world.ui_layouts[world.entities[0].ui_layout_index].hidden = false
	ecs.mark_ui_subtree_dirty(&world, 0)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.node_count == 2)
	testing.expect(t, state.ui_structure_sync_count == 3)
	world.entities[1].alive = false
	ecs.mark_ui_entity_dirty(&world, 1)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.node_count == 1)
	testing.expect(t, state.paint_count == 1)
	testing.expect(t, state.ui_structure_sync_count == 4)
}

@(test)
test_column_layout_places_children_in_order :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {size = {300, 200}, padding = {10, 10, 10, 10}},
			has_ui_vstack = true,
			ui_vstack = {gap = 5},
		},
		shared.Scene_Entity {
			name = "A",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {100, 20}},
		},
		shared.Scene_Entity {
			name = "B",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {100, 30}},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	a := find_node_by_entity_index(state, 1); b := find_node_by_entity_index(state, 2)
	testing.expect(t, a >= 0 && b >= 0)
	if a >= 0 &&
	   b >=
		   0 { testing.expect(t, state.nodes[a].rect.y == 10); testing.expect(t, state.nodes[b].rect.y == 35) }
	world.entities[1].alive = false
	ecs.mark_ui_entity_dirty(&world, 1)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	b = find_node_by_entity_index(state, 2)
	testing.expect(t, b >= 0 && state.nodes[b].rect.y == 10)
	world.entities[1].alive = true
	ecs.mark_ui_entity_dirty(&world, 1)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	a = find_node_by_entity_index(state, 1)
	b = find_node_by_entity_index(state, 2)
	testing.expect(t, a >= 0 && b >= 0)
	if a >= 0 && b >= 0 {
		testing.expect(t, state.nodes[a].rect.y == 10)
		testing.expect(t, state.nodes[b].rect.y == 35)
	}
}

@(test)
test_table_layout_uses_equal_width_columns_and_wraps_rows :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Table"),
			name = "Table",
			has_ui_layout = true,
			ui_layout = {size = {320, 100}, padding = {10, 10, 10, 10}},
			has_ui_table = true,
			ui_table = {columns = 3, column_gap = 10, row_gap = 4},
		},
	)
	for _ in 0 ..< 5 {
		append(
			&scene.entities,
			shared.Scene_Entity {
				name = "Cell",
				has_ui_layout = true,
				ui_layout = {parent = ui_test_id("Table"), size = {1, 20}},
			},
		)
	}
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 320, 100) == "")
	cell_width := f32(280) / 3
	for ordinal in 0 ..< 5 {
		node_index := find_node_by_entity_index(state, ordinal + 1)
		testing.expect(t, node_index >= 0)
		if node_index < 0 { continue }
		column := ordinal % 3
		row := ordinal / 3
		rect := state.nodes[node_index].rect
		testing.expect(t, math.abs(rect.width - cell_width) < 0.01)
		testing.expect(t, math.abs(rect.x - (10 + f32(column) * (cell_width + 10))) < 0.01)
		testing.expect(t, rect.y == 10 + f32(row) * 24)
	}
}

@(test)
test_table_layout_uses_first_row_proportions_and_draggable_separators :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Proportional Table"),
			name = "Proportional Table",
			has_ui_layout = true,
			ui_layout = {size = {320, 100}, padding = {10, 10, 10, 10}},
			has_ui_table = true,
			ui_table = {
				columns = 2,
				column_gap = 10,
				proportional_columns = true,
				resizable_columns = true,
				min_column_width = 48,
			},
		},
	)
	for ordinal in 0 ..< 4 {
		width := f32(1)
		if ordinal % 2 == 1 { width = 2 }
		append(
			&scene.entities,
			shared.Scene_Entity {
				name = "Cell",
				has_ui_layout = true,
				ui_layout = {parent = ui_test_id("Proportional Table"), size = {width, 20}},
			},
		)
	}
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 320, 100) == "")
	first := find_node_by_entity_index(state, 1)
	second := find_node_by_entity_index(state, 2)
	third := find_node_by_entity_index(state, 3)
	fourth := find_node_by_entity_index(state, 4)
	testing.expect(t, first >= 0 && second >= 0 && third >= 0 && fourth >= 0)
	testing.expect(t, state.split_handle_count == 1)
	if first < 0 || second < 0 || third < 0 || fourth < 0 { return }
	testing.expect(t, math.abs(state.nodes[first].rect.width - 290.0 / 3.0) < 0.01)
	testing.expect(t, math.abs(state.nodes[second].rect.width - 580.0 / 3.0) < 0.01)
	testing.expect(
		t,
		math.abs(state.nodes[third].rect.width - state.nodes[first].rect.width) < 0.01,
	)
	testing.expect(
		t,
		math.abs(state.nodes[fourth].rect.width - state.nodes[second].rect.width) < 0.01,
	)
	handle := state.split_handles[0]
	point := shared.Vec2{handle.rect.x + handle.rect.width * 0.5, handle.rect.y + 20}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			320,
			100,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, current_pointer_cursor(state) == .Horizontal_Resize)
	point.x += 30
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			320,
			100,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, state.nodes[first].rect.width > 120)
	testing.expect(t, state.nodes[second].rect.width < 180)
	testing.expect(
		t,
		math.abs(state.nodes[third].rect.width - state.nodes[first].rect.width) < 0.01,
	)
	testing.expect(
		t,
		math.abs(state.nodes[fourth].rect.width - state.nodes[second].rect.width) < 0.01,
	)
}

@(test)
test_panel_title_reserves_child_space_and_paints_a_title_band :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Panel"),
			name = "Panel",
			has_ui_layout = true,
			ui_layout = {
				size = {240, 100},
				padding = {8, 8, 8, 8},
				background = {0.05, 0.06, 0.07, 1},
			},
			has_ui_panel = true,
			ui_panel = {
				title = "TRANSFORM",
				title_color = {1, 1, 1, 1},
				title_background = {0.12, 0.13, 0.14, 1},
				title_size = 10,
				title_height = 24,
			},
			has_ui_vstack = true,
		},
		shared.Scene_Entity {
			name = "Child",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Panel"), size = {100, 20}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 240, 100) == "")
	child := find_node_by_entity_index(state, 1)
	testing.expect(t, child >= 0)
	if child >= 0 { testing.expect(t, state.nodes[child].rect.y == 32) }
	found_title_band := false
	title_background := shared.Vec4{0.12, 0.13, 0.14, 1}
	for command in state.paint[:state.paint_count] {
		if command.kind == .Panel &&
		   command.color == title_background &&
		   command.rect.height == 24 {
			found_title_band = true
			break
		}
	}
	testing.expect(t, found_title_band)
}

@(test)
test_collapsible_panel_title_toggles_content_layout_and_disclosure :: proc(t: ^testing.T) {
	panel_style := shared.ui_panel_default()
	panel_style.title = "TRANSFORM"
	panel_style.title_color = {1, 1, 1, 1}
	panel_style.title_size = 10
	panel_style.title_height = 24
	panel_style.disclosure_size = 9
	panel_style.disclosure_corner_radius = 0
	panel_style.collapsible = true
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {size = {240, 200}},
			has_ui_vstack = true,
			ui_vstack = {fill = true},
		},
		shared.Scene_Entity {
			id = ui_test_id("Panel"),
			name = "Panel",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {240, 100}},
			has_ui_panel = true,
			ui_panel = panel_style,
			has_ui_vstack = true,
		},
		shared.Scene_Entity {
			id = ui_test_id("Panel Child"),
			name = "Panel Child",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Panel"), size = {200, 30}},
		},
		shared.Scene_Entity {
			id = ui_test_id("Sibling"),
			name = "Sibling",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {240, 100}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 240, 200) == "")
	panel_node := find_node_by_entity_index(state, 1)
	child_node := find_node_by_entity_index(state, 2)
	sibling_node := find_node_by_entity_index(state, 3)
	testing.expect(t, panel_node >= 0 && child_node >= 0 && sibling_node >= 0)
	if panel_node < 0 || child_node < 0 || sibling_node < 0 { return }
	testing.expect(t, state.nodes[panel_node].rect.height == 100)
	testing.expect(t, state.nodes[child_node].laid_out)
	testing.expect(t, state.nodes[sibling_node].rect.y == 100)

	press := Pointer_Input {
		position = {5, 5},
		primary_down = true,
		available = true,
	}
	testing.expect(t, reconcile(state, &world, 240, 200, press) == "")
	testing.expect(t, world.ui_panels[0].collapsed)
	testing.expect(t, state.nodes[panel_node].rect.height == 24)
	testing.expect(t, !state.nodes[child_node].laid_out)
	testing.expect(t, state.nodes[sibling_node].rect.y == 24)
	testing.expect(t, state.nodes[sibling_node].rect.height == 176)
	found_collapsed_disclosure := false
	for command in state.paint[:state.paint_count] {
		if command.kind == .Disclosure &&
		   !command.disclosure_expanded &&
		   command.rect.width == 9 &&
		   command.corner_radius == 0 {
			found_collapsed_disclosure = true
			break
		}
	}
	testing.expect(t, found_collapsed_disclosure)

	release := Pointer_Input {
		position = {5, 5},
		available = true,
	}
	testing.expect(t, reconcile(state, &world, 240, 200, release) == "")
	testing.expect(t, reconcile(state, &world, 240, 200, press) == "")
	testing.expect(t, !world.ui_panels[0].collapsed)
	testing.expect(t, state.nodes[panel_node].rect.height == 100)
	testing.expect(t, state.nodes[child_node].laid_out)
	testing.expect(t, state.nodes[sibling_node].rect.y == 100)
}

@(test)
test_single_line_input_selects_edits_navigates_and_tabs_in_paint_order :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "First",
			has_ui_layout = true,
			ui_layout = {
				position = {10, 10},
				size = {160, 28},
				padding = {6, 8, 5, 8},
				background = {0.02, 0.03, 0.04, 1},
				border_color = {0.1, 0.1, 0.1, 1},
				border_width = 1,
			},
			has_ui_input = true,
			ui_input = {
				text = "alpha",
				color = {1, 1, 1, 1},
				size = 12,
				selection_background = {0.1, 0.5, 0.4, 0.5},
				focus_border_color = {0.1, 0.8, 0.7, 1},
			},
		},
		shared.Scene_Entity {
			name = "Second",
			has_ui_layout = true,
			ui_layout = {
				position = {10, 48},
				size = {160, 28},
				padding = {6, 8, 5, 8},
				hidden = true,
			},
			has_ui_input = true,
			ui_input = {text = "second", color = {1, 1, 1, 1}, size = 12},
		},
		shared.Scene_Entity {
			name = "Third",
			has_ui_layout = true,
			ui_layout = {position = {10, 48}, size = {160, 28}, padding = {6, 8, 5, 8}},
			has_ui_input = true,
			ui_input = {text = "third", color = {1, 1, 1, 1}, size = 12},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			200,
			100,
			{position = {30, 20}, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, state.has_focused_input && state.focused_input == world.entities[0].id)
	testing.expect(t, state.input_anchor == 0 && state.input_cursor == 5)
	testing.expect(
		t,
		reconcile(state, &world, 200, 100, {}, 0, 0, 1.0 / 60.0, {text = "beta"}) == "",
	)
	testing.expect(t, world.ui_inputs[0].text == "beta")
	testing.expect(
		t,
		reconcile(state, &world, 200, 100, {}, 0, 0, 1.0 / 60.0, {home = true}) == "",
	)
	testing.expect(
		t,
		reconcile(state, &world, 200, 100, {}, 0, 0, 1.0 / 60.0, {right = true, shift = true}) ==
		"",
	)
	testing.expect(t, state.input_anchor == 0 && state.input_cursor == 1)
	testing.expect(t, reconcile(state, &world, 200, 100, {}, 0, 0, 1.0 / 60.0, {text = "B"}) == "")
	testing.expect(t, world.ui_inputs[0].text == "Beta")
	testing.expect(t, reconcile(state, &world, 200, 100, {}, 0, 0, 1.0 / 60.0, {tab = true}) == "")
	testing.expect(t, state.focused_input == world.entities[2].id)
	testing.expect(
		t,
		state.input_anchor == 0 && state.input_cursor == len(world.ui_inputs[2].text),
	)
	testing.expect(
		t,
		reconcile(state, &world, 200, 100, {}, 0, 0, 1.0 / 60.0, {tab = true, shift = true}) == "",
	)
	testing.expect(t, state.focused_input == world.entities[0].id)
}

@(test)
test_numeric_input_exposes_reusable_validation_submit_cancel_and_scrub_state :: proc(
	t: ^testing.T,
) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Numeric Input",
			has_ui_layout = true,
			ui_layout = {position = {10, 10}, size = {160, 28}, padding = {6, 8, 5, 8}},
			has_ui_input = true,
			ui_input = {
				text = "1",
				prefix = "X",
				color = {1, 1, 1, 1},
				prefix_color = {0.9, 0.3, 0.3, 1},
				prefix_background = {0.9, 0.3, 0.3, 0.12},
				size = 12,
				prefix_width = UI_INPUT_PREFIX_WIDTH,
				prefix_gap = 4,
				prefix_corner_radius = 0,
				prefix_text_padding = 2,
				selection_corner_radius = 0,
				focus_border_width = 2,
				invalid_border_width = 3,
				caret_width = 2,
				caret_inset = 3,
				number = 1,
				step = 0.5,
				minimum = 0,
				maximum = 2,
				numeric = true,
				has_minimum = true,
				has_maximum = true,
				scrubbable = true,
			},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)

	press := Pointer_Input {
		position = {40, 20},
		primary_down = true,
		available = true,
	}
	testing.expect(t, reconcile(state, &world, 200, 80, press) == "")
	found_square_prefix := false
	for command in state.paint[:state.paint_count] {
		if command.kind == .Panel &&
		   command.color == world.ui_inputs[0].prefix_background &&
		   command.corner_radius == 0 {
			found_square_prefix = true
			break
		}
	}
	testing.expect(t, found_square_prefix)
	testing.expect(t, reconcile(state, &world, 200, 80, {}, 0, 0, 1.0 / 60.0, {up = true}) == "")
	input := &world.ui_inputs[world.entities[0].ui_input_index]
	interaction := &world.ui_states[world.entities[0].ui_state_index]
	testing.expect(t, input.number == 1.5 && input.text == "1.5")
	testing.expect(t, interaction.changed && interaction.change_revision == 1)
	testing.expect(
		t,
		reconcile(state, &world, 200, 80, {}, 0, 0, 1.0 / 60.0, {enter = true}) == "",
	)
	testing.expect(t, interaction.submitted && interaction.submit_revision == 1)
	testing.expect(t, interaction.valid)

	testing.expect(t, reconcile(state, &world, 200, 80, press) == "")
	testing.expect(
		t,
		reconcile(state, &world, 200, 80, {}, 0, 0, 1.0 / 60.0, {text = "bad"}) == "",
	)
	testing.expect(t, !interaction.valid)
	testing.expect(
		t,
		reconcile(state, &world, 200, 80, {}, 0, 0, 1.0 / 60.0, {escape = true}) == "",
	)
	testing.expect(t, input.text == "1.5" && input.number == 1.5)
	testing.expect(t, interaction.cancelled && interaction.cancel_revision == 1)
	testing.expect(t, interaction.valid)
}

@(test)
test_fill_stack_allocates_available_space_and_drags_between_adjacent_panes :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {size = {600, 200}, padding = {10, 10, 10, 10}},
			has_ui_hstack = true,
			ui_hstack = {gap = 6, fill = true, draggable = true, min_size = 80},
		},
		shared.Scene_Entity {
			name = "Left",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {100, 20}},
		},
		shared.Scene_Entity {
			name = "Center",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {200, 20}},
		},
		shared.Scene_Entity {
			name = "Right",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {100, 20}},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	testing.expect(t, reconcile(state, &world, 600, 200) == "")
	left := find_node_by_entity_index(
		state,
		1,
	); center := find_node_by_entity_index(state, 2); right := find_node_by_entity_index(state, 3)
	testing.expect(t, left >= 0 && center >= 0 && right >= 0 && state.split_handle_count == 2)
	if left >= 0 && center >= 0 && right >= 0 {
		testing.expect(t, math.abs(state.nodes[left].rect.width - 142) < 0.01)
		testing.expect(t, math.abs(state.nodes[center].rect.width - 284) < 0.01)
		testing.expect(t, math.abs(state.nodes[right].rect.width - 142) < 0.01)
		testing.expect(
			t,
			state.nodes[left].rect.height == 180 && state.nodes[center].rect.height == 180,
		)
		handle := state.split_handles[0]
		point := shared.Vec2{handle.rect.x + handle.rect.width * 0.5, handle.rect.y + 20}
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				600,
				200,
				{position = point, primary_down = true, available = true},
			) ==
			"",
		)
		testing.expect(t, current_pointer_cursor(state) == .Horizontal_Resize)
		point.x += 40
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				600,
				200,
				{position = point, primary_down = true, available = true},
			) ==
			"",
		)
		testing.expect(
			t,
			state.nodes[left].rect.width > 180 && state.nodes[center].rect.width < 250,
		)
		testing.expect(t, math.abs(state.nodes[right].rect.width - 142) < 0.1)
	}
}

@(test)
test_vertical_fill_stack_drags_and_fills_the_cross_axis :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {size = {200, 400}, padding = {10, 10, 10, 10}},
			has_ui_vstack = true,
			ui_vstack = {gap = 8, fill = true, draggable = true, min_size = 100},
		},
		shared.Scene_Entity {
			name = "Top",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {20, 100}},
		},
		shared.Scene_Entity {
			name = "Bottom",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {20, 100}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 200, 400) == "")
	top := find_node_by_entity_index(state, 1)
	bottom := find_node_by_entity_index(state, 2)
	testing.expect(t, top >= 0 && bottom >= 0 && state.split_handle_count == 1)
	if top >= 0 && bottom >= 0 {
		testing.expect(t, state.nodes[top].rect == Rect{10, 10, 180, 186})
		handle := state.split_handles[0]
		point := shared.Vec2{handle.rect.x + 20, handle.rect.y + handle.rect.height * 0.5}
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				200,
				400,
				{position = point, primary_down = true, available = true},
			) ==
			"",
		)
		testing.expect(t, current_pointer_cursor(state) == .Vertical_Resize)
		point.y += 30
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				200,
				400,
				{position = point, primary_down = true, available = true},
			) ==
			"",
		)
		testing.expect(t, math.abs(state.nodes[top].rect.height - 216) < 0.01)
		testing.expect(t, math.abs(state.nodes[bottom].rect.height - 156) < 0.01)
	}
}

@(test)
test_ui_text_right_alignment_uses_the_padded_content_edge :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Timing",
			has_ui_layout = true,
			ui_layout = {position = {10, 20}, size = {100, 30}, padding = {4, 7, 3, 5}},
			has_ui_text = true,
			ui_text = {text = "12", color = {1, 1, 1, 1}, size = 12, alignment = .Right},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 120, 60) == "")
	advance := text_advance_to(state, "12", 12, 2)
	expected_start := f32(10 + 100 - 7) - advance
	first_glyph := -1
	for command, index in state.paint[:state.paint_count] {
		if command.kind == .Glyph {
			first_glyph = index
			break
		}
	}
	testing.expect(t, first_glyph >= 0)
	if first_glyph >= 0 {
		glyph := state.font.glyphs^[int('1') - FONT_FIRST_CHAR]
		expected_ink_x := expected_start + glyph.plane.x * 12
		testing.expect(t, math.abs(state.paint[first_glyph].rect.x - expected_ink_x) < 0.001)
	}
}

@(test)
test_ui_button_alignment_uses_the_padded_content_edge :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Action",
			has_ui_layout = true,
			ui_layout = {position = {10, 20}, size = {100, 30}, padding = {4, 7, 3, 5}},
			has_ui_button = true,
			ui_button = {text = "GO", color = {1, 1, 1, 1}, size = 12, alignment = .Right},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 120, 60) == "")
	rightmost_ink := f32(-10000)
	for command in state.paint[:state.paint_count] {
		if command.kind == .Glyph {
			rightmost_ink = max(rightmost_ink, command.rect.x + command.rect.width)
		}
	}
	testing.expect(t, math.abs(rightmost_ink - 103) < 0.001)
}

@(test)
test_ui_text_selects_a_project_font_atlas_layer :: proc(t: ^testing.T) {
	registry: resources.Registry
	defer resources.destroy_registry(&registry)
	pixels := make([]u8, FONT_ATLAS_SIZE * FONT_ATLAS_SIZE * 4)
	defer delete(pixels)
	desc := resources.Font_Desc {
		pixels = pixels,
		width = FONT_ATLAS_SIZE,
		height = FONT_ATLAS_SIZE,
		ascender = 0.8,
	}
	desc.glyphs[int('A') - FONT_FIRST_CHAR] = {
		advance = 0.75,
		plane = {0, -0.8, 0.7, 0.2},
		uv = {0, 0, 0.1, 0.1},
	}
	_, font_err := resources.register_font(&registry, "display", desc)
	testing.expect(t, font_err == "")

	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Title",
			has_ui_layout = true,
			ui_layout = {position = {10, 20}, size = {100, 30}},
			has_ui_text = true,
			ui_text = {text = "A", font = "display", color = {1, 1, 1, 1}, size = 10},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 120, 60, {}, 0, 0, 1.0 / 60.0, {}, &registry) == "")

	glyph_found := false
	for command in state.paint[:state.paint_count] {
		if command.kind != .Glyph { continue }
		glyph_found = true
		testing.expect(t, command.font_layer == 1)
		break
	}
	testing.expect(t, glyph_found)
}

@(test)
test_box_model_applies_margins_padding_and_rounded_button_paint :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {position = {20, 30}, size = {300, 120}, padding = {10, 10, 10, 10}},
			has_ui_hstack = true,
			ui_hstack = {gap = 6},
		},
		shared.Scene_Entity {
			name = "Button",
			has_ui_layout = true,
			ui_layout = {
				parent = ui_test_id("Root"),
				size = {100, 40},
				margin = {2, 3, 4, 5},
				padding = {8, 8, 8, 8},
				background = {0.2, 0.4, 0.8, 1},
				border_color = {0.7, 0.8, 1, 1},
				border_width = 2,
				corner_radius = 12,
			},
			has_ui_button = true,
			ui_button = {text = "GO", color = {1, 1, 1, 1}, size = 16},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	button := find_node_by_entity_index(state, 1); testing.expect(t, button >= 0)
	if button >=
	   0 { testing.expect(t, state.nodes[button].rect.x == 35); testing.expect(t, state.nodes[button].rect.y == 42) }
	testing.expect(t, state.paint_count >= 3)
	if state.paint_count > 0 {
		testing.expect(t, state.paint[0].corner_radius == 12)
		testing.expect(t, state.paint[0].border_color == shared.Vec4{0.7, 0.8, 1, 1})
		testing.expect(t, state.paint[0].border_width == 2)
	}
}

@(test)
test_hidden_ui_box_removes_its_entire_subtree_without_despawning_entities :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {size = {200, 100}, hidden = true},
		},
		shared.Scene_Entity {
			name = "Child",
			has_ui_layout = true,
			ui_layout = {parent = ui_test_id("Root"), size = {100, 40}},
			has_ui_text = true,
			ui_text = {text = "Hidden", color = {1, 1, 1, 1}, size = 14},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.node_count == 0)
	testing.expect(t, world.entities[0].alive && world.entities[1].alive)
}

@(test)
test_pointer_states_belong_to_elements_and_buttons_consume_them :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Root"),
			name = "Root",
			has_ui_layout = true,
			ui_layout = {size = {300, 120}},
		},
		shared.Scene_Entity {
			name = "Button",
			has_ui_layout = true,
			ui_layout = {
				parent = ui_test_id("Root"),
				position = {20, 20},
				size = {100, 40},
				background = {0.1, 0.2, 0.3, 1},
			},
			has_ui_button = true,
			ui_button = {
				text = "GO",
				color = {1, 1, 1, 1},
				size = 16,
				alignment = .Center,
				hover_background = {0.2, 0.4, 0.6, 1},
				active_background = {0.05, 0.1, 0.15, 1},
			},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	button := 1

	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {position = {30, 30}, available = true}) == "",
	)
	testing.expect(t, state.nodes[button].hovered && !state.nodes[button].active)
	button_state := &world.ui_states[world.entities[button].ui_state_index]
	testing.expect(t, button_state.hovered && !button_state.active && !button_state.activated)
	testing.expect(t, state.paint[0].color == shared.Vec4{0.2, 0.4, 0.6, 1})
	ink_min_x, ink_min_y, ink_max_x, ink_max_y := f32(10000), f32(10000), f32(-10000), f32(-10000)
	for command in state.paint[:state.paint_count] { if command.kind == .Glyph { ink_min_x = min(ink_min_x, command.rect.x); ink_min_y = min(ink_min_y, command.rect.y); ink_max_x = max(ink_max_x, command.rect.x + command.rect.width); ink_max_y = max(ink_max_y, command.rect.y + command.rect.height) } }
	delta_x := (ink_min_x + ink_max_x) * 0.5 - 70; if delta_x < 0 { delta_x = -delta_x }
	delta_y := (ink_min_y + ink_max_y) * 0.5 - 40; if delta_y < 0 { delta_y = -delta_y }
	testing.expect(t, delta_x < 0.001 && delta_y < 0.001)

	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = {30, 30}, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, state.nodes[button].hovered && state.nodes[button].active)
	testing.expect(t, button_state.hovered && button_state.active && button_state.activated)
	testing.expect(t, button_state.activation_revision == 1)
	testing.expect(t, state.paint[0].color == shared.Vec4{0.05, 0.1, 0.15, 1})

	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = {500, 500}, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, !state.nodes[button].hovered && state.nodes[button].active)
	testing.expect(t, !button_state.hovered && button_state.active && !button_state.activated)

	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {position = {500, 500}, available = true}) == "",
	)
	testing.expect(t, !state.nodes[button].hovered && !state.nodes[button].active)
}

@(test)
test_scroll_area_clips_descendants_and_smoothly_approaches_wheel_target :: proc(t: ^testing.T) {
	scroll_style := shared.ui_scroll_area_default()
	scroll_style.scroll_speed = 60
	scroll_style.smoothness = 12
	scroll_style.scrollbar_width = 5
	scroll_style.scrollbar_corner_radius = 0
	scroll_style.scrollbar_thumb_color = {0.7, 0.8, 0.9, 1}
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Scroll"),
			name = "Scroll",
			has_ui_layout = true,
			ui_layout = {
				position = {20, 20},
				size = {200, 100},
				padding = {10, 10, 10, 10},
				background = {0.08, 0.09, 0.11, 1},
			},
			has_ui_scroll_area = true,
			ui_scroll_area = scroll_style,
		},
		shared.Scene_Entity {
			id = ui_test_id("Pane"),
			name = "Pane",
			has_ui_layout = true,
			ui_layout = {
				parent = ui_test_id("Scroll"),
				size = {180, 300},
				background = {0.12, 0.13, 0.15, 1},
			},
		},
		shared.Scene_Entity {
			name = "Button",
			has_ui_layout = true,
			ui_layout = {
				parent = ui_test_id("Pane"),
				position = {10, 75},
				size = {150, 40},
				background = {0.2, 0.3, 0.4, 1},
			},
			has_ui_button = true,
			ui_button = {text = "CLIPPED", color = {1, 1, 1, 1}, size = 12},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)

	// The button occupies this point geometrically, but the scroll viewport clips it.
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {position = {40, 115}, available = true}) == "",
	)
	scroll := find_node_by_entity_index(
		state,
		0,
	); pane := find_node_by_entity_index(state, 1); button := find_node_by_entity_index(state, 2)
	testing.expect(t, scroll >= 0 && pane >= 0 && button >= 0)
	if scroll >= 0 && pane >= 0 && button >= 0 {
		testing.expect(t, state.nodes[scroll].scroll_max == 220)
		testing.expect(t, state.nodes[pane].clip == Rect{30, 30, 180, 80})
		testing.expect(t, !state.nodes[button].hovered)
	}
	clipped_paint := false
	expected_clip := Rect{30, 30, 180, 80}
	for command in state.paint[:state.paint_count] { if command.has_clip && command.clip == expected_clip { clipped_paint = true; break } }
	testing.expect(t, clipped_paint)
	found_custom_thumb := false
	for command in state.paint[:state.paint_count] {
		if command.kind == .Panel &&
		   command.color == scroll_style.scrollbar_thumb_color &&
		   command.rect.width == 5 &&
		   command.corner_radius == 0 {
			found_custom_thumb = true
			break
		}
	}
	testing.expect(t, found_custom_thumb)

	initial_pane_y := state.nodes[pane].rect.y
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = {40, 40}, wheel_y = -1, available = true},
			0,
			0,
			1.0 / 60.0,
		) ==
		"",
	)
	testing.expect(t, state.nodes[scroll].scroll_target == 60)
	testing.expect(
		t,
		state.nodes[scroll].scroll_offset > 0 && state.nodes[scroll].scroll_offset < 60,
	)
	testing.expect(t, state.nodes[pane].rect.y < initial_pane_y)
	for _ in 0 ..< 60 { testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0) == "") }
	testing.expect(t, math.abs(state.nodes[scroll].scroll_offset - 60) < 0.02)

	// A later entity occupying a released retained-node slot starts at the top.
	for &entity, entity_index in world.entities {
		entity.alive = false
		ecs.mark_ui_entity_dirty(&world, entity_index)
	}
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	for &entity, entity_index in world.entities {
		entity.alive = true
		ecs.mark_ui_entity_dirty(&world, entity_index)
	}
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	scroll = find_node_by_entity_index(state, 0)
	testing.expect(
		t,
		scroll >= 0 &&
		state.nodes[scroll].scroll_offset == 0 &&
		state.nodes[scroll].scroll_target == 0,
	)
}

@(test)
test_editor_shell_is_an_editor_origin_ecs_ui_tree :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Game UI",
			has_ui_layout = true,
			ui_layout = {size = {100, 40}, background = {0.2, 0.3, 0.4, 1}},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	root := find_editor_role_node(state, .Root)
	viewport_node := find_editor_role_node(state, .Viewport)
	testing.expect(t, root >= 0 && viewport_node >= 0)
	testing.expect(t, len(world.editor_uis) > 0)
	for component, component_index in world.editor_uis {
		testing.expect(
			t,
			component.entity_index >= 0 && component.entity_index < len(world.entities),
		)
		if component.entity_index < 0 || component.entity_index >= len(world.entities) { continue }
		entity := world.entities[component.entity_index]
		testing.expect(t, entity.alive)
		testing.expect(t, entity.origin == .Editor)
		testing.expect(t, entity.editor_ui_index == component_index)
		testing.expect(t, entity.ui_layout_index >= 0)
		if entity.ui_text_index >= 0 {
			testing.expect(t, world.ui_texts[entity.ui_text_index].size == EDITOR_TEXT_SIZE)
		}
	}
	if root >= 0 {
		entity := world.entities[int(state.nodes[root].entity.index)]
		testing.expect(t, entity.origin == .Editor && entity.ui_layout_index >= 0)
	}
	viewport := editor_viewport(state, 1280, 720)
	if viewport_node >= 0 { testing.expect(t, viewport == state.nodes[viewport_node].rect) }
	testing.expect(t, state.editor_paint_start == 1)
	testing.expect(t, state.paint_count > state.editor_paint_start)
	pointer := project_pointer_input(
		state,
		{
			position = {viewport.x + viewport.width * 0.5, viewport.y + viewport.height * 0.5},
			available = true,
		},
		1280,
		720,
	)
	testing.expect(
		t,
		pointer.available &&
		math.abs(pointer.position.x - 640) < 0.01 &&
		math.abs(pointer.position.y - 360) < 0.01,
	)
	testing.expect(
		t,
		!project_pointer_input(state, {position = {20, 100}, available = true}, 1280, 720).available,
	)

	// ECS layout components and the derived viewport follow the full available drawable.
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 2048, 1096) == "")
	viewport = editor_viewport(state, 2048, 1096)
	viewport_node = find_editor_role_node(state, .Viewport)
	testing.expect(t, viewport_node >= 0 && viewport == state.nodes[viewport_node].rect)
	testing.expect(t, viewport.width > 1000 && viewport.height > 900)
	testing.expect(t, state.paint[state.editor_paint_start].rect.width == 2048)
	pointer = project_pointer_input(
		state,
		{
			position = {viewport.x + viewport.width * 0.5, viewport.y + viewport.height * 0.5},
			available = true,
		},
		1280,
		720,
		2048,
		1096,
	)
	testing.expect(
		t,
		pointer.available &&
		math.abs(pointer.position.x - 640) < 0.01 &&
		math.abs(pointer.position.y - 360) < 0.01,
	)
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{
				position = {viewport.x + 100, viewport.y + 100},
				primary_down = true,
				available = true,
			},
			2048,
			1096,
		) ==
		"",
	)
	testing.expect(t, state.editor_pick_requested)
	testing.expect(
		t,
		state.editor_pick_position == shared.Vec2{viewport.x + 100, viewport.y + 100},
	)

	// Native-density windows keep the same logical chrome size while painting at 2x resolution.
	state.editor_pixel_density = 2
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 2560, 1440) == "")
	viewport = editor_viewport(state, 2560, 1440)
	viewport_node = find_editor_role_node(state, .Viewport)
	if viewport_node >=
	   0 { testing.expect(t, viewport == Rect{state.nodes[viewport_node].rect.x * 2, state.nodes[viewport_node].rect.y * 2, state.nodes[viewport_node].rect.width * 2, state.nodes[viewport_node].rect.height * 2}) }
	testing.expect(
		t,
		state.paint[state.editor_paint_start].rect == Rect{0, 0, 2560, EDITOR_TOP_BAR_HEIGHT * 2},
	)

	// The chrome is composed from the same ECS stack components as project UI.
	state.editor_pixel_density = 1
	testing.expect(t, reconcile(state, &world, 760, 720, {}, 760, 720) == "")
	top_index, status_index := -1, -1
	for entity, entity_index in world.entities {
		switch entity.name {
			case EDITOR_UI_TOP_NAME:
				top_index = entity_index
			case EDITOR_UI_STATUS_NAME:
				status_index = entity_index
			case "__scrapbot_editor_signal_rail",
			     "__scrapbot_editor_subtitle",
			     "__scrapbot_editor_tool_hint",
			     "__scrapbot_editor_status_hint":
				testing.expect(t, false)
		}
	}
	testing.expect(t, top_index >= 0 && world.entities[top_index].ui_hstack_index >= 0)
	testing.expect(t, status_index >= 0 && world.entities[status_index].ui_hstack_index >= 0)
}

@(test)
test_editor_transport_buttons_control_simulation_and_request_stop_reload :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	play := find_editor_role_node(state, .Transport_Play)
	pause := find_editor_role_node(state, .Transport_Pause)
	stop := find_editor_role_node(state, .Transport_Stop)
	step := find_editor_role_node(state, .Transport_Step)
	save := find_editor_role_node(state, .Transport_Save)
	status := find_editor_role_node(state, .Status)
	testing.expect(
		t,
		play >= 0 && pause >= 0 && stop >= 0 && step >= 0 && save >= 0 && status >= 0,
	)
	if play < 0 || pause < 0 || stop < 0 || step < 0 || save < 0 || status < 0 {
		return
	}
	pause_entity := world.entities[int(state.nodes[pause].entity.index)]
	testing.expect(t, world.ui_buttons[pause_entity.ui_button_index].text == "PAUSE")
	stop_entity := world.entities[int(state.nodes[stop].entity.index)]
	testing.expect(t, world.ui_buttons[stop_entity.ui_button_index].text == "STOP")
	save_entity := world.entities[int(state.nodes[save].entity.index)]
	testing.expect(t, world.ui_buttons[save_entity.ui_button_index].text == "SAVE")
	status_entity := world.entities[int(state.nodes[status].entity.index)]
	testing.expect(t, world.ui_texts[status_entity.ui_text_index].text == "RUNNING")

	press := proc(state: ^State, world: ^shared.World, node_index: int) {
		rect := state.nodes[node_index].rect
		point := shared.Vec2{rect.x + rect.width * 0.5, rect.y + rect.height * 0.5}
		_ = reconcile(
			state,
			world,
			1280,
			720,
			{position = point, primary_down = true, available = true},
		)
		_ = reconcile(state, world, 1280, 720, {position = point, available = true})
	}

	testing.expect(t, state.editor_simulation_playing)
	press(state, &world, pause)
	testing.expect(t, !state.editor_simulation_playing)
	testing.expect(t, world.ui_texts[status_entity.ui_text_index].text == "PAUSED")
	delta, run := consume_simulation_delta(state, 0.2)
	testing.expect(t, !run && delta == 0)

	press(state, &world, step)
	delta, run = consume_simulation_delta(state, 0.2)
	testing.expect(t, run && delta == f32(1.0 / 60.0))
	_, run = consume_simulation_delta(state, 0.2)
	testing.expect(t, !run)

	press(state, &world, play)
	testing.expect(t, state.editor_simulation_playing)
	testing.expect(t, world.ui_texts[status_entity.ui_text_index].text == "RUNNING")
	delta, run = consume_simulation_delta(state, 0.2)
	testing.expect(t, run && delta == 0.2)

	press(state, &world, stop)
	testing.expect(t, !state.editor_simulation_playing)
	testing.expect(t, state.editor_simulation_stopped)
	testing.expect(t, world.ui_texts[status_entity.ui_text_index].text == "STOPPED")
	testing.expect(t, consume_scene_reload_request(state))
	testing.expect(t, !consume_scene_reload_request(state))
	state.editor_scene_dirty = true
	state.editor_snapshot_valid = false
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, world.ui_texts[status_entity.ui_text_index].text == "STOPPED  /  UNSAVED")
	press(state, &world, save)
	testing.expect(t, consume_scene_save_request(state))
	testing.expect(t, !consume_scene_save_request(state))
	complete_scene_save(state, true)
	testing.expect(t, !state.editor_scene_dirty)
	state.editor_scene_dirty = true
	state.editor_snapshot_valid = false
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {}, 0, 0, 1.0 / 60.0, {save = true}) == "",
	)
	testing.expect(t, consume_scene_save_request(state))
	complete_scene_save(state, true)
	testing.expect(t, !state.editor_scene_dirty)

	// Stopped authoring cannot accidentally transition to paused playback.
	editor_pause(state)
	testing.expect(t, state.editor_simulation_stopped)
}

@(test)
test_editor_scene_dirty_only_tracks_stopped_scene_entities :: proc(t: ^testing.T) {
	state := new(State)
	defer free(state)
	defer destroy(state)
	state.editor_simulation_stopped = true
	scene_entity := shared.World_Entity {
		uuid = shared.entity_uuid_from_engine_name("scene-dirty"),
		origin = .Scene,
	}
	runtime_entity := shared.World_Entity {
		origin = .Runtime,
	}
	editor_mark_scene_dirty(state, &runtime_entity)
	testing.expect(t, !state.editor_scene_dirty)
	editor_mark_scene_dirty(state, &scene_entity)
	testing.expect(t, state.editor_scene_dirty)
	testing.expect(t, len(state.editor_dirty_entities) == 1)
	editor_mark_scene_dirty(state, &scene_entity)
	testing.expect(t, len(state.editor_dirty_entities) == 1)
	state.editor_scene_dirty = false
	state.editor_simulation_stopped = false
	editor_mark_scene_dirty(state, &scene_entity)
	testing.expect(t, !state.editor_scene_dirty)
}

@(test)
test_editor_sidebar_separators_resize_panes_and_preserve_the_center_fill :: proc(t: ^testing.T) {
	scene :=
		shared.Scene{}; defer delete(scene.entities); append(&scene.entities, shared.Scene_Entity{name = "Entity"})
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state); state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, current_pointer_cursor(state) == .Default)
	viewport := editor_viewport(state, 1280, 720)
	initial := viewport
	editor_handles := [2]int{-1, -1}
	handle_count := 0
	for handle, index in state.split_handles[:state.split_handle_count] { if handle.editor && handle.horizontal && handle_count < 2 { editor_handles[handle_count] = index; handle_count += 1 } }
	testing.expect(t, handle_count == 2)
	left_handle := state.split_handles[editor_handles[0]]
	point := shared.Vec2{left_handle.rect.x + left_handle.rect.width * 0.5, 200}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, current_pointer_cursor(state) == .Horizontal_Resize)
	point.x += 80
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, current_pointer_cursor(state) == .Horizontal_Resize)
	viewport = editor_viewport(state, 1280, 720)
	testing.expect(t, math.abs(viewport.x - initial.x - 80) < 0.1)
	testing.expect(t, math.abs(viewport.width - initial.width + 80) < 0.1)
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {position = point, available = true}) == "",
	)
	right_handle := state.split_handles[editor_handles[1]]
	point = {right_handle.rect.x + right_handle.rect.width * 0.5, 200}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, current_pointer_cursor(state) == .Horizontal_Resize)
	point.x -= 60
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	final_viewport := editor_viewport(state, 1280, 720)
	testing.expect(t, math.abs(final_viewport.x - viewport.x) < 0.1)
	testing.expect(t, math.abs(final_viewport.width - viewport.width + 60) < 0.1)
	testing.expect(
		t,
		reconcile(state, &world, 1280, 720, {position = {500, 500}, available = true}) == "",
	)
	testing.expect(t, current_pointer_cursor(state) == .Default)
}

@(test)
test_editor_systems_separator_resizes_profiler_and_scene_panes :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(&scene.entities, shared.Scene_Entity{name = "Entity"})
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	systems := find_editor_role_node(state, .Systems_Scroll)
	browser := find_editor_role_node(state, .Browser_Scroll)
	vertical_handle := -1
	for handle, index in state.split_handles[:state.split_handle_count] {
		if handle.editor && !handle.horizontal {
			vertical_handle = index
			break
		}
	}
	testing.expect(t, systems >= 0 && browser >= 0 && vertical_handle >= 0)
	if systems < 0 || browser < 0 || vertical_handle < 0 {
		return
	}
	initial_system_height := state.nodes[systems].rect.height
	initial_browser_height := state.nodes[browser].rect.height
	handle := state.split_handles[vertical_handle]
	point := shared.Vec2 {
		handle.rect.x + handle.rect.width * 0.5,
		handle.rect.y + handle.rect.height * 0.5,
	}
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, current_pointer_cursor(state) == .Vertical_Resize)
	point.y += 60
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = point, primary_down = true, available = true},
		) ==
		"",
	)
	testing.expect(t, current_pointer_cursor(state) == .Vertical_Resize)
	testing.expect(t, state.nodes[systems].rect.height > initial_system_height + 59)
	testing.expect(t, state.nodes[browser].rect.height < initial_browser_height - 40)
}

@(test)
test_editor_sidebar_sections_share_collapsible_panel_styling :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(&scene.entities, shared.Scene_Entity{name = "Entity"})
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")

	systems := find_editor_role_node(state, .Systems_Scroll)
	scene_panel := find_editor_name_node(state, &world, EDITOR_UI_SCENE_NAME)
	inspector := find_editor_name_node(state, &world, EDITOR_UI_INSPECTOR_HEADER_NAME)
	sections := [3]int{systems, scene_panel, inspector}
	expected_titles := [3]string{"SYSTEMS / 0", "SCENE", "INSPECTOR"}
	expected_backgrounds := [3]shared.Vec4 {
		EDITOR_LIST_BACKGROUND,
		EDITOR_LIST_BACKGROUND,
		EDITOR_SECTION_BACKGROUND,
	}
	for node_index, section_index in sections {
		testing.expect(t, node_index >= 0)
		if node_index < 0 { continue }
		node := state.nodes[node_index]
		testing.expect(t, node.panel_index >= 0)
		if node.panel_index < 0 { continue }
		panel := world.ui_panels[node.panel_index]
		layout := world.ui_layouts[node.layout_index]
		testing.expect(t, panel.title == expected_titles[section_index])
		testing.expect(t, panel.collapsible)
		testing.expect(t, panel.title_height == EDITOR_SECTION_TITLE_HEIGHT)
		testing.expect(t, panel.title_color == EDITOR_SECTION_TITLE_COLOR)
		testing.expect(t, panel.title_background == EDITOR_SECTION_TITLE_BACKGROUND)
		testing.expect(t, layout.background == expected_backgrounds[section_index])
		testing.expect(t, layout.border_color == EDITOR_SECTION_BORDER)
		testing.expect(t, layout.corner_radius == EDITOR_SECTION_RADIUS)
	}

	if scene_panel >= 0 {
		node := state.nodes[scene_panel]
		point := shared.Vec2{node.rect.x + 18, node.rect.y + EDITOR_SECTION_TITLE_HEIGHT * 0.5}
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				1280,
				720,
				{position = point, primary_down = true, available = true},
			) ==
			"",
		)
		testing.expect(t, world.ui_panels[node.panel_index].collapsed)
	}
}

@(test)
test_editor_nested_scroll_prefers_inner_panes_and_sidebar_padding_targets_outer :: proc(
	t: ^testing.T,
) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	for _ in 0 ..< 25 {
		append(&scene.entities, shared.Scene_Entity{name = "Entity"})
	}
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	profile: shared.System_Profile
	profile.entry_count = 10
	profile.revision = 1
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	state.system_profile = &profile
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "")
	left := find_editor_name_node(state, &world, EDITOR_UI_LEFT_NAME)
	right := find_editor_name_node(state, &world, EDITOR_UI_RIGHT_NAME)
	systems := find_editor_role_node(state, .Systems_Scroll)
	testing.expect(t, left >= 0 && right >= 0 && systems >= 0)
	if left < 0 || right < 0 || systems < 0 {
		return
	}
	testing.expect(t, state.nodes[left].scroll_max > 0)
	testing.expect(t, state.nodes[right].scroll_max > 0)
	left_layout := world.ui_layouts[state.nodes[left].layout_index]
	right_layout := world.ui_layouts[state.nodes[right].layout_index]
	testing.expect(
		t,
		left_layout.padding ==
		shared.Vec4 {
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
			},
	)
	testing.expect(
		t,
		right_layout.padding ==
		shared.Vec4 {
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
				EDITOR_SIDEBAR_PADDING,
			},
	)

	system_rect := state.nodes[systems].rect
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = {system_rect.x + 20, system_rect.y + 60}, wheel_y = -1, available = true},
			1280,
			300,
		) ==
		"",
	)
	testing.expect(t, state.nodes[systems].scroll_target == EDITOR_SCROLL_SPEED)
	testing.expect(t, state.nodes[left].scroll_target == 0)

	left_rect := state.nodes[left].rect
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = {left_rect.x + 2, left_rect.y + 20}, wheel_y = -1, available = true},
			1280,
			300,
		) ==
		"",
	)
	testing.expect(t, state.nodes[left].scroll_target == EDITOR_SCROLL_SPEED)

	right_rect := state.nodes[right].rect
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = {right_rect.x + 2, right_rect.y + 20}, wheel_y = -1, available = true},
			1280,
			300,
		) ==
		"",
	)
	testing.expect(t, state.nodes[right].scroll_target == EDITOR_SCROLL_SPEED)
}

@(test)
test_editor_scene_panel_is_a_flush_scrollable_selectable_list :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	for _ in 0 ..< 31 {
		append(&scene.entities, shared.Scene_Entity{name = "Entity"})
	}
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 800, 500) == "")
	scene_node := find_editor_role_node(state, .Browser_Scroll)
	first_row, row_found := editor_ui_entity(&world, .Browser_Row, 0)
	testing.expect(t, scene_node >= 0 && row_found)
	if scene_node < 0 || !row_found { return }
	scene_panel := state.nodes[scene_node]
	row_node := find_node_by_entity_index(state, first_row)
	testing.expect(t, scene_panel.list_index >= 0)
	testing.expect(t, scene_panel.scroll_area_index >= 0)
	testing.expect(t, scene_panel.panel_index >= 0)
	testing.expect(t, world.ui_layouts[scene_panel.layout_index].padding == shared.Vec4{})
	testing.expect(t, row_node >= 0)
	if row_node >= 0 {
		row := state.nodes[row_node]
		testing.expect(t, math.abs(row.rect.x - scene_panel.rect.x) < 0.01)
		testing.expect(t, math.abs(row.rect.width - scene_panel.rect.width) < 0.01)
		testing.expect(
			t,
			math.abs(row.rect.y - scene_panel.rect.y - EDITOR_SECTION_TITLE_HEIGHT) < 0.01,
		)
	}
}

@(test)
test_resized_play_view_maps_pointer_back_to_project_canvas :: proc(t: ^testing.T) {
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	viewport := editor_viewport(state, 2048, 1096)
	testing.expect(t, viewport == Rect{0, 0, 2048, 1096})
	pointer := project_pointer_input(
		state,
		{position = {1024, 548}, available = true},
		1280,
		720,
		2048,
		1096,
	)
	testing.expect(t, pointer.available && pointer.position == shared.Vec2{640, 360})
}

@(test)
test_editor_browser_scrolls_selects_runtime_entities_and_clears_stale_selection :: proc(
	t: ^testing.T,
) {
	scene := shared.Scene{}; defer delete(scene.entities)
	for i in 0 ..< 25 { append(&scene.entities, shared.Scene_Entity{name = "Browser Entity"}) }
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	world.entities[24].origin = .Runtime
	world.entities[24].transform_index = len(
		world.transforms,
	); append_soa(&world.transforms, shared.Transform_Component{})
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state); state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "")
	left_sidebar := find_editor_name_node(state, &world, EDITOR_UI_LEFT_NAME)
	testing.expect(t, left_sidebar >= 0 && state.nodes[left_sidebar].scroll_max > 0)
	if left_sidebar >= 0 {
		state.nodes[left_sidebar].scroll_target = state.nodes[left_sidebar].scroll_max
	}
	for _ in 0 ..< 60 {
		testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "")
	}
	browser_index := find_editor_role_node(state, .Browser_Scroll)
	testing.expect(t, browser_index >= 0)
	browser_rect := state.nodes[browser_index].rect
	browser_visible := rect_intersection(browser_rect, state.nodes[browser_index].clip)
	browser_point := shared.Vec2 {
		browser_visible.x + min(browser_visible.width * 0.5, 20),
		browser_visible.y + min(browser_visible.height * 0.5, 20),
	}

	// A wheel step settles at a pixel offset between rows instead of snapping to one.
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = browser_point, wheel_y = -1, available = true},
			1280,
			300,
		) ==
		"",
	)
	browser_index = find_editor_role_node(state, .Browser_Scroll)
	testing.expect(t, state.nodes[browser_index].scroll_target == 48)
	testing.expect(
		t,
		int(state.nodes[browser_index].scroll_target) % int(EDITOR_ENTITY_ROW_HEIGHT) != 0,
	)
	for _ in 0 ..< 60 { testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "") }
	testing.expect(t, math.abs(state.nodes[browser_index].scroll_offset - 48) < 0.02)

	// A short window can continue smoothly to the runtime tail.
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = browser_point, wheel_y = -20, available = true},
			1280,
			300,
		) ==
		"",
	)
	testing.expect(t, state.nodes[browser_index].scroll_target > 48)
	testing.expect(
		t,
		state.nodes[browser_index].scroll_offset > 0 &&
		state.nodes[browser_index].scroll_offset < state.nodes[browser_index].scroll_target,
	)
	browser_index = find_editor_role_node(state, .Browser_Scroll)
	state.nodes[browser_index].scroll_target = state.nodes[browser_index].scroll_max
	for _ in 0 ..< 60 { testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "") }
	browser_index = find_editor_role_node(state, .Browser_Scroll)
	testing.expect(
		t,
		math.abs(
			state.nodes[browser_index].scroll_offset - state.nodes[browser_index].scroll_target,
		) <
		0.02,
	)
	runtime_row_entity := -1
	for component in world.editor_uis { if component.role == .Browser_Row && component.target == world.entities[24].id { runtime_row_entity = component.entity_index; break } }
	runtime_row_node := find_node_by_entity_index(state, runtime_row_entity)
	testing.expect(t, runtime_row_node >= 0 && state.nodes[runtime_row_node].has_clip)
	row_rect := state.nodes[runtime_row_node].rect
	row_point := shared.Vec2{row_rect.x + 20, row_rect.y + row_rect.height * 0.5}
	testing.expect(t, node_pointer_contains(state.nodes[runtime_row_node], row_point))
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{position = row_point, primary_down = true, available = true},
			1280,
			300,
		) ==
		"",
	)
	testing.expect(t, state.editor_has_selection)
	testing.expect(t, state.editor_selected_entity == world.entities[24].id)
	testing.expect(t, world.entities[24].origin == .Runtime)
	testing.expect(t, entity_component_count(&world, 24) == 1)
	browser_entity := world.entities[int(state.nodes[browser_index].entity.index)]
	testing.expect(
		t,
		world.ui_lists[browser_entity.ui_list_index].selected ==
		world.entities[runtime_row_entity].uuid,
	)

	world.entities[24].alive = false
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "")
	testing.expect(t, !state.editor_has_selection)
}

@(test)
test_editor_browser_uses_name_color_instead_of_provenance_labels :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity{name = "Authored"},
		shared.Scene_Entity{name = "Runtime"},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	world.entities[1].origin = .Runtime
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state); state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")

	scene_color := shared.Vec4{0.82, 0.85, 0.90, 1}
	runtime_color := EDITOR_RUNTIME_ENTITY_COLOR
	scene_label, runtime_label := -1, -1
	for component in world.editor_uis {
		if component.role != .Browser_Row_Label { continue }
		if component.target == world.entities[0].id { scene_label = component.entity_index }
		if component.target == world.entities[1].id { runtime_label = component.entity_index }
	}
	testing.expect(t, scene_label >= 0 && runtime_label >= 0)
	if scene_label >=
	   0 { label := world.ui_texts[world.entities[scene_label].ui_text_index]; testing.expect(t, label.color == scene_color); testing.expect(t, label.size == EDITOR_TEXT_SIZE); testing.expect(t, world.ui_layouts[world.entities[scene_label].ui_layout_index].size.y == EDITOR_ENTITY_ROW_HEIGHT) }
	if runtime_label >=
	   0 { testing.expect(t, world.ui_texts[world.entities[runtime_label].ui_text_index].color == runtime_color) }
}

@(test)
test_editor_browser_row_pool_survives_runtime_entity_count_churn :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity{name = "One"},
		shared.Scene_Entity{name = "Two"},
		shared.Scene_Entity{name = "Three"},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, editor_browser_row_count(&world) == 3)

	ecs.despawn_entity(&world, 1, world.entities[1].id.generation)
	ecs.despawn_entity(&world, 2, world.entities[2].id.generation)
	state.editor_snapshot_valid = false
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, editor_browser_row_count(&world) == 1)
	for component in world.editor_uis {
		if component.role != .Browser_Row || component.slot == 0 { continue }
		entity := world.entities[component.entity_index]
		testing.expect(t, entity.alive)
		testing.expect(t, world.ui_layouts[entity.ui_layout_index].hidden)
	}

	names := [3]string{"Runtime A", "Runtime B", "Runtime C"}
	for name in names {
		spawn: ecs.Spawn_Command
		testing.expect(t, ecs.init_spawn_command(&spawn, name) == "")
		_ = ecs.spawn_entity(&world, &spawn)
	}
	state.editor_snapshot_valid = false
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, editor_browser_row_count(&world) == 4)
	for component, component_index in world.editor_uis {
		if component.role != .Browser_Row && component.role != .Browser_Row_Label { continue }
		entity := world.entities[component.entity_index]
		testing.expect(t, entity.alive && entity.origin == .Editor)
		testing.expect(t, entity.editor_ui_index == component_index)
	}
}

@(test)
test_editor_scene_camera_and_editor_ui_are_hidden_from_the_entity_browser :: proc(t: ^testing.T) {
	scene: shared.Scene
	defer delete(scene.entities)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	entity_index, _, ok := ecs.reconcile_editor_scene_camera(&world, true)
	testing.expect(t, ok)
	testing.expect(t, world.entities[entity_index].origin == .Editor)
	testing.expect(t, entity_component_count(&world, entity_index) == 3)

	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, !editor_select_entity(state, &world, world.entities[entity_index].id, 720))
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	for component in world.editor_uis { if component.role == .Browser_Row || component.role == .Browser_Row_Label { testing.expect(t, component.target != world.entities[entity_index].id) } }
	testing.expect(t, editor_browser_row_count(&world) == 0)
}

@(test)
test_component_inspector_formats_live_fields_and_scrolls_independently :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "Inspectable",
			has_transform = true,
			transform = {position = {1, 2.5, -3}, rotation = {0.1, 0.2, 0.3}, scale = {1, 1, 1}},
			has_camera = true,
			camera = {fov = 60, near = 0.1, far = 500},
			has_shadow_caster = true,
			has_ui_layout = true,
			ui_layout = {
				parent = ui_test_id("Root"),
				position = {20, 30},
				size = {300, 120},
				padding = {4, 5, 6, 7},
				corner_radius = 8,
			},
			has_ui_button = true,
			ui_button = {
				text = "Launch",
				size = 14,
				color = {1, 1, 1, 1},
				hover_background = {0.2, 0.3, 0.4, 1},
			},
		},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state); state.editor_visible = true
	testing.expect(t, editor_select_entity(state, &world, world.entities[0].id, 300))
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "")
	testing.expect(t, state.editor_has_selection)
	content_entity, content_found := editor_ui_entity(&world, .Inspector_Content)
	inspector_node := find_editor_role_node(state, .Inspector_Scroll)
	testing.expect(t, content_found && inspector_node >= 0)
	if content_found {
		testing.expect(t, world.entities[content_entity].ui_text_index < 0)
		testing.expect(t, world.entities[content_entity].name == EDITOR_UI_RIGHT_CONTENT_NAME)
		testing.expect(t, world.entities[content_entity].ui_vstack_index >= 0)
	}
	header_node := find_editor_name_node(state, &world, EDITOR_UI_INSPECTOR_HEADER_NAME)
	first_panel_node := find_editor_role_node(state, .Inspector_Panel)
	testing.expect(t, header_node >= 0 && first_panel_node >= 0)
	if content_found && header_node >= 0 && first_panel_node >= 0 {
		header := state.nodes[header_node]
		panel := state.nodes[first_panel_node]
		testing.expect(t, header.parent_entity_index == content_entity)
		testing.expect(t, panel.parent_entity_index == content_entity)
		testing.expect(t, math.abs(header.rect.x - panel.rect.x) < 0.01)
		testing.expect(t, math.abs(header.rect.width - panel.rect.width) < 0.01)
	}
	first_table_node := find_editor_role_node(state, .Inspector_Table)
	first_cell_node := find_editor_role_node(state, .Inspector_Cell)
	testing.expect(t, first_panel_node >= 0 && first_table_node >= 0 && first_cell_node >= 0)
	if first_panel_node >= 0 && first_table_node >= 0 && first_cell_node >= 0 {
		panel := state.nodes[first_panel_node]
		table := state.nodes[first_table_node]
		cell := state.nodes[first_cell_node]
		testing.expect(t, math.abs(table.rect.x - panel.rect.x) < 0.01)
		testing.expect(t, math.abs(table.rect.width - panel.rect.width) < 0.01)
		testing.expect(
			t,
			math.abs(table.rect.y - panel.rect.y - INSPECTOR_PANEL_TITLE_HEIGHT) < 0.01,
		)
		testing.expect(
			t,
			math.abs(table.rect.y + table.rect.height - panel.rect.y - panel.rect.height) < 0.01,
		)
		testing.expect(t, math.abs(cell.rect.x - table.rect.x) < 0.01)
	}
	panel_count, table_count, cell_count, input_count, checkbox_count := 0, 0, 0, 0, 0
	found_transform, found_button := false, false
	found_position := false
	position_label_cell := -1
	found_read_only_checkbox, found_bound_checkbox := false, false
	position_inputs := [3]int{-1, -1, -1}
	fov_input := -1
	button_input := -1
	for component in world.editor_uis {
		if component.entity_index < 0 || component.entity_index >= len(world.entities) { continue }
		entity := world.entities[component.entity_index]
		if !entity.alive { continue }
		#partial switch component.role {
			case .Inspector_Panel:
				panel_count += 1
				panel := world.ui_panels[entity.ui_panel_index]
				layout := world.ui_layouts[entity.ui_layout_index]
				testing.expect(t, panel.title_height == INSPECTOR_PANEL_TITLE_HEIGHT)
				testing.expect(t, panel.title_size == EDITOR_TEXT_SIZE)
				testing.expect(t, layout.padding == INSPECTOR_PANEL_PADDING)
				found_transform = found_transform || panel.title == "TRANSFORM"
				found_button = found_button || panel.title == "UI BUTTON"
			case .Inspector_Table:
				table_count += 1
				table := world.ui_tables[entity.ui_table_index]
				testing.expect(t, table.columns == 2)
				testing.expect(t, table.column_gap == 0)
				testing.expect(t, table.proportional_columns)
				testing.expect(t, table.resizable_columns)
				testing.expect(t, table.min_column_width == 72)
			case .Inspector_Cell:
				cell_count += 1
				layout := world.ui_layouts[entity.ui_layout_index]
				testing.expect(t, layout.size.y == INSPECTOR_CELL_HEIGHT)
				if entity.ui_hstack_index >= 0 {
					testing.expect(t, world.ui_hstacks[entity.ui_hstack_index].gap == 6)
					testing.expect(t, layout.padding == INSPECTOR_VALUE_CELL_PADDING)
				}
				if entity.ui_text_index >= 0 {
					testing.expect(t, layout.padding == INSPECTOR_LABEL_CELL_PADDING)
					testing.expect(
						t,
						world.ui_texts[entity.ui_text_index].size == EDITOR_TEXT_SIZE,
					)
					found_position =
						found_position || world.ui_texts[entity.ui_text_index].text == "position"
					if position_label_cell < 0 &&
					   world.ui_texts[entity.ui_text_index].text == "position" {
						position_label_cell = component.entity_index
					}
				}
			case .Inspector_Input:
				input_count += 1
				testing.expect(
					t,
					world.ui_layouts[entity.ui_layout_index].size.y == INSPECTOR_CONTROL_HEIGHT,
				)
				testing.expect(t, world.ui_layouts[entity.ui_layout_index].corner_radius == 4)
				testing.expect(t, world.ui_inputs[entity.ui_input_index].size == EDITOR_TEXT_SIZE)
				if entity.ui_input_index >= 0 &&
				   entity.ui_input_index < len(world.ui_inputs) &&
				   world.ui_inputs[entity.ui_input_index].text == "Launch" {
					button_input = component.entity_index
				}
				if component.inspector_field == .Camera_Fov { fov_input = component.entity_index }
				if component.inspector_field == .Transform_Position {
					axis_index := int(component.inspector_axis) - 1
					if axis_index >= 0 && axis_index < len(position_inputs) {
						position_inputs[axis_index] = component.entity_index
					}
				}
			case .Inspector_Checkbox:
				checkbox_count += 1
				testing.expect(t, entity.ui_checkbox_index >= 0)
				testing.expect(
					t,
					world.ui_layouts[entity.ui_layout_index].size.y == INSPECTOR_CONTROL_HEIGHT,
				)
				checkbox := world.ui_checkboxes[entity.ui_checkbox_index]
				if component.inspector_field == .None {
					found_read_only_checkbox = checkbox.read_only && checkbox.checked
				} else if component.inspector_field == .UI_Layout_Hidden {
					found_bound_checkbox = !checkbox.read_only && !checkbox.checked
				}
		}
	}
	testing.expect(t, panel_count == 5)
	testing.expect(t, table_count == panel_count)
	testing.expect(t, cell_count > 20)
	testing.expect(t, input_count > cell_count / 2)
	testing.expect(t, checkbox_count == 2)
	testing.expect(t, found_read_only_checkbox && found_bound_checkbox)
	testing.expect(t, found_transform && found_button)
	testing.expect(t, found_position)
	for input in position_inputs { testing.expect(t, input >= 0) }
	testing.expect(t, fov_input >= 0)
	testing.expect(t, button_input >= 0)
	if position_inputs[0] >= 0 && position_inputs[1] >= 0 && position_inputs[2] >= 0 {
		x_node := find_node_by_entity_index(state, position_inputs[0])
		y_node := find_node_by_entity_index(state, position_inputs[1])
		z_node := find_node_by_entity_index(state, position_inputs[2])
		testing.expect(t, x_node >= 0 && y_node >= 0 && z_node >= 0)
		if x_node >= 0 && y_node >= 0 && z_node >= 0 {
			x_cell_node := find_node_by_entity_index(
				state,
				state.nodes[x_node].parent_entity_index,
			)
			testing.expect(t, x_cell_node >= 0)
			testing.expect(t, state.nodes[x_node].rect.height == INSPECTOR_CONTROL_HEIGHT)
			if x_cell_node >= 0 {
				cell := state.nodes[x_cell_node]
				input := state.nodes[x_node]
				testing.expect(t, input.rect.y - cell.rect.y == INSPECTOR_VALUE_CELL_PADDING.x)
				testing.expect(
					t,
					cell.rect.y + cell.rect.height - input.rect.y - input.rect.height ==
					INSPECTOR_VALUE_CELL_PADDING.z,
				)
			}
			label_node := find_node_by_entity_index(state, position_label_cell)
			testing.expect(t, label_node >= 0)
			if label_node >= 0 {
				input_layout :=
					world.ui_layouts[world.entities[position_inputs[0]].ui_layout_index]
				input_content_height :=
					state.nodes[x_node].rect.height -
					input_layout.padding.x -
					input_layout.padding.z
				label_baseline :=
					state.nodes[label_node].rect.y +
					INSPECTOR_LABEL_CELL_PADDING.x +
					state.font.ascender * EDITOR_TEXT_SIZE
				input_baseline :=
					state.nodes[x_node].rect.y +
					input_layout.padding.x +
					max((input_content_height - EDITOR_TEXT_SIZE) * 0.5, 0) +
					state.font.ascender * EDITOR_TEXT_SIZE
				testing.expectf(
					t,
					math.abs(label_baseline - input_baseline) < 0.01,
					"label baseline %.2f differs from input baseline %.2f",
					label_baseline,
					input_baseline,
				)
			}
			testing.expect(t, state.nodes[x_node].rect.y == state.nodes[y_node].rect.y)
			testing.expect(t, state.nodes[y_node].rect.y == state.nodes[z_node].rect.y)
			testing.expect(t, state.nodes[x_node].rect.x < state.nodes[y_node].rect.x)
			testing.expect(t, state.nodes[y_node].rect.x < state.nodes[z_node].rect.x)
			x_axis_accent_found := false
			for command in state.paint[:state.paint_count] {
				if command.kind == .Glyph &&
				   command.color.x > 0.9 &&
				   command.color.y < 0.4 &&
				   rect_contains(state.nodes[x_node].rect, {command.rect.x, command.rect.y}) {
					x_axis_accent_found = true
					break
				}
			}
			testing.expect(t, x_axis_accent_found)
		}
	}
	testing.expect(t, format_vec3({1, 2.5, -3}) == "(1.00, 2.50, -3.00)")
	position_input := position_inputs[0]
	testing.expect(t, position_input >= 0)
	if position_input >= 0 {
		focus_input(state, &world, position_input)
		refresh_count := state.editor_snapshot_refresh_count
		testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300, 0) == "")
		testing.expect(t, state.editor_snapshot_refresh_count == refresh_count)
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 1.0 / 60.0, {text = "9"}) == "",
		)
		testing.expect(t, world.transforms[0].position == shared.Vec3{9, 2.5, -3})
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 1.0 / 60.0, {escape = true}) == "",
		)
		testing.expect(t, world.transforms[0].position == shared.Vec3{1, 2.5, -3})
		focus_input(state, &world, position_inputs[0])
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				1280,
				720,
				{},
				1280,
				300,
				1.0 / 60.0,
				{text = "4", tab = true},
			) ==
			"",
		)
		testing.expect(t, state.focused_input == world.entities[position_inputs[1]].id)
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				1280,
				720,
				{},
				1280,
				300,
				1.0 / 60.0,
				{text = "5", tab = true},
			) ==
			"",
		)
		testing.expect(t, state.focused_input == world.entities[position_inputs[2]].id)
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				1280,
				720,
				{},
				1280,
				300,
				1.0 / 60.0,
				{text = "6", enter = true},
			) ==
			"",
		)
		testing.expect(t, world.transforms[0].position == shared.Vec3{4, 5, 6})
		testing.expect(t, !state.has_focused_input)
		testing.expect(t, state.editor_history_count == 3)

		// Axis prefixes reserve text width while horizontal reveal keeps the caret inside.
		focus_input(state, &world, position_inputs[0])
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 1.0 / 60.0, {text = "123456789"}) ==
			"",
		)
		testing.expect(t, state.input_scroll_x > 0)
		x_node := find_node_by_entity_index(state, position_inputs[0])
		caret_inside := false
		if x_node >= 0 {
			for command in state.paint[:state.paint_count] {
				if command.kind == .Panel && command.rect.width == 1 {
					caret_inside =
						command.rect.x >= state.nodes[x_node].rect.x &&
						command.rect.x <
							state.nodes[x_node].rect.x + state.nodes[x_node].rect.width
				}
			}
		}
		testing.expect(t, caret_inside)
		text_clipped_behind_axis := true
		if x_node >= 0 {
			layout := world.ui_layouts[world.entities[position_inputs[0]].ui_layout_index]
			text_viewport_left :=
				state.nodes[x_node].rect.x +
				layout.padding.w +
				UI_INPUT_PREFIX_WIDTH +
				UI_INPUT_PREFIX_GAP
			input_color := world.ui_inputs[world.entities[position_inputs[0]].ui_input_index].color
			for command in state.paint[:state.paint_count] {
				if command.kind == .Glyph &&
				   command.color == input_color &&
				   rect_contains(state.nodes[x_node].rect, {command.rect.x, command.rect.y}) &&
				   (!command.has_clip || command.clip.x < text_viewport_left) {
					text_clipped_behind_axis = false
					break
				}
			}
		}
		testing.expect(t, text_clipped_behind_axis)
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 0, {escape = true}) == "",
		)

		// Invalid text remains local, receives invalid styling, and cannot commit.
		focus_input(state, &world, position_inputs[0])
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 1.0 / 60.0, {text = "nope"}) == "",
		)
		testing.expect(t, !state.input_valid)
		testing.expect(t, world.transforms[0].position == shared.Vec3{4, 5, 6})
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 1.0 / 60.0, {enter = true}) == "",
		)
		testing.expect(t, state.has_focused_input)
		invalid_border_found := false
		x_node = find_node_by_entity_index(state, position_inputs[0])
		if x_node >= 0 {
			for command in state.paint[:state.paint_count] {
				if command.kind == .Panel &&
				   command.rect == state.nodes[x_node].rect &&
				   command.border_color.x > 0.9 &&
				   command.border_color.y < 0.3 {
					invalid_border_found = true
					break
				}
			}
		}
		testing.expect(t, invalid_border_found)
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 1.0 / 60.0, {escape = true}) == "",
		)

		// Stepping respects coarse/fine modifiers and records one completed command.
		focus_input(state, &world, position_inputs[0])
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				1280,
				720,
				{},
				1280,
				300,
				1.0 / 60.0,
				{up = true, shift = true},
			) ==
			"",
		)
		testing.expect(t, world.transforms[0].position.x == 5)
		testing.expect(
			t,
			reconcile(
				state,
				&world,
				1280,
				720,
				{},
				1280,
				300,
				1.0 / 60.0,
				{down = true, fine = true, enter = true},
			) ==
			"",
		)
		testing.expect(t, math.abs(world.transforms[0].position.x - 4.99) < 0.001)

		// Dragging the X axis label scrubs, commits on release, and participates in undo/redo.
		x_node = find_node_by_entity_index(state, position_inputs[0])
		if x_node >= 0 {
			start := shared.Vec2 {
				state.nodes[x_node].rect.x + 7,
				state.nodes[x_node].rect.y + state.nodes[x_node].rect.height * 0.5,
			}
			testing.expect(
				t,
				reconcile(
					state,
					&world,
					1280,
					720,
					{position = start, primary_down = true, available = true},
					1280,
					300,
				) ==
				"",
			)
			drag := start
			drag.x += 40
			testing.expect(
				t,
				reconcile(
					state,
					&world,
					1280,
					720,
					{position = drag, primary_down = true, available = true},
					1280,
					300,
				) ==
				"",
			)
			scrubbed := world.transforms[0].position.x
			testing.expect(t, math.abs(scrubbed - 5.99) < 0.001)
			testing.expect(
				t,
				reconcile(
					state,
					&world,
					1280,
					720,
					{position = drag, available = true},
					1280,
					300,
				) ==
				"",
			)
			testing.expect(t, state.editor_history_count > 0)
			if state.editor_history_count > 0 {
				command := state.editor_history[state.editor_history_count - 1]
				testing.expect(t, math.abs(command.changes[0].before_number - 4.99) < 0.001)
				testing.expect(t, math.abs(command.changes[0].after_number - scrubbed) < 0.001)
			}
			testing.expect(
				t,
				reconcile(state, &world, 1280, 720, {}, 1280, 300, 0, {undo = true}) == "",
			)
			testing.expect(t, math.abs(world.transforms[0].position.x - 4.99) < 0.001)
			testing.expect(
				t,
				reconcile(state, &world, 1280, 720, {}, 1280, 300, 0, {redo = true}) == "",
			)
			testing.expect(t, math.abs(world.transforms[0].position.x - scrubbed) < 0.001)
		}

		// Field constraints reject out-of-range but syntactically valid values.
		if fov_input >= 0 {
			focus_input(state, &world, fov_input)
			testing.expect(
				t,
				reconcile(state, &world, 1280, 720, {}, 1280, 300, 0, {text = "200"}) == "",
			)
			testing.expect(t, !state.input_valid)
			testing.expect(t, world.cameras[0].fov == 60)
			testing.expect(
				t,
				reconcile(state, &world, 1280, 720, {}, 1280, 300, 0, {escape = true}) == "",
			)
		}

		// Editor history shortcuts do not leak into the project while chrome is closed.
		before_hidden_undo := world.transforms[0].position.x
		state.editor_visible = false
		testing.expect(
			t,
			reconcile(state, &world, 1280, 720, {}, 1280, 300, 0, {undo = true}) == "",
		)
		testing.expect(t, world.transforms[0].position.x == before_hidden_undo)
		state.editor_visible = true

		// History refuses to cross a component remove/re-add boundary on the same entity.
		ecs.remove_transform(&world, 0)
		ecs.add_transform(&world, 0, {position = {77, 8, 9}, scale = {1, 1, 1}})
		testing.expect(t, !editor_history_apply(state, &world, false))
		testing.expect(t, world.transforms[world.entities[0].transform_index].position.x == 77)
	}
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300) == "")
	inspector_node = find_editor_role_node(state, .Inspector_Scroll)
	testing.expect(t, inspector_node >= 0)
	inspector_rect := state.nodes[inspector_node].rect
	testing.expect(
		t,
		reconcile(
			state,
			&world,
			1280,
			720,
			{
				position = {inspector_rect.x + 20, inspector_rect.y + 20},
				wheel_y = -4,
				available = true,
			},
			1280,
			300,
		) ==
		"",
	)
	testing.expect(t, state.nodes[inspector_node].scroll_offset > 0)
	testing.expect(
		t,
		state.nodes[inspector_node].scroll_offset < state.nodes[inspector_node].scroll_target,
	)
	browser_node := find_editor_role_node(state, .Browser_Scroll)
	testing.expect(t, browser_node >= 0 && state.nodes[browser_node].scroll_offset == 0)

	// Inspector focus cannot outlive the target component or entity represented by a pooled input.
	if position_input >= 0 {
		if button_input >= 0 {
			focus_input(state, &world, button_input)
			button_index := world.entities[0].ui_button_index
			world.entities[0].ui_button_index = -1
			testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300, 0.21) == "")
			testing.expect(t, !state.has_focused_input)
			world.entities[0].ui_button_index = button_index
		}

		focus_input(state, &world, position_input)
		transform_index := world.entities[0].transform_index
		world.entities[0].transform_index = -1
		testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300, 0) == "")
		testing.expect(t, !state.has_focused_input)
		world.entities[0].transform_index = transform_index

		focus_input(state, &world, position_input)
		world.entities[0].alive = false
		testing.expect(t, reconcile(state, &world, 1280, 720, {}, 1280, 300, 0) == "")
		testing.expect(t, !state.has_focused_input)
		testing.expect(t, !state.editor_has_selection)
	}
}

@(test)
test_editor_history_bounds_branches_and_skips_stale_commands :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "First",
			has_transform = true,
			transform = {position = {0, 0, 0}, scale = {1, 1, 1}},
		},
		shared.Scene_Entity {
			name = "Second",
			has_transform = true,
			transform = {position = {10, 0, 0}, scale = {1, 1, 1}},
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	first := shared.Editor_UI_Component {
		target = world.entities[0].id,
		inspector_field = .Transform_Position,
		inspector_axis = .X,
	}
	second := first
	second.target = world.entities[1].id

	for index in 0 ..< EDITOR_HISTORY_CAPACITY + 2 {
		editor_history_push(state, &world, first, f32(index), f32(index + 1))
	}
	testing.expect(t, state.editor_history_count == EDITOR_HISTORY_CAPACITY)
	testing.expect(t, state.editor_history_cursor == EDITOR_HISTORY_CAPACITY)
	testing.expect(t, state.editor_history[0].changes[0].before_number == 2)
	testing.expect(
		t,
		state.editor_history[EDITOR_HISTORY_CAPACITY - 1].changes[0].after_number == 130,
	)

	state.editor_history_count = 0
	state.editor_history_cursor = 0
	world.transforms[world.entities[0].transform_index].position.x = 1
	editor_history_push(state, &world, first, 0, 1)
	world.transforms[world.entities[0].transform_index].position.x = 2
	editor_history_push(state, &world, first, 1, 2)
	testing.expect(t, editor_history_apply(state, &world, false))
	testing.expect(t, world.transforms[world.entities[0].transform_index].position.x == 1)
	world.transforms[world.entities[0].transform_index].position.x = 3
	editor_history_push(state, &world, first, 1, 3)
	testing.expect(t, state.editor_history_count == 2)
	testing.expect(t, state.editor_history_cursor == 2)
	testing.expect(t, state.editor_history[1].changes[0].after_number == 3)
	testing.expect(t, !editor_history_apply(state, &world, true))
	testing.expect(t, world.transforms[world.entities[0].transform_index].position.x == 3)

	state.editor_history_count = 0
	state.editor_history_cursor = 0
	world.transforms[world.entities[1].transform_index].position.x = 11
	editor_history_push(state, &world, second, 10, 11)
	world.transforms[world.entities[0].transform_index].position.x = 4
	editor_history_push(state, &world, first, 3, 4)
	ecs.remove_transform(&world, 0)
	ecs.add_transform(&world, 0, {position = {77, 0, 0}, scale = {1, 1, 1}})
	testing.expect(t, editor_history_apply(state, &world, false))
	testing.expect(t, state.editor_history_count == 1)
	testing.expect(t, state.editor_history_cursor == 0)
	testing.expect(t, world.transforms[world.entities[0].transform_index].position.x == 77)
	testing.expect(t, world.transforms[world.entities[1].transform_index].position.x == 10)
}

@(test)
test_editor_history_transactions_undo_and_redo_boolean_changes :: proc(t: ^testing.T) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Undo Checkbox"),
			name = "Undo Checkbox",
			has_ui_layout = true,
			ui_layout = {size = {80, 32}},
			has_ui_checkbox = true,
			ui_checkbox = shared.ui_checkbox_default(),
		},
	)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_simulation_playing = false
	state.editor_simulation_stopped = true
	binding := shared.Editor_UI_Component {
		target = world.entities[0].id,
		inspector_field = .UI_Checkbox_Checked,
	}
	testing.expect(t, write_inspector_bool(state, &world, binding, true))
	editor_history_push_bool(state, &world, binding, false, true)
	testing.expect(t, state.editor_history_count == 1)
	testing.expect(t, state.editor_history[0].changes[0].kind == .Boolean)
	complete_scene_save(state, true)
	testing.expect(t, state.editor_history_count == 1)
	testing.expect(t, !state.editor_scene_dirty && len(state.editor_dirty_entities) == 0)
	testing.expect(t, editor_history_apply(state, &world, false))
	testing.expect(t, !world.ui_checkboxes[world.entities[0].ui_checkbox_index].checked)
	testing.expect(t, state.editor_scene_dirty && len(state.editor_dirty_entities) == 1)
	testing.expect(t, editor_history_apply(state, &world, true))
	testing.expect(t, world.ui_checkboxes[world.entities[0].ui_checkbox_index].checked)
	testing.expect(t, len(state.editor_dirty_entities) == 1)
	editor_stop(state)
	testing.expect(t, state.editor_history_count == 0)
	testing.expect(t, !state.editor_scene_dirty && len(state.editor_dirty_entities) == 0)
}

@(test)
test_editor_entity_and_component_snapshots_refresh_at_five_hz :: proc(t: ^testing.T) {
	scene := shared.Scene{}; defer delete(scene.entities)
	append(
		&scene.entities,
		shared.Scene_Entity {
			name = "First",
			has_transform = true,
			transform = {position = {1, 2, 3}, scale = {1, 1, 1}},
		},
		shared.Scene_Entity{name = "Second"},
	)
	world := ecs.build_world(&scene); defer ecs.destroy_world(&world)
	world.entities[1].alive = false
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	state.editor_visible = true
	testing.expect(t, editor_select_entity(state, &world, world.entities[0].id, 720))
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0) == "")
	testing.expect(t, state.editor_snapshot_refresh_count == 1)
	testing.expect(t, editor_browser_row_count(&world) == 1)

	world.entities[1].alive = true
	world.transforms[world.entities[0].transform_index].position.x = 99
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0.1) == "")
	testing.expect(t, state.editor_snapshot_refresh_count == 1)
	testing.expect(t, editor_browser_row_count(&world) == 1)
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0.11) == "")
	testing.expect(t, state.editor_snapshot_refresh_count == 2)
	testing.expect(t, editor_browser_row_count(&world) == 2)

	// Selection changes bypass the interval so the inspector never opens stale.
	testing.expect(t, editor_select_entity(state, &world, world.entities[1].id, 720))
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0) == "")
	testing.expect(t, state.editor_snapshot_refresh_count == 3)
}

@(test)
test_editor_system_profile_uses_selectable_list_panel_and_scroll_components :: proc(
	t: ^testing.T,
) {
	scene := shared.Scene{}
	defer delete(scene.entities)
	world := ecs.build_world(&scene)
	defer ecs.destroy_world(&world)
	profile: shared.System_Profile
	profile.entry_count = 3
	profile.sample_frames = 10
	profile.revision = 1
	profile.entries[0].kind = .Project_Odin
	profile.entries[0].average_nanoseconds = 1_500_000
	physics_name := "Physics"
	profile.entries[0].name_length = len(physics_name)
	for index in 0 ..< len(physics_name) {
		profile.entries[0].name[index] = physics_name[index]
	}
	profile.entries[1].kind = .Luau
	profile.entries[1].average_nanoseconds = 2_500
	luau_name := "Orbit Lights"
	profile.entries[1].name_length = len(luau_name)
	for index in 0 ..< len(luau_name) {
		profile.entries[1].name[index] = luau_name[index]
	}
	profile.entries[2].kind = .Luau
	profile.entries[2].average_nanoseconds = 4_000
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	state.system_profile = &profile

	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0) == "")
	systems, found := editor_ui_entity(&world, .Systems_Scroll)
	testing.expect(t, found)
	if found {
		entity := world.entities[systems]
		testing.expect(t, entity.ui_panel_index >= 0)
		testing.expect(t, entity.ui_list_index >= 0)
		testing.expect(t, entity.ui_scroll_area_index >= 0)
		testing.expect(t, world.ui_panels[entity.ui_panel_index].title == "SYSTEMS / 3")
		layout := world.ui_layouts[entity.ui_layout_index]
		testing.expect(t, layout.padding == (shared.Vec4{}))
		testing.expect(t, layout.background == EDITOR_LIST_BACKGROUND)
	}
	first_row, first_row_found := editor_ui_entity(&world, .Systems_Row, 0)
	name_cell, name_found := editor_ui_entity(&world, .Systems_Name, 0)
	time_cell, time_found := editor_ui_entity(&world, .Systems_Time, 0)
	luau_cell, luau_found := editor_ui_entity(&world, .Systems_Name, 1)
	luau_time_cell, luau_time_found := editor_ui_entity(&world, .Systems_Time, 1)
	fallback_cell, fallback_found := editor_ui_entity(&world, .Systems_Name, 2)
	testing.expect(
		t,
		first_row_found &&
		name_found &&
		time_found &&
		luau_found &&
		luau_time_found &&
		fallback_found,
	)
	if name_found {
		text := world.ui_texts[world.entities[name_cell].ui_text_index]
		testing.expect(t, text.text == "Physics")
		testing.expect(t, text.size == EDITOR_TEXT_SIZE)
	}
	if time_found {
		text := world.ui_texts[world.entities[time_cell].ui_text_index]
		testing.expect(t, text.text == "1.500 ms")
		testing.expect(t, text.size == EDITOR_TEXT_SIZE)
		testing.expect(t, text.alignment == .Right)
	}
	if luau_found {
		text := world.ui_texts[world.entities[luau_cell].ui_text_index]
		testing.expect(t, text.text == luau_name)
	}
	if luau_time_found {
		text := world.ui_texts[world.entities[luau_time_cell].ui_text_index]
		testing.expect(t, text.text == "0.003 ms")
	}
	if fallback_found {
		text := world.ui_texts[world.entities[fallback_cell].ui_text_index]
		testing.expect(t, text.text == "Luau System 2")
	}
	if found && first_row_found && name_found {
		row_layout := world.ui_layouts[world.entities[first_row].ui_layout_index]
		testing.expect(t, row_layout.padding.y == 8 && row_layout.padding.w == 8)
		name_layout := world.ui_layouts[world.entities[name_cell].ui_layout_index]
		testing.expect(t, name_layout.padding.w == 16)
		systems_node := find_node_by_entity_index(state, systems)
		row_node := find_node_by_entity_index(state, first_row)
		testing.expect(t, systems_node >= 0 && row_node >= 0)
		if systems_node >= 0 && row_node >= 0 {
			testing.expect(
				t,
				math.abs(state.nodes[row_node].rect.x - state.nodes[systems_node].rect.x) < 0.01,
			)
			testing.expect(
				t,
				math.abs(state.nodes[row_node].rect.width - state.nodes[systems_node].rect.width) <
				0.01,
			)
		}
		name_node := find_node_by_entity_index(state, name_cell)
		testing.expect(t, name_node >= 0)
		if name_node >= 0 {
			name_rect := state.nodes[name_node].rect
			testing.expect(
				t,
				reconcile(
					state,
					&world,
					1280,
					720,
					{
						position = {name_rect.x + 10, name_rect.y + name_rect.height * 0.5},
						primary_down = true,
						available = true,
					},
				) ==
				"",
			)
			list := world.ui_lists[world.entities[systems].ui_list_index]
			testing.expect(t, list.selected == world.entities[first_row].uuid)
		}
	}
	project_origin, project_origin_found := editor_ui_entity(&world, .Systems_Origin, 0)
	luau_origin, luau_origin_found := editor_ui_entity(&world, .Systems_Origin, 1)
	testing.expect(t, project_origin_found && luau_origin_found)
	if project_origin_found {
		layout := world.ui_layouts[world.entities[project_origin].ui_layout_index]
		testing.expect(t, layout.background == system_profile_origin_color(.Project_Odin))
	}
	if luau_origin_found {
		layout := world.ui_layouts[world.entities[luau_origin].ui_layout_index]
		testing.expect(t, layout.background == system_profile_origin_color(.Luau))
	}
	first_row_entity := world.entities[first_row]
	testing.expect(t, first_row_entity.ui_progress_index >= 0)
	if first_row_entity.ui_progress_index >= 0 {
		progress := world.ui_progresses[first_row_entity.ui_progress_index]
		testing.expect(t, progress.fill_color == system_profile_origin_color(.Project_Odin))
		testing.expect(t, progress.value == f32(profile.entries[0].average_nanoseconds))
		testing.expect(t, progress.maximum == f32(SYSTEM_PROFILE_BAR_MAX_NANOSECONDS))
		testing.expect(t, progress.right_to_left)
	}
	testing.expect(
		t,
		system_profile_origin_color(.Engine) != system_profile_origin_color(.Project_Odin) &&
		system_profile_origin_color(.Engine) != system_profile_origin_color(.Luau),
	)

	refresh_count := state.editor_snapshot_refresh_count
	profile.entries[0].average_nanoseconds = 750_000
	profile.revision += 1
	testing.expect(t, reconcile(state, &world, 1280, 720, {}, 0, 0, 0) == "")
	testing.expect(t, state.editor_snapshot_refresh_count == refresh_count + 1)
	if time_found {
		text := world.ui_texts[world.entities[time_cell].ui_text_index]
		testing.expect(t, text.text == "0.750 ms")
	}
}

@(test)
test_editor_gizmo_appends_three_axis_lines_and_handles :: proc(t: ^testing.T) {
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	state.editor_gizmo_visible =
		true; state.editor_gizmo_origin = {100, 100}; state.editor_gizmo_endpoints = {{180, 100}, {100, 20}, {145, 145}}; state.editor_gizmo_hovered_handle = .Y
	testing.expect(t, append_editor_gizmo(state) == "")
	line_count, triangle_count := 0, 0; active_color_line_found := false
	for command in state.paint[:state.paint_count] {
		if command.kind ==
		   .Line { line_count += 1; if command.color.y > 0.8 && command.line_thickness == 5 { active_color_line_found = true } }
		if command.kind == .Triangle { triangle_count += 1 }
		testing.expect(t, command.color.x > 0.1 || command.color.y > 0.1 || command.color.z > 0.1)
	}
	testing.expect(t, line_count == 3)
	testing.expect(t, triangle_count == 9)
	testing.expect(t, active_color_line_found)
	center_handle_found := false
	for command in state.paint[:state.paint_count] { if command.kind == .Panel && command.rect.width == 11 { center_handle_found = true } }
	testing.expect(t, center_handle_found)
}

@(test)
test_editor_gizmo_modes_render_rings_and_square_scale_handles :: proc(t: ^testing.T) {
	state := new(
		State,
	); defer free(state); testing.expect(t, init(state) == ""); defer destroy(state)
	state.editor_gizmo_visible =
		true; state.editor_gizmo_origin = {100, 100}; state.editor_gizmo_endpoints = {{180, 100}, {100, 20}, {145, 145}}
	for axis in 0 ..< 3 { for point_index in 0 ..< EDITOR_GIZMO_RING_POINT_COUNT { angle := f32(point_index) / EDITOR_GIZMO_RING_POINT_COUNT * 2 * math.PI; state.editor_gizmo_ring_points[axis][point_index] = {100 + math.cos(angle) * 60, 100 + math.sin(angle) * 60} } }
	state.editor_gizmo_mode = .Rotate
	testing.expect(t, append_editor_gizmo(state) == "")
	ring_count := 0
	for command in state.paint[:state.paint_count] { if command.kind == .Ring { ring_count += 1; testing.expect(t, command.ring_thickness == 1.35); testing.expect(t, command.ring_axis_x != shared.Vec2{} && command.ring_axis_y != shared.Vec2{}) } }
	testing.expect(t, ring_count == 3)

	state.paint_count = 0; state.editor_gizmo_mode = .Scale
	testing.expect(t, append_editor_gizmo(state) == "")
	square_handle_found := false
	for command in state.paint[:state.paint_count] { if command.kind == .Panel && command.rect.width == 12 && command.corner_radius == 1.5 { square_handle_found = true; break } }
	testing.expect(t, square_handle_found)

	state.editor_snapshot_valid =
		true; state.editor_gizmo_active_handle = .X; state.editor_gizmo_captures_pointer = true
	editor_set_gizmo_mode(state, .Translate)
	testing.expect(t, state.editor_gizmo_mode == .Translate && !state.editor_snapshot_valid)
	testing.expect(
		t,
		state.editor_gizmo_active_handle == .None && !state.editor_gizmo_captures_pointer,
	)
}
