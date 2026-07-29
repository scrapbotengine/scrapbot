package script

import ecs "../ecs"
import shared "../shared"
import c "core:c"
import "core:math"

scrapbot_ui_events :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil || runtime.world == nil {
		return luau_push_error(L, "scrapbot.ui.events requires an active world")
	}
	world := runtime.world
	after_sequence := world.ui_events.latest_pass_after_sequence
	if lua_gettop(L) >= 1 {
		is_number: c.int
		value := lua_tonumberx(L, 1, &is_number)
		if is_number == 0 ||
		   math.is_nan(value) ||
		   math.is_inf(value) ||
		   value < 0 ||
		   value > 9007199254740991 ||
		   value != math.floor(value) {
			return luau_push_error(
				L,
				"scrapbot.ui.events cursor must be a non-negative safe integer",
			)
		}
		after_sequence = u64(value)
	}

	lua_createtable(L, 0, 4)
	lua_createtable(L, c.int(ecs.ui_event_count_after(world, after_sequence)), 0)
	visible_index := 1
	for retained_index in 0 ..< ecs.ui_event_count_after(world, after_sequence) {
		event, ok := ecs.ui_event_after_at(world, after_sequence, retained_index)
		if !ok || event.origin == .Editor {
			continue
		}
		lua_pushinteger(L, c.ptrdiff_t(visible_index))
		push_ui_event_table(L, event)
		lua_settable(L, -3)
		visible_index += 1
	}
	lua_setfield(L, -2, "events")
	lua_pushnumber(L, f64(ecs.ui_event_latest_sequence(world)))
	lua_setfield(L, -2, "latest_sequence")
	lua_pushnumber(L, f64(ecs.ui_event_oldest_sequence(world)))
	lua_setfield(L, -2, "oldest_sequence")
	lua_pushboolean(L, c.int(ecs.ui_event_history_overflowed(world, after_sequence)))
	lua_setfield(L, -2, "overflowed")
	return 1
}

push_ui_event_table :: proc "c" (L: Lua_State, event: shared.UI_Event) {
	lua_createtable(L, 0, 13)
	lua_pushnumber(L, f64(event.sequence))
	lua_setfield(L, -2, "sequence")
	lua_pushnumber(L, f64(event.frame_index))
	lua_setfield(L, -2, "frame_index")
	push_string_field(L, "kind", ui_event_kind_name(event.kind))
	push_string_field(L, "part", ui_event_part_name(event.part))
	push_uuid_field(L, "entity", event.entity)
	push_uuid_field(L, "action_entity", event.action_entity)
	push_string_field(L, "action", event.action)
	push_string_field(L, "payload", event.payload)
	push_uuid_field(L, "drag_source", event.drag_source)
	push_uuid_field(L, "drop_target", event.drop_target)
	push_string_field(L, "drop_placement", ui_drop_placement_name(event.drop_placement))
	push_vec2_field(L, "position", event.position)
}

ui_event_kind_name :: proc "contextless" (kind: shared.UI_Event_Kind) -> string {
	switch kind {
		case .Activated:
			return "activated"
		case .Changed:
			return "changed"
		case .Submitted:
			return "submitted"
		case .Cancelled:
			return "cancelled"
		case .Dropped:
			return "dropped"
	}
	return ""
}

ui_event_part_name :: proc "contextless" (part: shared.UI_Event_Part) -> string {
	switch part {
		case .Control:
			return "control"
		case .Panel_Title:
			return "panel_title"
	}
	return ""
}

ui_drop_placement_name :: proc "contextless" (placement: shared.UI_Drop_Placement) -> string {
	switch placement {
		case .None:
			return "none"
		case .Before:
			return "before"
		case .Into:
			return "into"
		case .After:
			return "after"
	}
	return ""
}
