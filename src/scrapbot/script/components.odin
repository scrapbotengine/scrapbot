package script


import component "../component"
import ecs "../ecs"
import schedule "../schedule"
import shared "../shared"
import c "core:c"

scrapbot_component :: proc "c" (L: Lua_State) -> c.int {
	return register_luau_component(L, .Project, "scrapbot.component")
}

scrapbot_library_component :: proc "c" (L: Lua_State) -> c.int {
	return register_luau_component(L, .Library, "scrapbot.library_component")
}

scrapbot_component_handle :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil || lua_type(L, 1) != LUA_TSTRING {
		return luau_push_error(L, "scrapbot.component_handle expects a registered component name")
	}

	name_length: c.size_t
	name_data := lua_tolstring(L, 1, &name_length)
	if name_data == nil {
		return luau_push_error(L, "scrapbot.component_handle component name must be a string")
	}

	component_name := luau_string(name_data, name_length)
	definition, ok := component.find_definition(&runtime.registry, component_name)
	if !ok {
		return luau_push_error(L, "scrapbot.component_handle references an unregistered component")
	}

	push_component_handle(L, definition)
	return 1
}

register_luau_component :: proc "c" (
	L: Lua_State,
	owner: component.Owner,
	api_name: string,
) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil || lua_type(L, 1) != LUA_TSTRING || lua_type(L, 2) != LUA_TTABLE {
		if api_name == "scrapbot.library_component" {
			return luau_push_error(
				L,
				"scrapbot.library_component expects a component name and field schema table",
			)
		}
		return luau_push_error(
			L,
			"scrapbot.component expects a component name and field schema table",
		)
	}

	name_length: c.size_t
	name_data := lua_tolstring(L, 1, &name_length)
	if name_data == nil {
		if api_name == "scrapbot.library_component" {
			return luau_push_error(L, "scrapbot.library_component component name must be a string")
		}
		return luau_push_error(L, "scrapbot.component component name must be a string")
	}
	component_name := luau_string(name_data, name_length)
	if !shared.component_name_is_valid(component_name) {
		return luau_push_error(L, "component name must be dot-separated identifier tokens")
	}

	definition := component.Definition {
		name = component_name,
		owner = owner,
	}

	lua_pushnil(L)
	for lua_next(L, 2) != 0 {
		if definition.field_count >= component.MAX_COMPONENT_FIELDS {
			return luau_push_error(L, "too many fields in script component definition")
		}
		if lua_type(L, -2) != LUA_TSTRING {
			return luau_push_error(L, "component schema field names must be strings")
		}

		field_name_length: c.size_t
		field_name_data := lua_tolstring(L, -2, &field_name_length)
		if field_name_data == nil {
			return luau_push_error(L, "component schema field names must be strings")
		}

		field_definition, field_ok := component_schema_field_definition(L, -1)
		if !field_ok {
			return luau_push_error(L, "unsupported component field type")
		}

		field_definition.name = luau_string(field_name_data, field_name_length)
		definition.fields[definition.field_count] = field_definition
		definition.field_count += 1
		lua_settop(L, -2)
	}

	switch owner {
		case .Project:
			if err := component.register_project_component(&runtime.registry, definition);
			   err != "" {
				return luau_push_error(L, err)
			}
		case .Library:
			if err := component.register_library_component(&runtime.registry, definition);
			   err != "" {
				return luau_push_error(L, err)
			}
		case .Engine:
			return luau_push_error(
				L,
				"script components cannot register engine-owned component names",
			)
		case:
			return luau_push_error(L, "unsupported script component owner")
	}

	registered, _ := component.find_definition(&runtime.registry, definition.name)

	push_component_handle(L, registered)
	return 1
}

component_schema_field_definition :: proc "c" (
	L: Lua_State,
	index: c.int,
) -> (
	component.Field_Definition,
	bool,
) {
	field_type, ok := component_schema_field_type(L, index)
	if !ok {
		return {}, false
	}
	definition := component.Field_Definition {
		field_type = field_type,
	}
	if lua_type(L, index) != LUA_TTABLE {
		return definition, true
	}
	definition.editor.draggable = luau_optional_boolean_field(L, index, "draggable", false)
	definition.editor.step, _ = luau_optional_number_field(L, index, "step", 0.1)
	definition.editor.minimum, definition.editor.has_minimum = luau_optional_number_field(
		L,
		index,
		"minimum",
		0,
	)
	definition.editor.maximum, definition.editor.has_maximum = luau_optional_number_field(
		L,
		index,
		"maximum",
		0,
	)
	if definition.editor.step <= 0 ||
	   (definition.editor.has_minimum &&
			   definition.editor.has_maximum &&
			   definition.editor.minimum > definition.editor.maximum) {
		return {}, false
	}
	return definition, true
}

scrapbot_field :: proc "c" (L: Lua_State) -> c.int {
	field_type, ok := component_schema_field_type(L, 1)
	if !ok ||
	   (lua_type(L, 2) != LUA_TTABLE &&
			   lua_type(L, 2) != LUA_TNIL &&
			   lua_type(L, 2) != LUA_TNONE) {
		return luau_push_error(L, "scrapbot.field expects a field type and optional options table")
	}
	name := component_field_type_name(field_type)
	push_schema_field_marker(L, name)
	if lua_type(L, 2) == LUA_TTABLE {
		lua_getfield(L, 2, "draggable")
		lua_setfield(L, -2, "draggable")
		lua_getfield(L, 2, "step")
		lua_setfield(L, -2, "step")
		lua_getfield(L, 2, "minimum")
		lua_setfield(L, -2, "minimum")
		lua_getfield(L, 2, "maximum")
		lua_setfield(L, -2, "maximum")
	}
	return 1
}

luau_optional_boolean_field :: proc "c" (
	L: Lua_State,
	index: c.int,
	name: cstring,
	fallback: bool,
) -> bool {
	lua_getfield(L, index, name)
	defer lua_settop(L, -2)
	if lua_type(L, -1) == LUA_TNIL {
		return fallback
	}
	return lua_toboolean(L, -1) != 0
}

luau_optional_number_field :: proc "c" (
	L: Lua_State,
	index: c.int,
	name: cstring,
	fallback: f32,
) -> (
	f32,
	bool,
) {
	lua_getfield(L, index, name)
	defer lua_settop(L, -2)
	if lua_type(L, -1) == LUA_TNIL {
		return fallback, false
	}
	is_number: c.int
	value := lua_tonumberx(L, -1, &is_number)
	if is_number == 0 {
		return fallback, false
	}
	return f32(value), true
}

component_field_type_name :: proc "c" (field_type: component.Field_Type) -> string {
	switch field_type {
		case .Number:
			return "number"
		case .Vec2:
			return "vec2"
		case .Vec3:
			return "vec3"
		case .Vec4:
			return "vec4"
		case .Color:
			return "color"
		case .Bool:
			return "bool"
		case .String:
			return "string"
	}
	return ""
}

component_schema_field_type :: proc "c" (
	L: Lua_State,
	index: c.int,
) -> (
	field_type: component.Field_Type,
	ok: bool,
) {
	if lua_type(L, index) == LUA_TSTRING {
		field_type_length: c.size_t
		field_type_data := lua_tolstring(L, index, &field_type_length)
		if field_type_data == nil {
			return {}, false
		}
		field_type_name := luau_string(field_type_data, field_type_length)
		switch field_type_name {
			case "number":
				return .Number, true
			case "vec2":
				return .Vec2, true
			case "vec3":
				return .Vec3, true
			case "vec4":
				return .Vec4, true
			case "color":
				return .Color, true
		}
		return {}, false
	}

	if lua_type(L, index) != LUA_TTABLE {
		return {}, false
	}

	length: c.size_t
	lua_getfield(L, index, "__scrapbot_kind")
	kind_data := lua_tolstring(L, -1, &length)
	lua_settop(L, -2)
	if kind_data == nil || luau_string(kind_data, length) != SCHEMA_FIELD_KIND {
		return {}, false
	}

	lua_getfield(L, index, "name")
	name_data := lua_tolstring(L, -1, &length)
	lua_settop(L, -2)
	if name_data == nil {
		return {}, false
	}
	name := luau_string(name_data, length)
	switch name {
		case "number":
			return .Number, true
		case "vec2":
			return .Vec2, true
		case "vec3":
			return .Vec3, true
		case "vec4":
			return .Vec4, true
		case "color":
			return .Color, true
	}
	return {}, false
}

scrapbot_system :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil {
		return 0
	}
	if runtime.system_count >= MAX_SCRIPT_SYSTEMS {
		return luau_push_error(L, "too many script systems")
	}

	callback_index := c.int(1)
	system: Script_System
	if query_argument_is_query_object(L, 1) {
		query, query_err := query_object_argument(L, runtime, 1)
		if query_err != "" {
			return luau_push_error(L, query_err)
		}
		system.query = query
		system.has_query = true
		if err := add_query_accesses(&system.declaration, query); err != "" {
			return luau_push_error(L, err)
		}

		if lua_type(L, 2) == LUA_TFUNCTION {
			callback_index = 2
		} else if lua_type(L, 2) == LUA_TTABLE && lua_type(L, 3) == LUA_TFUNCTION {
			if err := read_system_options(L, runtime, 2, &system); err != "" {
				return luau_push_error(L, err)
			}
			callback_index = 3
		} else {
			return luau_push_error(
				L,
				"scrapbot.system expects a query, optional options table, and callback",
			)
		}
	} else if lua_type(L, 1) == LUA_TTABLE && lua_type(L, 2) == LUA_TFUNCTION {
		if err := read_system_options(L, runtime, 1, &system); err != "" {
			return luau_push_error(L, err)
		}
		callback_index = 2
	} else if lua_type(L, 1) != LUA_TFUNCTION {
		return luau_push_error(
			L,
			"scrapbot.system expects a callback or options table and callback",
		)
	}

	system.callback_ref = lua_ref(L, callback_index)
	runtime.systems[runtime.system_count] = system
	runtime.system_count += 1
	return 0
}

read_system_options :: proc "c" (
	L: Lua_State,
	runtime: ^Runtime,
	options_index: c.int,
	system: ^Script_System,
) -> string {
	if err := read_system_name(L, options_index, system); err != "" {
		return err
	}
	if err := read_system_access_list(
		L,
		runtime,
		options_index,
		"reads",
		.Read,
		&system.declaration,
	); err != "" {
		return err
	}
	if err := read_system_access_list(
		L,
		runtime,
		options_index,
		"writes",
		.Write,
		&system.declaration,
	); err != "" {
		return err
	}
	return ""
}

read_system_name :: proc "c" (
	L: Lua_State,
	options_index: c.int,
	system: ^Script_System,
) -> string {
	lua_getfield(L, options_index, "name")
	defer lua_settop(L, -2)
	if lua_type(L, -1) == LUA_TNIL {
		return ""
	}
	if lua_type(L, -1) != LUA_TSTRING {
		return "system name must be a string"
	}
	name_length: c.size_t
	name_data := lua_tolstring(L, -1, &name_length)
	if name_data == nil {
		return "system name must be a string"
	}
	name := luau_string(name_data, name_length)
	if len(name) == 0 {
		return "system name must not be empty"
	}
	if len(name) > len(system.name) {
		return "system name is too long"
	}
	system.name_length = len(name)
	for index in 0 ..< system.name_length {
		system.name[index] = name[index]
	}
	return ""
}

read_system_access_list :: proc "c" (
	L: Lua_State,
	runtime: ^Runtime,
	options_index: c.int,
	field: cstring,
	mode: schedule.Access_Mode,
	declaration: ^schedule.System,
) -> string {
	lua_getfield(L, options_index, field)
	defer lua_settop(L, -2)
	if lua_type(L, -1) == 0 {
		return ""
	}
	if lua_type(L, -1) != LUA_TTABLE {
		return "system access declarations must be arrays"
	}

	lua_pushnil(L)
	for lua_next(L, -2) != 0 {
		if mode == .Read && query_argument_is_query_object(L, -1) {
			query, query_err := query_object_argument(L, runtime, -1)
			if query_err != "" {
				return query_err
			}
			if err := add_query_accesses(declaration, query); err != "" {
				return err
			}
			lua_settop(L, -2)
			continue
		}

		component_ref, err := component_reference_argument(L, runtime, -1)
		if err != "" {
			if err == "component access declaration references unregistered component" {
				return "system access declaration references unregistered component"
			}
			return err
		}
		if err := add_system_access(declaration, component_ref.name, mode); err != "" {
			return err
		}
		lua_settop(L, -2)
	}

	return ""
}

add_query_accesses :: proc "c" (declaration: ^schedule.System, query: Query) -> string {
	for i in 0 ..< query.term_count {
		term := query.terms[i]
		if err := add_system_access(declaration, term.name, .Read); err != "" {
			return err
		}
	}
	return ""
}

add_system_access :: proc "c" (
	declaration: ^schedule.System,
	component_name: string,
	mode: schedule.Access_Mode,
) -> string {
	if declaration.access_count >= schedule.MAX_SYSTEM_ACCESSES {
		return "too many system component access declarations"
	}
	declaration.accesses[declaration.access_count] = schedule.Access {
		component = component_name,
		mode = mode,
	}
	declaration.access_count += 1
	return ""
}

component_reference_argument :: proc "c" (
	L: Lua_State,
	runtime: ^Runtime,
	index: c.int,
) -> (
	component_ref: Component_Reference,
	err: string,
) {
	id := shared.INVALID_COMPONENT_ID
	name := ""
	if lua_type(L, index) == LUA_TSTRING {
		name_length: c.size_t
		name_data := lua_tolstring(L, index, &name_length)
		if name_data == nil {
			return {},
				"component access declaration must be a component handle or registered component name"
		}
		name = luau_string(name_data, name_length)
	} else if lua_type(L, index) == LUA_TTABLE {
		name_length: c.size_t
		lua_getfield(L, index, "name")
		name_data := lua_tolstring(L, -1, &name_length)
		if name_data == nil {
			lua_settop(L, -2)
			return {}, "component access declaration handle must contain a name"
		}
		name = luau_string(name_data, name_length)
		lua_settop(L, -2)

		is_number: c.int
		lua_getfield(L, index, "id")
		id_value := lua_tointegerx(L, -1, &is_number)
		lua_settop(L, -2)
		if is_number != 0 {
			id = Component_ID(id_value)
		}
	} else {
		return {},
			"component access declaration must be a component handle or registered component name"
	}

	if id != shared.INVALID_COMPONENT_ID {
		definition, registered := component.find_definition_by_id(&runtime.registry, id)
		if !registered || definition.name != name {
			return {}, "component access declaration references unregistered component"
		}
		return Component_Reference{name = definition.name, id = definition.id}, ""
	}

	definition, registered := component.find_definition(&runtime.registry, name)
	if !registered {
		return {}, "component access declaration references unregistered component"
	}
	return Component_Reference{name = definition.name, id = definition.id}, ""
}

query_argument :: proc "c" (
	L: Lua_State,
	runtime: ^Runtime,
	index: c.int,
	api: Query_API,
) -> (
	query: Query,
	err: string,
) {
	if lua_type(L, index) != LUA_TTABLE {
		return {}, query_error(api, .Array_Contains_Non_Handle)
	}
	if query_argument_is_component_handle(L, index) {
		component_ref, component_err := component_reference_argument(L, runtime, index)
		if component_err != "" {
			return {}, query_error(api, .Component_Not_Registered)
		}
		query.terms[0] = Query_Term {
			component_id = component_ref.id,
			name = component_ref.name,
		}
		query.term_count = 1
		return query, ""
	}

	for i in 0 ..< ecs.MAX_QUERY_TERMS {
		lua_rawgeti(L, index, c.int(i + 1))
		if lua_type(L, -1) == LUA_TNIL {
			lua_settop(L, -2)
			break
		}
		if lua_type(L, -1) != LUA_TTABLE {
			lua_settop(L, -2)
			return {}, query_error(api, .Array_Contains_Non_Handle)
		}

		component_ref, component_err := component_reference_argument(L, runtime, -1)
		if component_err != "" {
			lua_settop(L, -2)
			return {}, query_error(api, .Component_Not_Registered)
		}
		query.terms[query.term_count] = Query_Term {
			component_id = component_ref.id,
			name = component_ref.name,
		}
		query.term_count += 1
		lua_settop(L, -2)
	}

	if query.term_count == 0 {
		return {}, query_error(api, .Array_Empty)
	}
	if query.term_count == ecs.MAX_QUERY_TERMS {
		lua_rawgeti(L, index, c.int(ecs.MAX_QUERY_TERMS + 1))
		if lua_type(L, -1) != LUA_TNIL {
			lua_settop(L, -2)
			return {}, query_error(api, .Array_Too_Large)
		}
		lua_settop(L, -2)
	}
	return query, ""
}

query_from_component_arguments :: proc "c" (
	L: Lua_State,
	runtime: ^Runtime,
	first_index: c.int,
	count: int,
	api: Query_API,
) -> (
	query: Query,
	err: string,
) {
	if count <= 0 || count > ecs.MAX_QUERY_TERMS {
		return {}, query_error(api, .Array_Too_Large)
	}
	for i in 0 ..< count {
		if lua_type(L, first_index + c.int(i)) != LUA_TTABLE {
			return {}, query_error(api, .Array_Contains_Non_Handle)
		}
		component_ref, component_err := component_reference_argument(
			L,
			runtime,
			first_index + c.int(i),
		)
		if component_err != "" {
			return {}, query_error(api, .Component_Not_Registered)
		}
		query.terms[i] = Query_Term {
			component_id = component_ref.id,
			name = component_ref.name,
		}
		query.term_count += 1
	}
	return query, ""
}

Query_Error :: enum {
	Component_Not_Registered,
	Array_Contains_Non_Handle,
	Array_Empty,
	Array_Too_Large,
}

query_error :: proc "c" (api: Query_API, err: Query_Error) -> string {
	if api == .View {
		#partial switch err {
			case .Component_Not_Registered:
				return "scrapbot.view component handle is not registered"
			case .Array_Contains_Non_Handle:
				return "scrapbot.view component arrays must contain component handles"
			case .Array_Empty:
				return "scrapbot.view component arrays must not be empty"
			case .Array_Too_Large:
				return "scrapbot.view component arrays are too large"
		}
	}

	#partial switch err {
		case .Component_Not_Registered:
			return "scrapbot.query component handle is not registered"
		case .Array_Contains_Non_Handle:
			return "scrapbot.query component arguments must be component handles"
		case .Array_Empty:
			return "scrapbot.query component arrays must not be empty"
		case .Array_Too_Large:
			return "scrapbot.query accepts at most eight component handles"
	}
	return "invalid query component argument"
}

query_argument_is_component_handle :: proc "c" (L: Lua_State, index: c.int) -> bool {
	if lua_type(L, index) != LUA_TTABLE {
		return false
	}
	name_length: c.size_t
	lua_getfield(L, index, "name")
	name_data := lua_tolstring(L, -1, &name_length)
	lua_settop(L, -2)
	return name_data != nil
}

query_argument_is_query_object :: proc "c" (L: Lua_State, index: c.int) -> bool {
	if lua_type(L, index) != LUA_TTABLE {
		return false
	}
	length: c.size_t
	lua_getfield(L, index, "__scrapbot_kind")
	data := lua_tolstring(L, -1, &length)
	lua_settop(L, -2)
	return data != nil && luau_string(data, length) == QUERY_OBJECT_KIND
}

query_object_argument :: proc "c" (
	L: Lua_State,
	runtime: ^Runtime,
	index: c.int,
) -> (
	query: Query,
	err: string,
) {
	if !query_argument_is_query_object(L, index) {
		return {}, "expected a Scrapbot query"
	}
	return query_argument(L, runtime, index, .Query)
}

validate_runtime_world :: proc(runtime: ^Runtime, world: ^World) -> string {
	if runtime == nil || world == nil {
		return ""
	}

	for &storage in world.custom_components {
		definition, found := component.find_definition(&runtime.registry, storage.name)
		if found {
			ecs.bind_custom_component_storage(world, storage.name, definition.id)
		}
		for scene_component in storage.components {
			if err := component.validate_custom_component(&runtime.registry, scene_component);
			   err != "" {
				return err
			}
		}
	}

	return ""
}

validate_world_components :: proc(runtime: ^Runtime) -> string {
	if runtime == nil {
		return ""
	}
	return validate_runtime_world(runtime, runtime.world)
}
