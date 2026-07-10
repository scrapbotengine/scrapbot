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
}

Script_System :: struct {
	callback_ref: c.int,
	declaration: schedule.System,
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
	runtime^ = {}
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
			if err := run_script_system(L, system, delta_seconds); err != "" {
				ecs.clear_commands(&runtime.commands)
				return err
			}
		}
	}
	return ecs.apply_commands(world, &runtime.commands)
}

run_script_system :: proc(L: Lua_State, system: Script_System, delta_seconds: f32) -> string {
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
	lua_createtable(L, 0, 11)

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

	lua_pushcclosurek(L, scrapbot_spawn, "scrapbot.spawn", 0, nil)
	lua_setfield(L, -2, "spawn")

	lua_pushcclosurek(L, scrapbot_despawn, "scrapbot.despawn", 0, nil)
	lua_setfield(L, -2, "despawn")

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

	push_component_handle(L, definition.name)
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
	if lua_type(L, 1) == LUA_TTABLE && lua_type(L, 2) == LUA_TFUNCTION {
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
		name, err := component_reference_argument(L, runtime, -1)
		if err != "" {
			return err
		}
		if declaration.access_count >= schedule.MAX_SYSTEM_ACCESSES {
			return "too many system component access declarations"
		}
		declaration.accesses[declaration.access_count] = schedule.Access {
			component = name,
			mode      = mode,
		}
		declaration.access_count += 1
		lua_settop(L, -2)
	}

	return ""
}

component_reference_argument :: proc "c" (
	L: Lua_State,
	runtime: ^Runtime,
	index: c.int,
) -> (name: string, err: string) {
	if lua_type(L, index) == LUA_TSTRING {
		name_length: c.size_t
		name_data := lua_tolstring(L, index, &name_length)
		if name_data == nil {
			return "", "component access declaration must be a component handle or registered component name"
		}
		name = luau_string(name_data, name_length)
	} else if lua_type(L, index) == LUA_TTABLE {
		name_length: c.size_t
		lua_getfield(L, index, "name")
		name_data := lua_tolstring(L, -1, &name_length)
		if name_data == nil {
			lua_settop(L, -2)
			return "", "component access declaration handle must contain a name"
		}
		name = luau_string(name_data, name_length)
		lua_settop(L, -2)
	} else {
		return "", "component access declaration must be a component handle or registered component name"
	}

	if _, registered := component.find_definition(&runtime.registry, name); !registered {
		return "", "system access declaration references unregistered component"
	}
	return name, ""
}

validate_world_components :: proc(runtime: ^Runtime) -> string {
	if runtime == nil || runtime.world == nil {
		return ""
	}

	for scene_component in runtime.world.custom_components {
		if err := component.validate_custom_component(&runtime.registry, scene_component); err != "" {
			return err
		}
	}

	return ""
}

scrapbot_query :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil || runtime.world == nil {
		return 0
	}
	if lua_type(L, 1) != LUA_TTABLE || lua_type(L, 2) != LUA_TFUNCTION {
		return luau_push_error(L, "scrapbot.query expects a component handle and callback")
	}

	name_length: c.size_t
	lua_getfield(L, 1, "name")
	name_data := lua_tolstring(L, -1, &name_length)
	if name_data == nil {
		lua_settop(L, -2)
		return luau_push_error(L, "scrapbot.query component handle must contain a name")
	}
	component_name := luau_string(name_data, name_length)
	lua_settop(L, -2)
	if _, registered := component.find_definition(&runtime.registry, component_name); !registered {
		return luau_push_error(L, "scrapbot.query component handle is not registered")
	}

	callback_ref := lua_ref(L, 2)
	for component in runtime.world.custom_components {
		if !ecs.entity_is_alive(runtime.world, component.entity_index) {
			continue
		}
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

scrapbot_spawn :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	if runtime == nil {
		return 0
	}

	name := ""
	if lua_type(L, 1) == LUA_TTABLE {
		name_length: c.size_t
		lua_getfield(L, 1, "name")
		name_data := lua_tolstring(L, -1, &name_length)
		if name_data != nil {
			name = luau_string(name_data, name_length)
		}
		lua_settop(L, -2)
	} else if lua_type(L, 1) != LUA_TNONE && lua_type(L, 1) != LUA_TNIL {
		return luau_push_error(L, "scrapbot.spawn expects an optional entity options table")
	}

	if err := ecs.queue_spawn(&runtime.commands, name); err != "" {
		return luau_push_error(L, err)
	}
	return 0
}

scrapbot_despawn :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	entity_index, ok := entity_index_argument(L, 1)
	if runtime == nil || !ok {
		return luau_push_error(L, "scrapbot.despawn expects an entity")
	}

	if err := ecs.queue_despawn(&runtime.commands, entity_index); err != "" {
		return luau_push_error(L, err)
	}
	return 0
}

push_component_handle :: proc "c" (L: Lua_State, name: string) {
	lua_createtable(L, 0, 1)
	lua_pushlstring(L, cstring(raw_data(name)), c.size_t(len(name)))
	lua_setfield(L, -2, "name")
}

scrapbot_get_rotation :: proc "c" (L: Lua_State) -> c.int {
	runtime := cast(^Runtime)lua_getthreaddata(L)
	entity_index, ok := entity_index_argument(L, 1)
	if !ok || runtime == nil || runtime.world == nil || !ecs.entity_is_alive(runtime.world, entity_index) {
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
	   !ecs.entity_is_alive(runtime.world, entity_index) {
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
	if ecs.entity_is_alive(world, entity_index) {
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
