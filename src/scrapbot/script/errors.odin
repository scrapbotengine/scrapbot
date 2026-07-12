package script


import "core:fmt"
import c "core:c"

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
