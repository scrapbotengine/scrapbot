package ecs

import shared "../shared"
import "core:math"
import "core:testing"

@(test)
test_time_resource_tracks_delta_elapsed_and_frame_index :: proc(t: ^testing.T) {
	time: shared.Time_Resource
	advance_time(&time, 0.1)
	testing.expect(t, math.abs(time.delta_time - 0.1) < 0.00001)
	testing.expect(t, math.abs(time.smooth_delta_time - 0.1) < 0.00001)
	testing.expect(t, math.abs(time.elapsed_time - 0.1) < 0.00001)
	testing.expect(t, time.frame_index == 1)

	advance_time(&time, 0.2)
	testing.expect(t, time.smooth_delta_time > 0.1 && time.smooth_delta_time < 0.2)
	testing.expect(t, math.abs(time.elapsed_time - 0.3) < 0.00001)
	testing.expect(t, time.frame_index == 2)
}

@(test)
test_time_resource_rejects_negative_delta :: proc(t: ^testing.T) {
	time: shared.Time_Resource
	advance_time(&time, -1)
	testing.expect(t, time.delta_time == 0)
	testing.expect(t, time.elapsed_time == 0)
}

@(test)
test_project_time_components_advance_at_independent_speeds_and_select_stable_default :: proc(
	t: ^testing.T,
) {
	world: shared.World
	defer destroy_world(&world)
	slow_entity, slow_ok := create_world_entity(&world, "Slow Time", {}, .Scene)
	fast_entity, fast_ok := create_world_entity(&world, "Fast Time", {}, .Scene)
	testing.expect(t, slow_ok && fast_ok)
	slow := shared.Custom_Component {
		name = "scrapbot.clock",
	}
	append(&slow.number_fields, shared.Named_Number{name = "speed", value = 0.5})
	defer delete(slow.number_fields)
	fast := shared.Custom_Component {
		name = "scrapbot.clock",
	}
	append(&fast.number_fields, shared.Named_Number{name = "speed", value = 2})
	defer delete(fast.number_fields)
	add_scene_custom_component(&world, slow_entity, slow)
	add_scene_custom_component(&world, fast_entity, fast)

	advance_project_time(&world, 0.2)
	testing.expect(t, math.abs(world.time.delta_time - 0.1) < 0.00001)
	testing.expect(t, math.abs(world.time.elapsed_time - 0.1) < 0.00001)
	storage := find_custom_component_storage(&world, shared.INVALID_COMPONENT_ID, "scrapbot.clock")
	testing.expect(t, storage != nil && len(storage.active_component_indices) == 2)
	slow_component, slow_found := custom_component_for_entity_ref(
		&world,
		slow_entity,
		shared.INVALID_COMPONENT_ID,
		"scrapbot.clock",
	)
	fast_component, fast_found := custom_component_for_entity_ref(
		&world,
		fast_entity,
		shared.INVALID_COMPONENT_ID,
		"scrapbot.clock",
	)
	testing.expect(t, slow_found && fast_found)
	testing.expect(
		t,
		math.abs(time_component_number(slow_component, "elapsed_time")^ - 0.1) < 0.00001,
	)
	testing.expect(
		t,
		math.abs(time_component_number(fast_component, "elapsed_time")^ - 0.4) < 0.00001,
	)

	default_elapsed := world.time.elapsed_time
	slow_elapsed := time_component_number(slow_component, "elapsed_time")^
	fast_elapsed := time_component_number(fast_component, "elapsed_time")^
	// A paused redraw does not call advance_project_time.
	testing.expect_value(t, world.time.elapsed_time, default_elapsed)
	testing.expect_value(t, time_component_number(slow_component, "elapsed_time")^, slow_elapsed)
	testing.expect_value(t, time_component_number(fast_component, "elapsed_time")^, fast_elapsed)
}

@(test)
test_project_time_adopts_a_new_default_clocks_existing_timeline :: proc(t: ^testing.T) {
	world: shared.World
	defer destroy_world(&world)
	first_entity, first_ok := create_world_entity(&world, "First", {}, .Scene)
	second_entity, second_ok := create_world_entity(&world, "Second", {}, .Scene)
	testing.expect(t, first_ok && second_ok)
	first := shared.Custom_Component {
		name = "scrapbot.clock",
	}
	second := shared.Custom_Component {
		name = "scrapbot.clock",
	}
	append(&first.number_fields, shared.Named_Number{name = "speed", value = 1})
	append(&second.number_fields, shared.Named_Number{name = "speed", value = 2})
	defer delete(first.number_fields)
	defer delete(second.number_fields)
	add_scene_custom_component(&world, first_entity, first)
	add_scene_custom_component(&world, second_entity, second)

	advance_project_time(&world, 0.25)
	remove_custom_component(&world, first_entity, shared.INVALID_COMPONENT_ID, "scrapbot.clock")
	advance_project_time(&world, 0.25)

	testing.expect(t, math.abs(world.time.elapsed_time - 1) < 0.00001)
	testing.expect(t, math.abs(world.time.delta_time - 0.5) < 0.00001)
}
