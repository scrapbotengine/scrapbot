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
World :: shared.World

Run_Result :: struct {
	ran: bool,
	err: string,
}

Run_Context :: struct {
	world: ^World,
}

run_project_script :: proc(root: string, world: ^World) -> Run_Result {
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

	result = run_source(string(source), DEFAULT_SCRIPT_CHUNK, world)
	result.ran = result.err == ""
	return result
}

run_source :: proc(source, chunk_name: string, world: ^World) -> Run_Result {
	result: Run_Result

	L := luaL_newstate()
	if L == nil {
		result.err = "failed to create Luau state"
		return result
	}
	defer lua_close(L)

	run_context := Run_Context{world = world}
	lua_setthreaddata(L, &run_context)

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

	result.ran = true
	return result
}

register_scrapbot_api :: proc(L: Lua_State) {
	lua_createtable(L, 0, 3)

	lua_pushcclosurek(L, scrapbot_log, "scrapbot.log", 0, nil)
	lua_setfield(L, -2, "log")

	lua_pushcclosurek(L, scrapbot_entity_count, "scrapbot.entity_count", 0, nil)
	lua_setfield(L, -2, "entity_count")

	lua_pushcclosurek(L, scrapbot_renderable_count, "scrapbot.renderable_count", 0, nil)
	lua_setfield(L, -2, "renderable_count")

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
	ctx := cast(^Run_Context)lua_getthreaddata(L)
	count := 0
	if ctx != nil && ctx.world != nil {
		count = len(ctx.world.entities)
	}
	lua_pushinteger(L, c.ptrdiff_t(count))
	return 1
}

scrapbot_renderable_count :: proc "c" (L: Lua_State) -> c.int {
	ctx := cast(^Run_Context)lua_getthreaddata(L)
	count := 0
	if ctx != nil && ctx.world != nil {
		count = len(ctx.world.renderables)
	}
	lua_pushinteger(L, c.ptrdiff_t(count))
	return 1
}

luau_stack_error :: proc(L: Lua_State, chunk_name: string) -> string {
	length: c.size_t
	data := lua_tolstring(L, -1, &length)
	if data == nil {
		return fmt.tprintf("%s: unknown Luau error", chunk_name)
	}
	return fmt.tprintf("%s: %s", chunk_name, luau_string(data, length))
}

luau_string :: proc(data: cstring, length: c.size_t) -> string {
	bytes := (cast([^]u8)rawptr(data))[:int(length)]
	return string(bytes)
}
