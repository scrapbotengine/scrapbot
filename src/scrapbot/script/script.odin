package script

import "core:fmt"
import c "core:c"
import libc "core:c/libc"
import "core:os"
import "core:path/filepath"
import "core:strings"
import component "../component"
import ecs "../ecs"
import schedule "../schedule"
import shared "../shared"

DEFAULT_SCRIPT :: shared.DEFAULT_SCRIPT
DEFAULT_SCRIPT_CHUNK :: "=" + DEFAULT_SCRIPT
MAX_SCRIPT_SYSTEMS :: schedule.MAX_SYSTEMS
World :: shared.World
Vec3 :: shared.Vec3
Transform_Component :: shared.Transform_Component
Custom_Component :: shared.Custom_Component
Named_Vec3 :: shared.Named_Vec3
Component_ID :: shared.Component_ID
Query :: ecs.Query
Query_Term :: ecs.Query_Term
QUERY_OBJECT_KIND : string : "scrapbot.query"

Run_Result :: struct {
	ran: bool,
	err: string,
}

Source_Options :: struct {
	log_enabled: bool,
}

Runtime :: struct {
	L: Lua_State,
	world: ^World,
	registry: component.Registry,
	log_enabled: bool,
	commands: ecs.Command_Buffer,
	systems: [MAX_SCRIPT_SYSTEMS]Script_System,
	system_count: int,
	active_system: schedule.System,
	has_active_system: bool,
}

Script_System :: struct {
	callback_ref: c.int,
	declaration: schedule.System,
	query: Query,
	has_query: bool,
}

Component_Reference :: struct {
	name: string,
	id:   Component_ID,
}

Query_API :: enum {
	Query,
	View,
}

run_project_script :: proc(runtime: ^Runtime, root: string, world: ^World) -> Run_Result {
	return run_project_script_with_options(runtime, root, world, Source_Options{log_enabled = true})
}

run_project_script_for_check :: proc(runtime: ^Runtime, root: string, world: ^World) -> Run_Result {
	return run_project_script_with_options(runtime, root, world, Source_Options{})
}

run_project_script_with_options :: proc(runtime: ^Runtime, root: string, world: ^World, options: Source_Options) -> Run_Result {
	result: Run_Result

	script_path, join_err := filepath.join({root, DEFAULT_SCRIPT})
	if join_err != nil {
		result.err = "failed to allocate script path"
		return result
	}
	defer delete(script_path)

	if !os.exists(script_path) {
		return result
	}

	source, read_err := os.read_entire_file(script_path, context.temp_allocator)
	if read_err != nil {
		result.err = fmt.tprintf("failed to read %s: %v", script_path, read_err)
		return result
	}

	result = run_source_with_options(runtime, string(source), DEFAULT_SCRIPT_CHUNK, world, options)
	result.ran = result.err == ""
	return result
}

run_source :: proc(runtime: ^Runtime, source, chunk_name: string, world: ^World) -> Run_Result {
	return run_source_with_options(runtime, source, chunk_name, world, Source_Options{log_enabled = true})
}

run_source_with_options :: proc(runtime: ^Runtime, source, chunk_name: string, world: ^World, options: Source_Options) -> Run_Result {
	result: Run_Result
	destroy_runtime(runtime)
	runtime^ = {}
	ecs.init_command_buffer(&runtime.commands)
	runtime.world = world
	runtime.log_enabled = options.log_enabled
	component.init_registry(&runtime.registry)

	L := luaL_newstate()
	if L == nil {
		result.err = "failed to create Luau state"
		return result
	}
	runtime.L = L

	lua_setthreaddata(L, runtime)

	luaL_openlibs(L)
	register_scrapbot_api(L)
	luaL_sandbox(L)
	luaL_sandboxthread(L)

	options := Compile_Options{optimization_level = 1, debug_level = 1}
	bytecode_size: c.size_t
	bytecode := luau_compile(cstring(raw_data(source)), c.size_t(len(source)), &options, &bytecode_size)
	if bytecode == nil {
		result.err = fmt.tprintf("%s: failed to compile Luau source", chunk_name)
		return result
	}
	defer free_luau_bytecode(bytecode)

	chunk_cstring, chunk_err := strings.clone_to_cstring(chunk_name, context.temp_allocator)
	if chunk_err != nil {
		result.err = "failed to allocate Luau chunk name"
		return result
	}
	status := luau_load(L, chunk_cstring, bytecode, bytecode_size, 0)
	if status != LUA_OK {
		result.err = luau_stack_error(L, chunk_name)
		return result
	}

	status = lua_pcall(L, 0, 0, 0)
	if status != LUA_OK {
		result.err = luau_stack_error(L, chunk_name)
		return result
	}

	result.err = validate_world_components(runtime)
	if result.err != "" {
		return result
	}

	result.ran = true
	return result
}

destroy_runtime :: proc(runtime: ^Runtime) {
	if runtime.L != nil {
		for system in runtime.systems[:runtime.system_count] {
			lua_unref(runtime.L, system.callback_ref)
		}
		lua_close(runtime.L)
	}
	ecs.destroy_command_buffer(&runtime.commands)
	runtime^ = {}
}

rebind_runtime :: proc(runtime: ^Runtime) {
	if runtime != nil && runtime.L != nil {
		lua_setthreaddata(runtime.L, runtime)
	}
}

step_runtime :: proc(runtime: ^Runtime, world: ^World, delta_seconds: f32) -> string {
	if runtime == nil || runtime.L == nil {
		return ""
	}
	runtime.world = world
	L := runtime.L
	scheduled_systems: [MAX_SCRIPT_SYSTEMS]schedule.System
	for system, index in runtime.systems[:runtime.system_count] {
		scheduled_systems[index] = system.declaration
	}
	plan := schedule.build_plan(scheduled_systems[:runtime.system_count])

	for batch in plan.batches[:plan.batch_count] {
		for i in 0..<batch.system_count {
			system_index := batch.system_indices[i]
			system := runtime.systems[system_index]
			if err := run_script_system(runtime, L, system, delta_seconds); err != "" {
				ecs.clear_commands(&runtime.commands)
				return err
			}
		}
	}
	return ecs.apply_commands(world, &runtime.commands)
}

run_script_system :: proc(runtime: ^Runtime, L: Lua_State, system: Script_System, delta_seconds: f32) -> string {
	runtime.active_system = system.declaration
	runtime.has_active_system = true
	defer {
		runtime.has_active_system = false
		runtime.active_system = {}
	}

	if system.has_query {
		for i in 0..<ecs.query_count(runtime.world, system.query) {
			entity_index, entity_ok := ecs.query_entity_at(runtime.world, system.query, i)
			if !entity_ok {
				continue
			}
			lua_rawgeti(L, LUA_REGISTRYINDEX, system.callback_ref)
			lua_pushnumber(L, f64(delta_seconds))
			push_entity_table(L, runtime.world, entity_index)
			for term_index in 0..<system.query.term_count {
				term := system.query.terms[term_index]
				push_query_component_table(L, runtime.world, entity_index, term)
			}
			status := lua_pcall(L, c.int(system.query.term_count + 2), 0, 0)
			if status != LUA_OK {
				return luau_stack_error(L, "Luau system")
			}
		}
		return ""
	}

	lua_rawgeti(L, LUA_REGISTRYINDEX, system.callback_ref)
	lua_pushnumber(L, f64(delta_seconds))
	status := lua_pcall(L, 1, 0, 0)
	if status != LUA_OK {
		return luau_stack_error(L, "Luau system")
	}
	return ""
}

step_frame_system :: proc(data: rawptr, world: ^World, delta_seconds: f32) -> string {
	runtime := cast(^Runtime)data
	return step_runtime(runtime, world, delta_seconds)
}

register_scrapbot_api :: proc(L: Lua_State) {
	lua_createtable(L, 0, 17)

	lua_pushcclosurek(L, scrapbot_log, "scrapbot.log", 0, nil)
	lua_setfield(L, -2, "log")

	lua_pushcclosurek(L, scrapbot_entity_count, "scrapbot.entity_count", 0, nil)
	lua_setfield(L, -2, "entity_count")

	lua_pushcclosurek(L, scrapbot_renderable_count, "scrapbot.renderable_count", 0, nil)
	lua_setfield(L, -2, "renderable_count")

	lua_pushcclosurek(L, scrapbot_component, "scrapbot.component", 0, nil)
	lua_setfield(L, -2, "component")

	push_registered_component_handle_by_name(L, "scrapbot.transform")
	lua_setfield(L, -2, "transform")

	push_registered_component_handle_by_name(L, "scrapbot.camera")
	lua_setfield(L, -2, "camera")

	push_registered_component_handle_by_name(L, "scrapbot.mesh")
	lua_setfield(L, -2, "mesh")

	lua_pushcclosurek(L, scrapbot_system, "scrapbot.system", 0, nil)
	lua_setfield(L, -2, "system")

	lua_pushcclosurek(L, scrapbot_query, "scrapbot.query", 0, nil)
	lua_setfield(L, -2, "query")

	lua_pushcclosurek(L, scrapbot_view, "scrapbot.view", 0, nil)
	lua_setfield(L, -2, "view")

	lua_pushcclosurek(L, scrapbot_get_rotation, "scrapbot.get_rotation", 0, nil)
	lua_setfield(L, -2, "get_rotation")

	lua_pushcclosurek(L, scrapbot_set_rotation, "scrapbot.set_rotation", 0, nil)
	lua_setfield(L, -2, "set_rotation")

	lua_pushcclosurek(L, scrapbot_spawn, "scrapbot.spawn", 0, nil)
	lua_setfield(L, -2, "spawn")

	lua_pushcclosurek(L, scrapbot_despawn, "scrapbot.despawn", 0, nil)
	lua_setfield(L, -2, "despawn")

	lua_pushcclosurek(L, scrapbot_add_component, "scrapbot.add_component", 0, nil)
	lua_setfield(L, -2, "add_component")

	lua_pushcclosurek(L, scrapbot_remove_component, "scrapbot.remove_component", 0, nil)
	lua_setfield(L, -2, "remove_component")

	lua_setfield(L, LUA_GLOBALSINDEX, "scrapbot")
}

scrapbot_log :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil || !runtime.log_enabled {
		return 0
	}

	length: c.size_t
	data := lua_tolstring(L, 1, &length)
	if data != nil {
		libc.printf("[luau] %.*s\n", c.int(length), data)
	} else {
		libc.printf("[luau]\n")
	}
	return 0
}

scrapbot_entity_count :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	count := 0
	if runtime != nil && runtime.world != nil {
		count = ecs.alive_entity_count(runtime.world)
	}
	lua_pushinteger(L, c.ptrdiff_t(count))
	return 1
}

scrapbot_renderable_count :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	count := 0
	if runtime != nil && runtime.world != nil {
		count = ecs.alive_renderable_count(runtime.world)
	}
	lua_pushinteger(L, c.ptrdiff_t(count))
	return 1
}

scrapbot_component :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil || lua_type(L, 1) != LUA_TSTRING || lua_type(L, 2) != LUA_TTABLE {
		return luau_push_error(L, "scrapbot.component expects a component name and field schema table")
	}

	name_length: c.size_t
	name_data := lua_tolstring(L, 1, &name_length)
	if name_data == nil {
		return luau_push_error(L, "scrapbot.component component name must be a string")
	}
	component_name := luau_string(name_data, name_length)
	if !shared.component_name_is_valid(component_name) {
		return luau_push_error(L, "component name must be dot-separated identifier tokens")
	}
	if !shared.component_name_is_project_level(component_name) {
		return luau_push_error(L, "project scripts can only define single-token project component names")
	}

	definition := component.Definition{name = component_name, owner = .Project}

	lua_pushnil(L)
	for lua_next(L, 2) != 0 {
		if definition.field_count >= component.MAX_COMPONENT_FIELDS {
			return luau_push_error(L, "too many fields in script component definition")
		}
		if lua_type(L, -2) != LUA_TSTRING || lua_type(L, -1) != LUA_TSTRING {
			return luau_push_error(L, "component schema fields must map names to field type strings")
		}

		field_name_length: c.size_t
		field_name_data := lua_tolstring(L, -2, &field_name_length)
		field_type_length: c.size_t
		field_type_data := lua_tolstring(L, -1, &field_type_length)
		if field_name_data == nil || field_type_data == nil {
			return luau_push_error(L, "component schema fields must map names to field type strings")
		}
		field_type_name := luau_string(field_type_data, field_type_length)
		if field_type_name != "vec3" {
			return luau_push_error(L, "unsupported component field type")
		}

		definition.fields[definition.field_count] = component.Field_Definition {
			name = luau_string(field_name_data, field_name_length),
			field_type = component.Field_Type.Vec3,
		}
		definition.field_count += 1
		lua_settop(L, -2)
	}

	if err := component.register_project_component(&runtime.registry, definition); err != "" {
		return luau_push_error(L, err)
	}
	registered, _ := component.find_definition(&runtime.registry, definition.name)

	push_component_handle(L, registered)
	return 1
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
	declaration: schedule.System
	system_query: Query
	has_query := false
	if query_argument_is_query_object(L, 1) {
		query, query_err := query_object_argument(L, runtime, 1)
		if query_err != "" {
			return luau_push_error(L, query_err)
		}
		system_query = query
		has_query = true
		if err := add_query_accesses(&declaration, query); err != "" {
			return luau_push_error(L, err)
		}

		if lua_type(L, 2) == LUA_TFUNCTION {
			callback_index = 2
		} else if lua_type(L, 2) == LUA_TTABLE && lua_type(L, 3) == LUA_TFUNCTION {
			if err := read_system_options(L, runtime, 2, &declaration); err != "" {
				return luau_push_error(L, err)
			}
			callback_index = 3
		} else {
			return luau_push_error(L, "scrapbot.system expects a query, optional options table, and callback")
		}
	} else if lua_type(L, 1) == LUA_TTABLE && lua_type(L, 2) == LUA_TFUNCTION {
		if err := read_system_options(L, runtime, 1, &declaration); err != "" {
			return luau_push_error(L, err)
		}
		callback_index = 2
	} else if lua_type(L, 1) != LUA_TFUNCTION {
		return luau_push_error(L, "scrapbot.system expects a callback or options table and callback")
	}

	callback_ref := lua_ref(L, callback_index)
	runtime.systems[runtime.system_count] = Script_System {
		callback_ref = callback_ref,
		declaration = declaration,
		query = system_query,
		has_query = has_query,
	}
	runtime.system_count += 1
	return 0
}

read_system_options :: proc "c" (
	L: Lua_State,
	runtime: ^Runtime,
	options_index: c.int,
	declaration: ^schedule.System,
) -> string {
	if err := read_system_access_list(L, runtime, options_index, "reads", .Read, declaration); err != "" {
		return err
	}
	if err := read_system_access_list(L, runtime, options_index, "writes", .Write, declaration); err != "" {
		return err
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
	for i in 0..<query.term_count {
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
		mode      = mode,
	}
	declaration.access_count += 1
	return ""
}

component_reference_argument :: proc "c" (
	L: Lua_State,
	runtime: ^Runtime,
	index: c.int,
) -> (component_ref: Component_Reference, err: string) {
	id := shared.INVALID_COMPONENT_ID
	name := ""
	if lua_type(L, index) == LUA_TSTRING {
		name_length: c.size_t
		name_data := lua_tolstring(L, index, &name_length)
		if name_data == nil {
			return {}, "component access declaration must be a component handle or registered component name"
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
		return {}, "component access declaration must be a component handle or registered component name"
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
) -> (query: Query, err: string) {
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
			name         = component_ref.name,
		}
		query.term_count = 1
		return query, ""
	}

	for i in 0..<ecs.MAX_QUERY_TERMS {
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
			name         = component_ref.name,
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
) -> (query: Query, err: string) {
	if count <= 0 || count > ecs.MAX_QUERY_TERMS {
		return {}, query_error(api, .Array_Too_Large)
	}
	for i in 0..<count {
		if lua_type(L, first_index + c.int(i)) != LUA_TTABLE {
			return {}, query_error(api, .Array_Contains_Non_Handle)
		}
		component_ref, component_err := component_reference_argument(L, runtime, first_index + c.int(i))
		if component_err != "" {
			return {}, query_error(api, .Component_Not_Registered)
		}
		query.terms[i] = Query_Term {
			component_id = component_ref.id,
			name         = component_ref.name,
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
) -> (query: Query, err: string) {
	if !query_argument_is_query_object(L, index) {
		return {}, "expected a Scrapbot query"
	}
	return query_argument(L, runtime, index, .Query)
}

validate_world_components :: proc(runtime: ^Runtime) -> string {
	if runtime == nil || runtime.world == nil {
		return ""
	}

	for &storage in runtime.world.custom_components {
		definition, found := component.find_definition(&runtime.registry, storage.name)
		if found {
			ecs.bind_custom_component_storage(runtime.world, storage.name, definition.id)
		}
		for scene_component in storage.components {
			if err := component.validate_custom_component(&runtime.registry, scene_component); err != "" {
				return err
			}
		}
	}

	return ""
}

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
		return luau_push_error(L, "scrapbot.query constructs a query; call query:each(callback) to iterate")
	}

	query, query_err := query_from_component_arguments(L, runtime, 1, int(arg_count), .Query)
	if query_err != "" {
		return luau_push_error(L, query_err)
	}

	push_query_object(L, query)
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
	for i in 0..<ecs.query_count(runtime.world, query) {
		entity_index, entity_ok := ecs.query_entity_at(runtime.world, query, i)
		if !entity_ok {
			continue
		}
		lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ref)
		push_entity_table(L, runtime.world, entity_index)
		for term_index in 0..<query.term_count {
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
	for i in 0..<count {
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

scrapbot_spawn :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil {
		return 0
	}

	spawn: ecs.Spawn_Command
	if err := ecs.init_spawn_command(&spawn, ""); err != "" {
		return luau_push_error(L, err)
	}
	if lua_type(L, 1) == LUA_TTABLE {
		name_length: c.size_t
		lua_getfield(L, 1, "name")
		name_data := lua_tolstring(L, -1, &name_length)
		if name_data != nil {
			if err := ecs.init_spawn_command(&spawn, luau_string(name_data, name_length)); err != "" {
				lua_settop(L, -2)
				return luau_push_error(L, err)
			}
		}
		lua_settop(L, -2)

		if err := read_spawn_components(L, runtime, 1, &spawn); err != "" {
			return luau_push_error(L, err)
		}
	} else if lua_type(L, 1) != LUA_TNONE && lua_type(L, 1) != LUA_TNIL {
		return luau_push_error(L, "scrapbot.spawn expects an optional entity options table")
	}

	if err := ecs.queue_spawn_command(&runtime.commands, spawn); err != "" {
		return luau_push_error(L, err)
	}
	return 0
}

scrapbot_despawn :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil {
		return 0
	}
	entity, ok := entity_argument(L, 1, runtime.world)
	if !ok {
		return luau_push_error(L, "scrapbot.despawn expects an entity")
	}

	if err := ecs.queue_despawn(&runtime.commands, entity.index, entity.generation); err != "" {
		return luau_push_error(L, err)
	}
	return 0
}

scrapbot_add_component :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil {
		return 0
	}
	entity, entity_ok := entity_argument(L, 1, runtime.world)
	if !entity_ok {
		return luau_push_error(L, "scrapbot.add_component expects an entity")
	}
	component_ref, component_err := component_reference_argument(L, runtime, 2)
	if component_err != "" {
		return luau_push_error(L, component_err)
	}
	if lua_type(L, 3) != LUA_TTABLE {
		return luau_push_error(L, "scrapbot.add_component expects a component payload table")
	}

	if component_ref.name == "scrapbot.transform" {
		if err := require_system_access(runtime, component_ref.name, .Write); err != "" {
			return luau_push_error(L, err)
		}
		transform, err := read_transform_payload(L, 3)
		if err != "" {
			return luau_push_error(L, err)
		}
		if err = ecs.queue_add_transform(&runtime.commands, entity.index, entity.generation, transform); err != "" {
			return luau_push_error(L, err)
		}
		return 0
	}

	if err := require_system_access(runtime, component_ref.name, .Write); err != "" {
		return luau_push_error(L, err)
	}
	command_component: ecs.Command_Component
	if err := read_custom_component_payload(L, runtime, component_ref, 3, &command_component); err != "" {
		return luau_push_error(L, err)
	}
	if err := ecs.queue_add_custom_component(&runtime.commands, entity.index, entity.generation, command_component); err != "" {
		return luau_push_error(L, err)
	}
	return 0
}

scrapbot_remove_component :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil {
		return 0
	}
	entity, entity_ok := entity_argument(L, 1, runtime.world)
	if !entity_ok {
		return luau_push_error(L, "scrapbot.remove_component expects an entity")
	}
	component_ref, component_err := component_reference_argument(L, runtime, 2)
	if component_err != "" {
		return luau_push_error(L, component_err)
	}
	if component_ref.name != "scrapbot.transform" && !shared.component_name_is_project_level(component_ref.name) {
		return luau_push_error(L, "runtime component removal only supports scrapbot.transform and project components")
	}
	if err := require_system_access(runtime, component_ref.name, .Write); err != "" {
		return luau_push_error(L, err)
	}
	if err := ecs.queue_remove_component(&runtime.commands, entity.index, entity.generation, component_ref.id, component_ref.name); err != "" {
		return luau_push_error(L, err)
	}
	return 0
}

read_spawn_components :: proc "c" (
	L: Lua_State,
	runtime: ^Runtime,
	options_index: c.int,
	spawn: ^ecs.Spawn_Command,
) -> string {
	lua_getfield(L, options_index, "components")
	defer lua_settop(L, -2)
	if lua_type(L, -1) == LUA_TNIL {
		return ""
	}
	if lua_type(L, -1) != LUA_TTABLE {
		return "spawn components must be a table"
	}

	lua_pushnil(L)
	for lua_next(L, -2) != 0 {
		if lua_type(L, -2) != LUA_TSTRING || lua_type(L, -1) != LUA_TTABLE {
			return "spawn components must map component names to payload tables"
		}
		name_length: c.size_t
		name_data := lua_tolstring(L, -2, &name_length)
		if name_data == nil {
			return "spawn component names must be strings"
		}
		component_name := luau_string(name_data, name_length)

		if component_name == "scrapbot.transform" {
			if err := require_system_access(runtime, component_name, .Write); err != "" {
				return err
			}
			transform, err := read_transform_payload(L, -1)
			if err != "" {
				return err
			}
			if err = ecs.spawn_set_transform(spawn, transform); err != "" {
				return err
			}
		} else {
			command_component: ecs.Command_Component
			definition, registered := component.find_definition(&runtime.registry, component_name)
			if !registered {
				return "runtime component payload references an unregistered component"
			}
			if err := require_system_access(runtime, definition.name, .Write); err != "" {
				return err
			}
			component_ref := Component_Reference{name = definition.name, id = definition.id}
			if err := read_custom_component_payload(L, runtime, component_ref, -1, &command_component); err != "" {
				return err
			}
			if err := ecs.spawn_add_custom_component(spawn, command_component); err != "" {
				return err
			}
		}

		lua_settop(L, -2)
	}
	return ""
}

read_transform_payload :: proc "c" (L: Lua_State, payload_index: c.int) -> (transform: Transform_Component, err: string) {
	transform.scale = Vec3{1, 1, 1}

	if value, found, ok := optional_vec3_field(L, payload_index, "position"); found {
		if !ok {
			return transform, "scrapbot.transform.position must be a vec3"
		}
		transform.position = value
	}
	if value, found, ok := optional_vec3_field(L, payload_index, "rotation"); found {
		if !ok {
			return transform, "scrapbot.transform.rotation must be a vec3"
		}
		transform.rotation = value
	}
	if value, found, ok := optional_vec3_field(L, payload_index, "scale"); found {
		if !ok {
			return transform, "scrapbot.transform.scale must be a vec3"
		}
		transform.scale = value
	}

	return transform, ""
}

read_custom_component_payload :: proc "c" (
	L: Lua_State,
	runtime: ^Runtime,
	component_ref: Component_Reference,
	payload_index: c.int,
	command_component: ^ecs.Command_Component,
) -> string {
	definition, registered := component.find_definition_by_id(&runtime.registry, component_ref.id)
	if !registered {
		if shared.component_name_is_project_level(component_ref.name) {
			return "runtime component payload references an unregistered project component"
		}
		return "runtime component payload references an unregistered component"
	}
	if definition.name != component_ref.name {
		return "runtime component payload references an unregistered component"
	}
	if definition.owner != .Project {
		return "runtime component mutation only supports scrapbot.transform and project components"
	}
	if err := ecs.init_command_component(command_component, component_ref.id, component_ref.name); err != "" {
		return err
	}

	for i in 0..<definition.field_count {
		field := definition.fields[i]
		if field.field_type != component.Field_Type.Vec3 {
			return "unsupported component field type"
		}
		value, found, ok := optional_vec3_field(L, payload_index, cstring(raw_data(field.name)))
		if !found {
			return "component payload is missing a required field"
		}
		if !ok {
			return "component payload field must be a vec3"
		}
		if err := ecs.command_component_add_vec3(command_component, field.name, value); err != "" {
			return err
		}
	}

	return ""
}

optional_vec3_field :: proc "c" (L: Lua_State, index: c.int, name: cstring) -> (value: Vec3, found, ok: bool) {
	lua_getfield(L, index, name)
	if lua_type(L, -1) == LUA_TNIL {
		lua_settop(L, -2)
		return {}, false, true
	}
	value, ok = vec3_argument(L, -1)
	lua_settop(L, -2)
	return value, true, ok
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

push_query_object :: proc "c" (L: Lua_State, query: Query) {
	lua_createtable(L, c.int(query.term_count), 2)
	for i in 0..<query.term_count {
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
	lua_createtable(L, 0, 3)
	lua_pushinteger(L, c.ptrdiff_t(entity_index + 1))
	lua_setfield(L, -2, "index")
	if ecs.entity_is_alive(world, entity_index) {
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
	for i in 0..<query.term_count {
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
	case "scrapbot.mesh":
		lua_createtable(L, 0, 0)
		return
	}

	if custom_component, ok := ecs.custom_component_for_entity(world, entity_index, term.component_id, term.name); ok {
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
	for i in 0..<query.term_count {
		term := query.terms[i]
		if err := require_system_access(runtime, term.name, mode); err != "" {
			return err
		}
	}
	return ""
}

Script_Entity :: struct {
	index:      int,
	generation: u32,
}

entity_argument :: proc "c" (L: Lua_State, index: c.int, world: ^World) -> (entity: Script_Entity, ok: bool) {
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

	entity = Script_Entity{index = int(value) - 1, generation = u32(generation)}
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

luau_stack_error :: proc(L: Lua_State, chunk_name: string) -> string {
	length: c.size_t
	data := lua_tolstring(L, -1, &length)
	if data == nil {
		return fmt.tprintf("%s: unknown Luau error", chunk_name)
	}
	return fmt.tprintf("%s: %s", chunk_name, luau_string(data, length))
}

luau_push_error :: proc "c" (L: Lua_State, message: string) -> c.int {
	lua_pushlstring(L, cstring(raw_data(message)), c.size_t(len(message)))
	return lua_error(L)
}

luau_string :: proc "c" (data: cstring, length: c.size_t) -> string {
	bytes := (cast([^]u8)rawptr(data))[:int(length)]
	return string(bytes)
}
