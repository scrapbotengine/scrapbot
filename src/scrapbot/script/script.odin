package script

import "core:fmt"
import c "core:c"
import libc "core:c/libc"
import "core:os"
import "core:path/filepath"
import "core:strings"
import shared "../shared"

DEFAULT_SCRIPT :: shared.DEFAULT_SCRIPT
DEFAULT_SCRIPT_CHUNK :: "=" + DEFAULT_SCRIPT
MAX_SCRIPT_COMPONENTS :: 64
MAX_SCRIPT_COMPONENT_FIELDS :: 16
MAX_SCRIPT_SYSTEMS :: 64
World :: shared.World
Vec3 :: shared.Vec3
Transform_Component :: shared.Transform_Component
Custom_Component :: shared.Custom_Component
Named_Vec3 :: shared.Named_Vec3

Run_Result :: struct {
	ran: bool,
	err: string,
}

Runtime :: struct {
	L: Lua_State,
	world: ^World,
	components: [MAX_SCRIPT_COMPONENTS]Component_Definition,
	component_count: int,
	systems: [MAX_SCRIPT_SYSTEMS]Script_System,
	system_count: int,
}

Component_Field_Type :: enum {
	Vec3,
}

Component_Field_Definition :: struct {
	name: string,
	field_type: Component_Field_Type,
}

Component_Definition :: struct {
	name: string,
	fields: [MAX_SCRIPT_COMPONENT_FIELDS]Component_Field_Definition,
	field_count: int,
}

Script_System :: struct {
	callback_ref: c.int,
}

run_project_script :: proc(runtime: ^Runtime, root: string, world: ^World) -> Run_Result {
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

	result = run_source(runtime, string(source), DEFAULT_SCRIPT_CHUNK, world)
	result.ran = result.err == ""
	return result
}

run_source :: proc(runtime: ^Runtime, source, chunk_name: string, world: ^World) -> Run_Result {
	result: Run_Result
	runtime^ = {}
	runtime.world = world

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
	runtime^ = {}
}

step_runtime :: proc(runtime: ^Runtime, world: ^World, delta_seconds: f32) -> string {
	if runtime == nil || runtime.L == nil {
		return ""
	}
	runtime.world = world
	L := runtime.L
	for system in runtime.systems[:runtime.system_count] {
		lua_rawgeti(L, LUA_REGISTRYINDEX, system.callback_ref)
		lua_pushnumber(L, f64(delta_seconds))
		status := lua_pcall(L, 1, 0, 0)
		if status != LUA_OK {
			return luau_stack_error(L, "Luau system")
		}
	}
	return ""
}

step_frame_system :: proc(data: rawptr, world: ^World, delta_seconds: f32) -> string {
	runtime := cast(^Runtime)data
	return step_runtime(runtime, world, delta_seconds)
}

register_scrapbot_api :: proc(L: Lua_State) {
	lua_createtable(L, 0, 9)

	lua_pushcclosurek(L, scrapbot_log, "scrapbot.log", 0, nil)
	lua_setfield(L, -2, "log")

	lua_pushcclosurek(L, scrapbot_entity_count, "scrapbot.entity_count", 0, nil)
	lua_setfield(L, -2, "entity_count")

	lua_pushcclosurek(L, scrapbot_renderable_count, "scrapbot.renderable_count", 0, nil)
	lua_setfield(L, -2, "renderable_count")

	lua_pushcclosurek(L, scrapbot_component, "scrapbot.component", 0, nil)
	lua_setfield(L, -2, "component")

	lua_pushcclosurek(L, scrapbot_system, "scrapbot.system", 0, nil)
	lua_setfield(L, -2, "system")

	lua_pushcclosurek(L, scrapbot_query, "scrapbot.query", 0, nil)
	lua_setfield(L, -2, "query")

	lua_pushcclosurek(L, scrapbot_get_rotation, "scrapbot.get_rotation", 0, nil)
	lua_setfield(L, -2, "get_rotation")

	lua_pushcclosurek(L, scrapbot_set_rotation, "scrapbot.set_rotation", 0, nil)
	lua_setfield(L, -2, "set_rotation")

	lua_setfield(L, LUA_GLOBALSINDEX, "scrapbot")
}

scrapbot_log :: proc "c" (L: Lua_State) -> c.int {
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
		count = len(runtime.world.entities)
	}
	lua_pushinteger(L, c.ptrdiff_t(count))
	return 1
}

scrapbot_renderable_count :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	count := 0
	if runtime != nil && runtime.world != nil {
		count = len(runtime.world.renderables)
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

	component_index, found := find_component_definition(runtime, component_name)
	if !found {
		if runtime.component_count >= MAX_SCRIPT_COMPONENTS {
			return luau_push_error(L, "too many script component definitions")
		}
		component_index = runtime.component_count
		runtime.component_count += 1
	}

	component := &runtime.components[component_index]
	component^ = {}
	component.name = component_name

	lua_pushnil(L)
	for lua_next(L, 2) != 0 {
		if component.field_count >= MAX_SCRIPT_COMPONENT_FIELDS {
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

		component.fields[component.field_count] = Component_Field_Definition {
			name = luau_string(field_name_data, field_name_length),
			field_type = .Vec3,
		}
		component.field_count += 1
		lua_settop(L, -2)
	}

	return 0
}

scrapbot_system :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil || runtime.system_count >= MAX_SCRIPT_SYSTEMS || lua_type(L, 1) != LUA_TFUNCTION {
		return 0
	}

	callback_ref := lua_ref(L, 1)
	runtime.systems[runtime.system_count] = Script_System{callback_ref = callback_ref}
	runtime.system_count += 1
	return 0
}

validate_world_components :: proc(runtime: ^Runtime) -> string {
	if runtime == nil || runtime.world == nil {
		return ""
	}

	for component in runtime.world.custom_components {
		definition, definition_ok := component_definition(runtime, component.name)
		if !definition_ok {
			return fmt.tprintf(
				`scene component "%s" is not defined by scripts/main.luau; add scrapbot.component("%s", schema)`,
				component.name,
				component.name,
			)
		}

		for field in component.vec3_fields {
			field_definition, field_ok := component_field(definition, field.name)
			if !field_ok {
				return fmt.tprintf(
					`scene component "%s" has field "%s" that is not defined by scripts/main.luau`,
					component.name,
					field.name,
				)
			}
			if field_definition.field_type != .Vec3 {
				return fmt.tprintf(
					`scene component "%s" field "%s" does not accept vec3 values`,
					component.name,
					field.name,
				)
			}
		}
	}

	return ""
}

find_component_definition :: proc "c" (runtime: ^Runtime, name: string) -> (index: int, ok: bool) {
	for component, i in runtime.components[:runtime.component_count] {
		if component.name == name {
			return i, true
		}
	}
	return -1, false
}

component_definition :: proc(runtime: ^Runtime, name: string) -> (definition: Component_Definition, ok: bool) {
	index, found := find_component_definition(runtime, name)
	if !found {
		return {}, false
	}
	return runtime.components[index], true
}

component_field :: proc(definition: Component_Definition, name: string) -> (field: Component_Field_Definition, ok: bool) {
	for i in 0..<definition.field_count {
		definition_field := definition.fields[i]
		if definition_field.name == name {
			return definition_field, true
		}
	}
	return {}, false
}

scrapbot_query :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil || runtime.world == nil || lua_type(L, 2) != LUA_TFUNCTION {
		return 0
	}

	name_length: c.size_t
	name_data := lua_tolstring(L, 1, &name_length)
	if name_data == nil {
		return 0
	}
	component_name := luau_string(name_data, name_length)

	callback_ref := lua_ref(L, 2)
	for component in runtime.world.custom_components {
		if component.name != component_name {
			continue
		}

		lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ref)
		push_entity_table(L, runtime.world, component.entity_index)
		push_component_table(L, component)
		status := lua_pcall(L, 2, 0, 0)
		if status != LUA_OK {
			lua_unref(L, callback_ref)
			return lua_error(L)
		}
	}
	lua_unref(L, callback_ref)
	return 0
}

scrapbot_get_rotation :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	entity_index, ok := entity_index_argument(L, 1)
	if !ok || runtime == nil || runtime.world == nil || entity_index < 0 || entity_index >= len(runtime.world.entities) {
		lua_pushnil(L)
		return 1
	}

	transform_index := runtime.world.entities[entity_index].transform_index
	if transform_index < 0 || transform_index >= len(runtime.world.transforms) {
		lua_pushnil(L)
		return 1
	}

	push_vec3_table(L, runtime.world.transforms[transform_index].rotation)
	return 1
}

scrapbot_set_rotation :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	entity_index, entity_ok := entity_index_argument(L, 1)
	rotation, rotation_ok := vec3_argument(L, 2)
	if !entity_ok || !rotation_ok || runtime == nil || runtime.world == nil ||
	   entity_index < 0 || entity_index >= len(runtime.world.entities) {
		return 0
	}

	transform_index := runtime.world.entities[entity_index].transform_index
	if transform_index < 0 || transform_index >= len(runtime.world.transforms) {
		return 0
	}

	transform := runtime.world.transforms[transform_index]
	transform.rotation = rotation
	runtime.world.transforms[transform_index] = transform
	return 0
}

push_entity_table :: proc "c" (L: Lua_State, world: ^World, entity_index: int) {
	lua_createtable(L, 0, 2)
	lua_pushinteger(L, c.ptrdiff_t(entity_index + 1))
	lua_setfield(L, -2, "index")
	if world != nil && entity_index >= 0 && entity_index < len(world.entities) {
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

push_vec3_table :: proc "c" (L: Lua_State, value: Vec3) {
	lua_createtable(L, 0, 3)
	lua_pushnumber(L, f64(value.x))
	lua_setfield(L, -2, "x")
	lua_pushnumber(L, f64(value.y))
	lua_setfield(L, -2, "y")
	lua_pushnumber(L, f64(value.z))
	lua_setfield(L, -2, "z")
}

entity_index_argument :: proc "c" (L: Lua_State, index: c.int) -> (entity_index: int, ok: bool) {
	if lua_type(L, index) != LUA_TTABLE {
		return -1, false
	}
	is_number: c.int
	lua_getfield(L, index, "index")
	value := lua_tointegerx(L, -1, &is_number)
	lua_settop(L, -2)
	if is_number == 0 {
		return -1, false
	}
	return int(value) - 1, true
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
