package ecs

import shared "../shared"
import "core:testing"

@(test)
test_ui_event_history_is_bounded_immutable_and_reports_cursor_overflow :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)
	for _ in 0 ..< shared.MAX_UI_EVENTS + 1 {
		sequence := append_ui_event(
			&world,
			{kind = .Activated, origin = .Scene, action = "test.activate", payload = "alpha"},
		)
		testing.expect(t, sequence > 0)
	}
	testing.expect_value(t, ui_event_latest_sequence(&world), u64(shared.MAX_UI_EVENTS + 1))
	testing.expect_value(t, ui_event_oldest_sequence(&world), u64(2))
	testing.expect_value(t, ui_event_count_after(&world, 0), shared.MAX_UI_EVENTS)
	testing.expect(t, ui_event_history_overflowed(&world, 0))
	first, first_ok := ui_event_after_at(&world, 0, 0)
	testing.expect(t, first_ok)
	testing.expect_value(t, first.sequence, u64(2))
	again, again_ok := ui_event_after_at(&world, 0, 0)
	testing.expect(t, again_ok)
	testing.expect_value(t, again.sequence, first.sequence)

	oversized := shared.UI_Event {
		action = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	}
	testing.expect_value(t, append_ui_event(&world, oversized), u64(0))
	testing.expect_value(t, ui_event_latest_sequence(&world), u64(shared.MAX_UI_EVENTS + 1))
}

@(test)
test_ui_action_inherits_from_nearest_layout_ancestor :: proc(t: ^testing.T) {
	world: World
	defer destroy_world(&world)
	parent_index, parent_created := create_world_entity(&world, "Parent")
	child_index, child_created := create_world_entity(&world, "Child")
	testing.expect(t, parent_created && child_created)
	testing.expect(t, set_ui_layout(&world, parent_index, {size = {100, 40}}))
	testing.expect(
		t,
		set_ui_layout(
			&world,
			child_index,
			{parent = world.entities[parent_index].uuid, size = {80, 32}},
		),
	)
	testing.expect(
		t,
		set_ui_action(&world, parent_index, {action = "menu.launch", payload = "campaign"}),
	)
	action_entity, action, payload := ui_action_for_entity(&world, child_index)
	testing.expect_value(t, action_entity, world.entities[parent_index].uuid)
	testing.expect(t, action == "menu.launch")
	testing.expect(t, payload == "campaign")
}
