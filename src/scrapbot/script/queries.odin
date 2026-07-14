package script


import component "../component"
import ecs "../ecs"
import schedule "../schedule"
import shared "../shared"
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
	for i in 0 ..< ecs.query_count(runtime.world, query) {
		entity_index, entity_ok := ecs.query_entity_at(runtime.world, query, i)
		if !entity_ok {
			continue
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
	for i in 0 ..< count {
		entity_index, entity_ok := ecs.query_entity_at(runtime.world, query, i)
		if !entity_ok {
			continue
		}
		lua_pushinteger(L, c.ptrdiff_t(i + 1))
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
	lua_createtable(L, 0, c.int(len(component.vec3_fields)))
	for field in component.vec3_fields {
		lua_pushlstring(L, cstring(raw_data(field.name)), c.size_t(len(field.name)))
		push_vec3_table(L, field.value)
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
		case "scrapbot.shadow_caster",
		     "scrapbot.shadow_receiver",
		     "scrapbot.ui_layout",
		     "scrapbot.ui_hstack",
		     "scrapbot.ui_vstack",
		     "scrapbot.ui_scroll_area",
		     "scrapbot.ui_panel",
		     "scrapbot.ui_table",
		     "scrapbot.ui_text",
		     "scrapbot.ui_button",
		     "scrapbot.ui_input":
			lua_createtable(L, 0, 0)
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
	lua_createtable(L, 0, 3)
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
