package script


import base_runtime "base:runtime"
import c "core:c"
import libc "core:c/libc"
import ecs "../ecs"
import resources "../resources"

register_scrapbot_api :: proc(L: Lua_State) {
	lua_createtable(L, 0, 20)

	lua_pushcclosurek(L, scrapbot_log, "scrapbot.log", 0, nil)
	lua_setfield(L, -2, "log")

	lua_pushcclosurek(L, scrapbot_entity_count, "scrapbot.entity_count", 0, nil)
	lua_setfield(L, -2, "entity_count")

	lua_pushcclosurek(L, scrapbot_renderable_count, "scrapbot.renderable_count", 0, nil)
	lua_setfield(L, -2, "renderable_count")

	lua_pushcclosurek(L, scrapbot_component, "scrapbot.component", 0, nil)
	lua_setfield(L, -2, "component")

	lua_pushcclosurek(L, scrapbot_library_component, "scrapbot.library_component", 0, nil)
	lua_setfield(L, -2, "library_component")

	lua_pushcclosurek(L, scrapbot_component_handle, "scrapbot.component_handle", 0, nil)
	lua_setfield(L, -2, "component_handle")

	push_schema_field_marker(L, "vec3")
	lua_setfield(L, -2, "vec3")

	push_registered_component_handle_by_name(L, "scrapbot.transform")
	lua_setfield(L, -2, "transform")

	push_registered_component_handle_by_name(L, "scrapbot.camera")
	lua_setfield(L, -2, "camera")
	push_registered_component_handle_by_name(L, "scrapbot.ambient_light"); lua_setfield(L,-2,"ambient_light")
	push_registered_component_handle_by_name(L, "scrapbot.directional_light"); lua_setfield(L,-2,"directional_light")
	push_registered_component_handle_by_name(L, "scrapbot.point_light"); lua_setfield(L,-2,"point_light")
	push_registered_component_handle_by_name(L, "scrapbot.shadow_caster"); lua_setfield(L,-2,"shadow_caster")
	push_registered_component_handle_by_name(L, "scrapbot.shadow_receiver"); lua_setfield(L,-2,"shadow_receiver")
	push_registered_component_handle_by_name(L, "scrapbot.ui_layout"); lua_setfield(L,-2,"ui_layout")
	push_registered_component_handle_by_name(L, "scrapbot.ui_hstack"); lua_setfield(L,-2,"ui_hstack")
	push_registered_component_handle_by_name(L, "scrapbot.ui_vstack"); lua_setfield(L,-2,"ui_vstack")
	push_registered_component_handle_by_name(L, "scrapbot.ui_text"); lua_setfield(L,-2,"ui_text")
	push_registered_component_handle_by_name(L, "scrapbot.ui_button"); lua_setfield(L,-2,"ui_button")

	push_registered_component_handle_by_name(L, "scrapbot.mesh")
	lua_setfield(L, -2, "mesh")

	push_registered_component_handle_by_name(L, "scrapbot.geometry")
	lua_setfield(L, -2, "geometry_component")
	push_registered_component_handle_by_name(L, "scrapbot.material")
	lua_setfield(L, -2, "material_component")

	lua_createtable(L, 0, 3)
	lua_pushcclosurek(L, scrapbot_geometry_create, "scrapbot.geometry.create", 0, nil); lua_setfield(L, -2, "create")
	lua_pushcclosurek(L, scrapbot_geometry_cube, "scrapbot.geometry.cube", 0, nil); lua_setfield(L, -2, "cube")
	lua_pushcclosurek(L, scrapbot_geometry_plane, "scrapbot.geometry.plane", 0, nil); lua_setfield(L, -2, "plane")
	lua_pushcclosurek(L, scrapbot_geometry_icosphere, "scrapbot.geometry.icosphere", 0, nil); lua_setfield(L, -2, "icosphere")
	lua_pushcclosurek(L, scrapbot_geometry_sphere, "scrapbot.geometry.sphere", 0, nil); lua_setfield(L, -2, "sphere")
	lua_pushcclosurek(L, scrapbot_geometry_pyramid, "scrapbot.geometry.pyramid", 0, nil); lua_setfield(L, -2, "pyramid")
	lua_pushcclosurek(L, scrapbot_geometry_cylinder, "scrapbot.geometry.cylinder", 0, nil); lua_setfield(L, -2, "cylinder")
	lua_setfield(L, -2, "geometry")
	lua_createtable(L, 0, 3)
	lua_pushcclosurek(L, scrapbot_material_unlit, "scrapbot.material.lit", 0, nil); lua_setfield(L, -2, "lit")
	lua_pushcclosurek(L, scrapbot_material_unlit, "scrapbot.material.unlit", 0, nil); lua_setfield(L, -2, "unlit")
	lua_pushcclosurek(L, scrapbot_material_textured, "scrapbot.material.textured", 0, nil); lua_setfield(L, -2, "textured")
	lua_setfield(L, -2, "material")

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

scrapbot_geometry_cube :: proc "c" (L: Lua_State) -> c.int {
	context = base_runtime.default_context()
	runtime := cast(^Runtime)lua_getthreaddata(L)
	name, ok := luau_required_string(L, 1)
	if runtime == nil || runtime.resource_registry == nil || !ok {return luau_push_error(L, "geometry.cube expects a resource name")}
	size := f32(1); if lua_gettop(L) >= 2 {is_number: c.int; size = f32(lua_tonumberx(L, 2, &is_number)); if is_number == 0 {return luau_push_error(L, "cube size must be a number")}}
	desc, err := resources.cube(size); if err != "" {return luau_push_error(L, err)}
	defer delete(desc.vertices); defer delete(desc.indices)
	handle, register_err := resources.register_geometry(runtime.resource_registry, name, desc)
	if register_err != "" {return luau_push_error(L, register_err)}
	ecs.reconcile_render_instances(runtime.world, runtime.resource_registry)
	push_resource_handle(L, "geometry", handle.index, handle.generation); return 1
}

scrapbot_geometry_create :: proc "c" (L: Lua_State) -> c.int {
	context = base_runtime.default_context()
	runtime := cast(^Runtime)lua_getthreaddata(L); name, name_ok := luau_required_string(L, 1)
	if runtime == nil || runtime.resource_registry == nil || !name_ok || lua_type(L, 2) != LUA_TTABLE {return luau_push_error(L, "geometry.create expects a name and descriptor")}
	vertices: [dynamic]resources.Vertex; indices: [dynamic]u32
	defer delete(vertices); defer delete(indices)
	lua_getfield(L, 2, "vertices")
	if lua_type(L, -1) != LUA_TTABLE {lua_settop(L,-2); return luau_push_error(L,"geometry vertices must be an array")}
	for i := 1; i <= 65536; i += 1 {
		lua_rawgeti(L, -1, c.int(i)); if lua_type(L,-1) == LUA_TNIL {lua_settop(L,-2); break}
		if lua_type(L,-1) != LUA_TTABLE {return luau_push_error(L,"geometry vertices must be tables")}
		lua_getfield(L,-1,"position"); position, position_ok := vec3_argument(L,-1); lua_settop(L,-2)
		lua_getfield(L,-1,"normal"); normal, normal_ok := vec3_argument(L,-1); lua_settop(L,-2)
		lua_getfield(L,-1,"uv"); ux, ux_ok := number_field(L,-1,"x"); uy, uy_ok := number_field(L,-1,"y"); lua_settop(L,-2)
		if !position_ok || !normal_ok || !ux_ok || !uy_ok {return luau_push_error(L,"geometry vertex requires position, normal, and uv")}
		append(&vertices, resources.Vertex{position=position,normal=normal,uv={ux,uy}}); lua_settop(L,-2)
	}
	lua_settop(L,-2)
	lua_getfield(L,2,"indices"); if lua_type(L,-1) != LUA_TTABLE {lua_settop(L,-2); return luau_push_error(L,"geometry indices must be an array")}
	for i := 1; i <= 196608; i += 1 {
		lua_rawgeti(L,-1,c.int(i)); if lua_type(L,-1) == LUA_TNIL {lua_settop(L,-2); break}
		is_number:c.int; value := lua_tointegerx(L,-1,&is_number); lua_settop(L,-2)
		if is_number == 0 || value < 0 {return luau_push_error(L,"geometry indices must be non-negative integers")}; append(&indices,u32(value))
	}
	lua_settop(L,-2)
	handle, err := resources.register_geometry(runtime.resource_registry,name,{vertices=vertices[:],indices=indices[:]}); if err != "" {return luau_push_error(L,err)}
	ecs.reconcile_render_instances(runtime.world, runtime.resource_registry)
	push_resource_handle(L,"geometry",handle.index,handle.generation); return 1
}

scrapbot_geometry_plane :: proc "c" (L: Lua_State) -> c.int {
	context = base_runtime.default_context()
	runtime := cast(^Runtime)lua_getthreaddata(L)
	name, ok := luau_required_string(L, 1)
	if runtime == nil || runtime.resource_registry == nil || !ok {return luau_push_error(L, "geometry.plane expects a resource name")}
	width, depth := f32(1), f32(1)
	if lua_gettop(L) >= 2 {is_number: c.int; width = f32(lua_tonumberx(L, 2, &is_number)); if is_number == 0 {return luau_push_error(L, "plane width must be a number")}}
	if lua_gettop(L) >= 3 {is_number: c.int; depth = f32(lua_tonumberx(L, 3, &is_number)); if is_number == 0 {return luau_push_error(L, "plane depth must be a number")}}
	desc, err := resources.plane(width, depth); if err != "" {return luau_push_error(L, err)}
	defer delete(desc.vertices); defer delete(desc.indices)
	handle, register_err := resources.register_geometry(runtime.resource_registry, name, desc)
	if register_err != "" {return luau_push_error(L, register_err)}
	ecs.reconcile_render_instances(runtime.world, runtime.resource_registry)
	push_resource_handle(L, "geometry", handle.index, handle.generation); return 1
}

scrapbot_geometry_icosphere :: proc "c" (L: Lua_State) -> c.int {
	context = base_runtime.default_context(); runtime := cast(^Runtime)lua_getthreaddata(L)
	name, ok := luau_required_string(L,1); if runtime == nil || runtime.resource_registry == nil || !ok {return luau_push_error(L,"geometry.icosphere expects a resource name")}
	radius, radius_ok := optional_f32(L,2,0.5); subdivisions, subdivisions_ok := optional_int(L,3,2)
	if !radius_ok || !subdivisions_ok {return luau_push_error(L,"icosphere radius and subdivisions must be numbers")}
	desc, err := resources.icosphere(radius,subdivisions); return register_generated_luau_geometry(L,runtime,name,desc,err)
}

scrapbot_geometry_sphere :: proc "c" (L: Lua_State) -> c.int {
	context = base_runtime.default_context(); runtime := cast(^Runtime)lua_getthreaddata(L)
	name, ok := luau_required_string(L,1); if runtime == nil || runtime.resource_registry == nil || !ok {return luau_push_error(L,"geometry.sphere expects a resource name")}
	radius, radius_ok := optional_f32(L,2,0.5); segments, segments_ok := optional_int(L,3,24); rings, rings_ok := optional_int(L,4,16)
	if !radius_ok || !segments_ok || !rings_ok {return luau_push_error(L,"sphere radius, segments, and rings must be numbers")}
	desc, err := resources.sphere(radius,segments,rings); return register_generated_luau_geometry(L,runtime,name,desc,err)
}

scrapbot_geometry_pyramid :: proc "c" (L: Lua_State) -> c.int {
	context = base_runtime.default_context(); runtime := cast(^Runtime)lua_getthreaddata(L)
	name, ok := luau_required_string(L,1); if runtime == nil || runtime.resource_registry == nil || !ok {return luau_push_error(L,"geometry.pyramid expects a resource name")}
	width, width_ok := optional_f32(L,2,1); height, height_ok := optional_f32(L,3,1); depth, depth_ok := optional_f32(L,4,1)
	if !width_ok || !height_ok || !depth_ok {return luau_push_error(L,"pyramid dimensions must be numbers")}
	desc, err := resources.pyramid(width,height,depth); return register_generated_luau_geometry(L,runtime,name,desc,err)
}

scrapbot_geometry_cylinder :: proc "c" (L: Lua_State) -> c.int {
	context = base_runtime.default_context(); runtime := cast(^Runtime)lua_getthreaddata(L)
	name, ok := luau_required_string(L,1); if runtime == nil || runtime.resource_registry == nil || !ok {return luau_push_error(L,"geometry.cylinder expects a resource name")}
	radius, radius_ok := optional_f32(L,2,0.5); height, height_ok := optional_f32(L,3,1); segments, segments_ok := optional_int(L,4,24)
	if !radius_ok || !height_ok || !segments_ok {return luau_push_error(L,"cylinder radius, height, and segments must be numbers")}
	desc, err := resources.cylinder(radius,height,segments); return register_generated_luau_geometry(L,runtime,name,desc,err)
}

register_generated_luau_geometry :: proc(L: Lua_State, runtime: ^Runtime, name: string, desc: resources.Geometry_Desc, generation_err: string) -> c.int {
	if generation_err != "" {return luau_push_error(L,generation_err)}
	defer delete(desc.vertices); defer delete(desc.indices)
	handle, err := resources.register_geometry(runtime.resource_registry,name,desc); if err != "" {return luau_push_error(L,err)}
	ecs.reconcile_render_instances(runtime.world,runtime.resource_registry)
	push_resource_handle(L,"geometry",handle.index,handle.generation); return 1
}

optional_f32 :: proc "c" (L: Lua_State, index: c.int, default: f32) -> (f32,bool) {
	if lua_gettop(L) < index {return default,true}; ok:c.int; value := f32(lua_tonumberx(L,index,&ok)); return value,ok != 0
}

optional_int :: proc "c" (L: Lua_State, index: c.int, default: int) -> (int,bool) {
	if lua_gettop(L) < index {return default,true}; ok:c.int; value := int(lua_tointegerx(L,index,&ok)); return value,ok != 0
}

scrapbot_material_unlit :: proc "c" (L: Lua_State) -> c.int {
	context = base_runtime.default_context()
	runtime := cast(^Runtime)lua_getthreaddata(L)
	name, ok := luau_required_string(L, 1)
	if runtime == nil || runtime.resource_registry == nil || !ok {return luau_push_error(L, "material.unlit expects a resource name")}
	values := [4]f32{1,1,1,1}
	for i in 0..<4 {if lua_gettop(L) >= c.int(i+2) {is_number: c.int; values[i] = f32(lua_tonumberx(L, c.int(i+2), &is_number)); if is_number == 0 {return luau_push_error(L, "material color values must be numbers")}}}
	handle, err := resources.register_material(runtime.resource_registry, name, {base_color={values[0],values[1],values[2],values[3]}})
	if err != "" {return luau_push_error(L, err)}
	ecs.reconcile_render_instances(runtime.world, runtime.resource_registry)
	push_resource_handle(L, "material", handle.index, handle.generation); return 1
}

scrapbot_material_textured :: proc "c" (L: Lua_State) -> c.int {
	context = base_runtime.default_context()
	runtime := cast(^Runtime)lua_getthreaddata(L)
	name, name_ok := luau_required_string(L, 1)
	path, path_ok := luau_required_string(L, 2)
	if runtime == nil || runtime.resource_registry == nil || runtime.project_root == "" || !name_ok || !path_ok {return luau_push_error(L, "material.textured expects a resource name and project asset path")}
	values := [4]f32{1,1,1,1}
	for i in 0..<4 {if lua_gettop(L) >= c.int(i+3) {is_number: c.int; values[i] = f32(lua_tonumberx(L,c.int(i+3),&is_number)); if is_number == 0 {return luau_push_error(L,"material tint values must be numbers")}}}
	handle, err := resources.register_textured_material(runtime.resource_registry,runtime.project_root,name,path,{values[0],values[1],values[2],values[3]})
	if err != "" {return luau_push_error(L,err)}
	ecs.reconcile_render_instances(runtime.world,runtime.resource_registry)
	push_resource_handle(L,"material",handle.index,handle.generation); return 1
}

luau_required_string :: proc "c" (L: Lua_State, index: c.int) -> (string, bool) {
	length: c.size_t; data := lua_tolstring(L, index, &length); if data == nil {return "", false}; return luau_string(data, length), true
}

push_resource_handle :: proc "c" (L: Lua_State, kind: cstring, index, generation: u32) {
	lua_createtable(L, 0, 3)
	lua_pushlstring(L, kind, c.size_t(len(string(kind)))); lua_setfield(L, -2, "kind")
	lua_pushinteger(L, c.ptrdiff_t(index)); lua_setfield(L, -2, "index")
	lua_pushinteger(L, c.ptrdiff_t(generation)); lua_setfield(L, -2, "generation")
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
