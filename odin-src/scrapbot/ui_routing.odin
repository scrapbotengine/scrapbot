package main

import "core:math"

UI_SCROLL_PIXELS_PER_WHEEL :: f32(24.0)
UI_EDITOR_TOP_BAR_HEIGHT :: f32(60.0)
UI_EDITOR_BOTTOM_BAR_HEIGHT :: f32(64.0)
UI_EDITOR_LEFT_SIDEBAR_TARGET_WIDTH :: f32(456.0)
UI_EDITOR_LEFT_SIDEBAR_MIN_WIDTH :: f32(280.0)
UI_EDITOR_RIGHT_SIDEBAR_TARGET_WIDTH :: f32(560.0)
UI_EDITOR_RIGHT_SIDEBAR_MIN_WIDTH :: f32(360.0)
UI_EDITOR_MIN_GAME_VIEWPORT_WIDTH :: f32(320.0)
UI_EDITOR_SPLITTER_WIDTH :: f32(2.0)
UI_EDITOR_PANEL_PADDING_X :: f32(20.0)
UI_EDITOR_CONTROL_BUTTON_WIDTH :: f32(104.0)
UI_EDITOR_CONTROL_BUTTON_HEIGHT :: f32(36.0)
UI_EDITOR_CONTROL_BUTTON_GAP :: f32(16.0)
UI_EDITOR_PANEL_PADDING_Y :: f32(24.0)
UI_EDITOR_PANEL_LABEL_GAP :: f32(12.0)
UI_EDITOR_PANEL_BOTTOM_PADDING :: f32(20.0)
UI_EDITOR_SIDEBAR_PANEL_MARGIN :: f32(8.0)
UI_EDITOR_LEFT_PANEL_GAP :: f32(12.0)
UI_EDITOR_ENTITY_PANEL_MIN_HEIGHT :: f32(160.0)
UI_EDITOR_SYSTEM_PANEL_MIN_HEIGHT :: f32(180.0)
UI_EDITOR_SYSTEM_ROW_STRIDE :: f32(44.0)
UI_EDITOR_SYSTEM_CARD_PADDING_Y :: f32(20.0)
UI_EDITOR_ENTITY_ROW_STRIDE :: f32(36.0)
UI_EDITOR_ENTITY_CARD_PADDING_Y :: f32(16.0)
UI_EDITOR_SCROLLBAR_WIDTH :: f32(8.0)
UI_EDITOR_SCROLLBAR_GAP :: f32(12.0)
UI_EDITOR_TEXT_HEIGHT :: f32(32.0)
UI_EDITOR_SCROLL_PIXELS_PER_WHEEL :: f32(18.0)

Ui_Command_Hit :: struct {
	entity:  Entity_Handle,
	source:  string,
	command: string,
}

route_test_frame_input :: proc(world: ^Runtime_World) -> Runtime_Error {
	scroll_err := update_scene_ui_scroll_views(world)
	if scroll_err != .None {
		return scroll_err
	}
	return update_ui_command_events(world)
}

update_scene_ui_scroll_views :: proc(world: ^Runtime_World) -> Runtime_Error {
	input_entity, input_ok := runtime_world_find_entity_by_id(world^, INPUT_ENTITY_ID)
	if !input_ok {
		return .None
	}
	ui_visible, ui_err := runtime_world_get_bool(world^, input_entity, INPUT_FRAME_COMPONENT_ID, "ui_visible")
	if ui_err != .None || !ui_visible {
		return ui_err
	}
	has_position, position_err := runtime_world_get_bool(world^, input_entity, INPUT_POINTER_COMPONENT_ID, "has_position")
	if position_err != .None || !has_position {
		return position_err
	}
	wheel_delta, wheel_err := runtime_world_get_vec3(world^, input_entity, INPUT_POINTER_COMPONENT_ID, "wheel_delta")
	if wheel_err != .None || wheel_delta[1] == 0 {
		return wheel_err
	}
	pointer_position, pointer_err := runtime_world_get_vec3(world^, input_entity, INPUT_POINTER_COMPONENT_ID, "position")
	if pointer_err != .None {
		return pointer_err
	}
	design_position, design_err := scene_ui_pointer_position(world^, input_entity, {pointer_position[0], pointer_position[1]})
	if design_err != .None {
		return design_err
	}
	_, route_err := apply_scroll_wheel_at(world, design_position, wheel_delta[1], UI_SCROLL_PIXELS_PER_WHEEL)
	return route_err
}

update_ui_command_events :: proc(world: ^Runtime_World) -> Runtime_Error {
	clear_err := clear_ui_command_event(world)
	if clear_err != .None {
		return clear_err
	}
	input_entity, input_ok := runtime_world_find_entity_by_id(world^, INPUT_ENTITY_ID)
	if !input_ok {
		return .None
	}
	ui_visible, ui_err := runtime_world_get_bool(world^, input_entity, INPUT_FRAME_COMPONENT_ID, "ui_visible")
	if ui_err != .None || !ui_visible {
		return ui_err
	}
	has_position, position_err := runtime_world_get_bool(world^, input_entity, INPUT_POINTER_COMPONENT_ID, "has_position")
	if position_err != .None || !has_position {
		return position_err
	}
	primary_released, released_err := runtime_world_get_bool(world^, input_entity, INPUT_POINTER_COMPONENT_ID, "primary_released")
	if released_err != .None || !primary_released {
		return released_err
	}
	pointer_position, pointer_err := runtime_world_get_vec3(world^, input_entity, INPUT_POINTER_COMPONENT_ID, "position")
	if pointer_err != .None {
		return pointer_err
	}
	design_position, design_err := scene_ui_pointer_position(world^, input_entity, {pointer_position[0], pointer_position[1]})
	if design_err != .None {
		return design_err
	}
	if hit, hit_ok, hit_err := command_at(world^, design_position); hit_err != .None {
		return hit_err
	} else if hit_ok {
		return emit_ui_command_event(world, hit.command, hit.source)
	}
	return .None
}

clear_ui_command_event :: proc(world: ^Runtime_World) -> Runtime_Error {
	event_entity, found := runtime_world_find_entity_by_id(world^, UI_COMMAND_EVENT_ENTITY_ID)
	if !found {
		return .None
	}
	_, err := runtime_world_remove_component(world, event_entity, UI_COMMAND_EVENT_COMPONENT_ID)
	return err
}

emit_ui_command_event :: proc(world: ^Runtime_World, command, source: string) -> Runtime_Error {
	event_entity, found := runtime_world_find_entity_by_id(world^, UI_COMMAND_EVENT_ENTITY_ID)
	if !found {
		create_err: Runtime_Error
		event_entity, create_err = runtime_world_create_entity(world, UI_COMMAND_EVENT_ENTITY_ID, "UI Command Event")
		if create_err != .None {
			return create_err
		}
	}
	fields := [?]Runtime_Component_Field_Value{
		{name = "command", value = Runtime_Component_Value{value_type = .String, string_value = command}},
		{name = "source", value = Runtime_Component_Value{value_type = .String, string_value = source}},
	}
	return runtime_world_set_component(world, event_entity, UI_COMMAND_EVENT_COMPONENT_ID, fields[:])
}

scene_ui_pointer_position :: proc(world: Runtime_World, input_entity: Entity_Handle, pointer_position: [2]f32) -> ([2]f32, Runtime_Error) {
	debug_overlay_visible, debug_err := runtime_world_get_bool(world, input_entity, INPUT_FRAME_COMPONENT_ID, "debug_overlay_visible")
	if debug_err != .None {
		return {}, debug_err
	}
	viewport, viewport_err := runtime_world_get_vec3(world, input_entity, INPUT_FRAME_COMPONENT_ID, "viewport")
	if viewport_err != .None {
		return {}, viewport_err
	}
	target_x := f32(0)
	target_y := f32(0)
	target_width := viewport[0]
	target_height := viewport[1]
	if debug_overlay_visible {
		target_x, target_y, target_width, target_height = editor_game_viewport(viewport[0], viewport[1])
	}
	offset, scale, transform_err := canvas_transform(world, target_x, target_y, target_width, target_height)
	if transform_err != .None {
		return {}, transform_err
	}
	return {
		(pointer_position[0] - offset[0]) / scale,
		(pointer_position[1] - offset[1]) / scale,
	}, .None
}

editor_game_viewport :: proc(window_width, window_height: f32) -> (f32, f32, f32, f32) {
	body_y := UI_EDITOR_TOP_BAR_HEIGHT
	body_width := max_f32(window_width, 1)
	body_height := max_f32(window_height - UI_EDITOR_TOP_BAR_HEIGHT - UI_EDITOR_BOTTOM_BAR_HEIGHT, 1)
	left, right := editor_side_widths(window_width)
	left_splitter_x := left
	right_x := body_width - right
	right_splitter_x := right_x - UI_EDITOR_SPLITTER_WIDTH
	game_x := left_splitter_x + UI_EDITOR_SPLITTER_WIDTH
	game_width := max_f32(right_splitter_x - game_x, 1)
	return game_x, body_y, game_width, body_height
}

editor_side_widths :: proc(window_width: f32) -> (f32, f32) {
	if window_width <= 0 {
		return UI_EDITOR_LEFT_SIDEBAR_TARGET_WIDTH, UI_EDITOR_RIGHT_SIDEBAR_TARGET_WIDTH
	}
	left := clamp_f32(window_width * 0.25, UI_EDITOR_LEFT_SIDEBAR_MIN_WIDTH, UI_EDITOR_LEFT_SIDEBAR_TARGET_WIDTH)
	right := clamp_f32(window_width * 0.32, UI_EDITOR_RIGHT_SIDEBAR_MIN_WIDTH, UI_EDITOR_RIGHT_SIDEBAR_TARGET_WIDTH)
	max_side_total := max_f32(window_width - UI_EDITOR_MIN_GAME_VIEWPORT_WIDTH, 1)
	if left + right > max_side_total {
		scale := max_side_total / (left + right)
		left = max_f32(left * scale, 1)
		right = max_f32(right * scale, 1)
	}
	max_clamped_total := max_f32(window_width - UI_EDITOR_MIN_GAME_VIEWPORT_WIDTH - UI_EDITOR_SPLITTER_WIDTH * 2, 1)
	left = clamp_f32(left, min_f32(UI_EDITOR_LEFT_SIDEBAR_MIN_WIDTH, max_clamped_total), max_clamped_total)
	right = clamp_f32(right, min_f32(UI_EDITOR_RIGHT_SIDEBAR_MIN_WIDTH, max_clamped_total), max_clamped_total)
	if left + right > max_clamped_total {
		scale := max_clamped_total / (left + right)
		left = max_f32(left * scale, 1)
		right = max_f32(right * scale, 1)
	}
	return left, right
}

canvas_transform :: proc(world: Runtime_World, target_x, target_y, target_width, target_height: f32) -> ([2]f32, f32, Runtime_Error) {
	if target_width <= 0 || target_height <= 0 {
		return {target_x, target_y}, 1, .None
	}
	query := [?]string{UI_CANVAS_COMPONENT_ID}
	cursor := 0
	canvas, found := runtime_world_query_next(world, query[:], &cursor)
	if !found {
		return {target_x, target_y}, 1, .None
	}
	design_size, size_err := runtime_world_get_vec3(world, canvas, UI_CANVAS_COMPONENT_ID, "design_size")
	if size_err != .None {
		return {}, 1, size_err
	}
	scale_mode, mode_err := runtime_world_get_string(world, canvas, UI_CANVAS_COMPONENT_ID, "scale_mode")
	if mode_err != .None {
		return {}, 1, mode_err
	}
	if scale_mode == "none" {
		return {target_x, target_y}, 1, .None
	}
	if design_size[0] <= 0 || design_size[1] <= 0 {
		return {}, 1, .Invalid_Field_Type
	}
	scale: f32
	if scale_mode == "fit" {
		scale = min_f32(target_width / design_size[0], target_height / design_size[1])
	} else if scale_mode == "fill" {
		scale = max_f32(target_width / design_size[0], target_height / design_size[1])
	} else {
		return {}, 1, .Invalid_Field_Type
	}
	return {
		target_x + (target_width - design_size[0] * scale) * 0.5,
		target_y + (target_height - design_size[1] * scale) * 0.5,
	}, scale, .None
}

command_at :: proc(world: Runtime_World, point: [2]f32) -> (Ui_Command_Hit, bool, Runtime_Error) {
	selected: Ui_Command_Hit
	selected_ok := false
	query := [?]string{UI_BUTTON_COMPONENT_ID, UI_COMMAND_COMPONENT_ID}
	cursor := 0
	for {
		entity, found := runtime_world_query_next(world, query[:], &cursor)
		if !found {
			break
		}
		position: [3]f32
		size: [3]f32
		if has_hit_area, has_err := runtime_world_has_component(world, entity, UI_HIT_AREA_COMPONENT_ID); has_err != .None {
			return {}, false, has_err
		} else if has_hit_area {
			hit_position, position_err := runtime_world_get_vec3(world, entity, UI_HIT_AREA_COMPONENT_ID, "position")
			if position_err != .None {
				return {}, false, position_err
			}
			hit_size, size_err := runtime_world_get_vec3(world, entity, UI_HIT_AREA_COMPONENT_ID, "size")
			if size_err != .None {
				return {}, false, size_err
			}
			position = hit_position
			size = hit_size
		} else {
			has_rect, rect_err := runtime_world_has_component(world, entity, UI_RECT_COMPONENT_ID)
			if rect_err != .None {
				return {}, false, rect_err
			}
			if !has_rect {
				continue
			}
			rect_position, position_err := runtime_world_get_vec3(world, entity, UI_RECT_COMPONENT_ID, "position")
			if position_err != .None {
				return {}, false, position_err
			}
			rect_size, size_err := runtime_world_get_vec3(world, entity, UI_RECT_COMPONENT_ID, "size")
			if size_err != .None {
				return {}, false, size_err
			}
			position = rect_position
			size = rect_size
		}
		if !point_inside_rect(point, position, size) {
			continue
		}
		command, command_err := runtime_world_get_string(world, entity, UI_COMMAND_COMPONENT_ID, "command")
		if command_err != .None {
			return {}, false, command_err
		}
		source := runtime_entity_id(world, entity)
		selected = Ui_Command_Hit{entity = entity, source = source, command = command}
		selected_ok = true
	}
	return selected, selected_ok, .None
}

apply_scroll_wheel_at :: proc(world: ^Runtime_World, point: [2]f32, wheel_delta_y, pixels_per_wheel: f32) -> (bool, Runtime_Error) {
	if wheel_delta_y == 0 || pixels_per_wheel == 0 {
		return false, .None
	}
	scroll_entity, found, find_err := scroll_view_at(world^, point)
	if find_err != .None || !found {
		return false, find_err
	}
	content_offset, offset_err := runtime_world_get_vec3(world^, scroll_entity, UI_SCROLL_VIEW_COMPONENT_ID, "content_offset")
	if offset_err != .None {
		return false, offset_err
	}
	max_y, max_err := scroll_max_y(world^, scroll_entity)
	if max_err != .None || max_y == 0 {
		return false, max_err
	}
	next_offset := content_offset
	next_offset[1] = clamp_f32(next_offset[1] + -wheel_delta_y * pixels_per_wheel, 0, max_y)
	return true, runtime_world_set_component_field_value(
		world,
		scroll_entity,
		UI_SCROLL_VIEW_COMPONENT_ID,
		"content_offset",
		Runtime_Component_Value{value_type = .Vec3, vec3 = next_offset},
	)
}

scroll_view_at :: proc(world: Runtime_World, point: [2]f32) -> (Entity_Handle, bool, Runtime_Error) {
	selected: Entity_Handle
	selected_ok := false
	query := [?]string{UI_SCROLL_VIEW_COMPONENT_ID}
	cursor := 0
	for {
		entity, found := runtime_world_query_next(world, query[:], &cursor)
		if !found {
			break
		}
		position, position_err := runtime_world_get_vec3(world, entity, UI_SCROLL_VIEW_COMPONENT_ID, "position")
		if position_err != .None {
			return {}, false, position_err
		}
		size, size_err := runtime_world_get_vec3(world, entity, UI_SCROLL_VIEW_COMPONENT_ID, "size")
		if size_err != .None {
			return {}, false, size_err
		}
		if point_inside_rect(point, position, size) {
			selected = entity
			selected_ok = true
		}
	}
	return selected, selected_ok, .None
}

scroll_max_y :: proc(world: Runtime_World, scroll_entity: Entity_Handle) -> (f32, Runtime_Error) {
	scroll_size, size_err := runtime_world_get_vec3(world, scroll_entity, UI_SCROLL_VIEW_COMPONENT_ID, "size")
	if size_err != .None {
		return 0, size_err
	}
	content_size, content_err := container_content_size(world, runtime_entity_id(world, scroll_entity))
	if content_err != .None {
		return 0, content_err
	}
	return max_f32(content_size[1] - scroll_size[1], 0), .None
}

container_content_size :: proc(world: Runtime_World, parent_id: string) -> ([3]f32, Runtime_Error) {
	content: [3]f32
	for entity, index in world.entities {
		handle := Entity_Handle{index = u32(index), generation = entity.generation}
		has_item, has_err := runtime_world_has_component(world, handle, UI_LAYOUT_ITEM_COMPONENT_ID)
		if has_err != .None {
			return {}, has_err
		}
		if !has_item {
			continue
		}
		parent, parent_err := runtime_world_get_string(world, handle, UI_LAYOUT_ITEM_COMPONENT_ID, "parent")
		if parent_err != .None {
			return {}, parent_err
		}
		if parent != parent_id {
			continue
		}
		child_size, size_err := item_size(world, handle)
		if size_err != .None {
			return {}, size_err
		}
		content[0] = max_f32(content[0], child_size[0])
		content[1] += child_size[1]
		content[2] = max_f32(content[2], child_size[2])
	}
	return content, .None
}

item_size :: proc(world: Runtime_World, entity: Entity_Handle) -> ([3]f32, Runtime_Error) {
	if has_scroll, err := runtime_world_has_component(world, entity, UI_SCROLL_VIEW_COMPONENT_ID); err != .None {
		return {}, err
	} else if has_scroll {
		return runtime_world_get_vec3(world, entity, UI_SCROLL_VIEW_COMPONENT_ID, "size")
	}
	if has_vgroup, err := runtime_world_has_component(world, entity, UI_VGROUP_COMPONENT_ID); err != .None {
		return {}, err
	} else if has_vgroup {
		return runtime_world_get_vec3(world, entity, UI_VGROUP_COMPONENT_ID, "size")
	}
	if has_rect, err := runtime_world_has_component(world, entity, UI_RECT_COMPONENT_ID); err != .None {
		return {}, err
	} else if has_rect {
		return runtime_world_get_vec3(world, entity, UI_RECT_COMPONENT_ID, "size")
	}
	if has_spacer, err := runtime_world_has_component(world, entity, UI_SPACER_COMPONENT_ID); err != .None {
		return {}, err
	} else if has_spacer {
		return runtime_world_get_vec3(world, entity, UI_SPACER_COMPONENT_ID, "size")
	}
	return {}, .None
}

runtime_world_get_bool :: proc(world: Runtime_World, entity: Entity_Handle, component_id, field: string) -> (bool, Runtime_Error) {
	value, err := runtime_world_get_component_field_value(world, entity, component_id, field)
	if err != .None {
		return false, err
	}
	if value.value_type != .Boolean {
		return false, .Invalid_Field_Type
	}
	return value.boolean, .None
}

runtime_world_get_vec3 :: proc(world: Runtime_World, entity: Entity_Handle, component_id, field: string) -> ([3]f32, Runtime_Error) {
	value, err := runtime_world_get_component_field_value(world, entity, component_id, field)
	if err != .None {
		return {}, err
	}
	if value.value_type != .Vec3 {
		return {}, .Invalid_Field_Type
	}
	return value.vec3, .None
}

runtime_world_get_string :: proc(world: Runtime_World, entity: Entity_Handle, component_id, field: string) -> (string, Runtime_Error) {
	value, err := runtime_world_get_component_field_value(world, entity, component_id, field)
	if err != .None {
		return "", err
	}
	if value.value_type != .String {
		return "", .Invalid_Field_Type
	}
	return value.string_value, .None
}

runtime_entity_id :: proc(world: Runtime_World, entity: Entity_Handle) -> string {
	stored, err := runtime_world_entity(world, entity)
	if err != .None {
		return ""
	}
	return stored.id
}

point_inside_rect :: proc(point: [2]f32, position, size: [3]f32) -> bool {
	return point[0] >= position[0] &&
	       point[1] >= position[1] &&
	       point[0] <= position[0] + size[0] &&
	       point[1] <= position[1] + size[1]
}

clamp_f32 :: proc(value, low, high: f32) -> f32 {
	return min_f32(max_f32(value, low), high)
}

min_f32 :: proc(left, right: f32) -> f32 {
	return math.min(left, right)
}

max_f32 :: proc(left, right: f32) -> f32 {
	return math.max(left, right)
}
