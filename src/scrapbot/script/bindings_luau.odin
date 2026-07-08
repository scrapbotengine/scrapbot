package script

import c "core:c"
import libc "core:c/libc"

foreign import luau "system:c"

Lua_State :: distinct rawptr
Lua_CFunction :: #type proc "c" (L: Lua_State) -> c.int

LUA_OK :: c.int(0)
LUA_MAXCSTACK :: 8000
LUA_GLOBALSINDEX :: -LUA_MAXCSTACK - 2002

Compile_Options :: struct {
	optimization_level:              c.int,
	debug_level:                     c.int,
	type_info_level:                 c.int,
	coverage_level:                  c.int,
	vector_lib:                      cstring,
	vector_ctor:                     cstring,
	vector_type:                     cstring,
	mutable_globals:                 [^]cstring,
	userdata_types:                  [^]cstring,
	libraries_with_known_members:    [^]cstring,
	library_member_type_callback:    rawptr,
	library_member_constant_callback: rawptr,
	disabled_builtins:               [^]cstring,
}

foreign luau {
	luaL_newstate :: proc "c" () -> Lua_State ---
	lua_close :: proc "c" (L: Lua_State) ---
	luaL_openlibs :: proc "c" (L: Lua_State) ---
	luaL_sandbox :: proc "c" (L: Lua_State) ---
	luaL_sandboxthread :: proc "c" (L: Lua_State) ---

	luau_compile :: proc "c" (
		source: cstring,
		size: c.size_t,
		options: ^Compile_Options,
		out_size: ^c.size_t,
	) -> rawptr ---
	luau_load :: proc "c" (
		L: Lua_State,
		chunkname: cstring,
		data: rawptr,
		size: c.size_t,
		env: c.int,
	) -> c.int ---

	lua_pcall :: proc "c" (L: Lua_State, nargs, nresults, errfunc: c.int) -> c.int ---
	lua_tolstring :: proc "c" (L: Lua_State, idx: c.int, len: ^c.size_t) -> cstring ---
	lua_pushcclosurek :: proc "c" (
		L: Lua_State,
		fn: Lua_CFunction,
		debugname: cstring,
		nup: c.int,
		cont: rawptr,
	) ---
	lua_pushinteger :: proc "c" (L: Lua_State, n: c.ptrdiff_t) ---
	lua_createtable :: proc "c" (L: Lua_State, narr, nrec: c.int) ---
	lua_setfield :: proc "c" (L: Lua_State, idx: c.int, k: cstring) ---
	lua_setthreaddata :: proc "c" (L: Lua_State, data: rawptr) ---
	lua_getthreaddata :: proc "c" (L: Lua_State) -> rawptr ---
}

free_luau_bytecode :: proc(bytecode: rawptr) {
	libc.free(bytecode)
}
