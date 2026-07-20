package script


import component "../component"
import ecs "../ecs"
import schedule "../schedule"
import shared "../shared"
import base_runtime "base:runtime"
import c "core:c"

scrapbot_query :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil {
		return 0
	}
	arg_count := lua_gettop(L)
	if arg_count < 1 {
		return luau_push_error(L, "scrapbot.query expects one or more component handles")
	}
	if lua_type(L, arg_count) == LUA_TFUNCTION {
		return luau_push_error(
			L,
			"scrapbot.query constructs a query; call query:each(callback) to iterate",
		)
	}

	query, query_err := query_from_component_arguments(L, runtime, 1, int(arg_count), .Query)
	if query_err != "" {
		return luau_push_error(L, query_err)
	}
	normalize_query(&query)

	if err := push_cached_query_object(L, runtime, query); err != "" {
		return luau_push_error(L, err)
	}
	return 1
}

scrapbot_query_each :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil || runtime.world == nil {
		return 0
	}
	if !query_argument_is_query_object(L, 1) || lua_type(L, 2) != LUA_TFUNCTION {
		return luau_push_error(L, "query:each expects a callback")
	}

	query, query_err := query_object_argument(L, runtime, 1)
	if query_err != "" {
		return luau_push_error(L, query_err)
	}
	if err := require_query_access(runtime, query, .Read); err != "" {
		return luau_push_error(L, err)
	}

	return run_query_callback(L, runtime, query, 2)
}

run_query_callback :: proc "c" (
	L: Lua_State,
	runtime: ^Runtime,
	query: Query,
	callback_index: c.int,
) -> c.int {
	callback_ref := lua_ref(L, callback_index)
	next_entity_index := 0
	for {
		entity_index, entity_ok := ecs.query_next(runtime.world, query, &next_entity_index)
		if !entity_ok {
			break
		}
		lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ref)
		push_entity_table(L, runtime.world, entity_index)
		for term_index in 0 ..< query.term_count {
			term := query.terms[term_index]
			push_query_component_table(L, runtime.world, entity_index, term)
		}
		status := lua_pcall(L, c.int(query.term_count + 1), 0, 0)
		if status != LUA_OK {
			lua_unref(L, callback_ref)
			return lua_error(L)
		}
	}
	lua_unref(L, callback_ref)
	return 0
}

scrapbot_view :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil || runtime.world == nil {
		lua_createtable(L, 0, 0)
		return 1
	}
	if lua_type(L, 1) != LUA_TTABLE {
		return luau_push_error(L, "scrapbot.view expects a component handle or component array")
	}

	query, query_err := query_argument(L, runtime, 1, .View)
	if query_err != "" {
		return luau_push_error(L, query_err)
	}
	if err := require_query_access(runtime, query, .Read); err != "" {
		return luau_push_error(L, err)
	}

	count := ecs.query_count(runtime.world, query)
	lua_createtable(L, c.int(count), 0)
	next_entity_index := 0
	visible_index := 0
	for {
		entity_index, entity_ok := ecs.query_next(runtime.world, query, &next_entity_index)
		if !entity_ok {
			break
		}
		visible_index += 1
		lua_pushinteger(L, c.ptrdiff_t(visible_index))
		push_query_item_table(L, runtime.world, entity_index, query)
		lua_settable(L, -3)
	}
	return 1
}


push_registered_component_handle_by_name :: proc "c" (L: Lua_State, name: string) {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil {
		lua_pushnil(L)
		return
	}
	definition, ok := component.find_definition(&runtime.registry, name)
	if !ok {
		lua_pushnil(L)
		return
	}
	push_component_handle(L, definition)
}

push_component_handle :: proc "c" (L: Lua_State, definition: component.Definition) {
	lua_createtable(L, 0, 2)
	lua_pushinteger(L, c.ptrdiff_t(definition.id))
	lua_setfield(L, -2, "id")
	lua_pushlstring(L, cstring(raw_data(definition.name)), c.size_t(len(definition.name)))
	lua_setfield(L, -2, "name")
}

push_schema_field_marker :: proc "c" (L: Lua_State, name: string) {
	lua_createtable(L, 0, 2)
	lua_pushlstring(L, cstring(raw_data(SCHEMA_FIELD_KIND)), c.size_t(len(SCHEMA_FIELD_KIND)))
	lua_setfield(L, -2, "__scrapbot_kind")
	lua_pushlstring(L, cstring(raw_data(name)), c.size_t(len(name)))
	lua_setfield(L, -2, "name")
}

normalize_query :: proc "c" (query: ^Query) {
	for i in 1 ..< query.term_count {
		term := query.terms[i]
		j := i
		for j > 0 && query.terms[j - 1].component_id > term.component_id {
			query.terms[j] = query.terms[j - 1]
			j -= 1
		}
		query.terms[j] = term
	}

	write_index := 0
	for read_index in 0 ..< query.term_count {
		term := query.terms[read_index]
		if write_index > 0 && query.terms[write_index - 1].component_id == term.component_id {
			continue
		}
		query.terms[write_index] = term
		write_index += 1
	}
	query.term_count = write_index
}

push_cached_query_object :: proc "c" (L: Lua_State, runtime: ^Runtime, query: Query) -> string {
	if runtime == nil {
		lua_pushnil(L)
		return ""
	}

	for query_object in runtime.query_objects[:runtime.query_object_count] {
		if queries_have_same_components(query_object.query, query) {
			lua_rawgeti(L, LUA_REGISTRYINDEX, query_object.ref)
			return ""
		}
	}

	if runtime.query_object_count >= MAX_QUERY_OBJECTS {
		return "too many cached query objects"
	}

	push_query_object(L, query)
	ref := lua_ref(L, -1)
	runtime.query_objects[runtime.query_object_count] = Query_Object {
		query = query,
		ref = ref,
	}
	runtime.query_object_count += 1
	return ""
}

queries_have_same_components :: proc "c" (a, b: Query) -> bool {
	if a.term_count != b.term_count {
		return false
	}
	for i in 0 ..< a.term_count {
		if a.terms[i].component_id != b.terms[i].component_id {
			return false
		}
	}
	return true
}

push_query_object :: proc "c" (L: Lua_State, query: Query) {
	lua_createtable(L, c.int(query.term_count), 2)
	for i in 0 ..< query.term_count {
		term := query.terms[i]
		lua_pushinteger(L, c.ptrdiff_t(i + 1))
		push_component_handle_from_term(L, term)
		lua_settable(L, -3)
	}

	lua_pushlstring(L, cstring(raw_data(QUERY_OBJECT_KIND)), c.size_t(len(QUERY_OBJECT_KIND)))
	lua_setfield(L, -2, "__scrapbot_kind")

	lua_pushcclosurek(L, scrapbot_query_each, "scrapbot.query.each", 0, nil)
	lua_setfield(L, -2, "each")
}

push_component_handle_from_term :: proc "c" (L: Lua_State, term: Query_Term) {
	lua_createtable(L, 0, 2)
	lua_pushinteger(L, c.ptrdiff_t(term.component_id))
	lua_setfield(L, -2, "id")
	lua_pushlstring(L, cstring(raw_data(term.name)), c.size_t(len(term.name)))
	lua_setfield(L, -2, "name")
}

scrapbot_get_rotation :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil || runtime.world == nil {
		lua_pushnil(L)
		return 1
	}
	if err := require_system_access(runtime, "scrapbot.transform", .Read); err != "" {
		return luau_push_error(L, err)
	}
	entity, ok := entity_argument(L, 1, runtime.world)
	if !ok {
		lua_pushnil(L)
		return 1
	}

	transform_index := runtime.world.entities[entity.index].transform_index
	if transform_index < 0 || transform_index >= len(runtime.world.transforms) {
		lua_pushnil(L)
		return 1
	}

	push_vec3_table(L, runtime.world.transforms[transform_index].rotation)
	return 1
}

scrapbot_set_rotation :: proc "c" (L: Lua_State) -> c.int {
	context = base_runtime.default_context()
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil || runtime.world == nil {
		return 0
	}
	if err := require_system_access(runtime, "scrapbot.transform", .Write); err != "" {
		return luau_push_error(L, err)
	}
	entity, entity_ok := entity_argument(L, 1, runtime.world)
	rotation, rotation_ok := vec3_argument(L, 2)
	if !entity_ok || !rotation_ok {
		return 0
	}

	transform_index := runtime.world.entities[entity.index].transform_index
	if transform_index < 0 || transform_index >= len(runtime.world.transforms) {
		return 0
	}

	transform := runtime.world.transforms[transform_index]
	transform.rotation = rotation
	runtime.world.transforms[transform_index] = transform
	ecs.mark_render_entity_dirty(runtime.world, int(entity.index))
	return 0
}

push_entity_table :: proc "c" (L: Lua_State, world: ^World, entity_index: int) {
	lua_createtable(L, 0, 4)
	lua_pushinteger(L, c.ptrdiff_t(entity_index + 1))
	lua_setfield(L, -2, "index")
	if ecs.entity_is_alive(world, entity_index) {
		id_buffer: [36]u8
		id := shared.entity_uuid_to_string(world.entities[entity_index].uuid, id_buffer[:])
		lua_pushlstring(L, cstring(raw_data(id)), c.size_t(len(id)))
		lua_setfield(L, -2, "id")
		lua_pushinteger(L, c.ptrdiff_t(world.entities[entity_index].id.generation))
		lua_setfield(L, -2, "generation")
		name := world.entities[entity_index].name
		lua_pushlstring(L, cstring(raw_data(name)), c.size_t(len(name)))
		lua_setfield(L, -2, "name")
	}
}

push_component_table :: proc "c" (L: Lua_State, component: Custom_Component) {
	field_count :=
		len(component.number_fields) +
		len(component.vec2_fields) +
		len(component.vec3_fields) +
		len(component.vec4_fields)
	lua_createtable(L, 0, c.int(field_count))
	for field in component.number_fields {
		lua_pushlstring(L, cstring(raw_data(field.name)), c.size_t(len(field.name)))
		lua_pushnumber(L, f64(field.value))
		lua_settable(L, -3)
	}
	for field in component.vec2_fields {
		lua_pushlstring(L, cstring(raw_data(field.name)), c.size_t(len(field.name)))
		push_vec2_table(L, field.value)
		lua_settable(L, -3)
	}
	for field in component.vec3_fields {
		lua_pushlstring(L, cstring(raw_data(field.name)), c.size_t(len(field.name)))
		push_vec3_table(L, field.value)
		lua_settable(L, -3)
	}
	for field in component.vec4_fields {
		lua_pushlstring(L, cstring(raw_data(field.name)), c.size_t(len(field.name)))
		push_vec4_table(L, field.value)
		lua_settable(L, -3)
	}
}

push_query_item_table :: proc "c" (L: Lua_State, world: ^World, entity_index: int, query: Query) {
	lua_createtable(L, 0, 3)
	push_entity_table(L, world, entity_index)
	lua_setfield(L, -2, "entity")

	if query.term_count == 1 {
		push_query_component_table(L, world, entity_index, query.terms[0])
		lua_setfield(L, -2, "component")
	}

	lua_createtable(L, c.int(query.term_count), 0)
	for i in 0 ..< query.term_count {
		term := query.terms[i]
		lua_pushinteger(L, c.ptrdiff_t(i + 1))
		push_query_component_table(L, world, entity_index, term)
		lua_settable(L, -3)
	}
	lua_setfield(L, -2, "components")
}

push_query_component_table :: proc "c" (
	L: Lua_State,
	world: ^World,
	entity_index: int,
	term: Query_Term,
) {
	if world == nil || !ecs.entity_is_alive(world, entity_index) {
		lua_createtable(L, 0, 0)
		return
	}

	entity := world.entities[entity_index]
	switch term.name {
		case "scrapbot.transform":
			if entity.transform_index >= 0 && entity.transform_index < len(world.transforms) {
				push_transform_table(L, world.transforms[entity.transform_index])
				return
			}
		case "scrapbot.camera":
			lua_createtable(L, 0, 0)
			return
		case "scrapbot.ambient_light":
			if entity.ambient_light_index >= 0 &&
			   entity.ambient_light_index <
				   len(
					   world.ambient_lights,
				   ) { light := world.ambient_lights[entity.ambient_light_index]; lua_createtable(L, 0, 2); push_vec3_table(L, light.color); lua_setfield(L, -2, "color"); lua_pushnumber(L, f64(light.intensity)); lua_setfield(L, -2, "intensity"); return }
		case "scrapbot.directional_light":
			if entity.directional_light_index >= 0 &&
			   entity.directional_light_index <
				   len(
					   world.directional_lights,
				   ) { light := world.directional_lights[entity.directional_light_index]; lua_createtable(L, 0, 3); push_vec3_table(L, light.direction); lua_setfield(L, -2, "direction"); push_vec3_table(L, light.color); lua_setfield(L, -2, "color"); lua_pushnumber(L, f64(light.intensity)); lua_setfield(L, -2, "intensity"); return }
		case "scrapbot.point_light":
			if entity.point_light_index >= 0 &&
			   entity.point_light_index <
				   len(
					   world.point_lights,
				   ) { light := world.point_lights[entity.point_light_index]; lua_createtable(L, 0, 3); push_vec3_table(L, light.color); lua_setfield(L, -2, "color"); lua_pushnumber(L, f64(light.intensity)); lua_setfield(L, -2, "intensity"); lua_pushnumber(L, f64(light.range)); lua_setfield(L, -2, "range"); return }
		case "scrapbot.shadow_caster", "scrapbot.shadow_receiver":
			lua_createtable(L, 0, 0)
			return
		case "scrapbot.ui_layout":
			push_ui_layout_table(L, world.ui_layouts[entity.ui_layout_index])
			return
		case "scrapbot.ui_hstack":
			push_ui_stack_table(L, world.ui_hstacks[entity.ui_hstack_index])
			return
		case "scrapbot.ui_vstack":
			push_ui_stack_table(L, world.ui_vstacks[entity.ui_vstack_index])
			return
		case "scrapbot.ui_scroll_area":
			push_ui_scroll_area_table(L, world.ui_scroll_areas[entity.ui_scroll_area_index])
			return
		case "scrapbot.ui_panel":
			push_ui_panel_table(L, world.ui_panels[entity.ui_panel_index])
			return
		case "scrapbot.ui_table":
			push_ui_table_table(L, world.ui_tables[entity.ui_table_index])
			return
		case "scrapbot.ui_list":
			push_ui_list_table(L, world.ui_lists[entity.ui_list_index])
			return
		case "scrapbot.ui_progress":
			push_ui_progress_table(L, world.ui_progresses[entity.ui_progress_index])
			return
		case "scrapbot.ui_state":
			push_ui_state_table(L, world.ui_states[entity.ui_state_index])
			return
		case "scrapbot.ui_text":
			push_ui_text_table(L, world.ui_texts[entity.ui_text_index])
			return
		case "scrapbot.ui_button":
			push_ui_button_table(L, world.ui_buttons[entity.ui_button_index])
			return
		case "scrapbot.ui_input":
			push_ui_input_table(L, world.ui_inputs[entity.ui_input_index])
			return
		case "scrapbot.ui_checkbox":
			push_ui_checkbox_table(L, world.ui_checkboxes[entity.ui_checkbox_index])
			return
		case "scrapbot.mesh":
			lua_createtable(L, 0, 0)
			return
	}

	if custom_component, ok := ecs.custom_component_for_entity(
		world,
		entity_index,
		term.component_id,
		term.name,
	); ok {
		push_component_table(L, custom_component)
		return
	}
	lua_createtable(L, 0, 0)
}

push_transform_table :: proc "c" (L: Lua_State, transform: Transform_Component) {
	lua_createtable(L, 0, 4)
	push_uuid_field(L, "parent", transform.parent)
	push_vec3_table(L, transform.position)
	lua_setfield(L, -2, "position")
	push_vec3_table(L, transform.rotation)
	lua_setfield(L, -2, "rotation")
	push_vec3_table(L, transform.scale)
	lua_setfield(L, -2, "scale")
}

push_vec3_table :: proc "c" (L: Lua_State, value: Vec3) {
	lua_createtable(L, 0, 3)
	lua_pushnumber(L, f64(value.x))
	lua_setfield(L, -2, "x")
	lua_pushnumber(L, f64(value.y))
	lua_setfield(L, -2, "y")
	lua_pushnumber(L, f64(value.z))
	lua_setfield(L, -2, "z")
}

push_vec2_table :: proc "c" (L: Lua_State, value: shared.Vec2) {
	lua_createtable(L, 0, 2)
	push_number_field(L, "x", value.x)
	push_number_field(L, "y", value.y)
}

push_vec4_table :: proc "c" (L: Lua_State, value: shared.Vec4) {
	lua_createtable(L, 0, 4)
	push_number_field(L, "x", value.x)
	push_number_field(L, "y", value.y)
	push_number_field(L, "z", value.z)
	push_number_field(L, "w", value.w)
}

push_number_field :: proc "c" (L: Lua_State, name: cstring, value: f32) {
	lua_pushnumber(L, f64(value))
	lua_setfield(L, -2, name)
}

push_bool_field :: proc "c" (L: Lua_State, name: cstring, value: bool) {
	encoded: c.int
	if value {
		encoded = 1
	}
	lua_pushboolean(L, encoded)
	lua_setfield(L, -2, name)
}

push_string_field :: proc "c" (L: Lua_State, name: cstring, value: string) {
	lua_pushlstring(L, cstring(raw_data(value)), c.size_t(len(value)))
	lua_setfield(L, -2, name)
}

push_vec2_field :: proc "c" (L: Lua_State, name: cstring, value: shared.Vec2) {
	push_vec2_table(L, value)
	lua_setfield(L, -2, name)
}

push_vec4_field :: proc "c" (L: Lua_State, name: cstring, value: shared.Vec4) {
	push_vec4_table(L, value)
	lua_setfield(L, -2, name)
}

push_uuid_field :: proc "c" (L: Lua_State, name: cstring, value: shared.Entity_UUID) {
	if value == (shared.Entity_UUID{}) {
		push_string_field(L, name, "")
		return
	}
	buffer: [36]u8
	push_string_field(L, name, shared.entity_uuid_to_string(value, buffer[:]))
}

push_ui_layout_table :: proc "c" (L: Lua_State, value: shared.UI_Layout_Component) {
	lua_createtable(L, 0, 20)
	push_uuid_field(L, "parent", value.parent)
	push_vec2_field(L, "position", value.position)
	push_vec2_field(L, "size", value.size)
	push_vec2_field(L, "min_size", value.min_size)
	push_vec4_field(L, "margin", value.margin)
	push_vec4_field(L, "padding", value.padding)
	push_vec4_field(L, "background", value.background)
	push_vec4_field(L, "border_color", value.border_color)
	push_number_field(L, "border_width", value.border_width)
	push_number_field(L, "corner_radius", value.corner_radius)
	push_bool_field(L, "hidden", value.hidden)
	push_bool_field(L, "fill_width", value.fill_width)
	push_bool_field(L, "fill_height", value.fill_height)
	push_bool_field(L, "fit_content_width", value.fit_content_width)
	push_bool_field(L, "fit_content_height", value.fit_content_height)
	push_bool_field(L, "fixed_in_fill", value.fixed_in_fill)
	push_bool_field(L, "tree_item", value.tree_item)
	push_uuid_field(L, "tree_parent", value.tree_parent)
	push_number_field(L, "tree_order", f32(value.tree_order))
	push_bool_field(L, "tree_collapsed", value.tree_collapsed)
}

push_ui_stack_table :: proc "c" (L: Lua_State, value: shared.UI_Stack_Component) {
	lua_createtable(L, 0, 4)
	push_number_field(L, "gap", value.gap)
	push_bool_field(L, "fill", value.fill)
	push_bool_field(L, "draggable", value.draggable)
	push_number_field(L, "min_size", value.min_size)
}

push_ui_scroll_area_table :: proc "c" (L: Lua_State, value: shared.UI_Scroll_Area_Component) {
	lua_createtable(L, 0, 9)
	push_number_field(L, "scroll_speed", value.scroll_speed)
	push_number_field(L, "smoothness", value.smoothness)
	push_number_field(L, "scrollbar_width", value.scrollbar_width)
	push_number_field(L, "scrollbar_right", value.scrollbar_right)
	push_number_field(L, "scrollbar_vertical_inset", value.scrollbar_vertical_inset)
	push_number_field(L, "minimum_thumb_size", value.minimum_thumb_size)
	push_number_field(L, "scrollbar_corner_radius", value.scrollbar_corner_radius)
	push_vec4_field(L, "scrollbar_track_color", value.scrollbar_track_color)
	push_vec4_field(L, "scrollbar_thumb_color", value.scrollbar_thumb_color)
}

push_ui_panel_table :: proc "c" (L: Lua_State, value: shared.UI_Panel_Component) {
	lua_createtable(L, 0, 14)
	push_string_field(L, "title", value.title)
	push_string_field(L, "font", value.font)
	push_vec4_field(L, "title_color", value.title_color)
	push_vec4_field(L, "title_background", value.title_background)
	push_number_field(L, "title_size", value.title_size)
	push_number_field(L, "title_height", value.title_height)
	push_number_field(L, "disclosure_size", value.disclosure_size)
	push_number_field(L, "disclosure_margin", value.disclosure_margin)
	push_number_field(L, "disclosure_gap", value.disclosure_gap)
	push_number_field(L, "disclosure_corner_radius", value.disclosure_corner_radius)
	push_bool_field(L, "collapsible", value.collapsible)
	push_bool_field(L, "collapsed", value.collapsed)
}

push_ui_table_table :: proc "c" (L: Lua_State, value: shared.UI_Table_Component) {
	lua_createtable(L, 0, 6)
	lua_pushinteger(L, c.ptrdiff_t(value.columns))
	lua_setfield(L, -2, "columns")
	push_number_field(L, "column_gap", value.column_gap)
	push_number_field(L, "row_gap", value.row_gap)
	push_bool_field(L, "proportional_columns", value.proportional_columns)
	push_bool_field(L, "resizable_columns", value.resizable_columns)
	push_number_field(L, "min_column_width", value.min_column_width)
}

push_ui_list_table :: proc "c" (L: Lua_State, value: shared.UI_List_Component) {
	lua_createtable(L, 0, 12)
	push_uuid_field(L, "selected", value.selected)
	push_number_field(L, "gap", value.gap)
	push_vec4_field(L, "selection_background", value.selection_background)
	push_vec4_field(L, "hover_background", value.hover_background)
	push_vec4_field(L, "active_background", value.active_background)
	push_bool_field(L, "draggable", value.draggable)
	push_number_field(L, "drag_threshold", value.drag_threshold)
	push_number_field(L, "drop_edge_fraction", value.drop_edge_fraction)
	push_vec4_field(L, "drop_target_background", value.drop_target_background)
	push_vec4_field(L, "drop_indicator_color", value.drop_indicator_color)
	push_number_field(L, "drop_indicator_thickness", value.drop_indicator_thickness)
	push_number_field(L, "drop_indicator_inset", value.drop_indicator_inset)
	push_bool_field(L, "tree_enabled", value.tree_enabled)
	push_number_field(L, "tree_indent", value.tree_indent)
}

push_ui_progress_table :: proc "c" (L: Lua_State, value: shared.UI_Progress_Component) {
	lua_createtable(L, 0, 7)
	push_number_field(L, "value", value.value)
	push_number_field(L, "maximum", value.maximum)
	push_vec4_field(L, "fill_color", value.fill_color)
	push_vec4_field(L, "background_color", value.background_color)
	push_vec4_field(L, "inset", value.inset)
	push_number_field(L, "corner_radius", value.corner_radius)
	push_bool_field(L, "right_to_left", value.right_to_left)
}

push_ui_state_table :: proc "c" (L: Lua_State, value: shared.UI_State_Component) {
	lua_createtable(L, 0, 18)
	push_bool_field(L, "hovered", value.hovered)
	push_bool_field(L, "active", value.active)
	push_bool_field(L, "focused", value.focused)
	push_bool_field(L, "activated", value.activated)
	push_bool_field(L, "changed", value.changed)
	push_bool_field(L, "valid", value.valid)
	push_bool_field(L, "submitted", value.submitted)
	push_bool_field(L, "cancelled", value.cancelled)
	push_bool_field(L, "dragging", value.dragging)
	push_uuid_field(L, "drag_source", value.drag_source)
	push_uuid_field(L, "drop_target", value.drop_target)
	drop_placement := "none"
	switch value.drop_placement {
		case .Before:
			drop_placement = "before"
		case .Into:
			drop_placement = "into"
		case .After:
			drop_placement = "after"
		case .None:
	}
	push_string_field(L, "drop_placement", drop_placement)
	lua_pushnumber(L, f64(value.activation_revision))
	lua_setfield(L, -2, "activation_revision")
	lua_pushnumber(L, f64(value.change_revision))
	lua_setfield(L, -2, "change_revision")
	lua_pushnumber(L, f64(value.submit_revision))
	lua_setfield(L, -2, "submit_revision")
	lua_pushnumber(L, f64(value.cancel_revision))
	lua_setfield(L, -2, "cancel_revision")
	lua_pushnumber(L, f64(value.drop_revision))
	lua_setfield(L, -2, "drop_revision")
}

push_ui_text_table :: proc "c" (L: Lua_State, value: shared.UI_Text_Component) {
	lua_createtable(L, 0, 5)
	push_string_field(L, "text", value.text)
	push_string_field(L, "font", value.font)
	push_vec4_field(L, "color", value.color)
	push_number_field(L, "size", value.size)
	alignment := "left"
	if value.alignment == .Center {
		alignment = "center"
	} else if value.alignment == .Right {
		alignment = "right"
	}
	push_string_field(L, "alignment", alignment)
}

push_ui_button_table :: proc "c" (L: Lua_State, value: shared.UI_Button_Component) {
	lua_createtable(L, 0, 13)
	push_string_field(L, "text", value.text)
	push_string_field(L, "font", value.font)
	push_vec4_field(L, "color", value.color)
	push_number_field(L, "size", value.size)
	push_string_field(L, "alignment", ui_text_alignment_name(value.alignment))
	push_vec4_field(L, "hover_background", value.hover_background)
	push_vec4_field(L, "active_background", value.active_background)
	push_vec4_field(L, "hover_color", value.hover_color)
	push_vec4_field(L, "active_color", value.active_color)
	push_string_field(L, "icon", ui_icon_name(value.icon))
	push_number_field(L, "icon_inset", value.icon_inset)
	push_number_field(L, "icon_stroke", value.icon_stroke)
	push_bool_field(L, "panel_action", value.panel_action)
}

push_ui_input_table :: proc "c" (L: Lua_State, value: shared.UI_Input_Component) {
	lua_createtable(L, 0, 30)
	push_string_field(L, "text", value.text)
	push_string_field(L, "font", value.font)
	push_string_field(L, "prefix", value.prefix)
	push_vec4_field(L, "color", value.color)
	push_vec4_field(L, "prefix_color", value.prefix_color)
	push_vec4_field(L, "prefix_background", value.prefix_background)
	push_number_field(L, "size", value.size)
	push_number_field(L, "prefix_width", value.prefix_width)
	push_vec4_field(L, "selection_background", value.selection_background)
	push_vec4_field(L, "focus_border_color", value.focus_border_color)
	push_vec4_field(L, "invalid_border_color", value.invalid_border_color)
	push_vec4_field(L, "caret_color", value.caret_color)
	push_number_field(L, "number", value.number)
	push_number_field(L, "step", value.step)
	push_number_field(L, "minimum", value.minimum)
	push_number_field(L, "maximum", value.maximum)
	push_number_field(L, "prefix_gap", value.prefix_gap)
	push_number_field(L, "prefix_corner_radius", value.prefix_corner_radius)
	push_number_field(L, "prefix_text_padding", value.prefix_text_padding)
	push_number_field(L, "selection_corner_radius", value.selection_corner_radius)
	push_number_field(L, "focus_border_width", value.focus_border_width)
	push_number_field(L, "invalid_border_width", value.invalid_border_width)
	push_number_field(L, "caret_width", value.caret_width)
	push_number_field(L, "caret_inset", value.caret_inset)
	push_bool_field(L, "read_only", value.read_only)
	push_bool_field(L, "numeric", value.numeric)
	push_bool_field(L, "draggable", value.draggable)
	push_bool_field(L, "has_minimum", value.has_minimum)
	push_bool_field(L, "has_maximum", value.has_maximum)
}

push_ui_checkbox_table :: proc "c" (L: Lua_State, value: shared.UI_Checkbox_Component) {
	lua_createtable(L, 0, 13)
	push_bool_field(L, "checked", value.checked)
	push_number_field(L, "box_size", value.box_size)
	push_vec4_field(L, "background", value.background)
	push_vec4_field(L, "checked_background", value.checked_background)
	push_vec4_field(L, "border_color", value.border_color)
	push_vec4_field(L, "check_color", value.check_color)
	push_vec4_field(L, "hover_background", value.hover_background)
	push_vec4_field(L, "active_background", value.active_background)
	push_number_field(L, "corner_radius", value.corner_radius)
	push_number_field(L, "border_width", value.border_width)
	push_number_field(L, "check_inset", value.check_inset)
	push_number_field(L, "check_corner_radius", value.check_corner_radius)
	push_bool_field(L, "read_only", value.read_only)
}

require_system_access :: proc "c" (
	runtime: ^Runtime,
	component_name: string,
	mode: schedule.Access_Mode,
) -> string {
	if runtime == nil || !runtime.has_active_system {
		return ""
	}
	declaration := runtime.active_system
	if declaration.access_count == 0 {
		return ""
	}

	for access in declaration.accesses[:declaration.access_count] {
		if access.component != component_name {
			continue
		}
		if access.mode == mode || access.mode == .Write {
			return ""
		}
	}

	if mode == .Read {
		return "system access declaration does not permit component read"
	}
	return "system access declaration does not permit component write"
}

require_query_access :: proc "c" (
	runtime: ^Runtime,
	query: Query,
	mode: schedule.Access_Mode,
) -> string {
	for i in 0 ..< query.term_count {
		term := query.terms[i]
		if err := require_system_access(runtime, term.name, mode); err != "" {
			return err
		}
	}
	return ""
}

Script_Entity :: struct {
	index: int,
	generation: u32,
}

entity_argument :: proc "c" (
	L: Lua_State,
	index: c.int,
	world: ^World,
) -> (
	entity: Script_Entity,
	ok: bool,
) {
	if lua_type(L, index) != LUA_TTABLE {
		return {}, false
	}
	is_number: c.int
	lua_getfield(L, index, "index")
	value := lua_tointegerx(L, -1, &is_number)
	lua_settop(L, -2)
	if is_number == 0 {
		return {}, false
	}

	generation_number: c.int
	lua_getfield(L, index, "generation")
	generation := lua_tointegerx(L, -1, &generation_number)
	lua_settop(L, -2)
	if generation_number == 0 {
		return {}, false
	}

	entity = Script_Entity {
		index = int(value) - 1,
		generation = u32(generation),
	}
	if !ecs.entity_is_current(world, entity.index, entity.generation) {
		return {}, false
	}
	return entity, true
}

vec3_argument :: proc "c" (L: Lua_State, index: c.int) -> (value: Vec3, ok: bool) {
	if lua_type(L, index) != LUA_TTABLE {
		return {}, false
	}

	value.x, ok = number_field(L, index, "x")
	if !ok {
		return {}, false
	}
	value.y, ok = number_field(L, index, "y")
	if !ok {
		return {}, false
	}
	value.z, ok = number_field(L, index, "z")
	if !ok {
		return {}, false
	}
	return value, true
}

vec2_argument :: proc "c" (L: Lua_State, index: c.int) -> (value: Vec2, ok: bool) {
	if lua_type(L, index) != LUA_TTABLE {
		return {}, false
	}
	value.x, ok = number_field(L, index, "x")
	if !ok {
		return {}, false
	}
	value.y, ok = number_field(L, index, "y")
	return value, ok
}

vec4_argument :: proc "c" (L: Lua_State, index: c.int) -> (value: Vec4, ok: bool) {
	if lua_type(L, index) != LUA_TTABLE {
		return {}, false
	}
	value.x, ok = number_field(L, index, "x")
	if !ok {
		return {}, false
	}
	value.y, ok = number_field(L, index, "y")
	if !ok {
		return {}, false
	}
	value.z, ok = number_field(L, index, "z")
	if !ok {
		return {}, false
	}
	value.w, ok = number_field(L, index, "w")
	return value, ok
}

number_field :: proc "c" (L: Lua_State, index: c.int, name: cstring) -> (value: f32, ok: bool) {
	is_number: c.int
	lua_getfield(L, index, name)
	number := lua_tonumberx(L, -1, &is_number)
	lua_settop(L, -2)
	if is_number == 0 {
		return 0, false
	}
	return f32(number), true
}
