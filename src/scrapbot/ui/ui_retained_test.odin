package ui

import ecs "../ecs"
import shared "../shared"
import "core:testing"

expect_retained_hierarchy_consistent :: proc(t: ^testing.T, state: ^State) {
	if state == nil {
		testing.expect(t, false)
		return
	}
	incoming_edges: [MAX_NODES]int
	paint_orders: [MAX_NODES]bool
	for parent_index in 0 ..< state.node_count {
		child_index := state.nodes[parent_index].first_child_node
		previous_child := -1
		steps := 0
		for child_index >= 0 {
			testing.expect(t, child_index < state.node_count)
			if child_index >= state.node_count {
				break
			}
			steps += 1
			testing.expect(t, steps <= state.node_count)
			if steps > state.node_count {
				break
			}
			testing.expect(t, state.nodes[child_index].parent_node_index == parent_index)
			testing.expect(t, child_index > previous_child)
			incoming_edges[child_index] += 1
			previous_child = child_index
			child_index = state.nodes[child_index].next_sibling_node
		}
	}
	for node, node_index in state.nodes[:state.node_count] {
		if node.parent_node_index < 0 {
			testing.expect(t, incoming_edges[node_index] == 0)
		} else {
			testing.expect(t, node.parent_node_index < state.node_count)
			testing.expect(t, incoming_edges[node_index] == 1)
		}
		testing.expect(t, node.laid_out)
		testing.expect(t, node.paint_order >= 0 && node.paint_order < state.node_count)
		if node.paint_order >= 0 && node.paint_order < state.node_count {
			testing.expect(t, !paint_orders[node.paint_order])
			paint_orders[node.paint_order] = true
		}
	}
	for index in 0 ..< state.node_count {
		testing.expect(t, paint_orders[index])
	}
}

@(test)
test_retained_layout_and_paint_visit_only_nodes_and_hierarchy_edges :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	root_index, created := ecs.create_world_entity(&world, "Root")
	testing.expect(t, created)
	testing.expect(t, ecs.set_ui_layout(&world, root_index, {size = {640, 640}}))
	testing.expect(t, ecs.set_ui_vstack(&world, root_index, {fill = true}))
	root_uuid := world.entities[root_index].uuid
	child_count := 128
	for child_ordinal in 0 ..< child_count {
		child_index, child_created := ecs.create_world_entity(&world, "Child")
		testing.expect(t, child_created)
		testing.expect(
			t,
			ecs.set_ui_layout(&world, child_index, {parent = root_uuid, size = {1, 1}}),
		)
	}
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)

	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	node_count := child_count + 1
	edge_count := child_count
	testing.expect(t, state.node_count == node_count)
	testing.expect(t, state.layout_node_visit_count == u64(node_count))
	testing.expect(t, state.layout_child_edge_visit_count == u64(edge_count * 2))
	testing.expect(t, state.paint_node_visit_count == u64(node_count))
	testing.expect(t, state.paint_child_edge_visit_count == u64(edge_count))
	expect_retained_hierarchy_consistent(t, state)

	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.layout_node_visit_count == 0)
	testing.expect(t, state.layout_child_edge_visit_count == 0)
	testing.expect(t, state.paint_node_visit_count == 0)
	testing.expect(t, state.paint_child_edge_visit_count == 0)
	expect_retained_hierarchy_consistent(t, state)

	// Paint-only changes invalidate retained commands without forcing layout.
	world.ui_layouts[world.entities[root_index].ui_layout_index].background = {0.2, 0.3, 0.4, 1}
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.layout_node_visit_count == 0)
	testing.expect(t, state.layout_child_edge_visit_count == 0)
	testing.expect(t, state.paint_node_visit_count == u64(node_count))
	testing.expect(t, state.paint_child_edge_visit_count == u64(edge_count))
}

@(test)
test_layout_changes_only_reflow_the_affected_ui_origin :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	project_index, project_created := ecs.create_world_entity(&world, "Project Root")
	editor_index, editor_created := ecs.create_world_entity(&world, "Editor Root")
	testing.expect(t, project_created && editor_created)
	world.entities[project_index].origin = .Scene
	world.entities[editor_index].origin = .Editor
	testing.expect(t, ecs.set_ui_layout(&world, project_index, {size = {320, 200}}))
	testing.expect(t, ecs.set_ui_layout(&world, editor_index, {size = {240, 180}}))
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	state.editor_visible = true
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	editor_node_count := 0
	for node in state.nodes[:state.node_count] {
		if node.origin == .Editor {
			editor_node_count += 1
		}
	}
	testing.expect(t, editor_node_count > 0)

	editor_layout := world.ui_layouts[world.entities[editor_index].ui_layout_index]
	editor_layout.size.x += 10
	testing.expect(t, ecs.set_ui_layout(&world, editor_index, editor_layout))
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.layout_node_visit_count == u64(editor_node_count))
	testing.expect(t, state.paint_node_visit_count == u64(editor_node_count))
}

@(test)
test_ui_value_updates_do_not_trigger_structural_synchronization :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	entity_index, created := ecs.create_world_entity(&world, "Everything")
	testing.expect(t, created)
	testing.expect(t, ecs.set_ui_layout(&world, entity_index, {size = {320, 240}}))
	testing.expect(t, ecs.set_ui_hstack(&world, entity_index, {}))
	testing.expect(t, ecs.set_ui_vstack(&world, entity_index, {}))
	testing.expect(
		t,
		ecs.set_ui_scroll_area(&world, entity_index, shared.ui_scroll_area_default()),
	)
	panel := shared.ui_panel_default()
	panel.title = "Panel"
	testing.expect(t, ecs.set_ui_panel(&world, entity_index, panel))
	testing.expect(t, ecs.set_ui_table(&world, entity_index, shared.ui_table_default()))
	testing.expect(t, ecs.set_ui_list(&world, entity_index, shared.ui_list_default()))
	testing.expect(t, ecs.set_ui_progress(&world, entity_index, shared.ui_progress_default()))
	text := shared.ui_text_default()
	text.text = "Text"
	testing.expect(t, ecs.set_ui_text(&world, entity_index, text))
	button := shared.ui_button_default()
	button.text = "Button"
	testing.expect(t, ecs.set_ui_button(&world, entity_index, button))
	input := shared.ui_input_default()
	input.text = "Input"
	testing.expect(t, ecs.set_ui_input(&world, entity_index, input))
	testing.expect(t, ecs.set_ui_checkbox(&world, entity_index, shared.ui_checkbox_default()))
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")

	sync_count := state.ui_structure_sync_count
	structure_revision := world.ui_structure_revision
	layout := world.ui_layouts[world.entities[entity_index].ui_layout_index]
	layout.size.x += 1
	testing.expect(t, ecs.set_ui_layout(&world, entity_index, layout))
	hstack := world.ui_hstacks[world.entities[entity_index].ui_hstack_index]
	hstack.gap += 1
	testing.expect(t, ecs.set_ui_hstack(&world, entity_index, hstack))
	vstack := world.ui_vstacks[world.entities[entity_index].ui_vstack_index]
	vstack.gap += 1
	testing.expect(t, ecs.set_ui_vstack(&world, entity_index, vstack))
	scroll := world.ui_scroll_areas[world.entities[entity_index].ui_scroll_area_index]
	scroll.smoothness += 1
	testing.expect(t, ecs.set_ui_scroll_area(&world, entity_index, scroll))
	panel = world.ui_panels[world.entities[entity_index].ui_panel_index]
	panel.title_height += 1
	testing.expect(t, ecs.set_ui_panel(&world, entity_index, panel))
	table := world.ui_tables[world.entities[entity_index].ui_table_index]
	table.column_gap += 1
	testing.expect(t, ecs.set_ui_table(&world, entity_index, table))
	list := world.ui_lists[world.entities[entity_index].ui_list_index]
	list.gap += 1
	testing.expect(t, ecs.set_ui_list(&world, entity_index, list))
	progress := world.ui_progresses[world.entities[entity_index].ui_progress_index]
	progress.value += 0.5
	testing.expect(t, ecs.set_ui_progress(&world, entity_index, progress))
	text = world.ui_texts[world.entities[entity_index].ui_text_index]
	text.size += 1
	testing.expect(t, ecs.set_ui_text(&world, entity_index, text))
	button = world.ui_buttons[world.entities[entity_index].ui_button_index]
	button.size += 1
	testing.expect(t, ecs.set_ui_button(&world, entity_index, button))
	input = world.ui_inputs[world.entities[entity_index].ui_input_index]
	input.size += 1
	testing.expect(t, ecs.set_ui_input(&world, entity_index, input))
	checkbox := world.ui_checkboxes[world.entities[entity_index].ui_checkbox_index]
	checkbox.checked = true
	testing.expect(t, ecs.set_ui_checkbox(&world, entity_index, checkbox))
	testing.expect(t, ecs.set_ui_text_value(&world, entity_index, "Updated text"))
	testing.expect(t, ecs.set_ui_input_value(&world, entity_index, "Updated input"))
	testing.expect(t, ecs.set_ui_input_prefix(&world, entity_index, "X"))
	testing.expect(t, ecs.set_ui_panel_title(&world, entity_index, "Updated panel"))
	testing.expect(t, world.ui_structure_revision == structure_revision)
	testing.expect(t, len(world.ui_dirty_entities) == 0)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.ui_structure_sync_count == sync_count)
}

@(test)
test_ui_membership_parent_and_visibility_changes_sync_once :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	root_index, root_created := ecs.create_world_entity(&world, "Root")
	child_index, child_created := ecs.create_world_entity(&world, "Child")
	testing.expect(t, root_created && child_created)
	testing.expect(t, ecs.set_ui_layout(&world, root_index, {size = {200, 200}}))
	testing.expect(t, ecs.set_ui_layout(&world, child_index, {size = {40, 40}}))
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")

	expected_sync_count := state.ui_structure_sync_count
	testing.expect(t, ecs.set_ui_hstack(&world, child_index, {}))
	expected_sync_count += 1
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.ui_structure_sync_count == expected_sync_count)
	testing.expect(t, ecs.remove_ui_component(&world, child_index, "scrapbot.ui_hstack"))
	expected_sync_count += 1
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.ui_structure_sync_count == expected_sync_count)
	testing.expect(t, ecs.set_ui_parent(&world, child_index, world.entities[root_index].uuid))
	expected_sync_count += 1
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.ui_structure_sync_count == expected_sync_count)
	testing.expect(t, ecs.set_ui_hidden(&world, root_index, true))
	expected_sync_count += 1
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.ui_structure_sync_count == expected_sync_count)
	testing.expect(t, state.node_count == 0)
	testing.expect(t, ecs.set_ui_hidden(&world, root_index, false))
	expected_sync_count += 1
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.ui_structure_sync_count == expected_sync_count)
	testing.expect(t, state.node_count == 2)
	child_layout := world.ui_layouts[world.entities[child_index].ui_layout_index]
	child_layout.parent = {}
	testing.expect(t, ecs.set_ui_layout(&world, child_index, child_layout))
	expected_sync_count += 1
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.ui_structure_sync_count == expected_sync_count)
	child_layout.hidden = true
	testing.expect(t, ecs.set_ui_layout(&world, child_index, child_layout))
	expected_sync_count += 1
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.ui_structure_sync_count == expected_sync_count)
	testing.expect(t, state.node_count == 1)
}

@(test)
test_retained_node_replacement_is_generation_safe :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	entity_index, created := ecs.create_world_entity(&world, "Old")
	testing.expect(t, created)
	testing.expect(t, ecs.set_ui_layout(&world, entity_index, {size = {200, 100}}))
	testing.expect(
		t,
		ecs.set_ui_scroll_area(&world, entity_index, shared.ui_scroll_area_default()),
	)
	testing.expect(t, ecs.set_ui_input(&world, entity_index, shared.ui_input_default()))
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	old_entity := world.entities[entity_index].id
	old_node := find_node(state, old_entity)
	testing.expect(t, old_node >= 0)
	if old_node >= 0 {
		state.nodes[old_node].scroll_offset = 42
		state.nodes[old_node].scroll_target = 64
		state.nodes[old_node].hovered = true
		state.nodes[old_node].active = true
	}
	focus_input(state, &world, entity_index)
	state.active_entity = old_entity
	state.has_active_entity = true
	ecs.despawn_entity(&world, entity_index, old_entity.generation)
	replacement_index, replacement_created := ecs.create_world_entity(&world, "Replacement")
	testing.expect(t, replacement_created)
	testing.expect(t, replacement_index == entity_index)
	testing.expect(t, ecs.set_ui_layout(&world, replacement_index, {size = {80, 40}}))
	testing.expect(
		t,
		ecs.set_ui_scroll_area(&world, replacement_index, shared.ui_scroll_area_default()),
	)
	new_entity := world.entities[replacement_index].id
	testing.expect(t, new_entity != old_entity)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	new_node := find_node(state, new_entity)
	testing.expect(t, find_node(state, old_entity) == -1)
	testing.expect(t, new_node >= 0)
	if new_node >= 0 {
		testing.expect(t, state.nodes[new_node].scroll_offset == 0)
		testing.expect(t, state.nodes[new_node].scroll_target == 0)
		testing.expect(t, !state.nodes[new_node].hovered)
		testing.expect(t, !state.nodes[new_node].active)
	}
	testing.expect(t, !state.has_focused_input)
	testing.expect(t, !state.has_active_entity)
}

@(test)
test_world_replacement_resets_retained_interaction_and_scroll_state :: proc(t: ^testing.T) {
	first_scene := shared.Scene{}
	defer delete(first_scene.entities)
	append(
		&first_scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Shared UI"),
			name = "First",
			has_ui_layout = true,
			ui_layout = {size = {200, 100}},
			has_ui_scroll_area = true,
			ui_scroll_area = shared.ui_scroll_area_default(),
			has_ui_input = true,
			ui_input = shared.ui_input_default(),
		},
	)
	second_scene := shared.Scene{}
	defer delete(second_scene.entities)
	append(
		&second_scene.entities,
		shared.Scene_Entity {
			id = ui_test_id("Shared UI"),
			name = "Second",
			has_ui_layout = true,
			ui_layout = {size = {300, 120}},
			has_ui_scroll_area = true,
			ui_scroll_area = shared.ui_scroll_area_default(),
			has_ui_input = true,
			ui_input = shared.ui_input_default(),
		},
	)
	first_world := ecs.build_world(&first_scene)
	defer ecs.destroy_world(&first_world)
	second_world := ecs.build_world(&second_scene)
	defer ecs.destroy_world(&second_world)
	testing.expect(t, first_world.instance_uuid != second_world.instance_uuid)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, sync_ui_structure(state, &first_world) == "")
	first_node := find_node_by_entity_index(state, 0)
	testing.expect(t, first_node >= 0)
	if first_node >= 0 {
		state.nodes[first_node].scroll_offset = 30
		state.nodes[first_node].scroll_target = 50
	}
	focus_input(state, &first_world, 0)
	state.active_entity = first_world.entities[0].id
	state.has_active_entity = true
	state.previous_primary_down = true
	state.editor_ui_has_active_entity = true
	state.editor_previous_primary_down = true
	testing.expect(t, sync_ui_structure(state, &second_world) == "")
	second_node := find_node_by_entity_index(state, 0)
	testing.expect(t, second_node >= 0)
	if second_node >= 0 {
		testing.expect(t, state.nodes[second_node].scroll_offset == 0)
		testing.expect(t, state.nodes[second_node].scroll_target == 0)
	}
	testing.expect(t, !state.has_focused_input)
	testing.expect(t, !state.has_active_entity)
	testing.expect(t, !state.previous_primary_down)
	testing.expect(t, !state.editor_ui_has_active_entity)
	testing.expect(t, !state.editor_previous_primary_down)
}

@(test)
test_retained_hierarchy_survives_wide_deep_mutation_churn :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	root_index, root_created := ecs.create_world_entity(&world, "Root")
	testing.expect(t, root_created)
	testing.expect(t, ecs.set_ui_layout(&world, root_index, {size = {800, 800}}))
	testing.expect(t, ecs.set_ui_vstack(&world, root_index, {}))
	root_uuid := world.entities[root_index].uuid
	branch_indices: [8]int
	leaf_indices: [8][4]int
	for branch_ordinal in 0 ..< len(branch_indices) {
		branch_index, branch_created := ecs.create_world_entity(&world, "Branch")
		testing.expect(t, branch_created)
		branch_indices[branch_ordinal] = branch_index
		testing.expect(
			t,
			ecs.set_ui_layout(&world, branch_index, {parent = root_uuid, size = {400, 80}}),
		)
		testing.expect(t, ecs.set_ui_hstack(&world, branch_index, {}))
		branch_uuid := world.entities[branch_index].uuid
		for leaf_ordinal in 0 ..< len(leaf_indices[branch_ordinal]) {
			leaf_index, leaf_created := ecs.create_world_entity(&world, "Leaf")
			testing.expect(t, leaf_created)
			leaf_indices[branch_ordinal][leaf_ordinal] = leaf_index
			testing.expect(
				t,
				ecs.set_ui_layout(&world, leaf_index, {parent = branch_uuid, size = {40, 20}}),
			)
		}
	}
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	expect_retained_hierarchy_consistent(t, state)

	testing.expect(t, ecs.set_ui_hidden(&world, branch_indices[3], true))
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, state.node_count == 1 + 7 * 5)
	expect_retained_hierarchy_consistent(t, state)
	testing.expect(t, ecs.set_ui_hidden(&world, branch_indices[3], false))
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	expect_retained_hierarchy_consistent(t, state)

	testing.expect(
		t,
		ecs.set_ui_parent(&world, branch_indices[6], world.entities[branch_indices[1]].uuid),
	)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	expect_retained_hierarchy_consistent(t, state)

	removed_index := leaf_indices[4][2]
	removed_generation := world.entities[removed_index].id.generation
	ecs.despawn_entity(&world, removed_index, removed_generation)
	replacement_index, replacement_created := ecs.create_world_entity(&world, "Replacement Leaf")
	testing.expect(t, replacement_created)
	testing.expect(t, replacement_index == removed_index)
	testing.expect(
		t,
		ecs.set_ui_layout(
			&world,
			replacement_index,
			{parent = world.entities[branch_indices[7]].uuid, size = {50, 20}},
		),
	)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	expect_retained_hierarchy_consistent(t, state)
}

@(test)
test_runtime_invalid_hierarchies_report_cycles_and_accept_orphans :: proc(t: ^testing.T) {
	world: shared.World
	defer ecs.destroy_world(&world)
	root_index, root_created := ecs.create_world_entity(&world, "Root")
	child_index, child_created := ecs.create_world_entity(&world, "Child")
	testing.expect(t, root_created && child_created)
	testing.expect(t, ecs.set_ui_layout(&world, root_index, {size = {200, 200}}))
	testing.expect(
		t,
		ecs.set_ui_layout(
			&world,
			child_index,
			{parent = world.entities[root_index].uuid, size = {50, 50}},
		),
	)
	state := new(State)
	defer free(state)
	testing.expect(t, init(state) == "")
	defer destroy(state)
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")

	testing.expect(t, ecs.set_ui_parent(&world, root_index, world.entities[child_index].uuid))
	testing.expect(t, reconcile(state, &world, 1280, 720) != "")
	testing.expect(t, ecs.set_ui_parent(&world, root_index, {}))
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	testing.expect(t, ecs.set_ui_parent(&world, root_index, world.entities[root_index].uuid))
	testing.expect(t, reconcile(state, &world, 1280, 720) != "")
	testing.expect(t, ecs.set_ui_parent(&world, root_index, {}))
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")

	missing_parent := shared.entity_uuid_from_engine_name("Missing Parent")
	testing.expect(t, ecs.set_ui_parent(&world, child_index, missing_parent))
	testing.expect(t, reconcile(state, &world, 1280, 720) == "")
	child_node := find_node_by_entity_index(state, child_index)
	testing.expect(t, child_node >= 0)
	if child_node >= 0 {
		testing.expect(t, state.nodes[child_node].parent_entity_index == -1)
		testing.expect(t, state.nodes[child_node].parent_node_index == -1)
	}
	expect_retained_hierarchy_consistent(t, state)
}
