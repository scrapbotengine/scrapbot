package ecs

import shared "../shared"

ui_event_stream_destroy :: proc(world: ^World) {
	if world == nil {
		return
	}
	for offset in 0 ..< world.ui_events.count {
		index := (world.ui_events.start + offset) % shared.MAX_UI_EVENTS
		event := &world.ui_events.events[index]
		delete_world_string(world, event.action)
		delete_world_string(world, event.payload)
		event^ = {}
	}
	world.ui_events = {}
}

append_ui_event :: proc(world: ^World, event: shared.UI_Event) -> u64 {
	if world == nil {
		return 0
	}
	if len(event.action) > shared.UI_ACTION_MAX_BYTES ||
	   len(event.payload) > shared.UI_ACTION_PAYLOAD_MAX_BYTES {
		return 0
	}
	stream := &world.ui_events
	index := 0
	if stream.count < shared.MAX_UI_EVENTS {
		index = (stream.start + stream.count) % shared.MAX_UI_EVENTS
		stream.count += 1
	} else {
		index = stream.start
		stream.start = (stream.start + 1) % shared.MAX_UI_EVENTS
		delete_world_string(world, stream.events[index].action)
		delete_world_string(world, stream.events[index].payload)
	}
	stream.next_sequence += 1
	stored := event
	stored.sequence = stream.next_sequence
	stored.frame_index = world.time.frame_index
	stored.action = clone_world_string(world, event.action)
	stored.payload = clone_world_string(world, event.payload)
	stream.events[index] = stored
	stream.revision += 1
	return stored.sequence
}

ui_event_latest_sequence :: proc "contextless" (world: ^World) -> u64 {
	if world == nil {
		return 0
	}
	return world.ui_events.next_sequence
}

ui_event_oldest_sequence :: proc "contextless" (world: ^World) -> u64 {
	if world == nil || world.ui_events.count == 0 {
		return 0
	}
	return world.ui_events.events[world.ui_events.start].sequence
}

ui_event_history_overflowed :: proc "contextless" (world: ^World, after_sequence: u64) -> bool {
	oldest := ui_event_oldest_sequence(world)
	return oldest > 1 && after_sequence < oldest - 1
}

ui_event_count_after :: proc "contextless" (world: ^World, after_sequence: u64) -> int {
	if world == nil || world.ui_events.count == 0 {
		return 0
	}
	if after_sequence >= world.ui_events.next_sequence {
		return 0
	}
	oldest := ui_event_oldest_sequence(world)
	first := oldest
	if after_sequence >= oldest {
		first = after_sequence + 1
	}
	return int(world.ui_events.next_sequence - first + 1)
}

ui_event_after_at :: proc "contextless" (
	world: ^World,
	after_sequence: u64,
	visible_index: int,
) -> (
	shared.UI_Event,
	bool,
) {
	if world == nil || visible_index < 0 {
		return {}, false
	}
	count := ui_event_count_after(world, after_sequence)
	if visible_index >= count {
		return {}, false
	}
	oldest := ui_event_oldest_sequence(world)
	first := oldest
	if after_sequence >= oldest {
		first = after_sequence + 1
	}
	offset := int(first - oldest) + visible_index
	index := (world.ui_events.start + offset) % shared.MAX_UI_EVENTS
	return world.ui_events.events[index], true
}

ui_action_for_entity :: proc(
	world: ^World,
	entity_index: int,
) -> (
	action_entity: shared.Entity_UUID,
	action: string,
	payload: string,
) {
	if world == nil || entity_index < 0 || entity_index >= len(world.entities) {
		return
	}
	index := entity_index
	for _ in 0 ..< len(world.entities) {
		entity := world.entities[index]
		if !entity.alive {
			return
		}
		if entity.ui_action_index >= 0 && entity.ui_action_index < len(world.ui_actions) {
			value := world.ui_actions[entity.ui_action_index]
			return entity.uuid, value.action, value.payload
		}
		if entity.ui_layout_index < 0 || entity.ui_layout_index >= len(world.ui_layouts) {
			return
		}
		parent := world.ui_layouts[entity.ui_layout_index].parent
		if parent == (shared.Entity_UUID{}) {
			return
		}
		next, found := entity_index_by_uuid(world, parent)
		if !found {
			return
		}
		index = next
	}
	return
}
